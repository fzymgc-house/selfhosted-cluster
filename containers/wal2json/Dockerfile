# syntax=docker/dockerfile:1
# wal2json extension image for CloudNativePG ImageVolume
# https://github.com/eulerto/wal2json

# Stage 1: Install wal2json from PGDG
FROM debian:trixie-slim AS builder

ARG PG_MAJOR=18

# PGDG GPG key fingerprint for verification
# https://www.postgresql.org/media/keys/ACCC4CF8.asc
ENV PGDG_KEY_FINGERPRINT="B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc -o /tmp/pgdg.asc && \
    gpg --import --import-options show-only /tmp/pgdg.asc | \
      grep -q "${PGDG_KEY_FINGERPRINT}" || \
      (echo "GPG key fingerprint mismatch!" && exit 1) && \
    gpg --dearmor -o /usr/share/keyrings/pgdg.gpg < /tmp/pgdg.asc && \
    rm /tmp/pgdg.asc && \
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      postgresql-${PG_MAJOR}-wal2json && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Create minimal extension image
# CNPG expects: /lib/*.so and /share/extension/*
FROM scratch

ARG PG_MAJOR=18

COPY --from=builder /usr/lib/postgresql/${PG_MAJOR}/lib/wal2json.so /lib/
COPY --from=builder /usr/share/postgresql/${PG_MAJOR}/extension/wal2json* /share/extension/
