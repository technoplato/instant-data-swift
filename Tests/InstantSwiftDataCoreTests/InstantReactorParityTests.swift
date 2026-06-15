import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantReactorParityTests {
  @Test
  func upstreamReactorGetLocalIDAlwaysReturnsSameID() async throws {
    let cacheURL = try temporaryReactorParityCacheURL()
    let idFactory = SequentialLocalIDFactory()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-local-id-parity",
        persistenceURL: cacheURL,
        makeID: idFactory.makeID
      )
    )

    let ids = try await withThrowingTaskGroup(of: String.self) { group in
      for _ in 0..<1_000 {
        group.addTask {
          try await runtime.localID(named: "id")
        }
      }

      var ids: [String] = []
      for try await id in group {
        ids.append(id)
      }
      return ids
    }

    let uniqueIDs = Set(ids)
    let firstID = try #require(uniqueIDs.first)
    expectNoDifference(uniqueIDs.count, 1, reactorGetLocalIDSource)
    expectNoDifference(idFactory.count, 1, reactorGetLocalIDSource)

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "reactor-local-id-parity",
        persistenceURL: cacheURL,
        makeID: { "unexpected-relaunch-local-id" }
      )
    )

    let relaunchedID = try await relaunchedRuntime.localID(named: "id")
    let persistedIDs = try await relaunchedRuntime.localIDs()
    expectNoDifference(relaunchedID, firstID, reactorGetLocalIDSource)
    expectNoDifference(persistedIDs, [InstantLocalID(name: "id", entityID: firstID)], reactorGetLocalIDSource)
  }
}

private let reactorGetLocalIDSource =
  "upstream/instant/client/packages/core/__tests__/src/Reactor.test.ts getLocalId always returns the same id [adapted: Swift uses InstantRuntime.localID over the local SQLite cache instead of the IndexedDB-backed Reactor harness.]"

private func temporaryReactorParityCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantReactorParityTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private final class SequentialLocalIDFactory: @unchecked Sendable {
  private let lock = NSLock()
  private var nextID = 0

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return nextID
  }

  func makeID() -> String {
    lock.lock()
    defer { lock.unlock() }
    nextID += 1
    return "local-\(nextID)"
  }
}
