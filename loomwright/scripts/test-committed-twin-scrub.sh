#!/usr/bin/env bash
# test-committed-twin-scrub.sh — the committed Twin stores carry ONLY loomwright content, and the
# gitignore negation that makes them committable re-includes exactly the intended paths.
#
# WHY THIS EXISTS: `vikashruhilgit/loomwright` is a PUBLIC repo. Committing `.claude/agent-memory/`
# and `.supervisor/memory/` publishes the Twin's accumulated judgment irreversibly — a push cannot
# be taken back, and `/setup memory remove` explicitly does NOT unpublish (setup-memory.sh:920-926).
# One memory entry cited a private work repo before this migration. This is the regression net that
# stops it coming back.
#
# ---------------------------------------------------------------------------------------------
# ONE-TIME AUDIT PROVENANCE (migration of 2026-08-07) — how the deny-list was DERIVED, not guessed
# ---------------------------------------------------------------------------------------------
# The terms below are NOT a guess at what contamination looks like. They were derived from data
# that already existed: the findings ledger's own `.repo` field values, split on `/` into org and
# short names, then matched WHOLE-WORD and CASE-INSENSITIVELY. The exact command was:
#
#     jq -r '.repo // empty' .supervisor/postmortem/results.jsonl | tr '/' '\n' | sort -u
#
# which returned, at migration time:
#
#     ai-agent-manager
#     hub
#     loomwright
#     vendsy
#     vikashruhilgit
#
# Own-repo terms (`vikashruhilgit`, `loomwright`, and the pre-rename `ai-agent-manager`) are
# dropped. The remainder — `vendsy` and `hub`, contributed by the 7 `vendsy/hub` records — is the
# deny-list in DENY_TERMS below. Record of the ledger census at that moment:
#     42  vikashruhilgit/ai-agent-manager   (pre-rename)
#     37  vikashruhilgit/loomwright
#      7  vendsy/hub                        (foreign — the reason this test exists)
#
# WHY THE METHOD IS THE DELIVERABLE, NOT JUST ITS RESULT: the ledger was gitignored, and a later
# item filters the foreign records out of it. Re-running the command above against the committed
# tree can therefore NEVER re-derive these terms — the evidence is post-filter. So the method is
# recorded here, in the committed tree, or it is lost.
#
# THAT LATER ITEM HAS NOW LANDED. The ledger is a committed, GATED third store (see group (D)); the
# 7 `vendsy/hub` records were filtered out before it was committed. The census above is therefore
# FROZEN HISTORY — do not "refresh" it from the committed tree, which is post-filter by construction
# and would silently narrow DENY_TERMS to nothing.
#
# WHY WHOLE-WORD, CASE-INSENSITIVE: two independent audits previously returned a FALSE CLEAN on
# `project_self_heal_rubber_stamp.md`. Both grepped `/hub` (slash-prefixed) while the real string
# was `HUB #146` — no slash, a space before the `#`, uppercase. Derive from data that exists and
# match on word boundaries; never grep a guessed string form.
#
# WHY AN EXPLICIT FILE LIST: a shell-glob sweep (`grep -riwE … .supervisor/memory/*`) SKIPS
# dot-prefixed files, which would silently miss `.supervisor/memory/.provenance.jsonl` and
# `.supervisor/memory/.lessons-provenance.jsonl` — exactly the provenance sidecars the negation
# goes out of its way to re-include. Both are named explicitly below. A `find`-based completeness
# check then asserts the explicit list covers EVERY file actually on disk, so a memory entry added
# later cannot quietly escape the sweep.
#
# KNOWN LIMIT — READ BEFORE TRUSTING A GREEN RUN: the deny-list is STATIC. It catches the known
# contamination class returning; it does NOT detect a NEW foreign org appearing for the first time
# in a memory file. That is a real class, not a theoretical one: the redacted entry cited a PR
# number that appears NOWHERE in the ledger, because agent memory is distilled from sessions that
# span repos. General detection is a separate, later item. A green run here means "the known
# contamination has not returned", NOT "these files are clean of everything".
#
# WRITE CONTAINMENT: this test makes ZERO writes under the real repo root. Every `apply`/`remove`
# exercise runs against a `mktemp -d` + `git init` fixture through `setup-memory.sh --root`, with
# `trap … EXIT` cleanup (pattern from test-no-junk-tracked-files.sh:62-71). This matters because
# CI hard-globs `loomwright/scripts/test-*.sh` (.github/workflows/ci.yml:62), so an unisolated
# test would rewrite the real `.gitignore` and litter a backup on every CI run. The containment is
# asserted, not assumed — see group (F).
#
# Fail-CLOSED: any violation exits 1. This is a correctness gate, not a fail-safe emitter.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
SETUP_MEMORY="$HERE/setup-memory.sh"

