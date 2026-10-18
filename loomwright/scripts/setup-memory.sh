#!/usr/bin/env bash
# setup-memory.sh — fail-safe engine for the `/setup memory` module: put a repo's Twin memory
# stores under version control IN PLACE via gitignore negation, plus the repo allowlist that
# decides which ledger records belong to this repo.
#
# WHAT: the Twin's accumulated judgment (`.claude/agent-memory/`, `.supervisor/memory/`) plus the
# findings ledger (`.supervisor/postmortem/results.jsonl`) is gitignored in every repo the plugin
# runs in, so a fresh clone, a second machine, CI and every `git worktree` checkout start COLD, and
# a bad curation pass is irreversible (there is no `git checkout` to undo it). This helper
# un-ignores exactly those THREE stores WHERE THEY ALREADY SIT — no move, no symlink, no generated
# copy, no bridge. Nothing moves, so the harness keeps injecting agent memory from its own fixed
# path and there is nothing to prove about injection.
#
# THE THIRD STORE IS GATED, THE FIRST TWO ARE NOT. The findings ledger is structurally CROSS-REPO:
# a `/pr-postmortem` append lands in the CURRENT working `.supervisor/`, never in the analysed
# repo's, so a ledger accumulates records belonging to OTHER repos (this plugin's own ledger held 7
# records belonging to a private downstream repo before it was filtered). Un-ignoring an unfiltered
# ledger therefore PUBLISHES another repo's churn analysis. So `apply` FAILS CLOSED on it: the ledger negation is
# emitted only while every record's `.repo` sits inside the resolved allowlist. Otherwise the
# negation is WITHHELD, the offending slugs are NAMED, the readiness verdict is the dedicated
# `gated` class — and the exit code is still 0 (see FAIL-SAFE CONTRACT below: the gate fails closed
# in the WRITE dimension, never in the exit-status dimension).
#
# EMITTING AND WITHDRAWING ARE ASYMMETRIC (see _evaluate_ledger_gate / ledger_negation_in_block).
# Emitting a NEW negation needs an affirmative EXAMINED-AND-CLEAN verdict. WITHDRAWING one that is
# already in the block needs an affirmative EXAMINED-AND-CONTAMINATED verdict naming REAL slugs.
# Every "could not examine" outcome — jq absent OR BROKEN, ledger unreadable, every record
# unparseable — blocks EMISSION but PRESERVES an existing negation, because a withdrawal is an
# unrequested state change justified by a diagnosis that was never made.
#
# HONEST LIMIT — the gate is evaluated AT APPLY TIME ONLY. A repo whose ledger gains a foreign
# record AFTER a clean apply stays un-ignored until the next `apply` runs, and a routine
# `git add -A` can commit it in between. Run `setup-memory.sh filter-ledger` before committing;
# do not read the gate as complete coverage. A withdrawal also does NOT un-track an ALREADY
# COMMITTED ledger — `.gitignore` only governs UNTRACKED files.
#
# NON-GOAL (a decision, not an oversight): the gate keys on `.repo` ONLY. A record whose `.repo` is
# allowlisted but whose finding TEXT cites a foreign org is NOT caught here; content-level sweeping
# of the ledger is a separate item (test-committed-twin-scrub.sh's EXPLICIT_STORE_ROOTS is
# deliberately NOT widened to `.supervisor/postmortem`).
#
# THE NAIVE NEGATION SILENTLY FAILS. Git cannot re-include a file whose parent directory is
# excluded, so this looks right and does NOTHING:
#     .claude/
#     !.claude/agent-memory/
# The working form excludes the directory's CONTENTS, which leaves the directory traversable:
#     .claude/*
#     !.claude/agent-memory/
# Both forms are asserted in test-setup-memory.sh — the failure is proven, not commented.
#
# WHY the allowlist is a LIST (and never the live remote): the findings ledger
# (`.supervisor/postmortem/results.jsonl`) carries a `repo` field per record, and a repo RENAME
# leaves older records under the old slug. This plugin's own ledger once held 42 records under
# `<owner>/ai-agent-manager` (pre-rename) against 39 under the current slug — a filter keyed on
# the live remote would have silently dropped the larger, older half. (Historical: on 2026-10-13
# those records were rewritten to the current slug on the metadata branch, so the live ledger no
# longer shows the split. Re-derive any such count with jq, never grep — the ledger mixes compact
# and spaced JSON, so `grep -c '"repo":"…"'` under-counts the spaced records silently.) So the allowlist
# is stored as a JSON ARRAY, defaults to the CURRENT remote's owner/repo on a fresh install (never a
# hardcoded owner — the plugin ships to other users), and is extended by hand when a repo is renamed.
# That config is gitignored and does not travel; the TRACKED `.agent/meta-allowlist.txt` does, but it
# can only REQUEST: an entry is granted only on a `gh` repository-id match with a github.com origin,
# each gh call time-bounded, and never without gh (see META_ALLOWLIST_REL / meta_allowlist_grants,
# beside load_allowlist).
#
# WHY here: this is the deterministic, mechanizable engine. The INTERACTIVE half — the
# consent-bearing AskUserQuestion offer that must be answered BEFORE anything is written — lives
# in the COMMAND layer (commands/setup.md), not here. This script probes, reports, and performs
# the two contained writes it is told to perform.
#
# CONSENT IS LOAD-BEARING: applying this makes a user's agent memory VERSION-CONTROLLED, and it
# travels wherever the repo travels (a public repo publishes it). Agent memory can hold
# proprietary architecture, internal service names, or client detail. `check` prints the exact
# disclosure the command layer must show before offering to apply; `apply` reprints it.
#
# FAIL-SAFE CONTRACT (mirrors read-postmortem.sh / read-rules.sh): every branch —
# no git repo, absent .gitignore, unparseable .gitignore, missing jq — STILL `exit 0`. The helper
# NEVER blocks a session, NEVER gates, NEVER changes a heal_decision or a review decision.
# Machine-readable status lines (`apply: …` / `remove: …` / `Memory readiness: …`) carry the
# outcome instead of an exit code.
#
# THE LEDGER GATE DOES NOT BREAK THAT CONTRACT. "Fails closed" here means REFUSE-TO-WRITE plus a
# named-slug status line plus `exit 0` — never a non-zero exit. The gate withholds a write; it
# never blocks a caller. Implementing it as a non-zero exit would regress every non-blocking
# caller that treats this helper as advisory.
#
# WRITE-CONTAINMENT INVARIANT: the ONLY things this helper writes are, under the resolved repo
# root, (a) `.gitignore` plus one timestamped `.gitignore.backup.<ts>` sibling (suffixed with the
# pid, then a counter, when that name is already taken — a backup NEVER overwrites another, and if
# every candidate name is taken the write is REFUSED outright rather than clobbering one), and (b)
# `.supervisor/config.json` `.setup_memory.repo_allowlist` (backup-first jq merge that preserves
# every unrelated key). It writes NOTHING under `~/.claude/` — with ONE exception: the user-scope
# learning-store consent record, CONSENT_FILE_REL under $HOME (see CONSENT below),
# written ONLY by `consent grant` / `consent decline` (one atomic mktemp + rename beside it, the
# record's other repos' entries preserved) — and it NEVER runs `git add`, `git rm`, `git commit` or
# any other history-touching command. `check`, `allowlist`, `filter-ledger`, `valid-branch`, `mode`
# and `consent status` write nothing at all — not even a temp file: the bounded `gh` runner behind
# the allowlist's request file (gh_id_bounded) reads gh's answer through a pipe.
#
# TRACKED-WRITE RISK (stated here, deliberately NOT fixed here): once `.claude/agent-memory/` is
# tracked, every memory write becomes a working-tree modification — it shows in `git status`, can
# be swept into an unrelated commit by `git add -A`, and MEMORY.md becomes a conflict surface
# under parallel workers. Today that is near-theoretical (hand-written, rare). The mitigation
# belongs to the memory-writer item (agent writes land in a gitignored proposal queue; only
# /dreaming-promoted entries touch the tracked store) — building a proposal queue here is OUT OF
# SCOPE by design.
#
# Usage:
#   setup-memory.sh check                          # report: ignore status per path + allowlist (no writes)
#   setup-memory.sh apply                          # write the negation block + seed the allowlist
#   setup-memory.sh remove                         # undo the negation block (does NOT unpublish history)
#   setup-memory.sh apply --branch-mode <branch>   # BRANCH MODE: run history lives on <branch> (meta-sync.sh)
#   setup-memory.sh apply --branch-mode off        # back to the default block (`off` is RESERVED — never a branch name)
#   setup-memory.sh mode                           # print ONE line: off | on <branch> | unknown <reason>
#   setup-memory.sh valid-branch <name>            # exit 0 iff <name> is a valid metadata branch (no writes)
#   setup-memory.sh allowlist                      # print the allowlist, one per line (status: stderr)
#   setup-memory.sh filter-ledger --ledger F       # print ledger records whose .repo is in the allowlist
#   setup-memory.sh filter-ledger --ledger F --allow owner/repo --allow owner/old-name
#   setup-memory.sh consent status                 # print ONE line: granted | declined | none | unknown <reason>
#   setup-memory.sh consent grant|decline          # record this repo's learning-store consent (user scope)
#   setup-memory.sh --root /path/to/repo check     # point at a fixture repo
#   setup-memory.sh -h | --help
#
# BRANCH MODE (opt-in, default OFF — skills/automate-loop/SKILL.md §"Branch mode"). `apply
# --branch-mode <branch>` writes a block that OMITS every run-history re-include (requirements/,
# jobs/done|failed/, automate/*.md and the three ledger lines) — run history then lives on the
# metadata branch `meta-sync.sh` syncs — and records the switch as ONE comment line inside the
# sentinels, `# loomwright-meta-branch: <branch>` (tracked, so a fresh clone can read it). A plain
# `apply` PRESERVES the mode line already in the block (inside proposed_applied_content, so `check`,
# `apply` and `remove` agree); `--branch-mode off` restores the default block; `remove` deletes the
# whole block, mode included. `mode` is the ONE reader every caller uses — nothing else parses the
# block. A branch name is accepted ONLY when ALL hold (valid_branch_name): it does not start with
# `-` and is not `HEAD` / `@` / the RESERVED word `off` (the switch-off spelling, so a metadata
# branch can never be named `off` and a hand-written `off` mode line reads `unknown`, never
# `on off`); `git check-ref-format --branch <name>` succeeds AND prints <name>
# back unchanged (so `@{-N}` shorthand, which it expands, is refused); and meta-sync.sh's own check,
# `git check-ref-format refs/heads/<name>`, succeeds. The accepted set is the INTERSECTION, so a
# recorded name is always one meta-sync.sh accepts and never one git would read as an option or a
# reserved ref. A value that is EMPTY or starts with `-` (e.g. `--branch-mode --root X`) is a usage
# error for every value flag (`--branch-mode`, `--root`, `--ledger`, `--allow`): nothing is written.
# The invariant above holds for the new flag too: switching mode only rewrites
# `.gitignore`; it NEVER runs `git add` / `git rm` / `git commit`, so it never untracks the run
# history already committed (that is a separate, deliberate operator step).
#
# VALID-BRANCH: `valid-branch <name>` asks that SAME valid_branch_name predicate — the one
# `apply --branch-mode` uses, never a copy — so a caller can vet a name BEFORE anything is written
# (`apply` itself exits 0 on a refusal, so its exit code cannot answer the question). The argument
# right after `valid-branch` is always the name, even when it starts with `-` (so `-x` is judged,
# and refused, rather than parsed as a flag). It runs before the repo root is resolved, reads no
# file and writes nothing; on acceptance it prints nothing.
#
# CONSENT (learning stores on the metadata branch — meta-sync.sh header: CONSENT). meta-sync.sh
# publishes the learning stores (twin contracts + .provenance.jsonl, agent-memory proposals, the
# eval JSONL files) only when this repo's record reads `granted`. The record is a fact about the
# USER, not the repo (a repo-relative file could at most REQUEST, never grant — the telemetry
# invariant): ONE JSON file, $HOME/<CONSENT_FILE_REL>,
#   {"schema_version": 1, "repos": {"<key>": {"learning_stores": "granted"|"declined",
#                                             "recorded_at": "<UTC ISO-8601>"}}}
# keyed by origin's `owner/repo` (remote_slug — it NEVER guesses an owner), falling back to the
# literal origin URL when no slug parses (a filesystem-path origin). No origin at all => no key:
# `status` prints `none`, `grant` / `decline` write nothing. `consent status` is the ONE reader
# (meta-sync.sh calls it; nothing else parses the file) and prints exactly one line: `granted` |
# `declined` | `none` (no file, or no entry for this key) | `unknown <reason>` (HOME unset, jq
# missing, a file that is not valid JSON or holds another value) — and every answer but `granted`
# publishes nothing. `consent grant` / `consent decline` are the ONLY writers; they refuse (nothing
# written, exit 0, a reason line) without jq, without HOME, without a key, or over an existing file
# that is not a JSON object (never clobbered). Asking is the command layer's job (`/setup memory`,
# commands/setup.md); this helper never asks.
#
# Exit: 0 in every normal path — EXCEPT `valid-branch`, a predicate whose exit code IS its answer:
# 0 accepted, 1 refused (one reason line on stderr; also for a missing name or an extra flag).

