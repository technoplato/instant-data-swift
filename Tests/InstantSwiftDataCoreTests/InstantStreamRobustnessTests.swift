import CustomDump
import Foundation
@testable import InstantSwiftDataCore
import Testing

/// Build 78's stream defects (#329), each pinned against upstream Instant at e7101761:
///
/// 1. An append tells each observation about the new bytes instead of re-reading the whole stream, while every
///    observation still receives the stream's complete content from its byte offset (Scribe's `materializeMedia`
///    returns the `content` of the first `done` read).
/// 2. A reader whose stream is done is deleted at done: its observation ends, and no reconnect subscribes it again.
/// 3. A stream written while the socket is closed reaches the server once it opens.
@Suite(.serialized)
struct InstantStreamRobustnessTests {
  // MARK: - Incremental snapshots

  @Test
  func anAppendTellsEveryObservationWithoutRereadingTheStream() async throws {
    let runtime = try await InstantRuntime.bootstrap(
      configuration: InstantRuntimeConfiguration(
        appID: "stream-incremental-snapshots",
        persistenceURL: try streamRobustnessCacheURL()
      )
    )
    _ = try await runtime.signInWithRefreshToken("refresh-token", userID: "user-1")
    let metadata = try await runtime.createStream(clientID: "incremental-writer")
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "abc")
    let observations = [
      try await runtime.observeStreamContent(streamID: metadata.id),
      try await runtime.observeStreamContent(clientID: "incremental-writer"),
      try await runtime.observeStreamContent(streamID: metadata.id, byteOffset: 3),
    ]
    let recorders = observations.map { _ in StreamReadRecorder() }
    let consumers = zip(observations, recorders).map { observation, recorder in
      Task {
        for await read in observation {
          await recorder.record(read)
          if read.done { break }
        }
      }
    }
    defer { consumers.forEach { $0.cancel() } }

    var decodedChunksPerAppend: [Int] = []
    for line in dictationLines(count: 40) {
      let before = await runtime.persistence.streamContentReadMetricsForTesting().decodedChunkCount
      _ = try await runtime.appendStreamContent(streamID: metadata.id, content: line)
      let after = await runtime.persistence.streamContentReadMetricsForTesting().decodedChunkCount
      decodedChunksPerAppend.append(after - before)
    }
    let beforeClose = await runtime.persistence.streamContentReadMetricsForTesting().decodedChunkCount
    _ = try await runtime.closeStream(streamID: metadata.id)
    let afterClose = await runtime.persistence.streamContentReadMetricsForTesting().decodedChunkCount

    expectNoDifference(decodedChunksPerAppend, Array(repeating: 0, count: 40), typescriptIncrementalStreamSource)
    expectNoDifference(afterClose - beforeClose, 0, typescriptIncrementalStreamSource)

