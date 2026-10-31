// History:
// - 2026-10-31: created (#1495): a publication's fan-out over the phone's observers while it records, timed, with its
//   publish metrics. The recording contention exercise's lists have no includes, so it could not show what three
//   50-row recordings lists with five includes each cost per publication (the #1482 audit's M3).

import Foundation
import Testing

@testable import InstantSwiftDataCore

/// The store's publication on a recording phone (#1495): 48 observers, three of them recordings lists of 50 rows with
/// five includes each (a recording's transcriptions, two preview lines, its audio and its preview image), eight
/// transcript pages of the live recording, its live line, and 36 small queries of past recordings; a live line written
/// four times then finalized, with the recording's duration every eighth write, at no pace: each write is committed and
/// published, and the publication alone is timed. As the app writes them (ADR 0069), an interim is the line's
/// `liveLines` row, which links to nothing, and the final is a transcript line linked to the recording and put in its
/// preview slot (A for an even index, B for an odd one), its live row deleted. INSTANT_PUBLISH_FANOUT_INTERIMS=segments
/// writes each interim into the open transcript line instead, linked to the recording, as a stress of the lists'
/// judgement. Set INSTANT_PUBLISH_FANOUT=1 to run it; INSTANT_PUBLISH_FANOUT_STEPS sets the measured writes (2,000).
@Suite(
  .serialized,
  .enabled(
    if: ProcessInfo.processInfo.environment["INSTANT_PUBLISH_FANOUT"] == "1",
    "Set INSTANT_PUBLISH_FANOUT=1 to run the publication fan-out exercise (#1495)."
  )
)
struct PublishFanOutExercises {
  @Test func recordingPhone() async throws {
    let environment = ProcessInfo.processInfo.environment
    let steps = environment["INSTANT_PUBLISH_FANOUT_STEPS"].flatMap(Int.init) ?? 2_000
    var fixture = PublishFanOutFixture(interimsAreLinked: environment["INSTANT_PUBLISH_FANOUT_INTERIMS"] == "segments")
    let store = try await fixture.seededStore()
    let plans = fixture.observedPlans()
    var readings: [Task<Void, Never>] = []
    for plan in plans {
      let stream = await store.observe(plan)
      readings.append(Task { for await _ in stream {} })
    }
    defer { readings.forEach { $0.cancel() } }
    print(
      "PUBLISH fanout setup interims=\(fixture.interimsAreLinked ? "segments" : "liveLines") "
        + "recordings=\(PublishFanOutFixture.recordingCount) "
        + "live_segments=\(PublishFanOutFixture.liveSegmentCount) observers=\(plans.count) lists=3 list_rows=50 "
        + "includes=5 triples=\(await store.currentTripleCount())"
    )

    for _ in 0..<50 {
      try await Self.publish(fixture.nextWrite(), to: store)
    }
    var durations: [String: [Duration]] = [:]
    var metrics = InstantStorePublishMetrics()
    for _ in 0..<steps {
      let write = fixture.nextWrite()
      let duration = try await Self.publish(write, to: store)
      durations[write.kind, default: []].append(duration)
      metrics.add(await store.lastPublishMetrics)
    }
    for kind in durations.keys.sorted() + ["all"] {
      let values = kind == "all" ? durations.values.flatMap { $0 } : durations[kind]!
      print(Self.line(kind: kind, values))
    }
    print(
      "PUBLISH fanout metrics publications=\(steps) skipped=\(metrics.skippedObserverCount) "
        + "spliced=\(metrics.splicedObserverCount) rematerialized=\(metrics.rematerializedObserverCount) "
        + "materialized_snapshots=\(metrics.materializedSnapshotCount) unchanged=\(metrics.unchangedObserverCount) "
        + "id_set_builds=\(metrics.allEntityIDsBuildCount)"
    )
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "after the exercise")
  }

  /// Commits `write` without publishing it, then times its publication: the fan-out over every observer.
  @discardableResult
  static func publish(_ write: PublishFanOutFixture.Write, to store: InstantStore) async throws -> Duration {
    let prepared = try await store.prepareCurrent(write.transaction)
    _ = await store.commitDeferringPublication(prepared)
    let started = ContinuousClock.now
    await store.publishPendingChanges()
    return ContinuousClock.now - started
  }

  static func line(kind: String, _ values: [Duration]) -> String {
    let micros = values.map { Double($0.components.seconds) * 1e6 + Double($0.components.attoseconds) / 1e12 }.sorted()
    func percentile(_ p: Double) -> Double {
      micros.isEmpty ? 0 : micros[min(micros.count - 1, Int((p * Double(micros.count - 1)).rounded()))]
    }
    let total = micros.reduce(0, +)
    return "PUBLISH fanout kind=\(kind) n=\(micros.count) "
      + String(
        format: "p50_us=%.1f p90_us=%.1f p99_us=%.1f max_us=%.1f mean_us=%.1f total_ms=%.1f",
        percentile(0.5), percentile(0.9), percentile(0.99), micros.last ?? 0, micros.isEmpty ? 0 : total / Double(micros.count),
        total / 1_000
      )
  }
}

