# ADR 0017: Streams Written Offline Reach the Server, Named by Their Client ID

- Status: Accepted
- Date: 2026-10-01
- Issue: #329 (build 78)
- Scope: write streams (`createStream`, `appendStreamContent`, `closeStream`), stream readers
  (`observeStreamContent`, `subscribeStreamContent`), the live session's stream writers, SQLite stream storage

## Context

A stream written while the socket was closed never reached the server. `InstantRuntime.createStream(clientID:)`
started a server stream only when the live session was open. Offline it stored a local stream under an id the client
made up (`configuration.makeID()`), the live session registered no writer for it, so `appendStreamContent` and
`closeStream` sent nothing, and nothing started it later: after `connect()` the server received only `init`.

Scribe publishes a recording's audio and timeline images as streams (`InstantRecordingRealtime.synchronizeMedia`) and
writes each stream's id and client id into the recording's media asset rows. Media synced offline therefore reached
other devices as asset rows whose streams the server never got. A reader device asked for the stream by the
client-made id (`ScribeInstantStore.completedMediaStreamContent`), the server answered 400 "Validation failed for
subscribe-stream: Stream is missing.", and the media never arrived (library-77 made that refusal end the observation
instead of hanging, 1ba00779).

The same gap had two smaller siblings in streams started online: an append made while the socket was down was dropped
(the live session did not buffer it), and a close made offline waited five seconds for a flush and then threw.

The design question: a stream written offline has only its client id until the server assigns one. How should the
writer, the queue that starts it later, and readers on other devices refer to it?

### What upstream does

`upstream/instant/client/packages/core/src/Stream.ts` (pinned e7101761):

- `createWriteStream({ clientId })` returns a `WritableStream` at once. Its `start` sends
  `start-stream { client-id, reconnect-token }` through `Reactor.js` `_trySendAuthed`, which drops the message unless
  the socket is authenticated; the start then waits for `start-stream-ok`, an error, or a connection status change
  (`onConnectionStatusChange` answers every pending start with `disconnect`, and `start` retries with a backoff).
- The stream id exists only after `start-stream-ok`; `streamId()` is a promise. Upstream never hands out a stream id
  before the server assigns one. Writes made before then wait in the `WritableStream`'s queue.
- After a reconnect, every registered writer calls `onConnectionReconnect`: `start-stream` with the same client id and
  reconnect token, which the server answers with the same stream id and the bytes it has flushed
  (`session.clj` `handle-start-stream!`, `buffer-byte-offset`). `discardFlushed` drops what the server holds and the
  writer resends the rest of its in-memory buffer. `close()` appends `done` once the stream id is known.
- `start-stream` errors close the write stream for good (`onRecieveError`).
- Readers subscribe by `streamId` or by `clientId` (`createReadStream`); the server resolves either
  (`app_stream.clj` `get-stream` looks up `clientId` when no `stream-id` is given).
- Write streams do not survive a page reload ("TODO(dww): accept a storage so that write streams can survive across
  browser restarts").

### What Swift must keep

- The library's write contract: a write never waits for the server, and offline writes succeed.
  `createStream(clientID:)` returns `InstantStreamMetadata`, whose `id` is not optional, and Scribe stores it.
- Swift already stores every stream's metadata and content in SQLite (`instant_streams`,
  `instant_stream_content_chunks`), so a stream outlives the process; only the writer's server state was in memory.

## Options