PASS=0
FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

cd "$REPO_ROOT" 2>/dev/null || { echo "FAIL: cannot cd to repo root" >&2; exit 1; }

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "SKIP: not a git repository — committed-twin-scrub gate not run"
  exit 0
fi

# ---- write-containment baseline (compared again in group (F)) ---------------
BASELINE_GITIGNORE_CKSUM="$(cksum < "$REPO_ROOT/.gitignore" 2>/dev/null || echo missing)"

TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT

# =============================================================================
# The deny-list. Derived, not guessed — see ONE-TIME AUDIT PROVENANCE above.
# =============================================================================
DENY_TERMS='vendsy|hub'

# -----------------------------------------------------------------------------
# assert_no_foreign_terms <label> <file> [file...]
#
# Sweeps the given files for DENY_TERMS, WHOLE-WORD (-w) and CASE-INSENSITIVE (-i).
# Returns 0 when clean, 1 when any file carries a foreign term (and prints the hits).
#
# `-w` IS LOAD-BEARING, NOT DECORATION. These files say "GitHub" constantly (GitHub Actions,
# github.com, GitHub CLI). Without `-w`, `hub` matches inside "GitHub" and this sweep goes red on
# every run — which, in practice, means someone deletes the check. Group (B) proves `-w` keeps
# "GitHub" clean while group (C) proves it still catches a real `HUB #146`. Drop the `-w` and
# group (B) goes red: that is the intended mutation test.
# -----------------------------------------------------------------------------
assert_no_foreign_terms() {
  local label="$1"; shift
  if [ "$#" -eq 0 ]; then
    echo "assert_no_foreign_terms: no files given for '$label'" >&2
    return 1
  fi
  local hits
  hits="$(grep -HinwE "$DENY_TERMS" "$@" 2>/dev/null)"
  if [ -n "$hits" ]; then
    echo "--- foreign-term hits ($label) ---" >&2
    printf '%s\n' "$hits" >&2
    return 1
  fi
  return 0
}

# ignore_is_in <repo-dir> <path> → ignored | committable | unknown
#
# `--verbose -n` IS NOT AN IGNORE PROBE — IT IS A "DID ANY PATTERN MATCH" PROBE. This function used
# to be `git check-ignore --verbose -n`, whose exit status is 0 whenever a pattern matched the path
# **including a NEGATED `!` pattern**, i.e. precisely when the path IS committable. Verified on
# git 2.50 against this repo:
#     check-ignore --verbose -n  .supervisor/postmortem/results.jsonl → rc 0, rule `!…results.jsonl`
#     check-ignore -q            .supervisor/postmortem/results.jsonl → rc 1  (correct: committable)
# The bug was INVISIBLE for the two memory stores because they are re-included by DIRECTORY patterns
# (`!.claude/agent-memory/`), which never match the FILE itself — the file's winning record is the
# bare `::` "no pattern" case, rc 1, right answer for the wrong reason. It surfaced the moment a
# store was re-included by a FILE pattern (the findings ledger's `!…/results.jsonl`), which reported
# a correctly-committable file as `ignored`. So the ignore verdict now comes from `-q`, which is the
# authoritative form and is what `setup-memory.sh`'s own `ignore_status()` uses; `--verbose -n` is
# used ONLY to print the winning rule in a failure message, never to decide anything.
#
# NEVER PASS `-q` ALONGSIDE `--verbose`. Git rejects the combination outright —
# `fatal: cannot have both --quiet and --verbose`, exit 128 — and 128 is neither 0 nor 1, so a
# naive `if git check-ignore --verbose -q …; then` reads the USAGE ERROR as "not ignored" and
# silently reports every path as committable. That false green was live in this very file during
# development: the working-negation assertion passed while probing nothing at all. Exit status is
# mapped explicitly below precisely so an error can never masquerade as a verdict.
ignore_is_in() {
  local r="$1" p="$2" rc
  git -C "$r" check-ignore -q -- "$p" >/dev/null 2>&1
  rc=$?
  case "$rc" in
    0) echo "ignored" ;;
    1) echo "committable" ;;
    *) echo "unknown" ;;
  esac
}

