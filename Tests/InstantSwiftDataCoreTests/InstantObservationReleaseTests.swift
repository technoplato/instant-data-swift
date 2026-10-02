import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #394: an observation ends when its consumer stops iterating.
///
/// `observe(_:)` returns an `AsyncStream` fed by a forwarding task that holds the stream's continuation, so a consumer
/// that returned out of `for await` left the stream alive: its `onTermination` never ran, and the store observer and
/// the live query registration stayed until the runtime closed. On Michael's Mac the store's observers grew from 151 to
/// 405 in 45 minutes, one per media-retry scan that read a first emission and returned, and each leaked observer was
/// evaluated again on every store mutation. Upstream returns an unsubscribe function from `subscribeQuery`; in Swift a
/// consumer ends an observation by dropping its stream or cancelling its task.
@Suite(.serialized)
struct InstantObservationReleaseTests {
  static func runtime(_ name: String) async throws -> InstantRuntime {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-observation-release-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "observation-release-\(name)",
        persistenceURL: directory.appendingPathComponent("instant.sqlite"),
        initialAttributes: TodoExample.attributes
      )
    )
  }

  static func waitForObservationCount(_ count: Int, in runtime: InstantRuntime) async throws -> Int {
    let deadline = ContinuousClock.now + .seconds(5)
    while true {
      let current = await runtime.store.activeObservationCount()
      if current == count || ContinuousClock.now >= deadline { return current }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test
  func anObservationEndsWhenItsConsumerReturnsOutOfItsLoop() async throws {
    let runtime = try await Self.runtime("return")
    let baseline = await runtime.store.activeObservationCount()
    for _ in 0..<3 {
      let stream = await runtime.observe(TodoExample.query)
      for await _ in stream { break }
    }
    let remaining = try await Self.waitForObservationCount(baseline, in: runtime)
    expectNoDifference(remaining, baseline, "every store observer released")
  }

  @Test
  func anObservationWhoseConsumerStillHoldsTheStreamStaysOpen() async throws {
    let runtime = try await Self.runtime("held")
    let baseline = await runtime.store.activeObservationCount()
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    _ = await iterator.next()
    try await Task.sleep(for: .milliseconds(200))
    let open = await runtime.store.activeObservationCount()
    expectNoDifference(open, baseline + 1, "the observation stays while its consumer holds it")
    // A write still reaches it.
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_394_000)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-observation-release",
        operations: TodoExample.createOperations(
          id: "todo-observation-release",
          text: "still observed",
          createdAt: createdAt,
          transactionID: "tx-observation-release"
        )
      ),
      createdAt: createdAt
    )
    let next = await iterator.next()
    expectNoDifference(try TodoExample.decode(next?.values ?? []).map(\.text), ["still observed"])
  }

  @Test
  func cancellingTheConsumingTaskStillEndsTheObservation() async throws {
    let runtime = try await Self.runtime("cancel")
    let baseline = await runtime.store.activeObservationCount()
    let consumer = Task {
      let stream = await runtime.observe(TodoExample.query)
      for await _ in stream {}
    }
    let opened = try await Self.waitForObservationCount(baseline + 1, in: runtime)
    expectNoDifference(opened, baseline + 1)
    consumer.cancel()
    await consumer.value
    let remaining = try await Self.waitForObservationCount(baseline, in: runtime)
    expectNoDifference(remaining, baseline)
  }
}
