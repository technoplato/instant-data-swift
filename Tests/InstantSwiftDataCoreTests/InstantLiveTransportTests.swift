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
  func transactMessageEncodesUpstreamShape() throws {
    let message = try InstantLiveMessage.transact(
      [
        .addTriple(
          entity: .id("todo-1"),
          attributeID: "todos/id",
          value: .string("todo-1")
        ),
        .addTriple(
          entity: .id("todo-1"),
          attributeID: "todos/done",
          value: .bool(false)
        ),
      ],
      clientEventID: "event-transact"
    )

    let data = try JSONEncoder().encode(message)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    expectNoDifference(object["op"] as? String, "transact")
    expectNoDifference(object["client-event-id"] as? String, "event-transact")
    let txSteps = try #require(object["tx-steps"] as? [[Any]])
    expectNoDifference(txSteps.count, 2)
    expectNoDifference(txSteps[0].count, 4)
    expectNoDifference(txSteps[1].count, 4)
    expectNoDifference(txSteps[0][0] as? String, "add-triple")
    expectNoDifference(txSteps[0][1] as? String, "todo-1")
    expectNoDifference(txSteps[0][2] as? String, "todos/id")
    expectNoDifference(txSteps[0][3] as? String, "todo-1")
    expectNoDifference(txSteps[1][3] as? Bool, false)
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
  func serverEventPreservesTransactISN() throws {
    let data = Data(
      """
      {
        "op": "transact-ok",
        "client-event-id": "event-tx",
        "tx-id": 126,
        "isn": "slot:lsn"
      }
      """.utf8
    )

    guard
      case let .transactOK(transactOK) = InstantLiveServerEvent(
        message: try JSONDecoder().decode(InstantLiveMessage.self, from: data)
      )
    else {
      #expect(Bool(false), "Expected transact-ok.")
      return
    }
    expectNoDifference(transactOK.clientEventID, "event-tx")
    expectNoDifference(transactOK.transactionID, "126")
    expectNoDifference(transactOK.isn, "slot:lsn")
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

  @Test
  func liveSessionValidationCanIncludeLocalTransaction() async throws {
    let ids = InstantLiveTransportTestIDSequence(["event-init", "event-query", "event-tx"])
    let result = try await InstantSwiftDataLiveSessionValidation.run(
      appID: "live-transaction-test",
      caseID: "validation.live.transaction",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      includeTransaction: true,
      timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      makeID: { ids.next() }
    )

    expectNoDifference(result.evidence.map(\.caseID), Array(
      repeating: "validation.live.transaction",
      count: 8
    ))
    expectNoDifference(result.evidence.map(\.event), [
      "session-url",
      "send-init",
      "receive-init-ok",
      "send-add-query",
      "receive-query",
      "send-transact",
      "receive-transact-ok",
      "receive-transaction-refresh",
    ])
    expectNoDifference(result.evidence.map(\.ok), Array(repeating: true, count: 8))

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(finalDetails.sentOps, ["init", "add-query", "transact"])
    expectNoDifference(finalDetails.receivedOps, [
      "init-ok", "add-query-ok", "transact-ok", "refresh-ok",
    ])
    expectNoDifference(finalDetails.clientEventIDs, ["event-init", "event-query", "event-tx"])
    expectNoDifference(finalDetails.transactionID, "local-event-tx")
    expectNoDifference(finalDetails.transactionISN, "local-isn-event-tx")
    expectNoDifference(finalDetails.processedTransactionID, "local-event-tx")
    expectNoDifference(finalDetails.refreshComputationCount, 0)
  }

  @Test
  func liveSessionValidationObservesExternalRefreshEntityID() async throws {
    let entityID = "typescript-live-boundary-test"
    let ids = InstantLiveTransportTestIDSequence(["event-init", "event-query"])
    let session = InstantScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init"),
      .addQueryOK(clientEventID: "event-query"),
      .refreshOK(
        clientEventID: "event-query-only",
        processedTransactionID: "server-tx-query-only",
        computations: [
          .object([
            "instaql-query": .object([
              TodoExample.namespace: .object([
                "$": .object([
                  "where": .object([
                    "id": .string(entityID)
                  ])
                ])
              ])
            ]),
            "instaql-result": .array([]),
          ])
        ]
      ),
      .refreshOK(
        clientEventID: "event-external",
        processedTransactionID: "server-tx-1",
        computations: [
          .object([
            "instaql-query": .object([
              TodoExample.namespace: .object([
                "$": .object([
                  "where": .object([
                    "id": .string(entityID)
                  ])
                ])
              ])
            ]),
            "instaql-result": .array([
              .object([
                "data": .object([
                  "id": .string(entityID)
                ]),
                "child-nodes": .array([]),
              ])
            ]),
          ])
        ]
      ),
    ])

    let result = try await InstantSwiftDataLiveSessionValidation.run(
      appID: "live-observe-test",
      caseID: "validation.live.observe",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      query: .object([
        TodoExample.namespace: .object([
          "$": .object([
            "where": .object([
              "id": .string(entityID)
            ])
          ])
        ])
      ]),
      expectedExternalRefreshEntityID: entityID,
      liveTransport: session.transport,
      proofLevel: "live-websocket-observe",
      timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      makeID: { ids.next() },
      maxServerEvents: 1
    )

    expectNoDifference(result.evidence.map(\.event), [
      "session-url",
      "send-init",
      "receive-init-ok",
      "send-add-query",
      "receive-query",
      "receive-external-refresh",
    ])
    expectNoDifference(result.evidence.last?.entityID, entityID)

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(finalDetails.sentOps, ["init", "add-query"])
    expectNoDifference(
      finalDetails.receivedOps,
      ["init-ok", "add-query-ok", "refresh-ok", "refresh-ok"]
    )
    expectNoDifference(finalDetails.processedTransactionID, "server-tx-1")
    expectNoDifference(finalDetails.refreshComputationCount, 1)
    expectNoDifference(finalDetails.observedEntityID, entityID)
    expectNoDifference(finalDetails.proofLevel, "live-websocket-observe")
  }

  @Test
  func liveTransactionResolvesServerAttributeIDsFromInitAttrs() async throws {
    let ids = InstantLiveTransportTestIDSequence(["event-init", "event-query", "event-tx"])
    let session = InstantScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: [
        .serverAttr(id: "server-todos-id", namespace: "todos", name: "id"),
        .serverAttr(id: "server-todos-text", namespace: "todos", name: "text"),
        .serverAttr(id: "server-todos-is-completed", namespace: "todos", name: "isCompleted"),
        .serverAttr(id: "server-todos-prerequisite", namespace: "todos", name: "prerequisite"),
      ]),
      .addQueryOK(clientEventID: "event-query"),
      .transactOK(clientEventID: "event-tx", transactionID: "server-tx-1", isn: "server-isn-1"),
      .refreshOK(clientEventID: "event-tx", processedTransactionID: "server-tx-1"),
    ])

    let result = try await InstantSwiftDataLiveSessionValidation.run(
      appID: "live-transaction-test",
      caseID: "validation.live.transaction",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      includeTransaction: true,
      transactionSteps: InstantSwiftDataLiveSessionValidation.defaultTransactionSteps + [
        .addTriple(
          entity: .id("live-transaction-note"),
          attributeID: "todos/prerequisite",
          value: .array([
            .string("todos/id"),
            .string("seed-todo"),
          ])
        )
      ],
      resolveTransactionAttributeIDs: true,
      liveTransport: session.transport,
      proofLevel: "live-websocket-transaction",
      timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      makeID: { ids.next() }
    )

    let finalDetails = try #require(result.evidence.last?.details)
    expectNoDifference(finalDetails.transactionID, "server-tx-1")
    expectNoDifference(finalDetails.transactionISN, "server-isn-1")
    expectNoDifference(finalDetails.processedTransactionID, "server-tx-1")

    let sentMessages = await session.sentMessages()
    let transact = try #require(sentMessages.first { $0.op == "transact" })
    expectNoDifference(
      transact.fields["tx-steps"],
      .array([
        .array([
          .string("add-triple"),
          .string("live-transaction-note"),
          .string("server-todos-id"),
          .string("live-transaction-note"),
        ]),
        .array([
          .string("add-triple"),
          .string("live-transaction-note"),
          .string("server-todos-text"),
          .string("Swift live transaction"),
        ]),
        .array([
          .string("add-triple"),
          .string("live-transaction-note"),
          .string("server-todos-is-completed"),
          .bool(false),
        ]),
        .array([
          .string("add-triple"),
          .string("live-transaction-note"),
          .string("server-todos-prerequisite"),
          .array([
            .string("server-todos-id"),
            .string("seed-todo"),
          ]),
        ]),
      ])
    )
  }

  @Test
  func liveTransactionRejectsUncorrelatedRefreshOK() async throws {
    let ids = InstantLiveTransportTestIDSequence(["event-init", "event-query", "event-tx"])
    let session = InstantScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init"),
      .addQueryOK(clientEventID: "event-query"),
      .transactOK(clientEventID: "event-tx", transactionID: "server-tx-1"),
      .refreshOK(clientEventID: "event-tx", processedTransactionID: "other-tx"),
    ])

    do {
      _ = try await InstantSwiftDataLiveSessionValidation.run(
        appID: "live-transaction-test",
        caseID: "validation.live.transaction",
        websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
        includeTransaction: true,
        liveTransport: session.transport,
        timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
        makeID: { ids.next() },
        eventTimeoutMilliseconds: 1,
        maxServerEvents: 1
      )
      Issue.record("Expected live transaction validation to reject an unrelated refresh-ok.")
    } catch let failure as LiveSessionValidationFailure {
      expectNoDifference(failure.evidence.last?.event, "failed")
      expectNoDifference(
        failure.evidence.last?.details.errorMessage?.contains("processed-tx-id matching"),
        true
      )
      expectNoDifference(
        failure.evidence.last?.details.receivedOps,
        ["init-ok", "add-query-ok", "transact-ok", "refresh-ok"]
      )
    }
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