# ignore_is <path> → status for the REAL repo root.
ignore_is() { ignore_is_in "$REPO_ROOT" "$1"; }

assert_committable() {
  local p="$1" st
  st="$(ignore_is "$p")"
  if [ "$st" = "committable" ]; then
    ok "committable (as intended): $p"
  else
    no "$p is '$st' but MUST be committable — the negation did not re-include it. Winning rule: $(git -C "$REPO_ROOT" check-ignore --verbose -n -- "$p" 2>/dev/null | head -n1)"
  fi
}

assert_ignored() {
  local p="$1" st
  st="$(ignore_is "$p")"
  if [ "$st" = "ignored" ]; then
    ok "still ignored (as intended): $p"
  else
    no "$p is '$st' but MUST stay ignored — the re-include is over-broad and would publish it."
  fi
}

# =============================================================================
# (A) THE SWEEP — explicit file list across BOTH committed stores
# =============================================================================
# The two dot-prefixed sidecars are named explicitly and FIRST, because they are the two paths a
# glob-based sweep drops silently.
EXPLICIT_SIDECARS='.supervisor/memory/.provenance.jsonl
.supervisor/memory/.lessons-provenance.jsonl'

EXPLICIT_STORE_ROOTS='.claude/agent-memory
.supervisor/memory'

# Full sweep list = the two explicitly-named sidecars, plus every regular file under the two store
# roots (`find -type f` DOES descend into dot-prefixed names, unlike a shell glob), de-duplicated.
SWEEP_LIST="$(
  {
    printf '%s\n' "$EXPLICIT_SIDECARS"
    while IFS= read -r d; do
      [ -n "$d" ] || continue
      [ -d "$REPO_ROOT/$d" ] && find "$d" -type f 2>/dev/null
    done <<EOF
$EXPLICIT_STORE_ROOTS
EOF
  } | awk 'NF && !seen[$0]++' | sort
)"

# Every explicitly-named sidecar must actually EXIST. A renamed/removed sidecar would otherwise
# make the sweep silently narrower while still reporting green.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if [ -f "$REPO_ROOT/$p" ]; then
    ok "explicitly-named sidecar present and swept: $p"
  else
    no "explicitly-named sidecar MISSING: $p — the sweep is narrower than it claims to be."
  fi
done <<EOF
$EXPLICIT_SIDECARS
EOF

# Completeness: the swept set must cover every file on disk under both stores. This is what keeps
# an "explicit list" from going stale as memory entries are added.
DISK_LIST="$(
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    [ -d "$REPO_ROOT/$d" ] && find "$d" -type f 2>/dev/null
  done <<EOF
$EXPLICIT_STORE_ROOTS
EOF
)"
UNSWEPT="$(printf '%s\n' "$DISK_LIST" | sort | comm -23 - <(printf '%s\n' "$SWEEP_LIST"))"
if [ -z "$UNSWEPT" ]; then
  ok "sweep covers every file on disk under both stores ($(printf '%s\n' "$SWEEP_LIST" | awk 'NF' | wc -l | tr -d ' ') files)"
else
  no "these committed-store files are NOT in the sweep list: $(printf '%s' "$UNSWEPT" | tr '\n' ' ')"
fi

# bash-3.2-safe expansion of the newline-separated list into positional args.
_oldIFS="$IFS"
IFS='
'
# shellcheck disable=SC2086
set -- $SWEEP_LIST
IFS="$_oldIFS"

if assert_no_foreign_terms "committed Twin stores" "$@"; then
  ok "no foreign terms (/$DENY_TERMS/, whole-word, case-insensitive) across both committed stores"
else
  no "FOREIGN TERMS FOUND in the committed Twin stores — this repo is PUBLIC; do NOT push. Redact (do not delete) the citation, keeping the finding intact."
fi

