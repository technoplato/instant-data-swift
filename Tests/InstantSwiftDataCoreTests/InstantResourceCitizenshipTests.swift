import CustomDump
import Foundation
import Testing

#if canImport(Darwin)
import Darwin
#endif

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantResourceCitizenshipTests {
  @Test("Accelerated native media remains a healthy realtime citizen")
  func nativeMediaPrimitiveReportsBurstAndRealtimeEquivalentResources() async throws {
    let policy = try ResourceCitizenshipPolicy.load()
      .profiles.nativeMediaPrimitiveBurst

    // Warm the allocator and actor runtime before the measured steady-state lane.
    try await runWarmup()

    let frameCount = 20_000
    let payloadByteCount = 320
    let maximumFrames = 64
    let maximumBytes = payloadByteCount * maximumFrames
    let durationMicroseconds = Int64(policy.logicalFrameDurationMicroseconds)
    let logicalSeconds =
      Double(frameCount) * Double(durationMicroseconds) / 1_000_000
    let buffer = try InstantMediaStreamBuffer<InstantAudioFrame>(
      policy: .realtime(
        maximumBytes: maximumBytes,
        maximumFrames: maximumFrames
      )
    )

    let startThermal = thermalStateName()
    let baseline = processResources()
    var peakPhysical = baseline.physicalFootprintBytes
    let clock = ContinuousClock()
    let started = clock.now

    let producer = Task {
      for index in 0..<frameCount {
        try await buffer.send(
          InstantAudioFrame(
            sequence: Int64(index),
            presentationTimeMicroseconds: Int64(index) * durationMicroseconds,
            durationMicroseconds: durationMicroseconds,
            flags: index == frameCount - 1 ? [.endOfSegment] : [],
            payload: Data(
              repeating: UInt8(truncatingIfNeeded: index),
              count: payloadByteCount
            )
          )
        )
      }
      await buffer.finish()
    }

    var expectedSequence: Int64 = 0
    var digest = InstantMediaStreamRollingDigest()
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

    try await Task.sleep(for: .milliseconds(50))
    let wallSeconds = started.duration(to: clock.now).secondsValue
    let end = processResources()
    let endThermal = thermalStateName()
    peakPhysical = maxOptional(peakPhysical, end.physicalFootprintBytes)
    let cpuSeconds = max(0, end.cpuSeconds - baseline.cpuSeconds)
    let burstAverageCPUPercent =
      wallSeconds > 0 ? cpuSeconds / wallSeconds * 100 : 0
    let cpuSecondsPerLogicalSecond =
      logicalSeconds > 0 ? cpuSeconds / logicalSeconds : 0
    let equivalentRealtimeCPUPercent = cpuSecondsPerLogicalSecond * 100
    let incrementalPeakBytes = positiveDifference(
      peakPhysical,
      baseline.physicalFootprintBytes
    )
    let settledGrowthBytes = positiveDifference(
      end.physicalFootprintBytes,
      baseline.physicalFootprintBytes
    )
    let metrics = await buffer.metrics

    print(
      String(
        format:
          "RESOURCE_CITIZENSHIP_STREAM frames=%d logical_s=%.3f wall_s=%.6f cpu_s=%.6f burst_cpu_pct=%.3f realtime_cpu_pct=%.6f cpu_s_per_logical_s=%.8f peak_growth_bytes=%lld settled_growth_bytes=%lld peak_buffer_bytes=%d peak_buffer_frames=%d dropped=%lld thermal_start=%@ thermal_end=%@ digest=%@",
        frameCount,
        logicalSeconds,
        wallSeconds,
        cpuSeconds,
        burstAverageCPUPercent,
        equivalentRealtimeCPUPercent,
        cpuSecondsPerLogicalSecond,
        incrementalPeakBytes ?? -1,
        settledGrowthBytes ?? -1,
        metrics.peakResidentBytes,
        metrics.peakResidentFrames,
        metrics.droppedFrames,
        startThermal,
        endThermal,
        digest.hexadecimal
      )
    )

    expectNoDifference(expectedSequence, Int64(frameCount))
    #expect(
      burstAverageCPUPercent
        <= policy.maximumBurstAverageCPUPercentOfOneCore
    )
    #expect(
      equivalentRealtimeCPUPercent
        <= policy.maximumEquivalentRealtimeCPUPercentOfOneCore
    )
    #expect(
      cpuSecondsPerLogicalSecond
        <= policy.maximumCPUSecondsPerLogicalSecond
    )
    #expect(metrics.peakResidentBytes <= policy.maximumBufferBytes)
    #expect(metrics.peakResidentFrames <= policy.maximumBufferFrames)
    #expect(metrics.droppedFrames <= policy.maximumDroppedFrames)
    if let incrementalPeakBytes {
      #expect(
        incrementalPeakBytes
          <= policy.maximumIncrementalPeakPhysicalFootprintBytes
      )
    }
    if let settledGrowthBytes {
      #expect(
        settledGrowthBytes
          <= policy.maximumSettledPhysicalFootprintGrowthBytes
      )
    }
    #if os(macOS)
    #expect(policy.allowedTerminalThermalStates.contains(endThermal))
    #endif
  }
}

private struct ResourceCitizenshipPolicy: Decodable {
  struct Profiles: Decodable {
    var nativeMediaPrimitiveBurst: NativeMediaPrimitiveBurst
  }

  struct NativeMediaPrimitiveBurst: Decodable {
    var logicalFrameDurationMicroseconds: Int
    var maximumBurstAverageCPUPercentOfOneCore: Double
    var maximumEquivalentRealtimeCPUPercentOfOneCore: Double
    var maximumCPUSecondsPerLogicalSecond: Double
    var maximumIncrementalPeakPhysicalFootprintBytes: Int64
    var maximumSettledPhysicalFootprintGrowthBytes: Int64
    var maximumBufferBytes: Int
    var maximumBufferFrames: Int
    var maximumDroppedFrames: Int64
    var allowedTerminalThermalStates: [String]
  }

  var profiles: Profiles

  static func load() throws -> Self {
    let testsDirectory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
    let packageRoot = testsDirectory
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let url = packageRoot
      .appendingPathComponent("validation")
      .appendingPathComponent("resource-citizenship-policy.json")
    return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
  }
}

private func runWarmup() async throws {
  let buffer = try InstantMediaStreamBuffer<InstantAudioFrame>(
    policy: .realtime(maximumBytes: 10_240, maximumFrames: 32)
  )
  let producer = Task {
    for index in 0..<256 {
      try await buffer.send(
        InstantAudioFrame(
          sequence: Int64(index),
          presentationTimeMicroseconds: Int64(index) * 20_000,
          durationMicroseconds: 20_000,
          payload: Data(repeating: 0xA5, count: 320)
        )
      )
    }
    await buffer.finish()
  }
  while try await buffer.next() != nil {}
  try await producer.value
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
    physicalFootprintBytes: vmResult == KERN_SUCCESS
      ? UInt64(vmInfo.phys_footprint)
      : nil,
    cpuSeconds: cpuSeconds
  )
  #else
  return ProcessResourceSnapshot(physicalFootprintBytes: nil, cpuSeconds: 0)
  #endif
}

private func thermalStateName() -> String {
  #if os(macOS)
  switch ProcessInfo.processInfo.thermalState {
  case .nominal: "nominal"
  case .fair: "fair"
  case .serious: "serious"
  case .critical: "critical"
  @unknown default: "unknown"
  }
  #else
  "unavailable"
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
