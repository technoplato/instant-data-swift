import Testing

@testable import InstantSwiftDataCore

@Suite struct InstantLiveTimeoutSleepTests {
  /// A far-future deadline waits instead of trapping. Converting milliseconds to nanoseconds
  /// overflowed above about 584 years, and the multiplication crashed the process (signal 5)
  /// in the full suite on 2026-09-27.
  @Test func farFutureSleepIsCancellableInsteadOfTrapping() async {
    let sleep = Task { try await instantLiveDefaultTimeoutSleep(.max) }
    sleep.cancel()
    await #expect(throws: CancellationError.self) { try await sleep.value }
  }

  @Test func ordinarySleepStillWaitsTheRequestedTime() async throws {
    let clock = ContinuousClock()
    let elapsed = try await clock.measure { try await instantLiveDefaultTimeoutSleep(20) }
    #expect(elapsed >= .milliseconds(20))
  }
}
