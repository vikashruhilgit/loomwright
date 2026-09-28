#!/usr/bin/env bash
# hermetic-test-env.sh — make the CURRENT shell hermetic for egress. SOURCE it, never execute it:
#
#   . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
#
# Every self-test (loomwright/scripts/test-*.sh, loomwright/scripts/adapters/*/test-*.sh,
# scripts/test-*.sh) sources this as its first executable line, and run-self-tests.sh sources it
# again for its workers. scripts/check-test-hermetic.sh fails CI on any covered test that does not.
#
# WHY: tests fake HOME but inherit the caller's ENVIRONMENT and PATH. A terminal whose shell exports
# LOOMWRIGHT_WEBHOOK_URL (highest precedence in resolve-egress-config.sh) made fixture events reach
# a real ntfy topic, and a test that staged the real notify-desktop.sh fired a real macOS banner.
# Fixing the two known sites alone leaves the next test free to do the same; sourcing this in every
# test (with a lint ratchet) closes the defect class.
#
# What sourcing it does:
#   (a) unsets every env var that routes data OUT (list derived below, next to the `unset`);
#   (b) exports LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0 — notify-desktop.sh's own "Opt-out gate";
#   (c) prepends a per-process shim dir to PATH whose osascript / notify-send / terminal-notifier /
#       curl / wget stubs append "<name> <argv>" to $HERMETIC_EGRESS_LOG and exit 0. `gh` is
#       deliberately NOT stubbed: tests stub gh themselves, and a global stub could mask a test's
#       own stub ordering (test-hermetic-egress.sh probes the telemetry route instead);
#   (d) exports HERMETIC_TEST_ENV=1 (the marker test-run-self-tests.sh and the probe read);
#   (e) never touches HOME — tests keep their own HOME isolation where they have it.
#
# Shim-dir lifecycle (idempotent — sourcing twice, e.g. runner then test, is safe):
#   - an exported HERMETIC_SHIM_DIR is REUSED only if it exists, carries this helper's marker file,
#     and every stub in it is present and executable; otherwise a fresh dir is made, so a stray
#     user-shell export or a half-built dir can never silently drop the stubs;
#   - the dir is prepended to PATH unless it is ALREADY the first entry, so these stubs always win
#     over shims placed earlier;
#   - each stub resolves its log at RUN time as ${HERMETIC_EGRESS_LOG:-<its own dir>/egress.log},
#     and an already-set HERMETIC_EGRESS_LOG is never overwritten — a test that asserts on the log
#     sets its OWN private HERMETIC_EGRESS_LOG first (under run-self-tests.sh the parallel workers
#     share one dir and one default log, which is fine for diagnostics but not for assertions);
#   - the dir is NEVER deleted and no EXIT trap is installed: tests install their own traps, and
#     dispatch-pr-review.sh's detached `nohup bash -c` child can outlive the test and still resolve
#     `curl` through PATH. A standalone run leaving one small temp dir behind is accepted.
#
# A test that genuinely needs the REAL curl (its subject is its own 127.0.0.1 server) either runs
# that one command under PATH="$(hermetic_path_without_shims)", or — when the curl call happens deep
# inside the script under test — calls `hermetic_allow_real curl` once, which puts ONLY the real
# curl back ahead of the stubs (the notifier stubs and the env scrub stay in force). Either way the
# test says why in a comment.
#
# Contract: safe under `set -euo pipefail` and `set -u` (every expansion is ${VAR:-} guarded), no
# `exit`, no `set` changes, bash 3.2 compatible. The stubs are POSIX sh using only parameter
# expansion (no dirname/basename), so they work even when a test narrows PATH around them.

# (a) Egress env vars. Derived from their readers — keep this list in sync with them:
#   LOOMWRIGHT_WEBHOOK_URL    — resolve-egress-config.sh "Process-env overrides" block (overrides the
#                               user-scope webhook_url) and send-webhook.sh "Resolve webhook URL";
#   LOOMWRIGHT_WEBHOOK_FORMAT — send-webhook.sh ntfy payload shaping (selects the request body form);
#   LOOMWRIGHT_TELEMETRY_REPO — resolve-egress-config.sh env override and send-telemetry-core.sh
#                               "Resolve target repo" (picks the repo a telemetry issue is filed in).
# Consent itself can never come from env (resolve-egress-config.sh: "there is no env var that can
# grant consent"), so there is no consent variable to scrub. LOOMWRIGHT_NOTIFY_* and
# LOOMWRIGHT_WEBHOOK_DRY_RUN only shape or suppress a send — they route nothing out.
unset LOOMWRIGHT_WEBHOOK_URL LOOMWRIGHT_WEBHOOK_FORMAT LOOMWRIGHT_TELEMETRY_REPO

