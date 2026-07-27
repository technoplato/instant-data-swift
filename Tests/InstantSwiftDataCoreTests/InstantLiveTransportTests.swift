import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

private let reactorIncomingRoomEventSource =
  "upstream/instant/client/packages/core/src/Reactor.js _onMessage join-room-ok, "
  + "refresh-presence, patch-presence, and server-broadcast branches "
  + "[source-derived: upstream has no dedicated transport decoder unit; this pins the exact "
  + "hyphenated operation names and room/data/edits/topic envelopes before Swift applies them]"

private let pythonStreamReaderResumeSource =
  "upstream/instant/client/packages/python/tests/test_streams_state.py "
  + "test_subscribe_msg_uses_current_seen_offset_not_initial_byte_offset, "
  + "test_subscribe_msg_omits_offset_when_zero, "
  + "test_reader_on_reconnect_resubscribes_with_current_offset, and "
  + "test_reader_on_reconnect_surfaces_resubscribe_error "
  + "[adapted: Swift's reader state carries the same canonical subscribe-stream envelope "
  + "and latest byte offset across a reconnect callback; upstream/instant/client/packages/"
  + "core/src/Stream.ts confirms the TypeScript wire keys, while owned runtime registration "
  + "is covered by its separate integration slice]"

private let pythonStreamAppendRetrySource =
  "upstream/instant/client/packages/python/tests/test_streams_state.py "
  + "test_reader_stream_append_with_retry_triggers_force_reconnect "
  + "[adapted: Swift decodes the canonical stream-append envelope, correlates it to the "
  + "active subscribe-stream event id, requests reconnect for retryable server errors, and "
  + "does not deliver the failed append; upstream/instant/client/packages/core/src/Stream.ts "
  + "onStreamAppend confirms the TypeScript behavior]"

private let pythonStreamAppendMaterializationSource =
  "upstream/instant/client/packages/python/src/instantdb/_async/streams/reader.py "
  + "_process_append plus tests/test_streams_state.py "
  + "test_reader_holds_partial_utf8_across_chunk_boundary "
  + "[adapted: Swift applies overlap and resume math in UTF-8 bytes, preserves a complete "
  + "multi-byte scalar, and delivers only bytes not already seen; upstream/instant/client/"
  + "packages/core/src/Stream.ts createReadStream uses the same seenOffset/discardLen rules]"

private let pythonStreamFileRetryBudgetSource =
  "upstream/instant/client/packages/python/tests/test_streams_state.py "
  + "test_reader_fetch_failure_triggers_reconnect_within_budget and "
  + "test_reader_fetch_failure_surfaces_after_budget_exhausted "
  + "[adapted: Swift requests reconnect for the first ten signed-file failures and stores "
  + "a terminal reader failure on the eleventh attempt]"

@Suite
struct InstantLiveTransportTests {
  @Test
  func sameMillisecondMutationsRetainInsertionOrderAcrossRelaunch() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let sameMillisecond = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let configuration = InstantRuntimeConfiguration(
      appID: "same-millisecond-outbox-order",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { sameMillisecond }
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    try await runtime.transact(
      InstantStoreTransaction(
        id: "z-first",
        operations: TodoExample.createOperations(
          id: "todo-first",
          text: "First",
          createdAt: sameMillisecond,
          transactionID: "z-first"
        )
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "a-second",
        operations: TodoExample.createOperations(
          id: "todo-second",
          text: "Second",
          createdAt: sameMillisecond,
          transactionID: "a-second"
        )
      )
    )

    let outboxIDs = await runtime.outboxMutations().map(\.id)
    expectNoDifference(outboxIDs, ["z-first", "a-second"])

    let relaunched = try await InstantRuntime.bootstrap(configuration: configuration)
    let relaunchedOutboxIDs = await relaunched.outboxMutations().map(\.id)
    expectNoDifference(relaunchedOutboxIDs, ["z-first", "a-second"])
  }

