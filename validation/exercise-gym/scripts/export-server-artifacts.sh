#!/usr/bin/env bash
# Export Instant Docker server logs + postgres inventory into an artifacts dir.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-${ROOT}/artifacts/server-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "${OUT}"
cd "${ROOT}/docker"

curl -fsS "http://localhost:8888/health/system" >"${OUT}/health.json" || true
docker compose --env-file .env ps >"${OUT}/compose-ps.txt" || true
docker compose --env-file .env logs --no-color --tail 10000 server >"${OUT}/server.logs.txt" 2>&1 || true
# Login codes / errors often land in server stdout when Postmark is unset
rg -i "transact|mutation|error|denied|magic|code|client-event|tx-id" "${OUT}/server.logs.txt" \
  >"${OUT}/server.interesting-lines.txt" || true

docker compose --env-file .env exec -T postgres \
  psql -U instant -d instant -c "\dt" >"${OUT}/postgres-tables.txt" 2>&1 || true
docker compose --env-file .env exec -T postgres \
  psql -U instant -d instant -c \
  "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY 1;" \
  >"${OUT}/postgres-public-tables.txt" 2>&1 || true

# Best-effort samples of common Instant table names if present
for t in transactions txs triples attrs apps app_users; do
  docker compose --env-file .env exec -T postgres \
    psql -U instant -d instant -c "SELECT count(*) FROM ${t};" \
    >"${OUT}/count-${t}.txt" 2>&1 || true
done

echo "Server artifacts → ${OUT}"
