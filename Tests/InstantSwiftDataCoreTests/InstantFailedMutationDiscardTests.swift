import CustomDump
import Foundation
import IssueReporting
import SQLite3
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantFailedMutationDiscardTests {
  private let upstreamProvenance = [
    "upstream/instant/client/packages/core/src/Reactor.js:_handleMutationError",
    "upstream/instant/client/packages/core/src/Reactor.js:_flushPendingMessages",
  ]
  private let upstreamOptimisticRefreshProvenance = [
    "upstream/instant/client/packages/core/src/Reactor.js:725-805",
    "upstream/instant/client/packages/core/src/Reactor.js:1374-1432",
    "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts:203-358",
  ]

  @Test
  func discardsOnlyFailedMutationWithoutClaimingTheConnectionRecovered() async throws {
    let cacheURL = temporaryDiscardCacheURL("status")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    try await enqueueDiscardMutation(id: "tx-first", runtime: runtime, offset: 0)
    try await enqueueDiscardMutation(id: "tx-second", runtime: runtime, offset: 1)
    _ = try await runtime.failMutation(id: "tx-first", message: "permission denied first")
    _ = try await runtime.failMutation(id: "tx-second", message: "permission denied second")

    let first = try await runtime.discardFailedMutation(id: "tx-first")
    expectNoDifference(first.id, "tx-first")
    expectNoDifference(first.status, .failed)
    expectNoDifference(first.failureMessage, "permission denied first")
    let afterFirstDiscard = await runtime.outboxMutations()
    let afterFirstStatus = try await runtime.connectionStatus()
    expectNoDifference(afterFirstDiscard.map(\.id), ["tx-second"])
    expectNoDifference(afterFirstStatus.state, .errored)

    _ = try await runtime.discardFailedMutation(id: "tx-second")
    let afterSecondDiscard = await runtime.outboxMutations()
    let afterSecondStatus = try await runtime.connectionStatus()
    expectNoDifference(afterSecondDiscard, [])
    expectNoDifference(afterSecondStatus.state, .errored)
    expectNoDifference(afterSecondStatus.lastErrorMessage, "permission denied second")

    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let relaunchedOutbox = await relaunched.outboxMutations()
    expectNoDifference(relaunchedOutbox, [])
    expectNoDifference(
      upstreamProvenance,
      [
        "upstream/instant/client/packages/core/src/Reactor.js:_handleMutationError",
        "upstream/instant/client/packages/core/src/Reactor.js:_flushPendingMessages",
      ]
    )
  }

  @Test
  func discardRollsBackOptimisticCreatePublishesAndPersists() async throws {
    let cacheURL = temporaryDiscardCacheURL("rollback-create")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let recorder = DiscardTodoEmissionRecorder()
    let stream = await runtime.observe(TodoExample.query)
    let observation = Task {
      for await emission in stream {
        let texts = (try? TodoExample.decode(emission.values).map(\.text)) ?? []
        await recorder.append(texts)
      }
    }
    defer { observation.cancel() }
    try await recorder.waitForCount(1)

    try await enqueueDiscardMutation(id: "tx-rejected-create", runtime: runtime, offset: 0)
    try await recorder.waitForCount(2)
    _ = try await runtime.failMutation(
      id: "tx-rejected-create",
      message: "permission denied create"
    )
    _ = try await runtime.discardFailedMutation(id: "tx-rejected-create")
    try await recorder.waitForCount(3)

    let emissions = await recorder.values
    expectNoDifference(emissions, [[], ["tx-rejected-create"], []])
    let immediateTodos = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(immediateTodos, [])

    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let relaunchedTodos = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(relaunchedTodos, [])
    let relaunchedOutbox = await relaunched.outboxMutations()
    expectNoDifference(relaunchedOutbox, [])
  }

  @Test
  func discardPreservesNewerOptimisticSuccessorWrite() async throws {
    let cacheURL = temporaryDiscardCacheURL("successor")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-base",
        operations: TodoExample.upsertOperations(
          id: "todo-successor",
          text: "server",
          createdAt: baseTime,
          transactionID: "server-base"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-update",
        operations: TodoExample.updateTextOperations(
          id: "todo-successor",
          text: "rejected",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-rejected-update"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-successor-update",
        operations: TodoExample.updateTextOperations(
          id: "todo-successor",
          text: "successor",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2),
          transactionID: "tx-successor-update"
        )
      )
    )
    _ = try await runtime.failMutation(
      id: "tx-rejected-update",
      message: "permission denied rejected update"
    )

    _ = try await runtime.discardFailedMutation(id: "tx-rejected-update")

    let current = try await TodoExample.decode(runtime.query(TodoExample.query))
    let currentOutbox = await runtime.outboxMutations()
    expectNoDifference(current.map(\.text), ["successor"])
    expectNoDifference(currentOutbox.map(\.id), ["tx-successor-update"])
    expectNoDifference(currentOutbox.map(\.status), [.pending])

    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let restored = try await TodoExample.decode(relaunched.query(TodoExample.query))
    let restoredOutbox = await relaunched.outboxMutations()
    expectNoDifference(restored.map(\.text), ["successor"])
    expectNoDifference(restoredOutbox.map(\.id), ["tx-successor-update"])
    expectNoDifference(restoredOutbox.map(\.status), [.pending])
  }

  @Test
  func discardRestoresValueOverwrittenByRejectedOptimisticUpdate() async throws {
    let cacheURL = temporaryDiscardCacheURL("restore-update")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-update-base",
        operations: TodoExample.upsertOperations(
          id: "todo-restore-update",
          text: "server value",
          createdAt: baseTime,
          transactionID: "server-update-base"
        )
      )
    )
    let recorder = DiscardTodoEmissionRecorder()
    let stream = await runtime.observe(TodoExample.query)
    let observation = Task {
      for await emission in stream {
        let texts = (try? TodoExample.decode(emission.values).map(\.text)) ?? []
        await recorder.append(texts)
      }
    }
    defer { observation.cancel() }
    try await recorder.waitForCount(1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-value",
        operations: TodoExample.updateTextOperations(
          id: "todo-restore-update",
          text: "rejected value",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-rejected-value"
        )
      )
    )
    try await recorder.waitForCount(2)
    _ = try await runtime.failMutation(
      id: "tx-rejected-value",
      message: "permission denied update"
    )

    _ = try await runtime.discardFailedMutation(id: "tx-rejected-value")
    try await recorder.waitForCount(3)

    let emissions = await recorder.values
    expectNoDifference(emissions, [["server value"], ["rejected value"], ["server value"]])
    let current = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(current.map(\.text), ["server value"])
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let restored = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(restored.map(\.text), ["server value"])
  }

  @Test
  func discardRestoresLatestServerValueReceivedUnderOptimisticOverlay() async throws {
    let cacheURL = temporaryDiscardCacheURL("restore-latest-server-value")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-original",
        operations: TodoExample.upsertOperations(
          id: "todo-latest-server-value",
          text: "server original",
          createdAt: baseTime,
          transactionID: "server-original"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-over-new-server-value",
        operations: TodoExample.updateTextOperations(
          id: "todo-latest-server-value",
          text: "optimistic local",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-rejected-over-new-server-value"
        )
      )
    )

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-newer",
        operations: TodoExample.updateTextOperations(
          id: "todo-latest-server-value",
          text: "server newer",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2),
          transactionID: "server-newer"
        )
      )
    )
    let stillOptimistic = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(stillOptimistic.map(\.text), ["optimistic local"])

    _ = try await runtime.failMutation(
      id: "tx-rejected-over-new-server-value",
      message: "permission denied over newer server value"
    )
    _ = try await runtime.discardFailedMutation(id: "tx-rejected-over-new-server-value")

    let restored = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(restored.map(\.text), ["server newer"])
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let relaunchedRestored = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(relaunchedRestored.map(\.text), ["server newer"])
  }

  @Test
  func discardAfterServerRefreshDoesNotReapplyObsoleteRollbackImage() async throws {
    let cacheURL = temporaryDiscardCacheURL("discard-after-server-refresh")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-before-rejection",
        operations: TodoExample.upsertOperations(
          id: "todo-discard-after-refresh",
          text: "server before rejection",
          createdAt: baseTime,
          transactionID: "server-before-rejection"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-before-refresh",
        operations: TodoExample.updateTextOperations(
          id: "todo-discard-after-refresh",
          text: "rejected optimistic value",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-rejected-before-refresh"
        )
      )
    )
    _ = try await runtime.failMutation(
      id: "tx-rejected-before-refresh",
      message: "permission denied before server refresh"
    )

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-after-rejection",
        operations: TodoExample.updateTextOperations(
          id: "todo-discard-after-refresh",
          text: "server after rejection",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2),
          transactionID: "server-after-rejection"
        )
      )
    )
    let reconciled = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(reconciled.map(\.text), ["server after rejection"])

    _ = try await runtime.discardFailedMutation(id: "tx-rejected-before-refresh")

    let afterDiscard = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(afterDiscard.map(\.text), ["server after rejection"])
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let relaunchedAfterDiscard = try await TodoExample.decode(
      relaunched.query(TodoExample.query)
    )
    expectNoDifference(relaunchedAfterDiscard.map(\.text), ["server after rejection"])
  }

  @Test
  func discardAfterServerDeleteDoesNotResurrectRejectedOverlayBase() async throws {
    let cacheURL = temporaryDiscardCacheURL("discard-after-server-delete")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-before-delete",
        operations: TodoExample.upsertOperations(
          id: "todo-discard-after-server-delete",
          text: "server value",
          createdAt: baseTime,
          transactionID: "server-before-delete"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-before-server-delete",
        operations: TodoExample.updateTextOperations(
          id: "todo-discard-after-server-delete",
          text: "rejected optimistic value",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-rejected-before-server-delete"
        )
      )
    )
    _ = try await runtime.failMutation(
      id: "tx-rejected-before-server-delete",
      message: "permission denied before server delete"
    )

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-delete-after-rejection",
        operations: [.deleteEntity("todo-discard-after-server-delete")]
      )
    )
    let serverDeleted = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(serverDeleted, [])

    _ = try await runtime.discardFailedMutation(id: "tx-rejected-before-server-delete")

    let afterDiscard = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(afterDiscard, [])
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let relaunchedAfterDiscard = try await TodoExample.decode(
      relaunched.query(TodoExample.query)
    )
    expectNoDifference(relaunchedAfterDiscard, [])
  }

  @Test
  func discardRestoresEntityRemovedByRejectedOptimisticDelete() async throws {
    let cacheURL = temporaryDiscardCacheURL("restore-delete")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-delete-base",
        operations: TodoExample.upsertOperations(
          id: "todo-restore-delete",
          text: "survives rejection",
          createdAt: baseTime,
          transactionID: "server-delete-base"
        )
      )
    )
    let recorder = DiscardTodoEmissionRecorder()
    let stream = await runtime.observe(TodoExample.query)
    let observation = Task {
      for await emission in stream {
        let texts = (try? TodoExample.decode(emission.values).map(\.text)) ?? []
        await recorder.append(texts)
      }
    }
    defer { observation.cancel() }
    try await recorder.waitForCount(1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-delete",
        operations: TodoExample.deleteOperations(id: "todo-restore-delete")
      )
    )
    try await recorder.waitForCount(2)
    _ = try await runtime.failMutation(
      id: "tx-rejected-delete",
      message: "permission denied delete"
    )

    _ = try await runtime.discardFailedMutation(id: "tx-rejected-delete")
    try await recorder.waitForCount(3)

    let emissions = await recorder.values
    expectNoDifference(emissions, [["survives rejection"], [], ["survives rejection"]])
    let current = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(current.map(\.text), ["survives rejection"])
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let restored = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(restored.map(\.text), ["survives rejection"])
  }

  @Test
  func discardRestoresRelationshipGraphRemovedByRejectedCascadeDelete() async throws {
    let cacheURL = temporaryDiscardCacheURL("restore-cascade-delete")
    let runtime = try await discardCascadeRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-cascade-base",
        operations: [
          .insert(
            .init(
              entityID: "user-cascade",
              attributeID: "users/name",
              value: .string("Blob"),
              txID: "server-cascade-base",
              txTime: baseTime
            )
          ),
          .insert(
            .init(
              entityID: "post-cascade",
              attributeID: "posts/title",
              value: .string("Restored post"),
              txID: "server-cascade-base",
              txTime: baseTime
            )
          ),
          .insert(
            .init(
              entityID: "post-cascade",
              attributeID: "posts/author",
              value: .ref("user-cascade"),
              txID: "server-cascade-base",
              txTime: baseTime
            )
          ),
        ]
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-cascade-delete",
        operations: [.deleteEntity("user-cascade")]
      )
    )
    let optimisticallyDeletedUsers = try await runtime.query(
      .init(id: "cascade.users", namespace: "users")
    )
    let optimisticallyDeletedPosts = try await runtime.query(
      .init(id: "cascade.posts", namespace: "posts")
    )
    expectNoDifference(optimisticallyDeletedUsers, [])
    expectNoDifference(optimisticallyDeletedPosts, [])

    _ = try await runtime.failMutation(
      id: "tx-rejected-cascade-delete",
      message: "permission denied cascade delete"
    )
    _ = try await runtime.discardFailedMutation(id: "tx-rejected-cascade-delete")

    let users = try await runtime.query(.init(id: "cascade.users", namespace: "users"))
    let posts = try await runtime.query(.init(id: "cascade.posts", namespace: "posts"))
    expectNoDifference(users.map(\.id), ["user-cascade"])
    expectNoDifference(posts.map(\.id), ["post-cascade"])
    expectNoDifference(posts.map { $0.values["author"]?.first }, [.ref("user-cascade")])

    let relaunched = try await discardCascadeRuntime(cacheURL: cacheURL)
    let relaunchedUsers = try await relaunched.query(
      .init(id: "cascade.users", namespace: "users")
    )
    let relaunchedPosts = try await relaunched.query(
      .init(id: "cascade.posts", namespace: "posts")
    )
    expectNoDifference(relaunchedUsers.map(\.id), ["user-cascade"])
    expectNoDifference(relaunchedPosts.map(\.id), ["post-cascade"])
  }

  @Test
  func discardReplaysNewerOptimisticDeleteAfterRestoringRejectedUpdate() async throws {
    let cacheURL = temporaryDiscardCacheURL("successor-delete")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-successor-delete-base",
        operations: TodoExample.upsertOperations(
          id: "todo-successor-delete",
          text: "server",
          createdAt: baseTime,
          transactionID: "server-successor-delete-base"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-before-delete",
        operations: TodoExample.updateTextOperations(
          id: "todo-successor-delete",
          text: "rejected",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-rejected-before-delete"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-successor-delete",
        operations: TodoExample.deleteOperations(id: "todo-successor-delete")
      )
    )
    _ = try await runtime.failMutation(
      id: "tx-rejected-before-delete",
      message: "permission denied update before delete"
    )

    _ = try await runtime.discardFailedMutation(id: "tx-rejected-before-delete")

    let current = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(current, [])
    let currentOutbox = await runtime.outboxMutations()
    expectNoDifference(currentOutbox.map(\.id), ["tx-successor-delete"])
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let restored = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(restored, [])
  }

  @Test
  func discardDoesNotEraseLaterIndependentConnectionFailure() async throws {
    let transport = InstantLiveTransportClient.connectionAttempts { _ in
      throw InstantError(
        code: .networkFailed,
        operation: "open independent test connection",
        message: "independent socket failure",
        recovery: "Keep the later connection failure visible."
      )
    }
    let runtime = try await discardRuntime(
      cacheURL: temporaryDiscardCacheURL("independent-error"),
      liveTransport: transport
    )
    try await enqueueDiscardMutation(id: "tx-old-failure", runtime: runtime, offset: 0)
    _ = try await runtime.failMutation(id: "tx-old-failure", message: "old permission denial")
    await #expect(throws: InstantError.self) {
      _ = try await runtime.connect()
    }
    let beforeDiscard = try await runtime.connectionStatus()
    #expect(beforeDiscard.lastErrorMessage?.contains("independent socket failure") == true)

    _ = try await runtime.discardFailedMutation(id: "tx-old-failure")

    let afterDiscard = try await runtime.connectionStatus()
    expectNoDifference(afterDiscard.state, .errored)
    expectNoDifference(afterDiscard.lastErrorMessage, beforeDiscard.lastErrorMessage)
  }

  @Test
  func refusesToDiscardPendingOrMissingMutation() async throws {
    let runtime = try await discardRuntime(cacheURL: temporaryDiscardCacheURL("refused"))
    try await enqueueDiscardMutation(id: "tx-pending", runtime: runtime, offset: 0)

    await expectDiscardFailure(id: "tx-pending", runtime: runtime, message: "is pending")
    await expectDiscardFailure(id: "tx-missing", runtime: runtime, message: "was not found")
    let pending = await runtime.pendingMutations()
    expectNoDifference(pending.map(\.id), ["tx-pending"])
  }

  @Test
  func discardedPermissionFailureCannotBeRetriedAfterLiveReconnect() async throws {
    let cacheURL = temporaryDiscardCacheURL("reconnect")
    let offline = try await discardRuntime(cacheURL: cacheURL)
    try await enqueueDiscardMutation(id: "tx-discarded", runtime: offline, offset: 0)
    _ = try await offline.failMutation(id: "tx-discarded", message: "permission denied")
    _ = try await offline.discardFailedMutation(id: "tx-discarded")

    let session = DiscardReconnectLiveSession()
    let live = try await discardRuntime(cacheURL: cacheURL, liveTransport: session.transport)
    _ = try await live.connect()
    await session.waitForSentMessageCount(1)
    try await Task.sleep(for: .milliseconds(20))

    let sent = await session.sentMessages()
    let outbox = await live.outboxMutations()
    expectNoDifference(sent.map(\.op), ["init"])
    expectNoDifference(outbox, [])
    _ = try await live.closeConnection()
  }

  @Test
  func discardDoesNotPublishFakeServerAcceptance() async throws {
    let runtime = try await discardRuntime(cacheURL: temporaryDiscardCacheURL("lifecycle"))
    let lifecycle = try await runtime.observeMutationLifecycle(id: "tx-lifecycle")
    let recorder = DiscardLifecycleRecorder()
    let observation = Task {
      for await event in lifecycle {
        await recorder.append(event)
      }
    }
    defer { observation.cancel() }
    try await recorder.waitForCount(1)

    try await enqueueDiscardMutation(id: "tx-lifecycle", runtime: runtime, offset: 0)
    _ = try await runtime.failMutation(id: "tx-lifecycle", message: "permission denied")
    try await recorder.waitForCount(2)
    _ = try await runtime.discardFailedMutation(id: "tx-lifecycle")
    try await Task.sleep(for: .milliseconds(20))

    let labels = await recorder.labels
    expectNoDifference(labels, ["waiting", "failed:tx-lifecycle"])
  }

  @Test
  func retryAfterRefreshReappliesOptimismPublishesResendsAndAccepts() async throws {
    let cacheURL = temporaryDiscardCacheURL("retry-after-refresh")
    let original = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let serverRefreshTime = InstantTimestamp(milliseconds: baseTime.milliseconds + 20)
    _ = try await original.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-retry-base",
        operations: TodoExample.upsertOperations(
          id: "todo-retry-after-refresh",
          text: "server base",
          createdAt: baseTime,
          transactionID: "server-retry-base"
        )
      )
    )
    try await original.transact(
      InstantStoreTransaction(
        id: "tx-retry-after-refresh",
        operations: TodoExample.updateTextOperations(
          id: "todo-retry-after-refresh",
          text: "retried optimistic value",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-retry-after-refresh"
        )
      )
    )
    _ = try await original.failMutation(
      id: "tx-retry-after-refresh",
      message: "permission denied before explicit retry"
    )
    _ = try await original.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-retry-refresh",
        operations: TodoExample.updateTextOperations(
          id: "todo-retry-after-refresh",
          text: "server refreshed value",
          updatedAt: serverRefreshTime,
          transactionID: "server-retry-refresh"
        )
      )
    )

    let reconciled = try await TodoExample.decode(original.query(TodoExample.query))
    expectNoDifference(reconciled.map(\.text), ["server refreshed value"])
    let removedOverlay = try #require(await original.outboxMutations().first)
    expectNoDifference(removedOverlay.status, .failed)
    expectNoDifference(removedOverlay.optimisticOverlayState, .removed)
    expectNoDifference(removedOverlay.rollbackTransaction, nil)

    let session = DiscardReconnectLiveSession()
    let relaunched = try await discardRuntime(cacheURL: cacheURL, liveTransport: session.transport)
    let recorder = DiscardTodoEmissionRecorder()
    let stream = await relaunched.observe(TodoExample.query)
    let observation = Task {
      for await emission in stream {
        let texts = (try? TodoExample.decode(emission.values).map(\.text)) ?? []
        await recorder.append(texts)
      }
    }
    defer { observation.cancel() }
    try await recorder.waitForCount(1)
    let initialEmissions = await recorder.values
    expectNoDifference(initialEmissions, [["server refreshed value"]])

    _ = try await relaunched.connect()
    await session.waitForSentMessageCount(2)
    let retried = try await relaunched.retryMutation(id: "tx-retry-after-refresh")
    try await recorder.waitForCount(2)
    await session.waitForSentMessageCount(3)

    expectNoDifference(retried.status, .pending)
    expectNoDifference(retried.optimisticOverlayState, .applied)
    let retriedEmissions = await recorder.values
    expectNoDifference(
      retriedEmissions,
      [["server refreshed value"], ["retried optimistic value"]]
    )
    let sentOperations = await session.sentMessages().map(\.op)
    expectNoDifference(
      sentOperations,
      ["init", "add-query", "transact"]
    )
    let sentTransact = try #require(
      await session.sentMessages().first { $0.op == "transact" }
    )
    let sentSteps = try #require(sentTransact.fields["tx-steps"]?.arrayValue)
    #expect(
      sentSteps.contains { step in
        guard let parts = step.arrayValue, parts.count > 3 else { return false }
        return parts[2].stringValue == "todos/text"
          && parts[3].stringValue == "retried optimistic value"
      },
      "Reapplying a failed mutation must preserve the rebased scalar on the wire."
    )
    let rollback = try #require(retried.rollbackTransaction)
    let retriedTextTimestamp = try #require(
      rollback.operations.compactMap { operation -> InstantTimestamp? in
        guard case .retract(let triple) = operation,
          triple.attributeID == "todos/text"
        else { return nil }
        return triple.txTime
      }.first
    )
    #expect(retriedTextTimestamp > serverRefreshTime)

    await session.acceptMutation(
      id: "tx-retry-after-refresh",
      serverTransactionID: "200"
    )
    let accepted = try await waitForDiscardMutation(
      id: "tx-retry-after-refresh",
      status: .confirmed,
      runtime: relaunched
    )
    expectNoDifference(accepted.serverTransactionID, "200")
    expectNoDifference(accepted.optimisticOverlayState, .applied)
    expectNoDifference(
      upstreamOptimisticRefreshProvenance,
      [
        "upstream/instant/client/packages/core/src/Reactor.js:725-805",
        "upstream/instant/client/packages/core/src/Reactor.js:1374-1432",
        "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts:203-358",
      ]
    )

    _ = try await relaunched.closeConnection()
    let acceptedRelaunch = try await discardRuntime(cacheURL: cacheURL)
    let acceptedValue = try await TodoExample.decode(
      acceptedRelaunch.store.materialize(TodoExample.query)
    )
    expectNoDifference(acceptedValue.map(\.text), ["retried optimistic value"])
    let acceptedOutbox = try #require(
      try await acceptedRelaunch.persistence.loadState().snapshot.outbox.first
    )
    expectNoDifference(acceptedOutbox.status, .confirmed)
    expectNoDifference(acceptedOutbox.optimisticOverlayState, .applied)
  }

  @Test
  func retryReappliesTerminallyRemovedOptimisticOverlayExactlyOnce() async throws {
    let runtime = try await discardRuntime(
      cacheURL: temporaryDiscardCacheURL("retry-applied-overlay")
    )
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-applied-overlay-base",
        operations: TodoExample.upsertOperations(
          id: "todo-applied-overlay",
          text: "server",
          createdAt: baseTime,
          transactionID: "server-applied-overlay-base"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-applied-overlay",
        operations: TodoExample.updateTextOperations(
          id: "todo-applied-overlay",
          text: "optimistic once",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-applied-overlay"
        )
      )
    )
    _ = try await runtime.failMutation(
      id: "tx-applied-overlay",
      message: "permission denied without refresh"
    )
    let failed = try #require(await runtime.outboxMutations().first)
    expectNoDifference(failed.optimisticOverlayState, .removed)
    expectNoDifference(failed.rollbackTransaction, nil)
    let afterFailure = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(afterFailure.map(\.text), ["server"])

    let retried = try await runtime.retryMutation(id: "tx-applied-overlay")

    expectNoDifference(retried.optimisticOverlayState, .applied)
    #expect(retried.rollbackTransaction != nil)
    let current = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(current.map(\.text), ["optimistic once"])
    let textValues = (await runtime.outboxMutations()).flatMap { mutation in
      mutation.rollbackTransaction?.operations.compactMap { operation -> String? in
        guard case .retract(let triple) = operation,
          triple.attributeID == "todos/text",
          case .string(let value) = triple.value
        else { return nil }
        return value
      } ?? []
    }
    expectNoDifference(textValues, ["optimistic once"])
  }

  @Test
  func failedAtomicRetryCommitRetainsRejectionAndDoesNotResend() async throws {
    let cacheURL = temporaryDiscardCacheURL("retry-atomic-failure")
    let session = DiscardReconnectLiveSession()
    let runtime = try await discardRuntime(cacheURL: cacheURL, liveTransport: session.transport)
    _ = try await runtime.connect()
    await session.waitForSentMessageCount(1)

    try await enqueueDiscardMutation(id: "tx-retry-atomic-failure", runtime: runtime, offset: 0)
    await session.waitForSentMessageCount(2)
    _ = try await runtime.failMutation(
      id: "tx-retry-atomic-failure",
      message: "retained rejection before retry"
    )
    let failedStatus = try await runtime.connectionStatus()
    expectNoDifference(failedStatus.state, .errored)
    expectNoDifference(failedStatus.lastErrorMessage, "retained rejection before retry")

    try installRetryMetadataDeletionFailure(in: cacheURL)
    let sentBeforeRetry = await session.sentMessages()
    do {
      _ = try await runtime.retryMutation(id: "tx-retry-atomic-failure")
      Issue.record("Expected the injected atomic retry commit to fail.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .persistenceFailed)
      #expect(error.message.contains("injected retry metadata deletion failure"))
    }

    try await Task.sleep(for: .milliseconds(20))
    let sentAfterRetry = await session.sentMessages()
    expectNoDifference(sentAfterRetry, sentBeforeRetry)
    let retained = try #require(
      await runtime.outboxMutations().first(where: { $0.id == "tx-retry-atomic-failure" })
    )
    expectNoDifference(retained.status, .failed)
    expectNoDifference(retained.failureMessage, "retained rejection before retry")
    let retainedStatus = try await runtime.connectionStatus()
    expectNoDifference(retainedStatus.state, .errored)
    expectNoDifference(retainedStatus.lastErrorMessage, "retained rejection before retry")
  }

  @Test
  func terminalFailureRemovesKnownOptimismBeforeAnyQueryRefreshAndPersistsRecovery() async throws {
    let cacheURL = temporaryDiscardCacheURL("terminal-failure-zero-query")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-terminal-base",
        operations: TodoExample.upsertOperations(
          id: "todo-terminal-failure",
          text: "server value",
          createdAt: baseTime,
          transactionID: "server-terminal-base"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-terminal-failure",
        operations: TodoExample.updateTextOperations(
          id: "todo-terminal-failure",
          text: "rejected optimistic value",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-terminal-failure"
        )
      )
    )

    let failed = try await runtime.failMutation(
      id: "tx-terminal-failure",
      message: "permission denied terminal failure"
    )

    expectNoDifference(failed.status, .failed)
    expectNoDifference(failed.optimisticOverlayState, .removed)
    expectNoDifference(failed.rollbackTransaction, nil)
    let immediate = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(immediate.map(\.text), ["server value"])
    let failedStatus = try await runtime.connectionStatus()
    expectNoDifference(failedStatus.state, .errored)
    expectNoDifference(failedStatus.lastErrorMessage, "permission denied terminal failure")

    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let afterRelaunch = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(afterRelaunch.map(\.text), ["server value"])
    let retained = try #require(await relaunched.outboxMutations().first)
    expectNoDifference(retained.optimisticOverlayState, .removed)
    expectNoDifference(retained.rollbackTransaction, nil)

    let retried = try await relaunched.retryMutation(id: "tx-terminal-failure")
    expectNoDifference(retried.status, .pending)
    expectNoDifference(retried.optimisticOverlayState, .applied)
    let afterOneRetry = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(afterOneRetry.map(\.text), ["rejected optimistic value"])

    _ = try await relaunched.failMutation(
      id: "tx-terminal-failure",
      message: "permission denied after one retry"
    )
    let afterSecondRejection = try await TodoExample.decode(
      relaunched.query(TodoExample.query)
    )
    expectNoDifference(afterSecondRejection.map(\.text), ["server value"])
    _ = try await relaunched.discardFailedMutation(id: "tx-terminal-failure")
    let afterDiscard = await relaunched.outboxMutations()
    expectNoDifference(afterDiscard, [])
  }

  @Test
  func terminalFailureReplaysSuccessorAndRebuildsItsInverse() async throws {
    let runtime = try await discardRuntime(
      cacheURL: temporaryDiscardCacheURL("terminal-failure-successor")
    )
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-successor-rebase-base",
        operations: TodoExample.upsertOperations(
          id: "todo-successor-rebase",
          text: "server value",
          createdAt: baseTime,
          transactionID: "server-successor-rebase-base"
        )
      )
    )
    let unrelatedHighWaterTime = InstantTimestamp(milliseconds: baseTime.milliseconds + 100)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-successor-rebase-high-water",
        operations: TodoExample.upsertOperations(
          id: "unrelated-high-water-todo",
          text: "unrelated server value",
          createdAt: unrelatedHighWaterTime,
          transactionID: "server-successor-rebase-high-water"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-rejected-predecessor",
        operations: TodoExample.updateTextOperations(
          id: "todo-successor-rebase",
          text: "rejected predecessor",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-rejected-predecessor"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-surviving-successor",
        operations: TodoExample.updateTextOperations(
          id: "todo-successor-rebase",
          text: "surviving successor",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2),
          transactionID: "tx-surviving-successor"
        )
      )
    )

    _ = try await runtime.failMutation(
      id: "tx-rejected-predecessor",
      message: "permission denied predecessor"
    )
    let afterFirstFailure = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(
      afterFirstFailure.first { $0.id == "todo-successor-rebase" }?.text,
      "surviving successor"
    )
    let successor = try #require(
      await runtime.outboxMutations().first { $0.id == "tx-surviving-successor" }
    )
    #expect(successor.rollbackTransaction != nil)
    let successorTransport = try #require(
      await runtime.outboxTransportMutations().first {
        $0.mutationID == "tx-surviving-successor"
      }
    )
    #expect(
      successorTransport.txSteps.contains { step in
        guard
          case let .addTriple(_, attributeID, value, _) = step,
          attributeID == "todos/text",
          value == .string("surviving successor")
        else { return false }
        return true
      },
      "Replaying a successor after terminal rejection must preserve its wire write."
    )

    _ = try await runtime.failMutation(
      id: "tx-surviving-successor",
      message: "permission denied successor"
    )
    let afterSuccessorFailure = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(
      afterSuccessorFailure.first { $0.id == "todo-successor-rebase" }?.text,
      "server value"
    )
  }

  @Test
  func failedServerMutationTransportRemovesKnownOptimisticStateAtomicallyAndPersistsAcrossRelaunch()
    async throws
  {
    let cacheURL = temporaryDiscardCacheURL("failed-server-transport")
    let transport = InstantMutationTransportClient { request in
      InstantMutationTransportResponse(
        results: request.mutations.map {
          InstantMutationTransportResult(
            mutationID: $0.mutationID,
            outcome: .failed,
            message: "permission denied by server transport"
          )
        }
      )
    }
    let runtime = try await discardRuntime(
      cacheURL: cacheURL,
      mutationTransport: transport
    )
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-transport-base",
        operations: TodoExample.upsertOperations(
          id: "todo-server-transport-failure",
          text: "server value",
          createdAt: baseTime,
          transactionID: "server-transport-base"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-server-transport-failure",
        operations: TodoExample.updateTextOperations(
          id: "todo-server-transport-failure",
          text: "unauthorized optimistic value",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-server-transport-failure"
        )
      )
    )

    let flush = try await runtime.flushPendingMutations()

    expectNoDifference(flush.failed.map(\.id), ["tx-server-transport-failure"])
    let failed = try #require(await runtime.outboxMutations().first)
    expectNoDifference(failed.status, .failed)
    expectNoDifference(failed.optimisticOverlayState, .removed)
    expectNoDifference(failed.rollbackTransaction, nil)
    let immediate = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(immediate.map(\.text), ["server value"])

    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let durable = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(durable.map(\.text), ["server value"])
    let durableFailure = try #require(await relaunched.outboxMutations().first)
    expectNoDifference(durableFailure.optimisticOverlayState, .removed)
    expectNoDifference(durableFailure.rollbackTransaction, nil)
  }

  @Test
  func mixedTransportBatchReplaysLocallyConfirmedSuccessorAfterPredecessorFailure() async throws {
    try await assertMixedTransportBatchPreservesAcceptedSuccessor(
      acceptance: nil,
      suffix: "local-confirmed"
    )
  }

  @Test
  func mixedTransportBatchReplaysServerAcceptedSuccessorAfterPredecessorFailure() async throws {
    try await assertMixedTransportBatchPreservesAcceptedSuccessor(
      acceptance: .serverAccepted,
      suffix: "server-accepted"
    )
  }

  @Test
  func serverAcceptedTransportRetainsReconciliationUntilAuthoritativeRefresh() async throws {
    let cacheURL = temporaryDiscardCacheURL("server-accepted-reconciliation")
    let runtime = try await discardRuntime(
      cacheURL: cacheURL,
      mutationTransport: InstantMutationTransportClient { request in
        InstantMutationTransportResponse(
          results: request.mutations.map {
            InstantMutationTransportResult(
              mutationID: $0.mutationID,
              outcome: .confirmed,
              acceptance: .serverAccepted
            )
          }
        )
      }
    )
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-reconciliation-base-X",
        operations: TodoExample.upsertOperations(
          id: "todo-server-reconciliation",
          text: "server X",
          createdAt: InstantTimestamp(milliseconds: 10),
          transactionID: "server-reconciliation-base-X"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-server-reconciliation-A",
        operations: TodoExample.updateTextOperations(
          id: "todo-server-reconciliation",
          text: "optimistic A",
          updatedAt: InstantTimestamp(milliseconds: 100),
          transactionID: "tx-server-reconciliation-A"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: 100)
    )

    let flush = try await runtime.flushPendingMutations()

    expectNoDifference(flush.confirmed.map(\.status), [.confirmed])
    let retainedProof = try #require(
      try await runtime.persistence.loadState().snapshot.outbox.first
    )
    expectNoDifference(retainedProof.confirmationSource, .serverTransport)
    expectNoDifference(retainedProof.optimisticOverlayState, .applied)
    #expect(retainedProof.rollbackTransaction != nil)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(id: "server-empty-catch-up", operations: [])
    )
    let afterEmptyCatchUp = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(afterEmptyCatchUp.map(\.text), ["optimistic A"])
    let afterEmptyOutbox = try await runtime.persistence.loadState().snapshot.outbox
    #expect(afterEmptyOutbox.first != nil)

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-authoritative-B",
        operations: TodoExample.updateTextOperations(
          id: "todo-server-reconciliation",
          text: "server B",
          updatedAt: InstantTimestamp(milliseconds: 50),
          transactionID: "server-authoritative-B"
        )
      )
    )

    let immediate = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(immediate.map(\.text), ["server B"])
    let reconciledOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(reconciledOutbox, [])
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let durable = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(durable.map(\.text), ["server B"])
    let durableOutbox = try await relaunched.persistence.loadState().snapshot.outbox
    expectNoDifference(durableOutbox, [])
  }

  @Test
  func serverAcceptedTransportReconcilesOnlyAuthoritativelyCoveredWrites() async throws {
    let cacheURL = temporaryDiscardCacheURL("server-accepted-partial-reconciliation")
    let runtime = try await discardRuntime(
      cacheURL: cacheURL,
      mutationTransport: InstantMutationTransportClient { request in
        InstantMutationTransportResponse(
          results: request.mutations.map {
            InstantMutationTransportResult(
              mutationID: $0.mutationID,
              outcome: .confirmed,
              acceptance: .serverAccepted
            )
          }
        )
      }
    )
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-partial-base",
        operations: TodoExample.upsertOperations(
          id: "todo-accepted-A",
          text: "server A0",
          createdAt: InstantTimestamp(milliseconds: 10),
          transactionID: "server-partial-base-A"
        ) + TodoExample.upsertOperations(
          id: "todo-accepted-B",
          text: "server B0",
          createdAt: InstantTimestamp(milliseconds: 11),
          transactionID: "server-partial-base-B"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-accepted-A1",
        operations: TodoExample.updateTextOperations(
          id: "todo-accepted-A",
          text: "accepted A1",
          updatedAt: InstantTimestamp(milliseconds: 100),
          transactionID: "tx-accepted-A1"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-accepted-B1",
        operations: TodoExample.updateTextOperations(
          id: "todo-accepted-B",
          text: "accepted B1",
          updatedAt: InstantTimestamp(milliseconds: 101),
          transactionID: "tx-accepted-B1"
        )
      ),
      createdAt: InstantTimestamp(milliseconds: 101)
    )
    _ = try await runtime.flushPendingMutations()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-authoritative-B2",
        operations: TodoExample.updateTextOperations(
          id: "todo-accepted-B",
          text: "server B2",
          updatedAt: InstantTimestamp(milliseconds: 50),
          transactionID: "server-authoritative-B2"
        )
      )
    )

    let afterBRefresh = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(
      Dictionary(uniqueKeysWithValues: afterBRefresh.map { ($0.id, $0.text) }),
      ["todo-accepted-A": "accepted A1", "todo-accepted-B": "server B2"]
    )
    let afterBOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(afterBOutbox.map(\.id), ["tx-accepted-A1"])
    expectNoDifference(afterBOutbox.map(\.confirmationSource), [.serverTransport])

    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let durableAfterB = try await TodoExample.decode(
      relaunched.store.materialize(TodoExample.query)
    )
    expectNoDifference(
      Dictionary(uniqueKeysWithValues: durableAfterB.map { ($0.id, $0.text) }),
      ["todo-accepted-A": "accepted A1", "todo-accepted-B": "server B2"]
    )
    _ = try await relaunched.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-authoritative-A2",
        operations: TodoExample.updateTextOperations(
          id: "todo-accepted-A",
          text: "server A2",
          updatedAt: InstantTimestamp(milliseconds: 60),
          transactionID: "server-authoritative-A2"
        )
      )
    )
    let afterARefresh = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(
      Dictionary(uniqueKeysWithValues: afterARefresh.map { ($0.id, $0.text) }),
      ["todo-accepted-A": "server A2", "todo-accepted-B": "server B2"]
    )
    let fullyReconciledOutbox = try await relaunched.persistence.loadState().snapshot.outbox
    expectNoDifference(fullyReconciledOutbox, [])
  }

  @Test
  func serverAcceptedManyInsertWaitsForExactAuthoritativeValueCoverage() async throws {
    let cacheURL = temporaryDiscardCacheURL("server-accepted-many-insert")
    let runtime = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [manyTagsAttribute],
      acceptsTransport: true
    )
    let entityID = "many-insert-row"
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-many-insert-base",
        operations: [
          coverageTripleOperation(
            entityID: entityID,
            attributeID: manyTagsAttribute.id,
            value: "old",
            transactionID: "server-many-insert-base",
            milliseconds: 10
          )
        ]
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-many-insert-accepted",
        operations: [
          coverageTripleOperation(
            entityID: entityID,
            attributeID: manyTagsAttribute.id,
            value: "accepted",
            transactionID: "tx-many-insert-accepted",
            milliseconds: 100
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    _ = try await runtime.flushPendingMutations()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-many-insert-unrelated",
        operations: [
          coverageTripleOperation(
            entityID: entityID,
            attributeID: manyTagsAttribute.id,
            value: "unrelated",
            transactionID: "server-many-insert-unrelated",
            milliseconds: 50
          )
        ]
      )
    )
    let afterUnrelatedInsert = try await coverageStringValues(
      runtime: runtime,
      entityID: entityID,
      attributeID: manyTagsAttribute.id
    )
    expectNoDifference(afterUnrelatedInsert, ["accepted", "old", "unrelated"])
    let partialOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(partialOutbox.map(\.id), ["tx-many-insert-accepted"])

    let relaunched = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [manyTagsAttribute]
    )
    let durableAfterUnrelatedInsert = try await coverageStringValues(
      runtime: relaunched,
      entityID: entityID,
      attributeID: manyTagsAttribute.id
    )
    expectNoDifference(durableAfterUnrelatedInsert, ["accepted", "old", "unrelated"])
    _ = try await relaunched.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-many-insert-exact-retract",
        operations: [
          .retract(
            coverageTriple(
              entityID: entityID,
              attributeID: manyTagsAttribute.id,
              value: "accepted",
              transactionID: "server-many-insert-exact-retract",
              milliseconds: 60
            )
          )
        ]
      )
    )
    let afterExactInsertCoverage = try await coverageStringValues(
      runtime: relaunched,
      entityID: entityID,
      attributeID: manyTagsAttribute.id
    )
    expectNoDifference(afterExactInsertCoverage, ["old", "unrelated"])
    let reconciledOutbox = try await relaunched.persistence.loadState().snapshot.outbox
    expectNoDifference(reconciledOutbox, [])
  }

  @Test
  func serverAcceptedManyRetractWaitsForExactAuthoritativeValueCoverage() async throws {
    let cacheURL = temporaryDiscardCacheURL("server-accepted-many-retract")
    let runtime = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [manyTagsAttribute],
      acceptsTransport: true
    )
    let entityID = "many-retract-row"
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-many-retract-base",
        operations: ["old", "accepted"].map { value in
          coverageTripleOperation(
            entityID: entityID,
            attributeID: manyTagsAttribute.id,
            value: value,
            transactionID: "server-many-retract-base",
            milliseconds: 10
          )
        }
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-many-retract-accepted",
        operations: [
          .retract(
            coverageTriple(
              entityID: entityID,
              attributeID: manyTagsAttribute.id,
              value: "accepted",
              transactionID: "tx-many-retract-accepted",
              milliseconds: 100
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    _ = try await runtime.flushPendingMutations()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-many-retract-unrelated",
        operations: [
          coverageTripleOperation(
            entityID: entityID,
            attributeID: manyTagsAttribute.id,
            value: "unrelated",
            transactionID: "server-many-retract-unrelated",
            milliseconds: 50
          )
        ]
      )
    )
    let afterUnrelatedRetractDelta = try await coverageStringValues(
      runtime: runtime,
      entityID: entityID,
      attributeID: manyTagsAttribute.id
    )
    expectNoDifference(afterUnrelatedRetractDelta, ["old", "unrelated"])
    let partialOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(partialOutbox.map(\.id), ["tx-many-retract-accepted"])

    let relaunched = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [manyTagsAttribute]
    )
    let durableAfterUnrelatedRetractDelta = try await coverageStringValues(
      runtime: relaunched,
      entityID: entityID,
      attributeID: manyTagsAttribute.id
    )
    expectNoDifference(durableAfterUnrelatedRetractDelta, ["old", "unrelated"])
    _ = try await relaunched.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-many-retract-exact-insert",
        operations: [
          coverageTripleOperation(
            entityID: entityID,
            attributeID: manyTagsAttribute.id,
            value: "accepted",
            transactionID: "server-many-retract-exact-insert",
            milliseconds: 60
          )
        ]
      )
    )
    let afterExactRetractCoverage = try await coverageStringValues(
      runtime: relaunched,
      entityID: entityID,
      attributeID: manyTagsAttribute.id
    )
    expectNoDifference(afterExactRetractCoverage, ["accepted", "old", "unrelated"])
    let reconciledOutbox = try await relaunched.persistence.loadState().snapshot.outbox
    expectNoDifference(reconciledOutbox, [])
  }

  @Test
  func serverAcceptedDeleteWaitsForAuthoritativeEntityDeletionBoundary() async throws {
    let cacheURL = temporaryDiscardCacheURL("server-accepted-delete-coverage")
    let runtime = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: deleteCoverageAttributes,
      acceptsTransport: true
    )
    let entityID = "delete-coverage-row"
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-delete-coverage-base",
        operations: [
          coverageTripleOperation(
            entityID: entityID,
            attributeID: deleteCoverageAttributes[0].id,
            value: "old title",
            transactionID: "server-delete-coverage-base",
            milliseconds: 10
          ),
          coverageTripleOperation(
            entityID: entityID,
            attributeID: deleteCoverageAttributes[1].id,
            value: "old note",
            transactionID: "server-delete-coverage-base",
            milliseconds: 10
          ),
        ]
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-delete-coverage-accepted",
        operations: [
          .deleteEntityInNamespace(entityID: entityID, namespace: "coverageRows")
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    _ = try await runtime.flushPendingMutations()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-delete-coverage-partial-field",
        operations: [
          coverageTripleOperation(
            entityID: entityID,
            attributeID: deleteCoverageAttributes[0].id,
            value: "new title",
            transactionID: "server-delete-coverage-partial-field",
            milliseconds: 50
          )
        ]
      )
    )
    let afterPartialDeleteCoverage = try await coverageEntityTriples(
      runtime: runtime,
      entityID: entityID
    )
    expectNoDifference(afterPartialDeleteCoverage, [])
    let partialOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(partialOutbox.map(\.id), ["tx-delete-coverage-accepted"])

    let relaunched = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: deleteCoverageAttributes
    )
    let durableAfterPartialDeleteCoverage = try await coverageEntityTriples(
      runtime: relaunched,
      entityID: entityID
    )
    expectNoDifference(durableAfterPartialDeleteCoverage, [])
    _ = try await relaunched.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-delete-coverage-full-delete",
        operations: [
          .deleteEntityInNamespace(entityID: entityID, namespace: "coverageRows")
        ]
      )
    )
    let afterFullDeleteCoverage = try await coverageEntityTriples(
      runtime: relaunched,
      entityID: entityID
    )
    expectNoDifference(afterFullDeleteCoverage, [])
    let reconciledOutbox = try await relaunched.persistence.loadState().snapshot.outbox
    expectNoDifference(reconciledOutbox, [])
  }

  @Test
  func serverAcceptedInsertWithoutBaseIgnoresUnrelatedAuthoritativeRetraction() async throws {
    let cacheURL = temporaryDiscardCacheURL("server-accepted-empty-insert-retraction")
    let runtime = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [jsonSettingsAttribute],
      acceptsTransport: true
    )
    let entityID = "empty-insert-retraction-row"
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-empty-insert-accepted",
        operations: [
          .insert(
            coverageJSONTriple(
              entityID: entityID,
              value: .object(["accepted": .bool(true)]),
              transactionID: "tx-empty-insert-accepted",
              milliseconds: 100
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    _ = try await runtime.flushPendingMutations()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-empty-insert-unrelated-retraction",
        operations: [
          .retract(
            coverageJSONTriple(
              entityID: entityID,
              value: .object(["unrelated": .bool(true)]),
              transactionID: "server-empty-insert-unrelated-retraction",
              milliseconds: 50
            )
          )
        ]
      )
    )
    let afterUnrelatedRetraction = try await coverageJSONValue(
      runtime: runtime,
      entityID: entityID
    )
    expectNoDifference(afterUnrelatedRetraction, .object(["accepted": .bool(true)]))
    let retainedOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(retainedOutbox.map(\.id), ["tx-empty-insert-accepted"])

    let relaunched = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [jsonSettingsAttribute]
    )
    let durableValue = try await coverageJSONValue(runtime: relaunched, entityID: entityID)
    expectNoDifference(durableValue, .object(["accepted": .bool(true)]))
    let durableOutbox = try await relaunched.persistence.loadState().snapshot.outbox
    expectNoDifference(durableOutbox.map(\.id), ["tx-empty-insert-accepted"])
  }

  @Test
  func serverAcceptedJSONMergeWaitsForCoveredPatchOrFullReplacement() async throws {
    let cacheURL = temporaryDiscardCacheURL("server-accepted-json-merge-coverage")
    let runtime = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [jsonSettingsAttribute],
      acceptsTransport: true
    )
    let entityID = "json-merge-coverage-row"
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-json-merge-base",
        operations: [
          .insert(
            coverageJSONTriple(
              entityID: entityID,
              value: .object(["base": .string("server")]),
              transactionID: "server-json-merge-base",
              milliseconds: 10
            )
          )
        ]
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-json-merge-accepted",
        operations: [
          .merge(
            coverageJSONTriple(
              entityID: entityID,
              value: .object(["accepted": .bool(true)]),
              transactionID: "tx-json-merge-accepted",
              milliseconds: 100
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    _ = try await runtime.flushPendingMutations()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-json-merge-unrelated-patch",
        operations: [
          .merge(
            coverageJSONTriple(
              entityID: entityID,
              value: .object(["unrelated": .bool(true)]),
              transactionID: "server-json-merge-unrelated-patch",
              milliseconds: 50
            )
          )
        ]
      )
    )
    let afterUnrelatedPatch = try await coverageJSONValue(runtime: runtime, entityID: entityID)
    expectNoDifference(
      afterUnrelatedPatch,
      .object([
        "accepted": .bool(true),
        "base": .string("server"),
        "unrelated": .bool(true),
      ])
    )
    let partialOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(partialOutbox.map(\.id), ["tx-json-merge-accepted"])

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-json-full-replacement",
        operations: [
          .insert(
            coverageJSONTriple(
              entityID: entityID,
              value: .object([
                "accepted": .bool(true),
                "base": .string("server"),
                "unrelated": .bool(true),
              ]),
              transactionID: "server-json-full-replacement",
              milliseconds: 60
            )
          )
        ]
      )
    )
    let reconciledOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(reconciledOutbox, [])
  }

  @Test
  func serverAcceptedJSONMergeReconcilesAgainstAuthoritativeRetraction() async throws {
    let cacheURL = temporaryDiscardCacheURL("server-accepted-json-merge-retraction")
    let runtime = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [jsonSettingsAttribute],
      acceptsTransport: true
    )
    let entityID = "json-merge-retraction-row"
    let authoritativeBase = coverageJSONTriple(
      entityID: entityID,
      value: .object(["base": .string("server")]),
      transactionID: "server-json-retraction-base",
      milliseconds: 10
    )
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-json-retraction-base",
        operations: [.insert(authoritativeBase)]
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-json-merge-retraction-accepted",
        operations: [
          .merge(
            coverageJSONTriple(
              entityID: entityID,
              value: .object(["accepted": .bool(true)]),
              transactionID: "tx-json-merge-retraction-accepted",
              milliseconds: 100
            )
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    _ = try await runtime.flushPendingMutations()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-json-retraction-absence",
        operations: [.retract(authoritativeBase)]
      )
    )
    let afterRetraction = try await coverageJSONValue(runtime: runtime, entityID: entityID)
    expectNoDifference(afterRetraction, nil)
    let reconciledOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(reconciledOutbox, [])

    let relaunched = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [jsonSettingsAttribute]
    )
    let durableAfterRetraction = try await coverageJSONValue(
      runtime: relaunched,
      entityID: entityID
    )
    expectNoDifference(durableAfterRetraction, nil)
    let relaunchedOutbox = try await relaunched.persistence.loadState().snapshot.outbox
    expectNoDifference(relaunchedOutbox, [])
  }

  @Test(arguments: CardinalityOneAcceptedWrite.allCases)
  fileprivate func serverAcceptedCardinalityOneWriteIgnoresUnrelatedAuthoritativeRetraction(
    write: CardinalityOneAcceptedWrite
  ) async throws {
    let cacheURL = temporaryDiscardCacheURL(
      "server-accepted-cardinality-one-unrelated-retraction-\(write.rawValue)"
    )
    let runtime = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [jsonSettingsAttribute],
      acceptsTransport: true
    )
    let entityID = "cardinality-one-unrelated-retraction-\(write.rawValue)"
    let mutationID = "tx-cardinality-one-unrelated-retraction-\(write.rawValue)"
    let authoritativeBase = coverageJSONTriple(
      entityID: entityID,
      value: .object(["base": .string("server")]),
      transactionID: "server-cardinality-one-base-\(write.rawValue)",
      milliseconds: 10
    )
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-cardinality-one-base-\(write.rawValue)",
        operations: [.insert(authoritativeBase)]
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: mutationID,
        operations: [
          write.operation(
            entityID: entityID,
            mutationID: mutationID,
            authoritativeBase: authoritativeBase
          )
        ]
      ),
      createdAt: InstantTimestamp(milliseconds: 100)
    )
    _ = try await runtime.flushPendingMutations()

    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-cardinality-one-unrelated-retraction-\(write.rawValue)",
        operations: [
          .retract(
            coverageJSONTriple(
              entityID: entityID,
              value: .object(["unrelated": .string("server")]),
              transactionID: "server-cardinality-one-unrelated-retraction-\(write.rawValue)",
              milliseconds: 50
            )
          )
        ]
      )
    )
    let afterUnrelatedRetraction = try await coverageJSONValue(
      runtime: runtime,
      entityID: entityID
    )
    expectNoDifference(afterUnrelatedRetraction, write.expectedValue)
    let retainedOutbox = try await runtime.persistence.loadState().snapshot.outbox
    expectNoDifference(retainedOutbox.map(\.id), [mutationID])

    let relaunched = try await serverAcceptedCoverageRuntime(
      cacheURL: cacheURL,
      attributes: [jsonSettingsAttribute]
    )
    let durableAfterUnrelatedRetraction = try await coverageJSONValue(
      runtime: relaunched,
      entityID: entityID
    )
    expectNoDifference(durableAfterUnrelatedRetraction, write.expectedValue)
    let relaunchedOutbox = try await relaunched.persistence.loadState().snapshot.outbox
    expectNoDifference(relaunchedOutbox.map(\.id), [mutationID])
  }

  private func assertMixedTransportBatchPreservesAcceptedSuccessor(
    acceptance: InstantMutationTransportResult.Acceptance?,
    suffix: String
  ) async throws {
    let cacheURL = temporaryDiscardCacheURL("mixed-transport-\(suffix)")
    let transport = InstantMutationTransportClient { request in
      InstantMutationTransportResponse(
        results: request.mutations.map { mutation in
          if mutation.mutationID == "tx-mixed-predecessor-A" {
            InstantMutationTransportResult(
              mutationID: mutation.mutationID,
              outcome: .failed,
              message: "permission denied mixed predecessor A"
            )
          } else {
            InstantMutationTransportResult(
              mutationID: mutation.mutationID,
              outcome: .confirmed,
              acceptance: acceptance
            )
          }
        }
      )
    }
    let runtime = try await discardRuntime(
      cacheURL: cacheURL,
      mutationTransport: transport
    )
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-mixed-base-X",
        operations: TodoExample.upsertOperations(
          id: "todo-mixed-transport",
          text: "server X",
          createdAt: baseTime,
          transactionID: "server-mixed-base-X"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-mixed-predecessor-A",
        operations: TodoExample.updateTextOperations(
          id: "todo-mixed-transport",
          text: "optimistic A",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-mixed-predecessor-A"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-mixed-successor-B",
        operations: TodoExample.updateTextOperations(
          id: "todo-mixed-transport",
          text: "accepted B",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2),
          transactionID: "tx-mixed-successor-B"
        )
      )
    )

    let flush = try await runtime.flushPendingMutations()

    expectNoDifference(flush.failed.map(\.id), ["tx-mixed-predecessor-A"])
    expectNoDifference(flush.confirmed.map(\.id), ["tx-mixed-successor-B"])
    expectNoDifference(flush.confirmed.map(\.status), [.confirmed])
    let immediate = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(immediate.map(\.text), ["accepted B"])
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let durableAccepted = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(durableAccepted.map(\.text), ["accepted B"])

    _ = try await relaunched.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-mixed-authoritative-C",
        operations: TodoExample.updateTextOperations(
          id: "todo-mixed-transport",
          text: "server C",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 3),
          transactionID: "server-mixed-authoritative-C"
        )
      )
    )
    if acceptance == nil {
      let stillAwaitingServer = try await TodoExample.decode(
        relaunched.query(TodoExample.query)
      )
      expectNoDifference(stillAwaitingServer.map(\.text), ["accepted B"])
      _ = try await relaunched.failMutation(
        id: "tx-mixed-successor-B",
        message: "server later rejected successor B"
      )
    }
    let authoritative = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(authoritative.map(\.text), ["server C"])
    let finalRelaunch = try await discardRuntime(cacheURL: cacheURL)
    let durableAuthoritative = try await TodoExample.decode(
      finalRelaunch.query(TodoExample.query)
    )
    expectNoDifference(durableAuthoritative.map(\.text), ["server C"])
  }

  @Test(arguments: LocalConfirmationRoute.allCases)
  fileprivate func localConfirmationRemainsLiveSendableAndRefreshSafe(
    route: LocalConfirmationRoute
  ) async throws {
    let cacheURL = temporaryDiscardCacheURL("local-confirmation-\(route.rawValue)")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let mutationID = "tx-local-confirmation-\(route.rawValue)"
    let entityID = "todo-local-confirmation-\(route.rawValue)"
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-local-confirmation-base-X",
        operations: TodoExample.upsertOperations(
          id: entityID,
          text: "server X",
          createdAt: baseTime,
          transactionID: "server-local-confirmation-base-X"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: mutationID,
        operations: TodoExample.updateTextOperations(
          id: entityID,
          text: "optimistic A",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: mutationID
        )
      )
    )

    let locallyConfirmed: PendingMutation
    switch route {
    case .manual:
      locallyConfirmed = try await runtime.confirmMutation(id: mutationID)
    case .drain:
      locallyConfirmed = try #require(await runtime.drainPendingMutationsLocally().first)
      let repeatedDrain = try await runtime.drainPendingMutationsLocally()
      expectNoDifference(repeatedDrain, [])
    case .localTransport:
      let flush = try await runtime.flushPendingMutations()
      locallyConfirmed = try #require(flush.confirmed.first)
      let repeatedFlush = try await runtime.flushPendingMutations()
      expectNoDifference(repeatedFlush.request.mutations, [])
      expectNoDifference(repeatedFlush.confirmed, [])
    }
    expectNoDifference(locallyConfirmed.status, .confirmed)
    expectNoDifference(locallyConfirmed.confirmationSource, route.confirmationSource)
    let liveWireQueue = await runtime.outboxTransportMutations()
    expectNoDifference(liveWireQueue.map(\.mutationID), [mutationID])
    expectNoDifference(liveWireQueue.map(\.status), [.pending])

    for (offset, value) in [(Int64(2), "server B"), (Int64(3), "server C")] {
      _ = try await runtime.applyServerTransaction(
        InstantStoreTransaction(
          id: "server-local-confirmation-\(value)",
          operations: TodoExample.updateTextOperations(
            id: entityID,
            text: value,
            updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + offset),
            transactionID: "server-local-confirmation-\(value)"
          )
        )
      )
      let stillOptimistic = try await TodoExample.decode(runtime.query(TodoExample.query))
      expectNoDifference(stillOptimistic.map(\.text), ["optimistic A"])
    }
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let durableOptimistic = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(durableOptimistic.map(\.text), ["optimistic A"])
    let durableReceipt = try #require(
      try await relaunched.persistence.loadState().snapshot.outbox.first
    )
    expectNoDifference(durableReceipt.status, .confirmed)
    expectNoDifference(durableReceipt.confirmationSource, route.confirmationSource)
    expectNoDifference(durableReceipt.optimisticOverlayState, .applied)
    #expect(durableReceipt.rollbackTransaction != nil)

    let session = DiscardReconnectLiveSession()
    let live = try await discardRuntime(cacheURL: cacheURL, liveTransport: session.transport)
    _ = try await live.connect()
    try await instantLiveWithTimeout(
      operation: "wait for locally confirmed mutation delivery",
      timeoutMilliseconds: 5_000
    ) {
      while await session.sentMessages().count < 2 {
        try await Task.sleep(for: .milliseconds(1))
      }
    }
    let sent = await session.sentMessages()
    expectNoDifference(sent.map(\.op), ["init", "transact"])
    expectNoDifference(sent.last?.clientEventID, mutationID)
    await session.acceptMutation(id: mutationID, serverTransactionID: "200")
    let accepted = try await waitForServerAcceptedDiscardMutation(
      id: mutationID,
      runtime: live
    )
    expectNoDifference(accepted.confirmationSource, .webSocketTransactOK)
    expectNoDifference(accepted.serverTransactionID, "200")

    _ = try await live.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-local-confirmation-authoritative-D",
        operations: TodoExample.updateTextOperations(
          id: entityID,
          text: "server D",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 4),
          transactionID: "server-local-confirmation-authoritative-D"
        )
      ),
      processedTransactionID: "200"
    )
    let prunedOutbox = try await live.persistence.loadState().snapshot.outbox
    expectNoDifference(prunedOutbox, [])
    let authoritative = try await TodoExample.decode(live.query(TodoExample.query))
    expectNoDifference(authoritative.map(\.text), ["server D"])
    _ = try await live.closeConnection()
    let finalRelaunch = try await discardRuntime(cacheURL: cacheURL)
    let durableAuthoritative = try await TodoExample.decode(
      finalRelaunch.store.materialize(TodoExample.query)
    )
    expectNoDifference(durableAuthoritative.map(\.text), ["server D"])
  }

  @Test(arguments: LocalConfirmationRoute.allCases)
  fileprivate func localConfirmationLiveRejectionRollsBackWithoutResend(
    route: LocalConfirmationRoute
  ) async throws {
    let cacheURL = temporaryDiscardCacheURL("local-rejection-\(route.rawValue)")
    let offline = try await discardRuntime(cacheURL: cacheURL)
    let mutationID = "tx-local-rejection-\(route.rawValue)"
    let entityID = "todo-local-rejection-\(route.rawValue)"
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await offline.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-local-rejection-base-X",
        operations: TodoExample.upsertOperations(
          id: entityID,
          text: "server X",
          createdAt: baseTime,
          transactionID: "server-local-rejection-base-X"
        )
      )
    )
    try await offline.transact(
      InstantStoreTransaction(
        id: mutationID,
        operations: TodoExample.updateTextOperations(
          id: entityID,
          text: "optimistic A",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: mutationID
        )
      )
    )
    switch route {
    case .manual:
      _ = try await offline.confirmMutation(id: mutationID)
    case .drain:
      _ = try await offline.drainPendingMutationsLocally()
    case .localTransport:
      _ = try await offline.flushPendingMutations()
    }

    let session = DiscardReconnectLiveSession()
    let live = try await discardRuntime(cacheURL: cacheURL, liveTransport: session.transport)
    let lifecycle = try await live.observeMutationLifecycle(id: mutationID)
    let recorder = DiscardLifecycleRecorder()
    let observation = Task {
      for await event in lifecycle {
        await recorder.append(event)
      }
    }
    defer { observation.cancel() }
    try await recorder.waitForCount(1)
    _ = try await live.connect()
    try await instantLiveWithTimeout(
      operation: "wait for locally confirmed mutation before rejection",
      timeoutMilliseconds: 5_000
    ) {
      while await session.sentMessages().count < 2 {
        try await Task.sleep(for: .milliseconds(1))
      }
    }
    await session.rejectMutation(
      id: mutationID,
      message: "permission denied local confirmation"
    )
    try await recorder.waitForCount(2)
    let failed = try await waitForDiscardMutation(
      id: mutationID,
      status: .failed,
      runtime: live
    )
    let lifecycleLabels = await recorder.labels
    expectNoDifference(lifecycleLabels, ["waiting", "failed:\(mutationID)"])
    expectNoDifference(failed.optimisticOverlayState, .removed)
    expectNoDifference(failed.rollbackTransaction, nil)
    let immediate = try await TodoExample.decode(live.query(TodoExample.query))
    expectNoDifference(immediate.map(\.text), ["server X"])
    try await Task.sleep(for: .milliseconds(20))
    let sent = await session.sentMessages()
    expectNoDifference(
      sent.map(\.op),
      ["init", "transact", "add-query", "remove-query"],
      "An explicitly opened session runs later one-shot queries through the live server."
    )
    _ = try await live.closeConnection()

    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let durable = try await TodoExample.decode(relaunched.store.materialize(TodoExample.query))
    expectNoDifference(durable.map(\.text), ["server X"])
    let durableFailure = try #require(await relaunched.outboxMutations().first)
    expectNoDifference(durableFailure.status, .failed)
    expectNoDifference(durableFailure.optimisticOverlayState, .removed)
    expectNoDifference(durableFailure.rollbackTransaction, nil)
  }

  @Test
  func discardRebuildsSuccessorInverseBeforeLaterFailureAndRelaunch() async throws {
    let cacheURL = temporaryDiscardCacheURL("discard-rebuilds-successor")
    let runtime = try await discardRuntime(cacheURL: cacheURL)
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-discard-successor-base",
        operations: TodoExample.upsertOperations(
          id: "todo-discard-successor",
          text: "server X",
          createdAt: baseTime,
          transactionID: "server-discard-successor-base"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-discard-predecessor-A",
        operations: TodoExample.updateTextOperations(
          id: "todo-discard-successor",
          text: "optimistic A",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1),
          transactionID: "tx-discard-predecessor-A"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-discard-successor-B",
        operations: TodoExample.updateTextOperations(
          id: "todo-discard-successor",
          text: "optimistic B",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2),
          transactionID: "tx-discard-successor-B"
        )
      )
    )
    try await markMutationFailedWithoutRemovingOverlay(
      id: "tx-discard-predecessor-A",
      runtime: runtime
    )

    _ = try await runtime.discardFailedMutation(id: "tx-discard-predecessor-A")
    let afterDiscard = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(afterDiscard.map(\.text), ["optimistic B"])
    let rebasedSuccessor = try #require(
      await runtime.outboxMutations().first { $0.id == "tx-discard-successor-B" }
    )
    #expect(rebasedSuccessor.rollbackTransaction != nil)

    _ = try await runtime.failMutation(
      id: "tx-discard-successor-B",
      message: "permission denied successor B"
    )
    let immediate = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(immediate.map(\.text), ["server X"])
    let relaunched = try await discardRuntime(cacheURL: cacheURL)
    let durable = try await TodoExample.decode(relaunched.query(TodoExample.query))
    expectNoDifference(durable.map(\.text), ["server X"])
  }

  @Test
  func legacyPendingUnknownUpdateAndDeleteRefuseRefreshBeforeRejectionWithoutChangingCache()
    async throws
  {
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let updateRuntime = try await discardRuntime(
      cacheURL: temporaryDiscardCacheURL("legacy-pending-update")
    )
    _ = try await updateRuntime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-legacy-pending-update-base",
        operations: TodoExample.upsertOperations(
          id: "todo-legacy-pending-update",
          text: "server value",
          createdAt: baseTime,
          transactionID: "server-legacy-pending-update-base"
        )
      )
    )
    try await updateRuntime.transact(
      InstantStoreTransaction(
        id: "tx-legacy-pending-update",
        operations: TodoExample.updateTextOperations(
          id: "todo-legacy-pending-update",
          text: "future pending update",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 10_000_000),
          transactionID: "tx-legacy-pending-update"
        )
      )
    )
    try await makeLegacyUnknownPending(id: "tx-legacy-pending-update", runtime: updateRuntime)
    let updateStateBeforeRefresh = try await updateRuntime.persistence.loadState().snapshot
    await withExpectedIssue {
      await expectUnknownStateFailure(id: "tx-legacy-pending-update", operation: "refresh") {
        _ = try await updateRuntime.applyServerTransaction(
          InstantStoreTransaction(
            id: "server-refresh-over-legacy-pending-update",
            operations: TodoExample.updateTextOperations(
              id: "todo-legacy-pending-update",
              text: "server refresh must not overwrite unknown pending state",
              updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2_000_000),
              transactionID: "server-refresh-over-legacy-pending-update"
            )
          )
        )
      }
    }
    let updateStateAfterRefresh = try await updateRuntime.persistence.loadState().snapshot
    expectNoDifference(updateStateAfterRefresh, updateStateBeforeRefresh)
    let retainedUpdate = try await TodoExample.decode(updateRuntime.query(TodoExample.query))
    expectNoDifference(retainedUpdate.map(\.text), ["future pending update"])

    let deleteRuntime = try await discardRuntime(
      cacheURL: temporaryDiscardCacheURL("legacy-pending-delete")
    )
    _ = try await deleteRuntime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-legacy-pending-delete-base",
        operations: TodoExample.upsertOperations(
          id: "todo-legacy-pending-delete",
          text: "server value",
          createdAt: baseTime,
          transactionID: "server-legacy-pending-delete-base"
        )
      )
    )
    try await deleteRuntime.transact(
      InstantStoreTransaction(
        id: "tx-legacy-pending-delete",
        operations: TodoExample.deleteOperations(id: "todo-legacy-pending-delete")
      )
    )
    try await makeLegacyUnknownPending(id: "tx-legacy-pending-delete", runtime: deleteRuntime)
    let deleteStateBeforeRefresh = try await deleteRuntime.persistence.loadState().snapshot
    await withExpectedIssue {
      await expectUnknownStateFailure(id: "tx-legacy-pending-delete", operation: "refresh") {
        _ = try await deleteRuntime.applyServerTransaction(
          InstantStoreTransaction(
            id: "server-refresh-over-legacy-pending-delete",
            operations: TodoExample.upsertOperations(
              id: "todo-legacy-pending-delete",
              text: "server refresh must not resurrect unknown pending delete",
              createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2_000_000),
              transactionID: "server-refresh-over-legacy-pending-delete"
            )
          )
        )
      }
    }
    let deleteStateAfterRefresh = try await deleteRuntime.persistence.loadState().snapshot
    expectNoDifference(deleteStateAfterRefresh, deleteStateBeforeRefresh)
    let retainedDelete = try await TodoExample.decode(deleteRuntime.query(TodoExample.query))
    expectNoDifference(retainedDelete, [])
  }

  @Test
  func legacyUnknownUpdateAndDeleteRefuseRetryAndDiscardWithoutChangingCache() async throws {
    let updateRuntime = try await discardRuntime(
      cacheURL: temporaryDiscardCacheURL("legacy-unknown-update")
    )
    let baseTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await updateRuntime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-legacy-update-base",
        operations: TodoExample.upsertOperations(
          id: "todo-legacy-update",
          text: "server value",
          createdAt: baseTime,
          transactionID: "server-legacy-update-base"
        )
      )
    )
    try await updateRuntime.transact(
      InstantStoreTransaction(
        id: "tx-legacy-unknown-update",
        operations: TodoExample.updateTextOperations(
          id: "todo-legacy-update",
          text: "future unknown value",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 1_000_000),
          transactionID: "tx-legacy-unknown-update"
        )
      )
    )
    try await makeLegacyUnknownFailure(
      id: "tx-legacy-unknown-update",
      runtime: updateRuntime
    )

    // Server apply must proceed over a failed+unknown-overlay row so live
    // refresh cannot thrash the receive loop (#134 / recipes 773e50f4). Retry
    // and discard still refuse — those paths would guess at the local effect.
    _ = try await updateRuntime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-refresh-over-legacy-update",
        operations: TodoExample.updateTextOperations(
          id: "todo-legacy-update",
          text: "server refresh applies without guessing rollback",
          updatedAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2_000_000),
          transactionID: "server-refresh-over-legacy-update"
        )
      )
    )
    await expectUnknownStateFailure(id: "tx-legacy-unknown-update", operation: "discard") {
      _ = try await updateRuntime.discardFailedMutation(id: "tx-legacy-unknown-update")
    }
    await expectUnknownStateFailure(id: "tx-legacy-unknown-update", operation: "retry") {
      _ = try await updateRuntime.retryMutation(id: "tx-legacy-unknown-update")
    }
    let retainedUpdate = try await TodoExample.decode(updateRuntime.query(TodoExample.query))
    expectNoDifference(
      retainedUpdate.map(\.text),
      ["server refresh applies without guessing rollback"]
    )

    let deleteRuntime = try await discardRuntime(
      cacheURL: temporaryDiscardCacheURL("legacy-unknown-delete")
    )
    _ = try await deleteRuntime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-legacy-delete-base",
        operations: TodoExample.upsertOperations(
          id: "todo-legacy-delete",
          text: "must stay deleted while unknown",
          createdAt: baseTime,
          transactionID: "server-legacy-delete-base"
        )
      )
    )
    try await deleteRuntime.transact(
      InstantStoreTransaction(
        id: "tx-legacy-unknown-delete",
        operations: TodoExample.deleteOperations(id: "todo-legacy-delete")
      )
    )
    try await makeLegacyUnknownFailure(
      id: "tx-legacy-unknown-delete",
      runtime: deleteRuntime
    )

    // Authoritative server upsert is allowed; the failed+unknown row stays
    // retained and still blocks retry/discard (cannot invent a before-image).
    _ = try await deleteRuntime.applyServerTransaction(
      InstantStoreTransaction(
        id: "server-refresh-over-legacy-delete",
        operations: TodoExample.upsertOperations(
          id: "todo-legacy-delete",
          text: "server refresh re-asserts entity",
          createdAt: InstantTimestamp(milliseconds: baseTime.milliseconds + 2_000_000),
          transactionID: "server-refresh-over-legacy-delete"
        )
      )
    )
    await expectUnknownStateFailure(id: "tx-legacy-unknown-delete", operation: "discard") {
      _ = try await deleteRuntime.discardFailedMutation(id: "tx-legacy-unknown-delete")
    }
    await expectUnknownStateFailure(id: "tx-legacy-unknown-delete", operation: "retry") {
      _ = try await deleteRuntime.retryMutation(id: "tx-legacy-unknown-delete")
    }
    let retainedDelete = try await TodoExample.decode(deleteRuntime.query(TodoExample.query))
    expectNoDifference(retainedDelete.map(\.text), ["server refresh re-asserts entity"])
  }

  @Test
  func legacyPendingMutationWithoutRollbackOrStructuredFailureStillDecodes() throws {
    let legacy = PendingMutation(
      id: "tx-legacy-failure",
      createdAt: InstantTimestamp(milliseconds: 1_700_000_000_000),
      transaction: InstantStoreTransaction(id: "tx-legacy-failure", operations: []),
      status: .failed,
      failureMessage: "permission denied by legacy payload"
    )
    let encoded = try JSONEncoder().encode(legacy)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "rollbackTransaction")
    object.removeValue(forKey: "failure")
    object.removeValue(forKey: "optimisticOverlayState")
    object.removeValue(forKey: "serverTransactionID")

    let decoded = try JSONDecoder().decode(
      PendingMutation.self,
      from: JSONSerialization.data(withJSONObject: object)
    )

    expectNoDifference(decoded.id, "tx-legacy-failure")
    expectNoDifference(decoded.rollbackTransaction, nil)
    expectNoDifference(decoded.failure, nil)
    expectNoDifference(decoded.optimisticOverlayState, nil)
    expectNoDifference(
      decoded.rejectionError(operation: "decode legacy", recovery: "retry").code,
      .permissionRejected
    )
  }
}