# (b) The OS-notifier opt-out that notify-desktop.sh already honours as its first gate.
export LOOMWRIGHT_DESKTOP_NOTIFICATIONS=0

# (c) Recording stubs.
_hermetic_stub_names="osascript notify-send terminal-notifier curl wget"

_hermetic_shim_dir_ok() {
  local d="${1:-}" s
  [ -n "$d" ] && [ -d "$d" ] && [ -f "$d/.hermetic-shim-dir" ] || return 1
  for s in $_hermetic_stub_names; do
    [ -f "$d/$s" ] && [ -x "$d/$s" ] || return 1
  done
  return 0
}

if ! _hermetic_shim_dir_ok "${HERMETIC_SHIM_DIR:-}"; then
  HERMETIC_SHIM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/hermetic-shims.XXXXXX" 2>/dev/null)" || HERMETIC_SHIM_DIR=""
  if [ -n "$HERMETIC_SHIM_DIR" ]; then
    for _hermetic_s in $_hermetic_stub_names; do
      cat > "$HERMETIC_SHIM_DIR/$_hermetic_s" <<'HERMETIC_STUB'
#!/bin/sh
# hermetic-test-env.sh recording stub: log the call, touch nothing, succeed.
printf '%s %s\n' "${0##*/}" "$*" >> "${HERMETIC_EGRESS_LOG:-${0%/*}/egress.log}" 2>/dev/null
exit 0
HERMETIC_STUB
      chmod +x "$HERMETIC_SHIM_DIR/$_hermetic_s"
    done
    unset _hermetic_s
    : > "$HERMETIC_SHIM_DIR/.hermetic-shim-dir"
  else
    printf 'hermetic-test-env.sh: WARNING: mktemp failed — egress env scrubbed but no PATH stubs installed\n' >&2
  fi
fi

if [ -n "${HERMETIC_SHIM_DIR:-}" ]; then
  export HERMETIC_SHIM_DIR
  case "${PATH:-}" in
    "$HERMETIC_SHIM_DIR"|"$HERMETIC_SHIM_DIR":*) : ;;
    *) PATH="$HERMETIC_SHIM_DIR${PATH:+:$PATH}" ;;
  esac
  export PATH
  export HERMETIC_EGRESS_LOG="${HERMETIC_EGRESS_LOG:-$HERMETIC_SHIM_DIR/egress.log}"
fi
unset -f _hermetic_shim_dir_ok
unset _hermetic_stub_names

# (d) Marker.
export HERMETIC_TEST_ENV=1

# hermetic_path_without_shims — print $PATH minus every hermetic shim dir (any entry carrying the
# marker file, so a stale outer shim dir is dropped too). For the rare command that needs the real
# binary, e.g.:  PATH="$(hermetic_path_without_shims)" curl -s "http://127.0.0.1:$port/"
hermetic_path_without_shims() {
  local out="" entry rest="${PATH:-}"
  while [ -n "$rest" ]; do
    case "$rest" in
      *:*) entry="${rest%%:*}"; rest="${rest#*:}" ;;
      *)   entry="$rest"; rest="" ;;
    esac
    if [ -n "$entry" ] && [ -f "$entry/.hermetic-shim-dir" ]; then continue; fi
    out="${out:+$out:}$entry"
  done
  printf '%s' "$out"
}

# hermetic_allow_real <cmd>... — for a test whose SUBJECT is a local server: prepend a private dir
# holding symlinks to the REAL <cmd> binaries (resolved with the shims removed), so only those
# commands escape the stubs. Scoped to the calling shell and its children. The egress env stays
# scrubbed, so a real curl still has no webhook/telemetry URL to reach. Returns 1 if a <cmd> has no
# real binary (the caller's own "tool missing" handling then applies as before).
hermetic_allow_real() {
  local d c real rc=0
  d="$(mktemp -d "${TMPDIR:-/tmp}/hermetic-real.XXXXXX" 2>/dev/null)" || return 1
  for c in "$@"; do
    real="$(PATH="$(hermetic_path_without_shims)" command -v "$c" 2>/dev/null)" || real=""
    case "$real" in /*) ln -s "$real" "$d/$c" ;; *) rc=1 ;; esac
  done
  PATH="$d:${PATH:-}"; export PATH
  return "$rc"
}
