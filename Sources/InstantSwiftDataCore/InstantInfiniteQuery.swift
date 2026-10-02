import Foundation

/// Controls how many pages an infinite-query subscription keeps resident.
public enum InstantInfiniteQueryRetentionPolicy: Hashable, Codable, Sendable {
  /// Retains every page loaded by the subscription.
  case accumulated
  /// Retains a contiguous sliding window of at most this many pages and evicts the opposite edge as the window
  /// moves.
  ///
  /// Loading the next page evicts pages at the top, and loading the previous page evicts pages at the bottom. While
  /// the window starts at the top of the list, live queries also show rows ordered before the first row, as
  /// upstream's reverse chunk does. Those rows fill pages like any others, so a window at the top follows a live
  /// head by evicting pages at the bottom. Evicted pages load again with `loadNextPage` and `loadPreviousPage`.
  case window(maximumPageCount: Int)

  fileprivate var maximumPageCount: Int? {
    switch self {
    case .accumulated:
      return nil
    case .window(let maximumPageCount):
      return maximumPageCount
    }
  }
}

public struct InstantInfiniteQuerySnapshot: Hashable, Codable, Sendable {
  public var queryID: String
  public var sequence: Int64
  public var values: [InstantEntitySnapshot]
  public var pageInfo: InstantQueryPageInfo?
  public var canLoadNextPage: Bool
  public var canLoadPreviousPage: Bool
  public var error: InstantError?

  public init(
    queryID: String,
    sequence: Int64,
    values: [InstantEntitySnapshot],
    pageInfo: InstantQueryPageInfo? = nil,
    canLoadNextPage: Bool,
    canLoadPreviousPage: Bool = false,
    error: InstantError? = nil
  ) {
    self.queryID = queryID
    self.sequence = sequence
    self.values = values
    self.pageInfo = pageInfo
    self.canLoadNextPage = canLoadNextPage
    self.canLoadPreviousPage = canLoadPreviousPage
    self.error = error
  }
}

package struct InstantInfiniteQueryCommandResidencySnapshot: Equatable, Sendable {
  package var runnerTaskCount: Int
  package var terminalTaskCount: Int
  package var pendingNavigationCount: Int
  package var hasResources: Bool
  package var isTerminalRequested: Bool

  package init(
    runnerTaskCount: Int = 0,
    terminalTaskCount: Int = 0,
    pendingNavigationCount: Int = 0,
    hasResources: Bool = false,
    isTerminalRequested: Bool = false
  ) {
    self.runnerTaskCount = runnerTaskCount
    self.terminalTaskCount = terminalTaskCount
    self.pendingNavigationCount = pendingNavigationCount
    self.hasResources = hasResources
    self.isTerminalRequested = isTerminalRequested
  }
}

/// Owns every closure and task retained by an infinite-query handle.
///
/// Synchronous commands feed one bounded runner. Navigation coalesces to one latest direction,
/// while terminal cleanup has priority and is represented by one memoized task. The resource
/// record is cleared after that exact cleanup finishes, so retaining a canceled public handle
/// cannot retain its coordinator, runtime, or upstream subscription.
// SAFETY: `lock` protects every access to retained resources, task handles,
// navigation, and terminal state.
package final class InstantInfiniteQueryCommandOwner: @unchecked Sendable {
  package typealias Operation = @Sendable () async -> Void
  package typealias ResidencyOperation =
    @Sendable () async -> InstantInfiniteQueryResidencySnapshot

  private enum Navigation: Sendable {
    case next
    case previous
  }

  private struct Resources: Sendable {
    var loadNextPage: Operation
    var loadPreviousPage: Operation
    var cancel: Operation
    var residencySnapshot: ResidencyOperation
  }

  private let lock = NSLock()
  private var resources: Resources?
  private var pendingNavigation: Navigation?
  private var runnerTask: Task<Void, Never>?
  private var terminalTask: Task<Void, Never>?
  private var isTerminalRequested = false
  private var isTerminalComplete = false

  package init(
    loadNextPage: @escaping Operation,
    loadPreviousPage: @escaping Operation = {},
    cancel: @escaping Operation,
    residencySnapshot: @escaping ResidencyOperation = {
      InstantInfiniteQueryResidencySnapshot()
    }
  ) {
    self.resources = Resources(
      loadNextPage: loadNextPage,
      loadPreviousPage: loadPreviousPage,
      cancel: cancel,
      residencySnapshot: residencySnapshot
    )
  }

  deinit {
    let abandoned = lock.withLock { () -> (Resources?, Task<Void, Never>?) in
      guard !isTerminalRequested else { return (nil, runnerTask) }
      isTerminalRequested = true
      pendingNavigation = nil
      let resources = self.resources
      self.resources = nil
      return (resources, runnerTask)
    }
    abandoned.1?.cancel()
    guard let resources = abandoned.0 else { return }
    Task {
      await resources.cancel()
    }
  }

  package func loadNextPage() {
    requestNavigation(.next)
  }

  package func loadPreviousPage() {
    requestNavigation(.previous)
  }

  /// Requests terminal cleanup. This synchronous method does not claim cleanup has finished.
  package func cancel() {
    _ = requestTerminalTask()
  }

  /// Requests terminal cleanup and waits for the one memoized terminal task.
  package func cancelAndWait() async {
    await requestTerminalTask()?.value
  }

  package func residencySnapshot() async -> InstantInfiniteQueryResidencySnapshot {
    let operation = lock.withLock { resources?.residencySnapshot }
    return await operation?() ?? InstantInfiniteQueryResidencySnapshot()
  }

  package func residencySnapshotForTesting()
    -> InstantInfiniteQueryCommandResidencySnapshot
  {
    lock.withLock {
      InstantInfiniteQueryCommandResidencySnapshot(
        runnerTaskCount: runnerTask == nil ? 0 : 1,
        terminalTaskCount: terminalTask == nil ? 0 : 1,
        pendingNavigationCount: pendingNavigation == nil ? 0 : 1,
        hasResources: resources != nil,
        isTerminalRequested: isTerminalRequested
      )
    }
  }

  private func requestNavigation(_ navigation: Navigation) {
    lock.withLock {
      guard resources != nil, !isTerminalRequested else { return }
      pendingNavigation = navigation
      ensureRunnerLocked()
    }
  }

  private func requestTerminalTask() -> Task<Void, Never>? {
    lock.withLock {
      guard !isTerminalComplete else { return nil }
      if let terminalTask {
        return terminalTask
      }
      isTerminalRequested = true
      pendingNavigation = nil
      let navigationTask = runnerTask
      let resources = self.resources
      let task = Task { [weak self] in
        navigationTask?.cancel()
        async let cleanup: Void = resources?.cancel() ?? ()
        async let navigation: Void = navigationTask?.value ?? ()
        _ = await (cleanup, navigation)
        self?.finishTerminalCleanup()
      }
      terminalTask = task
      return task
    }
  }

  private func ensureRunnerLocked() {
    guard runnerTask == nil else { return }
    let task = Task { [weak self] in
      while let operation = self?.takeNextNavigationOperation() {
        await operation()
      }
    }
    runnerTask = task
  }

  private func takeNextNavigationOperation() -> Operation? {
    lock.withLock {
      if isTerminalRequested {
        pendingNavigation = nil
        runnerTask = nil
        return nil
      }
      if let pendingNavigation, let resources {
        self.pendingNavigation = nil
        switch pendingNavigation {
        case .next:
          return resources.loadNextPage
        case .previous:
          return resources.loadPreviousPage
        }
      }
      runnerTask = nil
      return nil
    }
  }

  private func finishTerminalCleanup() {
    lock.withLock {
      // Parity: upstream `infiniteQuery.ts` unsubscribe (509-518) marks the query inactive,
      // invokes its retained unsubscriptions, and clears those references. Swift additionally
      // joins asynchronous cleanup before clearing this one resource record.
      pendingNavigation = nil
      resources = nil
      runnerTask = nil
      terminalTask = nil
      isTerminalComplete = true
    }
  }
}

public struct InstantInfiniteQuerySubscription: Sendable {
  public var snapshots: AsyncStream<InstantInfiniteQuerySnapshot>
  public var loadNextPage: @Sendable () -> Void
  public var loadPreviousPage: @Sendable () -> Void
  /// Cancels the subscription after replacing any buffered payload with an empty terminal
  /// snapshot that preserves the last sequence. Failure termination uses the same empty shape
  /// with its typed error attached.
  public var unsubscribe: @Sendable () -> Void
  private let commandOwner: InstantInfiniteQueryCommandOwner

  public init(
    snapshots: AsyncStream<InstantInfiniteQuerySnapshot>,
    loadNextPage: @escaping @Sendable () -> Void,
    loadPreviousPage: @escaping @Sendable () -> Void = {},
    unsubscribe: @escaping @Sendable () -> Void
  ) {
    let commandOwner = InstantInfiniteQueryCommandOwner(
      loadNextPage: { loadNextPage() },
      loadPreviousPage: { loadPreviousPage() },
      cancel: { unsubscribe() }
    )
    self.snapshots = snapshots
    self.loadNextPage = { commandOwner.loadNextPage() }
    self.loadPreviousPage = { commandOwner.loadPreviousPage() }
    self.unsubscribe = { commandOwner.cancel() }
    self.commandOwner = commandOwner
  }

  package init(
    snapshots: AsyncStream<InstantInfiniteQuerySnapshot>,
    commandOwner: InstantInfiniteQueryCommandOwner
  ) {
    self.snapshots = snapshots
    self.loadNextPage = { commandOwner.loadNextPage() }
    self.loadPreviousPage = { commandOwner.loadPreviousPage() }
    self.unsubscribe = { commandOwner.cancel() }
    self.commandOwner = commandOwner
  }

  /// Requests cancellation and waits until the exact subscription resources have been released.
  /// Repeated calls await the same cleanup task.
  public func unsubscribeAndWait() async {
    await commandOwner.cancelAndWait()
  }

  package func residencySnapshotForTesting() async
    -> InstantInfiniteQueryResidencySnapshot
  {
    await commandOwner.residencySnapshot()
  }

  package func commandResidencySnapshotForTesting()
    -> InstantInfiniteQueryCommandResidencySnapshot
  {
    commandOwner.residencySnapshotForTesting()
  }
}

private extension InstantInfiniteQuerySubscription {
  static var finished: Self {
    let output = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let outputStream = output.stream
    let outputContinuation = output.continuation
    outputContinuation.finish()
    return Self(
      snapshots: outputStream,
      loadNextPage: {},
      loadPreviousPage: {},
      unsubscribe: {}
    )
  }
}

extension InstantRuntime {
  public func subscribeInfiniteQuery(
    _ plan: InstantQueryPlan,
    retentionPolicy: InstantInfiniteQueryRetentionPolicy = .accumulated
  ) async -> InstantInfiniteQuerySubscription {
    guard !Task.isCancelled else { return .finished }
    let validationError = retentionPolicy.validationError(for: plan)
    let error: InstantError?
    if let validationError {
      error = validationError
    } else {
      switch await infiniteQueryValidationOutcome(for: plan.infiniteObservationPlan) {
      case .valid:
        error = nil
      case .invalid(let validationError):
        error = validationError
      case .cancelled:
        return .finished
      }
    }
    guard !Task.isCancelled else { return .finished }
    if let error {
      let stream = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      stream.continuation.yield(
        InstantInfiniteQuerySnapshot(
          queryID: plan.id,
          sequence: 0,
          values: [],
          canLoadNextPage: false,
          error: error
        )
      )
      stream.continuation.finish()
      return InstantInfiniteQuerySubscription(
        snapshots: stream.stream,
        loadNextPage: {},
        loadPreviousPage: {},
        unsubscribe: {}
      )
    }

    let attributes = await store.attributeSnapshot()
    guard !Task.isCancelled else { return .finished }
    if configuration.liveTransport != nil {
      let output = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
        bufferingPolicy: .bufferingNewest(1)
      )
      let outputStream = output.stream
      let outputContinuation = output.continuation
      let coordinator = InstantLiveInfiniteQueryCoordinator(
        runtime: self,
        plan: plan,
        retentionPolicy: retentionPolicy,
        attributes: attributes,
        continuation: outputContinuation
      )
      await coordinator.start()
      if Task.isCancelled {
        await coordinator.unsubscribeAndWait()
        return .finished
      }
      let commandOwner = InstantInfiniteQueryCommandOwner(
        loadNextPage: {
          await coordinator.loadNextPage()
        },
        loadPreviousPage: {
          await coordinator.loadPreviousPage()
        },
        cancel: {
          await coordinator.unsubscribeAndWait()
        },
        residencySnapshot: {
          await coordinator.residencySnapshot()
        }
      )
      outputContinuation.onTermination = { @Sendable [weak commandOwner] _ in
        commandOwner?.cancel()
      }
      return InstantInfiniteQuerySubscription(
        snapshots: outputStream,
        commandOwner: commandOwner
      )
    }