    let expected = [
      try await runtime.streamContent(streamID: metadata.id),
      try await runtime.streamContent(clientID: "incremental-writer"),
      try await runtime.streamContent(streamID: metadata.id, byteOffset: 3),
    ]
    for (index, consumer) in consumers.enumerated() {
      try await instantLiveWithTimeout(
        operation: "wait for observation \(index) to read the closed stream",
        timeoutMilliseconds: 10_000
      ) {
        await consumer.value
      }
      let reads = await recorders[index].reads
      expectNoDifference(reads.last, expected[index], "Observation \(index) ends with the stream's content.")
      for read in reads {
        #expect(expected[index].content.hasPrefix(read.content), "Every read is the stream so far.")
        expectNoDifference(Int64(read.content.utf8.count), read.byteCount)
      }
    }
  }

  @Test
  func aReadersCumulativeContentEqualsTheStreamAcrossAReconnect() async throws {
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "cumulative-reader-before-drop")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "cumulative-reader-after-drop")
    ])
    let transport = LiveReactorParityTransport(sessions: [first, second])
    let runtime = try await liveStreamRuntime(appID: "stream-cumulative-reader", transport: transport.transport)
    _ = try await runtime.signInAsGuest()
    _ = try await runtime.connect()

    let fromStart = try await runtime.observeStreamContent(clientID: "remote-dictation")
    let recorder = StreamReadRecorder()
    let consumer = Task {
      for await read in fromStart {
        await recorder.record(read)
        if read.done { break }
      }
    }
    defer { consumer.cancel() }
    let subscribe = try #require(try await sentMessages(of: first, op: "subscribe-stream").first)
    expectNoDifference(subscribe.fields, ["client-id": .string("remote-dictation")])

    let lines = dictationLines(count: 30)
    await runtime.persistence.resetStreamContentReadMetricsForTesting()
    var offset: Int64 = 0
    for line in lines[0..<15] {
      await first.enqueue(
        remoteStreamAppend(clientEventID: subscribe.clientEventID, content: line, offset: offset)
      )
      offset += Int64(line.utf8.count)
    }
    let seenBeforeDrop = offset
    try await eventually("the reader applies the first session's appends") {
      await recorder.latest?.byteCount == seenBeforeDrop
    }

    await first.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop the cumulative reader's session",
        message: "transient reader drop",
        recovery: "Reconnect and resubscribe from the seen offset."
      )
    )
    let resubscribe = try #require(try await sentMessages(of: second, op: "subscribe-stream").first)
    expectNoDifference(
      resubscribe.fields,
      ["client-id": .string("remote-dictation"), "offset": .number(Double(seenBeforeDrop))],
      typescriptIncrementalStreamSource
    )
    // The server resends from an earlier offset; the reader keeps only the bytes after what it has seen.
    let lastLine = lines[14]
    offset -= Int64(lastLine.utf8.count)
    for (index, line) in ([lastLine + lines[15]] + Array(lines[16...])).enumerated() {
      await second.enqueue(
        remoteStreamAppend(
          clientEventID: resubscribe.clientEventID,
          content: line,
          offset: offset,
          done: index == lines.count - 15 - 1
        )
      )
      offset += Int64(line.utf8.count)
    }
    try await instantLiveWithTimeout(
      operation: "wait for the reader to read the done stream",
      timeoutMilliseconds: 10_000
    ) {
      await consumer.value
    }

    let reads = await recorder.reads
    // The appends and the close told the observation without reading stored chunks back.
    let decodedChunks = await runtime.persistence.streamContentReadMetricsForTesting().decodedChunkCount
    expectNoDifference(decodedChunks, 0, typescriptIncrementalStreamSource)
    let stored = try await runtime.streamContent(clientID: "remote-dictation")
    expectNoDifference(stored.content, lines.joined(), typescriptIncrementalStreamSource)
    expectNoDifference(reads.last, stored, typescriptIncrementalStreamSource)
    #expect(reads.allSatisfy { stored.content.hasPrefix($0.content) }, "Every read is the stream so far.")
    _ = try await runtime.closeConnection()
  }

  // MARK: - A finished stream's reader

  @Test
  func aFinishedStreamsReaderIsDeletedAtDoneAndNeverSubscribedAgain() async throws {
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "finished-reader-before-drop")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "finished-reader-after-drop")
    ])
    let transport = LiveReactorParityTransport(sessions: [first, second])
    let runtime = try await liveStreamRuntime(appID: "stream-finished-reader", transport: transport.transport)
    _ = try await runtime.signInAsGuest()
    _ = try await runtime.connect()

    // A probe reader that sorts after the finished one: a reconnect resubscribes readers in key order, so once the
    // probe is resubscribed, a resubscription of the finished reader would already have been sent.
    let probe = try await runtime.observeStreamContent(streamID: probeStreamID)
    let probeConsumer = Task { for await _ in probe {} }
    defer { probeConsumer.cancel() }
    // The consumer keeps iterating, as a long-lived subscription does. Upstream closes a reader at done
    // (`Stream.ts` `onStreamAppend`), so its loop ends on its own.
    let observation = try await runtime.observeStreamContent(streamID: remoteStreamID)
    let consumer = Task { () -> [InstantStreamContentRead] in
      var reads: [InstantStreamContentRead] = []
      for await read in observation { reads.append(read) }
      return reads
    }
    defer { consumer.cancel() }
    let subscribe = try #require(
      try await sentMessages(of: first, op: "subscribe-stream", count: 2)
        .first { $0.fields["stream-id"] == .string(remoteStreamID) }
    )
    await first.enqueue(
      remoteStreamAppend(clientEventID: subscribe.clientEventID, content: "hello 🚀", offset: 0, done: true)
    )
    let reads = try await instantLiveWithTimeout(
      operation: "wait for the finished stream's observation to end",
      timeoutMilliseconds: 5_000
    ) {
      await consumer.value
    }
    expectNoDifference(reads.last?.content, "hello 🚀", typescriptFinishedReaderSource)
    expectNoDifference(reads.last?.done, true, typescriptFinishedReaderSource)
    try await eventually("the finished stream has no observers") {
      try await runtime.activeStreamContentObservationCount(streamID: remoteStreamID) == 0
    }

    await first.failReceive(
      InstantError(
        code: .networkFailed,
        operation: "drop the finished reader's session",
        message: "transient drop after a finished read",
        recovery: "Reconnect without the finished reader."
      )
    )
    try await eventually("the reconnect resubscribes the probe") {
      await second.sentMessages().contains { $0.op == "subscribe-stream" && $0.fields["stream-id"] == .string(probeStreamID) }
    }
    let subscriptions = await second.sentMessages().filter { $0.op == "subscribe-stream" }
    expectNoDifference(
      subscriptions.map { $0.fields["stream-id"] },
      [.string(probeStreamID)],
      typescriptFinishedReaderSource
    )
    let unsubscribes = await first.sentMessages().filter { $0.op == "unsubscribe-stream" }
    expectNoDifference(unsubscribes.count, 0, typescriptFinishedReaderSource)
    _ = try await runtime.closeConnection()
  }

  @Test
  func observingAStreamThatIsAlreadyDoneReadsItLocallyAndEnds() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "done-stream-local-read")
    ])
    let runtime = try await liveStreamRuntime(appID: "stream-done-local-read", transport: session.transport)
    let auth = try await runtime.signInAsGuest()
    let stored = try await seedRemoteStream(
      runtime,
      appID: "stream-done-local-read",
      userID: auth.userID,
      content: "already here",
      done: true
    )
    _ = try await runtime.connect()

    let observation = try await runtime.observeStreamContent(streamID: stored.metadata.id)
    let reads = try await instantLiveWithTimeout(
      operation: "wait for the done stream's observation to end",
      timeoutMilliseconds: 5_000
    ) {
      var reads: [InstantStreamContentRead] = []
      for await read in observation { reads.append(read) }
      return reads
    }
    expectNoDifference(reads, [stored], typescriptFinishedReaderSource)
    try await Task.sleep(for: .milliseconds(200))
    let ops = await session.sentMessages().map(\.op)
    expectNoDifference(ops, ["init"], "A done stream has nothing more to send, so nothing subscribes to it.")
    _ = try await runtime.closeConnection()
  }

  // MARK: - Streams written offline (#329)

  @Test
  func aStreamWrittenOfflineReachesTheServerOnceConnected() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "offline-writer")
    ])
    let runtime = try await liveStreamRuntime(
      appID: "stream-offline-writer",
      transport: session.transport
    )
    _ = try await runtime.signInAsGuest()
    let metadata = try await runtime.createStream(clientID: "offline-media")
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "hello ", expectedOffset: 0)
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "world 🚀", expectedOffset: 6)
    let closed = try await runtime.closeStream(streamID: metadata.id)
    expectNoDifference(closed.size, 16)
    let sentWhileOffline = await session.sentMessages().map(\.op)
    expectNoDifference(sentWhileOffline, [], "Nothing is sent while the socket is closed.")

    _ = try await runtime.connect()
    let start = try #require(try await sentMessages(of: session, op: "start-stream").first)
    expectNoDifference(start.fields["client-id"], .string("offline-media"), typescriptOfflineWriterSource)
    guard case let .string(reconnectToken)? = start.fields["reconnect-token"] else {
      Issue.record("start-stream carries a reconnect token.")
      return
    }
    #expect(UUID(uuidString: reconnectToken) != nil, "The server coerces the reconnect token as a UUID.")
    await session.enqueue(
      startStreamOK(clientEventID: start.clientEventID, clientID: "offline-media", streamID: offlineServerStreamID)
    )
    let appends = try await sentMessages(of: session, op: "append-stream", count: 3)
    expectNoDifference(
      appends.map(\.fields),
      [
        appendStreamFields(chunks: ["hello "], offset: 0),
        appendStreamFields(chunks: ["world 🚀"], offset: 6),
        appendStreamFields(chunks: [], offset: 16, done: true),
      ],
      typescriptOfflineWriterSource
    )
    await session.enqueue(streamFlushed(streamID: offlineServerStreamID, offset: 16, done: true))

    // The writer's handle is unchanged; only the wire names the stream by the server's id.
    let afterStart = try await runtime.streamMetadata(clientID: "offline-media")
    expectNoDifference(afterStart, closed)
    let read = try await runtime.streamContent(streamID: metadata.id)
    expectNoDifference(read.content, "hello world 🚀")
    try await Task.sleep(for: .milliseconds(200))
    let startCount = await session.sentMessages().filter { $0.op == "start-stream" }.count
    expectNoDifference(startCount, 1, "The stream starts once.")
    _ = try await runtime.closeConnection()
  }

  @Test
  func anotherDeviceReadsAStreamWrittenOfflineByItsClientID() async throws {
    let writerSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "offline-writer-device")
    ])
    let writer = try await liveStreamRuntime(
      appID: "stream-offline-shared",
      transport: writerSession.transport
    )
    _ = try await writer.signInAsGuest()
    let written = try await writer.createStream(clientID: "offline-shared-media")
    let chunks = ["iVBORw0KGgo", "AAAANSUhEUgAA", "ABAAAAAQCAYAAAAf8/9h", "é🚀"]
    var offset: Int64 = 0
    for chunk in chunks {
      _ = try await writer.appendStreamContent(streamID: written.id, content: chunk, expectedOffset: offset)
      offset += Int64(chunk.utf8.count)
    }
    _ = try await writer.closeStream(streamID: written.id)
    _ = try await writer.connect()
    let start = try #require(try await sentMessages(of: writerSession, op: "start-stream").first)
    await writerSession.enqueue(
      startStreamOK(
        clientEventID: start.clientEventID,
        clientID: "offline-shared-media",
        streamID: offlineServerStreamID
      )
    )
    let appends = try await sentMessages(of: writerSession, op: "append-stream", count: chunks.count + 1)

    // A reader device has only the asset row's ids. The stream id the writer device holds was made offline, so the
    // reader reads by the client id, which the server resolves (`session.clj` `handle-subscribe-stream!`).
    let readerSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "offline-reader-device")
    ])
    let reader = try await liveStreamRuntime(appID: "stream-offline-shared", transport: readerSession.transport)
    _ = try await reader.signInAsGuest()
    _ = try await reader.connect()
    let observation = try await reader.observeStreamContent(clientID: "offline-shared-media")
    let subscribe = try #require(try await sentMessages(of: readerSession, op: "subscribe-stream").first)
    expectNoDifference(subscribe.fields, ["client-id": .string("offline-shared-media")])
    // The server relays what the writer appended to the reader's subscription.
    for append in appends {
      guard case let .array(sent)? = append.fields["chunks"],
        case let .number(sentOffset)? = append.fields["offset"],
        case let .bool(done)? = append.fields["done"]
      else {
        Issue.record("append-stream carries chunks, an offset, and done.")
        return
      }
      let content = sent.compactMap { value -> String? in
        guard case let .string(chunk) = value else { return nil }
        return chunk
      }.joined()
      await readerSession.enqueue(
        remoteStreamAppend(
          clientEventID: subscribe.clientEventID,
          streamID: offlineServerStreamID,
          clientID: "offline-shared-media",
          content: content.isEmpty ? nil : content,
          offset: Int64(sentOffset),
          done: done
        )
      )
    }
    let final = try await instantLiveWithTimeout(
      operation: "wait for the reader to read the stream written offline",
      timeoutMilliseconds: 10_000
    ) {
      var last: InstantStreamContentRead?
      for await read in observation {
        last = read
        if read.done { break }
      }
      return last
    }
    expectNoDifference(final?.content, chunks.joined(), typescriptOfflineWriterSource)
    expectNoDifference(final?.done, true)
    expectNoDifference(final?.metadata.id, offlineServerStreamID)
    _ = try await reader.closeConnection()
    _ = try await writer.closeConnection()
  }

  @Test
  func appendsMadeWhileTheServerStartIsPendingFollowTheStoredContentInOrder() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "pending-start-writer")
    ])
    let runtime = try await liveStreamRuntime(
      appID: "stream-pending-start",
      transport: session.transport
    )
    _ = try await runtime.signInAsGuest()
    let metadata = try await runtime.createStream(clientID: "pending-start-media")
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "a", expectedOffset: 0)
    _ = try await runtime.connect()
    let start = try #require(try await sentMessages(of: session, op: "start-stream").first)

    // Upstream holds writes until the server names the stream; Swift's are already durable, so they wait in SQLite.
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "b", expectedOffset: 1)
    let appendsBeforeStart = await session.sentMessages().filter { $0.op == "append-stream" }.count
    expectNoDifference(appendsBeforeStart, 0)
    await session.enqueue(
      startStreamOK(clientEventID: start.clientEventID, clientID: "pending-start-media", streamID: offlineServerStreamID)
    )
    let caughtUp = try await sentMessages(of: session, op: "append-stream", count: 2)
    expectNoDifference(
      caughtUp.map(\.fields),
      [appendStreamFields(chunks: ["a"], offset: 0), appendStreamFields(chunks: ["b"], offset: 1)],
      typescriptOfflineWriterSource
    )

    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "c", expectedOffset: 2)
    let live = try await sentMessages(of: session, op: "append-stream", count: 3)
    expectNoDifference(live.last?.fields, appendStreamFields(chunks: ["c"], offset: 2), typescriptOfflineWriterSource)
    let closeTask = Task { try await runtime.closeStream(streamID: metadata.id) }
    let terminal = try await sentMessages(of: session, op: "append-stream", count: 4)
    expectNoDifference(terminal.last?.fields, appendStreamFields(chunks: [], offset: 3, done: true))
    await session.enqueue(streamFlushed(streamID: offlineServerStreamID, offset: 3, done: true))
    let closed = try await closeTask.value
    expectNoDifference(closed.done, true)
    let appendCount = await session.sentMessages().filter { $0.op == "append-stream" }.count
    expectNoDifference(appendCount, 4)
    _ = try await runtime.closeConnection()
  }

  @Test
  func aStreamStartedOnlineSendsWhatItGotOfflineFromTheServersOffset() async throws {
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "online-writer-before-gap")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "online-writer-after-gap")
    ])
    let transport = LiveReactorParityTransport(sessions: [first, second])
    let runtime = try await liveStreamRuntime(
      appID: "stream-online-writer-gap",
      transport: transport.transport
    )
    _ = try await runtime.signInAsGuest()
    _ = try await runtime.connect()
    let createTask = Task { try await runtime.createStream(clientID: "online-media") }
    let firstStart = try #require(try await sentMessages(of: first, op: "start-stream").first)
    await first.enqueue(
      startStreamOK(clientEventID: firstStart.clientEventID, clientID: "online-media", streamID: onlineServerStreamID)
    )
    let metadata = try await createTask.value
    expectNoDifference(metadata.id, onlineServerStreamID)
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "hello", expectedOffset: 0)
    _ = try await sentMessages(of: first, op: "append-stream", count: 1)
    _ = try await runtime.closeConnection()

    // Offline, an append and the close are kept, and the close does not wait for the server.
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: " world", expectedOffset: 5)
    let closed = try await instantLiveWithTimeout(
      operation: "close a stream while offline",
      timeoutMilliseconds: 2_000
    ) {
      try await runtime.closeStream(streamID: metadata.id)
    }
    expectNoDifference(closed.size, 11)

    _ = try await runtime.connect()
    let secondStart = try #require(try await sentMessages(of: second, op: "start-stream").first)
    expectNoDifference(secondStart.fields, firstStart.fields, "The writer restarts with its original token.")
    // The server flushed "hello" before the gap, so it answers with offset 5.
    await second.enqueue(
      startStreamOK(
        clientEventID: secondStart.clientEventID,
        clientID: "online-media",
        streamID: onlineServerStreamID,
        offset: 5
      )
    )
    let resent = try await sentMessages(of: second, op: "append-stream", count: 2)
    expectNoDifference(
      resent.map(\.fields),
      [
        appendStreamFields(chunks: [" world"], offset: 5, streamID: onlineServerStreamID),
        appendStreamFields(chunks: [], offset: 11, done: true, streamID: onlineServerStreamID),
      ],
      typescriptOfflineWriterSource
    )
    _ = try await runtime.closeConnection()
  }

  @Test
  func aStreamWrittenOfflineKeepsItsReconnectTokenAcrossARelaunch() async throws {
    let cacheURL = try streamRobustnessCacheURL()
    let firstSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "offline-writer-before-relaunch")
    ])
    let firstRuntime = try await liveStreamRuntime(
      appID: "stream-offline-relaunch",
      cacheURL: cacheURL,
      transport: firstSession.transport
    )
    _ = try await firstRuntime.signInAsGuest()
    let metadata = try await firstRuntime.createStream(clientID: "relaunched-media")
    _ = try await firstRuntime.appendStreamContent(streamID: metadata.id, content: "kept", expectedOffset: 0)
    _ = try await firstRuntime.connect()
    let firstStart = try #require(try await sentMessages(of: firstSession, op: "start-stream").first)
    // The app is killed before the server answers.
    _ = try await firstRuntime.closeConnection()

    let secondSession = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "offline-writer-after-relaunch")
    ])
    let relaunched = try await liveStreamRuntime(
      appID: "stream-offline-relaunch",
      cacheURL: cacheURL,
      transport: secondSession.transport
    )
    _ = try await relaunched.connect()
    let secondStart = try #require(try await sentMessages(of: secondSession, op: "start-stream").first)
    expectNoDifference(
      secondStart.fields,
      firstStart.fields,
      "The server accepts a restart only with the original reconnect token (session.clj handle-start-stream!)."
    )
    await secondSession.enqueue(
      startStreamOK(clientEventID: secondStart.clientEventID, clientID: "relaunched-media", streamID: offlineServerStreamID)
    )
    let appends = try await sentMessages(of: secondSession, op: "append-stream", count: 1)
    expectNoDifference(appends.map(\.fields), [appendStreamFields(chunks: ["kept"], offset: 0)])
    _ = try await relaunched.closeConnection()
  }

  @Test
  func aStartTheServerRefusesIsNotSentAgain() async throws {
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "refused-start-first")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "refused-start-second")
    ])
    let third = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "refused-start-third")
    ])
    let transport = LiveReactorParityTransport(sessions: [first, second, third])
    let runtime = try await liveStreamRuntime(
      appID: "stream-refused-start",
      transport: transport.transport
    )
    _ = try await runtime.signInAsGuest()
    let refused = try await runtime.createStream(clientID: "refused-media")
    _ = try await runtime.closeStream(streamID: refused.id)
    _ = try await runtime.createStream(clientID: "probe-media")
    _ = try await runtime.connect()

    let start = try #require(try await sentMessages(of: first, op: "start-stream").first)
    expectNoDifference(start.fields["client-id"], .string("refused-media"))
    await first.enqueue(
      InstantLiveMessage(
        op: "error",
        clientEventID: start.clientEventID,
        fields: [
          "message": .string("Validation failed for start-stream: Stream is closed."),
          "type": .string("validation-failed"),
          "status": .number(400),
          "original-event": .object([
            "client-event-id": start.clientEventID.map(InstantLiveJSONValue.string) ?? .null,
            "op": .string("start-stream"),
            "client-id": .string("refused-media"),
          ]),
        ]
      )
    )
    // The probe stream, created after the refused one, starts next: on this socket, or on the next one if the
    // refusal ended it.
    try await eventually("the probe stream starts") {
      let sessions = [first, second, third]
      for session in sessions {
        let starts = await session.sentMessages().filter { $0.op == "start-stream" }
        if starts.contains(where: { $0.fields["client-id"] == .string("probe-media") }) { return true }
      }
      return false
    }
    var refusedStarts = 0
    for session in [first, second, third] {
      refusedStarts += await session.sentMessages().filter {
        $0.op == "start-stream" && $0.fields["client-id"] == .string("refused-media")
      }.count
    }
    expectNoDifference(refusedStarts, 1, typescriptRefusedWriterSource)
    _ = try await runtime.closeConnection()
  }

  // MARK: - Refused appends (library-78)

  /// The server refuses an append of a live writer: upstream `Stream.ts` `onRecieveError` hands an `append-stream`
  /// error to the writer's `onAppendFailed`, which restarts the write stream on the same socket. Library-78 keeps the
  /// socket open for an error nothing owns, so without that restart the writer kept sending appends the server
  /// refuses until some other reconnect; before library-78 the refusal reconnected the socket.
  @Test
  func aRefusedAppendRestartsTheWriterOnTheSameSocketFromTheServersOffset() async throws {
    try await Self.assertTheWriterRestartsOnTheSameSocket(appID: "stream-refused-append") { first, append in
      await first.enqueue(
        InstantLiveMessage(
          op: "error",
          clientEventID: append.clientEventID,
          fields: [
            "message": .string("Validation failed for append-stream: Invalid offset for stream."),
            "type": .string("validation-failed"),
            "status": .number(400),
            "original-event": .object([
              "client-event-id": append.clientEventID.map(InstantLiveJSONValue.string) ?? .null,
              "op": .string("append-stream"),
              "stream-id": .string(onlineServerStreamID),
              "offset": .number(0),
            ]),
          ]
        )
      )
    }
  }

  /// The server could not flush a live writer's appends (`append-failed`): upstream `Reactor.js` hands it to
  /// `Stream.ts` `onAppendFailed`, which restarts the write stream on the same socket. Swift threw from the receive
  /// loop instead, which closed a healthy socket and re-added every query.
  @Test
  func anAppendTheServerCouldNotFlushRestartsTheWriterOnTheSameSocket() async throws {
    try await Self.assertTheWriterRestartsOnTheSameSocket(appID: "stream-append-failed") { first, _ in
      await first.enqueue(
        InstantLiveMessage(op: "append-failed", fields: ["stream-id": .string(onlineServerStreamID)])
      )
    }
  }

  static func assertTheWriterRestartsOnTheSameSocket(
    appID: String,
    failAppend: (LiveReactorParitySession, InstantLiveMessage) async -> Void
  ) async throws {
    let first = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "\(appID)-socket")
    ])
    let second = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "\(appID)-reconnected")
    ])
    let transport = LiveReactorParityTransport(sessions: [first, second])
    let runtime = try await liveStreamRuntime(appID: appID, transport: transport.transport)
    _ = try await runtime.signInAsGuest()
    _ = try await runtime.connect()
    let createTask = Task { try await runtime.createStream(clientID: "\(appID)-media") }
    let firstStart = try #require(try await sentMessages(of: first, op: "start-stream").first)
    await first.enqueue(
      startStreamOK(clientEventID: firstStart.clientEventID, clientID: "\(appID)-media", streamID: onlineServerStreamID)
    )
    let metadata = try await createTask.value
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "hello", expectedOffset: 0)
    let append = try #require(try await sentMessages(of: first, op: "append-stream").first)

    await failAppend(first, append)

    // The writer restarts with its original token on this socket; the server answers with what it holds.
    let starts = try await sentMessages(of: first, op: "start-stream", count: 2)
    expectNoDifference(starts.last?.fields, firstStart.fields, typescriptFailedAppendSource)
    await first.enqueue(
      startStreamOK(
        clientEventID: starts.last?.clientEventID,
        clientID: "\(appID)-media",
        streamID: onlineServerStreamID,
        offset: 0
      )
    )
    let resent = try await sentMessages(of: first, op: "append-stream", count: 2)
    expectNoDifference(
      resent.last?.fields,
      appendStreamFields(chunks: ["hello"], offset: 0, streamID: onlineServerStreamID),
      typescriptFailedAppendSource
    )
    // Caught up again, the writer sends appends as they happen.
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: " world", expectedOffset: 5)
    let live = try await sentMessages(of: first, op: "append-stream", count: 3)
    expectNoDifference(
      live.last?.fields,
      appendStreamFields(chunks: [" world"], offset: 5, streamID: onlineServerStreamID)
    )
    let reconnected = await second.sentMessages().map(\.op)
    expectNoDifference(reconnected, [], "The socket stays open: a failed append is the writer's, not the connection's.")
    _ = try await runtime.closeConnection()
  }

  @Test
  func theWritersOwnObservationOfAStreamWrittenOfflineDoesNotSubscribe() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "offline-writer-observes")
    ])
    let runtime = try await liveStreamRuntime(
      appID: "stream-offline-writer-observes",
      transport: session.transport
    )
    _ = try await runtime.signInAsGuest()
    let metadata = try await runtime.createStream(clientID: "observed-offline-media")
    let observation = try await runtime.observeStreamContent(streamID: metadata.id)
    let recorder = StreamReadRecorder()
    let consumer = Task {
      for await read in observation {
        await recorder.record(read)
        if read.done { break }
      }
    }
    defer { consumer.cancel() }
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "offline ", expectedOffset: 0)
    _ = try await runtime.connect()
    let start = try #require(try await sentMessages(of: session, op: "start-stream").first)
    await session.enqueue(
      startStreamOK(
        clientEventID: start.clientEventID,
        clientID: "observed-offline-media",
        streamID: offlineServerStreamID
      )
    )
    _ = try await sentMessages(of: session, op: "append-stream", count: 1)
    _ = try await runtime.appendStreamContent(streamID: metadata.id, content: "online", expectedOffset: 8)
    try await eventually("the writer's observation reads its own appends") {
      await recorder.latest?.content == "offline online"
    }
    // This device holds every byte it wrote; the server knows the stream by another id and would refuse it, which
    // would end the observation.
    let subscriptionCount = await session.sentMessages().filter { $0.op == "subscribe-stream" }.count
    expectNoDifference(subscriptionCount, 0)
    _ = try await runtime.closeConnection()
  }

  @Test
  func anotherUsersStreamWrittenOfflineIsNotStartedForTheSignedInUser() async throws {
    let session = LiveReactorParitySession(messages: [
      liveReactorInitOK(attrs: liveReactorTodoServerAttrs, sessionID: "offline-writer-other-user")
    ])
    let runtime = try await liveStreamRuntime(appID: "stream-offline-other-user", transport: session.transport)
    _ = try await runtime.signInAsGuest()
    let firstUsers = try await runtime.createStream(clientID: "first-users-media")
    _ = try await runtime.appendStreamContent(streamID: firstUsers.id, content: "private", expectedOffset: 0)
    try await runtime.signOut()
    _ = try await runtime.signInAsGuest()
    _ = try await runtime.createStream(clientID: "second-users-media")
    _ = try await runtime.connect()

    _ = try await sentMessages(of: session, op: "start-stream")
    try await Task.sleep(for: .milliseconds(200))
    // The connection authenticates as the second user, and the server would make the first user's stream theirs.
    let starts = await session.sentMessages().filter { $0.op == "start-stream" }
    expectNoDifference(starts.map { $0.fields["client-id"] }, [.string("second-users-media")])
    _ = try await runtime.closeConnection()
  }
}

