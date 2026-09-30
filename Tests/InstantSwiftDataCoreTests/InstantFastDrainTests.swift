import CustomDump
import Darwin
import Foundation
import Testing

@testable import InstantSwiftDataCore

// #296 open item 2. Recording 023's iPhone holds 2,487 pending writes linked to one recording. Every server frame
// that touched them peeled and replayed the whole connected component (1,864 and 616 writes); two finished rebases
// took 22.5 s and 24.9 s, and the outbox drained about 33 writes per 55 s. These tests drive a Scribe-shaped outbox
// through a consistent fake server: it accepts writes in delivery order and answers each with the full results of
// the queries the write touched, the way Instant's `refresh-ok` does.

// MARK: - Schema

enum FastDrainSchema {
  static let recordingID = "fast-drain-recording"
  static let transcriptionID = "fast-drain-transcription"
  static let ownerID = "fast-drain-owner"

  static func segmentID(_ index: Int) -> String {
    "fast-drain-segment-\(String(format: "%05d", index))"
  }

  /// Scribe's own link shape: `recordings/segments` and `recordings/transcriptions` are forward on the recording, with
  /// many values, and each write inserts the reverse form (`transcriptionSegments/recording`), which the store
  /// materializes on the recording. Recording 023's phone store holds them this way.
  static let scribeLinkAttributes: [InstantAttribute] = attributes.filter {
    $0.id != "transcriptionSegments/recording" && $0.id != "transcriptions/recording"
  } + [
    InstantAttribute(
      id: "recordings/segments", namespace: "recordings", name: "segments", valueType: .ref,
      isRequired: false, cardinality: .many, isIndexed: true,
      forwardIdentity: "recordings/segments", reverseIdentity: "transcriptionSegments/recording",
      linkNamespace: "transcriptionSegments", onDeleteReverse: .cascade
    ),
    InstantAttribute(
      id: "recordings/transcriptions", namespace: "recordings", name: "transcriptions", valueType: .ref,
      isRequired: false, cardinality: .many, isIndexed: true,
      forwardIdentity: "recordings/transcriptions", reverseIdentity: "transcriptions/recording",
      linkNamespace: "transcriptions", onDeleteReverse: .cascade
    ),
  ]

  static let attributes: [InstantAttribute] = [
    InstantAttribute(
      id: "recordings/id", namespace: "recordings", name: "id", valueType: .string,
      isRequired: false, isIndexed: true, isUnique: true, primaryKey: true
    ),
    InstantAttribute(id: "recordings/title", namespace: "recordings", name: "title", valueType: .string, isRequired: false),
    InstantAttribute(id: "recordings/activityKind", namespace: "recordings", name: "activityKind", valueType: .string, isRequired: false),
    InstantAttribute(id: "recordings/durationSeconds", namespace: "recordings", name: "durationSeconds", valueType: .number, isRequired: false),
    InstantAttribute(id: "recordings/updatedAtMs", namespace: "recordings", name: "updatedAtMs", valueType: .number, isRequired: false),
    InstantAttribute(
      id: "recordings/previewSegmentB", namespace: "recordings", name: "previewSegmentB", valueType: .ref,
      isRequired: false, cardinality: .one, isIndexed: true,
      forwardIdentity: "recordings/previewSegmentB", reverseIdentity: "transcriptionSegments/previewOfB",
      linkNamespace: "transcriptionSegments"
    ),
    InstantAttribute(
      id: "transcriptionSegments/id", namespace: "transcriptionSegments", name: "id", valueType: .string,
      isRequired: false, isIndexed: true, isUnique: true, primaryKey: true
    ),
    InstantAttribute(id: "transcriptionSegments/text", namespace: "transcriptionSegments", name: "text", valueType: .string, isRequired: false),
    InstantAttribute(id: "transcriptionSegments/segmentIndex", namespace: "transcriptionSegments", name: "segmentIndex", valueType: .number, isRequired: false),
    InstantAttribute(id: "transcriptionSegments/isFinal", namespace: "transcriptionSegments", name: "isFinal", valueType: .boolean, isRequired: false),
    InstantAttribute(id: "transcriptionSegments/ownerUserID", namespace: "transcriptionSegments", name: "ownerUserID", valueType: .string, isRequired: false),
    InstantAttribute(id: "transcriptionSegments/recordingID", namespace: "transcriptionSegments", name: "recordingID", valueType: .string, isRequired: false),
    InstantAttribute(id: "transcriptionSegments/wordsJSON", namespace: "transcriptionSegments", name: "wordsJSON", valueType: .string, isRequired: false),
    InstantAttribute(id: "transcriptionSegments/startTimeSeconds", namespace: "transcriptionSegments", name: "startTimeSeconds", valueType: .number, isRequired: false),
    InstantAttribute(id: "transcriptionSegments/endTimeSeconds", namespace: "transcriptionSegments", name: "endTimeSeconds", valueType: .number, isRequired: false),
    InstantAttribute(id: "transcriptionSegments/updatedAtMs", namespace: "transcriptionSegments", name: "updatedAtMs", valueType: .number, isRequired: false),
    InstantAttribute(
      id: "transcriptionSegments/recording", namespace: "transcriptionSegments", name: "recording", valueType: .ref,
      isRequired: false, cardinality: .one, isIndexed: true,
      forwardIdentity: "transcriptionSegments/recording", reverseIdentity: "recordings/transcriptionSegments",
      linkNamespace: "recordings"
    ),
    InstantAttribute(
      id: "transcriptions/id", namespace: "transcriptions", name: "id", valueType: .string,
      isRequired: false, isIndexed: true, isUnique: true, primaryKey: true
    ),
    InstantAttribute(id: "transcriptions/segmentCount", namespace: "transcriptions", name: "segmentCount", valueType: .number, isRequired: false),
    InstantAttribute(id: "transcriptions/wordCount", namespace: "transcriptions", name: "wordCount", valueType: .number, isRequired: false),
    InstantAttribute(id: "transcriptions/updatedAtMs", namespace: "transcriptions", name: "updatedAtMs", valueType: .number, isRequired: false),
    InstantAttribute(
      id: "transcriptions/recording", namespace: "transcriptions", name: "recording", valueType: .ref,
      isRequired: false, cardinality: .one, isIndexed: true,
      forwardIdentity: "transcriptions/recording", reverseIdentity: "recordings/transcriptions",
      linkNamespace: "recordings"
    ),
  ]
}

// MARK: - Local writes, shaped like Scribe's live recording writes

/// Scribe's writes during a live recording, per new transcript segment: open-segment updates while the words grow,
/// the final segment (which also re-asserts the recording's id), the recording summary with the transcription counts,
/// and a recording duration tick. Every write re-inserts whole rows, as `ScribeRecordingLibrary.persist` does.
struct FastDrainWriteScript {
  var nextSegmentIndex: Int
  var deviceMilliseconds: Int64
  var wordCount = 0
  var writeCount = 0

  init(firstSegmentIndex: Int, deviceMilliseconds: Int64) {
    nextSegmentIndex = firstSegmentIndex
    self.deviceMilliseconds = deviceMilliseconds
  }

  mutating func nextSegmentWrites() -> [InstantStoreTransaction] {
    let index = nextSegmentIndex
    nextSegmentIndex += 1
    var writes: [InstantStoreTransaction] = []
    var words: [String] = []
    for update in 0..<3 {
      words.append("word\(index)-\(update)")
      writes.append(segmentWrite(index: index, words: words, isFinal: false, assertsRecording: false))
    }
    words.append("final\(index)")
    writes.append(segmentWrite(index: index, words: words, isFinal: true, assertsRecording: true))
    wordCount += words.count
    writes.append(summaryWrite(previewSegmentIndex: index))
    writes.append(durationWrite())
    return writes
  }

  private mutating func stamp() -> (id: String, time: InstantTimestamp, milliseconds: Double) {
    deviceMilliseconds += 97
    writeCount += 1
    return (
      "fast-drain-write-\(String(format: "%05d", writeCount))",
      InstantTimestamp(milliseconds: deviceMilliseconds),
      Double(deviceMilliseconds) + 0.25
    )
  }

