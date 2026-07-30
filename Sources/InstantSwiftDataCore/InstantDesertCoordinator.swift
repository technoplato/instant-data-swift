import Foundation

public actor InstantDesertCoordinator {
  private struct TripleKey: Hashable, Sendable {
    var entityID: String
    var attributeID: String
    var manyValue: InstantLiveJSONValue?
  }

  private struct StoredTriple: Hashable, Sendable {
    var entityID: String
    var attributeID: String
    var value: InstantLiveJSONValue
    var txTime: Int64
  }

  private struct SessionState: Sendable {
    var mailbox: InstantDesertMailbox
    var queries: Set<InstantLiveJSONValue> = []
    var rooms: Set<String> = []
  }

  private struct CompletedTransaction: Sendable {
    var transactionID: Int64
    var isn: Int64
    var txSteps: [InstantLiveJSONValue]
  }

  public let appID: String
  public let initialAttributes: [InstantAttribute]

  private let attributesByID: [String: InstantAttribute]
  private let serverAttributes: [InstantLiveJSONValue]
  private let now: @Sendable () -> InstantTimestamp
  private var sessions: [String: SessionState] = [:]
  private var triples: [TripleKey: StoredTriple] = [:]
  private var completedTransactions: [String: CompletedTransaction] = [:]
  private var presenceByRoom: [String: [String: InstantLiveJSONValue]] = [:]
  private var nextSessionID = 1
  private var nextTransactionID: Int64 = 1
  private var lastTransactionTime: Int64?

  public init(
    appID: String,
    initialAttributes: [InstantAttribute] = [],
    now: @escaping @Sendable () -> InstantTimestamp = {
      InstantTimestamp(milliseconds: Int64(Date().timeIntervalSince1970 * 1_000))
    }
  ) {
    self.appID = appID
    self.initialAttributes = initialAttributes
    self.now = now
    self.attributesByID = Dictionary(
      initialAttributes.map { ($0.id, $0) },
      uniquingKeysWith: { _, latest in latest }
    )
    self.serverAttributes = initialAttributes.map(Self.serverAttribute).sorted {
      ($0.objectValue?["id"]?.stringValue ?? "")
        < ($1.objectValue?["id"]?.stringValue ?? "")
    }
  }

  public nonisolated var transport: InstantLiveTransportClient {
    InstantLiveTransportClient { request in
      try await self.openSession(appID: request.appID)
    }
  }

  func openSession(appID: String) throws -> InstantLiveWebSocketSession {
    guard appID == self.appID else {
      throw InstantError(
        code: .validationFailed,
        operation: "open Instant desert session",
        path: "appID",
        message: "The desert coordinator serves app id '\(self.appID)', not '\(appID)'.",
        recovery: "Use the same Instant app id on the desert host and every peer."
      )
    }

    let sessionID = "desert-session-\(nextSessionID)"
    nextSessionID += 1
    let mailbox = InstantDesertMailbox(sessionID: sessionID)
    sessions[sessionID] = SessionState(mailbox: mailbox)

    return InstantLiveWebSocketSession(
      send: { message in
        try await self.receive(message, from: sessionID)
      },
      receive: {
        try await mailbox.receive()
      },
      close: {
        await self.closeSession(sessionID)
      }
    )
  }

  private func receive(_ message: InstantLiveMessage, from sessionID: String) async throws {
    guard sessions[sessionID] != nil else {
      throw InstantError(
        code: .networkFailed,
        operation: "send Instant desert message",
        message: "The desert session is closed.",
        recovery: "Open a new desert session and retry the operation."
      )
    }

    do {
      try await handle(message, from: sessionID)
    } catch let error as InstantError {
      await enqueue(
        InstantLiveMessage(
          op: "error",
          clientEventID: message.clientEventID,
          fields: [
            "message": .string(error.message),
            "status": .number(400),
            "type": .string(error.code.rawValue),
          ]
        ),
        to: sessionID
      )
    } catch {
      await enqueue(
        InstantLiveMessage(
          op: "error",
          clientEventID: message.clientEventID,
          fields: [
            "message": .string(String(describing: error)),
            "status": .number(500),
            "type": .string("desert-coordinator-error"),
          ]
        ),
        to: sessionID
      )
    }
  }

  private func handle(_ message: InstantLiveMessage, from sessionID: String) async throws {
    switch message.op {
    case "init":
      let receivedAppID = message.fields["app-id"]?.stringValue
      guard receivedAppID == appID else {
        throw InstantError(
          code: .validationFailed,
          operation: "initialize Instant desert session",
          path: "app-id",
          message:
            "The peer requested app id '\(receivedAppID ?? "missing")' but this host serves '\(appID)'.",
          recovery: "Launch the host and peer with the same Instant app id."
        )
      }
      await enqueue(
        InstantLiveMessage(
          op: "init-ok",
          clientEventID: message.clientEventID,
          fields: [
            "attrs": .array(serverAttributes),
            "auth": .null,
            "session-id": .string(sessionID),
          ]
        ),
        to: sessionID
      )

    case "add-query":
      guard let query = message.fields["q"] else {
        throw malformed(message, reason: "add-query requires q.")
      }
      try validate(query: query)
      guard var session = sessions[sessionID] else { return }
      let wasAlreadyRegistered = session.queries.contains(query)
      session.queries.insert(query)
      sessions[sessionID] = session
      if wasAlreadyRegistered {
        await enqueue(
          InstantLiveMessage(
            op: "add-query-exists",
            clientEventID: message.clientEventID,
            fields: ["q": query]
          ),
          to: sessionID
        )
      } else {
        let processedTransactionID = currentProcessedTransactionID
        await enqueue(
          InstantLiveMessage(
            op: "add-query-ok",
            clientEventID: message.clientEventID,
            fields: [
              "processed-tx-id": .number(Double(processedTransactionID)),
              "q": query,
              "result": .array([canonicalResult(for: query)]),
            ]
          ),
          to: sessionID
        )
      }

    case "remove-query":
      guard let query = message.fields["q"], var session = sessions[sessionID] else { return }
      session.queries.remove(query)
      sessions[sessionID] = session

    case "transact":
      try await transact(message, from: sessionID)

    case "join-room":
      try await joinRoom(message, from: sessionID)

    case "set-presence":
      try await setPresence(message, from: sessionID)

    case "leave-room":
      try await leaveRoom(message, from: sessionID)

    case "client-broadcast":
      try await broadcastTopic(message, from: sessionID)

    default:
      throw InstantError(
        code: .validationFailed,
        operation: "handle Instant desert message",
        message: "Unsupported desert operation '\(message.op)'.",
        recovery:
          "Use init, query, transaction, room, presence, or topic operations in the prototype."
      )
    }
  }

  private func transact(_ message: InstantLiveMessage, from sessionID: String) async throws {
    guard let clientEventID = message.clientEventID, !clientEventID.isEmpty else {
      throw malformed(message, reason: "transact requires client-event-id.")
    }
    guard let steps = message.fields["tx-steps"]?.arrayValue else {
      throw malformed(message, reason: "transact requires tx-steps.")
    }
    if let completed = completedTransactions[clientEventID] {
      guard completed.txSteps == steps else {
        throw InstantError(
          code: .validationFailed,
          operation: "deduplicate Instant desert transaction",
          serverEventID: clientEventID,
          message: "The client event id was reused with different transaction steps.",
          recovery: "Generate one stable client event id per logical mutation."
        )
      }
      let acknowledgement = transactionAcknowledgement(clientEventID, completed)
      let refresh = refreshMessage(
        for: sessionID,
        clientEventID: clientEventID,
        processedTransactionID: completed.transactionID
      )
      await enqueue(acknowledgement, to: sessionID)
      await enqueue(refresh, to: sessionID)
      return
    }

    let transactionNumber = nextTransactionID
    let monotonicFloor =
      lastTransactionTime.map {
        $0 == .max ? Int64.max : $0 + 1
      } ?? Int64.min
    let txTime = max(now().milliseconds, monotonicFloor)
    var stagedTriples = triples
    for step in steps {
      try apply(step: step, txTime: txTime, to: &stagedTriples)
    }
    let completed = CompletedTransaction(
      transactionID: transactionNumber,
      isn: transactionNumber,
      txSteps: steps
    )
    triples = stagedTriples
    lastTransactionTime = txTime
    completedTransactions[clientEventID] = completed
    nextTransactionID += 1

    let acknowledgement = transactionAcknowledgement(clientEventID, completed)
    let refreshes = sessions.keys.sorted().map { targetSessionID in
      (
        targetSessionID,
        refreshMessage(
          for: targetSessionID,
          clientEventID: clientEventID,
          processedTransactionID: transactionNumber
        )
      )
    }
    await enqueue(acknowledgement, to: sessionID)
    for (targetSessionID, refresh) in refreshes {
      await enqueue(refresh, to: targetSessionID)
    }
  }

  private func apply(
    step: InstantLiveJSONValue,
    txTime: Int64,
    to triples: inout [TripleKey: StoredTriple]
  ) throws {
    guard let parts = step.arrayValue, let operation = parts.first?.stringValue else {
      throw malformed(nil, reason: "Transaction steps must be encoded arrays.")
    }
    switch operation {
    case "add-triple", "deep-merge-triple":
      guard parts.count >= 4, let attributeID = parts[2].stringValue else {
        throw malformed(nil, reason: "\(operation) requires entity, attribute, and value.")
      }
      let entityID = try resolveEntity(parts[1], in: triples)
      var value = try resolveReferenceValueIfNeeded(
        parts[3],
        attributeID: attributeID,
        in: triples
      )
      if operation == "deep-merge-triple",
        let current = triples.values.first(where: {
          $0.entityID == entityID && $0.attributeID == attributeID
        })?.value
      {
        value = Self.deepMerge(current, value)
      }
      store(
        entityID: entityID,
        attributeID: attributeID,
        value: value,
        txTime: txTime,
        in: &triples
      )

    case "retract-triple":
      guard parts.count >= 4, let attributeID = parts[2].stringValue else {
        throw malformed(nil, reason: "retract-triple requires entity, attribute, and value.")
      }
      let entityID = try resolveEntity(parts[1], in: triples)
      let value = try resolveReferenceValueIfNeeded(
        parts[3],
        attributeID: attributeID,
        in: triples
      )
      triples = triples.filter {
        !($0.value.entityID == entityID
          && $0.value.attributeID == attributeID
          && $0.value.value == value)
      }

    case "delete-entity":
      guard parts.count >= 2 else {
        throw malformed(nil, reason: "delete-entity requires an entity.")
      }
      let entityID = try resolveEntity(parts[1], in: triples)
      let namespace = parts.count >= 3 ? parts[2].stringValue : nil
      triples = triples.filter { _, triple in
        guard triple.entityID == entityID else { return true }
        guard let namespace else { return false }
        return attributeNamespace(triple.attributeID) != namespace
      }

    case "rule-params":
      break

    default:
      throw malformed(nil, reason: "Unsupported transaction step '\(operation)'.")
    }
  }

  private func store(
    entityID: String,
    attributeID: String,
    value: InstantLiveJSONValue,
    txTime: Int64,
    in triples: inout [TripleKey: StoredTriple]
  ) {
    let isMany = attributesByID[attributeID]?.cardinality == .many
    if !isMany {
      triples = triples.filter {
        !($0.value.entityID == entityID && $0.value.attributeID == attributeID)
      }
    }
    let key = TripleKey(
      entityID: entityID,
      attributeID: attributeID,
      manyValue: isMany ? value : nil
    )
    triples[key] = StoredTriple(
      entityID: entityID,
      attributeID: attributeID,
      value: value,
      txTime: txTime
    )
  }

  private func resolveEntity(
    _ value: InstantLiveJSONValue,
    in triples: [TripleKey: StoredTriple]
  ) throws -> String {
    if let id = value.stringValue { return id }
    guard let lookup = value.arrayValue, lookup.count >= 2,
      let attributeID = lookup[0].stringValue
    else {
      throw malformed(
        nil, reason: "Entity references must be ids or [attribute-id, value] lookups.")
    }
    guard
      let match = triples.values.first(where: {
        $0.attributeID == attributeID && $0.value == lookup[1]
      })
    else {
      throw InstantError(
        code: .validationFailed,
        operation: "resolve Instant desert lookup",
        path: attributeID,
        message: "No desert entity matches the lookup value.",
        recovery: "Create the unique lookup target before using it in a transaction."
      )
    }
    return match.entityID
  }

  private func resolveReferenceValueIfNeeded(
    _ value: InstantLiveJSONValue,
    attributeID: String,
    in triples: [TripleKey: StoredTriple]
  ) throws -> InstantLiveJSONValue {
    guard attributesByID[attributeID]?.valueType == .ref, value.arrayValue != nil else {
      return value
    }
    return .string(try resolveEntity(value, in: triples))
  }

  private func transactionAcknowledgement(
    _ clientEventID: String,
    _ transaction: CompletedTransaction
  ) -> InstantLiveMessage {
    InstantLiveMessage(
      op: "transact-ok",
      clientEventID: clientEventID,
      fields: [
        "isn": .number(Double(transaction.isn)),
        "tx-id": .number(Double(transaction.transactionID)),
      ]
    )
  }

  private func refreshMessage(
    for sessionID: String,
    clientEventID: String,
    processedTransactionID: Int64
  ) -> InstantLiveMessage {
    let queries = sessions[sessionID]?.queries.sorted { querySortKey($0) < querySortKey($1) } ?? []
    return InstantLiveMessage(
      op: "refresh-ok",
      clientEventID: clientEventID,
      fields: [
        "attrs": .array(serverAttributes),
        "computations": .array(
          queries.map { query in
            .object([
              "instaql-query": query,
              "instaql-result": .array([canonicalResult(for: query)]),
              "processed-tx-id": .number(Double(processedTransactionID)),
            ])
          }
        ),
        "processed-tx-id": .number(Double(processedTransactionID)),
      ]
    )
  }

  private func canonicalResult(for query: InstantLiveJSONValue) -> InstantLiveJSONValue {
    let namespaces = Set(
      query.objectValue?.keys.filter { !$0.hasPrefix("$") } ?? []
    )
    let matching = triples.values.filter { triple in
      namespaces.isEmpty || namespaces.contains(attributeNamespace(triple.attributeID))
    }
    let byEntity = Dictionary(grouping: matching, by: \.entityID)
    let joinRows: [InstantLiveJSONValue] = byEntity.keys.sorted().map { entityID in
      let row = (byEntity[entityID] ?? []).sorted {
        ($0.attributeID, querySortKey($0.value)) < ($1.attributeID, querySortKey($1.value))
      }
      return .array(
        row.map { triple in
          .array([
            .string(triple.entityID),
            .string(triple.attributeID),
            triple.value,
            .number(Double(triple.txTime)),
          ])
        }
      )
    }
    return .object([
      "child-nodes": .array([]),
      "data": .object([
        "datalog-result": .object([
          "join-rows": .array(joinRows)
        ])
      ]),
    ])
  }

  private func validate(query: InstantLiveJSONValue) throws {
    guard case .object(let namespaces) = query,
      namespaces.count == 1,
      let (namespace, body) = namespaces.first,
      !namespace.hasPrefix("$")
    else {
      throw unsupportedQuery(
        path: "q",
        reason: "Desert queries must select exactly one top-level namespace."
      )
    }
    guard case .object(let fields) = body else {
      throw unsupportedQuery(
        path: "q.\(namespace)",
        reason: "The desert namespace selection must be an object."
      )
    }
    for (key, value) in fields {
      guard key == "$" else {
        throw unsupportedQuery(
          path: "q.\(namespace).\(key)",
          reason: "Nested child queries are not implemented by the desert prototype."
        )
      }
      guard case .object(let options) = value else {
        throw unsupportedQuery(
          path: "q.\(namespace).$",
          reason: "Desert query options must be an object."
        )
      }
      let unsupported = options.keys.filter { $0 != "order" }.sorted()
      guard unsupported.isEmpty else {
        throw unsupportedQuery(
          path: "q.\(namespace).$.\(unsupported[0])",
          reason:
            "The desert prototype does not implement filters, pagination, cursors, limits, offsets, or field selection."
        )
      }
    }
  }

  private func unsupportedQuery(path: String, reason: String) -> InstantError {
    InstantError(
      code: .validationFailed,
      operation: "validate Instant desert query",
      path: path,
      message: reason,
      recovery: "Use a single unfiltered namespace query while running the desert prototype."
    )
  }

  private func joinRoom(_ message: InstantLiveMessage, from sessionID: String) async throws {
    guard let roomID = message.fields["room-id"]?.stringValue else {
      throw malformed(message, reason: "join-room requires room-id.")
    }
    guard var session = sessions[sessionID] else { return }
    session.rooms.insert(roomID)
    sessions[sessionID] = session
    presenceByRoom[roomID, default: [:]][sessionID] = presenceEnvelope(
      sessionID: sessionID,
      data: message.fields["data"] ?? .object([:])
    )
    await enqueue(
      InstantLiveMessage(
        op: "join-room-ok",
        clientEventID: message.clientEventID,
        fields: ["room-id": .string(roomID)]
      ),
      to: sessionID
    )
    await broadcastPresence(roomID: roomID, clientEventID: message.clientEventID)
  }

  private func setPresence(_ message: InstantLiveMessage, from sessionID: String) async throws {
    guard let roomID = message.fields["room-id"]?.stringValue,
      sessions[sessionID]?.rooms.contains(roomID) == true
    else {
      throw malformed(message, reason: "set-presence requires a joined room-id.")
    }
    presenceByRoom[roomID, default: [:]][sessionID] = presenceEnvelope(
      sessionID: sessionID,
      data: message.fields["data"] ?? .object([:])
    )
    await broadcastPresence(roomID: roomID, clientEventID: message.clientEventID)
  }

  private func leaveRoom(_ message: InstantLiveMessage, from sessionID: String) async throws {
    guard let roomID = message.fields["room-id"]?.stringValue else {
      throw malformed(message, reason: "leave-room requires room-id.")
    }
    await enqueue(
      InstantLiveMessage(
        op: "leave-room-ok",
        clientEventID: message.clientEventID,
        fields: ["room-id": .string(roomID)]
      ),
      to: sessionID
    )
    removePresence(sessionID: sessionID, roomID: roomID)
    await broadcastPresence(roomID: roomID, clientEventID: message.clientEventID)
  }

  private func broadcastPresence(roomID: String, clientEventID: String?) async {
    let members = presenceByRoom[roomID] ?? [:]
    let event = InstantLiveMessage(
      op: "refresh-presence",
      clientEventID: clientEventID,
      fields: [
        "data": .object(members),
        "room-id": .string(roomID),
      ]
    )
    for target in members.keys.sorted() {
      await enqueue(event, to: target)
    }
  }

  private func broadcastTopic(_ message: InstantLiveMessage, from sessionID: String) async throws {
    guard let roomID = message.fields["room-id"]?.stringValue,
      let topic = message.fields["topic"]?.stringValue,
      sessions[sessionID]?.rooms.contains(roomID) == true
    else {
      throw malformed(message, reason: "client-broadcast requires a joined room-id and topic.")
    }
    let event = InstantLiveMessage(
      op: "server-broadcast",
      clientEventID: message.clientEventID,
      fields: [
        "data": .object([
          "data": message.fields["data"] ?? .null,
          "peer-id": .string(sessionID),
          "user": .null,
        ]),
        "room-id": .string(roomID),
        "topic": .string(topic),
      ]
    )
    for target in (presenceByRoom[roomID] ?? [:]).keys.sorted() where target != sessionID {
      await enqueue(event, to: target)
    }
  }

  private func removePresence(sessionID: String, roomID: String) {
    presenceByRoom[roomID]?[sessionID] = nil
    if presenceByRoom[roomID]?.isEmpty == true {
      presenceByRoom[roomID] = nil
    }
    if var session = sessions[sessionID] {
      session.rooms.remove(roomID)
      sessions[sessionID] = session
    }
  }

  private func closeSession(_ sessionID: String) async {
    guard let session = sessions.removeValue(forKey: sessionID) else { return }
    for roomID in session.rooms {
      presenceByRoom[roomID]?[sessionID] = nil
      if presenceByRoom[roomID]?.isEmpty == true {
        presenceByRoom[roomID] = nil
      } else {
        await broadcastPresence(roomID: roomID, clientEventID: nil)
      }
    }
    await session.mailbox.close()
  }

  private func enqueue(_ message: InstantLiveMessage, to sessionID: String) async {
    guard let mailbox = sessions[sessionID]?.mailbox else { return }
    await mailbox.enqueue(message)
  }

  private func presenceEnvelope(
    sessionID: String,
    data: InstantLiveJSONValue
  ) -> InstantLiveJSONValue {
    .object([
      "data": data,
      "peer-id": .string(sessionID),
      "user": .null,
    ])
  }

  private var currentProcessedTransactionID: Int64 {
    nextTransactionID - 1
  }

  private func attributeNamespace(_ attributeID: String) -> String {
    attributesByID[attributeID]?.namespace
      ?? attributeID.split(separator: "/", maxSplits: 1).first.map(String.init)
      ?? attributeID
  }

  private func querySortKey(_ value: InstantLiveJSONValue) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
  }

  private func malformed(_ message: InstantLiveMessage?, reason: String) -> InstantError {
    InstantError(
      code: .decodeFailed,
      operation: "decode Instant desert message",
      serverEventID: message?.clientEventID,
      message: reason,
      recovery: "Inspect the prototype transport envelope and retry the operation."
    )
  }

  private static func deepMerge(
    _ current: InstantLiveJSONValue,
    _ update: InstantLiveJSONValue
  ) -> InstantLiveJSONValue {
    guard case .object(let currentObject) = current,
      case .object(let updateObject) = update
    else {
      return update
    }
    var merged = currentObject
    for key in updateObject.keys.sorted() {
      if let old = merged[key], let new = updateObject[key] {
        merged[key] = deepMerge(old, new)
      } else {
        merged[key] = updateObject[key]
      }
    }
    return .object(merged)
  }

  private static func serverAttribute(_ attribute: InstantAttribute) -> InstantLiveJSONValue {
    var object: [String: InstantLiveJSONValue] = [
      "cardinality": .string(attribute.cardinality.rawValue),
      "checked-data-type": .string(attribute.valueType.rawValue),
      "forward-identity": .array([
        .string("desert-forward-\(attribute.id)"),
        .string(attribute.namespace),
        .string(attribute.name),
      ]),
      "id": .string(attribute.id),
      "index?": .bool(attribute.isIndexed),
      "optional?": .bool(!attribute.isRequired),
      "unique?": .bool(attribute.isUnique),
      "value-type": .string(attribute.valueType.rawValue),
    ]
    if attribute.valueType == .ref, let reverse = attribute.reverseIdentity {
      let parts = reverse.split(separator: "/", maxSplits: 1).map(String.init)
      if parts.count == 2 {
        object["reverse-identity"] = .array([
          .string("desert-reverse-\(attribute.id)"),
          .string(parts[0]),
          .string(parts[1]),
        ])
      }
    }
    return .object(object)
  }
}

private actor InstantDesertMailbox {
  private let sessionID: String
  private var pending: [InstantLiveMessage] = []
  private var receivers: [CheckedContinuation<InstantLiveMessage, any Error>] = []
  private var isClosed = false

  init(sessionID: String) {
    self.sessionID = sessionID
  }

  func enqueue(_ message: InstantLiveMessage) {
    guard !isClosed else { return }
    if receivers.isEmpty {
      pending.append(message)
    } else {
      receivers.removeFirst().resume(returning: message)
    }
  }

  func receive() async throws -> InstantLiveMessage {
    if !pending.isEmpty { return pending.removeFirst() }
    guard !isClosed else { throw closedError }
    return try await withCheckedThrowingContinuation { continuation in
      receivers.append(continuation)
    }
  }

  func close() {
    guard !isClosed else { return }
    isClosed = true
    pending.removeAll()
    let error = closedError
    for receiver in receivers {
      receiver.resume(throwing: error)
    }
    receivers.removeAll()
  }

  private var closedError: InstantError {
    InstantError(
      code: .networkFailed,
      operation: "receive Instant desert message",
      serverEventID: sessionID,
      message: "The desert session is closed.",
      recovery: "Open a new desert session before receiving another message."
    )
  }
}
