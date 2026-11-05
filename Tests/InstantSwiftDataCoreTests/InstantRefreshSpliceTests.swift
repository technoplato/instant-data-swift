import Foundation
import Testing

@testable import InstantSwiftDataCore

// History:
// - 2026-11-04: #1513: a final line on a recording phone re-materialized the recordings list and the transcript's
//   windows, scanning every recording, or every line of the recording, for one changed row. The store now splices the
//   rows a publication reaches; these tests hold the cost (nothing re-materializes) and, over random Scribe-shaped
//   writes, the result (every observer equals a fresh materialization). Equality is asserted with `#expect`, which a
//   release run judges (`expectNoDifference` records nothing there).

/// A recording phone's publications (#1513): the recordings list (newest first, each row with its newest
/// transcriptions, two preview lines and its audio), the live recording's transcript windows (its newest lines by index
/// and by update time) and its live lines.
@Suite(.serialized)
struct InstantRefreshSpliceTests {
  /// A final line splices the list's row of its recording and places the new line in each window: no page is
  /// materialized from the store again.
  @Test
  func aFinalLineSplicesTheListRowAndPlacesTheLineInEachWindow() async throws {
    var fixture = SpliceFixture()
    let store = try await fixture.seededStore()
    let readings = await SpliceFixture.observe(SpliceFixture.plans(), in: store)
    defer { readings.forEach { $0.cancel() } }

    try await SpliceFixture.commit(fixture.finalLine(), to: store)

    let metrics = await store.lastPublishMetrics
    #expect(metrics.rematerializedObserverCount == 0, "\(metrics)")
    // The list's first page and the whole list (the recording's row), both windows, the live lines.
    #expect(metrics.splicedObserverCount == 5, "\(metrics)")
    // The list's second page does not show the live recording.
    #expect(metrics.skippedObserverCount == 1, "\(metrics)")
    try await SpliceFixture.expectEveryObserverIsFresh(in: store, "after the final")
  }

  /// The server's echo of a final brings new page info for the live windows: a window whose rows the page info does not
  /// bound still places the line among its rows and reports the new page info.
  @Test
  func theServersEchoWithNewPageInfoStillSplicesAHeadWindow() async throws {
    var fixture = SpliceFixture()
    let store = try await fixture.seededStore()
    let tail = SpliceFixture.tailWindow()
    let lease = await store.observeLiveQueryLease(
      tail,
      registrationKey: "splice.tail.key",
      remotePageInfo: .ready(SpliceFixture.pageInfo(first: "server-start", last: "server-end"))
    )
    let reading = Task { for await _ in lease.stream {} }
    defer { reading.cancel() }

    let prepared = try await store.prepareCurrent(fixture.finalLine())
    _ = await store.commitDeferringPublication(
      prepared,
      installingLiveQueryPageInfo: [
        InstantLiveQueryResultReplacement(
          key: "splice.tail.key",
          triples: [],
          pageInfo: SpliceFixture.pageInfo(first: "server-start-2", last: "server-end-2")
        )
      ]
    )
    await store.publishPendingChanges()

    let metrics = await store.lastPublishMetrics
    #expect(metrics.rematerializedObserverCount == 0, "\(metrics)")
    #expect(metrics.splicedObserverCount == 1, "\(metrics)")
    try await SpliceFixture.expectEveryObserverIsFresh(in: store, "after the echo")
  }

