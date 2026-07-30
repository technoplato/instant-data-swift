import CustomDump
import Foundation
import Testing

@testable import InstantSwiftDataCore

@Suite
struct InstantDesertCoordinatorTests {
  @Test
  func coordinatorBroadcastsCanonicalSnapshotsAndDeduplicatesTransactions() async throws {
    let coordinator = InstantDesertCoordinator(
      appID: "desert-coordinator",
      initialAttributes: TodoExample.attributes
    )
    let first = try await coordinator.transport.connect(
      InstantLiveSessionRequest(appID: "desert-coordinator")
    )
    let second = try await coordinator.transport.connect(
      InstantLiveSessionRequest(appID: "desert-coordinator")
    )

    try await first.send(.initMessage(appID: "desert-coordinator", clientEventID: "init-first"))
    try await second.send(.initMessage(appID: "desert-coordinator", clientEventID: "init-second"))
    let firstInit = try await receiveDesertMessage(from: first)
    let secondInit = try await receiveDesertMessage(from: second)
    expectNoDifference(firstInit.op, "init-ok")
    expectNoDifference(secondInit.op, "init-ok")

    let query: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])])
    try await first.send(.addQuery(query, clientEventID: "query-first"))
    try await second.send(.addQuery(query, clientEventID: "query-second"))
    let firstQuery = try await receiveDesertMessage(from: first)
    let secondQuery = try await receiveDesertMessage(from: second)
    expectNoDifference(firstQuery.op, "add-query-ok")
    expectNoDifference(secondQuery.op, "add-query-ok")

    let transaction = try InstantLiveMessage.transact(
      desertTodoSteps(text: "Across the desert"),
      clientEventID: "mutation-1"
    )
    try await first.send(transaction)
    let acknowledgement = try await receiveDesertMessage(from: first)
    let firstRefresh = try await receiveDesertMessage(from: first)
    let secondRefresh = try await receiveDesertMessage(from: second)

    expectNoDifference(acknowledgement.op, "transact-ok")
    expectNoDifference(firstRefresh.op, "refresh-ok")
    expectNoDifference(secondRefresh.op, "refresh-ok")
    expectNoDifference(
      desertTextValues(in: secondRefresh),
      ["Across the desert"]
    )

    try await first.send(transaction)
    let duplicateAcknowledgement = try await receiveDesertMessage(from: first)
    let duplicateRefresh = try await receiveDesertMessage(from: first)
    expectNoDifference(
      duplicateAcknowledgement.fields["tx-id"],
      acknowledgement.fields["tx-id"]
    )
    expectNoDifference(desertTextValues(in: duplicateRefresh), ["Across the desert"])

    try await first.send(
      .transact(
        desertTodoSteps(text: "Conflicting retry"),
        clientEventID: "mutation-1"
      )
    )
    let conflict = try await receiveDesertMessage(from: first)
    expectNoDifference(conflict.op, "error")
    #expect(conflict.fields["message"]?.stringValue?.contains("reused") == true)

    await first.close()
    await second.close()
  }

  @Test
  func twoRuntimesPropagateTodoMutationThroughPublicObservation() async throws {
    let appID = "desert-two-runtime"
    let generatedAttributes = TodoExample.attributes.filter { !$0.primaryKey }
    let coordinator = InstantDesertCoordinator(
      appID: appID,
      initialAttributes: generatedAttributes,
      now: { InstantTimestamp(milliseconds: 1_900_000_000_000) }
    )
    let route = InstantSyncRouteDescriptor(
      route: .desert,
      adapter: "in-process-desert",
      transport: .inProcess
    )
    let firstCache = try temporaryDesertCacheURL("first")
    let secondCache = try temporaryDesertCacheURL("second")
    defer { try? FileManager.default.removeItem(at: firstCache.deletingLastPathComponent()) }
    defer { try? FileManager.default.removeItem(at: secondCache.deletingLastPathComponent()) }
    let first = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: firstCache,
        initialAttributes: generatedAttributes,
        liveTransport: coordinator.transport,
        syncRoute: route
      )
    )
    let second = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: secondCache,
        initialAttributes: generatedAttributes,
        liveTransport: coordinator.transport,
        syncRoute: route
      )
    )

    let stream = await second.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let localInitial = try #require(await iterator.next())
    expectNoDifference(localInitial.values, [])
    let secondStatus = try await second.connect()
    let firstStatus = try await first.connect()
    expectNoDifference(secondStatus.state, .opened)
    expectNoDifference(secondStatus.transport, .inProcess)
    expectNoDifference(secondStatus.syncRoute, route)
    expectNoDifference(firstStatus.state, .opened)
    expectNoDifference(firstStatus.transport, .inProcess)
    expectNoDifference(firstStatus.syncRoute, route)

    let createdAt = InstantTimestamp(milliseconds: 1_800_000_000_000)
    try await first.transact(
      InstantStoreTransaction(
        id: "desert-runtime-mutation",
        operations: TodoExample.createOperations(
          id: "desert-runtime-todo",
          text: "Mac to Simulator",
          createdAt: createdAt,
          transactionID: "desert-runtime-mutation"
        )
      ),
      createdAt: createdAt
    )

    var receivedTodos: [TodoRecord] = []
    while receivedTodos.isEmpty {
      let emission = try #require(await iterator.next())
      receivedTodos = try TodoExample.decode(emission.values)
    }
    expectNoDifference(receivedTodos.map(\.text), ["Mac to Simulator"])
    let cleared = try #require(
      await first.observeConnectionStatus().first { $0.pendingMutationCount == 0 }
    )
    expectNoDifference(cleared.state, .opened)
    expectNoDifference(cleared.processedTransactionID, "1")
    let firstSyncState = try await first.syncState()
    expectNoDifference(firstSyncState.processedTransactionID, "1")

    let updatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await first.transact(
      InstantStoreTransaction(
        id: "desert-runtime-mutation-2",
        operations: TodoExample.updateTextOperations(
          id: "desert-runtime-todo",
          text: "Mac to Simulator twice",
          updatedAt: updatedAt,
          transactionID: "desert-runtime-mutation-2"
        )
      ),
      createdAt: updatedAt
    )
    let secondCleared = try #require(
      await first.observeConnectionStatus().first {
        $0.pendingMutationCount == 0 && $0.processedTransactionID == "2"
      }
    )
    expectNoDifference(secondCleared.state, .opened)
    let remainingMutations = await first.pendingMutations()
    expectNoDifference(remainingMutations, [])

    _ = try await first.closeConnection()
    _ = try await second.closeConnection()
  }

  @Test
  func transactionsAreAtomicAndFailedTransactionsDoNotConsumeIDs() async throws {
    let appID = "desert-atomic-transactions"
    let coordinator = InstantDesertCoordinator(
      appID: appID,
      initialAttributes: TodoExample.attributes,
      now: { InstantTimestamp(milliseconds: 2_000) }
    )
    let session = try await initializedDesertSession(coordinator: coordinator, appID: appID)

    let validFirstStep: InstantLiveJSONValue = .array([
      .string("add-triple"),
      .string("atomic-todo"),
      .string("todos/text"),
      .string("must roll back"),
    ])
    let invalidLaterStep: InstantLiveJSONValue = .array([.string("unsupported-step")])
    try await session.send(
      InstantLiveMessage(
        op: "transact",
        clientEventID: "atomic-invalid",
        fields: ["tx-steps": .array([validFirstStep, invalidLaterStep])]
      )
    )
    let failure = try await receiveDesertMessage(from: session)
    expectNoDifference(failure.op, "error")

    let query: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])])
    try await session.send(.addQuery(query, clientEventID: "atomic-query"))
    let afterFailure = try await receiveDesertMessage(from: session)
    expectNoDifference(afterFailure.op, "add-query-ok")
    expectNoDifference(desertTextValues(in: afterFailure), [])

    try await session.send(
      .transact(
        desertTodoSteps(id: "atomic-todo", text: "committed"),
        clientEventID: "atomic-valid"
      )
    )
    let acknowledgement = try await receiveDesertMessage(from: session)
    let refresh = try await receiveDesertMessage(from: session)
    expectNoDifference(acknowledgement.fields["tx-id"], .number(1))
    expectNoDifference(refresh.fields["processed-tx-id"], .number(1))
    expectNoDifference(desertTextValues(in: refresh), ["committed"])
    expectNoDifference(desertTransactionTimes(in: refresh), [2_000])

    await session.close()
  }

  @Test
  func concurrentTransactionsUseCapturedNumericIDsAndMonotonicTimes() async throws {
    let appID = "desert-concurrent-transactions"
    let coordinator = InstantDesertCoordinator(
      appID: appID,
      initialAttributes: TodoExample.attributes,
      now: { InstantTimestamp(milliseconds: 5_000) }
    )
    let first = try await initializedDesertSession(coordinator: coordinator, appID: appID)
    let second = try await initializedDesertSession(coordinator: coordinator, appID: appID)
    let query: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])])
    try await first.send(.addQuery(query, clientEventID: "concurrent-query-first"))
    try await second.send(.addQuery(query, clientEventID: "concurrent-query-second"))
    _ = try await receiveDesertMessage(from: first)
    _ = try await receiveDesertMessage(from: second)

    async let firstSend: Void = first.send(
      .transact(
        desertTodoSteps(id: "concurrent-first", text: "first"),
        clientEventID: "concurrent-first"
      )
    )
    async let secondSend: Void = second.send(
      .transact(
        desertTodoSteps(id: "concurrent-second", text: "second"),
        clientEventID: "concurrent-second"
      )
    )
    _ = try await (firstSend, secondSend)

    let firstMessages = try await receiveDesertMessages(3, from: first)
    let secondMessages = try await receiveDesertMessages(3, from: second)
    let messages = firstMessages + secondMessages
    let acknowledgements = messages.filter { $0.op == "transact-ok" }
    expectNoDifference(
      acknowledgements.compactMap { desertScalarString($0.fields["tx-id"]) }.sorted(),
      ["1", "2"]
    )
    let transactionIDByEvent: [String: String] = Dictionary(
      uniqueKeysWithValues: acknowledgements.compactMap { message in
        guard let eventID = message.clientEventID,
          let transactionID = desertScalarString(message.fields["tx-id"])
        else { return nil }
        return (eventID, transactionID)
      }
    )
    let refreshes = messages.filter { $0.op == "refresh-ok" }
    expectNoDifference(refreshes.count, 4)
    for refresh in refreshes {
      let eventID = try #require(refresh.clientEventID)
      expectNoDifference(
        desertScalarString(refresh.fields["processed-tx-id"]),
        transactionIDByEvent[eventID]
      )
    }
    let distinctRefreshes = Dictionary(
      refreshes.map { ($0.clientEventID ?? "", $0) },
      uniquingKeysWith: { first, _ in first }
    )
    let firstCommitted = try #require(
      distinctRefreshes.first {
        desertScalarString($0.value.fields["processed-tx-id"]) == "1"
      }?.value
    )
    let secondCommitted = try #require(
      distinctRefreshes.first {
        desertScalarString($0.value.fields["processed-tx-id"]) == "2"
      }?.value
    )
    expectNoDifference(desertTransactionTimes(in: firstCommitted), [5_000])
    expectNoDifference(desertTransactionTimes(in: secondCommitted), [5_000, 5_001])

    await first.close()
    await second.close()
  }

  @Test
  func orderedTodosQueryPassesButUnsupportedAuthoritativeShapesFailLoudly() async throws {
    let appID = "desert-query-capability"
    let coordinator = InstantDesertCoordinator(
      appID: appID,
      initialAttributes: TodoExample.attributes
    )
    let session = try await initializedDesertSession(coordinator: coordinator, appID: appID)
    let orderedTodosQuery: InstantLiveJSONValue = .object([
      "todos": .object([
        "$": .object([
          "order": .object(["serverCreatedAt": .string("desc")])
        ])
      ])
    ])
    try await session.send(.addQuery(orderedTodosQuery, clientEventID: "ordered-todos"))
    let orderedResponse = try await receiveDesertMessage(from: session)
    expectNoDifference(orderedResponse.op, "add-query-ok")

    let unsupportedQueries: [InstantLiveJSONValue] = [
      .object([
        "todos": .object([
          "$": .object(["where": .object(["isCompleted": .bool(false)])])
        ])
      ]),
      .object(["todos": .object(["$": .object(["limit": .number(10)])])]),
      .object([
        "todos": .object([
          "$": .object(["after": .array([.string("cursor"), .string("todo")])])
        ])
      ]),
      .object(["todos": .object(["comments": .object([:])])]),
    ]
    for (index, query) in unsupportedQueries.enumerated() {
      try await session.send(.addQuery(query, clientEventID: "unsupported-\(index)"))
      let response = try await receiveDesertMessage(from: session)
      expectNoDifference(response.op, "error")
      expectNoDifference(response.fields["type"], .string("validationFailed"))
      #expect(response.fields["message"]?.stringValue?.contains("prototype") == true)
    }

    await session.close()
  }

  @Test
  func exactTopLevelIDFilterWithFetchOneLimitReturnsOnlyTheRequestedEntity() async throws {
    let appID = "desert-exact-id-filter"
    let coordinator = InstantDesertCoordinator(
      appID: appID,
      initialAttributes: TodoExample.attributes
    )
    let session = try await initializedDesertSession(coordinator: coordinator, appID: appID)

    for (index, id) in ["wanted-todo", "other-todo"].enumerated() {
      try await session.send(
        .transact(
          desertTodoSteps(id: id, text: id),
          clientEventID: "seed-\(index)"
        )
      )
      _ = try await receiveDesertMessage(from: session)
      _ = try await receiveDesertMessage(from: session)
    }

    let query: InstantLiveJSONValue = .object([
      "todos": .object([
        "$": .object([
          "where": .object(["id": .string("wanted-todo")]),
          "limit": .number(1),
        ])
      ])
    ])
    try await session.send(.addQuery(query, clientEventID: "wanted-query"))
    let response = try await receiveDesertMessage(from: session)

    expectNoDifference(response.op, "add-query-ok")
    expectNoDifference(Set(desertEntityIDs(in: response)), ["wanted-todo"])

    await session.close()
  }

  @Test
  func publicRuntimePresenceAndTopicsUseCanonicalDesertEnvelopes() async throws {
    let appID = "desert-room-envelopes"
    let coordinator = InstantDesertCoordinator(appID: appID)
    let route = InstantSyncRouteDescriptor(
      route: .desert,
      adapter: "in-process-desert",
      transport: .inProcess
    )
    let first = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: try temporaryDesertCacheURL("room-first"),
        liveTransport: coordinator.transport,
        syncRoute: route
      )
    )
    let second = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: try temporaryDesertCacheURL("room-second"),
        liveTransport: coordinator.transport,
        syncRoute: route
      )
    )
    defer {
      try? FileManager.default.removeItem(
        at: first.configuration.persistenceURL.deletingLastPathComponent()
      )
      try? FileManager.default.removeItem(
        at: second.configuration.persistenceURL.deletingLastPathComponent()
      )
    }
    _ = try await first.connect()
    _ = try await second.connect()
    let room = InstantRoomHandle(type: "todos", id: "main")
    _ = try await first.joinRoom(room)
    _ = try await second.joinRoom(room)
    let presenceStream = try await first.observeRoomPresence(room: room)
    let topicStream = try await first.observeRoomTopicMessages(room: room, topic: "reaction")

    let presenceTask = Task {
      await presenceStream.first { members in
        members.contains { $0.values["status"] == .string("online") }
      }
    }
    let topicTask = Task {
      await topicStream.first { messages in
        messages.contains { $0.payload == .object(["emoji": .string("🏝️")]) }
      }
    }
    _ = try await second.setPresence(
      room: room,
      userID: "peer-user",
      values: ["status": .string("online")]
    )
    _ = try await second.publishTopicMessage(
      room: room,
      topic: "reaction",
      userID: "peer-user",
      payload: .object(["emoji": .string("🏝️")])
    )

    let receivedPresence = try await instantLiveWithTimeout(
      operation: "wait for desert presence",
      timeoutMilliseconds: 1_000
    ) {
      try #require(await presenceTask.value)
    }
    let remotePresence = try #require(
      receivedPresence.first { $0.values["status"] == .string("online") }
    )
    #expect(remotePresence.userID.hasPrefix("desert-session-"))
    let receivedTopics = try await instantLiveWithTimeout(
      operation: "wait for desert topic",
      timeoutMilliseconds: 1_000
    ) {
      try #require(await topicTask.value)
    }
    let remoteTopic = try #require(
      receivedTopics.first { $0.payload == .object(["emoji": .string("🏝️")]) }
    )
    #expect(remoteTopic.userID.hasPrefix("desert-session-"))

    _ = try await first.closeConnection()
    _ = try await second.closeConnection()
  }

  #if canImport(Network)
    @Test
    func networkFrameworkHostRejectsNonLoopbackBindAddress() async throws {
      do {
        _ = try await InstantNetworkDesertHost.start(
          appID: "desert-network-bind-rejection",
          host: "0.0.0.0",
          port: 0
        )
        Issue.record("Expected the unauthenticated desert host to reject all-interface binding.")
      } catch let error as InstantError {
        expectNoDifference(error.code, .validationFailed)
        expectNoDifference(error.operation, "start Instant Network.framework desert host")
        expectNoDifference(error.path, "host")
        #expect(error.message.contains("127.0.0.1"))
      }
    }

    @Test
    func networkFrameworkHostStopsWhilePeerIsIdle() async throws {
      let appID = "desert-network-idle-stop"
      let host = try await InstantNetworkDesertHost.start(appID: appID, port: 0)
      let session = try await InstantLiveTransportClient.networkFramework(
        host: "127.0.0.1",
        port: host.port
      ).connect(InstantLiveSessionRequest(appID: appID))
      try await session.send(.initMessage(appID: appID, clientEventID: "idle-init"))
      let response = try await receiveDesertMessage(from: session)
      expectNoDifference(response.op, "init-ok")

      try await instantLiveWithTimeout(
        operation: "stop idle Instant desert host",
        timeoutMilliseconds: 1_000
      ) {
        await host.stop()
      }
      await session.close()
    }

    @Test
    func networkFrameworkHostBindsAnExplicitLoopbackPort() async throws {
      let appID = "desert-network-explicit-port"
      var selectedHost: InstantNetworkDesertHost?
      var selectedPort: UInt16?
      var lastBindingError: (any Error)?
      for explicitPort in UInt16(49_000)...UInt16(49_100) {
        do {
          selectedHost = try await InstantNetworkDesertHost.start(
            appID: appID,
            host: "127.0.0.1",
            port: explicitPort
          )
          selectedPort = explicitPort
          break
        } catch {
          lastBindingError = error
        }
      }
      if selectedHost == nil, let lastBindingError { throw lastBindingError }
      let host = try #require(selectedHost)
      let explicitPort = try #require(selectedPort)
      expectNoDifference(host.port, explicitPort)
      let session = try await InstantLiveTransportClient.networkFramework(
        host: "127.0.0.1",
        port: explicitPort
      ).connect(InstantLiveSessionRequest(appID: appID))
      try await session.send(.initMessage(appID: appID, clientEventID: "explicit-port-init"))
      let response = try await receiveDesertMessage(from: session)
      expectNoDifference(response.op, "init-ok")

      await session.close()
      await host.stop()
    }

    @Test
    func cancellingNetworkFrameworkReadinessDoesNotStrandThePeer() async throws {
      let connection = Task {
        try await InstantLiveTransportClient.networkFramework(
          host: "203.0.113.1",
          port: 9
        ).connect(InstantLiveSessionRequest(appID: "desert-cancelled-peer"))
      }
      try await Task.sleep(for: .milliseconds(20))
      connection.cancel()

      do {
        _ = try await instantLiveWithTimeout(
          operation: "cancel pending Instant desert peer",
          timeoutMilliseconds: 1_000
        ) {
          try await connection.value
        }
        Issue.record("Expected a cancelled or unreachable desert peer to fail.")
      } catch is CancellationError {
      } catch let error as InstantError {
        expectNoDifference(error.code, .networkFailed)
      }
    }

    @Test
    func networkFrameworkBridgeRoundTripsLengthPrefixedMessages() async throws {
      let appID = "desert-network-loopback"
      let host = try await InstantNetworkDesertHost.start(
        appID: appID,
        initialAttributes: TodoExample.attributes,
        port: 0
      )
      let peer = InstantLiveTransportClient.networkFramework(
        host: "127.0.0.1",
        port: host.port
      )
      let session = try await peer.connect(InstantLiveSessionRequest(appID: appID))

      try await session.send(.initMessage(appID: appID, clientEventID: "network-init"))
      let initResponse = try await receiveDesertMessage(from: session)
      expectNoDifference(initResponse.op, "init-ok")
      let query: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])])
      try await session.send(.addQuery(query, clientEventID: "network-query"))
      let queryResponse = try await receiveDesertMessage(from: session)
      expectNoDifference(queryResponse.op, "add-query-ok")
      try await session.send(
        .transact(
          desertTodoSteps(text: "Four byte frame"),
          clientEventID: "network-mutation"
        )
      )
      let transactionResponse = try await receiveDesertMessage(from: session)
      expectNoDifference(transactionResponse.op, "transact-ok")
      let refresh = try await receiveDesertMessage(from: session)
      expectNoDifference(refresh.op, "refresh-ok")
      expectNoDifference(desertTextValues(in: refresh), ["Four byte frame"])

      await session.close()
      await host.stop()
    }
  #endif
}

