import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

@Suite(.serialized)
struct InstantCookieSyncParityTests {
  @Test
  func upstreamCookieSyncSyncsUserCookieOnStartupWhenLastSyncIsAtLeastADayOld()
    async throws
  {
    let appID = "cookie-sync-old-\(UUID().uuidString)"
    let cacheURL = try temporaryCookieSyncCacheURL()
    let recorder = CookieSyncRecorder()
    let client = await recorder.client()
    let startTime = InstantTimestamp(milliseconds: 1_767_225_600_000)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: cookieSyncConfiguration(
        appID: appID,
        cacheURL: cacheURL,
        now: startTime,
        client: client
      )
    )
    var requests = await recorder.requests()
    expectNoDifference(requests.map(\.type), ["sync-user"], cookieSyncOldSource)
    expectNoDifference(requests.map(\.appID), [appID], cookieSyncOldSource)
    expectNoDifference(requests.map(\.firstPartyURL), [cookieSyncFirstPartyURL], cookieSyncOldSource)
    expectNoDifference(requests.map(\.user), [nil], cookieSyncOldSource)

    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-id")
    requests = await recorder.requests()
    expectNoDifference(requests.count, 2, cookieSyncOldSource)
    expectNoDifference(requests.last?.user?.id, "user-id", cookieSyncOldSource)
    expectNoDifference(requests.last?.user?.refreshToken, "refresh-token", cookieSyncOldSource)
    expectNoDifference(requests.last?.user?.isGuest, false, cookieSyncOldSource)
    await recorder.reset()

    let oneDayLater = InstantTimestamp(
      milliseconds: startTime.milliseconds + InstantRuntime.cookieSyncIntervalMilliseconds
    )
    _ = try await InstantRuntime.bootstrap(
      configuration: cookieSyncConfiguration(
        appID: appID,
        cacheURL: cacheURL,
        now: oneDayLater,
        client: client
      )
    )

    requests = await recorder.requests()
    expectNoDifference(requests.count, 1, cookieSyncOldSource)
    expectNoDifference(requests.first?.type, "sync-user", cookieSyncOldSource)
    expectNoDifference(requests.first?.appID, appID, cookieSyncOldSource)
    expectNoDifference(requests.first?.user?.id, "user-id", cookieSyncOldSource)
    expectNoDifference(requests.first?.user?.refreshToken, "refresh-token", cookieSyncOldSource)
    expectNoDifference(requests.first?.user?.isGuest, false, cookieSyncOldSource)
  }

  @Test
  func upstreamCookieSyncDoesNotSyncUserCookieOnStartupWhenLastSyncIsRecent()
    async throws
  {
    let appID = "cookie-sync-recent-\(UUID().uuidString)"
    let cacheURL = try temporaryCookieSyncCacheURL()
    let recorder = CookieSyncRecorder()
    let client = await recorder.client()
    let startTime = InstantTimestamp(milliseconds: 1_767_225_600_000)

    let runtime = try await InstantRuntime.bootstrap(
      configuration: cookieSyncConfiguration(
        appID: appID,
        cacheURL: cacheURL,
        now: startTime,
        client: client
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-id")
    var requests = await recorder.requests()
    expectNoDifference(requests.count, 2, cookieSyncRecentSource)
    expectNoDifference(requests.last?.user?.id, "user-id", cookieSyncRecentSource)
    await recorder.reset()

    let almostOneDayLater = InstantTimestamp(
      milliseconds: startTime.milliseconds + InstantRuntime.cookieSyncIntervalMilliseconds - 1
    )
    _ = try await InstantRuntime.bootstrap(
      configuration: cookieSyncConfiguration(
        appID: appID,
        cacheURL: cacheURL,
        now: almostOneDayLater,
        client: client
      )
    )

    requests = await recorder.requests()
    expectNoDifference(requests, [], cookieSyncRecentSource)
  }

  @Test
  func cookieSyncRequestEncodesRouteHandlerWireShape() throws {
    let request = InstantUserCookieSyncRequest(
      appID: "app-id",
      firstPartyURL: cookieSyncFirstPartyURL,
      user: InstantUserCookieSyncUser(
        id: "user-id",
        refreshToken: "refresh-token",
        isGuest: false
      ),
      syncedAt: InstantTimestamp(milliseconds: 1_767_225_600_000)
    )

    let data = try JSONEncoder().encode(request)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    expectNoDifference(Set(object.keys), Set(["type", "appId", "user"]), cookieSyncWireSource)
    expectNoDifference(object["type"] as? String, "sync-user", cookieSyncWireSource)
    expectNoDifference(object["appId"] as? String, "app-id", cookieSyncWireSource)

    let user = try #require(object["user"] as? [String: Any])
    expectNoDifference(Set(user.keys), Set(["id", "refresh_token", "isGuest"]), cookieSyncWireSource)
    expectNoDifference(user["id"] as? String, "user-id", cookieSyncWireSource)
    expectNoDifference(user["refresh_token"] as? String, "refresh-token", cookieSyncWireSource)
    expectNoDifference(user["isGuest"] as? Bool, false, cookieSyncWireSource)

    let nilUserRequest = InstantUserCookieSyncRequest(
      appID: "app-id",
      firstPartyURL: cookieSyncFirstPartyURL,
      user: nil,
      syncedAt: InstantTimestamp(milliseconds: 1_767_225_600_000)
    )
    let nilUserData = try JSONEncoder().encode(nilUserRequest)
    let nilUserObject = try #require(
      JSONSerialization.jsonObject(with: nilUserData) as? [String: Any]
    )
    expectNoDifference(Set(nilUserObject.keys), Set(["type", "appId", "user"]), cookieSyncWireSource)
    expectNoDifference(nilUserObject["user"] is NSNull, true, cookieSyncWireSource)
  }

  @Test
  func cookieSyncLastSyncedMetadataIsScopedPerAppID() async throws {
    let cacheURL = try temporaryCookieSyncCacheURL()
    let recorder = CookieSyncRecorder()
    let client = await recorder.client()
    let startTime = InstantTimestamp(milliseconds: 1_767_225_600_000)

    _ = try await InstantRuntime.bootstrap(
      configuration: cookieSyncConfiguration(
        appID: "cookie-sync-app-a",
        cacheURL: cacheURL,
        now: startTime,
        client: client
      )
    )
    var requests = await recorder.requests()
    expectNoDifference(requests.map(\.appID), ["cookie-sync-app-a"], cookieSyncStorageSource)
    await recorder.reset()

    _ = try await InstantRuntime.bootstrap(
      configuration: cookieSyncConfiguration(
        appID: "cookie-sync-app-b",
        cacheURL: cacheURL,
        now: InstantTimestamp(milliseconds: startTime.milliseconds + 1),
        client: client
      )
    )

    requests = await recorder.requests()
    expectNoDifference(requests.map(\.appID), ["cookie-sync-app-b"], cookieSyncStorageSource)
    expectNoDifference(requests.map(\.user), [nil], cookieSyncStorageSource)
  }
}

