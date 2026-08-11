import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantInfiniteQueryParityTests {
  @Test
  func upstreamInfiniteQueryInitialSnapshotMatchesLiveSubscriptionData() async throws {
    let runtime = try await infiniteQueryRuntime()
    let plan = infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value"))
    let subscription = await runtime.subscribeInfiniteQuery(plan)
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([0, 1, 2, 3], prefix: "initial", in: runtime)
    let live = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(live), [0, 1, 2, 3], infiniteInitialSnapshotSource)

    let initialSnapshot = try await runtime.infiniteQueryInitialSnapshot(plan)
    expectNoDifference(loadedValues(initialSnapshot), loadedValues(live), infiniteInitialSnapshotSource)
    expectNoDifference(initialSnapshot.canLoadNextPage, false, infiniteInitialSnapshotSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryNoOrderFieldUsesImplicitStableOrder() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(infiniteItemsQuery(limit: 4, order: nil))
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([0, 1, 2, 3], prefix: "no-order", in: runtime)
    let snapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(snapshot), [0, 1, 2, 3], infiniteNoOrderSource)
    #expect(loadedValues(snapshot) != [3, 2, 10, 1, 2, 3])
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryAddingNewNumbersLoadsNextPageOnDemand() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([0, 1, 2, 3], prefix: "first", in: runtime)
    let firstPageSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(firstPageSnapshot), [0, 1, 2, 3], infiniteAddingNewNumbersSource)

    try await upsertNumberItems([5, 6, 7, 8], prefix: "second", in: runtime)
    let beforeLoad = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(beforeLoad), [0, 1, 2, 3], infiniteAddingNewNumbersSource)
    expectNoDifference(beforeLoad.canLoadNextPage, true, infiniteAddingNewNumbersSource)

    subscription.loadNextPage()
    let afterLoad = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(afterLoad), [0, 1, 2, 3, 5, 6, 7, 8], infiniteAddingNewNumbersSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryAddingNegativeNumbersPrependsLeadingRows() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([0, 1, 2, 3], prefix: "non-negative", in: runtime)
    let nonNegativeSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(nonNegativeSnapshot), [0, 1, 2, 3], infiniteNegativeNumbersSource)

    try await upsertNumberItems([-1], prefix: "negative-one", in: runtime)
    let negativeOneSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(negativeOneSnapshot), [-1, 0, 1, 2, 3], infiniteNegativeNumbersSource)

    try await upsertNumberItems([-4], prefix: "negative-four", in: runtime)
    let negativeFourSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(negativeFourSnapshot), [-4, -1, 0, 1, 2, 3], infiniteNegativeNumbersSource)

    try await upsertNumberItems([-2], prefix: "negative-two", in: runtime)
    let negativeTwoSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(negativeTwoSnapshot), [-4, -2, -1, 0, 1, 2, 3], infiniteNegativeNumbersSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryAddZeroTwiceKeepsDuplicateSortValues() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value", .descending))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberEntries(
      [("zero-a", 0), ("zero-b", 0)],
      transactionID: "tx-zero-twice",
      in: runtime
    )
    let duplicateZeroSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(duplicateZeroSnapshot), [0, 0], infiniteZeroTwiceSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryDescendingLoadsDuplicateLowerValues() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value", .descending))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([4, 5], prefix: "desc-top", in: runtime)
    let descendingTopSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(descendingTopSnapshot), [5, 4], infiniteDescendingSource)

    try await upsertNumberItems([1], prefix: "desc-one", in: runtime)
    let descendingOneSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(descendingOneSnapshot), [5, 4, 1], infiniteDescendingSource)

    try await upsertNumberEntries(
      [("desc-one-duplicate", 1), ("desc-two", 2), ("desc-three", 3)],
      transactionID: "tx-desc-more",
      in: runtime
    )
    let beforeLoad = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(beforeLoad), [5, 4, 3, 2], infiniteDescendingSource)
    expectNoDifference(beforeLoad.canLoadNextPage, true, infiniteDescendingSource)

    subscription.loadNextPage()
    let afterLoad = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(afterLoad), [5, 4, 3, 2, 1, 1], infiniteDescendingSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryDuplicateBoundaryValuesAcrossDescendingPages() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 3, order: InstantQueryOrder("value", .descending))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberEntries(
      [
        ("value-5", 5),
        ("value-4", 4),
        ("value-3", 3),
        ("value-2-a", 2),
        ("value-2-b", 2),
        ("value-2-c", 2),
        ("value-1", 1),
      ],
      transactionID: "tx-desc-boundary",
      in: runtime
    )
    let firstPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(firstPage), [5, 4, 3], infiniteDuplicateBoundarySource)
    expectNoDifference(firstPage.canLoadNextPage, true, infiniteDuplicateBoundarySource)

    subscription.loadNextPage()
    let secondPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(secondPage), [5, 4, 3, 2, 2, 2], infiniteDuplicateBoundarySource)
    expectNoDifference(secondPage.canLoadNextPage, true, infiniteDuplicateBoundarySource)

    subscription.loadNextPage()
    let finalPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(finalPage), [5, 4, 3, 2, 2, 2, 1], infiniteDuplicateBoundarySource)
    expectNoDifference(finalPage.canLoadNextPage, false, infiniteDuplicateBoundarySource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryLoadNextPageDoesNotDuplicatePages() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([1, 2, 3, 4, 5, 6], prefix: "rapid", in: runtime)
    let firstPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(firstPage), [1, 2], infiniteRapidLoadSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infiniteRapidLoadSource)

    subscription.loadNextPage()
    let secondPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(secondPage), [1, 2, 3, 4], infiniteRapidLoadSource)
    expectNoDifference(secondPage.canLoadNextPage, true, infiniteRapidLoadSource)
    subscription.unsubscribe()
  }

  @Test
  func windowRetentionKeepsOneHundredForwardLoadsToTwoPagesAndNavigatesBack() async throws {
    let runtime = try await infiniteQueryRuntime()
    let entries = Array(0...201).map { value in
      (id: "window-hundred-\(value)-\(value)", value: value)
    }
    for startIndex in stride(from: 0, to: entries.count, by: 100) {
      try await upsertNumberEntries(
        Array(entries[startIndex..<min(startIndex + 100, entries.count)]),
        transactionID: "tx-window-hundred-\(startIndex / 100)",
        in: runtime
      )
    }
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value")),
      retentionPolicy: .window(maximumPageCount: 2)
    )
    defer { subscription.unsubscribe() }
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    let firstPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(firstPage), [0, 1])
    expectNoDifference(firstPage.canLoadPreviousPage, false)
    expectNoDifference(firstPage.canLoadNextPage, true)

    var latest = firstPage
    for _ in 0..<100 {
      subscription.loadNextPage()
      latest = try #require(await snapshotPump.next())
      #expect(latest.values.count <= 4)
    }

    expectNoDifference(loadedValues(latest), [198, 199, 200, 201])
    expectNoDifference(latest.values.count, 4)
    expectNoDifference(latest.canLoadPreviousPage, true)
    expectNoDifference(latest.canLoadNextPage, false)
    expectNoDifference(latest.pageInfo?.hasPreviousPage, true)
    expectNoDifference(latest.pageInfo?.hasNextPage, false)
    expectNoDifference(latest.pageInfo?.startCursor?.entityID, "window-hundred-198-198")
    expectNoDifference(latest.pageInfo?.endCursor?.entityID, "window-hundred-201-201")

    subscription.loadPreviousPage()
    let previous = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(previous), [196, 197, 198, 199])
    expectNoDifference(previous.values.count, 4)
    expectNoDifference(previous.canLoadPreviousPage, true)
    expectNoDifference(previous.canLoadNextPage, true)
    expectNoDifference(previous.pageInfo?.hasPreviousPage, true)
    expectNoDifference(previous.pageInfo?.hasNextPage, true)
    expectNoDifference(previous.pageInfo?.startCursor?.entityID, "window-hundred-196-196")
    expectNoDifference(previous.pageInfo?.endCursor?.entityID, "window-hundred-199-199")
  }

  @Test
  func windowRetentionStaysCappedAcrossLocalPrependAndReorder() async throws {
    let runtime = try await infiniteQueryRuntime()
    let initialTimestamp = InstantTimestamp(milliseconds: 1_767_225_600_000)
    try await upsertNumberEntries(
      Array(0...7).enumerated().map { offset, value in
        ("window-local-\(offset)-\(value)", value)
      },
      transactionID: "tx-window-local-initial",
      timestamp: initialTimestamp,
      in: runtime
    )
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value")),
      retentionPolicy: .window(maximumPageCount: 2)
    )
    defer { subscription.unsubscribe() }
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(
      await snapshotPump.next(operation: "receive initial retained window")
    )
    subscription.loadNextPage()
    _ = try #require(
      await snapshotPump.next(operation: "receive first retained-window advance")
    )
    subscription.loadNextPage()
    let advanced = try #require(
      await snapshotPump.next(operation: "receive second retained-window advance")
    )
    expectNoDifference(loadedValues(advanced), [2, 3, 4, 5])

    try await upsertNumberEntries(
      [("window-local-prepend", -1)],
      transactionID: "tx-window-local-prepend",
      timestamp: InstantTimestamp(milliseconds: initialTimestamp.milliseconds + 1),
      in: runtime
    )
    let prepended = try #require(
      await snapshotPump.next(operation: "receive out-of-window local prepend")
    )
    expectNoDifference(loadedValues(prepended), [2, 3, 4, 5])
    expectNoDifference(prepended.values.count, 4)
    expectNoDifference(prepended.canLoadPreviousPage, true)

    try await upsertNumberEntries(
      [("window-local-7-7", 3)],
      transactionID: "tx-window-local-reorder",
      timestamp: InstantTimestamp(milliseconds: initialTimestamp.milliseconds + 2),
      in: runtime
    )
    let reordered = try #require(
      await snapshotPump.next(operation: "receive monotonic local reorder")
    )
    expectNoDifference(loadedValues(reordered), [2, 3, 3, 4])
    expectNoDifference(reordered.values.count, 4)
    expectNoDifference(reordered.canLoadPreviousPage, true)
    expectNoDifference(reordered.canLoadNextPage, true)
  }

  @Test
  func liveRetirementSlotCoalescesTenThousandReplacementsAndRejectsStaleCompletion()
    async throws
  {
    let retiredBarrier = InfiniteQuerySetupBarrier()
    let cleanupBarrier = InfiniteQuerySetupBarrier()
    let watchdogBarrier = InfiniteQuerySetupBarrier()
    let retiredTask = Task { await retiredBarrier.pause() }
    let cleanupTask = Task { await cleanupBarrier.pause() }
    let watchdogTask = Task { await watchdogBarrier.pause() }
    defer {
      Task {
        await retiredBarrier.release()
        await cleanupBarrier.release()
        await watchdogBarrier.release()
      }
      retiredTask.cancel()
      cleanupTask.cancel()
      watchdogTask.cancel()
    }
    try await waitForInfiniteSetupBarrier(
      retiredBarrier,
      operation: "own the retired live infinite-query subscription task"
    )
    try await waitForInfiniteSetupBarrier(
      cleanupBarrier,
      operation: "own the stalled live infinite-query retirement cleanup task"
    )
    try await waitForInfiniteSetupBarrier(
      watchdogBarrier,
      operation: "own the live infinite-query retirement watchdog task"
    )

    var retirement = InstantLiveInfiniteSubscriptionRetirementSlot<Int>(
      retiredSubscriptionID: 41,
      retiredTask: retiredTask,
      cleanupTask: cleanupTask,
      watchdogTask: watchdogTask,
      pendingReplacement: 0
    )
    for generation in 1...10_000 {
      retirement.coalesce(generation)
    }
    expectNoDifference(retirement.retiredSubscriptionID, 41)
    expectNoDifference(retirement.pendingReplacement, 10_000)
    expectNoDifference(retirement.ownedTaskCount, 3)

    retirement.markTimedOut()
    expectNoDifference(retirement.pendingReplacement, nil)
    expectNoDifference(retirement.ownedTaskCount, 2)
    expectNoDifference(retirement.didTimeOut, true)

    var retirements = ["forward": retirement]
    let staleRetiredSubscriptionID = 41
    retirements["forward"] = InstantLiveInfiniteSubscriptionRetirementSlot<Int>(
      retiredSubscriptionID: 42,
      retiredTask: retiredTask,
      cleanupTask: cleanupTask,
      watchdogTask: nil,
      pendingReplacement: 10_001
    )
    if retirements["forward"]?.retiredSubscriptionID == staleRetiredSubscriptionID {
      retirements["forward"] = nil
    }
    expectNoDifference(retirements["forward"]?.retiredSubscriptionID, 42)
    expectNoDifference(retirements["forward"]?.pendingReplacement, 10_001)

    await retiredBarrier.release()
    await cleanupBarrier.release()
    await watchdogBarrier.release()
    await retiredTask.value
    await cleanupTask.value
    await watchdogTask.value
  }

  @Test
  func localPublishRejectsStaleSameSequenceHydrationGeneration() async throws {
    let plan = infiniteItemsQuery(limit: 1, order: InstantQueryOrder("value"))
    let emission = InstantQueryEmission(
      queryID: plan.id,
      sequence: 7,
      values: [
        InstantEntitySnapshot(
          id: "same-sequence-generation",
          namespace: "items",
          values: ["value": .one(.number(1))]
        )
      ]
    )
    let coordinator = InstantInfiniteQueryCoordinator(
      plan: plan,
      retentionPolicy: .accumulated
    )
    let olderRequest = try #require(await coordinator.hydrationRequest(for: emission))
    let olderSnapshot = try #require(
      await coordinator.finishHydration(olderRequest, with: olderRequest.snapshot)
    )
    let newerRequest = try #require(await coordinator.hydrationRequest(for: emission))
    let output = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )

    #expect(
      await coordinator.publish(
        olderSnapshot,
        for: olderRequest,
        to: output.continuation
      ) == false
    )
    let staleResidency = await coordinator.residencySnapshot()
    expectNoDifference(staleResidency.publishedSnapshotCount, 0)

    let newerSnapshot = try #require(
      await coordinator.finishHydration(newerRequest, with: newerRequest.snapshot)
    )
    #expect(
      await coordinator.publish(
        newerSnapshot,
        for: newerRequest,
        to: output.continuation
      )
    )
    let accepted = try #require(
      await nextInfiniteSnapshot(
        operation: "receive only the current same-sequence hydration generation",
        in: output.stream
      )
    )
    expectNoDifference(accepted.sequence, 7)
    let acceptedResidency = await coordinator.residencySnapshot()
    expectNoDifference(acceptedResidency.publishedSnapshotCount, 1)
    await coordinator.cancel()
  }

  @Test
  func terminalCleanupReleasesTenThousandRowLocalGraphAfterFailureAndCancellation() async throws {
    let plan = infiniteItemsQuery(limit: 25, order: InstantQueryOrder("value"))
    let values = (0..<10_000).map { value in
      InstantEntitySnapshot(
        id: "terminal-residency-\(value)",
        namespace: "items",
        values: ["value": .one(.number(Double(value)))]
      )
    }
    let emission = InstantQueryEmission(
      queryID: plan.id,
      sequence: 47,
      values: values
    )
    let terminalError = InstantError(
      code: .decodeFailed,
      operation: "hydrate deferred infinite-query values",
      namespace: "items",
      message: "The terminal-residency fixture failed hydration.",
      recovery: "Release the retained query graph after publishing this failure."
    )

    let failingCoordinator = InstantInfiniteQueryCoordinator(
      plan: plan,
      retentionPolicy: .accumulated
    )
    let failureRequest = try #require(
      await failingCoordinator.hydrationRequest(for: emission)
    )
    let failureSnapshot = try #require(
      await failingCoordinator.finishHydration(
        failureRequest,
        with: failureRequest.snapshot
      )
    )
    let failureOutput = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    #expect(
      await failingCoordinator.publish(
        failureSnapshot,
        for: failureRequest,
        to: failureOutput.continuation
      )
    )
    let failingResidencyBeforeTermination = await failingCoordinator.residencySnapshot()
    expectNoDifference(
      failingResidencyBeforeTermination,
      InstantInfiniteQueryResidencySnapshot(
        latestEmissionValueCount: 10_000,
        hydratedEntityCount: 25,
        navigationReferenceCount: 1,
        publishedSnapshotCount: 1
      )
    )

    let failure = try #require(await failingCoordinator.fail(with: terminalError))
    expectNoDifference(failure.sequence, 47)
    expectNoDifference(failure.values, [])
    expectNoDifference(failure.canLoadPreviousPage, false)
    expectNoDifference(failure.canLoadNextPage, false)
    expectNoDifference(failure.error, terminalError)
    let failingResidencyAfterTermination = await failingCoordinator.residencySnapshot()
    expectNoDifference(
      failingResidencyAfterTermination,
      InstantInfiniteQueryResidencySnapshot()
    )

    let cancellingCoordinator = InstantInfiniteQueryCoordinator(
      plan: plan,
      retentionPolicy: .accumulated
    )
    let cancellationRequest = try #require(
      await cancellingCoordinator.hydrationRequest(for: emission)
    )
    let cancellationSnapshot = try #require(
      await cancellingCoordinator.finishHydration(
        cancellationRequest,
        with: cancellationRequest.snapshot
      )
    )
    let cancellationOutput = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    #expect(
      await cancellingCoordinator.publish(
        cancellationSnapshot,
        for: cancellationRequest,
        to: cancellationOutput.continuation
      )
    )
    let cancellingResidencyBeforeTermination =
      await cancellingCoordinator.residencySnapshot()
    expectNoDifference(
      cancellingResidencyBeforeTermination,
      InstantInfiniteQueryResidencySnapshot(
        latestEmissionValueCount: 10_000,
        hydratedEntityCount: 25,
        navigationReferenceCount: 1,
        publishedSnapshotCount: 1
      )
    )

    let cancellation = try #require(
      await cancellingCoordinator.cancelAndMakeTerminalSnapshot()
    )
    expectNoDifference(cancellation.sequence, 47)
    expectNoDifference(cancellation.values, [])
    expectNoDifference(cancellation.canLoadPreviousPage, false)
    expectNoDifference(cancellation.canLoadNextPage, false)
    expectNoDifference(cancellation.error, nil)
    let cancellingResidencyAfterTermination =
      await cancellingCoordinator.residencySnapshot()
    expectNoDifference(
      cancellingResidencyAfterTermination,
      InstantInfiniteQueryResidencySnapshot()
    )
  }

  @Test
  func unsubscribeEvictsUnconsumedTenThousandRowSnapshotBuffer() async throws {
    let cleanupBarrier = InfiniteQuerySetupBarrier()
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-local-terminal-before-cleanup",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() }
    )
    configuration.onLocalInfiniteQueryTerminalPublishedBeforeObservationCleanupForTesting = {
      await cleanupBarrier.pause()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await seedInfiniteQueryStore(rowCount: 10_000, in: runtime)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 10_000, order: InstantQueryOrder("value"))
    )
    defer {
      Task { await cleanupBarrier.release() }
      subscription.unsubscribe()
    }

    let resident = try await waitForInfiniteResidency(
      in: subscription,
      operation: "buffer an unconsumed ten-thousand-row infinite-query snapshot"
    ) { residency in
      residency.latestEmissionValueCount == 10_000
        && residency.hydratedEntityCount == 10_000
        && residency.ownedTaskCount == 1
        && residency.publishedSnapshotCount == 1
    }
    expectNoDifference(resident.latestEmissionValueCount, 10_000)
    expectNoDifference(resident.hydratedEntityCount, 10_000)

    subscription.unsubscribe()
    try await waitForInfiniteSetupBarrier(
      cleanupBarrier,
      operation: "publish the empty terminal snapshot before local observer cleanup"
    )
    let observationCountWhileCleanupIsBlocked = await runtime.store.activeObservationCount()
    expectNoDifference(observationCountWhileCleanupIsBlocked, 1)

    let terminal = try #require(
      await nextInfiniteSnapshot(
        operation: "receive the clean terminal snapshot that evicts the buffered payload",
        in: subscription.snapshots
      )
    )
    expectNoDifference(terminal.sequence, 1)
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.canLoadPreviousPage, false)
    expectNoDifference(terminal.canLoadNextPage, false)
    expectNoDifference(terminal.error, nil)
    #expect(
      try await nextInfiniteSnapshot(
        operation: "finish the clean terminal infinite-query stream",
        in: subscription.snapshots
      ) == nil
    )
    let payloadResidencyWhileCleanupIsBlocked =
      await subscription.residencySnapshotForTesting()
    expectNoDifference(payloadResidencyWhileCleanupIsBlocked.latestEmissionValueCount, 0)
    expectNoDifference(payloadResidencyWhileCleanupIsBlocked.hydratedEntityCount, 0)
    expectNoDifference(payloadResidencyWhileCleanupIsBlocked.navigationReferenceCount, 0)
    expectNoDifference(payloadResidencyWhileCleanupIsBlocked.inFlightPayloadValueCount, 0)
    expectNoDifference(payloadResidencyWhileCleanupIsBlocked.ownedTaskCount, 1)
    expectNoDifference(payloadResidencyWhileCleanupIsBlocked.publishedSnapshotCount, 0)

    await cleanupBarrier.release()
    let terminalResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "release the unconsumed ten-thousand-row infinite-query buffer"
    ) { $0 == InstantInfiniteQueryResidencySnapshot() }
    expectNoDifference(terminalResidency, InstantInfiniteQueryResidencySnapshot())
    let finalObservationCount = try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(finalObservationCount, 0)
  }

  @Test
  func terminalSequenceIgnoresBlockedNewerLocalHydration() async throws {
    let hydrationBarrier = InfiniteQueryPayloadBarrier()
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-local-terminal-last-published-sequence",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() }
    )
    configuration.onLocalInfiniteQueryHydrationRequestAcquiredForTesting = {
      sequence,
      valueCount in
      guard sequence == 2 else { return }
      try await hydrationBarrier.pause(payloadCount: valueCount)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await seedInfiniteQueryStore(rowCount: 2, in: runtime)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    defer {
      hydrationBarrier.release()
      subscription.unsubscribe()
    }
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    let published = try #require(
      await snapshotPump.next(operation: "publish the first local infinite-query sequence")
    )
    expectNoDifference(published.sequence, 1)
    expectNoDifference(loadedValues(published), [0, 1])

    try await upsertNumberEntries(
      [("seeded-infinite-item-0", 42)],
      transactionID: "tx-block-newer-local-infinite-hydration",
      in: runtime
    )
    let blockedValueCount = try await waitForInfinitePayloadBarrier(
      hydrationBarrier,
      operation: "block the newer local hydration after acquiring its payload"
    )
    expectNoDifference(blockedValueCount, 2)

    subscription.unsubscribe()
    let terminal = try #require(
      await snapshotPump.next(
        operation: "report the last published sequence while newer hydration is blocked"
      )
    )
    expectNoDifference(terminal.sequence, 1)
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.canLoadPreviousPage, false)
    expectNoDifference(terminal.canLoadNextPage, false)
    expectNoDifference(terminal.error, nil)
    #expect(
      try await snapshotPump.next(
        operation: "finish after ignoring the blocked unpublished local sequence"
      ) == nil
    )
    expectNoDifference(hydrationBarrier.isReleased, false)

    hydrationBarrier.release()
    let terminalResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "release the blocked unpublished local hydration"
    ) { $0 == InstantInfiniteQueryResidencySnapshot() }
    expectNoDifference(terminalResidency, .init())
    let finalObservationCount = try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(finalObservationCount, 0)
  }

  @Test
  func livePreBootstrapCancellationReleasesBlockedTenThousandRowExpansion() async throws {
    let barrier = InfiniteQueryPayloadBarrier()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-blocked-prebootstrap-retention",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.onLiveInfiniteQueryPreBootstrapPayloadAcquiredForTesting = { valueCount in
      try await barrier.pause(payloadCount: valueCount)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await seedInfiniteQueryStore(rowCount: 10_000, in: runtime)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 5_000, order: InstantQueryOrder("value"))
    )
    defer {
      barrier.release()
      subscription.unsubscribe()
    }
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    let firstPage = try #require(
      await snapshotPump.next(operation: "receive the five-thousand-row live starter page")
    )
    expectNoDifference(firstPage.values.count, 5_000)
    expectNoDifference(firstPage.canLoadNextPage, true)

    subscription.loadNextPage()
    let blockedLivePayloadCount = try await waitForInfinitePayloadBarrier(
      barrier,
      operation: "block after acquiring the ten-thousand-row live expansion payload"
    )
    expectNoDifference(blockedLivePayloadCount, 10_000)
    subscription.unsubscribe()

    let terminal = try #require(
      await snapshotPump.next(operation: "receive the live expansion cancellation snapshot")
    )
    expectNoDifference(terminal.sequence, 1)
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.error, nil)
    let canceledLiveResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "cancel the blocked live expansion and release its payload"
    ) { $0 == InstantInfiniteQueryResidencySnapshot() }
    expectNoDifference(canceledLiveResidency, InstantInfiniteQueryResidencySnapshot())
    expectNoDifference(barrier.isReleased, false)

    barrier.release()
    await Task.yield()
    let releasedLiveResidency = await subscription.residencySnapshotForTesting()
    expectNoDifference(releasedLiveResidency, .init())
    #expect(
      try await snapshotPump.next(operation: "prove no late live expansion repopulation") == nil
    )
    let finalObservationCount = try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(finalObservationCount, 0)
    _ = try await runtime.closeConnection()
  }

  @Test
  func localNavigationCancellationReleasesBlockedTenThousandRowRequest() async throws {
    let barrier = InfiniteQueryPayloadBarrier()
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-local-blocked-navigation-retention",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() }
    )
    configuration.onLocalInfiniteQueryNavigationRequestAcquiredForTesting = { valueCount in
      try await barrier.pause(payloadCount: valueCount)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await seedInfiniteQueryStore(rowCount: 10_000, in: runtime)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 5_000, order: InstantQueryOrder("value"))
    )
    defer {
      barrier.release()
      subscription.unsubscribe()
    }
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    let firstPage = try #require(
      await snapshotPump.next(operation: "receive the five-thousand-row local first page")
    )
    expectNoDifference(firstPage.values.count, 5_000)
    expectNoDifference(firstPage.canLoadNextPage, true)

    subscription.loadNextPage()
    for navigationIndex in 0..<9_999 {
      if navigationIndex.isMultiple(of: 2) {
        subscription.loadPreviousPage()
      } else {
        subscription.loadNextPage()
      }
    }
    let blockedLocalPayloadCount = try await waitForInfinitePayloadBarrier(
      barrier,
      operation: "block after acquiring the ten-thousand-row local navigation request"
    )
    expectNoDifference(blockedLocalPayloadCount, 10_000)
    let boundedNavigationResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "coalesce ten thousand blocked local navigation calls into one task and one scalar"
    ) { residency in
      residency.ownedTaskCount == 2
        && residency.navigationReferenceCount == 2
    }
    expectNoDifference(boundedNavigationResidency.ownedTaskCount, 2)
    expectNoDifference(boundedNavigationResidency.navigationReferenceCount, 2)
    subscription.unsubscribe()

    let terminal = try #require(
      await snapshotPump.next(operation: "receive the local navigation cancellation snapshot")
    )
    expectNoDifference(terminal.sequence, 1)
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.error, nil)
    let canceledLocalResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "cancel the blocked local navigation request and release its payload"
    ) { $0 == InstantInfiniteQueryResidencySnapshot() }
    expectNoDifference(canceledLocalResidency, InstantInfiniteQueryResidencySnapshot())
    expectNoDifference(barrier.isReleased, false)

    barrier.release()
    await Task.yield()
    let releasedLocalResidency = await subscription.residencySnapshotForTesting()
    expectNoDifference(releasedLocalResidency, .init())
    #expect(
      try await snapshotPump.next(operation: "prove no late local navigation repopulation") == nil
    )
    let finalObservationCount = try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(finalObservationCount, 0)
  }

  @Test
  func localInfiniteCleanupJoinsBlockedPrimaryTaskAfterImmediateTerminalPublication() async throws {
    let primaryBarrier = InfiniteQuerySetupBarrier()
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-local-exact-primary-cleanup",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() }
    )
    configuration.onLocalInfiniteQueryHydrationRequestAcquiredForTesting = { _, _ in
      await primaryBarrier.pause()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await seedInfiniteQueryStore(rowCount: 4, in: runtime)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    let cleanupCompletion = InfiniteQuerySetupCleanupProbe()
    var cleanupWaiter: Task<Void, Never>?
    defer {
      Task { await primaryBarrier.release() }
      cleanupWaiter?.cancel()
      subscription.unsubscribe()
    }
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    try await waitForInfiniteSetupBarrier(
      primaryBarrier,
      operation: "block the local infinite-query primary task"
    )
    subscription.unsubscribe()
    cleanupWaiter = Task {
      await subscription.unsubscribeAndWait()
      await cleanupCompletion.record()
    }

    let terminal = try #require(
      await snapshotPump.next(
        operation: "publish the local terminal snapshot before joining the blocked primary task"
      )
    )
    expectNoDifference(terminal.sequence, 0)
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.error, nil)
    #expect(
      try await snapshotPump.next(
        operation: "finish before the blocked local primary task releases"
      ) == nil
    )

    let cleanupPending = try await waitForInfiniteResidency(
      in: subscription,
      operation: "keep exact local primary cleanup owned while its task is blocked"
    ) { residency in
      residency.ownedTaskCount == 1
        && residency.latestEmissionValueCount == 0
        && residency.hydratedEntityCount == 0
    }
    expectNoDifference(cleanupPending.ownedTaskCount, 1)
    let observationCountDuringJoin = try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(observationCountDuringJoin, 0)
    let completionCountDuringJoin = await cleanupCompletion.count
    expectNoDifference(completionCountDuringJoin, 0)

    await primaryBarrier.release()
    if let cleanupWaiter {
      try await instantLiveWithTimeout(
        operation: "finish the exact local primary cleanup waiter",
        timeoutMilliseconds: 5_000
      ) {
        await cleanupWaiter.value
      }
    }
    let completionCountAfterJoin = await cleanupCompletion.count
    expectNoDifference(completionCountAfterJoin, 1)
    let released = try await waitForInfiniteResidency(
      in: subscription,
      operation: "join the released local primary task and exact Store lease"
    ) { $0 == InstantInfiniteQueryResidencySnapshot() }
    expectNoDifference(released, .init())
  }

  @Test
  func localInfiniteCleanupJoinsBlockedNavigationTaskWithoutLateNavigation() async throws {
    let navigationBarrier = InfiniteQuerySetupBarrier()
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-local-exact-navigation-cleanup",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() }
    )
    configuration.onLocalInfiniteQueryNavigationRequestAcquiredForTesting = { _ in
      await navigationBarrier.pause()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await seedInfiniteQueryStore(rowCount: 4, in: runtime)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    let cleanupCompletion = InfiniteQuerySetupCleanupProbe()
    var cleanupWaiter: Task<Void, Never>?
    defer {
      Task { await navigationBarrier.release() }
      cleanupWaiter?.cancel()
      subscription.unsubscribe()
    }
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)
    let first = try #require(
      await snapshotPump.next(operation: "publish the local first page before navigation")
    )
    expectNoDifference(loadedValues(first), [0, 1])

    subscription.loadNextPage()
    try await waitForInfiniteSetupBarrier(
      navigationBarrier,
      operation: "block the local infinite-query navigation task"
    )
    subscription.unsubscribe()
    cleanupWaiter = Task {
      await subscription.unsubscribeAndWait()
      await cleanupCompletion.record()
    }

    let terminal = try #require(
      await snapshotPump.next(
        operation: "publish the local terminal snapshot before joining blocked navigation"
      )
    )
    expectNoDifference(terminal.sequence, first.sequence)
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.error, nil)
    let cleanupPending = try await waitForInfiniteResidency(
      in: subscription,
      operation: "keep exact local navigation cleanup owned while its task is blocked"
    ) { residency in
      residency.ownedTaskCount == 1
        && residency.navigationReferenceCount == 0
    }
    expectNoDifference(cleanupPending.ownedTaskCount, 1)
    let observationCountDuringJoin = try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(observationCountDuringJoin, 0)
    let completionCountDuringJoin = await cleanupCompletion.count
    expectNoDifference(completionCountDuringJoin, 0)

    for _ in 0..<100 {
      subscription.loadNextPage()
      subscription.loadPreviousPage()
    }
    await navigationBarrier.release()
    if let cleanupWaiter {
      try await instantLiveWithTimeout(
        operation: "finish the exact local navigation cleanup waiter",
        timeoutMilliseconds: 5_000
      ) {
        await cleanupWaiter.value
      }
    }
    let completionCountAfterJoin = await cleanupCompletion.count
    expectNoDifference(completionCountAfterJoin, 1)
    let released = try await waitForInfiniteResidency(
      in: subscription,
      operation: "join the released local navigation task and reject late navigation"
    ) { $0 == InstantInfiniteQueryResidencySnapshot() }
    expectNoDifference(released, .init())
    #expect(
      try await snapshotPump.next(
        operation: "prove blocked navigation cannot publish after exact cleanup"
      ) == nil
    )
  }

  @Test
  func liveInfiniteCommandOwnerCoalescesTenThousandCallsAndPrioritizesTerminalCleanup() async throws {
    let navigationBarrier = InfiniteQuerySetupBarrier()
    let probe = InfiniteQueryCommandProbe(navigationBarrier: navigationBarrier)
    let owner = InstantInfiniteQueryCommandOwner(
      loadNextPage: { await probe.navigate("next") },
      loadPreviousPage: { await probe.navigate("previous") },
      cancel: { await probe.cancel() }
    )

    owner.loadNextPage()
    try await waitForInfiniteSetupBarrier(
      navigationBarrier,
      operation: "block the reusable live infinite-query command runner"
    )
    for index in 1..<10_000 {
      if index.isMultiple(of: 2) {
        owner.loadNextPage()
      } else {
        owner.loadPreviousPage()
      }
    }
    let bounded = owner.residencySnapshotForTesting()
    expectNoDifference(bounded.runnerTaskCount, 1)
    expectNoDifference(bounded.terminalTaskCount, 0)
    expectNoDifference(bounded.pendingNavigationCount, 1)
    expectNoDifference(bounded.hasResources, true)
    expectNoDifference(bounded.isTerminalRequested, false)

    owner.cancel()
    owner.cancel()
    for _ in 0..<10_000 {
      owner.loadNextPage()
      owner.loadPreviousPage()
    }
    let terminalPending = owner.residencySnapshotForTesting()
    expectNoDifference(terminalPending.runnerTaskCount, 1)
    expectNoDifference(terminalPending.terminalTaskCount, 1)
    expectNoDifference(terminalPending.pendingNavigationCount, 0)
    expectNoDifference(terminalPending.hasResources, true)
    expectNoDifference(terminalPending.isTerminalRequested, true)

    await navigationBarrier.release()
    try await instantLiveWithTimeout(
      operation: "finish the one exact live infinite-query command cleanup task",
      timeoutMilliseconds: 5_000
    ) {
      await owner.cancelAndWait()
      await owner.cancelAndWait()
    }
    let state = await probe.state()
    expectNoDifference(state.navigation, ["next"])
    expectNoDifference(state.cancelCount, 1)
    expectNoDifference(state.cancelWasAlreadyCancelled, false)
    expectNoDifference(
      owner.residencySnapshotForTesting(),
      InstantInfiniteQueryCommandResidencySnapshot(isTerminalRequested: true)
    )
  }

  @Test
  func liveInfiniteTerminalCleanupCanReleaseBlockedNavigationBeforeJoiningRunner() async throws {
    let navigationBarrier = InfiniteQuerySetupBarrier()
    let probe = InfiniteQueryCancellationUnblockProbe(navigationBarrier: navigationBarrier)
    let owner = InstantInfiniteQueryCommandOwner(
      loadNextPage: { await probe.navigate() },
      cancel: { await probe.cancel() }
    )
    defer {
      Task { await navigationBarrier.release() }
      owner.cancel()
    }

    owner.loadNextPage()
    try await waitForInfiniteSetupBarrier(
      navigationBarrier,
      operation: "block navigation until infinite-query cleanup releases its source"
    )

    try await instantLiveWithTimeout(
      operation: "run infinite-query cleanup before joining its blocked navigation runner",
      timeoutMilliseconds: 5_000
    ) {
      await owner.cancelAndWait()
    }

    let state = await probe.state()
    expectNoDifference(state.navigationCount, 1)
    expectNoDifference(state.cancelCount, 1)
    expectNoDifference(state.cancelWasAlreadyCancelled, false)
    expectNoDifference(
      owner.residencySnapshotForTesting(),
      InstantInfiniteQueryCommandResidencySnapshot(isTerminalRequested: true)
    )
  }

  @Test
  func retainedCanceledRawInfiniteHandleReleasesCoordinatorAndRuntime() async throws {
    let fixture = try await makeRetainedRawInfiniteQueryLifetimeFixture()
    #expect(!fixture.runtime.isReleased)
    fixture.subscription.unsubscribe()
    try await instantLiveWithTimeout(
      operation: "finish exact raw infinite-query handle cleanup",
      timeoutMilliseconds: 5_000
    ) {
      await fixture.subscription.unsubscribeAndWait()
      await fixture.subscription.unsubscribeAndWait()
    }

    #expect(fixture.runtime.isReleased)
    withExtendedLifetime(fixture.subscription) {}
  }

  @Test
  func upstreamInfiniteQueryDeletingLoadedItemKeepsNextPageClosed() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 4, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([1, 2, 3, 4, 5, 6], prefix: "delete", in: runtime)
    let firstPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(firstPage), [1, 2, 3, 4], infiniteDeletingSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infiniteDeletingSource)

    subscription.loadNextPage()
    let loaded = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(loaded), [1, 2, 3, 4, 5, 6], infiniteDeletingSource)
    expectNoDifference(loaded.canLoadNextPage, false, infiniteDeletingSource)

    try await deleteNumberItem("delete-2-3", transactionID: "tx-delete-three", in: runtime)
    let deleted = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(deleted), [1, 2, 4, 5, 6], infiniteDeletingSource)
    expectNoDifference(deleted.canLoadNextPage, false, infiniteDeletingSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryUpdatingOutOfWindowItemReordersIntoVisibleChunk() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 3, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([10, 20, 30, 40, 50, 60], prefix: "update", in: runtime)
    _ = try #require(await snapshotPump.next())

    try await upsertNumberEntries(
      [("update-5-60", 15)],
      transactionID: "tx-update-sixty-to-fifteen",
      timestamp: InstantTimestamp(milliseconds: 1_767_226_600_000),
      in: runtime
    )
    let current = try await runtime.query(
      infiniteItemsQuery(limit: 10, order: InstantQueryOrder("value"))
    )
    expectNoDifference(
      current.compactMap { entity in
        guard case .one(.number(let value)) = entity.values["value"] else { return nil }
        return Int(value)
      },
      [10, 15, 20, 30, 40, 50],
      infiniteUpdateSource
    )
    let reordered = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(reordered), [10, 15, 20], infiniteUpdateSource)
    expectNoDifference(reordered.canLoadNextPage, true, infiniteUpdateSource)

    subscription.loadNextPage()
    let loaded = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(loaded), [10, 15, 20, 30, 40, 50], infiniteUpdateSource)
    expectNoDifference(loaded.canLoadNextPage, false, infiniteUpdateSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryPageSizeOneAscending() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 1, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([0, 1], prefix: "page-one-asc", in: runtime)
    let firstPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(firstPage), [0], infinitePageOneAscendingSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infinitePageOneAscendingSource)

    subscription.loadNextPage()
    let secondPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(secondPage), [0, 1], infinitePageOneAscendingSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryPageSizeOneDescending() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 1, order: InstantQueryOrder("value", .descending))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    try await upsertNumberItems([0, -1], prefix: "page-one-desc", in: runtime)
    let firstPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(firstPage), [0], infinitePageOneDescendingSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infinitePageOneDescendingSource)

    subscription.loadNextPage()
    let secondPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(secondPage), [0, -1], infinitePageOneDescendingSource)
    subscription.unsubscribe()
  }

  @Test
  func upstreamInfiniteQueryEarlyLoadNextPageDoesNotBankFuturePages() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 1, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    _ = try #require(await snapshotPump.next())
    subscription.loadNextPage()

    try await upsertNumberItems([0, 1], prefix: "early-load", in: runtime)
    let firstPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(firstPage), [0], infiniteEarlyLoadSource)
    expectNoDifference(firstPage.canLoadNextPage, true, infiniteEarlyLoadSource)

    subscription.loadNextPage()
    let secondPage = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(secondPage), [0, 1], infiniteEarlyLoadSource)
    subscription.unsubscribe()
  }

  @Test
  func preLeaseCancellationFinishesBeforeLateSetupCleanupInstalls() async throws {
    let lease = InstantLiveInfiniteSubscriptionSetupLease()
    try await instantLiveWithTimeout(
      operation: "cancel an infinite-query setup before its cleanup lease installs",
      timeoutMilliseconds: 5_000
    ) {
      await lease.cancel()
    }

    let cleanup = InfiniteQuerySetupCleanupProbe()
    let installed = await lease.install {
      await cleanup.record()
    }
    let cleanupCount = await cleanup.count
    expectNoDifference(installed, false)
    expectNoDifference(cleanupCount, 1)
  }

  @Test
  func liveInfiniteUnsubscribeDuringPageInfoSetupCannotInstallLateObservers() async throws {
    let setupBarrier = InfiniteQuerySetupBarrier()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-cancel-page-info-setup",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.onLiveInfiniteQuerySetupCheckpointForTesting = { checkpoint in
      guard checkpoint == .beforePersistedPageInfoLoad else { return }
      await setupBarrier.pause()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    defer {
      Task { await setupBarrier.release() }
      subscription.unsubscribe()
    }

    try await waitForInfiniteSetupBarrier(
      setupBarrier,
      operation: "reach the persisted page-info setup checkpoint"
    )
    subscription.unsubscribe()
    let terminal = try #require(
      await nextInfiniteSnapshot(
        operation: "receive page-info-blocked infinite-query terminal snapshot",
        in: subscription.snapshots
      )
    )
    expectNoDifference(terminal.sequence, 0)
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.error, nil)
    #expect(
      try await nextInfiniteSnapshot(
        operation: "finish page-info-blocked infinite-query unsubscription",
        in: subscription.snapshots
      ) == nil
    )
    let observationCountBeforeRelease = await runtime.store.activeObservationCount()
    let activeQueryKeysBeforeRelease = await runtime.liveActiveQueryKeysForTesting()
    expectNoDifference(observationCountBeforeRelease, 0)
    expectNoDifference(activeQueryKeysBeforeRelease, [])
    try await requireInfiniteSetupReleasedOperationGate(in: runtime)

    await setupBarrier.release()
    try await waitForInfiniteSetupResidencyToClear(in: runtime)
    let liveOperations = await session.sentMessages().map(\.op)
    #expect(!liveOperations.contains("add-query"))
  }

  @Test
  func liveInfiniteUnsubscribeAfterLocalObserverSetupRemovesItBeforeRemoteRegistration() async throws {
    let setupBarrier = InfiniteQuerySetupBarrier()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-cancel-local-observer-setup",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.onLiveInfiniteQuerySetupCheckpointForTesting = { checkpoint in
      guard checkpoint == .localObservationInstalled else { return }
      await setupBarrier.pause()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    defer {
      Task { await setupBarrier.release() }
      subscription.unsubscribe()
    }

    try await waitForInfiniteSetupBarrier(
      setupBarrier,
      operation: "install the local infinite-query observer lease"
    )
    let installedObservationCount = await runtime.store.activeObservationCount()
    let activeQueryKeysBeforeCancellation = await runtime.liveActiveQueryKeysForTesting()
    expectNoDifference(installedObservationCount, 1)
    expectNoDifference(activeQueryKeysBeforeCancellation, [])

    subscription.unsubscribe()
    let terminal = try #require(
      await nextInfiniteSnapshot(
        operation: "receive local-observer-blocked infinite-query terminal snapshot",
        in: subscription.snapshots
      )
    )
    expectNoDifference(terminal.sequence, 0)
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.error, nil)
    #expect(
      try await nextInfiniteSnapshot(
        operation: "finish local-observer-blocked infinite-query unsubscription",
        in: subscription.snapshots
      ) == nil
    )
    try await waitForInfiniteSetupResidencyToClear(in: runtime)
    try await requireInfiniteSetupReleasedOperationGate(in: runtime)
    await setupBarrier.release()
    let liveOperations = await session.sentMessages().map(\.op)
    #expect(!liveOperations.contains("add-query"))
  }

  @Test
  func alreadyCancelledPublicInfiniteQuerySubscriptionReturnsInertWithoutSetup() async throws {
    let startBarrier = InfiniteQuerySetupBarrier()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-already-cancelled-public-subscribe",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscriptionTask = Task {
      await startBarrier.pause()
      return await runtime.subscribeInfiniteQuery(
        infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
      )
    }
    defer {
      Task { await startBarrier.release() }
      subscriptionTask.cancel()
    }
    try await waitForInfiniteSetupBarrier(
      startBarrier,
      operation: "pause before an already-cancelled public infinite-query subscription"
    )

    subscriptionTask.cancel()
    await startBarrier.release()
    let subscription = try await instantLiveWithTimeout(
      operation: "return an inert already-cancelled infinite-query subscription",
      timeoutMilliseconds: 5_000
    ) {
      await subscriptionTask.value
    }
    #expect(
      try await nextInfiniteSnapshot(
        operation: "finish an already-cancelled public infinite-query subscription",
        in: subscription.snapshots
      ) == nil
    )
    let operationGateWaiterCount = await runtime.operationGateWaiterCountForTesting()
    expectNoDifference(operationGateWaiterCount, 0)
    try await waitForInfiniteSetupResidencyToClear(in: runtime)
    let liveOperations = await session.sentMessages().map(\.op)
    #expect(!liveOperations.contains("add-query"))
  }

  @Test
  func gateQueuedPublicInfiniteQueryCancellationReturnsInertWithoutLateSetup() async throws {
    let operationGateBarrier = InfiniteQuerySetupBarrier()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-cancel-operation-gate-setup",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.onLiveQueryResultPruneActiveKeysCapturedForTesting = { _ in
      await operationGateBarrier.pause()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let prune = Task {
      try await runtime.pruneLiveQueryResults(
        policy: InstantLiveQueryResultPruningPolicy(maxEntries: 0),
        now: InstantTimestamp(milliseconds: 1)
      )
    }
    defer {
      Task { await operationGateBarrier.release() }
      prune.cancel()
    }
    try await waitForInfiniteSetupBarrier(
      operationGateBarrier,
      operation: "hold the operation gate ahead of infinite-query setup"
    )

    let subscriptionTask = Task {
      await runtime.subscribeInfiniteQuery(
        infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
      )
    }
    defer { subscriptionTask.cancel() }
    try await instantLiveWithTimeout(
      operation: "queue public infinite-query validation at the operation gate",
      timeoutMilliseconds: 5_000
    ) {
      while await runtime.operationGateWaiterCountForTesting() != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    let queuedObservationCount = await runtime.store.activeObservationCount()
    expectNoDifference(queuedObservationCount, 0)

    subscriptionTask.cancel()
    let subscription = try await instantLiveWithTimeout(
      operation: "cancel gate-queued public infinite-query validation",
      timeoutMilliseconds: 5_000
    ) {
      await subscriptionTask.value
    }
    #expect(
      try await nextInfiniteSnapshot(
        operation: "finish a canceled gate-queued public infinite-query subscription",
        in: subscription.snapshots
      ) == nil
    )
    try await instantLiveWithTimeout(
      operation: "remove canceled infinite-query setup from the operation gate",
      timeoutMilliseconds: 5_000
    ) {
      while await runtime.operationGateWaiterCountForTesting() != 0 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
    try await waitForInfiniteSetupResidencyToClear(in: runtime)

    await operationGateBarrier.release()
    _ = try await prune.value
    try await waitForInfiniteSetupResidencyToClear(in: runtime)
    let liveOperations = await session.sentMessages().map(\.op)
    #expect(!liveOperations.contains("add-query"))
  }

  @Test
  func localPublicInfiniteQueryCancellationAfterObservationInstallReturnsInertAndRemovesObserver()
    async throws
  {
    let setupBarrier = InfiniteQuerySetupBarrier()
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-local-cancel-after-observer-install",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes
    )
    configuration.onLocalInfiniteQueryObservationInstalledForTesting = {
      await setupBarrier.pause()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscriptionTask = Task {
      await runtime.subscribeInfiniteQuery(
        infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
      )
    }
    defer {
      Task { await setupBarrier.release() }
      subscriptionTask.cancel()
    }
    try await waitForInfiniteSetupBarrier(
      setupBarrier,
      operation: "install the local public infinite-query store observation"
    )
    let installedObservationCount = await runtime.store.activeObservationCount()
    expectNoDifference(installedObservationCount, 1)

    subscriptionTask.cancel()
    let subscription = try await instantLiveWithTimeout(
      operation: "cancel local infinite-query setup after observer installation",
      timeoutMilliseconds: 5_000
    ) {
      await subscriptionTask.value
    }
    #expect(
      try await nextInfiniteSnapshot(
        operation: "finish the canceled local public infinite-query subscription",
        in: subscription.snapshots
      ) == nil
    )
    try await waitForInfiniteSetupResidencyToClear(in: runtime)

    await setupBarrier.release()
    try await waitForInfiniteSetupResidencyToClear(in: runtime)
  }

  @Test
  func liveInfiniteQueryEmitsLocalStarterBeforeRemotePageInfo() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-local-starter",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    try await upsertNumberEntries(
      [("local-item", 1)],
      transactionID: "infinite-live-local-starter-write",
      in: runtime
    )

    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)
    let localSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(localSnapshot), [1], infiniteLocalStarterSource)
    #expect(!localSnapshot.canLoadNextPage)
    let sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages, [], infiniteLocalStarterSource)

    subscription.unsubscribe()
    _ = try await runtime.closeConnection()
  }

  @Test
  func liveInfiniteQueryShortStarterEmitsClosedPagingDiagnostics() async throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("infinite-query-diagnostics-\(UUID().uuidString).jsonl")
    InstantDiagnostics.shared.configure(
      InstantDiagnosticsConfiguration(fileURL: fileURL, minimumLevel: .info)
    )
    defer {
      InstantDiagnostics.shared.configure(
        InstantDiagnosticsConfiguration(fileURL: nil)
      )
      try? FileManager.default.removeItem(at: fileURL)
    }

    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-diag-short",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    try await upsertNumberEntries(
      [("diag-1", 1), ("diag-2", 2)],
      transactionID: "infinite-diag-short-seed",
      in: runtime
    )
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 10, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)
    let snapshot = try #require(await snapshotPump.next())
    #expect(!snapshot.canLoadNextPage)
    // Allow async subscribe.started / starter.snapshot to flush to the shared logger.
    try await Task.sleep(for: .milliseconds(80))
    subscription.unsubscribe()
    _ = try await runtime.closeConnection()

    let text = try String(contentsOf: fileURL, encoding: .utf8)
    #expect(text.contains("infinite.starter.snapshot"))
    #expect(text.contains("shortPageClosed") || text.contains("\"canLoadNextPage\":\"false\""))
    #expect(text.contains("infinite.subscribe.started"))
  }

  /// Regression: 1.5.0 trusted remote `hasNextPage` on a short pre-kickstart
  /// starter page. Scribe list UI auto-loadNextPage then thrashed until Jetsam
  /// (iPad ~4 GB, 2026-08-04/05). Pre-kickstart must only offer next page when
  /// the local window is full.
  @Test
  func liveInfiniteQueryShortStarterIgnoresRemoteHasNextPageWithoutKickstart() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-short-starter-has-next",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    try await upsertNumberEntries(
      [("item-1", 1), ("item-2", 2), ("item-3", 3)],
      transactionID: "infinite-live-short-starter-seed",
      in: runtime
    )

    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 10, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)
    let localSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(localSnapshot), [1, 2, 3], infiniteShortStarterThrashSource)
    #expect(!localSnapshot.canLoadNextPage, Comment(rawValue: infiniteShortStarterThrashSource))

    // Auth-session probe before starter registration can reorder early traffic;
    // wait for any add-query that carries `q`, not merely message count == 2.
    let starterQuery = try #require(
      await waitForInfiniteQueryField("q", in: session)
    )
    let startCursor = infiniteLiveCursor(id: "item-1", value: 1)
    let endCursor = infiniteLiveCursor(id: "item-3", value: 3)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: starterQuery,
        processedTransactionID: "infinite-live-short-starter-remote",
        result: infiniteLiveQueryResult(
          [("item-1", 1), ("item-2", 2), ("item-3", 3)],
          startCursor: startCursor,
          endCursor: endCursor,
          // Remote lies / claims more pages — must not open canLoadNextPage
          // without a full page + liveTuple kickstart path.
          hasNextPage: true
        )
      )
    )

    // Remote page-info re-emits the starter. Short page must stay closed even
    // when the server claims has-next-page.
    let afterRemote = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(afterRemote), [1, 2, 3], infiniteShortStarterThrashSource)
    #expect(!afterRemote.canLoadNextPage, Comment(rawValue: infiniteShortStarterThrashSource))

    // loadNextPage expands local-only; with a short local window it must close
    // (or no-op) rather than reopen canLoadNextPage.
    subscription.loadNextPage()
    let afterLoad = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(afterLoad), [1, 2, 3], infiniteShortStarterThrashSource)
    #expect(!afterLoad.canLoadNextPage, Comment(rawValue: infiniteShortStarterThrashSource))

    for _ in 0..<5 {
      subscription.loadNextPage()
    }
    // Allow any coalesced expand republishes to settle.
    try await Task.sleep(for: .milliseconds(50))
    subscription.loadNextPage()
    let afterThrash = try #require(await snapshotPump.next())
    expectNoDifference(loadedValues(afterThrash), [1, 2, 3], infiniteShortStarterThrashSource)
    #expect(!afterThrash.canLoadNextPage, Comment(rawValue: infiniteShortStarterThrashSource))

    subscription.unsubscribe()
    _ = try await runtime.closeConnection()
  }

  @Test
  func blockedDeferredHydrationKeepsExactRetirementOwnedUntilLeaseRelease() async throws {
    let cacheURL = try temporaryInfiniteQueryCacheURL()
    let payloadAttribute = InstantAttribute(
      id: "items/payloadJSON",
      namespace: "items",
      name: "payloadJSON",
      valueType: .json
    )
    let attributes = infiniteQueryAttributes + [payloadAttribute]
    let timestamp = InstantTimestamp(milliseconds: 1_767_225_600_001)
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    try await persistence.saveStoreSnapshot(
      InstantStoreSnapshot(
        attributes: attributes,
        triples: [
          InstantTriple(
            entityID: "deferred-item-1",
            attributeID: InstantAttribute.primaryKeyID(namespace: "items"),
            value: .string("deferred-item-1"),
            txID: "seed-blocked-deferred-hydration",
            txTime: timestamp
          ),
          InstantTriple(
            entityID: "deferred-item-1",
            attributeID: infiniteQueryValueAttributeID,
            value: .number(1),
            txID: "seed-blocked-deferred-hydration",
            txTime: timestamp
          ),
          InstantTriple(
            entityID: "deferred-item-1",
            attributeID: payloadAttribute.id,
            value: .json(.string(String(repeating: "payload", count: 10_000))),
            txID: "seed-blocked-deferred-hydration",
            txTime: timestamp
          ),
        ]
      )
    )

    let hydrationBarrier = InfiniteQueryDeferredHydrationBarrier()
    let cleanupProbe = InfiniteQuerySetupCleanupProbe()
    let session = LiveReactorParitySession(messages: [])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-blocked-deferred-hydration",
      persistenceURL: cacheURL,
      initialAttributes: attributes,
      deferredValueResidency: InstantDeferredValueResidencyPolicy(
        attributeIDs: [payloadAttribute.id]
      ),
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = false
    configuration.onLiveInfiniteQueryDeferredHydrationAcquiredForTesting = { valueCount in
      await hydrationBarrier.pause(valueCount: valueCount)
    }
    configuration.onLiveInfiniteQueryRetirementCleanupStartedForTesting = { _ in
      await cleanupProbe.record()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      InstantQueryPlan(
        id: "items.blocked-deferred-hydration",
        namespace: "items",
        order: InstantQueryOrder("value"),
        limit: 1,
        selectedFields: ["value", payloadAttribute.name]
      )
    )
    defer {
      Task { await hydrationBarrier.release() }
      subscription.unsubscribe()
    }

    let acquiredValueCount = try await instantLiveWithTimeout(
      operation: "block the live infinite-query deferred hydration after acquiring its payload",
      timeoutMilliseconds: 5_000
    ) {
      await hydrationBarrier.waitUntilReached()
    }
    expectNoDifference(acquiredValueCount, 1)
    let installedObservationCount = try await waitForInfiniteStoreObservationCount(1, in: runtime)
    expectNoDifference(installedObservationCount, 1)

    subscription.unsubscribe()
    let blockedResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "keep the deferred hydration retirement owned until its exact lease releases"
    ) { residency in
      residency.latestEmissionValueCount == 0
        && residency.hydratedEntityCount == 0
        && residency.navigationReferenceCount == 0
        && residency.ownedTaskCount == 3
        && residency.activeSubscriptionCount == 0
        && residency.retiringSubscriptionCount == 1
        && residency.pendingSubscriptionCount == 0
        && residency.retirementWatchdogCount == 1
    }
    expectNoDifference(blockedResidency.ownedTaskCount, 3)
    let blockedCleanupCount = try await instantLiveWithTimeout(
      operation: "begin the exact deferred-hydration retirement cleanup",
      timeoutMilliseconds: 5_000
    ) {
      while true {
        try Task.checkCancellation()
        let count = await cleanupProbe.count
        if count == 1 {
          return count
        }
        await Task.yield()
      }
    }
    expectNoDifference(blockedCleanupCount, 1)
    let observationCountWhileHydrationIsBlocked =
      try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(observationCountWhileHydrationIsBlocked, 0)

    await hydrationBarrier.release()
    let releasedResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "finish the exact deferred hydration retirement"
    ) { $0 == InstantInfiniteQueryResidencySnapshot() }
    expectNoDifference(releasedResidency, .init())
    let releasedCleanupCount = await cleanupProbe.count
    expectNoDifference(releasedCleanupCount, 1)
    let finalObservationCount = try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(finalObservationCount, 0)
  }

  @Test
  func liveRetirementTimeoutKeepsCleanupOwnedUntilExactLeaseRelease() async throws {
    let cleanupBarrier = InfiniteQuerySetupBarrier()
    let watchdogProbe = InfiniteQueryRetirementWatchdogProbe()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-retirement-timeout",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    configuration.onLiveInfiniteQueryRetirementCleanupStartedForTesting = {
      subscriptionID in
      guard subscriptionID == 2 else { return }
      await cleanupBarrier.pause()
    }
    configuration.liveInfiniteQueryRetirementWatchdogSleep = { milliseconds in
      await watchdogProbe.record(milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    defer {
      Task { await cleanupBarrier.release() }
      subscription.unsubscribe()
    }
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)
    _ = try #require(
      await snapshotPump.next(operation: "receive the retirement-timeout initial snapshot")
    )

    let starterQuery = try #require(await waitForInfiniteQuery(in: session) { options in
      options == [
        "limit": .number(2),
        "order": .object(["value": .string("asc")]),
      ]
    })
    let firstCursor = infiniteLiveCursor(id: "item-1", value: 1)
    let secondCursor = infiniteLiveCursor(id: "item-2", value: 2)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: starterQuery,
        processedTransactionID: "infinite-retirement-timeout-starter",
        result: infiniteLiveQueryResult(
          [("item-1", 1), ("item-2", 2)],
          startCursor: firstCursor,
          endCursor: secondCursor,
          hasNextPage: true
        )
      )
    )
    let forwardQuery = try #require(await waitForInfiniteQuery(in: session) { options in
      options == [
        "after": .array(firstCursor),
        "afterInclusive": .bool(true),
        "limit": .number(2),
        "order": .object(["value": .string("asc")]),
      ]
    })
    await session.enqueue(
      liveReactorAddQueryOK(
        query: forwardQuery,
        processedTransactionID: "infinite-retirement-timeout-forward",
        result: infiniteLiveQueryResult(
          [("item-1", 1), ("item-2", 2)],
          startCursor: firstCursor,
          endCursor: secondCursor,
          hasNextPage: true
        )
      )
    )
    _ = try await waitForInfiniteSnapshot(
      operation: "receive the live page before blocking its frozen replacement cleanup",
      in: subscription.snapshots,
      matchingIDs: ["item-1", "item-2"]
    )

    subscription.loadNextPage()
    try await waitForInfiniteSetupBarrier(
      cleanupBarrier,
      operation: "block the exact forward-query observation lease cleanup"
    )
    let watchdogMilliseconds = try await instantLiveWithTimeout(
      operation: "fire the live infinite-query retirement watchdog",
      timeoutMilliseconds: 5_000
    ) {
      while true {
        try Task.checkCancellation()
        if let milliseconds = await watchdogProbe.milliseconds {
          return milliseconds
        }
        await Task.yield()
      }
    }
    expectNoDifference(watchdogMilliseconds, 5_000)

    let terminal = try #require(
      await snapshotPump.next(operation: "receive the stalled-retirement terminal failure")
    )
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.canLoadPreviousPage, false)
    expectNoDifference(terminal.canLoadNextPage, false)
    expectNoDifference(terminal.error?.code, .implementationFailed)
    expectNoDifference(terminal.error?.operation, "retire live infinite query subscription")
    let stalledResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "retain only the exact stalled retirement cleanup after watchdog failure"
    ) { residency in
      residency.latestEmissionValueCount == 0
        && residency.hydratedEntityCount == 0
        && residency.navigationReferenceCount == 0
        && residency.ownedTaskCount == 2
        && residency.activeSubscriptionCount == 0
        && residency.retiringSubscriptionCount == 1
        && residency.pendingSubscriptionCount == 0
        && residency.retirementWatchdogCount == 0
    }
    expectNoDifference(stalledResidency.ownedTaskCount, 2)
    expectNoDifference(stalledResidency.retiringSubscriptionCount, 1)
    let blockedObservationCount = try await waitForInfiniteStoreObservationCount(1, in: runtime)
    expectNoDifference(blockedObservationCount, 1)

    let frozenForwardOptions: [String: InstantLiveJSONValue] = [
      "after": .array(firstCursor),
      "afterInclusive": .bool(true),
      "before": .array(secondCursor),
      "beforeInclusive": .bool(true),
      "order": .object(["value": .string("asc")]),
    ]
    let frozenRegistrationsBeforeRelease = await session.sentMessages().filter { message in
      message.op == "add-query"
        && message.fields["q"].flatMap { infiniteLiveOptions($0) } == frozenForwardOptions
    }
    expectNoDifference(frozenRegistrationsBeforeRelease, [])

    await cleanupBarrier.release()
    let releasedResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "finish the exact stalled retirement cleanup"
    ) { $0 == InstantInfiniteQueryResidencySnapshot() }
    expectNoDifference(releasedResidency, .init())
    let remainingStoreQueryKeys = await runtime.store.activeQueryCacheKeys()
    expectNoDifference(remainingStoreQueryKeys, [])
    let finalObservationCount = try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(finalObservationCount, 0)
    let activeAfterRelease = try await waitForActiveInfiniteQueries([], in: session)
    expectNoDifference(activeAfterRelease, [])
    let frozenRegistrationsAfterRelease = await session.sentMessages().filter { message in
      message.op == "add-query"
        && message.fields["q"].flatMap { infiniteLiveOptions($0) } == frozenForwardOptions
    }
    expectNoDifference(frozenRegistrationsAfterRelease, [])
    _ = try await runtime.closeConnection()
  }

  @Test
  func cleanLiveUnsubscribeReportsStalledRetirementUntilLeaseRelease() async throws {
    let diagnosticsURL = FileManager.default.temporaryDirectory.appendingPathComponent(
      "infinite-retirement-timeout-\(UUID().uuidString).jsonl"
    )
    InstantDiagnostics.shared.configure(
      InstantDiagnosticsConfiguration(fileURL: diagnosticsURL, minimumLevel: .info)
    )
    defer {
      InstantDiagnostics.shared.configure(InstantDiagnosticsConfiguration(fileURL: nil))
      try? FileManager.default.removeItem(at: diagnosticsURL)
    }

    let cleanupBarrier = InfiniteQuerySetupBarrier()
    let cleanupCompletion = InfiniteQuerySetupCleanupProbe()
    var cleanupWaiter: Task<Void, Never>?
    let watchdogProbe = InfiniteQueryRetirementWatchdogProbe()
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-clean-retirement-timeout",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    configuration.onLiveInfiniteQueryRetirementCleanupStartedForTesting = {
      subscriptionID in
      guard subscriptionID == 1 else { return }
      await cleanupBarrier.pause()
    }
    configuration.liveInfiniteQueryRetirementWatchdogSleep = { milliseconds in
      await watchdogProbe.record(milliseconds)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    defer {
      Task { await cleanupBarrier.release() }
      cleanupWaiter?.cancel()
      subscription.unsubscribe()
    }
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)
    _ = try #require(
      await snapshotPump.next(operation: "install the clean-timeout starter observation")
    )

    subscription.unsubscribe()
    cleanupWaiter = Task {
      await subscription.unsubscribeAndWait()
      await cleanupCompletion.record()
    }
    let terminal = try #require(
      await snapshotPump.next(operation: "receive the clean terminal before stalled cleanup")
    )
    expectNoDifference(terminal.values, [])
    expectNoDifference(terminal.error, nil)
    #expect(
      try await snapshotPump.next(operation: "finish the clean stalled-retirement stream") == nil
    )
    let watchdogMilliseconds = try await instantLiveWithTimeout(
      operation: "fire the clean-unsubscribe retirement watchdog",
      timeoutMilliseconds: 5_000
    ) {
      while true {
        try Task.checkCancellation()
        if let milliseconds = await watchdogProbe.milliseconds {
          return milliseconds
        }
        await Task.yield()
      }
    }
    expectNoDifference(watchdogMilliseconds, 5_000)
    let stalledResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "retain clean-unsubscribe cleanup after its watchdog fires"
    ) { residency in
      residency.latestEmissionValueCount == 0
        && residency.hydratedEntityCount == 0
        && residency.navigationReferenceCount == 0
        && residency.ownedTaskCount == 2
        && residency.activeSubscriptionCount == 0
        && residency.retiringSubscriptionCount == 1
        && residency.pendingSubscriptionCount == 0
        && residency.retirementWatchdogCount == 0
    }
    expectNoDifference(stalledResidency.ownedTaskCount, 2)
    let completionCountWhileStalled = await cleanupCompletion.count
    expectNoDifference(completionCountWhileStalled, 0)
    let blockedObservationCount = try await waitForInfiniteStoreObservationCount(1, in: runtime)
    expectNoDifference(blockedObservationCount, 1)
    let diagnosticText = try await instantLiveWithTimeout(
      operation: "record the inactive live retirement timeout diagnostic",
      timeoutMilliseconds: 5_000
    ) {
      while true {
        try Task.checkCancellation()
        let text = (try? String(contentsOf: diagnosticsURL, encoding: .utf8)) ?? ""
        if text.contains("infinite.retirement.timeout"),
          text.contains("\"coordinatorActive\":\"false\""),
          text.contains("\"subscriptionID\":\"1\""),
          text.contains("\"timeoutMilliseconds\":\"5000\"")
        {
          return text
        }
        await Task.yield()
      }
    }
    #expect(diagnosticText.contains("\"cleanupStillOwned\":\"true\""))

    await cleanupBarrier.release()
    if let cleanupWaiter {
      try await instantLiveWithTimeout(
        operation: "complete exact clean-unsubscribe cleanup after releasing its Store lease",
        timeoutMilliseconds: 5_000
      ) {
        await cleanupWaiter.value
      }
    }
    let completionCountAfterRelease = await cleanupCompletion.count
    expectNoDifference(completionCountAfterRelease, 1)
    let releasedResidency = try await waitForInfiniteResidency(
      in: subscription,
      operation: "finish the clean-unsubscribe stalled retirement cleanup"
    ) { $0 == InstantInfiniteQueryResidencySnapshot() }
    expectNoDifference(releasedResidency, .init())
    let finalObservationCount = try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(finalObservationCount, 0)
    let activeAfterRelease = try await waitForActiveInfiniteQueries([], in: session)
    expectNoDifference(activeAfterRelease, [])
    _ = try await runtime.closeConnection()
  }

  @Test
  func liveInfiniteQueryRegistersOnlyBoundedCursorChunks() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-bounded",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)
    _ = try #require(await snapshotPump.next())

    #expect(try await waitForInfiniteMessageCount(2, in: session))
    var sent = await session.sentMessages()
    let starterQuery = try #require(sent.last?.fields["q"])
    expectNoDifference(
      infiniteLiveOptions(starterQuery),
      [
        "limit": .number(2),
        "order": .object(["value": .string("asc")]),
      ],
      infiniteBoundedTransportSource
    )

    let firstCursor = infiniteLiveCursor(id: "item-1", value: 1)
    let secondCursor = infiniteLiveCursor(id: "item-2", value: 2)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: starterQuery,
        processedTransactionID: "infinite-live-starter",
        result: infiniteLiveQueryResult(
          [("item-1", 1), ("item-2", 2)],
          startCursor: firstCursor,
          endCursor: secondCursor,
          hasNextPage: true
        )
      )
    )

    #expect(try await waitForInfiniteMessageCount(4, in: session))
    sent = await session.sentMessages()
    let registeredQueries = sent
      .filter { $0.op == "add-query" }
      .compactMap { $0.fields["q"] }
    expectNoDifference(registeredQueries.count, 3, infiniteBoundedTransportSource)
    #expect(
      registeredQueries.allSatisfy { query in
        guard let options = infiniteLiveOptions(query) else { return false }
        return options["limit"] != nil
          || (options["after"] != nil && options["before"] != nil)
      },
      Comment(rawValue: infiniteBoundedTransportSource)
    )
    #expect(
      registeredQueries.contains { query in
        infiniteLiveOptions(query) == [
          "after": .array(firstCursor),
          "afterInclusive": .bool(true),
          "limit": .number(2),
          "order": .object(["value": .string("asc")]),
        ]
      },
      Comment(rawValue: infiniteBoundedTransportSource)
    )
    #expect(
      registeredQueries.contains { query in
        infiniteLiveOptions(query) == [
          "after": .array(firstCursor),
          "limit": .number(2),
          "order": .object(["value": .string("desc")]),
        ]
      },
      Comment(rawValue: infiniteBoundedTransportSource)
    )

    let forwardQuery = try #require(
      registeredQueries.first { query in
        infiniteLiveOptions(query) == [
          "after": .array(firstCursor),
          "afterInclusive": .bool(true),
          "limit": .number(2),
          "order": .object(["value": .string("asc")]),
        ]
      }
    )
    await session.enqueue(
      liveReactorAddQueryOK(
        query: forwardQuery,
        processedTransactionID: "infinite-live-forward-1",
        result: infiniteLiveQueryResult(
          [("item-1", 1), ("item-2", 2)],
          startCursor: firstCursor,
          endCursor: secondCursor,
          hasNextPage: true
        )
      )
    )
    let loadableSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(loadableSnapshot.values.map(\.id), ["item-1", "item-2"])
    #expect(loadableSnapshot.canLoadNextPage)

    subscription.loadNextPage()
    #expect(try await waitForInfiniteMessageCount(7, in: session))
    sent = await session.sentMessages()
    let pagedQueries = sent
      .filter { $0.op == "add-query" }
      .compactMap { $0.fields["q"] }
    expectNoDifference(pagedQueries.count, 5, infiniteBoundedTransportSource)
    #expect(
      pagedQueries.allSatisfy { query in
        guard let options = infiniteLiveOptions(query) else { return false }
        return options["limit"] != nil
          || (options["after"] != nil && options["before"] != nil)
      },
      Comment(rawValue: infiniteBoundedTransportSource)
    )
    #expect(
      pagedQueries.contains { query in
        infiniteLiveOptions(query) == [
          "after": .array(firstCursor),
          "afterInclusive": .bool(true),
          "before": .array(secondCursor),
          "beforeInclusive": .bool(true),
          "order": .object(["value": .string("asc")]),
        ]
      },
      Comment(rawValue: infiniteBoundedTransportSource)
    )
    #expect(
      pagedQueries.contains { query in
        infiniteLiveOptions(query) == [
          "after": .array(secondCursor),
          "limit": .number(2),
          "order": .object(["value": .string("asc")]),
        ]
      },
      Comment(rawValue: infiniteBoundedTransportSource)
    )

    subscription.unsubscribe()
    #expect(try await waitForInfiniteOpCount("remove-query", count: 5, in: session))
    sent = await session.sentMessages()
    let removedQueries = sent
      .filter { $0.op == "remove-query" }
      .compactMap { $0.fields["q"] }
    expectNoDifference(Set(removedQueries), Set(pagedQueries), infiniteBoundedTransportSource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func liveWindowEvictsAndCancelsOppositeCursorChunkInBothDirections() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-retention-window",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value")),
      retentionPolicy: .window(maximumPageCount: 1)
    )
    defer { subscription.unsubscribe() }
    _ = try await waitForInfiniteSnapshot(
      operation: "receive the live-window initial snapshot",
      in: subscription.snapshots
    )

    let starterQuery = try #require(await waitForInfiniteQuery(in: session) { options in
      options == [
        "limit": .number(2),
        "order": .object(["value": .string("asc")]),
      ]
    })
    let firstCursor = infiniteLiveCursor(id: "item-1", value: 1)
    let secondCursor = infiniteLiveCursor(id: "item-2", value: 2)
    let thirdCursor = infiniteLiveCursor(id: "item-3", value: 3)
    let fourthCursor = infiniteLiveCursor(id: "item-4", value: 4)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: starterQuery,
        processedTransactionID: "infinite-live-window-starter",
        result: infiniteLiveQueryResult(
          [("item-1", 1), ("item-2", 2)],
          startCursor: firstCursor,
          endCursor: secondCursor,
          hasNextPage: true
        )
      )
    )

    let firstForwardQuery = try #require(await waitForInfiniteQuery(in: session) { options in
      options == [
        "after": .array(firstCursor),
        "afterInclusive": .bool(true),
        "limit": .number(2),
        "order": .object(["value": .string("asc")]),
      ]
    })
    let leadingWatcherQuery = try #require(await waitForInfiniteQuery(in: session) { options in
      options == [
        "after": .array(firstCursor),
        "limit": .number(2),
        "order": .object(["value": .string("desc")]),
      ]
    })
    await session.enqueue(
      liveReactorAddQueryOK(
        query: firstForwardQuery,
        processedTransactionID: "infinite-live-window-first",
        result: infiniteLiveQueryResult(
          [("item-1", 1), ("item-2", 2)],
          startCursor: firstCursor,
          endCursor: secondCursor,
          hasNextPage: true
        )
      )
    )
    let first = try await waitForInfiniteSnapshot(
      operation: "receive the first bounded live-window page",
      in: subscription.snapshots,
      matchingIDs: ["item-1", "item-2"]
    )
    expectNoDifference(first.canLoadPreviousPage, false)
    expectNoDifference(first.canLoadNextPage, true)

    subscription.loadNextPage()
    let secondForwardQuery = try #require(await waitForInfiniteQuery(in: session) { options in
      options == [
        "after": .array(secondCursor),
        "limit": .number(2),
        "order": .object(["value": .string("asc")]),
      ]
    })
    await session.enqueue(
      liveReactorAddQueryOK(
        query: secondForwardQuery,
        processedTransactionID: "infinite-live-window-second",
        result: infiniteLiveQueryResult(
          [("item-3", 3), ("item-4", 4)],
          startCursor: thirdCursor,
          endCursor: fourthCursor,
          hasNextPage: true
        )
      )
    )
    let second = try await waitForInfiniteSnapshot(
      operation: "receive the forward bounded live-window page",
      in: subscription.snapshots,
      matchingIDs: ["item-3", "item-4"]
    )
    expectNoDifference(second.values.map(\.id), ["item-3", "item-4"])
    expectNoDifference(second.canLoadPreviousPage, true)
    expectNoDifference(second.canLoadNextPage, true)
    let expectedAfterForward = Set([leadingWatcherQuery, secondForwardQuery])
    let activeAfterForward = try await waitForActiveInfiniteQueries(
      expectedAfterForward,
      in: session
    )
    expectNoDifference(activeAfterForward, expectedAfterForward)
    let afterForward = await session.sentMessages()
    let registeredFrozenForwardQueries =
      afterForward
        .filter { message in
          message.op == "add-query"
            && message.fields["q"].map { query in
              infiniteLiveOptions(query) == [
                "after": .array(firstCursor),
                "afterInclusive": .bool(true),
                "before": .array(secondCursor),
                "beforeInclusive": .bool(true),
                "order": .object(["value": .string("asc")]),
              ]
            } == true
        }
        .compactMap { $0.fields["q"] }
    expectNoDifference(registeredFrozenForwardQueries.count, 1)
    let frozenForwardQuery = try #require(registeredFrozenForwardQueries.first)
    expectNoDifference(
      infiniteQueryRegistrationOperations(
        for: frozenForwardQuery,
        in: afterForward
      ),
      ["add-query", "remove-query"]
    )

    subscription.loadPreviousPage()
    let previousQuery = try #require(await waitForInfiniteQuery(in: session) { options in
      options == [
        "after": .array(thirdCursor),
        "limit": .number(2),
        "order": .object(["value": .string("desc")]),
      ]
    })
    await session.enqueue(
      liveReactorAddQueryOK(
        query: previousQuery,
        processedTransactionID: "infinite-live-window-previous",
        result: infiniteLiveQueryResult(
          [("item-2", 2), ("item-1", 1)],
          startCursor: secondCursor,
          endCursor: firstCursor,
          hasNextPage: false
        )
      )
    )
    let previous = try await waitForInfiniteSnapshot(
      operation: "receive the previous bounded live-window page",
      in: subscription.snapshots,
      matchingIDs: ["item-1", "item-2"]
    )
    expectNoDifference(previous.values.map(\.id), ["item-1", "item-2"])
    expectNoDifference(previous.canLoadPreviousPage, false)
    expectNoDifference(previous.canLoadNextPage, true)
    let expectedAfterPrevious = Set([leadingWatcherQuery, previousQuery])
    let activeAfterPrevious = try await waitForActiveInfiniteQueries(
      expectedAfterPrevious,
      in: session
    )
    expectNoDifference(activeAfterPrevious, expectedAfterPrevious)
    let afterPrevious = await session.sentMessages()
    #expect(
      afterPrevious.contains { message in
        message.op == "remove-query" && message.fields["q"] == secondForwardQuery
      }
    )

    subscription.loadNextPage()
    #expect(try await waitForActiveInfiniteQuery(secondForwardQuery, in: session))
    await session.enqueue(
      liveReactorAddQueryOK(
        query: secondForwardQuery,
        processedTransactionID: "infinite-live-window-forward-again",
        result: infiniteLiveQueryResult(
          [("item-3", 3), ("item-4", 4)],
          startCursor: thirdCursor,
          endCursor: fourthCursor,
          hasNextPage: true
        )
      )
    )
    let forwardAgain = try await waitForInfiniteSnapshot(
      operation: "receive the re-registered forward live-window page",
      in: subscription.snapshots,
      matchingIDs: ["item-3", "item-4"]
    )
    expectNoDifference(forwardAgain.values.map(\.id), ["item-3", "item-4"])
    expectNoDifference(forwardAgain.canLoadPreviousPage, true)
    expectNoDifference(forwardAgain.canLoadNextPage, true)
    let activeAfterForwardAgain = try await waitForActiveInfiniteQueries(
      expectedAfterForward,
      in: session
    )
    expectNoDifference(activeAfterForwardAgain, expectedAfterForward)

    subscription.unsubscribe()
    let activeAfterUnsubscribe = try await waitForActiveInfiniteQueries([], in: session)
    expectNoDifference(activeAfterUnsubscribe, [])
    let finalMessages = await session.sentMessages()
    let registeredQueries = Set(
      finalMessages.filter { $0.op == "add-query" }.compactMap { $0.fields["q"] }
    )
    let removedQueries = Set(
      finalMessages.filter { $0.op == "remove-query" }.compactMap { $0.fields["q"] }
    )
    expectNoDifference(removedQueries, registeredQueries)
    let expectedRegistrationOperations: [InstantLiveJSONValue: [String]] = [
      starterQuery: ["add-query", "remove-query"],
      firstForwardQuery: ["add-query", "remove-query"],
      frozenForwardQuery: ["add-query", "remove-query"],
      leadingWatcherQuery: ["add-query", "remove-query"],
      secondForwardQuery: ["add-query", "remove-query", "add-query", "remove-query"],
      previousQuery: ["add-query", "remove-query"],
    ]
    expectNoDifference(registeredQueries, Set(expectedRegistrationOperations.keys))
    for (query, expectedOperations) in expectedRegistrationOperations {
      expectNoDifference(
        infiniteQueryRegistrationOperations(for: query, in: finalMessages),
        expectedOperations
      )
    }
    let finalStoreObservationCount =
      try await waitForInfiniteStoreObservationCount(0, in: runtime)
    expectNoDifference(finalStoreObservationCount, 0)
    _ = try await runtime.closeConnection()
  }

  @Test
  func liveInfiniteQueryAutomaticallyBoundsReverseChunks() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: infiniteLiveServerAttributes)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "infinite-live-reverse",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)
    _ = try #require(await snapshotPump.next())

    #expect(try await waitForInfiniteMessageCount(2, in: session))
    var sent = await session.sentMessages()
    let starterQuery = try #require(sent.last?.fields["q"])
    let firstCursor = infiniteLiveCursor(id: "item-1", value: 1)
    let secondCursor = infiniteLiveCursor(id: "item-2", value: 2)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: starterQuery,
        processedTransactionID: "infinite-live-reverse-starter",
        result: infiniteLiveQueryResult(
          [("item-1", 1), ("item-2", 2)],
          startCursor: firstCursor,
          endCursor: secondCursor,
          hasNextPage: true
        )
      )
    )

    #expect(try await waitForInfiniteMessageCount(4, in: session))
    sent = await session.sentMessages()
    let initialQueries = sent
      .filter { $0.op == "add-query" }
      .compactMap { $0.fields["q"] }
    let reverseQuery = try #require(
      initialQueries.first { query in
        infiniteLiveOptions(query) == [
          "after": .array(firstCursor),
          "limit": .number(2),
          "order": .object(["value": .string("desc")]),
        ]
      }
    )
    let zeroCursor = infiniteLiveCursor(id: "item-0", value: 0)
    let negativeCursor = infiniteLiveCursor(id: "item-negative-1", value: -1)
    await session.enqueue(
      liveReactorAddQueryOK(
        query: reverseQuery,
        processedTransactionID: "infinite-live-reverse-1",
        result: infiniteLiveQueryResult(
          [("item-0", 0), ("item-negative-1", -1)],
          startCursor: zeroCursor,
          endCursor: negativeCursor,
          hasNextPage: true
        )
      )
    )
    let reverseSnapshot = try #require(await snapshotPump.next())
    expectNoDifference(
      reverseSnapshot.values.map(\.id),
      ["item-negative-1", "item-0"],
      infiniteBoundedTransportSource
    )

    #expect(try await waitForInfiniteMessageCount(7, in: session))
    sent = await session.sentMessages()
    let pagedQueries = sent
      .filter { $0.op == "add-query" }
      .compactMap { $0.fields["q"] }
    expectNoDifference(pagedQueries.count, 5, infiniteBoundedTransportSource)
    #expect(
      pagedQueries.allSatisfy { query in
        guard let options = infiniteLiveOptions(query) else { return false }
        return options["limit"] != nil
          || (options["after"] != nil && options["before"] != nil)
      },
      Comment(rawValue: infiniteBoundedTransportSource)
    )
    #expect(
      pagedQueries.contains { query in
        infiniteLiveOptions(query) == [
          "after": .array(firstCursor),
          "before": .array(negativeCursor),
          "beforeInclusive": .bool(true),
          "order": .object(["value": .string("desc")]),
        ]
      },
      Comment(rawValue: infiniteBoundedTransportSource)
    )
    #expect(
      pagedQueries.contains { query in
        infiniteLiveOptions(query) == [
          "after": .array(negativeCursor),
          "limit": .number(2),
          "order": .object(["value": .string("desc")]),
        ]
      },
      Comment(rawValue: infiniteBoundedTransportSource)
    )

    subscription.unsubscribe()
    #expect(try await waitForInfiniteOpCount("remove-query", count: 5, in: session))
    sent = await session.sentMessages()
    let removedQueries = sent
      .filter { $0.op == "remove-query" }
      .compactMap { $0.fields["q"] }
    expectNoDifference(Set(removedQueries), Set(pagedQueries), infiniteBoundedTransportSource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func upstreamInfiniteQueryInvalidQueryEmitsErrorResponse() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      InstantQueryPlan(
        id: "items.invalid-infinite",
        namespace: "missing_items",
        order: InstantQueryOrder("value"),
        limit: 4
      )
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    let snapshot = try #require(await snapshotPump.next())
    expectNoDifference(snapshot.values, [], infiniteInvalidQuerySource)
    expectNoDifference(snapshot.canLoadNextPage, false, infiniteInvalidQuerySource)
    expectNoDifference(snapshot.error?.code, .validationFailed, infiniteInvalidQuerySource)
    #expect(snapshot.error?.message.isEmpty == false)
    #expect(try await snapshotPump.next() == nil)
    subscription.loadNextPage()
    subscription.unsubscribe()
  }

  @Test
  func infiniteQueryRejectsAnEmptyRetentionWindow() async throws {
    let runtime = try await infiniteQueryRuntime()
    let subscription = await runtime.subscribeInfiniteQuery(
      infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value")),
      retentionPolicy: .window(maximumPageCount: 0)
    )
    let snapshotPump = InfiniteSnapshotPump(subscription.snapshots)

    let snapshot = try #require(await snapshotPump.next())
    expectNoDifference(snapshot.values, [])
    expectNoDifference(snapshot.canLoadPreviousPage, false)
    expectNoDifference(snapshot.canLoadNextPage, false)
    expectNoDifference(snapshot.error?.code, .validationFailed)
    expectNoDifference(snapshot.error?.operation, "validate infinite query retention")
    expectNoDifference(snapshot.error?.path, "retentionPolicy")
    #expect(try await snapshotPump.next() == nil)
    subscription.loadPreviousPage()
    subscription.loadNextPage()
    subscription.unsubscribe()
  }
}

