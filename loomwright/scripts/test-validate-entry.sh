#!/usr/bin/env bash
# test-validate-entry.sh — self-tests for the shared write-time validator.
#
# Runs entirely in temp dirs and against the repo's own read-only files. It NEVER writes to
# .supervisor/config.json, and section 12 asserts that by hashing the live config before and after
# the whole run — a fixture that moved the live allowlist would let `setup-memory.sh apply` judge
# foreign ledger records clean and publish another repo's churn analysis from this PUBLIC repo.
# Every fixture that needs a different allowlist supplies it through
# $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST in the test's OWN environment, or a `--root` fixture repo.
#
# Covers:
#    1. contract + load guard — the sentinel is the LAST line, a truncated copy defines SOME
#       validators but NO sentinel, an unparseable copy returns non-zero without killing the
#       caller, and sourcing does not mutate the caller's shell options
#    2. duplicate
#    3. contradiction
#    4. provenance
#    5. dead-reference, including AC6's `jq has()` key-PRESENCE discipline (missing key != null)
#    6. cross-repo — AC3 (foreign short name REFUSED), AC4 (own repo PASSES) and the false-positive
#       guards that keep ordinary prose writable (`PR #146`, `and/or`, 3-segment paths)
#    7. cross-repo blind spot (AC4) — an unrecognised shape passes undetected, pinned by test, and
#       the refusal message says so rather than claiming complete coverage
#    8. AC4c — an allowlist that CANNOT be resolved is a refusal naming the unresolved allowlist,
#       neither a silent pass-everything nor a silent refuse-everything
#    9. delegation — the allowlist comes from `setup-memory.sh allowlist` and NOT from a second
#       parser of $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST inside validate-entry.sh (proven behaviourally
#       with a stub resolver that disagrees with the env var, and statically)
#   10. one list, two consumers — moving the list once moves BOTH the resolver's output and the
#       cross-repo verdict (AC5's full form, incl. the ledger negative control, is subtask 3's)
#   11. MUTATION CONTROLS (AC4b, and R3 for every check) — each check is proven to be doing the
#       work its assertions credit it with. A guard this repo has not mutated is a guard it has
#       not tested; several shipped guards here were vacuous until someone mutated them.
#   12. no live state is touched
#   13. executable dispatch + verdict-code convention
#
# Exit 0 = all pass, 1 = any failure.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VE="$HERE/validate-entry.sh"
PLUGIN_ROOT="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
# Pin the plugin root for every invocation so the resolver lookup is deterministic and does not
# depend on the cwd the suite happens to run from. Section 1 separately covers the unset case.
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"

# The allowlist every fixture pins, unless it is deliberately varying it. Declared in COMMITTED
# test source, never derived by calling the resolver: a gate that takes its expectation from the
# machine it runs on asserts a property of whoever runs it. `vikashruhilgit/loomwright` is the
# value that resolves on a fresh clone and in CI (the git-remote default), which is also why AC4's
# positive token is `loomwright` and never `ai-agent-manager`.
OURS="vikashruhilgit/loomwright"
# A deliberately FOREIGN slug, used only inside this suite's own environment. Never written to any
# config, never added to the live allowlist.
FOREIGN="vendsy/hub"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TMP="$(mktemp -d)"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null; rm -rf "$TMP" 2>/dev/null' EXIT

# Snapshot the live config up front (section 12 re-checks it at the end).
LIVE_CFG="$REPO_ROOT/.supervisor/config.json"
if [ -f "$LIVE_CFG" ]; then LIVE_CFG_BEFORE="$(cksum < "$LIVE_CFG")"; else LIVE_CFG_BEFORE="ABSENT"; fi
# Same for the live curated stores, which section 11b READS. A validator suite that mutated the
# real memory it replays would be the "never write to live state" rule broken by the very test
# written to protect it.
LIVE_STORES_BEFORE="$(cksum < "$REPO_ROOT/.supervisor/memory/LESSONS.md" 2>/dev/null)|$(cksum < "$REPO_ROOT/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"

# vrc <script> <check> <args...> -> prints nothing, sets VRC to the verdict code.
vrc() { local s="$1"; shift; bash "$s" "$@" >"$TMP/out.txt" 2>"$TMP/err.txt"; VRC=$?; return 0; }
# verdict <want> <desc> <script> <check> <args...>
verdict() {
  local want="$1" desc="$2"; shift 2
  vrc "$@"
  if [ "$VRC" -eq "$want" ]; then ok "$desc (rc=$VRC)"; else no "$desc — got rc=$VRC, wanted $want"; fi
}
# reason <token> <desc> — asserts the last run named <token> on stderr.
reason() {
  if grep -qF "$1" "$TMP/err.txt" 2>/dev/null; then ok "$2"; else no "$2 — '$1' not on stderr"; fi
}

echo "== 1. contract + load guard =="
verdict 0 "contract subcommand prints the sentinel value" "$VE" contract
grep -qx 'validate-entry/1' "$TMP/out.txt" && ok "contract value is validate-entry/1" \
  || no "contract value is not validate-entry/1"

# The sentinel MUST be the last line: that is the whole reason clause (iii) of the load guard can
# detect a truncated helper.
LAST="$(awk 'NF{l=$0} END{print l}' "$VE")"
[ "$LAST" = 'VALIDATE_ENTRY_CONTRACT="validate-entry/1"' ] \
  && ok "sentinel assignment is the last non-empty line of validate-entry.sh" \
  || no "sentinel is NOT the last line (found: $LAST) — a truncated helper could still match it"

# Sourcing a HEALTHY helper defines all five validators and the sentinel.
bash -c '
  set -uo pipefail
  before="$-"
  . "$1" || exit 9
  [ "${VALIDATE_ENTRY_CONTRACT:-}" = "validate-entry/1" ] || exit 10
  for f in $VALIDATE_ENTRY_FUNCTIONS; do command -v "$f" >/dev/null 2>&1 || exit 11; done
  [ "$before" = "$-" ] || exit 12
  exit 0
' _ "$VE"
case $? in
  0)  ok "sourcing defines all five validators + the sentinel and leaves shell options unchanged" ;;
  10) no "sourcing did not set VALIDATE_ENTRY_CONTRACT" ;;
  11) no "sourcing did not define all five validators" ;;
  12) no "sourcing MUTATED the caller's shell options" ;;
  *)  no "sourcing the healthy helper failed outright" ;;
esac

