import Darwin
import Foundation
import InstantSwiftDataCore

/// `instant-domain-aev-bench --many-refs`: the list page of #570 at -O, 73 recordings that each hold 1,190 segment
/// refs forward, as Scribe's recordings hold `segments`. Prints the first materialization (every slot sorted) and the
/// median and minimum of later ones (every slot as the last one left it), in wall time and in the process's CPU time,
/// which host load inflates less. Nothing is gated: library-79's 1.9.9 dev run builds it before and after #570 and
/// reads the numbers for the release notes.
enum ManyRefsBench {
  static let recordingCount = 73
  static let refsPerRecording = 1_190
  static let iterations = 30

  static func run() async {
    var generator = SplitMix64(state: 0x570)
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: attributes, triples: seedTriples(using: &generator))
    )
    let plan = InstantQueryPlan(
      id: "recordings.list",
      namespace: "recordings",
      order: InstantQueryOrder("updatedAtMs", .descending),
      limit: 100
    )
    let first = await measure { await store.materializePage(plan).values.count }
    var wall: [Double] = []
    var cpu: [Double] = []
    var count = 0
    for _ in 0..<iterations {
      let measured = await measure { await store.materializePage(plan).values.count }
      wall.append(measured.wallMilliseconds)
      cpu.append(measured.cpuMilliseconds)
      count = measured.count
    }
    wall.sort()
    cpu.sort()
    print(
      """
      MANY_REFS_BENCH recordings=\(recordingCount) refs=\(refsPerRecording) rows=\(count) \
      first_wall_ms=\(format(first.wallMilliseconds)) first_cpu_ms=\(format(first.cpuMilliseconds)) \
      wall_median_ms=\(format(wall[wall.count / 2])) wall_min_ms=\(format(wall[0])) \
      cpu_median_ms=\(format(cpu[cpu.count / 2])) cpu_min_ms=\(format(cpu[0])) iterations=\(iterations) \
      load=\(loadAverageLine())
      """
    )
  }

  private static let attributes = [
    InstantAttribute(id: "recordings/title", namespace: "recordings", name: "title", valueType: .string, isRequired: false),
    InstantAttribute(
      id: "recordings/updatedAtMs",
      namespace: "recordings",
      name: "updatedAtMs",
      valueType: .number,
      isRequired: false,
      isIndexed: true
    ),
    InstantAttribute(
      id: "recordings/segments",
      namespace: "recordings",
      name: "segments",
      valueType: .ref,
      isRequired: false,
      cardinality: .many,
      isIndexed: true,
      forwardIdentity: "recordings/segments",
      reverseIdentity: "transcriptionSegments/recording",
      linkNamespace: "transcriptionSegments"
    ),
  ]

  private static func seedTriples(using generator: inout SplitMix64) -> [InstantTriple] {
    var triples: [InstantTriple] = []
    triples.reserveCapacity(recordingCount * (refsPerRecording + 2))
    for index in 0..<recordingCount {
      let id = "rec-\(String(format: "%03d", index))"
      let time = InstantTimestamp(milliseconds: 1_000 + Int64(index))
      triples.append(
        InstantTriple(entityID: id, attributeID: "recordings/title", value: .string("Recording \(index)"), txID: "seed", txTime: time)
      )
      triples.append(
        InstantTriple(
          entityID: id,
          attributeID: "recordings/updatedAtMs",
          value: .number(Double(10_000 + index)),
          txID: "seed",
          txTime: time
        )
      )
      for _ in 0..<refsPerRecording {
        triples.append(
          InstantTriple(
            entityID: id,
            attributeID: "recordings/segments",
            value: .ref(uuid(using: &generator)),
            txID: "seed",
            txTime: time
          )
        )
      }
    }
    return triples
  }

  private static func measure(
    _ body: () async -> Int
  ) async -> (wallMilliseconds: Double, cpuMilliseconds: Double, count: Int) {
    let cpu0 = processCPUNanoseconds()
    let wall0 = DispatchTime.now().uptimeNanoseconds
    let count = await body()
    let wall1 = DispatchTime.now().uptimeNanoseconds
    let cpu1 = processCPUNanoseconds()
    return (Double(wall1 &- wall0) / 1e6, Double(cpu1 &- cpu0) / 1e6, count)
  }

  /// User and system time of the whole process: the store's actor runs on the cooperative pool, not this thread.
  private static func processCPUNanoseconds() -> UInt64 {
    var usage = rusage()
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    let user = UInt64(usage.ru_utime.tv_sec) * 1_000_000_000 + UInt64(usage.ru_utime.tv_usec) * 1_000
    let system = UInt64(usage.ru_stime.tv_sec) * 1_000_000_000 + UInt64(usage.ru_stime.tv_usec) * 1_000
    return user + system
  }

  private static func uuid(using generator: inout SplitMix64) -> String {
    let high = generator.next()
    let low = generator.next()
    let hex = String(format: "%016llx%016llx", high, low)
    let characters = Array(hex)
    return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32]
      .map { String(characters[$0]) }
      .joined(separator: "-")
  }

  private static func format(_ value: Double) -> String {
    String(format: "%.3f", value)
  }

  private static func loadAverageLine() -> String {
    var loads = [Double](repeating: 0, count: 3)
    guard getloadavg(&loads, 3) == 3 else { return "unknown" }
    return loads.map { String(format: "%.2f", $0) }.joined(separator: ",")
  }

  private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }
}
