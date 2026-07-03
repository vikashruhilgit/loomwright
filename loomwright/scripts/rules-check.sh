#!/usr/bin/env bash
# rules-check.sh — the SOLE EXECUTION path for the committed .agent/rules/ house-rules substrate.
# (New file — north-star slice #3b-ii enforcement side. Mechanizes the /rules check verb from
#  skills/rules/SKILL.md §8 IN CODE — the ONE human-invoked + confirmed path that actually RUNS a
#  rule's `check` shell. The reader (read-rules.sh) NEVER executes a check; this helper is the only
#  place in the whole slice that can, and only behind an explicit confirmation gate.)
#
# WHAT IT RUNS (per skills/rules/SKILL.md §8):
#   - ONLY rules where enforcement == "must" AND check is a non-null STRING. Advisory rules and
#     null-check rules are SKIPPED (never run — excluded by the jq select below by construction).
#   - Each selected `check` runs from the REPO ROOT via `bash -c "<check>"`, byte-exact to the authored
#     rule (see INPUT CONTRACT below).
#   - An aggregate pass/fail summary is printed at the end.
#
# INPUT CONTRACT (load-bearing security): the `check` string is read DIRECTLY from .agent/rules/*.json
# via jq, reusing the SAME per-object validation + LC_ALL=C first-seen-id-wins dedup as read-rules.sh.
# It is NEVER parsed out of read-rules.sh's human-facing markdown — that reader renders `check` through
# a LOSSY display transform (`gsub("[\t\n]"; " ")`) for readability, so a checker parsing the reader's
# stdout could execute an ALTERED / mis-parsed command. The executed command MUST be byte-exact to the
# authored rule, so we go to the JSON source of truth and carry the check inside jq's data model
# (JSON-escaped) all the way to `bash -c`. (Parity with read-rules.sh's validation + dedup means a
# `check` this helper would run is exactly one the reader would emit — no parser drift can let us run a
# check the reader would have dropped.)
#
# INJECTION SAFETY (jq-only, mirrors read-rules.sh): untrusted rule text enters jq ONLY by jq reading
# each rule file as a POSITIONAL FILE-PATH argument (the path itself comes from `find`, never from rule
# content); the jq program text is fixed and the only flag-passed value is `--argjson fi`, the trusted
# integer file index. Rule text is never string-interpolated into a shell command or a jq program. A
# malformed / non-array file is fail-safe-skipped. The check STRING is emitted from jq (as a compact
# JSON object per line), re-read by jq per line, then run via `bash -c` — that IS arbitrary shell
# execution (the whole point of a confirmed check), gated by the confirmation model below; it is NOT a
# jq-injection surface.
#
# CONFIRMATION + GATE PRECEDENCE (the security core — mirrors run-ground-truth.sh --no-cmd):
#   - --no-cmd (or RULES_CHECK_NO_CMD=1): the unattended trust valve. SKIPS all check execution,
#     recording `[SKIP] ... (cmd execution disabled)`. DEFAULT-OFF but, when set, WINS OVER --confirm
#     (fail-safe: an unattended caller can guarantee nothing runs regardless of any confirm signal).
#   - --confirm (or RULES_CHECK_CONFIRM=1): explicit authorization to execute. Equivalent to an
#     interactive TTY confirmation.
#   - Interactive TTY (stdin AND stdout are TTYs): prompts once and executes on y/Y/yes.
#   - DEFAULT (no --no-cmd, no --confirm, non-interactive / no TTY): does NOT execute — each selected
#     check is reported `[SKIP] ... (skipped — needs confirmation)`. Never blind-executes author-supplied
#     shell with no human in the loop.
#   Precedence, evaluated top-down:  --no-cmd  >  (--confirm | TTY-yes)  >  default-skip.
#
# NOT AN UNATTENDED GATE in this slice: this helper is invoked by `/rules check` (human-invoked). No
# advisory / enforcement seam calls it with execution enabled. The reader stays the safe unattended path.
#
# Usage:  rules-check.sh [--confirm] [--no-cmd]
# Exit:   0 = ran (or skipped) with zero check FAILURES ; 1 = >=1 selected check FAILED when executed.
#         Fail-safe on tooling/absent-store paths (no jq / no rules) → exit 0 (nothing to run).

set -uo pipefail   # NO `set -e` — a failed check is a normal tally, not a script crash.

PROG="rules-check.sh"

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

