# syntax=docker/dockerfile:1
ARG BUN_VERSION=1.3.14
ARG PI_REPO=https://github.com/clssck/oh-my-pi.git
ARG PI_REF=9e9728e76a5a3847de433611594c5ffd43d4d359

FROM debian:bookworm-slim AS pi-src
ARG PI_REPO
ARG PI_REF
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates \
 && rm -rf /var/lib/apt/lists/*
RUN GIT_LFS_SKIP_SMUDGE=1 git clone --filter=blob:none "${PI_REPO}" /pi \
 && git -C /pi checkout "${PI_REF}"

FROM rust:1.86-slim-bookworm AS natives-builder
ARG BUN_VERSION
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates pkg-config libssl-dev unzip git \
 && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}" \
 && /root/.bun/bin/bun --version
ENV PATH="/root/.bun/bin:/usr/local/cargo/bin:${PATH}"
WORKDIR /pi
COPY --from=pi-src /pi /pi
RUN bun install --frozen-lockfile --ignore-scripts
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/pi/target \
    set -eux; \
    rustup show; \
    bun --cwd=packages/natives run build; \
    mkdir -p /out; \
    cp packages/natives/native/pi_natives.linux-*.node /out/

FROM oven/bun:${BUN_VERSION}-slim AS runtime
ENV PI_ROOT=/pi \
    HOME=/data
RUN apt-get update \
 && apt-get install -y --no-install-recommends bash ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY --from=pi-src /pi /pi
WORKDIR /pi
RUN bun install --frozen-lockfile --ignore-scripts
RUN bun --cwd=packages/coding-agent run generate-docs-index
RUN bun --cwd=packages/collab-web run build:tool-views
COPY --from=natives-builder /out/pi_natives.linux-*.node /opt/bun/bin/
RUN cp /opt/bun/bin/pi_natives.linux-*.node /usr/local/bin/ \
 && cp /opt/bun/bin/pi_natives.linux-*.node /pi/packages/natives/native/
RUN printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    ': "${PI_ROOT:=/pi}"' \
    'if [ ! -d "$PI_ROOT/packages/coding-agent" ]; then' \
    '  echo "pi: PI_ROOT=$PI_ROOT does not look like a pi checkout" >&2' \
    '  exit 127' \
    'fi' \
    'exec bun "$PI_ROOT/packages/coding-agent/src/cli.ts" "$@"' \
    > /usr/local/bin/omp \
 && chmod +x /usr/local/bin/omp

# omp's config root is $HOME/.omp. Mount a volume at /data/.omp to persist the
# credential vault (agent/agent.db) and the broker bearer token across restarts.
WORKDIR /data

# ENTRYPOINT is the omp wrapper; CMD defaults to running the auth-broker so the
# container Just Works with an empty "Command" field in the deploy UI.
ENTRYPOINT ["omp"]
CMD ["auth-broker", "serve", "--bind", "0.0.0.0:8765"]
