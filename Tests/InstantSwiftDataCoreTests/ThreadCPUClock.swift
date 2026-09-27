import Darwin

/// CPU time the current thread has spent running, so a cost measurement does not count time the
/// thread spent waiting for a core. Wall-clock timings on a shared machine varied fivefold between
/// identical runs on 2026-09-26; thread CPU time is the comparable number.
enum ThreadCPUClock {
  static func nanoseconds() -> UInt64 {
    clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
  }

  static func measure(_ body: () throws -> Void) rethrows -> (cpuMilliseconds: Double, wall: Duration) {
    let wallStart = ContinuousClock.now
    let cpuStart = nanoseconds()
    try body()
    let cpu = Double(nanoseconds() - cpuStart) / 1_000_000
    return (cpu, ContinuousClock.now - wallStart)
  }
}