# Modules (sourced in this order from setup-memory.d/):
# - probes.sh: the probe paths (INTENDED_PATHS, LEDGER_INTENDED_PATH, UNINTENDED_PATHS) and the
#     primitive probes — agent_memory_store_dir, ignore_status, tracked_count, gitignore_gate,
#     managed_block_present, strip_managed_block, comment_bare_excludes.
# - detect.sh: the managed block and the branch-mode reader — uncomment_bare_excludes,
#     managed_block, managed_block_branch_mode, read_mode, normalize_mode,
#     resolve_effective_branch.
# - gitignore.sh: the .gitignore writer — proposed_applied_content, proposed_removed_content,
#     unique_backup_path, write_gitignore.
# - allowlist.sh: the allowlist behind `allowlist` / `filter-ledger` — origin parsing
#     (parse_remote_url, resolve_origin, remote_slug), the tracked request file
#     (META_ALLOWLIST_REL, allowlist_gh_limit, allowlist_max_entries, gh_id_bounded,
#     meta_allowlist_grants), load_allowlist, resolve_allowlist, seed_allowlist,
#     filter_ledger_by_allowlist.
# - ledger-gate.sh: the findings-ledger gate — _evaluate_ledger_gate,
#     ledger_gate_blocks_foreign_records, ledger_gate_permits_negation,
#     ledger_gate_warrants_withdrawal, negation_line_in_block, existing_ledger_negation_present,
#     ledger_negation_in_block.
# - report.sh: the consent disclosure and the readiness report — print_consent_disclosure,
#     print_consent_disclosure_branch_mode, render_report, print_path_rules.
# - commands.sh: check, apply, remove, allowlist, filter-ledger, mode, consent —
#     warn_if_not_configured, do_check, do_apply, do_remove, do_allowlist, do_filter_ledger, the
#     top-level resolve_effective_branch call, do_mode, CONSENT_FILE_REL, consent_key, do_consent.
# This file keeps the header above, set -uo pipefail, the managed-block constants,
# valid_branch_name, the argument parsing, the valid-branch predicate, root resolution, the module
# loader and its source lines, apply_readiness_event (between report.sh and commands.sh, at its
# single-file position: it finds emit-script-event.sh through ${BASH_SOURCE[0]}, so it must stay in
# this file) and the final `case "$SUBCMD" in` dispatch. This map is its own comment block, after
# the header: `usage` prints only the first comment block, so --help is the single file's.

