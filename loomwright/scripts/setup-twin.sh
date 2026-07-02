#!/usr/bin/env bash
# setup-twin.sh — fail-safe engine for the `/setup twin` module: Twin-readiness status
# + guided cold-start bootstrap (graph + bridge + CLAUDE.md) for a repo.
#
# WHAT: gives a repo its Twin readiness picture and a mechanizable cold-start path. A fresh
# checkout has NO code graph (graphify-out/graph.json), so its findings->community BRIDGE never
# populates and area-knowledge stays empty — the Twin is silent until someone manually runs
# /graphify then build-bridge. This helper closes that "fresh repo's Twin never populates" gap by
# (a) reporting what's present/absent/stale from REAL probes only, and (b) driving the bootstrap:
# detect/guide (or, post-confirm, run) graphify, then ALWAYS rebuild the bridge, then surface a
# CLAUDE.md skeleton when none exists.
#
# WHY here: this is the deterministic, mechanizable engine. The INTERACTIVE half — the
# AskUserQuestion offer, actually running `graphify .`, writing CLAUDE.md, and the
# claude-md-validation freshness check — lives in the COMMAND layer (commands/setup.md), not here.
# This script only probes, guides, and runs the two safe mechanizable steps (build-bridge always;
# graphify only when explicitly told via --run-graphify).
#
# FAIL-SAFE CONTRACT (mirrors build-bridge.sh / read-bridge.sh): every branch — no data, missing
# dependency, absent graph, no git repo — STILL `exit 0`. `check` ALWAYS exits 0. The helper is
# advisory / directional / idempotent: it NEVER blocks a session, NEVER gates, NEVER changes a
# heal_decision or a review decision. A second run with the same state reports the same readiness.
#
# WRITE-CONTAINMENT INVARIANT: the ONLY thing this helper writes is `.supervisor/bridge/` — and
# only via the `build-bridge.sh --out "$repo/.supervisor/bridge"` call (the explicit --out
# short-circuits build-bridge.sh's config-redirect, guaranteeing containment). It writes NO
# CLAUDE.md (the skeleton is stdout-ONLY), NO ~/.claude/settings.json, nothing under ~/.claude/.
# The external `graphify` CLI (only on --run-graphify) writes graphify-out/ — that's graphify's
# write, not this helper's.
#
# Usage:
#   setup-twin.sh check                       # readiness report (always exit 0)
#   setup-twin.sh bootstrap                   # guided cold-start (guide-only for graphify)
#   setup-twin.sh bootstrap --run-graphify    # post-confirm: may run `graphify .` itself
#   setup-twin.sh --root /path/to/repo check  # point at a fixture dir (need not be a git repo)
#   setup-twin.sh -h | --help
#
# Exit: 0 in every normal path.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- arg parsing ------------------------------------------------------------
SUBCMD=""
ROOT_OVERRIDE=""
RUN_GRAPHIFY="no"

usage() {
  # Print the leading header comment block (line 2 through the last contiguous `#` line),
  # robust to header edits — no hard-coded line range to drift when the header grows/shrinks.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    check|bootstrap) [ -z "$SUBCMD" ] && SUBCMD="$1"; shift ;;
    --root)
      # Require a following value. Shift the flag first, then the value ONLY if present —
      # a bare trailing `--root` must NOT `shift 2` (that underflows when $#<2 and would
      # re-process the same arg → spin). A valueless --root is a usage error, not a silent
      # fall-back to git resolution.
      if [ $# -lt 2 ]; then
        echo "setup-twin: --root requires a path argument" >&2
        exit 0   # fail-safe: never break the caller
      fi
      ROOT_OVERRIDE="$2"; shift 2 ;;
    --run-graphify)  RUN_GRAPHIFY="yes"; shift ;;
    -h|--help)       usage ;;
    *) echo "setup-twin: unknown arg '$1' (try --help)" >&2; shift ;;
  esac
done

if [ -z "$SUBCMD" ]; then
  usage
fi

# ---- repo root resolution ---------------------------------------------------
# When --root is given, use it verbatim and do NOT require it to be a git repo (testability).
if [ -n "$ROOT_OVERRIDE" ]; then
  repo="$ROOT_OVERRIDE"