// MARK: - Support

private let remoteStreamID = "00000000-0000-0000-0000-000000000301"
private let offlineServerStreamID = "00000000-0000-0000-0000-000000000302"
private let onlineServerStreamID = "00000000-0000-0000-0000-000000000303"
private let probeStreamID = "ffffffff-ffff-4fff-bfff-ffffffffffff"

private let typescriptIncrementalStreamSource =
  "upstream/instant/client/packages/core/src/Stream.ts createReadStream runStartStream (enqueues only the bytes after seenOffset) [adapted: a Swift observation yields the stream's content so far, so the runtime extends each observation's last read with the new chunk instead of re-reading the stream from SQLite.]"

private let typescriptFinishedReaderSource =
  "upstream/instant/client/packages/core/src/Stream.ts onStreamAppend (done closes the iterator and deletes the reader) and onConnectionStatusChange (only remaining readers reconnect) [adapted: the observation yields the done read, then ends; a stream already done locally is read locally without a subscription.]"

private let typescriptOfflineWriterSource =
  "upstream/instant/client/packages/core/src/Stream.ts createWriteStream start, onConnectionReconnect, and discardFlushed, with Reactor.js _trySendAuthed [adapted: Swift keeps a stream's content and reconnect token in SQLite, so the writer restarts after any reconnect or relaunch and resends from the server's offset; see docs/adr/0017-streams-written-offline.md.]"