1. **Server id only (upstream's rule).** Offline, `createStream` would wait for a connection or fail. That breaks the
   write contract and Scribe's offline media sync, and needs a second store for content written before the id exists.
2. **Re-key the local stream to the server id once it starts.** Every local handle the app already holds (the id in
   memory, the id Scribe wrote into synced asset rows) would stop resolving, or the library would keep an alias table
   on every device. Reader devices still could not resolve the made-up id: only the writing device knows the mapping.
3. **Name the stream by its client id across devices; keep the local id as a device-local handle.** The writer keeps
   using the id `createStream` returned; the library starts the server copy by client id and records the server's id
   for the wire; readers on other devices read by client id, which the server resolves for streams written online
   and offline alike.

## Decision

Option 3. **A stream's client id is its name until the server assigns an id; the id `createStream` returns offline is
a handle valid on this device only.**

- **The writer** (this device) keeps naming the stream by the id `createStream` returned, offline or online, for every
  local call (`appendStreamContent`, `closeStream`, `streamContent`, `observeStreamContent`). The local row is never
  re-keyed, so code holding the id keeps working across the server start. Online, that id is the server's id, as
  before.
- **The queue that starts it** is a durable writer record per stream this device creates
  (`instant_stream_writers`: client id, reconnect token, the server's id once known, and whether the server holds the
  stream's close or refused it). After every connection opens, a catch-up pass (`InstantRuntime.catchUpStreamWriters`)
  takes each stream whose server copy may be behind, oldest first, and does what upstream's `start` and
  `onConnectionReconnect` do: `start-stream` with the client id and the reconnect token, record the server's id, resend
  from SQLite every stored chunk after the server's offset, then send the close if the stream is closed, and record
  the server's terminal `stream-flushed`. Appends and closes made while the catch-up runs wait in SQLite and follow in
  order; once caught up, the writer sends appends as they happen, as before. `append-stream` always names the stream by
  the server's id. The pass sends only the signed-in user's streams: the connection authenticates as that user, and the
  server would make another user's stream theirs.
- **Readers on other devices** read a stream they did not write by its client id (`observeStreamContent(clientID:)`).
  A stream id is a valid cross-device handle only for a stream created online. Before the writer's device reconnects,
  a reader by client id gets "Stream is missing." and its observation ends (library-77); the app reads again later.
- **The writer's own observations** of a stream it writes read SQLite and never subscribe: this device holds every
  byte, a subscription would only echo it back, and the server does not know an offline stream by its local id.

### Where Swift differs from upstream, and why

- **The buffer is SQLite, not memory.** Upstream resends an in-memory buffer; Swift resends stored chunks. The content
  is already durable, so the writer holds nothing extra in memory while offline, and a relaunch loses nothing.
- **The reconnect token is durable.** The server accepts a restart of an existing client id only with the original
  token, so storing it is what lets a stream started before a relaunch finish after it. Upstream loses its write
  streams on reload. A stream written offline gets its token at its first start, stored before `start-stream` is
  sent.
- **A local id exists before the server's.** It never crosses the wire; it only keeps the write contract.
- **A refusal is recorded.** Upstream closes the write stream; Swift records the refusal so no later connection asks
  again. A restart refused with "Stream is closed." means the server already holds the whole stream (its close was
  flushed before this device recorded that), so it counts as delivered.
- **The same replay was already specified.** The stream cases in `InstantLiveQueueBoundsTests.swift` (excluded from
  the test target since August as "tests ahead of production") describe this design: a disconnected append replayed
  from durable SQLite on reconnect, and an append made during the restart handshake sent once, after it.
- **The catch-up runs beside the outbox.** It no longer blocks `connect()` or holds mutation delivery behind it, and a
  writer the server refuses or leaves unanswered no longer closes the connection (the old `reconnectStreamWriters`
  did both).

## Consequences

- A stream created, appended, and closed offline reaches the server once a connection opens, with its content and
  close, and a second device reading by client id gets the whole stream (`InstantStreamRobustnessTests`
  `aStreamWrittenOfflineReachesTheServerOnceConnected`, `anotherDeviceReadsAStreamWrittenOfflineByItsClientID`;
  `InstantReactorParityTests.aStreamWrittenWhileOfflineStartsOnTheServerOnceConnected`, no longer a known issue).
- Appends and closes made while the socket is down, in streams started online, are no longer lost, and an offline
  close returns without waiting (`aStreamStartedOnlineSendsWhatItGotOfflineFromTheServersOffset`).
- A relaunch between writing and connecting resumes with the original reconnect token
  (`aStreamWrittenOfflineKeepsItsReconnectTokenAcrossARelaunch`).
- **Scribe must read media by `streamClientID`.** `ScribeInstantStore.completedMediaStreamContent` reads by
  `asset.streamID`, which for media synced offline is this device's local id. Reading by `asset.streamClientID` when
  present (and by `asset.streamID` for older rows without one) reaches every stream on the server.
- Streams written offline by builds before this one have no writer record, so nothing starts them. Their media stays
  on the writing device unless the app writes it again as a new stream: Scribe's media client ids include the
  content digest, so the same media finds the old local stream and reuses it.
- A stream left open (never closed) is restarted on every connection until it closes, as upstream restarts an open
  write stream after every reconnect.
- Until the live session routes `start-stream` errors to the stream (upstream `Reactor.js` `_handleReceiveError`
  sends every stream op's error to `Stream.ts` `onRecieveError`), a refused start still ends the connection once; the
  refusal is recorded first, so the next connection does not ask again.
- Readers that subscribe by a server stream id keep working unchanged; this decision only adds the client-id path for
  streams written offline.

## References

- `upstream/instant/client/packages/core/src/Stream.ts`: `createWriteStream` (`start`, `onConnectionReconnect`,
  `discardFlushed`, `close`), `createReadStream`, `InstantStream.onRecieveError`, `onStreamFlushed`
- `upstream/instant/client/packages/core/src/Reactor.js`: `_trySendAuthed`, `_setStatus` →
  `_instantStream.onConnectionStatusChange`, `_handleReceiveError` (stream ops)
- `upstream/instant/server/src/instant/reactive/session.clj`: `handle-start-stream!` (reconnect token, "Stream is
  closed."), `handle-append-stream!` (expected offset), `handle-subscribe-stream!` (by `stream-id` or `client-id`)
- `upstream/instant/server/src/instant/model/app_stream.clj`: `get-stream`, `create!`, `append` ("Invalid offset for
  stream.")
- Swift: `InstantRuntime.createStream`, `catchUpStreamWriters`, `InstantRuntimeLiveSession.restartStreamWriter`,
  `endStreamWriterCatchUp`, `SQLitePersistenceStore` migration `0025_stream_writers`
