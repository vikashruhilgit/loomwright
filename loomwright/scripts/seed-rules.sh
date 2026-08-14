#!/usr/bin/env bash
# seed-rules.sh — the `/setup rules` cold-start module engine: gives a repo with NO measured
# findings a small starting set of PORTABLE conventions in `.agent/rules/`, labelled SEEDED
# rather than presented as something this tool learned from the repo.
#
# WHAT IT IS FOR. `/dreaming` distils rules from what a repo has actually accumulated — ledger
# findings and the agent-memory corpus. A fresh repo has accumulated nothing, so that path yields
# an empty batch and the rules substrate stays cold forever. This helper closes that cold-start
# gap from the other end: it seeds conventions that are true of ANY repository, so a new user gets
# a non-empty, readable store on day one without anyone pretending the tool measured them.
#
# SEEDED IS NOT LEARNED, AND THE DISTINCTION IS DATA, NOT PROSE. Every rule authored here is
# stamped `provenance.source = setup:rules-seed`. That single distinctive value IS the mechanism —
# a reader (or a later curation pass) separates a shipped default from a rule `/dreaming` earned
# off this repo's own findings (`dreaming:<session_id>`) by reading `provenance.source` and
# nothing else. NO new member is added to the rule object and NO sidecar file is written: the
# schema is FROZEN at 7 always-present members (`id`, `category`, `statement`, `enforcement`,
# `check`, `provenance`, `applies_to`) plus the optional `supersedes`, `add-rule.sh` rejects any
# unknown argument outright, and a sidecar would be the same freeze violation one layer out.
# This script's own output says the same thing in words, so a user reading the terminal cannot
# come away believing these were earned.
#
# WHAT MAKES A SEED PORTABLE, and why the set is deliberately small. A seed earns its place only
# if it is true of any repository in any language — a convention that depends on this project's
# layout, stack or house style is NOT portable and must not be shipped as one. The set is a
# COMMITTED, reviewable table in this file (`seed_table` below); this script never invents rule
# prose at run time. Two consequences worth stating because they look like omissions:
#   · Every seed is REPO-WIDE (`applies_to: null`) and `--applies-to` is deliberately never
#     composed. A path glob is a claim about a directory layout — `src/**`, `app/**`, `lib/**`
#     exist in some repos and not others — so scoping a PORTABLE rule to a path would contradict
#     the very portability that qualifies it. The repo-wide scope is therefore a stated
#     justification, not a silent default: it is printed per rule in this script's own output.
#     A rule that genuinely needs a path scope is evidence-derived, which is `/dreaming`'s job.
#   · `check` is left `null` on every seed — `--check` is never passed. Rules are DATA, never
#     executed; the reader does not run them, the `--no-cmd` boundary in the rules checker is
#     unchanged, and this module ADDS NO GATE. A seeded rule is advisory and subordinate to the
#     project's own CLAUDE.md.
#
# AUTHORED THROUGH THE SOLE WRITER. Every rule is composed as an `add-rule.sh` invocation — this
# script never hand-builds a rule object, so category containment, the value validation, the
# deterministic id, the array-only parse gate and the write-time entry validator all apply to a
# seed exactly as they do to a hand-written `/rules add`.
#
# WRITE POSTURE — WHICH INVOCATION WRITES, stated explicitly so an accidental unattended run is
# safe. `add-rule.sh` has THREE branches and only the last is a dry run:
#     --confirm                                → writes.
#     no --confirm, but `[ -t 0 ] && [ -t 1 ]` → PROMPTS `Confirm write? [y/N]`, WRITES on `y`.
#     no --confirm, no TTY on stdin            → prints `PLANNED WRITE (not written …)`, exits 0.
# `/setup` runs interactively on a live TTY, i.e. exactly the prompting case, so omitting
# `--confirm` is NOT by itself a dry run. This script therefore:
#     seed-rules.sh check            → NEVER writes; read-only report, invokes no writer at all.
#     seed-rules.sh seed             → NEVER writes. Every writer invocation REDIRECTS STDIN FROM
#                                      /dev/null, which makes `[ -t 0 ]` false and the
#                                      PLANNED-WRITE branch the only reachable one.
#     seed-rules.sh seed --confirm   → WRITES. Unattended and silent by design.
# The `< /dev/null` is on BOTH paths, so THIS SCRIPT NEVER PROMPTS: consent is the command
# layer's job (`/setup rules` asks once, then passes `--confirm`), never N prompts fired at a
# user's terminal by a loop. A real write here is legitimate — `/setup` is an interactive,
# user-initiated command — but it takes an explicit `--confirm`, so a cron job, a hook or a
# careless `bash seed-rules.sh seed` writes nothing.
#
# IDEMPOTENCE. A seed is SKIPPED when a rule carrying the identical `statement` already exists in
# any well-formed `.agent/rules/*.json` array — checked BEFORE the writer is invoked, on both the
# plan and the write path. So a second `/setup rules` reports "already seeded", writes nothing,
# creates no duplicate and still exits 0. (Skipping is done here rather than left to the writer's
# own duplicate check: that check REFUSES with a non-zero status, which would turn a correct,
# already-configured second run into a reported failure.)
#
# Usage:
#   seed-rules.sh check                        # read-only: which seeds are present / absent
#   seed-rules.sh seed                         # PLAN only — prints the planned writes, writes nothing
#   seed-rules.sh seed --confirm               # apply: authors every absent seed via add-rule.sh
#   seed-rules.sh --root <dir> check           # point at a fixture repo (need not be a git repo)
#   seed-rules.sh --add-rule <path> seed       # use a specific writer (tests / mutation control)
#   seed-rules.sh -h | --help
#
# Exit:
#   0 — every seed handled: reported (check), planned (seed), written (seed --confirm), or already
#       present. Nothing partial is claimed on this path.
#   1 — at least one seed the writer REFUSED or could not write. The per-seed line names it and the
#       run does NOT report success.
#   2 — usage error (unknown argument, missing value, unknown or missing subcommand) or a missing
#       dependency (`jq`, or the `add-rule.sh` writer).