private let typescriptRefusedWriterSource =
  "upstream/instant/client/packages/core/src/Stream.ts onRecieveError (start-stream errors the write stream for good) [adapted: Swift records the refusal in SQLite so no later connection starts the stream again.]"

private let typescriptFailedAppendSource =
  "upstream/instant/client/packages/core/src/Stream.ts onAppendFailed (onDisconnect, then onConnectionReconnect on the same socket), reached from Reactor.js 'append-failed' and onRecieveError 'append-stream' [adapted: the writer's catch-up restarts it with its stored reconnect token and resends from SQLite what the server lacks.]"

private actor StreamReadRecorder {
  private(set) var reads: [InstantStreamContentRead] = []

  var latest: InstantStreamContentRead? { reads.last }

  func record(_ read: InstantStreamContentRead) {
    reads.append(read)
  }
}

private struct StreamRobustnessTimeout: Error, CustomStringConvertible {
  var description: String
}

private func streamRobustnessCacheURL() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("InstantStreamRobustnessTests-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("state.sqlite")
}

private func liveStreamRuntime(
  appID: String,
  cacheURL: URL? = nil,
  transport: InstantLiveTransportClient
) async throws -> InstantRuntime {
  var configuration = InstantRuntimeConfiguration(
    appID: appID,
    persistenceURL: try cacheURL ?? streamRobustnessCacheURL(),
    initialAttributes: TodoExample.attributes,
    liveTransport: transport
  )
  // As in the other live parity tests, the runtime connects only when asked, and a dropped socket reconnects at once.
  configuration.autoConnectLiveTransport = false
  configuration.liveReconnectSleep = { _ in }
  return try await InstantRuntime.bootstrap(configuration: configuration)
}