private func infiniteQueryRuntime() async throws -> InstantRuntime {
  try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "infinite-query-\(UUID().uuidString)",
      persistenceURL: temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() }
    )
  )
}

private let infiniteQueryAttributes: [InstantAttribute] = [
  .primaryKey(namespace: "items"),
  InstantAttribute(
    id: infiniteQueryValueAttributeID,
    namespace: "items",
    name: "value",
    valueType: .number,
    isIndexed: true
  ),
]

private let infiniteLiveServerAttributes: [InstantLiveJSONValue] = [
  infiniteLiveServerAttribute(id: "server-items-id", name: "id", valueType: "string"),
  infiniteLiveServerAttribute(id: "server-items-value", name: "value", valueType: "number"),
]

private func infiniteLiveServerAttribute(
  id: String,
  name: String,
  valueType: String
) -> InstantLiveJSONValue {
  .object([
    "cardinality": .string("one"),
    "forward-identity": .array([
      .string("identity-\(id)"),
      .string("items"),
      .string(name),
    ]),
    "id": .string(id),
    "index?": .bool(name == "value"),
    "unique?": .bool(name == "id"),
    "value-type": .string(valueType),
  ])
}

private func infiniteLiveCursor(id: String, value: Int) -> [InstantLiveJSONValue] {
  [
    .string(id),
    .string("server-items-value"),
    .number(Double(value)),
    .number(Double(1_767_225_600_000 + value)),
  ]
}