RULES_DIR=".agent/rules"

# ---------------------------------------------------------------------------
# Parse args + resolve the confirmation / gate signals.
# ---------------------------------------------------------------------------
NO_CMD=0
[ "${RULES_CHECK_NO_CMD:-0}" = "1" ] && NO_CMD=1
CONFIRM=0
[ "${RULES_CHECK_CONFIRM:-0}" = "1" ] && CONFIRM=1

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-cmd)  NO_CMD=1; shift ;;
    --confirm) CONFIRM=1; shift ;;
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      # Fail-safe: an unknown arg is ignored, NEVER executed — but warn on stderr so a
      # typo'd safety flag (e.g. `--no-cmnd` for `--no-cmd`) is not a SILENT no-op.
      # Without this warning a mistyped `--no-cmd` would be dropped, and a co-present
      # `--confirm`/TTY would then execute checks against the caller's intent.
      printf 'rules-check.sh: warning: ignoring unrecognized argument %s (did you mean --no-cmd or --confirm?)\n' "$1" >&2
      shift ;;
  esac
done

# ---------------------------------------------------------------------------
# Tooling presence (fail-safe): jq is REQUIRED to parse the store injection-safely. Absent jq → nothing
# can be resolved to run → fail-safe no-op, exit 0.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "$PROG: jq unavailable — cannot read rules, nothing to run (fail-safe)" >&2
  echo "Checks passed: 0/0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve the EXECUTION MODE up front so it is reported once and applied uniformly.
#   no-cmd      : --no-cmd / RULES_CHECK_NO_CMD=1 present  → skip ALL execution (WINS over confirm).
#   execute     : --confirm / RULES_CHECK_CONFIRM=1, OR an interactive TTY that confirms y/Y/yes.
#   need-confirm: default non-interactive / declined → skip, "needs confirmation".
# ---------------------------------------------------------------------------
MODE="need-confirm"
if [ "$NO_CMD" -eq 1 ]; then
  MODE="no-cmd"                      # --no-cmd WINS over --confirm (fail-safe)
elif [ "$CONFIRM" -eq 1 ]; then
  MODE="execute"
elif [ -t 0 ] && [ -t 1 ]; then
  printf 'Run the `must`-rule check commands from %s ? [y/N] ' "$GITROOT" >&2
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) MODE="execute" ;; *) MODE="need-confirm" ;; esac
fi

# ---------------------------------------------------------------------------
# Collect rule files in LC_ALL=C repo-relative-path-sorted order (deterministic merge order — parity
# with read-rules.sh). Absent dir / no *.json → nothing to run, exit 0.
# ---------------------------------------------------------------------------
files_list="$(mktemp)"
trap 'rm -f "$files_list" 2>/dev/null' EXIT
LC_ALL=C find "$RULES_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null \
  | LC_ALL=C sort > "$files_list" 2>/dev/null || true
if [ ! -s "$files_list" ]; then
  echo "$PROG: no .agent/rules/*.json rule files — nothing to check" >&2
  echo "Checks passed: 0/0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Pass 1 — read each file as a POSITIONAL jq arg (path from find, never rule content), tagging every
# element with its (file_index, elem_index) for deterministic first-seen ordering. Non-array / malformed
# files yield no rows (fail-safe-skip). This mirrors read-rules.sh's ingestion exactly.
# ---------------------------------------------------------------------------
combined="$(mktemp)"
trap 'rm -f "$files_list" "$combined" 2>/dev/null' EXIT
: > "$combined"
fidx=0
while IFS= read -r rf; do
  [ -n "$rf" ] || continue
  rows="$(jq -c \
            --argjson fi "$fidx" '
            if type == "array" then
              to_entries
              | map({ fi: $fi, ei: .key, obj: .value })
              | .[]
            else
              empty
            end' "$rf" 2>/dev/null)"
  [ -n "$rows" ] && printf '%s\n' "$rows" >> "$combined"
  fidx=$((fidx + 1))
done < "$files_list"

if [ ! -s "$combined" ]; then
  echo "$PROG: no parseable rule objects — nothing to check" >&2
  echo "Checks passed: 0/0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Pass 2 — validate every tagged row with the SAME per-object rules as read-rules.sh, dedup by