private func makeLegacyUnknownFailure(
  id: String,
  runtime: InstantRuntime
) async throws {
  _ = try await runtime.migrateLocalPersistenceSnapshot(name: "legacy-unknown-\(id)") { snapshot in
    var snapshot = snapshot
    guard let index = snapshot.outbox.firstIndex(where: { $0.id == id }) else { return snapshot }
    snapshot.outbox[index].status = .failed
    snapshot.outbox[index].failureMessage = "legacy unknown failure"
    snapshot.outbox[index].rollbackTransaction = nil
    snapshot.outbox[index].optimisticOverlayState = nil
    return snapshot
  }
}

private func makeLegacyUnknownPending(
  id: String,
  runtime: InstantRuntime
) async throws {
  _ = try await runtime.migrateLocalPersistenceSnapshot(name: "legacy-unknown-pending-\(id)") {
    snapshot in
    var snapshot = snapshot
    guard let index = snapshot.outbox.firstIndex(where: { $0.id == id }) else { return snapshot }
    snapshot.outbox[index].status = .pending
    snapshot.outbox[index].failureMessage = nil
    snapshot.outbox[index].failure = nil
    snapshot.outbox[index].rollbackTransaction = nil
    snapshot.outbox[index].optimisticOverlayState = nil
    return snapshot
  }
}

