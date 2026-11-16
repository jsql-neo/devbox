# jsql-devbox — JSQL-NEO build/dev toolchain.
#
# Base image is pinned by digest so the same Dockerfile always builds the same
# image (issue #3). Resolved with:
#   docker buildx imagetools inspect node:22-bookworm   # or any registry proxy
# The digest below is the multi-arch OCI index for node:22-bookworm
# (Node.js 22.23.5, Debian 12 "bookworm"; linux/amd64 + linux/arm64).
# To bump Node, re-resolve the digest and update both lines.
FROM node:22-bookworm@sha256:e13726ca604184d7a91fcacab1fc09eefd642dc28e79ac34e85540dd93b78cfb

# bash + pipefail for every RUN: a failing command inside a pipeline (e.g.
# `curl ... | sh`) must abort the build instead of being masked by the last
# element's exit status (issue #2).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# System build deps:
#   build-essential/pkg-config/libssl-dev/python3 -> N-API native modules
#   git                                           -> VCS in dev environment
#   perl                                          -> openssl-dependent native builds
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        build-essential \
        pkg-config \
        libssl-dev \
        python3 \
        git \
        perl \
        curl \
        ca-certificates; \
    rm -rf /var/lib/apt/lists/*

# Rust toolchain pinned to a concrete version for reproducible builds.
# (was: "stable" which moves and breaks reproducibility across contributors)
# The installer script is downloaded first and checked for content, so a failed
# download can never be mistaken for a successful install (issue #2).
ARG RUST_VERSION=1.83.0
ENV CARGO_HOME=/usr/local/cargo \
    RUSTUP_HOME=/usr/local/rustup \
    PATH=/usr/local/cargo/bin:$PATH

RUN set -eux; \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh; \
    test -s /tmp/rustup-init.sh; \
    sh /tmp/rustup-init.sh -y \
        --default-toolchain "${RUST_VERSION}" \
        --profile minimal \
        --target wasm32-unknown-unknown; \
    rm -f /tmp/rustup-init.sh; \
    rustup component add rustfmt clippy; \
    rustc --version; \
    cargo --version; \
    chown -R node:node /usr/local/cargo /usr/local/rustup

# wasm-pack: pinned version, direct static tarball into /usr/local/bin.
# Replaces `curl ... | sh` run as root (supply-chain / non-reproducible).
# The release asset name depends on the target architecture, taken from
# TARGETARCH which buildx sets for every --platform in a multi-arch build
# (issue #2). A plain `docker build` leaves it empty, which defaults to amd64.
ARG WASMPACK_VERSION=0.13.1
ARG TARGETARCH
RUN set -eux; \
    case "${TARGETARCH:-amd64}" in \
        amd64) wp_arch=x86_64 ;; \
        arm64) wp_arch=aarch64 ;; \
        *) echo "wasm-pack: unsupported target architecture '${TARGETARCH}'" >&2; exit 1 ;; \
    esac; \
    tarball="wasm-pack-v${WASMPACK_VERSION}-${wp_arch}-unknown-linux-musl"; \
    curl -fsSL "https://github.com/rustwasm/wasm-pack/releases/download/v${WASMPACK_VERSION}/${tarball}.tar.gz" -o /tmp/wasm-pack.tar.gz; \
    tar -xzf /tmp/wasm-pack.tar.gz -C /tmp; \
    install -m 0755 "/tmp/${tarball}/wasm-pack" /usr/local/bin/wasm-pack; \
    rm -rf /tmp/wasm-pack.tar.gz "/tmp/${tarball}"; \
    wasm-pack --version

# Auto-clone helper (see clone-jsql.sh for the full contract). It clones JSQL-NEO
# into /workspace/jsql-neo, pinned to a fixed ref, and is safe to re-run.
COPY clone-jsql.sh /usr/local/bin/clone-jsql.sh
RUN chmod 0755 /usr/local/bin/clone-jsql.sh

# Pre-create the clone target and hand it to the `node` user. /workspace is a bind
# mount at runtime (host ownership wins), but this keeps the image self-consistent.
RUN set -eux; \
    mkdir -p /workspace/jsql-neo; \
    chown -R node:node /workspace

# A bind-mounted workspace may be owned by a different uid than `node`; without
# this git refuses to operate on it ("detected dubious ownership").
RUN set -eux; \
    git config --system --add safe.directory /workspace; \
    git config --system --add safe.directory /workspace/jsql-neo; \
    git config --system --add safe.directory /home/node/jsql-neo

USER node
WORKDIR /workspace

# Without a CMD the image inherits `node` from the base image and `docker run`
# drops the user into a Node REPL instead of a shell (issues #1, #4).
CMD ["/bin/bash"]