# TRUNCATED copy: the danger is real (some validators ARE defined) and the sentinel is absent.
# Truncating mid-function leaves an unterminated construct, so bash aborts the parse — exactly the
# state a `command -v <one function>` guard would misread as a healthy load.
TRUNC_AT="$(grep -nF 'validate_dead_reference() {' "$VE" | head -1 | cut -d: -f1)"
awk -v n="$((TRUNC_AT + 3))" 'NR <= n' "$VE" > "$TMP/truncated.sh"
bash -c '
  . "$1" 2>/dev/null
  src_rc=$?
  defined=0
  for f in validate_duplicate validate_contradiction validate_provenance; do
    command -v "$f" >/dev/null 2>&1 && defined=$((defined+1))
  done
  [ -n "${VALIDATE_ENTRY_CONTRACT:-}" ] && exit 20   # sentinel survived truncation — guard is useless
  [ "$defined" -gt 0 ] || exit 21                    # nothing partially defined — test proves nothing
  [ "$src_rc" -ne 0 ] || exit 22                     # source must report failure
  exit 0
' _ "$TMP/truncated.sh"
case $? in
  0)  ok "a truncated helper leaves SOME validators defined but NO sentinel, and source reports non-zero" ;;
  20) no "the sentinel survived truncation — clause (iii) of the load guard cannot detect it" ;;
  21) no "truncation defined nothing at all — this fixture proves nothing, move the cut point" ;;
  22) no "sourcing a truncated helper returned 0" ;;
  *)  no "the truncation fixture did not run" ;;
esac

# Sourcing an UNPARSEABLE copy must return non-zero WITHOUT killing the caller.
{ cat "$VE"; printf 'if [ then\n'; } > "$TMP/unparseable.sh"
bash -c '. "$1" 2>/dev/null; rc=$?; [ "$rc" -ne 0 ] && echo ALIVE' _ "$TMP/unparseable.sh" >"$TMP/o" 2>/dev/null
grep -qx ALIVE "$TMP/o" && ok "sourcing an unparseable helper returns non-zero and the caller survives" \
  || no "sourcing an unparseable helper killed the caller or returned 0"

# Resolver lookup falls back to a SIBLING setup-memory.sh when CLAUDE_PLUGIN_ROOT is unset.
mkdir -p "$TMP/sibling"
cp "$VE" "$TMP/sibling/validate-entry.sh"
cat > "$TMP/sibling/setup-memory.sh" <<'STUB'
#!/usr/bin/env bash
echo "siblingorg/siblingrepo"
exit 0
STUB
( unset CLAUDE_PLUGIN_ROOT VALIDATE_ENTRY_SETUP_MEMORY
  bash "$TMP/sibling/validate-entry.sh" cross-repo --entry "see siblingorg/siblingrepo" ) >/dev/null 2>&1
[ $? -eq 0 ] && ok "with CLAUDE_PLUGIN_ROOT unset the resolver falls back to a sibling setup-memory.sh" \
  || no "sibling-dir resolver fallback did not work"

echo "== 2. duplicate =="
STORE="$TMP/store.md"
printf '# Project Lessons\n\n## auth\n- [abcd1234] the token cache is refreshed on every request  <!-- last_verified=2026-01-01T00:00:00Z -->\n- [beef0001] workers run inside linked git worktrees\n' > "$STORE"
verdict 1 "AC1-class: a reworded near-identical entry is REFUSED" \
  "$VE" duplicate --entry "on every request the token cache is refreshed" --store "$STORE"
reason "REFUSE_DUPLICATE" "the duplicate refusal names its check"
verdict 0 "a genuinely new entry passes" \
  "$VE" duplicate --entry "the plan reviewer gates the brief save before it is written" --store "$STORE"
verdict 0 "an OPPOSITE-polarity entry is not reported as a duplicate (it is the contradiction check's)" \
  "$VE" duplicate --entry "the token cache is never refreshed on any request" --store "$STORE"
verdict 0 "an ABSENT store means no prior entries — a real clean verdict, not could-not-examine" \
  "$VE" duplicate --entry "some brand new fact about caching" --store "$TMP/no-such-store.md"
: > "$TMP/unreadable.md"; chmod 000 "$TMP/unreadable.md"
if [ -r "$TMP/unreadable.md" ]; then
  ok "SKIPPED unreadable-store case (running as a user that can read mode-000 files)"
else
  verdict 2 "a PRESENT but UNREADABLE store is could-not-examine (2), never clean" \
    "$VE" duplicate --entry "some brand new fact about caching" --store "$TMP/unreadable.md"
  reason "REFUSE_DUPLICATE_STORE_UNREADABLE" "the unreadable-store refusal names the reason"
fi
chmod 644 "$TMP/unreadable.md" 2>/dev/null
verdict 2 "a MISSING --store is could-not-examine (2), never clean" \
  "$VE" duplicate --entry "some brand new fact about caching"
reason "REFUSE_DUPLICATE_NO_STORE" "the missing-store refusal names the reason"

echo "== 3. contradiction =="
verdict 1 "an opposite-polarity entry about the same subject is REFUSED" \
  "$VE" contradiction --entry "the token cache is never refreshed on any request" --store "$STORE"
reason "REFUSE_CONTRADICTION" "the contradiction refusal names its check"
reason "supersede it explicitly" "the contradiction refusal proposes supersede rather than a silent append"
verdict 0 "an unrelated negative statement does not trip the contradiction check" \
  "$VE" contradiction --entry "the plan reviewer does not gate the release surface" --store "$STORE"
verdict 2 "contradiction with a MISSING --store is could-not-examine (2)" \
  "$VE" contradiction --entry "anything at all here"
# Flag, never delete: section 12 re-checks this against every refusal the suite has made.
STORE_CK="$(cksum < "$STORE")"

echo "== 4. provenance =="
verdict 1 "an entry citing nothing that motivated it is REFUSED" \
  "$VE" provenance --entry "the cache is refreshed eagerly"
reason "REFUSE_PROVENANCE" "the provenance refusal names its check"
verdict 1 "a PLACEHOLDER --source (unknown) does not satisfy provenance" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source unknown
verdict 0 "a real --source satisfies provenance" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source "pr-138"
verdict 0 "a PR/issue number in the entry text satisfies provenance" \
  "$VE" provenance --entry "the cache is refreshed eagerly, see #138"
verdict 2 "provenance with no --entry at all is could-not-examine (2)" \
  "$VE" provenance --source "pr-138"

# AC17: strictness lives HERE, so all six writers inherit it. A source qualifies only when it
# carries a real reference; "any non-placeholder string" is the option decision (f) rejected.
verdict 1 "AC17: a bare command name (--source dreaming) does NOT satisfy provenance" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source "dreaming"
reason "REFUSE_PROVENANCE" "AC17: the bare-command-name refusal names the provenance check"
verdict 0 "AC17: --source 'dreaming:<session_id>' carries a real reference and PASSES" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source "dreaming:20260810T1200"
verdict 0 "AC17: a commit sha as --source PASSES" \
  "$VE" provenance --entry "the cache is refreshed eagerly" --source "c6bfda6"
verdict 0 "AC17: a bare command-name source still passes when the ENTRY itself cites the finding" \
  "$VE" provenance --entry "the cache is refreshed eagerly, see #138" --source "dreaming"

