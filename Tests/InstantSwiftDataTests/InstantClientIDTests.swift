import CustomDump
import Dependencies
import Foundation
import InstantSwiftData
import Testing

/// ADR 0015 / issue #155 P1 — public InstantSwiftDataClient.clientID().
@Suite
struct InstantClientIDClientTests {
  @Test
  func clientIDExposesStableLocalClientIdentity() async throws {
    let persistenceURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("instant-client-id-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: persistenceURL) }

    try await withDependencies {
      try await $0.bootstrapInstantSwiftData(
        appID: "client-id-client-\(UUID().uuidString)",
        persistenceURL: persistenceURL,
        context: .test
      )
    } operation: {
      @Dependency(\.defaultInstantSwiftData) var client

      let first = try await client.clientID()
      let second = try await client.clientID()
      expectNoDifference(first.isEmpty, false)
      expectNoDifference(first, second)
      let byName = try await client.localID(named: InstantClientID.name)
      expectNoDifference(byName, first)

      // Product activity ADT comparison shape (Scribe list / open recording).
      enum RecordingActivity: Equatable {
        case active(clientId: String)
        case playback(clientId: String)
      }

      let activityOnThisDevice = RecordingActivity.active(clientId: first)
      let activityOnOtherDevice = RecordingActivity.active(clientId: "other-device-client")

      func isThisDevice(_ activity: RecordingActivity, local: String) -> Bool {
        switch activity {
        case .active(let clientId), .playback(let clientId):
          InstantClientID.isThisClient(
            activityClientID: clientId,
            localClientID: local
          )
        }
      }

      expectNoDifference(isThisDevice(activityOnThisDevice, local: first), true)
      expectNoDifference(isThisDevice(activityOnOtherDevice, local: first), false)
    }
  }

  @Test
  func clientIDForwardsThroughInjectedLocalIDOperation() async throws {
    let client = InstantSwiftDataClient(
      transact: { transaction in
        InstantStoreMutationResult(
          transactionID: transaction.id,
          changedEntityIDs: [],
          tripleCount: transaction.operations.count,
          emissions: []
        )
      },
      query: { _ in [] },
      observe: { _ in AsyncStream { $0.finish() } },
      pendingMutations: { [] },
      localID: { name in
        "injected-\(name)"
      }
    )

    let id = try await client.clientID()
    expectNoDifference(id, "injected-\(InstantClientID.name)")
  }
}
