// History
// 2026-10-23  #1020  Created. A scripted live session's wait for 51 sent messages had no bound, and on a loaded Mac
//                    mini a run that sent fewer parked the whole InstantSwiftDataCoreTests bundle for 11-16 minutes at
//                    0% CPU. A live test wait now fails at a deadline with what it saw.

import Foundation
@testable import InstantSwiftDataCore

/// Why a live test-support wait gave up (#1020): what the scripted side had seen by its deadline, so a run that sends
/// too little fails in seconds with the messages it did send, instead of parking the suite until someone kills it.
struct InstantLiveTestWaitTimedOut: Error, CustomStringConvertible {
  var wait: String
  var timeout: Duration
  var observed: [String]

  var description: String {
    "Timed out after \(timeout) waiting for \(wait); saw \(observed.count): "
      + observed.joined(separator: ", ")
  }
}

enum InstantLiveTestWait {
  /// A live run sends its next message within milliseconds. 10 s leaves a loaded Mac room and still ends a run that
  /// never will (#1020).
  static let defaultTimeout: Duration = .seconds(10)

  /// One message as a timed-out wait reports it: its op and client event ID.
  static func summary(_ message: InstantLiveMessage) -> String {
    [message.op, message.clientEventID].compactMap { $0 }.joined(separator: " ")
  }
}

/// The tests waiting for a count a scripted live actor raises (sent messages, receive requests, connections), each
/// with the task that fails it at its deadline (#1020). The owning actor keeps it in a stored property and touches it
/// only on its own executor: it appends inside `withCheckedThrowingContinuation`, resumes the waiters a new count
/// satisfies, and fails one from its deadline task. Each continuation is removed before it is resumed, so it resumes
/// exactly once whichever comes first.
struct InstantLiveTestCountWaiters {
  private struct Waiter {
    var id: UUID
    var count: Int
    var continuation: CheckedContinuation<Void, any Error>
    var deadline: Task<Void, Never>
  }

  private var waiters: [Waiter] = []

  mutating func append(
    id: UUID,
    count: Int,
    continuation: CheckedContinuation<Void, any Error>,
    deadline: Task<Void, Never>
  ) {
    waiters.append(Waiter(id: id, count: count, continuation: continuation, deadline: deadline))
  }

  /// Resumes every waiter whose count `count` reaches and cancels its deadline.
  mutating func resume(reaching count: Int) {
    var pending: [Waiter] = []
    for waiter in waiters {
      if count >= waiter.count {
        waiter.deadline.cancel()
        waiter.continuation.resume()
      } else {
        pending.append(waiter)
      }
    }
    waiters = pending
  }

  /// Fails the waiter `id` with the error its awaited count describes, if it is still waiting.
  mutating func fail(_ id: UUID, with error: (_ awaitedCount: Int) -> any Error) {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
    let waiter = waiters.remove(at: index)
    waiter.continuation.resume(throwing: error(waiter.count))
  }
}