private func markMutationFailedWithoutRemovingOverlay(
  id: String,
  runtime: InstantRuntime
) async throws {
  _ = try await runtime.migrateLocalPersistenceSnapshot(name: "failed-applied-overlay-\(id)") {
    snapshot in
    var snapshot = snapshot
    guard let index = snapshot.outbox.firstIndex(where: { $0.id == id }) else { return snapshot }
    snapshot.outbox[index].status = .failed
    snapshot.outbox[index].failureMessage = "legacy failed mutation with applied overlay"
    snapshot.outbox[index].failure = InstantMutationFailure(
      code: .permissionRejected,
      message: "legacy failed mutation with applied overlay"
    )
    return snapshot
  }
}

private func expectUnknownStateFailure(
  id: String,
  operation: String,
  body: () async throws -> Void
) async {
  do {
    try await body()
    Issue.record("Expected \(operation) to refuse legacy mutation '\(id)'.")
  } catch let error as InstantError {
    expectNoDifference(error.localID, id)
    expectNoDifference(error.localMutationDisposition, .retainedUnknown)
    #expect(error.message.contains("optimistic-overlay metadata"))
  } catch {
    Issue.record("Unexpected \(operation) error for '\(id)': \(error)")
  }
}

private func waitForDiscardMutation(
  id: String,
  status: InstantMutationStatus,
  runtime: InstantRuntime
) async throws -> PendingMutation {
  for _ in 0..<5_000 {
    let persisted = try await runtime.persistence.loadState().snapshot.outbox
    if let mutation = persisted.first(where: { $0.id == id }),
      mutation.status == status
    {
      return mutation
    }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw InstantError(
    code: .implementationFailed,
    operation: "wait for discard mutation status",
    localID: id,
    message: "The mutation did not reach status '\(status.rawValue)'.",
    recovery: "Inspect retry delivery and transact-ok handling."
  )
}

private func waitForServerAcceptedDiscardMutation(
  id: String,
  runtime: InstantRuntime
) async throws -> PendingMutation {
  for _ in 0..<5_000 {
    let persisted = try await runtime.persistence.loadState().snapshot.outbox
    if let mutation = persisted.first(where: { $0.id == id }),
      mutation.confirmationSource == .webSocketTransactOK,
      mutation.serverTransactionID != nil
    {
      return mutation
    }
    try await Task.sleep(for: .milliseconds(1))
  }
  throw InstantError(
    code: .implementationFailed,
    operation: "wait for server-accepted discard mutation",
    localID: id,
    message: "The mutation did not receive transact-ok proof.",
    recovery: "Inspect live mutation resend and transact-ok handling."
  )
}

private func expectDiscardFailure(
  id: String,
  runtime: InstantRuntime,
  message: String
) async {
  do {
    _ = try await runtime.discardFailedMutation(id: id)
    Issue.record("Expected discarding mutation '\(id)' to fail.")
  } catch let error as InstantError {
    expectNoDifference(error.code, .validationFailed)
    expectNoDifference(error.operation, "discard failed outbox mutation")
    expectNoDifference(error.localID, id)
    #expect(error.message.contains(message))
  } catch {
    Issue.record("Unexpected error: \(error)")
  }
}

private func enqueueDiscardMutation(
  id: String,
  runtime: InstantRuntime,
  offset: Int64
) async throws {
  let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000 + offset)
  try await runtime.transact(
    InstantStoreTransaction(
      id: id,
      operations: TodoExample.createOperations(
        id: "todo-\(id)",
        text: id,
        createdAt: createdAt,
        transactionID: id
      )
    ),
    createdAt: createdAt
  )
}

