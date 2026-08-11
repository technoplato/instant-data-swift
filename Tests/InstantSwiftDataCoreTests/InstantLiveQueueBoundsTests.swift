import CustomDump
import Foundation
import SQLite3
import Testing

@testable import InstantSwiftDataCore

@Suite(.serialized)
struct InstantLiveQueueBoundsTests {
  @Test
  func disconnectedStreamAppendIsReplayedFromDurableSQLiteOnReconnect() async throws {
    let cacheURL = try liveQueueTemporaryCacheURL()
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "writer-online")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "writer-reconnected")
    ])
    let reconnectGate = LiveQueueOneShotGate()
    let transport = LiveQueueReconnectGateTransport(
      first: firstSession,
      second: secondSession,
      reconnectGate: reconnectGate
    )
    let replayCompleted = LiveQueueReplayCompletionProbe()
    var configuration = InstantRuntimeConfiguration(
      appID: "live-queue-disconnected-replay",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.onLiveStreamWriterReplayCompletedForTesting = { streamID in
      await replayCompleted.record(streamID: streamID)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.signInAsGuest()
    _ = try await liveQueueWithTimeout("connect the initial stream writer") {
      try await runtime.connect()
    }

    let streamID = "00000000-0000-0000-0000-00000000d101"
    let metadata = try await liveQueueCreateWriter(
      runtime: runtime,
      session: firstSession,
      clientID: "durable-disconnected-writer",
      streamID: streamID,
      expectedSentMessageCount: 2
    )

    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop stream writer before durable append",
        message: "The scripted first connection ended.",
        recovery: "Reconnect and replay the durable SQLite tail."
      )
    )
    try await liveQueueWait("wait for reconnect before session installation") {
      reconnectGate.didEnter
    }

    let append = try await liveQueueWithTimeout("persist the disconnected stream append") {
      try await runtime.appendStreamContent(
        streamID: metadata.id,
        content: "durable while disconnected",
        expectedOffset: 0
      )
    }
    expectNoDifference(append.offset, 0, liveQueueStreamSource)
    expectNoDifference(append.chunk.content, "durable while disconnected", liveQueueStreamSource)
    let localRead = try await runtime.streamContent(streamID: metadata.id)
    expectNoDifference(localRead.content, "durable while disconnected", liveQueueStreamSource)
    expectNoDifference(await secondSession.sentMessages(), [], liveQueueStreamSource)

    reconnectGate.release()
    try await liveQueueWaitForSentMessages(
      2,
      in: secondSession,
      operation: "wait for the reconnected stream handshake"
    )
    let reconnectStart = try #require(await secondSession.sentMessages().last)
    expectNoDifference(reconnectStart.op, "start-stream", liveQueueStreamSource)
    await secondSession.enqueue(
      liveQueueStartStreamOK(
        replyingTo: reconnectStart,
        clientID: metadata.clientID,
        streamID: metadata.id,
        offset: 0
      )
    )
    try await liveQueueWaitForSentMessages(
      3,
      in: secondSession,
      operation: "wait for the durable disconnected append replay"
    )
    try await liveQueueWait("wait for exact disconnected replay completion") {
      await replayCompleted.count(streamID: metadata.id) == 1
    }

    let replay = try #require(await secondSession.sentMessages().last)
    expectNoDifference(replay.op, "append-stream", liveQueueStreamSource)
    expectNoDifference(
      replay.fields,
      [
        "chunks": .array([.string("durable while disconnected")]),
        "done": .bool(false),
        "offset": .number(0),
        "stream-id": .string(metadata.id),
      ], liveQueueStreamSource)
    let replayMetrics = try #require(
      await runtime.liveStreamWriterReplayMetricsForTesting(streamID: metadata.id)
    )
    expectNoDifference(replayMetrics.residentFragmentCount, 0, liveQueueStreamSource)
    expectNoDifference(replayMetrics.residentRawPayloadByteCount, 0, liveQueueStreamSource)
    expectNoDifference(replayMetrics.residentEncodedBodyByteCount, 0, liveQueueStreamSource)

    _ = try await liveQueueWithTimeout("close the disconnected replay runtime") {
      try await runtime.closeConnection()
    }
    try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
  }

  @Test
  func tenThousandDurableStreamFragmentsReplayWithinEveryPageAndReleaseResidentPayload()
    async throws
  {
    let cacheURL = try liveQueueTemporaryCacheURL()
    let appID = "live-queue-ten-thousand-fragments"
    let clientID = "bounded-replay-writer"
    let streamID = "00000000-0000-0000-0000-00000000d201"
    let setupSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "writer-setup")
    ])
    let setupRuntime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: appID,
        persistenceURL: cacheURL,
        initialAttributes: TodoExample.attributes,
        liveTransport: setupSession.transport
      )
    )
    let auth = try await setupRuntime.signInAsGuest()
    _ = try await liveQueueWithTimeout("connect the durable replay setup runtime") {
      try await setupRuntime.connect()
    }
    _ = try await liveQueueCreateWriter(
      runtime: setupRuntime,
      session: setupSession,
      clientID: clientID,
      streamID: streamID,
      expectedSentMessageCount: 2
    )
    _ = try await liveQueueWithTimeout("close the durable replay setup runtime") {
      try await setupRuntime.closeConnection()
    }

    let fragmentCount = 10_000
    let fragment = String(repeating: "x", count: 4_096)
    try liveQueueSeedStreamFragments(
      fileURL: cacheURL,
      appID: appID,
      streamID: streamID,
      userID: auth.userID,
      count: fragmentCount,
      content: fragment
    )

    let replaySession = LiveQueueCountingStreamSession(
      clientID: clientID,
      streamID: streamID,
      serverOffset: 0
    )
    let replayCompleted = LiveQueueReplayCompletionProbe()
    var configuration = InstantRuntimeConfiguration(
      appID: appID,
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: replaySession.transport
    )
    configuration.onLiveStreamWriterReplayCompletedForTesting = { replayedStreamID in
      await replayCompleted.record(streamID: replayedStreamID)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await liveQueueWithTimeout("replay ten thousand durable stream fragments") {
      try await runtime.connect()
    }

    let wire = await replaySession.snapshot()
    expectNoDifference(wire.startStreamCount, 1, liveQueueStreamSource)
    expectNoDifference(wire.appendStreamCount, fragmentCount, liveQueueStreamSource)
    expectNoDifference(wire.firstUnexpectedOffset, nil, liveQueueStreamSource)
    expectNoDifference(
      wire.finalOffset,
      Int64(fragmentCount * fragment.utf8.count),
      liveQueueStreamSource
    )
    expectNoDifference(await replayCompleted.count(streamID: streamID), 1, liveQueueStreamSource)

    let metrics = try #require(
      await runtime.liveStreamWriterReplayMetricsForTesting(streamID: streamID)
    )
    expectNoDifference(metrics.selectedFragmentCount, fragmentCount, liveQueueStreamSource)
    expectNoDifference(metrics.pageCount, 40, liveQueueStreamSource)
    expectNoDifference(
      metrics.maximumPageFragmentCount,
      InstantLiveStreamReplayLimits.maximumFragmentCountPerPage,
      liveQueueStreamSource
    )
    #expect(metrics.maximumPageFragmentCount <= 256)
    expectNoDifference(
      metrics.maximumPageRawPayloadByteCount,
      1_048_576,
      liveQueueStreamSource
    )
    #expect(
      metrics.maximumPageRawPayloadByteCount
        <= InstantLiveStreamReplayLimits.maximumRawPayloadByteCountPerPage
    )
    #expect(
      metrics.maximumPageEncodedBodyByteCount
        <= InstantLiveStreamReplayLimits.maximumEncodedBodyByteCountPerPage
    )
    #expect(metrics.maximumPageEncodedBodyByteCount > 1_048_576)
    expectNoDifference(metrics.residentFragmentCount, 0, liveQueueStreamSource)
    expectNoDifference(metrics.residentRawPayloadByteCount, 0, liveQueueStreamSource)
    expectNoDifference(metrics.residentEncodedBodyByteCount, 0, liveQueueStreamSource)

    _ = try await liveQueueWithTimeout("close the bounded durable replay runtime") {
      try await runtime.closeConnection()
    }
    try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
  }

  @Test
  func reconnectHandshakeReentrancyCannotOverwriteConcurrentDurableAppend() async throws {
    let cacheURL = try liveQueueTemporaryCacheURL()
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "writer-generation-one")
    ])
    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "writer-generation-two")
    ])
    let thirdSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "writer-generation-three")
    ])
    let transport = LiveReactorParityTransport(sessions: [
      firstSession, secondSession, thirdSession,
    ])
    let replayCompleted = LiveQueueReplayCompletionProbe()
    var configuration = InstantRuntimeConfiguration(
      appID: "live-queue-reentrant-handshake",
      persistenceURL: cacheURL,
      initialAttributes: TodoExample.attributes,
      liveTransport: transport.transport
    )
    configuration.liveReconnectSleep = { _ in }
    configuration.onLiveStreamWriterReplayCompletedForTesting = { streamID in
      await replayCompleted.record(streamID: streamID)
    }
    let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
    _ = try await runtime.signInAsGuest()
    _ = try await liveQueueWithTimeout("connect the reentrant writer") {
      try await runtime.connect()
    }
    let metadata = try await liveQueueCreateWriter(
      runtime: runtime,
      session: firstSession,
      clientID: "reentrant-writer",
      streamID: "00000000-0000-0000-0000-00000000d301",
      expectedSentMessageCount: 2
    )

    await firstSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop writer before reentrant handshake",
        message: "The scripted first writer connection ended.",
        recovery: "Reconnect the durable writer."
      )
    )
    try await liveQueueWait("wait for the second writer connection") {
      await transport.connectionRequests().count == 2
    }
    try await liveQueueWaitForSentMessages(
      2,
      in: secondSession,
      operation: "wait for the blocked second start-stream handshake"
    )
    let secondStart = try #require(await secondSession.sentMessages().last)
    expectNoDifference(secondStart.op, "start-stream", liveQueueStreamSource)

    let concurrentAppend = try await liveQueueWithTimeout(
      "persist an append while start-stream acknowledgement is suspended"
    ) {
      try await runtime.appendStreamContent(
        streamID: metadata.id,
        content: "append acquired during reconnect",
        expectedOffset: 0
      )
    }
    expectNoDifference(concurrentAppend.offset, 0, liveQueueStreamSource)
    await secondSession.enqueue(
      liveQueueStartStreamOK(
        replyingTo: secondStart,
        clientID: metadata.clientID,
        streamID: metadata.id,
        offset: 0
      )
    )
    try await liveQueueWaitForSentMessages(
      3,
      in: secondSession,
      operation: "wait for the handshake-generation append send"
    )
    try await liveQueueWait("wait for the second writer replay to finish") {
      await replayCompleted.count(streamID: metadata.id) == 1
    }
    expectNoDifference(
      await secondSession.sentMessages().filter { $0.op == "append-stream" }.count,
      1,
      liveQueueStreamSource
    )

    await secondSession.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop writer after reentrant handshake",
        message: "The scripted second writer connection ended.",
        recovery: "Reconnect again and prove the concurrent append was not overwritten."
      )
    )
    try await liveQueueWait("wait for the third writer connection") {
      await transport.connectionRequests().count == 3
    }
    try await liveQueueWaitForSentMessages(
      2,
      in: thirdSession,
      operation: "wait for the third start-stream handshake"
    )
    let thirdStart = try #require(await thirdSession.sentMessages().last)
    await thirdSession.enqueue(
      liveQueueStartStreamOK(
        replyingTo: thirdStart,
        clientID: metadata.clientID,
        streamID: metadata.id,
        offset: 0
      )
    )
    try await liveQueueWaitForSentMessages(
      3,
      in: thirdSession,
      operation: "wait for the non-overwritten durable append replay"
    )
    try await liveQueueWait("wait for the third writer replay to finish") {
      await replayCompleted.count(streamID: metadata.id) == 2
    }
    expectNoDifference(
      await thirdSession.sentMessages().filter { $0.op == "append-stream" }.count,
      1,
      liveQueueStreamSource
    )

    let replay = try #require(await thirdSession.sentMessages().last)
    expectNoDifference(replay.op, "append-stream", liveQueueStreamSource)
    expectNoDifference(
      replay.fields,
      [
        "chunks": .array([.string("append acquired during reconnect")]),
        "done": .bool(false),
        "offset": .number(0),
        "stream-id": .string(metadata.id),
      ], liveQueueStreamSource)
    let localRead = try await runtime.streamContent(streamID: metadata.id)
    expectNoDifference(localRead.content, "append acquired during reconnect", liveQueueStreamSource)

    _ = try await liveQueueWithTimeout("close the reentrant writer runtime") {
      try await runtime.closeConnection()
    }
    try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
  }

  @Test
  func roomBroadcastQueuePreservesFIFOAndRejectsNewestAtEveryExactBoundWithoutSideEffects()
    async throws
  {
    let defaultLimits = InstantLiveRoomBroadcastQueueLimits()
    expectNoDifference(defaultLimits.maximumEncodedBytesPerMessage, 262_144)
    try await liveQueueAssertRoomFIFOWhileFirstSendIsBlocked()
    try await liveQueueAssertRoomCountBound()
    try await liveQueueAssertRoomGlobalCountBound()
    try await liveQueueAssertRoomSingleMessageByteBound()
    try await liveQueueAssertRoomByteBound()
    try await liveQueueAssertRoomGlobalByteBound()
  }
}