set -euo pipefail

PROG="seed-rules.sh"
SEED_SOURCE="setup:rules-seed"

die() { printf '%s: %s\n' "$PROG" "$1" >&2; exit "${2:-2}"; }

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  # Print the leading header comment block (line 2 through the last contiguous `#` line), robust
  # to header edits — no hard-coded line range to drift when the header grows or shrinks.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
  exit 0
}

# ---------------------------------------------------------------------------
# THE SEED TABLE — committed, reviewable, `<category>|<statement>` per line.
#
# Admission test for a row, applied to every one below: would this sentence be true and useful in
# a repository written in another language, by another team, with another directory layout? If the
# answer needs a "well, in this project…", the row does not belong here. Each row also names NO
# file, NO path and NO tool, which is both what keeps it portable and what keeps the writer's
# dead-reference check from having an opinion about a fixture repo's tree.
#
# `|` is the field delimiter: no statement contains one, and `add-rule.sh` rejects a category
# containing shell metacharacters outright, so the delimiter can never be smuggled in either half.
# ---------------------------------------------------------------------------
seed_table() {
  cat <<'SEEDS'
verification|Verify a claim against the system before asserting it: read the code, run the command, or check the state. Never assert that something does not exist, that an interface has a given shape, or that a change has landed, on memory alone.
security|Never commit credentials, tokens, private keys or personal data. Keep them in environment variables or a dedicated secret store, and keep them out of source, logs, test fixtures and error messages.
process|Keep a change to the scope its task requires. Unrelated refactoring, renaming and reformatting belong in a separate change, so a reviewer can tell what actually changed from what merely moved.
documentation|Update the documentation that describes a behaviour in the same change that alters that behaviour. Documentation left behind by the code it describes is a false claim, not a stale note.
error-handling|Surface a failure instead of swallowing it. Never discard an error status to make a step pass, and never report success on a path whose outcome was never actually checked.
SEEDS
}