  /// Random finals, interims, heartbeats, retired and edited lines, transcriptions and attachments, preview slots moved
  /// to older lines, recordings that start, move or go, and lines deleted, alone and several to a publication, some with
  /// new page info for the live windows: after every publication each observer holds, and was last handed, exactly what
  /// a fresh materialization of its plan returns.
  @Test(arguments: [UInt64(15_130), 15_131, 15_132, 15_133, 15_134, 15_135, 15_136, 15_137])
  func everyObserverHoldsAFreshResultThroughRandomRecordingWrites(seed: UInt64) async throws {
    var fixture = SpliceFixture()
    let store = try await fixture.seededStore()
    var readings = await SpliceFixture.observe(SpliceFixture.plans() + SpliceFixture.extraPlans(), in: store)
    for (index, plan) in [SpliceFixture.tailWindow(), SpliceFixture.updatedWindow(), SpliceFixture.listPage(0)]
      .enumerated()
    {
      let lease = await store.observeLiveQueryLease(
        plan,
        registrationKey: "splice.live.\(index)",
        remotePageInfo: .ready(SpliceFixture.pageInfo(first: "start-\(index)", last: "end-\(index)"))
      )
      readings.append(Task { for await _ in lease.stream {} })
    }
    defer { readings.forEach { $0.cancel() } }
    try await SpliceFixture.expectEveryObserverIsFresh(in: store, "seed \(seed) at the start")

    var random = InfiniteWindowRandom(seed: seed)
    for step in 0..<70 {
      let writeCount = random.chance(25) ? random.int(2...4) : 1
      var transactions: [InstantStoreTransaction] = []
      for _ in 0..<writeCount {
        transactions.append(fixture.randomWrite(&random))
      }
      var pageInfo: [InstantLiveQueryResultReplacement] = []
      if random.chance(30) {
        let index = random.int(0...2)
        pageInfo.append(
          InstantLiveQueryResultReplacement(
            key: "splice.live.\(index)",
            triples: [],
            pageInfo: SpliceFixture.pageInfo(first: "start-\(index)-\(step)", last: "end-\(index)-\(step)")
          )
        )
      }
      for (offset, transaction) in transactions.enumerated() {
        let prepared = try await store.prepareCurrent(transaction)
        _ = await store.commitDeferringPublication(
          prepared,
          installingLiveQueryPageInfo: offset == transactions.count - 1 ? pageInfo : []
        )
      }
      await store.publishPendingChanges()
      try await SpliceFixture.expectEveryObserverIsFresh(in: store, "seed \(seed) step \(step)")
    }
  }
}

/// Scribe's recordings, transcriptions, lines, live lines and attachments, small, and the writes a recording makes
/// (#1513).
struct SpliceFixture {
  static let recordings = "spliceRecordings"
  static let transcriptions = "spliceTranscriptions"
  static let segments = "spliceSegments"
  static let liveLines = "spliceLiveLines"
  static let attachments = "spliceAttachments"
  static let seededRecordingCount = 7
  static let seededLineCount = 6
  /// The recording being recorded: it started last, so it heads the list.
  static let live = seededRecordingCount - 1

