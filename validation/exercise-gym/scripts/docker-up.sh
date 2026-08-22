#!/usr/bin/env bash
# Start Instant self-host for the Exercise Gym on localhost.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}/docker"

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon not running. Opening Docker Desktop…" >&2
  open -a Docker || true
  for i in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then break; fi
    sleep 2
  done
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker still unavailable." >&2
  exit 1
fi

docker compose --env-file .env up -d
echo "Waiting for Instant health on http://localhost:8888/health/system …"
for i in $(seq 1 90); do
  if curl -fsS "http://localhost:8888/health/system" >/tmp/instant-gym-health.json 2>/dev/null; then
    echo "Healthy: $(cat /tmp/instant-gym-health.json)"
    echo "API:       http://localhost:8888"
    echo "Dashboard: http://localhost:3000"
    echo "Postgres:  localhost:8890 (user=instant db=instant)"
    echo "MinIO:     http://localhost:9000"
    exit 0
  fi
  sleep 2
done
echo "Timed out waiting for health. Recent server logs:" >&2
docker compose --env-file .env logs --tail 80 server >&2 || true
exit 1
