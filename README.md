# jsql-devbox

Official development container for [JSQL-NEO](https://github.com/vexify-org/JSQL-neo).

A reproducible, batteries-included dev environment so every contributor can build the
N-API native module, compile WASM targets, and run the protocol servers without
fighting a local toolchain.

## What's inside

- **Node.js 22** (`node:22-bookworm`, glibc/Debian)
- **C/C++ toolchain** — `build-essential`, `pkg-config`, `libssl-dev`, `python3`,
  plus `git`, `curl`, `ca-certificates`, `perl` (needed for N-API native builds)
- **Rust** pinned to **1.83.0**, with `wasm32-unknown-unknown`, `rustfmt`, and
  `clippy`, installed to a system-level `CARGO_HOME`/`RUSTUP_HOME` owned by the
  `node` user
- **wasm-pack 0.13.1** — prebuilt static binary (no `cargo install`)
- Dev container runs as the `node` user, workspace mounted at `/workspace`

## Files

| File | Purpose |
| ---- | ------- |
| [Dockerfile](Dockerfile) | Base image, build deps, pinned Rust + wasm-pack |
| [devcontainer.json](devcontainer.json) | Dev Containers config: mount, extensions, forwarded ports |
| [.dockerignore](.dockerignore) | Exclude `node_modules` and `.git` from the build context |

## Use with VS Code

1. Clone the JSQL-NEO repository.
2. Copy `Dockerfile`, `devcontainer.json`, and `.dockerignore` into the repo root.
3. Reopen the folder in a Dev Container (remote container extension / `Dev Containers: Reopen in Container`).
   Extensions install automatically and the workspace is mounted at `/workspace`.
4. Run `npm install` once inside the container. `postCreateCommand` is intentionally
   omitted so dependency installation stays explicit.

## Use from the CLI

```bash
docker build -t jsql-devbox .
docker run --rm -it \
  -v "$PWD:/workspace" \
  -p 3306:3306 -p 5432:5432 -p 27017:27017 -p 6379:6379 -p 8080:8080 \
  jsql-devbox
```

## Forwarded ports

| Port | Service |
| ---- | ------- |
| 3306 | MySQL |
| 5432 | PostgreSQL |
| 27017 | MongoDB |
| 6379 | Redis |
| 8080 | Web UI / HTTP |

## Notes

- Rust and wasm-pack versions are pinned for reproducible builds across contributors.
- On ARM64 hosts, swap the wasm-pack asset in `Dockerfile` to
  `wasm-pack-v0.13.1-aarch64-unknown-linux-musl.tar.gz` (see the comment in the Dockerfile).
