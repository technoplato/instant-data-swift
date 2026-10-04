import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #541: the live-query acknowledgement state forgets a key once no query holds it, and one revision counter for
/// every key keeps a wait that read a revision before the key was forgotten from missing the next answer.
@Suite
struct InstantLiveQueryAcknowledgementStateTests {
  actor Flag {
    private(set) var isSet = false
    func set() { isSet = true }
  }

  /// Waits up to two seconds for `wait` to return.
  static func returns(
    _ wait: @escaping @Sendable () async throws -> Void
  ) async throws -> Bool {
    let flag = Flag()
    let task = Task {
      try await wait()
      await flag.set()
    }
    let deadline = ContinuousClock.now + .seconds(2)
    while await !flag.isSet, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    let returned = await flag.isSet
    task.cancel()
    return returned
  }

  @Test
  func anAnswerAfterTheKeyWasForgottenStillEndsAWaitThatReadAnEarlierRevision() async throws {
    let state = InstantLiveQueryAcknowledgementState()
    await state.record(key: "agent-replies")
    await state.record(key: "agent-replies")
    // A queryOnce reads the revision, then the subscription that held the key unregisters before it registers.
    let observed = await state.revision(for: "agent-replies")
    await state.forget(key: "agent-replies")
    expectNoDifference(await state.keyCount(), 0)
    // The server's answer arrives before the queryOnce waits. A counter per key would start over at 1, below the
    // revision the queryOnce read, and the wait would last until its 5 s timeout.
    await state.record(key: "agent-replies")
    #expect(try await Self.returns { try await state.wait(for: "agent-replies", after: observed) })
  }

  @Test
  func anAnswerToAKeyNoQueryHoldsIsNotRememberedButStillResumesItsWaiters() async throws {
    let state = InstantLiveQueryAcknowledgementState()
    let observed = await state.revision(for: "late")
    let flag = Flag()
    let waiter = Task {
      try await state.wait(for: "late", after: observed)
      await flag.set()
    }
    try await Task.sleep(for: .milliseconds(50))
    await state.record(key: "late", remembering: false)
    let deadline = ContinuousClock.now + .seconds(2)
    while await !flag.isSet, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await flag.isSet, "the waiter resumed")
    expectNoDifference(await state.keyCount(), 0, "the answer was not remembered")
    waiter.cancel()
  }

  @Test
  func aRejectionIsRememberedUntilTheKeyIsForgotten() async throws {
    let state = InstantLiveQueryAcknowledgementState()
    let observed = await state.revision(for: "rejected")
    await state.reject(
      key: "rejected",
      error: InstantError(
        code: .permissionRejected,
        operation: "run Instant live query",
        message: "Permission denied.",
        recovery: "Inspect the query's permissions."
      )
    )
    await #expect(throws: InstantError.self) {
      try await state.wait(for: "rejected", after: observed)
    }
    await state.forget(key: "rejected")
    expectNoDifference(await state.keyCount(), 0)
  }
}