private func desertTodoSteps(
  id: String = "desert-todo",
  text: String
) -> [InstantTransportStep] {
  [
    .addTriple(
      entity: .id(id),
      attributeID: "todos/id",
      value: .string(id)
    ),
    .addTriple(
      entity: .id(id),
      attributeID: "todos/text",
      value: .string(text)
    ),
    .addTriple(
      entity: .id(id),
      attributeID: "todos/isCompleted",
      value: .bool(false)
    ),
    .addTriple(
      entity: .id(id),
      attributeID: "todos/createdAt",
      value: .string("2027-01-15T08:00:00.000Z")
    ),
  ]
}

private func desertResults(in message: InstantLiveMessage) -> [InstantLiveJSONValue] {
  if let results = message.fields["result"]?.arrayValue {
    return results
  }
  return (message.fields["computations"]?.arrayValue ?? []).flatMap {
    $0.objectValue?["instaql-result"]?.arrayValue ?? []
  }
}

private func desertTriples(in message: InstantLiveMessage) -> [[InstantLiveJSONValue]] {
  let results = desertResults(in: message)
  let rows = results.flatMap {
    $0.objectValue?["data"]?.objectValue?["datalog-result"]?.objectValue?["join-rows"]?
      .arrayValue ?? []
  }
  return rows.flatMap { $0.arrayValue ?? [] }.compactMap(\.arrayValue)
}