private func liveQueueAssertRoomFIFOWhileFirstSendIsBlocked() async throws {
  let cacheURL = try liveQueueTemporaryCacheURL()
  let room = InstantRoomHandle(type: "chat", id: "room-fifo")
  let session = LiveReactorParitySession(messages: [
    liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "room-fifo-session")
  ])
  let firstSendGate = LiveQueueOneShotGate()
  defer { firstSendGate.release() }
  let wire = LiveQueueRoomWireProbe(blockedLabel: "A", gate: firstSendGate)
  let publicationProbe = LiveQueueRoomPublicationProbe()
  let transport = session.transport.mapSessions { socket in
    socket.forwarding(
      send: { message in
        if let label = liveQueueRoomPayloadLabel(message) {
          await wire.started(label)
          if await wire.shouldBlock(label) {
            try await firstSendGate.wait()
          }
        }
        try await socket.send(message)
        if let label = liveQueueRoomPayloadLabel(message) {
          await wire.completed(label)
        }
      },
      receive: socket.receive,
      close: socket.close
    )
  }
  var configuration = InstantRuntimeConfiguration(
    appID: "live-queue-room-fifo",
    persistenceURL: cacheURL,
    initialAttributes: TodoExample.attributes,
    liveTransport: transport
  )
  configuration.liveRoomBroadcastQueueLimits = InstantLiveRoomBroadcastQueueLimits(
    maximumMessageCountPerRoom: 8,
    maximumMessageCountGlobally: 32,
    maximumEncodedBytesPerMessage: 262_144,
    maximumEncodedBytesPerRoom: 1_048_576,
    maximumEncodedBytesGlobally: 8_388_608
  )
  configuration.onRoomTopicSnapshotPublishedForTesting = { room, topic in
    await publicationProbe.record(room: room, topic: topic)
  }
  let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
  _ = try await liveQueueWithTimeout("connect the FIFO room runtime") {
    try await runtime.connect()
  }
  _ = try await runtime.joinRoom(room)
  try await liveQueueWaitForSentMessages(
    2,
    in: session,
    operation: "wait for the FIFO room join"
  )
  let roomObservation = try await runtime.observeRoomTopic(room: room, topic: "letters")

  for label in ["A", "B", "C"] {
    _ = try await runtime.publishTopicMessage(
      room: room,
      topic: "letters",
      userID: "fifo-user",
      payload: liveQueueRoomPayload(label)
    )
  }
  await session.enqueue(
    InstantLiveMessage(op: "join-room-ok", fields: ["room-id": .string(room.id)])
  )
  try await liveQueueWait("wait for room broadcast A to enter the blocked wire send") {
    firstSendGate.didEnter
  }
  expectNoDifference(await wire.startedLabels(), ["A"], liveQueueRoomSource)

  let publishD = Task {
    try await runtime.publishTopicMessage(
      room: room,
      topic: "letters",
      userID: "fifo-user",
      payload: liveQueueRoomPayload("D")
    )
  }
  defer {
    publishD.cancel()
  }
  try await liveQueueWait("wait for D to be durably accepted behind A, B, and C") {
    await publicationProbe.count(room: room, topic: "letters") == 4
  }
  expectNoDifference(await wire.startedLabels(), ["A"], liveQueueRoomSource)

  firstSendGate.release()
  _ = try await liveQueueWithTimeout("wait for accepted room broadcast D") {
    try await publishD.value
  }
  try await liveQueueWait("wait for the exact FIFO room wire drain") {
    await wire.completedLabels().count == 4
  }
  expectNoDifference(await wire.startedLabels(), ["A", "B", "C", "D"], liveQueueRoomSource)
  expectNoDifference(
    await wire.completedLabels(),
    ["A", "B", "C", "D"],
    liveQueueRoomSource
  )
  let residency = try #require(
    await runtime.liveRoomBroadcastQueueResidencyForTesting(room: room)
  )
  expectNoDifference(residency.queuedMessageCount, 0, liveQueueRoomSource)
  expectNoDifference(residency.queuedEncodedByteCount, 0, liveQueueRoomSource)
  withExtendedLifetime(roomObservation) {}

  _ = try await liveQueueWithTimeout("close the FIFO room runtime") {
    try await runtime.closeConnection()
  }
  try? FileManager.default.removeItem(at: cacheURL.deletingLastPathComponent())
}