  private mutating func segmentWrite(
    index: Int,
    words: [String],
    isFinal: Bool,
    assertsRecording: Bool
  ) -> InstantStoreTransaction {
    let (id, time, updatedAt) = stamp()
    let segment = FastDrainSchema.segmentID(index)
    func insert(_ attribute: String, _ value: InstantValue) -> InstantTripleOperation {
      .insert(InstantTriple(entityID: segment, attributeID: "transcriptionSegments/\(attribute)", value: value, txID: id, txTime: time))
    }
    var operations: [InstantTripleOperation] = []
    if assertsRecording {
      operations.append(.requireEntityExists(entityID: FastDrainSchema.recordingID, namespace: "recordings"))
      operations.append(
        .insert(InstantTriple(entityID: FastDrainSchema.recordingID, attributeID: "recordings/id", value: .string(FastDrainSchema.recordingID), txID: id, txTime: time))
      )
    }
    operations += [
      insert("id", .string(segment)),
      insert("ownerUserID", .string(FastDrainSchema.ownerID)),
      insert("recordingID", .string(FastDrainSchema.recordingID)),
      insert("segmentIndex", .number(Double(index))),
      insert("startTimeSeconds", .number(Double(index) * 4.25)),
      insert("endTimeSeconds", .number(Double(index) * 4.25 + Double(words.count))),
      insert("text", .string(words.joined(separator: " "))),
      insert("wordsJSON", .string("[" + words.map { "{\"word\":\"\($0)\"}" }.joined(separator: ",") + "]")),
      insert("isFinal", .bool(isFinal)),
      insert("updatedAtMs", .number(updatedAt)),
      insert("recording", .ref(FastDrainSchema.recordingID)),
    ]
    return InstantStoreTransaction(id: id, operations: operations)
  }

  private mutating func summaryWrite(previewSegmentIndex: Int) -> InstantStoreTransaction {
    let (id, time, updatedAt) = stamp()
    let recording = FastDrainSchema.recordingID
    let transcription = FastDrainSchema.transcriptionID
    return InstantStoreTransaction(
      id: id,
      operations: [
        .requireEntityExists(entityID: recording, namespace: "recordings"),
        .insert(InstantTriple(entityID: recording, attributeID: "recordings/id", value: .string(recording), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: recording, attributeID: "recordings/updatedAtMs", value: .number(updatedAt), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: recording, attributeID: "recordings/previewSegmentB", value: .ref(FastDrainSchema.segmentID(previewSegmentIndex)), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: transcription, attributeID: "transcriptions/id", value: .string(transcription), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: transcription, attributeID: "transcriptions/segmentCount", value: .number(Double(previewSegmentIndex + 1)), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: transcription, attributeID: "transcriptions/wordCount", value: .number(Double(wordCount)), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: transcription, attributeID: "transcriptions/updatedAtMs", value: .number(updatedAt), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: transcription, attributeID: "transcriptions/recording", value: .ref(recording), txID: id, txTime: time)),
      ]
    )
  }

  /// The write that marks the recording live (`activityKind`), as Scribe's start does.
  mutating func startWrite() -> InstantStoreTransaction {
    activityWrite("active")
  }

  /// The Stop: the only write of `activityKind` after the start, so its slot's first pending writer is the newest
  /// write, behind every other pending write of the recording (Recording 023's 18:44:07 Stop).
  mutating func stopWrite() -> InstantStoreTransaction {
    activityWrite("idle")
  }

  private mutating func activityWrite(_ kind: String) -> InstantStoreTransaction {
    let (id, time, updatedAt) = stamp()
    let recording = FastDrainSchema.recordingID
    return InstantStoreTransaction(
      id: id,
      operations: [
        .insert(InstantTriple(entityID: recording, attributeID: "recordings/id", value: .string(recording), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: recording, attributeID: "recordings/activityKind", value: .string(kind), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: recording, attributeID: "recordings/updatedAtMs", value: .number(updatedAt), txID: id, txTime: time)),
      ]
    )
  }

  private mutating func durationWrite() -> InstantStoreTransaction {
    let (id, time, updatedAt) = stamp()
    let recording = FastDrainSchema.recordingID
    return InstantStoreTransaction(
      id: id,
      operations: [
        .requireEntityExists(entityID: recording, namespace: "recordings"),
        .insert(InstantTriple(entityID: recording, attributeID: "recordings/id", value: .string(recording), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: recording, attributeID: "recordings/durationSeconds", value: .number(Double(writeCount) * 1.5), txID: id, txTime: time)),
        .insert(InstantTriple(entityID: recording, attributeID: "recordings/updatedAtMs", value: .number(updatedAt), txID: id, txTime: time)),
      ]
    )
  }
}

// MARK: - A consistent fake server

/// The queries Scribe keeps registered while a recording is open, reduced to the three whose results Recording 023's
/// writes change: the recording's timeline (the recording and every segment), the recording list with its preview
/// slot, and the transcription summary.
enum FastDrainQuery: String, CaseIterable, Sendable {
  case timeline
  case list
  case transcription

  var key: String { "fast-drain-query-\(rawValue)" }

  /// Scribe's timeline does not select a segment's owner; no query this device keeps does (#296 Pattern B).
  var omittedAttributeIDs: Set<String> {
    self == .timeline ? ["transcriptionSegments/ownerUserID"] : []
  }
}

/// Holds what the server has applied: each accepted write in order, stamped with the server's transaction time, the
/// way Instant stores it. Results are full query results, as `refresh-ok` computations carry them.
struct FastDrainServer {
  struct Fact: Equatable {
    var value: InstantValue
    var txTime: Int64
  }

  /// The timeline's window: the newest segments, as a paged transcript query holds them. Recording 023's phone kept
  /// 4 live results totalling 624 facts (the recording list the largest, 576). `INSTANT_FAST_DRAIN_TIMELINE_WINDOW=0`
  /// selects every segment instead, a stress case.
  var timelineWindow: Int = {
    let window = ProcessInfo.processInfo.environment["INSTANT_FAST_DRAIN_TIMELINE_WINDOW"].flatMap(Int.init) ?? 32
    return window == 0 ? .max : window
  }()

  /// The list result's link window, like Scribe's `attachments` include (limit 24).
  static let listLinkWindow = 24

  /// Every fact by entity, attribute, and value. Cardinality-one attributes hold one value.
  private(set) var facts: [String: [String: [InstantValue: Int64]]] = [:]
  private(set) var lastTransactionNumber: Int64 = 10_000
  private(set) var serverMilliseconds: Int64
  private let attributesByID: [String: InstantAttribute]
  /// Forward link attributes by their reverse identity, so a reverse-form write lands where the server keeps it.
  private let forwardByReverseIdentity: [String: InstantAttribute]

  init(serverMilliseconds: Int64, attributes: [InstantAttribute] = FastDrainSchema.attributes) {
    self.serverMilliseconds = serverMilliseconds
    attributesByID = Dictionary(uniqueKeysWithValues: attributes.map { ($0.id, $0) })
    forwardByReverseIdentity = Dictionary(
      attributes.compactMap { attribute in attribute.reverseIdentity.map { ($0, attribute) } },
      uniquingKeysWith: { first, _ in first }
    )
  }

  /// The one value a cardinality-one fact holds, for assertions.
  func value(_ entityID: String, _ attributeID: String) -> InstantValue? {
    facts[entityID]?[attributeID]?.keys.first
  }

  private mutating func store(entityID: String, attributeID: String, value: InstantValue, txTime: Int64) {
    if let forward = forwardByReverseIdentity[attributeID], case let .ref(targetID) = value {
      store(entityID: targetID, attributeID: forward.id, value: .ref(entityID), txTime: txTime)
      return
    }
    if attributesByID[attributeID]?.cardinality == .many {
      facts[entityID, default: [:]][attributeID, default: [:]][value] = txTime
    } else {
      facts[entityID, default: [:]][attributeID] = [value: txTime]
    }
  }

  /// Applies one accepted transaction's inserts and returns its server transaction id.
  mutating func accept(_ operations: [InstantTripleOperation]) -> String {
    lastTransactionNumber += 1
    serverMilliseconds += 3
    for operation in operations {
      guard case let .insert(triple) = operation else { continue }
      store(entityID: triple.entityID, attributeID: triple.attributeID, value: triple.value, txTime: serverMilliseconds)
    }
    return String(lastTransactionNumber)
  }

