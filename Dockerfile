FROM node:22-bookworm

# System build deps:
#   build-essential/pkg-config/libssl-dev/python3 -> N-API native modules
#   git                                           -> VCS in dev environment
#   perl                                          -> openssl-dependent native builds
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        python3 \
        git \
        perl \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Rust toolchain pinned to a concrete version for reproducible builds.
# (was: "stable" which moves and breaks reproducibility across contributors)
ARG RUST_VERSION=1.83.0
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
        --default-toolchain ${RUST_VERSION} \
        --profile minimal \
        --target wasm32-unknown-unknown \
    && rustup component add rustfmt clippy \
    && chown -R node:node /usr/local/cargo /usr/local/rustup

# wasm-pack: pinned version, direct static tarball into /usr/local/bin.
# Replaces `curl ... | sh` run as root (supply-chain / non-reproducible).
# NOTE: tarball is x86_64-only; for multi-arch buildx (arm64) swap the asset
# to wasm-pack-v<ver>-aarch64-unknown-linux-musl.tar.gz.
ARG WASMPACK_VERSION=0.13.1
RUN curl -fsSL "https://github.com/rustwasm/wasm-pack/releases/download/v${WASMPACK_VERSION}/wasm-pack-v${WASMPACK_VERSION}-x86_64-unknown-linux-musl.tar.gz" \
        | tar -xz -C /tmp \
    && mv "/tmp/wasm-pack-v${WASMPACK_VERSION}-x86_64-unknown-linux-musl/wasm-pack" /usr/local/bin/wasm-pack \
    && chmod +x /usr/local/bin/wasm-pack \
    && rm -rf "/tmp/wasm-pack-v${WASMPACK_VERSION}-x86_64-unknown-linux-musl"

# Pre-create the clone target and hand it to the `node` user. /workspace is a bind
# mount at runtime (host ownership wins), but this keeps the image self-consistent.
RUN mkdir -p /workspace/jsql-neo && chown -R node:node /workspace

# Auto-clone helper: on every container start (devcontainer postStartCommand)
# clone JSQL-NEO into /workspace/jsql-neo, or fast-forward pull if already present.
# Idempotent by design — safe to run repeatedly.
RUN printf '%s\n' \
        '#!/bin/bash' \
        'set -e' \
        'REPO_URL="https://github.com/vexify-org/JSQL-neo"' \
        'DEST=/workspace/jsql-neo' \
        'if [ ! -w /workspace ] && [ ! -w "$DEST" ]; then' \
        '  DEST=/home/node/jsql-neo' \
        '  echo "[clone-jsql] /workspace not writable, using $DEST"' \
        'fi' \
        'if [ -d "$DEST/.git" ]; then' \
        '  echo "[clone-jsql] $DEST exists, pulling..."' \
        '  git -C "$DEST" pull --ff-only || echo "[clone-jsql] pull failed (dirty tree?), keeping existing checkout" >&2' \
        'else' \
        '  echo "[clone-jsql] cloning $REPO_URL -> $DEST"' \
        '  git clone "$REPO_URL" "$DEST" || echo "[clone-jsql] clone failed (network?), continuing without sources" >&2' \
        'fi' \
        > /usr/local/bin/clone-jsql.sh \
    && chmod +x /usr/local/bin/clone-jsql.sh \
    && chown node:node /usr/local/bin/clone-jsql.sh

USER node
WORKDIR /workspace
