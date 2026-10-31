// History:
// - 2026-10-31: #1493: the observation chain with the phone's 48 live queries, each read by a FetchAll, measured in
//   release (scripts/contention-exercises/run-observation-exercise.sh).

import Foundation
import InstantSwiftData
import Observation

/// The observation exercise (#1493).
///
/// Opens the phone's 48 live queries as 48 `FetchAll` wrappers over a live transport that never connects (so each is a
/// live query's whole chain, registration and server-error stage included), then prints:
/// - `OBSERVATION tasks`: the library tasks the 48 open observations keep (the task census);
/// - `OBSERVATION latency`: for each write to a row all 48 show, the wall time from the store's publication starting
///   (`InstantStore.lastPublicationStartedAt`) to each wrapper's value changing (Observation's `onChange`), in
///   microseconds: p50, p90, p99 and the worst, over every write and wrapper.
///
/// Environment: `INSTANT_OBSERVATION_WRITES` (200), and `INSTANT_OBSERVATION_IDLE_SECONDS` (0) to hold the 48
/// observations open and idle that long first, so xctrace's Swift Concurrency template can count the tasks alive.
@main
struct InstantObservationExercise {
  static let observerCount = 48
  static let rowCount = 50

  static func main() async {
    do {
      try await run()
    } catch {
      FileHandle.standardError.write(Data("OBSERVATION failed: \(error)\n".utf8))
      exit(1)
    }
  }

  static func run() async throws {
    let environment = ProcessInfo.processInfo.environment
    let writes = Int(environment["INSTANT_OBSERVATION_WRITES"] ?? "") ?? 200
    let idleSeconds = Int(environment["INSTANT_OBSERVATION_IDLE_SECONDS"] ?? "") ?? 0
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantObservationExercise-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    var configuration = InstantRuntimeConfiguration(
      appID: "observation-chain-exercise",
      persistenceURL: directory.appendingPathComponent("state.sqlite"),
      initialAttributes: ExerciseLine.instantAttributes
    )
    configuration.liveTransport = .connectionAttempts { _ in throw ExerciseNoServer() }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let client = InstantSwiftDataClient(runtime: runtime)
    let seedTime = InstantTimestamp(milliseconds: 1_700_000_000_000)
    _ = try await runtime.applyServerTransaction(
      InstantStoreTransaction(
        id: "seed",
        operations: (0..<rowCount).flatMap { row in
          [
            ExerciseLine.insert(row: row, attributeID: ExerciseLine.idAttributeID, value: .string("line-\(row)"), at: seedTime),
            ExerciseLine.insert(row: row, attributeID: ExerciseLine.textAttributeID, value: .string("seed \(row)"), at: seedTime),
          ]
        }
      ),
      processedTransactionID: "1"
    )

    let census = InstantObservationTaskCensus()
    // A plan of its own for each, as the phone's 48 live queries are 48 plans; every one shows all 50 rows. `load`
    // starts each wrapper's automatic observation, as a view's first read does, inside the census.
    let fetches = (0..<observerCount).map { index in
      FetchAll<ExerciseLine>(ExerciseLine.query.limit(UInt(rowCount + index)))
    }
    try await InstantObservationTaskCensus.$current.withValue(census) {
      for fetch in fetches {
        try await fetch.load(using: client)
      }
    }
    try await wait("every wrapper's observation") {
      await runtime.store.activeObservationCount() == observerCount
    }
    let alive = census.aliveCount
    print(
      "OBSERVATION tasks observers=\(observerCount) alive=\(alive) perObserver="
        + String(format: "%.2f", Double(alive) / Double(observerCount))
    )
    if idleSeconds > 0 {
      print("OBSERVATION idle seconds=\(idleSeconds) pid=\(ProcessInfo.processInfo.processIdentifier)")
      fflush(stdout)
      try await Task.sleep(for: .seconds(idleSeconds))
    }

    let clock = ContinuousClock()
    var latencies: [Duration] = []
    latencies.reserveCapacity(writes * observerCount)
    for write in 0..<writes {
      let arrivals = ExerciseArrivals(count: observerCount)
      for (index, fetch) in fetches.enumerated() {
        withObservationTracking {
          _ = fetch.wrappedValue
        } onChange: {
          arrivals.record(index, at: clock.now)
        }
      }
      _ = try await runtime.transact(
        operations: [
          ExerciseLine.insert(
            row: write % rowCount,
            attributeID: ExerciseLine.textAttributeID,
            value: .string("write \(write)"),
            at: InstantTimestamp(milliseconds: seedTime.milliseconds + Int64(write) + 1)
          )
        ]
      )
      guard let publishedAt = await runtime.store.lastPublicationStartedAt else {
        throw ExerciseFailure(description: "write \(write) published nothing")
      }
      try await wait("write \(write) in every wrapper") { arrivals.isComplete }
      latencies += arrivals.instants.map { $0 - publishedAt }
    }
    let sorted = latencies.sorted()
    func percentile(_ fraction: Double) -> String {
      let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * fraction).rounded()))
      return microseconds(sorted[index])
    }
    print(
      "OBSERVATION latency observers=\(observerCount) writes=\(writes) samples=\(sorted.count) unit=us"
        + " p50=\(percentile(0.5)) p90=\(percentile(0.9)) p99=\(percentile(0.99))"
        + " max=\(microseconds(sorted.last ?? .zero))"
    )
    withExtendedLifetime(fetches) {}
  }

  static func microseconds(_ duration: Duration) -> String {
    let components = duration.components
    let microseconds = Double(components.seconds) * 1_000_000 + Double(components.attoseconds) / 1e12
    return String(format: "%.1f", microseconds)
  }

  /// Polls `condition` every millisecond for at most 5 s (the codebase's timeout rule).
  static func wait(_ description: String, _ condition: @Sendable () async -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !(await condition()) {
      guard ContinuousClock.now < deadline else {
        throw ExerciseFailure(description: "timed out after 5 s waiting for \(description)")
      }
      try await Task.sleep(for: .milliseconds(1))
    }
  }
}