    let coordinator = InstantInfiniteQueryCoordinator(
      plan: plan,
      retentionPolicy: retentionPolicy
    )
    let output = AsyncStream<InstantInfiniteQuerySnapshot>.makeStream(
      bufferingPolicy: .bufferingNewest(1)
    )
    let outputStream = output.stream
    let outputContinuation = output.continuation
    // The local coordinator needs the complete identity/order result to preserve upstream's
    // prepend and out-of-window reorder behavior. Keep that observation payload-free, slice its
    // visible window first, and only then read explicitly selected deferred values from SQLite.
    let observation = await store.observeInfiniteQueryLease(plan.infiniteObservationPlan)
    do {
      try await instantLiveWithTimeout(
        operation: "install local infinite query observation",
        timeoutMilliseconds: 5_000
      ) {
        await self.configuration.onLocalInfiniteQueryObservationInstalledForTesting?()
        try Task.checkCancellation()
      }
      try Task.checkCancellation()
    } catch {
      await observation.cancel()
      await coordinator.cancel()
      outputContinuation.finish()
      return .finished
    }
    let observationStream = observation.stream
    let taskOwner = InstantLocalInfiniteQuerySubscriptionOwner(
      observation: observation,
      onAbandon: {
        await coordinator.cancel()
      }
    )
    let terminalPublicationCheckpoint =
      configuration.onLocalInfiniteQueryTerminalPublishedBeforeObservationCleanupForTesting
    let finish: @Sendable (InstantError?) -> Void = { [weak taskOwner] failure in
      guard let taskOwner else { return }
      taskOwner.startTerminalPublication {
        let terminalSnapshot: InstantInfiniteQuerySnapshot?
        if let failure {
          terminalSnapshot = await coordinator.fail(with: failure)
        } else {
          terminalSnapshot = await coordinator.cancelAndMakeTerminalSnapshot()
        }
        if let terminalSnapshot {
          outputContinuation.yield(terminalSnapshot)
        }
        outputContinuation.finish()
        await terminalPublicationCheckpoint?()
        await taskOwner.completeTerminalCleanup()
      }
    }
    let finishCleanly: @Sendable () -> Void = {
      finish(nil)
    }
    let finishWithFailure: @Sendable (InstantError) -> Void = { failure in
      finish(failure)
    }

    taskOwner.startPrimary {
      do {
        for await emission in observationStream {
          try Task.checkCancellation()
          guard let request = await coordinator.hydrationRequest(for: emission) else { break }
          try await self.configuration.onLocalInfiniteQueryHydrationRequestAcquiredForTesting?(
            request.snapshot.sequence,
            request.snapshot.values.count
          )
          try Task.checkCancellation()
          guard let hydrated = try await self.hydrateDeferredInfiniteQuerySnapshot(
            request.snapshot,
            entityIDs: request.entityIDs,
            plan: plan,
            attributes: attributes
          ) else { continue }
          guard let snapshot = await coordinator.finishHydration(
            request,
            with: hydrated
          ) else { continue }
          guard await coordinator.publish(
            snapshot,
            for: request,
            to: outputContinuation
          ) else { break }
        }
        finishCleanly()
      } catch is CancellationError {
        finishCleanly()
      } catch {
        let failure = self.deferredValueHydrationFailure(error, plan: plan)
        finishWithFailure(failure)
      }
    }

    if Task.isCancelled {
      finishCleanly()
      await taskOwner.waitForTerminalCompletion()
      return .finished
    }

    let navigate: @Sendable (InstantInfiniteQueryNavigationDirection) async -> Void = {
      direction in
      do {
        let request: InstantInfiniteQueryHydrationRequest?
        switch direction {
        case .next:
          request = await coordinator.nextPageHydrationRequest()
        case .previous:
          request = await coordinator.previousPageHydrationRequest()
        case .refresh:
          return
        }
        guard let request else { return }
        try await self.configuration
          .onLocalInfiniteQueryNavigationRequestAcquiredForTesting?(request.snapshot.values.count)
        try Task.checkCancellation()
        guard let hydrated = try await self.hydrateDeferredInfiniteQuerySnapshot(
          request.snapshot,
          entityIDs: request.entityIDs,
          plan: plan,
          attributes: attributes
        ) else { return }
        guard let snapshot = await coordinator.finishHydration(
          request,
          with: hydrated
        ) else { return }
        _ = await coordinator.publish(
          snapshot,
          for: request,
          to: outputContinuation
        )
      } catch is CancellationError {
      } catch {
        let failure = self.deferredValueHydrationFailure(error, plan: plan)
        finishWithFailure(failure)
      }
    }

    let commandOwner = InstantInfiniteQueryCommandOwner(
      loadNextPage: {
        taskOwner.requestNavigation(.next, operation: navigate)
      },
      loadPreviousPage: {
        taskOwner.requestNavigation(.previous, operation: navigate)
      },
      cancel: {
        finishCleanly()
        await taskOwner.waitForTerminalCompletion()
      },
      residencySnapshot: {
        var residency = await coordinator.residencySnapshot()
        residency.ownedTaskCount = taskOwner.activeTaskCount
        residency.navigationReferenceCount += taskOwner.pendingNavigationCount
        return residency
      }
    )
    outputContinuation.onTermination = { @Sendable [weak commandOwner] _ in
      commandOwner?.cancel()
    }
    return InstantInfiniteQuerySubscription(
      snapshots: outputStream,
      commandOwner: commandOwner
    )
  }

  public func infiniteQueryInitialSnapshot(
    _ plan: InstantQueryPlan
  ) async throws -> InstantInfiniteQuerySnapshot {
    let emission = try await queryOnce(plan.infiniteFirstPagePlan)
    return InstantInfiniteQuerySnapshot(
      queryID: plan.id,
      sequence: emission.sequence,
      values: emission.values,
      pageInfo: emission.pageInfo,
      canLoadNextPage: false
    )
  }
}

package struct InstantInfiniteQueryHydrationRequest: Sendable {
  var generation: Int
  var snapshot: InstantInfiniteQuerySnapshot
  var entityIDs: Set<String>
  var reusesHydratedValues: Bool
}

package struct InstantInfiniteQueryResidencySnapshot: Equatable, Sendable {
  package var latestEmissionValueCount: Int
  package var hydratedEntityCount: Int
  package var navigationReferenceCount: Int
  package var ownedTaskCount: Int
  package var inFlightPayloadValueCount: Int
  package var activeSubscriptionCount: Int
  package var retiringSubscriptionCount: Int
  package var pendingSubscriptionCount: Int
  package var retirementWatchdogCount: Int
  package var publishedSnapshotCount: Int
  /// Live chunk subscriptions that have not received a result with page info yet.
  package var awaitingResultSubscriptionCount: Int

  package init(
    latestEmissionValueCount: Int = 0,
    hydratedEntityCount: Int = 0,
    navigationReferenceCount: Int = 0,
    ownedTaskCount: Int = 0,
    inFlightPayloadValueCount: Int = 0,
    activeSubscriptionCount: Int = 0,
    retiringSubscriptionCount: Int = 0,
    pendingSubscriptionCount: Int = 0,
    retirementWatchdogCount: Int = 0,
    publishedSnapshotCount: Int = 0,
    awaitingResultSubscriptionCount: Int = 0
  ) {
    self.latestEmissionValueCount = latestEmissionValueCount
    self.hydratedEntityCount = hydratedEntityCount
    self.navigationReferenceCount = navigationReferenceCount
    self.ownedTaskCount = ownedTaskCount
    self.inFlightPayloadValueCount = inFlightPayloadValueCount
    self.activeSubscriptionCount = activeSubscriptionCount
    self.retiringSubscriptionCount = retiringSubscriptionCount
    self.pendingSubscriptionCount = pendingSubscriptionCount
    self.retirementWatchdogCount = retirementWatchdogCount
    self.publishedSnapshotCount = publishedSnapshotCount
    self.awaitingResultSubscriptionCount = awaitingResultSubscriptionCount
  }
}

// SAFETY: `lock` protects every access to lifecycle, resource, task, and
// navigation state.
private final class InstantLocalInfiniteQuerySubscriptionOwner: @unchecked Sendable {
  typealias NavigationOperation =
    @Sendable (InstantInfiniteQueryNavigationDirection) async -> Void

  private struct CleanupResources: Sendable {
    var observation: InstantStoreQueryObservationLease
    var onAbandon: @Sendable () async -> Void
  }

  private let lock = NSLock()
  private var isTerminating = false
  private var isCleanupComplete = false
  private var cleanupResources: CleanupResources?
  private var primaryTask: Task<Void, Never>?
  private var navigationTask: Task<Void, Never>?
  private var pendingNavigation: InstantInfiniteQueryNavigationDirection?
  private var navigationOperation: NavigationOperation?
  private var terminalTask: Task<Void, Never>?
  private var cleanupTask: Task<Void, Never>?

  init(
    observation: InstantStoreQueryObservationLease,
    onAbandon: @escaping @Sendable () async -> Void
  ) {
    self.cleanupResources = CleanupResources(
      observation: observation,
      onAbandon: onAbandon
    )
  }

  deinit {
    let retained = lock.withLock {
      let retained = (
        primaryTask: primaryTask,
        navigationTask: navigationTask,
        cleanupResources: cleanupResources,
        cleanupTask: cleanupTask
      )
      isTerminating = true
      pendingNavigation = nil
      navigationOperation = nil
      primaryTask = nil
      navigationTask = nil
      terminalTask = nil
      cleanupTask = nil
      cleanupResources = nil
      return retained
    }
    retained.primaryTask?.cancel()
    retained.navigationTask?.cancel()
    if retained.cleanupTask != nil { return }
    guard let resources = retained.cleanupResources else { return }
    Task {
      await resources.observation.cancel()
      await resources.onAbandon()
      await retained.primaryTask?.value
      await retained.navigationTask?.value
    }
  }

  var activeTaskCount: Int {
    lock.withLock {
      (primaryTask == nil ? 0 : 1) + (navigationTask == nil ? 0 : 1)
    }
  }

  var pendingNavigationCount: Int {
    lock.withLock { pendingNavigation == nil ? 0 : 1 }
  }

  func startPrimary(_ operation: @escaping @Sendable () async -> Void) {
    lock.withLock {
      guard !isTerminating, primaryTask == nil else { return }
      primaryTask = Task { [weak self] in
        await operation()
        self?.finishPrimary()
      }
    }
  }

  func requestNavigation(
    _ direction: InstantInfiniteQueryNavigationDirection,
    operation: @escaping NavigationOperation
  ) {
    lock.withLock {
      guard !isTerminating else { return }
      navigationOperation = operation
      guard navigationTask == nil else {
        pendingNavigation = direction
        return
      }
      startNavigationLocked(direction, operation: operation)
    }
  }

  func startTerminalPublication(
    _ operation: @escaping @Sendable () async -> Void
  ) {
    let result = lock.withLock { () -> (didBegin: Bool, task: Task<Void, Never>?) in
      guard !isTerminating else { return (false, nil) }
      isTerminating = true
      pendingNavigation = nil
      navigationOperation = nil
      let task = Task {
        await operation()
      }
      terminalTask = task
      return (true, navigationTask)
    }
    guard result.didBegin else { return }
    result.task?.cancel()
  }

  func waitForTerminalCompletion() async {
    let task = lock.withLock { terminalTask }
    await task?.value
  }

  func completeTerminalCleanup() async {
    let cleanupTask = lock.withLock { () -> Task<Void, Never>? in
      guard !isCleanupComplete else { return nil }
      if let cleanupTask = self.cleanupTask {
        return cleanupTask
      }
      let primaryTask = self.primaryTask
      let navigationTask = self.navigationTask
      let cleanupResources = self.cleanupResources
      primaryTask?.cancel()
      navigationTask?.cancel()
      let cleanupTask = Task { [weak self] in
        await cleanupResources?.observation.cancel()
        await cleanupResources?.onAbandon()
        await primaryTask?.value
        await navigationTask?.value
        self?.finishTerminalCleanup()
      }
      self.cleanupTask = cleanupTask
      return cleanupTask
    }
    await cleanupTask?.value
  }

  private func finishPrimary() {
    lock.withLock {
      primaryTask = nil
    }
  }

  private func finishNavigation() {
    lock.withLock {
      navigationTask = nil
      guard !isTerminating,
        let pendingNavigation,
        let navigationOperation
      else {
        return
      }
      self.pendingNavigation = nil
      startNavigationLocked(pendingNavigation, operation: navigationOperation)
    }
  }

  private func startNavigationLocked(
    _ direction: InstantInfiniteQueryNavigationDirection,
    operation: @escaping NavigationOperation
  ) {
    navigationTask = Task { [weak self] in
      await operation(direction)
      self?.finishNavigation()
    }
  }

  private func finishTerminalCleanup() {
    lock.withLock {
      pendingNavigation = nil
      navigationOperation = nil
      primaryTask = nil
      navigationTask = nil
      terminalTask = nil
      cleanupTask = nil
      cleanupResources = nil
      isCleanupComplete = true
    }
  }
}

private enum InstantLiveInfiniteForwardChunkKey: Hashable, Sendable {
  case preBootstrap
  case cursor(InstantQueryCursor, afterInclusive: Bool)
}

