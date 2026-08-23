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

required_env_keys=(
  GYM_PG_AUTH
  GYM_OBJECT_STORE_AUTH
  GYM_DATABASE_DSN
  POSTGRES_PASSWORD
  MINIO_ROOT_PASSWORD
  AWS_SECRET_ACCESS_KEY
  DATABASE_URL
)

needs_env_write=0
if [[ ! -f .env ]]; then
  needs_env_write=1
else
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
  for key in "${required_env_keys[@]}"; do
    if [[ -z "${!key:-}" ]]; then
      needs_env_write=1
      break
    fi
  done
fi

if [[ "${needs_env_write}" -eq 1 ]]; then
  postgres_user="${POSTGRES_USER:-instant}"
  postgres_db="${POSTGRES_DB:-instant}"
  postgres_auth="${GYM_PG_AUTH:-${POSTGRES_PASSWORD:-}}"
  minio_user="${MINIO_ROOT_USER:-instantminio}"
  minio_auth="${GYM_OBJECT_STORE_AUTH:-${MINIO_ROOT_PASSWORD:-}}"
  database_dsn="${GYM_DATABASE_DSN:-${DATABASE_URL:-}}"

  if [[ -z "${postgres_auth}" ]]; then
    postgres_auth="$(openssl rand -hex 16)"
  fi
  if [[ -z "${minio_auth}" ]]; then
    minio_auth="$(openssl rand -hex 16)"
  fi
  if [[ -z "${postgres_auth}" || -z "${minio_auth}" ]]; then
    echo "Failed to produce gym credential material. Refusing to start." >&2
    exit 1
  fi
  if [[ -z "${database_dsn}" ]]; then
    database_dsn="postgresql://${postgres_user}:${postgres_auth}@postgres:5432/${postgres_db}?sslmode=disable"
  fi

  umask 077
  cat > .env <<EOF
POSTGRES_USER=${postgres_user}
POSTGRES_DB=${postgres_db}
POSTGRES_PASSWORD=${postgres_auth}
GYM_PG_AUTH=${postgres_auth}
MINIO_ROOT_USER=${minio_user}
MINIO_ROOT_PASSWORD=${minio_auth}
GYM_OBJECT_STORE_USER=${minio_user}
GYM_OBJECT_STORE_AUTH=${minio_auth}
AWS_ACCESS_KEY_ID=${minio_user}
AWS_SECRET_ACCESS_KEY=${minio_auth}
DATABASE_URL=${database_dsn}
GYM_DATABASE_DSN=${database_dsn}
EOF
  echo "Wrote gitignored docker/.env with generated local-only credentials."
fi

for key in "${required_env_keys[@]}"; do
  if ! grep -qE "^${key}=.+" .env; then
    echo "docker/.env is missing ${key}. Refusing to start." >&2
    exit 1
  fi
done

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
