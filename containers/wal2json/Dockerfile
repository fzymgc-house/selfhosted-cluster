# syntax=docker/dockerfile:1
# wal2json extension image for CloudNativePG ImageVolume
# https://github.com/eulerto/wal2json

# Stage 1: Install wal2json from PGDG
FROM debian:trixie-slim AS builder

ARG PG_MAJOR=18

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg && \
    curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | \
      gpg --dearmor -o /usr/share/keyrings/pgdg.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] http://apt.postgresql.org/pub/repos/apt trixie-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      postgresql-${PG_MAJOR}-wal2json && \
    rm -rf /var/lib/apt/lists/*

# Stage 2: Create minimal extension image
# CNPG expects: /lib/*.so and /share/extension/*
FROM scratch

COPY --from=builder /usr/lib/postgresql/18/lib/wal2json.so /lib/
COPY --from=builder /usr/share/postgresql/18/extension/wal2json* /share/extension/
