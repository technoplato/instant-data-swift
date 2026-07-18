import Foundation
@testable import InstantSwiftDataCore

actor LiveReactorParitySession {
  private var messages: [InstantLiveMessage]
  private var sent: [InstantLiveMessage] = []
  private var receiveContinuation: CheckedContinuation<InstantLiveMessage, Error>?
  private var isClosed = false

  init(messages: [InstantLiveMessage]) {
    self.messages = messages
  }

  nonisolated var transport: InstantLiveTransportClient {
    InstantLiveTransportClient { _ in
      InstantLiveWebSocketSession(
        send: { message in await self.send(message) },
        receive: { try await self.receive() },
        close: { await self.close() }
      )
    }
  }

  func sentMessages() -> [InstantLiveMessage] {
    sent
  }

  private func send(_ message: InstantLiveMessage) {
    sent.append(message)
  }

  private func receive() async throws -> InstantLiveMessage {
    if !messages.isEmpty {
      return messages.removeFirst()
    }
    if isClosed {
      throw CancellationError()
    }
    return try await withCheckedThrowingContinuation { continuation in
      receiveContinuation = continuation
    }
  }

  private func close() {
    isClosed = true
    receiveContinuation?.resume(throwing: CancellationError())
    receiveContinuation = nil
  }
}

let liveReactorTodoServerAttrs: [InstantLiveJSONValue] = [
  liveReactorServerAttr(id: "server-todos-id", name: "id"),
  liveReactorServerAttr(id: "server-todos-text", name: "text"),
  liveReactorServerAttr(id: "server-todos-is-completed", name: "isCompleted"),
  liveReactorServerAttr(id: "server-todos-created-at", name: "createdAt"),
]

func liveReactorInitOK(attrs: [InstantLiveJSONValue]) -> InstantLiveMessage {
  InstantLiveMessage(
    op: "init-ok",
    clientEventID: "event-init",
    fields: [
      "attrs": .array(attrs),
      "auth": .null,
      "session-id": .string("reactor-parity-session"),
    ]
  )
}

func liveReactorAddQueryOK(
  query: InstantLiveJSONValue,
  processedTransactionID: String,
  result: [InstantLiveJSONValue]
) -> InstantLiveMessage {
  InstantLiveMessage(
    op: "add-query-ok",
    clientEventID: "event-query",
    fields: [
      "q": query,
      "processed-tx-id": .string(processedTransactionID),
      "result": .array(result),
    ]
  )
}

func liveReactorTodoComputation(
  query: InstantLiveJSONValue,
  id: String,
  text: String,
  createdAt: InstantTimestamp,
  processedTransactionID: String
) -> InstantLiveJSONValue {
  .object([
    "instaql-query": query,
    "instaql-result": .array(
      liveReactorTodoQueryResult(id: id, text: text, createdAt: createdAt)
    ),
    "processed-tx-id": .string(processedTransactionID),
  ])
}

func liveReactorTodoQueryResult(
  id: String,
  text: String,
  createdAt: InstantTimestamp
) -> [InstantLiveJSONValue] {
  [
    .object([
      "data": .object([
        "datalog-result": .object([
          "join-rows": .array([
            .array([
              liveReactorJoinRow(id, "server-todos-id", .string(id), createdAt),
              liveReactorJoinRow(id, "server-todos-text", .string(text), createdAt),
              liveReactorJoinRow(id, "server-todos-is-completed", .bool(false), createdAt),
              liveReactorJoinRow(
                id,
                "server-todos-created-at",
                .number(Double(createdAt.milliseconds)),
                createdAt
              ),
            ])
          ])
        ])
      ]),
      "child-nodes": .array([]),
    ])
  ]
}

private func liveReactorJoinRow(
  _ entityID: String,
  _ attributeID: String,
  _ value: InstantLiveJSONValue,
  _ timestamp: InstantTimestamp
) -> InstantLiveJSONValue {
  .array([
    .string(entityID),
    .string(attributeID),
    value,
    .number(Double(timestamp.milliseconds)),
  ])
}

private func liveReactorServerAttr(id: String, name: String) -> InstantLiveJSONValue {
  .object([
    "cardinality": .string("one"),
    "forward-identity": .array([
      .string("identity-\(id)"),
      .string(TodoExample.namespace),
      .string(name),
    ]),
    "id": .string(id),
    "unique?": .bool(name == "id"),
    "value-type": .string(
      name == "createdAt" ? "date" : (name == "isCompleted" ? "boolean" : "string")
    ),
  ])
}
