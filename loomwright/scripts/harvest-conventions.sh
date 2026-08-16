#!/usr/bin/env bash
# harvest-conventions.sh — READ-ONLY distiller: turns accumulated `convention_mismatch` findings and
# the agent-memory corpus into a bounded, reviewable, path-scoped `.agent/rules/` proposal batch.
#
# WHAT IT IS FOR. The plugin has recorded convention violations for months and never converted them
# into conventions. This script is the missing distillation step: it reads what has actually been
# measured, triages every candidate into exactly one of three destinations, and prints a bounded
# batch of proposed rules together with the numbers that let a reader JUDGE the batch rather than
# take its word for it. It is the engine behind `/dreaming`'s rule-proposal phase.
#
# THIS SCRIPT HAS NO WRITE MODE AT ALL. Not "dry-run by default" — dry-run ONLY. It never creates a
# branch, never commits, never opens a PR, and never writes to `.agent/rules/`. Delivery (branch +
# `gh pr create`, behind an explicit human pre-push confirmation) belongs to `/dreaming`, which calls
# this script for its batch. A read-only engine is strictly stronger than an opt-in write flag: there
# is no flag here that could be passed by accident.
#
# THE DRY-RUN SUBSTRATE, and why the `< /dev/null` is load-bearing (NOT decorative).
# Proposals are authored THROUGH the sole writer `add-rule.sh` — this script never hand-builds a rule
# object, so the frozen 7-member schema, the category containment, the `--applies-to` validation and
# the write-time validator all apply to a proposal — THE SAME CHECKS RUN, against the store as it
# stands at the time of the call. That is deliberately not "exactly as they would to a real write":
# a dry run evaluates every proposal against the store BEFORE any rule in this batch has landed,
# whereas delivery evaluates rule N against a store already holding rules 1..N-1, so
# `validate_duplicate` / `validate_contradiction` can refuse at delivery something that planned
# cleanly here. A clean plan is evidence about the store today, not a guarantee about the batch.
# `add-rule.sh`
# has THREE branches, and only the third is a dry run:
#     --confirm                         → writes.
#     no --confirm, but `[ -t 0 ] && [ -t 1 ]` → PROMPTS `Confirm write? [y/N]`, and WRITES on `y`.
#     no --confirm, no TTY on stdin     → prints `PLANNED WRITE (not written …)`, exits 0.
# `/dreaming` runs interactively on a live TTY, i.e. exactly the prompting case, so omitting
# `--confirm` is NOT by itself a dry run. Every writer invocation composed here therefore REDIRECTS
# STDIN FROM /dev/null, which makes `[ -t 0 ]` false and the PLANNED-WRITE branch the only reachable
# one — and also stops N proposals from firing N prompts at the user's terminal. See `compose_add_rule`
# and `plan_rule` below; the composed string that is printed contains the redirection verbatim so a
# reader can check it, and the test suite asserts both the printed shape AND that a run with a LIVE
# stdin leaves the store byte-unchanged.
#
# RULES ARE DATA, NEVER EXECUTED. `check` is left `null` on every proposal: this script does not pass
# `--check` at all and NEVER synthesises a shell command into a rule. The `rules-check.sh --no-cmd`
# trust boundary is unchanged and no new gate is added — proposals are advisory and subordinate to
# CLAUDE.md.
#
# THE LEDGER IS READ WHOLE — NO REPO FILTER. The `.repo` values are reported as an observed
# distribution and nothing is ever dropped. When (and only when) the caller supplies `--expect-repo`
# — an expectation that arrives as a committed argument, not read from machine-local state — any
# other `.repo` is NAMED as an advisory line. This script deliberately does NOT resolve a repo
# allowlist itself: the one resolver available (`setup-memory.sh allowlist`) reads
# `.supervisor/config.json`, which is gitignored, so a check built on it passes locally with the
# developer's 2-entry list and behaves differently in CI with the shipped default. Naming, never
# filtering, and only against an expectation the caller states.
#
# HOW A CANDIDATE BECOMES A RULE (all of it computed, none of it asserted):
#   1. Ledger findings are assigned to THEMES by the committed lexicon in `theme_spec` below (first
#      match in a fixed precedence order, so a finding lands in exactly ONE theme).
#   2. A theme with at least $MIN_SUPPORT findings is a `rules` candidate; a thinner one is context.
#   3. A corpus entry is bucketed to `rules` only when it is NORMATIVE and at least $PROJECT_WIDE_PCT%
#      of its distinctive description terms already appear in this repo's committed convention
#      surfaces (CLAUDE.md, AGENT_GUIDELINES.md) — i.e. the project already asserts it repo-wide —
#      AND it corroborates a supported theme. A CORPUS ENTRY'S ROLE IS TO CORROBORATE A THEME, NEVER
#      TO EMIT A RULE OF ITS OWN. That corroboration requirement is not decoration: a corpus entry
#      carries no measured violation, and a rule justified by prose alone is exactly what this
#      harvester exists to avoid. So a bucketed entry contributes its independent agreement to a
#      theme whose rule the ledger already earned — the theme supplies the scope, the finding ids and
#      the support count — and is then counted as a deferral, never emitted as a second rule over the
#      same evidence. There is no branch by which a corpus entry alone becomes a rule.
#   4. `applies_to` is derived from the `changed_paths` of the motivating findings (`derive_applies_to`).
#
# WHAT THE THEME LEXICON IS, stated so it is not mistaken for machine-derived prose: the theme
# patterns, the canonical statement wording and the category of each theme are a COMMITTED, reviewable
# table in this file. The engine never invents rule prose at run time. What the engine computes is
# WHICH themes have enough measured support to become rules, WHAT their path scope is, WHICH finding
# ids motivated each one, and the three numbers below. The table is meant to be edited by a human.
#
# SCOPE-DERIVATION LIMIT, stated because it bounds what the numbers can mean: the ledger records
# `changed_paths` per PR RECORD, not per finding. A theme's paths are therefore the union of the file
# lists of the PRs its findings came from — an UPPER BOUND on the true scope, not the true scope. The
# prefix-frequency derivation concentrates on the dominant prefixes for that reason, and `scope
# fidelity` re-verifies the derived globs against those same paths with the SAME bash `case` matcher
# `read-rules.sh` uses at read time. That re-verification is a mechanical check of the derivation (it
# catches a glob that does not match what it was derived from), NOT an independent oracle.
#
# FINDING IDS. The ledger carries no finding ids, so this script derives a deterministic, re-derivable
# one: `<repo-name>#<pr-number>:L<1-based ledger line>.<1-based index into that record's .categories
# array>`. A reader resolves `loomwright#118:L71.3` by hand with:
#     sed -n '71p' .supervisor/postmortem/results.jsonl | jq '.categories[2]'
# THE LINE NUMBER IS NOT REDUNDANT with the PR number, which is why the id is not the prettier
# `<repo>#<pr>.<idx>`: MEASURED on today's ledger, 13 PRs carry TWO records each (a re-gather appends
# rather than replaces), so a PR-keyed id names two different findings and the traceability AC4 asks
# for would be ambiguous exactly where a reader went looking.
#
# Usage:
#   harvest-conventions.sh [--session-id <id>] [--cap <N>] [--min-support <N>]
#                          [--ledger <path>] [--corpus-dir <path>] [--proposals-dir <path>]
#                          [--surface <path> ...] [--root <dir>] [--add-rule <path>]
#                          [--expect-repo <owner/repo> ...] [--no-writer] [-h|--help]
#
# Exit contract — explicit, and deliberately NOT uniformly fail-safe:
#   0  the harvest ran and the report was printed. This INCLUDES every legitimately empty case: an
#      absent `.supervisor/agent-memory-proposals/` (it does not exist on disk today and its absence
#      is normal, never an error), an empty corpus, a ledger with zero `convention_mismatch`
#      findings, and a batch of zero proposed rules. Each is reported as such and the numbers are
#      printed with the real denominators.
#   2  usage error — an unknown argument, a non-numeric `--cap`/`--min-support`, or a `--session-id`
#      that cites nothing (empty, an unsubstituted `<…>` template, or the bare word `session_id`;
#      `add-rule.sh`'s write-time provenance check refuses all three, so accepting one here would
#      only defer the failure to N writer invocations).
#   3  could-not-examine — `jq` is absent, or the ledger path is missing/unreadable/unparseable. This
#      does NOT exit 0: this is a measurement tool whose whole output is numbers, and a run that
#      prints coverage over a ledger it could not read would be a confident lie. It is not a gate, so
#      exiting non-zero blocks nothing — `/dreaming` treats a non-zero harvest as "no batch to offer".
#   A missing WRITER (`add-rule.sh`) is NOT fatal: the batch and every metric are still printed, each
#   proposal's composed invocation is still shown, and the writer result reads `writer unavailable`.

set -uo pipefail

