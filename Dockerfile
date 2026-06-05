FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Self-contained omp binary (bundles auth-broker / auth-gateway).
# v15.9.2 is currently source-only on GitHub; pin to the latest published
# prebuilt binary so rebuilds are reproducible.
ENV PI_INSTALL_DIR=/usr/local/bin
RUN curl -fsSL https://omp.sh/install | sh -s -- --binary --ref v15.9.1

# omp's config root is $HOME/.omp. Mount a volume at /data/.omp to persist the
# credential vault (agent/agent.db) and the broker bearer token across restarts.
ENV HOME=/data
WORKDIR /data

# ENTRYPOINT is the omp binary; CMD defaults to running the auth-broker so the
# container Just Works with an empty "Command" field in the deploy UI. Override
# the command to run something else (e.g. `auth-gateway serve --bind 0.0.0.0:4000`).
ENTRYPOINT ["omp"]
CMD ["auth-broker", "serve", "--bind", "0.0.0.0:8765"]
