import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantMediaStreamOptimizationTests {
  @Test("Binary codec decodes fragmented frames into a caller-owned sink")
  func binaryCodecRoundTripsWithoutFrameArrayAllocation() throws {
    let codec = InstantMediaStreamBinaryCodec<InstantAudioFrame>(
      formatIdentifier: InstantAudioStreamFormat.voice().identifier,
      maximumFrameBytes: 64
    )
    let expected = (0..<32).map { index in
      InstantAudioFrame(
        sequence: Int64(index),
        presentationTimeMicroseconds: Int64(index * 20_000),
        durationMicroseconds: 20_000,
        flags: index == 31 ? [.endOfSegment] : [],
        payload: Data(repeating: UInt8(index), count: 16)
      )
    }
    var encoded = Data()
    for frame in expected {
      encoded.append(try codec.encode(frame))
    }

    var decoder = codec.makeDecoder(expectedSequence: 0)
    var observed: [InstantAudioFrame] = []
    observed.reserveCapacity(expected.count)
    let chunkSizes = [1, 7, 31, 5, 97, 13]
    var offset = 0
    var chunkIndex = 0
    while offset < encoded.count {
      let end = min(encoded.count, offset + chunkSizes[chunkIndex % chunkSizes.count])
      try decoder.append(Data(encoded[offset..<end])) { observed.append($0) }
      offset = end
      chunkIndex += 1
    }
    try decoder.finish()

    expectNoDifference(observed, expected)
    expectNoDifference(decoder.bufferedByteCount, 0)
    expectNoDifference(decoder.nextExpectedSequence, Int64(expected.count))
  }

  @Test("Ring buffer preserves order across sustained bounded backpressure")
  func ringBufferDrainsThousandsOfFramesWithoutPrefixCompaction() async throws {
    let frameCount = 2_000
    let buffer = try InstantMediaStreamBuffer<InstantAudioFrame>(
      policy: .realtime(maximumBytes: 32, maximumFrames: 8)
    )
    let producer = Task {
      for index in 0..<frameCount {
        try await buffer.send(
          InstantAudioFrame(
            sequence: Int64(index),
            presentationTimeMicroseconds: Int64(index),
            durationMicroseconds: 1,
            payload: Data([UInt8(truncatingIfNeeded: index)])
          )
        )
      }
      await buffer.finish()
    }

    var expectedSequence: Int64 = 0
    while let frame = try await buffer.next() {
      expectNoDifference(frame.sequence, expectedSequence)
      expectedSequence += 1
    }
    try await producer.value

    expectNoDifference(expectedSequence, Int64(frameCount))
    let metrics = await buffer.metrics
    expectNoDifference(metrics.peakResidentFrames, 8)
    #expect(metrics.peakResidentBytes <= 32)
    expectNoDifference(metrics.totalEnqueuedFrames, Int64(frameCount))
    expectNoDifference(metrics.totalDequeuedFrames, Int64(frameCount))
  }

  @Test("Allocation-free rolling digest matches the compatibility digest")
  func rollingDigestMatchesCompatibilityContract() {
    let frames = (0..<64).map { index in
      InstantVideoFrame(
        sequence: Int64(index),
        presentationTimeMicroseconds: Int64(index * 33_333),
        durationMicroseconds: 33_333,
        flags: index.isMultiple(of: 30) ? [.keyFrame] : [],
        payload: Data(repeating: UInt8(truncatingIfNeeded: index * 7), count: 128)
      )
    }
    var compatibility = InstantMediaStreamDigest()
    var optimized = InstantMediaStreamRollingDigest()
    for frame in frames {
      compatibility.update(frame)
      optimized.update(frame)
    }

    expectNoDifference(optimized.hexadecimal, compatibility.hexadecimal)
  }
}
