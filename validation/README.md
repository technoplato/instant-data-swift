# Validation Harness

This directory is the source of truth for acceptance proof.

The rule is simple: data must cross the real InstantDB boundary and the
Swift/TypeScript boundary. A unit test can protect a helper, but it does not
prove this library.

## Expected Layout

- `fixtures/schema.swift`: Swift source-of-truth schema declaration.
- `fixtures/instant.schema.ts`: expected generated TypeScript schema.
- `fixtures/instant.perms.ts`: expected generated TypeScript permissions.
- `fixtures/recording-action.server.schema.ts`: captured server-normalized
  recording schema, including known Instant-managed additions.
- `fixtures/recording-action.server.perms.ts`: captured server-normalized
  recording permissions.
- `instant-swift-data`: Swift CLI validation commands built by the package.
- `instant-swift-data-validation-runner`: legacy Swift validation executable
  built by the package.
- `ts-runner`: TypeScript executable using `@instantdb/core` and
  `@instantdb/admin`.
- `run-e2e.sh`: orchestration entry point.
- `results/`: per-run JSONL evidence and timing output.

## Local Swift Evidence

The Swift runners currently emit local-only evidence for the durable todo
workflow, local integration surfaces, Reminders, generated typed drafts, public
adapter wrappers, and parity coverage provenance. They prove the Swift core can
seed, update, cache, reset, relaunch, authenticate, publish room
presence/topics, upload/read file contents, append stream chunks,
create/accept/revoke shares, validate Reminders search/tags/share roles, create
and edit generated drafts, bind public wrapper adapters, and report upstream
Instant/SQLiteData parity records without SwiftUI. Reminders validation includes
a `search-token-model` row for tag suggestions and tag-token search.
The standalone runner goes through
`InstantSwiftDataTesting.InstantSwiftDataTestHarness` where practical, so the
same evidence helpers are available to package tests and terminal validation:

```bash
swift run instant-swift-data validation local-todos --jsonl
swift run instant-swift-data validation local-integrations --jsonl
swift run instant-swift-data validation reminders --jsonl
swift run instant-swift-data validation cloudkit-demo --jsonl
swift run instant-swift-data validation live-session --jsonl
swift run instant-swift-data validation live-transaction --jsonl
swift run instant-swift-data validation typed-drafts --jsonl
swift run instant-swift-data validation platform-adapters --jsonl
swift run instant-swift-data validation syncups-recording --jsonl
swift run instant-swift-data validation parity-report --jsonl
swift run instant-swift-data validation coverage --jsonl
swift run instant-swift-data-validation-runner --local-todos
swift run instant-swift-data-validation-runner --local-integrations
swift run instant-swift-data-validation-runner --reminders
swift run instant-swift-data-validation-runner --cloudkit-demo
swift run instant-swift-data-validation-runner --live-session
swift run instant-swift-data-validation-runner --live-transaction
swift run instant-swift-data validation reminders --jsonl | jq 'select(.event == "search-token-model") | .details.searchTokens'
swift run instant-swift-data-validation-runner --typed-drafts
swift run instant-swift-data-validation-runner --platform-adapters
swift run instant-swift-data-validation-runner --syncups-recording
swift run instant-swift-data-validation-runner --parity-report
swift run instant-swift-data-validation-runner --coverage
swift run instant-swift-data-benchmarks --suite local-todos --iterations 1 --jsonl
```

Macro snapshot tests use Point-Free's MacroTesting library in the package's
dedicated macro test target:

```bash
validation/run-macro-tests.sh
```

Validation commands that accept `--jsonl` emit the JSON Lines evidence format
below. `validation reminders` covers local Reminders search, tag suggestions,
tag-token search, tags, rich fields, smart-list stats, list sharing roles,
permission rejections, writer updates, and relaunch persistence. Real InstantDB
and Swift/TypeScript boundary cases remain required for final acceptance.

## Local Swift Fixture Evidence

The Swift fixture source names the canonical
`InstantSchemaExamples.validationDocument` and
`InstantSchemaExamples.validationPermissions` values:

```bash
sed -n '1,80p' validation/fixtures/schema.swift
```

`validation/run-e2e.sh` generates schema/perms artifacts from that Swift-owned
example and verifies both the generated files and the committed TypeScript
fixtures:

```bash
swift run instant-swift-data schema generate --example validation --to validation.generated.schema.ts --json
swift run instant-swift-data perms generate --example validation --to validation.generated.perms.ts --json
swift run instant-swift-data schema verify --example validation --from validation/fixtures/instant.schema.ts --json
swift run instant-swift-data perms verify --example validation --from validation/fixtures/instant.perms.ts --json
```

## Local TypeScript Fixture Evidence

The TypeScript contract uses a committed pnpm lockfile and exact versions tied
to pinned upstream revision `e71017612aed4031710a35e2fcace30d38d557ac`:
`@instantdb/core` 1.0.49, `@instantdb/admin` 1.0.49, `instant-cli` 1.0.49,
and TypeScript 5.9.3. Install and run the generated/pulled artifact compiler
gate with:

```bash
pnpm --dir validation/ts-runner install --frozen-lockfile
pnpm --dir validation/ts-runner test
```

The type-check row contains the pinned revisions, zero compiler-warning count,
and SHA-256 hashes for generated and server-readback schema and permissions.

From a clean worktree, the live contract command creates a temporary Instant
app, pushes the Swift-generated `recording-action` schema and permissions,
pulls both through the pinned canonical CLI, verifies the normalized Swift
documents, type-checks the pulled TypeScript, removes the retained admin-token
file, and writes non-secret evidence:

```bash
validation/verify-recording-contract-live.sh
```

The same command runs the recording graph in both SDK directions. Swift writes
the owner/member/recording/transcription/attachment graph through its normal
live transaction path and the canonical TypeScript SDK queries the exact nested
values. The canonical TypeScript SDK then writes and finishes a second graph
while Swift's normal live observer decodes and projects the exact refreshed
values. The aggregate evidence fails unless both shapes match, both child
commands succeed, the worktree is clean, and the warning lists are empty. A
clean passing example for commit `771ed4c` is
`/private/tmp/instant-data-swift-recording-bidirectional-clean-771ed4c-20260718/evidence.json`.

Instant-managed `$files`, `$streams`, `$users` attributes, and system links are
reported with stable `system-entity`, `system-attribute`, and `system-link`
warning codes. Unexpected application entities, attributes, link semantics,
or rooms fail verification.

The TypeScript runner parses and compares the committed `instant.schema.ts` and
`instant.perms.ts` fixture shapes from the TypeScript side and emits JSONL
evidence without requiring an Instant app or admin token:

```bash
node validation/ts-runner/src/main.ts --fixtures
INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR=/tmp/instant-validation-results validation/run-e2e.sh
node validation/ts-runner/src/main.ts --swift-transport-contract /tmp/instant-validation-results/swift-transport-contract.json --app-id local-validation
INSTANT_APP_ID=local-validation swift run instant-swift-data validation local-integrations --jsonl > /tmp/instant-validation-results/swift-local-integrations.jsonl
node validation/ts-runner/src/main.ts --swift-local-integrations-contract /tmp/instant-validation-results/swift-local-integrations.jsonl --app-id local-validation
INSTANT_APP_ID=local-validation swift run instant-swift-data validation typed-drafts --jsonl > /tmp/instant-validation-results/swift-typed-drafts.jsonl
node validation/ts-runner/src/main.ts --swift-typed-drafts-contract /tmp/instant-validation-results/swift-typed-drafts.jsonl --app-id local-validation
node validation/ts-runner/src/main.ts --swift-live-session-contract /tmp/instant-validation-results/swift-live-session.jsonl --app-id local-validation
swift run instant-swift-data validation live-transaction --jsonl
node validation/ts-runner/src/main.ts --swift-live-transaction-contract /tmp/instant-validation-results/swift-live-transaction.jsonl --app-id local-validation
swift run instant-swift-data validation live-observe --jsonl
node validation/ts-runner/src/main.ts --boundary-preflight
INSTANT_SWIFT_DATA_REMOTE_APP_ID=your-app-id INSTANT_ADMIN_TOKEN=your-admin-token node validation/ts-runner/src/main.ts --boundary-admin-smoke --require-boundary
INSTANT_SWIFT_DATA_REMOTE_APP_ID=your-app-id INSTANT_ADMIN_TOKEN=your-admin-token node validation/ts-runner/src/main.ts --boundary-swift-live-observe --require-boundary
INSTANT_SWIFT_DATA_REMOTE_APP_ID=your-app-id INSTANT_ADMIN_TOKEN=your-admin-token node validation/ts-runner/src/main.ts --boundary-typescript-live-observe --require-boundary
INSTANT_APP_ID=your-app-id INSTANT_ADMIN_TOKEN=your-admin-token INSTANT_SWIFT_DATA_RUN_LIVE_SESSION=1 swift run instant-swift-data validation live-session --jsonl
INSTANT_APP_ID=your-app-id INSTANT_ADMIN_TOKEN=your-admin-token INSTANT_SWIFT_DATA_RUN_LIVE_TRANSACTION=1 swift run instant-swift-data validation live-transaction --jsonl
INSTANT_APP_ID=your-app-id INSTANT_ADMIN_TOKEN=your-admin-token INSTANT_SWIFT_DATA_RUN_LIVE_OBSERVE=1 swift run instant-swift-data validation live-observe --jsonl
INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR=/tmp/instant-validation-results INSTANT_SWIFT_DATA_REMOTE_APP_ID=your-app-id INSTANT_ADMIN_TOKEN=your-admin-token INSTANT_SWIFT_DATA_RUN_LIVE_BOUNDARY=1 INSTANT_SWIFT_DATA_RUN_TYPESCRIPT_LIVE_BOUNDARY=1 validation/run-e2e.sh
INSTANT_SWIFT_DATA_COVERAGE_ARTIFACTS_DIR=/tmp/instant-validation-results swift run instant-swift-data validation coverage --json
```

When running from launchd or another sparse shell environment, point the harness
at a concrete Node binary:

```bash
INSTANT_SWIFT_DATA_NODE=/path/to/node validation/run-e2e.sh
```

