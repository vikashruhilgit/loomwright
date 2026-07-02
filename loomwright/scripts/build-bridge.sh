#!/usr/bin/env bash
# build-bridge.sh — re-runnable READ-ONLY builder for the findings->community BRIDGE index.
#
# WHAT: rebuilds the per-community bridge (.supervisor/bridge/bridge.json + bridge.md) from the
# current code graph (graphify-out/graph.json) + the plugin's accumulated findings, so the runtime
# reader (read-bridge.sh) can answer "what do we already know about the areas this change touches?"
# (finding.changed_paths -> graph node.source_file -> node.community). Graduated from the Step-4
# scratch spike; the heavy lifting lives in the sibling build-bridge.py, this wrapper just resolves
# the repo root + output dir and invokes it. See docs/SPIKES/LOCAL_TWIN_PATH.md Step 5.
#
# READ-ONLY toward the graph + findings it reads; it WRITES only under --out (default the current
# repo's .supervisor/bridge/, which is gitignored). Operator-invoked (like /graphify and
# measure-heal-signal) — NOT auto-built by any phase. Advisory/directional — never gating-grade,
# never blocks a run, never changes a heal_decision.
#
# Output-dir / root resolution:
#   --root PATH    repo root (default: git rev-parse --show-toplevel, else CWD)
#   --out  PATH    output dir (default: <root>/.supervisor/bridge)
#   .supervisor/config.json .build_bridge.out  (only if jq present) — optional override
#
# Usage:
#   build-bridge.sh                          # build for the current repo
#   build-bridge.sh --out /tmp/bridge        # custom output dir
#   build-bridge.sh --root /path/to/repo
#
# NOTE on staleness: only an ABSENT graph is a silent no-op (this wrapper skips + exits 0). A STALE
# graph (HEAD past built_at_commit) STILL builds — the reader downgrades it to a "hint" caveat. To
# refresh the graph first, run `/graphify .` (the graph is gitignored runtime state).
#
# jq is NOT a builder dependency: the engine is pure-Python (json module). jq is consulted ONLY for
# an optional config out-dir override and is guarded by `command -v jq` (proceeds without it).
#
# Exit: 0 in every normal path (a build tool must never break its caller). A missing python3 /
# missing engine / absent graph prints one skip line and exits 0; the engine's own exit code is
# otherwise propagated.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE="$HERE/build-bridge.py"
GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

ROOT=""
OUT=""

usage() {
  sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --out)  OUT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "build-bridge: unknown arg '$1' (try --help)" >&2; exit 0 ;;
  esac
done

[ -n "$ROOT" ] || ROOT="$GITROOT"

# ---- python3 (fail-safe: skip, never break the caller) ----------------------
PY="$(command -v python3 || command -v python || true)"
if [ -z "$PY" ]; then
  echo "build-bridge: python3 required — skipping (no bridge written)." >&2
  exit 0
fi
if [ ! -f "$ENGINE" ]; then
  echo "build-bridge: engine not found at $ENGINE — skipping." >&2
  exit 0
fi

# ---- graph presence (fail-safe: skip, never break the caller) ---------------
if [ ! -f "$ROOT/graphify-out/graph.json" ]; then
  echo "build-bridge: no graph at $ROOT/graphify-out/graph.json — skipping (run /graphify first)." >&2
  exit 0
fi

# ---- optional out-dir override from config (jq-guarded; NOT a hard dependency) ----
if [ -z "$OUT" ] && command -v jq >/dev/null 2>&1 && [ -f "$ROOT/.supervisor/config.json" ]; then
  _cfg_out="$(jq -r '.build_bridge.out // empty' "$ROOT/.supervisor/config.json" 2>/dev/null || true)"
  [ -n "$_cfg_out" ] && OUT="$_cfg_out"
fi

# ---- build engine argv ------------------------------------------------------
ARGS=(--root "$ROOT")
[ -n "$OUT" ] && ARGS+=(--out "$OUT")

"$PY" "$ENGINE" "${ARGS[@]}"
exit $?
