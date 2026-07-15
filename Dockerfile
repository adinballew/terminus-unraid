# syntax=docker/dockerfile:1

# ─────────────────────────────────────────────────────────────
# Terminus All-in-One for Unraid
# Bundles: Terminus (Ruby Hanami) + PostgreSQL 18 + Valkey 9
# Base image is Debian-slim (ruby:4.0.6-slim)
# ─────────────────────────────────────────────────────────────

# ── Stage: Build Valkey from source (glibc-compatible) ──
FROM ghcr.io/usetrmnl/terminus:latest AS valkey-builder

USER root
RUN apt-get update -qq \
  && apt-get install --no-install-recommends -y build-essential tcl \
  && rm -rf /var/lib/apt/lists /var/cache/apt/archives

ARG VALKEY_VERSION=9.1.0
RUN curl -fsSL https://github.com/valkey-io/valkey/archive/refs/tags/${VALKEY_VERSION}.tar.gz | tar xz -C /tmp \
  && cd /tmp/valkey-${VALKEY_VERSION} \
  && make -j$(nproc) BUILD_TLS=yes \
  && make install \
  && rm -rf /tmp/valkey-${VALKEY_VERSION}

# ── Final stage: all-in-one ──
FROM ghcr.io/usetrmnl/terminus:latest AS final

USER root

# Install supervisor, PostgreSQL 18 server, locales, and tools via apt
# Base image already has the PGDG repo configured and postgresql-client-18 installed
RUN apt-get update -qq \
  && apt-get install --no-install-recommends -y \
    supervisor \
    locales \
    postgresql-18 \
    tzdata \
  && rm -rf /var/lib/apt/lists /var/cache/apt/archives \
  && echo "en_US.UTF-8 UTF-8" > /etc/locale.gen \
  && locale-gen \
  # Create postgres user if not exists
  && id postgres 2>/dev/null || useradd --system --gid 100 --home-dir /var/lib/postgresql postgres \
  && mkdir -p /var/lib/postgresql/18/docker \
  && chown -R postgres:postgres /var/lib/postgresql \
  && mkdir -p /var/run/postgresql \
  && chown postgres:postgres /var/run/postgresql

# Copy Valkey binaries built from source (glibc-linked)
COPY --from=valkey-builder /usr/local/bin/valkey-server /usr/local/bin/valkey-server
COPY --from=valkey-builder /usr/local/bin/valkey-cli /usr/local/bin/valkey-cli
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

ENV HANAMI_ENV=production \
    HANAMI_SERVE_ASSETS=true \
    RACK_ENV=production

EXPOSE 2300

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -sf http://localhost:2300/ || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