private func infiniteLiveQueryResult(
  _ entries: [(id: String, value: Int)],
  startCursor: [InstantLiveJSONValue]?,
  endCursor: [InstantLiveJSONValue]?,
  hasNextPage: Bool
) -> [InstantLiveJSONValue] {
  let joinRows = entries.map { entry in
    InstantLiveJSONValue.array([
      .array([
        .string(entry.id),
        .string("server-items-id"),
        .string(entry.id),
        .number(1_767_225_600_000),
      ]),
      .array([
        .string(entry.id),
        .string("server-items-value"),
        .number(Double(entry.value)),
        .number(Double(1_767_225_600_000 + entry.value)),
      ]),
    ])
  }
  return [
    .object([
      "child-nodes": .array([]),
      "data": .object([
        "datalog-result": .object(["join-rows": .array(joinRows)]),
        "page-info": .object([
          "items": .object([
            "end-cursor": endCursor.map(InstantLiveJSONValue.array) ?? .null,
            "has-next-page?": .bool(hasNextPage),
            "has-previous-page?": .bool(false),
            "start-cursor": startCursor.map(InstantLiveJSONValue.array) ?? .null,
          ])
        ]),
      ]),
    ])
  ]
}

private func infiniteLiveOptions(
  _ query: InstantLiveJSONValue
) -> [String: InstantLiveJSONValue]? {
  query.objectValue?["items"]?.objectValue?["$"]?.objectValue
}

