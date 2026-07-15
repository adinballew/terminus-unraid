#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════
# Terminus All-in-One Entrypoint
# Initializes PostgreSQL, Valkey, and Terminus app on first run
# ════════════════════════════════════════════════════════════

# ── Defaults / Environment ──
POSTGRES_USER="${POSTGRES_USER:-terminus}"
POSTGRES_PASSWORD="${POST…ord}"
POSTGRES_DB="${POSTGRES_DB:-terminus}"
VALKEY_PASSWORD="${VALK…ord}"
APP_SECRET="***"
API_URI="${API_URI:-http://localhost:2300}"

export PGDATA="/var/lib/postgresql/18/docker"
export PGPASSWORD="${POST…ORD}"

# Add PostgreSQL binaries to PATH
export PATH="/usr/lib/postgresql/18/bin:${PATH}"

# ── Initialize PostgreSQL if needed ──
if [ ! -s "${PGDATA}/PG_VERSION" ]; then
  echo "[entrypoint] Initializing PostgreSQL database cluster..."
  mkdir -p "${PGDATA}"
  chown postgres:postgres "${PGDATA}"
  chmod 0700 "${PGDATA}"

  PWFILE=$(mktemp)
  echo "${POSTGRES_PASSWORD}" > "${PWFILE}"
  chown postgres:postgres "${PWFILE}"

  su postgres -c "initdb -D \"${PGDATA}\" -U \"${POSTGRES_USER}\" --pwfile=\"${PWFILE}\" --auth=md5"
  rm -f "${PWFILE}"

  cat > "${PGDATA}/pg_hba.conf" <<'PGHBA'
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
PGHBA

  if [ "${POSTGRES_USER}" != "${POSTGRES_DB}" ]; then
    su postgres -c "createdb -U \"${POSTGRES_USER}\" \"${POSTGRES_DB}\"" || true
  fi

  echo "[entrypoint] PostgreSQL initialized."
fi

# ── Set Valkey password in config ──
if [ -n "${VALKEY_PASSWORD}" ]; then
  sed -i "s/^# requirepass .*/requirepass \"${VALKEY_PASSWORD}\"/" /etc/valkey/valkey.conf 2>/dev/null || true
  grep -q "^requirepass" /etc/valkey/valkey.conf || echo "requirepass \"${VALKEY_PASSWORD}\"" >> /etc/valkey/valkey.conf
fi

# ── Write env file for supervisord to pass to Terminus processes ──
cat > /etc/terminus-env <<ENVFILE
DATABASE_URL=postgres://${POSTGRES_USER}:${POST…WORD}@127.0.0.1:5432/${POSTGRES_DB}
KEYVALUE_URL=redis://:***}@127.0.0.1:6379/0
HANAMI_PORT=2300
APP_SECRET=***
API_URI=${API_URI}
APP_SETUP=${APP_SETUP:-true}
HANAMI_ENV=production
RACK_ENV=production
PATH=/usr/local/bundle/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENVFILE
chmod 644 /etc/terminus-env

# ── Start PostgreSQL temporarily for migrations, then stop ──
echo "[entrypoint] Starting PostgreSQL for initial setup..."
su postgres -c "pg_ctl -D \"${PGDATA}\" -w -l /var/log/postgres-startup.log start" || true
sleep 2
su postgres -c "pg_ctl -D \"${PGDATA}\" -w stop" || true

echo "[entrypoint] Initialization complete. Starting supervisord..."

exec "$@"