# =============================================================================
# (B) POSITIVE CONTROL — "GitHub" must NOT trip the sweep
# =============================================================================
GH_FIXTURE="$TMPD/github-control.md"
cat > "$GH_FIXTURE" <<'GHEOF'
GitHub Actions billing blocks are per-ACCOUNT — check the owner, not the repo.
See https://github.com/owner/repo/pull/1 and the GitHub CLI (`gh`).
Github, GITHUB, github — every casing of the legitimate word.
GHEOF
if assert_no_foreign_terms "github positive control" "$GH_FIXTURE"; then
  ok "positive control: 'GitHub'/'github.com'/'GITHUB' do NOT match \\bhub\\b (whole-word matching works)"
else
  no "positive control BROKE: the sweep matches 'hub' inside 'GitHub'. Whole-word (-w) matching is not in effect; the sweep would be red on every run and would get deleted."
fi

# =============================================================================
# (C) NEGATIVE CONTROL — the sweep must actually FAIL on a re-added citation
# =============================================================================
# A test that only ever passes is worthless here: two previous audits returned a false clean on
# this exact file. So inject the real contamination shape into a COPY and prove red, then green.
CONTAM_SRC=".claude/agent-memory/loomwright-loomwright-code-reviewer/project_self_heal_rubber_stamp.md"
CONTAM_FIXTURE="$TMPD/contaminated.md"
if [ -f "$REPO_ROOT/$CONTAM_SRC" ]; then
  cp "$REPO_ROOT/$CONTAM_SRC" "$CONTAM_FIXTURE"
else
  printf 'placeholder body\n' > "$CONTAM_FIXTURE"
fi

# Clean copy first — establishes the baseline is green before we contaminate it.
if assert_no_foreign_terms "pre-injection baseline" "$CONTAM_FIXTURE"; then
  ok "negative control: the un-contaminated copy of the redacted entry sweeps clean"
else
  no "negative control setup: the copy is already contaminated before injection — the real file still carries a foreign term."
fi

# Inject the EXACT historical shape: uppercase, no slash, a space before the '#'.
printf 'Across 8 recent session_end records (HUB #146/#129/#133/#139 + this repo #24) …\n' >> "$CONTAM_FIXTURE"
if assert_no_foreign_terms "post-injection" "$CONTAM_FIXTURE" >/dev/null 2>&1; then
  no "negative control DID NOT FIRE: a re-added 'HUB #146' citation swept clean. This guard cannot fail and is therefore not a guard."
else
  ok "negative control: a re-added 'HUB #146' citation makes the sweep FAIL (red)"
fi

# And a second foreign shape — the org name, lowercase, slash-joined.
VENDSY_FIXTURE="$TMPD/vendsy.md"
printf 'a record attributed to vendsy/hub slipped in\n' > "$VENDSY_FIXTURE"
if assert_no_foreign_terms "vendsy shape" "$VENDSY_FIXTURE" >/dev/null 2>&1; then
  no "negative control DID NOT FIRE for the 'vendsy/hub' org shape."
else
  ok "negative control: a 'vendsy/hub' org citation makes the sweep FAIL (red)"
fi

# Remove the injected line — the sweep must go green again (proves it keys on the citation, not
# on some incidental property of the fixture).
if [ -f "$REPO_ROOT/$CONTAM_SRC" ]; then
  cp "$REPO_ROOT/$CONTAM_SRC" "$CONTAM_FIXTURE"
else
  printf 'placeholder body\n' > "$CONTAM_FIXTURE"
fi
if assert_no_foreign_terms "post-removal" "$CONTAM_FIXTURE"; then
  ok "negative control: removing the citation makes the sweep PASS again (green↔red both proven)"
else
  no "negative control: the sweep stayed red after the citation was removed — it is keying on something else."
fi

# =============================================================================
# (D) IGNORE STATUS — intended paths committable, unintended paths still ignored
# =============================================================================
# INTENDED. The two dot-prefixed sidecars are asserted INDIVIDUALLY, not as part of a `**` case:
# a dotfile inside a re-included directory is its own silent-failure class.
#
# `.supervisor/postmortem/results.jsonl` MOVED HERE from the `assert_ignored` list below. The
# deferral comment that used to sit above it said the ledger "must STAY ignored until a later item
# filters it behind an explicit consent surface" — THIS IS THAT LATER ITEM. The ledger is now the
# THIRD managed store: `setup-memory.sh apply` un-ignores it, but only behind a fail-closed gate that
# refuses while any record's `.repo` sits outside the repo allowlist (`gated` verdict, offending
# slugs named, exit still 0). The 7 `vendsy/hub` records that made the deferral necessary were
# filtered out of the committed ledger in the same change, and `test-setup-memory.sh` groups (l)/(m)
# pin the gate itself. The consent surface is `print_consent_disclosure()`, relayed verbatim by
# `commands/setup.md`.
while IFS= read -r p; do
  [ -n "$p" ] || continue
  assert_committable "$p"