private func discardRuntime(
  cacheURL: URL,
  liveTransport: InstantLiveTransportClient? = nil,
  mutationTransport: InstantMutationTransportClient = .local
) async throws -> InstantRuntime {
  var configuration = InstantRuntimeConfiguration(
    appID: "failed-mutation-discard",
    persistenceURL: cacheURL,
    initialAttributes: TodoExample.attributes,
    mutationTransport: mutationTransport,
    liveTransport: liveTransport
  )
  configuration.autoConnectLiveTransport = false
  return try await InstantRuntime.bootstrap(configuration: configuration)
}

private func discardCascadeRuntime(cacheURL: URL) async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "failed-mutation-discard-cascade",
      persistenceURL: cacheURL,
      initialAttributes: [
        InstantAttribute(
          id: "posts/author",
          namespace: "posts",
          name: "author",
          valueType: .ref,
          isIndexed: true,
          forwardIdentity: "posts/author",
          reverseIdentity: "users/posts",
          linkNamespace: "users",
          onDelete: .cascade
        ),
        InstantAttribute(
          id: "posts/title",
          namespace: "posts",
          name: "title",
          valueType: .string
        ),
        InstantAttribute(
          id: "users/name",
          namespace: "users",
          name: "name",
          valueType: .string
        ),
      ]
    )
  )
}