set -uo pipefail

# ---- managed-block constants (timestamp-FREE by design: apply/remove compare the proposed
#      content byte-for-byte against the current file to decide "already configured") ---------
MB_BEGIN='# >>> loomwright /setup memory BEGIN — committable Twin stores (managed block) >>>'
MB_END='# <<< loomwright /setup memory END <<<'
DISABLED_MARK='# [loomwright/setup-memory] disabled: a bare directory exclude defeats the negation below'
# The branch-mode switch: ONE comment line inside the sentinels (read only by read_mode()).
MODE_PREFIX='# loomwright-meta-branch: '

# valid_branch_name <name> — exit 0 iff <name> may be recorded as (or read back from) the mode
# line. The accepted set is the INTERSECTION of `git check-ref-format --branch` (output equal to
# the input — `@{-N}` expands, so it is refused) and meta-sync.sh's own `git check-ref-format
# refs/heads/<name>`, minus anything option-shaped (`-…`) or reserved (`HEAD`, `@` — belt and
# braces for a git whose --branch check predates refusing them — and `off`, this script's own
# switch-off spelling). Used by the --branch-mode check AND read_mode, so a hand-written `-x` or
# `off` mode line reads `unknown`, never `on -x` / `on off`. The --branch probe
# runs as `git -C /` so the verdict never depends on the caller's cwd: a bare `--branch` consults
# the cwd's repo (expanding `@{-N}` there) and FAILS outright when the cwd was deleted, which would
# turn a valid recorded mode into `unknown`. Outside any repo `@{-N}` is refused, as intended.
valid_branch_name() {
  local v="${1:-}" out
  [ -n "$v" ] || return 1
  case "$v" in -*|HEAD|@|off) return 1 ;; esac
  out="$(git -C / check-ref-format --branch "$v" 2>/dev/null)" || return 1
  [ "$out" = "$v" ] || return 1
  git check-ref-format "refs/heads/$v" >/dev/null 2>&1 || return 1
  return 0
}

