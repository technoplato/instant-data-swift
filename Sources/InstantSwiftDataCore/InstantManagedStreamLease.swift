import Foundation

// SAFETY: `lock` linearizes the synchronous cancellation request across every
// copy of a lease. The asynchronous owner clears its operation capture after
// exact cleanup completes.
private final class InstantManagedStreamLeaseState: @unchecked Sendable {
  private let lock = NSLock()
  private let owner: InstantAsyncCancellationOwner
  private var onCancellationRequested: (@Sendable () -> Void)?

  init(
    onCancellationRequested: @escaping @Sendable () -> Void
  ) {
    self.onCancellationRequested = onCancellationRequested
    self.owner = InstantAsyncCancellationOwner()
  }

  func install(cancelAndWait: @escaping @Sendable () async -> Void) {
    owner.install(cancelAndWait: cancelAndWait)
  }

  func requestCancellation() {
    let operation = lock.withLock { () -> (@Sendable () -> Void)? in
      defer { onCancellationRequested = nil }
      return onCancellationRequested
    }
    operation?()
    owner.cancel()
  }

  func cancelAndWait() async {
    requestCancellation()
    await owner.wait()
  }
}

/// A stream paired with the exact lifetime of the work that produces it.
///
/// Cancellation is idempotent across every copy. The synchronous cancellation
/// request runs once, then `cancelAndWait()` waits until the producer has
/// released all of its owned resources.
package struct InstantManagedStreamLease<Stream: Sendable>: Sendable {
  package let stream: Stream
  private let state: InstantManagedStreamLeaseState

  package init(
    stream: Stream,
    onCancellationRequested: @escaping @Sendable () -> Void = {}
  ) {
    self.stream = stream
    self.state = InstantManagedStreamLeaseState(
      onCancellationRequested: onCancellationRequested
    )
  }

  package init(
    stream: Stream,
    onCancellationRequested: @escaping @Sendable () -> Void = {},
    cancelAndWait: @escaping @Sendable () async -> Void
  ) {
    self.init(
      stream: stream,
      onCancellationRequested: onCancellationRequested
    )
    state.install(cancelAndWait: cancelAndWait)
  }

  package var cancellationRequest: @Sendable () -> Void {
    { [state] in state.requestCancellation() }
  }

  package func install(cancelAndWait: @escaping @Sendable () async -> Void) {
    state.install(cancelAndWait: cancelAndWait)
  }

  package func cancelAndWait() async {
    await state.cancelAndWait()
  }
}