private actor InstantScriptedLiveSession {
  private var messages: [InstantLiveMessage]
  private var sent: [InstantLiveMessage] = []

  init(messages: [InstantLiveMessage]) {
    self.messages = messages
  }

  nonisolated var transport: InstantLiveTransportClient {
    InstantLiveTransportClient { _ in
      InstantLiveWebSocketSession(
        send: { message in
          await self.send(message)
        },
        receive: {
          try await self.receive()
        },
        close: {}
      )
    }
  }

  func sentMessages() -> [InstantLiveMessage] {
    sent
  }

  private func send(_ message: InstantLiveMessage) {
    sent.append(message)
  }

  private func receive() throws -> InstantLiveMessage {
    guard !messages.isEmpty else {
      throw InstantError(
        code: .networkFailed,
        operation: "script Instant live session",
        message: "No scripted live messages remain.",
        recovery: "Add another scripted message for this test."
      )
    }
    return messages.removeFirst()
  }
}

private extension InstantLiveMessage {
  static func initOK(
    clientEventID: String,
    attrs: [InstantLiveJSONValue] = []
  ) -> Self {
    Self(
      op: "init-ok",
      clientEventID: clientEventID,
      fields: [
        "attrs": .array(attrs),
        "auth": .null,
        "session-id": .string("scripted-session"),
      ]
    )
  }