private enum InstantLiveInfiniteSubscriptionKey: Hashable, Sendable {
  case starter
  case forward(InstantLiveInfiniteForwardChunkKey)
  case reverse(InstantQueryCursor)
}

package actor InstantLiveInfiniteSubscriptionSetupLease {
  private var action: (@Sendable () async -> Void)?
  private var task: Task<Void, Never>?
  private var cancellationRequested = false
  private var setupFinished = false

  package func install(_ action: @escaping @Sendable () async -> Void) async -> Bool {
    guard !setupFinished else {
      // A setup path that produces a lease after declaring itself finished is
      // already stale. Clean it instead of letting the late observer escape.
      await action()
      return false
    }
    if cancellationRequested {
      let task = Task { await action() }
      self.task = task
      await task.value
      self.task = nil
      setupFinished = true
      return false
    }
    self.action = action
    return true
  }

  package func cancel() async {
    cancellationRequested = true
    guard !setupFinished else { return }
    if let task {
      await task.value
      return
    }
    if let action {
      self.action = nil
      let task = Task { await action() }
      self.task = task
      await task.value
      self.task = nil
      setupFinished = true
      return
    }
    // Setup has not installed a cleanup action yet. Cancellation must not wait
    // on arbitrary auth, persistence, actor-gate, or transport work. A later
    // install observes `cancellationRequested` and cleans its lease immediately.
  }

  package func finishWithoutInstallation() {
    guard action == nil, task == nil else { return }
    setupFinished = true
  }
}

private struct InstantLiveInfiniteSubscription: Sendable {
  var id: Int
  var task: Task<Void, Never>
  var termination: InstantLiveInfiniteSubscriptionSetupLease
  /// Whether a result with page info has arrived (residency diagnostics only).
  var hasResult = false
}

private struct InstantLiveInfinitePendingSubscription: Sendable {
  var plan: InstantQueryPlan
}

package struct InstantLiveInfiniteSubscriptionRetirementSlot<Pending: Sendable>: Sendable {
  package let retiredSubscriptionID: Int
  package let retiredTask: Task<Void, Never>
  package let cleanupTask: Task<Void, Never>
  package var watchdogTask: Task<Void, Never>?
  package var pendingReplacement: Pending?
  package var didTimeOut: Bool

  package init(
    retiredSubscriptionID: Int,
    retiredTask: Task<Void, Never>,
    cleanupTask: Task<Void, Never>,
    watchdogTask: Task<Void, Never>?,
    pendingReplacement: Pending?,
    didTimeOut: Bool = false
  ) {
    self.retiredSubscriptionID = retiredSubscriptionID
    self.retiredTask = retiredTask
    self.cleanupTask = cleanupTask
    self.watchdogTask = watchdogTask
    self.pendingReplacement = pendingReplacement
    self.didTimeOut = didTimeOut
  }

  package var ownedTaskCount: Int {
    2 + (watchdogTask == nil ? 0 : 1)
  }

  package mutating func coalesce(_ pendingReplacement: Pending?) {
    guard !didTimeOut else { return }
    self.pendingReplacement = pendingReplacement
  }

  package mutating func markTimedOut() {
    didTimeOut = true
    watchdogTask = nil
    pendingReplacement = nil
  }
}

private struct InstantLiveInfiniteChunk: Sendable {
  var data: [InstantEntitySnapshot]
  var sequence: Int64
  var pageInfo: InstantQueryPageInfo?
  var hasMore: Bool
  var endCursor: InstantQueryCursor?
  /// When the coordinator stored this chunk's rows, counted across the window's chunks. Two chunks can hold one row
  /// for a moment after it moves between them; the copy stored later is where the store has it now (#388).
  var storedOrdinal: UInt64 = 0
}

private struct InstantLiveInfiniteReverseAdvance: Hashable, Sendable {
  var startCursor: InstantQueryCursor
  var endCursor: InstantQueryCursor
}

private enum InstantInfiniteQueryNavigationDirection: Equatable, Sendable {
  case next
  case previous
  case refresh
}

private enum InstantLiveInfiniteRetainedChunkKey: Hashable, Sendable {
  case forward(InstantLiveInfiniteForwardChunkKey)
  case reverse(InstantQueryCursor)
}