done <<'EOF'
.claude/agent-memory/loomwright-loomwright-code-reviewer/MEMORY.md
.claude/agent-memory/loomwright-loomwright-qa-executor/MEMORY.md
.claude/agent-memory/loomwright-loomwright-red-team-reviewer/MEMORY.md
.supervisor/memory/LESSONS.md
.supervisor/memory/PROJECT_MEMORY.md
.supervisor/memory/.provenance.jsonl
.supervisor/memory/.lessons-provenance.jsonl
.supervisor/postmortem/results.jsonl
EOF

# THE COMMITTED LEDGER CARRIES ZERO FOREIGN RECORDS — asserted with jq, NEVER grep. This ledger
# mixes compact (`"repo":"x"`) and spaced (`"repo": "x"`) JSON, so a compact-form grep silently
# under-counts and a foreign record appended in the spaced form would evade it entirely.
LEDGER_PATH=".supervisor/postmortem/results.jsonl"
if ! command -v jq >/dev/null 2>&1; then
  ok "jq unavailable — the committed-ledger census is skipped (this is a static gate, not a fail)"
elif [ ! -f "$REPO_ROOT/$LEDGER_PATH" ]; then
  ok "no findings ledger present — nothing to census"
else
  # THE EXPECTED SLUGS ARE DECLARED HERE, IN COMMITTED CODE — deliberately NOT read from
  # `setup-memory.sh allowlist`. That resolver reads `.supervisor/config.json`, which is GITIGNORED
  # (`.gitignore` excludes `.supervisor/*`; the managed block re-includes the memory stores and the
  # ledger, never the config). So the allowlist DOES NOT TRAVEL with the repo: on any fresh clone —
  # and in CI — it falls back to the live git remote ALONE, one entry, and every pre-rename
  # `vikashruhilgit/ai-agent-manager` record in the committed ledger is then judged FOREIGN.
  #
  # That is not hypothetical: this exact census passed on the author's machine (2-entry config) and
  # failed in CI (1-entry remote default) on the very commit that introduced it. A gate asserting a
  # property of COMMITTED data must take its expectation from COMMITTED source, or it asserts a
  # property of whoever happens to run it.
  #
  # Both slugs are legitimate and BOTH must stay: the repo was renamed ai-agent-manager -> loomwright,
  # and records written before the rename carry the old slug. Dropping it would not "clean" the
  # ledger, it would discard the larger, older half of this repo's own history — which is precisely
  # why setup-memory.sh stores the allowlist as a LIST and warns that a rename needs the old slug
  # added by hand.
  OWNED_SLUGS='vikashruhilgit/loomwright