# first-seen id (LC_ALL=C path-sorted, then array index), and emit ONE COMPACT-JSON object per SELECTED
# rule (enforcement=="must" AND check is a non-null STRING) as a single line:  {"id":…,"check":…}
# The check is carried inside jq's data model (JSON-escaped) so a check containing newlines/tabs/quotes
# is byte-exact on ONE physical line per record — robust to any whitespace in the check, and with NO
# lossy gsub transform (that transform is the READER's human render, which we must NOT parse). Records
# are emitted in the same category,id sort order the reader uses (stable, deterministic).
# ---------------------------------------------------------------------------
selected="$(mktemp)"
trap 'rm -f "$files_list" "$combined" "$selected" 2>/dev/null' EXIT

jq -cs '
  sort_by([.fi, .ei])
  | reduce .[] as $row ( {seen: {}, out: []};
      ($row.obj) as $o
      | (
          if ($o | type) != "object" then                                        {tag:"SKIP"}
          elif ($o.id        | type) != "string" then                            {tag:"SKIP"}
          elif ($o.category  | type) != "string" then                            {tag:"SKIP"}
          elif ($o.statement | type) != "string" then                            {tag:"SKIP"}
          elif (($o.enforcement | type) != "string")
               or (($o.enforcement == "advisory") or ($o.enforcement == "must") | not) then {tag:"SKIP"}
          elif ($o | has("check") | not) then                                    {tag:"SKIP"}
          elif (($o.check | type) != "string") and (($o.check) != null) then     {tag:"SKIP"}
          elif ($o.provenance | type) != "object" then                          {tag:"SKIP"}
          elif (.seen[$o.id] // false) then                                      {tag:"SKIP"}
          else                                                                   {tag:"OK", obj:$o}
          end
        ) as $res
      | if $res.tag == "OK" then
          { seen: (.seen + { ($res.obj.id): true }),
            out:  (.out  + [ $res.obj ]) }
        else
          { seen: .seen, out: .out }
        end
    )
  | .out
  # Select ONLY must-rules whose check is a non-null string, in category,id order. Emit one compact
  # JSON object per selected rule; the RAW check stays byte-exact inside JSON (no lossy transform).
  | map(select(.enforcement == "must" and (.check | type) == "string"))
  | sort_by([.category, .id])
  | .[]
  | {id: .id, check: .check}
' "$combined" 2>/dev/null > "$selected" || true

# ---------------------------------------------------------------------------
# Execute / skip each SELECTED check per the resolved MODE. Advisory + null-check rules were already
# excluded by the jq select above (they are the "skipped" set by construction — never run).
# ---------------------------------------------------------------------------
total=0
passed=0
failures=0
skipped=0

# One compact-JSON record per line. Re-extract id + RAW check via jq (never string-splitting) so a
# check containing tabs/quotes/newlines is recovered byte-exact from the JSON, then run it via bash -c.
while IFS= read -r record; do
  [ -n "$record" ] || continue
  rid="$(printf '%s' "$record" | jq -r '.id')"
  rcheck="$(printf '%s' "$record" | jq -r '.check')"
  total=$((total + 1))

  case "$MODE" in
    no-cmd)
      skipped=$((skipped + 1))
      printf '  [SKIP] %s: %s (cmd execution disabled)\n' "$rid" "$rcheck"
      ;;
    need-confirm)
      skipped=$((skipped + 1))
      printf '  [SKIP] %s: %s (skipped — needs confirmation)\n' "$rid" "$rcheck"
      ;;
    execute)
      # DISPLAY the command, then run it byte-exact from the repo root.
      printf '  [RUN ] %s: %s\n' "$rid" "$rcheck"
      if bash -c "$rcheck" >/dev/null 2>&1; then
        passed=$((passed + 1))
        printf '  [PASS] %s\n' "$rid"
      else
        failures=$((failures + 1))
        printf '  [FAIL] %s\n' "$rid"
      fi
      ;;
  esac
done < "$selected"

# ---------------------------------------------------------------------------
# Aggregate summary. When nothing executed (no-cmd / need-confirm), passed=0 and the line reflects
# 0/<total>; failures drive the exit code.
# ---------------------------------------------------------------------------
if [ "$MODE" != "execute" ]; then
  printf 'Checks skipped: %d/%d (mode: %s)\n' "$skipped" "$total" "$MODE"
  echo "Checks passed: 0/$total"
else
  echo "Checks passed: $passed/$total"
fi

[ "$failures" -eq 0 ] || exit 1
exit 0