private func liveQueueAssertRoomCountBound() async throws {
  let room = InstantRoomHandle(type: "chat", id: "room-count-bound")
  let limits = InstantLiveRoomBroadcastQueueLimits(
    maximumMessageCountPerRoom: 3,
    maximumMessageCountGlobally: 32,
    maximumEncodedBytesPerMessage: 262_144,
    maximumEncodedBytesPerRoom: 1_048_576,
    maximumEncodedBytesGlobally: 8_388_608
  )
  let fixture = try await liveQueueRoomLimitFixture(
    appID: "live-queue-room-count-bound",
    room: room,
    topic: "count",
    limits: limits
  )
  let observation = try await fixture.runtime.observeRoomTopic(room: room, topic: "count")
  for label in ["A", "B", "C"] {
    _ = try await fixture.runtime.publishTopicMessage(
      room: room,
      topic: "count",
      userID: "limit-user",
      payload: liveQueueRoomPayload(label)
    )
  }
  let before = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: room)
  )
  expectNoDifference(before.queuedMessageCount, 3, liveQueueRoomSource)
  expectNoDifference(
    await fixture.publications.count(room: room, topic: "count"),
    3,
    liveQueueRoomSource
  )

  try await liveQueueExpectRoomQueueRejection(
    runtime: fixture.runtime,
    room: room,
    topic: "count",
    payload: liveQueueRoomPayload("D")
  )
  let persisted = try await fixture.runtime.roomTopicMessages(room: room, topic: "count")
  expectNoDifference(
    persisted.compactMap { liveQueueRoomPayloadLabel($0.payload) },
    ["A", "B", "C"]
  )
  expectNoDifference(
    await fixture.publications.count(room: room, topic: "count"),
    3,
    liveQueueRoomSource
  )
  let after = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: room)
  )
  expectNoDifference(after, before, liveQueueRoomSource)
  withExtendedLifetime(observation) {}
  try await liveQueueCloseRoomLimitFixture(fixture)
}