private func temporaryDiscardCacheURL(_ suffix: String) -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(
    "instant-failed-mutation-discard-\(suffix)-\(UUID().uuidString).sqlite"
  )
}

private enum LocalConfirmationRoute: String, CaseIterable, Sendable {
  case manual
  case drain
  case localTransport

  var confirmationSource: InstantMutationConfirmationSource {
    switch self {
    case .manual:
      .manual
    case .drain:
      .localDrain
    case .localTransport:
      .localTransport
    }
  }
}

private enum CardinalityOneAcceptedWrite: String, CaseIterable, Sendable {
  case insert
  case retract
  case merge

  func operation(
    entityID: String,
    mutationID: String,
    authoritativeBase: InstantTriple
  ) -> InstantTripleOperation {
    switch self {
    case .insert:
      .insert(
        coverageJSONTriple(
          entityID: entityID,
          value: .object(["replacement": .string("accepted")]),
          transactionID: mutationID,
          milliseconds: 100
        )
      )
    case .retract:
      .retract(
        InstantTriple(
          entityID: authoritativeBase.entityID,
          attributeID: authoritativeBase.attributeID,
          value: authoritativeBase.value,
          txID: mutationID,
          txTime: InstantTimestamp(milliseconds: 100)
        )
      )
    case .merge:
      .merge(
        coverageJSONTriple(
          entityID: entityID,
          value: .object(["accepted": .bool(true)]),
          transactionID: mutationID,
          milliseconds: 100
        )
      )
    }
  }