/// The instant each wrapper's value changed, for one write.
// SAFETY: `lock` protects `recorded`.
private final class ExerciseArrivals: @unchecked Sendable {
  private let lock = NSLock()
  private var recorded: [ContinuousClock.Instant?]

  init(count: Int) {
    recorded = Array(repeating: nil, count: count)
  }

  func record(_ index: Int, at instant: ContinuousClock.Instant) {
    lock.withLock { recorded[index] = recorded[index] ?? instant }
  }

  var isComplete: Bool { lock.withLock { !recorded.contains(nil) } }
  var instants: [ContinuousClock.Instant] { lock.withLock { recorded.compactMap { $0 } } }
}

private struct ExerciseNoServer: Error {}

private struct ExerciseFailure: Error, CustomStringConvertible {
  var description: String
}

private struct ExerciseLine: Hashable, Codable, InstantEntityModel {
  var id: InstantID<ExerciseLine>
  var text: String

  static let instantNamespace = "exercise_lines"
  static let idAttributeID = InstantAttribute.primaryKeyID(namespace: instantNamespace)
  static let textAttributeID = "\(instantNamespace)/text"
  static let text = InstantAttributePath<ExerciseLine, String>("text")
  static let instantAttributes = [
    InstantAttribute.primaryKey(namespace: instantNamespace),
    InstantAttribute(
      id: textAttributeID,
      namespace: instantNamespace,
      name: "text",
      valueType: .string,
      isIndexed: true
    ),
  ]

  static func insert(
    row: Int,
    attributeID: String,
    value: InstantValue,
    at time: InstantTimestamp
  ) -> InstantTripleOperation {
    .insert(InstantTriple(entityID: "line-\(row)", attributeID: attributeID, value: value, txID: "exercise", txTime: time))
  }

  init(snapshot: InstantEntitySnapshot) throws {
    id = InstantID(rawValue: snapshot.id)
    guard case let .string(text) = snapshot.values["text"]?.first else {
      throw InstantError(
        code: .validationFailed,
        operation: "decode exercise line",
        namespace: Self.instantNamespace,
        path: "text",
        localID: snapshot.id,
        message: "Expected a string text value.",
        recovery: "Store a string in the text attribute before decoding this fixture."
      )
    }
    self.text = text
  }
}
