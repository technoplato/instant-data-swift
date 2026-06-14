# Validation Harness

This directory is the source of truth for acceptance proof.

The rule is simple: data must cross the real InstantDB boundary and the
Swift/TypeScript boundary. A unit test can protect a helper, but it does not
prove this library.

## Expected Layout

- `fixtures/schema.swift`: Swift source-of-truth schema declaration.
- `fixtures/instant.schema.ts`: expected generated TypeScript schema.
- `fixtures/instant.perms.ts`: expected generated TypeScript permissions.
- `instant-swift-data`: Swift CLI validation commands built by the package.
- `instant-swift-data-validation-runner`: legacy Swift validation executable
  built by the package.
- `ts-runner`: TypeScript executable using `@instantdb/core` and
  `@instantdb/admin`.
- `run-e2e.sh`: orchestration entry point.
- `results/`: per-run JSONL evidence and timing output.

## Local Swift Evidence

The Swift runners currently emit local-only evidence for the durable todo
workflow, local integration surfaces, generated typed drafts, public adapter
wrappers, and parity coverage provenance. They prove the Swift core can seed,
update, cache, reset, relaunch, authenticate, publish room presence/topics,
upload/read file contents, append stream chunks, create/accept/revoke shares,
create and edit generated drafts, bind public wrapper adapters, and report
upstream Instant/SQLiteData parity records without SwiftUI.
The standalone runner goes through
`InstantSwiftDataTesting.InstantSwiftDataTestHarness` where practical, so the
same evidence helpers are available to package tests and terminal validation:

```bash
swift run instant-swift-data validation local-todos --jsonl
swift run instant-swift-data validation local-integrations --jsonl
swift run instant-swift-data validation typed-drafts --jsonl
swift run instant-swift-data validation platform-adapters --jsonl
swift run instant-swift-data validation parity-report --jsonl
swift run instant-swift-data-validation-runner --local-todos
swift run instant-swift-data-validation-runner --local-integrations
swift run instant-swift-data-benchmarks --suite local-todos --iterations 1 --jsonl
```

The output is JSON Lines using the evidence format below. Real InstantDB and
Swift/TypeScript boundary cases remain required for final acceptance.

## Local TypeScript Fixture Evidence

The TypeScript runner parses and compares the committed `instant.schema.ts` and
`instant.perms.ts` fixture shapes from the TypeScript side and emits JSONL
evidence without requiring an Instant app or admin token:

```bash
node validation/ts-runner/src/main.ts --fixtures
```

The fixture rows include exact expected/actual evidence for entities, fields,
field modifiers, links, room presence/topic shapes, permission namespaces, and
allowed operations. `validation/run-e2e.sh` records all Swift local validation
streams (`swift-local.jsonl`, `swift-local-integrations.jsonl`,
`swift-typed-drafts.jsonl`, `swift-platform-adapters.jsonl`, and
`swift-parity-report.jsonl`), records the local benchmark evidence, and then
runs this fixture check when Node is available. Set
`INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR` to direct artifacts to a specific
directory, and
`INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS` to adjust the benchmark
iteration count. The parity report command can succeed while individual blocked
provenance rows intentionally carry `ok: false`; the orchestrator records the
artifact command result, not an all-rows-passed summary. The harness records the
real Instant boundary as pending until ephemeral app creation, schema push, and
admin query/transact are implemented.

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
