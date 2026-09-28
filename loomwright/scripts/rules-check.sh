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
# THE PARITY IS OVER VALIDITY, NOT APPLICABILITY — THIS CHECKER IS DELIBERATELY REPO-WIDE:
# `read-rules.sh` routes on `applies_to`: given a set of touched paths it emits only the rules scoped
# to them. This checker does NOT follow that routing and takes NO path arguments (see the Usage line
# below; the arg loop warns-and-ignores anything unrecognized). That is a decision, not an oversight.
# The two are on different axes. Routing is an EMISSION FILTER for advisory injection — "which of our
# conventions are worth putting in front of an agent editing THESE files right now?" — and its input is
# a diff. `/rules check` is an AUDIT — "are all our conventions upheld?" — and its input is the repo.
# A rule routed out of some worker's advisory block has not stopped being true, so a routed-out rule is
# STILL selected here and its `check` still runs under confirmation (pinned by test-rules-check.sh case
# (f)). The parity this file promises with the reader is over PER-OBJECT VALIDATION + `LC_ALL=C`
# first-seen-id dedup — *which objects are well-formed* — and routing touches neither. Giving the
# checker a path scope would also be new surface the source requirement's Non-goals foreclose.
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
#     AND --if-stamped (fail-safe: an unattended caller can guarantee nothing runs regardless of any
#     other signal).
#   - --confirm (or RULES_CHECK_CONFIRM=1): explicit authorization to execute. Equivalent to an
#     interactive TTY confirmation. EXCEPTION (PR #267 Phase 4.5 finding 1): when --if-stamped is on
#     argv, the RULES_CHECK_CONFIRM env var does NOT count — only an explicit argv `--confirm` can
#     confirm. Otherwise an ambient `RULES_CHECK_CONFIRM=1` in the environment of an unattended
#     `--if-stamped` caller would run every must-check with no stamp at all AND write the stamp,
#     laundering an unconfirmed set into a "confirmed" one.
#   - --if-stamped (executable-rule-candidates/01, non-interactive, NEVER prompts): the UNATTENDED
#     REPLAY valve. It computes the live sha256 hash of the SAME (sorted `id\tcheck`) selection this
#     run would otherwise execute, and compares it to the STAMP recorded for this repository (keyed by
#     its physical `git rev-parse --git-common-dir`, see "THE STAMP" below) in the user-scope stamp
#     file $RULES_CHECK_STAMP_FILE. Equal ⇒ execute with no prompt, same output shape as --confirm.
#     Unequal or absent ⇒ print `[SKIP] all (unstamped)` and `Checks passed: 0/0`, exit 0 — the
#     per-rule loop below is not even entered. It is evaluated BEFORE the TTY prompt, so an
#     `--if-stamped` run never prompts even on a terminal. A stamped REPLAY does NOT itself refresh
#     the stamp (see "THE STAMP WRITE" below) — only a genuine --confirm/TTY-y run does, so the stamp
#     always traces back to an actual human confirmation, never to an automated replay of one.
#   - Interactive TTY (stdin AND stdout are TTYs, no --if-stamped): prompts once and executes on
#     y/Y/yes.
#   Precedence, evaluated top-down (--list-selected and --list-gateable, two read-only listings, sit
#   above all of these):
#     --list-selected  >  --list-gateable  >  --no-cmd
#               >  argv --confirm (or RULES_CHECK_CONFIRM=1 when --if-stamped is ABSENT)
#               >  --if-stamped  >  TTY-yes  >  default-skip.
#
# THE STAMP (R2 — the SECOND security boundary this slice adds, independent of the reject/allowlist
# boundary in harvest-conventions.sh's check_candidate). `.agent/rules/*.json` is repo-committed and
# MODEL-WRITABLE inside an unreviewed PR — unlike a Launch-Pad-authored brief, which only ever saves
# after an explicit human Phase 6 approval. So execution is keyed to a fact recorded OUTSIDE the repo,
# in USER scope: a fresh `git clone` of a repo carrying a maliciously-edited `check` cannot forge its
# own "a human already confirmed this" — the stamp lives on the human's own machine, in the SAME
# per-user Loomwright config directory under $HOME that red-team-hardening item 02 established for
# `egress.json` (resolve-egress-config.sh), but in its OWN file (`rules-check-stamp.json`, never `egress.json` itself, which is telemetry-specific).
# KEYED PER REPOSITORY, NOT PER CHECKOUT PATH (PR #267 Phase 4.5 finding 5): the key is the PHYSICAL
# absolute path of `git rev-parse --git-common-dir` (made physical via `cd … && pwd -P`, not the
# non-portable `realpath`). Every linked worktree of one repository shares that directory, so a set
# confirmed in the main checkout replays in an /automate worktree of the same repo on the same
# machine — while a separate clone (its own .git) is a separate key and stays unstamped. Outside a
# git repo the key falls back to the physical cwd. The record stores `git_common_dir` (the key),
# `repo_root` (the checkout that LAST confirmed — informational only, never read back), `hash`, `ts`.
# This is DELIBERATELY the opposite mechanism from `exec-acceptance-lib.sh`'s brief-embedded
# `sha256:` stamp line (red-team-hardening item 05) — that stamp lives INSIDE the (human-approved)
# brief precisely because a brief only exists after a human already signed off on it; a `.agent/rules/`
# object has no such gate, so its stamp cannot live in the same repo-committed place without
# reintroducing exactly the vulnerability this design prevents. Deliberately per-user-per-machine, NOT
# shared across CI or teammates: every other machine/CI replays `unstamped` until ITS OWN human runs
# `/rules check --confirm` once there.
#
# HONEST LIMIT — CONCURRENT WRITES: the stamp write is a read-modify-rename with NO lock. Two
# confirming runs for different repos racing on one machine are last-writer-wins: one repo's fresh
# record can be lost, and that repo simply replays `unstamped` until its human confirms again. That
# is fail-closed (a lost stamp never RUNS anything), so no lock is taken.
#
# THE STAMP WRITE. On a run whose MODE resolves to `execute` via a GENUINE --confirm/RULES_CHECK_CONFIRM=1
# /TTY-y (never via a --if-stamped-promoted replay), this script writes
# `{git_common_dir, repo_root, hash, ts}` into the stamp file, keyed by $STAMP_KEY (the physical
# git-common-dir — see "THE STAMP"), AFTER the run completes — regardless of whether any
# individual check PASSED or FAILED (the stamp records "a human confirmed THIS SET was run", not "every
# check in it currently passes"; a failing stamped check still replays and still fails under
# --if-stamped, which is the honest, non-gating behaviour this whole feature is advisory for). `hash` is
# sha256 over the sorted `id\tcheck\n` lines of EXACTLY the must-rules the execute loop's own selection
# query chose — the SAME in-memory value feeds both the stamp write and the --if-stamped comparison, so
# the two can never independently drift on what "the set" means.
#
# UNATTENDED CALLERS: this helper is invoked by `/rules check` (human-invoked) and, for --if-stamped
# only, by advisory consumers — Phase 4.5's replay (`skills/self-heal-advisory/SKILL.md`),
# run-ground-truth.sh's `rule:` kind, and, at worker Step 5, `worker-rule-selfcheck.sh` (REPORT-ONLY
# `rule:` deviations) — and by `rules-gate-verdict.sh`, the fail-CLOSED verdict helper the review and
# merge gates delegate to (rule-enforcement-at-review-and-merge): it maps a STAMPED, COUNTABLE (see
# `binds` below) must-check's FAIL to a gating verdict, while `unstamped` / `cmd_disabled` / advisory
# stay advisory. No caller has unattended WRITE authority; --if-stamped can only ever replay a set a
# human already confirmed on this machine, and this script remains the SOLE executor of a check.
#
# --list-selected (plan-time-rule-routing, READ-ONLY enumeration): prints the id of every rule the
# execute loop WOULD select (enforcement `must` AND a non-null string `check`, after the SAME
# per-object validation + LC_ALL=C first-seen dedup), one per line, LC_ALL=C-sorted, and exits 0. It
# executes NOTHING, writes NO stamp and NEVER prompts: it short-circuits the MODE block (no TTY
# prompt, no confirm/if-stamped branch) and exits right after the selection is computed, before the
# --if-stamped comparison and the execute loop. It therefore WINS over --confirm, --if-stamped AND
# --no-cmd (listing ids executes nothing, so the no-cmd valve has nothing to guard). Every early-exit
# path (no jq / no rule files / no parseable objects) prints NOTHING on stdout in this mode, so the
# stdout is EXACTLY the id list (empty on an empty/absent store). An id containing a newline or CR is
# OMITTED from the list (it could otherwise inject a second, forged id line, and no one-line
# `rule: <id>` bullet can name it anyway); a caller comparing the list's length to a later
# `Checks passed: N/M` total therefore sees a mismatch and fails CLOSED. Consumers: run-ground-truth.sh's
# `rule:` kind and worker-rule-selfcheck.sh, which learn "which ids are checkable?" without ever
# reading the store themselves — this script stays the ONE place that parses a `check`.
#
# `binds` + --list-gateable (rule-enforcement-at-review-and-merge, D-a — the gate's universe):
#   A rule MAY carry an OPTIONAL `binds` field: `null`/absent, or an array of repo-relative path
#   strings (the `applies_to` path space; the same write-time rejections — `..`, absolute, `~`).
#   Semantics: "the repo-TRACKED files this check EXECUTES; their CONTENT is part of what the
#   confirming human approved".
#   HASH BINDING: when a selected rule carries a NON-EMPTY `binds` array, its LIVE_HASH input line
#   becomes `id\tcheck\t<path>=<sha256 of content | MISSING | INVALID>` per element in LC_ALL=C sorted
#   order (paths resolved from the repo root; `MISSING` = tracked but absent from the working tree;
#   `INVALID` = malformed / untracked / outside the repo / not a string). A rule WITHOUT `binds`
#   (absent, `null`, `[]`, or not an array) hashes EXACTLY as before `binds` existed, so every existing
#   stamp stays valid. Both the stamp WRITE and the --if-stamped COMPARE read the one LIVE_HASH, so a
#   PR that edits a bound file moves the live hash ⇒ `[SKIP] all (unstamped)` — the edit cannot turn
#   a stamped failure into a counted pass without a human re-running `/rules check --confirm`.
#   --list-gateable (READ-ONLY classification, same early-exit tier as --list-selected — executes
#   nothing, writes no stamp, never prompts, exits 0; every early-exit path prints NOTHING on stdout):
#   prints ONE `id<TAB>countable|advisory<TAB><reason>` line per SELECTED id (the --list-selected set),
#   LC_ALL=C sorted. Per check it derives the DETECTED INVOKED FILES = every whitespace-split token
#   (surrounding quotes and a leading `./` stripped) that resolves from the repo root to a git-TRACKED
#   file (`git ls-files --error-unmatch`, never `[ -e ]` alone) AND is executable (`test -x`) OR
#   starts with `#!` OR is immediately preceded by an interpreter word from the FIXED set
#   `bash sh zsh source . python python3 node perl ruby`. Reasons:
#     advisory   binds_undeclared   no `binds` key or `binds: null` — nothing a human declared is counted
#     advisory   binds_invalid      `binds` present but not an array of strings, or an element that is
#                                   absolute / `..`-bearing / `~` / untracked / control-char-bearing
#     advisory   unbound:<p>[,<p>]  detected invoked files NOT declared in `binds` (the declaration
#                                   was dishonest or incomplete — the heuristic DEMOTES it)
#     countable  no_invocations     explicit `binds: []` AND zero detected invoked files
#     countable  bound:<n>          non-empty `binds`, every detected file declared (n = distinct paths)
#   The (i) leg is an EXPLICIT human declaration, never an inference: the heuristic only ever DEMOTES a
#   rule to advisory; it never promotes one.
#   HONEST LIMITS of the detection (all resolve to "a countable rule whose check executes something it
#   did not declare" — the remedy is to declare the executed files in `binds`, and item 09's
#   `audit-rules.sh unbound_invocation` follow-up is the seam that should flag them):
#     - TASK-RUNNER INDIRECTION: `make lint`, `npm run lint`, `pytest`, `cargo test`, `go test ./...`
#       execute tracked files (Makefile, package.json scripts, conftest/test modules) that a
#       whitespace-token scan cannot see — a human who declares `binds: []` on such a check has
#       asserted something false.
#     - TRANSITIVE CALLS: a bound script that calls another script — only the first hop is bound.
#     - `$(…)`, `eval`, backticks, globs, brace expansion, variables: the token is not a literal path.
#     - INTERPRETER ALIASES / wrappers (`python3.12`, `uv run`, `npx`, `bun`, `/usr/bin/env python`):
#       the preceding-word set is fixed; a non-+x, non-`#!` file behind an alias is not detected.
#     - NON-CANONICAL PATH FORMS (`scripts/../scripts/x.sh`, `"$ROOT/x.sh"`) and a token glued to
#       punctuation (`x.sh;`, `x.sh)`) are not resolved.
#   An id containing a tab is printed as-is (the consumer parses the LAST two tab fields); an id
#   carrying a newline/CR is omitted exactly as under --list-selected.
#
# Usage:  rules-check.sh [--confirm] [--no-cmd] [--if-stamped] [--list-selected] [--list-gateable]
# Exit:   0 = ran (or skipped) with zero check FAILURES ; 1 = >=1 selected check FAILED when executed.
#         Fail-safe on tooling/absent-store paths (no jq / no rules) → exit 0 (nothing to run).
#         --list-selected and --list-gateable always exit 0.

