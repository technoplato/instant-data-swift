import CustomDump
import Foundation
@testable import InstantSwiftData
import Testing

@Suite(.serialized)
struct StandardObservationLifecycleTests {
  @Test
  func publicFetchCancellationWaitsForExactStoreCleanupAndRunsOnce() async throws {
    let cleanupBarrier = StandardObservationCleanupBarrier()
    var configuration = InstantRuntimeConfiguration(
      appID: "public-fetch-standard-observation-cleanup",
      persistenceURL: try standardObservationCacheURL(),
      initialAttributes: StandardObservationTodo.instantAttributes
    )
    configuration.onStandardQueryObservationCleanupStartedForTesting = {
      await cleanupBarrier.pause()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let client = InstantSwiftDataClient(runtime: runtime)
    let subscription = await client.subscribe(StandardObservationTodo.query)
    let installedObserverCount = await runtime.store.activeObservationCount()
    expectNoDifference(installedObserverCount, 1)

    let completion = StandardObservationCompletionFlag()
    let lifetime = Task {
      do {
        try await subscription.task
        await completion.finish(error: nil)
      } catch {
        await completion.finish(error: String(describing: error))
      }
    }

    subscription.cancel()
    subscription.cancel()
    try await cleanupBarrier.waitUntilEntered()
    let observerCountWhileCleanupIsBlocked = await runtime.store.activeObservationCount()
    let didCompleteWhileCleanupIsBlocked = await completion.didFinish
    expectNoDifference(observerCountWhileCleanupIsBlocked, 1)
    #expect(!didCompleteWhileCleanupIsBlocked)

    await cleanupBarrier.release()
    _ = try await instantLiveWithTimeout(
      operation: "finish public Fetch cancellation after exact Store cleanup",
      timeoutMilliseconds: 5_000,
      onAbandon: { lifetime.cancel() }
    ) {
      await lifetime.value
    }
    let finalObserverCount = await runtime.store.activeObservationCount()
    let cleanupEntryCount = await cleanupBarrier.entryCount
    let completionError = await completion.error
    expectNoDifference(finalObserverCount, 0)
    expectNoDifference(cleanupEntryCount, 1)
    expectNoDifference(completionError, nil)
  }

  @Test
  func publicFetchTaskCancellationWaitsForExactStoreCleanup() async throws {
    let cleanupBarrier = StandardObservationCleanupBarrier()
    var configuration = InstantRuntimeConfiguration(
      appID: "public-fetch-task-standard-observation-cleanup",
      persistenceURL: try standardObservationCacheURL(),
      initialAttributes: StandardObservationTodo.instantAttributes
    )
    configuration.onStandardQueryObservationCleanupStartedForTesting = {
      await cleanupBarrier.pause()
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let client = InstantSwiftDataClient(runtime: runtime)
    let fetch = FetchAll<StandardObservationTodo>(StandardObservationTodo.query)
    let completion = StandardObservationCompletionFlag()
    let lifetime = Task {
      do {
        try await fetch.task(using: client)
        await completion.finish(error: nil)
      } catch {
        await completion.finish(error: String(describing: error))
      }
    }
    try await instantLiveWithTimeout(
      operation: "wait for public Fetch task Store observation",
      timeoutMilliseconds: 5_000,
      onAbandon: { lifetime.cancel() }
    ) {
      while await runtime.store.activeObservationCount() != 1 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }

    lifetime.cancel()
    try await cleanupBarrier.waitUntilEntered()
    let observerCountWhileCleanupIsBlocked = await runtime.store.activeObservationCount()
    let didCompleteWhileCleanupIsBlocked = await completion.didFinish
    expectNoDifference(observerCountWhileCleanupIsBlocked, 1)
    #expect(!didCompleteWhileCleanupIsBlocked)

    await cleanupBarrier.release()
    _ = try await instantLiveWithTimeout(
      operation: "finish public Fetch task after exact Store cleanup",
      timeoutMilliseconds: 5_000,
      onAbandon: { lifetime.cancel() }
    ) {
      await lifetime.value
    }
    let finalObserverCount = await runtime.store.activeObservationCount()
    let cleanupEntryCount = await cleanupBarrier.entryCount
    let didFinish = await completion.didFinish
    expectNoDifference(finalObserverCount, 0)
    expectNoDifference(cleanupEntryCount, 1)
    #expect(didFinish)
  }

  @Test
  func retainedCanceledFetchHandleReleasesCompletedCleanupCaptureGraph() async throws {
    let invocationCount = StandardObservationInvocationCount()
    var probe: StandardObservationLifetimeProbe? = StandardObservationLifetimeProbe()
    weak var weakProbe = probe
    let subscription = makeRetainedProbeSubscription(
      probe: probe!,
      invocationCount: invocationCount
    )
    probe = nil
    #expect(weakProbe != nil)

    subscription.cancel()
    subscription.cancel()
    _ = try await instantLiveWithTimeout(
      operation: "finish retained Fetch cleanup exactly once",
      timeoutMilliseconds: 5_000
    ) {
      try await subscription.task
    }

    let count = await invocationCount.value
    expectNoDifference(count, 1)
    #expect(weakProbe == nil)
    withExtendedLifetime(subscription) {}
  }

  @Test
  func retainedNaturallyFinishedMappedFetchReleasesChildAndPreservesFinalBuffer() async throws {
    let invocationCount = StandardObservationInvocationCount()
    var probe: StandardObservationLifetimeProbe? = StandardObservationLifetimeProbe()
    weak var weakProbe = probe
    let source = AsyncThrowingStream<Int, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let child = FetchSubscription<Int>(
      stream: source.stream,
      cancelAndWait: { [capturedProbe = probe!] in
        _ = capturedProbe
        await invocationCount.record()
      }
    )
    source.continuation.yield(21)
    source.continuation.finish()
    let mapped = child.map { $0 * 2 }
    probe = nil

    try await instantLiveWithTimeout(
      operation: "finish a finite mapped Fetch subscription",
      timeoutMilliseconds: 5_000,
      onAbandon: { mapped.cancel() }
    ) {
      try await mapped.task
    }

    let cleanupCount = await invocationCount.value
    expectNoDifference(cleanupCount, 1)
    #expect(weakProbe == nil)

    var values: [Int] = []
    for try await value in mapped {
      values.append(value)
    }
    expectNoDifference(values, [42])

    mapped.cancel()
    mapped.cancel()
    try await mapped.task
    let repeatedCleanupCount = await invocationCount.value
    expectNoDifference(repeatedCleanupCount, 1)
    withExtendedLifetime(mapped) {}
  }

  @Test
  func naturalFetchCompletionDoesNotMasqueradeAsSetupCancellation() async throws {
    let naturalCompletionCount = StandardObservationInvocationCount()
    let naturallyFinished = FetchSubscriptionCancellation()
    naturallyFinished.finish()
    naturallyFinished.install {
      await naturalCompletionCount.record()
    }

    #expect(!naturallyFinished.completeSetup())
    try await instantLiveWithTimeout(
      operation: "finish natural Fetch cleanup before setup handoff",
      timeoutMilliseconds: 5_000
    ) {
      await naturallyFinished.wait()
    }
    let completedCount = await naturalCompletionCount.value
    expectNoDifference(completedCount, 1)

    let explicitCancellationCount = StandardObservationInvocationCount()
    let explicitlyCancelled = FetchSubscriptionCancellation()
    explicitlyCancelled.finish()
    explicitlyCancelled.cancelBeforeSetupCompletes()
    explicitlyCancelled.install {
      await explicitCancellationCount.record()
    }

    #expect(explicitlyCancelled.completeSetup())
    try await instantLiveWithTimeout(
      operation: "finish explicit Fetch cleanup after natural completion",
      timeoutMilliseconds: 5_000
    ) {
      await explicitlyCancelled.wait()
    }
    let cancelledCount = await explicitCancellationCount.value
    expectNoDifference(cancelledCount, 1)

    let transferredCleanupCount = StandardObservationInvocationCount()
    let transferred = FetchSubscriptionCancellation()
    transferred.install {
      await transferredCleanupCount.record()
    }
    #expect(!transferred.completeSetup())
    transferred.cancelBeforeSetupCompletes()
    await Task.yield()
    let countAfterLateSetupCancellation = await transferredCleanupCount.value
    expectNoDifference(countAfterLateSetupCancellation, 0)

    transferred.cancel()
    try await instantLiveWithTimeout(
      operation: "clean an explicitly cancelled Fetch after setup ownership transfer",
      timeoutMilliseconds: 5_000
    ) {
      await transferred.wait()
    }
    let transferredCount = await transferredCleanupCount.value
    expectNoDifference(transferredCount, 1)
  }

  @Test
  func explicitCancellationAfterNaturalFinishEvictsUnreadFinalBuffer() async throws {
    let cleanupCount = StandardObservationInvocationCount()
    let source = AsyncThrowingStream<Int, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let child = FetchSubscription<Int>(
      stream: source.stream,
      cancelAndWait: {
        await cleanupCount.record()
      }
    )
    source.continuation.yield(21)
    source.continuation.finish()
    let mapped = child.map { $0 * 2 }

    try await instantLiveWithTimeout(
      operation: "finish a finite Fetch before explicit buffer eviction",
      timeoutMilliseconds: 5_000,
      onAbandon: { mapped.cancel() }
    ) {
      try await mapped.task
    }
    mapped.cancel()

    var iterator = mapped.makeAsyncIterator()
    let value = try await iterator.next()
    #expect(value == nil)
    let count = await cleanupCount.value
    expectNoDifference(count, 1)
  }

  @Test
  func combinedFetchFailsPromptlyAndCancelsItsStillLiveSibling() async throws {
    let failingSource = AsyncThrowingStream<Int, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let liveSource = AsyncThrowingStream<String, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let failingCleanupCount = StandardObservationInvocationCount()
    let liveCleanupCount = StandardObservationInvocationCount()
    let failing = FetchSubscription<Int>(
      stream: failingSource.stream,
      cancelAndWait: {
        failingSource.continuation.finish()
        await failingCleanupCount.record()
      }
    )
    let live = FetchSubscription<String>(
      stream: liveSource.stream,
      cancelAndWait: {
        liveSource.continuation.finish()
        await liveCleanupCount.record()
      }
    )
    let combined = combineLatest(failing, live)

    failingSource.continuation.finish(throwing: StandardObservationFiniteFailure())
    try await instantLiveWithTimeout(
      operation: "fail a combined Fetch and cancel its still-live sibling",
      timeoutMilliseconds: 5_000,
      onAbandon: { combined.cancel() }
    ) {
      try await combined.task
    }

    let failingCount = await failingCleanupCount.value
    let liveCount = await liveCleanupCount.value
    expectNoDifference(failingCount, 1)
    expectNoDifference(liveCount, 1)

    do {
      for try await _ in combined {}
      Issue.record("Expected the combined Fetch subscription to retain its terminal error.")
    } catch {
      #expect(error is StandardObservationFiniteFailure)
    }
  }
}

private actor StandardObservationCleanupBarrier {
  private var didRelease = false
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var entryCount = 0

  func pause() async {
    entryCount += 1
    guard !didRelease else { return }
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func waitUntilEntered() async throws {
    try await instantLiveWithTimeout(
      operation: "wait for public Fetch Store cleanup to start",
      timeoutMilliseconds: 5_000
    ) {
      while await self.entryCount == 0 {
        try Task.checkCancellation()
        await Task.yield()
      }
    }
  }

  func release() {
    didRelease = true
    continuation?.resume()
    continuation = nil
  }
}

private actor StandardObservationCompletionFlag {
  private(set) var didFinish = false
  private(set) var error: String?

  func finish(error: String?) {
    didFinish = true
    self.error = error
  }
}

private actor StandardObservationInvocationCount {
  private(set) var value = 0

  func record() {
    value += 1
  }
}

private final class StandardObservationLifetimeProbe: @unchecked Sendable {}

private struct StandardObservationFiniteFailure: Error {}

private func makeRetainedProbeSubscription(
  probe: StandardObservationLifetimeProbe,
  invocationCount: StandardObservationInvocationCount
) -> FetchSubscription<StandardObservationLifetimeProbe> {
  let stream = AsyncThrowingStream<StandardObservationLifetimeProbe, Error>.makeStream(
    bufferingPolicy: .bufferingNewest(1)
  )
  stream.continuation.yield(probe)
  return FetchSubscription<StandardObservationLifetimeProbe>(
    stream: stream.stream,
    cancelAndWait: { [capturedProbe = probe] in
      _ = capturedProbe
      await invocationCount.record()
      stream.continuation.finish()
    }
  )
}

private struct StandardObservationTodo: Hashable, Codable, InstantEntityModel {
  var id: InstantID<StandardObservationTodo>
  var text: String

  static let instantNamespace = "standard_observation_lifecycle_todos"
  static let text = InstantAttributePath<StandardObservationTodo, String>("text")
  static let instantAttributes = [
    InstantAttribute(
      id: "standard-observation-lifecycle-todos/text",
      namespace: instantNamespace,
      name: "text",
      valueType: .string,
      isIndexed: true
    )
  ]

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .string(text) = snapshot.values["text"]?.first else {
      throw InstantError(
        code: .validationFailed,
        operation: "decode standard observation lifecycle todo",
        namespace: Self.instantNamespace,
        path: "text",
        localID: snapshot.id,
        message: "Expected a string text value.",
        recovery: "Store a string in the text attribute before decoding this fixture."
      )
    }
    self.text = text
  }
}

private func standardObservationCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("StandardObservationLifecycleTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}