PROG="harvest-conventions.sh"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-2}"; }

# ---------------------------------------------------------------------------
# Tunables. Every one of these is printed in the report, so a reader never has to open this file to
# know which thresholds produced the batch they are looking at.
# ---------------------------------------------------------------------------
CAP=5                    # hard bound on the emitted batch (AC4: an explicit, stated cap)
MIN_SUPPORT=8            # findings a theme needs before it may become a rule
PROJECT_WIDE_PCT=85      # % of a corpus entry's distinctive terms that must already appear in the
                         # committed convention surfaces before it counts as "already asserted
                         # repo-wide". The measured separation that justifies this threshold is
                         # NOT restated here — a measurement copied into a comment goes stale
                         # silently against prose that changes every release (these figures are a
                         # % of term overlap with CLAUDE.md + AGENT_GUIDELINES.md, so an unrelated
                         # banner edit moves them). It is recorded, with its run, in
                         # `docs/HARVEST_DRYRUN_SAMPLE.md`: the corroborating example clears the
                         # threshold comfortably while the two that must STAY in agent-memory land
                         # far below it, and that gap — not any single number — is the argument.
DISTILLATION_FLOOR=200   # hundredths: 2.00 findings-in per rule-out. Below this the run reports a
                         # DISTILLATION FAILURE in its own output (AC5) instead of shipping the batch.
APPLIES_TO_COVER=95      # % of a theme's motivating FINDINGS the derived globs must route before the
                         # greedy cover stops. Set high on purpose: at 60% every rule in this repo
                         # derived the single glob `CLAUDE.md` and stopped, because CLAUDE.md is
                         # touched by almost every PR and so covers the threshold on its own — a
                         # scope that describes the repo's busiest file rather than the convention.
MAX_GLOBS=4              # cap on the derived applies_to array

SESSION_ID=""
LEDGER=""
CORPUS_DIR=""
PROPOSALS_DIR=""
ROOT=""
ADD_RULE=""
NO_WRITER=0
SURFACES=()
EXPECT_REPOS=()
RAW_ARGV=("$0" "$@")

usage() {
  # Print the leading header comment block (line 2 through the last contiguous `#` line), robust to
  # header edits — no hard-coded line range to drift. Same scan as seed-rules.sh's usage(), written
  # in the same batch: a fixed `2,140p` here already over-ran the header and printed ~38 lines of
  # live source with `# ` stripped.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
  exit 0
}

is_num() { case "${1:-}" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# pct <numerator> <denominator> — a REPORTED share, ROUNDED HALF-UP, never truncated. Prints 0 for a
# zero/absent denominator so no caller has to guard division separately.
#
# WHY ROUNDING AND NOT `a * 100 / b`: bash integer division TRUNCATES, and every other surface that
# quotes these same ratios computes them with Python `round()` (`measure-heal-signal.py`). Measured
# on this repo's headline ratio, that is a visible disagreement between two COMMITTED artifacts:
# 107*100/225 = 47.55… → truncated 47, rounded 48, so `docs/HARVEST_DRYRUN_SAMPLE.md` printed
# `107/225 (47%)` for the identical statistic `docs/RULES_BASELINE.md`, `CHANGELOG.md` and the
# CLAUDE.md banner all state as 48%. A reader cross-referencing the two artifacts trips over the
# number this change leads with. `(a*200 + b) / (2*b)` is half-up with integer arithmetic only.
#
# THE THRESHOLD COMPARISONS ARE DELIBERATELY LEFT TRUNCATING, and this is a judgement, not an
# oversight — they are not reported shares, they are decisions, and rounding each one WEAKENS the
# decision by up to half a point:
#   - the `applies-to-cover` stop condition in derive_applies_to: rounding lets the greedy cover stop
#     early (94.5% would satisfy a 95% floor), narrowing a derived scope for a display reason.
#   - `dedupe_rate`'s hundredths against $DISTILLATION_FLOOR: rounding turns a true 1.995
#     findings-per-rule into a passing 2.00, i.e. it would let a batch this script is supposed to
#     self-report as a DISTILLATION FAILURE ship instead.
#   - `pw` against $PROJECT_WIDE_PCT: pw is printed, but it is printed BECAUSE it is the decision
#     variable, and rounding it would admit an 84.5% corpus entry to the `rules` bucket — a change to
#     which candidates are proposed, made for a formatting reason. Displaying the exact value the
#     decision used is the correct reporting, and no other artifact quotes a pw.
# No other committed surface quotes any of those three, so leaving them truncated moves no
# inconsistency anywhere; rounding them would trade a cosmetic fix for a behavioural one.
#
# HONEST LIMIT — half-up is NOT byte-identical to Python's `round()` AT EXACTLY .5. Python rounds
# half-to-EVEN (banker's), so 5/8 = 62.5% prints 62 there and 63 here; the two agree everywhere else,
# including on every ratio actually cross-quoted today (107/225 → 48 both ways, 60/95 → 63 both ways,
# 54/74 → 73 both ways). Half-up is chosen anyway because it is the rule a reader hand-checking
# "47.55 rounds to 48" will apply, and because matching banker's rounding would need an even/odd
# branch that no cross-artifact disagreement currently justifies. If a .5 ratio ever IS quoted on
# both sides, this is the line that explains the one-point gap.
pct() {
  local n="${1:-0}" d="${2:-0}"
  is_num "$n" || n=0
  is_num "$d" || d=0
  if [ "$d" -le 0 ]; then printf '0'; return 0; fi
  printf '%s' "$(( (n * 200 + d) / (2 * d) ))"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --session-id)    [ "$#" -ge 2 ] || die "--session-id requires a value"; SESSION_ID="$2"; shift 2 ;;
    --cap)           [ "$#" -ge 2 ] || die "--cap requires a value"; CAP="$2"; shift 2 ;;
    --min-support)   [ "$#" -ge 2 ] || die "--min-support requires a value"; MIN_SUPPORT="$2"; shift 2 ;;
    --ledger)        [ "$#" -ge 2 ] || die "--ledger requires a value"; LEDGER="$2"; shift 2 ;;
    --corpus-dir)    [ "$#" -ge 2 ] || die "--corpus-dir requires a value"; CORPUS_DIR="$2"; shift 2 ;;
    --proposals-dir) [ "$#" -ge 2 ] || die "--proposals-dir requires a value"; PROPOSALS_DIR="$2"; shift 2 ;;
    --surface)       [ "$#" -ge 2 ] || die "--surface requires a value"; SURFACES+=("$2"); shift 2 ;;
    --expect-repo)   [ "$#" -ge 2 ] || die "--expect-repo requires a value"; EXPECT_REPOS+=("$2"); shift 2 ;;
    --root)          [ "$#" -ge 2 ] || die "--root requires a value"; ROOT="$2"; shift 2 ;;
    --add-rule)      [ "$#" -ge 2 ] || die "--add-rule requires a value"; ADD_RULE="$2"; shift 2 ;;
    --no-writer)     NO_WRITER=1; shift ;;
    -h|--help)       usage ;;
    *) die "unknown argument: $1 (see --help)" 2 ;;
  esac
done

is_num "$CAP"          || die "--cap must be a non-negative integer (got: $CAP)" 2
is_num "$MIN_SUPPORT"  || die "--min-support must be a non-negative integer (got: $MIN_SUPPORT)" 2

command -v jq >/dev/null 2>&1 || die "jq is required but not available — refusing to print numbers over a ledger this run could not read" 3

# ---------------------------------------------------------------------------
# Resolve inputs.
# ---------------------------------------------------------------------------
[ -n "$ROOT" ] || ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
[ -d "$ROOT" ] || die "--root is not a directory: $ROOT" 2
[ -n "$LEDGER" ]        || LEDGER="$ROOT/.supervisor/postmortem/results.jsonl"
[ -n "$CORPUS_DIR" ]    || CORPUS_DIR="$ROOT/.claude/agent-memory"
[ -n "$PROPOSALS_DIR" ] || PROPOSALS_DIR="$ROOT/.supervisor/agent-memory-proposals"
[ -n "$ADD_RULE" ]      || ADD_RULE="$HERE/add-rule.sh"
if [ "${#SURFACES[@]}" -eq 0 ]; then
  SURFACES=("$ROOT/CLAUDE.md" "$ROOT/AGENT_GUIDELINES.md")
fi
RULES_DIR="$ROOT/.agent/rules"

# --session-id: default to a real, re-derivable citation (UTC date + short HEAD sha). Validated
# against exactly what add-rule.sh's write-time provenance check will accept, so a proposal can never
# fail N times at the writer for a reason knowable once, here.
if [ -z "$SESSION_ID" ]; then
  _sha="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || printf 'nogit')"
  SESSION_ID="$(date -u +%Y%m%d)-$_sha"
