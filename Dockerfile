FROM node:22-bookworm

# System build deps required to compile N-API native modules
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        python3 \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Rust stable + wasm32 target + rustfmt + clippy, installed system-wide
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
        --profile minimal \
        --target wasm32-unknown-unknown \
        --component rustfmt clippy \
    && chown -R node:node /usr/local/cargo /usr/local/rustup

# wasm-pack (precompiled static binary, faster than `cargo install`)
RUN curl -sSf https://raw.githubusercontent.com/rustwasm/wasm-pack/main/install.sh | sh \
    && chown node:node /usr/local/cargo/bin/wasm-pack

USER node
WORKDIR /workspace
