// The phone half of the codec measurement (#1012, ADR 0021): the same encoders, on the device's own cores.
//
// scripts/run_on_phone.sh copies a speech excerpt to Resources/speech.wav (never committed) and runs this suite on the
// phone with xcodebuild; each result prints as one "CODEC-LAB {json}" line. Without the excerpt the suite measures a
// synthetic tone and says so, which is enough to check what the OS can encode but not what speech costs.

import AudioCodecLab
import Foundation
import Testing

@Suite(.serialized) struct DeviceMatrixTests {
  static func input() -> (PCM16, String) {
    if let url = Bundle.module.url(forResource: "speech", withExtension: "wav", subdirectory: "Resources"),
      let pcm = try? PCM16(contentsOf: url)
    {
      return (pcm, "speech")
    }
    return (tone(seconds: 60), "tone")
  }

  static func emit(_ object: [String: Any]) {
    var object = object
    object["os"] = ProcessInfo.processInfo.operatingSystemVersionString
    object["thermalState"] = ProcessInfo.processInfo.thermalState.rawValue
    object["lowPowerMode"] = ProcessInfo.processInfo.isLowPowerModeEnabled
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print("CODEC-LAB " + String(decoding: data, as: UTF8.self))
  }

  @Test func probeTheOS() {
    let result = probe()
    Self.emit([
      "kind": "probe", "encoderImplementations": result.encoderImplementations, "encoders": result.encoders, "decoders": result.decoders,
      "playableMIMETypes": result.playableMIMETypes, "hlsWriter": result.hlsWriter, "bitRates": result.bitRates,
    ])
  }

  // Each encoder at the default QoS (performance cores) and, for the candidates, at background QoS (efficiency cores,
  // where an always-on recorder's encoder runs while the phone is in a pocket).
  @Test(arguments: [
    ("aac-lc", 48_000.0, 32_000, nil, "default"), ("aac-lc", 48_000, 32_000, "max", "default"),
    ("aac-lc", 48_000, 64_000, nil, "default"), ("aac-lc", 24_000, 24_000, nil, "default"),
    ("aac-lc", 16_000, 24_000, nil, "default"), ("he-aac", 48_000, 24_000, nil, "default"),
    ("opus", 48_000, 24_000, nil, "default"), ("opus", 48_000, 16_000, nil, "default"), ("opus", 16_000, 16_000, nil, "default"),
    ("aac-lc", 48_000, 32_000, nil, "background"), ("aac-lc", 24_000, 24_000, nil, "background"),
    ("opus", 48_000, 24_000, nil, "background"),
  ] as [(String, Double, Int, String?, String)])
  func encodeOnTheDevice(codec: String, rate: Double, bitRate: Int, quality: String?, qos: String) throws {
    let (pcm, source) = Self.input()
    var best: EncodedAudio?
    for _ in 0..<3 {
      let encoded = try onThread(qos: qos == "background" ? .background : .userInitiated) {
        try encode(
          pcm, codec: LabCodec(rawValue: codec)!, sampleRate: rate, bitRate: bitRate,
          quality: quality.flatMap(LabQuality.init(rawValue:))
        )
      }
      if best == nil || encoded.cpuSeconds < best!.cpuSeconds { best = encoded }
    }
    let encoded = best!
    Self.emit([
      "kind": "device-encode", "source": source, "codec": codec, "rate": Int(rate), "bitrate": bitRate,
      "quality": quality ?? "default", "qos": qos, "inputSeconds": encoded.inputSeconds,
      "packetBytes": encoded.packets.count, "bytesPerMinute": Int(encoded.bytesPerMinute),
      "cpuSecondsPerMinute": encoded.cpuSecondsPerMinute, "corePercent": encoded.corePercent,
      "realtimeFactor": encoded.inputSeconds / max(encoded.wallSeconds, 1e-9),
    ])
  }

  @Test(arguments: [("aac-lc", 48_000.0, 32_000, 6.0), ("aac-lc", 24_000, 24_000, 6.0), ("opus", 48_000, 24_000, 6.0)])
  func segmentOnTheDevice(codec: String, rate: Double, bitRate: Int, segment: Double) throws {
    let (pcm, source) = Self.input()
    var best: HLSResult?
    for _ in 0..<3 {
      let result = try writeHLS(pcm, codec: LabCodec(rawValue: codec)!, sampleRate: rate, bitRate: bitRate, segmentSeconds: segment)
      if best == nil || result.processCPUSeconds < best!.processCPUSeconds { best = result }
    }
    let result = best!
    Self.emit([
      "kind": "device-hls", "source": source, "codec": codec, "rate": Int(rate), "bitrate": bitRate,
      "segmentSeconds": segment, "segments": result.segments.count, "totalBytes": result.totalBytes,
      "bytesPerMinute": Int(result.bytesPerMinute), "cpuSecondsPerMinute": result.cpuSecondsPerMinute,
      "corePercent": result.corePercent,
    ])
  }
}