echo "== 5. dead reference =="
verdict 0 "an entry citing a path that still resolves passes" \
  "$VE" dead-reference --entry "the sole writer is loomwright/scripts/write-lessons.sh" --root "$REPO_ROOT"
# The `file:N` in the next fixture is FIXTURE INPUT, not a prose citation — it exists to prove
# that a real path carrying a line suffix still resolves. The citation-drift ratchet cannot tell
# the two apart, so it is pinned like any live citation. If the anchor moves, update the fixture
# rather than dropping the pin. NOTE: the pin must sit on the citation's own line (or the one
# after it) — a pin placed ABOVE is not seen, and a comment inside a `\`-continuation silently
# breaks the argument list, which is how this fixture was broken once already.
verdict 0 "a bare CLAUDE.md and a :N line citation both resolve" \
  "$VE" dead-reference --entry "see CLAUDE.md and loomwright/scripts/setup-memory.sh:128" --root "$REPO_ROOT"  # [pins: `robust to header edits`]
verdict 1 "an entry citing a path that no longer resolves is REFUSED" \
  "$VE" dead-reference --entry "the guard lives in loomwright/scripts/long-gone.sh" --root "$REPO_ROOT"
reason "REFUSE_DEAD_REFERENCE" "the dead-reference refusal names its check"
verdict 0 "a URL is not treated as a repo path" \
  "$VE" dead-reference --entry "see https://example.com/nope/missing.md" --root "$REPO_ROOT"
verdict 0 "backticks and trailing punctuation are stripped before resolution" \
  "$VE" dead-reference --entry "read \`loomwright/scripts/read-lessons.sh\`, then stop." --root "$REPO_ROOT"
verdict 2 "an unusable --root is could-not-examine (2), never clean" \
  "$VE" dead-reference --entry "loomwright/scripts/write-lessons.sh" --root "$TMP/no-such-root"
reason "REFUSE_DEAD_REFERENCE_ROOT_MISSING" "the unusable-root refusal names the reason"

echo "== 5a. AC16: resolve against the REPO, and SKIP what is unresolvable BY SHAPE =="
# A bare filename that lives in a subdirectory is a REAL file; resolving only against the repo root
# refused nine live curated entries for citing files that exist.
verdict 0 "AC16: a bare filename that lives under loomwright/scripts/ resolves (not just repo-root)" \
  "$VE" dead-reference --entry "a green check-doc-currency.sh is necessary but not sufficient" --root "$REPO_ROOT"
verdict 0 "AC16: two more real-but-not-at-root filenames resolve (send-webhook.sh, test-telemetry.sh)" \
  "$VE" dead-reference --entry "the send-webhook.sh emitter and test-telemetry.sh goldens" --root "$REPO_ROOT"
verdict 1 "a bare filename that exists NOWHERE in the repo is still REFUSED — the suffix match did not blanket-pass" \
  "$VE" dead-reference --entry "the guard lives in long-gone-nowhere.sh" --root "$REPO_ROOT"
# SKIP vs REFUSE. These name no single file, so "does it still resolve" is not a question about
# them: not examined, not a verdict. This is NOT decision (b) relaxed — an unusable --root above
# still refuses with 2.
verdict 0 "AC16: a GLOB ('test-*.sh') is unresolvable BY SHAPE and is SKIPPED, not refused" \
  "$VE" dead-reference --entry "eleven test-*.sh suites run in CI" --root "$REPO_ROOT"
verdict 0 "AC16: a tilde path ('~/.claude/settings.json') is unresolvable BY SHAPE and is SKIPPED" \
  "$VE" dead-reference --entry "it is set =1 in this repo's ~/.claude/settings.json" --root "$REPO_ROOT"
verdict 0 "AC16: a <placeholder> and a \$VAR-bearing path are SKIPPED for the same reason" \
  "$VE" dead-reference --entry "see <agent-name>.md and \$HOME/never-there.sh" --root "$REPO_ROOT"

echo "== 5b. AC6: nullable-but-required field asserts key PRESENCE via jq has() =="
if command -v jq >/dev/null 2>&1; then
  verdict 1 "a present string field citing a dead path is REFUSED" \
    "$VE" dead-reference --json '{"path":"loomwright/scripts/long-gone.sh"}' --field path --root "$REPO_ROOT"
  verdict 0 "a present string field citing a live path passes" \
    "$VE" dead-reference --json '{"path":"loomwright/scripts/write-lessons.sh"}' --field path --root "$REPO_ROOT"
  verdict 0 "an EXPLICIT null is valid — the field is nullable, so nothing is cited" \
    "$VE" dead-reference --json '{"path":null}' --field path --root "$REPO_ROOT"
  verdict 2 "a MISSING key does NOT pass as valid — it is could-not-examine (2), distinct from null" \
    "$VE" dead-reference --json '{"other":"x"}' --field path --root "$REPO_ROOT"
  reason "REFUSE_DEAD_REFERENCE_FIELD_ABSENT" "the missing-key refusal names the absent key"
  verdict 2 "unparseable JSON is could-not-examine (2)" \
    "$VE" dead-reference --json '{oops' --field path --root "$REPO_ROOT"
  verdict 2 "a non-object JSON record is could-not-examine (2)" \
    "$VE" dead-reference --json '[1,2]' --field path --root "$REPO_ROOT"
  # jq ABSENT is could-not-examine, never clean (decision (b)).
  mkdir -p "$TMP/nojq"
  for b in bash awk sed grep tr cut git printf cksum; do
    p="$(command -v "$b" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$TMP/nojq/$b" 2>/dev/null
  done
  ( PATH="$TMP/nojq" bash "$VE" dead-reference --json '{"path":null}' --field path --root "$REPO_ROOT" ) \
    >/dev/null 2>"$TMP/err.txt"
  rc=$?
  [ "$rc" -eq 2 ] && ok "an ABSENT jq is could-not-examine (2), never clean (rc=$rc)" \
    || no "an absent jq gave rc=$rc, wanted 2"
  reason "REFUSE_DEAD_REFERENCE_NO_JQ" "the absent-jq refusal names the reason"
else
  ok "SKIPPED AC6 jq cases (jq not installed on this host)"
fi

echo "== 6. cross-repo: AC3 refuses foreign, AC4 passes own =="
export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS"
verdict 1 "AC3: 'HUB #146' is REFUSED — a repo-shaped token NOT in the allowlist" \
  "$VE" cross-repo --entry "the same defect was fixed in HUB #146 last week"
reason "REFUSE_CROSS_REPO" "the cross-repo refusal names its check"
verdict 1 "a foreign owner/repo slug is REFUSED" \
  "$VE" cross-repo --entry "context lives in $FOREIGN"
verdict 1 "a github.com URL naming a foreign repo is REFUSED" \
  "$VE" cross-repo --entry "context lives in https://github.com/$FOREIGN for now"
verdict 0 "AC4: this repo's own slug PASSES — an entry may freely reference its own repo" \
  "$VE" cross-repo --entry "the guard landed in $OURS"
