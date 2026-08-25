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

if [[ ! -f .env ]]; then
  postgres_user="${POSTGRES_USER:-instant}"
  postgres_db="${POSTGRES_DB:-instant}"
  postgres_password="$(openssl rand -hex 16)"
  minio_user="${MINIO_ROOT_USER:-instantminio}"
  minio_password="$(openssl rand -hex 16)"
  umask 077
  cat > .env <<EOF
POSTGRES_USER=${postgres_user}
POSTGRES_DB=${postgres_db}
POSTGRES_PASSWORD=${postgres_password}
GYM_PG_AUTH=${postgres_password}
MINIO_ROOT_USER=${minio_user}
MINIO_ROOT_PASSWORD=${minio_password}
GYM_OBJECT_STORE_USER=${minio_user}
GYM_OBJECT_STORE_AUTH=${minio_password}
AWS_ACCESS_KEY_ID=${minio_user}
AWS_SECRET_ACCESS_KEY=${minio_password}
DATABASE_URL=postgresql://${postgres_user}:${postgres_password}@postgres:5432/${postgres_db}?sslmode=disable
GYM_DATABASE_DSN=postgresql://${postgres_user}:${postgres_password}@postgres:5432/${postgres_db}?sslmode=disable
EOF
  echo "Wrote gitignored docker/.env with generated local-only credentials."
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
