import Foundation
import IssueReporting

package final class InstantRuntimeExactTaskOwner: @unchecked Sendable {
  struct Handle: Sendable {
    fileprivate var token: UInt64?
    fileprivate var task: Task<Void, Never>?

    func wait() async {
      await task?.value
    }
  }

  private let lock = NSLock()
  private var nextToken: UInt64 = 0
  private var isSuspended = false
  private var running: Handle?
  private var pendingRestartOperation: (@Sendable () async -> Void)?

  @discardableResult
  func start(
    priority: TaskPriority? = nil,
    restartIfRunning: Bool = false,
    operation: @escaping @Sendable () async -> Void
  ) -> Bool {
    lock.withLock {
      guard !isSuspended else { return false }
      guard running == nil else {
        if restartIfRunning {
          pendingRestartOperation = operation
        }
        return false
      }
      nextToken &+= 1
      let token = nextToken
      // The task may begin immediately, but its terminal transition needs this
      // same lock. Install the handle before releasing the lock so completion
      // and stop can never observe an unowned task.
      let task = Task(priority: priority) { [weak self] in
        var nextOperation: (@Sendable () async -> Void)? = operation
        while let currentOperation = nextOperation {
          await currentOperation()
          nextOperation = self?.takeRestartOperationOrFinish(token: token)
        }
      }
      running = Handle(token: token, task: task)
      return true
    }
  }

  func requestStop() -> Handle {
    let handle = lock.withLock {
      isSuspended = true
      pendingRestartOperation = nil
      return running ?? Handle(token: nil, task: nil)
    }
    handle.task?.cancel()
    return handle
  }

  func resume() {
    lock.withLock {
      isSuspended = false
    }
  }

  var isIdle: Bool {
    lock.withLock { running == nil }
  }

  private func takeRestartOperationOrFinish(
    token: UInt64
  ) -> (@Sendable () async -> Void)? {
    lock.withLock {
      guard running?.token == token else { return nil }
      guard !isSuspended else {
        running = nil
        pendingRestartOperation = nil
        return nil
      }
      if let pendingRestartOperation {
        self.pendingRestartOperation = nil
        return pendingRestartOperation
      }
      running = nil
      return nil
    }
  }
}

package struct InstantRuntimeExactCloseIdleState: Sendable {
  var automaticLiveConnection: Bool
  var startupCookieSync: Bool
  var reconnect: Bool
  var receiver: Bool
  var mutationDeliveryPump: Bool
  var explicitMutationFlush: Bool

  var allIdle: Bool {
    automaticLiveConnection
      && startupCookieSync
      && reconnect
      && receiver
      && mutationDeliveryPump
      && explicitMutationFlush
  }

  var nonIdleOwnerNames: [String] {
    var names: [String] = []
    if !automaticLiveConnection { names.append("automatic live connection") }
    if !startupCookieSync { names.append("startup cookie sync") }
    if !reconnect { names.append("live reconnect") }
    if !receiver { names.append("live receiver") }
    if !mutationDeliveryPump { names.append("mutation delivery pump") }
    if !explicitMutationFlush { names.append("explicit mutation flush") }
    return names
  }
}