set -uo pipefail   # NO `set -e` — a failed check is a normal tally, not a script crash.

PROG="rules-check.sh"

GITROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$GITROOT" 2>/dev/null || true

# STAMP_KEY — the physical git-common-dir (shared by every linked worktree of this repository), or
# the physical cwd outside a repo. See the header's "THE STAMP" note. `--git-common-dir` may print a
# path RELATIVE to the cwd (e.g. `.git` in a main checkout), hence resolving it after the cd above.
STAMP_KEY=""
_rc_gcd="$(git rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "$_rc_gcd" ]; then
  STAMP_KEY="$(cd "$_rc_gcd" 2>/dev/null && pwd -P)"
fi
[ -n "$STAMP_KEY" ] || STAMP_KEY="$(pwd -P)"
# Honest limit: `git rev-parse` honours a caller-set GIT_DIR/GIT_COMMON_DIR, so the CALLER's
# environment can redirect STAMP_KEY. A repository cannot set its caller's environment, and whoever
# controls that environment can already execute anything (e.g. BASH_ENV) — so this is not unset here.

RULES_DIR=".agent/rules"

# ---------------------------------------------------------------------------
# Parse args + resolve the confirmation / gate signals.
# ---------------------------------------------------------------------------
NO_CMD=0
[ "${RULES_CHECK_NO_CMD:-0}" = "1" ] && NO_CMD=1
CONFIRM=0
CONFIRM_ENV=0
[ "${RULES_CHECK_CONFIRM:-0}" = "1" ] && CONFIRM_ENV=1
IF_STAMPED=0
LIST_SELECTED=0
LIST_GATEABLE=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-cmd)     NO_CMD=1; shift ;;
    --confirm)    CONFIRM=1; shift ;;   # ARGV confirm — the only confirm that counts under --if-stamped
    --if-stamped) IF_STAMPED=1; shift ;;
    --list-selected) LIST_SELECTED=1; shift ;;   # read-only enumeration — wins over every mode flag
    --list-gateable) LIST_GATEABLE=1; shift ;;   # read-only classification — same tier, below --list-selected
    -h|--help)
      grep -E '^# ' "$0" | sed -E 's/^# ?//'
      exit 0 ;;
    *)
      # Fail-safe: an unknown arg is ignored, NEVER executed — but warn on stderr so a
      # typo'd safety flag (e.g. `--no-cmnd` for `--no-cmd`) is not a SILENT no-op.
      # Without this warning a mistyped `--no-cmd` would be dropped, and a co-present
      # `--confirm`/TTY would then execute checks against the caller's intent.
      printf 'rules-check.sh: warning: ignoring unrecognized argument %s (did you mean --no-cmd, --confirm, --if-stamped, --list-selected, or --list-gateable?)\n' "$1" >&2
      shift ;;
  esac