fi
case "$SESSION_ID" in
  *"<"*|*">"*) die "--session-id looks like an unsubstituted template ('$SESSION_ID') — add-rule.sh's provenance check refuses one; pass a real session id" 2 ;;
  session_id)  die "--session-id is the literal placeholder word 'session_id', which cites nothing; pass a real session id" 2 ;;
esac
case "$SESSION_ID" in
  *[0-9a-zA-Z]*) : ;;
  *) die "--session-id must contain at least one alphanumeric character (got: '$SESSION_ID')" 2 ;;
esac
SOURCE_VAL="dreaming:$SESSION_ID"

[ -f "$LEDGER" ] && [ -r "$LEDGER" ] || die "ledger not found or unreadable: $LEDGER" 3
# `jq empty` is the parse-only gate: it emits nothing and exits 0 on a valid stream INCLUDING an
# empty one. `jq -e .` was wrong here — its status reflects the LAST output value, so a zero-record
# ledger (a legitimate fresh-repo state) exited 4 and this script reported could-not-examine for a
# file that was perfectly readable and simply had nothing in it.
if ! jq empty "$LEDGER" >/dev/null 2>&1; then
  die "ledger is not parseable as JSONL: $LEDGER" 3
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK" 2>/dev/null' EXIT

US=$'\037'   # in-field list separator (the same one read-rules.sh uses for its route cells)

# ---------------------------------------------------------------------------
# THE THEME LEXICON — committed, reviewable, human-edited. One block per theme, in PRECEDENCE order
# (most specific first): a finding is assigned to the FIRST theme whose pattern it matches, so every
# finding lands in exactly one theme and the coverage denominator is unambiguous.
# Fields: key | category | lowercase `case` glob alternatives (|-separated) | canonical statement.
# The patterns were derived by measuring the live 107-finding corpus, not guessed; the top evidence
# tokens are drift(39) count(26) claude(15) stale(14) changelog(12) banner(11) cross-reference(8).
# ---------------------------------------------------------------------------
THEME_KEYS="restated-count-version cross-surface-sync doc-currency-drift citation-anchor test-vacuity gate-exit-contract naming-framing"

theme_field() {   # theme_field <key> <category|patterns|statement>
  local k="$1" f="$2"
  case "$k" in
    restated-count-version)
      case "$f" in
        category)  printf 'process' ;;
        patterns)  printf '*count*|*version*|*bump*|*banner*|*tally*|*plugin.json*' ;;
        statement) printf 'A count or version number is claimed in exactly one authoritative machine-readable place; every other surface derives it at read time or names the authority instead of restating the literal, because a restated number is a live claim that nothing keeps current.' ;;
      esac ;;
    cross-surface-sync)
      case "$f" in
        category)  printf 'process' ;;
        patterns)  printf '*cross-ref*|*cross-surface*|*restat*|*single-source*|*mirror*|*parity*|*sync*|*enumerated*|*duplicat*' ;;
        statement) printf 'When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.' ;;
      esac ;;
    doc-currency-drift)
      case "$f" in
        category)  printf 'documentation' ;;
        patterns)  printf '*drift*|*stale*|*diverg*|*outdated*|*out of sync*|*currency*|*rot*' ;;
        statement) printf 'Prose that describes current behaviour is corrected in the same change that alters the behaviour; a sweep for the OLD wording across every doc surface is part of the change, not a follow-up.' ;;
      esac ;;
    citation-anchor)
      case "$f" in
        category)  printf 'documentation' ;;
        patterns)  printf '*line number*|*anchor*|*citation*|*cite*|*dead ref*|*dead-ref*|*broken link*|*pointer*' ;;
        statement) printf 'A committed reference to code uses a descriptive anchor or a pinned citation that can be re-derived; a bare file:line is falsified silently by the next insertion above it.' ;;
      esac ;;
    test-vacuity)
      case "$f" in
        category)  printf 'testing' ;;
        patterns)  printf '*vacuous*|*mutation*|*fixture*|*assert*|*coverage*|*golden*|*no test*|*untested*' ;;
        statement) printf 'A load-bearing assertion is mutation-controlled: break the mechanism it guards, observe the test go RED, restore. An assertion never observed failing is not known to test anything.' ;;
      esac ;;
    gate-exit-contract)
      case "$f" in
        category)  printf 'process' ;;
        patterns)  printf '*fail-clos*|*fail clos*|*fail-safe*|*fail safe*|*exit 0*|*exit code*|*gate*|*hook*|*invariant*' ;;
        statement) printf 'A correctness gate fails CLOSED and a runtime side-effect emitter fails SAFE; changing which side of that split a surface sits on is a security change and is stated as one.' ;;
      esac ;;
    naming-framing)
      case "$f" in
        category)  printf 'documentation' ;;
        patterns)  printf '*wording*|*framing*|*prose*|*heading*|*naming*|*typo*|*phrasing*|*nit*' ;;
        statement) printf 'Wording that carries a contract — a heading a gate greps for, a sentence that states a guarantee — is treated as an interface: renaming it is a change to that interface and its consumers move with it.' ;;
      esac ;;
  esac
}

# matches_any <lowercased text> <'|'-separated glob alternatives> — tests the text against each
# alternative SEPARATELY.
# THIS SPLIT IS LOAD-BEARING, NOT STYLE. `case "$t" in $pats)` does NOT expand `|` alternation out of
# a variable: `case` parses its pattern-list separators at SYNTAX time, so an expanded `a*|b*` is one
# pattern containing a literal `|` and matches nothing. Measured — the first run of this script
# assigned 0 of 107 findings to any theme for exactly that reason, and every downstream number was a
# confident zero. A single glob from a variable, as used below, DOES expand normally.
matches_any() {
  local t="$1" rest="$2" g
  while [ -n "$rest" ]; do
    g="${rest%%|*}"
    if [ "$g" = "$rest" ]; then rest=""; else rest="${rest#*|}"; fi
    [ -n "$g" ] || continue
    case "$t" in $g) return 0 ;; esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# harvest_convention_findings — INTAKE SOURCE (i). Reads the ledger WHOLE (decision (a): no repo
