import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// #1493: an open query observation keeps no library task of its own.
///
/// A live observation reached its consumer through two forwarding tasks around the store's stream and three more that
/// merged the query's server error in, five tasks resumed one after another by every emission; a local one ran two, and
/// deferred values one more. The store now yields into the stream the consumer reads, the server error writes into the
/// same stream, and deferred values are read in the consumer's own pull, so the consumer's task is the only one.
@Suite(.serialized)
struct InstantObservationTaskCountTests {
  /// A todo's notes, a JSON value kept out of the hot store as Scribe's route samples are.
  static let notes = InstantAttribute(
    id: "todos/notesJSON",
    namespace: TodoExample.namespace,
    name: "notesJSON",
    valueType: .json
  )

  static func runtime(
    _ name: String,
    connectsToServer: Bool,
    defersNotes: Bool = false
  ) async throws -> InstantRuntime {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-observation-task-count-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var configuration = InstantRuntimeConfiguration(
      appID: "observation-task-count-\(name)",
      persistenceURL: directory.appendingPathComponent("instant.sqlite"),
      initialAttributes: TodoExample.attributes + [notes],
      deferredValueResidency: defersNotes
        ? InstantDeferredValueResidencyPolicy(attributeIDs: [notes.id]) : .none
    )
    // A transport the runtime never connects (automatic connection is off): the live query's registration, its
    // server-error stage and everything else a live observation builds are in place without a socket.
    if connectsToServer {
      configuration.liveTransport = .connectionAttempts { _ in throw ObservationTaskCountNoServer() }
    }
    return try await InstantRuntime.bootstrap(configuration: configuration)
  }

  /// The library tasks alive while `plan`'s observation is open on `runtime`, read after its first emission.
  static func tasksAliveWhileObserving(_ plan: InstantQueryPlan, on runtime: InstantRuntime) async throws -> Int {
    let census = InstantObservationTaskCensus()
    let stream = await InstantObservationTaskCensus.$current.withValue(census) {
      await runtime.observe(plan)
    }
    var iterator = stream.makeAsyncIterator()
    _ = try #require(await iterator.next())
    return census.aliveCount
  }

  @Test
  func anOpenLiveObservationKeepsNoLibraryTask() async throws {
    let runtime = try await Self.runtime("live", connectsToServer: true)
    let alive = try await Self.tasksAliveWhileObserving(TodoExample.query, on: runtime)
    expectNoDifference(alive, 0, "five before #1493: two forwarders and the server error's three")
  }

  @Test
  func anOpenLocalObservationKeepsNoLibraryTask() async throws {
    let runtime = try await Self.runtime("local", connectsToServer: false)
    let alive = try await Self.tasksAliveWhileObserving(TodoExample.query, on: runtime)
    expectNoDifference(alive, 0, "two before #1493: the forwarders around the store's stream")
  }

  @Test
  func anOpenLiveObservationOfDeferredValuesKeepsNoLibraryTask() async throws {
    let runtime = try await Self.runtime("deferred", connectsToServer: true, defersNotes: true)
    let plan = InstantQueryPlan(
      id: "todos.deferred-notes",
      namespace: TodoExample.namespace,
      selectedFields: ["text", Self.notes.name]
    )
    let alive = try await Self.tasksAliveWhileObserving(plan, on: runtime)
    expectNoDifference(alive, 0, "six before #1493: the live chain's five and the deferred values' reader")
  }
}

private struct ObservationTaskCountNoServer: Error {}
