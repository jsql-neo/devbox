#!/usr/bin/env bash
# clone-jsql.sh — materialise a JSQL-NEO checkout inside the jsql-devbox container.
#
# Invoked automatically on container start by the Dev Containers
# `postStartCommand` hook, and usable by hand from a plain `docker run` shell:
#
#   docker run --rm -it -v "$PWD:/workspace" jsql-devbox \
#     bash -c '/usr/local/bin/clone-jsql.sh && exec bash'
#
# Guarantees:
#   * clones into /workspace/jsql-neo (visible on the mounted host folder).
#     Only when /workspace is genuinely not writable does it fall back to
#     ~/jsql-neo, and it says so with a loud warning.
#   * the checkout is pinned to a fixed ref (JSQL_REF) so every container start
#     yields the same sources — no silent drift from a moving default branch.
#   * a half-cloned or non-git leftover directory is healed by cloning into a
#     temp directory and atomically swapping it in, so the script is idempotent
#     and can be re-run any number of times.
#   * every git failure is reported on stderr and turns into a non-zero exit
#     code. The script never claims success after a failed clone/pull.
#
# Environment overrides:
#   JSQL_REPO_URL  git URL to clone         (default https://github.com/vexify-org/JSQL-neo)
#   JSQL_REF       tag/branch/commit to pin (default v6.7.2; empty = default branch HEAD)
#   JSQL_DEST      checkout location        (default /workspace/jsql-neo)
#   JSQL_FALLBACK_DEST                      (default ${HOME:-/home/node}/jsql-neo) used
#                                           only when JSQL_DEST's parent is not writable

set -euo pipefail

REPO_URL="${JSQL_REPO_URL:-https://github.com/vexify-org/JSQL-neo}"
REF="${JSQL_REF-v6.7.2}"
DEST="${JSQL_DEST:-/workspace/jsql-neo}"
FALLBACK_DEST="${JSQL_FALLBACK_DEST:-${HOME:-/home/node}/jsql-neo}"

log()  { printf '[clone-jsql] %s\n' "$*"; }
warn() { printf '[clone-jsql] WARNING: %s\n' "$*" >&2; }
die()  { printf '[clone-jsql] ERROR: %s\n' "$*" >&2; exit 1; }

# Ensure DIR exists and is writable by the current user. Bind mounts inherit the
# host's ownership, so if the mount point belongs to us a chmod is enough; a
# chown is attempted as well (only useful when running as root).
ensure_writable_dir() {
    local dir="$1"
    [ -d "$dir" ] || mkdir -p "$dir" 2>/dev/null || return 1
    [ -w "$dir" ] && return 0
    if [ -O "$dir" ]; then
        chmod u+rwx "$dir" 2>/dev/null || true
    else
        chown "$(id -u):$(id -g)" "$dir" 2>/dev/null || true
    fi
    [ -w "$dir" ]
}

is_git_checkout() {
    [ -d "$1/.git" ] && git -C "$1" rev-parse --verify --quiet HEAD >/dev/null 2>&1
}

# Clone from scratch into DEST, atomically replacing whatever is there.
clone_fresh() {
    local dest="$1" parent tmp stale
    parent="$(dirname "$dest")"
    tmp="$(mktemp -d "$parent/.clone-jsql.XXXXXX")" \
        || die "cannot create a temporary directory in $parent"
    # shellcheck disable=SC2064  # expand $tmp now on purpose
    trap "rm -rf '$tmp'" EXIT

    log "cloning $REPO_URL${REF:+ (ref $REF)} -> $dest"
    if [ -n "$REF" ]; then
        if ! git clone --quiet --depth 1 --branch "$REF" "$REPO_URL" "$tmp/repo" 2>/dev/null; then
            log "shallow clone of ref '$REF' failed — retrying with a full clone"
            git clone --quiet "$REPO_URL" "$tmp/repo" \
                || die "git clone failed for $REPO_URL (network or credentials?)"
            git -C "$tmp/repo" -c advice.detachedHead=false checkout --quiet "$REF" \
                || die "ref '$REF' does not exist in $REPO_URL"
        fi
    else
        git clone --quiet --depth 1 "$REPO_URL" "$tmp/repo" \
            || die "git clone failed for $REPO_URL (network or credentials?)"
    fi

    if [ -e "$dest" ]; then
        stale="${dest}.stale.$$"
        warn "$dest exists but is not a usable git checkout — replacing it"
        warn "previous contents are kept at $stale only on swap failure"
        mv "$dest" "$stale" || die "cannot move $dest out of the way"
        if ! mv "$tmp/repo" "$dest"; then
            mv "$stale" "$dest" || warn "could not restore $stale to $dest"
            die "cannot move the fresh clone into $dest"
        fi
        rm -rf "$stale" || warn "could not remove stale copy at $stale"
    else
        mv "$tmp/repo" "$dest" || die "cannot move the fresh clone into $dest"
    fi
}

