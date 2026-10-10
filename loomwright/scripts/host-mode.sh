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
# ONE ROOT RULE (every caller, host mode or not): `<root>` may be ANY worktree of the repo — the
# main one (emitters anchor there, as `loom_main_root` in loom-log-owner.sh prints) or a linked one
# (the guards anchor on the session's project dir). The resolver normalises internally, so both
# resolve the same dir: the D1 key hashes the MAIN worktree path `git worktree list` reports, and
# "outside the repo" is tested against EVERY worktree git lists, by filesystem identity (`-ef`). Off mode is not
# normalised — it prints `<root>/.supervisor` verbatim, exactly as before. Every READ of a piece of
# state resolves through the SAME resolver body as its writer (_lw_gate_resolve; the reader form
# only declines to create), so readers and writers never disagree on the path.
#
# lw_host_mode — returns 0 iff LOOMWRIGHT_HOST_MODE is exactly `1`.
#
# lw_host_state_dir [root] — prints $LOOMWRIGHT_HOST_STATE_DIR and returns 0 only when it is an
#   absolute (`/`-prefixed) path to an existing directory that is NOT inside [root] nor any other
#   worktree of its repo (judged by filesystem identity — `-ef` on each ancestor — so neither a
#   symlink nor a case-variant spelling on a case-insensitive volume smuggles it back in). Else
#   prints nothing, returns 1. A host-provided dir is the host's: no ownership test is applied.
#
# lw_state_dir <root> — the `.supervisor`-equivalent for NON-gate writes (logs, markers, nudges).
#   Off: prints <root>/.supervisor. On + valid state dir: prints it. On without one: prints
#   nothing and returns 1 — the caller SKIPS its write and keeps its fail-SAFE exit 0.
#
# lw_gate_state_dir <root> — the `.supervisor`-equivalent for GATE state: the guard markers, the
#   finalize-gate marker, and the state those gates read (`state.md`'s `## Session` block, the
#   plugin session log and its `.owner` seed). Off: <root>/.supervisor (never created here). On +
#   valid state dir: that dir. On without one (owner decision D1): <base>/loomwright-host-<uid>/
#   <repo-hash>, where <repo-hash> is the first 12 hex of the SHA-256 of the repo's absolute
#   main-worktree path and <base> is ${TMPDIR} when that is an absolute existing directory outside
#   every worktree, else /tmp. The D1 root lives in a shared tmp, so the resolver CREATES its two
#   components itself (`mkdir`, umask 077 — never `mkdir -p` through a pre-planted path) and then
#   requires each to be a real directory (not a symlink), owned by this uid, writable, and not
#   group/world-writable. Any failure prints nothing and returns 1: the gate dir is UNRESOLVABLE —
#   the guards deny (guard_unavailable) and every emitter skips. Writers create subdirs (`logs/`,
#   `guard/`) with `mkdir -p` under `umask 077`. ONLY the gate writers that legitimately START a
#   run's state call this creating form: guard-arm.sh when it writes a marker, seed-run-owner.sh
#   when Context-Keeper's Write of the repo state.md names a live run (its header says why), and
#   guard-finalize-publish.sh write-marker.
#
# lw_gate_state_dir_existing <root> — the same answer WITHOUT creating anything: the PRESENCE GATE
#   every other caller (emitters, the guards' read paths, check-children-settled.sh,
#   lw_state_md_read) goes through, mirroring off mode's "the plugin has run here iff `.supervisor/`
#   exists". Off: <root>/.supervisor, rc 0 (byte-identical). On + valid state dir: that dir, rc 0
#   (it exists by validation). On, D1: the gate dir and rc 0 only when both D1 components already
#   exist AND pass the same safety test as above; rc 1 (nothing printed) when either exists but
#   fails it — a pre-planted unsafe root stays UNRESOLVABLE, so the guards still deny; rc 2 (nothing
#   printed) when either is ABSENT — no Loomwright run has created gate state for this repo yet: the
#   guards are inert (as off mode with no `.supervisor/guard`) and the emitters skip. An armed
#   session's marker lives in the root, so an armed session never reads rc 2.
#   COST (the cheap path): before any fork, a reader checks whether an entry named
#   loomwright-host-<uid> exists under $TMPDIR or /tmp — the only two bases the full resolve can pick.
#   None ⇒ rc 2 with no `git worktree list` and no hash. Anything there (even a hostile entry) takes
#   the full resolve, so the outside-every-worktree base rule and the main-worktree hash still decide
#   which root applies; correctness is never traded for the shortcut. Once any host-mode run has
#   created the per-user root, readers pay the git + hash forks (but still create nothing).
#   A gate WRITER that cannot create the root (unwritable base) leaves no marker, so the readers then
#   see rc 2 and stay inert — the documented "a failed arm proceeds visibly unguarded" outcome
#   (skills/supervisor-config/SKILL.md, INIT step 7), the same as an unwritable `.supervisor/` off.
#
# lw_state_md_read <root> — the path every hook READS `state.md` from. The repo copy (the
#   agent-authored seed — Context-Keeper writes it with the Write tool) decides which run is
#   current. Off: always <root>/.supervisor/state.md. On: the gate dir's state.md when its
#   `- session_id:` EQUALS the repo copy's, or when the repo copy is absent; in every other case
#   (gate copy missing, or stale from an earlier run) <root>/.supervisor/state.md, which hooks
#   only READ under host mode. The gate dir outlives runs, so a gate copy alone never wins over a
#   newer repo seed. An unresolvable or absent gate dir (lw_gate_state_dir_existing — this reader
#   never creates it) reads the repo copy.
#
# Sourcing has no side effects beyond defining the functions. bash 3.2 safe.