private func liveQueueAssertRoomGlobalCountBound() async throws {
  let globalCountLimit = 32
  let rooms = (0...globalCountLimit).map {
    InstantRoomHandle(type: "chat", id: String(format: "room-global-count-%02d", $0))
  }
  let topic = "global-count"
  let limits = InstantLiveRoomBroadcastQueueLimits(
    maximumMessageCountPerRoom: globalCountLimit,
    maximumMessageCountGlobally: globalCountLimit,
    maximumEncodedBytesPerMessage: 262_144,
    maximumEncodedBytesPerRoom: 1_048_576,
    maximumEncodedBytesGlobally: 8_388_608
  )
  let fixture = try await liveQueueRoomLimitFixture(
    appID: "live-queue-room-global-count-bound",
    room: rooms[0],
    topic: topic,
    limits: limits
  )
  for room in rooms.dropFirst() {
    _ = try await fixture.runtime.joinRoom(room)
  }
  for index in 0..<globalCountLimit {
    _ = try await fixture.runtime.publishTopicMessage(
      room: rooms[index],
      topic: topic,
      userID: "limit-user",
      payload: liveQueueRoomPayload("tiny-\(index)")
    )
  }
  let rejectedRoom = rooms[globalCountLimit]
  let rejectedObservation = try await fixture.runtime.observeRoomTopic(
    room: rejectedRoom,
    topic: topic
  )
  let before = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: rooms[0])
  )
  expectNoDifference(before.globalQueuedMessageCount, globalCountLimit, liveQueueRoomSource)
  #expect(before.globalQueuedEncodedByteCount < limits.maximumEncodedBytesGlobally)

  try await liveQueueExpectRoomQueueRejection(
    runtime: fixture.runtime,
    room: rejectedRoom,
    topic: topic,
    payload: liveQueueRoomPayload("tiny-rejected")
  )
  let persisted = try await fixture.runtime.roomTopicMessages(room: rejectedRoom, topic: topic)
  expectNoDifference(persisted, [], liveQueueRoomSource)
  expectNoDifference(
    await fixture.publications.count(room: rejectedRoom, topic: topic),
    0,
    liveQueueRoomSource
  )
  let after = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: rooms[0])
  )
  expectNoDifference(after, before, liveQueueRoomSource)
  withExtendedLifetime(rejectedObservation) {}
  try await liveQueueCloseRoomLimitFixture(fixture)
}

