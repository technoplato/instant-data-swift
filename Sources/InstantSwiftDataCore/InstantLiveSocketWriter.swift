// History:
// - 2026-10-31: created. Each frame the live session sent started three unstructured tasks (its own, and
//   instantLiveWithTimeout's work and deadline tasks) and armed a 5 s timer, about 270 tasks and 90 timers a minute
//   while recording; and two sends that overlapped could reach the socket in either order (#1496).

import Foundation
import os

/// Writes one live socket's frames from one task, in the order the live session sent them (#1496).
///
/// Upstream `Reactor.js` writes each frame with a synchronous `ws.send`, in call order, which no caller can interrupt.
/// A socket's `send` here is asynchronous, so each frame is an entry in this writer's mailbox: its task takes the
/// entries in order and awaits each `send`, and each caller awaits its own entry. A caller's cancellation does not reach
/// the write (library-78: cancelling an observation while its add-query was being written closed a healthy socket).
///
/// A write that has not finished `timeoutMilliseconds` after it started fails its caller then, with the error
/// `instantLiveWithTimeout` gave, and the caller's failure path aborts the socket; nothing waits for the abandoned
/// write. One deadline watcher keeps that clock for the socket. It sleeps only while a write is in progress, until that
/// write's deadline, so a run of writes arms about one timer per timeout interval instead of one each, and an idle
/// socket arms none.
///
/// ``finish()`` fails every frame not yet written; the live session calls it when it lets go of the socket. Both tasks
/// end once the write in progress, if any, is over.
final class InstantLiveSocketWriter: Sendable {
  /// The socket this writer writes to.
  let sessionIdentity: UUID
  /// The tasks this writer started: the writer, and the deadline watcher unless writes have no timeout.
  let startedTaskCount: Int

  private struct Entry: Sendable {
    var id: UInt64
    var message: InstantLiveMessage
    var continuation: CheckedContinuation<Void, any Error>
  }

  private struct InProgress: Sendable {
    var id: UInt64
    var deadline: ContinuousClock.Instant
    /// Nil once the deadline watcher has failed the write's caller.
    var continuation: CheckedContinuation<Void, any Error>?
  }

  private struct State: Sendable {
    var queue: [Entry] = []
    var queueHead = 0
    var inProgress: InProgress?
    var parkedWriter: CheckedContinuation<Void, Never>?
    var parkedWatcher: CheckedContinuation<Void, Never>?
    var lastID: UInt64 = 0
    var isFinished = false
  }

  private enum NextEntry: Sendable {
    case write(Entry, wakingWatcher: CheckedContinuation<Void, Never>?)
    case finished
    case park
  }

  private enum NextDeadline: Sendable {
    case watch(id: UInt64, deadline: ContinuousClock.Instant)
    case finished
    case park
  }

  private let state = OSAllocatedUnfairLock(initialState: State())
  private let timeoutMilliseconds: UInt64
  private let timeout: Duration
  private let operation: String

  /// Starts the writer for `session`, and its deadline watcher when `timeoutMilliseconds` is above zero. Both tasks
  /// run at `priority`, or at the caller's.
  init(
    session: InstantLiveWebSocketSession,
    timeoutMilliseconds: UInt64 = instantLiveOperationTimeoutMilliseconds,
    operation: String = "send Instant live session message",
    priority: TaskPriority? = nil
  ) {
    sessionIdentity = session.identity
    self.timeoutMilliseconds = timeoutMilliseconds
    // A year bounds the deadline's arithmetic; a socket write is never meant to wait that long.
    timeout = .milliseconds(Int64(min(timeoutMilliseconds, 31_536_000_000)))
    self.operation = operation
    startedTaskCount = timeoutMilliseconds > 0 ? 2 : 1
    let send = session.send
    Task(priority: priority) { await self.writeFrames(with: send) }
    if timeoutMilliseconds > 0 {
      Task(priority: priority) { await self.watchDeadlines() }
    }
  }