done

# THE ANTI-LAUNDERING RULE (PR #267 Phase 4.5 finding 1): the RULES_CHECK_CONFIRM env var confirms
# ONLY when --if-stamped is absent. With --if-stamped on argv, an ambient env confirm is ignored — an
# unattended replay caller cannot be promoted into a fresh, stamp-writing confirmation by its
# environment. Only an explicit argv --confirm (a deliberate human act on the command line) can.
if [ "$CONFIRM_ENV" -eq 1 ] && [ "$IF_STAMPED" -eq 0 ]; then
  CONFIRM=1
fi

# ---------------------------------------------------------------------------
# sha256 helper — mirrors exec-acceptance-lib.sh's OWN fallback chain (shasum -a 256 -> sha256sum ->
# openssl dgst) for CONSISTENCY, not by sourcing that library: this stamp is a deliberately SEPARATE
# trust boundary from the brief-embedded `sha256:` stamp exec-acceptance-lib.sh implements (see the
# header's "THE STAMP" note), so it gets its own small, self-contained hasher rather than a shared
# dependency on a library built for a different mechanism.
# ---------------------------------------------------------------------------
_rc_sha256_file() {
  local f="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$f" 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$f" 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$f" 2>/dev/null | awk '{print $NF}'
  fi
}

# stamp file location — USER scope, NEVER the repo. The same per-user directory under $HOME that
# red-team-hardening/02 established for egress.json, but its OWN, separate file. This assignment is
# the ONE place the path is spelled out; every other reference derives from it.
RULES_CHECK_STAMP_FILE="${HOME:-}/.claude/loomwright/rules-check-stamp.json"

