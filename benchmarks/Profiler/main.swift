import Foundation
import InstantSwiftDataCore

@main
struct InstantColdStartProfiler {
  static func main() async throws {
    guard CommandLine.arguments.count == 2 else {
      FileHandle.standardError.write(
        Data("Usage: InstantColdStartProfiler <disposable-sqlite-copy>\n".utf8)
      )
      exit(64)
    }

    let recorder = StartupEventRecorder()
    var configuration = InstantRuntimeConfiguration(
      appID: "cold-start-profiler",
      persistenceURL: URL(fileURLWithPath: CommandLine.arguments[1])
    )
    configuration.startupTrace = InstantStartupTrace(id: "cold-start-profiler") { event in
      recorder.record(event)
    }

    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let state = try await runtime.persistence.loadState()
    print(
      "cold-start-profiler attributes=\(state.snapshot.store.attributes.count) "
        + "triples=\(state.snapshot.store.triples.count) "
        + "outbox=\(state.snapshot.outbox.count)"
    )
    for event in recorder.events where event.kind == .completed {
      print(
        "cold-start-profiler phase=\(event.phase) "
          + "durationMilliseconds=\(event.durationMilliseconds ?? -1) "
          + "elapsedMilliseconds=\(event.elapsedMilliseconds)"
      )
    }
    withExtendedLifetime(runtime) {}
  }
}

private final class StartupEventRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [InstantStartupTraceEvent] = []

  var events: [InstantStartupTraceEvent] {
    lock.withLock { storage }
  }

  func record(_ event: InstantStartupTraceEvent) {
    lock.withLock { storage.append(event) }
  }
}
