# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────────────────────
# Terminus All-in-One for Unraid
# Bundles: Terminus (Ruby Hanami) + PostgreSQL 18 + Valkey 9
# Base image is Debian-slim (ruby:4.0.6-slim)
# ─────────────────────────────────────────────────────────────

# ── Stage: Copy Valkey binary from official Alpine image ──
FROM valkey/valkey:9-alpine AS valkey-bin

# ── Final stage: all-in-one ──
FROM ghcr.io/usetrmnl/terminus:latest AS final

USER root

# Install supervisor, PostgreSQL 18 server, and tools via apt
# Base image already has the PGDG repo configured and postgresql-client-18 installed
RUN apt-get update -qq \
  && apt-get install --no-install-recommends -y \
    supervisor \
    postgresql-18 \
    tzdata \
  && rm -rf /var/lib/apt/lists /var/cache/apt/archives \
  # Create postgres user if not exists
  && id postgres 2>/dev/null || useradd --system --gid 100 --home-dir /var/lib/postgresql postgres \
  && mkdir -p /var/lib/postgresql/18/docker \
  && chown -R postgres:postgres /var/lib/postgresql \
  && mkdir -p /var/run/postgresql \
  && chown postgres:postgres /var/run/postgresql

# Copy Valkey binary from Alpine stage
COPY --from=valkey-bin /usr/local/bin/valkey-server /usr/local/bin/valkey-server
COPY --from=valkey-bin /usr/local/bin/valkey-cli /usr/local/bin/valkey-cli
RUN chmod +x /usr/local/bin/valkey-server /usr/local/bin/valkey-cli \
  && groupadd --system valkey \
  && useradd --system --gid valkey --home-dir /var/valkey valkey \
  && mkdir -p /var/valkey \
  && chown valkey:valkey /var/valkey

# Copy Valkey config
COPY config/valkey.conf /etc/valkey/valkey.conf

# Copy supervisord config
COPY config/supervisord.conf /etc/supervisor/supervisord.conf

# Copy entrypoint
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Ensure Terminus app dirs exist
RUN mkdir -p /app/public/fonts /app/public/uploads /usr/share/fonts/terminus

# PostgreSQL data directory
ENV PGDATA=/var/lib/postgresql/18/docker

# Valkey data directory
ENV VALKEY_DATA=/var/valkey

EXPOSE 2300

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -sf http://localhost:2300/ || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
