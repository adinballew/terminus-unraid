# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────────────────────
# Terminus All-in-One for Unraid
# Bundles: Terminus (Ruby Hanami) + PostgreSQL 18 + Valkey 9
# ─────────────────────────────────────────────────────────────

FROM ghcr.io/usetrmnl/terminus:latest AS terminus-base

# ── Stage: PostgreSQL 18 client binaries ──
FROM postgres:18-alpine AS postgres-builder

# ── Stage: Valkey 9 ──
FROM valkey/valkey:9-alpine AS valkey-builder

# ── Final stage: all-in-one ──
FROM ghcr.io/usetrmnl/terminus:latest AS final

USER root

# Install supervisord, PostgreSQL 18, Valkey 9, and supporting tools
RUN apk add --no-cache \
    supervisor \
    postgresql18 \
    postgresql18-client \
    postgresql18-contrib \
    valkey \
    bash \
    curl \
    tzdata \
  && mkdir -p /var/lib/postgresql/18/docker \
  && chown -R postgres:postgres /var/lib/postgresql \
  && mkdir -p /var/run/postgresql \
  && chown postgres:postgres /var/run/postgresql \
  && mkdir -p /var/valkey \
  && chown valkey:valkey /var/valkey

# Copy Valkey config defaults
COPY config/valkey.conf /etc/valkey/valkey.conf

# Copy supervisord config
COPY config/supervisord.conf /etc/supervisord.conf

# Copy entrypoint
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Ensure Terminus app dirs exist and are owned by the app user
RUN mkdir -p /app/public/fonts /app/public/uploads /usr/share/fonts/terminus \
  && chown -R $(id -u):$(id -g) /app/public/fonts /app/public/uploads 2>/dev/null || true

# PostgreSQL data directory
ENV PGDATA=/var/lib/postgresql/18/docker

# Valkey data directory
ENV VALKEY_DATA=/var/valkey

# Expose Terminus web port
EXPOSE 2300

# Health check hits Terminus web
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -sf http://localhost:2300/ || exit 1

# Single entrypoint starts supervisord which manages all three processes
ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisord.conf"]