/// The phone's recordings, their transcripts and attachments, and the live recording's writes (#1495).
struct PublishFanOutFixture {
  static let recordingCount = 352
  static let liveSegmentCount = 512
  static let pastSegmentCount = 8
  static let recordings = "fanoutRecordings"
  static let transcriptions = "fanoutTranscriptions"
  static let segments = "fanoutSegments"
  static let attachments = "fanoutAttachments"
  static let liveLines = "fanoutLiveLines"
  /// The newest recording, the one being recorded.
  static let live = recordingCount - 1

  struct Write {
    var kind: String
    var transaction: InstantStoreTransaction
  }

  /// Whether an interim rewrites the open transcript line, linked to the recording, instead of its live row.
  let interimsAreLinked: Bool
  private var step = 0
  private var openSegment = liveSegmentCount
  private var openRevision = 0

  init(interimsAreLinked: Bool = false) {
    self.interimsAreLinked = interimsAreLinked
  }

  static let attributes: [InstantAttribute] = {
    func scalar(_ namespace: String, _ name: String, _ type: InstantValueType, indexed: Bool = false) -> InstantAttribute {
      InstantAttribute(id: "\(namespace)/\(name)", namespace: namespace, name: name, valueType: type, isIndexed: indexed)
    }
    func link(_ name: String, to namespace: String, many: Bool, reverse: String) -> InstantAttribute {
      InstantAttribute(
        id: "\(recordings)/\(name)",
        namespace: recordings,
        name: name,
        valueType: .ref,
        cardinality: many ? .many : .one,
        isIndexed: true,
        forwardIdentity: "\(recordings)/\(name)",
        reverseIdentity: "\(namespace)/\(reverse)",
        linkNamespace: namespace
      )
    }
    return [
      .primaryKey(namespace: recordings),
      scalar(recordings, "title", .string),
      scalar(recordings, "startedAtMs", .number, indexed: true),
      scalar(recordings, "durationSeconds", .number),
      scalar(recordings, "updatedAtMs", .number),
      link("transcriptions", to: transcriptions, many: true, reverse: "recording"),
      link("segments", to: segments, many: true, reverse: "recording"),
      link("previewSegmentA", to: segments, many: false, reverse: "previewOfA"),
      link("previewSegmentB", to: segments, many: false, reverse: "previewOfB"),
      link("audioAttachment", to: attachments, many: false, reverse: "audioOf"),
      link("previewImage", to: attachments, many: false, reverse: "imageOf"),
      .primaryKey(namespace: transcriptions),
      scalar(transcriptions, "recordingID", .string, indexed: true),
      scalar(transcriptions, "updatedAtMs", .number, indexed: true),
      scalar(transcriptions, "status", .string),
      .primaryKey(namespace: segments),
      scalar(segments, "recordingID", .string, indexed: true),
      scalar(segments, "index", .number, indexed: true),
      scalar(segments, "text", .string),
      scalar(segments, "wordsJSON", .json),
      scalar(segments, "isFinal", .boolean),
      scalar(segments, "updatedAtMs", .number),
      .primaryKey(namespace: liveLines),
      scalar(liveLines, "recordingID", .string, indexed: true),
      scalar(liveLines, "segmentIndex", .number),
      scalar(liveLines, "text", .string),
      scalar(liveLines, "wordsJSON", .json),
      scalar(liveLines, "updatedAtMs", .number),
      .primaryKey(namespace: attachments),
      scalar(attachments, "recordingID", .string, indexed: true),
      scalar(attachments, "kind", .string),
      scalar(attachments, "url", .string),
      scalar(attachments, "updatedAtMs", .number, indexed: true),
    ]
  }()

