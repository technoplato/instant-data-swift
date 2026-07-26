import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantStartupTraceTests {
  @Test func runtimeBootstrapReportsOrderedLocalStartupPhases() async throws {
    let events = StartupTraceRecorder()
    let trace = InstantStartupTrace(id: "startup-test") { event in
      events.record(event)
    }
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-startup-trace-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    var configuration = InstantRuntimeConfiguration(
      appID: "startup-trace-test",
      persistenceURL: persistenceURL
    )
    configuration.startupTrace = trace

    _ = try await InstantRuntime.bootstrap(configuration: configuration)

    expectNoDifference(
      events.values.map { "\($0.kind.rawValue):\($0.phase)" },
      [
        "started:runtime.bootstrap",
        "completed:runtime.validation",
        "started:sqlite.open",
        "completed:sqlite.open",
        "started:sqlite.schema",
        "completed:sqlite.schema",
        "started:sqlite.state-load",
        "completed:sqlite.state-load",
        "completed:runtime.store-materialization",
        "completed:runtime.attribute-store-merge",
        "completed:runtime.attribute-merge",
        "completed:runtime.services-scheduled",
        "completed:runtime.bootstrap",
      ]
    )
    let completedEvents = events.values.filter { $0.kind == .completed }
    #expect(completedEvents.allSatisfy { ($0.durationMilliseconds ?? -1) >= 0 })
  }

  @Test func queryObservationSeparatesStoreWaitFromLocalRegistration() async throws {
    let events = StartupTraceRecorder()
    let trace = InstantStartupTrace(id: "query-trace-test") { event in
      events.record(event)
    }
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-query-trace-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    var configuration = InstantRuntimeConfiguration(
      appID: "query-trace-test",
      persistenceURL: persistenceURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.startupTrace = trace
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    _ = await runtime.observe(TodoExample.query)

    expectNoDifference(
      events.values
        .filter { $0.phase.hasPrefix("query.") }
        .map { "\($0.kind.rawValue):\($0.phase)" },
      [
        "started:query.observe",
        "completed:query.schema-snapshot",
        "completed:query.local-registration",
        "completed:query.local-observer",
      ]
    )
  }

  @Test func persistenceOnlyReportsItsFirstStateLoadAsStartupWork() async throws {
    let events = StartupTraceRecorder()
    let trace = InstantStartupTrace(id: "state-load-trace-test") { event in
      events.record(event)
    }
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-state-load-trace-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }
    let persistence = try SQLitePersistenceStore(
      fileURL: persistenceURL,
      startupTrace: trace
    )
    try await persistence.bootstrap()

    _ = try await persistence.loadState()
    _ = try await persistence.loadState()

    expectNoDifference(
      events.values
        .filter { $0.phase == "sqlite.state-load" }
        .map(\.kind),
      [.started, .completed]
    )
  }

  @Test func startupCanReadAttributesAndSkipANoOpMergeWithoutMaterializingTriples() async {
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: TodoExample.attributes)
    )

    let attributes = await store.attributeSnapshot()
    expectNoDifference(attributes, TodoExample.attributes.sorted { $0.id < $1.id })
    #expect(await store.mergeAttributesIfChanged(TodoExample.attributes) == nil)
  }
}

private final class StartupTraceRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [InstantStartupTraceEvent] = []

  var values: [InstantStartupTraceEvent] {
    lock.withLock { storage }
  }

  func record(_ event: InstantStartupTraceEvent) {
    lock.withLock { storage.append(event) }
  }
}