verdict 0 "AC4: the short name 'LOOMWRIGHT #146' PASSES (whole word, case-insensitive)" \
  "$VE" cross-repo --entry "the guard landed in LOOMWRIGHT #146"
# False-positive guards. A wrong refusal blocks a legitimate write, which is worse than a miss.
verdict 0 "'PR #146' is not read as a repository called pr" \
  "$VE" cross-repo --entry "fixed in PR #146"
verdict 0 "'fixed in #146' is not read as a repository called in" \
  "$VE" cross-repo --entry "fixed in #146"
verdict 0 "'and/or' is not read as an owner/repo slug" \
  "$VE" cross-repo --entry "the gate is advisory and/or read-only"
verdict 0 "a three-segment path is not read as an owner/repo slug" \
  "$VE" cross-repo --entry "the guard is in loomwright/scripts/read-rules.sh"
verdict 0 "a docs path with one slash is not read as an owner/repo slug" \
  "$VE" cross-repo --entry "recorded in docs/PITFALLS.md"

echo "== 6b. AC16: English prose pairs are not owner/repo slugs; a MARKED slug still is =="
# The exact six pairs that refused live curated entries. Asserted individually, not as one blob, so
# a regression names which pair came back.
for pair in "tests must parse YAML/JSON rather than hit live dependencies" \
            "the dev/CI shell may set it globally" \
            "the gate never scans budget/zone numbers" \
            "any user/PR-text -> JSON in a firing path must use jq --arg" \
            "the contrib image is distroless (no shell/wget)" \
            "fixtures are WORKER_RESULT/CODE_REVIEW_RESULT payloads only"; do
  verdict 0 "AC16: prose pair passes — \"$pair\"" "$VE" cross-repo --entry "$pair"
done
# ... and the recogniser did NOT go blind: every MARKED form of a foreign slug still refuses.
# A bare `owner/repo` is THE canonical foreign-repo citation, so the four markers below are what
# stop the false-positive fix from opening a bigger hole than it closed. Each marker gets its own
# assertion AND its own mutation control in section 11.
verdict 1 "a foreign slug after a cue word ('landed in vendsy/hub') is still REFUSED" \
  "$VE" cross-repo --entry "the same defect landed in $FOREIGN last week"
verdict 1 "marker (2), trailing: 'the vendsy/hub repo' is REFUSED — the cue can follow the slug" \
  "$VE" cross-repo --entry "the $FOREIGN repo has the same bug"
verdict 1 "marker (3): a KNOWN owner is recognised — 'vikashruhilgit/hub' is not in the allowlist and is REFUSED" \
  "$VE" cross-repo --entry "vikashruhilgit/hub has the same bug"
verdict 1 "marker (4): a hyphenated owner is slug-only structure — 'acme-corp/widget-svc' is REFUSED" \
  "$VE" cross-repo --entry "acme-corp/widget-svc has the same bug"
verdict 1 "marker (4): CamelCase is slug-only structure — 'octocat/Hello-World' is REFUSED" \
  "$VE" cross-repo --entry "octocat/Hello-World has the bug"
verdict 1 "marker (4): a digit is slug-only structure — 'octocat/repo2' is REFUSED" \
  "$VE" cross-repo --entry "octocat/repo2 has the bug"
verdict 1 "a foreign 'owner/repo#123' citation is still REFUSED (structural marker, no cue needed)" \
  "$VE" cross-repo --entry "fixed by $FOREIGN#12 yesterday"
verdict 1 "a foreign 'owner/repo.git' clone target is still REFUSED (structural marker)" \
  "$VE" cross-repo --entry "cloned $FOREIGN.git yesterday"
verdict 0 "AC16: the OWNER half must be a legal GitHub login — an underscore owner is never a slug" \
  "$VE" cross-repo --entry "the payloads live in worker_result/code_review_result"

echo "== 7. cross-repo blind spot (AC4) — stated, not hidden =="
verdict 0 "prose naming a repo in an unrecognised shape passes UNDETECTED ('the hub repository')" \
  "$VE" cross-repo --entry "the hub repository has the same bug"
verdict 0 "a plain lowercase 'hub #146' is also unrecognised (the deliberate under-recognition)" \
  "$VE" cross-repo --entry "landed in hub #146"
# THE RESIDUAL BOUND, pinned so it is a stated limitation rather than an unnoticed hole: an
# all-lowercase `word/word` with no cue beside it, no known owner and no slug structure cannot be
# told apart FROM THE TEXT ALONE from an English pair — `vendsy/hub` and `budget/zone` are the same
# shape. Refusing that shape would refuse six live curated entries, so it is a deliberate miss.
verdict 0 "RESIDUAL BOUND: a bare all-lowercase 'vendsy/hub' with no marker passes undetected — the same shape as 'budget/zone'" \
  "$VE" cross-repo --entry "$FOREIGN has the same bug"
verdict 0 "RESIDUAL BOUND control: the English pair it cannot be distinguished from passes for the SAME reason" \
  "$VE" cross-repo --entry "budget/zone has the same bug"
grep -qF "RESIDUAL BOUND" "$VE" && ok "validate-entry.sh states the residual bound in its header, not just in this test" \
  || no "validate-entry.sh header does not state the residual bound"
vrc "$VE" cross-repo --entry "the same defect was fixed in HUB #146"
if grep -qF "invisible to it" "$TMP/err.txt" && grep -qF "not proof" "$TMP/err.txt"; then
  ok "the refusal message states the coverage bound instead of claiming complete coverage"
else
  no "the refusal message does not state the coverage bound"
fi
grep -qF "COVERAGE BOUND" "$VE" && ok "validate-entry.sh documents the coverage bound in its header" \
  || no "validate-entry.sh header does not document the coverage bound"

echo "== 8. AC4c: an allowlist that cannot be resolved =="
FIXTURE_ROOT="$TMP/fixture-repo"        # a bare dir: no config, no git remote => empty allowlist
mkdir -p "$FIXTURE_ROOT"
( unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST
  bash "$VE" cross-repo --entry "context lives in $FOREIGN" --root "$FIXTURE_ROOT" ) >/dev/null 2>"$TMP/err.txt"
rc=$?
[ "$rc" -eq 2 ] && ok "an unresolvable allowlist is could-not-examine (2) — not a silent pass, not a bare refusal (rc=$rc)" \
  || no "unresolvable allowlist gave rc=$rc, wanted 2"
reason "REFUSE_CROSS_REPO_ALLOWLIST_UNRESOLVED" "the refusal names the UNRESOLVED ALLOWLIST as the reason"
( unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST
  bash "$VE" cross-repo --entry "no repository is named anywhere in this entry" --root "$FIXTURE_ROOT" ) >/dev/null 2>&1
[ $? -eq 0 ] && ok "an unresolvable allowlist does NOT refuse an entry that cites no repo at all" \
  || no "an unresolvable allowlist refused an entry with no repo reference (refuse-everything)"
( unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST
  VALIDATE_ENTRY_SETUP_MEMORY="$TMP/absent-resolver.sh" CLAUDE_PLUGIN_ROOT="$TMP" \
  bash "$VE" cross-repo --entry "context lives in $FOREIGN" ) >/dev/null 2>"$TMP/err.txt"
[ $? -eq 2 ] && ok "an ABSENT allowlist resolver is could-not-examine (2)" \
  || no "an absent allowlist resolver did not give rc=2"
reason "REFUSE_CROSS_REPO_ALLOWLIST_UNRESOLVED" "the absent-resolver refusal names the reason"

echo "== 9. delegation: one resolver, never a second parser =="
cat > "$TMP/stub-resolver.sh" <<'STUB'
#!/usr/bin/env bash
# Stub standing in for setup-memory.sh. Prints a list that DISAGREES with the env var, so a
# validate-entry.sh that parsed $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST itself would reach a different
# verdict from one that delegates.
echo "stuborg/stubrepo"
echo "# source: stub" >&2
exit 0
STUB
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$FOREIGN" VALIDATE_ENTRY_SETUP_MEMORY="$TMP/stub-resolver.sh" \
  bash "$VE" cross-repo --entry "context lives in $FOREIGN" >/dev/null 2>&1
[ $? -eq 1 ] && ok "the stub resolver's list wins over the env var — the allowlist is DELEGATED, not re-parsed" \
  || no "the env var beat the resolver — validate-entry.sh is parsing the allowlist itself"
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$FOREIGN" VALIDATE_ENTRY_SETUP_MEMORY="$TMP/stub-resolver.sh" \
  bash "$VE" cross-repo --entry "context lives in stuborg/stubrepo" >/dev/null 2>&1
[ $? -eq 0 ] && ok "a slug in the resolver's list passes (the delegation is read, not merely invoked)" \
  || no "a slug in the resolver's list was refused"
# Static half: no code position in validate-entry.sh may EXPAND the env var. (It appears in prose
# and in a refusal message; those carry no `$`.)
if grep -nE '\$\{?LOOMWRIGHT_MEMORY_REPO_ALLOWLIST' "$VE" >/dev/null 2>&1; then
  no "validate-entry.sh expands \$LOOMWRIGHT_MEMORY_REPO_ALLOWLIST — that is a second parser"
else
  ok "validate-entry.sh never expands \$LOOMWRIGHT_MEMORY_REPO_ALLOWLIST"
fi
grep -qF 'allowlist' "$VE" && grep -qE 'bash "\$sm"' "$VE" \
  && ok "validate-entry.sh invokes the resolver as \`bash <setup-memory.sh> ... allowlist\`" \
  || no "validate-entry.sh does not invoke setup-memory.sh for the allowlist"

echo "== 10. one list, two consumers (AC5's shared-list half) =="
SM="$PLUGIN_ROOT/scripts/setup-memory.sh"
L1="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$SM" allowlist 2>/dev/null)"
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$VE" cross-repo --entry "context lives in $FOREIGN" >/dev/null 2>&1
V1=$?
L2="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS,$FOREIGN" bash "$SM" allowlist 2>/dev/null)"
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS,$FOREIGN" bash "$VE" cross-repo --entry "context lives in $FOREIGN" >/dev/null 2>&1
V2=$?
if [ "$L1" != "$L2" ] && [ "$V1" -eq 1 ] && [ "$V2" -eq 0 ]; then
  ok "moving the list ONCE moves both the resolver's output and the cross-repo verdict (1 -> 0)"
else
  no "shared-list move did not move both consumers (L1='$L1' L2='$L2' V1=$V1 V2=$V2)"
fi

echo "== 11. MUTATION CONTROLS =="
# Every mutant is run through the SAME code path as the real check. A guard whose mutant stays
# green is a guard that was never doing the work its assertion credits it with.
# mutated_differs <file-in-TMP> <desc> — the gate every mutant passes before it is trusted.
# THREE conditions, and all three are load-bearing. This suite's first run produced an EMPTY mutant
# (a `sed` whose `|` delimiter collided with `||` in the pattern), and the assertion that followed
# went green anyway: an empty script "reports clean" for every input, so the control claimed to
# prove the guard was real while proving nothing at all. A mutant must therefore be non-empty,
# genuinely different from the original, AND still a parseable bash program.
mutated_differs() {
  local f="$TMP/$1" desc="$2"
  if [ ! -s "$f" ]; then no "$desc — the mutant is EMPTY (the mutation command failed; vacuous control)"; return 1; fi
  if cmp -s "$VE" "$f"; then no "$desc — the mutation changed NOTHING (vacuous control)"; return 1; fi
  if ! bash -n "$f" 2>/dev/null; then no "$desc — the mutant does not parse (vacuous control)"; return 1; fi
  return 0
}

# (i) AC4b: invert the membership test (`in` <-> `not in`) => AC4 must go RED.
IN_LINE="$(grep -cF '*" ${1:-} "*) return 0 ;;' "$VE")"
if [ "$IN_LINE" -ne 1 ]; then
  no "the membership test anchor is not unique ($IN_LINE hits) — the inversion mutant cannot be aimed"
else
  L="$(grep -nF '*" ${1:-} "*) return 0 ;;' "$VE" | cut -d: -f1)"
  awk -v a="$L" -v b="$((L+2))" 'NR==a{sub(/return 0/,"return 1")} NR==b{sub(/return 1/,"return 0")} {print}' \
    "$VE" > "$TMP/mut-membership.sh"
  if mutated_differs mut-membership.sh "membership inversion"; then
    LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-membership.sh" cross-repo \
      --entry "the guard landed in $OURS" >/dev/null 2>&1
    r1=$?
    LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-membership.sh" cross-repo \
      --entry "the guard landed in LOOMWRIGHT #146" >/dev/null 2>&1
    r2=$?
    LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-membership.sh" cross-repo \
      --entry "the same defect was fixed in HUB #146" >/dev/null 2>&1
    r3=$?
    [ "$r1" -eq 1 ] && [ "$r2" -eq 1 ] \
      && ok "AC4b(i): inverting the membership test turns AC4 RED (own slug and own short name both refused)" \
      || no "AC4b(i): inverting membership left AC4 GREEN (slug rc=$r1, short rc=$r2) — AC4 is not discriminating"
    [ "$r3" -eq 0 ] && ok "AC4b(i): the same inversion also makes the foreign token PASS — the direction is what is tested" \
      || no "AC4b(i): the inverted build still refused the foreign token (rc=$r3)"
  fi
fi

# (ii) AC4b: a FIXTURE allowlist that ADDS vendsy/hub must make AC3's entry PASS — proving the
# check reads the list rather than pattern-matching a hardcoded token. Supplied via the env var in
# this test's own environment; the live config is never touched.
LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS,$FOREIGN" bash "$VE" cross-repo \
  --entry "the same defect was fixed in HUB #146" >/dev/null 2>&1
