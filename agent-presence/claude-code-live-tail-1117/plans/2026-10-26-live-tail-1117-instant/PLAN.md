# Plan 2026-10-26-live-tail-1117-instant: the wire meter says which query each refresh's bytes answered

- planId: 2026-10-26-live-tail-1117-instant
- agentId: claude-code/live-tail-1117@strangelearning
- role: grower (diagnostics ordered on the consuming app's #1117 and #1214)
- issues: #1117, #1214, #1124 (the wire meter)

## Why

The wire meter (#1124) counts refresh-ok frames and bytes by op only. On one device a recording received about 1.15 MB
per final line in refresh-ok frames; telling which live query carried them took two copies of the device's store and
reading `instant_live_query_results` by hand. A refresh-ok's `computations` each carry their `instaql-query`, so the
library can say which query each byte answered, at no extra pass over the frame.

## Design

1. The frame parser records the byte length of each element of a top-level `computations` array as it parses it (two
   integers per computation; no second pass, no copy).
2. Decoding a frame counts each computation's bytes in the wire meter under its query's shape: the namespaces, the
   top-level `limit`/`first`/`last`, and the attribute names its `where` tests (no values, so no ids), for example
   `transcriptionSegments/64[recordingID]`. An `add-query-ok` counts its whole frame under its query's shape. At most
   48 shapes; later ones count as `other`.
3. `InstantWireSnapshot.receivedByQuery` and `subtracting` carry them; the minute's summary line names the three
   heaviest. Upstream parity: the server's frames are unchanged; this only reads them.

## Steps

1. This plan and its claims (plan-only commit on main).
2. Red: InstantWireMeterTests (spans equal each computation's bytes; shapes; the cap; a refresh through the decoder
   lands in the meter). Green. Focused suites plus the frame decode suites.
3. Release after cellular-1237's 1.9.44: 1.9.45 (docs/releases/v1.9.45.md, CHANGELOG.md, PROGRESS.md,
   docs/audits/commit-changelog.md); the app pins it.

## Touching

Sources/InstantSwiftDataCore/InstantLiveJSONParser.swift, Sources/InstantSwiftDataCore/InstantLiveFrameDecoding.swift,
Sources/InstantSwiftDataCore/InstantWireMeter.swift, Tests/InstantSwiftDataCoreTests/InstantWireMeterTests.swift,
docs/releases/v1.9.45.md (new), CHANGELOG.md, PROGRESS.md, docs/audits/commit-changelog.md.

## Conflict check

cellular-1237 holds InstantLiveTransport.swift (where the socket records each frame), InstantRuntime.swift and
docs/releases/v1.9.44.md: none touched here; the count happens in the frame decoder the transport already calls.
Channel agent-presence/_channels/2026-10-26-cellular-1237.md.
