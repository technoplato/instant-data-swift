import CustomDump
import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#endif

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantMediaStreamOptimizationTests {
  @Test("Binary codec decodes fragmented frames into a caller-owned sink")
  func binaryCodecRoundTripsWithoutFrameArrayAllocation() throws {
    let codec = InstantMediaStreamBinaryCodec<InstantAudioFrame>(
      formatIdentifier: InstantAudioStreamFormat.voice().identifier,
      maximumFrameBytes: 64
    )
    var expected: [InstantAudioFrame] = []
    expected.reserveCapacity(32)
    for index in 0..<32 {
      let sequence = Int64(index)
      let presentationTime = sequence * 20_000
      let flags: InstantMediaStreamFrameFlags = index == 31 ? [.endOfSegment] : []
      let payload = Data(repeating: UInt8(index), count: 16)
      expected.append(
        InstantAudioFrame(
          sequence: sequence,
          presentationTimeMicroseconds: presentationTime,
          durationMicroseconds: 20_000,
          flags: flags,
          payload: payload
        )
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

  @Test("Direct binary framing is smaller and faster than the JSON/Base64 compatibility envelope")
  func binaryCodecRemovesBase64AndJSONCPU() throws {
    let payload = Data(repeating: 0xA5, count: 4_096)
    let frame = InstantAudioFrame(
      sequence: 41,
      presentationTimeMicroseconds: 820_000,
      durationMicroseconds: 20_000,
      flags: [.endOfSegment],
      payload: payload
    )
    let format = InstantAudioStreamFormat.voice().identifier
    let binary = InstantMediaStreamBinaryCodec<InstantAudioFrame>(
      formatIdentifier: format,
      maximumFrameBytes: payload.count
    )
    let compatibility = InstantMediaStreamFrameCodec<InstantAudioFrame>(
      formatIdentifier: format,
      maximumFrameBytes: payload.count
    )

    let binaryBytes = try binary.encode(frame)
    let compatibilityString = try compatibility.encode(frame)
    let compatibilityBytes = Data(compatibilityString.utf8)
    expectNoDifference(
      binaryBytes.count,
      InstantMediaStreamBinaryCodec<InstantAudioFrame>.headerByteCount + payload.count
    )
    #expect(compatibilityBytes.count > binaryBytes.count + payload.count / 4)

    let iterationCount = 2_000
    let binarySeconds = try bestOfThreeSeconds {
      var byteCount = 0
      for _ in 0..<iterationCount {
        byteCount += try binary.encode(frame).count
      }
      #expect(byteCount > 0)
    }
    let compatibilitySeconds = try bestOfThreeSeconds {
      var byteCount = 0
      for _ in 0..<iterationCount {
        let value = try compatibility.encode(frame)
        byteCount += value.utf8.count
      }
      #expect(byteCount > 0)
    }
    print(
      String(
        format:
          "SEVEN_OPT_BINARY_CODEC binary_s=%.6f compatibility_s=%.6f ratio=%.3f binary_bytes=%d compatibility_bytes=%d",
        binarySeconds,
        compatibilitySeconds,
        binarySeconds / compatibilitySeconds,
        binaryBytes.count,
        compatibilityBytes.count
      )
    )
    #expect(binarySeconds < compatibilitySeconds)
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

  @Test("One released slot wakes one suspended producer instead of a thundering herd")
  func oneSlotResumesOneProducer() async throws {
    let buffer = try InstantMediaStreamBuffer<InstantAudioFrame>(
      policy: .realtime(maximumBytes: 1, maximumFrames: 1)
    )
    try await buffer.send(oneByteFrame(sequence: 0))

    var producers: [Task<Void, any Error>] = []
    producers.reserveCapacity(8)
    for sequence in 1...8 {
      producers.append(
        Task {
          try await buffer.send(oneByteFrame(sequence: Int64(sequence)))
        }
      )
    }
    defer { producers.forEach { $0.cancel() } }

    try await waitUntil {
      await buffer.metrics.suspendedProducerCount >= 8
    }
    let first = try #require(await buffer.next())
    expectNoDifference(first.sequence, 0)
    try await waitUntil {
      await buffer.metrics.totalEnqueuedFrames >= 2
    }
    try await Task.sleep(for: .milliseconds(10))
    var metrics = await buffer.metrics
    expectNoDifference(metrics.totalEnqueuedFrames, 2)
    expectNoDifference(metrics.residentFrames, 1)

    var observed: Set<Int64> = [0]
    for _ in 0..<8 {
      let frame = try #require(await buffer.next())
      observed.insert(frame.sequence)
    }
    for producer in producers {
      try await producer.value
    }
    expectNoDifference(observed, Set((0...8).map(Int64.init)))
    metrics = await buffer.metrics
    expectNoDifference(metrics.totalEnqueuedFrames, 9)
    expectNoDifference(metrics.totalDequeuedFrames, 9)
  }

  @Test("Allocation-free rolling digest matches the compatibility digest")
  func rollingDigestMatchesCompatibilityContract() {
    var frames: [InstantVideoFrame] = []
    frames.reserveCapacity(64)
    for index in 0..<64 {
      let sequence = Int64(index)
      let flags: InstantMediaStreamFrameFlags = index.isMultiple(of: 30) ? [.keyFrame] : []
      frames.append(
        InstantVideoFrame(
          sequence: sequence,
          presentationTimeMicroseconds: sequence * 33_333,
          durationMicroseconds: 33_333,
          flags: flags,
          payload: Data(
            repeating: UInt8(truncatingIfNeeded: index * 7),
            count: 128
          )
        )
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

  @Test("Twenty thousand synchronized audio frames stay inside a fixed memory and CPU envelope")
  func sustainedAudioStreamHasBoundedResources() async throws {
    let frameCount = 20_000
    let payloadByteCount = 320
    let maximumFrames = 64
    let maximumBytes = payloadByteCount * maximumFrames
    let buffer = try InstantMediaStreamBuffer<InstantAudioFrame>(
      policy: .realtime(
        maximumBytes: maximumBytes,
        maximumFrames: maximumFrames
      )
    )
    let baseline = processResources()
    var peakPhysical = baseline.physicalFootprintBytes
    let clock = ContinuousClock()
    let started = clock.now

    let producer = Task {
      for index in 0..<frameCount {
        try await buffer.send(
          InstantAudioFrame(
            sequence: Int64(index),
            presentationTimeMicroseconds: Int64(index * 20_000),
            durationMicroseconds: 20_000,
            flags: index == frameCount - 1 ? [.endOfSegment] : [],
            payload: Data(repeating: UInt8(truncatingIfNeeded: index), count: payloadByteCount)
          )
        )
      }
      await buffer.finish()
    }

    var digest = InstantMediaStreamRollingDigest()
    var expectedSequence: Int64 = 0
    while let frame = try await buffer.next() {
      expectNoDifference(frame.sequence, expectedSequence)
      digest.update(frame)
      expectedSequence += 1
      if expectedSequence.isMultiple(of: 512) {
        peakPhysical = maxOptional(
          peakPhysical,
          processResources().physicalFootprintBytes
        )
      }
    }
    try await producer.value

    let wallSeconds = started.duration(to: clock.now).secondsValue
    let end = processResources()
    peakPhysical = maxOptional(peakPhysical, end.physicalFootprintBytes)
    let cpuSeconds = max(0, end.cpuSeconds - baseline.cpuSeconds)
    let averageCPUPercent = wallSeconds > 0 ? cpuSeconds / wallSeconds * 100 : 0
    let incrementalPeakBytes = positiveDifference(peakPhysical, baseline.physicalFootprintBytes)
    let settledGrowthBytes = positiveDifference(
      end.physicalFootprintBytes,
      baseline.physicalFootprintBytes
    )
    let metrics = await buffer.metrics

    print(
      String(
        format:
          "SEVEN_OPT_STREAM_RESOURCE frames=%d wall_s=%.6f frames_per_s=%.1f cpu_pct=%.1f peak_growth_bytes=%lld settled_growth_bytes=%lld peak_buffer_bytes=%d peak_buffer_frames=%d digest=%@",
        frameCount,
        wallSeconds,
        Double(frameCount) / max(wallSeconds, 0.000_001),
        averageCPUPercent,
        incrementalPeakBytes ?? -1,
        settledGrowthBytes ?? -1,
        metrics.peakResidentBytes,
        metrics.peakResidentFrames,
        digest.hexadecimal
      )
    )

    expectNoDifference(expectedSequence, Int64(frameCount))
    #expect(metrics.peakResidentBytes <= maximumBytes)
    #expect(metrics.peakResidentFrames <= maximumFrames)
    #expect(metrics.droppedFrames == 0)
    #expect(wallSeconds < 5)
    #expect(averageCPUPercent <= 200)
    if let incrementalPeakBytes {
      #expect(incrementalPeakBytes <= 32 * 1_024 * 1_024)
    }
    if let settledGrowthBytes {
      #expect(settledGrowthBytes <= 16 * 1_024 * 1_024)
    }
  }
}

private func oneByteFrame(sequence: Int64) -> InstantAudioFrame {
  InstantAudioFrame(
    sequence: sequence,
    presentationTimeMicroseconds: sequence,
    durationMicroseconds: 1,
    payload: Data([UInt8(truncatingIfNeeded: sequence)])
  )
}

private func waitUntil(
  timeout: Duration = .seconds(1),
  condition: @escaping @Sendable () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while true {
    if await condition() { return }
    guard clock.now < deadline else {
      throw InstantError(
        code: .validationFailed,
        operation: "wait for seven-optimization condition",
        message: "Timed out waiting for a bounded stream condition.",
        recovery: "Inspect producer and consumer waiter ownership."
      )
    }
    try await Task.sleep(for: .milliseconds(2))
  }
}

private func bestOfThreeSeconds(
  _ operation: () throws -> Void
) rethrows -> Double {
  let clock = ContinuousClock()
  var best = Double.infinity
  for _ in 0..<3 {
    let started = clock.now
    try operation()
    best = min(best, started.duration(to: clock.now).secondsValue)
  }
  return best
}

private struct ProcessResourceSnapshot {
  var physicalFootprintBytes: UInt64?
  var cpuSeconds: Double
}

private func processResources() -> ProcessResourceSnapshot {
  #if canImport(Darwin)
  var vmInfo = task_vm_info_data_t()
  var vmCount = mach_msg_type_number_t(
    MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
  )
  let vmResult = withUnsafeMutablePointer(to: &vmInfo) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) { rebound in
      task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &vmCount)
    }
  }
  var usage = rusage()
  let usageResult = getrusage(RUSAGE_SELF, &usage)
  let cpuSeconds = usageResult == 0
    ? Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
      + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    : 0
  return ProcessResourceSnapshot(
    physicalFootprintBytes: vmResult == KERN_SUCCESS ? UInt64(vmInfo.phys_footprint) : nil,
    cpuSeconds: cpuSeconds
  )
  #else
  return ProcessResourceSnapshot(physicalFootprintBytes: nil, cpuSeconds: 0)
  #endif
}

private func maxOptional(_ lhs: UInt64?, _ rhs: UInt64?) -> UInt64? {
  switch (lhs, rhs) {
  case let (.some(lhs), .some(rhs)): max(lhs, rhs)
  case let (.some(lhs), .none): lhs
  case let (.none, .some(rhs)): rhs
  case (.none, .none): nil
  }
}

private func positiveDifference(_ lhs: UInt64?, _ rhs: UInt64?) -> Int64? {
  guard let lhs, let rhs else { return nil }
  return lhs >= rhs ? Int64(clamping: lhs - rhs) : 0
}

private extension Duration {
  var secondsValue: Double {
    let components = self.components
    return Double(components.seconds)
      + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }
}