# ---- arg parsing ------------------------------------------------------------
SUBCMD=""
ROOT_OVERRIDE=""
LEDGER=""
ALLOW_FLAGS=""     # newline-separated (bash-3.2-safe: no arrays needed downstream)
BRANCH_MODE_SET=0  # 1 when --branch-mode was given (its value is REQUIRED: <branch> | off)
BRANCH_MODE_VAL=""
VB_NAME=""         # valid-branch: the name to judge (the argument right after the subcommand)
CONSENT_ACTION=""  # consent: grant | decline | status (the argument right after the subcommand)

# reject_option_value <flag> <noun> <value> — an EMPTY or option-shaped (`-…`) value is the NEXT
# flag (or nothing), never the value: `--root --branch-mode apply` must not resolve a root named
# `--branch-mode`. Same stderr usage line as the missing-value case, exit 0, nothing written.
reject_option_value() {
  case "$3" in
    '') echo "setup-memory: $1 requires $2 — got an empty value. Nothing was written." >&2; exit 0 ;;
    -*) echo "setup-memory: $1 requires $2 — got option-shaped '$3'. Nothing was written." >&2; exit 0 ;;
  esac
}

usage() {
  # Print the leading header comment block (line 2 through the last contiguous `#` line),
  # robust to header edits — no hard-coded line range to drift when the header grows/shrinks.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    check|apply|remove|allowlist|filter-ledger|mode)
      [ -z "$SUBCMD" ] && SUBCMD="$1"; shift ;;
    consent)
      # The NEXT argument is the action (grant | decline | status), judged by do_consent.
      if [ -z "$SUBCMD" ]; then
        SUBCMD="$1"
        [ $# -ge 2 ] && { CONSENT_ACTION="$2"; shift; }
      fi
      shift ;;
    valid-branch)
      # The NEXT argument is the name, verbatim — even an option-shaped one, which the predicate
      # then refuses (`valid-branch -x` judges `-x`; it never parses it as a flag).
      if [ -z "$SUBCMD" ]; then
        SUBCMD="$1"
        [ $# -ge 2 ] && { VB_NAME="$2"; shift; }
      fi
      shift ;;
    --root)
      # Require a following value. Shift the flag first, then the value ONLY if present — a bare
      # trailing `--root` must NOT `shift 2` (that underflows when $#<2 and would re-process the
      # same arg → spin). A valueless --root is a usage error, never a silent fall-back.
      if [ $# -lt 2 ]; then
        echo "setup-memory: --root requires a path argument" >&2
        exit 0
      fi
      reject_option_value --root "a path argument" "$2"
      ROOT_OVERRIDE="$2"; shift 2 ;;
    --ledger)
      if [ $# -lt 2 ]; then
        echo "setup-memory: --ledger requires a path argument" >&2
        exit 0
      fi
      reject_option_value --ledger "a path argument" "$2"
      LEDGER="$2"; shift 2 ;;
    --allow)
      if [ $# -lt 2 ]; then
        echo "setup-memory: --allow requires an owner/repo argument" >&2
        exit 0
      fi
      reject_option_value --allow "an owner/repo argument" "$2"
      ALLOW_FLAGS="${ALLOW_FLAGS}${2}
"
      shift 2 ;;
    --branch-mode)
      # The value is REQUIRED — a bare `--branch-mode` is a usage error and nothing is written
      # (silently defaulting a branch name would switch a repo's run history somewhere unasked).
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        echo "setup-memory: --branch-mode requires a value: <branch> (e.g. loomwright-meta) or off (reserved — never a branch name). Nothing was written."
        exit 0
      fi
      # An option-shaped value is the NEXT flag, not a branch (`--branch-mode --root X` must never
      # record `--root` as the branch — nor resolve the root from the wrong checkout). Usage error.
      case "$2" in
        -*) echo "setup-memory: --branch-mode requires a value: <branch> (e.g. loomwright-meta) or off (reserved — never a branch name) — got option-shaped '$2'. Nothing was written."
            exit 0 ;;
      esac
      BRANCH_MODE_SET=1; BRANCH_MODE_VAL="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "setup-memory: unknown arg '$1' (try --help)" >&2; shift ;;
  esac