private func liveQueueAssertRoomSingleMessageByteBound() async throws {
  let room = InstantRoomHandle(type: "chat", id: "room-single-message-bound")
  let topic = "single-message"
  let maximumEncodedBytesPerMessage = 262_144
  let oversizedPayload = liveQueueRoomPayload(
    String(repeating: "x", count: maximumEncodedBytesPerMessage)
  )
  let encodedByteCount = try InstantLiveRoomBroadcastQueueLimits.encodedByteCount(
    room: room,
    topic: topic,
    payload: oversizedPayload
  )
  #expect(encodedByteCount > maximumEncodedBytesPerMessage)
  let limits = InstantLiveRoomBroadcastQueueLimits(
    maximumMessageCountPerRoom: 32,
    maximumMessageCountGlobally: 64,
    maximumEncodedBytesPerMessage: maximumEncodedBytesPerMessage,
    maximumEncodedBytesPerRoom: 1_048_576,
    maximumEncodedBytesGlobally: 8_388_608
  )
  let fixture = try await liveQueueRoomLimitFixture(
    appID: "live-queue-room-single-message-bound",
    room: room,
    topic: topic,
    limits: limits
  )
  let observation = try await fixture.runtime.observeRoomTopic(room: room, topic: topic)
  let before = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: room)
  )
  expectNoDifference(before.queuedMessageCount, 0, liveQueueRoomSource)
  expectNoDifference(before.queuedEncodedByteCount, 0, liveQueueRoomSource)

  try await liveQueueExpectRoomQueueRejection(
    runtime: fixture.runtime,
    room: room,
    topic: topic,
    payload: oversizedPayload
  )
  let persisted = try await fixture.runtime.roomTopicMessages(room: room, topic: topic)
  expectNoDifference(persisted, [], liveQueueRoomSource)
  expectNoDifference(
    await fixture.publications.count(room: room, topic: topic),
    0,
    liveQueueRoomSource
  )
  let after = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: room)
  )
  expectNoDifference(after, before, liveQueueRoomSource)
  withExtendedLifetime(observation) {}
  try await liveQueueCloseRoomLimitFixture(fixture)
}

private func liveQueueAssertRoomByteBound() async throws {
  let room = InstantRoomHandle(type: "chat", id: "room-byte-bound")
  let topic = "bytes"
  let acceptedPayload = liveQueueRoomPayload("A")
  let exactBytes = try InstantLiveRoomBroadcastQueueLimits.encodedByteCount(
    room: room,
    topic: topic,
    payload: acceptedPayload
  )
  let limits = InstantLiveRoomBroadcastQueueLimits(
    maximumMessageCountPerRoom: 32,
    maximumMessageCountGlobally: 64,
    maximumEncodedBytesPerMessage: 262_144,
    maximumEncodedBytesPerRoom: exactBytes,
    maximumEncodedBytesGlobally: exactBytes * 32
  )
  let fixture = try await liveQueueRoomLimitFixture(
    appID: "live-queue-room-byte-bound",
    room: room,
    topic: topic,
    limits: limits
  )
  let observation = try await fixture.runtime.observeRoomTopic(room: room, topic: topic)
  _ = try await fixture.runtime.publishTopicMessage(
    room: room,
    topic: topic,
    userID: "limit-user",
    payload: acceptedPayload
  )
  let before = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: room)
  )
  expectNoDifference(before.queuedEncodedByteCount, exactBytes, liveQueueRoomSource)

  try await liveQueueExpectRoomQueueRejection(
    runtime: fixture.runtime,
    room: room,
    topic: topic,
    payload: liveQueueRoomPayload("B")
  )
  let persisted = try await fixture.runtime.roomTopicMessages(room: room, topic: topic)
  expectNoDifference(persisted.compactMap { liveQueueRoomPayloadLabel($0.payload) }, ["A"])
  expectNoDifference(
    await fixture.publications.count(room: room, topic: topic),
    1,
    liveQueueRoomSource
  )
  let after = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: room)
  )
  expectNoDifference(after, before, liveQueueRoomSource)
  withExtendedLifetime(observation) {}
  try await liveQueueCloseRoomLimitFixture(fixture)
}

private func liveQueueAssertRoomGlobalByteBound() async throws {
  let firstRoom = InstantRoomHandle(type: "chat", id: "room-global-bound-a")
  let secondRoom = InstantRoomHandle(type: "chat", id: "room-global-bound-b")
  let topic = "global"
  let acceptedPayload = liveQueueRoomPayload("A")
  let exactGlobalBytes = try InstantLiveRoomBroadcastQueueLimits.encodedByteCount(
    room: firstRoom,
    topic: topic,
    payload: acceptedPayload
  )
  let limits = InstantLiveRoomBroadcastQueueLimits(
    maximumMessageCountPerRoom: 32,
    maximumMessageCountGlobally: 64,
    maximumEncodedBytesPerMessage: 262_144,
    maximumEncodedBytesPerRoom: exactGlobalBytes * 32,
    maximumEncodedBytesGlobally: exactGlobalBytes
  )
  let fixture = try await liveQueueRoomLimitFixture(
    appID: "live-queue-room-global-bound",
    room: firstRoom,
    topic: topic,
    limits: limits
  )
  _ = try await fixture.runtime.joinRoom(secondRoom)
  let observation = try await fixture.runtime.observeRoomTopic(room: secondRoom, topic: topic)
  _ = try await fixture.runtime.publishTopicMessage(
    room: firstRoom,
    topic: topic,
    userID: "limit-user",
    payload: acceptedPayload
  )
  let before = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: firstRoom)
  )
  expectNoDifference(before.globalQueuedEncodedByteCount, exactGlobalBytes, liveQueueRoomSource)

  try await liveQueueExpectRoomQueueRejection(
    runtime: fixture.runtime,
    room: secondRoom,
    topic: topic,
    payload: liveQueueRoomPayload("B")
  )
  let persisted = try await fixture.runtime.roomTopicMessages(room: secondRoom, topic: topic)
  expectNoDifference(persisted, [], liveQueueRoomSource)
  expectNoDifference(
    await fixture.publications.count(room: secondRoom, topic: topic),
    0,
    liveQueueRoomSource
  )
  let after = try #require(
    await fixture.runtime.liveRoomBroadcastQueueResidencyForTesting(room: firstRoom)
  )
  expectNoDifference(after, before, liveQueueRoomSource)
  withExtendedLifetime(observation) {}
  try await liveQueueCloseRoomLimitFixture(fixture)
}

