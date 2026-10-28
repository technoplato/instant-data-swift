import CustomDump
import Foundation
import Testing
@testable import InstantSwiftDataCore

/// The live session over HTTP (#1315): upstream `client/packages/core/src/Connection.ts` `SSEConnection`, which
/// `Reactor.js` `createTransport` opens at `${apiURI}/runtime/sse?app_id=` and posts to at the same URL.
struct InstantLiveEventStreamTests {
  @Test
  func theEventStreamLivesAtTheSessionHostOverHTTP() throws {
    expectNoDifference(
      try InstantLiveSessionRequest(appID: "app-1").eventStreamURL().absoluteString,
      "https://api.instantdb.com/runtime/sse?app_id=app-1"
    )
    expectNoDifference(
      try InstantLiveSessionRequest(
        appID: "app-2",
        websocketURI: URL(string: "ws://localhost:8888/runtime/session")!
      ).eventStreamURL().absoluteString,
      "http://localhost:8888/runtime/sse?app_id=app-2"
    )
  }

  @Test
  func theStreamRequestAsksForEventsAndKeepsTheAttemptsNetworkAccess() throws {
    let request = try InstantLiveSessionRequest(appID: "app-1", allowsExpensiveNetworkAccess: false)
      .eventStreamRequest()
    expectNoDifference(request.httpMethod, "GET")
    expectNoDifference(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
    expectNoDifference(request.allowsExpensiveNetworkAccess, false)
  }

  /// The server's wire, measured 2026-10-28 on api.instantdb.com: `data:{"op":"sse-init",...}`, a blank line, then a
  /// `:` comment every 15 s while idle.
  @Test
  func theParserYieldsEachEventsDataAndSkipsComments() {
    var parser = InstantLiveEventStreamParser()
    let lines = [
      #"data:{"op":"sse-init"}"#, "",
      ":", "",
      "data: {\"op\":\"a\",", "data:\"x\":1}", "",
      "event:message", #"data:{"op":"b"}"#, "",
    ]
    expectNoDifference(
      lines.compactMap { parser.consume(line: $0) },
      [#"{"op":"sse-init"}"#, "{\"op\":\"a\",\n\"x\":1}", #"{"op":"b"}"#]
    )
  }

  @Test
  func anEventMayCarryOneMessageOrAnArrayOfThem() throws {
    expectNoDifference(
      try InstantLiveEventStreamPayload.messages(fromData: #"{"op":"init-ok","client-event-id":"e1"}"#).map(\.op),
      ["init-ok"]
    )
    expectNoDifference(
      try InstantLiveEventStreamPayload.messages(fromData: #"[{"op":"a"},{"op":"b","x":1}]"#).map(\.op),
      ["a", "b"]
    )
  }

  @Test
  func aPostCarriesTheStreamsTokensAndTheMessages() throws {
    let start = try #require(
      InstantLiveEventStreamStart(
        InstantLiveMessage(
          op: "sse-init",
          fields: ["machine-id": .string("m"), "session-id": .string("s"), "sse-token": .string("t")]
        )
      )
    )
    let body = try start.postBody(messages: [InstantLiveMessage(op: "add-query", clientEventID: "e1")])
    let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    expectNoDifference(object["machine_id"] as? String, "m")
    expectNoDifference(object["session_id"] as? String, "s")
    expectNoDifference(object["sse_token"] as? String, "t")
    let messages = try #require(object["messages"] as? [[String: Any]])
    expectNoDifference(messages.map { $0["op"] as? String }, ["add-query"])
    expectNoDifference(messages.map { $0["client-event-id"] as? String }, ["e1"])
  }

  @Test
  func theFirstEventMustBeTheStreamsStart() {
    #expect(InstantLiveEventStreamStart(InstantLiveMessage(op: "init-ok")) == nil)
    #expect(InstantLiveEventStreamStart(InstantLiveMessage(op: "sse-init", fields: ["machine-id": .string("m")])) == nil)
  }

  /// watchOS blocks `URLSessionWebSocketTask` outside an audio stream or a call (TN3135), so the Watch's live session
  /// is the event stream; every other platform keeps the WebSocket.
  @Test
  func theWatchUsesTheEventStream() {
    #if os(watchOS)
      #expect(InstantLiveTransportClient.liveKind == .eventStream)
    #else
      #expect(InstantLiveTransportClient.liveKind == .webSocket)
    #endif
  }

  /// Against a real server, opt-in like `InstantURLSessionKeepaliveLiveTests`: `init` answers over the stream, and
  /// the stream outlives a 35 s quiet stretch (the server's 15 s comments keep it under the 20 s idle bound), after
  /// which a query is still answered.
  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment["INSTANT_KEEPALIVE_PROBE_APP_ID"] != nil,
      "Set INSTANT_KEEPALIVE_PROBE_APP_ID to a throwaway Instant app to run the live event-stream probe."
    ),
    .timeLimit(.minutes(1))
  )
  func aRealServerAnswersOverTheEventStreamAndKeepsItOpenWhenQuiet() async throws {
    let appID = try #require(ProcessInfo.processInfo.environment["INSTANT_KEEPALIVE_PROBE_APP_ID"])
    let session = try await InstantLiveTransportClient.liveEventStream.connectSession(
      InstantLiveSessionRequest(appID: appID),
      operation: "probe the Instant event stream"
    )
    defer { session.abort() }
    try await session.send(InstantLiveSessionRequest(appID: appID).initMessage(clientEventID: "probe-init"))
    let initAnswer = try await session.receive()
    expectNoDifference(initAnswer.op, "init-ok")
    try await Task.sleep(for: .seconds(35))
    try await session.send(
      InstantLiveMessage(
        op: "add-query",
        clientEventID: "probe-query",
        fields: ["q": .object(["probeEntities": .object(["$": .object(["limit": .number(1)])])])]
      )
    )
    var op = try await session.receive().op
    while op == "refresh-ok" { op = try await session.receive().op }
    #expect(["add-query-ok", "add-query-exists"].contains(op))
  }
}