else
  repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# ---- sibling-script resolution (installed plugin OR bare repo) --------------
# Prefer the plugin-bundled build-bridge.sh when CLAUDE_PLUGIN_ROOT is set + that file exists,
# else fall back to the sibling next to THIS script (the bare-repo / self-test path).
BUILD_BRIDGE="$HERE/build-bridge.sh"
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/build-bridge.sh" ]; then
  BUILD_BRIDGE="${CLAUDE_PLUGIN_ROOT}/scripts/build-bridge.sh"
fi

# ---- probes (REAL only — never assert an unprobed state) --------------------

# graph presence + prefix-tolerant staleness. Echoes one of:
#   absent | present (fresh) | present (stale — hint: re-run /graphify) | present (freshness unknown)
probe_graph() {
  local graph="$repo/graphify-out/graph.json"
  if [ ! -e "$graph" ]; then
    echo "absent"
    return
  fi

  # Read built_at_commit. jq preferred; grep fallback. Missing both => freshness unknown.
  local built_at=""
  if command -v jq >/dev/null 2>&1; then
    built_at="$(jq -r '.built_at_commit // empty' "$graph" 2>/dev/null || true)"
  else
    # grep fallback: pull the first "built_at_commit": "<sha>" value, tolerate whitespace.
    built_at="$(grep -oE '"built_at_commit"[[:space:]]*:[[:space:]]*"[^"]*"' "$graph" 2>/dev/null \
      | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' || true)"
  fi

  local cur_head=""
  cur_head="$(git -C "$repo" rev-parse HEAD 2>/dev/null || true)"

  # When HEAD can't be resolved (e.g. --root fixture not a git repo) OR built_at is empty,
  # we cannot decide freshness — never crash, never false-stale.
  if [ -z "$built_at" ] || [ -z "$cur_head" ]; then
    echo "present (freshness unknown)"
    return
  fi

  # Prefix-tolerant compare (mirrors read-bridge.sh's prefix-tolerant `case "$CUR_HEAD"` staleness
  # block EXACTLY — anchored by description, not a line range, which drifts). built_at may be an
  # ABBREVIATED SHA while cur_head is the full 40-char rev-parse, so an exact != false-stales.
  local stale="no"
  case "$cur_head" in
    "$built_at"*) : ;;                          # built_at is a prefix of full head → fresh
    *) case "$built_at" in
         "${cur_head:0:12}"*) : ;;              # head's 12-char prefix is a prefix of built_at → fresh
         *) stale="yes" ;;
       esac ;;
  esac

  if [ "$stale" = "yes" ]; then
    echo "present (stale — hint: re-run /graphify)"
  else
    echo "present (fresh)"
  fi
}

# CLAUDE.md presence + optional age-in-days (never fails on it).
probe_claude_md() {
  local f="$repo/CLAUDE.md"
  if [ ! -f "$f" ]; then
    echo "absent"
    return
  fi
  # Optional mtime-derived age in days (best-effort; portable across GNU + BSD/macOS stat).
  # Try GNU `-c %Y` FIRST (the Linux/CI platform), then BSD/macOS `-f %m`. CRITICAL: the WRONG
  # flavor does not always fail — GNU `stat -f` is filesystem-mode and can return a NON-numeric
  # value (e.g. `?`/a mount point) with exit 0, so we MUST validate that mtime/now are numeric
  # before any arithmetic. An unvalidated non-numeric mtime makes `$(( ))` error and leaves `age`
  # unset, which then trips `set -u` in the echo and silently empties this probe's output
  # (regression: the populated fixture mis-read as `needs bootstrap` on Linux CI).
  local mtime now age
  mtime="$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || true)"
  case "$mtime" in
    ''|*[!0-9]*) echo "present"; return ;;   # empty / non-numeric → no age, never crash
  esac
  now="$(date +%s 2>/dev/null || true)"
  case "$now" in
    ''|*[!0-9]*) echo "present"; return ;;
  esac
  age=$(( (now - mtime) / 86400 ))
  [ "$age" -lt 0 ] && age=0   # clamp clock-skew / future-mtime negatives to a tidy 0d
  echo "present (age: ${age}d)"
}