  /// A write another device made: the server changes one fact without this device's outbox.
  mutating func acceptForeignWrite(entityID: String, attributeID: String, value: InstantValue) -> String {
    lastTransactionNumber += 1
    serverMilliseconds += 1_000_000
    store(entityID: entityID, attributeID: attributeID, value: value, txTime: serverMilliseconds)
    return String(lastTransactionNumber)
  }

  func entities(in query: FastDrainQuery) -> [String] {
    let recording = FastDrainSchema.recordingID
    switch query {
    case .timeline:
      let segments = facts
        .filter { $0.value["transcriptionSegments/recordingID"]?.keys.first == .string(recording) }
        .map(\.key)
        .sorted()
      return (facts[recording] == nil ? [] : [recording]) + segments.suffix(timelineWindow)
    case .list:
      var entities = facts[recording] == nil ? [] : [recording]
      if case let .ref(preview)? = value(recording, "recordings/previewSegmentB"), facts[preview] != nil {
        entities.append(preview)
      }
      return entities
    case .transcription:
      return facts[FastDrainSchema.transcriptionID] == nil ? [] : [FastDrainSchema.transcriptionID]
    }
  }

  func triples(in query: FastDrainQuery, transactionID: String) -> [InstantTriple] {
    entities(in: query).flatMap { entityID in
      (facts[entityID] ?? [:]).keys.sorted().filter { attributeID in
        guard !query.omittedAttributeIDs.contains(attributeID) else { return false }
        // Links from the recording travel only in the list result, as Scribe's attachments do.
        return query == .list || attributesByID[attributeID]?.cardinality != .many
      }.flatMap { attributeID -> [InstantTriple] in
        var values = facts[entityID]![attributeID]!.sorted { $0.key.comparableKey < $1.key.comparableKey }
        if attributesByID[attributeID]?.cardinality == .many {
          values = Array(values.suffix(Self.listLinkWindow))
        }
        return values.map { value, txTime in
          InstantTriple(
            entityID: entityID,
            attributeID: attributeID,
            value: value,
            txID: transactionID,
            txTime: InstantTimestamp(milliseconds: txTime)
          )
        }
      }
    }
  }

  /// The queries a write's entities appear in, as the server's invalidation would select them.
  func queries(touching entityIDs: Set<String>) -> [FastDrainQuery] {
    FastDrainQuery.allCases.filter { query in
      !Set(entities(in: query)).isDisjoint(with: entityIDs)
    }
  }

  /// One `refresh-ok`-shaped frame: every triple of each query result as an insert stamped with the processed
  /// transaction id, plus the result replacements that drive live-query retraction and persistence.
  func frame(
    queries: [FastDrainQuery],
    processedTransactionID: String
  ) -> (transaction: InstantStoreTransaction, replacements: [InstantLiveQueryResultReplacement]) {
    var operations: [InstantTripleOperation] = []
    var replacements: [InstantLiveQueryResultReplacement] = []
    for query in queries {
      let triples = triples(in: query, transactionID: processedTransactionID)
      operations += triples.map(InstantTripleOperation.insert)
      replacements.append(InstantLiveQueryResultReplacement(key: query.key, triples: triples, pageInfo: nil))
    }
    return (InstantStoreTransaction(id: processedTransactionID, operations: operations), replacements)
  }
}

// MARK: - Fixture

struct FastDrainFixture {
  var runtime: InstantRuntime
  var server: FastDrainServer
  var script: FastDrainWriteScript
  var claimSequence = 0
  /// The delivery clock claims are stamped with. Advancing it past the 6 s claim deadline makes the next claim
  /// reclaim unanswered writes and send them again, the replays Recording 023's phone made after lost answers.
  var claimMilliseconds: Int64 = 1_790_800_000_000

  /// A server base like Recording 023 at segment 549 (the recording, its transcription, and `serverSegmentCount`
  /// segments, with every query result stored), then `pendingSegmentCount` segments of pending local writes (six
  /// writes each).
  static func make(
    suffix: String,
    serverSegmentCount: Int,
    pendingSegmentCount: Int,
    reducesServerApply: Bool = true,
    timelineWindow: Int? = nil,
    scribeLinks: Bool = false,
    endsWithStop: Bool = false,
    defersSegmentText: Bool = false
  ) async throws -> Self {
    let attributes = scribeLinks ? FastDrainSchema.scribeLinkAttributes : FastDrainSchema.attributes
    let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "instant-fast-drain-\(suffix)-\(UUID().uuidString).sqlite"
    )
    let clock = FastDrainClock(milliseconds: 1_790_700_000_000)
    var configuration = InstantRuntimeConfiguration(
      appID: "fast-drain-\(suffix)",
      persistenceURL: cacheURL,
      initialAttributes: attributes,
      now: { clock.now() }
    )
    // INSTANT_FAST_DRAIN_FULL_REBASE=1 runs every fixture on the whole-component rebase, the behavior before #296's
    // fast drain, so these tests can be seen failing against it.
    configuration.reducesServerApplyToAffectedOverlays =
      reducesServerApply && ProcessInfo.processInfo.environment["INSTANT_FAST_DRAIN_FULL_REBASE"] != "1"
    if defersSegmentText {
      // Scribe keeps a segment's text and words out of memory (`ScribeInstantBootstrap.deferredValueResidency`).
      configuration.deferredValueResidency = InstantDeferredValueResidencyPolicy(
        attributeIDs: ["transcriptionSegments/text", "transcriptionSegments/wordsJSON"]
      )
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    // The server's history before this device went offline: the same writes, already accepted.
    var server = FastDrainServer(serverMilliseconds: 1_790_700_000_000, attributes: attributes)
    if let timelineWindow { server.timelineWindow = timelineWindow }
    var history = FastDrainWriteScript(firstSegmentIndex: 0, deviceMilliseconds: 1_790_600_000_000)
    if endsWithStop {
      _ = server.accept(history.startWrite().operations)
    }
    for _ in 0..<serverSegmentCount {
      for write in history.nextSegmentWrites() {
        _ = server.accept(write.operations)
      }
    }
    let seedTransactionID = String(server.lastTransactionNumber)
    let seed = server.frame(queries: FastDrainQuery.allCases, processedTransactionID: seedTransactionID)
    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      seed.transaction,
      attributesToMerge: [],
      liveQueryResultReplacements: seed.replacements
    )

    var script = FastDrainWriteScript(
      firstSegmentIndex: serverSegmentCount,
      deviceMilliseconds: 1_790_710_000_000
    )
    for _ in 0..<pendingSegmentCount {
      for write in script.nextSegmentWrites() {
        _ = try await runtime.transact(write, createdAt: InstantTimestamp(milliseconds: script.deviceMilliseconds))
      }
    }
    if endsWithStop {
      let stop = script.stopWrite()
      _ = try await runtime.transact(stop, createdAt: InstantTimestamp(milliseconds: script.deviceMilliseconds))
    }
    return Self(runtime: runtime, server: server, script: script)
  }

  /// Writes more local segments while the drain runs, as a still-recording phone does.
  mutating func writeSegments(_ count: Int) async throws -> [String] {
    var ids: [String] = []
    for _ in 0..<count {
      for write in script.nextSegmentWrites() {
        _ = try await runtime.transact(write, createdAt: InstantTimestamp(milliseconds: script.deviceMilliseconds))
        ids.append(write.id)
      }
    }
    return ids
  }

  /// Claims the next delivery window the way the automatic pump does.
  mutating func claimWindow(maximumMutationCount: Int = 50) async throws -> (token: String, mutations: [PendingMutation]) {
    claimSequence += 1
    let token = "fast-drain-claim-\(claimSequence)"
    let window = try await runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: await runtime.automaticDeliveryClaimantIDForTesting(),
        claimToken: token,
        now: InstantTimestamp(milliseconds: claimMilliseconds),
        maximumMutationCount: maximumMutationCount
      )
    )
    return (token, window.mutations)
  }

  /// The server accepts one claimed write (`transact-ok`), then answers with one frame holding the full results of
  /// the queries that write touched (`refresh-ok`).
  mutating func acceptAndRefresh(
    _ mutation: PendingMutation,
    claimToken: String
  ) async throws -> FastDrainFrameMeasurement {
    let transactionID = server.accept(mutation.transaction.operations)
    _ = try await runtime.acceptMutationIfPresent(
      id: mutation.id,
      serverTransactionID: transactionID,
      claimToken: claimToken
    )
    let touched = Set(mutation.transaction.operations.compactMap(\.fastDrainInsertedTriple).map(\.entityID))
    return try await refresh(queries: server.queries(touching: touched), processedTransactionID: transactionID)
  }

  /// Delivers one server frame with the current results of `queries`.
  func refresh(
    queries: [FastDrainQuery],
    processedTransactionID: String? = nil
  ) async throws -> FastDrainFrameMeasurement {
    let processed = processedTransactionID ?? String(server.lastTransactionNumber)
    let frame = server.frame(queries: queries, processedTransactionID: processed)
    let before = await runtime.persistence.serverApplyMetricsForTesting()
    let started = ContinuousClock.now
    _ = try await runtime.applyServerTransactionMergingAttributesForTesting(
      frame.transaction,
      attributesToMerge: [],
      liveQueryResultReplacements: frame.replacements
    )
    let elapsed = ContinuousClock.now - started
    let after = await runtime.persistence.serverApplyMetricsForTesting()
    return FastDrainFrameMeasurement(
      duration: elapsed,
      plannedBodyCount: after.plannedComponentBodyCount - before.plannedComponentBodyCount,
      decodedBodyCount: after.decodedBodyCount - before.decodedBodyCount
    )
  }

  func pendingCount() async throws -> Int {
    try await runtime.persistence.countOutboxMutations(status: .pending)
  }
}