vikashruhilgit/ai-agent-manager'
  ALLOW_JSON="$(printf '%s\n' "$OWNED_SLUGS" | jq -R . | jq -s .)"
  N_ALLOW="$(printf '%s' "$ALLOW_JSON" | jq 'length' 2>/dev/null || echo 0)"
  if [ "${N_ALLOW:-0}" -gt 0 ]; then
    ok "the committed owned-slug list resolves to $N_ALLOW entries (declared in this file, NOT read from the gitignored config — an empty list would make the census below vacuous)"
  else
    no "the committed owned-slug list resolved to NOTHING — the foreign-record census below would be meaningless"
  fi
  # Cross-check, advisory: report when the machine-local allowlist disagrees with the committed
  # expectation. NOT a failure — a contributor's config is theirs — but a silent divergence here is
  # what made the CI break confusing, so name it.
  LOCAL_ALLOW="$(bash "$SETUP_MEMORY" --root "$REPO_ROOT" allowlist 2>/dev/null | sort | tr '\n' ' ')"
  EXPECT_ALLOW="$(printf '%s\n' "$OWNED_SLUGS" | sort | tr '\n' ' ')"
  if [ "$LOCAL_ALLOW" = "$EXPECT_ALLOW" ]; then
    ok "the machine-local allowlist matches the committed owned-slug list"
  else
    ok "note (not a failure): the machine-local allowlist [$LOCAL_ALLOW] differs from the committed owned-slug list [$EXPECT_ALLOW]; the census uses the committed list"
  fi
  FOREIGN="$(jq -r --argjson allow "$ALLOW_JSON" \
    '((.repo // "") | tostring) as $r | select(($allow | index($r)) == null) | (if $r == "" then "(no .repo field)" else $r end)' \
    "$REPO_ROOT/$LEDGER_PATH" 2>/dev/null | sort -u | tr '\n' ' ')"
  if [ -z "${FOREIGN// /}" ]; then
    ok "the COMMITTED findings ledger holds ZERO records outside the allowlist ($(jq -s 'length' "$REPO_ROOT/$LEDGER_PATH" 2>/dev/null) records, counted with jq)"
  else
    no "the COMMITTED findings ledger holds FOREIGN records — this repo is PUBLIC; do NOT push. Offending slugs: $FOREIGN. Filter with: bash loomwright/scripts/setup-memory.sh filter-ledger --ledger $LEDGER_PATH"
  fi
  # NEGATIVE CONTROL — a SPACED-FORM foreign record must make that census FAIL. Injected into a COPY
  # (never the real ledger), because a census that can only ever pass is not a census.
  LEDGER_FIXTURE="$TMPD/ledger-contaminated.jsonl"
  cp "$REPO_ROOT/$LEDGER_PATH" "$LEDGER_FIXTURE"
  printf '{"schema_version": 1, "repo": "vendsy/hub", "number": 999}\n' >> "$LEDGER_FIXTURE"
  INJ="$(jq -r --argjson allow "$ALLOW_JSON" \
    '((.repo // "") | tostring) as $r | select(($allow | index($r)) == null) | $r' \
    "$LEDGER_FIXTURE" 2>/dev/null | sort -u | tr '\n' ' ')"
  case "$INJ" in
    *vendsy/hub*) ok "negative control: a SPACED-FORM 'vendsy/hub' record injected into a copy makes the census FAIL (red↔green both proven)" ;;
    *)            no "negative control DID NOT FIRE: an injected spaced-form foreign record swept clean. This census cannot fail and is therefore not a census." ;;
  esac
fi

# UNINTENDED. `.supervisor/postmortem/` keeps entries here for its NON-ledger contents: the managed
# block re-includes exactly ONE file in that directory, so a sibling artifact must still be ignored.
# (Non-goal, stated so the omission is a decision: the gate keys on each record's `.repo` ONLY.
# EXPLICIT_STORE_ROOTS is deliberately NOT widened to `.supervisor/postmortem`, so a record whose
# `.repo` is allowlisted but whose finding TEXT cites a foreign org is NOT caught here. Widening the
# content sweep to the ledger is its own item.)
while IFS= read -r p; do
  [ -n "$p" ] || continue
  assert_ignored "$p"
done <<'EOF'
.claude/worktrees/busy-darwin/README.md
.claude/settings.local.json
.supervisor/logs/session.jsonl
.supervisor/jobs/pending/some-brief.md
.supervisor/automate/some-run.json
.supervisor/requirements/twin-loop/some-item.md
.supervisor/postmortem/some-other-artifact.json
EOF

# The predictable `apply` artifacts must be ignored too — `apply` ALWAYS writes them, no
# pre-existing pattern matched them, and `git add -A` would otherwise stage them.
assert_ignored ".gitignore.backup.20260101-000000"
assert_ignored ".supervisor/config.json.backup.20260101-000000"

# =============================================================================
# (E) THE NAIVE NEGATION IS A PROVEN-FAILING NEGATIVE CONTROL
# =============================================================================
# Git cannot re-include a file whose PARENT DIRECTORY is excluded. `.claude/` + `!.claude/agent-memory/`
# looks right and does NOTHING. This is pinned as an executed failure rather than a comment,
# because a comment cannot notice when git's behaviour changes.
NAIVE_FIXTURE="$TMPD/naive"
mkdir -p "$NAIVE_FIXTURE/.claude/agent-memory"
(
  cd "$NAIVE_FIXTURE" || exit 1
  git init -q . 2>/dev/null
  printf 'entry\n' > .claude/agent-memory/MEMORY.md
) >/dev/null 2>&1

