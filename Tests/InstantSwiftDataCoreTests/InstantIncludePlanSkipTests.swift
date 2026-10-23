import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

/// #1007: a plan with includes (a recordings list showing each recording's newest lines and attachments) refreshed on
/// every change to any of its namespaces, so every page of the list re-materialized for a duration heartbeat, a line,
/// or an attachment of a recording another page shows. A page shows its root namespace's ordered set, windowed, and for
/// each shown root the included entities its links reach. A change that no shown entity holds, that touches no entity
/// linked to a shown one, and that moves no root in or out of the set or along its order, cannot change the page.
@Suite(.serialized)
struct InstantIncludePlanSkipTests {
  /// A heartbeat of a recording the second page shows refreshes the second page only.
  @Test
  func aHeartbeatRefreshesOnlyThePageThatShowsTheRecording() async throws {
    let store = try await Self.seededStore()
    let readings = await Self.observe(Self.pages(), in: store)
    defer { readings.forEach { $0.cancel() } }

    try await Self.commit(Self.heartbeat(recording: 4, seconds: 60, at: 500), to: store)

    let metrics = await store.lastPublishMetrics
    expectNoDifference(metrics.rematerializedObserverCount + metrics.splicedObserverCount, 1)
    expectNoDifference(metrics.skippedObserverCount, 2)
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "after the heartbeat")
  }

  /// A line of a recording the first page shows refreshes the first page only.
  @Test
  func aNewLineRefreshesOnlyThePageThatShowsItsRecording() async throws {
    let store = try await Self.seededStore()
    let readings = await Self.observe(Self.pages(), in: store)
    defer { readings.forEach { $0.cancel() } }

    try await Self.commit(Self.addSegment(recording: 8, index: 4, at: 500), to: store)

    let metrics = await store.lastPublishMetrics
    expectNoDifference(metrics.rematerializedObserverCount + metrics.splicedObserverCount, 1)
    expectNoDifference(metrics.skippedObserverCount, 2)
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "after the line")
  }

  /// An attachment the third page does not show, of a recording it does show, may enter that recording's newest two, so
  /// the third page refreshes; the others do not.
  @Test
  func aHiddenAttachmentOfAShownRecordingRefreshesItsPage() async throws {
    let store = try await Self.seededStore()
    let readings = await Self.observe(Self.pages(), in: store)
    defer { readings.forEach { $0.cancel() } }

    // Recording 1's oldest attachment, outside its newest two, becomes its newest.
    try await Self.commit(Self.touchAttachment(recording: 1, index: 0, updatedAtMs: 9_000, at: 500), to: store)

    let metrics = await store.lastPublishMetrics
    expectNoDifference(metrics.rematerializedObserverCount + metrics.splicedObserverCount, 1)
    expectNoDifference(metrics.skippedObserverCount, 2)
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "after the attachment")
  }

  /// An attachment linked to no recording any page shows refreshes no page.
  @Test
  func anAttachmentNoPageCanReachRefreshesNoPage() async throws {
    let store = try await Self.seededStore()
    let readings = await Self.observe(Self.pages(), in: store)
    defer { readings.forEach { $0.cancel() } }

    try await Self.commit(Self.orphanAttachment("loose", updatedAtMs: 9_000, at: 500), to: store)

    let metrics = await store.lastPublishMetrics
    expectNoDifference(metrics.rematerializedObserverCount + metrics.splicedObserverCount, 0)
    expectNoDifference(metrics.skippedObserverCount, 3)
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "after the loose attachment")
  }

  /// Random lines, attachments, heartbeats, moves along the list's order, new recordings and deletes, alone and in
  /// batches published together: after every publication each page holds, and was last handed, exactly what a fresh
  /// materialization of its plan returns.
  @Test(arguments: [UInt64(31_007), 31_008, 31_009, 31_010, 31_011, 31_012])
  func everyPageHoldsAFreshResultThroughRandomWrites(seed: UInt64) async throws {
    let store = try await Self.seededStore()
    let readings = await Self.observe(Self.pages() + Self.extraPlans(), in: store)
    defer { readings.forEach { $0.cancel() } }
    try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "seed \(seed) at the start")

    var random = InfiniteWindowRandom(seed: seed)
    var recordingCount = Self.recordingCount
    var segmentCounts = Array(repeating: Self.childCount, count: recordingCount)
    var attachmentCounts = Array(repeating: Self.childCount, count: recordingCount)
    var time = 1_000
    for step in 0..<80 {
      let writeCount = random.chance(30) ? random.int(2...4) : 1
      var transactions: [InstantStoreTransaction] = []
      for _ in 0..<writeCount {
        let recording = random.int(0...(recordingCount - 1))
        switch random.int(0...9) {
        case 0, 1:
          transactions.append(Self.addSegment(recording: recording, index: segmentCounts[recording], at: time))
          segmentCounts[recording] += 1
        case 2:
          transactions.append(
            Self.addAttachment(recording: recording, index: attachmentCounts[recording], updatedAtMs: Double(time), at: time)
          )
          attachmentCounts[recording] += 1
        case 3 where attachmentCounts[recording] > 0:
          let index = random.int(0...(attachmentCounts[recording] - 1))
          transactions.append(
            Self.touchAttachment(recording: recording, index: index, updatedAtMs: Double(time), at: time)
          )
        case 4:
          transactions.append(Self.heartbeat(recording: recording, seconds: Double(time), at: time))
        case 5:
          // A move along the list's order: the recording's start time changes.
          transactions.append(Self.move(recording: recording, startedAtMs: Double(random.int(0...20_000)), at: time))
        case 6:
          transactions.append(Self.createRecording(recordingCount, startedAtMs: Double(random.int(0...20_000)), at: time))
          recordingCount += 1
          segmentCounts.append(0)
          attachmentCounts.append(0)
        case 7 where attachmentCounts[recording] > 0:
          let index = random.int(0...(attachmentCounts[recording] - 1))
          transactions.append(Self.deleteAttachment(recording: recording, index: index, at: time))
        case 8 where segmentCounts[recording] > 0:
          let index = random.int(0...(segmentCounts[recording] - 1))
          transactions.append(Self.editSegment(recording: recording, index: index, text: "edit \(time)", at: time))
        default:
          transactions.append(Self.orphanAttachment("loose-\(time)", updatedAtMs: Double(time), at: time))
        }
        time += 1
      }
      if transactions.count == 1 {
        try await Self.commit(transactions[0], to: store)
      } else {
        for transaction in transactions {
          let prepared = try await store.prepareCurrent(transaction)
          _ = await store.commitDeferringPublication(prepared)
        }
        await store.publishPendingChanges()
      }
      try await InstantPageRefreshEnergyTests.expectEveryObserverIsCurrent(in: store, "seed \(seed) step \(step)")
    }
  }

  /// A link is found from either end, whichever side of it is smaller: a recording holding more refs than the shown set
  /// is probed by the shown ids, a smaller one is scanned; a target many entities point to likewise.
  @Test
  func aLinkIsFoundFromEitherEndWhicheverSideIsSmaller() {
    let cover = InstantAttribute(
      id: "\(Self.recordings)/cover",
      namespace: Self.recordings,
      name: "cover",
      valueType: .ref,
      cardinality: .one,
      forwardIdentity: "\(Self.recordings)/cover",
      reverseIdentity: "\(Self.attachments)/coverOf",
      linkNamespace: Self.attachments
    )
    let attributes = AttributeStore(attributes: Self.attributes + [cover])
    var triples: [InstantTriple] = []
    func link(_ source: String, _ attributeID: String, _ target: String) {
      triples.append(
        InstantTriple(
          entityID: source,
          attributeID: attributeID,
          value: .ref(target),
          txID: "tx-\(triples.count)",
          txTime: InstantTimestamp(milliseconds: Int64(triples.count + 1))
        )
      )
    }
    let lines = (0..<20).map { "line-\($0)" }
    for line in lines {
      link("hub", "\(Self.recordings)/segments", line)
    }
    for recording in 0..<5 {
      link("recording-\(recording)", "\(Self.recordings)/segments", "shared")
    }
    link("hub", cover.id, "poster")
    let indexes = TripleIndexes(triples: triples, attributes: attributes)
    let strangers = Set((0..<30).map { "stranger-\($0)" })

    let answers: [String: Bool] = [
      "hub to one of its lines (probe)": indexes.hasLink("hub", toAnyOf: ["line-5"], attributes: attributes),
      "hub to a line among 30 ids (scan)": indexes.hasLink(
        "hub",
        toAnyOf: strangers.union(["line-7"]),
        attributes: attributes
      ),
      "hub to 30 strangers": indexes.hasLink("hub", toAnyOf: strangers, attributes: attributes),
      "hub to one stranger": indexes.hasLink("hub", toAnyOf: ["stranger-1"], attributes: attributes),
      "hub to nothing": indexes.hasLink("hub", toAnyOf: [], attributes: attributes),
      "a line to its hub": indexes.hasLink("line-5", toAnyOf: ["hub"], attributes: attributes),
      "shared to one of five holders (probe)": indexes.hasLink(
        "shared",
        toAnyOf: ["recording-2"],
        attributes: attributes
      ),
      "shared to a holder among 30 ids (scan)": indexes.hasLink(
        "shared",
        toAnyOf: strangers.union(["recording-4"]),
        attributes: attributes
      ),
      "shared to a stranger": indexes.hasLink("shared", toAnyOf: ["stranger-2"], attributes: attributes),
      "hub to its cover": indexes.hasLink("hub", toAnyOf: ["poster"], attributes: attributes),
      "the cover to its hub": indexes.hasLink("poster", toAnyOf: ["hub"], attributes: attributes),
      "an unknown entity": indexes.hasLink("nobody", toAnyOf: ["hub", "line-1"], attributes: attributes),
    ]

    expectNoDifference(
      answers,
      [
        "hub to one of its lines (probe)": true,
        "hub to a line among 30 ids (scan)": true,
        "hub to 30 strangers": false,
        "hub to one stranger": false,
        "hub to nothing": false,
        "a line to its hub": true,
        "shared to one of five holders (probe)": true,
        "shared to a holder among 30 ids (scan)": true,
        "shared to a stranger": false,
        "hub to its cover": true,
        "the cover to its hub": true,
        "an unknown entity": false,
      ]
    )
  }

  // MARK: - Helpers

  static let recordings = "skipRecordings"
  static let segments = "skipSegments"
  static let attachments = "skipAttachments"
  static let recordingCount = 9
  static let childCount = 4

  static let attributes: [InstantAttribute] = [
    .primaryKey(namespace: recordings),
    InstantAttribute(
      id: "\(recordings)/startedAtMs",
      namespace: recordings,
      name: "startedAtMs",
      valueType: .number,
      isIndexed: true
    ),
    InstantAttribute(
      id: "\(recordings)/durationSeconds",
      namespace: recordings,
      name: "durationSeconds",
      valueType: .number
    ),
    // Forward has-many links on the recording, as the app's schema keeps them (recordings.segments, .attachments).
    InstantAttribute(
      id: "\(recordings)/segments",
      namespace: recordings,
      name: "segments",
      valueType: .ref,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "\(recordings)/segments",
      reverseIdentity: "\(segments)/recording",
      linkNamespace: segments
    ),
    InstantAttribute(
      id: "\(recordings)/attachments",
      namespace: recordings,
      name: "attachments",
      valueType: .ref,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "\(recordings)/attachments",
      reverseIdentity: "\(attachments)/recording",
      linkNamespace: attachments
    ),
    .primaryKey(namespace: segments),
    InstantAttribute(id: "\(segments)/index", namespace: segments, name: "index", valueType: .number, isIndexed: true),
    InstantAttribute(id: "\(segments)/text", namespace: segments, name: "text", valueType: .string),
    .primaryKey(namespace: attachments),
    InstantAttribute(
      id: "\(attachments)/updatedAtMs",
      namespace: attachments,
      name: "updatedAtMs",
      valueType: .number,
      isIndexed: true
    ),
  ]

  /// Three pages of three recordings each, newest first, each with its newest two lines and newest two attachments.
  static func pages() -> [InstantQueryPlan] {
    (0..<3).map { page in listPlan(id: "skip.page.\(page)", offset: page * 3, limit: 3) }
  }

  /// More shapes for the random test: a page with one include, an unpaged list, a page past the end.
  static func extraPlans() -> [InstantQueryPlan] {
    [
      InstantQueryPlan(
        id: "skip.segments-only",
        namespace: recordings,
        order: InstantQueryOrder("startedAtMs", .ascending),
        limit: 4,
        includes: [
          InstantQueryInclude(
            "segments",
            query: InstantQueryPlan(
              id: "skip.segments-only.segments",
              namespace: segments,
              order: InstantQueryOrder("index", .ascending),
              limit: 1
            )
          )!
        ]
      ),
      listPlan(id: "skip.all", offset: nil, limit: nil),
      listPlan(id: "skip.past-end", offset: 30, limit: 3),
    ]
  }

  static func listPlan(id: String, offset: Int?, limit: Int?) -> InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: recordings,
      order: InstantQueryOrder("startedAtMs", .descending),
      offset: offset,
      limit: limit,
      includes: [
        InstantQueryInclude(
          "segments",
          query: InstantQueryPlan(
            id: "\(id).segments",
            namespace: segments,
            order: InstantQueryOrder("index", .descending),
            limit: 2
          )
        )!,
        InstantQueryInclude(
          "attachments",
          query: InstantQueryPlan(
            id: "\(id).attachments",
            namespace: attachments,
            order: InstantQueryOrder("updatedAtMs", .descending),
            limit: 2
          )
        )!,
      ]
    )
  }

  /// Nine recordings (recording N started at N x 1,000 ms, so recording 8 is the newest), each with four lines and four
  /// attachments.
  static func seededStore() async throws -> InstantStore {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    var time = 1
    for recording in 0..<recordingCount {
      try await commit(createRecording(recording, startedAtMs: Double(recording * 1_000), at: time), to: store)
      time += 1
      for index in 0..<childCount {
        try await commit(addSegment(recording: recording, index: index, at: time), to: store)
        try await commit(
          addAttachment(recording: recording, index: index, updatedAtMs: Double(index * 10), at: time),
          to: store
        )
        time += 1
      }
    }
    return store
  }

  static func observe(_ plans: [InstantQueryPlan], in store: InstantStore) async -> [Task<Void, Never>] {
    await InstantUnresolvedEntityRefreshTests.observe(plans, in: store)
  }

  static func commit(_ transaction: InstantStoreTransaction, to store: InstantStore) async throws {
    try await InstantUnresolvedEntityRefreshTests.commit(transaction, to: store)
  }

  static func recordingID(_ recording: Int) -> String { "recording-\(recording)" }
  static func segmentID(_ recording: Int, _ index: Int) -> String { "segment-\(recording)-\(index)" }
  static func attachmentID(_ recording: Int, _ index: Int) -> String { "attachment-\(recording)-\(index)" }

  static func insert(_ entityID: String, _ attributeID: String, _ value: InstantValue, _ transactionID: String, at step: Int)
    -> InstantTripleOperation
  {
    InstantUnresolvedEntityRefreshTests.insert(entityID, attributeID, value, transactionID, at: step)
  }

  static func createRecording(_ recording: Int, startedAtMs: Double, at step: Int) -> InstantStoreTransaction {
    let id = recordingID(recording)
    let transactionID = "tx-create-\(id)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(id, InstantAttribute.primaryKeyID(namespace: recordings), .string(id), transactionID, at: step),
        insert(id, "\(recordings)/startedAtMs", .number(startedAtMs), transactionID, at: step),
        insert(id, "\(recordings)/durationSeconds", .number(0), transactionID, at: step),
      ]
    )
  }

  static func addSegment(recording: Int, index: Int, at step: Int) -> InstantStoreTransaction {
    let id = segmentID(recording, index)
    let transactionID = "tx-segment-\(id)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(id, InstantAttribute.primaryKeyID(namespace: segments), .string(id), transactionID, at: step),
        insert(id, "\(segments)/index", .number(Double(index)), transactionID, at: step),
        insert(id, "\(segments)/text", .string("line \(index)"), transactionID, at: step),
        insert(recordingID(recording), "\(recordings)/segments", .ref(id), transactionID, at: step),
      ]
    )
  }

  static func editSegment(recording: Int, index: Int, text: String, at step: Int) -> InstantStoreTransaction {
    let transactionID = "tx-edit-\(recording)-\(index)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [insert(segmentID(recording, index), "\(segments)/text", .string(text), transactionID, at: step)]
    )
  }

  static func addAttachment(recording: Int, index: Int, updatedAtMs: Double, at step: Int) -> InstantStoreTransaction {
    let id = attachmentID(recording, index)
    let transactionID = "tx-attachment-\(id)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(id, InstantAttribute.primaryKeyID(namespace: attachments), .string(id), transactionID, at: step),
        insert(id, "\(attachments)/updatedAtMs", .number(updatedAtMs), transactionID, at: step),
        insert(recordingID(recording), "\(recordings)/attachments", .ref(id), transactionID, at: step),
      ]
    )
  }

  static func touchAttachment(recording: Int, index: Int, updatedAtMs: Double, at step: Int) -> InstantStoreTransaction {
    let transactionID = "tx-touch-\(recording)-\(index)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(attachmentID(recording, index), "\(attachments)/updatedAtMs", .number(updatedAtMs), transactionID, at: step)
      ]
    )
  }

  static func deleteAttachment(recording: Int, index: Int, at step: Int) -> InstantStoreTransaction {
    InstantStoreTransaction(
      id: "tx-delete-attachment-\(recording)-\(index)-\(step)",
      operations: [.deleteEntityInNamespace(entityID: attachmentID(recording, index), namespace: attachments)]
    )
  }

  static func orphanAttachment(_ id: String, updatedAtMs: Double, at step: Int) -> InstantStoreTransaction {
    let transactionID = "tx-orphan-\(id)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(id, InstantAttribute.primaryKeyID(namespace: attachments), .string(id), transactionID, at: step),
        insert(id, "\(attachments)/updatedAtMs", .number(updatedAtMs), transactionID, at: step),
      ]
    )
  }

  static func heartbeat(recording: Int, seconds: Double, at step: Int) -> InstantStoreTransaction {
    let transactionID = "tx-heartbeat-\(recording)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(recordingID(recording), "\(recordings)/durationSeconds", .number(seconds), transactionID, at: step)
      ]
    )
  }

  static func move(recording: Int, startedAtMs: Double, at step: Int) -> InstantStoreTransaction {
    let transactionID = "tx-move-\(recording)-\(step)"
    return InstantStoreTransaction(
      id: transactionID,
      operations: [
        insert(recordingID(recording), "\(recordings)/startedAtMs", .number(startedAtMs), transactionID, at: step)
      ]
    )
  }
}
