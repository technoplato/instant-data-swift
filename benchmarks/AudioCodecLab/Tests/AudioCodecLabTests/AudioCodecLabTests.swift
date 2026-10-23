// Smoke tests for the codec lab (#1012). They run on a Mac and, through xcodebuild, on a phone, where the probe
// answers what that OS can encode, mux and play.

import AudioCodecLab
import Foundation
import Testing

/// One second of a 220 Hz tone with a slow tremolo: enough signal for every encoder to produce packets.
func tone(seconds: Double = 2, sampleRate: Double = 48_000) -> PCM16 {
  let count = Int(seconds * sampleRate)
  let samples = (0..<count).map { i -> Int16 in
    let t = Double(i) / sampleRate
    return Int16(8_000 * sin(2 * .pi * 220 * t) * (0.6 + 0.4 * sin(2 * .pi * 3 * t)))
  }
  return PCM16(samples: samples, sampleRate: sampleRate)
}

@Suite struct AudioCodecLabTests {
  @Test func probeListsTheAACEncoder() {
    let result = probe()
    print("probe", result)
    #expect(result.encoders.contains("aac "))
  }

  @Test(arguments: [LabCodec.aacLC, .heAAC, .opus])
  func encodeAndDecodeRoundTrip(codec: LabCodec) throws {
    let pcm = tone()
    let encoded = try encode(pcm, codec: codec, sampleRate: 48_000, bitRate: codec == .opus ? 24_000 : 32_000)
    #expect(!encoded.packets.isEmpty)
    let decoded = try decode(encoded, sampleRate: 16_000)
    #expect(decoded.samples.count > 16_000)
    print(codec.rawValue, "corePercent", encoded.corePercent, "bytesPerMinute", encoded.bytesPerMinute)
  }

  @Test func aacSegmentsAsFragmentedMP4() throws {
    let result = try writeHLS(tone(seconds: 13), codec: .aacLC, sampleRate: 48_000, bitRate: 32_000, segmentSeconds: 6)
    #expect(!result.initialization.isEmpty)
    #expect(result.segments.count >= 2)
  }
}