  var expectedValue: JSONValue? {
    switch self {
    case .insert:
      .object(["replacement": .string("accepted")])
    case .retract:
      nil
    case .merge:
      .object([
        "accepted": .bool(true),
        "base": .string("server"),
      ])
    }
  }
}

private let manyTagsAttribute = InstantAttribute(
  id: "coverageRows/tags",
  namespace: "coverageRows",
  name: "tags",
  valueType: .string,
  cardinality: .many
)

private let jsonSettingsAttribute = InstantAttribute(
  id: "coverageRows/settings",
  namespace: "coverageRows",
  name: "settings",
  valueType: .json
)

private let deleteCoverageAttributes = [
  InstantAttribute(
    id: "coverageRows/title",
    namespace: "coverageRows",
    name: "title",
    valueType: .string
  ),
  InstantAttribute(
    id: "coverageRows/note",
    namespace: "coverageRows",
    name: "note",
    valueType: .string
  ),
]

private func serverAcceptedCoverageRuntime(
  cacheURL: URL,
  attributes: [InstantAttribute],
  acceptsTransport: Bool = false
) async throws -> InstantRuntime {
  let mutationTransport: InstantMutationTransportClient =
    acceptsTransport
    ? InstantMutationTransportClient { request in
      InstantMutationTransportResponse(
        results: request.mutations.map {
          InstantMutationTransportResult(
            mutationID: $0.mutationID,
            outcome: .confirmed,
            acceptance: .serverAccepted
          )
        }
      )
    }
    : .local
  return try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "server-accepted-write-coverage",
      persistenceURL: cacheURL,
      initialAttributes: attributes,
      mutationTransport: mutationTransport
    )
  )
}