private func desertTextValues(in message: InstantLiveMessage) -> [String] {
  desertTriples(in: message).compactMap { values in
    guard values.count >= 3, values[1].stringValue == "todos/text" else { return nil }
    return values[2].stringValue
  }.sorted()
}

private func desertEntityIDs(in message: InstantLiveMessage) -> [String] {
  desertTriples(in: message).compactMap { values in
    values.first?.stringValue
  }
}

private func desertTransactionTimes(in message: InstantLiveMessage) -> [Int64] {
  Array(
    Set(
      desertTriples(in: message).compactMap { values in
        guard values.count >= 4 else { return nil }
        guard case .number(let value) = values[3], value.rounded() == value else { return nil }
        return Int64(value)
      }
    )
  ).sorted()
}

private func initializedDesertSession(
  coordinator: InstantDesertCoordinator,
  appID: String
) async throws -> InstantLiveWebSocketSession {
  let session = try await coordinator.transport.connect(InstantLiveSessionRequest(appID: appID))
  try await session.send(.initMessage(appID: appID, clientEventID: "init-\(UUID().uuidString)"))
  let response = try await receiveDesertMessage(from: session)
  expectNoDifference(response.op, "init-ok")
  return session
}

private func receiveDesertMessages(
  _ count: Int,
  from session: InstantLiveWebSocketSession
) async throws -> [InstantLiveMessage] {
  var messages: [InstantLiveMessage] = []
  for _ in 0..<count {
    messages.append(try await receiveDesertMessage(from: session))
  }
  return messages
}

private func receiveDesertMessage(
  from session: InstantLiveWebSocketSession
) async throws -> InstantLiveMessage {
  try await instantLiveWithTimeout(
    operation: "receive Instant desert test message",
    timeoutMilliseconds: 1_000
  ) {
    try await session.receive()
  }
}

private func desertScalarString(_ value: InstantLiveJSONValue?) -> String? {
  switch value {
  case .string(let value):
    return value
  case .number(let value) where value.rounded() == value:
    return String(Int64(value))
  default:
    return nil
  }
}

private func temporaryDesertCacheURL(_ name: String) throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantDesertCoordinatorTests-\(name)-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}
