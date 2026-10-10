#!/usr/bin/env bash
# host-mode.sh — sourceable helper: THE one resolver for where a Loomwright hook keeps its
# `.supervisor/`-equivalent state, so a host (Loomwright Studio first) can keep that state out of
# the session's repo.
#
# The switch is `LOOMWRIGHT_HOST_MODE=1` (exactly `1`; any other value, or unset, is OFF). The
# optional destination is `LOOMWRIGHT_HOST_STATE_DIR`. With the switch OFF every function below
# prints exactly the path the hooks used before this helper existed (`<root>/.supervisor`,
# `<root>/.supervisor/state.md`) — byte-identical, no git or hash fork. With it ON no hook writes
# inside the repo: redirected state keeps the `.supervisor/` relative layout under the resolved dir
# (`<dir>/logs/<session>.jsonl`, `<dir>/state.md`, `<dir>/guard/<id>.json`,
# `<dir>/logs/<id>.finalize-gate`).
#
# Callers pass `<root>` = the repo's MAIN worktree (the same anchoring `loom_main_root` in
# loom-log-owner.sh prints). Every READ of a piece of state resolves through the SAME function as
# its writer, so readers and writers never disagree.
#
# lw_host_mode — returns 0 iff LOOMWRIGHT_HOST_MODE is exactly `1`.
#
# lw_host_state_dir [root] — prints $LOOMWRIGHT_HOST_STATE_DIR and returns 0 only when it is an
#   absolute (`/`-prefixed) path to an existing directory that is NOT inside [root] (compared on
#   physical paths, so a symlink cannot smuggle it back in). Else prints nothing, returns 1.
#
# lw_state_dir <root> — the `.supervisor`-equivalent for NON-gate writes (logs, markers, nudges).
#   Off: prints <root>/.supervisor. On + valid state dir: prints it. On without one: prints
#   nothing and returns 1 — the caller SKIPS its write and keeps its fail-SAFE exit 0.
#
# lw_gate_state_dir <root> — the `.supervisor`-equivalent for GATE state: the guard markers, the
#   finalize-gate marker, and the state those gates read (`state.md`'s `## Session` block, the
#   plugin session log and its `.owner` seed). Off: <root>/.supervisor. On + valid state dir: that
#   dir. On without one (owner decision D1): ${TMPDIR:-/tmp}/loomwright-host-<uid>/<repo-hash>,
#   where <repo-hash> is the first 12 hex of the SHA-256 of the repo's absolute main-worktree path.
#   Always returns 0 with a path. It NEVER creates the dir — a writer does, with `mkdir -p` under
#   `umask 077`.
#
# lw_state_md_read <root> — the path every hook READS `state.md` from. The repo copy (the
#   agent-authored seed — Context-Keeper writes it with the Write tool) decides which run is
#   current. Off: always <root>/.supervisor/state.md. On: the gate dir's state.md when its
#   `- session_id:` EQUALS the repo copy's, or when the repo copy is absent; in every other case
#   (gate copy missing, or stale from an earlier run) <root>/.supervisor/state.md, which hooks
#   only READ under host mode. The gate dir outlives runs, so a gate copy alone never wins over a
#   newer repo seed.
#
# Sourcing has no side effects beyond defining the functions. bash 3.2 safe.

lw_host_mode() {
  [ "${LOOMWRIGHT_HOST_MODE:-}" = "1" ]
}

lw_host_state_dir() {
  local _sd="${LOOMWRIGHT_HOST_STATE_DIR:-}" _root="${1:-}" _sd_p="" _root_p=""
  case "$_sd" in /*) ;; *) return 1 ;; esac
  [ -d "$_sd" ] || return 1
  if [ -n "$_root" ]; then
    _sd_p="$(cd "$_sd" 2>/dev/null && pwd -P)" || return 1
    [ -n "$_sd_p" ] || return 1
    _root_p="$(cd "$_root" 2>/dev/null && pwd -P)" || _root_p=""
    [ -n "$_root_p" ] || _root_p="$_root"
    case "$_sd_p/" in "${_root_p%/}/"*) return 1 ;; esac
  fi
  printf '%s' "$_sd"
}

lw_state_dir() {
  local _root="${1:-}"
  if ! lw_host_mode; then
    printf '%s/.supervisor' "$_root"
    return 0
  fi
  lw_host_state_dir "$_root"
}

lw_gate_state_dir() {
  local _root="${1:-}" _main="" _hash="" _uid=""
  if ! lw_host_mode; then
    printf '%s/.supervisor' "$_root"
    return 0
  fi
  if lw_host_state_dir "$_root"; then
    return 0
  fi
  # D1: per-user gate root OUTSIDE the repo, keyed on the main-worktree path so every linked
  # worktree of one repo shares one gate root and two repos never collide.
  _main="$(git -C "$_root" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  [ -n "$_main" ] || _main="$_root"
  # Any SHA-256 tool prints the same digest, so the key is stable whichever one is on PATH.
  _hash="$(printf '%s' "$_main" | shasum -a 256 2>/dev/null | cut -c1-12)"
  case "$_hash" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *)
    _hash="$(printf '%s' "$_main" | sha256sum 2>/dev/null | cut -c1-12)" ;;
  esac
  case "$_hash" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *)
    _hash="$(printf '%s' "$_main" | openssl dgst -sha256 2>/dev/null | sed 's/^.*= *//' | cut -c1-12)" ;;
  esac
  case "$_hash" in [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;; *)
    _hash="$(printf '%s' "$_main" | cksum 2>/dev/null | awk '{printf "%012x", $1}')" ;;
  esac
  _uid="$(id -u 2>/dev/null)"
  case "$_uid" in ''|*[!0-9]*) _uid="unknown" ;; esac
  printf '%s/loomwright-host-%s/%s' "${TMPDIR:-/tmp}" "$_uid" "$_hash"
}

lw_state_md_read() {
  local _root="${1:-}" _repo="" _gate="" _repo_sid="" _gate_sid=""
  _repo="$_root/.supervisor/state.md"
  if ! lw_host_mode; then
    printf '%s' "$_repo"
    return 0
  fi
  _gate="$(lw_gate_state_dir "$_root")/state.md"
  if [ ! -f "$_repo" ]; then
    printf '%s' "$_gate"
    return 0
  fi
  # Same `- session_id:` extraction + charset as the emitters' own state.md read.
  _repo_sid="$(sed -nE 's/^- session_id:[[:space:]]*//p' "$_repo" 2>/dev/null | head -1 | tr -cd 'A-Za-z0-9_-')"
  if [ -n "$_repo_sid" ] && [ -f "$_gate" ]; then
    _gate_sid="$(sed -nE 's/^- session_id:[[:space:]]*//p' "$_gate" 2>/dev/null | head -1 | tr -cd 'A-Za-z0-9_-')"
    if [ "$_gate_sid" = "$_repo_sid" ]; then
      printf '%s' "$_gate"
      return 0
    fi
  fi
  printf '%s' "$_repo"
}