  private var step = 100
  private var recordingCount = SpliceFixture.seededRecordingCount
  /// Lines per recording, including deleted ones (an index is never reused).
  private var lineCounts = Array(repeating: SpliceFixture.seededLineCount, count: SpliceFixture.seededRecordingCount)
  private var deletedLines: Set<String> = []
  private var deletedRecordings: Set<Int> = []
  private var attachmentCount = 0
  /// The live recording's open line, which its live line shows until the final.
  private var openLine = SpliceFixture.seededLineCount

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
      scalar(recordings, "startedAtMs", .number, indexed: true),
      scalar(recordings, "durationSeconds", .number),
      scalar(recordings, "title", .string),
      link("transcriptions", to: transcriptions, many: true, reverse: "recording"),
      link("segments", to: segments, many: true, reverse: "recording"),
      link("previewSegmentA", to: segments, many: false, reverse: "previewOfA"),
      link("previewSegmentB", to: segments, many: false, reverse: "previewOfB"),
      link("audioAttachment", to: attachments, many: false, reverse: "audioOf"),
      .primaryKey(namespace: transcriptions),
      scalar(transcriptions, "recordingID", .string, indexed: true),
      scalar(transcriptions, "updatedAtMs", .number, indexed: true),
      scalar(transcriptions, "segmentCount", .number),
      .primaryKey(namespace: segments),
      scalar(segments, "recordingID", .string, indexed: true),
      scalar(segments, "index", .number, indexed: true),
      scalar(segments, "text", .string),
      scalar(segments, "updatedAtMs", .number, indexed: true),
      scalar(segments, "retiredAtMs", .number),
      .primaryKey(namespace: liveLines),
      scalar(liveLines, "recordingID", .string, indexed: true),
      scalar(liveLines, "segmentIndex", .number, indexed: true),
      scalar(liveLines, "text", .string),
      .primaryKey(namespace: attachments),
      scalar(attachments, "kind", .string),
    ]
  }()

  static func recordingID(_ recording: Int) -> String { "splice-recording-\(recording)" }
  static func transcriptionID(_ recording: Int, _ index: Int) -> String { "splice-transcription-\(recording)-\(index)" }
  static func segmentID(_ recording: Int, _ index: Int) -> String { "splice-segment-\(recording)-\(index)" }
  static func liveLineID(_ index: Int) -> String { "splice-live-line-\(index)" }

  // MARK: - Plans

  /// A page of the list, three recordings newest first, each with its two newest transcriptions, its preview lines and
  /// its audio: Scribe's list shape (ScribeRecordingLibrary.listQuery).
  static func listPage(_ page: Int?) -> InstantQueryPlan {
    let id = page.map { "splice.list.\($0)" } ?? "splice.list.all"
    func include(_ name: String, _ namespace: String, order: InstantQueryOrder? = nil, limit: Int? = nil)
      -> InstantQueryInclude
    {
      InstantQueryInclude(
        name,
        query: InstantQueryPlan(id: "\(id).\(name)", namespace: namespace, order: order, limit: limit)
      )!
    }
    return InstantQueryPlan(
      id: id,
      namespace: recordings,
      order: InstantQueryOrder("startedAtMs", .descending),
      offset: page.flatMap { $0 == 0 ? nil : $0 * 3 },
      limit: page == nil ? nil : 3,
      includes: [
        include("transcriptions", transcriptions, order: InstantQueryOrder("updatedAtMs", .descending), limit: 2),
        include("previewSegmentA", segments),
        include("previewSegmentB", segments),
        include("audioAttachment", attachments),
      ]
    )
  }

  /// The live recording's newest four lines by index, as the phone's transcript tail reads them.
  static func tailWindow() -> InstantQueryPlan {
    InstantQueryPlan(
      id: "splice.tail",
      namespace: segments,
      filters: [.equals(field: "recordingID", value: .string(recordingID(live)))],
      order: InstantQueryOrder("index", .descending),
      limit: 4
    )
  }

  /// The live recording's two most recently updated lines.
  static func updatedWindow() -> InstantQueryPlan {
    InstantQueryPlan(
      id: "splice.updated",
      namespace: segments,
      filters: [.equals(field: "recordingID", value: .string(recordingID(live)))],
      order: InstantQueryOrder("updatedAtMs", .descending),
      limit: 2
    )
  }

  /// The live recording's live lines, oldest first.
  static func liveLineWindow() -> InstantQueryPlan {
    InstantQueryPlan(
      id: "splice.live-lines",
      namespace: liveLines,
      filters: [.equals(field: "recordingID", value: .string(recordingID(live)))],
      order: InstantQueryOrder("segmentIndex", .ascending),
      limit: 8
    )
  }

  /// The list's first and second pages, the whole list, both windows and the live lines.
  static func plans() -> [InstantQueryPlan] {
    [listPage(0), listPage(1), listPage(nil), tailWindow(), updatedWindow(), liveLineWindow()]
  }

  /// More shapes for the random test: a page past a cursor, a window of an older recording's lines, the newest lines
  /// with no filter.
  static func extraPlans() -> [InstantQueryPlan] {
    var pastCursor = listPage(nil)
    pastCursor.id = "splice.list.after"
    pastCursor.after = InstantQueryCursor(
      entityID: recordingID(live - 2),
      sortValue: .number(Double(live - 2) * 60_000),
      inclusive: true
    )
    pastCursor.limit = 3
    return [
      pastCursor,
      InstantQueryPlan(
        id: "splice.older-tail",
        namespace: segments,
        filters: [.equals(field: "recordingID", value: .string(recordingID(live - 1)))],
        order: InstantQueryOrder("index", .descending),
        limit: 3
      ),
      InstantQueryPlan(
        id: "splice.newest-anywhere",
        namespace: segments,
        order: InstantQueryOrder("updatedAtMs", .descending),
        limit: 5
      ),
    ]
  }

  static func pageInfo(first: String, last: String) -> InstantQueryPageInfo {
    InstantQueryPageInfo(
      startCursor: InstantQueryCursor(entityID: first),
      endCursor: InstantQueryCursor(entityID: last),
      hasPreviousPage: false,
      hasNextPage: true
    )
  }

  // MARK: - Store

  /// Seven recordings a minute apart, each with two transcriptions, six lines (its last two in its preview slots) and
  /// an audio attachment; the live recording's open line in a live line.
  mutating func seededStore() async throws -> InstantStore {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: Self.attributes))
    for recording in 0..<Self.seededRecordingCount {
      var operations = Self.entity(
        Self.recordingID(recording),
        Self.recordings,
        [
          "startedAtMs": .number(Double(recording) * 60_000),
          "durationSeconds": .number(600),
          "title": .string("Recording \(recording)"),
        ]
      )
      for index in 0..<2 {
        let transcription = Self.transcriptionID(recording, index)
        operations += Self.entity(
          transcription,
          Self.transcriptions,
          [
            "recordingID": .string(Self.recordingID(recording)),
            "updatedAtMs": .number(Double(index)),
            "segmentCount": .number(0),
          ]
        )
        operations.append(Self.set(Self.recordingID(recording), "transcriptions", .ref(transcription)))
      }
      for index in 0..<Self.seededLineCount {
        operations += lineOperations(recording: recording, index: index, updatedAtMs: Double(index))
      }
      operations.append(
        Self.set(Self.recordingID(recording), "previewSegmentA", .ref(Self.segmentID(recording, Self.seededLineCount - 2)))
      )
      operations.append(
        Self.set(Self.recordingID(recording), "previewSegmentB", .ref(Self.segmentID(recording, Self.seededLineCount - 1)))
      )
      operations += attachmentOperations(recording: recording)
      try await Self.commit(transaction(operations), to: store)
    }
    try await Self.commit(transaction(liveLineOperations(index: openLine, revision: 0)), to: store)
    return store
  }

  // MARK: - Writes

  /// The live recording's open line made final: the line, linked to its recording and put in a preview slot, its
  /// transcription's count and time, its live line deleted and the next one's started.
  mutating func finalLine() -> InstantStoreTransaction {
    let index = openLine
    let recording = Self.live
    lineCounts[recording] = max(lineCounts[recording], index + 1)
    var operations = lineOperations(recording: recording, index: index, updatedAtMs: Double(step))
    operations.append(
      Self.set(
        Self.recordingID(recording),
        index.isMultiple(of: 2) ? "previewSegmentA" : "previewSegmentB",
        .ref(Self.segmentID(recording, index))
      )
    )
    operations.append(Self.set(Self.transcriptionID(recording, 1), "\(Self.transcriptions)/updatedAtMs", .number(Double(step))))
    operations.append(Self.set(Self.transcriptionID(recording, 1), "\(Self.transcriptions)/segmentCount", .number(Double(index))))
    operations.append(.deleteEntityInNamespace(entityID: Self.liveLineID(index), namespace: Self.liveLines))
    openLine += 1
    operations += liveLineOperations(index: openLine, revision: 0)
    return transaction(operations)
  }

  mutating func randomWrite(_ random: inout InfiniteWindowRandom) -> InstantStoreTransaction {
    let recording = random.int(0...(recordingCount - 1))
    switch random.int(0...13) {
    case 0, 1, 2:
      return finalLine()
    case 3, 4:
      // An interim: the open line's live line rewritten.
      return transaction(liveLineOperations(index: openLine, revision: random.int(1...9)))
    case 5:
      return heartbeat(recording)
    case 6:
      // A line retired or edited, shown or not.
      guard lineCounts[recording] > 0 else { return heartbeat(recording) }
      let index = random.int(0...(lineCounts[recording] - 1))
      let line = Self.segmentID(recording, index)
      guard !deletedLines.contains(line) else { return heartbeat(recording) }
      return random.chance(50)
        ? transaction([Self.set(line, "\(Self.segments)/retiredAtMs", .number(Double(step)))])
        : transaction([
          Self.set(line, "\(Self.segments)/text", .string("edit \(step)")),
          Self.set(line, "\(Self.segments)/updatedAtMs", .number(Double(step))),
        ])
    case 7:
      // A transcription touched: the older one may become the newest.
      let index = random.int(0...1)
      return transaction([
        Self.set(Self.transcriptionID(recording, index), "\(Self.transcriptions)/updatedAtMs", .number(Double(step)))
      ])
    case 8:
      // A preview slot moved to an older line, or a new audio attachment.
      if random.chance(50), lineCounts[recording] > 0 {
        let index = random.int(0...(lineCounts[recording] - 1))
        guard !deletedLines.contains(Self.segmentID(recording, index)) else { return heartbeat(recording) }
        return transaction([
          Self.set(Self.recordingID(recording), "previewSegmentB", .ref(Self.segmentID(recording, index)))
        ])
      }
      return transaction(attachmentOperations(recording: recording))
    case 9:
      // A recording starts, anywhere along the list's order.
      let new = recordingCount
      recordingCount += 1
      lineCounts.append(0)
      return transaction(
        Self.entity(
          Self.recordingID(new),
          Self.recordings,
          ["startedAtMs": .number(Double(random.int(0...600_000))), "durationSeconds": .number(0)]
        )
      )
    case 10:
      // A recording moves along the list's order.
      guard !deletedRecordings.contains(recording) else { return heartbeat(recording) }
      return transaction([
        Self.set(Self.recordingID(recording), "startedAtMs", .number(Double(random.int(0...600_000))))
      ])
    case 11:
      // A line deleted.
      guard lineCounts[recording] > 0 else { return heartbeat(recording) }
      let line = Self.segmentID(recording, random.int(0...(lineCounts[recording] - 1)))
      guard deletedLines.insert(line).inserted else { return heartbeat(recording) }
      return transaction([.deleteEntityInNamespace(entityID: line, namespace: Self.segments)])
    case 12:
      // A line of another recording, as a second device's recording writes it.
      guard recording != Self.live else { return finalLine() }
      let index = lineCounts[recording]
      lineCounts[recording] += 1
      return transaction(lineOperations(recording: recording, index: index, updatedAtMs: Double(step)))
    default:
      // A recording deleted, now and then.
      guard random.chance(20), recording != Self.live, deletedRecordings.insert(recording).inserted else {
        return heartbeat(recording)
      }
      return transaction([.deleteEntityInNamespace(entityID: Self.recordingID(recording), namespace: Self.recordings)])
    }
  }

  /// A recording's duration, written every few seconds while it records.
  private mutating func heartbeat(_ recording: Int) -> InstantStoreTransaction {
    transaction([Self.set(Self.recordingID(recording), "durationSeconds", .number(Double(step)))])
  }

  private mutating func transaction(_ operations: [InstantTripleOperation]) -> InstantStoreTransaction {
    step += 1
    let transactionID = "splice-tx-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: operations.map { operation in
        guard case var .insert(triple) = operation else { return operation }
        triple.txID = transactionID
        triple.txTime = InstantPageRefreshEnergyTests.time(step)
        return .insert(triple)
      }
    )
  }

  private func lineOperations(recording: Int, index: Int, updatedAtMs: Double) -> [InstantTripleOperation] {
    let line = Self.segmentID(recording, index)
    return Self.entity(
      line,
      Self.segments,
      [
        "recordingID": .string(Self.recordingID(recording)),
        "index": .number(Double(index)),
        "text": .string("line \(index)"),
        "updatedAtMs": .number(updatedAtMs),
      ]
    ) + [Self.set(Self.recordingID(recording), "segments", .ref(line))]
  }

  private func liveLineOperations(index: Int, revision: Int) -> [InstantTripleOperation] {
    Self.entity(
      Self.liveLineID(index),
      Self.liveLines,
      [
        "recordingID": .string(Self.recordingID(Self.live)),
        "segmentIndex": .number(Double(index)),
        "text": .string("live \(index) revision \(revision)"),
      ]
    )
  }

  private mutating func attachmentOperations(recording: Int) -> [InstantTripleOperation] {
    attachmentCount += 1
    let attachment = "splice-attachment-\(attachmentCount)"
    return Self.entity(attachment, Self.attachments, ["kind": .string("audio")])
      + [Self.set(Self.recordingID(recording), "audioAttachment", .ref(attachment))]
  }

  /// An entity's primary key and values, unstamped.
  static func entity(_ id: String, _ namespace: String, _ values: [String: InstantValue]) -> [InstantTripleOperation] {
    [insert(id, InstantAttribute.primaryKeyID(namespace: namespace), .string(id))]
      + values.keys.sorted().map { insert(id, "\(namespace)/\($0)", values[$0]!) }
  }

  /// One value of a recording (a bare name) or of any entity (an attribute id), unstamped.
  static func set(_ entityID: String, _ name: String, _ value: InstantValue) -> InstantTripleOperation {
    insert(entityID, name.contains("/") ? name : "\(recordings)/\(name)", value)
  }

  static func insert(_ entityID: String, _ attributeID: String, _ value: InstantValue) -> InstantTripleOperation {
    .insert(
      InstantTriple(
        entityID: entityID,
        attributeID: attributeID,
        value: value,
        txID: "",
        txTime: InstantTimestamp(milliseconds: 0)
      )
    )
  }

  // MARK: - Checks

  static func observe(_ plans: [InstantQueryPlan], in store: InstantStore) async -> [Task<Void, Never>] {
    await InstantUnresolvedEntityRefreshTests.observe(plans, in: store)
  }

  static func commit(_ transaction: InstantStoreTransaction, to store: InstantStore) async throws {
    try await InstantUnresolvedEntityRefreshTests.commit(transaction, to: store)
  }

  /// Every observer holds, and was last handed, what a fresh materialization of its plan returns.
  static func expectEveryObserverIsFresh(in store: InstantStore, _ description: String) async throws {
    let observed = await store.observerResultsForTesting()
    #expect(!observed.isEmpty)
    for result in observed {
      let fresh = await store.materializeEmission(result.plan, remotePageInfo: result.remotePageInfo)
      #expect(result.values == fresh.values, "\(description): \(result.plan.id) holds a stale result")
      #expect(result.pageInfo == fresh.pageInfo, "\(description): \(result.plan.id) holds stale page info")
      #expect(result.handedValues == fresh.values, "\(description): \(result.plan.id) was handed a stale result")
      #expect(result.handedPageInfo == fresh.pageInfo, "\(description): \(result.plan.id) was handed stale page info")
    }
  }
}
