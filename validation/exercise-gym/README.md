# Instant Exercise Gym

Cross-runtime **correctness + throughput** gym for InstantDB TypeScript
(`@instantdb/core` / admin) vs Instant Swift Data.

A **gym** is a training/measurement harness — not a Ruby gem.

Tracks [issue #156](https://issues.knophy.com/issues/156).

## Self-host Instant (Docker)

```bash
# Start Instant on localhost (API :8888, dashboard :3000, postgres :8890)
# docker-up.sh writes gitignored docker/.env with generated local passwords
# if that file is missing. Compose has no committed password defaults.
bash scripts/docker-up.sh

# Provision ephemeral app on self-host + run all suites
EXERCISE_GYM_SELF_HOST=1 EXERCISE_GYM_DURATION_SECONDS=15 \
  bash scripts/provision-and-run.sh all

# Export server logs + postgres inventory anytime
bash scripts/export-server-artifacts.sh

# Stop
bash scripts/docker-down.sh
```

Health: `curl -fsS http://localhost:8888/health/system` → `{"wal":"ok"}`.

Server artifacts (per run when self-host is up):

```text
artifacts/<run>/run/server/
  health.json
  server.logs.txt
  server.interesting-lines.txt   # transact / magic-code / error lines
  postgres-public-tables.txt
  compose-ps.json
```

Without Docker, the gym still runs against Instant Cloud with full client
WebSocket message logs.

## Suites

| Lane | What it measures |
|------|------------------|
| **simple** | Flat counter upserts; RTT via observe / server acceptance |
| **complex** | Document→chapter→block→annotation linked graph (TS + Swift) |
| **speed** | Uncapped observed writes/s |
| **memory-cap** | Max throughput with app-attributed RSS ≤ 150 MiB |
| **bandwidth-cap** | Payload byte/s throttle |
| **cpu-cap** | Approximate CPU % throttle |

Memory: process RSS − boot baseline (never VSZ).

## CLI

```bash
export INSTANT_APP_ID=… INSTANT_ADMIN_TOKEN=…
# optional self-host:
export INSTANT_API_URI=http://localhost:8888
export INSTANT_WEBSOCKET_URI=ws://localhost:8888/runtime/session

npx tsx src/run.ts --suite all --duration 15 --out ./artifacts/manual
npx tsx src/run.ts --suite complex --duration 10
npx tsx src/run.ts --suite simple --swift-only
```

### Swift only

```bash
swift build --package-path swift-cli -c release
./swift-cli/.build/release/ExerciseGym \
  --suite complex \
  --app-id "$INSTANT_APP_ID" \
  --refresh-token "$TOKEN" --user-id "$USER_ID" \
  --api-uri http://localhost:8888 \
  --websocket-uri ws://localhost:8888/runtime/session \
  --duration 15 --out /tmp/swift-complex.json
```

## UIs

```bash
npm run electron          # Electron live list
swift run --package-path mac-app ExerciseGemMac   # Mac SwiftUI live list
```

## Correctness checks

1. Every write event has **clientId** + **descriptor**
2. Wire frames tagged with process clientId
3. Admin (or self-host) ground truth includes those fields
4. Complex: nested links present with clientId on children
5. Per-entity **seq** monotonic
6. RTT / server-acceptance samples when observe path succeeds