# filter, nothing dropped) and emits one TSV row per `convention_mismatch` finding:
#   1 finding-id   2 repo   3 flow_stage   4 self_heal_miss   5 evidence   6 changed_paths (US-joined)
# The record-level totals it also needs (records, all findings, all misses) are computed alongside so
# the ledger is parsed once.
# ---------------------------------------------------------------------------
harvest_convention_findings() {
  local ledger="$1" out="$2"
  # The column-6 separator is passed in as a NAMED argument on purpose. It used to be a raw 0x1F
  # byte typed inline into the jq program below — which worked (jq accepts a literal control
  # character inside a string literal), but rendered as `join("")` in every reader, grep, diff and
  # review tool. Two independent review channels consequently reported it as a critical "paths are
  # concatenated with the empty string" bug, and an editor or `sed` normalisation pass that ate the
  # invisible byte would have introduced exactly that bug with no visible diff. Named, it is legible
  # and it is the same $US the two `awk -F'\t' -v us="$US" … split($6, p, us)` consumers split on.
  jq -s -r --arg us "$US" '
    to_entries[]
    | (.key + 1) as $line
    | .value as $r
    | (($r.repo // "unknown/unknown") | split("/") | last) as $rn
    | (($r.changed_paths // []) | map(select(type=="string")) | join($us)) as $cp
    | ([$r.categories[]?] | to_entries[]?)
    | select((.value | type) == "object" and .value.class == "convention_mismatch")
    | [ ($rn + "#" + (($r.number // 0)|tostring) + ":L" + ($line|tostring) + "." + ((.key+1)|tostring)),
        ($r.repo // "unknown/unknown"),
        (.value.flow_stage // "unknown"),
        (if .value.self_heal_miss == true then "miss" else "-" end),
        ((.value.evidence // "") | gsub("[\t\n\r]"; " ")),
        $cp ]
    | @tsv
  ' "$ledger" > "$out" 2>/dev/null || return 1
  return 0
}

# ---------------------------------------------------------------------------
# triage_bucket — assigns exactly ONE of agent-memory | rules | project-memory, plus a reason.
# Sets the globals BUCKET and BUCKET_REASON (bash 3.2 has no return-two-values).
# Deliberately a single function for BOTH intake sources so the three-bucket contract is stated once.
#
#   kind=theme   arg1=support(count)   arg2=stage-profile("unknowable-only"|"mixed")
#   kind=corpus  arg1=normative(0|1)   arg2=project-wide %   arg3=corroborating theme ("" = none)
#                arg4=that theme's support
# ---------------------------------------------------------------------------
triage_bucket() {
  local kind="$1"; shift
  BUCKET=""; BUCKET_REASON=""
  case "$kind" in
    theme)
      local support="$1" stages="$2"
      if [ "$stages" = "unknowable-only" ]; then
        BUCKET="agent-memory"
        BUCKET_REASON="every one of its $support findings is labelled flow_stage=unknowable, so it is attributable to no DO-side stage — a labelling/lens artifact that belongs in the labelling agent's own memory, not in a repo-wide convention"
      elif [ "$support" -ge "$MIN_SUPPORT" ]; then
        BUCKET="rules"
        BUCKET_REASON="$support convention_mismatch findings (>= the $MIN_SUPPORT support floor) recur across the ledger and reach the DO side, so the convention has to be readable before the code is written, not only after"
      else
        BUCKET="project-memory"
        BUCKET_REASON="only $support corroborating findings (< the $MIN_SUPPORT support floor) — too thin to generalise into a committed convention; recorded as durable project context instead"
      fi ;;
    corpus)
      local normative="$1" pw="$2" theme="$3" tsupport="${4:-0}"
      if [ "$normative" -eq 1 ] && [ "$pw" -ge "$PROJECT_WIDE_PCT" ] && [ -n "$theme" ] && [ "$tsupport" -ge "$MIN_SUPPORT" ]; then
        BUCKET="rules"
        BUCKET_REASON="normative, and ${pw}% of its distinctive terms already appear in this repo's committed convention surfaces (>= ${PROJECT_WIDE_PCT}%), so the project already asserts it repo-wide; still corroborated by the '$theme' theme's $tsupport findings, so it is a convention being broken rather than one merely written down. It CORROBORATES that theme's rule and does not become a rule of its own — the batch counts it as a deferral, since the theme's rule already covers the same evidence"
      elif [ "$normative" -eq 1 ] && [ "$pw" -ge "$PROJECT_WIDE_PCT" ]; then
        BUCKET="project-memory"
        BUCKET_REASON="normative and repo-wide (${pw}% of its terms are in the committed convention surfaces) but no theme reaches the $MIN_SUPPORT-finding support floor, so there is no measured violation to justify a rule — durable project context"
      else
        BUCKET="agent-memory"
        BUCKET_REASON="role-lens knowledge: normative=$normative and only ${pw}% of its distinctive terms appear in the committed convention surfaces (< ${PROJECT_WIDE_PCT}%), so it binds one agent's review lens rather than the repository"
      fi ;;
    *) BUCKET="project-memory"; BUCKET_REASON="unrecognised candidate kind '$kind' — defaulted to the non-committed destination" ;;
  esac
}

# ---------------------------------------------------------------------------
# path_matches_globs <path> <US-joined globs> — the SAME native bash `case` glob semantics
# read-rules.sh applies at read time (`*` crosses `/`; the pattern is matched against the whole
# string). Used by both derive_applies_to and scope_fidelity so the derivation and its verification
# can never diverge on matcher flavour.
# ---------------------------------------------------------------------------
path_matches_globs() {
  local p="$1" globs="$2" rest="$globs" g
  while [ -n "$rest" ]; do
    g="${rest%%"$US"*}"
    if [ "$g" = "$rest" ]; then rest=""; else rest="${rest#*"$US"}"; fi
    [ -n "$g" ] || continue
    case "$p" in $g) return 0 ;; esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# derive_applies_to <rowpaths-file> <scratch-dir> — AC2. Derives a bounded `applies_to` array from
# the `changed_paths` of the motivating findings. The input is one `<finding-ordinal>\t<live path>`
# pair per line, and the derivation is a GREEDY SET COVER OVER FINDINGS, not a frequency count over
# paths: at each step it takes the DIRECTORY prefix that covers the most still-uncovered FINDINGS,
# and stops once the chosen globs reach $APPLIES_TO_COVER% of findings or $MAX_GLOBS is reached.
# "Directory prefix" is depth-dependent and that is the whole subtlety: `a/b/c.md` yields `a/b/*`,
# but a TWO-segment path `a/b.json` yields `a/*`, because its second segment is the file itself —
# `a/b.json/*` would match only paths nested under a directory named `b.json`, i.e. never the path
# it came from. A derivation that cannot match its own motivating path is a structurally dead scope;
# scope_fidelity below reports it as 0%, which is how this was caught, but the derivation is the
# thing that has to be right.
# Ranking by findings rather than by raw path count is deliberate and it changes the answer: the
# ledger records `changed_paths` per PR, so one PR that touched 40 files under a single directory
# would otherwise outrank a directory implicated by a dozen separate findings — the scope would
# describe the biggest commit rather than the recurring convention.
# A root-level file (no `/`) contributes itself as a literal pattern.
# Prints the globs US-joined; prints NOTHING when no live path survives, which is the ONLY way a
# proposal reaches `applies_to: null` — and that path carries an explicit stated justification at the
# call site, never a silent default.
# ---------------------------------------------------------------------------
derive_applies_to() {
  local src="$1" scratch="$2" rowtotal covered=0 taken=0 out="" pref line
  local rem="$scratch/rem" hit="$scratch/hit" prefs="$scratch/prefs"
  rowtotal="$(cut -f1 "$src" 2>/dev/null | LC_ALL=C sort -u | grep -c . || true)"
  is_num "$rowtotal" || rowtotal=0
  [ "$rowtotal" -gt 0 ] || return 0

  # Reduce each (finding, path) pair to (finding, prefix), deduped.
  # THREE cases, and the two-segment one is not the three-segment one with a shorter path (see the
  # header note): `a/b/c.md` has a DIRECTORY at s[2] so `a/b/*` routes it, but `a/b` is a FILE at
  # s[2], and `a/b/*` would then match only things nested under a directory named `b` — never the
  # file it was derived from. Its directory prefix is `a/*`.
  awk -F'\t' '{ n=split($2, s, "/");
                if (n >= 3)      print $1 "\t" s[1] "/" s[2] "/*";
                else if (n == 2) print $1 "\t" s[1] "/*";
                else             print $1 "\t" $2 }' "$src" \
    | LC_ALL=C sort -u > "$rem"

  while [ "$taken" -lt "$MAX_GLOBS" ]; do
    cut -f2 "$rem" | LC_ALL=C sort | uniq -c | LC_ALL=C sort -rn > "$prefs"
    line="$(head -1 "$prefs")"
    [ -n "$line" ] || break
    pref="$(printf '%s' "$line" | sed -E 's/^ *[0-9]+ //')"
    [ -n "$pref" ] || break
    if [ -n "$out" ]; then out="$out$US$pref"; else out="$pref"; fi
    taken=$((taken + 1))
    awk -F'\t' -v p="$pref" '$2==p {print $1}' "$rem" | LC_ALL=C sort -u > "$hit"
    covered=$((covered + $(grep -c . "$hit" 2>/dev/null || echo 0)))
    awk -F'\t' 'NR==FNR { d[$1]=1; next } !($1 in d)' "$hit" "$rem" > "$rem.next" \
      && mv -f "$rem.next" "$rem"
    [ -s "$rem" ] || break
    # TRUNCATING ON PURPOSE — a stop DECISION, not a reported share (see pct()'s header): rounding
    # would let 94.5% satisfy a 95% floor and stop the cover early, narrowing a real scope.
    [ $((covered * 100 / rowtotal)) -lt "$APPLIES_TO_COVER" ] || break
  done
  printf '%s' "$out"
}

# ---------------------------------------------------------------------------
# scope_fidelity <rowpaths-file> <US-joined globs> — AC4. Mechanically re-verifies, with the SAME
# `case` matcher read-rules.sh uses at read time, that the derived scope actually routes the findings
# it was derived from: a finding counts as matched when at least one of its live changed_paths
# matches at least one derived glob. Prints "<matched> <total> <pct>".
# This is a check OF THE DERIVATION (it catches a glob that does not match what it came from — a
# root-file literal that needed a trailing `*`, a pattern shape the writer would reject), NOT an
# independent oracle for whether the scope is the RIGHT one. It cannot be, because the derivation
# and the verification read the same evidence; what it can do, and does, is fail loudly when the two
# disagree.
# ---------------------------------------------------------------------------
scope_fidelity() {
  # `share`, not `pct`: a local named `pct` would read as shadowing the pct() helper called below.
  local src="$1" globs="$2" total=0 matched=0 row share p ok
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    total=$((total + 1))
    ok=0
    # Read the row's paths LINE-wise, never by word-splitting: a changed_path containing a space
    # would otherwise be shredded into tokens that are matched independently, which can report both
    # a false match and a false miss for the same finding.
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      path_matches_globs "$p" "$globs" && { ok=1; break; }
    done <<EOP
$(awk -F'\t' -v r="$row" '$1==r {print $2}' "$src")
EOP
    matched=$((matched + ok))
  done <<EOF
$(cut -f1 "$src" | LC_ALL=C sort -u)
EOF
  share="$(pct "$matched" "$total")"
  printf '%s %s %s' "$matched" "$total" "$share"
}

# ---------------------------------------------------------------------------
# coverage_share <mapped> <total> — AC4. Share of the target class's findings that map to at least
# one PROPOSED rule. Prints "<pct> <unmapped>" so the remainder is always available to be STATED
# rather than hidden.
# ---------------------------------------------------------------------------
coverage_share() {
  local mapped="$1" total="$2"
  is_num "$mapped" || mapped=0
  is_num "$total"  || total=0
  printf '%s %s' "$(pct "$mapped" "$total")" "$((total - mapped))"
}

# ---------------------------------------------------------------------------
# dedupe_rate <findings-in> <rules-out> — AC4/AC5. Findings distilled per rule emitted, in HUNDREDTHS
# (bash 3.2 has no floats). Prints "<hundredths> <verdict>", verdict being OK or FAILURE against
# $DISTILLATION_FLOOR. A batch approaching one rule per finding has distilled nothing, and this is
# what makes the run say so in its own output instead of shipping it.
# ---------------------------------------------------------------------------
dedupe_rate() {
  local inn="$1" out="$2" rate verdict
  is_num "$inn" || inn=0
  is_num "$out" || out=0
  if [ "$out" -le 0 ]; then
    printf '0 EMPTY'; return 0
  fi
  # TRUNCATING ON PURPOSE (see pct()'s header): this hundredths value is compared to
  # $DISTILLATION_FLOOR, and rounding would let a true 1.995 findings-per-rule pass as 2.00 — i.e.
  # ship a batch this script exists to self-report as a DISTILLATION FAILURE.
  rate=$((inn * 100 / out))
  if [ "$rate" -lt "$DISTILLATION_FLOOR" ]; then verdict="FAILURE"; else verdict="OK"; fi
  printf '%s %s' "$rate" "$verdict"
}

# ---------------------------------------------------------------------------
# compose_add_rule — builds the writer invocation for ONE proposal. Prints the human-readable,
# shell-quoted command string INCLUDING the mandatory `< /dev/null` stdin detachment (decision (f)),
# and leaves the real argv in the global ADD_RULE_ARGV array for plan_rule to execute.
# `--check` is NEVER passed (AC9b) and no flag outside add-rule.sh's own set is ever composed, so no
# new member can reach the frozen rule object (AC9).
# ---------------------------------------------------------------------------
shq() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }

compose_add_rule() {
  local category="$1" statement="$2" globs="$3" rest g
  ADD_RULE_ARGV=(--category "$category" --statement "$statement" --enforcement advisory)
  ADD_RULE_CMD="add-rule.sh --category $(shq "$category") --statement $(shq "$statement") --enforcement advisory"
  rest="$globs"
  while [ -n "$rest" ]; do
    g="${rest%%"$US"*}"
    if [ "$g" = "$rest" ]; then rest=""; else rest="${rest#*"$US"}"; fi
    [ -n "$g" ] || continue
    ADD_RULE_ARGV+=(--applies-to "$g")
    ADD_RULE_CMD="$ADD_RULE_CMD --applies-to $(shq "$g")"
  done
  ADD_RULE_ARGV+=(--source "$SOURCE_VAL")
  ADD_RULE_CMD="$ADD_RULE_CMD --source $(shq "$SOURCE_VAL") < /dev/null"
}

# ---------------------------------------------------------------------------
# plan_rule — runs the composed invocation with STDIN DETACHED. This is the enforcement point for
# decision (f)/AC3b: `< /dev/null` makes add-rule.sh's `[ -t 0 ]` branch false, so the PLANNED-WRITE
# branch is the only reachable one even when this script is run from a live TTY. Sets PLAN_STATUS and
# PLAN_DETAIL. A writer refusal (a duplicate of an already-stored rule, a write-time validator
# violation) is REPORTED, never fatal — a refused proposal is a real and useful outcome.
# ---------------------------------------------------------------------------
plan_rule() {
  local out rc
  if [ "$NO_WRITER" -eq 1 ]; then
    PLAN_STATUS="writer skipped (--no-writer)"; PLAN_DETAIL=""; return 0
  fi
  if [ ! -f "$ADD_RULE" ] || [ ! -r "$ADD_RULE" ]; then
    PLAN_STATUS="writer unavailable at $ADD_RULE"; PLAN_DETAIL=""; return 0
  fi
  out="$( cd "$ROOT" && bash "$ADD_RULE" "${ADD_RULE_ARGV[@]}" < /dev/null 2>&1 )"; rc=$?
  if [ "$rc" -eq 0 ]; then
    case "$out" in
      *"PLANNED WRITE"*) PLAN_STATUS="PLANNED WRITE (not written)" ;;
      *) PLAN_STATUS="writer exited 0 WITHOUT printing PLANNED WRITE — investigate before delivery" ;;
    esac
  else
    PLAN_STATUS="writer REFUSED this proposal (exit $rc) — reported, not fatal"
  fi
  PLAN_DETAIL="$(printf '%s' "$out" | head -4)"
}

# ===========================================================================
# INTAKE (i) — the ledger.
# ===========================================================================
FINDINGS="$WORK/findings.tsv"
harvest_convention_findings "$LEDGER" "$FINDINGS" \
  || die "could not extract findings from the ledger: $LEDGER" 3

REC_TOTAL="$(grep -c . "$LEDGER" 2>/dev/null || true)"; is_num "$REC_TOTAL" || REC_TOTAL=0
# AC14's two denominators. `jq` already parses the ledger, so it does the summing too: an earlier
# form piped a per-record count through `paste -sd+ - | bc`, which made `bc` an UNDECLARED dependency
# — unlike `jq` (checked above) nothing verified it, and with `bc` absent the `|| true` + `is_num`
# fallback quietly produced 0, printing `107/0 (0%)` for the one share this whole batch is justified
# by. `reduce inputs` streams (no slurp) and emits exactly one integer; an empty ledger yields 0.
ALL_FINDINGS="$(jq -n 'reduce inputs as $r (0; . + ([$r.categories[]?] | length))' "$LEDGER" 2>/dev/null || true)"
# The `select(type=="object")` is NOT decoration. `.self_heal_miss` INDEXES the element, and jq
# throws `Cannot index string with string` on a bare string / number / null inside `categories[]` —
# which `2>/dev/null || true` then swallows into an empty ALL_MISSES, failing the `is_num` gate below
# and killing the run with exit 3 ("could not count …") on a ledger that is otherwise perfectly
# readable. That turns a handleable element into a hard failure. `harvest_convention_findings` above
# already guards exactly this shape (`select((.value | type) == "object" …)`) and the sibling
# ALL_FINDINGS line never indexes an element so it is immune — this was the one aggregate that
# skipped the guard. With 83 of 84 ledger records model-authored (`agent_generated_guess: true`), a
# malformed element is not theoretical. Verified count-preserving on the real ledger: 95 before, 95
# after.
ALL_MISSES="$(jq -n 'reduce inputs as $r (0; . + ([$r.categories[]? | select(type=="object") | select(.self_heal_miss==true)] | length))' "$LEDGER" 2>/dev/null || true)"
# Not a silent 0: `jq` is present (checked above) and the ledger already parsed (the exit-3 die
# above), so a non-numeric result here means the numbers cannot be trusted — and the whole output of
# this tool is numbers. Same rationale as the ledger die, same exit code.
is_num "$ALL_FINDINGS" && is_num "$ALL_MISSES" \
  || die "could not count findings/misses in the ledger — refusing to print a share over a denominator this run could not compute: $LEDGER" 3
CM_TOTAL="$(grep -c . "$FINDINGS" 2>/dev/null || true)"; is_num "$CM_TOTAL" || CM_TOTAL=0
CM_MISSES="$(awk -F'\t' '$4=="miss"' "$FINDINGS" 2>/dev/null | grep -c . || true)"; is_num "$CM_MISSES" || CM_MISSES=0

# Build the repo-index of live paths ONCE (a derived scope must be able to route something today).
LIVE_INDEX="$WORK/live.idx"
( cd "$ROOT" && git ls-files 2>/dev/null ) | LC_ALL=C sort > "$LIVE_INDEX" || : > "$LIVE_INDEX"
LIVE_INDEX_N="$(grep -c . "$LIVE_INDEX" 2>/dev/null || true)"; is_num "$LIVE_INDEX_N" || LIVE_INDEX_N=0

# Assign every finding to exactly one theme (first match in THEME_KEYS precedence order).
: > "$WORK/unthemed.tsv"
for k in $THEME_KEYS; do : > "$WORK/theme.$k.tsv"; done
while IFS=$'\t' read -r fid frepo fstage fmiss fev fpaths; do
  [ -n "$fid" ] || continue
  lev="$(printf '%s' "$fev" | tr '[:upper:]' '[:lower:]')"
  hit=""
  for k in $THEME_KEYS; do
    if matches_any "$lev" "$(theme_field "$k" patterns)"; then hit="$k"; break; fi
  done
  if [ -n "$hit" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$fid" "$frepo" "$fstage" "$fmiss" "$fev" "$fpaths" >> "$WORK/theme.$hit.tsv"
  else
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$fid" "$frepo" "$fstage" "$fmiss" "$fev" "$fpaths" >> "$WORK/unthemed.tsv"
  fi
done < "$FINDINGS"
UNTHEMED_N="$(grep -c . "$WORK/unthemed.tsv" 2>/dev/null || true)"; is_num "$UNTHEMED_N" || UNTHEMED_N=0

# Per-theme support, stage profile, and the alive-path set its scope will be derived from.
for k in $THEME_KEYS; do
  n="$(grep -c . "$WORK/theme.$k.tsv" 2>/dev/null || true)"; is_num "$n" || n=0
  printf '%s' "$n" > "$WORK/support.$k"
  stages="mixed"
  if [ "$n" -gt 0 ]; then
    other="$(awk -F'\t' '$3!="unknowable"' "$WORK/theme.$k.tsv" 2>/dev/null | grep -c . || true)"
    is_num "$other" || other=0
    [ "$other" -eq 0 ] && stages="unknowable-only"
  fi
  printf '%s' "$stages" > "$WORK/stages.$k"
  : > "$WORK/paths.$k"
  : > "$WORK/rowpaths.$k"
  if [ "$n" -gt 0 ]; then
    # All recorded paths for this theme (the raw denominator, used only for the null-scope
    # justification), and the per-finding (ordinal, LIVE path) pairs the scope is derived from.
    awk -F'\t' -v us="$US" '{ split($6, p, us); for (i in p) if (p[i] != "") print p[i] }' \
      "$WORK/theme.$k.tsv" | LC_ALL=C sort -u > "$WORK/paths.$k" || true
    awk -F'\t' -v us="$US" '{ split($6, p, us); for (i in p) if (p[i] != "") print NR "\t" p[i] }' \
      "$WORK/theme.$k.tsv" | LC_ALL=C sort -u > "$WORK/rowpaths.raw.$k" || true
    if [ "$LIVE_INDEX_N" -gt 0 ]; then
      # Keep only pairs whose path is still tracked: a scope derived from a path that no longer
      # exists could not route anything at read time, so it would be a dead rule authored on purpose.
      awk -F'\t' 'NR==FNR { live[$0]=1; next } ($2 in live)' \
        "$LIVE_INDEX" "$WORK/rowpaths.raw.$k" > "$WORK/rowpaths.$k" || true
    else
      cp "$WORK/rowpaths.raw.$k" "$WORK/rowpaths.$k"
    fi
  fi
done

# ===========================================================================
# INTAKE (ii) — the agent-memory corpus + any pending proposals.
# `MEMORY.md` index files are excluded (they are indexes of the corpus, not entries in it).
# An ABSENT proposals directory is a NORMAL EMPTY CASE, never an error: it does not exist on disk in
# this repo today, and a harvester that treated its absence as a failure would be unrunnable here.
# ===========================================================================
CORPUS_LIST="$WORK/corpus.txt"; : > "$CORPUS_LIST"
CORPUS_PRESENT=0
if [ -d "$CORPUS_DIR" ]; then
  CORPUS_PRESENT=1
  find "$CORPUS_DIR" -type f -name '*.md' ! -name 'MEMORY.md' 2>/dev/null | LC_ALL=C sort >> "$CORPUS_LIST" || true
fi
PROPOSALS_N=0
PROPOSALS_STATE="absent (normal empty case — the queue has never been populated in this repo)"
if [ -d "$PROPOSALS_DIR" ]; then
  find "$PROPOSALS_DIR" -type f -name '*.md' ! -name 'MEMORY.md' 2>/dev/null | LC_ALL=C sort >> "$CORPUS_LIST" || true
  PROPOSALS_N="$(find "$PROPOSALS_DIR" -type f -name '*.md' ! -name 'MEMORY.md' 2>/dev/null | grep -c . || true)"
  is_num "$PROPOSALS_N" || PROPOSALS_N=0
  PROPOSALS_STATE="present ($PROPOSALS_N pending file(s))"
fi
CORPUS_N="$(grep -c . "$CORPUS_LIST" 2>/dev/null || true)"; is_num "$CORPUS_N" || CORPUS_N=0

# The committed convention surfaces, lowercased and word-split once, for the project-wide signal.
SURFACE_TXT="$WORK/surface.txt"
: > "$SURFACE_TXT"
SURFACES_FOUND=0
for s in "${SURFACES[@]}"; do
  if [ -f "$s" ] && [ -r "$s" ]; then
    SURFACES_FOUND=$((SURFACES_FOUND + 1))
    tr 'A-Z' 'a-z' < "$s" | tr -cs 'a-z0-9' ' ' >> "$SURFACE_TXT"
  fi
done
SURFACE_WORDS=" $(tr -s ' \n' '  ' < "$SURFACE_TXT") "

STOPWORDS=" this that with from have been will must never always when then than each into only over your they them there their which while about after before shall would could should where whose those these using used uses value values thing things every other must-be "

# entry_tokens <file> — the entry's distinctive terms (>=5 chars, de-stopworded), from its
# frontmatter `description:` (the entry's own one-line thesis), falling back to its first body lines.
entry_tokens() {
  local f="$1" desc
  desc="$(sed -n 's/^description: //p' "$f" 2>/dev/null | head -1)"
  [ -n "$desc" ] || desc="$(grep -v '^---$' "$f" 2>/dev/null | grep -v '^[a-z_]*:' | grep -v '^$' | head -2 | tr '\n' ' ')"
  printf '%s' "$desc" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '\n' | awk 'length($0)>=5' | LC_ALL=C sort -u
}

# ===========================================================================
# TRIAGE (AC1) — every candidate from BOTH sources gets exactly one bucket and a recorded reason.
# ===========================================================================
TRIAGE="$WORK/triage.tsv"; : > "$TRIAGE"     # bucket \t source \t key \t support \t reason
RULE_THEMES=""                                # themes bucketed to `rules`, in precedence order

for k in $THEME_KEYS; do
  n="$(cat "$WORK/support.$k")"; stages="$(cat "$WORK/stages.$k")"
  [ "$n" -gt 0 ] || continue
  triage_bucket theme "$n" "$stages"
  printf '%s\tledger\ttheme:%s\t%s\t%s\n' "$BUCKET" "$k" "$n" "$BUCKET_REASON" >> "$TRIAGE"
  [ "$BUCKET" = "rules" ] && RULE_THEMES="$RULE_THEMES $k"
done

CORPUS_RULE_LIST="$WORK/corpus-rules.tsv"; : > "$CORPUS_RULE_LIST"   # name \t theme \t statement
while IFS= read -r f; do
  [ -n "$f" ] || continue
  name="$(basename "$f" .md)"
  toks="$(entry_tokens "$f")"
  n=0; hit=0
  for t in $toks; do
    case "$STOPWORDS" in *" $t "*) continue ;; esac
    n=$((n + 1))
    case "$SURFACE_WORDS" in *" $t "*) hit=$((hit + 1)) ;; esac
  done
  # TRUNCATING ON PURPOSE (see pct()'s header): pw is printed, but it is printed BECAUSE it is the
  # variable compared to $PROJECT_WIDE_PCT below. Rounding it would admit an 84.5% entry to the
  # `rules` bucket — a change to WHICH candidates get proposed, made for a display reason.
  pw=0; [ "$n" -gt 0 ] && pw=$((hit * 100 / n))
  [ "$SURFACES_FOUND" -gt 0 ] || pw=0
  normative=0
  grep -qE '(MUST|NEVER|ALWAYS|FORBIDDEN|REQUIRED|must be|may not|never |always )' "$f" 2>/dev/null && normative=1
  # Corroboration: the theme (among those bucketed to `rules`) whose findings' evidence shares the
  # most distinctive terms with this entry. Purely lexical and reported as such.
  best=""; bestscore=0
  for k in $RULE_THEMES; do
    sc=0
    ev="$(awk -F'\t' '{print tolower($5)}' "$WORK/theme.$k.tsv" 2>/dev/null | tr -cs 'a-z0-9' ' ')"
    ev=" $(printf '%s' "$ev" | tr -s ' \n' '  ') "
    for t in $toks; do
      case "$STOPWORDS" in *" $t "*) continue ;; esac
      case "$ev" in *" $t "*) sc=$((sc + 1)) ;; esac
    done
    if [ "$sc" -gt "$bestscore" ]; then bestscore="$sc"; best="$k"; fi
  done
  tsup=0; [ -n "$best" ] && tsup="$(cat "$WORK/support.$best")"
  triage_bucket corpus "$normative" "$pw" "$best" "$tsup"
  printf '%s\tcorpus\t%s\t%s\t%s\n' "$BUCKET" "$name" "pw=${pw}%,normative=$normative" "$BUCKET_REASON" >> "$TRIAGE"
  if [ "$BUCKET" = "rules" ]; then
    stmt="$(sed -n 's/^description: //p' "$f" 2>/dev/null | head -1)"
    [ -n "$stmt" ] || stmt="$name"
    printf '%s\t%s\t%s\n' "$name" "$best" "$stmt" >> "$CORPUS_RULE_LIST"
  fi
done < "$CORPUS_LIST"

# ===========================================================================
# BATCH — bounded by $CAP. EVERY emitted rule comes from a ledger theme: themes carry the measured
# support, and a corroborating corpus entry is a deferral rather than a rule of its own (header step
# 3). Every emitted rule names the finding ids that motivated it.
# ===========================================================================
BATCH="$WORK/batch.txt"; : > "$BATCH"
EMITTED=0
MAPPED=0
DEFERRED=0
# CAP_DEFERRED is the CAP arm of $DEFERRED alone, kept separate because $DEFERRED mixes two causes
# (cap bound + corroborating corpus entries) and the empty-batch diagnostic must name the real one.
# Without it the empty batch asserted "no theme reached the support floor" UNCONDITIONALLY, which is
# false whenever themes DID reach the floor and were deferred — `--cap 0` printed that sentence one
# line under a header stating "10 deferred by cap", i.e. the output contradicted itself.
CAP_DEFERRED=0
FIDELITY_TOTAL=0; FIDELITY_MATCHED=0
# FIDELITY_ALL_TOTAL is the HONEST denominator: every motivating finding of every EMITTED rule —
# scoped or repo-wide — including the ones the fidelity check cannot see. FIDELITY_TOTAL counts only the CHECKABLE ones (a finding
# with at least one still-tracked changed_path). Both are printed. Reporting only the first would be
# a metric that flatters itself by silently dropping the evidence that could contradict it — the
# exact failure AC4's "computed, not asserted" exists to prevent.
FIDELITY_ALL_TOTAL=0
NULL_SCOPE_N=0
# Themes that actually got a rule. NOT the same set as $RULE_THEMES: a theme bucketed `rules` can
# still be deferred by $CAP, in which case its findings are UNMAPPED and belong in the remainder
# breakdown below. Keying that breakdown on $RULE_THEMES made the itemised list under-sum the very
# total it was printed under, silently.
EMITTED_THEMES=""

emit_rule() {   # emit_rule <theme> <category> <statement> <origin-label>
  local k="$1" category="$2" statement="$3" origin="$4"
  local globs just="" fid_list fid_n sf_m sf_t sf_p sf_all ex_nopath ex_dead

  if [ "$EMITTED" -ge "$CAP" ]; then DEFERRED=$((DEFERRED + 1)); CAP_DEFERRED=$((CAP_DEFERRED + 1)); return 0; fi
  EMITTED_THEMES="$EMITTED_THEMES $k"

  mkdir -p "$WORK/derive.$k"
  globs="$(derive_applies_to "$WORK/rowpaths.$k" "$WORK/derive.$k")"
  if [ -z "$globs" ]; then
    NULL_SCOPE_N=$((NULL_SCOPE_N + 1))
    just="REPO-WIDE JUSTIFICATION (stated, never a silent default): none of the $(grep -c . "$WORK/paths.$k" 2>/dev/null || echo 0) changed_paths recorded against this theme's findings still exists in the repository index ($LIVE_INDEX_N tracked files), so any glob derived from them would route nothing at read time. A repo-wide scope is proposed instead, and this justification is what a reviewer is being asked to accept."
  fi

  fid_n="$(grep -c . "$WORK/theme.$k.tsv" 2>/dev/null || true)"; is_num "$fid_n" || fid_n=0
  # The HONEST denominator accumulates for EVERY emitted rule, scoped or repo-wide. Accumulating it
  # only in the scoped branch would have dropped a null-scope rule's findings from BOTH sides of the
  # ratio — and a rule goes null-scope precisely BECAUSE none of its changed_paths is still live,
  # which is the very population the second figure exists to keep visible. Dropping them would make
  # a batch of one 10/10 scoped rule plus a 5-finding repo-wide rule print "100% (10 of 10)", the
  # self-flattering arithmetic this two-number design was built to prevent.
  FIDELITY_ALL_TOTAL=$((FIDELITY_ALL_TOTAL + fid_n))
  fid_list="$(awk -F'\t' '{print $1}' "$WORK/theme.$k.tsv" | head -12 | tr '\n' ' ')"
  [ "$fid_n" -gt 12 ] && fid_list="$fid_list… (+$((fid_n - 12)) more)"

  compose_add_rule "$category" "$statement" "$globs"
  plan_rule

  {
    printf '  %s) [%s] theme=%s  origin=%s\n' "$((EMITTED + 1))" "$category" "$k" "$origin"
    printf '     statement: %s\n' "$statement"
    printf '     enforcement: advisory\n'
    printf '     check: null  (AC9b — no obviously mechanical check; this harvester never synthesises shell into `check`)\n'
    if [ -n "$globs" ]; then
      printf '     applies_to: [%s]\n' "$(printf '%s' "$globs" | tr "$US" ',' | sed 's/,/, /g')"
      set -- $(scope_fidelity "$WORK/rowpaths.$k" "$globs")
      sf_m="$1"; sf_t="$2"; sf_p="$3"
      FIDELITY_MATCHED=$((FIDELITY_MATCHED + sf_m)); FIDELITY_TOTAL=$((FIDELITY_TOTAL + sf_t))
      # The two excluded populations, NAMED rather than absorbed into a flattering percentage.
      ex_nopath="$(awk -F'\t' '$6==""' "$WORK/theme.$k.tsv" 2>/dev/null | grep -c . || true)"
      is_num "$ex_nopath" || ex_nopath=0
      ex_dead=$((fid_n - ex_nopath - sf_t)); [ "$ex_dead" -lt 0 ] && ex_dead=0
      sf_all="$(pct "$sf_m" "$fid_n")"
      printf '     scope fidelity: %s%% (%s of the %s CHECKABLE motivating findings have a live changed_path matched by the derived globs, via the same bash `case` matcher read-rules.sh uses)\n' "$sf_p" "$sf_m" "$sf_t"
      printf '                     over ALL %s motivating findings: %s%% (%s of %s). The denominator above is SMALLER on purpose and the filter is not silent: %s finding(s) come from a ledger record with no changed_paths at all, and %s have changed_paths of which none is still tracked by git. Neither can be matched against a glob, so neither is evidence for OR against the scope — but they are motivating findings all the same, and the honest figure is the second one.\n' \
        "$fid_n" "$sf_all" "$sf_m" "$fid_n" "$ex_nopath" "$ex_dead"
    else
      printf '     applies_to: null\n'
      printf '     scope fidelity: n/a (repo-wide) — but all %s of its motivating findings DO count in the all-findings aggregate denominator below, none of them as matched. They are not quietly excluded: a repo-wide fallback happens exactly when no changed_path survives, so dropping them would remove the least flattering evidence in the batch from the honest figure.\n' "$fid_n"
      printf '     %s\n' "$just"
    fi
    printf '     motivating findings (%s): %s\n' "$fid_n" "$fid_list"
    printf '     invocation: %s\n' "$ADD_RULE_CMD"
    printf '     writer result: %s\n' "$PLAN_STATUS"
    [ -n "$PLAN_DETAIL" ] && printf '%s\n' "$PLAN_DETAIL" | sed 's/^/       | /'
    printf '\n'
  } >> "$BATCH"

  EMITTED=$((EMITTED + 1))
  MAPPED=$((MAPPED + fid_n))
  return 0
}

for k in $RULE_THEMES; do
  emit_rule "$k" "$(theme_field "$k" category)" "$(theme_field "$k" statement)" "ledger theme"
done
# A corroborating corpus entry NEVER emits a rule of its own — see the header's step 3. Its theme is
# chosen from $RULE_THEMES and `triage_bucket corpus` requires a non-empty theme, so every entry that
# reaches this list carries a theme whose own rule was already emitted above, over the same evidence.
# There is deliberately no second arm here: an `else` branch emitting a `corpus graduate: <name>` rule
# would be unreachable by construction, and a documented branch that cannot fire is this repo's
# most-repeated defect class. Each entry is counted as a deferral so the batch stays honest about it.
while IFS=$'\t' read -r cname ctheme cstmt; do
  [ -n "$cname" ] || continue
  DEFERRED=$((DEFERRED + 1))
done < "$CORPUS_RULE_LIST"

# ===========================================================================
# METRICS (AC4/AC5) and REPORT.
# ===========================================================================
set -- $(coverage_share "$MAPPED" "$CM_TOTAL"); COV_PCT="$1"; COV_UNMAPPED="$2"
set -- $(dedupe_rate "$MAPPED" "$EMITTED"); DEDUPE="$1"; DEDUPE_VERDICT="$2"
AGG_FID="$(pct "$FIDELITY_MATCHED" "$FIDELITY_TOTAL")"
AGG_FID_ALL="$(pct "$FIDELITY_MATCHED" "$FIDELITY_ALL_TOTAL")"
CM_SHARE="$(pct "$CM_TOTAL" "$ALL_FINDINGS")"
CM_MISS_SHARE="$(pct "$CM_MISSES" "$ALL_MISSES")"

INVOCATION=""
for a in "${RAW_ARGV[@]}"; do INVOCATION="$INVOCATION $(shq "$a")"; done
INVOCATION="${INVOCATION# }"

echo "=== harvest-conventions.sh — DRY RUN (read-only: this tool has no write mode at all) ==="
echo "invocation: $INVOCATION"
echo "session source (--source passed to add-rule.sh): $SOURCE_VAL"
echo "thresholds: cap=$CAP  min-support=$MIN_SUPPORT  project-wide=$PROJECT_WIDE_PCT%  distillation-floor=$((DISTILLATION_FLOOR / 100)).$(printf '%02d' $((DISTILLATION_FLOOR % 100)))  applies-to-cover=$APPLIES_TO_COVER%  max-globs=$MAX_GLOBS"
echo
echo "--- inputs read ---"
echo "  (i)  ledger:    $LEDGER"
echo "       $REC_TOTAL records read WHOLE (no repo filter — decision (a); nothing dropped), $ALL_FINDINGS findings, $ALL_MISSES self-heal misses"
echo "  (ii) corpus:    $CORPUS_DIR"
if [ "$CORPUS_PRESENT" -eq 1 ]; then
  echo "       $((CORPUS_N - PROPOSALS_N)) entries (MEMORY.md indexes excluded)"
else
  echo "       ABSENT — normal empty case, 0 entries"
fi
echo "       proposals queue: $PROPOSALS_DIR — $PROPOSALS_STATE"
echo "  convention surfaces for the project-wide signal: $SURFACES_FOUND of ${#SURFACES[@]} readable"
echo "  rules store (read for context, NEVER written): $RULES_DIR"
echo
echo "--- repo distribution (advisory cross-check, decision (a)) ---"
awk -F'\t' '{print $2}' "$FINDINGS" | LC_ALL=C sort | uniq -c | while read -r c r; do
  flagged=""
  if [ "${#EXPECT_REPOS[@]}" -gt 0 ]; then
    flagged=" [OUT-OF-ALLOWLIST — named, not dropped]"
    for e in "${EXPECT_REPOS[@]}"; do [ "$e" = "$r" ] && flagged=""; done
  fi
  printf '  %6s  %s%s\n' "$c" "$r" "$flagged"
done
if [ "${#EXPECT_REPOS[@]}" -eq 0 ]; then
  echo "  (no --expect-repo supplied, so nothing is flagged. This script never resolves a repo"
  echo "   allowlist itself: the available resolver reads gitignored machine-local config, which"
  echo "   would make this check behave differently here and in CI. Pass --expect-repo to arm it.)"
fi
echo
echo "--- target class (AC14) ---"
echo "  this batch targets: convention_mismatch"
echo "  share of all findings:      $CM_TOTAL/$ALL_FINDINGS (${CM_SHARE}%)"
echo "  share of self-heal MISSES:  $CM_MISSES/$ALL_MISSES (${CM_MISS_SHARE}%) — the class this batch is aimed at"
echo "  by flow stage:"
awk -F'\t' '{print $3}' "$FINDINGS" | LC_ALL=C sort | uniq -c | sed 's/^/    /'
echo
echo "--- triage (AC1): every candidate in exactly ONE bucket, with the assigning reason ---"
for b in rules agent-memory project-memory; do
  n="$(awk -F'\t' -v b="$b" '$1==b' "$TRIAGE" | grep -c . || true)"; is_num "$n" || n=0
  echo "  [$b] $n candidate(s)"
  awk -F'\t' -v b="$b" '$1==b {printf "    - %s (%s: %s)\n      reason: %s\n", $3, $2, $4, $5}' "$TRIAGE"
done
echo
echo "--- proposed rule batch (cap $CAP; $EMITTED emitted, $DEFERRED deferred by cap or already-covered evidence) ---"
if [ "$EMITTED" -eq 0 ] && [ "$CAP_DEFERRED" -gt 0 ]; then
  # The cause is MEASURED, not assumed: $CAP_DEFERRED themes cleared the support floor and were
  # turned away by the batch bound, so the floor is NOT what emptied this batch. Printing the
  # support-floor sentence here contradicted the header line directly above it.
  echo "  (empty batch — but NOT for want of evidence: $CAP_DEFERRED theme(s) reached the $MIN_SUPPORT-finding support floor and were deferred by the cap=$CAP batch bound. Raise --cap to emit them; the support floor is not the cause here)"
elif [ "$EMITTED" -eq 0 ]; then
  echo "  (empty batch — no theme reached the support floor; a corpus entry corroborates a theme and never emits a rule on its own, so there is nothing else that could have been emitted)"
else
  cat "$BATCH"
fi
echo "--- metrics (AC4) — computed from the run above, not asserted ---"
echo "  coverage:        $MAPPED/$CM_TOTAL convention_mismatch findings (${COV_PCT}%) map to >= 1 proposed rule"
echo "                   UNMAPPED REMAINDER: $COV_UNMAPPED findings, of which $UNTHEMED_N matched no theme in the lexicon"
echo "                   and the rest belong to the themes itemised below, EACH WITH THE REASON it"
echo "                   emitted no rule. The reason is printed rather than assumed: a theme can be"
echo "                   unmapped for three different causes, and only one of them is the support"
echo "                   floor. Every unmapped theme appears here, so this list sums to"
echo "                   $COV_UNMAPPED minus the $UNTHEMED_N unthemed findings — it cannot under-state its own total:"
for k in $THEME_KEYS; do
  n="$(cat "$WORK/support.$k" 2>/dev/null || echo 0)"
  case " $EMITTED_THEMES " in *" $k "*) continue ;; esac
  [ "$n" -gt 0 ] || continue
  why="below the $MIN_SUPPORT-finding support floor"
  case " $RULE_THEMES " in
    *" $k "*) why="reached the support floor but was DEFERRED BY THE cap=$CAP batch bound — not a thin theme" ;;
    *) [ "$(cat "$WORK/stages.$k" 2>/dev/null || echo mixed)" = "unknowable-only" ] \
         && why="every finding is flow_stage=unknowable (support $n is NOT the reason)" ;;
  esac
  printf '                     %-24s %-4s %s\n' "$k" "$n" "($why)"
