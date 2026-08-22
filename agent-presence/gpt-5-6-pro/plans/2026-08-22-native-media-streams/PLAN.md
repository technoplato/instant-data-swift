# Native synced audio/video streams and cross-SDK memory plan

- **planId:** `2026-08-22-native-media-streams`
- **agentId:** `gpt-5-6-pro`
- **role:** grower for a first-class generated Swift API; mower for buffering, copying, and retention costs
- **parent plan:** `2026-08-22-100x-two-hour-transcription-soak`
- **started:** 2026-08-22 11:25 EDT

## Outcome

Add a native Instant Swift Data abstraction for continuously writing and reading synchronized audio/video frames over the existing durable Instant stream transport. The public API must use generated entity metadata, typed builders, bounded backpressure, resumable offsets, and AsyncSequence—not raw stream IDs and unbounded strings at product call sites.

The same work adds Swift-versus-TypeScript memory, CPU, throughput, framing-overhead, and correctness comparisons for long-running audio and video streams. The 100× two-hour transcription gate must run while audio/video streams are active so transcript, linked query, infinite query, and media pressure are measured together.

## Design invariants

1. Reuse the existing `$streams`, durable SQLite fragment spool, reconnect token, offset, flush, close, and abort protocol. Do not create a second offline queue.
2. Keep at most the configured high-water bytes resident. The default realtime policy suspends the producer; dropping requires an explicit media policy.
3. Encode one bounded frame at a time. Never build a whole recording, movie, or two-hour base64 string in memory.
4. Audio/video frames carry sequence, presentation timestamp, duration, flags, codec/format metadata, and payload. Readers reject gaps, duplicates, offset regressions, malformed envelopes, and format changes that violate the declared descriptor.
5. Entity delivery and media delivery remain independently retryable and rejectable.
6. Writer success means frame accepted into the durable local stream spool. `flush()` and `finish(waitForRemote:)` are explicitly named server waits.
7. Reader buffering is bounded by bytes and frames, cancellation releases buffered payloads, and resumed readers continue from an exact byte offset or frame sequence.
8. Generated `@InstantEntity` models provide the owner namespace and stable stream client ID; application code does not repeat raw namespaces.

## API shape

```swift
let audio = Recording.stream(
  ownerID: recording.id,
  name: "audio",
  as: InstantAudioFrame.self
)
.audio(.pcm(sampleRate: 48_000, channels: 1, sampleFormat: .int16))
.buffering(.realtime(maximumBytes: 1_048_576))
.resume(.automatic)

let writer = try await db.streams.open(audio)
try await writer.write(frame)
try await writer.finish(waitForRemote: true)

for try await frame in try await db.streams.read(audio) {
  player.enqueue(frame)
}
```

The builder is value-semantic and type-preserving, analogous to a generated Instant query descriptor: entity type + owner id + stream name + frame type + format + buffering/resume policy. Convenience presets may be named `.voice`, `.music`, `.cameraPreview`, and `.recordingVideo`, but their concrete settings remain inspectable.

## Benchmark contract

### Audio

- logical duration: 7,200 seconds
- PCM16 mono 48 kHz source semantics, encoded into bounded test frames
- exact sequence/hash equality across Swift and TypeScript readers
- no unbounded payload residency

### Video

- logical duration: 7,200 seconds
- deterministic encoded-frame fixture with keyframe cadence and presentation timestamps
- exact sequence/hash equality across Swift and TypeScript readers
- bounded frame window and explicit drop/suspend policy

### Measurements

- physical footprint start/peak/end and incremental peak
- RSS/heap where platform-specific
- average and peak CPU
- payload bytes, encoded bytes, base64/framing overhead
- frames/second and bytes/second
- producer suspension time and high-water utilization
- durable fragment count/bytes and final resident raw-payload bytes
- reconnect/resume correctness and final remote hash

### Release policy

- zero loss, duplication, sequence gap, offset regression, hash mismatch, or post-close frame
- Swift incremental peak and settled memory no greater than TypeScript for equivalent framed workloads
- Swift throughput no lower than TypeScript
- resident payload never exceeds configured high-water bytes plus one maximum frame
- final stream spool and outbox have no remotely outstanding work
- two-hour 100× transcript + audio/video combined lane stays within the parent CPU/memory ceilings

## Test-first sequence

1. Descriptor/builder and generated-entity route tests.
2. Frame envelope round-trip, malformed input, sequence, and format validation tests.
3. Backpressure actor tests proving byte/frame high-water limits and cancellation release.
4. Durable writer/read adapter over existing low-level stream APIs.
5. Cross-SDK deterministic audio/video memory benchmark.
6. Credentialed Swift writer → TypeScript reader and TypeScript writer → Swift reader stream lanes.
7. Fold stream comparisons into `.home-runner/transcription-100x-2h.sh` and the release gate.
8. Integrate Scribe progressive audio first; add video buffer use through the same descriptor without coupling transcript synchronization.

## Touching

- `Sources/InstantSwiftData/InstantMediaStreams.swift`
- `Sources/InstantSwiftDataCore/InstantMediaStreamFrames.swift`
- `Sources/InstantSwiftDataCore/InstantMediaStreamBuffer.swift`
- `Sources/InstantSwiftDataCore/InstantRuntimeLiveSession.swift`
- `Tests/InstantSwiftDataTests/InstantMediaStreamsTests.swift`
- `Tests/InstantSwiftDataCoreTests/InstantMediaStreamBufferTests.swift`
- `validation/ts-runner/src/media-stream-memory-benchmark.ts`
- `validation/run-media-stream-memory-benchmark.sh`
- `.home-runner/transcription-100x-2h.sh`
- `.github/workflows/transcription-100x-2h.yml`
- `validation/run-performance-gate.sh`
- `docs/benchmarks/native-media-streams.md`
- `INSTANT_DATA_API_DESIGN_PREFERENCES_V2.md`

## Channel

`agent-presence/_channels/2026-08-22-native-media-streams.md`