private actor InstantLiveInfiniteQueryCoordinator {
  private let runtime: InstantRuntime
  private let plan: InstantQueryPlan
  private let retentionPolicy: InstantInfiniteQueryRetentionPolicy
  private let attributes: [InstantAttribute]
  private let pageSize: Int
  private let continuation: AsyncStream<InstantInfiniteQuerySnapshot>.Continuation
  private var subscriptions:
    [InstantLiveInfiniteSubscriptionKey: InstantLiveInfiniteSubscription] = [:]
  private var retiringSubscriptions:
    [
      InstantLiveInfiniteSubscriptionKey:
        InstantLiveInfiniteSubscriptionRetirementSlot<InstantLiveInfinitePendingSubscription>
    ] = [:]
  private var nextSubscriptionID = 0
  private var forwardKeys: [InstantLiveInfiniteForwardChunkKey] = []
  private var forwardChunks: [InstantLiveInfiniteForwardChunkKey: InstantLiveInfiniteChunk] = [:]
  private var reverseKeys: [InstantQueryCursor] = []
  private var reverseChunks: [InstantQueryCursor: InstantLiveInfiniteChunk] = [:]
  private var advancedForwardChunks: Set<InstantLiveInfiniteForwardChunkKey> = []
  private var advancedReverseChunks: Set<InstantLiveInfiniteReverseAdvance> = []
  /// The `before` bound each frozen chunk was frozen with (upstream `freezeForward` and `freezeReverse`). Upstream
  /// starts the next chunk at that same cursor, so when the window loads an evicted neighbor again it starts there.
  private var frozenForwardEndCursors: [InstantLiveInfiniteForwardChunkKey: InstantQueryCursor] = [:]
  private var frozenReverseEndCursors: [InstantQueryCursor: InstantQueryCursor] = [:]
  private var reverseNavigationKeys: Set<InstantQueryCursor> = []
  /// Upstream's live reverse chunk: rows ordered before the first row. It exists only while the window starts at the
  /// top of the list; once it holds rows it is one of the window's pages, like every other chunk.
  private var leadingWatcherKey: InstantQueryCursor?
  private var hasEvictedBefore = false
  private var hasEvictedAfter = false
  private var latestCanLoadPreviousPage = false
  private var hasKickstarted = false
  private var isActive = true
  private var nextPlanID = 0
  /// Local-first expansion while waiting for server liveTuple cursors.
  private var preBootstrapLoadedPages = 1
  private var preBootstrapWindowOffsetPages = 0
  private var preBootstrapPendingNavigation: InstantInfiniteQueryNavigationDirection?
  private var preBootstrapExpandPending = false
  private var preBootstrapHydratedSequence: Int64?
  private var preBootstrapHydratedValuesByEntityID: [String: InstantEntitySnapshot] = [:]
  private var preBootstrapExpansionTask: Task<Void, Never>?
  private var preBootstrapExpansionGeneration = 0
  private var preBootstrapExpansionPayloadValueCount = 0
  /// The server's latest error for each chunk's live query (#360). A failed chunk keeps its rows and its
  /// subscription while the runtime sends the query again; the snapshot reports the error until it clears.
  private var chunkServerErrors: [InstantLiveInfiniteSubscriptionKey: InstantError] = [:]
  private var pushedSnapshotCount = 0
  private var nextStoredChunkOrdinal: UInt64 = 0
  /// The last snapshot this query published (#388).
  private var lastPublishedSnapshot: InstantInfiniteQuerySnapshot?
  /// The kickstart's first forward chunk, until its server answer arrives. The starter's rows leave with the
  /// pre-bootstrap chunk at kickstart, so a snapshot published before that answer would show the window without them:
  /// the Mac's recording list showed no rows for about 0.6 s at every kickstart when the leading watcher answered
  /// first (#388). Until then the coordinator keeps the last published snapshot when it showed rows.
  private var kickstartForwardKeyAwaitingAnswer: InstantLiveInfiniteForwardChunkKey?

  init(
    runtime: InstantRuntime,
    plan: InstantQueryPlan,
    retentionPolicy: InstantInfiniteQueryRetentionPolicy,
    attributes: [InstantAttribute],
    continuation: AsyncStream<InstantInfiniteQuerySnapshot>.Continuation
  ) {
    self.runtime = runtime
    self.plan = plan
    self.retentionPolicy = retentionPolicy
    self.attributes = attributes
    self.pageSize = InstantInfiniteQueryCoordinator.pageSize(for: plan)
    self.continuation = continuation
  }

  func start() {
    guard isActive,
      subscriptions[.starter] == nil,
      retiringSubscriptions[.starter] == nil
    else { return }
    let starterPlan = chunkPlan(
      name: "starter",
      order: resolvedOrder,
      limit: pageSize,
      after: nil,
      before: nil
    )
    InstantInfiniteQueryDiagnostics.record(
      event: "infinite.subscribe.started",
      message: "Live infinite query coordinator started its starter subscription.",
      metadata: [
        "namespace": plan.namespace,
        "pageSize": pageSize.description,
        "planID": plan.id,
        "hasIncludes": ((plan.includes?.isEmpty) == false).description,
      ],
      correlationID: plan.id
    )
    startSubscription(key: .starter, plan: starterPlan)
  }

  func loadNextPage() {
    guard isActive else { return }

    // Before live cursors exist, expand from the local full observation window
    // (starter emissions are limit-sized and never grow on their own).
    if !hasKickstarted {
      // Already closed (short page or expand found no growth): republish so
      // consumers leave isLoadingNextPage without more queryLocally work.
      if let chunk = forwardChunks[.preBootstrap], !chunk.hasMore {
        InstantInfiniteQueryDiagnostics.record(
          event: "infinite.load-next.noop-closed",
          message:
            "loadNextPage no-op: pre-kickstart window already closed (local fullness).",
          metadata: [
            "namespace": plan.namespace,
            "pageSize": pageSize.description,
            "resultCount": chunk.data.count.description,
            "hasKickstarted": "false",
            "phase": "preBootstrap",
          ],
          correlationID: plan.id
        )
        pushSnapshot()
        return
      }
      preBootstrapPendingNavigation = .next
      schedulePreBootstrapExpansion()
      return
    }

    if retentionPolicy.maximumPageCount != nil, hasEvictedAfter {
      reloadPageAfterTheWindow()
      return
    }

    guard let key = forwardKeys.last,
      case .cursor = key,
      let chunk = forwardChunks[key],
      let endCursor = chunk.endCursor,
      advancedForwardChunks.insert(key).inserted
    else {
      // Never leave consumers stuck on "loading next" when we cannot advance
      // (already advanced, missing cursor, or empty forward window).
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.load-next.noop-cannot-advance",
        message:
          "loadNextPage no-op: cannot advance forward cursor after kickstart.",
        metadata: [
          "namespace": plan.namespace,
          "pageSize": pageSize.description,
          "hasKickstarted": "true",
          "phase": "liveCursor",
          "forwardChunkCount": forwardKeys.count.description,
        ],
        correlationID: plan.id
      )
      pushSnapshot()
      return
    }
    InstantInfiniteQueryDiagnostics.record(
      event: "infinite.load-next.advance-cursor",
      message: "loadNextPage advancing past the current live forward cursor.",
      metadata: [
        "namespace": plan.namespace,
        "pageSize": pageSize.description,
        "chunkResultCount": chunk.data.count.description,
        "endEntityFingerprint": InstantInfiniteQueryDiagnostics.fingerprint(
          endCursor.entityID
        ),
        "phase": "liveCursor",
      ],
      correlationID: plan.id
    )
    freezeForward(key: key, chunk: chunk)
    pushNewForward(startCursor: endCursor)
  }

  /// The pages after the window were evicted, by backward navigation or by a live head the window followed. Loads the
  /// page that follows the window again, from the exact cursor where the window ends, so no row is skipped or shown
  /// twice.
  private func reloadPageAfterTheWindow() {
    guard let boundary = windowEndBoundary else {
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.load-next.noop-cannot-advance",
        message: "loadNextPage no-op: the page after the window is already loading.",
        metadata: [
          "namespace": plan.namespace,
          "pageSize": pageSize.description,
          "hasKickstarted": "true",
          "phase": "liveCursor",
          "reason": "pageAfterWindowLoading",
          "forwardChunkCount": forwardKeys.count.description,
        ],
        correlationID: plan.id
      )
      pushSnapshot()
      return
    }
    InstantInfiniteQueryDiagnostics.record(
      event: "infinite.load-next.reload-evicted",
      message: "loadNextPage loading the evicted page after the window again.",
      metadata: [
        "namespace": plan.namespace,
        "pageSize": pageSize.description,
        "startEntityFingerprint": InstantInfiniteQueryDiagnostics.fingerprint(boundary.cursor.entityID),
        "startInclusive": boundary.isInclusive.description,
        "phase": "liveCursor",
      ],
      correlationID: plan.id
    )
    pushNewForward(startCursor: boundary.cursor, afterInclusive: boundary.isInclusive)
  }

  func loadPreviousPage() {
    guard isActive, retentionPolicy.maximumPageCount != nil else { return }
    guard latestCanLoadPreviousPage else {
      pushSnapshot()
      return
    }
    if !hasKickstarted {
      preBootstrapPendingNavigation = .previous
      schedulePreBootstrapExpansion()
      return
    }
    guard let boundary = windowStartBoundary() else {
      pushSnapshot()
      return
    }
    pushNewReverse(
      startCursor: boundary.cursor,
      inclusive: boundary.isInclusive,
      advancesAutomatically: false
    )
  }

  func unsubscribe() {
    guard let sequence = terminateAndReleaseRetainedGraph() else { return }
    continuation.yield(
      InstantInfiniteQuerySnapshot(
        queryID: plan.id,
        sequence: sequence,
        values: [],
        canLoadNextPage: false
      )
    )
    continuation.finish()
  }

  func unsubscribeAndWait() async {
    unsubscribe()
    // Inactivity closes this task set: termination has moved every active subscription into
    // retirement, and no replacement or pre-bootstrap expansion can start afterward. Snapshot
    // only the exact cleanup tasks, not their watchdogs; watchdogs report a five-second stall
    // but never satisfy or abandon cleanup.
    let retirementTasks = retiringSubscriptions.values.map(\.cleanupTask)
    let preBootstrapExpansionTask = self.preBootstrapExpansionTask
    for retirementTask in retirementTasks {
      await retirementTask.value
    }
    await preBootstrapExpansionTask?.value
  }

  private func failSubscription(
    with error: InstantError,
    for key: InstantLiveInfiniteSubscriptionKey,
    subscriptionID: Int
  ) {
    guard subscriptions[key]?.id == subscriptionID else { return }
    failDeferredValueHydration(with: error)
  }

  private func failDeferredValueHydration(with error: InstantError) {
    guard let sequence = terminateAndReleaseRetainedGraph() else { return }
    continuation.yield(
      InstantInfiniteQuerySnapshot(
        queryID: plan.id,
        sequence: sequence,
        values: [],
        canLoadNextPage: false,
        error: error
      )
    )
    continuation.finish()
  }

  private func terminateAndReleaseRetainedGraph() -> Int64? {
    guard isActive else { return nil }
    let sequence = (Array(reverseChunks.values) + Array(forwardChunks.values))
      .map(\.sequence)
      .max()
      ?? 0
    isActive = false
    cancelPreBootstrapExpansion()
    for key in Array(retiringSubscriptions.keys) {
      guard var retirement = retiringSubscriptions[key] else { continue }
      retirement.coalesce(nil)
      retiringSubscriptions[key] = retirement
    }
    for key in Array(subscriptions.keys) {
      retireSubscription(key)
    }

    forwardKeys.removeAll(keepingCapacity: false)
    forwardChunks.removeAll(keepingCapacity: false)
    reverseKeys.removeAll(keepingCapacity: false)
    reverseChunks.removeAll(keepingCapacity: false)
    advancedForwardChunks.removeAll(keepingCapacity: false)
    advancedReverseChunks.removeAll(keepingCapacity: false)
    frozenForwardEndCursors.removeAll(keepingCapacity: false)
    frozenReverseEndCursors.removeAll(keepingCapacity: false)
    reverseNavigationKeys.removeAll(keepingCapacity: false)
    leadingWatcherKey = nil
    hasEvictedBefore = false
    hasEvictedAfter = false
    latestCanLoadPreviousPage = false
    hasKickstarted = false
    kickstartForwardKeyAwaitingAnswer = nil
    lastPublishedSnapshot = nil
    preBootstrapLoadedPages = 1
    preBootstrapWindowOffsetPages = 0
    preBootstrapPendingNavigation = nil
    preBootstrapExpandPending = false
    preBootstrapHydratedSequence = nil
    preBootstrapHydratedValuesByEntityID.removeAll(keepingCapacity: false)
    return sequence
  }

  func residencySnapshot() -> InstantInfiniteQueryResidencySnapshot {
    let pendingSubscriptionCount = retiringSubscriptions.values.count {
      $0.pendingReplacement != nil
    }
    let retirementWatchdogCount = retiringSubscriptions.values.count {
      $0.watchdogTask != nil
    }
    let retirementTaskCount = retiringSubscriptions.values.reduce(0) {
      $0 + $1.ownedTaskCount
    }
    return InstantInfiniteQueryResidencySnapshot(
      latestEmissionValueCount:
        forwardChunks.values.reduce(0) { $0 + $1.data.count }
        + reverseChunks.values.reduce(0) { $0 + $1.data.count },
      hydratedEntityCount: preBootstrapHydratedValuesByEntityID.count,
      navigationReferenceCount: forwardKeys.count + reverseKeys.count
        + advancedForwardChunks.count + advancedReverseChunks.count
        + frozenForwardEndCursors.count + frozenReverseEndCursors.count
        + reverseNavigationKeys.count + (leadingWatcherKey == nil ? 0 : 1)
        + (preBootstrapPendingNavigation == nil ? 0 : 1)
        + pendingSubscriptionCount,
      ownedTaskCount: subscriptions.count + retirementTaskCount
        + (preBootstrapExpansionTask == nil ? 0 : 1),
      inFlightPayloadValueCount: preBootstrapExpansionPayloadValueCount,
      activeSubscriptionCount: subscriptions.count,
      retiringSubscriptionCount: retiringSubscriptions.count,
      pendingSubscriptionCount: pendingSubscriptionCount,
      retirementWatchdogCount: retirementWatchdogCount,
      awaitingResultSubscriptionCount: subscriptions.values.count { !$0.hasResult }
    )
  }

  private func receiveStarter(
    _ emission: InstantQueryEmission,
    subscriptionID: Int
  ) {
    guard subscriptions[.starter]?.id == subscriptionID,
      isActive,
      !hasKickstarted
    else { return }

    // Server-backed page info with opaque live tuple → real live infinite chunks.
    if emission.values.count >= pageSize,
      let startCursor = emission.pageInfo?.startCursor,
      startCursor.liveTuple != nil
    {
      forwardKeys.removeAll { $0 == .preBootstrap }
      forwardChunks[.preBootstrap] = nil
      hasKickstarted = true
      if retentionPolicy.maximumPageCount != nil {
        retireSubscription(.starter)
      }
      cancelPreBootstrapExpansion()
      preBootstrapWindowOffsetPages = 0
      preBootstrapPendingNavigation = nil
      preBootstrapHydratedSequence = nil
      preBootstrapHydratedValuesByEntityID.removeAll(keepingCapacity: false)
      var kickMeta: [String: String] = [
        "namespace": plan.namespace,
        "pageSize": pageSize.description,
        "resultCount": emission.values.count.description,
        "phase": "kickstart",
        "hasMoreSource": "liveTupleKickstart",
      ]
      kickMeta.merge(InstantInfiniteQueryDiagnostics.cursorMetadata(emission.pageInfo)) {
        _, new in new
      }
      kickMeta.merge(
        InstantInfiniteQueryDiagnostics.ownerSampleMetadata(from: emission.values)
      ) { _, new in new }
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.kickstart",
        message:
          "Full starter page with liveTuple cursor; switching to live infinite chunks.",
        metadata: kickMeta,
        correlationID: plan.id
      )
      kickstartForwardKeyAwaitingAnswer = .cursor(startCursor, afterInclusive: true)
      pushNewForward(startCursor: startCursor, afterInclusive: true)
      pushNewReverse(startCursor: startCursor)
      return
    }

    // Local-first / pre-cursor phase.
    cachePreBootstrapHydratedValues(
      emission.values,
      sequence: emission.sequence
    )
    if retentionPolicy.maximumPageCount != nil,
      (preBootstrapLoadedPages > 1 || preBootstrapWindowOffsetPages > 0),
      let existing = forwardChunks[.preBootstrap]
    {
      guard existing.sequence != emission.sequence else { return }
      preBootstrapPendingNavigation = .refresh
      schedulePreBootstrapExpansion()
      return
    }
    // Never clobber a non-empty optimistic page with an empty live emission
    // (logs showed 3→0 flashes while the store still held 20 roots).
    if emission.values.isEmpty,
      let existing = forwardChunks[.preBootstrap],
      !existing.data.isEmpty
    {
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.starter.empty-ignored",
        message:
          "Ignored empty starter emission over a non-empty pre-bootstrap window.",
        metadata: [
          "namespace": plan.namespace,
          "pageSize": pageSize.description,
          "existingCount": existing.data.count.description,
          "phase": "preBootstrap",
        ],
        correlationID: plan.id
      )
      return
    }

    // Keep expanded local window if we already loadNext'd past the starter.
    let data: [InstantEntitySnapshot]
    if let existing = forwardChunks[.preBootstrap],
      existing.data.count > emission.values.count,
      existing.sequence == emission.sequence,
      !emission.values.isEmpty
    {
      // Prefer the larger expanded local window unless starter grew.
      data = existing.data
    } else {
      data = emission.values
      // Reset expansion baseline when starter content changes identity/size down.
      if emission.values.count <= pageSize {
        preBootstrapLoadedPages = max(1, preBootstrapLoadedPages)
      }
    }

    // Pre-kickstart can only expand the local store. Remote `hasNextPage` without
    // a liveTuple kickstart is not actionable — trusting it (1.5.0) left
    // canLoadNextPage=true on short pages forever, and Scribe's list UI
    // onAppear auto-load thrashed until Jetsam (~4 GB, iPad 2026-08-04/05).
    // 1.4.0 always set hasMore=false here; keep local fullness as the only signal.
    let existingClosedWithoutGrowth =
      forwardChunks[.preBootstrap].map { existing in
        !existing.hasMore && existing.data.count >= data.count
      } ?? false
    let remoteHasNext = emission.pageInfo?.hasNextPage
    let localFull = data.count >= pageSize
    let hasMore = !existingClosedWithoutGrowth && localFull
    let hasMoreSource: String
    if existingClosedWithoutGrowth {
      hasMoreSource = "keptClosed"
    } else if localFull {
      hasMoreSource = "localFullness"
    } else {
      hasMoreSource = "shortPageClosed"
    }

    var starterMeta: [String: String] = [
      "namespace": plan.namespace,
      "pageSize": pageSize.description,
      "emissionCount": emission.values.count.description,
      "windowCount": data.count.description,
      "canLoadNextPage": hasMore.description,
      "hasMoreSource": hasMoreSource,
      "remoteHasNextPageIgnored": remoteHasNext.map {
        ($0 && !hasMore).description
      } ?? "nil",
      "remoteHasNextPageRaw": remoteHasNext.map(\.description) ?? "nil",
      "localFullness": localFull.description,
      "phase": "preBootstrap",
      "preBootstrapLoadedPages": preBootstrapLoadedPages.description,
    ]
    starterMeta.merge(InstantInfiniteQueryDiagnostics.cursorMetadata(emission.pageInfo)) {
      _, new in new
    }
    starterMeta.merge(InstantInfiniteQueryDiagnostics.ownerSampleMetadata(from: data)) {
      _, new in new
    }
    InstantInfiniteQueryDiagnostics.record(
      event: "infinite.starter.snapshot",
      message: hasMore
        ? "Pre-kickstart starter page can expand from local fullness."
        : "Pre-kickstart starter page closed (short of page size or already closed).",
      metadata: starterMeta,
      correlationID: plan.id,
      changeKey: plan.id
    )

    setForwardChunk(
      key: .preBootstrap,
      chunk: InstantLiveInfiniteChunk(
        data: data,
        sequence: emission.sequence,
        pageInfo: InstantQueryPageInfo(
          startCursor: data.first.map {
            InstantQueryCursor(entityID: $0.id, sortValue: nil)
          },
          endCursor: data.last.map {
            InstantQueryCursor(entityID: $0.id, sortValue: nil)
          },
          hasPreviousPage: false,
          hasNextPage: hasMore
        ),
        hasMore: hasMore,
        endCursor: data.last.map {
          InstantQueryCursor(entityID: $0.id, sortValue: nil)
        }
      )
    )
  }

  /// Pull a larger local window while waiting for live cursors.
  /// Always re-publishes a snapshot so UI cannot stick on "loading next".
  private func schedulePreBootstrapExpansion() {
    guard isActive, !hasKickstarted else { return }
    if preBootstrapExpansionTask != nil {
      preBootstrapExpandPending = true
      return
    }
    preBootstrapExpansionGeneration += 1
    let generation = preBootstrapExpansionGeneration
    preBootstrapExpansionTask = Task { [weak self] in
      await self?.expandPreBootstrapFromLocalStore(generation: generation)
    }
  }

  private func cancelPreBootstrapExpansion() {
    preBootstrapExpansionGeneration += 1
    preBootstrapExpandPending = false
    preBootstrapExpansionTask?.cancel()
    if preBootstrapExpansionTask == nil {
      preBootstrapExpansionPayloadValueCount = 0
    }
  }

  private func finishPreBootstrapExpansion(generation: Int) {
    preBootstrapExpansionPayloadValueCount = 0
    preBootstrapExpansionTask = nil
    guard preBootstrapExpandPending, isActive, !hasKickstarted else { return }
    preBootstrapExpandPending = false
    schedulePreBootstrapExpansion()
  }

  private func preBootstrapExpansionIsCurrent(_ generation: Int) -> Bool {
    isActive
      && !hasKickstarted
      && generation == preBootstrapExpansionGeneration
      && !Task.isCancelled
  }

  private func expandPreBootstrapFromLocalStore(generation: Int) async {
    defer { finishPreBootstrapExpansion(generation: generation) }
    guard preBootstrapExpansionIsCurrent(generation) else { return }

    let previousLoadedPages = preBootstrapLoadedPages
    let previousWindowOffsetPages = preBootstrapWindowOffsetPages
    let navigation = preBootstrapPendingNavigation ?? .refresh
    preBootstrapPendingNavigation = nil
    if let maximumPageCount = retentionPolicy.maximumPageCount {
      switch navigation {
      case .next:
        if preBootstrapLoadedPages < maximumPageCount {
          preBootstrapLoadedPages += 1
        } else {
          preBootstrapWindowOffsetPages += 1
        }
      case .previous:
        preBootstrapWindowOffsetPages = max(0, preBootstrapWindowOffsetPages - 1)
        preBootstrapLoadedPages = min(maximumPageCount, preBootstrapLoadedPages + 1)
      case .refresh:
        break
      }
    } else if navigation == .next {
      preBootstrapLoadedPages += 1
    }
    let limit = pageSize * preBootstrapLoadedPages
    let expandedPlan = InstantQueryPlan(
      id:
        "\(plan.id)#prebootstrap-expand-\(preBootstrapWindowOffsetPages)-\(preBootstrapLoadedPages)",
      namespace: plan.namespace,
      filters: plan.filters,
      order: plan.order ?? .serverCreatedAt,
      offset: retentionPolicy.maximumPageCount == nil
        ? nil
        : preBootstrapWindowOffsetPages * pageSize,
      limit: limit,
      selectedFields: plan.selectedFields,
      includes: plan.includes ?? []
    )

    do {
      // Expand identity and ordering from the hot store without reading selected deferred
      // payloads. Live cursors kickstart the real path when server page info arrives.
      let emission = try await runtime.materializeLocalInfiniteQueryIdentity(expandedPlan)
      guard preBootstrapExpansionIsCurrent(generation) else { return }

      let existing = forwardChunks[.preBootstrap]
      let rawValues: [InstantEntitySnapshot]
      if retentionPolicy.maximumPageCount != nil {
        if emission.values.isEmpty,
          let existing,
          existing.sequence == emission.sequence,
          !existing.data.isEmpty
        {
          preBootstrapLoadedPages = previousLoadedPages
          preBootstrapWindowOffsetPages = previousWindowOffsetPages
          rawValues = existing.data
        } else {
          rawValues = emission.values
        }
      } else if emission.values.isEmpty,
        let existing,
        existing.sequence == emission.sequence,
        !existing.data.isEmpty
      {
        // No growth; republish existing so consumers leave loading state.
        rawValues = existing.data
        preBootstrapLoadedPages = max(1, preBootstrapLoadedPages - 1)
      } else if let existing,
        existing.sequence == emission.sequence,
        emission.values.count < existing.data.count
      {
        // Don't shrink the window on a partial local read.
        rawValues = existing.data
        preBootstrapLoadedPages = max(1, preBootstrapLoadedPages - 1)
      } else {
        rawValues = emission.values
      }

      let visibleEntityIDs = Set(rawValues.map(\.id))
      let reusesHydratedValues = preBootstrapHydratedSequence == emission.sequence
      let entityIDsToHydrate = reusesHydratedValues
        ? visibleEntityIDs.subtracting(Set(preBootstrapHydratedValuesByEntityID.keys))
        : visibleEntityIDs
      let unhydratedSnapshot = InstantInfiniteQuerySnapshot(
        queryID: plan.id,
        sequence: emission.sequence,
        values: rawValues,
        pageInfo: emission.pageInfo,
        canLoadNextPage: false
      )
      let partiallyHydrated: InstantInfiniteQuerySnapshot
      do {
        let hydrated = try await runtime.hydrateDeferredInfiniteQuerySnapshot(
          unhydratedSnapshot,
          entityIDs: entityIDsToHydrate,
          plan: plan,
          attributes: attributes
        )
        guard preBootstrapExpansionIsCurrent(generation) else { return }
        guard let hydrated else {
          // The raw identity window lost a race with a store publication. Retry from the
          // current store revision rather than combining it with newer SQLite payloads.
          preBootstrapLoadedPages = previousLoadedPages
          preBootstrapWindowOffsetPages = previousWindowOffsetPages
          preBootstrapExpandPending = true
          return
        }
        partiallyHydrated = hydrated
      } catch is CancellationError {
        return
      } catch {
        guard preBootstrapExpansionIsCurrent(generation) else { return }
        let failure = runtime.deferredValueHydrationFailure(error, plan: plan)
        failDeferredValueHydration(with: failure)
        return
      }
      guard preBootstrapExpansionIsCurrent(generation) else { return }
      let values = finishPreBootstrapHydration(
        partiallyHydrated.values,
        hydratedEntityIDs: entityIDsToHydrate,
        sequence: emission.sequence,
        reusesHydratedValues: reusesHydratedValues
      )
      preBootstrapExpansionPayloadValueCount = values.count
      try await runtime.configuration
        .onLiveInfiniteQueryPreBootstrapPayloadAcquiredForTesting?(values.count)
      guard preBootstrapExpansionIsCurrent(generation) else { return }

      // Pre-kickstart expand is local-only. End when the expanded window is not
      // full — never re-open from remote hasNextPage (not actionable without
      // liveTuple, and it caused infinite loadNextPage thrash on Scribe iPad).
      let closedHasMore = retentionPolicy.maximumPageCount == nil
        ? values.count >= limit
        : emission.pageInfo?.hasNextPage ?? (values.count >= limit)
      let canLoadPreviousPage = retentionPolicy.maximumPageCount != nil
        && (preBootstrapWindowOffsetPages > 0
          || emission.pageInfo?.hasPreviousPage == true)
      let priorCount = existing?.data.count ?? 0
      var expandMeta: [String: String] = [
        "namespace": plan.namespace,
        "pageSize": pageSize.description,
        "expandLimit": limit.description,
        "emissionCount": emission.values.count.description,
        "windowCount": values.count.description,
        "priorWindowCount": priorCount.description,
        "grew": (values.count > priorCount).description,
        "canLoadNextPage": closedHasMore.description,
        "hasMoreSource": closedHasMore ? "localFullness" : "expandShortClosed",
        "remoteHasNextPageRaw": emission.pageInfo.map {
          $0.hasNextPage.description
        } ?? "nil",
        "phase": "preBootstrapExpand",
        "preBootstrapLoadedPages": preBootstrapLoadedPages.description,
        "preBootstrapWindowOffsetPages": preBootstrapWindowOffsetPages.description,
      ]
      expandMeta.merge(InstantInfiniteQueryDiagnostics.ownerSampleMetadata(from: values)) {
        _, new in new
      }
      InstantInfiniteQueryDiagnostics.record(
        event: "infinite.expand.snapshot",
        message: closedHasMore
          ? "Pre-kickstart local expand filled the window; more may exist locally."
          : "Pre-kickstart local expand did not fill the window; paging closed.",
        metadata: expandMeta,
        correlationID: plan.id
      )

      setForwardChunk(
        key: .preBootstrap,
        chunk: InstantLiveInfiniteChunk(
          data: values,
          sequence: emission.sequence,
          pageInfo: InstantQueryPageInfo(
            startCursor: emission.pageInfo?.startCursor,
            endCursor: emission.pageInfo?.endCursor,
            hasPreviousPage: canLoadPreviousPage,
            hasNextPage: closedHasMore
          ),
          hasMore: closedHasMore,
          endCursor: emission.pageInfo?.endCursor
        )
      )
    } catch is CancellationError {
      return
    } catch {
      guard preBootstrapExpansionIsCurrent(generation) else { return }
      // Always republish last good chunk so UI unsticks from loadingNextPage.
      preBootstrapLoadedPages = previousLoadedPages
      preBootstrapWindowOffsetPages = previousWindowOffsetPages
      InstantInfiniteQueryDiagnostics.record(
        .warning,
        event: "infinite.expand.failed",
        message: "Pre-kickstart local expand failed; closing paging on last good window.",
        metadata: [
          "namespace": plan.namespace,
          "pageSize": pageSize.description,
          "phase": "preBootstrapExpand",
          "errorType": String(reflecting: type(of: error)),
        ],
        correlationID: plan.id
      )
      if let existing = forwardChunks[.preBootstrap] {
        setForwardChunk(
          key: .preBootstrap,
          chunk: InstantLiveInfiniteChunk(
            data: existing.data,
            sequence: existing.sequence,
            pageInfo: InstantQueryPageInfo(
              startCursor: existing.pageInfo?.startCursor,
              endCursor: existing.pageInfo?.endCursor,
              hasPreviousPage: existing.pageInfo?.hasPreviousPage ?? false,
              hasNextPage: false
            ),
            hasMore: false,
            endCursor: existing.endCursor
          )
        )
      } else {
        pushSnapshot()
      }
    }
  }

  private func cachePreBootstrapHydratedValues(
    _ values: [InstantEntitySnapshot],
    sequence: Int64
  ) {
    if preBootstrapHydratedSequence != sequence {
      preBootstrapHydratedValuesByEntityID.removeAll(keepingCapacity: true)
    }
    preBootstrapHydratedSequence = sequence
    for value in values {
      preBootstrapHydratedValuesByEntityID[value.id] = value
    }
  }

  private func finishPreBootstrapHydration(
    _ partiallyHydratedValues: [InstantEntitySnapshot],
    hydratedEntityIDs: Set<String>,
    sequence: Int64,
    reusesHydratedValues: Bool
  ) -> [InstantEntitySnapshot] {
    let partiallyHydratedByEntityID = Dictionary(
      uniqueKeysWithValues: partiallyHydratedValues.map { ($0.id, $0) }
    )
    let values = partiallyHydratedValues.map { value in
      guard reusesHydratedValues, !hydratedEntityIDs.contains(value.id) else {
        return value
      }
      return preBootstrapHydratedValuesByEntityID[value.id]
        ?? partiallyHydratedByEntityID[value.id]
        ?? value
    }
    preBootstrapHydratedSequence = sequence
    preBootstrapHydratedValuesByEntityID = Dictionary(
      uniqueKeysWithValues: values.map { ($0.id, $0) }
    )
    return values
  }

  private func receiveForward(
    key: InstantLiveInfiniteForwardChunkKey,
    emission: InstantQueryEmission,
    subscriptionID: Int
  ) {
    guard subscriptions[.forward(key)]?.id == subscriptionID,
      isActive,
      let pageInfo = emission.pageInfo
    else { return }
    // The page after the window arrived, so nothing after the window is evicted any more. A refresh of the frozen
    // chunk above an evicted page does not count: that page is still evicted.
    if retentionPolicy.maximumPageCount != nil,
      key == forwardKeys.last,
      frozenForwardEndCursors[key] == nil
    {
      hasEvictedAfter = false
    }
    setForwardChunk(
      key: key,
      chunk: InstantLiveInfiniteChunk(
        data: emission.values,
        sequence: emission.sequence,
        pageInfo: pageInfo,
        hasMore: pageInfo.hasNextPage,
        endCursor: pageInfo.endCursor
      )
    )
  }

  private func receiveReverse(
    startCursor: InstantQueryCursor,
    emission: InstantQueryEmission,
    subscriptionID: Int
  ) {
    guard subscriptions[.reverse(startCursor)]?.id == subscriptionID,
      isActive,
      let pageInfo = emission.pageInfo
    else { return }
    setReverseChunk(
      startCursor: startCursor,
      chunk: InstantLiveInfiniteChunk(
        data: emission.values,
        sequence: emission.sequence,
        pageInfo: pageInfo,
        hasMore: pageInfo.hasNextPage,
        endCursor: pageInfo.endCursor
      )
    )
  }

  private func setForwardChunk(
    key: InstantLiveInfiniteForwardChunkKey,
    chunk: InstantLiveInfiniteChunk
  ) {
    guard isActive else { return }
    if forwardChunks[key] == nil {
      forwardKeys.append(key)
    }
    forwardChunks[key] = stamped(chunk)
    trimRetainedChunks(evicting: .previous)
    pushSnapshot()
  }

  private func setReverseChunk(
    startCursor: InstantQueryCursor,
    chunk: InstantLiveInfiniteChunk
  ) {
    if reverseChunks[startCursor] == nil {
      reverseKeys.append(startCursor)
    }
    reverseChunks[startCursor] = stamped(chunk)
    if reverseNavigationKeys.contains(startCursor) {
      // A page loaded by `loadPreviousPage`. While it is the top chunk and still growing, it says whether rows remain
      // above the window; when none do, the window starts at the top of the list again.
      if startCursor == reverseKeys.last, frozenReverseEndCursors[startCursor] == nil {
        hasEvictedBefore = chunk.hasMore
        if !chunk.hasMore {
          windowReachedTheTop(navigationKey: startCursor)
        }
      }
    } else {
      // The leading watcher, or a page it froze (upstream `setReverseChunk` and `maybeAdvanceReverse`).
      maybeAdvanceReverse()
    }
    // Rows before the window's first row, from backward navigation or a live head the window follows: make room at
    // the bottom.
    trimRetainedChunks(evicting: .next)
    pushSnapshot()
  }

  private func pushNewForward(
    startCursor: InstantQueryCursor,
    afterInclusive: Bool = false
  ) {
    let key = InstantLiveInfiniteForwardChunkKey.cursor(
      startCursor,
      afterInclusive: afterInclusive
    )
    if forwardChunks[key] == nil {
      forwardKeys.append(key)
      forwardChunks[key] = placeholderChunk()
    }
    let queryPlan = chunkPlan(
      name: "forward",
      order: resolvedOrder,
      limit: pageSize,
      after: cursor(startCursor, inclusive: afterInclusive),
      before: nil
    )
    replaceSubscription(key: .forward(key), plan: queryPlan)
  }

  private func freezeForward(
    key: InstantLiveInfiniteForwardChunkKey,
    chunk: InstantLiveInfiniteChunk
  ) {
    guard case let .cursor(startCursor, afterInclusive) = key,
      let endCursor = chunk.endCursor
    else {
      return
    }
    forwardChunks[key] = chunk
    frozenForwardEndCursors[key] = endCursor
    let queryPlan = chunkPlan(
      name: "forward-frozen",
      order: resolvedOrder,
      limit: nil,
      after: cursor(startCursor, inclusive: afterInclusive),
      before: cursor(endCursor, inclusive: true)
    )
    replaceSubscription(key: .forward(key), plan: queryPlan)
  }

  /// Subscribes a reverse chunk: rows ordered before `startCursor`, nearest first (upstream `pushNewReverse`). The
  /// chunk's key is the cursor with `inclusive` set, so a chunk that includes its cursor differs from one that
  /// does not.
  private func pushNewReverse(
    startCursor: InstantQueryCursor,
    inclusive: Bool = false,
    advancesAutomatically: Bool = true
  ) {
    let key = cursor(startCursor, inclusive: inclusive)
    if reverseChunks[key] == nil {
      reverseKeys.append(key)
      reverseChunks[key] = placeholderChunk()
    }
    if advancesAutomatically {
      leadingWatcherKey = key
      reverseNavigationKeys.remove(key)
    } else {
      reverseNavigationKeys.insert(key)
    }
    let queryPlan = chunkPlan(
      name: "reverse",
      order: reversedOrder,
      limit: pageSize,
      after: key,
      before: nil
    )
    replaceSubscription(key: .reverse(key), plan: queryPlan)
  }

  private func freezeReverse(
    startCursor: InstantQueryCursor,
    chunk: InstantLiveInfiniteChunk
  ) {
    guard let endCursor = chunk.endCursor else { return }
    reverseChunks[startCursor] = chunk
    frozenReverseEndCursors[startCursor] = endCursor
    let queryPlan = chunkPlan(
      name: "reverse-frozen",
      order: reversedOrder,
      limit: nil,
      after: startCursor,
      before: cursor(endCursor, inclusive: true)
    )
    replaceSubscription(key: .reverse(startCursor), plan: queryPlan)
  }

  /// Upstream `maybeAdvanceReverse`: a full leading watcher is frozen as a page and a new watcher starts at its end.
  private func maybeAdvanceReverse() {
    guard let startCursor = leadingWatcherKey,
      let chunk = reverseChunks[startCursor],
      chunk.hasMore,
      let endCursor = chunk.endCursor,
      advancedReverseChunks.insert(
        InstantLiveInfiniteReverseAdvance(
          startCursor: startCursor,
          endCursor: endCursor
        )
      ).inserted
    else {
      return
    }
    freezeReverse(startCursor: startCursor, chunk: chunk)
    pushNewReverse(startCursor: endCursor, advancesAutomatically: true)
  }

  /// A page loaded by `loadPreviousPage` found no rows above it: the window starts at the top of the list again.
  /// Watch for rows ordered before it, as upstream's reverse chunk does: freeze the page at its end and start the
  /// leading watcher there. A page without rows becomes the leading watcher itself.
  private func windowReachedTheTop(navigationKey key: InstantQueryCursor) {
    InstantInfiniteQueryDiagnostics.record(
      event: "infinite.window.top-reached",
      message: "The window starts at the top of the list again; watching for rows ordered before it.",
      metadata: [
        "namespace": plan.namespace,
        "pageSize": pageSize.description,
        "pageResultCount": (reverseChunks[key]?.data.count ?? 0).description,
        "phase": "liveCursor",
      ],
      correlationID: plan.id
    )
    guard let chunk = reverseChunks[key], !chunk.data.isEmpty, let endCursor = chunk.endCursor else {
      reverseNavigationKeys.remove(key)
      leadingWatcherKey = key
      return
    }
    freezeReverse(startCursor: key, chunk: chunk)
    pushNewReverse(startCursor: endCursor, advancesAutomatically: true)
  }

  /// Where the page after the window starts: the `before` bound the bottom forward chunk was frozen with, or, when the
  /// window holds only reverse chunks, the bottom one's key (the cursor a reverse chunk grows away from). `nil` while
  /// the page after the window is already loading.
  private var windowEndBoundary: (cursor: InstantQueryCursor, isInclusive: Bool)? {
    if let key = forwardKeys.last {
      guard let endCursor = frozenForwardEndCursors[key] else { return nil }
      return (cursor(endCursor, inclusive: false), false)
    }
    guard let bottom = reverseKeys.first else { return nil }
    return (cursor(bottom, inclusive: false), !bottom.inclusive)
  }

  /// Where the page before the window starts, in reverse order. For a top forward chunk that is its key's cursor, on
  /// the other side of its inclusivity. A top page loaded by `loadPreviousPage` that is still growing is frozen
  /// first, as upstream `loadNextPage` freezes the chunk it grows from, so the new page cannot overlap it. `nil`
  /// while the page before the window is loading, or while the window starts at the top of the list.
  private func windowStartBoundary() -> (cursor: InstantQueryCursor, isInclusive: Bool)? {
    if let top = reverseKeys.last {
      if let endCursor = frozenReverseEndCursors[top] {
        return (cursor(endCursor, inclusive: false), false)
      }
      guard top != leadingWatcherKey,
        let chunk = reverseChunks[top],
        chunk.pageInfo != nil,
        let endCursor = chunk.endCursor
      else {
        return nil
      }
      freezeReverse(startCursor: top, chunk: chunk)
      return (cursor(endCursor, inclusive: false), false)
    }
    guard let first = forwardKeys.first, case let .cursor(startCursor, afterInclusive) = first else {
      return nil
    }
    return (cursor(startCursor, inclusive: false), !afterInclusive)
  }

  /// Keeps at most `maximumPageCount` pages by cutting the window at a page boundary. `.previous` removes the top page
  /// and everything above it (the leading watcher, a page still loading); `.next` removes the bottom page and
  /// everything below it. So no chunk is ever left on the far side of a gap.
  private func trimRetainedChunks(
    evicting direction: InstantInfiniteQueryNavigationDirection
  ) {
    guard let maximumPageCount = retentionPolicy.maximumPageCount else { return }
    while true {
      let pages = retainedPageChunkKeys
      guard pages.count > maximumPageCount else { return }
      let chunks = orderedChunkKeys
      switch direction {
      case .previous:
        guard let cut = pages.first, let index = chunks.firstIndex(of: cut) else { return }
        for key in chunks[...index] {
          removeRetainedChunk(key)
        }
        hasEvictedBefore = true
      case .next:
        guard let cut = pages.last, let index = chunks.lastIndex(of: cut) else { return }
        for key in chunks[index...] {
          removeRetainedChunk(key)
        }
        hasEvictedAfter = true
      case .refresh:
        return
      }
    }
  }

  /// Every chunk from the top of the window to the bottom.
  private var orderedChunkKeys: [InstantLiveInfiniteRetainedChunkKey] {
    reverseKeys.reversed().map(InstantLiveInfiniteRetainedChunkKey.reverse)
      + forwardKeys.map(InstantLiveInfiniteRetainedChunkKey.forward)
  }

  /// The window's pages, top to bottom: every chunk with rows.
  private var retainedPageChunkKeys: [InstantLiveInfiniteRetainedChunkKey] {
    orderedChunkKeys.filter { key in
      switch key {
      case .forward(let forwardKey):
        return forwardChunks[forwardKey]?.data.isEmpty == false
      case .reverse(let startCursor):
        return reverseChunks[startCursor]?.data.isEmpty == false
      }
    }
  }

  private func removeRetainedChunk(_ key: InstantLiveInfiniteRetainedChunkKey) {
    switch key {
    case .forward(let forwardKey):
      forwardKeys.removeAll { $0 == forwardKey }
      forwardChunks[forwardKey] = nil
      advancedForwardChunks.remove(forwardKey)
      frozenForwardEndCursors[forwardKey] = nil
      retireSubscription(.forward(forwardKey))
    case .reverse(let startCursor):
      reverseKeys.removeAll { $0 == startCursor }
      reverseChunks[startCursor] = nil
      reverseNavigationKeys.remove(startCursor)
      frozenReverseEndCursors[startCursor] = nil
      advancedReverseChunks = Set(
        advancedReverseChunks.filter { $0.startCursor != startCursor }
      )
      retireSubscription(.reverse(startCursor))
      if leadingWatcherKey == startCursor {
        leadingWatcherKey = nil
      }
    }
  }

  private func replaceSubscription(
    key: InstantLiveInfiniteSubscriptionKey,
    plan: InstantQueryPlan
  ) {
    guard isActive else { return }
    let pending = InstantLiveInfinitePendingSubscription(plan: plan)
    if var retirement = retiringSubscriptions[key] {
      retirement.coalesce(pending)
      retiringSubscriptions[key] = retirement
      return
    }
    guard subscriptions[key] != nil else {
      startSubscription(key: key, plan: plan)
      return
    }
    beginRetiringSubscription(key, pendingReplacement: pending)
  }

  private func startSubscription(
    key: InstantLiveInfiniteSubscriptionKey,
    plan: InstantQueryPlan
  ) {
    guard isActive,
      subscriptions[key] == nil,
      retiringSubscriptions[key] == nil
    else { return }
    nextSubscriptionID += 1
    let subscriptionID = nextSubscriptionID
    let termination = InstantLiveInfiniteSubscriptionSetupLease()
    let cleanupStarted =
      runtime.configuration.onLiveInfiniteQueryRetirementCleanupStartedForTesting
    // A page loaded by `loadPreviousPage` can repeat an earlier chunk's query exactly (the page above the first page
    // is the original leading watcher's query). That query's stored answer about the rows above it can predate rows
    // that arrived since, and this page's answer decides whether the window reached the top, so it waits for the server.
    let seedsFromStoredResult: Bool
    if case .reverse(let startCursor) = key, reverseNavigationKeys.contains(startCursor) {
      seedsFromStoredResult = false
    } else {
      seedsFromStoredResult = true
    }
    let task = Task { [runtime, weak self] in
      guard !Task.isCancelled else {
        await termination.finishWithoutInstallation()
        return
      }
      let observation: InstantLiveInfiniteQueryChunkObservation
      do {
        observation = try await runtime.observeLiveInfiniteQueryChunk(
          plan,
          seedsFromStoredResult: seedsFromStoredResult,
          onCancellationStarted: {
            await cleanupStarted?(subscriptionID)
          },
          onDeferredValueHydrationFailure: { [weak self] error in
            await self?.failSubscription(
              with: error,
              for: key,
              subscriptionID: subscriptionID
            )
          }
        )
      } catch is CancellationError {
        await termination.finishWithoutInstallation()
        return
      } catch {
        await termination.finishWithoutInstallation()
        let failure = (error as? InstantError) ?? InstantError(
          code: .networkFailed,
          operation: "start live infinite query subscription",
          namespace: plan.namespace,
          message: String(describing: error),
          recovery: "Reconnect Instant, then retry this infinite query subscription."
        )
        await self?.failSubscription(
          with: failure,
          for: key,
          subscriptionID: subscriptionID
        )
        return
      }
      let cancelObservation = observation.cancel
      guard await termination.install({
        await cancelObservation()
      }) else { return }
      if Task.isCancelled {
        return
      }
      for await emission in observation.stream {
        guard !Task.isCancelled else { break }
        await self?.receive(
          emission,
          for: key,
          subscriptionID: subscriptionID
        )
      }
      if !Task.isCancelled {
        await termination.cancel()
      }
    }
    subscriptions[key] = InstantLiveInfiniteSubscription(
      id: subscriptionID,
      task: task,
      termination: termination
    )
  }

  private func retireSubscription(_ key: InstantLiveInfiniteSubscriptionKey) {
    if var retirement = retiringSubscriptions[key] {
      retirement.coalesce(nil)
      retiringSubscriptions[key] = retirement
      return
    }
    beginRetiringSubscription(key, pendingReplacement: nil)
  }

  private func beginRetiringSubscription(
    _ key: InstantLiveInfiniteSubscriptionKey,
    pendingReplacement: InstantLiveInfinitePendingSubscription?
  ) {
    guard retiringSubscriptions[key] == nil,
      let subscription = subscriptions.removeValue(forKey: key)
    else { return }
    chunkServerErrors[key] = nil
    subscription.task.cancel()
    let retiredSubscriptionID = subscription.id
    let cleanupTask = Task { [weak self] in
      await subscription.termination.cancel()
      await subscription.task.value
      await self?.finishRetiringSubscription(
        key,
        retiredSubscriptionID: retiredSubscriptionID
      )
    }
    let watchdogSleep = runtime.configuration.liveInfiniteQueryRetirementWatchdogSleep
    let watchdogTask = Task { [weak self] in
      do {
        try await watchdogSleep(instantLiveOperationTimeoutMilliseconds)
      } catch is CancellationError {
        return
      } catch {
        // A broken test clock or sleeper is itself a failed watchdog deadline.
        // Keep the cleanup visible and fail the query instead of hiding the slot.
      }
      guard !Task.isCancelled else { return }
      await self?.retiringSubscriptionTimedOut(
        key,
        retiredSubscriptionID: retiredSubscriptionID
      )
    }
    retiringSubscriptions[key] = InstantLiveInfiniteSubscriptionRetirementSlot(
      retiredSubscriptionID: retiredSubscriptionID,
      retiredTask: subscription.task,
      cleanupTask: cleanupTask,
      watchdogTask: watchdogTask,
      pendingReplacement: pendingReplacement
    )
  }

  private func finishRetiringSubscription(
    _ key: InstantLiveInfiniteSubscriptionKey,
    retiredSubscriptionID: Int
  ) {
    guard let retirement = retiringSubscriptions[key],
      retirement.retiredSubscriptionID == retiredSubscriptionID
    else { return }
    retirement.watchdogTask?.cancel()
    retiringSubscriptions[key] = nil
    guard isActive,
      !retirement.didTimeOut,
      let pendingReplacement = retirement.pendingReplacement
    else { return }
    startSubscription(key: key, plan: pendingReplacement.plan)
  }

  private func retiringSubscriptionTimedOut(
    _ key: InstantLiveInfiniteSubscriptionKey,
    retiredSubscriptionID: Int
  ) {
    guard var retirement = retiringSubscriptions[key],
      retirement.retiredSubscriptionID == retiredSubscriptionID,
      !retirement.didTimeOut
    else { return }
    retirement.markTimedOut()
    retiringSubscriptions[key] = retirement
    let subscriptionKind: String
    switch key {
    case .starter:
      subscriptionKind = "starter"
    case .forward:
      subscriptionKind = "forward"
    case .reverse:
      subscriptionKind = "reverse"
    }
    InstantInfiniteQueryDiagnostics.record(
      .error,
      event: "infinite.retirement.timeout",
      message: "A live infinite-query observer cleanup exceeded its exact deadline.",
      metadata: [
        "subscriptionKind": subscriptionKind,
        "subscriptionID": retiredSubscriptionID.description,
        "timeoutMilliseconds": instantLiveOperationTimeoutMilliseconds.description,
        "coordinatorActive": isActive.description,
        "cleanupStillOwned": "true",
      ],
      correlationID: plan.id
    )
    guard isActive else { return }
    failDeferredValueHydration(
      with: InstantError(
        code: .implementationFailed,
        operation: "retire live infinite query subscription",
        namespace: plan.namespace,
        message:
          "A live infinite-query subscription did not release within 5,000 milliseconds.",
        recovery:
          "Inspect the stalled query observer cleanup before starting another cursor subscription."
      )
    )
  }

  private func receive(
    _ emission: InstantQueryEmission,
    for key: InstantLiveInfiniteSubscriptionKey,
    subscriptionID: Int
  ) {
    if emission.pageInfo != nil, subscriptions[key]?.id == subscriptionID {
      subscriptions[key]?.hasResult = true
    }
    var serverErrorChanged = false
    if subscriptions[key]?.id == subscriptionID, chunkServerErrors[key] != emission.error {
      chunkServerErrors[key] = emission.error
      serverErrorChanged = true
    }
    let pushedSnapshotCountBefore = pushedSnapshotCount
    defer {
      // An emission that only reports or clears a server error changes no rows, so the chunk handlers may not
      // publish it (#360).
      if serverErrorChanged, pushedSnapshotCount == pushedSnapshotCountBefore {
        pushSnapshot()
      }
    }
    switch key {
    case .starter:
      receiveStarter(emission, subscriptionID: subscriptionID)
    case .forward(let forwardKey):
      receiveForward(
        key: forwardKey,
        emission: emission,
        subscriptionID: subscriptionID
      )
    case .reverse(let startCursor):
      receiveReverse(
        startCursor: startCursor,
        emission: emission,
        subscriptionID: subscriptionID
      )
    }
  }

  private func stamped(_ chunk: InstantLiveInfiniteChunk) -> InstantLiveInfiniteChunk {
    var chunk = chunk
    nextStoredChunkOrdinal &+= 1
    chunk.storedOrdinal = nextStoredChunkOrdinal
    return chunk
  }

  /// The window's rows in order, each entity once (#388).
  ///
  /// A row that moves between chunks leaves one chunk and joins another in the same store commit, but each chunk's
  /// emission reaches the coordinator through its own task, so for a moment both chunks hold it: the chunk that heard
  /// first shows it where it is now, and the other where it was. A chunk frozen by `loadNextPage` keeps its old rows
  /// until its replacement answers, so the moment can last a round trip. Upstream `normalizeChunks` concatenates the
  /// chunks anyway, which costs React a key warning; a consumer keyed by id traps (Scribe's recording list,
  /// `IdentifiedArray(uniqueElements:)`, on the Mac and the iPhone on 2026-10-01). The copy from the newer store
  /// commit wins, and between copies from one commit the chunk stored later; the row keeps that copy's position.
  private static func windowRows(
    reverse orderedReverseChunks: [InstantLiveInfiniteChunk],
    forward orderedForwardChunks: [InstantLiveInfiniteChunk]
  ) -> [InstantEntitySnapshot] {
    let chunks = orderedReverseChunks.map { (chunk: $0, rows: Array($0.data.reversed())) }
      + orderedForwardChunks.map { (chunk: $0, rows: $0.data) }
    var owner: [String: Int] = [:]
    var hasRepeat = false
    for (index, entry) in chunks.enumerated() {
      for row in entry.rows {
        guard let current = owner[row.id] else {
          owner[row.id] = index
          continue
        }
        hasRepeat = true
        let holder = chunks[current].chunk
        if (entry.chunk.sequence, entry.chunk.storedOrdinal) > (holder.sequence, holder.storedOrdinal) {
          owner[row.id] = index
        }
      }
    }
    guard hasRepeat else { return chunks.flatMap(\.rows) }
    var listed = Set<String>()
    var rows: [InstantEntitySnapshot] = []
    for (index, entry) in chunks.enumerated() {
      for row in entry.rows where owner[row.id] == index && listed.insert(row.id).inserted {
        rows.append(row)
      }
    }
    return rows
  }

  private func pushSnapshot() {
    guard isActive else { return }
    if let key = kickstartForwardKeyAwaitingAnswer {
      if let chunk = forwardChunks[key], chunk.pageInfo == nil, var held = lastPublishedSnapshot,
        !held.values.isEmpty
      {
        // Keep the starter's rows until the first forward chunk answers; report a server error on them meanwhile. A
        // window that showed no rows has nothing to keep, so it shows the leading watcher's rows as they arrive.
        let error = currentChunkServerError()
        if held.error != error {
          held.error = error
          lastPublishedSnapshot = held
          pushedSnapshotCount &+= 1
          continuation.yield(held)
        }
        return
      }
      kickstartForwardKeyAwaitingAnswer = nil
    }
    let orderedReverseChunks = reverseKeys.reversed().compactMap { reverseChunks[$0] }
    let orderedForwardChunks = forwardKeys.compactMap { forwardChunks[$0] }
    let values = Self.windowRows(reverse: orderedReverseChunks, forward: orderedForwardChunks)
    let firstReverseChunk = orderedReverseChunks.first(where: { !$0.data.isEmpty })
    let firstForwardChunk = orderedForwardChunks.first(where: { !$0.data.isEmpty })
    let lastReverseChunk = orderedReverseChunks.last(where: { !$0.data.isEmpty })
    let lastForwardChunk = orderedForwardChunks.last(where: { !$0.data.isEmpty })
    let canLoadPreviousPage: Bool
    if retentionPolicy.maximumPageCount == nil {
      canLoadPreviousPage = false
    } else if hasKickstarted {
      // Rows are above the window only when its top was evicted: until then the leading watcher shows them. A
      // chunk's own `hasPreviousPage` cannot say, because the server computes it over the whole list, so it is true
      // whenever the leading watcher holds rows.
      canLoadPreviousPage = hasEvictedBefore
    } else {
      canLoadPreviousPage = firstForwardChunk?.pageInfo?.hasPreviousPage == true
    }
    let canLoadNextPage = hasEvictedAfter || lastForwardChunk?.hasMore == true
    latestCanLoadPreviousPage = canLoadPreviousPage
    let startCursor = firstReverseChunk?.pageInfo?.endCursor
      ?? firstForwardChunk?.pageInfo?.startCursor
    let endCursor = lastForwardChunk?.pageInfo?.endCursor
      ?? lastReverseChunk?.pageInfo?.startCursor
    let sequence = (orderedReverseChunks + orderedForwardChunks)
      .map(\.sequence)
      .max()
      ?? 0
    let pageInfo = (orderedReverseChunks + orderedForwardChunks).isEmpty
      ? nil
      : InstantQueryPageInfo(
        startCursor: startCursor,
        endCursor: endCursor,
        hasPreviousPage: canLoadPreviousPage,
        hasNextPage: canLoadNextPage
      )
    let snapshot = InstantInfiniteQuerySnapshot(
      queryID: plan.id,
      sequence: sequence,
      values: values,
      pageInfo: pageInfo,
      canLoadNextPage: canLoadNextPage,
      canLoadPreviousPage: canLoadPreviousPage,
      error: currentChunkServerError()
    )
    lastPublishedSnapshot = snapshot
    pushedSnapshotCount &+= 1
    continuation.yield(snapshot)
  }

  /// The first chunk's server error, in window order, starting with the starter page (#360).
  private func currentChunkServerError() -> InstantError? {
    guard !chunkServerErrors.isEmpty else { return nil }
    if let error = chunkServerErrors[.starter] {
      return error
    }
    for key in forwardKeys {
      if let error = chunkServerErrors[.forward(key)] { return error }
    }
    for key in reverseKeys {
      if let error = chunkServerErrors[.reverse(key)] { return error }
    }
    return chunkServerErrors.values.first
  }

  private func placeholderChunk() -> InstantLiveInfiniteChunk {
    InstantLiveInfiniteChunk(
      data: [],
      sequence: 0,
      pageInfo: nil,
      hasMore: false,
      endCursor: nil
    )
  }

  private func cursor(
    _ cursor: InstantQueryCursor,
    inclusive: Bool
  ) -> InstantQueryCursor {
    var cursor = cursor
    cursor.inclusive = inclusive
    return cursor
  }

  private var resolvedOrder: InstantQueryOrder {
    plan.order ?? .serverCreatedAt
  }

  private var reversedOrder: InstantQueryOrder {
    InstantQueryOrder(
      resolvedOrder.field,
      resolvedOrder.direction == .ascending ? .descending : .ascending
    )
  }

  private func chunkPlan(
    name: String,
    order: InstantQueryOrder,
    limit: Int?,
    after: InstantQueryCursor?,
    before: InstantQueryCursor?
  ) -> InstantQueryPlan {
    defer { nextPlanID += 1 }
    return InstantQueryPlan(
      id: "\(plan.id).infinite.\(name).\(nextPlanID)",
      namespace: plan.namespace,
      filters: plan.filters,
      order: order,
      limit: limit,
      after: after,
      before: before,
      selectedFields: plan.selectedFields,
      includes: plan.includes ?? []
    )
  }
}