struct FastDrainFrameMeasurement {
  var duration: Duration
  /// Pending writes the frame peeled and replayed (its component); pruned, confirmed, and re-receipted rows are not
  /// counted.
  var plannedBodyCount: Int
  var decodedBodyCount: Int

  /// A frame that peeled and replayed pending writes, rather than only pruning and recording results.
  var isRebase: Bool { plannedBodyCount > 0 }
}

struct FastDrainMeasurement: CustomStringConvertible {
  var writesAtStart = 0
  var frames = 0
  var rebases = 0
  var plannedBodies = 0
  var decodedBodies = 0
  var wall: Duration = .zero
  var cpuMilliseconds = 0.0
  var slowestFrame: Duration = .zero
  var applyTime: Duration = .zero
  var rebaseTime: Duration = .zero

  mutating func record(_ frame: FastDrainFrameMeasurement) {
    frames += 1
    plannedBodies += frame.plannedBodyCount
    decodedBodies += frame.decodedBodyCount
    applyTime += frame.duration
    slowestFrame = max(slowestFrame, frame.duration)
    if frame.isRebase {
      rebases += 1
      rebaseTime += frame.duration
    }
  }

  var description: String {
    """
    writes \(writesAtStart), frames \(frames), rebases \(rebases) (\(milliseconds(rebaseTime)) ms), \
    bodies planned \(plannedBodies) decoded \(decodedBodies), wall \(milliseconds(wall)) ms, \
    apply \(milliseconds(applyTime)) ms, slowest frame \(milliseconds(slowestFrame)) ms, \
    process CPU \(Int(cpuMilliseconds)) ms
    """
  }

  private func milliseconds(_ duration: Duration) -> Int {
    Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
  }
}

/// Process CPU time (user plus system, all threads): the runtime's work runs on actor executors, not the test's
/// thread.
enum FastDrainProcessCPU {
  static func milliseconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let user = Double(usage.ru_utime.tv_sec) * 1_000 + Double(usage.ru_utime.tv_usec) / 1_000
    let system = Double(usage.ru_stime.tv_sec) * 1_000 + Double(usage.ru_stime.tv_usec) / 1_000
    return user + system
  }
}

final class FastDrainDeclineCounter: @unchecked Sendable {
  private let lock = NSLock()
  private var counts: [String: Int] = [:]

  /// Counts the reduction's decline reasons (with the attribute that decided each) while `body` runs.
  static func counting<T>(_ body: () async throws -> T) async rethrows -> (T, [String: Int]) {
    let declines = FastDrainDeclineCounter()
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard entry.event == "server-apply.reduction-declined" else { return }
      declines.record(
        [entry.metadata["reason"], entry.metadata["attributeID"]].compactMap { $0 }.joined(separator: " ")
      )
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }
    let value = try await body()
    return (value, declines.snapshot())
  }

  func record(_ reason: String) {
    lock.lock()
    defer { lock.unlock() }
    counts[reason, default: 0] += 1
  }

  func snapshot() -> [String: Int] {
    lock.lock()
    defer { lock.unlock() }
    return counts
  }
}

final class FastDrainClock: @unchecked Sendable {
  private let lock = NSLock()
  private var milliseconds: Int64

  init(milliseconds: Int64) {
    self.milliseconds = milliseconds
  }

  func now() -> InstantTimestamp {
    lock.lock()
    defer { lock.unlock() }
    milliseconds += 1
    return InstantTimestamp(milliseconds: milliseconds)
  }
}

extension FastDrainFixture {
  /// Drains the outbox window by window, one server frame per accepted write, until nothing is pending or
  /// `maximumFrames` frames were delivered.
  mutating func drain(maximumFrames: Int = .max, windowSize: Int = 50) async throws -> FastDrainMeasurement {
    var measurement = FastDrainMeasurement()
    measurement.writesAtStart = try await pendingCount()
    let cpuStart = FastDrainProcessCPU.milliseconds()
    let started = ContinuousClock.now
    drain: while try await pendingCount() > 0 {
      let window = try await claimWindow(maximumMutationCount: windowSize)
      guard !window.mutations.isEmpty else { break }
      for mutation in window.mutations {
        measurement.record(try await acceptAndRefresh(mutation, claimToken: window.token))
        if measurement.frames >= maximumFrames { break drain }
      }
    }
    measurement.wall = ContinuousClock.now - started
    measurement.cpuMilliseconds = FastDrainProcessCPU.milliseconds() - cpuStart
    return measurement
  }
}

// MARK: - Measurements

@Suite(.serialized)
struct InstantFastDrainTests {
  /// The phone's reconnect: each connection re-sent its queries, and the server answered each with a result equal
  /// to the one stored. Each such result peeled and replayed the whole component.
  @Test
  func anUnchangedQueryResultDoesNotRebaseThePendingWrites() async throws {
    let fixture = try await FastDrainFixture.make(suffix: "unchanged", serverSegmentCount: 20, pendingSegmentCount: 20)
    for query in FastDrainQuery.allCases {
      let frame = try await fixture.refresh(queries: [query])
      expectNoDifference(frame.plannedBodyCount, 0, "\(query) result equal to the stored one peeled \(frame.plannedBodyCount) writes")
    }
    let pending = try await fixture.pendingCount()
    expectNoDifference(pending, 120)
  }

  /// The drain itself: the server accepts the oldest pending write and answers with the results that write changed.
  /// Those results only restate what the device already shows, so no pending write needs to be peeled.
  @Test
  func aFrameThatOnlyConfirmsAcceptedWritesDoesNotRebaseThePendingWrites() async throws {
    var fixture = try await FastDrainFixture.make(suffix: "confirming", serverSegmentCount: 20, pendingSegmentCount: 20)
    let measurement = try await fixture.drain(maximumFrames: 60)
    print("confirming frames: \(measurement)")
    expectNoDifference(measurement.rebases, 0)
    let pending = try await fixture.pendingCount()
    expectNoDifference(pending, 60)
  }