done

[ -z "$SUBCMD" ] && usage

# ---- valid-branch: the predicate alone (before root resolution — it reads and writes nothing) ----
# Exit 0 iff valid_branch_name accepts the name; 1 otherwise, with ONE reason line on stderr. A flag
# that could only be silently ignored here (--branch-mode, --ledger, --allow) is refused too.
if [ "$SUBCMD" = "valid-branch" ]; then
  if [ "$BRANCH_MODE_SET" = 1 ] || [ -n "$LEDGER" ] || [ -n "$ALLOW_FLAGS" ]; then
    echo "setup-memory: valid-branch takes only a name (got --branch-mode / --ledger / --allow); nothing was judged" >&2
    exit 1
  fi
  if valid_branch_name "$VB_NAME"; then exit 0; fi
  echo "setup-memory: valid-branch: '$VB_NAME' is not a valid metadata branch name (must pass git check-ref-format --branch unchanged AND refs/heads/<name>, and not be empty, option-shaped, HEAD/@ or the reserved word off)" >&2
  exit 1
fi

# ---- repo root resolution ---------------------------------------------------
# When --root is given, use it verbatim and do NOT require it to be a git repo (testability).
if [ -n "$ROOT_OVERRIDE" ]; then
  repo="$ROOT_OVERRIDE"