private func waitForInfiniteMessageCount(
  _ count: Int,
  in session: LiveReactorParitySession
) async throws -> Bool {
  let deadline = ContinuousClock.now + .milliseconds(500)
  while ContinuousClock.now < deadline {
    if await session.sentMessages().count >= count {
      return true
    }
    try await Task.sleep(for: .milliseconds(5))
  }
  return await session.sentMessages().count >= count
}

private func waitForInfiniteQueryField(
  _ field: String,
  in session: LiveReactorParitySession
) async -> InstantLiveJSONValue? {
  let deadline = ContinuousClock.now + .milliseconds(1_000)
  while ContinuousClock.now < deadline {
    let sent = await session.sentMessages()
    if let value = sent.reversed().compactMap({ $0.fields[field] }).first {
      return value
    }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return await session.sentMessages().reversed().compactMap { $0.fields[field] }.first
}

private func waitForInfiniteOpCount(
  _ op: String,
  count: Int,
  in session: LiveReactorParitySession
) async throws -> Bool {
  let deadline = ContinuousClock.now + .milliseconds(500)
  while ContinuousClock.now < deadline {
    if await session.sentMessages().count(where: { $0.op == op }) >= count {
      return true
    }
    try await Task.sleep(for: .milliseconds(5))
  }
  return await session.sentMessages().count(where: { $0.op == op }) >= count
}

private struct InfiniteSnapshotObservationEnded: Error, CustomStringConvertible, Sendable {
  var operation: String

  var description: String {
    "The infinite-query snapshot observation ended while waiting to \(operation)."
  }
}

private actor InfiniteSnapshotPump {
  private let snapshots: AsyncStream<InstantInfiniteQuerySnapshot>
  private var isWaiting = false

  init(_ snapshots: AsyncStream<InstantInfiniteQuerySnapshot>) {
    self.snapshots = snapshots
  }

  func next(operation: String = #function) async throws -> InstantInfiniteQuerySnapshot? {
    precondition(!isWaiting, "Infinite-query snapshot waits must remain sequential.")
    isWaiting = true
    defer { isWaiting = false }

    return try await nextInfiniteSnapshot(
      operation: "receive the next infinite-query snapshot in \(operation)",
      in: snapshots
    )
  }
}

private actor InfiniteQuerySetupCleanupProbe {
  private(set) var count = 0

  func record() {
    count += 1
  }
}

private actor InfiniteQueryCommandProbe {
  private let navigationBarrier: InfiniteQuerySetupBarrier
  private var navigation: [String] = []
  private var cancelCount = 0
  private var cancelWasAlreadyCancelled = false

  init(navigationBarrier: InfiniteQuerySetupBarrier) {
    self.navigationBarrier = navigationBarrier
  }

  func navigate(_ direction: String) async {
    navigation.append(direction)
    if navigation.count == 1 {
      await navigationBarrier.pause()
    }
  }

  func cancel() {
    cancelCount += 1
    cancelWasAlreadyCancelled = Task.isCancelled
  }

  func state() -> (
    navigation: [String],
    cancelCount: Int,
    cancelWasAlreadyCancelled: Bool
  ) {
    (navigation, cancelCount, cancelWasAlreadyCancelled)
  }
}

private actor InfiniteQueryCancellationUnblockProbe {
  private let navigationBarrier: InfiniteQuerySetupBarrier
  private var navigationCount = 0
  private var cancelCount = 0
  private var cancelWasAlreadyCancelled = false

  init(navigationBarrier: InfiniteQuerySetupBarrier) {
    self.navigationBarrier = navigationBarrier
  }

  func navigate() async {
    navigationCount += 1
    await navigationBarrier.pause()
  }

  func cancel() async {
    cancelCount += 1
    cancelWasAlreadyCancelled = Task.isCancelled
    await navigationBarrier.release()
  }

  func state() -> (
    navigationCount: Int,
    cancelCount: Int,
    cancelWasAlreadyCancelled: Bool
  ) {
    (navigationCount, cancelCount, cancelWasAlreadyCancelled)
  }
}

private final class WeakInfiniteQueryRuntime: @unchecked Sendable {
  private let lock = NSLock()
  private weak var runtime: InstantRuntime?

  init(_ runtime: InstantRuntime) {
    self.runtime = runtime
  }

  var isReleased: Bool {
    lock.withLock { runtime == nil }
  }
}

private func makeRetainedRawInfiniteQueryLifetimeFixture() async throws -> (
  subscription: InstantInfiniteQuerySubscription,
  runtime: WeakInfiniteQueryRuntime
) {
  var runtime: InstantRuntime? = try await InstantRuntime.bootstrap(
    configuration: InstantRuntimeConfiguration(
      appID: "infinite-raw-retained-handle-lifetime",
      persistenceURL: try temporaryInfiniteQueryCacheURL(),
      initialAttributes: infiniteQueryAttributes,
      makeID: { UUID().uuidString.lowercased() }
    )
  )
  let retainedRuntime = try #require(runtime)
  let weakRuntime = WeakInfiniteQueryRuntime(retainedRuntime)
  let subscription = await retainedRuntime.subscribeInfiniteQuery(
    infiniteItemsQuery(limit: 2, order: InstantQueryOrder("value"))
  )
  runtime = nil
  return (subscription, weakRuntime)
}

private actor InfiniteQueryRetirementWatchdogProbe {
  private(set) var milliseconds: UInt64?

  func record(_ milliseconds: UInt64) {
    self.milliseconds = milliseconds
  }
}

private actor InfiniteQueryDeferredHydrationBarrier {
  private var acquiredValueCount: Int?
  private var reachedContinuation: CheckedContinuation<Int, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?
  private var isReleased = false

  func pause(valueCount: Int) async {
    acquiredValueCount = valueCount
    reachedContinuation?.resume(returning: valueCount)
    reachedContinuation = nil
    guard !isReleased else { return }
    await withCheckedContinuation { continuation in
      if isReleased {
        continuation.resume()
      } else {
        releaseContinuation = continuation
      }
    }
  }

  func waitUntilReached() async -> Int {
    if let acquiredValueCount { return acquiredValueCount }
    return await withCheckedContinuation { continuation in
      reachedContinuation = continuation
    }
  }

  func release() {
    isReleased = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private final class InfiniteQueryPayloadBarrier: @unchecked Sendable {
  private let lock = NSLock()
  private var didReach = false
  private var didRelease = false
  private var didCancel = false
  private var payloadCount = 0
  private var reachedContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Error>?

  var isReleased: Bool {
    lock.withLock { didRelease }
  }

  func pause(payloadCount: Int) async throws {
    let reachedContinuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
      self.payloadCount = payloadCount
      didReach = true
      defer { self.reachedContinuation = nil }
      return self.reachedContinuation
    }
    reachedContinuation?.resume()
    try Task.checkCancellation()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        let result = lock.withLock { () -> Result<Void, Error>? in
          if didRelease {
            return .success(())
          }
          if didCancel || Task.isCancelled {
            return .failure(CancellationError())
          }
          releaseContinuation = continuation
          return nil
        }
        if let result {
          continuation.resume(with: result)
        }
      }
    } onCancel: {
      self.cancelPause()
    }
  }

  func waitUntilReached() async -> Int {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let didReach = lock.withLock { () -> Bool in
        if self.didReach {
          return true
        }
        reachedContinuation = continuation
        return false
      }
      if didReach {
        continuation.resume()
      }
    }
    return lock.withLock { payloadCount }
  }

  func release() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
      didRelease = true
      defer { releaseContinuation = nil }
      return releaseContinuation
    }
    continuation?.resume(returning: ())
  }

  private func cancelPause() {
    let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
      didCancel = true
      defer { releaseContinuation = nil }
      return releaseContinuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}

