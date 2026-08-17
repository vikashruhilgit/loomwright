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
# IDEMPOTENCE, AND WHY IT IS PROVENANCE-KEYED RATHER THAN TEXT-KEYED. A seed is SKIPPED when it is
# already PRESENT in any well-formed `.agent/rules/*.json` array — checked BEFORE the writer is
# invoked, on both the plan and the write path. So a second `/setup rules` reports "already seeded",
# writes nothing, creates no duplicate and still exits 0. (Skipping is done here rather than left to
# the writer's own duplicate check: that check REFUSES with a non-zero status, which would turn a
# correct, already-configured second run into a reported failure.)
#
# PRESENT deliberately does NOT mean "a rule with this exact statement exists". It did once, and
# that made the skip STRICTLY NARROWER than the refusal it exists to avoid: this pre-check compared
# statements EXACTLY while the writer's duplicate validator refuses on NEAR-identical text. Every
# curated seed fell in that gap. The store is committed and human-curated — the `/setup rules` docs
# tell a user in as many words that a seed they disagree with is meant to be EDITED — and one word
# changed in a seeded statement put the module into a PERMANENT failure state: `check` reported the
# seed ABSENT, `seed --confirm` therefore called the writer, the writer REFUSED the near-duplicate,
# and the run exited 1 for good, on a correctly-configured repo. `seed_present` is therefore keyed
# on the SEEDED STAMP, which survives an edit to the prose:
#   · `.statement == <the seed's statement>` — exact, any provenance. Keeps a hand-authored
#     identical rule counting as present, exactly as before, and covers a seeded rule whose
#     provenance a user has since rewritten.
#   · OR `.provenance.source == setup:rules-seed` AND the rule belongs to this seed's CATEGORY —
#     matched either on `.category` or on the `<category>-` prefix of the frozen `.id`, so a
#     re-categorised seed is still recognised. Statement text is not consulted at all on this
#     branch, which is the point: an edited seed is a CURATED seed, not a missing one.
# CATEGORY IS THE PER-SEED KEY ONLY BECAUSE THE TABLE HAS ONE ROW PER CATEGORY, and that is not
# left to a future editor's memory: a duplicate category in `seed_table` is a hard error at startup
# (see the invariant directly below the table). Were two seeds to share a category, one curated
# survivor would mask the other's absence and it would silently never be seeded.
#
# WHAT IS STILL NOT IDEMPOTENT — RETRACTION. Editing a seed is durable curation; RETRACTING one is
# not. `add-rule.sh --retract` removes the object outright, so nothing remains to carry the stamp,
# and a later `/setup rules` re-offers and rewrites that seed at exit 0 with no record that the user
# rejected it. This is a KNOWN LIMIT, not an oversight: recording a retraction needs somewhere to
# put it, and the rule schema is FROZEN (7 members) while a sidecar would be the same freeze
# violation one layer out. So the honest statement — made here, in the module docs and in the
# terminal output — is that RETRACT IS NOT A PERMANENT OPT-OUT. To keep a seed out today, edit it
# (durable) or do not re-run the module.
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

# ---- THE ONE-ROW-PER-CATEGORY INVARIANT (asserted, never assumed) -----------
# `seed_present` keys a seeded rule to its seed by CATEGORY (see the IDEMPOTENCE block above), which
# is a faithful key only while every category appears at most once in the table. Adding a second row
# to an existing category would make the first curated survivor answer for both, and the second seed
# would then be silently skipped forever — a quiet mismatch, exactly the failure class this script
# was fixed for. So the table is checked at startup and a duplicate category is a LOUD failure: a
# future editor adding such a row cannot get a green run out of it.
_dupe_cat="$(seed_table | cut -d'|' -f1 | LC_ALL=C sort | LC_ALL=C uniq -d | head -1 || true)"
[ -z "$_dupe_cat" ] || die "seed table invariant violated: category '$_dupe_cat' appears in more than one row. seed_present() keys presence on (seeded stamp + category), so two seeds sharing a category would make one of them permanently unseedable — give the second seed its own category, or re-key seed_present per seed before adding the row"
unset _dupe_cat

# ---- THE CATEGORY-IS-ALREADY-ITS-OWN-SLUG INVARIANT (asserted, never assumed) ----------
# The SAME permanent-failure class as the guard directly above, reached through the category instead
# of the statement text — and today it is INVISIBLE, because all five seed categories happen to be
# valid slugs already, so raw == slug and nothing can go wrong yet.
#
# The mechanism: seed_present() matches the STORED rule's `.category` (and the `<category>-` prefix
# of its frozen `.id`) against the RAW string from seed_table. But `add-rule.sh` SLUGS the category
# before writing it. A future row reading `Error Handling` would be stored as
# `.category: "error-handling"`; the raw-string match would never fire; the seed would report ABSENT
# on every run FOREVER; the writer would be re-invoked every run and would very plausibly hit its own
# near-duplicate refusal — exactly the loop the statement-keyed fix above was written for.
#
# MIRRORED, not invented: this is `add-rule.sh`'s own `slug()` (lowercase → non-[a-z0-9] runs to '-'
# → collapse repeats → strip leading/trailing '-'), copied verbatim rather than approximated. A
# looser property such as `^[a-z0-9-]+$` would NOT catch it: `--foo-` and `a--b` both satisfy that
# and both are still rewritten by slug(). If add-rule.sh's slug() ever changes, this mirror must move
# with it — that coupling is the cost of asserting the real invariant instead of a weaker proxy, and
# it is stated here so the next editor knows the mirror exists.
_slug_of() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//'
}
# A HEREDOC, never `seed_table | while`: a piped loop body runs in a SUBSHELL, where this die()'s
# `exit` would kill only that subshell and the run would sail on past a violated invariant.
while IFS='|' read -r _cat _rest; do
  [ -n "$_cat" ] || continue
  _cat_slug="$(_slug_of "$_cat")"
  [ "$_cat" = "$_cat_slug" ] || die "seed table invariant violated: category '$_cat' is not already its own slug (add-rule.sh would store it as '$_cat_slug'). seed_present() matches the STORED rule's .category against this RAW string, so this seed would report ABSENT forever, re-invoke the writer every run, and hit its near-duplicate refusal — use '$_cat_slug' as the category in seed_table"