private actor CookieSyncRecorder {
  private var values: [InstantUserCookieSyncRequest] = []

  func client() -> InstantUserCookieSyncClient {
    InstantUserCookieSyncClient { request in
      await self.record(request)
    }
  }

  func requests() -> [InstantUserCookieSyncRequest] {
    values
  }

  func reset() {
    values.removeAll()
  }

  private func record(_ request: InstantUserCookieSyncRequest) {
    values.append(request)
  }
}

private let cookieSyncFirstPartyURL = URL(string: "https://example.com")!

private func cookieSyncConfiguration(
  appID: String,
  cacheURL: URL,
  now: InstantTimestamp,
  client: InstantUserCookieSyncClient
) -> InstantRuntimeConfiguration {
  InstantRuntimeConfiguration(
    appID: appID,
    apiURI: InstantRuntimeConfiguration.defaultAPIURI,
    websocketURI: InstantRuntimeConfiguration.defaultWebSocketURI,
    firstPartyURL: cookieSyncFirstPartyURL,
    persistenceURL: cacheURL,
    initialAttributes: [.primaryKey(namespace: "animal")],
    now: { now },
    makeID: { UUID().uuidString.lowercased() },
    userCookieSyncClient: client
  )
}

private func temporaryCookieSyncCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantCookieSyncParityTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private let cookieSyncOldSource =
  "upstream/instant/client/packages/core/__tests__/src/cookieSync.e2e.test.ts syncs user cookie on startup when last sync is at least a day old [adapted: Swift uses a live/injectable user-cookie sync client and app-scoped SQLite metadata instead of MSW and IndexedDB.]"

private let cookieSyncRecentSource =
  "upstream/instant/client/packages/core/__tests__/src/cookieSync.e2e.test.ts does not sync user cookie on startup when last sync is recent [adapted: Swift uses a live/injectable user-cookie sync client and app-scoped SQLite metadata instead of MSW and IndexedDB.]"

private let cookieSyncWireSource =
  "upstream/instant/client/packages/core/src/routeHandlerProtocol.ts sync-user body [adapted: Swift Encodable request uses the same appId and refresh_token wire keys.]"

private let cookieSyncStorageSource =
  "upstream/instant/client/packages/core/src/Reactor.js Storage(appId, 'kv') [adapted: Swift scopes the lastSyncedUserCookie SQLite metadata key by app id.]"
