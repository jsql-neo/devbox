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
        --component rustfmt clippy \
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

USER node
WORKDIR /workspace