# _rc_read_stamp_hash <stamp_key> — prints the stored hash for this key, or empty (absent /
# unreadable / unparseable / no HOME / no jq — all fail CLOSED to "no stamp", never a fabricated match).
_rc_read_stamp_hash() {
  local key="$1"
  [ -n "${HOME:-}" ] || return 0
  [ -r "$RULES_CHECK_STAMP_FILE" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -e . "$RULES_CHECK_STAMP_FILE" >/dev/null 2>&1 || return 0
  jq -r --arg k "$key" \
    'if type == "object" then ((.[$k].hash // "") | if type == "string" then . else "" end) else "" end' \
    "$RULES_CHECK_STAMP_FILE" 2>/dev/null || true
}

# _rc_write_stamp <stamp_key> <repo_root> <hash> — best-effort: never blocks/errors the run and never
# changes the exit code, but a write that does not land is WARNED on stderr (a silent failure would
# leave the human believing the set is stamped when every later --if-stamped replays `unstamped`).
# Only ever called after a GENUINE --confirm/TTY-y execute completes — see "THE STAMP WRITE" above.
# No lock: concurrent writers are last-writer-wins (header, "HONEST LIMIT — CONCURRENT WRITES").
_rc_write_stamp() {
  local key="$1" repo_root="$2" hash="$3" dir ts tmp existing
  [ -n "${HOME:-}" ] || { echo "$PROG: warning: HOME unset — stamp not written" >&2; return 0; }
  command -v jq >/dev/null 2>&1 || return 0
  dir="$(dirname "$RULES_CHECK_STAMP_FILE")"
  mkdir -p "$dir" 2>/dev/null || { echo "$PROG: warning: cannot create $dir — stamp not written" >&2; return 0; }
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  existing="{}"
  if [ -r "$RULES_CHECK_STAMP_FILE" ] && jq -e . "$RULES_CHECK_STAMP_FILE" >/dev/null 2>&1; then
    if [ "$(jq -r 'type' "$RULES_CHECK_STAMP_FILE" 2>/dev/null)" != "object" ]; then
      # Valid JSON that is not an object: never clobber a file we do not understand.
      echo "$PROG: warning: $RULES_CHECK_STAMP_FILE is valid JSON but not an object — stamp not written (fix or remove the file)" >&2
      return 0
    fi
    existing="$(cat "$RULES_CHECK_STAMP_FILE" 2>/dev/null || echo '{}')"
  fi
  tmp="$(mktemp "$dir/.rules-check-stamp.XXXXXX" 2>/dev/null)" \
    || { echo "$PROG: warning: cannot create a temp file in $dir — stamp not written" >&2; return 0; }
  if printf '%s' "$existing" | jq --arg k "$key" --arg rr "$repo_root" --arg h "$hash" --arg ts "$ts" \
       '. + {($k): {git_common_dir: $k, repo_root: $rr, hash: $h, ts: $ts}}' > "$tmp" 2>/dev/null \
     && mv -f "$tmp" "$RULES_CHECK_STAMP_FILE" 2>/dev/null; then
    :
  else
    rm -f "$tmp" 2>/dev/null
    echo "$PROG: warning: failed to write $RULES_CHECK_STAMP_FILE — stamp not written" >&2
  fi
}

# ---------------------------------------------------------------------------
# Tooling presence (fail-safe): jq is REQUIRED to parse the store injection-safely. Absent jq → nothing
# can be resolved to run → fail-safe no-op, exit 0.
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  echo "$PROG: jq unavailable — cannot read rules, nothing to run (fail-safe)" >&2
  # --list-selected / --list-gateable: stdout is ONLY the listing (empty here).
  [ "$LIST_SELECTED" -eq 1 ] || [ "$LIST_GATEABLE" -eq 1 ] || echo "Checks passed: 0/0"
  exit 0
fi

# ---------------------------------------------------------------------------
# Resolve the EXECUTION MODE up front so it is reported once and applied uniformly.
#   no-cmd      : --no-cmd / RULES_CHECK_NO_CMD=1 present  → skip ALL execution (WINS over everything).
#   execute     : argv --confirm / RULES_CHECK_CONFIRM=1 (env counts ONLY without --if-stamped — see
#                 the anti-laundering rule above), OR — without --if-stamped — an interactive TTY that
#                 confirms y/Y/yes. CAME_FROM_CONFIRM=1 records that this is a GENUINE confirmation
#                 (eligible to write a stamp), as opposed to a later --if-stamped promotion below.
#   if-stamped  : --if-stamped, no --no-cmd, no argv --confirm. Evaluated BEFORE the TTY branch, so it
#                 NEVER prompts, even on a terminal. DEFERRED — the
#                 actual hash comparison happens after $selected is built below (it needs the same
#                 selection the execute loop will use), and either promotes this to "execute"
#                 (CAME_FROM_CONFIRM stays 0 — a replay is not a fresh confirmation) or short-circuits
#                 the whole run with "[SKIP] all (unstamped)" before the per-rule loop is even entered.
#   need-confirm: default non-interactive / declined / no --if-stamped → skip, "needs confirmation".
# ---------------------------------------------------------------------------
MODE="need-confirm"
CAME_FROM_CONFIRM=0
if [ "$LIST_SELECTED" -eq 1 ]; then
  MODE="list-selected"               # read-only enumeration: WINS over everything, never prompts
elif [ "$LIST_GATEABLE" -eq 1 ]; then
  MODE="list-gateable"               # read-only classification: same tier, executes nothing, never prompts
elif [ "$NO_CMD" -eq 1 ]; then
  MODE="no-cmd"                      # --no-cmd WINS over everything (fail-safe)
elif [ "$CONFIRM" -eq 1 ]; then
  MODE="execute"; CAME_FROM_CONFIRM=1
elif [ "$IF_STAMPED" -eq 1 ]; then
  MODE="if-stamped"                  # BEFORE the TTY branch: an --if-stamped run never prompts
elif [ -t 0 ] && [ -t 1 ]; then
  printf 'Run the `must`-rule check commands from %s ? [y/N] ' "$GITROOT" >&2
  read -r reply || reply=""
  case "$reply" in y|Y|yes|YES) MODE="execute"; CAME_FROM_CONFIRM=1 ;; *) MODE="need-confirm" ;; esac
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
  [ "$MODE" = "list-selected" ] || [ "$MODE" = "list-gateable" ] || echo "Checks passed: 0/0"
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
  [ "$MODE" = "list-selected" ] || [ "$MODE" = "list-gateable" ] || echo "Checks passed: 0/0"
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
  # `binds` (rule-enforcement-at-review-and-merge, D-a) is carried ONLY when the key is PRESENT, so
  # downstream an explicit `has("binds")` can tell an ABSENT key (advisory: nothing declared) from an
  # explicit `binds: []` (a human asserted "this check executes no repo file"). Never `// []` here —
  # that would collapse the two and silently promote an undeclared rule to countable.
  | {id: .id, check: .check} + (if has("binds") then {binds: .binds} else {} end)