[ $? -eq 0 ] && ok "AC4b(ii): adding vendsy/hub to a FIXTURE allowlist makes 'HUB #146' pass — the check reads the list" \
  || no "AC4b(ii): 'HUB #146' was refused even with vendsy/hub allowlisted — the token is hardcoded"

# (iii) R3: remove the could-not-examine refusal on an unresolvable allowlist => it reports CLEAN.
UL="$(grep -nF 'resolved to nothing' "$VE" | head -1 | cut -d: -f1)"
awk -v b="$((UL+1))" 'NR==b{sub(/return 2/,"return 0")} {print}' "$VE" > "$TMP/mut-unresolved.sh"
if mutated_differs mut-unresolved.sh "unresolvable-allowlist fail-open"; then
  ( unset LOOMWRIGHT_MEMORY_REPO_ALLOWLIST
    bash "$TMP/mut-unresolved.sh" cross-repo --entry "context lives in $FOREIGN" --root "$FIXTURE_ROOT" ) >/dev/null 2>&1
  [ $? -eq 0 ] && ok "R3: dropping the unresolved-allowlist refusal makes it report CLEAN — AC4c's assertion is real" \
    || no "R3: the unresolved-allowlist mutant did not change the verdict — AC4c may be passing for another reason"
fi

# (iv) R3: conflate UNREADABLE with ABSENT in the store guard => could-not-examine becomes clean.
: > "$TMP/unreadable-2.md"; chmod 000 "$TMP/unreadable-2.md"
if [ -r "$TMP/unreadable-2.md" ]; then
  ok "SKIPPED store-guard mutant (running as a user that can read mode-000 files)"
else
  # awk + index(), not sed: the target line contains `||` and `[`, which collide with sed's
  # delimiter and BRE metacharacters. That collision is what produced the empty mutant above.
  awk '{ if (index($0, "[ -r \"$p\" ] || return 2")) sub(/return 2/, "return 1"); print }' \
    "$VE" > "$TMP/mut-store.sh"
  if mutated_differs mut-store.sh "store absent-vs-unreadable conflation"; then
    bash "$TMP/mut-store.sh" duplicate --entry "brand new fact" --store "$TMP/unreadable-2.md" >/dev/null 2>&1
    [ $? -eq 0 ] && ok "R3: conflating unreadable with absent makes the store guard report CLEAN — the guard is real" \
      || no "R3: the store-guard mutant did not change the verdict"
  fi
fi
chmod 644 "$TMP/unreadable-2.md" 2>/dev/null

# (v) R3: raise the duplicate threshold out of reach => the duplicate refusal disappears.
sed 's/^VALIDATE_ENTRY_DUPLICATE_THRESHOLD=90$/VALIDATE_ENTRY_DUPLICATE_THRESHOLD=999/' "$VE" > "$TMP/mut-dup.sh"
if mutated_differs mut-dup.sh "duplicate threshold"; then
  bash "$TMP/mut-dup.sh" duplicate --entry "on every request the token cache is refreshed" --store "$STORE" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "R3: raising the duplicate threshold clears the refusal — the comparison is what refuses" \
    || no "R3: the duplicate mutant still refused — the refusal is not coming from the comparison"
fi

# (vi) R3: same for contradiction.
sed 's/^VALIDATE_ENTRY_CONTRADICTION_THRESHOLD=60$/VALIDATE_ENTRY_CONTRADICTION_THRESHOLD=999/' "$VE" > "$TMP/mut-con.sh"
if mutated_differs mut-con.sh "contradiction threshold"; then
  bash "$TMP/mut-con.sh" contradiction --entry "the token cache is never refreshed on any request" --store "$STORE" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "R3: raising the contradiction threshold clears the refusal — the comparison is what refuses" \
    || no "R3: the contradiction mutant still refused"
fi

# (vii) R3: make the provenance pattern match anything => the provenance refusal disappears.
awk '/^_VE_PROVENANCE_RE=/{print "_VE_PROVENANCE_RE=\x27.\x27"; next} {print}' "$VE" > "$TMP/mut-prov.sh"
if mutated_differs mut-prov.sh "provenance pattern"; then
  bash "$TMP/mut-prov.sh" provenance --entry "the cache is refreshed eagerly" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "R3: a match-anything provenance pattern clears the refusal — the pattern is what refuses" \
    || no "R3: the provenance mutant still refused"
fi

# (viii) R3: make every path resolve => the dead-reference refusal disappears.
awk '/^_ve_path_resolves\(\) \{$/{print; print "  return 0"; next} {print}' "$VE" > "$TMP/mut-dead.sh"
if mutated_differs mut-dead.sh "path resolution"; then
  bash "$TMP/mut-dead.sh" dead-reference --entry "the guard lives in loomwright/scripts/long-gone.sh" --root "$REPO_ROOT" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "R3: making every path resolve clears the refusal — resolution is what refuses" \
    || no "R3: the dead-reference mutant still refused"
fi

# (ix) AC6: drop the jq has() key-presence assertion => a MISSING key passes as valid.
if command -v jq >/dev/null 2>&1; then
  sed 's/(has(\$f) | tostring)/("true")/' "$VE" > "$TMP/mut-has.sh"
  if mutated_differs mut-has.sh "jq has() presence assertion"; then
    bash "$TMP/mut-has.sh" dead-reference --json '{"other":"x"}' --field path --root "$REPO_ROOT" >/dev/null 2>&1
    [ $? -eq 0 ] && ok "AC6: dropping the has() presence assertion lets a MISSING key pass — the assertion is real" \
      || no "AC6: the has() mutant did not change the verdict"
  fi
fi

# (x) The aggregate must actually CALL each check: delete one call and the corresponding fixture
# must go green. Without this, `validate_entry_all` could source five checks and invoke four.
sed '/^  validate_cross_repo_reference "\$@";/d' "$VE" > "$TMP/mut-all.sh"
if mutated_differs mut-all.sh "aggregate call site"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-all.sh" all \
    --entry "the same defect was fixed in HUB #146, source pr-138" --store "$STORE" --source "pr-138" --root "$REPO_ROOT" >/dev/null 2>&1
  m=$?
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$VE" all \
    --entry "the same defect was fixed in HUB #146, source pr-138" --store "$STORE" --source "pr-138" --root "$REPO_ROOT" >/dev/null 2>&1
  b=$?
  { [ "$b" -eq 1 ] && [ "$m" -eq 0 ]; } \
    && ok "deleting the cross-repo call from validate_entry_all turns the aggregate green — the call site is tested, not just the source line" \
    || no "aggregate call-site mutant did not discriminate (baseline rc=$b, mutant rc=$m)"
fi