# brain wiki: matches brain-context's Signal 2 EXACTLY (skills/brain-context/SKILL.md:42) —
# LOOMWRIGHT_BRAIN_ROOT set AND it contains a `wiki/` dir. Checking only the root dir
# would report a false-ready wiki signal that brain-context's read path would then skip.
probe_brain() {
  local root="${LOOMWRIGHT_BRAIN_ROOT:-}"
  if [ -n "$root" ] && [ -d "$root/wiki" ]; then
    echo "set ($root/wiki)"
  else
    echo "not set"
  fi
}

# ---- readiness render (shared by check + bootstrap step d) ------------------
render_readiness() {
  local graph bridge claude brain verdict

  graph="$(probe_graph)"
  if [ -e "$repo/.supervisor/bridge/bridge.json" ]; then bridge="present"; else bridge="absent"; fi
  claude="$(probe_claude_md)"
  brain="$(probe_brain)"

  echo "Twin readiness report for: $repo"
  echo "  graph:      $graph"
  echo "  bridge:     $bridge"
  echo "  CLAUDE.md:  $claude"
  echo "  brain wiki: $brain"

  # Verdict: bootstrapped only when graph+bridge+CLAUDE.md are all present AND the graph is not
  # stale. A `present (stale …)` graph is built but drifting — it needs a re-graphify, so it does
  # NOT count as bootstrapped (this matches the command layer's dashboard cell, which renders a
  # stale graph as `needs bootstrap (stale graph)`). `present (fresh)` / `present (freshness
  # unknown)` / bare `present` still count.
  local has_graph has_claude
  case "$graph" in
    *stale*)  has_graph="no" ;;
    present*) has_graph="yes" ;;
    *)        has_graph="no" ;;
  esac
  case "$claude" in present*) has_claude="yes" ;; *) has_claude="no" ;; esac
  if [ "$has_graph" = "yes" ] && [ "$bridge" = "present" ] && [ "$has_claude" = "yes" ]; then
    verdict="bootstrapped"
  else
    verdict="needs bootstrap"
  fi
  echo "Twin readiness: $verdict"
}

# ---- starter CLAUDE.md skeleton (stdout-ONLY — NEVER written by this helper) ----
print_claude_md_skeleton() {
  # The writable region is delimited by two stable SENTINEL lines so the command layer's
  # confirmed write is machine-extractable — NOT left to agent judgment. The EXACT bytes to
  # write to CLAUDE.md are everything strictly BETWEEN the BEGIN and END sentinels (exclude both
  # sentinel lines and this preamble; there is intentionally NO code fence to strip). A clean
  # extraction recipe is:  sed -n '/CLAUDE_MD_STARTER:BEGIN/,/CLAUDE_MD_STARTER:END/p' | sed '1d;$d'
  cat <<'SKELETON'
A repo CLAUDE.md is ABSENT. This helper NEVER writes CLAUDE.md — the command layer offers to
write it on confirm. Write ONLY the content strictly between the two sentinel lines below,
verbatim (omit the sentinels and this preamble; do NOT wrap it in a code fence):

# >>> setup-twin CLAUDE_MD_STARTER:BEGIN (write everything between BEGIN and END, verbatim) >>>
# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project Overview
<!-- One paragraph: what this project is and who it's for. -->

## Tech Stack
<!-- Languages, frameworks, runtimes, notable libraries, datastores. -->

## Directory Structure
<!-- The top-level layout and what each significant directory holds. -->

## Key Patterns
<!-- Conventions, invariants, and gotchas that aren't obvious from the code.
     Cite concrete file:line references where useful. -->

## How to Run & Test
<!-- The exact commands to build, run, lint, and test locally. -->
# <<< setup-twin CLAUDE_MD_STARTER:END <<<
SKELETON
}

# ---- subcommand: check ------------------------------------------------------
do_check() {
  render_readiness
  exit 0
}