# Resolve REF on the remote to a commit sha without downloading objects
# (ls-remote is a few hundred bytes; fetching every tag is not).
remote_ref_sha() {
    local ref="$1" out peeled direct
    # The peeled line (refs/tags/<ref>^{}) is only advertised together with a
    # wildcard pattern, so query with one and filter for the exact names.
    out="$(git ls-remote "$REPO_URL" "refs/tags/$ref*" "refs/heads/$ref*" 2>/dev/null)" || return 1
    peeled="$(printf '%s\n' "$out" | awk -v t="refs/tags/$ref^{}" '$2 == t {print $1; exit}')"
    direct="$(printf '%s\n' "$out" | awk -v t="refs/tags/$ref" -v b="refs/heads/$ref" '$2 == t || $2 == b {print $1; exit}')"
    printf '%s\n' "${peeled:-$direct}"
}

# Re-point an existing checkout at the pinned ref, or fast-forward it.
update_existing() {
    local dest="$1" want have
    if [ -n "$REF" ]; then
        want="$(remote_ref_sha "$REF")" \
            || die "cannot query $REPO_URL for ref '$REF' (network?)"
        have="$(git -C "$dest" rev-parse HEAD)"
        if [ -n "$want" ] && [ "$want" = "$have" ]; then
            log "$dest already at $REF (${have:0:7})"
            return 0
        fi
        if [ -z "$want" ]; then
            # Not a tag/branch on the remote: allow a raw commit sha.
            if ! printf '%s' "$REF" | grep -Eq '^[0-9a-fA-F]{7,40}$'; then
                die "ref '$REF' does not exist in $REPO_URL"
            fi
            if [ "${have#$REF}" != "$have" ]; then
                log "$dest already at commit $REF"
                return 0
            fi
        fi
        log "updating $dest to $REF${want:+ (${want:0:7})}"
        git -C "$dest" fetch --quiet --depth 1 origin "$REF" \
            || die "git fetch of '$REF' failed in $dest"
        git -C "$dest" -c advice.detachedHead=false checkout --quiet FETCH_HEAD \
            || die "cannot check out '$REF' in $dest (dirty tree?) — clean the checkout or set JSQL_REF=\"\""
    else
        log "fast-forwarding $dest (default branch HEAD)"
        git -C "$dest" pull --ff-only \
            || die "git pull --ff-only failed in $dest (dirty tree or diverged history?)"
    fi
}

# --- pick a writable destination ------------------------------------------------
if ! ensure_writable_dir "$(dirname "$DEST")"; then
    warn "$(dirname "$DEST") is not writable for uid $(id -u) — falling back to $FALLBACK_DEST"
    warn "the checkout will NOT appear in the mounted /workspace folder;"
    warn "mount a writable host directory or pass --user $(id -u):$(id -g) to docker run"
    DEST="$FALLBACK_DEST"
    ensure_writable_dir "$(dirname "$DEST")" || die "cannot create $DEST"
fi

log "repository: $REPO_URL"
log "ref:        ${REF:-<default branch HEAD>}"
log "target:     $DEST"

# --- obtain the sources ---------------------------------------------------------
if is_git_checkout "$DEST"; then
    update_existing "$DEST"
elif [ -e "$DEST" ]; then
    warn "$DEST exists but holds no usable git checkout (interrupted clone?) — re-cloning"
    clone_fresh "$DEST"
else
    clone_fresh "$DEST"
fi

HEAD_SHA="$(git -C "$DEST" rev-parse --short HEAD)" || die "no HEAD in $DEST after clone"
log "ready: $DEST at $HEAD_SHA"