' "$combined" 2>/dev/null > "$selected" || true

# ---------------------------------------------------------------------------
# --list-selected: print the SELECTED ids (the exact set the execute loop would run), sorted, and
# exit 0 — BEFORE the hash / --if-stamped comparison / execute loop / stamp write, none of which a
# listing may reach. Ids carrying a newline/CR are dropped (see the header): one id, one line.
# ---------------------------------------------------------------------------
if [ "$MODE" = "list-selected" ]; then
  jq -r '.id | select(test("[\n\r]") | not)' "$selected" 2>/dev/null | LC_ALL=C sort
  exit 0
fi

# ---------------------------------------------------------------------------
# `binds` helpers (rule-enforcement-at-review-and-merge, D-a). Shared by the LIVE_HASH extension and
# the --list-gateable classification below. All READ-ONLY: `git ls-files`, `test`, `head -c 2`,
# sha256 of file content — nothing here executes a check or a bound file.
# ---------------------------------------------------------------------------

# _rc_path_ok <p> — exit 0 iff <p> is a well-formed repo-relative path string: the SAME write-time
# rejections /rules add applies to `applies_to` (non-empty; not absolute; not `~`-relative; no `..`;
# no tab / newline / CR).
_rc_path_ok() {
  local p="$1"
  [ -n "$p" ] || return 1
  case "$p" in
    /*|'~'*|*..*|*$'\t'*|*$'\n'*|*$'\r'*) return 1 ;;
  esac
  return 0
}

# _rc_tracked_file <p> — exit 0 iff <p> is a git-TRACKED file path (an index entry EXACTLY <p>,
# resolved from the repo root; a directory or an untracked / gitignored / outside-the-repo path is
# not). `core.quotePath=false` so a non-ASCII path compares byte-exact; `--literal-pathspecs` so a
# token carrying `*`/`?`/`[`/`:(magic)` is matched as a literal name, never as a pattern. The WHOLE
# listing is compared (no `| head` — under pipefail a truncated multi-line listing would SIGPIPE the
# producer and hide the answer). Never `[ -e ]` alone.
_rc_tracked_file() {
  local p="$1" listed
  listed="$(git --literal-pathspecs -c core.quotePath=false ls-files --error-unmatch -- "$p" 2>/dev/null </dev/null)" || return 1
  [ -n "$listed" ] && [ "$listed" = "$p" ]
}

# _rc_bind_value <p> — the hash-input value for ONE `binds` element: the sha256 of its content, or
# `MISSING` (tracked but absent from the working tree), or `INVALID` (malformed / untracked / outside
# the repo). Deterministic for any input; INVALID also drives --list-gateable's `binds_invalid`.
_rc_bind_value() {
  local p="$1"
  _rc_path_ok "$p" || { printf 'INVALID\n'; return 0; }
  _rc_tracked_file "$p" || { printf 'INVALID\n'; return 0; }
  if [ -f "$p" ]; then _rc_sha256_file "$p"; else printf 'MISSING\n'; fi
}

# _rc_binds_lines <record> — one line per `binds` element, LC_ALL=C sorted: `S<TAB><path>` for a
# string element free of tab/newline/CR, `X<TAB><json>` for anything else (always INVALID). Prints
# nothing when `binds` is absent / null / not an array / empty — the binds-free hash stays as today.
_rc_binds_lines() {
  printf '%s' "$1" | jq -r '
    if (has("binds") and (.binds | type) == "array") then
      .binds[]
      | if (type == "string" and (test("[\t\n\r]") | not)) then "S\t" + . else "X\t" + tojson end
    else empty end' 2>/dev/null | LC_ALL=C sort
}

# _rc_hash_line <record> — this record's LIVE_HASH input line: `id\tcheck` (byte-identical to the
# pre-`binds` checker for a rule whose `binds` is absent / null / `[]` / not an array — every existing
# stamp stays valid) and, for a non-empty `binds` array, `\t<path>=<sha256|MISSING|INVALID>` appended
# per element in `_rc_binds_lines` order. A bound file's CONTENT is thereby part of what the
# confirming human approved: editing it moves the live hash ⇒ `--if-stamped` replays `unstamped`.
_rc_hash_line() {
  local rec="$1" line l tag p v blines
  blines="$(_rc_binds_lines "$rec")"
  if [ -z "$blines" ]; then
    # BINDS-FREE: the pre-`binds` pipeline VERBATIM (jq straight into the hash input — no capture, so
    # not even a jq failure or a byte a command substitution would drop can differ from before).
    printf '%s' "$rec" | jq -r '[.id, .check] | @tsv' 2>/dev/null
    return 0
  fi
  line="$(printf '%s' "$rec" | jq -r '[.id, .check] | @tsv' 2>/dev/null)" || return 0
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    tag="${l%%$'\t'*}"; p="${l#*$'\t'}"
    if [ "$tag" = "S" ]; then v="$(_rc_bind_value "$p")"; else v="INVALID"; fi
    line="$line"$'\t'"$p=$v"
  done <<EOF
$blines
EOF
  printf '%s\n' "$line"
}

# _rc_is_interp <tok> — the fixed interpreter-word set: a tracked file token that immediately follows
# one of these is "invoked" even when it is neither +x nor `#!`-headed.
_rc_is_interp() {
  case "$1" in bash|sh|zsh|source|.|python|python3|node|perl|ruby) return 0 ;; esac
  return 1
}

# _rc_detect_invoked <check> — the DETECTED INVOKED FILES of a check, one per line, LC_ALL=C sorted,
# deduplicated: every whitespace-split token (surrounding quotes and a leading `./` stripped) that
# resolves from the repo root to a git-TRACKED file present in the working tree AND is executable
# (`test -x`) OR starts with `#!` OR is immediately preceded by an interpreter word (_rc_is_interp).
# Glob expansion is OFF while splitting (a `*` token must stay a literal token). This is a HEURISTIC
# that only ever DEMOTES a rule (see the header's --list-gateable honest limits): it cannot see
# task-runner indirection, transitive calls, `$(…)`/`eval`/globs or interpreter aliases.
_rc_detect_invoked() {
  local check="$1" tok t prev="" out=""
  set -f
  # shellcheck disable=SC2086 — whitespace-splitting the check into tokens is the point.
  for tok in $check; do
    t="$tok"
    while :; do case "$t" in \'*|\"*) t="${t#?}" ;; *) break ;; esac; done
    while :; do case "$t" in *\'|*\") t="${t%?}" ;; *) break ;; esac; done
    t="${t#./}"
    if [ -n "$t" ] && _rc_path_ok "$t" && _rc_tracked_file "$t" && [ -f "$t" ]; then
      if [ -x "$t" ] || [ "$(head -c 2 "$t" 2>/dev/null)" = "#!" ] || _rc_is_interp "$prev"; then
        case $'\n'"$out" in *$'\n'"$t"$'\n'*) : ;; *) out="$out$t"$'\n' ;; esac
      fi
    fi
    prev="$t"
  done
  set +f
  printf '%s' "$out" | LC_ALL=C sort
}

# _rc_lg_classify <record> <id> <check> — ONE `id<TAB>countable|advisory<TAB><reason>` line. The
# classification only ever DEMOTES: nothing is counted that a human did not explicitly declare.
#   binds absent / null                      ⇒ advisory  binds_undeclared
#   binds not an array / element not a well-formed tracked path ⇒ advisory  binds_invalid
#   detected invoked files ⊄ binds           ⇒ advisory  unbound:<p>[,<p>]  (sorted, the undeclared ones)
#   binds == [] and zero detections          ⇒ countable no_invocations
#   non-empty binds, detected ⊆ binds        ⇒ countable bound:<n>  (n = distinct bound paths)
_rc_lg_classify() {
  local rec="$1" rid="$2" rcheck="$3" bkind l tag p v invalid=0 nb=0 bset="" detected unbound="" nl
  nl=$'\n'
  bkind="$(printf '%s' "$rec" | jq -r '
    if (has("binds") | not) then "absent"
    elif .binds == null then "null"
    elif (.binds | type) != "array" then "nonarray"
    else "array" end' 2>/dev/null)"
  case "$bkind" in
    absent|null) printf '%s\tadvisory\tbinds_undeclared\n' "$rid"; return 0 ;;
    array) : ;;
    *)           printf '%s\tadvisory\tbinds_invalid\n' "$rid"; return 0 ;;
  esac
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    tag="${l%%$'\t'*}"; p="${l#*$'\t'}"
    if [ "$tag" != "S" ]; then invalid=1; continue; fi
    v="$(_rc_bind_value "$p")"
    [ "$v" != "INVALID" ] || invalid=1
    case "$nl$bset" in *"$nl$p$nl"*) : ;; *) bset="$bset$p$nl"; nb=$((nb + 1)) ;; esac
  done <<EOF
$(_rc_binds_lines "$rec")
EOF
  if [ "$invalid" -eq 1 ]; then printf '%s\tadvisory\tbinds_invalid\n' "$rid"; return 0; fi
  detected="$(_rc_detect_invoked "$rcheck")"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    case "$nl$bset" in *"$nl$p$nl"*) : ;; *) unbound="${unbound:+$unbound,}$p" ;; esac
  done <<EOF
$detected
EOF
  if [ -n "$unbound" ]; then
    printf '%s\tadvisory\tunbound:%s\n' "$rid" "$unbound"
  elif [ "$nb" -eq 0 ]; then
    printf '%s\tcountable\tno_invocations\n' "$rid"
  else
    printf '%s\tcountable\tbound:%d\n' "$rid" "$nb"
  fi
}

# ---------------------------------------------------------------------------
# --list-gateable: print ONE `id<TAB>countable|advisory<TAB><reason>` line per SELECTED id (the same
# set --list-selected prints, ids carrying a newline/CR dropped), LC_ALL=C sorted, exit 0 — in the
# SAME early-exit tier as --list-selected: BEFORE the hash / --if-stamped comparison / execute loop /
# stamp write. It executes NOTHING (the canary case in test-rules-gate-verdict.sh proves it) and is
# the ONLY place the `binds` / invoked-file classification is computed — this script stays the one
# parser of a check (skills/rules/SKILL.md §9).
# ---------------------------------------------------------------------------
if [ "$MODE" = "list-gateable" ]; then
  _rc_lg_out="$(mktemp)"
  trap 'rm -f "$files_list" "$combined" "$selected" "$_rc_lg_out" 2>/dev/null' EXIT
  while IFS= read -r _rc_rec; do
    [ -n "$_rc_rec" ] || continue
    rid="$(printf '%s' "$_rc_rec" | jq -r '.id | select(test("[\n\r]") | not)' 2>/dev/null)"
    [ -n "$rid" ] || continue
    rcheck="$(printf '%s' "$_rc_rec" | jq -r '.check' 2>/dev/null)"
    _rc_lg_classify "$_rc_rec" "$rid" "$rcheck" >> "$_rc_lg_out"
  done < "$selected"
  LC_ALL=C sort "$_rc_lg_out"
  exit 0
fi

# ---------------------------------------------------------------------------
# LIVE_HASH — sha256 of the sorted `id\tcheck\n` lines of EXACTLY the set $selected holds above
# (`_rc_hash_line`: a bound rule's line additionally carries `\t<path>=<sha256|MISSING|INVALID>` per
# `binds` element; a binds-free rule's line is byte-identical to before `binds` existed). This is the
# ONE computation both the stamp WRITE (below, after the loop) and the --if-stamped COMPARISON
# (immediately below) read from — the same in-memory value, so the two can never independently drift
# on what "the set" means (executable-rule-candidates/01 AC; D-a's "extend that ONE line").
# ---------------------------------------------------------------------------
LIVE_HASH=""
_rc_hash_input="$(mktemp)"
trap 'rm -f "$files_list" "$combined" "$selected" "$_rc_hash_input" 2>/dev/null' EXIT
while IFS= read -r _rc_rec; do
  [ -n "$_rc_rec" ] || continue
  _rc_hash_line "$_rc_rec"
done < "$selected" | LC_ALL=C sort > "$_rc_hash_input"
LIVE_HASH="$(_rc_sha256_file "$_rc_hash_input")"
rm -f "$_rc_hash_input" 2>/dev/null

# ---------------------------------------------------------------------------
# --if-stamped RESOLUTION (deferred from the MODE block above — it needs $LIVE_HASH). Compares the
# live hash to the stamp recorded for THIS repository ($STAMP_KEY); equal ⇒ promote to "execute" (no
# prompt, same output shape as a real --confirm run, CAME_FROM_CONFIRM stays 0 so this replay does
# NOT itself refresh the stamp); unequal or absent ⇒ the whole run short-circuits here, before the
# per-rule loop is even entered — a single "all" line, not a per-rule one, because there is nothing
# stamped for THIS set to report per-rule against.
# ---------------------------------------------------------------------------
if [ "$MODE" = "if-stamped" ]; then
  _rc_stamped_hash="$(_rc_read_stamp_hash "$STAMP_KEY")"
  # THE HASH-COMPARISON LINE — the load-bearing gate a mutation control proves is not vacuous
  # (test-rules-check.sh case (h)/(M-hash)): delete/weaken this comparison and a stale or absent
  # stamp starts being treated as valid.
  if [ -n "$_rc_stamped_hash" ] && [ "$_rc_stamped_hash" = "$LIVE_HASH" ]; then
    MODE="execute"
  else
    echo "  [SKIP] all (unstamped)"
    echo "Checks passed: 0/0"
    exit 0
  fi
fi

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
      # DISPLAY the command, then run it byte-exact from the repo root. stdin is /dev/null: this loop
      # reads its records from "$selected" on stdin, so a check that reads stdin (`cat`, `read`)
      # would otherwise SWALLOW the remaining records and silently shrink the run.
      printf '  [RUN ] %s: %s\n' "$rid" "$rcheck"
      if bash -c "$rcheck" </dev/null >/dev/null 2>&1; then
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

# ---------------------------------------------------------------------------
# THE STAMP WRITE — ONLY on a GENUINE --confirm/RULES_CHECK_CONFIRM=1/TTY-y run (CAME_FROM_CONFIRM=1),
# NEVER on a --if-stamped-promoted replay (which does not itself constitute a fresh human
# confirmation — see the header's "THE STAMP WRITE" note). Regardless of pass/fail tally: the stamp
# records that a human confirmed THIS SET, not that every check in it currently passes. Best-effort
# — a failed write is warned about on stderr but never changes this script's exit code or stdout.
# ---------------------------------------------------------------------------
if [ "$MODE" = "execute" ] && [ "$CAME_FROM_CONFIRM" -eq 1 ] && [ -n "$LIVE_HASH" ]; then
  _rc_write_stamp "$STAMP_KEY" "$GITROOT" "$LIVE_HASH"
fi

[ "$failures" -eq 0 ] || exit 1
exit 0