  /// Measures a Scribe-shaped drain. Scale with `INSTANT_FAST_DRAIN_SEGMENTS` (six writes per segment) and cap the
  /// frames with `INSTANT_FAST_DRAIN_MAX_FRAMES`; the defaults keep the suite fast.
  @Test
  func measureAScribeShapedDrain() async throws {
    let environment = ProcessInfo.processInfo.environment
    let segments = environment["INSTANT_FAST_DRAIN_SEGMENTS"].flatMap(Int.init) ?? 50
    let maximumFrames = environment["INSTANT_FAST_DRAIN_MAX_FRAMES"].flatMap(Int.init) ?? .max
    let reduces = environment["INSTANT_FAST_DRAIN_FULL_REBASE"] != "1"
    let setupStarted = ContinuousClock.now
    var fixture = try await FastDrainFixture.make(
      suffix: "measure",
      serverSegmentCount: 550,
      pendingSegmentCount: segments,
      reducesServerApply: reduces
    )
    let setup = ContinuousClock.now - setupStarted

    var reconnect = FastDrainMeasurement()
    reconnect.writesAtStart = try await fixture.pendingCount()
    let reconnectCPU = FastDrainProcessCPU.milliseconds()
    let reconnectStarted = ContinuousClock.now
    for query in FastDrainQuery.allCases {
      reconnect.record(try await fixture.refresh(queries: [query]))
    }
    reconnect.wall = ContinuousClock.now - reconnectStarted
    reconnect.cpuMilliseconds = FastDrainProcessCPU.milliseconds() - reconnectCPU

    let declines = FastDrainDeclineCounter()
    let token = InstantDiagnostics.shared.addHandler { entry in
      guard entry.event == "server-apply.reduction-declined" else { return }
      declines.record(
        [entry.metadata["reason"], entry.metadata["attributeID"]].compactMap { $0 }.joined(separator: " ")
      )
    }
    defer { InstantDiagnostics.shared.removeHandler(token) }
    let drain = try await fixture.drain(maximumFrames: maximumFrames)
    let pendingAfter = try await fixture.pendingCount()
    print(
      """
      fast-drain measurement (\(reduces ? "reduced" : "full rebase")), setup \(setup)
        reconnect: \(reconnect)
        drain: \(drain)
        pending after: \(pendingAfter)
        declined reductions: \(declines.snapshot())
      """
    )
    if maximumFrames == .max {
      let pending = try await fixture.pendingCount()
      expectNoDifference(pending, 0)
    }
  }
}

extension InstantTripleOperation {
  fileprivate var fastDrainInsertedTriple: InstantTriple? {
    if case let .insert(triple) = self { return triple }
    return nil
  }
}

// MARK: - Differential: the reduced apply against the whole-component rebase

/// What a read can observe: every fact's value, and each pending write's identity and state. Stamps (`txID`,
/// `txTime`) are last-write-wins bookkeeping; the full rebase re-stamps every replayed write, the reduced apply does
/// not replay them.
struct FastDrainObservation: Equatable, CustomDumpStringConvertible {
  struct Fact: Hashable, Comparable {
    var entityID: String
    var attributeID: String
    var value: String

    static func < (lhs: Self, rhs: Self) -> Bool {
      (lhs.entityID, lhs.attributeID, lhs.value) < (rhs.entityID, rhs.attributeID, rhs.value)
    }
  }

  struct Write: Hashable {
    var id: String
    var status: InstantMutationStatus
    var overlay: String
  }

  var hotFacts: [Fact]
  var persistedFacts: [Fact]
  var outbox: [Write]

  static func observe(_ runtime: InstantRuntime) async throws -> Self {
    func facts(_ triples: [InstantTriple]) -> [Fact] {
      Set(triples.map { Fact(entityID: $0.entityID, attributeID: $0.attributeID, value: "\($0.value)") }).sorted()
    }
    let hot = await runtime.store.snapshot()
    let state = try await runtime.persistence.loadState()
    return Self(
      hotFacts: facts(hot.triples),
      persistedFacts: facts(state.snapshot.store.triples),
      outbox: state.snapshot.outbox
        .sorted(by: PendingMutation.creationOrder)
        .map { Write(id: $0.id, status: $0.status, overlay: "\($0.optimisticOverlayState)") }
    )
  }

  var customDumpDescription: String {
    "\(hotFacts.count) hot facts, \(persistedFacts.count) persisted facts, \(outbox.count) outbox rows"
  }
}

/// SplitMix64, so a failing seed replays exactly.
struct FastDrainRandom {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func int(_ range: ClosedRange<Int>) -> Int {
    range.lowerBound + Int(next() % UInt64(range.count))
  }

  mutating func chance(_ percent: Int) -> Bool { int(1...100) <= percent }
}

/// One server, two devices with the same outbox: `reduced` applies frames with #296's reduction, `full` peels and
/// replays the whole component for every frame, as before.
struct FastDrainDifferentialPair {
  var reduced: FastDrainFixture
  var full: FastDrainFixture
  var log: [String] = []
  /// Writes the server has applied, answered or not. A re-send of one is a replay the app's rules can refuse.
  var appliedMutationIDs: Set<String> = []

  static func make(
    seed: UInt64,
    serverSegmentCount: Int,
    pendingSegmentCount: Int,
    scribeLinks: Bool = false,
    endsWithStop: Bool = false,
    defersSegmentText: Bool = false
  ) async throws -> Self {
    Self(
      reduced: try await FastDrainFixture.make(
        suffix: "differential-\(seed)-reduced",
        serverSegmentCount: serverSegmentCount,
        pendingSegmentCount: pendingSegmentCount,
        reducesServerApply: true,
        timelineWindow: 5,
        scribeLinks: scribeLinks,
        endsWithStop: endsWithStop,
        defersSegmentText: defersSegmentText
      ),
      full: try await FastDrainFixture.make(
        suffix: "differential-\(seed)-full",
        serverSegmentCount: serverSegmentCount,
        pendingSegmentCount: pendingSegmentCount,
        reducesServerApply: false,
        timelineWindow: 5,
        scribeLinks: scribeLinks,
        endsWithStop: endsWithStop,
        defersSegmentText: defersSegmentText
      )
    )
  }

  func expectSameObservation(
    after event: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async throws -> Bool {
    let reducedObservation = try await FastDrainObservation.observe(reduced.runtime)
    let fullObservation = try await FastDrainObservation.observe(full.runtime)
    let same = reducedObservation == fullObservation
    if !same {
      expectNoDifference(
        reducedObservation.hotFacts,
        fullObservation.hotFacts,
        "hot store after \(event); events: \(log.suffix(8).joined(separator: " | "))"
      )
      expectNoDifference(
        reducedObservation.persistedFacts,
        fullObservation.persistedFacts,
        "persisted store after \(event)"
      )
      expectNoDifference(reducedObservation.outbox, fullObservation.outbox, "outbox after \(event)")
    }
    #expect(reduced.server.lastTransactionNumber == full.server.lastTransactionNumber, sourceLocation: sourceLocation)
    return same
  }

  /// Claims the same window on both devices; the windows must name the same writes.
  mutating func claim(_ count: Int) async throws -> [(reduced: String, full: String, mutation: PendingMutation)]? {
    let reducedWindow = try await reduced.claimWindow(maximumMutationCount: count)
    let fullWindow = try await full.claimWindow(maximumMutationCount: count)
    expectNoDifference(reducedWindow.mutations.map(\.id), fullWindow.mutations.map(\.id))
    guard reducedWindow.mutations.map(\.id) == fullWindow.mutations.map(\.id) else { return nil }
    return zip(reducedWindow.mutations, fullWindow.mutations).map {
      (reducedWindow.token, fullWindow.token, $0.0)
    }
  }

  /// The server applies the claimed writes in order. Each is acknowledged unless `losesAcknowledgements`; a frame
  /// follows each write with probability `framePercent`, and one frame for all touched queries always ends the batch.
  /// With `framesAheadOfAnswers`, a write's frame reaches the device before its answer, as Instant sometimes sends a
  /// refresh-ok ahead of the transact-ok it reflects.
  mutating func deliver(
    _ claimed: [(reduced: String, full: String, mutation: PendingMutation)],
    losesAcknowledgements: Bool,
    framePercent: Int,
    framesAheadOfAnswers: Bool = false,
    random: inout FastDrainRandom
  ) async throws {
    var touched: Set<String> = []
    for (reducedToken, fullToken, mutation) in claimed {
      let transactionID = reduced.server.accept(mutation.transaction.operations)
      _ = full.server.accept(mutation.transaction.operations)
      appliedMutationIDs.insert(mutation.id)
      let entities = Set(mutation.transaction.operations.compactMap(\.fastDrainInsertedTriple).map(\.entityID))
      touched.formUnion(entities)
      let framed = random.chance(framePercent)
      if framed, framesAheadOfAnswers {
        try await frame(queries: reduced.server.queries(touching: entities), processedTransactionID: transactionID)
      }
      if !losesAcknowledgements {
        _ = try await reduced.runtime.acceptMutationIfPresent(id: mutation.id, serverTransactionID: transactionID, claimToken: reducedToken)
        _ = try await full.runtime.acceptMutationIfPresent(id: mutation.id, serverTransactionID: transactionID, claimToken: fullToken)
      }
      if framed, !framesAheadOfAnswers {
        try await frame(queries: reduced.server.queries(touching: entities), processedTransactionID: transactionID)
      }
    }
    try await frame(queries: reduced.server.queries(touching: touched), processedTransactionID: nil)
  }

  mutating func frame(queries: [FastDrainQuery], processedTransactionID: String?) async throws {
    guard !queries.isEmpty else { return }
    _ = try await reduced.refresh(queries: queries, processedTransactionID: processedTransactionID)
    _ = try await full.refresh(queries: queries, processedTransactionID: processedTransactionID)
  }

  func pendingIDs() async -> [String] {
    await reduced.runtime.pendingMutations().map(\.id)
  }
}

extension InstantFastDrainTests {
  /// Randomized interleavings of acceptances, frames (one per write, coalesced, or skipped), reconnect re-sends,
  /// another device's writes, refusals, lost acknowledgements (Recording 023's replays), and new local writes. After
  /// every event the reduced device must observe exactly what the full-rebase device observes.
  @Test(arguments: [UInt64(1), 2, 3, 4, 5, 6])
  func theReducedApplyObservesWhatTheFullRebaseObserves(seed: UInt64) async throws {
    try await runDifferential(seed: seed, scribeLinks: false)
  }