private actor InfiniteQuerySetupBarrier {
  private var isReached = false
  private var isReleased = false
  private var reachedContinuation: CheckedContinuation<Void, Never>?
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  func pause() async {
    guard !isReleased else { return }
    isReached = true
    reachedContinuation?.resume()
    reachedContinuation = nil
    await withCheckedContinuation { continuation in
      if isReleased {
        continuation.resume()
      } else {
        releaseContinuation = continuation
      }
    }
  }

  func waitUntilReached() async {
    guard !isReached else { return }
    await withCheckedContinuation { continuation in
      reachedContinuation = continuation
    }
  }

  func release() {
    isReleased = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }
}

private func waitForInfinitePayloadBarrier(
  _ barrier: InfiniteQueryPayloadBarrier,
  operation: String
) async throws -> Int {
  try await instantLiveWithTimeout(
    operation: operation,
    timeoutMilliseconds: 5_000
  ) {
    await barrier.waitUntilReached()
  }
}

private func waitForInfiniteResidency(
  in subscription: InstantInfiniteQuerySubscription,
  operation: String,
  matching predicate: @escaping @Sendable (InstantInfiniteQueryResidencySnapshot) -> Bool
) async throws -> InstantInfiniteQueryResidencySnapshot {
  try await instantLiveWithTimeout(
    operation: operation,
    timeoutMilliseconds: 5_000
  ) {
    while true {
      try Task.checkCancellation()
      let residency = await subscription.residencySnapshotForTesting()
      if predicate(residency) {
        return residency
      }
      await Task.yield()
    }
  }
}

