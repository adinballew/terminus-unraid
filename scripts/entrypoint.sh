#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════
# Terminus All-in-One Entrypoint
# Initializes PostgreSQL, Valkey, and Terminus app on first run
# ════════════════════════════════════════════════════════════

# ── Defaults / Environment ──
POSTGRES_USER="${POSTGRES_USER:-terminus}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-terminus_password}"
POSTGRES_DB="${POSTGRES_DB:-terminus}"
VALKEY_PASSWORD="${VALKEY_PASSWORD:-valkey_password}"
APP_SECRET="${APP_SECRET:-$(openssl rand -hex 32)}"
API_URI="${API_URI:-http://localhost:2300}"

export PGDATA="/var/lib/postgresql/18/docker"
export PGPASSWORD="${POSTGRES_PASSWORD}"

# ── Initialize PostgreSQL if needed ──
if [ ! -s "${PGDATA}/PG_VERSION" ]; then
  echo "[entrypoint] Initializing PostgreSQL database cluster..."
  mkdir -p "${PGDATA}"
  chown postgres:postgres "${PGDATA}"
  chmod 0700 "${PGDATA}"

  su postgres -c "initdb -D \"${PGDATA}\" -U \"${POSTGRES_USER}\" --pwfile=<(echo \"${POSTGRES_PASSWORD}\")"

  # Configure pg_hba to allow local connections with password
  cat > "${PGDATA}/pg_hba.conf" <<'PGHBA'
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
PGHBA

  # Create database if not default user/db
  if [ "${POSTGRES_USER}" != "${POSTGRES_DB}" ]; then
    su postgres -c "createdb -U \"${POSTGRES_USER}\" \"${POSTGRES_DB}\""
  fi

  echo "[entrypoint] PostgreSQL initialized."
fi

# ── Set Valkey password in config ──
if [ -n "${VALKEY_PASSWORD}" ]; then
  sed -i "s/^# requirepass .*/requirepass \"${VALKEY_PASSWORD}\"/" /etc/valkey/valkey.conf 2>/dev/null || true
  # Append if not present
  grep -q "^requirepass" /etc/valkey/valkey.conf || echo "requirepass \"${VALKEY_PASSWORD}\"" >> /etc/valkey/valkey.conf
fi

# ── Set Terminus environment variables ──
export DATABASE_URL="postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:5432/${POSTGRES_DB}"
export KEYVALUE_URL="redis://:${VALKEY_PASSWORD}@127.0.0.1:6379/0"
export HANAMI_PORT="2300"
export APP_SECRET
export API_URI
export APP_SETUP="${APP_SETUP:-true}"

# ── Wait for PostgreSQL to be ready before starting Terminus ──
# (supervisord will handle restarts, but we give PG a head start)
echo "[entrypoint] Starting PostgreSQL first for initial setup..."
su postgres -c "pg_ctl -D \"${PGDATA}\" -w -l /var/log/postgres-startup.log start" || true

# Give it a moment to be ready
sleep 2

# Stop it so supervisord can manage it
su postgres -c "pg_ctl -D \"${PGDATA}\" -w stop" || true

echo "[entrypoint] Initialization complete. Starting supervisord..."

# ── Hand off to supervisord ──
exec "$@"