  /// Writes `message` after every frame sent before it, and returns once the socket took it. Throws the socket's error,
  /// the timeout's, or ``InstantSupersededLiveSessionSend`` when the writer finished first. The caller's cancellation
  /// does not stop the write.
  func write(_ message: InstantLiveMessage) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
      let writer = state.withLock { state -> CheckedContinuation<Void, Never>?? in
        guard !state.isFinished else { return .none }
        state.lastID &+= 1
        state.queue.append(Entry(id: state.lastID, message: message, continuation: continuation))
        defer { state.parkedWriter = nil }
        return .some(state.parkedWriter)
      }
      guard let writer else {
        continuation.resume(throwing: InstantSupersededLiveSessionSend())
        return
      }
      writer?.resume()
    }
  }

  /// Fails every frame not yet written with ``InstantSupersededLiveSessionSend`` and refuses new ones. The write in
  /// progress finishes, or fails its caller at its deadline.
  func finish() {
    let (unwritten, writer, watcher) = state.withLock {
      state -> ([Entry], CheckedContinuation<Void, Never>?, CheckedContinuation<Void, Never>?) in
      guard !state.isFinished else { return ([], nil, nil) }
      state.isFinished = true
      let unwritten = Array(state.queue[state.queueHead...])
      state.queue = []
      state.queueHead = 0
      defer {
        state.parkedWriter = nil
        state.parkedWatcher = nil
      }
      return (unwritten, state.parkedWriter, state.parkedWatcher)
    }
    for entry in unwritten {
      entry.continuation.resume(throwing: InstantSupersededLiveSessionSend())
    }
    writer?.resume()
    watcher?.resume()
  }

  /// Frames waiting behind the write in progress, for tests.
  var unwrittenCountForTesting: Int {
    state.withLock { $0.queue.count - $0.queueHead }
  }

  // MARK: - The writer

  private func writeFrames(with send: @Sendable (InstantLiveMessage) async throws -> Void) async {
    while let entry = await nextEntry() {
      let result: Result<Void, any Error>
      do {
        try await send(entry.message)
        result = .success(())
      } catch {
        result = .failure(error)
      }
      let caller = state.withLock { state -> CheckedContinuation<Void, any Error>? in
        guard state.inProgress?.id == entry.id else { return nil }
        defer { state.inProgress = nil }
        return state.inProgress?.continuation
      }
      caller?.resume(with: result)
    }
  }

  /// The next frame to write, marked in progress; nil once the writer finished.
  private func nextEntry() async -> Entry? {
    while true {
      let next = state.withLock { state -> NextEntry in
        guard state.queueHead < state.queue.count else { return state.isFinished ? .finished : .park }
        let entry = state.queue[state.queueHead]
        state.queueHead += 1
        if state.queueHead == state.queue.count {
          state.queue.removeAll(keepingCapacity: true)
          state.queueHead = 0
        }
        state.inProgress = InProgress(
          id: entry.id,
          deadline: ContinuousClock.now + timeout,
          continuation: entry.continuation
        )
        defer { state.parkedWatcher = nil }
        return .write(entry, wakingWatcher: state.parkedWatcher)
      }
      switch next {
      case let .write(entry, watcher):
        watcher?.resume()
        return entry
      case .finished:
        return nil
      case .park:
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          let resumesNow = state.withLock { state -> Bool in
            guard !state.isFinished, state.queueHead == state.queue.count else { return true }
            state.parkedWriter = continuation
            return false
          }
          if resumesNow { continuation.resume() }
        }
      }
    }
  }

  // MARK: - The deadline watcher

  private func watchDeadlines() async {
    var watchedID: UInt64 = 0
    while let next = await nextDeadline(after: watchedID) {
      let id = next.id
      watchedID = id
      try? await Task.sleep(until: next.deadline, clock: .continuous)
      let caller = state.withLock { state -> CheckedContinuation<Void, any Error>? in
        guard state.inProgress?.id == id else { return nil }
        defer { state.inProgress?.continuation = nil }
        return state.inProgress?.continuation
      }
      caller?.resume(
        throwing: InstantError(
          code: .networkFailed,
          operation: operation,
          message: "Timed out after \(timeoutMilliseconds)ms waiting for Instant live transport.",
          recovery: "Check the Instant WebSocket endpoint, credentials, and server response."
        )
      )
    }
  }

  /// The write in progress that started after `watchedID`, with its deadline; nil once the writer finished and no such
  /// write remains.
  private func nextDeadline(after watchedID: UInt64) async -> (id: UInt64, deadline: ContinuousClock.Instant)? {
    while true {
      let next = state.withLock { state -> NextDeadline in
        if let inProgress = state.inProgress, inProgress.id > watchedID, inProgress.continuation != nil {
          return .watch(id: inProgress.id, deadline: inProgress.deadline)
        }
        return state.isFinished ? .finished : .park
      }
      switch next {
      case let .watch(id, deadline):
        return (id, deadline)
      case .finished:
        return nil
      case .park:
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
          let resumesNow = state.withLock { state -> Bool in
            if state.isFinished { return true }
            if let inProgress = state.inProgress, inProgress.id > watchedID, inProgress.continuation != nil {
              return true
            }
            state.parkedWatcher = continuation
            return false
          }
          if resumesNow { continuation.resume() }
        }
      }
    }
  }
}