  /// The same randomized interleavings with Scribe's own shape, which the fake-server schema above does not exercise:
  /// forward links on the recording written from the segment side, segment text and words kept out of memory, and a
  /// Stop behind the pending writes.
  @Test(arguments: [UInt64(11), 12, 13, 14, 15, 16])
  func theReducedApplyObservesWhatTheFullRebaseObservesWithScribeLinks(seed: UInt64) async throws {
    try await runDifferential(seed: seed, scribeLinks: true)
  }

  private func runDifferential(seed: UInt64, scribeLinks: Bool) async throws {
    var random = FastDrainRandom(seed: seed)
    var pair = try await FastDrainDifferentialPair.make(
      seed: seed,
      serverSegmentCount: 6,
      pendingSegmentCount: 8,
      scribeLinks: scribeLinks,
      endsWithStop: scribeLinks,
      defersSegmentText: scribeLinks
    )
    guard try await pair.expectSameObservation(after: "setup") else { return }
    for step in 0..<70 {
      let roll = random.int(1...100)
      let event: String
      switch roll {
      case 1...32:
        let count = random.int(1...12)
        guard let claimed = try await pair.claim(count) else { return }
        event = "deliver \(claimed.count)"
        try await pair.deliver(claimed, losesAcknowledgements: false, framePercent: random.int(0...100), random: &random)
      case 33...40:
        let count = random.int(1...12)
        guard let claimed = try await pair.claim(count) else { return }
        event = "deliver \(claimed.count), frames ahead of answers"
        try await pair.deliver(
          claimed, losesAcknowledgements: false, framePercent: random.int(30...100), framesAheadOfAnswers: true,
          random: &random
        )
      case 41...50:
        event = "reconnect re-send"
        for query in FastDrainQuery.allCases where random.chance(70) {
          try await pair.frame(queries: [query], processedTransactionID: nil)
        }
      case 51...62:
        let entityID: String
        let attributeID: String
        let value: InstantValue
        switch random.int(1...5) {
        case 1: (entityID, attributeID, value) = (FastDrainSchema.recordingID, "recordings/title", .string("title \(step)"))
        case 2: (entityID, attributeID, value) = (FastDrainSchema.recordingID, "recordings/updatedAtMs", .number(Double(step)))
        case 3: (entityID, attributeID, value) = (FastDrainSchema.transcriptionID, "transcriptions/wordCount", .number(Double(step)))
        case 4:
          let index = random.int(0...(pair.reduced.script.nextSegmentIndex - 1))
          (entityID, attributeID, value) = (FastDrainSchema.segmentID(index), "transcriptionSegments/text", .string("edited \(step)"))
        default:
          (entityID, attributeID, value) = (FastDrainSchema.recordingID, "recordings/activityKind", .string(random.chance(50) ? "active" : "idle"))
        }
        guard pair.reduced.server.facts[entityID] != nil else { continue }
        event = "foreign \(entityID) \(attributeID)"
        let transactionID = pair.reduced.server.acceptForeignWrite(entityID: entityID, attributeID: attributeID, value: value)
        _ = pair.full.server.acceptForeignWrite(entityID: entityID, attributeID: attributeID, value: value)
        try await pair.frame(queries: pair.reduced.server.queries(touching: [entityID]), processedTransactionID: transactionID)
      case 63...70:
        guard let claimed = try await pair.claim(random.int(1...4)), let refused = claimed.first else { continue }
        event = "refuse \(refused.mutation.id) of \(claimed.count)"
        _ = try await pair.reduced.runtime.failMutation(id: refused.mutation.id, message: "Permission denied: not perms-pass?")
        _ = try await pair.full.runtime.failMutation(id: refused.mutation.id, message: "Permission denied: not perms-pass?")
        try await pair.deliver(Array(claimed.dropFirst()), losesAcknowledgements: false, framePercent: 50, random: &random)
      case 71...78:
        guard let claimed = try await pair.claim(random.int(1...6)) else { return }
        event = "lost acknowledgements for \(claimed.count)"
        try await pair.deliver(claimed, losesAcknowledgements: true, framePercent: 50, random: &random)
        // The answers never arrive: the claims expire and the next window sends the writes again.
        pair.reduced.claimMilliseconds += 10_000
        pair.full.claimMilliseconds += 10_000
      case 79...84:
        // The next window re-sends writes the server already applied; the app's rules refuse those replays
        // (Recording 023's validUpdate refusals), and the device rolls each back.
        guard let claimed = try await pair.claim(random.int(1...6)) else { return }
        let replays = claimed.filter { pair.appliedMutationIDs.contains($0.mutation.id) }
        guard !replays.isEmpty else {
          event = "no replays among \(claimed.count); deliver"
          try await pair.deliver(claimed, losesAcknowledgements: false, framePercent: 50, random: &random)
          break
        }
        event = "refuse \(replays.count) replays of \(claimed.count)"
        for replay in replays {
          _ = try await pair.reduced.runtime.failMutation(id: replay.mutation.id, message: "Permission denied: not perms-pass?")
          _ = try await pair.full.runtime.failMutation(id: replay.mutation.id, message: "Permission denied: not perms-pass?")
        }
        let fresh = claimed.filter { !pair.appliedMutationIDs.contains($0.mutation.id) }
        try await pair.deliver(fresh, losesAcknowledgements: false, framePercent: 50, random: &random)
      default:
        event = "local writes"
        let reducedIDs = try await pair.reduced.writeSegments(1)
        let fullIDs = try await pair.full.writeSegments(1)
        expectNoDifference(reducedIDs, fullIDs)
      }
      pair.log.append("\(step): \(event)")
      if ProcessInfo.processInfo.environment["INSTANT_FAST_DRAIN_TRACE"] == "1" {
        let metrics = await pair.reduced.runtime.persistence.serverApplyMetricsForTesting()
        func duration(_ runtime: InstantRuntime) async -> String {
          await runtime.store.snapshot().triples.first {
            $0.entityID == FastDrainSchema.recordingID && $0.attributeID == "recordings/durationSeconds"
          }.map { "\($0.value) tx \($0.txID) t \($0.txTime.milliseconds)" } ?? "none"
        }
        let pendingIDs = await pair.reduced.runtime.pendingMutations().map(\.id)
        print(
          """
          trace \(step): \(event) | reductions \(metrics.reductionCount) reduced \(metrics.reducedCount) \
          | reduced \(await duration(pair.reduced.runtime)) | full \(await duration(pair.full.runtime)) \
          | server \(pair.reduced.server.value(FastDrainSchema.recordingID, "recordings/durationSeconds").map { "\($0)" } ?? "none") \
          | pending \(pendingIDs.count) first \(pendingIDs.first ?? "-")
          """
        )
      }
      guard try await pair.expectSameObservation(after: "step \(step): \(event)") else { return }
    }
    let metrics = await pair.reduced.runtime.persistence.serverApplyMetricsForTesting()
    print(
      """
      differential seed \(seed)\(scribeLinks ? " (Scribe links)" : ""): \(metrics.reductionCount) reductions, \
      \(metrics.reducedCount) reduced, \(metrics.receiptPatchCount) receipt patches, \
      \(metrics.plannedComponentBodyCount) component bodies
      """
    )
  }
}

extension InstantFastDrainTests {
  /// Another device changes a slot a pending write also writes. Skipping that frame would leave the pending write's
  /// receipt holding the old base value, so refusing the write later would resurrect a value the server no longer has
  /// (the shape of #296's Pattern B). The frame must reach the receipt.
  @Test
  func aServerChangeBeneathAPendingWriteReachesItsReceipt() async throws {
    var fixture = try await FastDrainFixture.make(suffix: "beneath", serverSegmentCount: 4, pendingSegmentCount: 1)
    let pending = await fixture.runtime.pendingMutations()
    // The summary write is the only pending write of the recording's preview slot.
    let summary = try #require(pending.first { mutation in
      mutation.transaction.operations.contains {
        $0.fastDrainInsertedTriple?.attributeID == "recordings/previewSegmentB"
      }
    })
    let transactionID = fixture.server.acceptForeignWrite(
      entityID: FastDrainSchema.recordingID,
      attributeID: "recordings/previewSegmentB",
      value: .ref(FastDrainSchema.segmentID(0))
    )
    _ = try await fixture.refresh(queries: [.list, .timeline], processedTransactionID: transactionID)
    _ = try await fixture.runtime.failMutation(id: summary.id, message: "Permission denied: not perms-pass?")

