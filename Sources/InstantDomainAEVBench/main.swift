import Darwin
import Foundation
import InstantSwiftDataCore

/// Isolated Release ship gate for the store-only DomainAEV lookup floor.
///
/// `locationLabel` equals uses `indexedValueEntities`, not a full EAV scan.
/// The 0.069 ms bar is the TypeScript InstaQL floor. Do not lower it. Invoke
/// only the `instant-domain-aev-bench` product so gym test targets are not
/// compiled before the measurement. Wait briefly for a quiet host after that
/// compile. Score wall time when the host is quiet. On a noisy host, score
/// in-thread CPU of the same materialize loop so host preemption is not a
/// product miss. Missing thread-CPU samples fail closed.
@main
struct InstantDomainAEVBench {
  static func main() async {
    do {
      try await run()
    } catch {
      fputs("DOMAIN_AEV_SHIP_GATE failed error=\(error)\n", stderr)
      exit(1)
    }
  }

  private static let maximumLocationAverageMilliseconds = 0.069
  private static let maximumPhysicalGrowthBytes = 9 * 1024 * 1024
  private static let recordingCount = 200
  private static let segmentsPerRecording = 8
  private static let warmupIterations = 5
  private static let measuredIterations = 500
  private static let maximumOneMinuteLoadAveragePerCPU = 1.0
  private static let quietWaitTimeoutNanoseconds: UInt64 = 90 * 1_000_000_000
  private static let quietWaitPollNanoseconds: UInt64 = 2 * 1_000_000_000
  private static let locations = [
    "Home Office", "Kitchen", "Car — commute", "Park walk", "Coffee shop",
    "Conference room A", "Conference room B", "Airport terminal", "Gym", "Library",
  ]

  private static func run() async throws {
    _ = pthread_set_qos_class_self_np(QOS_CLASS_USER_INTERACTIVE, 0)
    let quietWait = await waitForQuietHost()
    let baseline = InstantProcessMemory.sample()
    let triples = productSeedTriples()
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(
        attributes: domainAttributes(),
        triples: triples
      )
    )

    let locationPlan = InstantQueryPlan(
      id: "store.location",
      namespace: "recordings",
      filters: [.equals(field: "locationLabel", value: .string("Conference room A"))],
      limit: 200
    )
    _ = await store.measureMaterializeAverages(
      locationPlan,
      iterations: warmupIterations
    )
    let locationBench = await store.measureMaterializeAverages(
      locationPlan,
      iterations: measuredIterations
    )
    let locationAvgMs = locationBench.averageWallNanoseconds / 1_000_000
    let locationCPUAvgMs = locationBench.averageThreadCPUNanoseconds / 1_000_000
    let locationCount = locationBench.lastCount

    let listPlan = InstantQueryPlan(
      id: "store.list",
      namespace: "recordings",
      order: InstantQueryOrder("updatedAtMs", .descending),
      limit: 50
    )
    _ = await store.measureMaterializeAverages(
      listPlan,
      iterations: warmupIterations
    )
    let listBench = await store.measureMaterializeAverages(
      listPlan,
      iterations: measuredIterations
    )
    let listAvgMs = listBench.averageWallNanoseconds / 1_000_000
    let listCPUAvgMs = listBench.averageThreadCPUNanoseconds / 1_000_000
    let listCount = listBench.lastCount

    let after = InstantProcessMemory.sample()
    let growth: UInt64 =
      if let baseline, let after, after.physicalFootprintBytes > baseline.physicalFootprintBytes
      {
        after.physicalFootprintBytes - baseline.physicalFootprintBytes
      } else { 0 }

    let scoredMetric = scoredLatencyMetric(
      wallMilliseconds: locationAvgMs,
      threadCPUMilliseconds: locationCPUAvgMs,
      isQuiet: quietWait.isQuiet
    )
    print(
      """
      STORE_ONLY_BENCH profile=200rec×8seg_wordsJSON \
      \(hostLoadAverageLine()) \
      host_quiet=\(quietWait.isQuiet) host_wait_s=\(String(format: "%.1f", quietWait.waitedSeconds)) \
      scored_metric=\(scoredMetric.rawValue) \
      physical_growth_bytes=\(growth) mb_growth=\(String(format: "%.1f", Double(growth) / 1024 / 1024)) \
      triple_count=\(triples.count) \
      list50_avg_ms=\(String(format: "%.4f", listAvgMs)) list50_cpu_avg_ms=\(String(format: "%.4f", listCPUAvgMs)) list_count=\(listCount) \
      location_eq_avg_ms=\(String(format: "%.4f", locationAvgMs)) location_eq_cpu_avg_ms=\(String(format: "%.4f", locationCPUAvgMs)) location_matches=\(locationCount)
      """
    )

