import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

/// ADR 0015 / issue #155 P1 — Instant client id for activity ADT (this vs other).
///
/// Upstream: `Reactor.getLocalId` in
/// `upstream/instant/client/packages/core/src/Reactor.js` — stable local id
/// unique to this device and app (not websocket `session-id`).
@Suite
struct InstantClientIDTests {
  @Test
  func clientIDUsesReservedLocalIDNameAndPersistsAcrossRelaunch() async throws {
    let cacheURL = try temporaryClientIDCacheURL()
    defer { try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent()) }

    let firstRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "client-id-p1",
        persistenceURL: cacheURL,
        makeID: { "stable-client-id-1" }
      )
    )

    let first = try await firstRuntime.clientID()
    expectNoDifference(first, "stable-client-id-1")

    // Same process: stable.
    let again = try await firstRuntime.clientID()
    expectNoDifference(again, first)

    // Named localID with the reserved name is the same value (not a second id type).
    let byName = try await firstRuntime.localID(named: InstantClientID.name)
    expectNoDifference(byName, first)

    let persisted = try await firstRuntime.localIDs()
    expectNoDifference(
      persisted,
      [InstantLocalID(name: InstantClientID.name, entityID: first)]
    )

    // Relaunch: survives (offline-safe; no network involved).
    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "client-id-p1",
        persistenceURL: cacheURL,
        makeID: { "should-not-allocate" }
      )
    )
    let relaunchedID = try await relaunched.clientID()
    expectNoDifference(relaunchedID, first)
  }

  @Test
  func distinctStoresGetDistinctClientIDs() async throws {
    let firstURL = try temporaryClientIDCacheURL()
    let secondURL = try temporaryClientIDCacheURL()
    defer {
      try? FileManager.default.removeItem(at: firstURL.deletingLastPathComponent())
      try? FileManager.default.removeItem(at: secondURL.deletingLastPathComponent())
    }

    let phone = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "client-id-p1",
        persistenceURL: firstURL,
        makeID: { "phone-client" }
      )
    )
    let mac = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "client-id-p1",
        persistenceURL: secondURL,
        makeID: { "mac-client" }
      )
    )

    let phoneID = try await phone.clientID()
    let macID = try await mac.clientID()
    expectNoDifference(phoneID, "phone-client")
    expectNoDifference(macID, "mac-client")

    // Activity on Mac looks like "other device" on the phone.
    expectNoDifference(
      InstantClientID.isThisClient(activityClientID: macID, localClientID: phoneID),
      false
    )
    expectNoDifference(
      InstantClientID.isThisClient(activityClientID: phoneID, localClientID: phoneID),
      true
    )
  }

  @Test
  func isThisClientComparesActivityClientIDToLocal() {
    expectNoDifference(
      InstantClientID.isThisClient(
        activityClientID: "device-a",
        localClientID: "device-a"
      ),
      true
    )
    expectNoDifference(
      InstantClientID.isThisClient(
        activityClientID: "device-b",
        localClientID: "device-a"
      ),
      false
    )
  }
}

private func temporaryClientIDCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantClientIDTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}