else
  repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
GI="$repo/.gitignore"
CFG="$repo/.supervisor/config.json"

if [ "$BRANCH_MODE_SET" = 1 ]; then
  if [ "$SUBCMD" != "apply" ]; then
    echo "setup-memory: --branch-mode applies only to 'apply' (got '$SUBCMD'). Nothing was written."
    exit 0
  fi
  if [ "$BRANCH_MODE_VAL" != "off" ] && ! valid_branch_name "$BRANCH_MODE_VAL"; then
    echo "apply: ABORTED — invalid --branch-mode branch name '$BRANCH_MODE_VAL' (must pass git check-ref-format --branch unchanged AND refs/heads/<name>, and not be option-shaped, HEAD/@ or the reserved word off). Nothing was written."
    exit 0
  fi
fi

# >>> module loader (_sm_source / _sm_bundle) — entry-only, belongs to no module
# The code from here on lives in setup-memory.d/<name>.sh (automate-speed/20, a move-only split;
# the Modules map after the header names what each holds). Each is sourced by ONE
# `_sm_source <name>` line between `# >>> setup-memory.d/<name>.sh` and
# `# <<< setup-memory.d/<name>.sh` markers, at the position its text held when this was a single
# file, so `_sm_bundle` (this script with each such line replaced by the module's text) reproduces
# that file's line order, and top-level statements between functions (the probe-path globals, the
# resolve_effective_branch call, CONSENT_FILE_REL) still run in that order.
# Listed by name, never globbed: a stray file in setup-memory.d/ is never sourced.
# A missing, unreadable or empty module fails CLOSED (exit 1, the file named on stderr), never a
# silent no-op — the one non-zero exit outside `valid-branch`, and only on a broken install
# (precedent: automate-trail.sh's _trail_source). Empty is refused too, as _sm_bundle refuses it:
# an empty module defines nothing, so the run would die later on `command not found` with exit 0.
# The modules load after the argument parsing, so `--help`, a usage error and `valid-branch`
# answer exactly as the single file did. The dir comes from this file's ${BASH_SOURCE[0]}.
_sm_source() {
  local _sm_f
  _sm_f="$(dirname "${BASH_SOURCE[0]}")/setup-memory.d/$1.sh"
  { [ -f "$_sm_f" ] && [ -r "$_sm_f" ] && [ -s "$_sm_f" ]; } \
    || { echo "setup-memory: missing module file: setup-memory.d/$1.sh" >&2; exit 1; }
  . "$_sm_f"
}
# _sm_bundle [<entry>] — print <entry> (default: this script) with every `_sm_source <name>` line
# replaced by setup-memory.d/<name>.sh read from beside it. Self-contained (a test evals this one
# function): a missing, unreadable or empty module prints one stderr line naming it and exits 1.
_sm_bundle() {
  local _sm_e="${1:-${BASH_SOURCE[0]}}"
  SM_MOD="$(dirname "$_sm_e")/setup-memory.d" awk '
    /^_sm_source [a-z][a-z-]*$/ {
      f = ENVIRON["SM_MOD"] "/" $2 ".sh"; n = 0
      while ((r = (getline l < f)) > 0) { print l; n++ }
      close(f)
      if (r < 0 || n == 0) { print "setup-memory: missing module file: setup-memory.d/" $2 ".sh" > "/dev/stderr"; exit 1 }
      next
    }
    { print }
  ' "$_sm_e"
}
# <<< module loader
# >>> setup-memory.d/probes.sh
_sm_source probes
# <<< setup-memory.d/probes.sh