lw_host_mode() {
  [ "${LOOMWRIGHT_HOST_MODE:-}" = "1" ]
}

# _lw_under_any <path> <dir>... — 0 iff <path> or one of its ancestors IS one of the <dir>s, judged by
# filesystem identity (`-ef`: same device + inode), never by spelling. A string prefix test is fooled
# by a case-variant path on case-insensitive APFS (`/x/REPO` names `/x/repo` but shares no prefix
# with it) and by any second name for a directory; inode identity is not. The walk strips one
# component per step and stops at `/` (or when stripping changes nothing), so it is bounded by the
# path's depth times the number of <dir>s — builtin tests only, no fork. A missing <dir> never matches.
_lw_under_any() {
  local _d="$1" _prev="" _t=""
  shift
  [ "$#" -gt 0 ] || return 1
  case "$_d" in /*) ;; *) _d="$PWD/$_d" ;; esac
  while :; do
    while [ "${#_d}" -gt 1 ] && [ "${_d%/}" != "$_d" ]; do _d="${_d%/}"; done
    for _t in "$@"; do
      [ -n "$_t" ] && [ "$_d" -ef "$_t" ] && return 0
    done
    [ "$_d" = "/" ] && return 1
    _prev="$_d"; _d="${_d%/*}"; [ -n "$_d" ] || _d="/"
    [ "$_d" = "$_prev" ] && return 1
  done
}

# _lw_in_worktree <path> <root> — 0 iff the path is <root>, any worktree of <root>'s repo, or inside
# one, by filesystem identity (_lw_under_any). A path that is not an existing directory cannot be
# placed, so it counts as INSIDE (every caller then rejects it — the fail-closed direction).
_lw_in_worktree() {
  local _p="$1" _root="${2:-}" _list="" _w=""
  [ -n "$_root" ] || return 1
  [ -d "$_p" ] || return 0
  # Collected first, then scanned: no pipeline, so a caller's `set -o pipefail` (SIGPIPE on an early
  # match) cannot flip the answer.
  _list="$(git -C "$_root" worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
  set -- "$_root"
  while IFS= read -r _w; do
    [ -n "$_w" ] && set -- "$@" "$_w"
  done <<EOF
$_list
EOF
  _lw_under_any "$_p" "$@"
}

# _lw_private_dir <dir> — 0 iff <dir> is a real directory (not a symlink) owned by this uid, writable
# and searchable by it, and neither group- nor world-writable.
_lw_private_dir() {
  local _d="$1" _m=""
  [ -d "$_d" ] && [ ! -L "$_d" ] && [ -O "$_d" ] && [ -w "$_d" ] && [ -x "$_d" ] || return 1
  _m="$(ls -ld "$_d" 2>/dev/null)" || return 1
  case "$_m" in ?????w*|????????w*) return 1 ;; esac
  return 0
}

# _lw_private_mkdir <dir> — create <dir> (one level, umask 077) when nothing is there, then verify it
# with _lw_private_dir. Creating first and checking after closes the check-then-create window: a
# racing or pre-planted entry makes `mkdir` fail and is then judged on what is actually there.
_lw_private_mkdir() {
  if [ ! -e "$1" ] && [ ! -L "$1" ]; then
    ( umask 077; mkdir "$1" ) 2>/dev/null
  fi
  _lw_private_dir "$1"
}

lw_host_state_dir() {
  local _sd="${LOOMWRIGHT_HOST_STATE_DIR:-}" _root="${1:-}" _sd_p=""
  case "$_sd" in /*) ;; *) return 1 ;; esac
  [ -d "$_sd" ] || return 1
  if [ -n "$_root" ]; then
    _sd_p="$(cd "$_sd" 2>/dev/null && pwd -P)" || return 1
    [ -n "$_sd_p" ] || return 1
    _lw_in_worktree "$_sd_p" "$_root" && return 1
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

# _lw_uid — this user's numeric uid, or `unknown`.
_lw_uid() {
  local _u
  _u="$(id -u 2>/dev/null)"
  case "$_u" in ''|*[!0-9]*) _u="unknown" ;; esac
  printf '%s' "$_u"
}

# _lw_d1_none <uid> — 0 iff NO entry (dir, file or symlink, dangling included) named
# loomwright-host-<uid> exists under either base the D1 resolver could pick ($TMPDIR, spelled as the
# resolver spells it, and /tmp). Then the D1 root cannot exist wherever the full resolve would put it,
# so a reader can answer "absent" without `git worktree list` or a hash. Builtin tests only.
_lw_d1_none() {
  local _b="${TMPDIR:-}" _t=""
  while [ "${#_b}" -gt 1 ] && [ "${_b%/}" != "$_b" ]; do _b="${_b%/}"; done
  for _t in "$_b" /tmp; do
    case "$_t" in /*) ;; *) continue ;; esac
    _t="$_t/loomwright-host-$1"
    if [ -e "$_t" ] || [ -L "$_t" ]; then return 1; fi
  done
  return 0
}

# _lw_gate_resolve <root> <create: 1|0> — the shared body of lw_gate_state_dir (create=1) and
# lw_gate_state_dir_existing (create=0). Host mode only (callers handle off). Prints the gate dir and
# returns 0; returns 1 (nothing printed) when it is unresolvable; with create=0 returns 2 (nothing
# printed) when the D1 root, or this repo's dir in it, does not exist yet.
_lw_gate_resolve() {
  local _root="${1:-}" _create="${2:-1}" _main="" _hash="" _uid="" _base="" _base_p="" _top=""
  if lw_host_state_dir "$_root"; then
    return 0
  fi
  _uid="$(_lw_uid)"
  # The cheap path (readers only): no per-user root under either candidate base => absent, decided
  # before any git or hash fork. Anything there at all (even a hostile entry) takes the full path.
  if [ "$_create" != 1 ] && _lw_d1_none "$_uid"; then
    return 2
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
  # The base: $TMPDIR only when absolute, an existing directory, and outside every worktree
  # (filesystem identity) — a relative or in-repo TMPDIR would put "outside the repo" state inside it.
  _base="${TMPDIR:-}"
  while [ "${#_base}" -gt 1 ] && [ "${_base%/}" != "$_base" ]; do _base="${_base%/}"; done
  case "$_base" in /*) ;; *) _base="" ;; esac
  if [ -n "$_base" ]; then
    _base_p="$(cd "$_base" 2>/dev/null && pwd -P)" || _base_p=""
    if [ -z "$_base_p" ] || _lw_in_worktree "$_base_p" "$_root"; then _base=""; fi
  fi
  if [ -z "$_base" ]; then
    _base="/tmp"
    _base_p="$(cd "$_base" 2>/dev/null && pwd -P)" || return 1
    [ -n "$_base_p" ] || return 1
    _lw_in_worktree "$_base_p" "$_root" && return 1
  fi
  _top="$_base/loomwright-host-$_uid"
  if [ "$_create" = 1 ]; then
    _lw_private_mkdir "$_top" || return 1
    _lw_private_mkdir "$_top/$_hash" || return 1
  else
    # Never created here. Absent => 2. Present => the SAME safety test the creating form applies,
    # so a pre-planted unsafe root is unresolvable (1) for readers exactly as for writers.
    if [ ! -e "$_top" ] && [ ! -L "$_top" ]; then return 2; fi
    _lw_private_dir "$_top" || return 1
    if [ ! -e "$_top/$_hash" ] && [ ! -L "$_top/$_hash" ]; then return 2; fi
    _lw_private_dir "$_top/$_hash" || return 1
  fi
  printf '%s' "$_top/$_hash"
}

lw_gate_state_dir() {
  local _root="${1:-}"
  if ! lw_host_mode; then
    printf '%s/.supervisor' "$_root"
    return 0
  fi
  _lw_gate_resolve "$_root" 1
}

lw_gate_state_dir_existing() {
  local _root="${1:-}"
  if ! lw_host_mode; then
    printf '%s/.supervisor' "$_root"
    return 0
  fi
  _lw_gate_resolve "$_root" 0
}

lw_state_md_read() {
  local _root="${1:-}" _repo="" _gate="" _repo_sid="" _gate_sid=""
  _repo="$_root/.supervisor/state.md"
  if ! lw_host_mode; then
    printf '%s' "$_repo"
    return 0
  fi
  if ! _gate="$(lw_gate_state_dir_existing "$_root")"; then
    printf '%s' "$_repo"
    return 0
  fi
  _gate="$_gate/state.md"
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
