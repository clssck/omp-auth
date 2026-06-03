FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Self-contained omp binary (bundles auth-broker / auth-gateway).
# Pin a release for reproducible deploys, e.g.:
#   RUN curl -fsSL https://omp.sh/install | sh -s -- --binary --ref v15.8.3
ENV PI_INSTALL_DIR=/usr/local/bin
RUN curl -fsSL https://omp.sh/install | sh -s -- --binary

# omp's config root is $HOME/.omp. Mount a volume at /data/.omp to persist the
# credential vault (agent/agent.db) and the broker bearer token across restarts.
ENV HOME=/data
WORKDIR /data

ENTRYPOINT ["omp"]