# >>> setup-memory.d/detect.sh
_sm_source detect
# <<< setup-memory.d/detect.sh

# >>> setup-memory.d/gitignore.sh
_sm_source gitignore
# <<< setup-memory.d/gitignore.sh

# >>> setup-memory.d/allowlist.sh
_sm_source allowlist
# <<< setup-memory.d/allowlist.sh

# >>> setup-memory.d/ledger-gate.sh
_sm_source ledger-gate
# <<< setup-memory.d/ledger-gate.sh

# >>> setup-memory.d/report.sh
_sm_source report
# <<< setup-memory.d/report.sh

# apply_readiness_event — apply's verdict as an opt-in script event (docs/TELEMETRY.md §"Script
# events"): `configured` is a pass (it closes this step's open threads), partial / unknown / not
# configured a warn with the leaked / blocked path COUNTS. `gated` is not reported: it reflects the
# repo's own ledger records, not plugin behaviour. Plugin facts only; fire-and-forget (exit 0, no
# output). LOOMWRIGHT_SCRIPT_EVENT_CALLER names the plugin step that ran apply (migrate-branch-mode
# sets it), so a warning only one caller sees is visible as such.
apply_readiness_event() {
  local outcome code leaked blocked
  case "$REPORT_VERDICT" in
    configured) outcome=pass; code=ok ;;
    partial*) outcome=warn; code=readiness_partial ;;
    unknown*) outcome=warn; code=readiness_unknown ;;
    "not configured"*) outcome=warn; code=readiness_not_configured ;;
    *) return 0 ;;
  esac
  leaked="$(printf '%s' "$REPORT_LEAKED_UNINTENDED" | grep -c .)"; blocked="$(printf '%s' "$REPORT_BLOCKED_INTENDED" | grep -c .)"
  bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/emit-script-event.sh" --root "$repo" setup-memory apply "$outcome" "$code" \
    --count "leaked_unintended=$leaked" --count "blocked_intended=$blocked" --count "branch_mode=$([ -n "$EFFECTIVE_BRANCH" ] && echo 1 || echo 0)" \
    ${LOOMWRIGHT_SCRIPT_EVENT_CALLER:+--caller "$LOOMWRIGHT_SCRIPT_EVENT_CALLER"} >/dev/null 2>&1 || true
}

# >>> setup-memory.d/commands.sh
_sm_source commands
# <<< setup-memory.d/commands.sh

case "$SUBCMD" in
  consent)       do_consent ;;
  mode)          do_mode ;;
  check)         do_check ;;
  apply)         do_apply ;;
  remove)        do_remove ;;
  allowlist)     do_allowlist ;;
  filter-ledger) do_filter_ledger ;;
  *)             usage ;;
esac
