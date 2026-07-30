import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite
struct InstantSyncRouteSeamTests {
  @Test
  func runtimeRejectsDesertRouteWithoutLiveTransportBeforeOpeningPersistence() async throws {
    let persistenceURL = try temporaryCacheURL("missing-transport")
    defer { try? FileManager.default.removeItem(at: persistenceURL.deletingLastPathComponent()) }
    do {
      _ = try await InstantRuntime.bootstrap(
        configuration: InstantRuntimeConfiguration(
          appID: "desert-missing-transport",
          persistenceURL: persistenceURL,
          syncRoute: InstantSyncRouteDescriptor(
            route: .desert,
            adapter: "network-framework",
            transport: .networkFramework
          )
        )
      )
      #expect(Bool(false), "Expected desert bootstrap to require a live transport.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "bootstrap sync route configuration")
      expectNoDifference(error.path, "liveTransport")
      #expect(error.message.contains("desert"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    #expect(FileManager.default.fileExists(atPath: persistenceURL.path) == false)
  }

  @Test
  func runtimeRejectsLiveTransportWithLocalCacheRoute() async throws {
    let persistenceURL = try temporaryCacheURL("local-route-live-transport")
    defer { try? FileManager.default.removeItem(at: persistenceURL.deletingLastPathComponent()) }
    do {
      _ = try await InstantRuntime.bootstrap(
        configuration: InstantRuntimeConfiguration(
          appID: "desert-local-route-live-transport",
          persistenceURL: persistenceURL,
          liveTransport: .local,
          syncRoute: .localCache
        )
      )
      #expect(Bool(false), "Expected local-cache bootstrap to reject a live transport.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .validationFailed)
      expectNoDifference(error.operation, "bootstrap sync route configuration")
      expectNoDifference(error.path, "liveTransport")
      #expect(error.message.contains("local-cache"))
    } catch {
      #expect(Bool(false), "Unexpected error: \(error)")
    }
    #expect(FileManager.default.fileExists(atPath: persistenceURL.path) == false)
  }

  @Test
  func connectionStatusDecodesLegacyPayloadWithoutSyncRoute() throws {
    let cloudData = Data(
      #"{"appID":"legacy-status","apiURI":"https://api.instantdb.com","websocketURI":"wss://api.instantdb.com/runtime/session","transport":"websocket","state":"opened","isAuthenticated":false,"userID":null,"pendingMutationCount":0,"processedTransactionID":null,"lastErrorMessage":null}"#
        .utf8
    )
    let desertData = Data(
      #"{"appID":"legacy-desert-status","apiURI":"https://api.instantdb.com","websocketURI":"wss://api.instantdb.com/runtime/session","transport":"network-framework","state":"opened","isAuthenticated":false,"userID":null,"pendingMutationCount":0,"processedTransactionID":null,"lastErrorMessage":null}"#
        .utf8
    )

    let cloudStatus = try JSONDecoder().decode(InstantConnectionStatus.self, from: cloudData)
    let desertStatus = try JSONDecoder().decode(InstantConnectionStatus.self, from: desertData)

    expectNoDifference(cloudStatus.transport, .webSocket)
    expectNoDifference(
      cloudStatus.syncRoute,
      InstantSyncRouteDescriptor(
        route: .cloud,
        adapter: "websocket",
        transport: .webSocket
      )
    )
    expectNoDifference(desertStatus.transport, .networkFramework)
    expectNoDifference(
      desertStatus.syncRoute,
      InstantSyncRouteDescriptor(
        route: .desert,
        adapter: "network-framework",
        transport: .networkFramework
      )
    )
  }

  private func temporaryCacheURL(_ name: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("InstantSyncRouteSeamTests-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("state.sqlite")
  }
}