# ---- subcommand: bootstrap --------------------------------------------------
do_bootstrap() {
  echo "== Twin bootstrap for: $repo =="

  # (a / a2) graph step. A graph that is ABSENT or STALE is a graph-(re)producing condition:
  # under --run-graphify (post-confirm) we run `graphify .` to (re)build it — refreshing a stale
  # graph is what lets a `needs bootstrap (stale graph)` repo actually reach `bootstrapped`,
  # otherwise the stale verdict could never clear via /setup twin. A FRESH (or freshness-unknown)
  # graph is left as-is. Reuses probe_graph so the staleness rule stays single-sourced.
  local graph_state graph_action
  graph_state="$(probe_graph)"
  case "$graph_state" in
    absent)  graph_action="build"   ;;   # no graph → build
    *stale*) graph_action="refresh" ;;   # present-but-stale → refresh
    *)       graph_action="none"    ;;   # fresh / freshness-unknown → leave as-is
  esac

  if [ "$graph_action" = "none" ]; then
    echo "[graph] $graph_state — leaving the existing graph as-is (no graphify needed)."
  else
    echo "[graph] $graph_state ⇒ graph needs a ${graph_action}."
    if command -v graphify >/dev/null 2>&1; then
      if [ "$RUN_GRAPHIFY" = "yes" ]; then
        echo "[graph] graphify found and --run-graphify set — running 'graphify .' in $repo to ${graph_action} the graph ..."
        # graphify writes graphify-out/ (graphify's write, not ours). Fail-safe: never break.
        ( cd "$repo" && graphify . ) || echo "[graph] graphify run did not complete cleanly — continuing (fail-safe)." >&2
      elif [ "$graph_action" = "refresh" ]; then
        echo "[graph] graphify CLI is available; the graph is STALE — run 'graphify .' in this repo to refresh it."
        echo "[graph] (the bridge below is rebuilt either way, but the stale verdict clears ONLY after a graph refresh.)"
      else
        echo "[graph] graphify CLI is available; run 'graphify .' in this repo to build the code graph."
        echo "[graph] (the command layer passes --run-graphify only AFTER you confirm; this helper does not prompt.)"
      fi
    else
      echo "[graph] graphify is an EXTERNAL user-global skill/CLI (~/.claude/skills/graphify), triggered by /graphify."
      if [ "$graph_action" = "refresh" ]; then
        echo "[graph] It is not a plugin command. The graph is STALE — run '/graphify .' in this repo to refresh it, then re-run bootstrap."
      else
        echo "[graph] It is not a plugin command. Run '/graphify .' in this repo to build the code graph, then re-run bootstrap."
      fi
    fi
  fi

  # (b) ALWAYS rebuild the bridge after any graph-producing step. build-bridge.sh is itself
  #     fail-safe (no-ops + exit 0 when no graph), so calling it unconditionally is correct.
  #     The explicit --out "$repo/.supervisor/bridge" is MANDATORY — it short-circuits
  #     build-bridge.sh's config-redirect (its `[ -z "$OUT" ] && … .build_bridge.out` override
  #     block, which only fires when --out is empty), guaranteeing write containment.
  if [ -f "$BUILD_BRIDGE" ]; then
    echo "[bridge] rebuilding via $BUILD_BRIDGE ..."
    bash "$BUILD_BRIDGE" --root "$repo" --out "$repo/.supervisor/bridge" \
      || echo "[bridge] build-bridge.sh exited non-zero — continuing (fail-safe)." >&2
  else
    echo "[bridge] build-bridge.sh not found at $BUILD_BRIDGE — skipping bridge rebuild (fail-safe)." >&2
  fi

  # (c) CLAUDE.md.
  if [ -f "$repo/CLAUDE.md" ]; then
    echo "[CLAUDE.md] present — the command layer will validate it (claude-md-validation skill); not validated here."
  else
    echo "[CLAUDE.md] absent — printing a starter skeleton (stdout only; never written by this helper):"
    print_claude_md_skeleton
  fi

  # (d) re-report readiness using the same render as `check`.
  echo "== post-bootstrap readiness =="
  render_readiness
  exit 0
}

case "$SUBCMD" in
  check)     do_check ;;
  bootstrap) do_bootstrap ;;
  *)         usage ;;
esac