    let state = try await fixture.runtime.persistence.loadState()
    let preview = state.snapshot.store.triples.first {
      $0.entityID == FastDrainSchema.recordingID && $0.attributeID == "recordings/previewSegmentB"
    }
    expectNoDifference(preview?.value, .ref(FastDrainSchema.segmentID(0)))
  }

  /// Recording 023's replays: the server applied a write whose answer was lost, so the write is still pending when a
  /// frame restates it, and its re-send is later refused. The base beneath the write changed, so its receipt must hold
  /// the server's values when the refusal rolls it back. The reduced apply patches that receipt instead of peeling and
  /// replaying the component; afterwards both devices must observe the same thing.
  @Test
  func aFrameRestatingAWriteWhoseAnswerWasLostPatchesItsReceiptWithoutARebase() async throws {
    var reduced = try await FastDrainFixture.make(suffix: "lost-answer-reduced", serverSegmentCount: 4, pendingSegmentCount: 2)
    var full = try await FastDrainFixture.make(
      suffix: "lost-answer-full", serverSegmentCount: 4, pendingSegmentCount: 2, reducesServerApply: false
    )
    let window = try await reduced.claimWindow(maximumMutationCount: 1)
    _ = try await full.claimWindow(maximumMutationCount: 1)
    let head = try #require(window.mutations.first)
    let transactionID = reduced.server.accept(head.transaction.operations)
    _ = full.server.accept(head.transaction.operations)
    let touched = Set(head.transaction.operations.compactMap(\.fastDrainInsertedTriple).map(\.entityID))
    let queries = reduced.server.queries(touching: touched)
    let (frame, declines) = try await FastDrainDeclineCounter.counting {
      try await reduced.refresh(queries: queries, processedTransactionID: transactionID)
    }
    _ = try await full.refresh(queries: queries, processedTransactionID: transactionID)
    expectNoDifference(frame.plannedBodyCount, 0, "declines: \(declines)")
    let pendingIDs = await reduced.runtime.pendingMutations().map(\.id)
    #expect(pendingIDs.contains(head.id))

    // The re-send is refused: the server applied the first offer. Rolling the write back must keep what the server has.
    _ = try await reduced.runtime.failMutation(id: head.id, message: "Permission denied: not perms-pass?")
    _ = try await full.runtime.failMutation(id: head.id, message: "Permission denied: not perms-pass?")
    let reducedObservation = try await FastDrainObservation.observe(reduced.runtime)
    let fullObservation = try await FastDrainObservation.observe(full.runtime)
    expectNoDifference(reducedObservation.hotFacts, fullObservation.hotFacts)
    expectNoDifference(reducedObservation.persistedFacts, fullObservation.persistedFacts)
    expectNoDifference(reducedObservation.outbox, fullObservation.outbox)
  }

  /// Seen live on the build-71 soak: Instant can send a query's refresh before the answer to the write it reflects
  /// (a refresh-ok 50 ms ahead of its transact-ok). The write is still pending, so the frame changes the base beneath
  /// it. Every such frame fell back to the whole-component rebase, the rebases grew with the backlog, and the device
  /// fell behind the recording. The frame must patch the receipts instead, and match the full rebase afterwards.
  @Test
  func aFrameAheadOfItsAnswersDoesNotRebaseThePendingWrites() async throws {
    var reduced = try await FastDrainFixture.make(suffix: "in-flight-reduced", serverSegmentCount: 4, pendingSegmentCount: 4)
    var full = try await FastDrainFixture.make(
      suffix: "in-flight-full", serverSegmentCount: 4, pendingSegmentCount: 4, reducesServerApply: false
    )
    for round in 0..<3 {
      let window = try await reduced.claimWindow(maximumMutationCount: 5)
      let fullWindow = try await full.claimWindow(maximumMutationCount: 5)
      expectNoDifference(window.mutations.map(\.id), fullWindow.mutations.map(\.id))
      var accepted: [(mutation: PendingMutation, transactionID: String)] = []
      var touched: Set<String> = []
      for mutation in window.mutations {
        let transactionID = reduced.server.accept(mutation.transaction.operations)
        _ = full.server.accept(mutation.transaction.operations)
        accepted.append((mutation, transactionID))
        touched.formUnion(mutation.transaction.operations.compactMap(\.fastDrainInsertedTriple).map(\.entityID))
      }
      // The refresh for the whole window arrives first.
      let queries = reduced.server.queries(touching: touched)
      let processed = accepted.last?.transactionID
      let (frame, declines) = try await FastDrainDeclineCounter.counting {
        try await reduced.refresh(queries: queries, processedTransactionID: processed)
      }
      _ = try await full.refresh(queries: queries, processedTransactionID: processed)
      expectNoDifference(
        frame.plannedBodyCount, 0, "round \(round): the frame ahead of its answers rebased; declines: \(declines)"
      )
      // Then the answers.
      for (mutation, transactionID) in accepted {
        _ = try await reduced.runtime.acceptMutationIfPresent(id: mutation.id, serverTransactionID: transactionID, claimToken: window.token)
        _ = try await full.runtime.acceptMutationIfPresent(id: mutation.id, serverTransactionID: transactionID, claimToken: fullWindow.token)
      }
      let reducedObservation = try await FastDrainObservation.observe(reduced.runtime)
      let fullObservation = try await FastDrainObservation.observe(full.runtime)
      expectNoDifference(reducedObservation.hotFacts, fullObservation.hotFacts, "round \(round)")
      expectNoDifference(reducedObservation.persistedFacts, fullObservation.persistedFacts, "round \(round)")
      expectNoDifference(reducedObservation.outbox, fullObservation.outbox, "round \(round)")
    }
  }

  /// Scribe keeps segment text and words out of memory (deferred residency), so the store could not show them to the
  /// reduction, which then saw every restated segment as a change beneath its pending writes. Seen live on the fixed
  /// reduction's first soak: changesShadowedFact on `transcriptionSegments/text` and `wordsJSON` in most declines. The
  /// reduction must hydrate them, as the full rebase does, and match the full rebase afterwards.
  @Test
  func deferredSegmentTextDoesNotForceARebase() async throws {
    var reduced = try await FastDrainFixture.make(
      suffix: "deferred-reduced", serverSegmentCount: 6, pendingSegmentCount: 4, defersSegmentText: true
    )
    var full = try await FastDrainFixture.make(
      suffix: "deferred-full", serverSegmentCount: 6, pendingSegmentCount: 4, reducesServerApply: false,
      defersSegmentText: true
    )
    let (measurement, declines) = try await FastDrainDeclineCounter.counting {
      try await reduced.drain(maximumFrames: 12)
    }
    _ = try await full.drain(maximumFrames: 12)
    expectNoDifference(measurement.rebases, 0, "declines: \(declines)")
    let reducedObservation = try await FastDrainObservation.observe(reduced.runtime)
    let fullObservation = try await FastDrainObservation.observe(full.runtime)
    expectNoDifference(reducedObservation.persistedFacts, fullObservation.persistedFacts)
    expectNoDifference(reducedObservation.outbox, fullObservation.outbox)
  }

  /// Scribe writes a recording's links from the other side: each summary re-asserts the transcription's `recording`,
  /// which the store keeps as the recording's `transcriptions`. Seen live: reverseLinkWriter declines on
  /// `recordings/transcriptions` and `recordings/attachments` whenever such a write was pending. The writer's receipt
  /// shows the link was already there, so the frame changes nothing beneath it.
  @Test
  func aLinkReassertedFromTheOtherSideDoesNotForceARebase() async throws {
    var reduced = try await FastDrainFixture.make(
      suffix: "reverse-link-reduced", serverSegmentCount: 6, pendingSegmentCount: 4, scribeLinks: true
    )
    var full = try await FastDrainFixture.make(
      suffix: "reverse-link-full", serverSegmentCount: 6, pendingSegmentCount: 4, reducesServerApply: false,
      scribeLinks: true
    )
    let (measurement, declines) = try await FastDrainDeclineCounter.counting {
      try await reduced.drain(maximumFrames: 12)
    }
    _ = try await full.drain(maximumFrames: 12)
    expectNoDifference(measurement.rebases, 0, "declines: \(declines)")
    let reducedObservation = try await FastDrainObservation.observe(reduced.runtime)
    let fullObservation = try await FastDrainObservation.observe(full.runtime)
    expectNoDifference(reducedObservation.persistedFacts, fullObservation.persistedFacts)
    expectNoDifference(reducedObservation.outbox, fullObservation.outbox)
  }

  /// Recording 023 ends with a Stop: the only pending write of `activityKind`, behind every other pending write of the
  /// recording. The reduction used to prove that none of the recording's earlier writes retracted the slot by
  /// decoding them, capped at 32, so every frame after a Stop fell back to the whole-component rebase. The Stop's own
  /// receipt already shows the base value beneath it.
  @Test
  func aStopBehindManyPendingWritesDoesNotRebaseTheDrainFrames() async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "stop", serverSegmentCount: 4, pendingSegmentCount: 10, endsWithStop: true
    )
    let measurement = try await fixture.drain(maximumFrames: 30)
    print("frames behind a Stop: \(measurement)")
    expectNoDifference(measurement.rebases, 0)
  }
}