  static func recordingID(_ recording: Int) -> String { "fanout-recording-\(recording)" }
  static func segmentID(_ recording: Int, _ index: Int) -> String { "fanout-segment-\(recording)-\(index)" }
  static func transcriptionID(_ recording: Int, _ index: Int) -> String { "fanout-transcription-\(recording)-\(index)" }
  static func attachmentID(_ recording: Int, _ index: Int) -> String { "fanout-attachment-\(recording)-\(index)" }
  static func liveLineID(_ index: Int) -> String { "fanout-live-line-\(index)" }

  /// The three lists, the live recording's eight transcript pages, its live line and 36 small queries of past
  /// recordings: 48.
  func observedPlans() -> [InstantQueryPlan] {
    var plans = (0..<3).map { page in Self.listPlan(id: "fanout.list.\(page)", offset: page * 50, limit: 50) }
    plans += (0..<8).map { page in
      InstantQueryPlan(
        id: "fanout.transcript.\(page)",
        namespace: Self.segments,
        filters: [.equals(field: "recordingID", value: .string(Self.recordingID(Self.live)))],
        order: InstantQueryOrder("index", .descending),
        offset: page == 0 ? nil : page * 64,
        limit: 64
      )
    }
    plans.append(
      InstantQueryPlan(
        id: "fanout.live-line",
        namespace: Self.liveLines,
        filters: [.equals(field: "recordingID", value: .string(Self.recordingID(Self.live)))]
      )
    )
    for index in 0..<36 {
      let recording = Self.live - 1 - index
      let namespace = [Self.segments, Self.attachments, Self.transcriptions][index % 3]
      plans.append(
        InstantQueryPlan(
          id: "fanout.past.\(index)",
          namespace: namespace,
          filters: [.equals(field: "recordingID", value: .string(Self.recordingID(recording)))],
          limit: 64
        )
      )
    }
    return plans
  }

  static func listPlan(id: String, offset: Int?, limit: Int?) -> InstantQueryPlan {
    func include(_ name: String, _ namespace: String, order: InstantQueryOrder? = nil, limit: Int? = nil) -> InstantQueryInclude {
      InstantQueryInclude(
        name,
        query: InstantQueryPlan(id: "\(id).\(name)", namespace: namespace, order: order, limit: limit)
      )!
    }
    return InstantQueryPlan(
      id: id,
      namespace: recordings,
      order: InstantQueryOrder("startedAtMs", .descending),
      offset: offset,
      limit: limit,
      includes: [
        include("transcriptions", transcriptions, order: InstantQueryOrder("updatedAtMs", .descending), limit: 3),
        include("previewSegmentA", segments),
        include("previewSegmentB", segments),
        include("audioAttachment", attachments),
        include("previewImage", attachments),
      ]
    )
  }