    var failures: [String] = []
    if locationCount != 20 {
      failures.append("location_matches=\(locationCount) expected=20")
    }
    if listCount != 50 {
      failures.append("list_count=\(listCount) expected=50")
    }
    if growth >= UInt64(maximumPhysicalGrowthBytes) {
      failures.append(
        "physical_growth_bytes=\(growth) maximum=\(maximumPhysicalGrowthBytes)"
      )
    }
    switch scoredMetric {
    case .wall, .threadCPU:
      break
    case .threadCPUUnavailable:
      failures.append(
        "THREAD_CPU_UNAVAILABLE location_eq_avg_ms=\(String(format: "%.4f", locationAvgMs)) location_eq_cpu_avg_ms=\(String(format: "%.4f", locationCPUAvgMs)) maximum=\(maximumLocationAverageMilliseconds)"
      )
    case .product:
      if quietWait.isQuiet {
        failures.append(
          "location_eq_avg_ms=\(String(format: "%.4f", locationAvgMs)) location_eq_cpu_avg_ms=\(String(format: "%.4f", locationCPUAvgMs)) maximum=\(maximumLocationAverageMilliseconds)"
        )
      } else {
        failures.append(
          "location_eq_avg_ms=\(String(format: "%.4f", locationAvgMs)) location_eq_cpu_avg_ms=\(String(format: "%.4f", locationCPUAvgMs)) maximum=\(maximumLocationAverageMilliseconds) \(hostLoadAverageLine())"
        )
      }
    }
    if !failures.isEmpty {
      print("DOMAIN_AEV_SHIP_GATE failed \(failures.joined(separator: " "))")
      exit(1)
    }
    print("DOMAIN_AEV_SHIP_GATE passed")
  }

  private static func productSeedTriples() -> [InstantTriple] {
    var triples: [InstantTriple] = []
    let now = InstantTimestamp(milliseconds: 1_700_200_000_000)
    let tx = "domain-aev-seed"
    let wordsJSON =
      "[{\"t\":\"w0\"},{\"t\":\"w1\"},{\"t\":\"w2\"},{\"t\":\"w3\"},{\"t\":\"w4\"},{\"t\":\"w5\"},{\"t\":\"w6\"},{\"t\":\"w7\"},{\"t\":\"w8\"},{\"t\":\"w9\"},{\"t\":\"w10\"},{\"t\":\"w11\"}]"
    for index in 0..<recordingCount {
      let rid = "rec-\(index)"
      let loc = locations[index % locations.count]
      triples.append(contentsOf: [
        InstantTriple(
          entityID: rid,
          attributeID: "recordings/id",
          value: .string(rid),
          txID: tx,
          txTime: now
        ),
        InstantTriple(
          entityID: rid,
          attributeID: "recordings/title",
          value: .string(String(format: "Recording %03d", index + 1)),
          txID: tx,
          txTime: now
        ),
        InstantTriple(
          entityID: rid,
          attributeID: "recordings/locationLabel",
          value: .string(loc),
          txID: tx,
          txTime: now
        ),
        InstantTriple(
          entityID: rid,
          attributeID: "recordings/latitude",
          value: .number(37.7 + Double(index % 50) * 0.01),
          txID: tx,
          txTime: now
        ),
        InstantTriple(
          entityID: rid,
          attributeID: "recordings/speakerCount",
          value: .number(Double(1 + index % 3)),
          txID: tx,
          txTime: now
        ),
        InstantTriple(
          entityID: rid,
          attributeID: "recordings/updatedAtMs",
          value: .number(Double(1_700_200_000_000 - index * 60_000)),
          txID: tx,
          txTime: now
        ),
      ])
      for segment in 0..<segmentsPerRecording {
        let sid = "seg-\(index)-\(segment)"
        triples.append(contentsOf: [
          InstantTriple(
            entityID: sid,
            attributeID: "transcriptionSegments/id",
            value: .string(sid),
            txID: tx,
            txTime: now
          ),
          InstantTriple(
            entityID: sid,
            attributeID: "transcriptionSegments/recordingID",
            value: .string(rid),
            txID: tx,
            txTime: now
          ),
          InstantTriple(
            entityID: sid,
            attributeID: "transcriptionSegments/wordsJSON",
            value: .string(wordsJSON),
            txID: tx,
            txTime: now
          ),
          InstantTriple(
            entityID: sid,
            attributeID: "transcriptionSegments/wordCount",
            value: .number(12),
            txID: tx,
            txTime: now
          ),
          InstantTriple(
            entityID: sid,
            attributeID: "transcriptionSegments/seq",
            value: .number(Double(segment)),
            txID: tx,
            txTime: now
          ),
        ])
      }
    }
    return triples
  }

  private static func domainAttributes() -> [InstantAttribute] {
    [
      .primaryKey(namespace: "recordings"),
      InstantAttribute(
        id: "recordings/title",
        namespace: "recordings",
        name: "title",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "recordings/locationLabel",
        namespace: "recordings",
        name: "locationLabel",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "recordings/latitude",
        namespace: "recordings",
        name: "latitude",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "recordings/speakerCount",
        namespace: "recordings",
        name: "speakerCount",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "recordings/updatedAtMs",
        namespace: "recordings",
        name: "updatedAtMs",
        valueType: .number,
        isIndexed: true
      ),
      .primaryKey(namespace: "transcriptionSegments"),
      InstantAttribute(
        id: "transcriptionSegments/recordingID",
        namespace: "transcriptionSegments",
        name: "recordingID",
        valueType: .string,
        isIndexed: true
      ),
      InstantAttribute(
        id: "transcriptionSegments/wordsJSON",
        namespace: "transcriptionSegments",
        name: "wordsJSON",
        valueType: .string
      ),
      InstantAttribute(
        id: "transcriptionSegments/wordCount",
        namespace: "transcriptionSegments",
        name: "wordCount",
        valueType: .number,
        isIndexed: true
      ),
      InstantAttribute(
        id: "transcriptionSegments/seq",
        namespace: "transcriptionSegments",
        name: "seq",
        valueType: .number,
        isIndexed: true
      ),
    ]
  }

  private static func waitForQuietHost() async -> QuietHostWait {
    let ncpu = logicalCPUCount()
    let maximumLoad = maximumOneMinuteLoadAveragePerCPU * Double(ncpu)
    let started = DispatchTime.now()
    print(
      "HOST_WAIT started ncpu=\(ncpu) maximum_loadavg1=\(String(format: "%.2f", maximumLoad)) timeout_s=90 \(hostLoadAverageLine())"
    )
    while true {
      let load1 = oneMinuteLoadAverage()
      let elapsedNanoseconds = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
      let waitedSeconds = Double(elapsedNanoseconds) / 1_000_000_000
      if let load1, load1 <= maximumLoad {
        print(
          "HOST_WAIT reached loadavg1=\(String(format: "%.2f", load1)) waited_s=\(String(format: "%.1f", waitedSeconds))"
        )
        return QuietHostWait(isQuiet: true, waitedSeconds: waitedSeconds)
      }
      if elapsedNanoseconds >= quietWaitTimeoutNanoseconds {
        let loadText = load1.map { String(format: "%.2f", $0) } ?? "unavailable"
        print(
          "HOST_WAIT timeout CONTAMINATED_HOST loadavg1=\(loadText) waited_s=\(String(format: "%.1f", waitedSeconds))"
        )
        return QuietHostWait(isQuiet: false, waitedSeconds: waitedSeconds)
      }
      try? await Task.sleep(nanoseconds: quietWaitPollNanoseconds)
    }
  }

  private static func logicalCPUCount() -> Int {
    var count: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let result = sysctlbyname("hw.logicalcpu", &count, &size, nil, 0)
    if result == 0, count > 0 {
      return Int(count)
    }
    return 10
  }

  private static func loadAverages() -> (Double, Double, Double)? {
    var loads = [Double](repeating: 0, count: 3)
    let count = loads.withUnsafeMutableBufferPointer { buffer -> Int32 in
      guard let base = buffer.baseAddress else {
        return -1
      }
      return getloadavg(base, 3)
    }
    guard count == 3 else {
      return nil
    }
    return (loads[0], loads[1], loads[2])
  }

  private static func oneMinuteLoadAverage() -> Double? {
    loadAverages()?.0
  }

  private static func hostLoadAverageLine() -> String {
    guard let loads = loadAverages() else {
      return "host_loadavg=unavailable"
    }
    return String(
      format: "host_loadavg=%.2f %.2f %.2f",
      loads.0,
      loads.1,
      loads.2
    )
  }
}

private struct QuietHostWait {
  var isQuiet: Bool
  var waitedSeconds: Double
}

private enum ScoredLatencyMetric: String {
  case wall
  case threadCPU = "thread_cpu"
  case threadCPUUnavailable = "thread_cpu_unavailable"
  case product
}

private func scoredLatencyMetric(
  wallMilliseconds: Double,
  threadCPUMilliseconds: Double,
  isQuiet: Bool
) -> ScoredLatencyMetric {
  if wallMilliseconds < InstantDomainAEVBench.maximumLocationAverageMilliseconds {
    return .wall
  }
  if isQuiet {
    return .product
  }
  if threadCPUMilliseconds <= 0 {
    return .threadCPUUnavailable
  }
  if threadCPUMilliseconds < InstantDomainAEVBench.maximumLocationAverageMilliseconds {
    return .threadCPU
  }
  return .product
}