extension InstantFastDrainTests {
  /// #296 Pattern B, reproduced: 8 of Recording 023's segments (502-545) lost `ownerUserID` on the phone while the
  /// server has it. The server applied a segment's first write, but its answer was lost; the newer writes of that
  /// segment were accepted; the replay of the first write was refused. The next server apply both removes the refused
  /// write's overlay and prunes the accepted ones at the watermark. The reverse pass skips the pruned rows and peels
  /// the refused create, whose receipt deletes the whole entity, so it also deletes the facts the pruned writes kept.
  /// The server result restores only what a query selects, and no query selects the owner.
  ///
  /// This is the whole-component rebase path (a failed overlay makes the reduced apply ineligible), which this change
  /// does not alter. Recorded as a known issue until that path is fixed.
  @Test(arguments: [true, false])
  func patternBARefusedCreatePeeledBeneathPrunedWritesDropsUnselectedFields(reduces: Bool) async throws {
    var fixture = try await FastDrainFixture.make(
      suffix: "pattern-b-\(reduces)",
      serverSegmentCount: 4,
      // More than 50 connected writes, so the refusal defers its component peel to the next server apply, as each of
      // Recording 023's 36 refusals did (`outbox.mutation.terminal-component-deferred`).
      pendingSegmentCount: 10,
      reducesServerApply: reduces
    )
    let segment = FastDrainSchema.segmentID(4)
    let window = try await fixture.claimWindow(maximumMutationCount: 4)
    expectNoDifference(window.mutations.count, 4)
    let create = window.mutations[0]
    // The server applied the create on an earlier connection; its answer was lost.
    _ = fixture.server.accept(create.transaction.operations)
    var lastTransactionID = ""
    for mutation in window.mutations.dropFirst() {
      lastTransactionID = fixture.server.accept(mutation.transaction.operations)
      _ = try await fixture.runtime.acceptMutationIfPresent(
        id: mutation.id,
        serverTransactionID: lastTransactionID,
        claimToken: window.token
      )
    }
    // The create's replay is refused: the server already holds newer values for the row.
    _ = try await fixture.runtime.failClaimedMutationForTesting(
      id: create.id,
      message: "Permission denied: not perms-pass?",
      claimToken: window.token
    )
    _ = try await fixture.refresh(queries: [.timeline, .list], processedTransactionID: lastTransactionID)

    let state = try await fixture.runtime.persistence.loadState()
    let owner = state.snapshot.store.triples.first {
      $0.entityID == segment && $0.attributeID == "transcriptionSegments/ownerUserID"
    }
    withKnownIssue("#296 Pattern B: the refused create's receipt is peeled beneath the pruned writes") {
      expectNoDifference(owner?.value, .string(FastDrainSchema.ownerID))
    }
    let text = state.snapshot.store.triples.first {
      $0.entityID == segment && $0.attributeID == "transcriptionSegments/text"
    }
    expectNoDifference(text?.value, fixture.server.value(segment, "transcriptionSegments/text"))
  }
}

extension InstantFastDrainTests {
  /// A pending write shows on top of the server's facts. The store resolves cardinality-one facts by stamp, and a
  /// resident fact can carry a later stamp than a new local write (a server clock ahead of this device's, or an
  /// overlay a rebase restamped), so the write lost and stayed invisible until the next whole-component rebase
  /// restamped it. With frames no longer rebasing, it must show at once.
  @Test
  func aLocalWriteShowsEvenWhenTheResidentFactCarriesALaterStamp() async throws {
    var fixture = try await FastDrainFixture.make(suffix: "later-stamp", serverSegmentCount: 2, pendingSegmentCount: 0)
    let transactionID = fixture.server.acceptForeignWrite(
      entityID: FastDrainSchema.recordingID,
      attributeID: "recordings/title",
      value: .string("from the server")
    )
    _ = try await fixture.refresh(queries: [.list], processedTransactionID: transactionID)
    let serverStamp = try #require(
      await fixture.runtime.store.snapshot().triples.first {
        $0.entityID == FastDrainSchema.recordingID && $0.attributeID == "recordings/title"
      }?.txTime.milliseconds
    )

    // This device's clock is behind the server's.
    let localStamp = InstantTimestamp(milliseconds: serverStamp - 60_000)
    _ = try await fixture.runtime.transact(
      InstantStoreTransaction(
        id: "later-stamp-local-title",
        operations: [
          .insert(InstantTriple(entityID: FastDrainSchema.recordingID, attributeID: "recordings/title", value: .string("typed on this device"), txID: "later-stamp-local-title", txTime: localStamp))
        ]
      ),
      createdAt: localStamp
    )

    let shown = await fixture.runtime.store.snapshot().triples.first {
      $0.entityID == FastDrainSchema.recordingID && $0.attributeID == "recordings/title"
    }?.value
    expectNoDifference(shown, .string("typed on this device"))
    let persisted = try await fixture.runtime.persistence.loadState().snapshot.store.triples.first {
      $0.entityID == FastDrainSchema.recordingID && $0.attributeID == "recordings/title"
    }?.value
    expectNoDifference(persisted, .string("typed on this device"))

    // Delivery drops an assignment stamped older than the visible fact, so an invisible write was never sent either.
    let window = try await fixture.runtime.persistence.claimAutomaticOutboxDeliveryWindow(
      InstantAutomaticOutboxClaimRequest(
        claimantID: await fixture.runtime.automaticDeliveryClaimantIDForTesting(),
        claimToken: "later-stamp-claim",
        now: InstantTimestamp(milliseconds: fixture.claimMilliseconds)
      )
    )
    let sentTitles = window.projectedMutations.flatMap(\.transaction.operations).compactMap { operation -> InstantValue? in
      guard case let .insert(triple) = operation, triple.attributeID == "recordings/title" else { return nil }
      return triple.value
    }
    expectNoDifference(sentTitles, [.string("typed on this device")])
  }
}
