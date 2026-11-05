import Foundation
import Testing

@testable import InstantSwiftDataCore

// History:
// - 2026-11-04: #1513: a page with no limit, ordered by an indexed field, ordered and materialized every entity of its
//   namespace and only then applied its filters, so a recording's attachments (filtered by the recording, newest
//   first) and an infinite query's frozen pages of a recording's lines each read every attachment or line the device
//   holds. These tests hold the candidates to the filter's index hits, and the page to what the whole namespace gives.
//   Asserted with `#expect`, which a release run judges.

/// Pages with no limit, ordered by an indexed field and filtered by an indexed one (#1513): twenty recordings' thirty
/// attachments each, and a recording's attachments, newest first.
@Suite(.serialized)
struct InstantFilteredOrderedPageTests {
  /// A recording's attachments, newest first, are ordered from the recording's 30, not the namespace's 600.
  @Test
  func aRecordingsAttachmentsAreOrderedFromItsOwnRows() async throws {
    let store = try await FilteredOrderedFixture.seededStore()

    let result = await store.materializePageWithMetrics(FilteredOrderedFixture.recordingPlan(7))

    #expect(result.page.values.map(\.id) == FilteredOrderedFixture.expectedIDs(recording: 7))
    #expect(result.metrics.examinedCandidateCount == FilteredOrderedFixture.attachmentsPerRecording, "\(result.metrics)")
    #expect(result.metrics.materializedSnapshotCount == FilteredOrderedFixture.attachmentsPerRecording, "\(result.metrics)")
  }

  /// A frozen page between two cursors reads the recording's rows too, and keeps the rows between the cursors.
  @Test
  func aFrozenPageBetweenCursorsIsOrderedFromItsRecordingsRows() async throws {
    let store = try await FilteredOrderedFixture.seededStore()
    var plan = FilteredOrderedFixture.recordingPlan(3)
    let expected = FilteredOrderedFixture.expectedIDs(recording: 3)
    plan.after = FilteredOrderedFixture.cursor(recording: 3, rank: 4, inclusive: false)
    plan.before = FilteredOrderedFixture.cursor(recording: 3, rank: 19, inclusive: true)

    let result = await store.materializePageWithMetrics(plan)

    #expect(result.page.values.map(\.id) == Array(expected[5...19]))
    #expect(result.metrics.examinedCandidateCount == FilteredOrderedFixture.attachmentsPerRecording, "\(result.metrics)")
  }

  /// A second filter no index covers still applies to the indexed filter's rows.
  @Test
  func aFilterNoIndexCoversStillAppliesToTheIndexedRows() async throws {
    let store = try await FilteredOrderedFixture.seededStore()
    var plan = FilteredOrderedFixture.recordingPlan(11)
    plan.filters.append(.equals(field: "kind", value: .string("image")))

    let result = await store.materializePageWithMetrics(plan)

    let images = FilteredOrderedFixture.expectedIDs(recording: 11).filter { id in
      FilteredOrderedFixture.kind(ofAttachment: id) == "image"
    }
    #expect(result.page.values.map(\.id) == images)
    #expect(result.metrics.examinedCandidateCount == FilteredOrderedFixture.attachmentsPerRecording, "\(result.metrics)")
  }
}

/// Twenty recordings with thirty attachments each, every attachment with an indexed recording and update time.
enum FilteredOrderedFixture {
  static let attachments = "filteredAttachments"
  static let recordingCount = 20
  static let attachmentsPerRecording = 30

  static let attributes: [InstantAttribute] = {
    func scalar(_ name: String, _ type: InstantValueType, indexed: Bool = false) -> InstantAttribute {
      InstantAttribute(id: "\(attachments)/\(name)", namespace: attachments, name: name, valueType: type, isIndexed: indexed)
    }
    return [
      .primaryKey(namespace: attachments),
      scalar("recordingID", .string, indexed: true),
      scalar("updatedAtMs", .number, indexed: true),
      scalar("kind", .string),
    ]
  }()

  static func recordingID(_ recording: Int) -> String { "filtered-recording-\(recording)" }
  static func attachmentID(_ recording: Int, _ index: Int) -> String { "filtered-attachment-\(recording)-\(index)" }

  /// Interleaved update times, with ties between recordings and within one, so the id breaks them.
  static func updatedAtMs(_ recording: Int, _ index: Int) -> Double { Double((index * 7 + recording * 3) % 50) }

  static func kind(ofAttachment id: String) -> String {
    Int(id.split(separator: "-").last!)!.isMultiple(of: 3) ? "image" : "audio"
  }

  /// The recording's attachments, newest first: the attachments query of a recording's screen.
  static func recordingPlan(_ recording: Int) -> InstantQueryPlan {
    InstantQueryPlan(
      id: "filtered.recording.\(recording)",
      namespace: attachments,
      filters: [.equals(field: "recordingID", value: .string(recordingID(recording)))],
      order: InstantQueryOrder("updatedAtMs", .descending)
    )
  }

  /// The recording's attachment ids in the page's order: update time, newest first, then id, descending.
  static func expectedIDs(recording: Int) -> [String] {
    (0..<attachmentsPerRecording)
      .map { (id: attachmentID(recording, $0), time: updatedAtMs(recording, $0)) }
      .sorted { lhs, rhs in lhs.time != rhs.time ? lhs.time > rhs.time : lhs.id > rhs.id }
      .map(\.id)
  }

  /// A cursor at the recording's attachment `rank` places in its page's order.
  static func cursor(recording: Int, rank: Int, inclusive: Bool) -> InstantQueryCursor {
    let id = expectedIDs(recording: recording)[rank]
    let index = Int(id.split(separator: "-").last!)!
    return InstantQueryCursor(entityID: id, sortValue: .number(updatedAtMs(recording, index)), inclusive: inclusive)
  }

  static func seededStore() async throws -> InstantStore {
    let store = InstantStore(snapshot: InstantStoreSnapshot(attributes: attributes))
    for recording in 0..<recordingCount {
      var operations: [InstantTripleOperation] = []
      for index in 0..<attachmentsPerRecording {
        let id = attachmentID(recording, index)
        operations += SpliceFixture.entity(
          id,
          attachments,
          [
            "recordingID": .string(recordingID(recording)),
            "updatedAtMs": .number(updatedAtMs(recording, index)),
            "kind": .string(kind(ofAttachment: id)),
          ]
        )
      }
      let transactionID = "filtered-seed-\(recording)"
      try await SpliceFixture.commit(
        InstantStoreTransaction(
          id: transactionID,
          operations: operations.map { operation in
            guard case var .insert(triple) = operation else { return operation }
            triple.txID = transactionID
            triple.txTime = InstantPageRefreshEnergyTests.time(recording)
            return .insert(triple)
          }
        ),
        to: store
      )
    }
    return store
  }
}