private func waitForInfiniteSetupBarrier(
  _ barrier: InfiniteQuerySetupBarrier,
  operation: String
) async throws {
  try await instantLiveWithTimeout(
    operation: operation,
    timeoutMilliseconds: 5_000
  ) {
    await barrier.waitUntilReached()
  }
}

private func waitForInfiniteSetupResidencyToClear(
  in runtime: InstantRuntime
) async throws {
  try await instantLiveWithTimeout(
    operation: "clear canceled infinite-query setup residency",
    timeoutMilliseconds: 5_000
  ) {
    while true {
      try Task.checkCancellation()
      let localObservationCount = await runtime.store.activeObservationCount()
      let activeQueryKeys = await runtime.liveActiveQueryKeysForTesting()
      if localObservationCount == 0, activeQueryKeys.isEmpty {
        return
      }
      await Task.yield()
    }
  }
}

private func requireInfiniteSetupReleasedOperationGate(
  in runtime: InstantRuntime
) async throws {
  _ = try await instantLiveWithTimeout(
    operation: "use the operation gate after canceling infinite-query setup",
    timeoutMilliseconds: 5_000
  ) {
    try await runtime.materializeLocalInfiniteQueryIdentity(
      infiniteItemsQuery(limit: 1, order: InstantQueryOrder("value"))
    )
  }
}