  static func addQueryOK(clientEventID: String) -> Self {
    Self(
      op: "add-query-ok",
      clientEventID: clientEventID,
      fields: [
        "q": .object([TodoExample.namespace: .object([:])]),
        "result": .array([]),
      ]
    )
  }

  static func transactOK(
    clientEventID: String,
    transactionID: String,
    isn: String? = nil
  ) -> Self {
    var fields: [String: InstantLiveJSONValue] = [
      "tx-id": .string(transactionID)
    ]
    if let isn {
      fields["isn"] = .string(isn)
    }
    return Self(op: "transact-ok", clientEventID: clientEventID, fields: fields)
  }

  static func refreshOK(
    clientEventID: String,
    processedTransactionID: String,
    computations: [InstantLiveJSONValue] = []
  ) -> Self {
    Self(
      op: "refresh-ok",
      clientEventID: clientEventID,
      fields: [
        "attrs": .array([]),
        "computations": .array(computations),
        "processed-tx-id": .string(processedTransactionID),
      ]
    )
  }
}

private extension InstantLiveJSONValue {
  static func serverAttr(id: String, namespace: String, name: String) -> Self {
    .object([
      "forward-identity": .array([
        .string("identity-\(id)"),
        .string(namespace),
        .string(name),
      ]),
      "id": .string(id),
    ])
  }
}
