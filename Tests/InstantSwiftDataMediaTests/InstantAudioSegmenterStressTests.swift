// Drives AVAssetWriter's HLS segmenter through the orderings suspected of crashing it on its own queue (#2529): Apple's
// writer died in a CoreMedia deferred notification on com.apple.coremedia.assetwriter (a freed CFArray or CFDictionary,
// or a double free on the format writer's thread) in three test processes and one command-line copy on a build machine.
//
// Off unless SEGMENTER_STRESS names a scenario (or "all"): each round runs SEGMENTER_WIDTH segmenters at once,
// SEGMENTER_ROUNDS times, with SEGMENTER_LOAD busy threads beside them, so a crash is attributable to one scenario. Run
// one scenario per process: a crash ends the process and its report names the queue.

#if canImport(AVFoundation) && !os(watchOS)
  import AVFoundation
  import Foundation
  import InstantSwiftData
  import InstantSwiftDataMedia
  import Testing

  private let environment = ProcessInfo.processInfo.environment
  private let stressScenario = environment["SEGMENTER_STRESS"]

  @Suite(.serialized, .enabled(if: stressScenario != nil, "SEGMENTER_STRESS names a scenario (#2529)"))
  struct InstantAudioSegmenterStressTests {
    enum Scenario: String, CaseIterable, Sendable {
      /// Append in 1 s reads, finish, release: the phone's take at Stop.
      case finishThenRelease
      /// Append, then release without finishing: a take dropped mid-write.
      case releaseMidWrite
      /// Append, then release while the writer still cuts a segment: released right after an append that crossed a
      /// segment boundary.
      case releaseDuringSegment
      /// Finish called while an append waits for the input to be ready (the actor is reentrant at its sleep).
      case finishDuringAppend
      /// Writers left writing (a take replaced without finishing) while others start, write and finish.
      case liveLeftBehind
      /// One writer encoding a long file as fast as it can, as the command-line copy does.
      case longFile
    }

    var width: Int { Int(environment["SEGMENTER_WIDTH"] ?? "") ?? 8 }
    var rounds: Int { Int(environment["SEGMENTER_ROUNDS"] ?? "") ?? 20 }
    var load: Int { Int(environment["SEGMENTER_LOAD"] ?? "") ?? 0 }

    @Test(arguments: Scenario.allCases)
    func scenario(_ scenario: Scenario) async throws {
      guard stressScenario == "all" || stressScenario == scenario.rawValue else { return }
      let busy = Busy(threads: load)
      defer { busy.stop() }
      let started = Date()
      var leftBehind: [InstantAudioSegmenter] = []
      for round in 0..<rounds {
        try await withThrowingTaskGroup(of: InstantAudioSegmenter?.self) { group in
          for lane in 0..<width {
            group.addTask { try await run(scenario, lane: lane) }
          }
          for try await kept in group {
            if let kept { leftBehind.append(kept) }
          }
        }
        if round % 5 == 4 {
          print("segmenter-stress \(scenario.rawValue) round \(round + 1)/\(rounds) width \(width) load \(load) live \(leftBehind.count) \(Int(Date().timeIntervalSince(started))) s")
        }
      }
      print("segmenter-stress \(scenario.rawValue) survived \(rounds) rounds of \(width) in \(Int(Date().timeIntervalSince(started))) s")
      withExtendedLifetime(leftBehind) {}
    }

    /// One segmenter through the scenario; returns it when the scenario leaves it writing.
    private func run(_ scenario: Scenario, lane: Int) async throws -> InstantAudioSegmenter? {
      let segmenter = try InstantAudioSegmenter(format: .speech, inputSampleRate: 48_000)
      let drained = Task { for await _ in segmenter.outputs {} }
      defer { drained.cancel() }
      let second = tone(seconds: 1)
      switch scenario {
      case .finishThenRelease:
        for _ in 0..<13 { try await segmenter.append(second) }
        try await segmenter.finish()
        return nil
      case .releaseMidWrite:
        for _ in 0..<(3 + lane % 5) { try await segmenter.append(second) }
        return nil
      case .releaseDuringSegment:
        // 6 s crosses the first segment boundary: the writer cuts it on its own queue as the segmenter is released.
        for _ in 0..<6 { try await segmenter.append(second) }
        try await segmenter.append(Array(second.prefix(4_800)))
        return nil
      case .finishDuringAppend:
        let long = tone(seconds: 30)
        async let appended: Void = segmenter.append(long)
        try? await Task.sleep(for: .milliseconds(lane % 3))
        try? await segmenter.finish()
        try? await appended
        return nil
      case .liveLeftBehind:
        if lane == 0 {
          for _ in 0..<4 { try await segmenter.append(second) }
          return segmenter
        }
        for _ in 0..<8 { try await segmenter.append(second) }
        try await segmenter.finish()
        return nil
      case .longFile:
        guard lane == 0 else { return nil }
        for _ in 0..<600 { try await segmenter.append(second) }
        try await segmenter.finish()
        return nil
      }
    }
  }

  /// Threads that spin, so the writer's queues compete for cores as they did at load 190 (#2474).
  private final class Busy: @unchecked Sendable {
    private let lock = NSLock()
    private var running = true
    init(threads: Int) {
      for _ in 0..<threads {
        Thread.detachNewThread { [self] in
          var x = 0.0
          while isRunning { for i in 0..<100_000 { x += sin(Double(i)) } }
          _ = x
        }
      }
    }
    var isRunning: Bool { lock.withLock { running } }
    func stop() { lock.withLock { running = false } }
  }

  private func tone(seconds: Double, sampleRate: Double = 48_000) -> [Int16] {
    (0..<Int(seconds * sampleRate)).map { i in
      let t = Double(i) / sampleRate
      return Int16(8_000 * sin(2 * .pi * 220 * t) * (0.6 + 0.4 * sin(2 * .pi * 3 * t)))
    }
  }
#endif
