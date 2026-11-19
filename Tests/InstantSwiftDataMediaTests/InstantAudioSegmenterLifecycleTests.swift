// Every AVAssetWriter the segmenter starts ends exactly once, on the segmenter's own isolation, before it is released
// (#2529): finished, failed, or cancelled, whichever way its owner leaves it.

#if canImport(AVFoundation) && !os(watchOS)
  import CustomDump
  import Foundation
  import InstantSwiftData
  import InstantSwiftDataMedia
  import Testing

  @Suite struct InstantAudioSegmenterLifecycleTests {
    /// A finish ends the writer once; a second finish returns the first one's outcome instead of asking AVAssetWriter to
    /// finish a file it already completed (an Objective-C exception).
    @Test func aSecondFinishReturnsTheFirstOnesOutcome() async throws {
      let endings = Endings()
      let segmenter = try InstantAudioSegmenter(
        format: .speech, inputSampleRate: 48_000, onEnd: { endings.record($0) }
      )
      let drained = Task { for await _ in segmenter.outputs {} }
      try await segmenter.append(tone(seconds: 2))
      try await segmenter.finish()
      try await segmenter.finish()
      await drained.value
      expectNoDifference(endings.value, [.finished])
    }

    /// Cancel ends the writer at once: its outputs end, and an append after it throws instead of reaching an input
    /// AVAssetWriter has cancelled.
    @Test func cancelEndsTheWriterAndItsOutputs() async throws {
      let endings = Endings()
      let segmenter = try InstantAudioSegmenter(
        format: .speech, inputSampleRate: 48_000, onEnd: { endings.record($0) }
      )
      let drained = Task { for await _ in segmenter.outputs {} }
      try await segmenter.append(tone(seconds: 2))
      await segmenter.cancel()
      await segmenter.cancel()
      await drained.value
      await #expect(throws: InstantError.self) { try await segmenter.append(tone(seconds: 1)) }
      await #expect(throws: InstantError.self) { try await segmenter.finish() }
      expectNoDifference(endings.value, [.cancelled])
    }

    /// An append after the finish throws: AVAssetWriter raises an Objective-C exception for a sample appended to an
    /// input marked finished.
    @Test func anAppendAfterTheFinishThrows() async throws {
      let segmenter = try InstantAudioSegmenter(format: .speech, inputSampleRate: 48_000)
      let drained = Task { for await _ in segmenter.outputs {} }
      try await segmenter.append(tone(seconds: 1))
      try await segmenter.finish()
      await drained.value
      await #expect(throws: InstantError.self) { try await segmenter.append(tone(seconds: 1)) }
    }

    /// A segmenter released while its writer still writes (its owner dropped it mid-recording) cancels the writer first,
    /// so AVAssetWriter is never deallocated with a file in progress and its queue's work still pending.
    @Test func aSegmenterReleasedWhileWritingCancelsItsWriter() async throws {
      let endings = Endings()
      var segmenter: InstantAudioSegmenter? = try InstantAudioSegmenter(
        format: .speech, inputSampleRate: 48_000, onEnd: { endings.record($0) }
      )
      let outputs = try #require(segmenter?.outputs)
      let drained = Task { for await _ in outputs {} }
      try await segmenter?.append(tone(seconds: 7))
      segmenter = nil
      await drained.value
      expectNoDifference(endings.value, [.cancelledAtRelease])
    }

    /// A finish that meets an append still waiting for the input ends the writer after that append, never during it:
    /// the append either lands before the finish or throws, and the writer ends once.
    @Test func aFinishDuringAWaitingAppendEndsTheWriterOnce() async throws {
      let endings = Endings()
      let segmenter = try InstantAudioSegmenter(
        format: .speech, inputSampleRate: 48_000, onEnd: { endings.record($0) }
      )
      let drained = Task { for await _ in segmenter.outputs {} }
      // Enough PCM in one append that the input stops being ready while it is handed over.
      let appends = (0..<4).map { _ in Task { try? await segmenter.append(tone(seconds: 30)) } }
      try? await segmenter.finish()
      for append in appends { await append.value }
      await drained.value
      expectNoDifference(endings.value.count, 1)
    }
  }

  /// How each writer ended, in order.
  private final class Endings: @unchecked Sendable {
    private let lock = NSLock()
    private var endings: [InstantAudioSegmenter.Ending] = []
    var value: [InstantAudioSegmenter.Ending] { lock.withLock { endings } }
    func record(_ ending: InstantAudioSegmenter.Ending) { lock.withLock { endings.append(ending) } }
  }

  private func tone(seconds: Double, sampleRate: Double = 48_000) -> [Int16] {
    (0..<Int(seconds * sampleRate)).map { i in
      let t = Double(i) / sampleRate
      return Int16(8_000 * sin(2 * .pi * 220 * t) * (0.6 + 0.4 * sin(2 * .pi * 3 * t)))
    }
  }
#endif