# ---------------------------------------------------------------------------
# Arg parsing. Same flat namespace as the sibling setup helpers; the subcommand is positional.
# ---------------------------------------------------------------------------
SUBCMD=""
ROOT_OVERRIDE=""
ADD_RULE=""
CONFIRM_FLAG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    check|seed)  [ -z "$SUBCMD" ] && SUBCMD="$1"; shift ;;
    --root)      [ "$#" -ge 2 ] || die "--root requires a path argument"; ROOT_OVERRIDE="$2"; shift 2 ;;
    --add-rule)  [ "$#" -ge 2 ] || die "--add-rule requires a path argument"; ADD_RULE="$2"; shift 2 ;;
    --confirm)   CONFIRM_FLAG="--confirm"; shift ;;
    -h|--help)   usage ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

[ -n "$SUBCMD" ] || die "a subcommand is required: 'check' or 'seed' (see --help)"

command -v jq >/dev/null 2>&1 || die "jq is required but not available"

[ -n "$ADD_RULE" ] || ADD_RULE="$HERE/add-rule.sh"
if [ "$SUBCMD" = "seed" ] && { [ ! -f "$ADD_RULE" ] || [ ! -r "$ADD_RULE" ]; }; then
  die "the sole writer add-rule.sh is missing or unreadable at '$ADD_RULE' — refusing to author a rule object by hand"
fi

# ---- root resolution --------------------------------------------------------
# An explicit --root wins and is used verbatim (it need NOT be a git repo — that is what makes a
# fixture testable); otherwise the git toplevel; otherwise $PWD. The writer is invoked from inside
# this root, so its own repo-root anchoring resolves to the same store this script reports on.
if [ -n "$ROOT_OVERRIDE" ]; then
  ROOT="$ROOT_OVERRIDE"
else
  ROOT="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
RULES_DIR="$ROOT/.agent/rules"

# ---------------------------------------------------------------------------
# seed_present <statement> — 0 when a rule carrying this EXACT statement already exists in any
# WELL-FORMED `.agent/rules/*.json` array. Only array files are searched, mirroring the writer's
# and the reader's own fail-safe scope: a malformed sibling contributes nothing either way.
# Sets SEED_PRESENT_FILE / SEED_PRESENT_ID for the report line.
# ---------------------------------------------------------------------------
SEED_PRESENT_FILE=""
SEED_PRESENT_ID=""
seed_present() {
  local st="$1" rf id
  SEED_PRESENT_FILE=""; SEED_PRESENT_ID=""
  [ -d "$RULES_DIR" ] || return 1
  while IFS= read -r rf; do
    [ -n "$rf" ] || continue
    jq -e 'type=="array"' "$rf" >/dev/null 2>&1 || continue
    id="$(jq -r --arg s "$st" 'first(.[]? | select((type=="object") and (.statement == $s)) | .id) // empty' "$rf" 2>/dev/null || true)"
    if [ -n "$id" ]; then
      SEED_PRESENT_FILE="$rf"; SEED_PRESENT_ID="$id"
      return 0
    fi
  done < <(LC_ALL=C find "$RULES_DIR" -maxdepth 1 -type f -name '*.json' 2>/dev/null | LC_ALL=C sort)
  return 1
}

# ---------------------------------------------------------------------------
# The seeded-vs-learned disclosure. Printed FIRST on every path, including `check`, so the framing
# is read before any rule text is — a user must never take these for something the tool measured.
# ---------------------------------------------------------------------------
print_disclosure() {
  local n="$1"
  echo "== /setup rules — portable convention seeds =="
  echo "root: $ROOT"
  echo
  echo "These $n rules are SEEDED DEFAULTS shipped with the plugin. They were NOT learned from this"
  echo "repository: nothing here has been measured, harvested or observed to produce them. They are"
  echo "conventions held to be true of ANY repository, offered as a starting point."
  echo
  echo "  · every seeded rule is stamped provenance.source=$SEED_SOURCE — that stamp is how a"
  echo "    reader tells a shipped default from a rule /dreaming EARNED from this repo's own"
  echo "    findings (which carries dreaming:<session_id> instead);"
  echo "  · every seed is repo-wide (applies_to: null) on purpose — a path glob is a claim about a"
  echo "    directory layout, and no layout is universal, so scoping a portable rule to a path"
  echo "    would contradict the portability that qualifies it;"
  echo "  · check is null on every seed — rules are DATA, never executed, advisory, and"
  echo "    subordinate to this project's own CLAUDE.md. This module adds NO gate;"
  echo "  · edit or retract any of them: they are a starting point, not a verdict on your repo."
  echo
}