private func nextInfiniteSnapshot(
  operation: String,
  in snapshots: AsyncStream<InstantInfiniteQuerySnapshot>,
  matchingIDs expectedIDs: [String]? = nil
) async throws -> InstantInfiniteQuerySnapshot? {
  try await instantLiveWithTimeout(
    operation: operation,
    timeoutMilliseconds: 5_000
  ) {
    try Task.checkCancellation()
    let snapshot = await snapshots.first(where: { snapshot in
      expectedIDs.map { snapshot.values.map(\.id) == $0 } ?? true
    })
    try Task.checkCancellation()
    return snapshot
  }
}

private func waitForInfiniteSnapshot(
  operation: String,
  in snapshots: AsyncStream<InstantInfiniteQuerySnapshot>,
  matchingIDs expectedIDs: [String]? = nil
) async throws -> InstantInfiniteQuerySnapshot {
  guard
    let snapshot = try await nextInfiniteSnapshot(
      operation: operation,
      in: snapshots,
      matchingIDs: expectedIDs
    )
  else {
    throw InfiniteSnapshotObservationEnded(operation: operation)
  }
  return snapshot
}

private func waitForInfiniteQuery(
  in session: LiveReactorParitySession,
  matching predicate: ([String: InstantLiveJSONValue]) -> Bool
) async -> InstantLiveJSONValue? {
  let deadline = ContinuousClock.now + .seconds(5)
  while ContinuousClock.now < deadline {
    let queries = await session.sentMessages()
      .filter { $0.op == "add-query" }
      .compactMap { $0.fields["q"] }
    if let query = queries.last(where: { query in
      infiniteLiveOptions(query).map(predicate) == true
    }) {
      return query
    }
    try? await Task.sleep(for: .milliseconds(5))
  }
  return nil
}