done
if [ "$EMITTED" -eq 0 ]; then
  echo "  dedupe rate:     n/a (0 rules emitted)"
else
  echo "  dedupe rate:     $((DEDUPE / 100)).$(printf '%02d' $((DEDUPE % 100))) findings distilled per rule emitted ($MAPPED in / $EMITTED out)"
fi
echo "  scope fidelity:  aggregate ${AGG_FID}% ($FIDELITY_MATCHED of $FIDELITY_TOTAL CHECKABLE motivating findings routed by their own rule's derived globs)"
echo "                   over ALL motivating findings: ${AGG_FID_ALL}% ($FIDELITY_MATCHED of $FIDELITY_ALL_TOTAL) — the $((FIDELITY_ALL_TOTAL - FIDELITY_TOTAL)) difference is findings whose ledger record carries no changed_paths, or none still tracked by git; they cannot be matched against a glob either way. This denominator spans EVERY emitted rule, including the $NULL_SCOPE_N repo-wide one(s) whose findings are unmatchable by construction — excluding those would drop the batch's least flattering evidence from the very figure meant to expose it. Both figures are printed because the first one alone would flatter the derivation by dropping its own unfalsifiable evidence; per-rule breakdowns are with each rule above"
echo "                   $NULL_SCOPE_N proposal(s) fell back to a repo-wide (null) scope, each with the stated justification shown above"
if [ "$DEDUPE_VERDICT" = "FAILURE" ]; then
  echo "  DISTILLATION FAILURE (AC5): at $((DEDUPE / 100)).$(printf '%02d' $((DEDUPE % 100))) findings per rule this batch is approaching one rule per"
  echo "                   finding, which is a restatement of the ledger rather than a distillation of it."
  echo "                   DO NOT DELIVER THIS BATCH — raise --min-support or merge themes first."
elif [ "$DEDUPE_VERDICT" = "EMPTY" ]; then
  echo "  distillation:    n/a — nothing was emitted, so there is nothing to have distilled."
else
  echo "  distillation:    OK — above the $((DISTILLATION_FLOOR / 100)).$(printf '%02d' $((DISTILLATION_FLOOR % 100))) findings-per-rule floor."
fi
echo
echo "=== END DRY RUN — no branch, no commit, no PR, nothing written to $RULES_DIR ==="
exit 0