# ---------------------------------------------------------------------------
# Run.
# ---------------------------------------------------------------------------
TOTAL=0; PRESENT=0; ABSENT=0; PLANNED=0; WROTE=0; FAILED=0

TOTAL="$(seed_table | grep -c '|' || true)"
print_disclosure "$TOTAL"

if [ "$SUBCMD" = "seed" ]; then
  if [ -n "$CONFIRM_FLAG" ]; then
    echo "mode: seed --confirm — absent seeds WILL be written to $RULES_DIR"
  else
    echo "mode: seed (plan only) — nothing is written; pass --confirm to apply"
  fi
else
  echo "mode: check — read-only, no writer is invoked"
fi
echo

while IFS='|' read -r category statement; do
  [ -n "$category" ] || continue
  [ -n "$statement" ] || continue

  if seed_present "$statement"; then
    PRESENT=$((PRESENT + 1))
    printf 'seed: ALREADY SEEDED  [%s]  id=%s  (in %s)\n' "$category" "$SEED_PRESENT_ID" "$SEED_PRESENT_FILE"
    printf '  %s\n\n' "$statement"
    continue
  fi

  ABSENT=$((ABSENT + 1))
  if [ "$SUBCMD" = "check" ]; then
    printf 'seed: ABSENT  [%s]  (run `/setup rules` to seed it)\n' "$category"
    printf '  %s\n\n' "$statement"
    continue
  fi

  printf 'seed: %s  [%s]  source=%s  scope=repo-wide (justification: portable by construction — see the disclosure above)\n' \
    "$( [ -n "$CONFIRM_FLAG" ] && echo "WRITING" || echo "PLANNED" )" "$category" "$SEED_SOURCE"
  # The invocation is printed verbatim, `< /dev/null` included, so a reader can check the
  # stdin detachment rather than take this file's word for it.
  printf '  add-rule.sh --category %s --statement <the statement above> --enforcement advisory --source %s%s < /dev/null\n' \
    "$category" "$SEED_SOURCE" "${CONFIRM_FLAG:+ $CONFIRM_FLAG}"

  # `--check` is NEVER passed (rules stay DATA) and `--applies-to` is NEVER passed (repo-wide by
  # construction). The stdin redirection is load-bearing on BOTH paths — see the WRITE POSTURE
  # block in this file's header.
  if ( cd "$ROOT" && bash "$ADD_RULE" \
         --category "$category" \
         --statement "$statement" \
         --enforcement advisory \
         --source "$SEED_SOURCE" \
         $CONFIRM_FLAG < /dev/null ); then
    if [ -n "$CONFIRM_FLAG" ]; then WROTE=$((WROTE + 1)); else PLANNED=$((PLANNED + 1)); fi
  else
    FAILED=$((FAILED + 1))
    printf 'seed: FAILED  [%s] — the writer refused or could not write this seed (its reason is above)\n' "$category" >&2
  fi
  echo
done <<EOF
$(seed_table)
EOF

echo "== summary =="
printf 'seeds: %s total · %s already seeded · %s absent\n' "$TOTAL" "$PRESENT" "$ABSENT"
case "$SUBCMD" in
  check) printf 'nothing was written (check is read-only).\n' ;;
  seed)
    if [ -n "$CONFIRM_FLAG" ]; then
      printf 'written: %s · failed: %s\n' "$WROTE" "$FAILED"
    else
      printf 'planned: %s · failed: %s · NOTHING WAS WRITTEN (pass --confirm to apply)\n' "$PLANNED" "$FAILED"
    fi ;;
esac
printf 'every rule above is a SEEDED default (provenance.source=%s), not something learned from this repo.\n' "$SEED_SOURCE"

[ "$FAILED" -eq 0 ] || exit 1
exit 0