private struct LiveQueueRoomLimitFixture {
  var runtime: InstantRuntime
  var session: LiveReactorParitySession
  var publications: LiveQueueRoomPublicationProbe
  var cacheURL: URL
}

private func liveQueueRoomLimitFixture(
  appID: String,
  room: InstantRoomHandle,
  topic: String,
  limits: InstantLiveRoomBroadcastQueueLimits
) async throws -> LiveQueueRoomLimitFixture {
  let cacheURL = try liveQueueTemporaryCacheURL()
  let session = LiveReactorParitySession(messages: [
    liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "\(appID)-session")
  ])
  let publications = LiveQueueRoomPublicationProbe()
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: cacheURL,
    initialAttributes: TodoExample.attributes,
    liveTransport: session.transport
  )
  configuration.liveRoomBroadcastQueueLimits = limits
  configuration.onRoomTopicSnapshotPublishedForTesting = { publishedRoom, publishedTopic in
    await publications.record(room: publishedRoom, topic: publishedTopic)
  }
  let runtime = try await InstantRuntime.bootstrap(configuration: configuration)
  _ = try await liveQueueWithTimeout("connect \(appID)") {
    try await runtime.connect()
  }
  _ = try await runtime.joinRoom(room)
  try await liveQueueWaitForSentMessages(
    2,
    in: session,
    operation: "wait for \(appID) room join"
  )
  return LiveQueueRoomLimitFixture(
    runtime: runtime,
    session: session,
    publications: publications,
    cacheURL: cacheURL
  )
}

private func liveQueueCloseRoomLimitFixture(_ fixture: LiveQueueRoomLimitFixture) async throws {
  _ = try await liveQueueWithTimeout("close the bounded room fixture") {
    try await fixture.runtime.closeConnection()
  }
  try? FileManager.default.removeItem(at: fixture.cacheURL.deletingLastPathComponent())
}

private func liveQueueExpectRoomQueueRejection(
  runtime: InstantRuntime,
  room: InstantRoomHandle,
  topic: String,
  payload: JSONValue
) async throws {
  do {
    _ = try await runtime.publishTopicMessage(
      room: room,
      topic: topic,
      userID: "limit-user",
      payload: payload
    )
    Issue.record("Expected the newest room broadcast to be rejected at the configured bound.")
  } catch let error as InstantError {
    expectNoDifference(error.code, .networkFailed, liveQueueRoomSource)
    expectNoDifference(error.operation, "publish room topic", liveQueueRoomSource)
    expectNoDifference(error.path, "roomBroadcastQueue", liveQueueRoomSource)
    expectNoDifference(error.localID, room.id, liveQueueRoomSource)
  }
}

private func liveQueueCreateWriter(
  runtime: InstantRuntime,
  session: LiveReactorParitySession,
  clientID: String,
  streamID: String,
  expectedSentMessageCount: Int
) async throws -> InstantStreamMetadata {
  let create = Task {
    try await runtime.createStream(clientID: clientID)
  }
  defer { create.cancel() }
  try await liveQueueWaitForSentMessages(
    expectedSentMessageCount,
    in: session,
    operation: "wait for start-stream for \(clientID)"
  )
  let start = try #require(await session.sentMessages().last)
  expectNoDifference(start.op, "start-stream", liveQueueStreamSource)
  await session.enqueue(
    liveQueueStartStreamOK(
      replyingTo: start,
      clientID: clientID,
      streamID: streamID,
      offset: 0
    )
  )
  return try await liveQueueWithTimeout("finish start-stream for \(clientID)") {
    try await create.value
  }
}

private func liveQueueStartStreamOK(
  replyingTo start: InstantLiveMessage,
  clientID: String,
  streamID: String,
  offset: Int64
) -> InstantLiveMessage {
  InstantLiveMessage(
    op: "start-stream-ok",
    clientEventID: start.clientEventID,
    fields: [
      "client-id": .string(clientID),
      "offset": .number(Double(offset)),
      "stream-id": .string(streamID),
    ]
  )
}

private func liveQueueWaitForSentMessages(
  _ count: Int,
  in session: LiveReactorParitySession,
  operation: String
) async throws {
  try await liveQueueWithTimeout(operation) {
    await session.waitForSentMessageCount(count)
  }
}

private func liveQueueWithTimeout<Value: Sendable>(
  _ operation: String,
  _ work: @escaping @Sendable () async throws -> Value
) async throws -> Value {
  try await instantLiveWithTimeout(
    operation: operation,
    timeoutMilliseconds: 5_000,
    work
  )
}

private func liveQueueWait(
  _ operation: String,
  until condition: @escaping @Sendable () async -> Bool
) async throws {
  try await liveQueueWithTimeout(operation) {
    while !(await condition()) {
      try Task.checkCancellation()
      await Task.yield()
    }
  }
}

private func liveQueueTemporaryCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantLiveQueueBoundsTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private final class LiveQueueOneShotGate: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: InstantLiveTestThrowingContinuationBox<Void>?
  private var entered = false
  private var released = false

  var didEnter: Bool {
    lock.withLock { entered }
  }

  func wait() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { rawContinuation in
        let continuation = InstantLiveTestThrowingContinuationBox(rawContinuation)
        let resolveImmediately = lock.withLock { () -> Result<Void, any Error>? in
          entered = true
          if released { return .success(()) }
          if Task.isCancelled { return .failure(CancellationError()) }
          self.continuation = continuation
          return nil
        }
        if let resolveImmediately {
          switch resolveImmediately {
          case .success:
            continuation.resume(returning: ())
          case .failure(let error):
            continuation.resume(throwing: error)
          }
        }
      }
    } onCancel: {
      cancel()
    }
  }

  func release() {
    let continuation = lock.withLock {
      released = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume(returning: ())
  }

  func cancel() {
    let continuation = lock.withLock {
      released = true
      defer { self.continuation = nil }
      return self.continuation
    }
    continuation?.resume(throwing: CancellationError())
  }
}