private func waitForActiveInfiniteQueries(
  _ expected: Set<InstantLiveJSONValue>,
  in session: LiveReactorParitySession
) async throws -> Set<InstantLiveJSONValue> {
  let deadline = ContinuousClock.now + .seconds(5)
  while ContinuousClock.now < deadline {
    let active = activeInfiniteQueries(in: await session.sentMessages())
    if active == expected {
      return active
    }
    try await Task.sleep(for: .milliseconds(5))
  }
  return activeInfiniteQueries(in: await session.sentMessages())
}

private func waitForActiveInfiniteQuery(
  _ query: InstantLiveJSONValue,
  in session: LiveReactorParitySession
) async throws -> Bool {
  let deadline = ContinuousClock.now + .seconds(5)
  while ContinuousClock.now < deadline {
    if activeInfiniteQueries(in: await session.sentMessages()).contains(query) {
      return true
    }
    try await Task.sleep(for: .milliseconds(5))
  }
  return activeInfiniteQueries(in: await session.sentMessages()).contains(query)
}

private func activeInfiniteQueries(
  in messages: [InstantLiveMessage]
) -> Set<InstantLiveJSONValue> {
  messages.reduce(into: Set<InstantLiveJSONValue>()) { active, message in
    guard let query = message.fields["q"] else { return }
    switch message.op {
    case "add-query":
      active.insert(query)
    case "remove-query":
      active.remove(query)
    default:
      break
    }
  }
}

private func infiniteQueryRegistrationOperations(
  for query: InstantLiveJSONValue,
  in messages: [InstantLiveMessage]
) -> [String] {
  messages.compactMap { message in
    guard message.fields["q"] == query,
      message.op == "add-query" || message.op == "remove-query"
    else {
      return nil
    }
    return message.op
  }
}

private func waitForInfiniteStoreObservationCount(
  _ expectedCount: Int,
  in runtime: InstantRuntime
) async throws -> Int {
  try await instantLiveWithTimeout(
    operation: "wait for \(expectedCount) local store observers during infinite-query termination",
    timeoutMilliseconds: 5_000
  ) {
    while await runtime.store.activeObservationCount() != expectedCount {
      try Task.checkCancellation()
      try await Task.sleep(for: .milliseconds(5))
    }
    return expectedCount
  }
}

private func infiniteItemsQuery(
  limit: Int,
  order: InstantQueryOrder?
) -> InstantQueryPlan {
  InstantQueryPlan(
    id: "items.infinite",
    namespace: "items",
    order: order,
    limit: limit
  )
}

private func seedInfiniteQueryStore(
  rowCount: Int,
  in runtime: InstantRuntime
) async {
  let timestamp = InstantTimestamp(milliseconds: 1_767_225_600_000)
  var triples: [InstantTriple] = []
  triples.reserveCapacity(rowCount * 2)
  for value in 0..<rowCount {
    let entityID = "seeded-infinite-item-\(value)"
    triples.append(
      InstantTriple(
        entityID: entityID,
        attributeID: InstantAttribute.primaryKeyID(namespace: "items"),
        value: .string(entityID),
        txID: "seed-infinite-query-store",
        txTime: timestamp
      )
    )
    triples.append(
      InstantTriple(
        entityID: entityID,
        attributeID: infiniteQueryValueAttributeID,
        value: .number(Double(value)),
        txID: "seed-infinite-query-store",
        txTime: timestamp
      )
    )
  }
  await runtime.store.replaceSnapshot(
    InstantStoreSnapshot(attributes: infiniteQueryAttributes, triples: triples)
  )
}

private func upsertNumberItems(
  _ values: [Int],
  prefix: String,
  in runtime: InstantRuntime
) async throws {
  try await upsertNumberEntries(
    values.enumerated().map { offset, value in
      ("\(prefix)-\(offset)-\(value)", value)
    },
    transactionID: "tx-\(prefix)-\(UUID().uuidString)",
    in: runtime
  )
}

private func upsertNumberEntries(
  _ entries: [(id: String, value: Int)],
  transactionID: String,
  timestamp: InstantTimestamp? = nil,
  in runtime: InstantRuntime
) async throws {
  let txTime = timestamp ?? InstantTimestamp(
    milliseconds: infiniteQueryTimestamp(for: transactionID)
  )
  try await runtime.transact(
    InstantStoreTransaction(
      id: transactionID,
      operations: entries.flatMap { entry in
        [
          .insert(
            InstantTriple(
              entityID: entry.id,
              attributeID: InstantAttribute.primaryKeyID(namespace: "items"),
              value: .string(entry.id),
              txID: transactionID,
              txTime: txTime
            )
          ),
          .insert(
            InstantTriple(
              entityID: entry.id,
              attributeID: infiniteQueryValueAttributeID,
              value: .number(Double(entry.value)),
              txID: transactionID,
              txTime: txTime
            )
          ),
        ]
      }
    ),
    createdAt: txTime
  )
}

private func deleteNumberItem(
  _ id: String,
  transactionID: String,
  in runtime: InstantRuntime
) async throws {
  let txTime = InstantTimestamp(milliseconds: infiniteQueryTimestamp(for: transactionID))
  try await runtime.transact(
    InstantStoreTransaction(
      id: transactionID,
      operations: [.deleteEntityInNamespace(entityID: id, namespace: "items")]
    ),
    createdAt: txTime
  )
}

private func loadedValues(_ snapshot: InstantInfiniteQuerySnapshot) -> [Int] {
  snapshot.values.compactMap { entity in
    guard case let .one(.number(value)) = entity.values["value"] else { return nil }
    return Int(value)
  }
}

private func temporaryInfiniteQueryCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantInfiniteQueryParityTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func infiniteQueryTimestamp(for transactionID: String) -> Int64 {
  let offset = transactionID.utf8.reduce(Int64(0)) { partial, byte in
    (partial * 31 + Int64(byte)) % 1_000_000
  }
  return 1_767_225_600_000 + offset
}

private let infiniteQueryValueAttributeID = "items/value"

private let infiniteInitialSnapshotSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts empty result [adapted: Swift reads the local first-page snapshot instead of Reactor.getPreviousResult.]"
private let infiniteNoOrderSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts no order field [adapted: Swift observes the local store with implicit serverCreatedAt ordering.]"
private let infiniteAddingNewNumbersSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts adding new numbers [adapted: Swift uses a local infinite-query coordinator over InstantRuntime.observe.]"
private let infiniteNegativeNumbersSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts adding negative numbers [adapted: Swift prepends rows before the initial anchor instead of maintaining separate reverse subscriptions.]"
private let infiniteZeroTwiceSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts add zero twice [adapted: Swift relies on materialized duplicate scalar rows and id tie-breaking.]"
private let infiniteDescendingSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts descending [adapted: Swift expands the local forward page window on loadNextPage.]"
private let infiniteDuplicateBoundarySource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts duplicate boundary values across pages (desc) [adapted: Swift uses full local ordering plus forward page counts instead of chunk subscriptions.]"
private let infiniteRapidLoadSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts rapid loadNextPage calls do not duplicate pages [adapted: upstream calls loadNextPage once; Swift asserts one expansion.]"
private let infiniteDeletingSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts deleting an item [adapted: Swift recomputes the loaded local window after deletion.]"
private let infiniteUpdateSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts updating an out-of-window item can reorder into visible chunk [adapted: Swift recomputes the anchored forward chunk after local updates.]"
private let infinitePageOneAscendingSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts page size 1, asc [adapted: Swift expands one local row per loaded page.]"
private let infinitePageOneDescendingSource =
  "upstream/instant/client/packages/core/__tests__/src/infiniteQuery.e2e.test.ts page size 1, desc [adapted: Swift expands one local row per loaded page.]"
private let infiniteEarlyLoadSource =
  "upstream/instant/client/packages/core/src/infiniteQuery.ts loadNextPage endCursor guard [adapted: Swift loadNextPage no-ops until the current local window can load another page.]"
private let infiniteInvalidQuerySource =
  "upstream/instant/client/packages/core/src/infiniteQuery.ts sendError [adapted: Swift invalid infinite queries emit an error snapshot with no data and canLoadNextPage false.]"
private let infiniteBoundedTransportSource =
  "upstream/instant/client/packages/core/src/infiniteQuery.ts starter, pushNewForward, and pushNewReverse [ported: Swift live infinite queries register only limited or cursor-bounded Reactor subscriptions.]"
private let infiniteLocalStarterSource =
  "upstream/instant/client/packages/core/src/infiniteQuery.ts starter subscription [adapted: Swift emits the locally materialized starter page immediately while awaiting authoritative remote page-info.]"
private let infiniteShortStarterThrashSource =
  "scribe-ipad-jetsam-2026-08-05: short pre-kickstart starter must ignore remote hasNextPage so loadNextPage cannot thrash canLoadNextPage open."