# (xi) AC16: drop the MARKER requirement on `owner/repo` => ordinary prose pairs are refused again.
# This is the mutant that reproduces the 12-of-21 false-refusal defect on demand.
awk '{ if (index($0, "if [ \"$structural\" != \"1\" ]; then")) { print "  if false; then"; next } print }' \
  "$VE" > "$TMP/mut-cue.sh"
if mutated_differs mut-cue.sh "cross-repo marker requirement"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-cue.sh" cross-repo \
    --entry "tests must parse YAML/JSON rather than hit live dependencies" >/dev/null 2>&1
  [ $? -eq 1 ] && ok "AC16: dropping the marker requirement refuses 'YAML/JSON' again — the marker is what keeps prose writable" \
    || no "AC16: the marker mutant still passed the prose pair — the pair is passing for some other reason"
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-cue.sh" cross-repo \
    --entry "context lives in $FOREIGN" >/dev/null 2>&1
  [ $? -eq 1 ] && ok "AC16: the same mutant still refuses a genuinely foreign slug — the mutation removed only the marker rule" \
    || no "AC16: the marker mutant stopped refusing foreign slugs — it changed more than the marker rule"
fi

# (xii) AC16: drop the unresolvable-BY-SHAPE skips => a glob and a tilde path are refused again.
awk '{ if (index($0, "resolves to no single file: SKIP") || index($0, "outside any repo root: SKIP")) next; print }' \
  "$VE" > "$TMP/mut-shape.sh"
if mutated_differs mut-shape.sh "unresolvable-by-shape skip"; then
  bash "$TMP/mut-shape.sh" dead-reference --entry "eleven test-*.sh suites run in CI" --root "$REPO_ROOT" >/dev/null 2>&1
  r1=$?
  bash "$TMP/mut-shape.sh" dead-reference --entry "set =1 in ~/.claude/settings.json" --root "$REPO_ROOT" >/dev/null 2>&1
  r2=$?
  { [ "$r1" -eq 1 ] && [ "$r2" -eq 1 ]; } \
    && ok "AC16: dropping the by-shape skips refuses the glob and the tilde path again — the skips are what pass them" \
    || no "AC16: the by-shape mutant did not discriminate (glob rc=$r1, tilde rc=$r2)"
fi

# (xiii) AC16: disable the repo-wide suffix resolution => a real file that is not at the repo root
# is refused again. This is the other half of the 12-of-21 defect.
awk '/^_ve_index_has\(\) \{$/{print; print "  return 1"; next} {print}' "$VE" > "$TMP/mut-index.sh"
if mutated_differs mut-index.sh "repo-wide path resolution"; then
  bash "$TMP/mut-index.sh" dead-reference --entry "a green check-doc-currency.sh is necessary" --root "$REPO_ROOT" >/dev/null 2>&1
  [ $? -eq 1 ] && ok "AC16: disabling the repo-wide suffix match refuses 'check-doc-currency.sh' again — the match is what resolves it" \
    || no "AC16: the index mutant did not change the verdict — the bare filename resolves some other way"
  bash "$TMP/mut-index.sh" dead-reference --entry "the sole writer is loomwright/scripts/write-lessons.sh" --root "$REPO_ROOT" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "AC16: the same mutant still resolves a root-relative path — the mutation removed only the suffix match" \
    || no "AC16: the index mutant broke ordinary root-relative resolution — it changed more than the suffix match"
fi

# (xiv) AC17: drop the strict-source test => a bare command name satisfies provenance again, which
# is exactly the "any non-placeholder string" option decision (f) rejected.
awk '{ if (index($0, "*[0-9]*|*:*|*/*")) { print "          *) return 0 ;;"; next } print }' "$VE" > "$TMP/mut-strict.sh"
if mutated_differs mut-strict.sh "strict --source test"; then
  bash "$TMP/mut-strict.sh" provenance --entry "the cache is refreshed eagerly" --source "dreaming" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "AC17: dropping the strict-source test lets a bare command name pass — the strictness is real" \
    || no "AC17: the strict-source mutant did not change the verdict"
fi

# (xv) Marker (3), KNOWN OWNER: disable the owner test => a foreign repo under a known owner stops
# being recognised. This is the marker that reads real data rather than shape.
awk '{ if (index($0, "a KNOWN repo owner")) { print "                *\") never-a-real-owner \"*) : ;;"; next } print }' \
  "$VE" > "$TMP/mut-owner.sh"
if mutated_differs mut-owner.sh "known-owner marker"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-owner.sh" cross-repo \
    --entry "vikashruhilgit/hub has the same bug" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "marker (3): disabling the known-owner test stops 'vikashruhilgit/hub' being recognised — the owner set is what marks it" \
    || no "marker (3): the known-owner mutant still refused — recognition is coming from somewhere else"
fi

# (xvi) Marker (4), SLUG-ONLY STRUCTURE: make it always fail => the hyphen/CamelCase forms stop
# being recognised, and the corpus prose pairs must STILL pass (the mutation removed only structure).
awk '/^_ve_slug_structured\(\) \{$/{print; print "  return 1"; next} {print}' "$VE" > "$TMP/mut-struct.sh"
if mutated_differs mut-struct.sh "slug-only structure marker"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-struct.sh" cross-repo \
    --entry "acme-corp/widget-svc has the same bug" >/dev/null 2>&1
  r1=$?
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-struct.sh" cross-repo \
    --entry "octocat/Hello-World has the bug" >/dev/null 2>&1
  r2=$?
  { [ "$r1" -eq 0 ] && [ "$r2" -eq 0 ]; } \
    && ok "marker (4): disabling slug-only structure stops the hyphen and CamelCase forms being recognised — structure is what marks them" \
    || no "marker (4): the structure mutant did not discriminate (hyphen rc=$r1, CamelCase rc=$r2)"
fi

# (xvii) Marker (2), TRAILING CUE: remove it => 'the vendsy/hub repo' stops being recognised.
awk '{ if (index($0, "_VE_SLUG_TRAILING_CUE_WORDS=")) { print "_VE_SLUG_TRAILING_CUE_WORDS=\" \""; next } print }' \
  "$VE" > "$TMP/mut-trail.sh"
if mutated_differs mut-trail.sh "trailing cue marker"; then
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-trail.sh" cross-repo \
    --entry "the $FOREIGN repo has the same bug" >/dev/null 2>&1
  [ $? -eq 0 ] && ok "marker (2): emptying the trailing cue list stops 'the vendsy/hub repo' being recognised" \
    || no "marker (2): the trailing-cue mutant still refused"
  LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$TMP/mut-trail.sh" cross-repo \
    --entry "the same defect landed in $FOREIGN last week" >/dev/null 2>&1
  [ $? -eq 1 ] && ok "marker (2): the same mutant still refuses the LEADING-cue form — the two cue lists are independent" \
    || no "marker (2): emptying the trailing list also broke the leading cue"
fi