package actor InstantInfiniteQueryCoordinator {
  private let plan: InstantQueryPlan
  private let retentionPolicy: InstantInfiniteQueryRetentionPolicy
  private let pageSize: Int
  private var anchorID: String?
  private var windowAnchorID: String?
  private var windowAnchorIndex = 0
  private var loadedForwardPageCount = 1
  private var latestCanLoadNextPage = false
  private var latestCanLoadPreviousPage = false
  private var latestEmission: InstantQueryEmission?
  private var hydratedSequence: Int64?
  private var lastPublishedSnapshot: InstantInfiniteQuerySnapshot?
  private var hydratedValuesByEntityID: [String: InstantEntitySnapshot] = [:]
  private var hydrationGeneration = 0
  private var isActive = true

  init(
    plan: InstantQueryPlan,
    retentionPolicy: InstantInfiniteQueryRetentionPolicy
  ) {
    self.plan = plan
    self.retentionPolicy = retentionPolicy
    self.pageSize = Self.pageSize(for: plan)
  }

  func hydrationRequest(
    for emission: InstantQueryEmission
  ) -> InstantInfiniteQueryHydrationRequest? {
    guard isActive else { return nil }
    latestEmission = emission
    return makeHydrationRequest(
      for: makeSnapshot(values: emission.values, sequence: emission.sequence)
    )
  }

  func nextPageHydrationRequest() -> InstantInfiniteQueryHydrationRequest? {
    guard isActive, latestCanLoadNextPage, let latestEmission else { return nil }
    advanceWindowForward(in: latestEmission.values)
    return makeHydrationRequest(
      for: makeSnapshot(values: latestEmission.values, sequence: latestEmission.sequence)
    )
  }

  func previousPageHydrationRequest() -> InstantInfiniteQueryHydrationRequest? {
    guard isActive, latestCanLoadPreviousPage, let latestEmission else { return nil }
    advanceWindowBackward(in: latestEmission.values)
    return makeHydrationRequest(
      for: makeSnapshot(values: latestEmission.values, sequence: latestEmission.sequence)
    )
  }

  func finishHydration(
    _ request: InstantInfiniteQueryHydrationRequest,
    with partiallyHydratedSnapshot: InstantInfiniteQuerySnapshot
  ) -> InstantInfiniteQuerySnapshot? {
    guard isActive, request.generation == hydrationGeneration else { return nil }
    var snapshot = partiallyHydratedSnapshot
    if request.reusesHydratedValues {
      snapshot.values = partiallyHydratedSnapshot.values.map { value in
        guard !request.entityIDs.contains(value.id) else { return value }
        return hydratedValuesByEntityID[value.id] ?? value
      }
    }
    hydratedSequence = snapshot.sequence
    hydratedValuesByEntityID = Dictionary(
      uniqueKeysWithValues: snapshot.values.map { ($0.id, $0) }
    )
    return snapshot
  }

  func publish(
    _ snapshot: InstantInfiniteQuerySnapshot,
    for request: InstantInfiniteQueryHydrationRequest,
    to continuation: AsyncStream<InstantInfiniteQuerySnapshot>.Continuation
  ) -> Bool {
    guard isActive,
      request.generation == hydrationGeneration,
      snapshot.sequence == hydratedSequence
    else { return false }
    guard snapshot != lastPublishedSnapshot else { return true }
    if case .terminated = continuation.yield(snapshot) {
      return false
    }
    lastPublishedSnapshot = snapshot
    return true
  }

  func fail(with error: InstantError) -> InstantInfiniteQuerySnapshot? {
    guard let sequence = terminateAndReleaseRetainedGraph() else { return nil }
    return InstantInfiniteQuerySnapshot(
      queryID: plan.id,
      sequence: sequence,
      values: [],
      canLoadNextPage: false,
      error: error
    )
  }

  func cancel() {
    _ = terminateAndReleaseRetainedGraph()
  }

  func cancelAndMakeTerminalSnapshot() -> InstantInfiniteQuerySnapshot? {
    guard let sequence = terminateAndReleaseRetainedGraph() else { return nil }
    return InstantInfiniteQuerySnapshot(
      queryID: plan.id,
      sequence: sequence,
      values: [],
      canLoadNextPage: false
    )
  }

  package func residencySnapshot() -> InstantInfiniteQueryResidencySnapshot {
    InstantInfiniteQueryResidencySnapshot(
      latestEmissionValueCount: latestEmission?.values.count ?? 0,
      hydratedEntityCount: hydratedValuesByEntityID.count,
      navigationReferenceCount: (anchorID == nil ? 0 : 1) + (windowAnchorID == nil ? 0 : 1),
      publishedSnapshotCount: lastPublishedSnapshot == nil ? 0 : 1
    )
  }

  private func terminateAndReleaseRetainedGraph() -> Int64? {
    guard isActive else { return nil }
    let sequence = lastPublishedSnapshot?.sequence ?? 0
    isActive = false
    hydrationGeneration += 1
    anchorID = nil
    windowAnchorID = nil
    windowAnchorIndex = 0
    loadedForwardPageCount = 1
    latestCanLoadNextPage = false
    latestCanLoadPreviousPage = false
    latestEmission = nil
    hydratedSequence = nil
    lastPublishedSnapshot = nil
    hydratedValuesByEntityID.removeAll(keepingCapacity: false)
    return sequence
  }

  private func makeHydrationRequest(
    for snapshot: InstantInfiniteQuerySnapshot
  ) -> InstantInfiniteQueryHydrationRequest {
    hydrationGeneration += 1
    let visibleEntityIDs = Set(snapshot.values.map(\.id))
    let reusesHydratedValues = hydratedSequence == snapshot.sequence
    let entityIDs = reusesHydratedValues
      ? visibleEntityIDs.subtracting(Set(hydratedValuesByEntityID.keys))
      : visibleEntityIDs
    return InstantInfiniteQueryHydrationRequest(
      generation: hydrationGeneration,
      snapshot: snapshot,
      entityIDs: entityIDs,
      reusesHydratedValues: reusesHydratedValues
    )
  }

  private func makeSnapshot(
    values: [InstantEntitySnapshot],
    sequence: Int64
  ) -> InstantInfiniteQuerySnapshot {
    let window = visibleWindow(in: values)
    latestCanLoadNextPage = window.canLoadNextPage
    latestCanLoadPreviousPage = window.canLoadPreviousPage
    return InstantInfiniteQuerySnapshot(
      queryID: plan.id,
      sequence: sequence,
      values: window.values,
      pageInfo: pageInfo(
        for: window.values,
        canLoadPreviousPage: window.canLoadPreviousPage,
        canLoadNextPage: window.canLoadNextPage
      ),
      canLoadNextPage: window.canLoadNextPage,
      canLoadPreviousPage: window.canLoadPreviousPage
    )
  }

  private func visibleWindow(
    in values: [InstantEntitySnapshot]
  ) -> (
    values: [InstantEntitySnapshot],
    canLoadPreviousPage: Bool,
    canLoadNextPage: Bool
  ) {
    if retentionPolicy.maximumPageCount != nil {
      return retainedWindow(in: values)
    }

    guard !values.isEmpty else {
      anchorID = nil
      return ([], false, false)
    }

    if anchorID == nil {
      if values.count < pageSize {
        return (values, false, false)
      }
      anchorID = values[0].id
    }

    guard let anchorID,
      let anchorIndex = values.firstIndex(where: { $0.id == anchorID })
    else {
      self.anchorID = values[0].id
      let visible = Array(values.prefix(forwardLimit))
      return (visible, false, values.count > visible.count)
    }

    let leading = values[..<anchorIndex]
    let forwardValues = values[anchorIndex...]
    let visibleForward = forwardValues.prefix(forwardLimit)
    let visible = Array(leading) + Array(visibleForward)
    return (visible, false, forwardValues.count > visibleForward.count)
  }

  private func retainedWindow(
    in values: [InstantEntitySnapshot]
  ) -> (
    values: [InstantEntitySnapshot],
    canLoadPreviousPage: Bool,
    canLoadNextPage: Bool
  ) {
    guard !values.isEmpty else {
      windowAnchorID = nil
      windowAnchorIndex = 0
      loadedForwardPageCount = 1
      return ([], false, false)
    }

    let startIndex: Int
    if let windowAnchorID,
      let currentIndex = values.firstIndex(where: { $0.id == windowAnchorID })
    {
      startIndex = currentIndex
    } else {
      startIndex = min(windowAnchorIndex, values.count - 1)
      windowAnchorID = values[startIndex].id
    }
    windowAnchorIndex = startIndex
    let endIndex = min(values.count, startIndex + retainedLimit)
    return (
      Array(values[startIndex..<endIndex]),
      startIndex > 0,
      endIndex < values.count
    )
  }

  private func advanceWindowForward(in values: [InstantEntitySnapshot]) {
    guard let maximumPageCount = retentionPolicy.maximumPageCount else {
      loadedForwardPageCount += 1
      return
    }
    guard !values.isEmpty else { return }
    if loadedForwardPageCount < maximumPageCount {
      loadedForwardPageCount += 1
      return
    }
    let currentIndex = windowAnchorID.flatMap { anchorID in
      values.firstIndex(where: { $0.id == anchorID })
    } ?? min(windowAnchorIndex, values.count - 1)
    let nextIndex = min(values.count - 1, currentIndex + pageSize)
    windowAnchorIndex = nextIndex
    windowAnchorID = values[nextIndex].id
  }

  private func advanceWindowBackward(in values: [InstantEntitySnapshot]) {
    guard let maximumPageCount = retentionPolicy.maximumPageCount, !values.isEmpty else {
      return
    }
    let currentIndex = windowAnchorID.flatMap { anchorID in
      values.firstIndex(where: { $0.id == anchorID })
    } ?? min(windowAnchorIndex, values.count - 1)
    let previousIndex = max(0, currentIndex - pageSize)
    windowAnchorIndex = previousIndex
    windowAnchorID = values[previousIndex].id
    loadedForwardPageCount = min(maximumPageCount, loadedForwardPageCount + 1)
  }

  private var forwardLimit: Int {
    pageSize * loadedForwardPageCount
  }

  private var retainedLimit: Int {
    pageSize * loadedForwardPageCount
  }

  private func pageInfo(
    for values: [InstantEntitySnapshot],
    canLoadPreviousPage: Bool,
    canLoadNextPage: Bool
  ) -> InstantQueryPageInfo? {
    guard !values.isEmpty else {
      return InstantQueryPageInfo(
        startCursor: nil,
        endCursor: nil,
        hasPreviousPage: canLoadPreviousPage,
        hasNextPage: canLoadNextPage
      )
    }
    return InstantQueryPageInfo(
      startCursor: values.first.map(cursor(for:)),
      endCursor: values.last.map(cursor(for:)),
      hasPreviousPage: canLoadPreviousPage,
      hasNextPage: canLoadNextPage
    )
  }

  private func cursor(for snapshot: InstantEntitySnapshot) -> InstantQueryCursor {
    InstantQueryCursor(
      entityID: snapshot.id,
      sortValue: plan.order.flatMap { snapshot.values[$0.field]?.first }
    )
  }

  static func pageSize(for plan: InstantQueryPlan) -> Int {
    guard let limit = plan.limit, limit > 0 else { return 10 }
    return limit
  }
}

