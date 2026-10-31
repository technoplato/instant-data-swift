// History:
// - 2026-10-31: created. Each frame the live session sent started three unstructured tasks (its own, and
//   instantLiveWithTimeout's work and deadline tasks) and armed a 5 s timer, which still fired after the write had
//   returned: about 270 tasks and 90 timers a minute while recording. A frame now starts one task, and one watcher per
//   socket keeps every write's deadline (#1496).

import Foundation
import os

/// Writes one live socket's frames, each from its own task, and fails a write's caller at its deadline (#1496).
///
/// Each frame is written by one unstructured task, so the caller's cancellation does not reach the write (library-78:
/// cancelling an observation while its add-query was being written closed a healthy socket), and writes stay
/// independent: a frame held at the socket does not hold a later one. The runtime relies on that: a room is left while
/// a presence write is stuck (#461), and an equivalent query registers while the earlier one's removal is held (#1131).
/// A single task writing the frames in order, as upstream `Reactor.js` writes them with a synchronous `ws.send`, made
/// both wait for the held write.
///
/// A write that has not finished `timeoutMilliseconds` after it started fails its caller then, with the error
/// `instantLiveWithTimeout` gave, and the caller's failure path aborts the socket; nothing waits for the abandoned
/// write. One deadline watcher keeps that clock for every write on the socket. It sleeps only while a write is in
/// flight, until the earliest deadline, so a recording's writes arm about one timer per timeout interval instead of one
/// each, and an idle socket arms none.
///
/// ``finish()`` refuses later frames; the live session calls it when it lets go of the socket. Writes in flight finish
/// or fail at their deadlines, and the watcher ends after them.
final class InstantLiveSocketWriter: Sendable {
  /// The socket this writer writes to.
  let sessionIdentity: UUID

  private struct Write: Sendable {
    var deadline: ContinuousClock.Instant
    var continuation: CheckedContinuation<Void, any Error>
  }

  private struct State: Sendable {
    var inFlight: [UInt64: Write] = [:]
    var lastID: UInt64 = 0
    var parkedWatcher: CheckedContinuation<Void, Never>?
    var isFinished = false
    var startedTaskCount = 0
  }

  private enum NextDeadline: Sendable {
    case sleep(until: ContinuousClock.Instant)
    case finished
    case park
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let send: @Sendable (InstantLiveMessage) async throws -> Void
  private let timeoutMilliseconds: UInt64
  private let timeout: Duration
  private let operation: String

  /// Writes to `session`, and starts the deadline watcher when `timeoutMilliseconds` is above zero, at `priority` or
  /// at the caller's.
  init(
    session: InstantLiveWebSocketSession,
    timeoutMilliseconds: UInt64 = instantLiveOperationTimeoutMilliseconds,
    operation: String = "send Instant live session message",
    priority: TaskPriority? = nil
  ) {
    sessionIdentity = session.identity
    send = session.send
    self.timeoutMilliseconds = timeoutMilliseconds
    // A year bounds the deadline's arithmetic; a socket write is never meant to wait that long.
    timeout = .milliseconds(Int64(min(timeoutMilliseconds, 31_536_000_000)))
    self.operation = operation
    if timeoutMilliseconds > 0 {
      state.withLock { $0.startedTaskCount += 1 }
      Task(priority: priority) { await self.watchDeadlines() }
    }
  }

  /// The tasks this writer started: the deadline watcher, and one for each frame.
  var startedTaskCount: Int {
    state.withLock { $0.startedTaskCount }
  }

  /// Writes `message` from a task of its own and returns once the socket took it. Throws the socket's error, the
  /// timeout's, or ``InstantSupersededLiveSessionSend`` when the writer had finished. The caller's cancellation does not
  /// stop the write.
  func write(_ message: InstantLiveMessage) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      let deadline = ContinuousClock.now + timeout
      let registered = state.withLock { state -> (id: UInt64, watcher: CheckedContinuation<Void, Never>?)? in
        guard !state.isFinished else { return nil }
        state.lastID &+= 1
        state.inFlight[state.lastID] = Write(deadline: deadline, continuation: continuation)
        state.startedTaskCount += 1
        defer { state.parkedWatcher = nil }
        return (state.lastID, state.parkedWatcher)
      }
      guard let registered else {
        continuation.resume(throwing: InstantSupersededLiveSessionSend())
        return
      }
      registered.watcher?.resume()
      Task {
        let result: Result<Void, any Error>
        do {
          try await self.send(message)
          result = .success(())
        } catch {
          result = .failure(error)
        }
        let caller = self.state.withLock { $0.inFlight.removeValue(forKey: registered.id)?.continuation }
        caller?.resume(with: result)
      }
    }
  }

  /// Refuses every later frame with ``InstantSupersededLiveSessionSend``. Writes in flight finish, or fail their callers
  /// at their deadlines.
  func finish() {
    let watcher = state.withLock { state -> CheckedContinuation<Void, Never>? in
      state.isFinished = true
      defer { state.parkedWatcher = nil }
      return state.parkedWatcher
    }
    watcher?.resume()
  }

  /// Writes started and not yet finished or timed out, for tests.
  var inFlightCountForTesting: Int {
    state.withLock { $0.inFlight.count }
  }

  // MARK: - The deadline watcher

  private func watchDeadlines() async {
    while let deadline = await earliestDeadline() {
      try? await Task.sleep(until: deadline, clock: .continuous)
      let expired = state.withLock { state -> [CheckedContinuation<Void, any Error>] in
        let now = ContinuousClock.now
        let ids = state.inFlight.compactMap { $0.value.deadline <= now ? $0.key : nil }
        return ids.compactMap { state.inFlight.removeValue(forKey: $0)?.continuation }
      }
      for caller in expired {
        caller.resume(
          throwing: InstantError(
            code: .networkFailed,
            operation: operation,
            message: "Timed out after \(timeoutMilliseconds)ms waiting for Instant live transport.",
            recovery: "Check the Instant WebSocket endpoint, credentials, and server response."
          )
        )
      }
    }
  }

  /// The earliest deadline among the writes in flight. Waits while none is; nil once the writer finished and none is.
  private func earliestDeadline() async -> ContinuousClock.Instant? {
    while true {
      let next = state.withLock { state -> NextDeadline in
        if let earliest = state.inFlight.values.lazy.map(\.deadline).min() {
          return .sleep(until: earliest)
        }
        return state.isFinished ? .finished : .park
      }
      switch next {
      case let .sleep(until: deadline):
        return deadline
      case .finished:
        return nil
      case .park:
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          let resumesNow = state.withLock { state -> Bool in
            guard state.inFlight.isEmpty, !state.isFinished else { return true }
            state.parkedWatcher = continuation
            return false
          }
          if resumesNow { continuation.resume() }
        }
      }
    }
  }
}
