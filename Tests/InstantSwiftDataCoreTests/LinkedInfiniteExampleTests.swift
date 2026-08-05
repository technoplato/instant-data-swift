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

  /// Scribe blank-detail recipe shape: recording root + linked transcription
  /// child. After an empty live-query replacement, the join must still project
  /// the pending optimistic transcription word count (not blank detail).
  @Test
  func emptyLiveQueryReplacementPreservesOptimisticTranscriptionJoin() async throws {
    let cacheURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("LinkedInfiniteBlankDetail-\(UUID().uuidString)")
      .appendingPathComponent("state.sqlite")
    try FileManager.default.createDirectory(
      at: cacheURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    let createdAt = InstantTimestamp(milliseconds: 1_700_000_900_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "linked-infinite-blank-detail",
        persistenceURL: cacheURL,
        initialAttributes: LinkedInfiniteExample.attributes,
        now: { InstantTimestamp(milliseconds: createdAt.milliseconds + 10) }
      )
    )

    let recordingID = "recording-blank-detail"
    let transcriptionID = "transcription-blank-detail"
    let seedTx = "tx-linked-seed"
    try await runtime.transact(
      InstantStoreTransaction(
        id: seedTx,
        operations:
          LinkedInfiniteExample.createRecordingOperations(
            id: recordingID,
            title: "Blank detail repro",
            updatedAt: createdAt,
            transactionID: seedTx
          ) + LinkedInfiniteExample.createTranscriptionOperations(
            id: transcriptionID,
            recordingID: recordingID,
            wordCount: 3,
            updatedAt: createdAt,
            transactionID: seedTx
          )
      ),
      createdAt: createdAt
    )

    // Authoritative live ownership of the same graph (server previously had it).
    let recordingsQuery: InstantLiveJSONValue = .object([
      LinkedInfiniteExample.recordingNamespace: .object([:]),
    ])
    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "event-linked-initial",
        processedTransactionID: "server-linked-initial",
        attrs: LinkedInfiniteExample.serverAttrs,
        computations: [
          LinkedInfiniteExample.liveJoinComputation(
            query: recordingsQuery,
            recordingID: recordingID,
            title: "Blank detail repro",
            transcriptionID: transcriptionID,
            wordCount: 3,
            updatedAt: createdAt,
            processedTransactionID: "server-linked-initial"
          )
        ]
      ),
      receivedAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    )

    // Optimistic word-count update (still pending delivery).
    let updateAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 2)
    let updateTx = "tx-linked-optimistic-words"
    try await runtime.transact(
      InstantStoreTransaction(
        id: updateTx,
        operations: [
          .requireEntityExists(
            entityID: transcriptionID,
            namespace: LinkedInfiniteExample.transcriptionNamespace
          ),
          .insert(
            InstantTriple(
              entityID: transcriptionID,
              attributeID: "\(LinkedInfiniteExample.transcriptionNamespace)/wordCount",
              value: .number(44),
              txID: updateTx,
              txTime: updateAt
            )
          ),
          .insert(
            InstantTriple(
              entityID: transcriptionID,
              attributeID: InstantAttribute.primaryKeyID(
                namespace: LinkedInfiniteExample.transcriptionNamespace
              ),
              value: .string(transcriptionID),
              txID: updateTx,
              txTime: updateAt
            )
          ),
        ]
      ),
      createdAt: updateAt
    )

    let beforeEmpty = try LinkedInfiniteExample.decodeRecordings(
      try await runtime.query(LinkedInfiniteExample.recordingsQuery(pageSize: 10))
    )
    expectNoDifference(beforeEmpty.map(\.transcriptionWordCount), [44])

    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "event-linked-empty",
        processedTransactionID: "server-linked-empty",
        attrs: [],
        computations: [
          LinkedInfiniteExample.emptyLiveJoinComputation(query: recordingsQuery)
        ]
      ),
      receivedAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 3)
    )

    let pending = await runtime.pendingMutations().map(\.id)
    #expect(pending.contains(updateTx))
    let afterEmpty = try LinkedInfiniteExample.decodeRecordings(
      try await runtime.query(LinkedInfiniteExample.recordingsQuery(pageSize: 10))
    )
    expectNoDifference(afterEmpty.map(\.id), [recordingID])
    expectNoDifference(
      afterEmpty.map(\.transcriptionWordCount),
      [44],
      "Empty live replacement must not blank the transcription join while optimistic delivery is pending."
    )
  }
}