private enum InstantInfiniteQueryValidationOutcome: Sendable {
  case valid
  case invalid(InstantError)
  case cancelled
}

private extension InstantRuntime {
  func infiniteQueryValidationOutcome(
    for plan: InstantQueryPlan
  ) async -> InstantInfiniteQueryValidationOutcome {
    guard !Task.isCancelled else { return .cancelled }
    let attributes: [InstantAttribute]
    do {
      let synchronizedAttributes = try await attributesForInfiniteQueryValidation()
      attributes = synchronizedAttributes
    } catch is CancellationError {
      return .cancelled
    } catch {
      guard !Task.isCancelled else { return .cancelled }
      attributes = await store.snapshot().attributes
      guard !Task.isCancelled else { return .cancelled }
    }
    guard let issue = TripleIndexes.validate(
      plan,
      attributes: AttributeStore(attributes: attributes)
    ) else {
      return .valid
    }
    return .invalid(
      InstantError(
        code: .validationFailed,
        operation: "validate infinite query",
        namespace: issue.namespace,
        path: issue.path,
        message: issue.message,
        recovery: issue.recovery
      )
    )
  }
}

private extension InstantInfiniteQueryRetentionPolicy {
  func validationError(for plan: InstantQueryPlan) -> InstantError? {
    guard case .window(let maximumPageCount) = self, maximumPageCount < 1 else {
      return nil
    }
    return InstantError(
      code: .validationFailed,
      operation: "validate infinite query retention",
      namespace: plan.namespace,
      path: "retentionPolicy",
      message: "An infinite-query retention window must keep at least one page.",
      recovery: "Use .window(maximumPageCount:) with a positive page count."
    )
  }
}

private extension InstantQueryPlan {
  var infiniteObservationPlan: InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: namespace,
      filters: filters,
      order: order ?? .serverCreatedAt,
      selectedFields: selectedFields,
      includes: includes ?? []
    )
  }

  var infiniteFirstPagePlan: InstantQueryPlan {
    InstantQueryPlan(
      id: id,
      namespace: namespace,
      filters: filters,
      order: order ?? .serverCreatedAt,
      limit: InstantInfiniteQueryCoordinator.pageSize(for: self),
      selectedFields: selectedFields,
      includes: includes ?? []
    )
  }
}
