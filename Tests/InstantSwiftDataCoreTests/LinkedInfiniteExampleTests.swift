import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite
struct LinkedInfiniteExampleTests {
  @Test
  func seedAndInfiniteIncludePagesRootWithLinkedWordCounts() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("LinkedInfiniteExample-\(UUID().uuidString)")
      .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(
      at: cacheURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "linked-infinite-example-test",
        persistenceURL: cacheURL,
        initialAttributes: LinkedInfiniteExample.attributes,
        makeID: { UUID().uuidString.lowercased() }
      )
    )

    var recordingIDs: [String] = []
    var transcriptionIDs: [String] = []
    for index in LinkedInfiniteExample.seedTitles.indices {
      recordingIDs.append(
        try await runtime.localID(named: LinkedInfiniteExample.seedLocalIDName(index: index))
      )
      transcriptionIDs.append(
        try await runtime.localID(
          named: LinkedInfiniteExample.transcriptionLocalIDName(index: index)
        )
      )
    }

    let transactionID = runtime.configuration.makeID()
    let now = InstantTimestamp(milliseconds: 1_700_000_700_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: transactionID,
        operations: LinkedInfiniteExample.seedOperations(
          recordingIDs: recordingIDs,
          transcriptionIDs: transcriptionIDs,
          baseTime: now,
          transactionID: transactionID
        )
      ),
      createdAt: now
    )

    let plan = LinkedInfiniteExample.recordingsQuery(pageSize: 3)
    let subscription = await runtime.subscribeInfiniteQuery(plan)
    defer { subscription.unsubscribe() }
    var iterator = subscription.snapshots.makeAsyncIterator()

    let first = try #require(await iterator.next())
    #expect(first.error == nil)
    expectNoDifference(first.values.count, 3)
    expectNoDifference(first.canLoadNextPage, true)

    let firstRows = try LinkedInfiniteExample.decodeRecordings(first.values)
    #expect(firstRows.allSatisfy { $0.transcriptionWordCount > 0 })
    // Newest first by updatedAt: last seed title has highest timestamp.
    expectNoDifference(firstRows.map(\.title).first, LinkedInfiniteExample.seedTitles.last)
    expectNoDifference(
      firstRows.first?.transcriptionWordCount,
      LinkedInfiniteExample.seedTitles.count * 40
    )

    subscription.loadNextPage()
    let second = try #require(await iterator.next())
    #expect(second.error == nil)
    expectNoDifference(second.values.count, 6)
    expectNoDifference(second.canLoadNextPage, true)

    let secondRows = try LinkedInfiniteExample.decodeRecordings(second.values)
    #expect(secondRows.allSatisfy { $0.transcriptionWordCount > 0 })

    subscription.loadNextPage()
    let third = try #require(await iterator.next())
    #expect(third.error == nil)
    // After two expansions we still have more pages for the larger seed set.
    expectNoDifference(third.values.count, 9)
    expectNoDifference(third.canLoadNextPage, true)

    let thirdRows = try LinkedInfiniteExample.decodeRecordings(third.values)
    #expect(thirdRows.allSatisfy { $0.transcriptionWordCount > 0 })
    #expect(LinkedInfiniteExample.seedTitles.count >= 15)
  }
}