/// Stores a stream as a reader device holds one it materialized from the server, not one it wrote.
private func seedRemoteStream(
  _ runtime: InstantRuntime,
  appID: String,
  userID: String,
  content: String,
  done: Bool
) async throws -> InstantStreamContentRead {
  let createdAt = InstantTimestamp(milliseconds: 1_700_000_090_000)
  _ = try await runtime.persistence.ensureStreamMetadata(
    appID: appID,
    streamID: remoteStreamID,
    clientID: "remote-client",
    userID: userID,
    createdAt: createdAt
  )
  _ = try await runtime.persistence.appendStreamContent(
    appID: appID,
    streamID: remoteStreamID,
    chunkID: "remote-chunk-0",
    content: content,
    expectedOffset: 0,
    userID: userID,
    createdAt: createdAt
  )
  if done {
    _ = try await runtime.persistence.closeStream(
      appID: appID,
      streamID: remoteStreamID,
      abortReason: nil,
      updatedAt: createdAt
    )
  }
  return try await runtime.streamContent(streamID: remoteStreamID)
}

/// Waits for `session` to have sent `count` messages with `op`, and returns every such message.
private func sentMessages(
  of session: LiveReactorParitySession,
  op: String,
  count: Int = 1,
  timeout: Duration = .seconds(10)
) async throws -> [InstantLiveMessage] {
  let deadline = ContinuousClock.now + timeout
  while true {
    let messages = await session.sentMessages().filter { $0.op == op }
    if messages.count >= count { return messages }
    guard ContinuousClock.now < deadline else {
      let ops = await session.sentMessages().map(\.op)
      throw StreamRobustnessTimeout(description: "Expected \(count) '\(op)' message(s); the session sent \(ops).")
    }
    try await Task.sleep(for: .milliseconds(20))
  }
}