printf '.claude/\n!.claude/agent-memory/\n' > "$NAIVE_FIXTURE/.gitignore"
_naive="$(ignore_is_in "$NAIVE_FIXTURE" .claude/agent-memory/MEMORY.md)"
if [ "$_naive" = "ignored" ]; then
  ok "naive form ('.claude/' + '!.claude/agent-memory/') PROVEN FAILING — the file is still ignored"
else
  no "naive form probed as '$_naive', expected 'ignored'. If 'committable', git's precedence changed and the managed block's form must be re-derived; if 'unknown', this probe errored and proved nothing."
fi

printf '.claude/*\n!.claude/agent-memory/\n' > "$NAIVE_FIXTURE/.gitignore"
_working="$(ignore_is_in "$NAIVE_FIXTURE" .claude/agent-memory/MEMORY.md)"
if [ "$_working" = "committable" ]; then
  ok "working form ('.claude/*' + '!.claude/agent-memory/') re-includes the file — contents excluded, directory traversable"
else
  no "working form probed as '$_working', expected 'committable' — the shipped managed block's negation does not re-include the file."
fi

# =============================================================================
# (F) WRITE CONTAINMENT — apply/remove exercised ONLY against a fixture
# =============================================================================
APPLY_FIXTURE="$TMPD/applyrepo"
mkdir -p "$APPLY_FIXTURE/.claude/agent-memory" "$APPLY_FIXTURE/.supervisor/memory"
(
  cd "$APPLY_FIXTURE" || exit 1
  git init -q . 2>/dev/null
  printf '.claude/\n.supervisor/\n' > .gitignore
  printf 'entry\n' > .claude/agent-memory/MEMORY.md
  printf 'lesson\n' > .supervisor/memory/LESSONS.md
  printf 'prov\n' > .supervisor/memory/.provenance.jsonl
) >/dev/null 2>&1

if [ -x "$SETUP_MEMORY" ] || [ -f "$SETUP_MEMORY" ]; then
  APPLY_OUT="$(bash "$SETUP_MEMORY" --root "$APPLY_FIXTURE" apply 2>&1)"
  case "$APPLY_OUT" in
    *"Memory readiness: configured"*)
      ok "fixture apply reaches 'configured' (capability consumed as shipped, against --root)" ;;
    *)
      no "fixture apply did not reach 'configured' — output tail: $(printf '%s' "$APPLY_OUT" | tail -n 3 | tr '\n' ' ')" ;;
  esac

  # The dot-prefixed sidecar must be committable in the fixture too.
  _fx="$(ignore_is_in "$APPLY_FIXTURE" .supervisor/memory/.provenance.jsonl)"
  if [ "$_fx" = "committable" ]; then
    ok "fixture: dot-prefixed sidecar is committable after apply"
  else
    no "fixture: .supervisor/memory/.provenance.jsonl probed as '$_fx' after apply, expected 'committable'"
  fi

  REMOVE_OUT="$(bash "$SETUP_MEMORY" --root "$APPLY_FIXTURE" remove 2>&1)"
  case "$REMOVE_OUT" in
    *"remove: removed"*) ok "fixture remove reverts the managed block" ;;
    *)                   no "fixture remove did not report removal — tail: $(printf '%s' "$REMOVE_OUT" | tail -n 3 | tr '\n' ' ')" ;;
  esac
else
  no "setup-memory.sh not found at $SETUP_MEMORY — cannot exercise apply/remove in a fixture"
fi

# ZERO WRITES UNDER THE REAL REPO ROOT. Asserted, not assumed.
AFTER_GITIGNORE_CKSUM="$(cksum < "$REPO_ROOT/.gitignore" 2>/dev/null || echo missing)"
if [ "$BASELINE_GITIGNORE_CKSUM" = "$AFTER_GITIGNORE_CKSUM" ]; then
  ok "write containment: the real .gitignore is byte-identical after this test ran"
else
  no "write containment BROKEN: this test modified the real $REPO_ROOT/.gitignore"
fi

STRAY="$(find "$REPO_ROOT" -maxdepth 1 -name '.gitignore.backup.*' 2>/dev/null)"
if [ -z "$STRAY" ]; then
  ok "write containment: no .gitignore.backup.* artifact at the real repo root"
else
  no "write containment BROKEN: backup artifact(s) at the real repo root: $(printf '%s' "$STRAY" | tr '\n' ' ')"
fi

echo "----"
echo "test-committed-twin-scrub: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