private func coverageTriple(
  entityID: String,
  attributeID: String,
  value: String,
  transactionID: String,
  milliseconds: Int64
) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: attributeID,
    value: .string(value),
    txID: transactionID,
    txTime: InstantTimestamp(milliseconds: milliseconds)
  )
}

private func coverageTripleOperation(
  entityID: String,
  attributeID: String,
  value: String,
  transactionID: String,
  milliseconds: Int64
) -> InstantTripleOperation {
  .insert(
    coverageTriple(
      entityID: entityID,
      attributeID: attributeID,
      value: value,
      transactionID: transactionID,
      milliseconds: milliseconds
    )
  )
}

private func coverageJSONTriple(
  entityID: String,
  value: JSONValue,
  transactionID: String,
  milliseconds: Int64
) -> InstantTriple {
  InstantTriple(
    entityID: entityID,
    attributeID: jsonSettingsAttribute.id,
    value: .json(value),
    txID: transactionID,
    txTime: InstantTimestamp(milliseconds: milliseconds)
  )
}

private func coverageJSONValue(runtime: InstantRuntime, entityID: String) async throws -> JSONValue? {
  let state = try await runtime.persistence.loadState()
  for triple in state.snapshot.store.triples {
    guard triple.entityID == entityID,
      triple.attributeID == jsonSettingsAttribute.id,
      case let .json(value) = triple.value
    else { continue }
    return value
  }
  return nil
}