private func eventually(
  _ description: String,
  timeout: Duration = .seconds(10),
  _ condition: () async throws -> Bool
) async throws {
  let deadline = ContinuousClock.now + timeout
  while try await !condition() {
    guard ContinuousClock.now < deadline else {
      throw StreamRobustnessTimeout(description: "Timed out waiting until \(description).")
    }
    try await Task.sleep(for: .milliseconds(20))
  }
}

/// Dictation-shaped interim lines, with multi-byte characters so byte offsets differ from character counts.
private func dictationLines(count: Int) -> [String] {
  (0..<count).map { index in
    switch index % 4 {
    case 0: "line \(index): so I was thinking about the stream primitive "
    case 1: "café \(index) — résumé "
    case 2: "🚀 \(index) 🎙️ "
    default: "\(index) "
    }
  }
}

private func remoteStreamAppend(
  clientEventID: String?,
  streamID: String = remoteStreamID,
  clientID: String = "remote-dictation",
  content: String?,
  offset: Int64,
  done: Bool = false
) -> InstantLiveMessage {
  var fields: [String: InstantLiveJSONValue] = [
    "client-id": .string(clientID),
    "offset": .number(Double(offset)),
    "retry": .bool(false),
    "stream-id": .string(streamID),
  ]
  if let content {
    fields["content"] = .string(content)
  }
  if done {
    fields["done"] = .bool(true)
  }
  return InstantLiveMessage(op: "stream-append", clientEventID: clientEventID, fields: fields)
}

private func startStreamOK(
  clientEventID: String?,
  clientID: String,
  streamID: String,
  offset: Int64 = 0
) -> InstantLiveMessage {
  InstantLiveMessage(
    op: "start-stream-ok",
    clientEventID: clientEventID,
    fields: [
      "client-id": .string(clientID),
      "offset": .number(Double(offset)),
      "stream-id": .string(streamID),
    ]
  )
}

private func streamFlushed(streamID: String, offset: Int64, done: Bool) -> InstantLiveMessage {
  InstantLiveMessage(
    op: "stream-flushed",
    fields: [
      "done": .bool(done),
      "offset": .number(Double(offset)),
      "stream-id": .string(streamID),
    ]
  )
}

private func appendStreamFields(
  chunks: [String],
  offset: Int64,
  done: Bool = false,
  streamID: String = offlineServerStreamID
) -> [String: InstantLiveJSONValue] {
  [
    "chunks": .array(chunks.map(InstantLiveJSONValue.string)),
    "done": .bool(done),
    "offset": .number(Double(offset)),
    "stream-id": .string(streamID),
  ]
}