echo "== 11b. AC16 CORPUS REGRESSION: every live curated entry replays with ZERO refusals =="
# THE regression guard whose absence let a 57% false-refusal rate reach a working tree. The five
# checks looked correct in isolation and were green on 87 hand-written fixtures; replayed against
# the real corpus they refused 12 of 21 legitimate entries. Hand-written fixtures are written by the
# same mind that wrote the check and inherit its blind spots — only real prose does not.
#
# Two design notes, both load-bearing:
#  · The store is deliberately ABSENT. Replaying a stored entry against the store that already holds
#    it is a duplicate BY CONSTRUCTION, so an absent store is what makes duplicate/contradiction
#    examined-and-clean and puts the prose-scanning checks (provenance, dead-reference, cross-repo)
#    under test — which is where every false refusal came from.
#  · The corpus is read READ-ONLY and may legitimately change over time, so this asserts a PROPERTY
#    of it (zero refusals), never a count. If the stores are absent it SKIPS LOUDLY rather than
#    passing vacuously — the (e5) precedent — and if they are present but yield no entries that is a
#    FAILURE, not a pass, because a silently empty corpus is the vacuous form of this whole section.
CORPUS_L="$REPO_ROOT/.supervisor/memory/LESSONS.md"
CORPUS_P="$REPO_ROOT/.supervisor/memory/PROJECT_MEMORY.md"

# replay_corpus <file>... -> REPLAY_N entries replayed, REPLAY_BAD refused, REPLAY_FIRST names one.
replay_corpus() {
  REPLAY_N=0; REPLAY_BAD=0; REPLAY_FIRST=""
  local f line id text out rc
  for f in "$@"; do
    [ -f "$f" ] && [ -r "$f" ] || continue
    while IFS= read -r line; do
      case "$line" in "- ["*) : ;; *) continue ;; esac
      id="$(printf '%s' "$line" | sed -e 's/^- \[\([0-9a-fA-F]*\)\].*$/\1/')"
      text="$(printf '%s' "$line" | sed -e 's/^- \[[0-9a-fA-F]*\][[:space:]]*//' -e 's/<!--.*-->[[:space:]]*$//')"
      [ -n "$text" ] || continue
      REPLAY_N=$((REPLAY_N + 1))
      out="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="$OURS" bash "$VE" all \
        --entry "$text" --source "corpus-replay:$id" \
        --store "$TMP/no-such-corpus-store.md" --root "$REPO_ROOT" 2>&1)"
      rc=$?
      if [ "$rc" -ne 0 ]; then
        REPLAY_BAD=$((REPLAY_BAD + 1))
        [ -n "$REPLAY_FIRST" ] || REPLAY_FIRST="[$id] rc=$rc $(printf '%s' "$out" | sed -n '1p')"
      fi
    done < "$f"
  done
  return 0
}

if [ -r "$CORPUS_L" ] || [ -r "$CORPUS_P" ]; then
  replay_corpus "$CORPUS_L" "$CORPUS_P"
  if [ "$REPLAY_N" -eq 0 ]; then
    no "AC16: the live curated stores are present but yielded NO entries — this replay would pass vacuously"
  else
    [ "$REPLAY_BAD" -eq 0 ] \
      && ok "AC16: all $REPLAY_N live curated entries replay with ZERO refusals" \
      || no "AC16: $REPLAY_BAD of $REPLAY_N live curated entries were REFUSED (false positives) — first: $REPLAY_FIRST"
  fi
else
  ok "AC16 SKIPPED: no live curated store at .supervisor/memory/ (gitignored, so absent on a fresh clone and in CI) — not asserted rather than asserted vacuously"
fi

# Vacuity control for the harness itself: the same replay path, over a SYNTHETIC corpus seeded with
# one entry that must refuse, has to report that refusal. Without this, a replay loop that silently
# ran zero validators — or swallowed the status — would report "zero refusals" forever.
mkdir -p "$TMP/corpus"
{ printf '# Synthetic\n'
  printf -- '- [aaaa0001] the guard lives in loomwright/scripts/long-gone-nowhere.sh\n'
  printf -- '- [aaaa0002] a perfectly ordinary entry naming no path and no repo\n'
} > "$TMP/corpus/SEEDED.md"
replay_corpus "$TMP/corpus/SEEDED.md"
{ [ "$REPLAY_N" -eq 2 ] && [ "$REPLAY_BAD" -eq 1 ]; } \
  && ok "AC16 control: the replay harness DOES report a refusal when one is seeded (2 replayed, 1 refused)" \
  || no "AC16 control: the seeded corpus gave N=$REPLAY_N bad=$REPLAY_BAD, wanted 2/1 — the replay harness is not discriminating"

echo "== 12. no live state is touched =="
if [ -f "$LIVE_CFG" ]; then LIVE_CFG_AFTER="$(cksum < "$LIVE_CFG")"; else LIVE_CFG_AFTER="ABSENT"; fi
[ "$LIVE_CFG_BEFORE" = "$LIVE_CFG_AFTER" ] \
  && ok "the live .supervisor/config.json is byte-unchanged by this suite" \
  || no "this suite MODIFIED the live .supervisor/config.json"
if [ -f "$LIVE_CFG" ] && command -v jq >/dev/null 2>&1; then
  if jq -e '((.setup_memory.repo_allowlist // [])[] | select(test("^vendsy/"; "i")))' "$LIVE_CFG" >/dev/null 2>&1; then
    no "a FOREIGN slug is present in the live allowlist — the publication gate is compromised"
  else
    ok "no foreign slug is present in the live allowlist"
  fi
fi
[ "$(cksum < "$STORE")" = "$STORE_CK" ] \
  && ok "the fixture store is byte-unchanged after every refusal (flag, never delete)" \
  || no "a refusal MUTATED the store"
LIVE_STORES_AFTER="$(cksum < "$REPO_ROOT/.supervisor/memory/LESSONS.md" 2>/dev/null)|$(cksum < "$REPO_ROOT/.supervisor/memory/PROJECT_MEMORY.md" 2>/dev/null)"
[ "$LIVE_STORES_BEFORE" = "$LIVE_STORES_AFTER" ] \
  && ok "the live curated stores are byte-unchanged — the corpus replay reads them, never writes" \
  || no "the corpus replay MODIFIED a live curated store"

echo "== 13. executable dispatch + verdict-code convention =="
verdict 0 "--help prints usage and exits 0" "$VE" --help
verdict 2 "an unknown check exits 2 rather than silently succeeding" "$VE" not-a-check
grep -qE '^VALIDATE_ENTRY_RC_UNEXAMINABLE=2$' "$VE" \
  && ok "the could-not-examine verdict code is a named constant, not an anonymous 2" \
  || no "VALIDATE_ENTRY_RC_UNEXAMINABLE is not declared"
bash -n "$VE" && ok "validate-entry.sh parses cleanly under bash -n" || no "validate-entry.sh has a syntax error"

echo
echo "validate-entry: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
