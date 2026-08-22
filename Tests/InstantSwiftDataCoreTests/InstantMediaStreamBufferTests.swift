import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantMediaStreamBufferTests {
  @Test("Frame codec survives arbitrary transport chunk boundaries")
  func frameCodecRoundTripsFragmentedContent() throws {
    let format = InstantAudioStreamFormat.voice()
    let codec = InstantMediaStreamFrameCodec<InstantAudioFrame>(
      formatIdentifier: format.identifier,
      maximumFrameBytes: 64
    )
    let frames = [
      InstantAudioFrame(
        sequence: 0,
        presentationTimeMicroseconds: 0,
        durationMicroseconds: 20_000,
        payload: Data([0, 1, 2, 3])
      ),
      InstantAudioFrame(
        sequence: 1,
        presentationTimeMicroseconds: 20_000,
        durationMicroseconds: 20_000,
        flags: [.endOfSegment],
        payload: Data([4, 5, 6, 7])
      ),
    ]
    let bytes = Data(try frames.map(codec.encode).joined().utf8)
    let firstBoundary = min(7, bytes.count)
    let secondBoundary = min(firstBoundary + 19, bytes.count)
    var decoder = codec.makeDecoder(expectedSequence: 0)

    expectNoDifference(try decoder.append(bytes.prefix(firstBoundary)), [])
    let middle = try decoder.append(bytes[firstBoundary..<secondBoundary])
    let final = try decoder.append(bytes[secondBoundary...])
    try decoder.finish()

    expectNoDifference(middle + final, frames)
    expectNoDifference(decoder.bufferedByteCount, 0)
    expectNoDifference(decoder.nextExpectedSequence, 2)
  }

  @Test("Frame decoder rejects gaps and duplicates")
  func frameDecoderRejectsSequenceMismatch() throws {
    let format = InstantVideoStreamFormat.h264(
      width: 1_920,
      height: 1_080,
      frameRate: 30
    )
    let codec = InstantMediaStreamFrameCodec<InstantVideoFrame>(
      formatIdentifier: format.identifier
    )
    let frame = InstantVideoFrame(
      sequence: 2,
      presentationTimeMicroseconds: 66_666,
      durationMicroseconds: 33_333,
      flags: [.keyFrame],
      payload: Data([9, 8, 7])
    )
    var decoder = codec.makeDecoder(expectedSequence: 0)

    #expect(throws: InstantMediaStreamFrameError.sequenceMismatch(expected: 0, actual: 2)) {
      _ = try decoder.append(codec.encode(frame))
    }
  }

  @Test("Lossless buffer suspends instead of exceeding its byte high-water mark")
  func losslessBufferSuspendsProducer() async throws {
    let buffer = try InstantMediaStreamBuffer<InstantAudioFrame>(
      policy: .realtime(maximumBytes: 4, maximumFrames: 1)
    )
    let first = InstantAudioFrame(
      sequence: 0,
      presentationTimeMicroseconds: 0,
      durationMicroseconds: 20_000,
      payload: Data([0, 1, 2, 3])
    )
    let second = InstantAudioFrame(
      sequence: 1,
      presentationTimeMicroseconds: 20_000,
      durationMicroseconds: 20_000,
      payload: Data([4, 5, 6, 7])
    )
    try await buffer.send(first)
    let blocked = Task { try await buffer.send(second) }
    defer { blocked.cancel() }

    try await waitUntil {
      await buffer.metrics.suspendedProducerCount > 0
    }
    var metrics = await buffer.metrics
    expectNoDifference(metrics.residentBytes, 4)
    expectNoDifference(metrics.residentFrames, 1)
    expectNoDifference(metrics.totalEnqueuedFrames, 1)

    expectNoDifference(try await buffer.next(), first)
    try await blocked.value
    expectNoDifference(try await buffer.next(), second)

    metrics = await buffer.metrics
    expectNoDifference(metrics.peakResidentBytes, 4)
    expectNoDifference(metrics.peakResidentFrames, 1)
    expectNoDifference(metrics.totalEnqueuedFrames, 2)
    expectNoDifference(metrics.totalDequeuedFrames, 2)
  }

  @Test("Preview buffering drops oldest frames only when explicitly requested")
  func previewBufferDropsOldest() async throws {
    let buffer = try InstantMediaStreamBuffer<InstantVideoFrame>(
      policy: .preview(maximumBytes: 8, maximumFrames: 2)
    )
    for sequence in 0..<3 {
      try await buffer.send(
        InstantVideoFrame(
          sequence: Int64(sequence),
          presentationTimeMicroseconds: Int64(sequence * 33_333),
          durationMicroseconds: 33_333,
          payload: Data(repeating: UInt8(sequence), count: 4)
        )
      )
    }

    expectNoDifference(try await buffer.next()?.sequence, 1)
    expectNoDifference(try await buffer.next()?.sequence, 2)
    let metrics = await buffer.metrics
    expectNoDifference(metrics.droppedFrames, 1)
    expectNoDifference(metrics.peakResidentBytes, 8)
    expectNoDifference(metrics.peakResidentFrames, 2)
  }

  @Test("Cancellation releases a suspended producer and retained payload")
  func cancellationReleasesPayloadAndWaiter() async throws {
    let buffer = try InstantMediaStreamBuffer<InstantAudioFrame>(
      policy: .realtime(maximumBytes: 1, maximumFrames: 1)
    )
    try await buffer.send(
      InstantAudioFrame(
        sequence: 0,
        presentationTimeMicroseconds: 0,
        durationMicroseconds: 1,
        payload: Data([0])
      )
    )
    let blocked = Task {
      try await buffer.send(
        InstantAudioFrame(
          sequence: 1,
          presentationTimeMicroseconds: 1,
          durationMicroseconds: 1,
          payload: Data([1])
        )
      )
    }
    try await waitUntil {
      await buffer.metrics.suspendedProducerCount > 0
    }
    blocked.cancel()
    await #expect(throws: CancellationError.self) {
      try await blocked.value
    }

    await buffer.cancel()
    let metrics = await buffer.metrics
    expectNoDifference(metrics.residentBytes, 0)
    expectNoDifference(metrics.residentFrames, 0)
  }

  @Test("Cross-SDK digest is deterministic and frame-sensitive")
  func digestIsDeterministic() {
    let frame = InstantAudioFrame(
      sequence: 7,
      presentationTimeMicroseconds: 140_000,
      durationMicroseconds: 20_000,
      payload: Data([1, 3, 3, 7])
    )
    var first = InstantMediaStreamDigest()
    var second = InstantMediaStreamDigest()
    first.update(frame)
    second.update(frame)
    expectNoDifference(first, second)

    var different = InstantMediaStreamDigest()
    different.update(
      InstantAudioFrame(
        sequence: frame.sequence,
        presentationTimeMicroseconds: frame.presentationTimeMicroseconds,
        durationMicroseconds: frame.durationMicroseconds,
        payload: Data([1, 3, 3, 8])
      )
    )
    #expect(first != different)
  }
}

private func waitUntil(
  timeout: Duration = .seconds(1),
  condition: @escaping @Sendable () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while !await condition() {
    guard clock.now < deadline else {
      throw InstantError(
        code: .validationFailed,
        operation: "wait for media stream test condition",
        message: "Timed out waiting for an asynchronous media-stream condition.",
        recovery: "Inspect the bounded buffer waiter state."
      )
    }
    try await Task.sleep(for: .milliseconds(2))
  }
}
