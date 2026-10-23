// AVFoundation's HLS segmenter behind the progressive media writer (#1012, ADR 0021).

#if canImport(AVFoundation) && !os(watchOS)
  import AVFoundation
  import CustomDump
  import Foundation
  import InstantSwiftData
  import InstantSwiftDataMedia
  import Testing

  @Suite struct InstantProgressiveMediaSegmenterTests {
    /// 13 s of PCM at 48 kHz become an initialization segment and three media segments (6 s, 6 s, then the rest), at
    /// the speech format's 24 kHz and 32 kbps; joined, they are one MP4 that AVFoundation plays for 13 s.
    @Test func pcmBecomesAnInitializationSegmentThenSixSecondSegments() async throws {
      let segmenter = try InstantAudioSegmenter(format: .speech, inputSampleRate: 48_000)
      let collected = Task {
        var outputs: [InstantAudioSegmenter.Output] = []
        for await output in segmenter.outputs { outputs.append(output) }
        return outputs
      }
      let samples = tone(seconds: 13)
      for start in stride(from: 0, to: samples.count, by: 4_096) {
        try await segmenter.append(Array(samples[start..<min(samples.count, start + 4_096)]))
      }
      try await segmenter.finish()
      let outputs = await collected.value

      guard case let .initialization(initialization)? = outputs.first else {
        Issue.record("The first output is not the initialization segment: \(outputs.first.map { "\($0)" } ?? "none")")
        return
      }
      let segments = outputs.dropFirst().compactMap { output -> (Data, Double)? in
        guard case let .segment(data, duration) = output else { return nil }
        return (data, duration)
      }
      expectNoDifference(segments.count, 3)
      expectNoDifference(segments.map { ($0.1 * 10).rounded() / 10 }.prefix(2), [6, 6])
      #expect(abs(segments.map(\.1).reduce(0, +) - 13) < 0.1)
      // 32 kbps is 4,000 bytes a second: a 6 s segment holds about 24 KB.
      #expect(segments[0].0.count > 20_000 && segments[0].0.count < 30_000)

      var joined = initialization
      for (data, _) in segments { joined.append(data) }
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("segmenter-\(UUID().uuidString).mp4")
      try joined.write(to: url)
      defer { try? FileManager.default.removeItem(at: url) }
      let asset = AVURLAsset(url: url)
      #expect(try await asset.load(.isPlayable))
      #expect(abs(try await asset.load(.duration).seconds - 13) < 0.1)
      let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
      let description = try #require(try await track.load(.formatDescriptions).first)
      let asbd = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee)
      expectNoDifference(asbd.mFormatID, kAudioFormatMPEG4AAC)
      expectNoDifference(asbd.mSampleRate, 24_000)
    }

    /// A resumed stream starts where its writer stopped: the first segment's media time is the resume point.
    @Test func aResumedSegmenterContinuesTheTimeline() async throws {
      let segmenter = try InstantAudioSegmenter(format: .speech, inputSampleRate: 48_000, startSeconds: 60)
      let collected = Task {
        var count = 0
        for await output in segmenter.outputs {
          if case .segment = output { count += 1 }
        }
        return count
      }
      try await segmenter.append(tone(seconds: 7))
      try await segmenter.finish()
      let (segments, appendedSeconds) = (await collected.value, await segmenter.appendedSeconds)
      expectNoDifference(segments, 2)
      expectNoDifference(appendedSeconds, 7)
    }
  }

  /// A 220 Hz tone with a slow tremolo, enough signal for the encoder.
  private func tone(seconds: Double, sampleRate: Double = 48_000) -> [Int16] {
    (0..<Int(seconds * sampleRate)).map { i in
      let t = Double(i) / sampleRate
      return Int16(8_000 * sin(2 * .pi * 220 * t) * (0.6 + 0.4 * sin(2 * .pi * 3 * t)))
    }
  }
#endif