private final class LiveQueueReconnectGateTransport: @unchecked Sendable {
  private let lock = NSLock()
  private let first: LiveReactorParitySession
  private let second: LiveReactorParitySession
  private let reconnectGate: LiveQueueOneShotGate
  private var attemptCount = 0

  init(
    first: LiveReactorParitySession,
    second: LiveReactorParitySession,
    reconnectGate: LiveQueueOneShotGate
  ) {
    self.first = first
    self.second = second
    self.reconnectGate = reconnectGate
  }

  var transport: InstantLiveTransportClient {
    .connectionAttempts { _ in
      let attempt = self.lock.withLock {
        self.attemptCount += 1
        return self.attemptCount
      }
      switch attempt {
      case 1:
        return InstantLiveConnectionAttempt(session: self.first.webSocketSession)
      case 2:
        return InstantLiveConnectionAttempt(
          connect: {
            try await self.reconnectGate.wait()
            return self.second.webSocketSession
          },
          abort: {
            self.reconnectGate.cancel()
            self.second.webSocketSession.abort()
          }
        )
      default:
        return InstantLiveConnectionAttempt(
          connect: {
            throw InstantError(
              code: .networkFailed,
              operation: "connect scripted bounded stream transport",
              message: "Unexpected connection attempt \(attempt).",
              recovery: "Keep the disconnected replay test to exactly two sessions."
            )
          },
          abort: {}
        )
      }
    }
  }
}

private actor LiveQueueReplayCompletionProbe {
  private var counts: [String: Int] = [:]

  func record(streamID: String) {
    counts[streamID, default: 0] += 1
  }

  func count(streamID: String) -> Int {
    counts[streamID, default: 0]
  }
}

private actor LiveQueueRoomPublicationProbe {
  private var counts: [String: Int] = [:]

  func record(room: InstantRoomHandle, topic: String) {
    counts["\(room.type)/\(room.id)/\(topic)", default: 0] += 1
  }

  func count(room: InstantRoomHandle, topic: String) -> Int {
    counts["\(room.type)/\(room.id)/\(topic)", default: 0]
  }
}

private actor LiveQueueRoomWireProbe {
  private let blockedLabel: String
  private let gate: LiveQueueOneShotGate
  private var starts: [String] = []
  private var completions: [String] = []

  init(blockedLabel: String, gate: LiveQueueOneShotGate) {
    self.blockedLabel = blockedLabel
    self.gate = gate
  }

  func started(_ label: String) {
    starts.append(label)
  }

  func completed(_ label: String) {
    completions.append(label)
  }

  func shouldBlock(_ label: String) -> Bool {
    label == blockedLabel && !gate.didEnter
  }

  func startedLabels() -> [String] {
    starts
  }

  func completedLabels() -> [String] {
    completions
  }
}

private func liveQueueRoomPayload(_ label: String) -> JSONValue {
  .object(["label": .string(label)])
}

private func liveQueueRoomPayloadLabel(_ message: InstantLiveMessage) -> String? {
  guard message.op == "client-broadcast",
    case .object(let payload)? = message.fields["data"],
    case .string(let label)? = payload["label"]
  else { return nil }
  return label
}

private func liveQueueRoomPayloadLabel(_ payload: JSONValue) -> String? {
  guard case .object(let values) = payload,
    case .string(let label)? = values["label"]
  else { return nil }
  return label
}

private struct LiveQueueCountingStreamSnapshot: Equatable, Sendable {
  var startStreamCount: Int
  var appendStreamCount: Int
  var firstUnexpectedOffset: Int64?
  var finalOffset: Int64
}

private actor LiveQueueCountingStreamSession {
  nonisolated private let abortState = InstantLiveTestWireAbortState()
  private let clientID: String
  private let streamID: String
  private let serverOffset: Int64
  private var messages: [InstantLiveMessage]
  private var receiveContinuation: InstantLiveTestPendingOperation<InstantLiveMessage>?
  private var isClosed = false
  private var startStreamCount = 0
  private var appendStreamCount = 0
  private var expectedOffset: Int64
  private var firstUnexpectedOffset: Int64?

  init(clientID: String, streamID: String, serverOffset: Int64) {
    self.clientID = clientID
    self.streamID = streamID
    self.serverOffset = serverOffset
    self.expectedOffset = serverOffset
    self.messages = [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "counting-replay-session")
    ]
  }

  nonisolated var transport: InstantLiveTransportClient {
    .immediate { _ in self.webSocketSession }
  }

  nonisolated var webSocketSession: InstantLiveWebSocketSession {
    InstantLiveWebSocketSession(
      send: { message in try await self.send(message) },
      receive: {
        try self.abortState.check()
        return try await self.receive()
      },
      close: { await self.close() },
      abort: { self.abortState.abort() }
    )
  }

  func snapshot() -> LiveQueueCountingStreamSnapshot {
    LiveQueueCountingStreamSnapshot(
      startStreamCount: startStreamCount,
      appendStreamCount: appendStreamCount,
      firstUnexpectedOffset: firstUnexpectedOffset,
      finalOffset: expectedOffset
    )
  }

  private func send(_ message: InstantLiveMessage) throws {
    try abortState.check()
    switch message.op {
    case "start-stream":
      startStreamCount += 1
      enqueue(
        liveQueueStartStreamOK(
          replyingTo: message,
          clientID: clientID,
          streamID: streamID,
          offset: serverOffset
        )
      )
    case "append-stream":
      appendStreamCount += 1
      guard case .number(let offsetNumber)? = message.fields["offset"] else { return }
      let offset = Int64(offsetNumber)
      if offset != expectedOffset, firstUnexpectedOffset == nil {
        firstUnexpectedOffset = offset
      }
      guard case .array(let chunks)? = message.fields["chunks"] else { return }
      expectedOffset += chunks.reduce(Int64(0)) { partial, chunk in
        guard case .string(let content) = chunk else { return partial }
        return partial + Int64(content.utf8.count)
      }
    default:
      break
    }
  }

  private func enqueue(_ message: InstantLiveMessage) {
    guard !abortState.isAborted else { return }
    if let receiveContinuation {
      self.receiveContinuation = nil
      abortState.unregister(receiveContinuation.abortToken)
      receiveContinuation.continuation.resume(returning: message)
    } else if !isClosed {
      messages.append(message)
    }
  }

  private func receive() async throws -> InstantLiveMessage {
    try abortState.check()
    if !messages.isEmpty { return messages.removeFirst() }
    if isClosed { throw CancellationError() }
    let id = UUID()
    defer { clearReceiveContinuation(id: id) }
    return try await withCheckedThrowingContinuation { rawContinuation in
      let continuation = InstantLiveTestThrowingContinuationBox(rawContinuation)
      guard
        let abortToken = abortState.register({
          continuation.resume(throwing: CancellationError())
        })
      else {
        continuation.resume(throwing: CancellationError())
        return
      }
      receiveContinuation = InstantLiveTestPendingOperation(
        id: id,
        abortToken: abortToken,
        continuation: continuation
      )
    }
  }

  private func close() {
    isClosed = true
    abortState.abort()
    receiveContinuation = nil
  }

  private func clearReceiveContinuation(id: UUID) {
    guard let receiveContinuation, receiveContinuation.id == id else { return }
    abortState.unregister(receiveContinuation.abortToken)
    self.receiveContinuation = nil
  }
}

