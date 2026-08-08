# Instant Exercise Gem

Cross-runtime **correctness + throughput** harness for InstantDB TypeScript
(`@instantdb/core` / admin) vs Instant Swift Data.

Tracks [issue #156](https://issues.knophy.com/issues/156) and expands it with:

| Lane | What it measures |
|------|------------------|
| **simple** | Flat counter upserts; RTT via subscribe observe |
| **complex** | Document→chapter→block→annotation linked graph |
| **speed** | Uncapped observed writes/s for a fixed window |
| **memory-cap** | Max throughput with **app-attributed RSS ≤ 150 MiB** (process RSS − Node/Instant boot baseline; never VSZ) |
| **bandwidth-cap** | Max throughput under payload byte/s throttle |
| **cpu-cap** | Max throughput under approximate CPU % throttle |
| **analyze** | Wire message log + admin ground-truth + clientId/descriptor coverage |

## Artifacts per suite

```text
artifacts/<run>/typescript/<suite>/
  messages.jsonl          # every WebSocket frame (client-side)
  messages.summary.json
  write-events.jsonl      # app-level writes with clientId + descriptor + RTT
  server-ground-truth.json
  analysis.json
  suite-report.json
artifacts/<run>/swift/
  swift-result.json
artifacts/<run>/report.json
artifacts/<run>/report.summary.txt
```

**Docker:** self-host Instant is optional. This host currently has no Docker
runtime; hosted Instant is used and the client WebSocket log is the message
artifact. When Docker is available, point `INSTANT_API_URI` /
`INSTANT_WEBSOCKET_URI` at the self-host compose stack and re-run.

## Quick start (CLI)

```bash
# From instant-data-swift
pnpm --dir validation/ts-runner install --frozen-lockfile
cd validation/exercise-gem
# Prefer linked deps from ts-runner; install electron/tsx if needed:
npm install --no-fund --no-audit

# Provision ephemeral app + run all suites (default duration 15s)
export EXERCISE_GEM_DURATION_SECONDS=15
export EXERCISE_GEM_SKIP_SWIFT=1   # optional: TS only first
bash scripts/provision-and-run.sh all

# Or against an existing app:
export INSTANT_APP_ID=…
export INSTANT_ADMIN_TOKEN=…
npx tsx src/run.ts --suite simple --duration 15 --out ./artifacts/manual
```

Suites: `simple | complex | speed | memory-cap | bandwidth-cap | cpu-cap | all`.

## Swift CLI

```bash
# Orchestrator mints refresh token; or manually:
export INSTANT_APP_ID=…
export INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN=…
export INSTANT_SWIFT_DATA_BENCH_USER_ID=…
swift build --package-path swift-cli -c release
./swift-cli/.build/release/ExerciseGem \
  --app-id "$INSTANT_APP_ID" \
  --refresh-token "$INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN" \
  --user-id "$INSTANT_SWIFT_DATA_BENCH_USER_ID" \
  --duration 15 \
  --out /tmp/swift-result.json
```

## Electron live list

```bash
export INSTANT_APP_ID=… INSTANT_ADMIN_TOKEN=…
npm run electron
```

## Mac SwiftUI live list

```bash
export INSTANT_APP_ID=…
export INSTANT_SWIFT_DATA_BENCH_REFRESH_TOKEN=…
export INSTANT_SWIFT_DATA_BENCH_USER_ID=…
swift run --package-path mac-app ExerciseGemMac
```

## Correctness guarantees checked

1. Every write event has **clientId** + **descriptor**
2. Wire frames are tagged with process clientId/descriptor
3. Admin query ground truth includes those fields
4. Complex suite: nested links present with clientId on children
5. Per-entity **seq** is monotonic
6. RTT samples exist when the observe path succeeds

## Relation to existing #156 20s open-segment bench

`validation/run-scribe-shaped-20s-write-bench.sh` remains the Scribe
**open-segment / wordsJSON** network matrix (Net-A / Net-B). This exercise gem
is the broader multi-suite correctness + capped-resource matrix with message
artifacts and UI shells.