private func coverageStringValues(
  runtime: InstantRuntime,
  entityID: String,
  attributeID: String
) async throws -> [String] {
  try await runtime.persistence.loadState().snapshot.store.triples.compactMap { triple in
    guard triple.entityID == entityID,
      triple.attributeID == attributeID,
      case let .string(value) = triple.value
    else { return nil }
    return value
  }.sorted()
}

private func coverageEntityTriples(
  runtime: InstantRuntime,
  entityID: String
) async throws -> [InstantTriple] {
  try await runtime.persistence.loadState().snapshot.store.triples
    .filter { $0.entityID == entityID }
    .sorted { lhs, rhs in
      (lhs.attributeID, String(describing: lhs.value))
        < (rhs.attributeID, String(describing: rhs.value))
    }
}

private func installRetryMetadataDeletionFailure(in cacheURL: URL) throws {
  var database: OpaquePointer?
  guard sqlite3_open_v2(cacheURL.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
    defer { sqlite3_close(database) }
    throw NSError(
      domain: "InstantFailedMutationDiscardTests",
      code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Could not open the retry fault-injection database."]
    )
  }
  defer { sqlite3_close(database) }
  let sql =
    """
    CREATE TRIGGER instant_test_fail_retry_metadata_delete
    BEFORE DELETE ON instant_sync_metadata
    WHEN OLD.key = 'connection.last_error:failed-mutation-discard'
    BEGIN
      SELECT RAISE(ABORT, 'injected retry metadata deletion failure');
    END
    """
  var errorMessage: UnsafeMutablePointer<CChar>?
  guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
    let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite trigger error."
    sqlite3_free(errorMessage)
    throw NSError(
      domain: "InstantFailedMutationDiscardTests",
      code: 2,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }
}

private actor DiscardReconnectLiveSession {
  private struct SentWaiter {
    var count: Int
    var continuation: CheckedContinuation<Void, Never>
  }

  nonisolated private let abortState = InstantLiveTestWireAbortState()
  private var messages: [InstantLiveMessage] = []
  private var receiveContinuation: InstantLiveTestPendingOperation<InstantLiveMessage>?
  private var sent: [InstantLiveMessage] = []
  private var sentWaiters: [SentWaiter] = []
  private var isClosed = false

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in
      InstantLiveWebSocketSession(
        send: { message in try await self.send(message) },
        receive: {
          try self.abortState.check()
          return try await self.receive()
        },
        close: { await self.close() },
        abort: { self.abortState.abort() }
      )
    }
  }

  func sentMessages() -> [InstantLiveMessage] {
    sent
  }

  func waitForSentMessageCount(_ count: Int) async {
    guard sent.count < count else { return }
    await withCheckedContinuation { continuation in
      sentWaiters.append(SentWaiter(count: count, continuation: continuation))
    }
  }

  func acceptMutation(id: String, serverTransactionID: String) {
    enqueue(
      InstantLiveMessage(
        op: "transact-ok",
        clientEventID: id,
        fields: ["tx-id": .string(serverTransactionID)]
      )
    )
  }

  func rejectMutation(id: String, message: String) {
    enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: id,
        fields: [
          "message": .string(message),
          "original-event": .object([
            "client-event-id": .string(id),
            "op": .string("transact"),
          ]),
          "status": .number(403),
          "type": .string("permission-denied"),
        ]
      )
    )
  }

  private func send(_ message: InstantLiveMessage) throws {
    try abortState.check()
    sent.append(message)
    if message.op == "init" {
      enqueue(
        InstantLiveMessage(
          op: "init-ok",
          clientEventID: message.clientEventID,
          fields: [
            "attrs": .array([]),
            "auth": .null,
            "session-id": .string("discard-reconnect-session"),
          ]
        )
      )
    } else if message.op == "add-query" {
      enqueue(
        InstantLiveMessage(
          op: "add-query-ok",
          clientEventID: message.clientEventID,
          fields: [
            "q": message.fields["q"] ?? .object([:]),
            "result": .array([]),
          ]
        )
      )
    }
    var pending: [SentWaiter] = []
    for waiter in sentWaiters {
      if sent.count >= waiter.count {
        waiter.continuation.resume()
      } else {
        pending.append(waiter)
      }
    }
    sentWaiters = pending
  }

  private func enqueue(_ message: InstantLiveMessage) {
    guard !abortState.isAborted else { return }
    if let receiveContinuation {
      self.receiveContinuation = nil
      abortState.unregister(receiveContinuation.abortToken)
      receiveContinuation.continuation.resume(returning: message)
    } else if !isClosed {
      messages.append(message)
    }
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !messages.isEmpty {
      return messages.removeFirst()
    }
    if isClosed {
      throw CancellationError()
    }
    let id = UUID()
    defer { clearReceiveContinuation(id: id) }
    return try await withCheckedThrowingContinuation { continuation in
      let continuation = InstantLiveTestThrowingContinuationBox(continuation)
      guard
        let abortToken = abortState.register({
          continuation.resume(throwing: CancellationError())
        })
      else {
        continuation.resume(throwing: CancellationError())
        return
      }
      receiveContinuation = InstantLiveTestPendingOperation(
        id: id,
        abortToken: abortToken,
        continuation: continuation
      )
    }
  }

  private func close() {
    isClosed = true
    abortState.abort()
    receiveContinuation = nil
  }

  private func clearReceiveContinuation(id: UUID) {
    guard let receiveContinuation, receiveContinuation.id == id else { return }
    abortState.unregister(receiveContinuation.abortToken)
    self.receiveContinuation = nil
  }
}

private actor DiscardLifecycleRecorder {
  private(set) var labels: [String] = []

  func append(_ event: InstantMutationLifecycleEvent) {
    switch event {
    case .waiting:
      labels.append("waiting")
    case .serverAccepted(let mutation):
      labels.append("accepted:\(mutation.id)")
    case .failed(let mutation):
      labels.append("failed:\(mutation.id)")
    }
  }

  func waitForCount(_ count: Int) async throws {
    for _ in 0..<5_000 {
      if labels.count >= count {
        return
      }
      try await Task.sleep(for: .milliseconds(1))
    }
    throw InstantError(
      code: .implementationFailed,
      operation: "wait for discard lifecycle event",
      message: "The expected lifecycle event was not observed.",
      recovery: "Inspect the mutation lifecycle publication path."
    )
  }
}

private actor DiscardTodoEmissionRecorder {
  private(set) var values: [[String]] = []

  func append(_ value: [String]) {
    values.append(value)
  }

  func waitForCount(_ count: Int) async throws {
    for _ in 0..<5_000 {
      if values.count >= count {
        return
      }
      try await Task.sleep(for: .milliseconds(1))
    }
    throw InstantError(
      code: .implementationFailed,
      operation: "wait for discard query emission",
      message: "The expected query emission was not observed.",
      recovery: "Inspect rejected optimistic rollback publication."
    )
  }
}