private struct LiveQueueSQLiteError: Error, CustomStringConvertible {
  var operation: String
  var message: String

  var description: String { "\(operation): \(message)" }
}

private let liveQueueSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func liveQueueSeedStreamFragments(
  fileURL: URL,
  appID: String,
  streamID: String,
  userID: String,
  count: Int,
  content: String
) throws {
  var database: OpaquePointer?
  guard
    sqlite3_open_v2(
      fileURL.path,
      &database,
      SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    ) == SQLITE_OK, let database
  else {
    throw LiveQueueSQLiteError(
      operation: "open live queue seed database",
      message: "SQLite could not open \(fileURL.path)."
    )
  }
  defer { sqlite3_close(database) }
  try liveQueueSQLiteExecute(database, sql: "PRAGMA foreign_keys = ON")
  try liveQueueSQLiteExecute(database, sql: "BEGIN IMMEDIATE")
  do {
    let sql =
      """
      INSERT INTO instant_stream_content_chunks
        (app_id, stream_id, chunk_id, offset, byte_count, created_at_ms, json)
      VALUES (?, ?, ?, ?, ?, ?, ?)
      """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else {
      throw liveQueueSQLiteFailure(database, operation: "prepare live queue fragment seed")
    }
    defer { sqlite3_finalize(statement) }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let byteCount = Int64(content.utf8.count)
    for index in 0..<count {
      let offset = Int64(index) * byteCount
      let chunk = InstantStreamContentChunk(
        id: String(format: "fragment-%05d", index),
        appID: appID,
        streamID: streamID,
        offset: offset,
        byteCount: byteCount,
        content: content,
        userID: userID,
        createdAt: InstantTimestamp(milliseconds: 1_700_100_000_000 + Int64(index))
      )
      let json = String(decoding: try encoder.encode(chunk), as: UTF8.self)
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      sqlite3_bind_text(statement, 1, appID, -1, liveQueueSQLiteTransient)
      sqlite3_bind_text(statement, 2, streamID, -1, liveQueueSQLiteTransient)
      sqlite3_bind_text(statement, 3, chunk.id, -1, liveQueueSQLiteTransient)
      sqlite3_bind_int64(statement, 4, offset)
      sqlite3_bind_int64(statement, 5, byteCount)
      sqlite3_bind_int64(statement, 6, chunk.createdAt.milliseconds)
      sqlite3_bind_text(statement, 7, json, -1, liveQueueSQLiteTransient)
      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw liveQueueSQLiteFailure(database, operation: "insert live queue fragment seed")
      }
    }
    try liveQueueSQLiteExecute(database, sql: "COMMIT")
  } catch {
    _ = try? liveQueueSQLiteExecute(database, sql: "ROLLBACK")
    throw error
  }
}

private func liveQueueSQLiteExecute(_ database: OpaquePointer, sql: String) throws {
  var errorMessage: UnsafeMutablePointer<CChar>?
  guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
    let message = errorMessage.map { String(cString: $0) } ?? "Unknown SQLite error."
    sqlite3_free(errorMessage)
    throw LiveQueueSQLiteError(operation: "execute live queue seed SQL", message: message)
  }
}

private func liveQueueSQLiteFailure(
  _ database: OpaquePointer,
  operation: String
) -> LiveQueueSQLiteError {
  LiveQueueSQLiteError(
    operation: operation,
    message: String(cString: sqlite3_errmsg(database))
  )
}

private let liveQueueStreamSource =
  "upstream/instant/client/packages/core/src/Stream.ts createWriteStream/startWriteStream/appendStream and upstream/instant/client/packages/python/tests/test_streams_state.py reconnect cases [adapted: Swift makes SQLite the writer replay authority, pages the durable tail by 256 fragments / 1 MiB raw / 8 MiB encoded, and releases each page before selecting the next.]"

private let liveQueueRoomSource =
  "upstream/instant/client/packages/core/src/Reactor.js _flushEnqueuedRoomData/publishTopic [adapted: Swift runs one FIFO room-broadcast drain, counts the in-flight item against fixed per-message, per-room, and process-global count/byte limits, and rejects admission before local persistence or observer publication.]"