done <<SEEDCATS
$(seed_table)
SEEDCATS
unset _cat _rest _cat_slug

# ---------------------------------------------------------------------------
# Arg parsing. Same flat namespace as the sibling setup helpers; the subcommand is positional.
# ---------------------------------------------------------------------------
SUBCMD=""
ROOT_OVERRIDE=""
ADD_RULE=""
CONFIRM_FLAG=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    # A SECOND subcommand is a hard error, never a silent drop. Guarding only the assignment while
    # shifting unconditionally meant `seed check` kept `seed`, discarded `check` with no diagnostic,
    # and went on to WRITE — the opposite of what the caller asked for. Every other malformed input
    # in this family (category containment, --retract exclusivity) dies; so does this one.
    check|seed)  [ -z "$SUBCMD" ] || die "only one subcommand may be given (already have '$SUBCMD', then got '$1')"
                 SUBCMD="$1"; shift ;;
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
# seed_present <category> <statement> — 0 when this seed is already PRESENT in any WELL-FORMED
# `.agent/rules/*.json` array. PRESENT is the two-branch, provenance-keyed test described in the
# IDEMPOTENCE block at the top of this file: an EXACT statement match (any provenance), OR a rule
# stamped `provenance.source = setup:rules-seed` belonging to this seed's category — the latter
# recognises a seed whose statement a user has since EDITED, which is curation, not absence.
# Only array files are searched, mirroring the writer's and the reader's own fail-safe scope: a
# malformed sibling contributes nothing either way.
# Sets SEED_PRESENT_FILE / SEED_PRESENT_ID / SEED_PRESENT_HOW (exact|curated) for the report line.
# ---------------------------------------------------------------------------
SEED_PRESENT_FILE=""
SEED_PRESENT_ID=""
SEED_PRESENT_HOW=""
seed_present() {
  local cat="$1" st="$2" rf hit
  SEED_PRESENT_FILE=""; SEED_PRESENT_ID=""; SEED_PRESENT_HOW=""
  [ -d "$RULES_DIR" ] || return 1
  while IFS= read -r rf; do
    [ -n "$rf" ] || continue
    jq -e 'type=="array"' "$rf" >/dev/null 2>&1 || continue
    # Every member is read defensively (`| strings`, an explicit object test on `.provenance`): a
    # stray non-object element or a hand-mangled member must not abort the scan of a whole file.
    # `(.statement | strings)` is EMPTY when `.statement` is absent or non-string, and an empty
    # operand makes the whole `==` empty, which jq propagates by DROPPING the element — before the
    # provenance branch of the `or` is ever evaluated. That silently defeated the curated arm: a
    # rule stamped `provenance.source = setup:rules-seed` for this category but missing `.statement`
    # reported ABSENT, contradicting this comment in the one function written to survive hand
    # editing. `// ""` collapses the empty to a value so the `or` can short-circuit properly. The
    # same hoist is applied to the exact-vs-curated label below, which had the identical defect (an
    # empty `if` condition emits nothing, yielding a one-column @tsv row).
    hit="$(jq -r --arg s "$st" --arg c "$cat" --arg src "$SEED_SOURCE" '
        first(
          .[]?
          | select(type == "object")
          | select(
              (((.statement | strings) // "") == $s)
              or (
                ((.provenance | if type == "object" then (.source | strings) else empty end) == $src)
                and (
                  ((.category | strings) == $c)
                  or (((.id | strings) // "") | startswith($c + "-"))
                )
              )
            )
          | [ ((.id | strings) // ""), (if (((.statement | strings) // "") == $s) then "exact" else "curated" end) ]
          | @tsv
        ) // empty' "$rf" 2>/dev/null || true)"
    if [ -n "$hit" ]; then
      SEED_PRESENT_FILE="$rf"
      SEED_PRESENT_ID="${hit%%$'\t'*}"
      SEED_PRESENT_HOW="${hit##*$'\t'}"
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
  echo "    EDIT is durable — a rule keeping the seeded stamp for its category counts as seeded"
  echo "    whatever you rewrite it to say, so a later run reports it present and rewrites nothing."
  echo "    RETRACT IS NOT A PERMANENT OPT-OUT: it removes the object, so nothing is left to carry"
  echo "    the stamp and a later /setup rules will offer and write that seed again. Recording a"
  echo "    refusal would need a store the frozen rule schema has no room for. To keep a seed out"
  echo "    today, edit it down to what you do want, or do not re-run this module."
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

  if seed_present "$category" "$statement"; then
    PRESENT=$((PRESENT + 1))
    printf 'seed: ALREADY SEEDED  [%s]  id=%s  (in %s)\n' "$category" "$SEED_PRESENT_ID" "$SEED_PRESENT_FILE"
    # A CURATED match is reported as such: the stored rule no longer carries the shipped wording, and
    # the shipped wording below is the seed this repo started from, NOT what the store says today.
    if [ "$SEED_PRESENT_HOW" = "curated" ]; then
      printf '  (curated: the stored rule carries the seeded stamp for this category but its own\n'
      printf '   wording — your edit stands and is never overwritten. Shipped seed text was:)\n'
    fi
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