  /// Every recording with three transcriptions, its lines, two preview lines, an audio file and a preview image; the
  /// live one has 512 lines and one open.
  mutating func seededStore() async throws -> InstantStore {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: Self.attributes))
    for recording in 0..<Self.recordingCount {
      var operations: [InstantTripleOperation] = []
      let id = Self.recordingID(recording)
      let segmentCount = recording == Self.live
        ? Self.liveSegmentCount + (interimsAreLinked ? 1 : 0)
        : Self.pastSegmentCount
      operations += Self.entity(
        id,
        Self.recordings,
        [
          "title": .string("Recording \(recording)"),
          "startedAtMs": .number(Double(recording) * 60_000),
          "durationSeconds": .number(600),
          "updatedAtMs": .number(Double(recording) * 60_000),
        ]
      )
      for index in 0..<3 {
        let transcription = Self.transcriptionID(recording, index)
        operations += Self.entity(
          transcription,
          Self.transcriptions,
          ["recordingID": .string(id), "updatedAtMs": .number(Double(index)), "status": .string("done")]
        )
        operations.append(Self.set(id, "transcriptions", .ref(transcription)))
      }
      for index in 0..<segmentCount {
        let segment = Self.segmentID(recording, index)
        operations += Self.entity(segment, Self.segments, Self.segmentValues(recording, index, revision: 0, final: true))
        operations.append(Self.set(id, "segments", .ref(segment)))
      }
      let lastFinal = recording == Self.live ? Self.liveSegmentCount - 1 : Self.pastSegmentCount - 1
      for index in [lastFinal - 1, lastFinal] {
        operations.append(Self.set(id, Self.previewSlot(index), .ref(Self.segmentID(recording, index))))
      }
      if recording == Self.live, !interimsAreLinked {
        operations += Self.entity(
          Self.liveLineID(Self.liveSegmentCount),
          Self.liveLines,
          Self.liveLineValues(Self.liveSegmentCount, revision: 0)
        )
      }
      for (index, kind) in ["audio", "image"].enumerated() {
        let attachment = Self.attachmentID(recording, index)
        operations += Self.entity(
          attachment,
          Self.attachments,
          [
            "recordingID": .string(id), "kind": .string(kind), "url": .string("file:///\(attachment)"),
            "updatedAtMs": .number(Double(index)),
          ]
        )
        operations.append(Self.set(id, kind == "audio" ? "audioAttachment" : "previewImage", .ref(attachment)))
      }
      let transactionID = "fanout-seed-\(recording)"
      let prepared = try await store.prepareCurrent(
        InstantStoreTransaction(id: transactionID, operations: operations.map { $0.stamped(transactionID, step: 0) })
      )
      _ = await store.commitAndPublish(prepared)
    }
    return store
  }

  /// The live recording's next write: its open line's next interim, every fifth write the line's final, and every
  /// eighth the recording's duration.
  mutating func nextWrite() -> Write {
    step += 1
    let live = Self.recordingID(Self.live)
    let transactionID = "fanout-write-\(step)"
    if step % 8 == 0 {
      return Write(
        kind: "duration",
        transaction: InstantStoreTransaction(
          id: transactionID,
          operations: [Self.set(live, "durationSeconds", .number(600 + Double(step)))]
            .map { $0.stamped(transactionID, step: step) }
        )
      )
    }
    openRevision += 1
    if openRevision < 5 {
      let operations = interimsAreLinked
        ? Self.entity(
          Self.segmentID(Self.live, openSegment),
          Self.segments,
          Self.segmentValues(Self.live, openSegment, revision: openRevision, final: false)
        )
        : Self.entity(Self.liveLineID(openSegment), Self.liveLines, Self.liveLineValues(openSegment, revision: openRevision))
      return Write(
        kind: "interim",
        transaction: InstantStoreTransaction(
          id: transactionID,
          operations: operations.map { $0.stamped(transactionID, step: step) }
        )
      )
    }
    let finalLine = Self.segmentID(Self.live, openSegment)
    var operations = Self.entity(
      finalLine,
      Self.segments,
      Self.segmentValues(Self.live, openSegment, revision: openRevision, final: true)
    )
    operations.append(Self.set(live, "segments", .ref(finalLine)))
    operations.append(Self.set(live, Self.previewSlot(openSegment), .ref(finalLine)))
    if !interimsAreLinked {
      operations.append(.deleteEntityInNamespace(entityID: Self.liveLineID(openSegment), namespace: Self.liveLines))
    }
    openSegment += 1
    openRevision = 0
    if interimsAreLinked {
      let next = Self.segmentID(Self.live, openSegment)
      operations += Self.entity(next, Self.segments, Self.segmentValues(Self.live, openSegment, revision: 0, final: false))
      operations.append(Self.set(live, "segments", .ref(next)))
    } else {
      operations += Self.entity(Self.liveLineID(openSegment), Self.liveLines, Self.liveLineValues(openSegment, revision: 0))
    }
    return Write(
      kind: "final",
      transaction: InstantStoreTransaction(
        id: transactionID,
        operations: operations.map { $0.stamped(transactionID, step: step) }
      )
    )
  }

  /// The preview slot a final line goes to, as the app picks it: A for an even index, B for an odd one.
  static func previewSlot(_ index: Int) -> String {
    index.isMultiple(of: 2) ? "previewSegmentA" : "previewSegmentB"
  }

  static func liveLineValues(_ index: Int, revision: Int) -> [String: InstantValue] {
    var values = segmentValues(live, index, revision: revision, final: false)
    values["segmentIndex"] = values.removeValue(forKey: "index")
    values["isFinal"] = nil
    return values
  }

  static func segmentValues(_ recording: Int, _ index: Int, revision: Int, final: Bool) -> [String: InstantValue] {
    let words = (0..<(4 + revision * 3)).map { word in
      JSONValue.object([
        "text": .string("word\(word)"),
        "start": .number(Double(index) * 5 + Double(word) * 0.3),
        "end": .number(Double(index) * 5 + Double(word) * 0.3 + 0.25),
      ])
    }
    return [
      "recordingID": .string(recordingID(recording)),
      "index": .number(Double(index)),
      "text": .string((0..<(4 + revision * 3)).map { "word\($0)" }.joined(separator: " ")),
      "wordsJSON": .json(.array(words)),
      "isFinal": .bool(final),
      "updatedAtMs": .number(Double(index) * 5_000 + Double(revision)),
    ]
  }

  /// An entity's primary key and values, unstamped.
  static func entity(_ id: String, _ namespace: String, _ values: [String: InstantValue]) -> [InstantTripleOperation] {
    [
      .insert(
        InstantTriple(
          entityID: id,
          attributeID: InstantAttribute.primaryKeyID(namespace: namespace),
          value: .string(id),
          txID: "",
          txTime: InstantTimestamp(milliseconds: 0)
        )
      )
    ]
      + values.keys.sorted().map { name in
        .insert(
          InstantTriple(
            entityID: id,
            attributeID: "\(namespace)/\(name)",
            value: values[name]!,
            txID: "",
            txTime: InstantTimestamp(milliseconds: 0)
          )
        )
      }
  }

  /// One value of a recording, unstamped.
  static func set(_ recording: String, _ name: String, _ value: InstantValue) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: recording,
        attributeID: "\(recordings)/\(name)",
        value: value,
        txID: "",
        txTime: InstantTimestamp(milliseconds: 0)
      )
    )
  }
}

extension InstantTripleOperation {
  /// This insert stamped with `transactionID` at `step`.
  fileprivate func stamped(_ transactionID: String, step: Int) -> InstantTripleOperation {
    guard case var .insert(triple) = self else { return self }
    triple.txID = transactionID
    triple.txTime = InstantPageRefreshEnergyTests.time(step)
    return .insert(triple)
  }
}
