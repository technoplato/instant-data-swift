# Validation Harness

This directory is the source of truth for acceptance proof.

The rule is simple: data must cross the real InstantDB boundary and the
Swift/TypeScript boundary. A unit test can protect a helper, but it does not
prove this library.

## Expected Layout

- `fixtures/schema.swift`: Swift source-of-truth schema declaration.
- `fixtures/instant.schema.ts`: expected generated TypeScript schema.
- `fixtures/instant.perms.ts`: expected generated TypeScript permissions.
- `instant-swift-data-validation-runner`: Swift executable built by the package.
- `ts-runner`: TypeScript executable using `@instantdb/core` and
  `@instantdb/admin`.
- `run-e2e.sh`: orchestration entry point.
- `results/`: per-run JSONL evidence and timing output.

## Local Swift Evidence

The Swift runner currently emits local-only evidence for the durable todo
workflow. It proves the Swift core can seed, update, cache, reset, and relaunch
against the same SQLite state without SwiftUI:

```bash
swift run instant-swift-data validation local-todos --jsonl
swift run instant-swift-data-validation-runner --local-todos
```

The output is JSON Lines using the evidence format below. Real InstantDB and
Swift/TypeScript boundary cases remain required for final acceptance.

## Required Cases

- Swift writes, TypeScript observes.
- TypeScript writes, Swift observes.
- Swift linked graph writes, TypeScript nested query observes.
- TypeScript linked graph writes, Swift nested query observes.
- Swift offline optimistic writes flush after reconnect.
- TypeScript offline/server writes refresh Swift after reconnect.
- High-bandwidth scalar writes.
- High-bandwidth linked writes.
- Presence in both directions.
- Topics in both directions.
- Storage in both directions.
- Streams in both directions.
- Sharing and permissions across two users.
- Permissions reject unauthorized writes in both paths.
- CLI example commands reuse the same core auth, cache, and outbox state.
- Benchmark runs emit JSON/JSONL metrics for Swift and TypeScript parity.

## Evidence Format

Each runner should emit JSON Lines. Every row should include:

- `case`: stable case id.
- `side`: `swift`, `typescript`, or `orchestrator`.
- `event`: stable event name.
- `appID`: ephemeral Instant app id.
- `entityID` or `streamID` when applicable.
- `timestampMs`.
- `latencyMs` for observed round trips.
- `ok`: boolean.
- `details`: object with case-specific fields.
