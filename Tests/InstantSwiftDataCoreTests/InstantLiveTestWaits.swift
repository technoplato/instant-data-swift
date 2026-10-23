// History
// 2026-10-23  #1020  Created. A scripted live session's wait for 51 sent messages had no bound, and on a loaded Mac
//                    mini a run that sent fewer parked the whole InstantSwiftDataCoreTests bundle for 11-16 minutes at
//                    0% CPU. A live test wait now fails at a deadline with what it saw.
// 2026-10-23  #1020  The deadline measures a stall, not the whole wait. Under the bundle's load the runtime sent that
//                    test's 50 transacts over 27-40 s (gaps up to 3.6 s), so a 10 s total bound failed a run that was
//                    still moving; a wait now fails only after 10 s with no new message.

import Foundation
@testable import InstantSwiftDataCore

/// Why a live test-support wait gave up (#1020): the count stopped moving for `timeout`, and this is what the scripted
/// side had seen, so a run that stalls fails in seconds with the messages it did send instead of parking the suite
/// until someone kills it.
struct InstantLiveTestWaitTimedOut: Error, CustomStringConvertible {
  var wait: String
  var timeout: Duration
  var observed: [String]

  var description: String {
    "No progress for \(timeout) while waiting for \(wait); saw \(observed.count): "
      + observed.joined(separator: ", ")
  }
}

enum InstantLiveTestWait {
  /// How long a wait lets its count stand still before it fails (#1020). Idle, a live run sends its next message
  /// within milliseconds; under the whole bundle's load the longest gap measured was 3.6 s. 10 s leaves that room and
  /// still ends a run that will never send again.
  static let defaultTimeout: Duration = .seconds(10)

  /// The task that checks a wait every `timeout` until `check` says it is over: the waiter was resumed, or it failed
  /// because its count had not moved since the previous check.
  static func stallDeadline(
    every timeout: Duration,
    _ check: @escaping @Sendable () async -> Bool
  ) -> Task<Void, Never> {
    Task {
      while (try? await Task.sleep(for: timeout)) != nil {
        if await check() { return }
      }
    }
  }

  /// One message as a timed-out wait reports it: its op and client event ID.
  static func summary(_ message: InstantLiveMessage) -> String {
    [message.op, message.clientEventID].compactMap { $0 }.joined(separator: " ")
  }
}

/// The tests waiting for a count a scripted live actor raises (sent messages, receive requests, connections), each
/// with the task that fails it once the count stalls (#1020). The owning actor keeps it in a stored property and
/// touches it only on its own executor: it appends inside `withCheckedThrowingContinuation`, resumes the waiters a new
/// count satisfies, and checks one from its deadline task. Each continuation is removed before it is resumed, so it
/// resumes exactly once whichever comes first.
struct InstantLiveTestCountWaiters {
  private struct Waiter {
    var id: UUID
    var count: Int
    var countAtLastCheck: Int
    var continuation: CheckedContinuation<Void, any Error>
    var deadline: Task<Void, Never>
  }

  private var waiters: [Waiter] = []

  mutating func append(
    id: UUID,
    count: Int,
    currentCount: Int,
    continuation: CheckedContinuation<Void, any Error>,
    deadline: Task<Void, Never>
  ) {
    waiters.append(
      Waiter(
        id: id,
        count: count,
        countAtLastCheck: currentCount,
        continuation: continuation,
        deadline: deadline
      )
    )
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

  /// At a deadline: fails the waiter `id` with the error its awaited count describes if `currentCount` has not moved
  /// since the previous check. Returns whether the wait is over (failed now, or already resumed).
  mutating func failIfStalled(
    _ id: UUID,
    currentCount: Int,
    with error: (_ awaitedCount: Int) -> any Error
  ) -> Bool {
    guard let index = waiters.firstIndex(where: { $0.id == id }) else { return true }
    guard currentCount <= waiters[index].countAtLastCheck else {
      waiters[index].countAtLastCheck = currentCount
      return false
    }
    let waiter = waiters.remove(at: index)
    waiter.continuation.resume(throwing: error(waiter.count))
    return true
  }
}
