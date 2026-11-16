# jsql-devbox

Official development container for [JSQL-NEO](https://github.com/vexify-org/JSQL-neo).

A reproducible, batteries-included **build toolchain** so every contributor can compile the
N-API native module and the WASM targets without fighting a local setup.

> **Scope:** this image ships compilers and Node.js — it does **not** run MySQL,
> PostgreSQL, MongoDB, Redis or a web UI. JSQL-NEO speaks those wire protocols from
> its own Node process; see [Ports](#ports-not-services) for how the reserved ports
> are meant to be used.

## What's inside

- **Node.js 22.23.5** — `node:22-bookworm` (glibc/Debian 12), pinned by digest
- **C/C++ toolchain** — `build-essential`, `pkg-config`, `libssl-dev`, `python3`,
  plus `git`, `curl`, `ca-certificates`, `perl` (needed for N-API native builds)
- **Rust** pinned to **1.83.0**, with `wasm32-unknown-unknown`, `rustfmt` and
  `clippy`, installed to a system-level `CARGO_HOME`/`RUSTUP_HOME` owned by the
  `node` user
- **wasm-pack 0.13.1** — prebuilt static binary (no `cargo install`), selected per
  target architecture (`amd64`/`arm64`) at build time
- **`clone-jsql.sh`** — pinned, idempotent, self-healing checkout helper
- Runs as the `node` user, workspace mounted at `/workspace`, default command `/bin/bash`

## Files

| File | Purpose |
| ---- | ------- |
| [Dockerfile](Dockerfile) | Base image (digest-pinned), build deps, pinned Rust + wasm-pack, default `CMD` |
| [clone-jsql.sh](clone-jsql.sh) | Checkout helper installed to `/usr/local/bin/clone-jsql.sh` |
| [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) | Dev Containers config: mount, extensions, forwarded ports, auto-clone hook |
| [.dockerignore](.dockerignore) | Exclude `node_modules` and `.git` from the build context |

## Auto-clone on start

`/usr/local/bin/clone-jsql.sh` clones JSQL-NEO into `/workspace/jsql-neo`:

- **Pinned ref.** It checks out `v6.7.2` by default (override with `JSQL_REF`, e.g.
  `JSQL_REF=v6.6.4`, or `JSQL_REF=` for the moving default branch), so every
  container start yields the same sources instead of drifting with `HEAD`.
- **Idempotent and self-healing.** An existing checkout is re-checked at the pinned
  ref (a plain `git pull --ff-only` when `JSQL_REF` is empty); the pinned ref is
  compared against the remote with `git ls-remote`, so a restart at the same ref
  is a fast no-op. A leftover directory
  that is not a usable git checkout (e.g. an interrupted clone) is replaced by
  cloning into a temporary directory and atomically swapping it in.
- **Fails loudly.** Any `git clone`/`fetch`/`checkout` failure prints an error to
  stderr and exits non-zero — the script never reports success with an empty
  workspace.
- **Fallback.** If `/workspace` is not writable for the `node` user (e.g. a bind
  mount owned by another uid), it warns and falls back to `~/jsql-neo`
  (`/home/node/jsql-neo`). The sources then live *outside* the mounted host
  folder — mount a writable directory or pass `--user "$(id -u):$(id -g)"` to
  avoid this.

**The auto-clone hook is Dev Containers only.** `postStartCommand` in
`devcontainer.json` is executed by VS Code / the Dev Containers CLI; a plain
`docker run` never runs it. Use the explicit command in
[Use from the CLI](#use-from-the-cli) instead.

## Use with VS Code

1. Clone the JSQL-NEO repository.
2. Copy `Dockerfile`, `clone-jsql.sh` and `.dockerignore` into the repo root, and
   `devcontainer.json` into `.devcontainer/`.
3. Reopen the folder in a Dev Container (remote container extension / `Dev Containers: Reopen in Container`).
   Extensions install automatically, the workspace is mounted at `/workspace`, and
   `postStartCommand` runs `clone-jsql.sh` on every start.
4. Run `npm install` once inside the container. `postCreateCommand` is intentionally
   omitted so dependency installation stays explicit.

## Use from the CLI

```bash
docker build -t jsql-devbox .
docker run --rm -it \
  -v "$PWD:/workspace" \
  --user "$(id -u):$(id -g)" \
  -p 3306:3306 -p 5432:5432 -p 27017:27017 -p 6379:6379 -p 8080:8080 \
  jsql-devbox \
  bash -c '/usr/local/bin/clone-jsql.sh && exec bash'
```

The container's default command is `/bin/bash`, so a bare
`docker run --rm -it -v "$PWD:/workspace" jsql-devbox` gives you a shell — run
`/usr/local/bin/clone-jsql.sh` yourself if you skipped the step above. To pick a
different revision:

```bash
docker run --rm -it -v "$PWD:/workspace" -e JSQL_REF=v6.6.4 jsql-devbox
```

## Ports (not services)

`devcontainer.json` forwards these ports, and the CLI example publishes them, purely
as **reserved slots**: they are where *you* start JSQL-NEO's own protocol servers
inside the container. Nothing in the image listens on them.

| Port | Reserved for |
| ---- | ------------ |
| 3306 | JSQL-NEO MySQL-compatible listener (start it yourself) |
| 5432 | JSQL-NEO PostgreSQL-compatible listener (start it yourself) |
| 27017 | JSQL-NEO MongoDB-compatible listener (start it yourself) |
| 6379 | JSQL-NEO Redis-compatible listener (start it yourself) |
| 8080 | JSQL-NEO HTTP / web UI (start it yourself) |

There is no MySQL, PostgreSQL, MongoDB or Redis server installed in the image.

## Reproducibility notes

- The base image is pinned by digest (`node:22-bookworm@sha256:…`), Rust by version
  (`1.83.0`) and wasm-pack by version (`0.13.1`), so a given commit of this
  Dockerfile builds the same toolchain everywhere.
- `JSQL_REF` pins the sources that `clone-jsql.sh` materialises.
- To move to a newer Node base, re-resolve the digest
  (`docker buildx imagetools inspect node:22-bookworm`) and update the `FROM` line.
- Multi-arch builds work as-is: `docker buildx build --platform linux/amd64,linux/arm64 .`
  picks the matching wasm-pack asset via `TARGETARCH`.