  @Test
  func olderOptimisticMutationCannotOverwriteNewerLocalState() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let seedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let olderAt = InstantTimestamp(milliseconds: seedAt.milliseconds + 1)
    let newerAt = InstantTimestamp(milliseconds: seedAt.milliseconds + 2)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "optimistic-mutation-domain-order",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-seed",
        operations: TodoExample.createOperations(
          id: "todo-1",
          text: "Seed",
          createdAt: seedAt,
          transactionID: "tx-seed"
        )
      ),
      createdAt: seedAt
    )
    try await runtime.confirmMutation(id: "tx-seed")

    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-newer",
        operations: TodoExample.updateTextOperations(
          id: "todo-1",
          text: "Newer value",
          updatedAt: newerAt,
          transactionID: "tx-newer"
        )
      ),
      createdAt: newerAt
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-older",
        operations: TodoExample.updateTextOperations(
          id: "todo-1",
          text: "Older value",
          updatedAt: olderAt,
          transactionID: "tx-older"
        )
      ),
      createdAt: olderAt
    )

    let visible = try TodoExample.decode(try await runtime.queryOnce(TodoExample.query).values)
    expectNoDifference(visible.map(\.text), ["Newer value"])
    let outboxIDs = await runtime.outboxMutations().map(\.id)
    expectNoDifference(outboxIDs, ["tx-older", "tx-newer"])
    let olderTransport = try #require(
      await runtime.outboxTransportMutations().first { $0.mutationID == "tx-older" }
    )
    #expect(
      olderTransport.txSteps.contains { step in
        guard
          case let .addTriple(_, attributeID, value, _) = step,
          attributeID == "todos/text",
          value == .string("Older value")
        else { return false }
        return true
      }
    )

    try await runtime.confirmMutation(id: "tx-newer")
    let staleOnlyTransport = try #require(
      await runtime.outboxTransportMutations().first { $0.mutationID == "tx-older" }
    )
    #expect(
      !staleOnlyTransport.txSteps.contains { step in
        guard
          case let .addTriple(_, attributeID, value, _) = step,
          attributeID == "todos/text",
          value == .string("Older value")
        else { return false }
        return true
      }
    )

    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "optimistic-mutation-domain-order",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let restored = try TodoExample.decode(try await relaunched.queryOnce(TodoExample.query).values)
    expectNoDifference(restored.map(\.text), ["Newer value"])
  }

  @Test
  func preparedStoreMutationsComposeWithoutSnapshotRoundTrip() async throws {
    let timestamp = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let store = InstantStore(
      snapshot: InstantStoreSnapshot(attributes: TodoExample.attributes)
    )
    let preparedServer = try await store.prepare(
      InstantStoreTransaction(
        id: "server-refresh",
        operations: [
          .insert(
            InstantTriple(
              entityID: "server-todo",
              attributeID: "todos/id",
              value: .string("server-todo"),
              txID: "server-refresh",
              txTime: timestamp
            )
          )
        ]
      )
    )

    let preparedRebase = try await store.prepare(
      InstantStoreTransaction(
        id: "pending-local-write",
        operations: [
          .insert(
            InstantTriple(
              entityID: "local-todo",
              attributeID: "todos/id",
              value: .string("local-todo"),
              txID: "pending-local-write",
              txTime: timestamp
            )
          )
        ]
      ),
      applyingTo: preparedServer
    )

    expectNoDifference(
      preparedRebase.snapshot.triples.map(\.entityID),
      ["local-todo", "server-todo"]
    )
    expectNoDifference(preparedRebase.result.tripleCount, 2)
  }

  @Test
  func repeatedLiveWebSocketsReuseOneLongLivedURLSession() async throws {
    let generationCount = 64
    var urlSessionIdentities: Set<ObjectIdentifier> = []
    for _ in 0..<generationCount {
      var socket: InstantURLSessionLiveWebSocket? = try InstantURLSessionLiveWebSocket(
        url: try #require(URL(string: "ws://127.0.0.1:1/runtime/session"))
      )
      if let socket {
        urlSessionIdentities.insert(await socket.urlSessionIdentity)
      }
      await socket?.close()
      socket = nil
    }
    expectNoDifference(urlSessionIdentities.count, 1)
  }

  @Test
  func liveWebSocketSessionWaitsForConnectivity() async throws {
    let socket = try InstantURLSessionLiveWebSocket(
      url: try #require(URL(string: "ws://127.0.0.1:1/runtime/session"))
    )
    #expect(await socket.waitsForConnectivity)
    await socket.close()
  }

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
  func transactMessagePreservesZeroAndOneAsNumbers() throws {
    let message = try InstantLiveMessage.transact(
      [
        .addTriple(
          entity: .id("recording-1"),
          attributeID: "recordings/durationMilliseconds",
          value: .number(0)
        ),
        .addTriple(
          entity: .id("attachment-1"),
          attributeID: "attachments/offsetMilliseconds",
          value: .number(1)
        ),
      ],
      clientEventID: "event-numeric-transact"
    )

    guard case let .array(steps) = message.fields["tx-steps"] else {
      Issue.record("Expected tx-steps array.")
      return
    }
    guard case let .array(zeroStep) = steps[0],
      case let .array(oneStep) = steps[1]
    else {
      Issue.record("Expected transaction step arrays.")
      return
    }
    expectNoDifference(zeroStep[3], .number(0))
    expectNoDifference(oneStep[3], .number(1))

    let object = try #require(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(message)) as? [String: Any]
    )
    let encodedSteps = try #require(object["tx-steps"] as? [[Any]])
    let encodedZero = try #require(encodedSteps[0][3] as? NSNumber)
    let encodedOne = try #require(encodedSteps[1][3] as? NSNumber)
    #expect(CFGetTypeID(encodedZero) != CFBooleanGetTypeID())
    #expect(CFGetTypeID(encodedOne) != CFBooleanGetTypeID())
    expectNoDifference(encodedZero.doubleValue, 0)
    expectNoDifference(encodedOne.doubleValue, 1)
  }

  @Test
  func roomMessagesEncodeCanonicalReactorShapes() throws {
    let room = InstantRoomHandle(type: "chat", id: "room-1")
    let presence: [String: JSONValue] = [
      "cursor": .object([
        "x": .number(12),
        "y": .number(34),
      ]),
      "name": .string("Ada"),
    ]

    let join = InstantLiveMessage.joinRoom(
      room,
      presence: presence,
      clientEventID: "event-join"
    )
    expectNoDifference(join.op, "join-room")
    expectNoDifference(join.clientEventID, "event-join")
    expectNoDifference(join.fields, [
      "data": .object([
        "cursor": .object([
          "x": .number(12),
          "y": .number(34),
        ]),
        "name": .string("Ada"),
      ]),
      "room-id": .string("room-1"),
      "room-type": .string("chat"),
    ])

    let setPresence = InstantLiveMessage.setPresence(
      room: room,
      values: presence,
      clientEventID: "event-presence"
    )
    let livePresence = try #require(join.fields["data"])
    expectNoDifference(setPresence.op, "set-presence")
    expectNoDifference(setPresence.fields, [
      "data": livePresence,
      "room-id": .string("room-1"),
    ])

    let broadcast = InstantLiveMessage.clientBroadcast(
      room: room,
      topic: "reaction",
      payload: .object(["emoji": .string("🔥")]),
      clientEventID: "event-broadcast"
    )
    expectNoDifference(broadcast.op, "client-broadcast")
    expectNoDifference(broadcast.fields, [
      "data": .object(["emoji": .string("🔥")]),
      "room-id": .string("room-1"),
      "roomType": .string("chat"),
      "topic": .string("reaction"),
    ])

    let leave = InstantLiveMessage.leaveRoom(room, clientEventID: "event-leave")
    expectNoDifference(leave.op, "leave-room")
    expectNoDifference(leave.fields, ["room-id": .string("room-1")])
  }

  @Test
  func streamSubscribeUsesCurrentSeenOffsetNotInitialByteOffset() async throws {
    let reader = try InstantLiveStreamReaderState(clientID: "c", initialByteOffset: 5)
    await reader.recordSeenOffset(12)

    let message = try await reader.subscribeMessage(clientEventID: "evt-current")

    expectNoDifference(message.op, "subscribe-stream", pythonStreamReaderResumeSource)
    expectNoDifference(message.clientEventID, "evt-current", pythonStreamReaderResumeSource)
    expectNoDifference(
      message.fields,
      [
        "client-id": .string("c"),
        "offset": .number(12),
      ],
      pythonStreamReaderResumeSource
    )
  }

  @Test
  func streamSubscribeOmitsOffsetWhenZero() async throws {
    let reader = try InstantLiveStreamReaderState(clientID: "c")

    let message = try await reader.subscribeMessage(clientEventID: "evt-zero")

    expectNoDifference(message.op, "subscribe-stream", pythonStreamReaderResumeSource)
    expectNoDifference(
      message.fields,
      ["client-id": .string("c")],
      pythonStreamReaderResumeSource
    )
  }

  @Test
  func streamSubscribeAndUnsubscribeEncodeCanonicalTypeScriptShapes() throws {
    let subscribe = try InstantLiveMessage.subscribeStream(
      streamID: "stream-1",
      offset: 12,
      ruleParams: .object(["workspace": .string("shared")]),
      clientEventID: "evt-subscribe"
    )
    expectNoDifference(subscribe.op, "subscribe-stream", pythonStreamReaderResumeSource)
    expectNoDifference(subscribe.clientEventID, "evt-subscribe", pythonStreamReaderResumeSource)
    expectNoDifference(
      subscribe.fields,
      [
        "offset": .number(12),
        "rule-params": .object(["workspace": .string("shared")]),
        "stream-id": .string("stream-1"),
      ],
      pythonStreamReaderResumeSource
    )

    let unsubscribe = InstantLiveMessage.unsubscribeStream(
      subscriptionEventID: "evt-subscribe",
      clientEventID: "evt-unsubscribe"
    )
    expectNoDifference(unsubscribe.op, "unsubscribe-stream", pythonStreamReaderResumeSource)
    expectNoDifference(unsubscribe.clientEventID, "evt-unsubscribe", pythonStreamReaderResumeSource)
    expectNoDifference(
      unsubscribe.fields,
      ["subscribe-event-id": .string("evt-subscribe")],
      pythonStreamReaderResumeSource
    )
  }

  @Test
  func streamWriterMessagesAndAcknowledgementsUseCanonicalShapes() throws {
    let start = InstantLiveMessage.startStream(
      clientID: "chat-1",
      reconnectToken: "00000000-0000-0000-0000-000000000001",
      ruleParams: .object(["workspace": .string("shared")]),
      clientEventID: "event-start"
    )
    expectNoDifference(start.op, "start-stream")
    expectNoDifference(start.fields, [
      "client-id": .string("chat-1"),
      "reconnect-token": .string("00000000-0000-0000-0000-000000000001"),
      "rule-params": .object(["workspace": .string("shared")]),
    ])

    let append = InstantLiveMessage.appendStream(
      streamID: "00000000-0000-0000-0000-000000000002",
      chunks: ["hello ", "🚀"],
      offset: 0,
      done: true,
      abortReason: "complete",
      clientEventID: "event-append"
    )
    expectNoDifference(append.op, "append-stream")
    expectNoDifference(append.fields, [
      "abort-reason": .string("complete"),
      "chunks": .array([.string("hello "), .string("🚀")]),
      "done": .bool(true),
      "offset": .number(0),
      "stream-id": .string("00000000-0000-0000-0000-000000000002"),
    ])

    let startEvent = InstantLiveServerEvent(
      message: InstantLiveMessage(
        op: "start-stream-ok",
        clientEventID: "event-start",
        fields: [
          "client-id": .string("chat-1"),
          "offset": .number(4),
          "stream-id": .string("00000000-0000-0000-0000-000000000002"),
        ]
      )
    )
    expectNoDifference(
      startEvent,
      .startStreamOK(
        InstantLiveStartStreamOK(
          clientEventID: "event-start",
          streamID: "00000000-0000-0000-0000-000000000002",
          clientID: "chat-1",
          offset: 4
        )
      )
    )

    expectNoDifference(
      InstantLiveServerEvent(
        message: InstantLiveMessage(
          op: "stream-flushed",
          fields: [
            "done": .bool(true),
            "offset": .number(10),
            "stream-id": .string("00000000-0000-0000-0000-000000000002"),
          ]
        )
      ),
      .streamFlushed(
        InstantLiveStreamFlushed(
          streamID: "00000000-0000-0000-0000-000000000002",
          offset: 10,
          done: true
        )
      )
    )
    expectNoDifference(
      InstantLiveServerEvent(
        message: InstantLiveMessage(
          op: "append-failed",
          fields: ["stream-id": .string("00000000-0000-0000-0000-000000000002")]
        )
      ),
      .appendFailed(
        InstantLiveAppendFailed(streamID: "00000000-0000-0000-0000-000000000002")
      )
    )
  }

  @Test
  func streamReaderReconnectResubscribesWithCurrentOffset() async throws {
    let reader = try InstantLiveStreamReaderState(clientID: "c")
    let recorder = InstantLiveStreamMessageRecorder()
    await reader.recordSeenOffset(12)
    await reader.recordSubscriptionEventID("evt-original")

    try await reader.reconnect(clientEventID: "evt-after-reconnect") { message in
      await recorder.append(message)
    }

    let recordedMessages = await recorder.messages()
    expectNoDifference(
      recordedMessages,
      [
        InstantLiveMessage(
          op: "subscribe-stream",
          clientEventID: "evt-after-reconnect",
          fields: [
            "client-id": .string("c"),
            "offset": .number(12),
          ]
        )
      ],
      pythonStreamReaderResumeSource
    )
    let subscriptionEventID = await reader.subscriptionEventID
    expectNoDifference(
      subscriptionEventID,
      "evt-after-reconnect",
      pythonStreamReaderResumeSource
    )
  }

  @Test
  func streamReaderReconnectSurfacesResubscribeError() async throws {
    let reader = try InstantLiveStreamReaderState(clientID: "c")
    await reader.recordSubscriptionEventID("evt-original")

    do {
      try await reader.reconnect(clientEventID: "evt-after-reconnect") { _ in
        throw InstantLiveStreamTestError.pushFailed
      }
      Issue.record("Expected stream reconnect to surface the resubscribe failure.")
    } catch let error as InstantError {
      #expect(error.message.contains("push failed"), Comment(rawValue: pythonStreamReaderResumeSource))
    }

    do {
      try await reader.checkForFailure()
      Issue.record("Expected the stream reader to retain the resubscribe failure.")
    } catch let error as InstantError {
      #expect(error.message.contains("push failed"), Comment(rawValue: pythonStreamReaderResumeSource))
    }
  }

  @Test
  func streamReaderRetainsTargetedServerSubscriptionFailure() async throws {
    let reader = try InstantLiveStreamReaderState(streamID: "missing-stream")
    await reader.recordSubscriptionEventID("evt-subscribe")

    let failure = await reader.recordServerFailure(
      clientEventID: "evt-subscribe",
      message: "Validation failed for subscribe-stream: Stream is missing."
    )

    expectNoDifference(failure.operation, "subscribe to Instant stream")
    expectNoDifference(failure.serverEventID, "evt-subscribe")
    do {
      try await reader.checkForFailure()
      Issue.record("Expected the reader to retain its targeted server failure.")
    } catch let error as InstantError {
      expectNoDifference(error, failure)
    }
  }

  @Test
  func streamAppendRetryRequestsReconnectWithoutDeliveringAppend() async throws {
    let reader = try InstantLiveStreamReaderState(clientID: "c")
    await reader.recordSubscriptionEventID("evt-1")
    let event = InstantLiveServerEvent(
      message: InstantLiveMessage(
        op: "stream-append",
        clientEventID: "evt-1",
        fields: [
          "client-id": .string("c"),
          "error": .string("transient"),
          "offset": .number(12),
          "retry": .bool(true),
          "stream-id": .string("s-1"),
        ]
      )
    )
    guard case let .streamAppend(append) = event else {
      Issue.record("Expected canonical stream-append decoding.")
      return
    }

    let disposition = await reader.receive(append)

    expectNoDifference(disposition, .requestReconnect, pythonStreamAppendRetrySource)
    let deliveredAppends = await reader.deliveredAppends
    expectNoDifference(deliveredAppends, [], pythonStreamAppendRetrySource)
  }

  @Test
  func streamAppendDiscardsAlreadySeenUTF8Prefix() async throws {
    let reader = try InstantLiveStreamReaderState(clientID: "c", initialByteOffset: 5)
    await reader.recordSubscriptionEventID("evt-1")
    let append = InstantLiveStreamAppend(
      clientEventID: "evt-1",
      streamID: "s-1",
      clientID: "c",
      offset: 3,
      content: "lo 🚀"
    )

    let disposition = await reader.receive(append)
    let delivered = await reader.takeDeliveredAppend()

    expectNoDifference(
      disposition,
      .deliver(
        InstantLiveStreamAppend(
          clientEventID: "evt-1",
          streamID: "s-1",
          clientID: "c",
          offset: 5,
          content: " 🚀"
        )
      ),
      pythonStreamAppendMaterializationSource
    )
    expectNoDifference(
      delivered,
      InstantLiveStreamAppend(
        clientEventID: "evt-1",
        streamID: "s-1",
        clientID: "c",
        offset: 5,
        content: " 🚀"
      ),
      pythonStreamAppendMaterializationSource
    )

    await reader.recordSeenOffset(10)
    let nextDisposition = await reader.receive(
      InstantLiveStreamAppend(
        clientEventID: "evt-1",
        streamID: "s-1",
        clientID: "c",
        offset: 10,
        content: "!"
      )
    )
    expectNoDifference(
      nextDisposition,
      .deliver(
        InstantLiveStreamAppend(
          clientEventID: "evt-1",
          streamID: "s-1",
          clientID: "c",
          offset: 10,
          content: "!"
        )
      ),
      pythonStreamAppendMaterializationSource
    )
    await reader.recordSeenOffset(11)
    let resume = try await reader.subscribeMessage(clientEventID: "evt-resume")
    expectNoDifference(
      resume.fields,
      [
        "client-id": .string("c"),
        "offset": .number(11),
      ],
      pythonStreamAppendMaterializationSource
    )
  }

  @Test
  func streamFileFetchFailureSurfacesAfterRetryBudget() async throws {
    let reader = try InstantLiveStreamReaderState(clientID: "c")
    await reader.recordSubscriptionEventID("evt-1")

    for _ in 0..<10 {
      let disposition = await reader.recordFileFetchFailure()
      expectNoDifference(
        disposition,
        .requestReconnect,
        pythonStreamFileRetryBudgetSource
      )
    }
    let exhausted = await reader.recordFileFetchFailure()
    guard case let .failure(failure) = exhausted else {
      Issue.record("Expected the eleventh file-fetch failure to exhaust the reader retry budget.")
      return
    }
    expectNoDifference(failure.operation, "process Instant stream file retries")
    await #expect(throws: InstantError.self) {
      try await reader.checkForFailure()
    }
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
  func reactorIncomingRoomEventsDecodeCanonicalShapes() throws {
    let join = InstantLiveServerEvent(
      message: InstantLiveMessage(
        op: "join-room-ok",
        clientEventID: "event-join",
        fields: ["room-id": .string("room-1")]
      )
    )
    guard case let .joinRoomOK(joinOK) = join else {
      Issue.record("Expected join-room-ok, got \(join.op).")
      return
    }
    expectNoDifference(joinOK.roomID, "room-1", reactorIncomingRoomEventSource)
    expectNoDifference(joinOK.clientEventID, "event-join", reactorIncomingRoomEventSource)

    let sessions: [String: InstantLiveJSONValue] = [
      "session-peer": .object([
        "data": .object(["status": .string("online")]),
        "peer-id": .string("session-peer"),
        "user": .null,
      ])
    ]
    let refresh = InstantLiveServerEvent(
      message: InstantLiveMessage(
        op: "refresh-presence",
        fields: [
          "data": .object(sessions),
          "room-id": .string("room-1"),
        ]
      )
    )
    guard case let .refreshPresence(presence) = refresh else {
      Issue.record("Expected refresh-presence, got \(refresh.op).")
      return
    }
    expectNoDifference(presence.roomID, "room-1", reactorIncomingRoomEventSource)
    expectNoDifference(presence.sessions, sessions, reactorIncomingRoomEventSource)

    let edits: [InstantLiveJSONValue] = [
      .array([
        .array([.string("session-peer"), .string("data"), .string("status")]),
        .string("r"),
        .string("away"),
      ])
    ]
    let patch = InstantLiveServerEvent(
      message: InstantLiveMessage(
        op: "patch-presence",
        fields: [
          "edits": .array(edits),
          "room-id": .string("room-1"),
        ]
      )
    )
    guard case let .patchPresence(presencePatch) = patch else {
      Issue.record("Expected patch-presence, got \(patch.op).")
      return
    }
    expectNoDifference(presencePatch.edits, edits, reactorIncomingRoomEventSource)

    let envelope: InstantLiveJSONValue = .object([
      "data": .object(["emoji": .string("🔥")]),
      "peer-id": .string("session-peer"),
      "user": .null,
    ])
    let broadcast = InstantLiveServerEvent(
      message: InstantLiveMessage(
        op: "server-broadcast",
        fields: [
          "data": envelope,
          "room-id": .string("room-1"),
          "topic": .string("reaction"),
        ]
      )
    )
    guard case let .serverBroadcast(message) = broadcast else {
      Issue.record("Expected server-broadcast, got \(broadcast.op).")
      return
    }
    expectNoDifference(message.roomID, "room-1", reactorIncomingRoomEventSource)
    expectNoDifference(message.topic, "reaction", reactorIncomingRoomEventSource)
    expectNoDifference(message.envelope, envelope, reactorIncomingRoomEventSource)
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
  func runtimeLiveSessionInstallsQueryAndAppliesInitialResult() async throws {
    let serverCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_123)
    let query: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "order": .object(["createdAt": .string("asc")])
        ])
      ])
    ])
    let computation = InstantLiveJSONValue.todoJoinRowsComputation(
      entityID: "runtime-live-todo",
      text: "Arrived through the runtime event pump",
      isCompleted: true,
      createdAt: serverCreatedAt,
      processedTransactionID: "server-tx-runtime"
    )
    let initialResult = try #require(
      computation.objectValue?["instaql-result"]?.arrayValue
    )
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs),
      .addQueryOK(
        clientEventID: "event-query",
        query: query,
        result: initialResult,
        processedTransactionID: "server-tx-runtime",
      ),
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-refresh",
        websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
        persistenceURL: temporaryLiveCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let initial = try #require(await iterator.next())
    expectNoDifference(initial.values, [])

    let connected = try await runtime.connect()
    expectNoDifference(connected.state, .opened)

    let update = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(update.values),
      [
        TodoRecord(
          id: "runtime-live-todo",
          text: "Arrived through the runtime event pump",
          isCompleted: true,
          createdAt: serverCreatedAt
        )
      ]
    )
    let syncState = try await runtime.syncState()
    expectNoDifference(syncState.processedTransactionID, "server-tx-runtime")
    let sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "add-query"])
    expectNoDifference(sentMessages.last?.fields["q"], query)

    let closed = try await runtime.closeConnection()
    expectNoDifference(closed.state, .closed)
  }

  @Test
  func runtimeLiveQueryOnceOpensSessionAndWaitsForServerResult() async throws {
    let serverCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_789)
    let query: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "order": .object(["createdAt": .string("asc")])
        ])
      ])
    ])
    let computation = InstantLiveJSONValue.todoJoinRowsComputation(
      entityID: "runtime-query-once-live-todo",
      text: "Arrived through live queryOnce",
      isCompleted: false,
      createdAt: serverCreatedAt,
      processedTransactionID: "server-tx-query-once"
    )
    let initialResult = try #require(
      computation.objectValue?["instaql-result"]?.arrayValue
    )
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs),
      .addQueryOK(
        clientEventID: "event-query",
        query: query,
        result: initialResult,
        processedTransactionID: "server-tx-query-once",
      ),
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "runtime-live-query-once",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      persistenceURL: try temporaryLiveCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let emission = try await runtime.queryOnce(TodoExample.query)
    expectNoDifference(
      try TodoExample.decode(emission.values),
      [
        TodoRecord(
          id: "runtime-query-once-live-todo",
          text: "Arrived through live queryOnce",
          isCompleted: false,
          createdAt: serverCreatedAt
        )
      ]
    )

    await session.waitForSentMessageCount(3)
    let sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "add-query", "remove-query"])
    expectNoDifference(sentMessages[1].fields["q"], query)
    let syncState = try await runtime.syncState()
    expectNoDifference(syncState.processedTransactionID, "server-tx-query-once")
    let closed = try await runtime.closeConnection()
    expectNoDifference(closed.state, .closed)
  }

  @Test
  func runtimeLiveQueryOnceRevalidatesAnAlreadyObservedQuery() async throws {
    let serverCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_790)
    let query: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "order": .object(["createdAt": .string("asc")])
        ])
      ])
    ])
    let computation = InstantLiveJSONValue.todoJoinRowsComputation(
      entityID: "runtime-observed-query-once-todo",
      text: "Already materialized for the active observer",
      isCompleted: false,
      createdAt: serverCreatedAt,
      processedTransactionID: "server-tx-observed-query-once"
    )
    let initialResult = try #require(
      computation.objectValue?["instaql-result"]?.arrayValue
    )
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs),
      .addQueryOK(
        clientEventID: "event-observation",
        query: query,
        result: initialResult,
        processedTransactionID: "server-tx-observed-query-once"
      ),
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "runtime-live-observed-query-once",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      persistenceURL: try temporaryLiveCacheURL(),
      initialAttributes: TodoExample.attributes,
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let observation = await runtime.observe(TodoExample.query)
    let consumer = Task {
      var emissions: [InstantQueryEmission] = []
      for await emission in observation {
        emissions.append(emission)
      }
      return emissions
    }
    await session.waitForSentMessageCount(2)

    let oneShot = Task {
      try await runtime.queryOnce(TodoExample.query)
    }
    await session.waitForSentMessageCount(3)
    await session.enqueue(
      .addQueryExists(clientEventID: "event-query-once", query: query)
    )

    let emission = try await oneShot.value
    expectNoDifference(
      try TodoExample.decode(emission.values).map(\.text),
      ["Already materialized for the active observer"]
    )
    var sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "add-query", "add-query"])

    consumer.cancel()
    _ = await consumer.value
    await session.waitForSentMessageCount(4)
    sentMessages = await session.sentMessages()
    expectNoDifference(
      sentMessages.map(\.op),
      ["init", "add-query", "add-query", "remove-query"]
    )
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeLiveTransactOpensSessionAndSendsMutationWithoutExplicitConnect() async throws {
    let ids = InstantLiveTransportTestIDSequence(["event-init", "event-tx"])
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs)
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "runtime-live-transact-autoconnect",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      persistenceURL: try temporaryLiveCacheURL(),
      initialAttributes: TodoExample.attributes,
      makeID: { ids.next() },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    _ = try await runtime.transact(
      InstantStoreTransaction(
        id: "event-tx",
        operations: TodoExample.createOperations(
          id: "runtime-live-transact-autoconnect-todo",
          text: "Sent through live transact autoconnect",
          createdAt: InstantTimestamp(milliseconds: 1_700_000_001_000),
          transactionID: "event-tx"
        )
      )
    )

    await session.waitForSentMessageCount(2)
    let sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "transact"])
    expectNoDifference(sentMessages[1].clientEventID, "event-tx")
    let status = try await runtime.connectionStatus()
    expectNoDifference(status.transport, .webSocket)
    expectNoDifference(status.pendingMutationCount, 1)
    let closed = try await runtime.closeConnection()
    expectNoDifference(closed.state, .closed)
  }

  @Test
  func runtimeLiveTransactCommitsLocallyWhileAutomaticConnectionIsStillOpening() async throws {
    let ids = InstantLiveTransportTestIDSequence(["event-init", "event-tx"])
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs)
    ])
    let blockedTransport = InstantRuntimeBlockedLiveTransport(base: session.transport)
    var configuration = InstantRuntimeConfiguration(
      appID: "runtime-live-transact-blocked-autoconnect",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      persistenceURL: try temporaryLiveCacheURL(),
      initialAttributes: TodoExample.attributes,
      makeID: { ids.next() },
      liveTransport: blockedTransport.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    await blockedTransport.waitUntilConnectStarts()

    let transaction = InstantStoreTransaction(
      id: "event-tx",
      operations: TodoExample.createOperations(
        id: "runtime-live-transact-blocked-todo",
        text: "Committed before connectivity",
        createdAt: InstantTimestamp(milliseconds: 1_700_000_001_001),
        transactionID: "event-tx"
      )
    )
    let transactionTask = Task {
      try await runtime.transact(transaction)
    }

    var committedBeforeConnectivity = false
    for _ in 0..<100 {
      if await runtime.pendingMutations().contains(where: { $0.id == transaction.id }) {
        committedBeforeConnectivity = true
        break
      }
      try await Task.sleep(for: .milliseconds(5))
    }

    await blockedTransport.releaseConnection()
    _ = try await transactionTask.value
    #expect(committedBeforeConnectivity)
    let values = await runtime.store.materialize(TodoExample.query)
    expectNoDifference(
      try TodoExample.decode(values).map(\.text),
      ["Committed before connectivity"]
    )
    await session.waitForSentMessageCount(2)
    let sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "transact"])
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeLiveRefreshReusesInitAttributesWhenPayloadOmitsThem() async throws {
    let serverCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_456)
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs),
      .addQueryOK(clientEventID: "event-query"),
      .refreshOK(
        clientEventID: "event-refresh",
        processedTransactionID: "server-tx-refresh",
        computations: [
          .todoJoinRowsComputation(
            entityID: "runtime-refresh-todo",
            text: "Translated with init attributes",
            isCompleted: false,
            createdAt: serverCreatedAt,
            processedTransactionID: "server-tx-refresh"
          )
        ]
      ),
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-refresh-attrs",
        persistenceURL: temporaryLiveCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let initial = try #require(await iterator.next())
    expectNoDifference(initial.values, [])

    _ = try await runtime.connect()
    let update = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(update.values),
      [
        TodoRecord(
          id: "runtime-refresh-todo",
          text: "Translated with init attributes",
          isCompleted: false,
          createdAt: serverCreatedAt
        )
      ]
    )
    let syncState = try await runtime.syncState()
    expectNoDifference(syncState.processedTransactionID, "server-tx-refresh")
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeLiveSessionUsesCanonicalQueryShapeAndReferenceCountsObservers() async throws {
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init"),
      .addQueryOK(clientEventID: "event-query"),
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-query-shape",
        websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
        persistenceURL: temporaryLiveCacheURL(),
        initialAttributes: TodoProjectExample.attributes,
        liveTransport: session.transport
      )
    )
    let plan = InstantQueryPlan(
      id: "runtime-live-query-shape-a",
      namespace: TodoExample.namespace,
      filters: [
        .equals(field: "isCompleted", value: .bool(false)),
        .or([
          .like(field: "text", pattern: "A%"),
          .isNull(field: "project"),
        ]),
      ],
      order: InstantQueryOrder("createdAt", .descending),
      limit: 25,
      selectedFields: ["isCompleted", "text"],
      includes: [
        InstantQueryInclude(
          "project",
          query: InstantQueryIncludePlan(
            id: "runtime-live-query-project",
            namespace: TodoProjectExample.namespace,
            order: InstantQueryOrder("title"),
            selectedFields: ["title"]
          )
        )
      ]
    )
    let equivalentPlan = InstantQueryPlan(
      id: "runtime-live-query-shape-b",
      namespace: plan.namespace,
      filters: plan.filters,
      order: plan.order,
      limit: plan.limit,
      selectedFields: plan.selectedFields,
      includes: plan.includes ?? []
    )
    let firstObservation = await runtime.observe(plan)
    let secondObservation = await runtime.observe(equivalentPlan)
    let firstConsumer = Task {
      for await _ in firstObservation {}
    }
    let secondConsumer = Task {
      for await _ in secondObservation {}
    }

    _ = try await runtime.connect()
    let query: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "fields": .array([.string("isCompleted"), .string("text")]),
          "limit": .number(25),
          "order": .object(["createdAt": .string("desc")]),
          "where": .object([
            "and": .array([
              .object(["isCompleted": .bool(false)]),
              .object([
                "or": .array([
                  .object(["text": .object(["$like": .string("A%")])]),
                  .object(["project": .object(["$isNull": .bool(true)])]),
                ])
              ]),
            ])
          ]),
        ]),
        "project": .object([
          "$": .object([
            "fields": .array([.string("title")]),
            "order": .object(["title": .string("asc")]),
          ])
        ]),
      ])
    ])
    var sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "add-query"])
    expectNoDifference(sentMessages.last?.fields["q"], query)

    firstConsumer.cancel()
    secondConsumer.cancel()
    await firstConsumer.value
    await secondConsumer.value
    await session.waitForSentMessageCount(3)

    sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "add-query", "remove-query"])
    expectNoDifference(sentMessages.last?.fields["q"], query)
    _ = try await runtime.closeConnection()
  }

  @Test
  func liveQueryEncoderPortsWhereOperatorsAndReverseIncludes() throws {
    let plan = InstantQueryPlan(
      id: "runtime-live-query-operators",
      namespace: TodoProjectExample.namespace,
      filters: [
        .or([
          .equals(field: "title", value: .string("Launch linked todos")),
          .in(field: "id", values: [.string("project-1"), .string("project-2")]),
        ])
      ],
      order: InstantQueryOrder("title", .descending),
      offset: 1,
      limit: 10,
      selectedFields: ["title"],
      includes: [
        InstantQueryInclude(
          "todos",
          direction: .reverse,
          query: InstantQueryIncludePlan(
            id: "runtime-live-query-operators.todos",
            namespace: TodoExample.namespace,
            filters: [
              .equals(field: "isCompleted", value: .bool(false)),
              .notEquals(field: "text", value: .string("Done")),
              .greaterThan(field: "text", value: .string("A")),
              .greaterThanOrEqual(field: "text", value: .string("A")),
              .lessThan(field: "text", value: .string("Z")),
              .lessThanOrEqual(field: "text", value: .string("Z")),
              .in(field: "text", values: [.string("Wire"), .string("Review")]),
              .like(field: "text", pattern: "%wire%"),
              .iLike(field: "text", pattern: "%WIRE%"),
              .isNull(field: "project"),
              .isNotNull(field: "project"),
              .and([
                .equals(field: "isCompleted", value: .bool(false)),
                .or([
                  .like(field: "text", pattern: "Wire%"),
                  .equals(field: "project", value: .ref("project-1")),
                ]),
              ]),
            ],
            order: InstantQueryOrder("text", .ascending),
            selectedFields: ["text", "isCompleted", "project"]
          )
        )
      ]
    )

    expectNoDifference(
      try InstantLiveQueryEncoder.encode(plan),
      .object([
        "projects": .object([
          "$": .object([
            "fields": .array([.string("title")]),
            "limit": .number(10),
            "offset": .number(1),
            "order": .object(["title": .string("desc")]),
            "where": .object([
              "or": .array([
                .object(["title": .string("Launch linked todos")]),
                .object([
                  "id": .object([
                    "$in": .array([.string("project-1"), .string("project-2")])
                  ])
                ]),
              ])
            ]),
          ]),
          "todos": .object([
            "$": .object([
              "fields": .array([.string("isCompleted"), .string("project"), .string("text")]),
              "order": .object(["text": .string("asc")]),
              "where": .object([
                "and": .array([
                  .object(["isCompleted": .bool(false)]),
                  .object(["text": .object(["$ne": .string("Done")])]),
                  .object(["text": .object(["$gt": .string("A")])]),
                  .object(["text": .object(["$gte": .string("A")])]),
                  .object(["text": .object(["$lt": .string("Z")])]),
                  .object(["text": .object(["$lte": .string("Z")])]),
                  .object([
                    "text": .object([
                      "$in": .array([.string("Wire"), .string("Review")])
                    ])
                  ]),
                  .object(["text": .object(["$like": .string("%wire%")])]),
                  .object(["text": .object(["$ilike": .string("%WIRE%")])]),
                  .object(["project": .object(["$isNull": .bool(true)])]),
                  .object(["project": .object(["$isNull": .bool(false)])]),
                  .object([
                    "and": .array([
                      .object(["isCompleted": .bool(false)]),
                      .object([
                        "or": .array([
                          .object(["text": .object(["$like": .string("Wire%")])]),
                          .object(["project": .string("project-1")]),
                        ])
                      ]),
                    ])
                  ]),
                ])
              ]),
            ])
          ]),
        ])
      ])
    )
  }

  @Test
  func runtimeLiveCursorMismatchRecordsActionableConnectionError() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-cursor-error",
        persistenceURL: temporaryLiveCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: .local
      )
    )
    let plan = InstantQueryPlan(
      id: "runtime-live-cursor-error",
      namespace: TodoExample.namespace,
      order: InstantQueryOrder("createdAt"),
      after: InstantQueryCursor(
        entityID: "todo-cursor",
        sortValue: .date(Date(timeIntervalSince1970: 1_700_000_000))
      )
    )

    let observation = await runtime.observe(plan)
    var iterator = observation.makeAsyncIterator()
    _ = await iterator.next()

    let status = try await runtime.connectionStatus()
    expectNoDifference(status.state, .errored)
    #expect(status.lastErrorMessage?.contains("opaque four-element tuples") == true)
    #expect(status.lastErrorMessage?.contains("path: after") == true)
    #expect(status.lastErrorMessage?.contains("canonical Instant SDK") == true)
  }

  @Test
  func runtimeLiveQueryOncePreservesOpaqueServerPageInfoCursor() async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_123)
    let plan = InstantQueryPlan(
      id: "runtime-live-page-info",
      namespace: TodoExample.namespace,
      order: InstantQueryOrder("createdAt"),
      limit: 1
    )
    let query = try InstantLiveQueryEncoder.encode(plan)
    let cursor: [InstantLiveJSONValue] = [
      .string("todo-live-page-info"),
      .string("server-todos-created-at"),
      .number(Double(createdAt.milliseconds)),
      .number(Double(createdAt.milliseconds)),
    ]
    var result = liveReactorTodoQueryResult(
      id: "todo-live-page-info",
      text: "Preserve opaque cursor",
      createdAt: createdAt
    )
    guard case var .object(node) = result[0],
      case var .object(data)? = node["data"]
    else {
      Issue.record("Expected canonical live query result data.")
      return
    }
    data["page-info"] = .object([
      TodoExample.namespace: .object([
        "start-cursor": .array(cursor),
        "end-cursor": .array(cursor),
        "has-next-page?": .bool(true),
        "has-previous-page?": .bool(false),
      ])
    ])
    node["data"] = .object(data)
    result[0] = .object(node)
    let translated = try InstantLiveRefreshTranslator.translate(
      InstantLiveRefreshOK(
        clientEventID: nil,
        processedTransactionID: "live-page-info-translation",
        attrs: liveReactorTodoServerAttrs,
        computations: [
          .object([
            "instaql-query": query,
            "instaql-result": .array(result),
          ])
        ]
      ),
      existingAttributes: TodoExample.attributes,
      receivedAt: createdAt
    )
    let translatedPageInfo = try #require(
      translated.queryResultReplacements.first?.pageInfo
    )
    expectNoDifference(translatedPageInfo.hasNextPage, true)
    expectNoDifference(translatedPageInfo.endCursor?.entityID, "todo-live-page-info")

    let session = InstantRuntimeScriptedLiveSession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs),
      liveReactorAddQueryOK(
        query: query,
        processedTransactionID: "live-page-info-1",
        result: result
      ),
    ])
    let cacheURL = try temporaryLiveCacheURL()
    var configuration = InstantRuntimeConfiguration(
      appID: "runtime-live-page-info",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { InstantTimestamp(milliseconds: createdAt.milliseconds + 2) },
      liveTransport: session.transport
    )
    configuration.autoConnectLiveTransport = true
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    let emission = try await runtime.queryOnce(plan)
    let endCursor = try #require(emission.pageInfo?.endCursor)
    let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    let persistedResult = try #require(
      try await runtime.persistence.liveQueryResult(key: registrationKey)
    )

    expectNoDifference(emission.pageInfo?.hasNextPage, true)
    expectNoDifference(persistedResult.pageInfo, emission.pageInfo)
    expectNoDifference(endCursor.entityID, "todo-live-page-info")
    expectNoDifference(
      endCursor.sortValue,
      .date(Date(timeIntervalSince1970: Double(createdAt.milliseconds) / 1_000))
    )
    expectNoDifference(
      try InstantLiveQueryEncoder.encode(
        InstantQueryPlan(
          id: "runtime-live-page-info-next",
          namespace: TodoExample.namespace,
          order: InstantQueryOrder("createdAt"),
          limit: 1,
          after: endCursor
        )
      ),
      .object([
        TodoExample.namespace: .object([
          "$": .object([
            "after": .array(cursor),
            "limit": .number(1),
            "order": .object(["createdAt": .string("asc")]),
          ])
        ])
      ])
    )
    await session.waitForSentMessageCount(3)
    _ = try await runtime.closeConnection()

    let relaunchedSession = InstantRuntimeScriptedLiveSession(messages: [
      liveReactorInitOK(
        attrs: liveReactorTodoServerAttrs,
        sessionID: "runtime-live-page-info-relaunch"
      ),
      .addQueryExists(clientEventID: "event-query-relaunch", query: query),
    ])
    configuration.liveTransport = relaunchedSession.transport
    let relaunched = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await relaunched.connect()
    let relaunchedEmission = try await relaunched.queryOnce(plan)

    expectNoDifference(relaunchedEmission.pageInfo, emission.pageInfo)
    expectNoDifference(
      relaunchedEmission.pageInfo?.endCursor?.liveTuple,
      cursor
    )
    await relaunchedSession.waitForSentMessageCount(3)
    _ = try await relaunched.closeConnection()
  }

  @Test
  func liveQueryEncoderRoundTripsOpaqueInclusiveCursors() throws {
    let tuple: [InstantLiveJSONValue] = [
      .string("todo-live-page-info"),
      .string("server-todos-created-at"),
      .number(1_700_000_000_123),
      .number(1_700_000_000_123),
    ]
    let cursor = InstantQueryCursor(
      entityID: "todo-live-page-info",
      sortValue: .date(Date(timeIntervalSince1970: 1_700_000_000.123)),
      inclusive: true,
      liveTuple: tuple
    )
    let roundTripped = try JSONDecoder().decode(
      InstantQueryCursor.self,
      from: JSONEncoder().encode(cursor)
    )

    expectNoDifference(roundTripped, cursor)
    expectNoDifference(
      try InstantLiveQueryEncoder.encode(
        InstantQueryPlan(
          id: "runtime-live-page-info-after-inclusive",
          namespace: TodoExample.namespace,
          after: roundTripped
        )
      ),
      .object([
        TodoExample.namespace: .object([
          "$": .object([
            "after": .array(tuple),
            "afterInclusive": .bool(true),
          ])
        ])
      ])
    )
    expectNoDifference(
      try InstantLiveQueryEncoder.encode(
        InstantQueryPlan(
          id: "runtime-live-page-info-before-inclusive",
          namespace: TodoExample.namespace,
          before: roundTripped
        )
      ),
      .object([
        TodoExample.namespace: .object([
          "$": .object([
            "before": .array(tuple),
            "beforeInclusive": .bool(true),
          ])
        ])
      ])
    )
  }

  @Test
  func runtimeLiveSessionSendsAndConfirmsDurableOutboxMutation() async throws {
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-outbox-confirm",
        persistenceURL: temporaryLiveCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    let statuses = try await runtime.observeConnectionStatus()
    var statusIterator = statuses.makeAsyncIterator()
    let initialStatus = try #require(await statusIterator.next())
    expectNoDifference(initialStatus.state, .closed)
    let connectedStatus = try await runtime.connect()
    expectNoDifference(connectedStatus.state, .opened)
    let observedConnectedStatus = try #require(await statusIterator.next())
    expectNoDifference(observedConnectedStatus.state, .opened)

    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_789)
    let transaction = InstantStoreTransaction(
      id: "tx-runtime-live-confirm",
      operations: TodoExample.createOperations(
        id: "runtime-live-confirm-todo",
        text: "Send through owned live session",
        createdAt: createdAt,
        transactionID: "tx-runtime-live-confirm"
      )
    )
    _ = try await runtime.transact(transaction, createdAt: createdAt)
    let pendingStatus = try #require(await statusIterator.next())
    expectNoDifference(pendingStatus.pendingMutationCount, 1)
    await session.waitForSentMessageCount(2)

    let pending = try #require(await runtime.pendingMutations().first)
    let sentMessages = await session.sentMessages()
    let expectedSteps = try InstantLiveMutationEncoder.resolveAttributeIDs(
      in: InstantTransportMutation(pending).txSteps,
      attrs: .todoServerAttrs
    )
    let expectedMessage = try InstantLiveMessage.transact(
      expectedSteps,
      clientEventID: pending.id
    )
    expectNoDifference(sentMessages.map(\.op), ["init", "transact"])
    expectNoDifference(sentMessages.last, expectedMessage)
    let sentSteps = try #require(sentMessages.last?.fields["tx-steps"]?.arrayValue)
    expectNoDifference(
      sentSteps.compactMap { $0.arrayValue?[2].stringValue },
      [
        "server-todos-id",
        "server-todos-text",
        "server-todos-is-completed",
        "server-todos-created-at",
      ]
    )

    await session.enqueue(
      .transactOK(
        clientEventID: pending.id,
        transactionID: "server-tx-runtime-confirm"
      )
    )
    let confirmedStatus = try #require(await statusIterator.next())
    expectNoDifference(confirmedStatus.pendingMutationCount, 0)
    let remainingPending = await runtime.pendingMutations()
    let remainingOutbox = await runtime.outboxMutations()
    expectNoDifference(remainingPending, [])
    expectNoDifference(remainingOutbox, [])
    _ = try await runtime.closeConnection()
  }

  @Test
  func acceptedOptimisticMutationSurvivesRefreshUntilServerWatermarkCatchesUp() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_800)
    let query: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([:])
    ])
    let staleComputation = InstantLiveJSONValue.todoJoinRowsComputation(
      entityID: "runtime-live-watermark-todo",
      text: "Stale server value",
      isCompleted: false,
      createdAt: createdAt,
      processedTransactionID: "199"
    )
    let staleResult = try #require(
      staleComputation.objectValue?["instaql-result"]?.arrayValue
    )
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-accepted-watermark",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    _ = try #require(await iterator.next())
    _ = try await runtime.connect()
    await session.waitForSentMessageCount(2)
    await session.enqueue(
      .addQueryOK(
        clientEventID: "event-query-initial",
        query: query,
        result: staleResult,
        processedTransactionID: "100"
      )
    )
    let serverEmission = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(serverEmission.values).map(\.text),
      ["Stale server value"]
    )

    let mutationID = "tx-runtime-live-accepted-watermark"
    let optimisticAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: mutationID,
        operations: TodoExample.updateTextOperations(
          id: "runtime-live-watermark-todo",
          text: "Accepted optimistic value",
          updatedAt: optimisticAt,
          transactionID: mutationID
        )
      ),
      createdAt: optimisticAt
    )
    let optimisticEmission = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(optimisticEmission.values).map(\.text),
      ["Accepted optimistic value"]
    )
    await session.waitForSentMessageCount(3)
    await session.enqueue(
      .transactOK(clientEventID: mutationID, transactionID: "200")
    )
    _ = try #require(
      await runtime.observeConnectionStatus().first { $0.pendingMutationCount == 0 }
    )

    await session.enqueue(
      .refreshOK(
        clientEventID: "event-stale-refresh",
        processedTransactionID: "199",
        computations: [staleComputation]
      )
    )
    _ = try #require(
      await runtime.observeConnectionStatus().first { $0.processedTransactionID == "199" }
    )

    let afterStaleRefresh = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-accepted-watermark",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let staleRefreshValues = try await afterStaleRefresh.query(TodoExample.query)
    expectNoDifference(
      try TodoExample.decode(staleRefreshValues).map(\.text),
      ["Accepted optimistic value"]
    )
    let stalePersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    let staleOutbox = try await stalePersistence.loadSnapshot().outbox
    let retainedAcceptance = try #require(staleOutbox.first)
    expectNoDifference(retainedAcceptance.status, .confirmed)
    expectNoDifference(retainedAcceptance.serverTransactionID, "200")

    let caughtUpComputation = InstantLiveJSONValue.todoJoinRowsComputation(
      entityID: "runtime-live-watermark-todo",
      text: "Accepted optimistic value",
      isCompleted: false,
      createdAt: optimisticAt,
      processedTransactionID: "200"
    )
    await session.enqueue(
      .refreshOK(
        clientEventID: "event-caught-up-refresh",
        processedTransactionID: "200",
        computations: [caughtUpComputation]
      )
    )
    _ = try #require(
      await runtime.observeConnectionStatus().first { $0.processedTransactionID == "200" }
    )

    let afterCaughtUpRefresh = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-accepted-watermark",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let caughtUpValues = try await afterCaughtUpRefresh.query(TodoExample.query)
    expectNoDifference(
      try TodoExample.decode(caughtUpValues).map(\.text),
      ["Accepted optimistic value"]
    )
    let caughtUpPersistence = try SQLitePersistenceStore(fileURL: cacheURL)
    let persistedCaughtUpOutbox = try await caughtUpPersistence.loadSnapshot().outbox
    expectNoDifference(persistedCaughtUpOutbox, [])
    let caughtUpOutbox = await afterCaughtUpRefresh.outboxMutations()
    expectNoDifference(caughtUpOutbox, [])
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeLiveMutationEncodingFailureDoesNotBlockTheFollowingMutation() async throws {
    let incompleteAttrs = Array(Array<InstantLiveJSONValue>.todoServerAttrs.dropLast())
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: incompleteAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-outbox-schema-error",
        persistenceURL: temporaryLiveCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    _ = try await runtime.connect()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_790)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "a-runtime-live-schema-error",
        operations: TodoExample.createOperations(
          id: "runtime-live-schema-error-todo",
          text: "Keep pending until schema matches",
          createdAt: createdAt,
          transactionID: "a-runtime-live-schema-error"
        )
      ),
      createdAt: createdAt
    )
    let updateAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "b-runtime-live-healthy",
        operations: TodoExample.updateTextOperations(
          id: "runtime-live-schema-error-todo",
          text: "Deliver the valid update",
          updatedAt: updateAt,
          transactionID: "b-runtime-live-healthy"
        )
      ),
      createdAt: updateAt
    )
    await session.waitForSentMessageCount(2)

    let status = try await runtime.connectionStatus()
    expectNoDifference(status.state, .opened)
    let sentOps = await session.sentMessages().map(\.op)
    expectNoDifference(sentOps, ["init", "transact"])
    let outbox = await runtime.outboxMutations()
    expectNoDifference(outbox.map(\.id), [
      "a-runtime-live-schema-error",
      "b-runtime-live-healthy",
    ])
    expectNoDifference(outbox.map(\.status), [.failed, .pending])
    #expect(outbox[0].failureMessage?.contains("todos/createdAt") == true)
    let lastClientEventID = await session.sentMessages().last?.clientEventID
    expectNoDifference(lastClientEventID, "b-runtime-live-healthy")
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeLiveConnectResendsPersistedPendingMutation() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_800)
    let writer = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-outbox-relaunch",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await writer.transact(
      InstantStoreTransaction(
        id: "tx-runtime-live-relaunch",
        operations: TodoExample.createOperations(
          id: "runtime-live-relaunch-todo",
          text: "Resume durable pending mutation",
          createdAt: createdAt,
          transactionID: "tx-runtime-live-relaunch"
        )
      ),
      createdAt: createdAt
    )

    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-outbox-relaunch",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    let connected = try await runtime.connect()
    expectNoDifference(connected.pendingMutationCount, 1)
    let pending = try #require(await runtime.pendingMutations().first)
    let sentMessages = await session.sentMessages()
    expectNoDifference(sentMessages.map(\.op), ["init", "transact"])
    expectNoDifference(sentMessages.last?.clientEventID, pending.id)

    let statuses = try await runtime.observeConnectionStatus()
    var iterator = statuses.makeAsyncIterator()
    let pendingStatus = try #require(await iterator.next())
    expectNoDifference(pendingStatus.pendingMutationCount, 1)
    await session.enqueue(
      .transactOK(
        clientEventID: pending.id,
        transactionID: "server-tx-runtime-relaunch"
      )
    )
    let confirmedStatus = try #require(await iterator.next())
    expectNoDifference(confirmedStatus.pendingMutationCount, 0)
    let remaining = await runtime.outboxMutations()
    expectNoDifference(remaining, [])
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeLiveMutationErrorPersistsFailureAndRetryResends() async throws {
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init")
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-outbox-retry",
        persistenceURL: temporaryLiveCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    _ = try await runtime.connect()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_890)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-runtime-live-retry",
        operations: TodoExample.createOperations(
          id: "runtime-live-retry-todo",
          text: "Retry after permission error",
          createdAt: createdAt,
          transactionID: "tx-runtime-live-retry"
        )
      ),
      createdAt: createdAt
    )
    await session.waitForSentMessageCount(2)

    await session.enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: "tx-runtime-live-retry",
        fields: [
          "message": .string("permission denied"),
          "status": .number(403),
          "type": .string("permission-denied"),
        ]
      )
    )
    let failed = try #require(
      await runtime.observeConnectionStatus().first { $0.state == .errored }
    )
    expectNoDifference(failed.lastErrorMessage, "permission denied")
    let failedMutation = try #require(await runtime.outboxMutations().first)
    expectNoDifference(failedMutation.status, .failed)
    expectNoDifference(failedMutation.failureMessage, "permission denied")

    _ = try await runtime.retryMutation(id: failedMutation.id)
    await session.waitForSentMessageCount(3)
    let sentOps = await session.sentMessages().map(\.op)
    expectNoDifference(
      sentOps,
      ["init", "transact", "transact"]
    )
    await session.enqueue(
      .transactOK(
        clientEventID: failedMutation.id,
        transactionID: "server-tx-runtime-retry"
      )
    )
    let confirmed = try #require(
      await runtime.observeConnectionStatus().first { $0.pendingMutationCount == 0 }
    )
    expectNoDifference(confirmed.state, .opened)
    let remainingOutbox = await runtime.outboxMutations()
    expectNoDifference(remainingOutbox, [])
    _ = try await runtime.closeConnection()
  }

  @Test
  func runtimeLiveMutationErrorRefetchesActiveQueriesAndDropsRejectedOptimism() async throws {
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_891)
    let query: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "order": .object(["createdAt": .string("asc")])
        ])
      ])
    ])
    let serverComputation = InstantLiveJSONValue.todoJoinRowsComputation(
      entityID: "runtime-live-rejected-todo",
      text: "Server value",
      isCompleted: false,
      createdAt: createdAt,
      processedTransactionID: "server-tx-before-rejection"
    )
    let serverResult = try #require(
      serverComputation.objectValue?["instaql-result"]?.arrayValue
    )
    let session = InstantRuntimeScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs)
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "runtime-live-rejected-query-refresh",
        persistenceURL: temporaryLiveCacheURL(),
        initialAttributes: TodoExample.attributes,
        liveTransport: session.transport
      )
    )
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    _ = try #require(await iterator.next())
    _ = try await runtime.connect()
    await session.waitForSentMessageCount(2)
    await session.enqueue(
      .addQueryOK(
        clientEventID: "event-query-initial",
        query: query,
        result: serverResult,
        processedTransactionID: "server-tx-before-rejection"
      )
    )
    let serverEmission = try #require(await iterator.next())
    expectNoDifference(try TodoExample.decode(serverEmission.values).map(\.text), ["Server value"])

    let rejectedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-runtime-live-rejected-refresh",
        operations: TodoExample.updateTextOperations(
          id: "runtime-live-rejected-todo",
          text: "Rejected value",
          updatedAt: rejectedAt,
          transactionID: "tx-runtime-live-rejected-refresh"
        )
      ),
      createdAt: rejectedAt
    )
    let optimisticEmission = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(optimisticEmission.values).map(\.text),
      ["Rejected value"]
    )

    await session.enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: "tx-runtime-live-rejected-refresh",
        fields: [
          "message": .string("permission denied"),
          "status": .number(403),
          "type": .string("permission-denied"),
        ]
      )
    )
    _ = try #require(
      await runtime.observeConnectionStatus().first { $0.state == .errored }
    )

    await session.waitForSentMessageCount(5)
    let sentOps = await session.sentMessages().map(\.op)
    expectNoDifference(
      sentOps,
      ["init", "add-query", "transact", "remove-query", "add-query"]
    )

    await session.enqueue(
      .addQueryOK(
        clientEventID: "event-query-after-rejection",
        query: query,
        result: serverResult,
        processedTransactionID: "server-tx-after-rejection"
      )
    )
    let reconciledEmission = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(reconciledEmission.values).map(\.text),
      ["Server value"]
    )
    let pending = await runtime.pendingMutations()
    expectNoDifference(pending, [])
    let failedMutation = try #require(await runtime.outboxMutations().first)
    expectNoDifference(failedMutation.status, .failed)
    expectNoDifference(failedMutation.failureMessage, "permission denied")
    _ = try await runtime.closeConnection()
  }

  @Test
  func liveRefreshAppliesCanonicalJoinRowsThroughRuntimeObservers() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-refresh-application",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let stream = await runtime.observe(TodoExample.query)
    var iterator = stream.makeAsyncIterator()
    let initial = try #require(await iterator.next())
    expectNoDifference(initial.values, [])

    let serverCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_123)
    let refresh = InstantLiveRefreshOK(
      clientEventID: "event-refresh",
      processedTransactionID: "server-tx-100",
      attrs: .todoServerAttrs,
      computations: [
        .todoJoinRowsComputation(
          entityID: "remote-todo",
          text: "Arrived through refresh-ok",
          isCompleted: true,
          createdAt: serverCreatedAt,
          processedTransactionID: "server-tx-100"
        )
      ]
    )

    let result = try await runtime.applyLiveRefresh(
      refresh,
      receivedAt: InstantTimestamp(milliseconds: serverCreatedAt.milliseconds + 1)
    )

    expectNoDifference(result.insertedTripleCount, 4)
    expectNoDifference(result.mergedAttributeCount, 0)
    expectNoDifference(result.confirmedMutation?.id, nil)
    expectNoDifference(result.application.syncState.processedTransactionID, "server-tx-100")
    expectNoDifference(result.application.mutation.changedEntityIDs, Set(["remote-todo"]))
    expectNoDifference(
      result.transaction.operations.compactMap(\.insertedAttributeID),
      ["todos/id", "todos/text", "todos/isCompleted", "todos/createdAt"]
    )

    let update = try #require(await iterator.next())
    expectNoDifference(
      try TodoExample.decode(update.values),
      [
        TodoRecord(
          id: "remote-todo",
          text: "Arrived through refresh-ok",
          isCompleted: true,
          createdAt: serverCreatedAt
        )
      ]
    )
    let syncState = try await runtime.syncState()
    expectNoDifference(syncState.processedTransactionID, "server-tx-100")
  }

  @Test
  func liveQueryReplacementRetractsPersistedRowsAfterRelaunch() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_123)
    let query: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "where": .object(["isCompleted": .bool(false)])
        ])
      ])
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-query-result-relaunch",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { InstantTimestamp(milliseconds: createdAt.milliseconds + 2) }
      )
    )
    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "event-live-query-result-initial",
        processedTransactionID: "server-live-query-result-initial",
        attrs: .todoServerAttrs,
        computations: [
          .todoJoinRowsComputation(
            query: query,
            entityID: "persisted-live-query-todo",
            text: "Owned before relaunch",
            isCompleted: false,
            createdAt: createdAt,
            processedTransactionID: "server-live-query-result-initial"
          )
        ]
      ),
      receivedAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
    )

    let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    let persistedResult = try #require(
      try await runtime.persistence.liveQueryResult(key: registrationKey)
    )
    expectNoDifference(persistedResult.key, registrationKey)
    expectNoDifference(persistedResult.triples.count, 4)

    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-query-result-relaunch",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { InstantTimestamp(milliseconds: createdAt.milliseconds + 2) }
      )
    )
    let replacement = try await relaunched.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "event-live-query-result-empty",
        processedTransactionID: "server-live-query-result-empty",
        attrs: [],
        computations: [.todoEmptyJoinRowsComputation(query: query)]
      ),
      receivedAt: InstantTimestamp(milliseconds: createdAt.milliseconds + 2)
    )

    expectNoDifference(
      replacement.transaction.operations.compactMap(\.retractedEntityID),
      Array(repeating: "persisted-live-query-todo", count: 4)
    )
    let replacementSnapshots = try await relaunched.query(TodoExample.query)
    expectNoDifference(replacementSnapshots, [])
    let persistedReplacement = try #require(
      try await relaunched.persistence.liveQueryResult(key: registrationKey)
    )
    expectNoDifference(persistedReplacement.triples, [])

    let thirdRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-query-result-relaunch",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { InstantTimestamp(milliseconds: createdAt.milliseconds + 2) }
      )
    )
    let thirdSnapshots = try await thirdRuntime.query(TodoExample.query)
    expectNoDifference(thirdSnapshots, [])
    let thirdPersistedResult = try #require(
      try await thirdRuntime.persistence.liveQueryResult(key: registrationKey)
    )
    expectNoDifference(thirdPersistedResult.triples, [])
    let thirdSyncState = try await thirdRuntime.syncState()
    expectNoDifference(thirdSyncState.processedTransactionID, "server-live-query-result-empty")
  }

  @Test
  func duplicateCanonicalLiveComputationsUseOnlyTheFinalResult() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_321)
    let query: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "where": .object(["isCompleted": .bool(false)])
        ])
      ])
    ])
    let refresh = InstantLiveRefreshOK(
      clientEventID: "event-duplicate-canonical-query",
      processedTransactionID: "server-duplicate-canonical-query",
      attrs: .todoServerAttrs,
      computations: [
        .todoJoinRowsComputation(
          query: query,
          entityID: "duplicate-canonical-todo",
          text: "Earlier result must not leak",
          isCompleted: false,
          createdAt: createdAt,
          processedTransactionID: "server-duplicate-canonical-query"
        ),
        .todoEmptyJoinRowsComputation(query: query),
      ]
    )
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "duplicate-canonical-live-computations",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { InstantTimestamp(milliseconds: createdAt.milliseconds + 1) }
      )
    )

    let result = try await runtime.applyLiveRefresh(
      refresh,
      receivedAt: createdAt
    )

    expectNoDifference(result.insertedTripleCount, 0)
    expectNoDifference(result.transaction.operations, [])
    let snapshots = try await runtime.query(TodoExample.query)
    expectNoDifference(snapshots, [])
    let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    let persistedResult = try #require(
      try await runtime.persistence.liveQueryResult(key: registrationKey)
    )
    expectNoDifference(persistedResult.triples, [])

    let reopened = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "duplicate-canonical-live-computations",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        now: { InstantTimestamp(milliseconds: createdAt.milliseconds + 1) }
      )
    )
    let reopenedSnapshots = try await reopened.query(TodoExample.query)
    expectNoDifference(reopenedSnapshots, [])
    let reopenedPersistedResult = try #require(
      try await reopened.persistence.liveQueryResult(key: registrationKey)
    )
    expectNoDifference(reopenedPersistedResult.triples, [])
  }

  @Test
  func liveQueryReplacementRetainsRowsOwnedByAnotherPersistedQuery() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_456)
    let incompleteQuery: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "where": .object(["isCompleted": .bool(false)])
        ])
      ])
    ])
    let recentQuery: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object([
          "where": .object(["createdAt": .object(["$gte": .number(0)])])
        ])
      ])
    ])
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-query-shared-ownership",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    for (query, suffix) in [(incompleteQuery, "incomplete"), (recentQuery, "recent")] {
      _ = try await runtime.applyLiveRefresh(
        InstantLiveRefreshOK(
          clientEventID: "event-shared-\(suffix)",
          processedTransactionID: "server-shared-\(suffix)",
          attrs: .todoServerAttrs,
          computations: [
            .todoJoinRowsComputation(
              query: query,
              entityID: "shared-live-query-todo",
              text: "Owned by two queries",
              isCompleted: false,
              createdAt: createdAt,
              processedTransactionID: "server-shared-\(suffix)"
            )
          ]
        )
      )
    }

    let relaunched = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-query-shared-ownership",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let firstReplacement = try await relaunched.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "event-shared-incomplete-empty",
        processedTransactionID: "server-shared-incomplete-empty",
        attrs: [],
        computations: [.todoEmptyJoinRowsComputation(query: incompleteQuery)]
      )
    )
    expectNoDifference(firstReplacement.transaction.operations, [])
    let retainedSnapshots = try await relaunched.query(TodoExample.query)
    expectNoDifference(
      try TodoExample.decode(retainedSnapshots).map(\.id),
      ["shared-live-query-todo"]
    )

    let finalReplacement = try await relaunched.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "event-shared-recent-empty",
        processedTransactionID: "server-shared-recent-empty",
        attrs: [],
        computations: [.todoEmptyJoinRowsComputation(query: recentQuery)]
      )
    )
    expectNoDifference(finalReplacement.transaction.operations.count, 4)
    let finalSnapshots = try await relaunched.query(TodoExample.query)
    expectNoDifference(finalSnapshots, [])
  }

  @Test
  func liveQueryRetentionPreservesActiveRegistrationThenCollectsAfterUnsubscribe() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_789)
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    var configuration = InstantRuntimeConfiguration(
      appID: "live-query-active-retention",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: .local
    )
    configuration.liveQueryResultPruningPolicy = InstantLiveQueryResultPruningPolicy(
      maxEntries: 0
    )
    configuration.liveQueryResultPruningWriteInterval = 1
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    let observation = await runtime.observe(TodoExample.query)
    let consumer = Task {
      for await _ in observation {
        if Task.isCancelled { break }
      }
    }

    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "event-active-retention",
        processedTransactionID: "server-active-retention",
        attrs: .todoServerAttrs,
        computations: [
          .todoJoinRowsComputation(
            query: query,
            entityID: "active-retention-todo",
            text: "Active registration owns this row",
            isCompleted: false,
            createdAt: createdAt,
            processedTransactionID: "server-active-retention"
          )
        ]
      )
    )

    let retained = try await runtime.persistence.liveQueryResult(key: registrationKey)
    #expect(retained != nil)

    consumer.cancel()
    await consumer.value
    var removal: InstantLiveQueryResultPruningResult?
    for _ in 0..<100 {
      let result = try await runtime.pruneLiveQueryResults(
        policy: InstantLiveQueryResultPruningPolicy(maxEntries: 0),
        now: InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
      )
      if result.removedQueryKeys.contains(registrationKey) {
        removal = result
        break
      }
      await Task.yield()
    }

    let completedRemoval = try #require(removal)
    expectNoDifference(completedRemoval.removedQueryKeys, [registrationKey])
    expectNoDifference(completedRemoval.removedOrphanedTripleCount, 4)
    let collectedSnapshots = try await runtime.query(TodoExample.query)
    expectNoDifference(collectedSnapshots, [])
  }

  @Test
  func liveQueryRegistrationCannotEnterBetweenPruneSnapshotAndStoreReplacement() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_900)
    let query = try InstantLiveQueryEncoder.encode(TodoExample.query)
    let registrationKey = try InstantLiveQueryEncoder.registrationKey(for: query)
    let barrier = InstantLiveQueryPruneBarrier()
    let recorder = InstantActorHopRecorder()
    var configuration = InstantRuntimeConfiguration(
      appID: "live-query-prune-registration-serialization",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { InstantTimestamp(milliseconds: createdAt.milliseconds + 1) },
      liveTransport: .local
    )
    configuration.actorHopRecorder = recorder
    configuration.liveQueryResultPruningPolicy = InstantLiveQueryResultPruningPolicy(
      maxEntries: 0
    )
    configuration.liveQueryResultPruningWriteInterval = 100
    configuration.onLiveQueryResultPruneActiveKeysCapturedForTesting = { keys in
      await barrier.pauseAfterCapture(keys)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "event-prune-registration-race",
        processedTransactionID: "server-prune-registration-race",
        attrs: .todoServerAttrs,
        computations: [
          .todoJoinRowsComputation(
            query: query,
            entityID: "prune-registration-race-todo",
            text: "Must not emit before a racing prune finishes",
            isCompleted: false,
            createdAt: createdAt,
            processedTransactionID: "server-prune-registration-race"
          )
        ]
      ),
      receivedAt: createdAt
    )
    #expect(try await runtime.persistence.liveQueryResult(key: registrationKey) != nil)

    await barrier.arm()
    let actorHopBaseline = recorder.baseline()
    let prune = Task {
      try await runtime.pruneLiveQueryResults(
        policy: InstantLiveQueryResultPruningPolicy(maxEntries: 0),
        now: InstantTimestamp(milliseconds: createdAt.milliseconds + 1)
      )
    }
    let capturedKeys = await barrier.waitForCapture()
    expectNoDifference(capturedKeys, [])

    let observation = Task {
      await runtime.observe(TodoExample.query)
    }
    let registrationWaitedAtGate = await waitForOperationGateHopCount(
      2,
      recorder: recorder,
      since: actorHopBaseline
    )
    #expect(
      registrationWaitedAtGate,
      "The live registration must queue behind the prune operation gate."
    )
    await barrier.release()

    let pruneResult = try await prune.value
    expectNoDifference(pruneResult.removedQueryKeys, [registrationKey])
    expectNoDifference(pruneResult.removedOrphanedTripleCount, 4)
    let stream = await observation.value
    var iterator = stream.makeAsyncIterator()
    let firstEmission = try #require(await iterator.next())
    expectNoDifference(firstEmission.values, [])
    #expect(try await runtime.persistence.liveQueryResult(key: registrationKey) == nil)
  }

  @Test
  func liveQueryRetentionPrunesUnloadedResultOnConfiguredWriteCadence() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let firstTimestamp = InstantTimestamp(milliseconds: 1_700_000_001_000)
    let secondTimestamp = InstantTimestamp(milliseconds: firstTimestamp.milliseconds + 1)
    let firstQuery: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object(["where": .object(["id": .string("cadence-first")])])
      ])
    ])
    let secondQuery: InstantLiveJSONValue = .object([
      TodoExample.namespace: .object([
        "$": .object(["where": .object(["id": .string("cadence-second")])])
      ])
    ])
    var configuration = InstantRuntimeConfiguration(
      appID: "live-query-write-cadence",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes
    )
    configuration.liveQueryResultPruningPolicy = InstantLiveQueryResultPruningPolicy(
      maxEntries: 1
    )
    configuration.liveQueryResultPruningWriteInterval = 1
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    for (query, entityID, timestamp) in [
      (firstQuery, "cadence-first", firstTimestamp),
      (secondQuery, "cadence-second", secondTimestamp),
    ] {
      _ = try await runtime.applyLiveRefresh(
        InstantLiveRefreshOK(
          clientEventID: "event-\(entityID)",
          processedTransactionID: "server-\(entityID)",
          attrs: .todoServerAttrs,
          computations: [
            .todoJoinRowsComputation(
              query: query,
              entityID: entityID,
              text: entityID,
              isCompleted: false,
              createdAt: timestamp,
              processedTransactionID: "server-\(entityID)"
            )
          ]
        ),
        receivedAt: timestamp
      )
    }

    let firstKey = try InstantLiveQueryEncoder.registrationKey(for: firstQuery)
    let secondKey = try InstantLiveQueryEncoder.registrationKey(for: secondQuery)
    #expect(try await runtime.persistence.liveQueryResult(key: firstKey) == nil)
    #expect(try await runtime.persistence.liveQueryResult(key: secondKey) != nil)
    let snapshots = try await runtime.query(TodoExample.query)
    expectNoDifference(try TodoExample.decode(snapshots).map(\.id), ["cadence-second"])
  }

  @Test
  func liveQueryRetentionUsesTheDefaultSixtyFourthWriteCadence() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let baseTimestamp = InstantTimestamp(milliseconds: 1_700_000_002_000)
    var configuration = InstantRuntimeConfiguration(
      appID: "live-query-default-write-cadence",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { InstantTimestamp(milliseconds: baseTimestamp.milliseconds + 64) }
    )
    configuration.liveQueryResultPruningPolicy = InstantLiveQueryResultPruningPolicy(
      maxEntries: 63
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    var keys: [String] = []

    for index in 0..<64 {
      let entityID = String(format: "default-cadence-%02d", index)
      let timestamp = InstantTimestamp(milliseconds: baseTimestamp.milliseconds + Int64(index))
      let query: InstantLiveJSONValue = .object([
        TodoExample.namespace: .object([
          "$": .object(["where": .object(["id": .string(entityID)])])
        ])
      ])
      keys.append(try InstantLiveQueryEncoder.registrationKey(for: query))
      _ = try await runtime.applyLiveRefresh(
        InstantLiveRefreshOK(
          clientEventID: "event-\(entityID)",
          processedTransactionID: "server-\(entityID)",
          attrs: .todoServerAttrs,
          computations: [
            .todoJoinRowsComputation(
              query: query,
              entityID: entityID,
              text: entityID,
              isCompleted: false,
              createdAt: timestamp,
              processedTransactionID: "server-\(entityID)"
            )
          ]
        ),
        receivedAt: timestamp
      )
      if index == 62 {
        #expect(try await runtime.persistence.liveQueryResult(key: keys[0]) != nil)
      }
    }

    #expect(try await runtime.persistence.liveQueryResult(key: keys[0]) == nil)
    #expect(try await runtime.persistence.liveQueryResult(key: keys[63]) != nil)
    let remaining = try await TodoExample.decode(runtime.query(TodoExample.query))
    expectNoDifference(
      remaining.map(\.id),
      (1..<64).map { String(format: "default-cadence-%02d", $0) }
    )
  }

  @Test
  func liveQueryRetentionPrunesPersistedResultsDuringBootstrap() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let persistence = try SQLitePersistenceStore(fileURL: cacheURL)
    try await persistence.bootstrap()
    let olderTriples: [InstantTriple] = TodoExample.createOperations(
      id: "bootstrap-retention-older",
      text: "Collected during bootstrap",
      createdAt: InstantTimestamp(milliseconds: 1),
      transactionID: "server-bootstrap-retention-older"
    ).compactMap { operation -> InstantTriple? in
      guard case let .insert(triple) = operation else { return nil }
      return triple
    }
    let newerTriples: [InstantTriple] = TodoExample.createOperations(
      id: "bootstrap-retention-newer",
      text: "Retained during bootstrap",
      createdAt: InstantTimestamp(milliseconds: 2),
      transactionID: "server-bootstrap-retention-newer"
    ).compactMap { operation -> InstantTriple? in
      guard case let .insert(triple) = operation else { return nil }
      return triple
    }
    let older = InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(
        key: "bootstrap-retention-older",
        triples: olderTriples,
        pageInfo: nil
      ),
      updatedAt: InstantTimestamp(milliseconds: 1)
    )
    let newer = InstantPersistedLiveQueryResult(
      replacement: InstantLiveQueryResultReplacement(
        key: "bootstrap-retention-newer",
        triples: newerTriples,
        pageInfo: nil
      ),
      updatedAt: InstantTimestamp(milliseconds: 2)
    )
    let state = try await persistence.loadState()
    let didSave = try await persistence.saveLiveRefresh(
      InstantPersistenceSnapshot(
        store: InstantStoreSnapshot(
          attributes: TodoExample.attributes,
          triples: olderTriples + newerTriples
        )
      ),
      queryResults: [older, newer],
      storeChanged: true,
      outboxChanged: false,
      metadataKey: "test.live-query-result-bootstrap-pruning",
      metadataValue: "seeded",
      metadataUpdatedAt: InstantTimestamp(milliseconds: 2),
      expectedStoreRevision: state.storeRevision,
      expectedOutboxRevision: state.outboxRevision
    )
    expectNoDifference(didSave, true)

    var configuration = InstantRuntimeConfiguration(
      appID: "live-query-bootstrap-retention",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      now: { InstantTimestamp(milliseconds: 3) }
    )
    configuration.liveQueryResultPruningPolicy = InstantLiveQueryResultPruningPolicy(
      maxEntries: 1
    )
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)

    #expect(try await runtime.persistence.liveQueryResult(key: older.key) == nil)
    #expect(try await runtime.persistence.liveQueryResult(key: newer.key) != nil)
    let bootstrapSnapshots = try await runtime.query(TodoExample.query)
    expectNoDifference(
      try TodoExample.decode(bootstrapSnapshots).map(\.id),
      ["bootstrap-retention-newer"]
    )
    let independentReopen = try SQLitePersistenceStore(fileURL: cacheURL)
    try await independentReopen.bootstrap()
    let independentState = try await independentReopen.loadState()
    expectNoDifference(
      Set(independentState.snapshot.store.triples),
      Set(newerTriples)
    )
  }

  @Test
  func liveRefreshTranslatesCanonicalRelationIdentityPaths() throws {
    let translation = try InstantLiveRefreshTranslator.translate(
      InstantLiveRefreshOK(
        clientEventID: "event-recording-relation",
        processedTransactionID: "server-tx-recording-relation",
        attrs: [
          .serverAttr(
            id: "server-recording-title",
            namespace: "v3_capture_recordings",
            name: "title"
          ),
          .serverRefAttr(
            id: "server-attachment-recording",
            namespace: "v3_capture_attachments",
            name: "recording",
            reverseNamespace: "v3_capture_recordings",
            reverseName: "attachments"
          )
        ],
        computations: []
      ),
      existingAttributes: [],
      receivedAt: InstantTimestamp(milliseconds: 1_700_000_000_000)
    )

    let relation = try #require(
      translation.attributesToMerge.first {
        $0.id == "server-attachment-recording"
      }
    )
    expectNoDifference(relation.forwardIdentity, "v3_capture_attachments/recording")
    expectNoDifference(relation.reverseIdentity, "v3_capture_recordings/attachments")
    expectNoDifference(relation.linkNamespace, "v3_capture_recordings")
    expectNoDifference(
      TripleIndexes.validate(
        InstantQueryPlan(
          id: "recording-with-attachments",
          namespace: "v3_capture_recordings",
          includes: [InstantQueryInclude("attachments", direction: .reverse)]
        ),
        attributes: AttributeStore(attributes: translation.attributesToMerge)
      ),
      nil
    )
  }

  @Test
  func liveRefreshConfirmsMatchingLocalMutationAfterApplyingServerState() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let localCreatedAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let serverCreatedAt = InstantTimestamp(milliseconds: localCreatedAt.milliseconds + 50)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-refresh-confirmation",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "server-tx-local",
        operations: TodoExample.createOperations(
          id: "local-todo",
          text: "Local optimistic text",
          createdAt: localCreatedAt,
          transactionID: "server-tx-local"
        )
      ),
      createdAt: localCreatedAt
    )
    let initialPendingMutationIDs = await runtime.pendingMutations().map(\.id)
    expectNoDifference(initialPendingMutationIDs, ["server-tx-local"])

    let refresh = InstantLiveRefreshOK(
      clientEventID: "event-refresh-local",
      processedTransactionID: "server-tx-local",
      attrs: .todoServerAttrs,
      computations: [
        .todoJoinRowsComputation(
          entityID: "local-todo",
          text: "Server confirmed text",
          isCompleted: true,
          createdAt: serverCreatedAt,
          processedTransactionID: "server-tx-local"
        )
      ]
    )

    let result = try await runtime.applyLiveRefresh(
      refresh,
      receivedAt: InstantTimestamp(milliseconds: serverCreatedAt.milliseconds + 1)
    )

    expectNoDifference(result.confirmedMutation?.id, "server-tx-local")
    expectNoDifference(result.application.pendingMutationCount, 0)
    let finalPendingMutations = await runtime.pendingMutations()
    expectNoDifference(finalPendingMutations, [])
    let finalTodos = try await runtime.query(TodoExample.query)
    expectNoDifference(
      try TodoExample.decode(finalTodos),
      [
        TodoRecord(
          id: "local-todo",
          text: "Server confirmed text",
          isCompleted: true,
          createdAt: serverCreatedAt
        )
      ]
    )
  }

  @Test
  func liveRefreshRebasesRemainingOptimisticMutationAfterConfirmation() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let updatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 10)
    let serverCreatedAt = InstantTimestamp(milliseconds: createdAt.milliseconds + 20)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-refresh-rebase",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-create",
        operations: TodoExample.createOperations(
          id: "rebase-todo",
          text: "First optimistic text",
          createdAt: createdAt,
          transactionID: "tx-create"
        )
      ),
      createdAt: createdAt
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-update",
        operations: TodoExample.updateTextOperations(
          id: "rebase-todo",
          text: "Second optimistic text",
          updatedAt: updatedAt,
          transactionID: "tx-update"
        )
      ),
      createdAt: updatedAt
    )

    let refresh = InstantLiveRefreshOK(
      clientEventID: "event-refresh-rebase",
      processedTransactionID: "tx-create",
      attrs: .todoServerAttrs,
      computations: [
        .todoJoinRowsComputation(
          entityID: "rebase-todo",
          text: "Server confirmed first text",
          isCompleted: true,
          createdAt: serverCreatedAt,
          processedTransactionID: "tx-create"
        )
      ]
    )

    let result = try await runtime.applyLiveRefresh(refresh)

    expectNoDifference(result.confirmedMutation?.id, "tx-create")
    expectNoDifference(result.application.pendingMutationCount, 1)
    let pendingMutationIDs = await runtime.pendingMutations().map(\.id)
    expectNoDifference(pendingMutationIDs, ["tx-update"])
    let todoSnapshots = try await runtime.query(TodoExample.query)
    let todos = try TodoExample.decode(todoSnapshots)
    expectNoDifference(todos.map(\.text), ["Second optimistic text"])
    expectNoDifference(todos.map(\.isCompleted), [true])

    let relaunchedRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-refresh-rebase",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let relaunchedSnapshots = try await relaunchedRuntime.query(TodoExample.query)
    let relaunchedTodos = try TodoExample.decode(relaunchedSnapshots)
    expectNoDifference(relaunchedTodos.map(\.text), ["Second optimistic text"])
    let relaunchedPendingMutationIDs = await relaunchedRuntime.pendingMutations().map(\.id)
    expectNoDifference(relaunchedPendingMutationIDs, ["tx-update"])
  }

  @Test
  func emptyLiveRefreshConfirmsMatchingMutationWithoutDroppingOptimisticRows() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-refresh-empty-confirm",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-empty-confirm",
        operations: TodoExample.createOperations(
          id: "empty-confirm-todo",
          text: "Optimistic row survives",
          createdAt: createdAt,
          transactionID: "tx-empty-confirm"
        )
      ),
      createdAt: createdAt
    )

    let result = try await runtime.applyLiveRefresh(
      InstantLiveRefreshOK(
        clientEventID: "event-empty-confirm",
        processedTransactionID: "tx-empty-confirm",
        attrs: [],
        computations: []
      )
    )

    expectNoDifference(result.insertedTripleCount, 0)
    expectNoDifference(result.confirmedMutation?.id, "tx-empty-confirm")
    expectNoDifference(result.application.pendingMutationCount, 0)
    let pendingMutations = await runtime.pendingMutations()
    expectNoDifference(pendingMutations, [])
    let syncState = try await runtime.syncState()
    expectNoDifference(syncState.processedTransactionID, "tx-empty-confirm")
    let todoSnapshots = try await runtime.query(TodoExample.query)
    let todos = try TodoExample.decode(todoSnapshots)
    expectNoDifference(todos.map(\.text), ["Optimistic row survives"])
  }

  @Test
  func decodedRefreshOKJSONAppliesCanonicalJoinRows() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-refresh-json-fixture",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    let data = Data(
      """
      {
        "op": "refresh-ok",
        "client-event-id": "event-json-refresh",
        "processed-tx-id": "server-json-tx",
        "attrs": [
          {
            "id": "server-todos-id",
            "forward-identity": ["server-todos-id", "todos", "id"],
            "value-type": "blob",
            "checked-data-type": "string",
            "cardinality": "one"
          },
          {
            "id": "server-todos-text",
            "forward-identity": ["server-todos-text", "todos", "text"],
            "value-type": "blob",
            "checked-data-type": "string",
            "cardinality": "one"
          },
          {
            "id": "server-todos-is-completed",
            "forward-identity": ["server-todos-is-completed", "todos", "isCompleted"],
            "value-type": "blob",
            "checked-data-type": "boolean",
            "cardinality": "one"
          },
          {
            "id": "server-todos-created-at",
            "forward-identity": ["server-todos-created-at", "todos", "createdAt"],
            "value-type": "blob",
            "checked-data-type": "date",
            "cardinality": "one"
          },
          {
            "id": "server-todos-completed-at",
            "forward-identity": ["server-todos-completed-at", "todos", "completedAt"],
            "value-type": "blob",
            "checked-data-type": "date",
            "cardinality": "one",
            "optional?": true
          }
        ],
        "computations": [
          {
            "instaql-query": {"todos": {}},
            "instaql-result": [
              {
                "data": {
                  "datalog-result": {
                    "join-rows": [
                      [
                        ["json-todo", "server-todos-id", "json-todo", 1700000000123],
                        ["json-todo", "server-todos-text", "Decoded refresh", 1700000000123],
                        ["json-todo", "server-todos-is-completed", true, 1700000000123],
                        ["json-todo", "server-todos-created-at", 1700000000123, 1700000000123],
                        ["json-todo", "server-todos-completed-at", null, 1700000000123]
                      ]
                    ]
                  }
                },
                "child-nodes": []
              }
            ]
          }
        ]
      }
      """.utf8
    )
    let event = InstantLiveServerEvent(
      message: try JSONDecoder().decode(InstantLiveMessage.self, from: data)
    )
    guard case let .refreshOK(refreshOK) = event else {
      Issue.record("Expected decoded refresh-ok.")
      return
    }

    let result = try await runtime.applyLiveRefresh(refreshOK)

    expectNoDifference(result.insertedTripleCount, 5)
    expectNoDifference(result.application.syncState.processedTransactionID, "server-json-tx")
    let todoSnapshots = try await runtime.query(TodoExample.query)
    expectNoDifference(todoSnapshots.first?.values["completedAt"], .one(.null))
    let todos = try TodoExample.decode(todoSnapshots)
    expectNoDifference(todos.map(\.text), ["Decoded refresh"])
  }

  @Test
  func malformedLiveRefreshDoesNotCheckpointOrConfirmMutation() async throws {
    let cacheURL = try temporaryLiveCacheURL()
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_000)
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "live-refresh-malformed",
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes
      )
    )
    try await runtime.transact(
      InstantStoreTransaction(
        id: "tx-malformed",
        operations: TodoExample.createOperations(
          id: "malformed-todo",
          text: "Still pending",
          createdAt: createdAt,
          transactionID: "tx-malformed"
        )
      ),
      createdAt: createdAt
    )

    do {
      _ = try await runtime.applyLiveRefresh(
        InstantLiveRefreshOK(
          clientEventID: "event-malformed",
          processedTransactionID: "tx-malformed",
          attrs: .todoServerAttrs,
          computations: [
            .object([
              "instaql-query": .object([TodoExample.namespace: .object([:])]),
              "instaql-result": .object([:]),
            ])
          ]
        )
      )
      Issue.record("Expected malformed refresh-ok to fail before checkpointing.")
    } catch let error as InstantError {
      expectNoDifference(error.code, .decodeFailed)
    }

    let pendingMutationIDs = await runtime.pendingMutations().map(\.id)
    expectNoDifference(pendingMutationIDs, ["tx-malformed"])
    let syncState = try await runtime.syncState()
    expectNoDifference(syncState.processedTransactionID, nil)
    let todoSnapshots = try await runtime.query(TodoExample.query)
    let todos = try TodoExample.decode(todoSnapshots)
    expectNoDifference(todos.map(\.text), ["Still pending"])
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
  func liveSessionValidationAppliesExternalRefreshEntityIDToRuntime() async throws {
    let entityID = "typescript-live-boundary-test"
    let createdAt = InstantTimestamp(milliseconds: 1_700_000_000_123)
    let ids = InstantLiveTransportTestIDSequence(["event-init", "event-query"])
    let session = InstantScriptedLiveSession(messages: [
      .initOK(clientEventID: "event-init", attrs: .todoServerAttrs),
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
          .todoJoinRowsComputation(
            entityID: entityID,
            text: "Arrived from TypeScript boundary",
            isCompleted: false,
            createdAt: createdAt,
            processedTransactionID: "server-tx-1"
          )
        ]
      ),
    ])
    let cacheURL = try temporaryLiveCacheURL()

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
      applyRefreshesToRuntime: true,
      runtimePersistenceURL: cacheURL,
      liveTransport: session.transport,
      proofLevel: "live-websocket-observe",
      timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      makeID: { ids.next() },
      runtimeProjection: { runtime in
        let todos = try await TodoExample.decode(runtime.query(TodoExample.query))
        return LiveSessionRuntimeProjection(
          cachedEntityIDs: todos.map(\.id),
          cachedTodoTexts: todos.map(\.text),
          observedSnapshot: .object([
            "id": .string(entityID),
            "text": .string("Arrived from TypeScript boundary"),
          ])
        )
      },
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
    expectNoDifference(finalDetails.runtimeCachePath, cacheURL.path)
    expectNoDifference(finalDetails.appliedRefreshCount, 1)
    expectNoDifference(finalDetails.appliedRefreshTransactionIDs, ["server-tx-1"])
    expectNoDifference(finalDetails.appliedInsertedTripleCount, 4)
    expectNoDifference(finalDetails.cachedEntityIDs, [entityID])
    expectNoDifference(finalDetails.cachedTodoTexts, ["Arrived from TypeScript boundary"])
    expectNoDifference(
      finalDetails.observedSnapshot,
      .object([
        "id": .string(entityID),
        "text": .string("Arrived from TypeScript boundary"),
      ])
    )
    expectNoDifference(finalDetails.pendingMutationCount, 0)
    expectNoDifference(finalDetails.proofLevel, "live-websocket-observe")
  }

  @Test
  func liveSessionValidationStreamsEvidenceRowsWhenRecorded() async throws {
    let ids = InstantLiveTransportTestIDSequence(["event-init", "event-query"])
    let recorder = InstantLiveEvidenceRecorder()

    let result = try await InstantSwiftDataLiveSessionValidation.run(
      appID: "live-streaming-test",
      websocketURI: try #require(URL(string: "wss://ws.example.test/runtime/session")),
      timestamp: { InstantTimestamp(milliseconds: 1_700_000_000_000) },
      makeID: { ids.next() },
      onEvidence: { row in
        recorder.append(row)
      }
    )

    let streamedRows = recorder.rows()
    expectNoDifference(streamedRows.map(\.event), result.evidence.map(\.event))
    expectNoDifference(streamedRows.map(\.details.sentOps), result.evidence.map(\.details.sentOps))
    expectNoDifference(
      streamedRows.map(\.details.receivedOps),
      result.evidence.map(\.details.receivedOps)
    )
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
          value: .lookupRef(
            attributeID: "todos/id",
            value: .string("seed-todo")
          )
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
  func liveTransactionPreservesTwoElementJSONArrayValues() throws {
    let playerIDs: InstantTransportValue = .array([
      .string("2fe78833-f4f7-453d-98b3-21663443b405"),
      .string("c746147b-923d-498f-b24b-f95b080fa57e"),
    ])

    expectNoDifference(
      try InstantLiveMutationEncoder.resolveAttributeIDs(
        in: [
          .addTriple(
            entity: .id("game-1"),
            attributeID: "todos/text",
            value: playerIDs
          )
        ],
        attrs: .todoServerAttrs
      ),
      [
        .addTriple(
          entity: .id("game-1"),
          attributeID: "server-todos-text",
          value: playerIDs
        )
      ]
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

private final class InstantLiveEvidenceRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var recordedRows: [ValidationEvidenceRow<LiveSessionValidationDetails>] = []

  func append(_ row: ValidationEvidenceRow<LiveSessionValidationDetails>) {
    lock.lock()
    defer { lock.unlock() }
    recordedRows.append(row)
  }

  func rows() -> [ValidationEvidenceRow<LiveSessionValidationDetails>] {
    lock.lock()
    defer { lock.unlock() }
    return recordedRows
  }
}

private actor InstantLiveQueryPruneBarrier {
  private var isArmed = false
  private var capturedKeys: Set<String>?
  private var captureWaiter: CheckedContinuation<Set<String>, Never>?
  private var releaseWaiter: CheckedContinuation<Void, Never>?

  func arm() {
    isArmed = true
  }

  func pauseAfterCapture(_ keys: Set<String>) async {
    guard isArmed else { return }
    capturedKeys = keys
    captureWaiter?.resume(returning: keys)
    captureWaiter = nil
    await withCheckedContinuation { continuation in
      releaseWaiter = continuation
    }
  }

  func waitForCapture() async -> Set<String> {
    if let capturedKeys { return capturedKeys }
    return await withCheckedContinuation { continuation in
      captureWaiter = continuation
    }
  }

  func release() {
    isArmed = false
    releaseWaiter?.resume()
    releaseWaiter = nil
  }
}

private func waitForOperationGateHopCount(
  _ count: Int,
  recorder: InstantActorHopRecorder,
  since baseline: InstantActorHopBaseline
) async -> Bool {
  for _ in 0..<1_000 {
    if recorder.summary(since: baseline).breakdown["operation-gate", default: 0] >= count {
      return true
    }
    await Task.yield()
  }
  return recorder.summary(since: baseline).breakdown["operation-gate", default: 0] >= count
}

private func temporaryLiveCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantLiveTransportTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
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

private actor InstantRuntimeScriptedLiveSession {
  private struct SentWaiter {
    var count: Int
    var continuation: CheckedContinuation<Void, Never>
  }

  private var messages: [InstantLiveMessage]
  private var sent: [InstantLiveMessage] = []
  private var sentWaiters: [SentWaiter] = []
  private var receiveContinuation: CheckedContinuation<InstantLiveMessage, Error>?
  private var isClosed = false

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
        close: {
          await self.close()
        }
      )
    }
  }

  func sentMessages() -> [InstantLiveMessage] {
    sent
  }

  func waitForSentMessageCount(_ count: Int) async {
    guard sent.count < count else { return }
    await withCheckedContinuation { continuation in
      sentWaiters.append(SentWaiter(count: count, continuation: continuation))
    }
  }

  func enqueue(_ message: InstantLiveMessage) {
    if let receiveContinuation {
      self.receiveContinuation = nil
      receiveContinuation.resume(returning: message)
    } else if !isClosed {
      messages.append(message)
    }
  }

  private func send(_ message: InstantLiveMessage) {
    sent.append(message)
    var pending: [SentWaiter] = []
    for waiter in sentWaiters {
      if sent.count >= waiter.count {
        waiter.continuation.resume()
      } else {
        pending.append(waiter)
      }
    }
    sentWaiters = pending
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

private actor InstantRuntimeBlockedLiveTransport {
  private let base: InstantLiveTransportClient
  private var didStartConnecting = false
  private var isReleased = false
  private var releaseContinuation: CheckedContinuation<Void, Never>?

  init(base: InstantLiveTransportClient) {
    self.base = base
  }

  nonisolated var transport: InstantLiveTransportClient {
    InstantLiveTransportClient { request in
      await self.waitForRelease()
      return try await self.base.connect(request)
    }
  }

  func waitUntilConnectStarts() async {
    while !didStartConnecting {
      await Task.yield()
    }
  }

  func releaseConnection() {
    isReleased = true
    releaseContinuation?.resume()
    releaseContinuation = nil
  }

  private func waitForRelease() async {
    didStartConnecting = true
    guard !isReleased else { return }
    await withCheckedContinuation { continuation in
      releaseContinuation = continuation
    }
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

  static func addQueryOK(
    clientEventID: String,
    query: InstantLiveJSONValue = .object([TodoExample.namespace: .object([:])]),
    result: [InstantLiveJSONValue] = [],
    processedTransactionID: String? = nil
  ) -> Self {
    var fields: [String: InstantLiveJSONValue] = [
      "q": query,
      "result": .array(result),
    ]
    if let processedTransactionID {
      fields["processed-tx-id"] = .string(processedTransactionID)
    }
    return Self(
      op: "add-query-ok",
      clientEventID: clientEventID,
      fields: fields
    )
  }

  static func addQueryExists(
    clientEventID: String,
    query: InstantLiveJSONValue
  ) -> Self {
    Self(
      op: "add-query-exists",
      clientEventID: clientEventID,
      fields: ["q": query]
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
    attrs: [InstantLiveJSONValue] = [],
    computations: [InstantLiveJSONValue] = []
  ) -> Self {
    Self(
      op: "refresh-ok",
      clientEventID: clientEventID,
      fields: [
        "attrs": .array(attrs),
        "computations": .array(computations),
        "processed-tx-id": .string(processedTransactionID),
      ]
    )
  }
}

private extension InstantTripleOperation {
  var insertedAttributeID: String? {
    guard case let .insert(triple) = self else { return nil }
    return triple.attributeID
  }

  var retractedEntityID: String? {
    guard case let .retract(triple) = self else { return nil }
    return triple.entityID
  }
}

private extension Array where Element == InstantLiveJSONValue {
  static var todoServerAttrs: [InstantLiveJSONValue] {
    [
      .serverAttr(id: "server-todos-id", namespace: "todos", name: "id"),
      .serverAttr(id: "server-todos-text", namespace: "todos", name: "text"),
      .serverAttr(id: "server-todos-is-completed", namespace: "todos", name: "isCompleted"),
      .serverAttr(id: "server-todos-created-at", namespace: "todos", name: "createdAt"),
    ]
  }
}

private extension InstantLiveJSONValue {
  static func todoJoinRowsComputation(
    query: InstantLiveJSONValue? = nil,
    entityID: String,
    text: String,
    isCompleted: Bool,
    createdAt: InstantTimestamp,
    processedTransactionID: String
  ) -> Self {
    .object([
      "instaql-query": query ?? .object([TodoExample.namespace: .object([:])]),
      "instaql-result": .array([
        .object([
          "data": .object([
            "datalog-result": .object([
              "join-rows": .array([
                .array([
                  .array([
                    .string(entityID),
                    .string("server-todos-id"),
                    .string(entityID),
                    .number(Double(createdAt.milliseconds)),
                  ]),
                  .array([
                    .string(entityID),
                    .string("server-todos-text"),
                    .string(text),
                    .number(Double(createdAt.milliseconds)),
                  ]),
                  .array([
                    .string(entityID),
                    .string("server-todos-is-completed"),
                    .bool(isCompleted),
                    .number(Double(createdAt.milliseconds)),
                  ]),
                  .array([
                    .string(entityID),
                    .string("server-todos-created-at"),
                    .number(Double(createdAt.milliseconds)),
                    .number(Double(createdAt.milliseconds)),
                  ]),
                ])
              ])
            ])
          ]),
          "child-nodes": .array([]),
        ])
      ]),
      "processed-tx-id": .string(processedTransactionID),
    ])
  }

  static func todoEmptyJoinRowsComputation(query: InstantLiveJSONValue) -> Self {
    .object([
      "instaql-query": query,
      "instaql-result": .array([
        .object([
          "data": .object([
            "datalog-result": .object([
              "join-rows": .array([])
            ])
          ]),
          "child-nodes": .array([]),
        ])
      ]),
    ])
  }

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

  static func serverRefAttr(
    id: String,
    namespace: String,
    name: String,
    reverseNamespace: String,
    reverseName: String
  ) -> Self {
    .object([
      "id": .string(id),
      "value-type": .string("ref"),
      "cardinality": .string("one"),
      "forward-identity": .array([
        .string("forward-identity-\(id)"),
        .string(namespace),
        .string(name),
      ]),
      "reverse-identity": .array([
        .string("reverse-identity-\(id)"),
        .string(reverseNamespace),
        .string(reverseName),
      ]),
    ])
  }
}

private actor InstantLiveStreamMessageRecorder {
  private var recordedMessages: [InstantLiveMessage] = []

  func append(_ message: InstantLiveMessage) {
    recordedMessages.append(message)
  }

  func messages() -> [InstantLiveMessage] {
    recordedMessages
  }
}

private enum InstantLiveStreamTestError: LocalizedError {
  case pushFailed

  var errorDescription: String? {
    "push failed"
  }
}
