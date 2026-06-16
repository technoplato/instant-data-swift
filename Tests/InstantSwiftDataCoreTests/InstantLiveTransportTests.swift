import CustomDump
import Foundation
import InstantSwiftDataCore
import Testing

@Suite
struct InstantLiveTransportTests {
  @Test
  func sessionURLAppendsAppID() throws {
    let request = InstantLiveSessionRequest(
      appID: "app-123",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session"))
    )

    expectNoDifference(
      try request.sessionURL().absoluteString,
      "wss://ws.example.test/runtime/session?app_id=app-123"
    )
  }

  @Test
  func initMessageEncodesUpstreamShape() throws {
    let message = InstantLiveMessage.initMessage(
      appID: "app-123",
      refreshToken: "refresh-token",
      adminToken: "admin-token",
      clientEventID: "event-1",
      versions: ["InstantDB-Swift": "test"]
    )

    let data = try JSONEncoder().encode(message)
    let json = String(decoding: data, as: UTF8.self)
    #expect(json.contains(#""op":"init""#))
    #expect(json.contains(#""client-event-id":"event-1""#))
    #expect(json.contains(#""app-id":"app-123""#))
    #expect(json.contains(#""refresh-token":"refresh-token""#))
    #expect(json.contains(#""__admin-token":"admin-token""#))
    #expect(json.contains(#""versions":{"InstantDB-Swift":"test"}"#))

    let decoded = try JSONDecoder().decode(InstantLiveMessage.self, from: data)
    expectNoDifference(decoded.op, "init")
    expectNoDifference(decoded.clientEventID, "event-1")
    expectNoDifference(decoded.fields["app-id"], .string("app-123"))
    expectNoDifference(decoded.fields["refresh-token"], .string("refresh-token"))
  }

  @Test
  func serverEventDecodesDynamicHyphenatedMessages() throws {
    let data = Data(
      """
      {
        "op": "init-ok",
        "client-event-id": "event-1",
        "session-id": "session-1",
        "attrs": [{"id": "todos/id"}],
        "auth": null
      }
      """.utf8
    )

    let message = try JSONDecoder().decode(InstantLiveMessage.self, from: data)
    let event = InstantLiveServerEvent(message: message)

    guard case let .initOK(initOK) = event else {
      #expect(Bool(false), "Expected init-ok, got \(event.op).")
      return
    }
    expectNoDifference(initOK.clientEventID, "event-1")
    expectNoDifference(initOK.sessionID, "session-1")
    expectNoDifference(initOK.attrs.count, 1)
  }

  @Test
  func serverEventPreservesNumericProcessedTransactionIDs() throws {
    let queryData = Data(
      """
      {
        "op": "add-query-ok",
        "client-event-id": "event-query",
        "processed-tx-id": 124,
        "q": {"todos": {}},
        "result": []
      }
      """.utf8
    )

    guard
      case let .addQueryOK(queryOK) = InstantLiveServerEvent(
        message: try JSONDecoder().decode(InstantLiveMessage.self, from: queryData)
      )
    else {
      #expect(Bool(false), "Expected add-query-ok.")
      return
    }
    expectNoDifference(queryOK.processedTransactionID, "124")

    let refreshData = Data(
      """
      {
        "op": "refresh-ok",
        "processed-tx-id": 125,
        "attrs": [],
        "computations": []
      }
      """.utf8
    )

    guard
      case let .refreshOK(refreshOK) = InstantLiveServerEvent(
        message: try JSONDecoder().decode(InstantLiveMessage.self, from: refreshData)
      )
    else {
      #expect(Bool(false), "Expected refresh-ok.")
      return
    }
    expectNoDifference(refreshOK.processedTransactionID, "125")
  }

  @Test
  func liveSessionValidationUsesLocalProtocolHarness() async throws {
    let ids = InstantLiveTransportTestIDSequence(["event-init", "event-query"])
    let result = try await InstantSwiftDataLiveSessionValidation.run(
      appID: "live-session-test",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      makeID: { ids.next() }
    )

    expectNoDifference(result.appID, "live-session-test")
    expectNoDifference(
      result.websocketURL.absoluteString,
      "wss://ws.example.test/runtime/session?app_id=live-session-test"
    )
    expectNoDifference(result.evidence.map(\.event), [
      "session-url",
      "send-init",
      "receive-init-ok",
      "send-add-query",
      "receive-query",
    ])
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 5))

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(finalDetails.sentOps, ["init", "add-query"])
    expectNoDifference(finalDetails.receivedOps, ["init-ok", "add-query-ok"])
    expectNoDifference(finalDetails.clientEventIDs, ["event-init", "event-query"])
    expectNoDifference(finalDetails.sessionID, "local-session-live-session-test")
    expectNoDifference(finalDetails.attrCount, 0)
    expectNoDifference(finalDetails.queryResultCount, 0)
    expectNoDifference(finalDetails.proofLevel, "local-protocol")
    expectNoDifference(finalDetails.remoteBoundary, "pending-cross-client-sync")
  }
}

private final class InstantLiveTransportTestIDSequence: @unchecked Sendable {
  private let lock = NSLock()
  private var ids: [String]

  init(_ ids: [String]) {
    self.ids = ids
  }

  func next() -> String {
    lock.lock()
    defer { lock.unlock() }
    guard !ids.isEmpty else { return UUID().uuidString.lowercased() }
    return ids.removeFirst()
  }
}