The fixture rows include exact expected/actual evidence for entities, fields,
field modifiers, links, room presence/topic shapes, permission namespaces, and
allowed operations. Platform adapter evidence also records dynamic reload,
nil-query, cached-prior-error, and cancellation-cleanup probes for `@FetchAll`,
plus filtered active-row reloads through `@FetchAll` and `@Fetch`.
`validation/run-e2e.sh` records all Swift local validation
streams (`swift-local.jsonl`, `swift-local-integrations.jsonl`,
`swift-server-transaction-loopback.jsonl`, `swift-cloudkit-demo.jsonl`,
`swift-live-session.jsonl`, `swift-live-transaction.jsonl`,
`swift-live-observe.jsonl`,
`swift-reminders.jsonl`, `swift-typed-drafts.jsonl`, `swift-platform-adapters.jsonl`,
`swift-syncups-recording.jsonl`, and `swift-parity-report.jsonl`), records the
compact coverage gate as
`swift-coverage.jsonl`, records a post-boundary artifact-aware gate as
`swift-coverage-final.jsonl`, records Swift schema/perms generation and verification
artifacts (`swift-schema-generate.json`,
`swift-perms-generate.json`, `swift-schema-verify.json`,
`swift-perms-verify.json`, `swift-generated-schema-verify.json`, and
`swift-generated-perms-verify.json`), records the MacroTesting run as
`swift-macro-tests.log`, records the local benchmark evidence, and then runs
the TypeScript fixture and contract checks when Node is available. The local
integration contract check writes `typescript-local-integrations-contract.jsonl`
after TypeScript validates Swift's room presence/topic evidence. The typed
drafts contract check writes `typescript-typed-drafts-contract.jsonl` after
TypeScript validates Swift's nil-id draft create, `Draft(existing)` edit,
relation ref metadata, pending mutation shape, and relaunch persistence. The
transport contract check writes `typescript-transport-contract.jsonl` as
contract-only evidence; it proves the local Swift outbox lowering can be
consumed from TypeScript, not that Instant has accepted the mutation. The live-session
contract check writes
`typescript-live-session-contract.jsonl` after TypeScript validates Swift's
WebSocket protocol evidence. `instant-swift-data validation live-transaction`
proves the upstream `transact` / `transact-ok` / `refresh-ok` WebSocket message
shape locally by default, and TypeScript records
`typescript-live-transaction-contract.jsonl` after validating that transcript;
set `INSTANT_SWIFT_DATA_RUN_LIVE_TRANSACTION=1` to send that mutation to the
configured WebSocket app. The server transaction
contract writes
`typescript-server-transaction-contract.json` and
`typescript-server-transaction-contract.jsonl`, then Swift consumes it into
`swift-typescript-server-transaction-contract.jsonl`. The preflight writes
`typescript-boundary.jsonl`; set
`INSTANT_SWIFT_DATA_REMOTE_APP_ID` or `INSTANT_APP_ID`, plus
`INSTANT_ADMIN_TOKEN` or `INSTANTDB_ADMIN_TOKEN`, and add
`INSTANT_SWIFT_DATA_REQUIRE_REMOTE_PREFLIGHT=1` to make missing credentials fail
the orchestration run. Optional preflight checks credential-shaped inputs and
endpoint syntax only; required mode runs `--boundary-admin-smoke`, opens
Instant's admin SSE subscription endpoint, writes through admin transact,
observes the refresh, and confirms the row with admin query. Set
`INSTANT_SWIFT_DATA_RUN_LIVE_BOUNDARY=1` to add
`--boundary-swift-live-observe`: the TypeScript runner seeds the `todos` attrs,
opens admin SSE for a unique Swift validation row, runs Swift's live WebSocket
transaction command, and confirms TypeScript observed the Swift-authored row.
Set `INSTANT_SWIFT_DATA_RUN_TYPESCRIPT_LIVE_BOUNDARY=1` to add
`--boundary-typescript-live-observe`: the TypeScript runner opens Swift's live
WebSocket observer, writes a unique todo through admin HTTP, and requires Swift
to observe that external refresh.
When both opt-in live boundary modes have produced
`typescript-swift-boundary.jsonl` and `swift-typescript-boundary.jsonl`, rerun
`INSTANT_SWIFT_DATA_COVERAGE_ARTIFACTS_DIR=/tmp/instant-validation-results swift run instant-swift-data validation coverage --json`
to promote the two live-transport parity records from blocked to adapted. The
same fallback works with `INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR`; the e2e
harness writes this final artifact-aware gate to `swift-coverage-final.jsonl`
automatically after the TypeScript boundary section.
Set `INSTANT_SWIFT_DATA_LIVE_BOUNDARY_SWIFT_TIMEOUT_MS` if a cold SwiftPM build
needs more than the default 30 seconds.
Set
`INSTANT_SWIFT_DATA_RUN_LIVE_SESSION=1` to make the Swift live-session smoke
use Instant's real WebSocket endpoint instead of the deterministic local
protocol client.
Set
`INSTANT_SWIFT_DATA_VALIDATION_RESULTS_DIR` to direct artifacts to a specific
directory, and
`INSTANT_SWIFT_DATA_VALIDATION_BENCHMARK_ITERATIONS` to adjust the benchmark
iteration count. The parity report command can succeed while individual blocked
provenance rows intentionally carry `ok: false`; the orchestrator records the
artifact command result, not an all-rows-passed summary. The coverage stream is
the one-row gate to use when a caller needs blocked IDs and aggregate parity
counts. The static coverage stream still records the real Instant live transport
boundary as blocked until credentialed artifacts are present, while
`INSTANT_SWIFT_DATA_RUN_LIVE_BOUNDARY=1` and
`INSTANT_SWIFT_DATA_RUN_TYPESCRIPT_LIVE_BOUNDARY=1` can capture those artifacts
against an existing app.

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
