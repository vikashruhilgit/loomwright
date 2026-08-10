#!/usr/bin/env bash
# test-setup-memory.sh — STATIC, fixture-driven self-tests for setup-memory.sh (the `/setup memory`
# module engine: gitignore negation `check` / `apply` / `remove` + the repo allowlist and its
# ledger filter). STATIC ONLY: no network, no Docker, no GitHub — so it runs on the plugin's
# Ubuntu CI like every other test-*.sh (auto-registered by ci.yml's test-*.sh glob).
# Exit 0 = all pass, 1 = any assertion failed, 2 = FIXTURE SETUP is broken.
#
# 1 and 2 are deliberately distinct and must stay that way. 1 means the assertions ran and
# setup-memory.sh genuinely misbehaved. 2 means a fixture could not be BUILT as specified, so the
# assertions after it would be testing something other than what they name — a defect in this
# harness, not in the script under test. Conflating the two is the exact bug this distinction
# exists to prevent: see the (f5) flake described at `mkfix` below, where a silently-failed
# `ln -s` reported itself as "the symlink was clobbered" and read as a rewriter bug.
#
# Mirrors test-setup-twin.sh convention: pass/fail counters, ok()/no() helpers, a
# "RESULT: N passed, M failed" tail, exit 1 on any failure.
#
# FIXTURE ISOLATION IS LOAD-BEARING. This suite writes `.gitignore` files and `git init`s repos,
# and it runs INSIDE the plugin's own repo in CI — so every fixture is its own `mktemp -d` +
# `git init`, cleaned in a `trap`. The harness NEVER touches the plugin repo's own `.gitignore`,
# its `.supervisor/config.json`, or the developer's `$HOME/.claude/`; group (k) asserts that
# mechanically by checksumming this repo's own `.gitignore` before and after the whole run.
# (The plugin repo's `.supervisor/config.json` is engine-owned at runtime — nothing here may
# write it, which is why every allowlist config read/write below happens in a fixture.)
#
# Every fixture repo pins `core.excludesFile=/dev/null` so a developer's global gitignore can
# never leak into a `git check-ignore` assertion.
#
# FIXTURE NAMES ARE UNIQUE BY CONSTRUCTION (`mktemp -d`), NEVER BY `$RANDOM`. See mkfix's comment
# for the flake this closed. Corollary, and the reason `setup_fail` exists: fixture SETUP is not
# under test. A mis-built fixture reports itself as a behavioural defect in setup-memory.sh and
# sends the reader hunting a bug that is not there, so a setup step must never fall through into
# an `ok`/`no` assertion.
#
# One MECHANICALLY AUDITABLE class, stated exactly so this note cannot rot into a claim the code
# does not back: the setup calls that FAIL on a pre-existing path or a refused mode change —
# bare `mkdir`, bare `ln -s`, and `chmod 000`. To audit, run
# `grep -n 'mkdir "\|ln -s \|chmod 000' "$0"` and confirm every CALL SITE it lists is followed by
# a `|| setup_fail …` — on the same line, or on the next one where the call is line-continued.
# It resolves to exactly four call sites (f5, f6, f7, l9). Its other hits are PROSE, not calls:
# this comment's own self-match, the (f7)/(l9) group headers explaining chmod-000, and assertion
# and setup_fail message strings that mention it. Read the hits, do not just count the lines.
#
# Two further setup guards exist that this grep deliberately does NOT match, because they are not
# in that class and finding only four hits should not read as a gap: `newgit` asserts a fresh
# fixture has no pre-existing `.gitignore`, and (f8) asserts the NUL byte survived its `printf`.
# Each is explained at its own call site; neither is a mkdir/ln -s/chmod failure.
#
# The suite's OTHER setup calls are deliberately unguarded and must not be "fixed" by copying the
# pattern around: `mkdir -p`, `ln -sf` and `chmod +x` cannot fail on a pre-existing path — that is
# precisely what the `-p`/`-f` flags buy — so a guard there would be noise asserting a tautology.
#
# NO `producer | grep -q` PIPELINES. Under `set -o pipefail`, `grep -q` exits at the first match
# and SIGPIPEs the producer, so the PIPELINE status becomes 141 even though grep matched — an
# assertion written that way fails whenever the match is early in the output. Every text
# assertion below therefore captures stdout into a variable first and matches it with a
# here-string (`has`/`hasi`/`hasF`), which involves no pipeline at all.
#
# Covers (each = an acceptance criterion):
#   (a)  the NAIVE `.claude/` + `!.claude/agent-memory/` negation is asserted to FAIL, and the
#        `.claude/*` form to succeed — the silent failure is asserted, never merely commented
#   (b)  after apply: each intended path is committable and each unintended path stays ignored,
#        asserted PER PATH via `git check-ignore` (never a bulk claim)
#   (b2) the RECURSIVE `.claude/**` / `**/.claude/` family is neutralised like the bare form, and
#        an exclude this rewriter does NOT recognise is reported (warning + the winning pattern
#        from a real `git check-ignore -v`) instead of hiding under an `apply: applied` headline
#   (b3) the WORKING `X/*` form is the one directory-shaped exclude deliberately NOT neutralised:
#        a user's pre-existing `.claude/*` SURVIVES apply uncommented (and round-trips through
#        remove), while a bare `.supervisor/` in the same file is still neutralised
#   (b4) the `partial` verdict (OVER-inclusion: an unintended path became committable) is driven by
#        a real fixture and gets its OWN remediation copy — it points at the over-broad `!`
#        re-include, and must NOT print the under-inclusion "comment out the rule named above" text
#   (b5) git's own lexer decides what is an obstacle: a LEADING-whitespace or INLINE-`#` "bare
#        exclude" ignores nothing in git, so leaving it live is correct — asserted, not assumed
#   (c)  dotfile sidecars (.provenance.jsonl / .lessons-provenance.jsonl) commit — asserted
#        explicitly and separately from the `**` globs
#   (d)  allowlist: stored as a JSON ARRAY (never a string); a renamed repo retains records under
#        BOTH slugs; a foreign-repo record is excluded; a fresh install defaults to the remote
#   (e)  idempotency: a second apply is a no-op that writes nothing (.gitignore AND config
#        byte-identical, no second backup); PLUS backup-before-write asserted positively — the
#        backup exists and its CONTENT is the pristine pre-apply file — and two applies inside the
#        same second (pinned clock) produce two backups rather than overwriting the original; PLUS
#        backup-name EXHAUSTION fails CLOSED — with every candidate name seeded, apply ABORTS,
#        .gitignore is untouched and the pre-existing backup is not clobbered
#   (f)  absent / unparseable .gitignore: change nothing, say why, no partial write, no backup;
#        and an INDENTED sentinel is stripped, never duplicated into an unrepairable file.
#        Every abort branch of gitignore_gate() has a fixture: conflict markers, sentinel
#        imbalance, SYMLINK (link and target both untouched), NON-REGULAR file, chmod-000
#        (skipped under root, which bypasses mode bits), and NUL/binary content — the last with
#        a two-sided assertion (a text .gitignore must NOT be called binary) so it cannot pass
#        under the `grep -q $'\0'` empty-pattern regression it exists to prevent
#   (g)  remove: block gone, byte-exact round-trip, and the output states plainly that git history
#        retains anything already pushed + that already-tracked files need `git rm --cached`
#   (h)  the consent disclosure (what becomes version-controlled) is printed BEFORE applying
#   (i)  write containment: only .gitignore(+backup) and .supervisor/config.json; `check` writes
#        nothing; no commit/index/HEAD is ever touched; only read-only git subcommands are used
#   (j)  fail-safe: every subcommand exits 0, including on a non-git root and a bad flag — and a
#        root where nothing could be probed reports the VERDICT as `unknown`, never `partial`
#   (l)  the FINDINGS-LEDGER GATE: a clean ledger is un-ignored (and ONLY the ledger, not its
#        siblings); a foreign `.repo` record REFUSES the negation, names the slug and still exits 0;
#        the refusal is driven by a record appended in the SPACED JSON form, because that is the
#        shape a compact-form grep cannot see; absent ledger PASSES; absent `jq` leaves the gate
#        UNEVALUATED (verdict unchanged, negation NOT emitted); an empty allowlist and an
#        unattributable record both REFUSE (fail-closed); and BOTH wrong emission forms — the naive
#        one-liner and the correct three lines placed BEFORE `.supervisor/*` — are pinned as
#        negative controls that leave the ledger IGNORED
#   (m)  the `gated` VERDICT CLASS: a refusal reports `gated`, never `not configured`; its warning
#        names the offending slugs and the filter-ledger/extend-allowlist remedy, states that
#        withholding does NOT un-track an already-committed ledger, and NEVER emits the
#        under-inclusion "comment out the rule named above" copy; a second apply on a gated repo does
#        NOT print the `apply: no-op — already configured` headline; and a clean→contaminated
#        re-apply ANNOUNCES the withdrawal
#   (n)  the EMIT/WITHDRAW ASYMMETRY on an ALREADY-APPLIED repo: a could-not-examine gate (jq
#        ABSENT, and jq PRESENT-BUT-BROKEN — `command -v` tests presence, not function) PRESERVES the
#        existing negation and claims no contamination, while a REAL foreign record still WITHDRAWS
#        it and names the real slug
#   (o)  `remove` is LEDGER-AWARE: on a repo whose ledger was un-ignored by a clean apply AND really
#        `git add`ed, remove reports the THIRD tracked count for the ledger path (non-zero, so it
#        cannot pass trivially), re-ignores the ledger (probed with git, not a .gitignore grep) and
#        names all three stores in its `git rm -r --cached` remediation
#   (k)  the suite never touched the plugin repo's own .gitignore
#
# EVERY LEDGER ASSERTION IN THIS FILE USES jq, NEVER grep. A findings ledger mixes compact
# (`"repo":"x"`) and spaced (`"repo": "x"`) JSON — this plugin's own ledger carries one spaced
# record among 88 — so `grep -c '"repo":"owner/name"'` silently under-counts AND a foreign record
# appended in the spaced form evades a compact grep entirely. The ledger_count / ledger_has_repo
# helpers below are the only sanctioned way to assert on ledger content here.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
MEM="$HERE/setup-memory.sh"
PLUGIN_REPO="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

# Pipeline-free text matchers (see the header note about pipefail + `grep -q`).
has()  { grep -q  -e "$1" <<< "$2"; }   # ERE-less basic regex
hasE() { grep -qE -e "$1" <<< "$2"; }
hasi() { grep -qi -e "$1" <<< "$2"; }
hasF() { grep -qF -e "$1" <<< "$2"; }

# ---- fixture lifecycle ------------------------------------------------------
# A SETUP failure is NOT a behavioural failure. If a fixture cannot be built as specified, the
# assertions that follow it would test something other than what they claim — so abort the whole
# suite loudly and immediately rather than letting the mis-built fixture masquerade as a defect
# in setup-memory.sh. (This is exactly how the (f5) symlink flake presented: a fixture whose
# `ln -s` had silently failed reported "abort did not name the symlink" / "symlink was clobbered",
# which reads as a rewriter bug and is not one.)
#
# `kill -s TERM $$` is load-bearing, not decoration: mkfix/newgit are ALWAYS invoked in a command
# substitution, where a bare `exit 2` would kill only the subshell and let the suite sail on with
# an empty fixture path. `$$` stays the top-level shell's pid inside a subshell, so the signal
# reaches the real suite; the TERM trap turns it into exit 2, and the EXIT trap still cleans up.
setup_fail() {
  echo "  SETUP FAILURE: $1" >&2
  echo "ABORTED: fixture setup is broken — the assertions below would be meaningless." >&2
  kill -s TERM $$ 2>/dev/null
  exit 2
}
trap 'exit 2' TERM

# The scratch root is itself an unguarded setup step — an unwritable or full $TMPDIR leaves it
# EMPTY, after which every fixture path is a bare "/fix-…" and the whole suite reports nonsense
# (and `rm -rf "$FIXTURE_ROOT"` in cleanup would be aimed at nothing useful). Checked, not assumed.
FIXTURE_ROOT="$(mktemp -d 2>/dev/null)"
[ -n "$FIXTURE_ROOT" ] && [ -d "$FIXTURE_ROOT" ] \
  || setup_fail "mktemp -d failed — no writable scratch root (TMPDIR=${TMPDIR:-/tmp})"
cleanup() { [ -n "${FIXTURE_ROOT:-}" ] && rm -rf "$FIXTURE_ROOT" 2>/dev/null; }
trap cleanup EXIT

# All fixtures live UNDER one scratch root, so the trap cleans them even though mkfix runs in a
# command substitution (a `FIXTURES+=(...)` array there would be lost with the subshell).
#
# UNIQUENESS IS LOAD-BEARING AND MUST NOT DEPEND ON $RANDOM. This was once
# `FIXN=$((FIXN+1)); d="$FIXTURE_ROOT/fix-$FIXN-$RANDOM"; mkdir -p "$d"`, which has two compounding
# defects: mkfix ALWAYS runs in a command substitution, so the `FIXN` increment happens in the
# subshell and the parent's FIXN stays 0 forever (every dir was `fix-1-*`); uniqueness therefore
# rested entirely on a 15-bit `$RANDOM` drawn ~46 times — a ~3% birthday collision per run. On a
# collision `mkdir -p` SILENTLY succeeds on the existing directory and the new fixture inherits
# the previous one's `.gitignore`, after which a `printf >` overwrites it (invisible) but an
# `ln -s`/`mkdir` fails (visible only as a bogus behavioural failure downstream — this is the
# (f5) "abort did not name the symlink" / "the symlink was clobbered" CI flake). `mktemp -d`
# makes the name unique by construction (O_EXCL in the kernel), so the class is closed at the
# root rather than made rarer.
mkfix() {
  local d
  d="$(mktemp -d "$FIXTURE_ROOT/fix-XXXXXXXX")" || setup_fail "mktemp -d under $FIXTURE_ROOT failed"
  printf '%s' "$d"
}

# new git repo with an identity, one commit, a pinned empty global-excludes, and an optional
# origin remote. Echoes the dir.
newgit() {
  local d remote="${1:-}"
  d="$(mkfix)"
  (
    cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git config core.excludesFile /dev/null \
      && { [ -z "$remote" ] || git remote add origin "$remote"; } \
      && echo seed > seed.txt && git add seed.txt && git commit -qm seed
  ) >/dev/null 2>&1
  # A fresh fixture repo must start with NO .gitignore of any kind. Everything downstream assumes
  # it — a `printf >` would silently overwrite a stray one, an `ln -s`/`mkdir` would fail and only
  # surface as a bogus behavioural failure. A stray one here means either a colliding fixture dir
  # or a `git init` template (init.templateDir / ~/.config/git/template) shipping one, and both
  # invalidate the group that follows.
  [ -e "$d/.gitignore" ] || [ -L "$d/.gitignore" ] \
    && setup_fail "newgit produced a fixture that ALREADY has a .gitignore ($d) — colliding fixture dir, or a git init template is supplying one"
  printf '%s' "$d"
}

mem() { bash "$MEM" --root "$1" "${@:2}"; }

# ignored <dir> <path> → 0 when git ignores it, 1 when it is committable.
ignored() { git -C "$1" check-ignore -q -- "$2" >/dev/null 2>&1; }

# assert_ignored / assert_committable — ONE assertion per path (never a bulk claim).
assert_ignored()     { if ignored "$1" "$2"; then ok "$3"; else no "$3 (got: committable)"; fi; }
assert_committable() { if ignored "$1" "$2"; then no "$3 (got: ignored)"; else ok "$3"; fi; }

sum() { cksum < "$1" 2>/dev/null; }

# ---- ledger assertion helpers — jq ONLY (see the header note) ----------------
# ledger_count <jsonl-text> → number of RECORDS (not lines). An empty string counts as 0.
ledger_count() { printf '%s\n' "$1" | jq -s 'length' 2>/dev/null || echo "?"; }
# ledger_has_repo <jsonl-text> <slug> → status 0 when at least one record carries that `.repo`.
ledger_has_repo() {
  local n
  n="$(printf '%s\n' "$1" | jq -s --arg r "$2" 'map(select(((.repo // "") | tostring) == $r)) | length' 2>/dev/null || echo 0)"
  [ "${n:-0}" -gt 0 ]
}
# ledger_has_field <jsonl-text> <key> <numeric value> → status 0 when a record matches.
ledger_has_field() {
  local n
  n="$(printf '%s\n' "$1" | jq -s --arg k "$2" --argjson v "$3" 'map(select(.[$k] == $v)) | length' 2>/dev/null || echo 0)"
  [ "${n:-0}" -gt 0 ]
}

P_LEDGER=".supervisor/postmortem/results.jsonl"
P_LEDGER_SIBLING=".supervisor/postmortem/some-other-artifact.json"

# make a populated store tree inside a fixture (real files, so tracking assertions are real)
seed_stores() {
  local d="$1"
  mkdir -p "$d/.claude/agent-memory/loomwright:supervisor" "$d/.supervisor/memory" \
           "$d/.claude/worktrees/busy-darwin" "$d/.supervisor/logs"
  echo "# MEMORY"  > "$d/.claude/agent-memory/loomwright:supervisor/MEMORY.md"
  echo '{"p":1}'   > "$d/.claude/agent-memory/loomwright:supervisor/.provenance.jsonl"
  echo "# LESSONS" > "$d/.supervisor/memory/LESSONS.md"
  echo '{"p":1}'   > "$d/.supervisor/memory/.lessons-provenance.jsonl"
  echo "wt"        > "$d/.claude/worktrees/busy-darwin/README.md"
  echo '{}'        > "$d/.claude/settings.local.json"
  echo '{}'        > "$d/.supervisor/logs/session.jsonl"
}

P_MEM=".claude/agent-memory/loomwright:supervisor/MEMORY.md"
P_MEM_DOT=".claude/agent-memory/loomwright:supervisor/.provenance.jsonl"
P_LES=".supervisor/memory/LESSONS.md"
P_LES_DOT=".supervisor/memory/.lessons-provenance.jsonl"
P_WT=".claude/worktrees/busy-darwin/README.md"
P_LOCAL=".claude/settings.local.json"
P_LOGS=".supervisor/logs/session.jsonl"

# snapshot the PLUGIN repo's own .gitignore up front — group (k) re-checks it at the end.
PLUGIN_GI="$PLUGIN_REPO/.gitignore"
PLUGIN_GI_SUM_BEFORE="$(sum "$PLUGIN_GI")"

JQ="$(command -v jq || true)"

# ============================================================================
echo "== 0. script under test exists =="
[ -f "$MEM" ] && ok "setup-memory.sh present" || no "setup-memory.sh missing at $MEM"
if [ ! -f "$MEM" ]; then echo; echo "RESULT: $pass passed, $fail failed"; exit 1; fi

# ============================================================================
echo "== (a) the NAIVE negation is proven to FAIL; the /* form is proven to WORK =="
# This is the whole reason the module exists: `.claude/` excludes the DIRECTORY, so git never
# descends into it and NO later `!` line can re-include anything below it. The failure is
# asserted here, not described in a comment.
Na="$(newgit)"
seed_stores "$Na"
printf '.claude/\n!.claude/agent-memory/\n.supervisor/\n!.supervisor/memory/\n' > "$Na/.gitignore"
assert_ignored "$Na" "$P_MEM"     "(a1) NAIVE '.claude/' + '!.claude/agent-memory/' STILL ignores $P_MEM — the negation silently fails, as claimed"
assert_ignored "$Na" "$P_LES"     "(a1) NAIVE '.supervisor/' + '!.supervisor/memory/' STILL ignores $P_LES — same silent failure"
assert_ignored "$Na" "$P_MEM_DOT" "(a1) NAIVE form also still ignores the dotfile sidecar $P_MEM_DOT"

# Same fixture, rewritten to the working form → committable.
printf '.claude/*\n!.claude/agent-memory/\n.supervisor/*\n!.supervisor/memory/\n' > "$Na/.gitignore"
assert_committable "$Na" "$P_MEM" "(a2) WORKING '.claude/*' + '!.claude/agent-memory/' makes $P_MEM committable"
assert_committable "$Na" "$P_LES" "(a2) WORKING '.supervisor/*' + '!.supervisor/memory/' makes $P_LES committable"
assert_ignored "$Na" "$P_WT"    "(a3) WORKING form leaves $P_WT ignored"
assert_ignored "$Na" "$P_LOCAL" "(a3) WORKING form leaves $P_LOCAL ignored"
assert_ignored "$Na" "$P_LOGS"  "(a3) WORKING form leaves $P_LOGS ignored"

# ============================================================================
echo "== (b) apply on a repo carrying the naive bare excludes → per-path ignore status flips correctly =="
Ab="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Ab"
# The realistic starting point: the plugin's own historical form — bare directory excludes.
printf '# editor\n*.swp\n\n# runtime\n.claude/\n.supervisor/\nlogs/\n' > "$Ab/.gitignore"
assert_ignored "$Ab" "$P_MEM" "(b) precondition: $P_MEM ignored before apply"
out_b="$(mem "$Ab" apply 2>&1)"; rc_b=$?
[ "$rc_b" -eq 0 ] && ok "(b) apply exits 0" || no "(b) apply non-zero ($rc_b)"
has '^apply: applied' "$out_b" && ok "(b) apply reports 'applied'" || no "(b) apply did not report 'applied'"
# INTENDED — one assertion per path.
assert_committable "$Ab" "$P_MEM" "(b) after apply $P_MEM is committable"
assert_committable "$Ab" "$P_LES" "(b) after apply $P_LES is committable"
# A deeper nested file must also survive (the re-included directory is traversable all the way down).
assert_committable "$Ab" ".claude/agent-memory/loomwright:worker/notes/deep.md" "(b) after apply a DEEPLY nested agent-memory file is committable"
# UNINTENDED — one assertion per path, never a bulk claim.
assert_ignored "$Ab" "$P_WT"    "(b) after apply $P_WT stays ignored"
assert_ignored "$Ab" "$P_LOCAL" "(b) after apply $P_LOCAL stays ignored"
assert_ignored "$Ab" "$P_LOGS"  "(b) after apply $P_LOGS stays ignored"
# The bare excludes must be NEUTRALISED, not merely out-ordered (a surviving `.claude/` line
# anywhere defeats the whole block).
gi_b="$(cat "$Ab/.gitignore")"
hasE '^[[:space:]]*\.claude/[[:space:]]*$' "$gi_b" && no "(b) a live bare '.claude/' line survived apply — the negation would be dead" || ok "(b) no live bare '.claude/' line survives apply"
hasE '^[[:space:]]*\.supervisor/[[:space:]]*$' "$gi_b" && no "(b) a live bare '.supervisor/' line survived apply" || ok "(b) no live bare '.supervisor/' line survives apply"
hasE '^\*\.swp$' "$gi_b" && ok "(b) unrelated user rule '*.swp' preserved verbatim" || no "(b) apply dropped an unrelated user rule"
chk_b="$(mem "$Ab" check 2>/dev/null)"
has '^Memory readiness: configured' "$chk_b" && ok "(b) check verdict = configured after apply" || no "(b) check verdict not 'configured' after apply"

# ============================================================================
echo "== (b2) the RECURSIVE '.claude/**' family is neutralised too, and a survivor is not sold as success =="
# `.claude/**` matches every path BELOW the directory and git applies the LAST matching rule, so
# it still beats the block's `!.claude/agent-memory/` (which is directory-only and never matches
# the files inside). A survivor left the negation silently dead under an `apply: applied` headline.
Bx="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Bx"
printf '# editor\n*.swp\n.claude/**\n.supervisor/**\n**/.claude/\n' > "$Bx/.gitignore"
assert_ignored "$Bx" "$P_MEM" "(b2) precondition: '.claude/**' ignores $P_MEM before apply"
out_bx="$(mem "$Bx" apply 2>&1)"; rc_bx=$?
[ "$rc_bx" -eq 0 ] && ok "(b2) apply exits 0 on a '**'-family .gitignore" || no "(b2) apply non-zero ($rc_bx)"
assert_committable "$Bx" "$P_MEM"     "(b2) a pre-existing '.claude/**' no longer defeats the negation"
assert_committable "$Bx" "$P_LES"     "(b2) a pre-existing '.supervisor/**' no longer defeats the negation"
assert_committable "$Bx" "$P_MEM_DOT" "(b2) the dotfile sidecar survives the '**' family too"
assert_ignored "$Bx" "$P_WT"    "(b2) $P_WT still ignored"
assert_ignored "$Bx" "$P_LOGS"  "(b2) $P_LOGS still ignored"
gi_bx="$(cat "$Bx/.gitignore")"
hasE '^[[:space:]]*\.claude/\*\*[[:space:]]*$'     "$gi_bx" && no "(b2) a live '.claude/**' survived apply"     || ok "(b2) '.claude/**' was neutralised"
hasE '^[[:space:]]*\.supervisor/\*\*[[:space:]]*$' "$gi_bx" && no "(b2) a live '.supervisor/**' survived apply" || ok "(b2) '.supervisor/**' was neutralised"
hasE '^[[:space:]]*\*\*/\.claude/[[:space:]]*$'    "$gi_bx" && no "(b2) a live '**/.claude/' survived apply"    || ok "(b2) '**/.claude/' was neutralised"
hasE '^\*\.swp$' "$gi_bx" && ok "(b2) unrelated user rule '*.swp' preserved verbatim" || no "(b2) apply dropped an unrelated user rule"
hasF 'apply: WARNING' "$out_bx" && no "(b2) apply warned even though the negation DID take effect" || ok "(b2) no spurious warning when readiness is 'configured'"
# remove must still round-trip the newly-recognised forms
orig_bx="$(mkfix)/orig.gitignore"; printf '# editor\n*.swp\n.claude/**\n.supervisor/**\n**/.claude/\n' > "$orig_bx"
mem "$Bx" remove >/dev/null 2>&1
if cmp -s "$orig_bx" "$Bx/.gitignore"; then ok "(b2) apply → remove restores the '**'-family .gitignore BYTE-EXACTLY"; else no "(b2) the '**' family did not round-trip through remove"; fi

# A survivor this rewriter does NOT recognise (a deeper `.claude/agent-memory/**`) must be
# reported, not papered over: the headline is qualified and the WINNING pattern is named from a
# real `git check-ignore -v` probe, never guessed.
By="$(newgit https://github.com/acme/widget.git)"
seed_stores "$By"
printf '.claude/\n.claude/agent-memory/**\n' > "$By/.gitignore"
out_by="$(mem "$By" apply 2>&1)"; rc_by=$?
[ "$rc_by" -eq 0 ] && ok "(b2) apply still exits 0 with an unrecognised surviving exclude" || no "(b2) non-zero ($rc_by)"
hasF 'apply: WARNING' "$out_by" && ok "(b2) apply WARNS when the post-write verdict is not 'configured' (no unqualified success)" || no "(b2) apply reported plain success while an intended path stayed ignored"
hasF 'STILL IGNORED' "$out_by" && ok "(b2) the warning says which intended paths are still ignored" || no "(b2) the warning does not flag the still-ignored intended paths"
hasF '.claude/agent-memory/**' "$out_by" && ok "(b2) the warning NAMES the surviving pattern (from git check-ignore -v, not a guess)" || no "(b2) the warning does not name the surviving pattern"

# ============================================================================
echo "== (b3) a user's PRE-EXISTING working '.claude/*' form SURVIVES apply UNCOMMENTED =="
# `X/*` is the one directory-shaped form deliberately absent from comment_bare_excludes' list. Not
# because commenting it could neutralise the module's own fix — it cannot, since
# proposed_applied_content pipes only the STRIPPED pre-existing file through the neutraliser and
# appends the managed block AFTERWARDS — but because `X/*` is not an obstacle at all: it excludes
# the CONTENTS and leaves the directory traversable, which is exactly what the `!` lines need. A
# user who already wrote it is already correct, so neutralising it would be pointless churn (and
# `remove` would then have to restore it). A comment is not a test; this fixture is the pin.
Bz="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Bz"
printf '# editor\n*.swp\n.claude/*\n!.claude/agent-memory/\n.supervisor/\n' > "$Bz/.gitignore"
orig_bz="$(mkfix)/orig.gitignore"; cp "$Bz/.gitignore" "$orig_bz"
out_bz="$(mem "$Bz" apply 2>&1)"; rc_bz=$?
[ "$rc_bz" -eq 0 ] && ok "(b3) apply exits 0 on a .gitignore that already carries the working '.claude/*' form" || no "(b3) apply non-zero ($rc_bz)"
gi_bz="$(cat "$Bz/.gitignore")"
hasE '^# \.claude/\*[[:space:]]' "$gi_bz" && no "(b3) apply COMMENTED OUT the user's pre-existing '.claude/*' — the WORKING form must never be neutralised" || ok "(b3) the user's pre-existing '.claude/*' survives apply UNCOMMENTED"
n_live_bz="$(grep -cE '^\.claude/\*$' <<< "$gi_bz" | tr -d ' ')"
[ "${n_live_bz:-0}" -eq 2 ] && ok "(b3) BOTH live '.claude/*' lines remain (the user's own + the managed block's)" || no "(b3) expected 2 live '.claude/*' lines, found ${n_live_bz:-0} — the user's copy was neutralised"
hasE '^# \.supervisor/[[:space:]]' "$gi_bz" && ok "(b3) the BARE '.supervisor/' in the same file is still neutralised (only the working form is exempt)" || no "(b3) the bare '.supervisor/' was not neutralised"
assert_committable "$Bz" "$P_MEM" "(b3) $P_MEM is committable with a pre-existing working form in place"
assert_ignored "$Bz" "$P_LOGS" "(b3) $P_LOGS still ignored"
mem "$Bz" remove >/dev/null 2>&1
if cmp -s "$orig_bz" "$Bz/.gitignore"; then ok "(b3) apply → remove round-trips a .gitignore carrying the working form BYTE-EXACTLY"; else no "(b3) the pre-existing working form did not round-trip through remove"; fi

# ============================================================================
echo "== (b4) the 'partial' verdict (OVER-inclusion) gets its OWN remediation copy =="
# `partial` fires when an UNINTENDED path becomes COMMITTABLE — the OPPOSITE of (b2)'s surviving
# exclude. Until this fixture existed the branch was entirely undriven, and warn_if_not_configured()
# fell through to the UNDER-inclusion copy: with REPORT_BLOCKED_INTENDED empty it named NOTHING and
# then told the user to "comment out the rule named above" — backwards advice whose remedy (deleting
# an exclude) would leak MORE.
#
# The driver is a NESTED .gitignore, which is the realistic shape: patterns in `.claude/.gitignore`
# take PRECEDENCE over the root file, so an over-broad `!` there survives the appended managed block
# (whose own `.claude/*` would otherwise re-ignore anything a root-level `!` re-included).
B4="$(newgit https://github.com/acme/widget.git)"
seed_stores "$B4"
printf '.claude/\n.supervisor/\n' > "$B4/.gitignore"
printf '!settings.local.json\n!worktrees/\n' > "$B4/.claude/.gitignore"
out_b4="$(mem "$B4" apply 2>&1)"; rc_b4=$?
[ "$rc_b4" -eq 0 ] && ok "(b4) apply exits 0 on an over-including .gitignore (fail-safe)" || no "(b4) apply non-zero ($rc_b4)"
# The verdict really is `partial` — the branch is genuinely driven, not assumed.
has '^Memory readiness: partial' "$out_b4" && ok "(b4) the verdict really IS 'partial' (the branch is driven by a real fixture)" || no "(b4) fixture did not produce a 'partial' verdict (got: $(grep '^Memory readiness:' <<< "$out_b4" | head -n1))"
# ...for the right reason: intended paths fine, unintended leaking.
assert_committable "$B4" "$P_MEM"   "(b4) precondition: the intended $P_MEM is committable (so this is NOT under-inclusion)"
assert_committable "$B4" "$P_LOCAL" "(b4) precondition: the unintended $P_LOCAL LEAKED (committable) — the over-inclusion this branch is about"
hasF 'apply: WARNING' "$out_b4" && ok "(b4) apply WARNS on a 'partial' verdict (no unqualified success headline)" || no "(b4) apply reported plain success while an unintended path was committable"
hasF 'OVER-inclusion' "$out_b4" && ok "(b4) the warning names the failure mode as OVER-inclusion" || no "(b4) the warning does not name over-inclusion"
hasF "$P_LOCAL" "$out_b4" && ok "(b4) the warning NAMES the specific unintended path that became committable" || no "(b4) the warning names no leaked path"
hasF "$P_WT" "$out_b4" && ok "(b4) the warning names the second leaked unintended path too (per path, never a bulk claim)" || no "(b4) the warning omitted a leaked path"
hasF '!settings.local.json' "$out_b4" && ok "(b4) the warning names the winning '!' rule from a real check-ignore -v probe, not a guess" || no "(b4) the warning does not name the winning re-include"
hasi 're-include' "$out_b4" && ok "(b4) the remediation points at the over-broad '!' re-include as the cause" || no "(b4) the remediation does not point at the re-include"
# THE BACKWARDS COPY MUST BE ABSENT. This is the actual regression the branch exists to prevent.
hasi 'comment out the rule named above' "$out_b4" && no "(b4) the MISLEADING under-inclusion copy ('comment out the rule named above') was printed for an over-inclusion failure" || ok "(b4) the misleading under-inclusion copy is NOT printed"
hasF 'STILL IGNORED' "$out_b4" && no "(b4) the warning claimed intended paths are STILL IGNORED when none are" || ok "(b4) the warning does not claim a non-existent under-inclusion"
# and the UNDER-inclusion branch must keep its own copy (no cross-contamination from the new branch)
hasi 'comment out the rule named above' "$out_by" && ok "(b4) the under-inclusion branch (b2) still carries its own 'comment out the rule' remedy" || no "(b4) the under-inclusion remedy was lost from the (b2) path"
hasF 'OVER-inclusion' "$out_by" && no "(b4) the under-inclusion branch wrongly printed the over-inclusion copy" || ok "(b4) the under-inclusion branch does not print over-inclusion copy"

# ============================================================================
echo "== (b5) git's own lexer decides what is an obstacle — leading-space / inline-# forms ignore NOTHING =="
# A reviewer flagged `.claude/   # my note` as escaping comment_bare_excludes' trimmed match. It
# does escape it — and that is CORRECT, because git has NO inline-comment syntax and does not strip
# LEADING whitespace: neither form excludes anything under `.claude/`, so neither is an obstacle to
# the negation and neutralising it would rewrite a user's file for no benefit. Asserted against real
# `git check-ignore`, because "git treats it as X" is exactly the kind of claim that must be probed.
B5="$(newgit https://github.com/acme/widget.git)"
seed_stores "$B5"
printf '.claude/   # my note\n   .supervisor/\n' > "$B5/.gitignore"
assert_committable "$B5" "$P_MEM" "(b5) an INLINE-# '.claude/   # my note' line does not ignore $P_MEM (git has no inline comments)"
assert_committable "$B5" "$P_LOCAL" "(b5) it does not ignore $P_LOCAL either — it is not a directory exclude at all"
assert_committable "$B5" "$P_LES" "(b5) a LEADING-whitespace '   .supervisor/' line does not ignore $P_LES (git keeps leading whitespace)"
# TRAILING whitespace IS stripped by git, so that form IS a real obstacle — and IS neutralised.
B5b="$(newgit https://github.com/acme/widget.git)"
seed_stores "$B5b"
printf '.claude/   \n' > "$B5b/.gitignore"
assert_ignored "$B5b" "$P_MEM" "(b5) by contrast a TRAILING-whitespace '.claude/   ' IS a real exclude in git (trailing space is stripped)"
out_b5b="$(mem "$B5b" apply 2>&1)"
has '^Memory readiness: configured' "$out_b5b" && ok "(b5) apply neutralises the trailing-whitespace form (verdict configured)" || no "(b5) the trailing-whitespace exclude was not neutralised"
assert_committable "$B5b" "$P_MEM" "(b5) $P_MEM is committable after neutralising the trailing-whitespace exclude"
# The non-obstacle forms survive apply UNTOUCHED and still round-trip byte-exactly through remove.
orig_b5="$(mkfix)/orig.gitignore"; cp "$B5/.gitignore" "$orig_b5"
out_b5="$(mem "$B5" apply 2>&1)"
gi_b5="$(cat "$B5/.gitignore")"
hasF '.claude/   # my note' "$gi_b5" && ok "(b5) the inline-# line survives apply verbatim (not commented, not dropped)" || no "(b5) apply mangled the inline-# line"
hasF '   .supervisor/' "$gi_b5" && ok "(b5) the leading-whitespace line survives apply verbatim" || no "(b5) apply mangled the leading-whitespace line"
has '^Memory readiness: configured' "$out_b5" && ok "(b5) the verdict is 'configured' — leaving the non-obstacles live costs nothing" || no "(b5) leaving the non-obstacle forms live broke the negation"
mem "$B5" remove >/dev/null 2>&1
if cmp -s "$orig_b5" "$B5/.gitignore"; then ok "(b5) apply → remove round-trips the non-obstacle forms BYTE-EXACTLY"; else no "(b5) the non-obstacle forms did not round-trip through remove"; fi

# ============================================================================
echo "== (c) dotfile sidecars commit — asserted explicitly, separately from the ** globs =="
# Their absence would silently strip provenance from a fresh clone (read-lessons.sh's read-side
# provenance gate depends on them), and a dotfile inside a re-included directory is its own
# silent-failure class — so these get their own assertions, not a '** covers it' claim.
assert_committable "$Ab" "$P_MEM_DOT" "(c) dotfile sidecar $P_MEM_DOT is committable"
assert_committable "$Ab" "$P_LES_DOT" "(c) dotfile sidecar $P_LES_DOT is committable"

# ============================================================================
echo "== (d) allowlist — a LIST, rename-tolerant, foreign records excluded, remote-defaulted =="
if [ -z "$JQ" ]; then
  ok "(d) jq unavailable — allowlist/ledger group skipped (pass)"
else
  # (d1) fresh install with NO config → defaults to the CURRENT remote's owner/repo.
  D1="$(newgit https://github.com/acme/widget.git)"
  al_d1="$(mem "$D1" allowlist 2>/dev/null)"
  [ "$al_d1" = "acme/widget" ] && ok "(d1) fresh install defaults the allowlist to the current remote (acme/widget)" || no "(d1) fresh-install default wrong (got: $al_d1)"
  src_d1="$(mem "$D1" allowlist 2>&1 >/dev/null)"
  hasF 'default (current git remote)' "$src_d1" && ok "(d1) source reported as 'default (current git remote)'" || no "(d1) allowlist source not reported as the remote default (got: $src_d1)"
  # ssh scp-style remotes resolve identically (no owner is ever hardcoded).
  D1b="$(newgit git@github.com:someone-else/other-repo.git)"
  al_d1b="$(mem "$D1b" allowlist 2>/dev/null)"
  [ "$al_d1b" = "someone-else/other-repo" ] && ok "(d1) ssh scp-style remote resolves to owner/repo (no hardcoded owner)" || no "(d1) ssh remote did not resolve (got: $al_d1b)"

  # (d2) apply STORES the allowlist as a JSON ARRAY — never a string.
  D2="$(newgit https://github.com/acme/widget.git)"
  printf '.claude/\n.supervisor/\n' > "$D2/.gitignore"
  mem "$D2" apply >/dev/null 2>&1
  cfg_type="$(jq -r '.setup_memory.repo_allowlist | type' "$D2/.supervisor/config.json" 2>/dev/null)"
  [ "$cfg_type" = "array" ] && ok "(d2) seeded .setup_memory.repo_allowlist is a JSON array (never a string)" || no "(d2) seeded allowlist type is '$cfg_type', expected array"
  [ "$(jq -r '.setup_memory.repo_allowlist[0]' "$D2/.supervisor/config.json" 2>/dev/null)" = "acme/widget" ] && ok "(d2) seeded entry is the current remote" || no "(d2) seeded entry wrong"
  # unrelated config keys survive the merge
  D2b="$(newgit https://github.com/acme/widget.git)"
  printf '.claude/\n' > "$D2b/.gitignore"
  mkdir -p "$D2b/.supervisor"; printf '{"auto_review": false, "other": {"k": 1}}\n' > "$D2b/.supervisor/config.json"
  mem "$D2b" apply >/dev/null 2>&1
  [ "$(jq -r '.auto_review' "$D2b/.supervisor/config.json" 2>/dev/null)" = "false" ] && ok "(d2) unrelated config key .auto_review survived the allowlist merge" || no "(d2) allowlist merge clobbered an unrelated config key"
  [ "$(jq -r '.other.k' "$D2b/.supervisor/config.json" 2>/dev/null)" = "1" ] && ok "(d2) nested unrelated config key survived" || no "(d2) nested unrelated config key lost"

  # (d3) THE RENAME CASE — the reason the field is a list at all. A ledger holding records under a
  # PRE-RENAME slug and the CURRENT slug must retain BOTH when both are listed.
  D3="$(newgit https://github.com/acme/widget.git)"
  cat > "$D3/ledger.jsonl" <<'LEDGER'
{"repo":"acme/old-name","number":1,"review_rounds":3}
{"repo":"acme/widget","number":2,"review_rounds":1}
{"repo":"stranger/elsewhere","number":3,"review_rounds":9}
{"number":4,"review_rounds":0}
LEDGER
  both="$(mem "$D3" filter-ledger --ledger "$D3/ledger.jsonl" --allow acme/widget --allow acme/old-name 2>/dev/null)"
  # jq, never grep — `grep -c '"repo"'` cannot see a SPACED-form record and would under-count here
  # exactly as it does against this plugin's own ledger. See the header note and group (l2).
  n_both="$(ledger_count "$both")"
  [ "$n_both" = "2" ] && ok "(d3) rename case: records under BOTH slugs retained (2 of 4, counted with jq)" || no "(d3) rename case retained $n_both records, expected 2"
  ledger_has_repo "$both" "acme/old-name" && ok "(d3) the PRE-RENAME slug's record is retained (a live-remote filter would have dropped it)" || no "(d3) pre-rename record dropped"
  ledger_has_repo "$both" "acme/widget"   && ok "(d3) the current slug's record is retained" || no "(d3) current-slug record dropped"
  # (d4) a record OUTSIDE the allowlist is excluded.
  ledger_has_repo "$both" "stranger/elsewhere" && no "(d4) a foreign-repo record leaked through the filter" || ok "(d4) foreign-repo record 'stranger/elsewhere' excluded"
  ledger_has_field "$both" number 4 && no "(d4) a record with NO .repo leaked through (unattributable must be excluded)" || ok "(d4) record with no .repo excluded (unattributable → not retained)"
  # (d5) the live-remote default alone drops the pre-rename half — the documented hazard, asserted.
  only_remote="$(mem "$D3" filter-ledger --ledger "$D3/ledger.jsonl" 2>/dev/null)"
  ledger_has_repo "$only_remote" "acme/old-name" && no "(d5) remote-only allowlist unexpectedly retained the pre-rename record" || ok "(d5) remote-only allowlist DROPS the pre-rename record — this is exactly why the allowlist is a list"
  ledger_has_repo "$only_remote" "acme/widget" && ok "(d5) remote-only allowlist still retains the current slug" || no "(d5) remote-only allowlist retained nothing at all"
  # (d6) an empty allowlist retains NOTHING (fail-closed), never everything.
  D6="$(newgit)"   # no remote at all
  cp "$D3/ledger.jsonl" "$D6/ledger.jsonl"
  empty_out="$(mem "$D6" filter-ledger --ledger "$D6/ledger.jsonl" 2>/dev/null)"
  [ -z "$empty_out" ] && ok "(d6) empty allowlist retains NOTHING (fail-closed, never 'everything')" || no "(d6) empty allowlist leaked records"
  src_d6="$(mem "$D6" allowlist 2>&1 >/dev/null)"
  hasF 'unset (no git remote' "$src_d6" && ok "(d6) no-remote fixture reports the allowlist source as unset" || no "(d6) no-remote source label wrong (got: $src_d6)"
  # (d7) a STRING-shaped allowlist is warned about (the stored shape must be a list).
  D7="$(newgit)"
  mkdir -p "$D7/.supervisor"; printf '{"setup_memory":{"repo_allowlist":"acme/widget"}}\n' > "$D7/.supervisor/config.json"
  warn_d7="$(mem "$D7" allowlist 2>&1 >/dev/null)"
  hasi 'MUST be a JSON array' "$warn_d7" && ok "(d7) a STRING allowlist is loudly flagged as a misconfiguration" || no "(d7) string-shaped allowlist accepted silently (got: $warn_d7)"
  # (d8) a malformed ledger line is skipped, not fatal.
  printf 'NOT JSON AT ALL\n{"repo":"acme/widget","number":99}\n' >> "$D3/ledger.jsonl"
  robust="$(mem "$D3" filter-ledger --ledger "$D3/ledger.jsonl" --allow acme/widget 2>/dev/null)"; rc_r=$?
  [ "$rc_r" -eq 0 ] && ok "(d8) filter-ledger exits 0 on a ledger containing a malformed line" || no "(d8) filter-ledger non-zero on malformed line ($rc_r)"
  ledger_has_field "$robust" number 99 && ok "(d8) records AFTER the malformed line are still retained (per-line fallback works)" || no "(d8) the malformed line swallowed the rest of the ledger"

  # (d10) AN UNTERMINATED FINAL LINE IS STILL FILTERED — the `|| [ -n "$line" ]` guard on
  # filter_ledger_by_allowlist's per-line fallback, pinned.
  #
  # THE FIXTURE DELIBERATELY OMITS THE TRAILING NEWLINE — same reason as group (l8), and it must not
  # be "tidied" into one. A bare `while IFS= read -r line; do … done < "$ledger"` NEVER RUNS ITS BODY
  # for an unterminated final line (`read` returns non-zero at EOF even though it filled $line), and
  # every OTHER filter-ledger fixture above ends with a newline, so nothing else here can catch it.
  # Here the loss is in the OPPOSITE direction from (l8): the dropped final line is a VALID,
  # ALLOWLISTED record, so it is silently absent from `filter-ledger > tmp && mv tmp ledger` — the
  # documented remedy — i.e. real data loss in the exact path users are told to run.
  D10="$(newgit https://github.com/acme/widget.git)"
  # The malformed middle line is what forces the per-line FALLBACK (the whole-file jq pass aborts);
  # without it the guard is never reached and this case would assert nothing.
  printf '%s\n%s\n%s' \
    '{"repo":"acme/widget","number":1}' \
    'NOT JSON AT ALL' \
    '{"repo":"acme/widget","number":3}' > "$D10/ledger.jsonl"
  tail_out="$(mem "$D10" filter-ledger --ledger "$D10/ledger.jsonl" --allow acme/widget 2>/dev/null)"
  ledger_has_field "$tail_out" number 1 && ok "(d10) the record BEFORE the malformed line is retained" || no "(d10) the leading record was dropped"
  # THE assertion — this is the one that goes red when `|| [ -n "$line" ]` is reverted.
  ledger_has_field "$tail_out" number 3 && ok "(d10) a VALID allowlisted FINAL record with NO trailing newline is RETAINED (unterminated-line guard)" || no "(d10) the unterminated final record was SILENTLY DROPPED — data loss in the filter-ledger remedy path"
  # NEGATIVE CONTROL — the guard recovers the line, it does not defeat jq's `select`. Same shape,
  # same missing trailing newline, but the final record is FOREIGN and must still be excluded.
  D10b="$(newgit https://github.com/acme/widget.git)"
  printf '%s\n%s\n%s' \
    '{"repo":"acme/widget","number":1}' \
    'NOT JSON AT ALL' \
    '{"repo":"stranger/elsewhere","number":3}' > "$D10b/ledger.jsonl"
  tail_foreign="$(mem "$D10b" filter-ledger --ledger "$D10b/ledger.jsonl" --allow acme/widget 2>/dev/null)"
  ledger_has_repo "$tail_foreign" "stranger/elsewhere" && no "(d10) a FOREIGN unterminated final record leaked through — the guard defeated the allowlist filter" || ok "(d10) a FOREIGN final record with NO trailing newline is still EXCLUDED (guard recovers the line, jq still filters it)"
fi

# (d9) A FILESYSTEM-PATH REMOTE CARRIES NO OWNER. `origin = /Users/x/myrepo` has the same shape as
# `host/owner/repo` once you only look at the last two segments, so a naive tail split returns
# `x/myrepo` — an owner invented from a parent DIRECTORY name, which contradicts remote_slug's own
# "NEVER guesses an owner" contract and would silently mis-scope the ledger filter.
# (Outside the jq guard on purpose: `allowlist` resolution needs no jq.)
D9="$(newgit /Users/someone/parent-dir/myrepo)"
al_d9="$(mem "$D9" allowlist 2>/dev/null)"
[ -z "$al_d9" ] && ok "(d9) a filesystem-path remote yields NO allowlist default (no owner fabricated from a parent dir)" || no "(d9) a filesystem-path remote fabricated the owner '$al_d9'"
src_d9="$(mem "$D9" allowlist 2>&1 >/dev/null)"
hasF 'unset (no git remote' "$src_d9" && ok "(d9) the path remote is reported as 'unset', not as a resolved default" || no "(d9) wrong source label for a path remote (got: $src_d9)"
D9b="$(newgit ../sibling-repo)"
[ -z "$(mem "$D9b" allowlist 2>/dev/null)" ] && ok "(d9) a RELATIVE path remote also yields no default" || no "(d9) a relative path remote fabricated an owner"
D9c="$(newgit ssh://git@github.com/acme/widget.git)"
[ "$(mem "$D9c" allowlist 2>/dev/null)" = "acme/widget" ] && ok "(d9) a real ssh:// URL still resolves (the path guard did not over-reject)" || no "(d9) the path guard broke ssh:// URL resolution"

# ============================================================================
echo "== (e) idempotency + BACKUP-BEFORE-WRITE — a second apply is a no-op that writes NOTHING =="
Ee="$(newgit https://github.com/acme/widget.git)"
printf '# junk\n.claude/\n.supervisor/\n' > "$Ee/.gitignore"
# Snapshot the PRISTINE user file BEFORE the first apply. Backup-first is the module's only
# user-data safety net, so it is asserted POSITIVELY below (the backup EXISTS and its CONTENT is
# this snapshot) — never as a count comparison across the no-op second apply, which passes as
# "0 = 0" when no backup is ever written and left `cp "$GI" "$backup"` completely unasserted.
gi_pristine="$(sum "$Ee/.gitignore")"
mem "$Ee" apply >/dev/null 2>&1
gi1="$(sum "$Ee/.gitignore")"
cfg1="$(sum "$Ee/.supervisor/config.json" 2>/dev/null || echo none)"
bk1="$(ls "$Ee"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' ')"
bk1_path="$(ls "$Ee"/.gitignore.backup.* 2>/dev/null | head -n1)"
[ "$bk1" -eq 1 ] && ok "(e) the first apply wrote EXACTLY ONE .gitignore.backup.* (backup-before-write happened at all)" || no "(e) the first apply wrote $bk1 backup(s), expected exactly 1 — backup-before-write did NOT happen"
if [ -n "$bk1_path" ] && [ "$(sum "$bk1_path")" = "$gi_pristine" ]; then
  ok "(e) that backup holds the PRISTINE pre-apply .gitignore byte-for-byte (recoverable original)"
else
  no "(e) the backup does not match the pre-apply .gitignore — the user's original is NOT recoverable"
fi
[ "$gi1" != "$gi_pristine" ] && ok "(e) the first apply really did rewrite .gitignore (the backup is not a copy of the new file)" || no "(e) the first apply did not change .gitignore — the backup assertion above would be vacuous"
out_e="$(mem "$Ee" apply 2>&1)"; rc_e=$?
gi2="$(sum "$Ee/.gitignore")"
cfg2="$(sum "$Ee/.supervisor/config.json" 2>/dev/null || echo none)"
bk2="$(ls "$Ee"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' ')"
[ "$rc_e" -eq 0 ] && ok "(e) second apply exits 0" || no "(e) second apply non-zero ($rc_e)"
# Anchored to the apply STATUS LINE: `seed_allowlist` prints "already configured" on every second
# apply regardless of what the .gitignore path did, so `hasi 'already configured'` was passing
# without discriminating the no-op at all.
has '^apply: no-op' "$out_e" && ok "(e) second apply reports the 'apply: no-op' status line" || no "(e) second apply did not report 'apply: no-op'"
[ "$gi1" = "$gi2" ] && ok "(e) .gitignore byte-identical after the second apply (nothing written)" || no "(e) second apply MUTATED .gitignore"
[ "$cfg1" = "$cfg2" ] && ok "(e) .supervisor/config.json byte-identical after the second apply" || no "(e) second apply MUTATED the config"
[ "$bk2" -eq 1 ] && ok "(e) still EXACTLY ONE backup after the no-op apply (it wrote none)" || no "(e) the no-op apply changed the backup count ($bk1 → $bk2)"
c1="$(mem "$Ee" check 2>/dev/null)"; c2="$(mem "$Ee" check 2>/dev/null)"
[ "$c1" = "$c2" ] && ok "(e) check stdout byte-identical across two runs" || no "(e) check stdout differed between runs"

# --- SAME-SECOND BACKUP COLLISION -------------------------------------------------------------
# The backup name is second-granular, so two applies inside one second resolve to the same path
# and the second `cp` would OVERWRITE the first backup — losing the user's pristine original and
# leaving only a copy of the tool's own output. Driven with a PINNED clock (a fake `date` first on
# PATH) so the collision is deterministic instead of a race the suite would only sometimes hit.
Ec="$(newgit https://github.com/acme/widget.git)"
printf '# junk\n.claude/\n' > "$Ec/.gitignore"
ec_pristine="$(sum "$Ec/.gitignore")"
mkdir -p "$Ec/fakebin"
printf '#!/bin/sh\necho 20260101-000000\n' > "$Ec/fakebin/date"
chmod +x "$Ec/fakebin/date"
PATH="$Ec/fakebin:$PATH" bash "$MEM" --root "$Ec" apply >/dev/null 2>&1
printf '*.log\n' >> "$Ec/.gitignore"   # forces the SECOND apply to be a real write, not a no-op
PATH="$Ec/fakebin:$PATH" bash "$MEM" --root "$Ec" apply >/dev/null 2>&1
n_bk_ec="$(ls "$Ec"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' ')"
[ "$n_bk_ec" -eq 2 ] && ok "(e) two applies in the SAME second produce TWO distinct backups (no collision)" || no "(e) same-second applies left $n_bk_ec backup(s) — one overwrote the other"
[ "$(sum "$Ec/.gitignore.backup.20260101-000000")" = "$ec_pristine" ] && ok "(e) the FIRST backup still holds the pristine original after the same-second second apply" || no "(e) the same-second second apply OVERWROTE the user's pristine original backup"

# --- BACKUP-NAME EXHAUSTION MUST FAIL CLOSED --------------------------------------------------
# unique_backup_path escalates <file>.backup.<ts> → .<pid> → .<pid>.<n> with the counter BOUNDED,
# so "a free name always exists" is not something it can promise. It used to fall out of the loop
# AT the bound and return `.<pid>.<bound>` with that file still present — a path it never verified,
# which the caller's `cp` would then have OVERWRITTEN. It now returns EMPTY and write_gitignore
# aborts. Driven deterministically, not as a race: the clock is pinned with a fake `date` on PATH,
# and the seeding must happen while the helper is alive but has not yet run, because the candidate
# names are qualified by the helper's OWN pid — which does not exist until it is running. That
# chicken-and-egg is the only reason a handshake exists here at all.
#
# THE HANDSHAKE MUST NOT BE ABLE TO HANG THIS SUITE, ON ANY PLATFORM. This file is a HARD CI GATE
# inside a `for t in test-*.sh` loop that sets NO per-test timeout, so a wedged fixture does not
# report a failure — it burns the entire job. An earlier revision sequenced this with a FIFO, which
# put a blocking open(2) on the critical path (`echo go > fifo` blocks until a reader arrives) and
# then tried to defuse it with `exec 9<>` — O_RDWR on a FIFO, which is formally UNDEFINED in POSIX
# and therefore a portability bet, not a guarantee. Both are gone. The gate is now two plain files
# and two BOUNDED polls, so no step can block on any platform:
#   · the helper publishes its own `$$` (atomically: write-temp + rename) and then polls for `go`
#   · the parent polls for `pid`, seeds every candidate name, then creates `go`
#   · BOTH loops are capped at a fixed iteration count (~60s of budget either way). Exhaustion is
#     never silent: the helper exits 97 with a distinct message, the parent records a FAILED
#     assertion. The parent's `wait` is therefore bounded by the helper's own cap even if the
#     helper is never released, and a helper that dies early just makes `wait` return immediately.
# Fractional `sleep` is a GNU/BSD extension, not POSIX, so it is PROBED once rather than assumed —
# a shell without it falls back to whole seconds with a proportionally smaller cap, never to a
# spin that would exhaust the bound instantly and fail spuriously.
if sleep 0.05 2>/dev/null; then gate_unit=0.05; gate_max=1200; else gate_unit=1; gate_max=60; fi
Ex="$(newgit https://github.com/acme/widget.git)"
printf '# junk\n.claude/\n' > "$Ex/.gitignore"
ex_pristine="$(sum "$Ex/.gitignore")"
mkdir -p "$Ex/fakebin"
printf '#!/bin/sh\necho 20260101-000000\n' > "$Ex/fakebin/date"
chmod +x "$Ex/fakebin/date"
# $1=fixture root, $2=setup-memory.sh, $3=poll unit, $4=poll cap. `$$` here is the helper's own pid
# and survives the `exec`, so it is the pid `unique_backup_path` will use.
bash -c '
  printf "%s\n" "$$" > "$1/pid.tmp" && mv -f "$1/pid.tmp" "$1/pid"
  n=0
  while [ ! -e "$1/go" ]; do
    n=$((n + 1))
    [ "$n" -le "$4" ] || { echo "fixture: helper timed out waiting for the go flag" >&2; exit 97; }
    sleep "$3"
  done
  export PATH="$1/fakebin:$PATH"
  exec bash "$2" --root "$1" apply
' _ "$Ex" "$MEM" "$gate_unit" "$gate_max" > "$Ex/out.txt" 2>&1 &
ex_job=$!
ex_pid=""; n=0
while [ "$n" -le "$gate_max" ]; do
  if [ -s "$Ex/pid" ]; then ex_pid="$(cat "$Ex/pid" 2>/dev/null)"; [ -n "$ex_pid" ] && break; fi
  n=$((n + 1)); sleep "$gate_unit"
done
[ -n "$ex_pid" ] && ok "(e) the exhaustion helper published its pid before the seeding step" || no "(e) the exhaustion helper never published a pid within the poll bound — fixture did not run"
ex_base="$Ex/.gitignore.backup.20260101-000000"
: > "$ex_base"                         # the pristine-original slot — must NOT be clobbered
if [ -n "$ex_pid" ]; then
  : > "$ex_base.$ex_pid"               # the pid-qualified fallback
  touch "$ex_base.$ex_pid."{1..1000}   # every counter slot, up to the helper's bound
fi
ex_seed_sum="$(sum "$ex_base")"
: > "$Ex/go"                           # release the helper; it calls the pinned `date` from here on
wait "$ex_job"; rc_ex=$?
ex_out="$(cat "$Ex/out.txt" 2>/dev/null)"
[ "$rc_ex" -eq 0 ] && ok "(e) apply still exits 0 when no backup name is free (fail-safe)" || no "(e) apply exited $rc_ex on backup exhaustion"
has '^apply: ABORTED' "$ex_out" && ok "(e) apply ABORTS when no non-colliding backup name can be derived" || no "(e) apply did not abort on backup exhaustion (got: $(head -n3 <<< "$ex_out"))"
# Pin the EXHAUSTION branch specifically — a generic `cp`-failure abort would satisfy the line above.
hasF 'refusing to overwrite an existing backup' "$ex_out" && ok "(e) the abort names backup-name EXHAUSTION as the reason (not a generic cp failure)" || no "(e) the abort did not come from the exhaustion branch"
[ "$(sum "$Ex/.gitignore")" = "$ex_pristine" ] && ok "(e) .gitignore is byte-identical after the exhaustion abort (nothing written)" || no "(e) .gitignore was REWRITTEN despite having no backup"
[ "$(sum "$ex_base")" = "$ex_seed_sum" ] && ok "(e) the pre-existing backup was NOT overwritten (the user's pristine original survives)" || no "(e) the exhausted path CLOBBERED an existing backup"

# ============================================================================
echo "== (f) absent / unparseable .gitignore — change nothing, say why, no partial write =="
# (f1) ABSENT — nothing is ignoring the stores, so there is nothing to negate.
F1="$(newgit)"
out_f1="$(mem "$F1" apply 2>&1)"; rc_f1=$?
[ "$rc_f1" -eq 0 ] && ok "(f1) apply on a repo with NO .gitignore exits 0 (fail-safe)" || no "(f1) non-zero on absent .gitignore ($rc_f1)"
has '^apply: ABORTED' "$out_f1" && ok "(f1) apply reports ABORTED on an absent .gitignore" || no "(f1) apply did not report ABORTED"
hasi 'no .gitignore' "$out_f1" && ok "(f1) the abort states WHY (no .gitignore)" || no "(f1) abort gave no reason"
[ ! -e "$F1/.gitignore" ] && ok "(f1) no .gitignore was created (changed nothing)" || no "(f1) apply CREATED a .gitignore"

# (f2) UNPARSEABLE — unresolved conflict markers.
F2="$(newgit)"
printf '.claude/\n<<<<<<< HEAD\n.supervisor/\n=======\n.supervisor/*\n>>>>>>> other\n' > "$F2/.gitignore"
before_f2="$(sum "$F2/.gitignore")"
out_f2="$(mem "$F2" apply 2>&1)"; rc_f2=$?
[ "$rc_f2" -eq 0 ] && ok "(f2) apply on a conflict-marked .gitignore exits 0" || no "(f2) non-zero ($rc_f2)"
has '^apply: ABORTED' "$out_f2" && ok "(f2) apply ABORTS on a conflict-marked .gitignore" || no "(f2) apply did not abort on conflict markers"
hasi 'conflict marker' "$out_f2" && ok "(f2) the abort names the reason (conflict markers)" || no "(f2) abort did not name the reason"
[ "$before_f2" = "$(sum "$F2/.gitignore")" ] && ok "(f2) .gitignore byte-identical after the abort (no partial write)" || no "(f2) .gitignore MUTATED despite the abort"
[ -z "$(ls "$F2"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f2) no backup written on the abort path (nothing was staged)" || no "(f2) a backup was written despite aborting"

# (f3) UNPARSEABLE — a half-deleted managed block (hand-edited: BEGIN without END).
F3="$(newgit)"
printf '.claude/\n# >>> loomwright /setup memory BEGIN — committable Twin stores (managed block) >>>\n.claude/*\n' > "$F3/.gitignore"
before_f3="$(sum "$F3/.gitignore")"
out_f3="$(mem "$F3" apply 2>&1)"
has '^apply: ABORTED' "$out_f3" && ok "(f3) apply ABORTS on an unbalanced managed block (hand-edited)" || no "(f3) apply did not abort on an unbalanced block"
hasi 'sentinel' "$out_f3" && ok "(f3) the abort names the sentinel imbalance" || no "(f3) abort did not name the sentinel problem"
[ "$before_f3" = "$(sum "$F3/.gitignore")" ] && ok "(f3) .gitignore unchanged after the sentinel abort" || no "(f3) .gitignore MUTATED on the sentinel abort path"
# remove must abort on the same input rather than half-repairing it
out_f3r="$(mem "$F3" remove 2>&1)"
has '^remove: ABORTED' "$out_f3r" && ok "(f3) remove ABORTS on the same unparseable file (never half-repairs)" || no "(f3) remove did not abort on an unparseable file"
[ "$before_f3" = "$(sum "$F3/.gitignore")" ] && ok "(f3) .gitignore unchanged after the remove abort" || no "(f3) remove MUTATED an unparseable .gitignore"

# (f4) AN INDENTED BEGIN SENTINEL MUST NEVER PRODUCE A DUPLICATED BLOCK.
# The presence gate counts sentinels with `grep -F` (substring, anywhere on the line) while the
# stripper used to anchor at column 1. An indented BEGIN therefore passed the gate as "one valid
# block" but was NOT stripped, so apply APPENDED a second block — after which the file held
# BEGIN x2 / END x2 and every later apply AND remove aborted with "duplicated managed-block
# sentinels": a corrupt state the tool created itself and then refused to repair. One matcher now
# serves both, so the file must stay repairable by BOTH subcommands.
F4="$(newgit https://github.com/acme/widget.git)"
seed_stores "$F4"
{
  printf '# editor\n*.swp\n.claude/\n'
  printf '   # >>> loomwright /setup memory BEGIN — committable Twin stores (managed block) >>>\n'
  printf '.claude/*\n!.claude/agent-memory/\n'
  printf '   # <<< loomwright /setup memory END <<<\n'
} > "$F4/.gitignore"
out_f4="$(mem "$F4" apply 2>&1)"; rc_f4=$?
[ "$rc_f4" -eq 0 ] && ok "(f4) apply on an INDENTED-sentinel .gitignore exits 0" || no "(f4) non-zero ($rc_f4)"
nb_f4="$(grep -cF '>>> loomwright /setup memory BEGIN' "$F4/.gitignore" 2>/dev/null | tr -d ' ')"
ne_f4="$(grep -cF '<<< loomwright /setup memory END'   "$F4/.gitignore" 2>/dev/null | tr -d ' ')"
[ "${nb_f4:-0}" -eq 1 ] && [ "${ne_f4:-0}" -eq 1 ] && ok "(f4) apply left EXACTLY ONE managed block (indented sentinel stripped, never duplicated)" || no "(f4) apply left BEGIN x${nb_f4:-0} / END x${ne_f4:-0} — it duplicated the block and bricked the file"
assert_committable "$F4" "$P_MEM" "(f4) the rewritten file still makes $P_MEM committable"
# the brick state must be UNREACHABLE: both subcommands still work on the once-indented file
out_f4b="$(mem "$F4" apply 2>&1)"
hasi 'duplicated managed-block sentinels' "$out_f4b" && no "(f4) a follow-up apply is BRICKED with 'duplicated managed-block sentinels'" || ok "(f4) a follow-up apply is not bricked"
has '^apply: no-op' "$out_f4b" && ok "(f4) the follow-up apply is a clean no-op (the first pass produced canonical content)" || no "(f4) the follow-up apply was not a no-op"
out_f4r="$(mem "$F4" remove 2>&1)"; rc_f4r=$?
[ "$rc_f4r" -eq 0 ] && ok "(f4) remove exits 0 on the once-indented file" || no "(f4) remove non-zero ($rc_f4r)"
hasi 'duplicated managed-block sentinels' "$out_f4r" && no "(f4) remove is BRICKED on the same file" || ok "(f4) remove is not bricked either"
nb_f4r="$(grep -cF 'loomwright /setup memory' "$F4/.gitignore" 2>/dev/null | tr -d ' ')"
[ "${nb_f4r:-1}" -eq 0 ] && ok "(f4) remove leaves NO managed-block sentinel behind (fully repairable)" || no "(f4) remove left ${nb_f4r} managed-block line(s) behind"

# (f5) SYMLINK — the gate refuses to FOLLOW it. The point is not merely "abort": it is that
# someone else's file (the link TARGET) is never rewritten, and the link itself is left intact.
F5="$(newgit)"
printf '# someone else owns this\n.claude/\n.supervisor/\n' > "$F5/real-gitignore.txt"
target_f5="$(sum "$F5/real-gitignore.txt")"
ln -s real-gitignore.txt "$F5/.gitignore" \
  || setup_fail "(f5) ln -s failed — $F5/.gitignore could not be made a symlink"
# Assert the SHAPE, not just ln's exit status: this whole group is meaningless unless .gitignore
# really is a symlink at the moment apply runs.
[ -L "$F5/.gitignore" ] || setup_fail "(f5) $F5/.gitignore is not a symlink after ln -s"
out_f5="$(mem "$F5" apply 2>&1)"; rc_f5=$?
[ "$rc_f5" -eq 0 ] && ok "(f5) apply on a SYMLINK .gitignore exits 0 (fail-safe)" || no "(f5) non-zero ($rc_f5)"
has '^apply: ABORTED' "$out_f5" && ok "(f5) apply ABORTS on a symlinked .gitignore" || no "(f5) apply did not abort on a symlink"
hasi 'symlink' "$out_f5" && ok "(f5) the abort names the reason (symlink)" || no "(f5) abort did not name the symlink"
[ -L "$F5/.gitignore" ] && ok "(f5) .gitignore is STILL a symlink (the link was not replaced by a regular file)" || no "(f5) the symlink was clobbered"
[ "$target_f5" = "$(sum "$F5/real-gitignore.txt")" ] && ok "(f5) the symlink TARGET is byte-identical (someone else's file was not rewritten)" || no "(f5) the rewriter FOLLOWED the symlink and mutated the target"
[ -z "$(ls "$F5"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f5) no backup written on the symlink abort path" || no "(f5) a backup was written despite aborting"

# (f6) NON-REGULAR FILE — a directory named .gitignore exists (`-e` true, `-f` false), so the
# absent branch must NOT swallow it and the rewriter must not try to write through it.
F6="$(newgit)"
mkdir "$F6/.gitignore" || setup_fail "(f6) mkdir failed — $F6/.gitignore could not be made a directory"
[ -d "$F6/.gitignore" ] && [ ! -L "$F6/.gitignore" ] \
  || setup_fail "(f6) $F6/.gitignore is not a plain directory after mkdir"
out_f6="$(mem "$F6" apply 2>&1)"; rc_f6=$?
[ "$rc_f6" -eq 0 ] && ok "(f6) apply on a DIRECTORY named .gitignore exits 0 (fail-safe)" || no "(f6) non-zero ($rc_f6)"
has '^apply: ABORTED' "$out_f6" && ok "(f6) apply ABORTS on a non-regular .gitignore" || no "(f6) apply did not abort on a non-regular file"
hasi 'not a regular file' "$out_f6" && ok "(f6) the abort names the reason (not a regular file)" || no "(f6) abort did not name the non-regular file"
[ -d "$F6/.gitignore" ] && ok "(f6) .gitignore is STILL a directory (nothing was written through it)" || no "(f6) the .gitignore directory was replaced"
[ -z "$(ls "$F6"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f6) no backup written on the non-regular abort path" || no "(f6) a backup was written despite aborting"

# (f7) NOT READABLE/WRITABLE — `chmod 000`. SKIPPED UNDER ROOT: root bypasses the permission
# bits entirely, so `[ -r ]`/`[ -w ]` are both true there and the guard legitimately does not
# fire; asserting it would fail spuriously in a root CI container.
if [ "$(id -u)" = 0 ]; then
  ok "(f7) running as root — the chmod-000 permission fixture is skipped (root bypasses mode bits)"
else
  F7="$(newgit)"
  printf '# editor\n*.swp\n.claude/\n' > "$F7/.gitignore" \
    || setup_fail "(f7) could not write $F7/.gitignore"
  before_f7="$(sum "$F7/.gitignore")"
  chmod 000 "$F7/.gitignore" || setup_fail "(f7) chmod 000 failed on $F7/.gitignore"
  # The guard under test is the permission bits, so assert they really did take — a fixture that
  # is still readable would make the "did not abort" assertion below a false accusation.
  { [ ! -r "$F7/.gitignore" ] || [ ! -w "$F7/.gitignore" ]; } \
    || setup_fail "(f7) $F7/.gitignore is still readable AND writable after chmod 000"
  out_f7="$(mem "$F7" apply 2>&1)"; rc_f7=$?
  chmod 644 "$F7/.gitignore"   # restore BEFORE any assertion so the trap can always clean up
  [ "$rc_f7" -eq 0 ] && ok "(f7) apply on an unreadable/unwritable .gitignore exits 0 (fail-safe)" || no "(f7) non-zero ($rc_f7)"
  has '^apply: ABORTED' "$out_f7" && ok "(f7) apply ABORTS on a chmod-000 .gitignore" || no "(f7) apply did not abort on chmod 000"
  hasi 'readable and writable' "$out_f7" && ok "(f7) the abort names the reason (not both readable and writable)" || no "(f7) abort did not name the permission problem"
  [ "$before_f7" = "$(sum "$F7/.gitignore")" ] && ok "(f7) .gitignore byte-identical after the permission abort" || no "(f7) .gitignore MUTATED despite the abort"
  [ -z "$(ls "$F7"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f7) no backup written on the permission abort path" || no "(f7) a backup was written despite aborting"
fi

# (f8) NUL BYTES — binary content is not a line-oriented ignore file.
# THIS FIXTURE IS DELIBERATELY TWO-SIDED. The guard was once written `grep -q $'\0' "$GI"`,
# which CANNOT work: bash cannot hold a NUL in a variable, so `$'\0'` collapses to the EMPTY
# pattern, which matches every line of every file — every .gitignore was reported as binary.
# A one-sided "a NUL file aborts" assertion would pass under that broken form too (it aborts on
# everything), so it would be vacuous. The negative control below — a plain TEXT .gitignore must
# NOT be reported as binary — is what actually pins the `tr | cmp` fix.
F8="$(newgit)"
printf '.claude/\nbin\000ary\n' > "$F8/.gitignore" || setup_fail "(f8) could not write $F8/.gitignore"
# The NUL is the entire point of this fixture; a printf that dropped it would silently turn the
# group into a duplicate of the text control below. Counted with `tr -d`, deliberately NOT with a
# grep for `$'\0'` — bash cannot hold a NUL in a variable, so that pattern collapses to the EMPTY
# pattern and matches every file (the very regression the (f8) negative control exists to pin).
[ "$(LC_ALL=C tr -d '\000' < "$F8/.gitignore" | wc -c)" -lt "$(wc -c < "$F8/.gitignore")" ] \
  || setup_fail "(f8) $F8/.gitignore contains no NUL byte — printf dropped it"
before_f8="$(sum "$F8/.gitignore")"
out_f8="$(mem "$F8" apply 2>&1)"; rc_f8=$?
[ "$rc_f8" -eq 0 ] && ok "(f8) apply on a NUL-containing .gitignore exits 0 (fail-safe)" || no "(f8) non-zero ($rc_f8)"
has '^apply: ABORTED' "$out_f8" && ok "(f8) apply ABORTS on a .gitignore containing NUL bytes" || no "(f8) apply did not abort on NUL bytes"
hasi 'NUL bytes' "$out_f8" && ok "(f8) the abort names the reason (NUL bytes / binary)" || no "(f8) abort did not name the NUL bytes"
[ "$before_f8" = "$(sum "$F8/.gitignore")" ] && ok "(f8) .gitignore byte-identical after the binary abort" || no "(f8) .gitignore MUTATED despite the abort"
[ -z "$(ls "$F8"/.gitignore.backup.* 2>/dev/null)" ] && ok "(f8) no backup written on the binary abort path" || no "(f8) a backup was written despite aborting"
# NEGATIVE CONTROL — the same content with the NUL removed is ordinary text and must be handled
# normally. This is the assertion that goes RED if the guard regresses to an empty-pattern grep.
F8b="$(newgit)"
seed_stores "$F8b"
printf '.claude/\nbinary\n' > "$F8b/.gitignore"
out_f8b="$(mem "$F8b" apply 2>&1)"
hasi 'NUL bytes' "$out_f8b" && no "(f8) a plain TEXT .gitignore was misreported as binary (empty-pattern regression)" || ok "(f8) a plain TEXT .gitignore is NOT misreported as binary (guard is not an empty pattern)"
has '^apply: applied' "$out_f8b" && ok "(f8) the text control applies normally (the binary guard did not swallow it)" || no "(f8) the text control did not apply"

# ============================================================================
echo "== (g) remove — reverts exactly, and says plainly that history retains what was pushed =="
Gg="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Gg"
printf '# editor\n*.swp\n\n# runtime\n.claude/\n.supervisor/\n' > "$Gg/.gitignore"
orig_g="$(mkfix)/orig.gitignore"; cp "$Gg/.gitignore" "$orig_g"
mem "$Gg" apply >/dev/null 2>&1
assert_committable "$Gg" "$P_MEM" "(g) precondition: $P_MEM committable after apply"
out_g="$(mem "$Gg" remove 2>&1)"; rc_g=$?
[ "$rc_g" -eq 0 ] && ok "(g) remove exits 0" || no "(g) remove non-zero ($rc_g)"
has '^remove: removed' "$out_g" && ok "(g) remove reports 'removed'" || no "(g) remove did not report 'removed'"
# future tracking stops again — per path
assert_ignored "$Gg" "$P_MEM" "(g) after remove $P_MEM is ignored again (future tracking stopped)"
assert_ignored "$Gg" "$P_LES" "(g) after remove $P_LES is ignored again"
gi_g="$(cat "$Gg/.gitignore")"
hasF '>>> loomwright /setup memory BEGIN' "$gi_g" && no "(g) the managed block survived remove" || ok "(g) the managed block is gone after remove"
# byte-exact round-trip: apply → remove restores the original file
if cmp -s "$orig_g" "$Gg/.gitignore"; then ok "(g) apply → remove restores .gitignore BYTE-EXACTLY"; else no "(g) apply → remove did not restore the original .gitignore"; fi
# the history statement — a required, explicit user-facing claim, not an implication
hasi 'history' "$out_g" && ok "(g) remove output mentions git history" || no "(g) remove output never mentions history"
hasE 'does NOT unpublish|cannot take it back' "$out_g" && ok "(g) remove states plainly that removal does NOT unpublish what was already pushed" || no "(g) remove does not state that history retains pushed content"
hasF 'git rm -r --cached' "$out_g" && ok "(g) remove tells the user how to stop tracking already-tracked files (git rm --cached)" || no "(g) remove omits the already-tracked guidance"
hasi 'NEVER runs git rm' "$out_g" && ok "(g) remove states that the helper itself never runs git rm/add/commit" || no "(g) remove omits the never-runs-git claim"

# ============================================================================
echo "== (h) consent disclosure is printed BEFORE anything is written =="
Hh="$(newgit https://github.com/acme/widget.git)"
printf '.claude/\n.supervisor/\n' > "$Hh/.gitignore"
out_hc="$(mem "$Hh" check 2>&1)"
hasi 'becomes VERSION-CONTROLLED' "$out_hc" && ok "(h) check prints what becomes version-controlled" || no "(h) check omits the version-controlled disclosure"
hasi 'Committing publishes' "$out_hc" && ok "(h) check warns that committing publishes the memory" || no "(h) check omits the publishing warning"
hasi 'proprietary' "$out_hc" && ok "(h) check names the proprietary/client-detail risk explicitly" || no "(h) check omits the proprietary-content risk"
hasi 'does NOT unpublish' "$out_hc" && ok "(h) check states up front that removal does not unpublish" || no "(h) check omits the not-unpublishable warning"
out_ha="$(mem "$Hh" apply 2>&1)"
line_disc="$(grep -n 'becomes VERSION-CONTROLLED' <<< "$out_ha" | head -n1 | cut -d: -f1)"
line_app="$(grep -n '^apply: applied' <<< "$out_ha" | head -n1 | cut -d: -f1)"
if [ -n "$line_disc" ] && [ -n "$line_app" ] && [ "$line_disc" -lt "$line_app" ]; then
  ok "(h) apply prints the disclosure BEFORE reporting the write (line $line_disc < $line_app)"
else
  no "(h) apply did not print the disclosure before the write (disc=$line_disc app=$line_app)"
fi

# ============================================================================
echo "== (i) write containment — only .gitignore(+backup) and .supervisor/config.json =="
Ii="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Ii"
printf '.claude/\n.supervisor/\n' > "$Ii/.gitignore"
# (i1) check writes NOTHING at all.
before_i="$(cd "$Ii" && find . -not -path './.git/*' -not -name '.git' | LC_ALL=C sort)"
mem "$Ii" check >/dev/null 2>&1
after_i="$(cd "$Ii" && find . -not -path './.git/*' -not -name '.git' | LC_ALL=C sort)"
[ "$before_i" = "$after_i" ] && ok "(i1) check created no files at all (read-only)" || no "(i1) check created or removed files"
# (i2) apply touches only the sanctioned paths — anything else under the root is a containment breach.
head_before="$(git -C "$Ii" rev-parse HEAD 2>/dev/null)"
idx_before="$(git -C "$Ii" diff --cached --name-only 2>/dev/null | LC_ALL=C sort)"
mem "$Ii" apply >/dev/null 2>&1
unexpected="$(cd "$Ii" && find . -not -path './.git/*' -not -name '.git' -type f \
  ! -name '.gitignore' ! -name '.gitignore.backup.*' ! -name 'seed.txt' \
  ! -path './.supervisor/config.json' \
  ! -path './.claude/agent-memory/*' ! -path './.supervisor/memory/*' \
  ! -path './.claude/worktrees/*' ! -name 'settings.local.json' ! -path './.supervisor/logs/*' \
  | LC_ALL=C sort)"
[ -z "$unexpected" ] && ok "(i2) apply wrote ONLY .gitignore, its backup, and .supervisor/config.json" || no "(i2) apply wrote unexpected files: $(tr '\n' ' ' <<< "$unexpected")"
[ ! -e "$Ii/.claude/settings.json" ] && ok "(i2) no <root>/.claude/settings.json written" || no "(i2) apply wrote <root>/.claude/settings.json"
# (i3) nothing was staged, committed, or otherwise pushed into git — behavioural, not a grep.
mem "$Ii" remove >/dev/null 2>&1
head_after="$(git -C "$Ii" rev-parse HEAD 2>/dev/null)"
idx_after="$(git -C "$Ii" diff --cached --name-only 2>/dev/null | LC_ALL=C sort)"
[ "$head_before" = "$head_after" ] && ok "(i3) HEAD unchanged across apply+remove (nothing committed)" || no "(i3) HEAD MOVED — the helper committed something"
[ "$idx_before" = "$idx_after" ] && ok "(i3) the git index is unchanged across apply+remove (nothing staged)" || no "(i3) the helper STAGED files (index changed)"
# (i4) static corroboration: every git invocation in the helper is read-only. Extracted from the
# actual `git -C "<dir>" <subcommand>` call sites, NOT a bare `git rm` text grep — the helper's
# user-facing copy legitimately QUOTES `git rm -r --cached` as guidance, and a text grep would
# false-positive on that prose.
git_subs="$(grep -oE 'git -C "[^"]*" [a-z-]+' "$MEM" | awk '{print $NF}' | LC_ALL=C sort -u | tr '\n' ' ')"
case "$git_subs" in
  *add*|*commit*|*rm*|*push*|*reset*|*checkout*|*stash*)
    no "(i4) a mutating git subcommand is invoked by setup-memory.sh: $git_subs" ;;
  *)
    ok "(i4) only read-only git subcommands are invoked: $git_subs" ;;
esac
mem_src="$(cat "$MEM")"
hasF 'HOME' "$mem_src" && no "(i4) setup-memory.sh references \$HOME (must never write under ~/.claude/)" || ok "(i4) setup-memory.sh never references \$HOME"

# ============================================================================
echo "== (j) fail-safe — every subcommand exits 0, including on hostile input =="
Jj="$(mkfix)"   # a bare directory: NOT a git repo, no .gitignore
for sub in check apply remove allowlist; do
  mem "$Jj" "$sub" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && ok "(j) '$sub' exits 0 on a non-git, .gitignore-less root" || no "(j) '$sub' exited $rc on a non-git root"
done
mem "$Jj" filter-ledger --ledger "$Jj/nope.jsonl" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(j) 'filter-ledger' exits 0 on a missing ledger" || no "(j) filter-ledger exited $rc on a missing ledger"
bash "$MEM" --root "$Jj" check --bogus-flag >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(j) an unknown flag is warned about and exits 0" || no "(j) unknown flag exited $rc"
bash "$MEM" --root >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(j) a valueless trailing --root exits 0 (no arg-shift underflow / spin)" || no "(j) valueless --root exited $rc"
# `--ledger` and `--allow` carry the SAME shift-underflow hazard as `--root` above (a bare trailing
# flag must not `shift 2`), and both early-exit 0 with a stderr reason. Untested until now.
err_lg="$(bash "$MEM" --root "$Jj" filter-ledger --ledger 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && ok "(j) a valueless trailing --ledger exits 0 (no arg-shift underflow / spin)" || no "(j) valueless --ledger exited $rc"
hasF '--ledger requires a path argument' "$err_lg" && ok "(j) valueless --ledger says WHY on stderr (never a silent fall-back)" || no "(j) valueless --ledger gave no reason (got: $err_lg)"
err_al="$(bash "$MEM" --root "$Jj" allowlist --allow 2>&1 >/dev/null)"; rc=$?
[ "$rc" -eq 0 ] && ok "(j) a valueless trailing --allow exits 0 (no arg-shift underflow / spin)" || no "(j) valueless --allow exited $rc"
hasF '--allow requires an owner/repo argument' "$err_al" && ok "(j) valueless --allow says WHY on stderr" || no "(j) valueless --allow gave no reason (got: $err_al)"
bash "$MEM" --help >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(j) --help exits 0" || no "(j) --help exits $rc"
# check on a non-git root must degrade to 'unknown', never crash or claim a status it did not probe
chk_j="$(mem "$Jj" check 2>/dev/null)"
has 'unknown' "$chk_j" && ok "(j) a non-git root reports ignore status as 'unknown' (never an unprobed claim)" || no "(j) non-git root did not report 'unknown'"
has '^  .gitignore:        absent' "$chk_j" && ok "(j) a missing .gitignore is reported as 'absent'" || no "(j) missing .gitignore not reported as absent"
# The VERDICT must inherit that too. With every cell 'unknown' the old fall-through printed
# "partial (an unintended path is committable …)" — asserting a state it never probed.
has '^Memory readiness: unknown' "$chk_j" && ok "(j) the VERDICT is 'unknown' when nothing could be probed (never 'partial', which claims an unprobed state)" || no "(j) non-git verdict is not 'unknown' (got: $(grep '^Memory readiness:' <<< "$chk_j"))"
hasF 'could not be probed' "$chk_j" && ok "(j) the unknown verdict says WHY (not a git repo)" || no "(j) the unknown verdict gives no reason"

# ============================================================================
# mkgate — a fixture carrying BOTH memory stores, a `.supervisor/postmortem/` directory, a CLEAN
# single-record ledger attributed to the fixture's own remote slug, one SIBLING artifact in the same
# directory (which must stay ignored), and the historical bare directory excludes. Echoes the dir.
mkgate() {
  local d
  d="$(newgit https://github.com/acme/widget.git)"
  seed_stores "$d"
  mkdir -p "$d/.supervisor/postmortem"
  printf '{"repo":"acme/widget","number":1,"review_rounds":2}\n' > "$d/$P_LEDGER"
  printf '{"stray":true}\n' > "$d/$P_LEDGER_SIBLING"
  printf '.claude/\n.supervisor/\n' > "$d/.gitignore"
  printf '%s' "$d"
}

echo "== (l) the findings-ledger gate — a THIRD managed store, un-ignored ONLY when it is clean =="
# The ledger is structurally CROSS-REPO (a /pr-postmortem append lands in the CURRENT working
# .supervisor/, never the analysed repo's), so un-ignoring an unfiltered one PUBLISHES another repo's
# churn analysis. Everything below drives that gate against real `git check-ignore` probes.

# -----------------------------------------------------------------------------------------------
# test_negation_wrong_position_still_ignored — TWO NEGATIVE CONTROLS THAT BOTH LOOK CORRECT.
#
# Git applies the LAST matching rule, so a `!` line placed BEFORE the exclude that beats it is dead;
# and git cannot re-include a file whose PARENT DIRECTORY is excluded, so the naive one-liner is dead
# too. Both were live design mistakes in this change, and neither is visible by reading — only a real
# probe distinguishes them. Deliberately driven WITHOUT the helper: these fixtures assert what GIT
# does, which is the reference the emitted block has to satisfy.
# -----------------------------------------------------------------------------------------------
test_negation_wrong_position_still_ignored() {
  local d1 d2 d3 gi ln_sup ln_neg
  # (i) the CORRECT three lines in the WRONG POSITION — emitted BEFORE `.supervisor/*`.
  d1="$(newgit https://github.com/acme/widget.git)"
  mkdir -p "$d1/.supervisor/postmortem"; printf '{"repo":"acme/widget"}\n' > "$d1/$P_LEDGER"
  printf '.claude/*\n!.claude/agent-memory/\n!.supervisor/postmortem/\n.supervisor/postmortem/*\n!.supervisor/postmortem/results.jsonl\n.supervisor/*\n!.supervisor/memory/\n' > "$d1/.gitignore"
  assert_ignored "$d1" "$P_LEDGER" "(l7) NEGATIVE CONTROL: the correct three lines placed BEFORE '.supervisor/*' leave the ledger IGNORED — position is load-bearing, git applies the LAST matching rule"

  # (ii) the NAIVE ONE-LINER, correctly positioned but structurally dead.
  d2="$(newgit https://github.com/acme/widget.git)"
  mkdir -p "$d2/.supervisor/postmortem"; printf '{"repo":"acme/widget"}\n' > "$d2/$P_LEDGER"
  printf '.supervisor/*\n!.supervisor/memory/\n!.supervisor/postmortem/results.jsonl\n' > "$d2/.gitignore"
  assert_ignored "$d2" "$P_LEDGER" "(l7) NEGATIVE CONTROL: the NAIVE one-line '!.supervisor/postmortem/results.jsonl' does NOTHING — its parent directory is excluded"

  # (iii) POSITIVE CONTROL on the same fixture — the shipped shape DOES work, so (i) and (ii) prove
  # a real ordering/shape failure rather than a broken probe.
  printf '.supervisor/*\n!.supervisor/memory/\n!.supervisor/postmortem/\n.supervisor/postmortem/*\n!.supervisor/postmortem/results.jsonl\n' > "$d2/.gitignore"
  assert_committable "$d2" "$P_LEDGER" "(l7) POSITIVE CONTROL: the shipped three-line form AFTER '.supervisor/*' DOES re-include the ledger"

  # (iv) STRUCTURAL: what the helper ACTUALLY emits must sit INSIDE the managed block and AFTER the
  # block's own `.supervisor/*`. A hand-added copy OUTSIDE the block (the pre-fix shape) is defeated
  # by the block that apply appends afterwards, so "it worked once by hand" is not the contract.
  d3="$(mkgate)"
  printf '!.supervisor/postmortem/\n.supervisor/postmortem/*\n!.supervisor/postmortem/results.jsonl\n' >> "$d3/.gitignore"
  mem "$d3" apply >/dev/null 2>&1
  gi="$(cat "$d3/.gitignore")"
  ln_sup="$(grep -n '^\.supervisor/\*$' <<< "$gi" | tail -n1 | cut -d: -f1)"
  ln_neg="$(grep -n '^!\.supervisor/postmortem/results\.jsonl$' <<< "$gi" | tail -n1 | cut -d: -f1)"
  if [ -n "$ln_sup" ] && [ -n "$ln_neg" ] && [ "$ln_neg" -gt "$ln_sup" ]; then
    ok "(l7) the EMITTED ledger negation sits AFTER the managed block's own '.supervisor/*' (line $ln_neg > $ln_sup)"
  else
    no "(l7) the emitted ledger negation is mis-positioned (.supervisor/* at line ${ln_sup:-none}, negation at line ${ln_neg:-none})"
  fi
  assert_committable "$d3" "$P_LEDGER" "(l7) and the ledger really is committable after apply, hand-added stray lines notwithstanding"
}

if [ -z "$JQ" ]; then
  ok "(l) jq unavailable — the ledger-gate group is skipped (pass)"
else
  # (l1) CLEAN LEDGER ⇒ the gate PASSES, and the negation re-includes the LEDGER ONLY.
  L1="$(mkgate)"
  assert_ignored "$L1" "$P_LEDGER" "(l1) precondition: the ledger is ignored before apply"
  out_l1="$(mem "$L1" apply 2>&1)"; rc_l1=$?
  [ "$rc_l1" -eq 0 ] && ok "(l1) apply exits 0 with a clean ledger" || no "(l1) apply non-zero ($rc_l1)"
  assert_committable "$L1" "$P_LEDGER"         "(l1) a CLEAN ledger is COMMITTABLE after apply (the gate passed)"
  assert_ignored     "$L1" "$P_LEDGER_SIBLING" "(l1) a SIBLING file under .supervisor/postmortem/ stays IGNORED — the negation is ONE FILE wide, not a directory"
  assert_committable "$L1" "$P_MEM"            "(l1) the two memory stores are unaffected by the third store"
  assert_ignored     "$L1" "$P_LOGS"           "(l1) .supervisor/logs/ still ignored alongside the new negation"
  has '^Memory readiness: configured' "$out_l1" && ok "(l1) the verdict is 'configured' with a clean ledger" || no "(l1) verdict not configured (got: $(grep '^Memory readiness:' <<< "$out_l1" | head -n1))"
  hasE "^ +${P_LEDGER//./\\.} +committable$" "$out_l1" && ok "(l1) the ledger is PROBED and reported under 'intended (must be committable)'" || no "(l1) the ledger is not probed in the intended set"
  # (l1b) IDEMPOTENCY — the negation lives INSIDE the managed block, so re-emission cannot lose it.
  out_l1b="$(mem "$L1" apply 2>&1)"
  has '^apply: no-op' "$out_l1b" && ok "(l1) the second apply is a byte-compare no-op" || no "(l1) the second apply was not a no-op"
  assert_committable "$L1" "$P_LEDGER" "(l1) the ledger is STILL committable after a SECOND apply (a hand-added line outside the block would have been re-ignored here)"

  # ---------------------------------------------------------------------------------------------
  # test_gate_blocks_foreign_spaced_form — THE NAMED SPACED-FORM FIXTURE CASE.
  #
  # This plugin's own ledger carries ONE spaced-form record (`"repo": "…"`) among 88 compact ones, so
  # `grep -c '"repo":"vikashruhilgit/loomwright"'` returns 38 where jq returns 39. The consequence is
  # not a cosmetic under-count: a FOREIGN record appended in the spaced form is INVISIBLE to a compact
  # grep, which would make a grep-based gate a guard that cannot fire. The evasion is proven inside the
  # fixture (grep=0, jq=1) before the gate is exercised, so this can never decay into a jq-vs-jq
  # tautology.
  # ---------------------------------------------------------------------------------------------
  test_gate_blocks_foreign_spaced_form() {
    local d out rc n_jq n_grep out2
    d="$(mkgate)"
    mem "$d" apply >/dev/null 2>&1
    assert_committable "$d" "$P_LEDGER" "(l2) precondition: the ledger is committable while clean"
    printf '{"schema_version": 1, "ts": "2026-08-04T14:06:03Z", "repo": "otherco/othersvc", "number": 124}\n' >> "$d/$P_LEDGER"
    n_grep="$(grep -cF '"repo":"otherco/othersvc"' "$d/$P_LEDGER" 2>/dev/null || true)"; [ -n "$n_grep" ] || n_grep=0
    n_jq="$(jq -s 'map(select(.repo == "otherco/othersvc")) | length' "$d/$P_LEDGER" 2>/dev/null)"
    if [ "${n_grep:-0}" -eq 0 ] && [ "$n_jq" = "1" ]; then
      ok "(l2) THE EVASION IS REAL: a compact-form grep sees 0 spaced-form foreign records where jq sees 1 — this is why every ledger assertion here is jq"
    else
      no "(l2) the spaced-form evasion fixture did not behave as claimed (grep=$n_grep, jq=$n_jq) — the gate assertion below would be vacuous"
    fi
    out="$(mem "$d" apply 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "(l2) apply STILL EXITS 0 on the refusal path (fail-closed in the WRITE dimension, never in the exit status)" || no "(l2) apply exited $rc on the refusal path — the FAIL-SAFE CONTRACT is broken"
    assert_ignored     "$d" "$P_LEDGER" "(l2) the gate REFUSED: the ledger is IGNORED again, so the spaced-form foreign record cannot be published"
    assert_committable "$d" "$P_MEM"    "(l2) the two memory stores stay APPLIED while only the ledger is withheld"
    hasF 'otherco/othersvc' "$out" && ok "(l2) the refusal NAMES the offending slug" || no "(l2) the refusal does not name the offending slug"
    # ...and removing the record makes the gate PASS again — red↔green both proven, so the gate keys
    # on the record and not on some incidental property of the fixture.
    jq -c 'select(.repo != "otherco/othersvc")' "$d/$P_LEDGER" > "$d/ledger.clean" 2>/dev/null && mv "$d/ledger.clean" "$d/$P_LEDGER"
    out2="$(mem "$d" apply 2>&1)"
    assert_committable "$d" "$P_LEDGER" "(l2) removing the foreign record makes the gate PASS again and re-emits the negation"
    has '^Memory readiness: configured' "$out2" && ok "(l2) the verdict returns to 'configured' once the ledger is clean" || no "(l2) the verdict did not return to 'configured'"
  }
  test_gate_blocks_foreign_spaced_form

  # (l3) LEDGER ABSENT ⇒ the gate PASSES. This is every fresh user repo, and it is load-bearing for
  # test-committed-twin-scrub.sh's group (F) fixture, which asserts `configured` with no ledger.
  L3="$(newgit https://github.com/acme/widget.git)"
  seed_stores "$L3"
  printf '.claude/\n.supervisor/\n' > "$L3/.gitignore"
  out_l3="$(mem "$L3" apply 2>&1)"; rc_l3=$?
  [ "$rc_l3" -eq 0 ] && ok "(l3) apply exits 0 with NO ledger present" || no "(l3) apply non-zero ($rc_l3) with no ledger"
  has '^Memory readiness: configured' "$out_l3" && ok "(l3) an ABSENT ledger PASSES the gate and the verdict still reaches 'configured' (no records ⇒ no foreign records)" || no "(l3) an absent ledger did not reach 'configured' (got: $(grep '^Memory readiness:' <<< "$out_l3" | head -n1))"
  has '^Memory readiness: gated' "$out_l3" && no "(l3) an absent ledger was treated as CONTAMINATED — that would redden every fresh repo" || ok "(l3) an absent ledger is not treated as contaminated"

  # (l5) EMPTY ALLOWLIST ⇒ REFUSE. filter_ledger_by_allowlist retains NOTHING under an empty list, so
  # every record is outside it. Fail-closed: "nothing configured" must never read as "all fine".
  L5="$(newgit)"   # no remote at all → nothing to default from
  seed_stores "$L5"
  mkdir -p "$L5/.supervisor/postmortem"
  printf '{"repo":"acme/widget","number":1}\n' > "$L5/$P_LEDGER"
  printf '.claude/\n.supervisor/\n' > "$L5/.gitignore"
  out_l5="$(mem "$L5" apply 2>&1)"; rc_l5=$?
  [ "$rc_l5" -eq 0 ] && ok "(l5) apply exits 0 with an empty allowlist" || no "(l5) apply non-zero ($rc_l5)"
  assert_ignored "$L5" "$P_LEDGER" "(l5) an EMPTY allowlist REFUSES the negation (fail-closed — never 'nothing configured ⇒ retain everything')"

  # (l6) A RECORD WITH NO `.repo` is unattributable and must REFUSE — it cannot be SHOWN to belong here.
  L6="$(mkgate)"
  printf '{"number":42,"review_rounds":1}\n' >> "$L6/$P_LEDGER"
  out_l6="$(mem "$L6" apply 2>&1)"
  assert_ignored "$L6" "$P_LEDGER" "(l6) an UNATTRIBUTABLE record (no .repo) REFUSES the negation"
  hasF 'no .repo field' "$out_l6" && ok "(l6) the refusal says WHICH problem it found (a record with no .repo field)" || no "(l6) the refusal does not identify the unattributable record"

  # (l8) A MALFORMED ledger line cannot be parsed, so it cannot be shown to be allowlisted ⇒ REFUSE.
  #
  # THE FIXTURE DELIBERATELY OMITS THE TRAILING NEWLINE. A malformed record is, in practice, a
  # TRUNCATED one — an interrupted `/pr-postmortem` append leaves exactly this shape — and a bare
  # `while IFS= read -r line; do … done < "$ledger"` NEVER RUNS ITS BODY for an unterminated final
  # line (`read` returns non-zero at EOF even though it filled $line). The per-line fallback then
  # examined nothing, produced no output, and the gate read "no output" as "clean" ⇒ FAIL-OPEN, with
  # the negation emitted over a ledger holding an unexaminable record. Writing this fixture WITH a
  # trailing newline is what hid that bug, so the newline must stay off.
  L8="$(mkgate)"
  printf 'NOT JSON AT ALL' >> "$L8/$P_LEDGER"
  out_l8="$(mem "$L8" apply 2>&1)"; rc_l8=$?
  [ "$rc_l8" -eq 0 ] && ok "(l8) apply exits 0 on a ledger holding a malformed line" || no "(l8) apply non-zero ($rc_l8) on a malformed ledger"
  assert_ignored "$L8" "$P_LEDGER" "(l8) an UNPARSEABLE record REFUSES the negation (fail-closed per-line fallback, never a silent skip)"
  hasF 'unparseable record' "$out_l8" && ok "(l8) the refusal names the unparseable record" || no "(l8) the refusal does not name the unparseable record"

  # (l9) AN UNREADABLE LEDGER (`chmod 000`) must REFUSE, never pass.
  #
  # `[ -f "$ledger" ]` is TRUE for a chmod-000 regular file, so the gate does not take its
  # ledger-absent PASS shortcut; the whole-file jq then cannot open it (rc≠0) and the per-line
  # fallback's `done < "$ledger"` redirect fails outright, so the loop body never runs. "Examined
  # nothing" and "examined everything and found nothing foreign" both produced EMPTY output, and the
  # gate could not tell them apart ⇒ FAIL-OPEN. A record that cannot be READ cannot be shown to
  # belong to this repo, so the only sound verdict is refuse.
  #
  # SKIPPED UNDER ROOT, mirroring (f7): root bypasses the mode bits entirely, so the ledger stays
  # readable there and this case would pass VACUOUSLY rather than driving the branch.
  if [ "$(id -u)" = 0 ]; then
    ok "(l9) running as root — the chmod-000 unreadable-ledger fixture is skipped (root bypasses mode bits)"
  else
    L9="$(mkgate)"
    chmod 000 "$L9/$P_LEDGER" || setup_fail "(l9) chmod 000 failed on $L9/$P_LEDGER"
    # Same reasoning as (f7): the unreadable bit IS the fixture, so prove it took rather than
    # letting a still-readable ledger turn a vacuous pass into an apparent fail-open.
    [ ! -r "$L9/$P_LEDGER" ] || setup_fail "(l9) $L9/$P_LEDGER is still readable after chmod 000"
    out_l9="$(mem "$L9" apply 2>&1)"; rc_l9=$?
    chmod 644 "$L9/$P_LEDGER"   # restore BEFORE any assertion so the trap can always clean up
    [ "$rc_l9" -eq 0 ] && ok "(l9) apply exits 0 on an UNREADABLE ledger (fail-safe in the exit status)" || no "(l9) apply non-zero ($rc_l9) on an unreadable ledger"
    assert_ignored "$L9" "$P_LEDGER" "(l9) an UNREADABLE ledger REFUSES the negation — 'could not examine' is never 'examined and clean'"
    hasF 'could not be read' "$out_l9" && ok "(l9) the refusal says the ledger could not be read at all" || no "(l9) the refusal does not name the unreadable ledger"
    assert_committable "$L9" "$P_MEM" "(l9) the two memory stores are still applied while only the unreadable ledger is withheld"
  fi

  test_negation_wrong_position_still_ignored
fi

# (l4) jq ABSENT ⇒ the gate is NOT EVALUATED: nothing is probed, the negation is NOT emitted, the
# pre-existing verdict is unchanged and the exit code is still 0. Failing toward `gated` would
# permanently mis-report for every jq-less user; failing toward emitting would publish an unchecked
# ledger. Driven by a PATH containing symlinks to the helper's own dependencies and nothing else —
# not by deleting jq, and not by a shim named `jq` (which `command -v` would still find).
# Outside the JQ guard on purpose: this branch is about jq's ABSENCE.
L4="$(mkgate)"
L4BIN="$L4/onlybin"; mkdir -p "$L4BIN"
for _c in bash sh git awk grep sed cut head tail tr cmp date cp mv rm mkdir rmdir dirname basename wc cat ls sort uniq find id chmod touch expr sleep env; do
  _p="$(command -v "$_c" 2>/dev/null)" && ln -sf "$_p" "$L4BIN/$_c"
done
# Probed in a FRESH bash, not with `PATH=… command -v jq` in this shell: bash caches command
# locations in its own hash table, so the builtin resolves a previously-hashed jq even under a PATH
# that does not contain it — and this meta-check would then fail while the branch below is in fact
# genuinely driven. A fresh interpreter starts with an empty hash table.
if PATH="$L4BIN" bash -c 'command -v jq' >/dev/null 2>&1; then
  no "(l4) the jq-absent fixture still resolves jq on its pinned PATH — the branch below would be untested"
else
  ok "(l4) the jq-absent fixture really has no jq on PATH (the branch is genuinely driven)"
fi
out_l4="$(PATH="$L4BIN" bash "$MEM" --root "$L4" apply 2>&1)"; rc_l4=$?
[ "$rc_l4" -eq 0 ] && ok "(l4) apply exits 0 with jq unavailable (fail-safe)" || no "(l4) apply exited $rc_l4 without jq"
has '^Memory readiness: configured' "$out_l4" && ok "(l4) without jq the pre-existing verdict is PRESERVED ('configured' for the two memory stores)" || no "(l4) the verdict changed when jq went missing (got: $(grep '^Memory readiness:' <<< "$out_l4" | head -n1))"
has '^Memory readiness: gated' "$out_l4" && no "(l4) a missing jq failed toward 'gated' — that would permanently mis-report for every jq-less user" || ok "(l4) a missing jq does NOT fail toward 'gated'"
hasF 'gate not evaluated' "$out_l4" && ok "(l4) the report says plainly that the gate was NOT evaluated (never an unprobed claim)" || no "(l4) the report makes no statement about the unevaluated gate"
assert_ignored "$L4" "$P_LEDGER" "(l4) with the gate unevaluated the negation is NOT emitted — the ledger stays ignored (never publish what was not checked)"
out_l4c="$(PATH="$L4BIN" bash "$MEM" --root "$L4" check 2>&1)"; rc_l4c=$?
[ "$rc_l4c" -eq 0 ] && ok "(l4) check also exits 0 with jq unavailable" || no "(l4) check exited $rc_l4c without jq"

# ============================================================================
echo "== (m) the 'gated' verdict class — a CORRECT refusal must NOT report as 'not configured' =="
# render_report sets intended_ok=no for any INTENDED path probing `ignored`, which yields
# `not configured`, whose remediation copy tells the user to comment out "the surviving exclude" —
# which for a withheld ledger is this module's OWN `.supervisor/*` line. Following that advice
# un-ignores the contaminated ledger, and commands/setup.md mandates relaying the copy VERBATIM. So a
# gated repo needs its own verdict AND its own copy; this group pins both.
if [ -z "$JQ" ]; then
  ok "(m) jq unavailable — the gated-verdict group is skipped (pass)"
else
  Mg="$(mkgate)"
  printf '{"repo":"otherco/othersvc","number":7}\n' >> "$Mg/$P_LEDGER"
  out_m="$(mem "$Mg" apply 2>&1)"; rc_m=$?
  [ "$rc_m" -eq 0 ] && ok "(m) apply exits 0 on the gated path" || no "(m) apply exited $rc_m on the gated path"
  has '^Memory readiness: gated' "$out_m" && ok "(m) the verdict is the THIRD class 'gated'" || no "(m) the verdict is not 'gated' (got: $(grep '^Memory readiness:' <<< "$out_m" | head -n1))"
  has '^Memory readiness: not configured' "$out_m" && no "(m) a CORRECT refusal reported as 'not configured' — the destructive mis-classification this class exists to prevent" || ok "(m) the refusal is NOT reported as 'not configured'"
  hasi 'comment out the rule named above' "$out_m" && no "(m) THE DESTRUCTIVE UNDER-INCLUSION COPY was printed for a gated repo — it points at this module's own '.supervisor/*' line" || ok "(m) the misleading under-inclusion copy is NOT printed on the gated path"
  hasF 'otherco/othersvc' "$out_m" && ok "(m) the gated warning NAMES the offending slug" || no "(m) the gated warning names no slug"
  hasF 'filter-ledger' "$out_m" && ok "(m) the gated warning gives the filter-ledger remedy" || no "(m) the gated warning omits the filter-ledger remedy"
  hasF 'repo_allowlist' "$out_m" && ok "(m) the gated warning also offers the extend-the-allowlist remedy" || no "(m) the gated warning omits the allowlist remedy"
  hasi 'does NOT un-track' "$out_m" && ok "(m) the gated warning states the honest limit: withholding does NOT un-track an already-committed ledger" || no "(m) the gated warning omits the already-committed honest limit"
  assert_committable "$Mg" "$P_MEM"    "(m) the two memory stores ARE applied on the gated path (gated is not 'nothing happened')"
  assert_ignored     "$Mg" "$P_LEDGER" "(m) the ledger stays ignored while gated"
  chk_m="$(mem "$Mg" check 2>&1)"
  has '^Memory readiness: gated' "$chk_m" && ok "(m) 'check' reports the gated verdict too (not just apply)" || no "(m) check did not report the gated verdict"
  # THE NO-OP HEADLINE. proposed_applied_content omits the ledger lines while gated, so current ==
  # proposed and do_apply reaches its no-op branch — which used to print the exact 'already
  # configured' copy the gated class exists to prevent, and setup.md mandates relaying it verbatim.
  out_m2="$(mem "$Mg" apply 2>&1)"
  has '^apply: no-op' "$out_m2" && ok "(m) the second apply on a gated repo is still a byte-compare no-op" || no "(m) the second apply on a gated repo was not a no-op"
  hasF 'apply: no-op — already configured' "$out_m2" && no "(m) the gated repo printed 'apply: no-op — already configured' — setup.md relays that headline VERBATIM, so it would state the opposite of the truth" || ok "(m) the gated no-op headline names the gated state instead of 'already configured'"
  hasF 'GATED' "$out_m2" && ok "(m) the gated no-op headline says the ledger is GATED and stays ignored" || no "(m) the gated no-op headline does not name the gated state"

  # THE WITHDRAWAL TRANSITION: applied cleanly, THEN contaminated. Correct fail-closed behaviour, but
  # it rewrites .gitignore and must be ANNOUNCED — never a bare `apply: applied`.
  Wd="$(mkgate)"
  mem "$Wd" apply >/dev/null 2>&1
  assert_committable "$Wd" "$P_LEDGER" "(m) precondition: the clean apply un-ignored the ledger"
  printf '{"schema_version": 1, "repo": "stranger/elsewhere", "number": 3}\n' >> "$Wd/$P_LEDGER"
  out_w="$(mem "$Wd" apply 2>&1)"; rc_w=$?
  [ "$rc_w" -eq 0 ] && ok "(m) the withdrawal re-apply exits 0" || no "(m) the withdrawal re-apply exited $rc_w"
  hasF 'WITHDRAWN' "$out_w" && ok "(m) the clean→contaminated re-apply ANNOUNCES the withdrawal" || no "(m) the withdrawal was silent"
  hasF 'stranger/elsewhere' "$out_w" && ok "(m) the withdrawal names WHICH slugs appeared since the last apply" || no "(m) the withdrawal does not name the new slugs"
  hasE '^apply: applied — managed block written' "$out_w" && no "(m) the withdrawal was reported under a BARE 'apply: applied' headline" || ok "(m) the headline itself is qualified — never a bare 'apply: applied'"
  hasi 'does not un-track' "$out_w" && ok "(m) the withdrawal states that it does NOT un-track an already-committed ledger" || no "(m) the withdrawal implies the ledger is unpublished — it is not"
  assert_ignored "$Wd" "$P_LEDGER" "(m) after the withdrawal the ledger is IGNORED again"
fi

# ============================================================================
echo "== (n) EMIT vs WITHDRAW are ASYMMETRIC — 'could not examine' must never withdraw a good negation =="
# THE ROOT CAUSE THIS GROUP PINS. The emission decision (`pass`) also governed whether an EXISTING
# negation survived the regenerated block, so "we could not determine the ledger's state" was treated
# identically to "we determined the ledger is contaminated". On a FRESH repo that is correct
# fail-closed behaviour (groups l4/l8/l9 pin it). On an ALREADY-APPLIED repo it silently WITHDREW a
# good negation and blamed foreign slugs that do not exist.
#
# Emitting a NEW negation still requires an affirmative examined `pass`. WITHDRAWING an existing one
# now requires an affirmative `refuse` backed by REAL, EXAMINED foreign slugs.
if [ -z "$JQ" ]; then
  ok "(n) jq unavailable — the emit/withdraw asymmetry group is skipped (pass)"
else
  # (n1) ALREADY APPLIED + jq ABSENT ⇒ the negation is PRESERVED. Same PATH-with-no-jq fixture shape
  # as (l4), but against a repo that ALREADY carries the negation — that is the whole difference.
  N1="$(mkgate)"
  mem "$N1" apply >/dev/null 2>&1
  assert_committable "$N1" "$P_LEDGER" "(n1) precondition: the clean apply un-ignored the ledger"
  out_n1="$(PATH="$L4BIN" bash "$MEM" --root "$N1" apply 2>&1)"; rc_n1=$?
  [ "$rc_n1" -eq 0 ] && ok "(n1) the jq-absent re-apply exits 0" || no "(n1) the jq-absent re-apply exited $rc_n1"
  assert_committable "$N1" "$P_LEDGER" "(n1) THE FIX: with jq ABSENT on an ALREADY-APPLIED repo the negation is PRESERVED — the ledger stays committable"
  hasF 'WITHDRAWN' "$out_n1" && no "(n1) a missing jq WITHDREW the negation — an unrequested state change on a diagnosis never made" || ok "(n1) the jq-absent re-apply does not announce a withdrawal"
  hasF 'records outside the allowlist' "$out_n1" && no "(n1) the jq-absent re-apply claimed FOREIGN RECORDS it never observed" || ok "(n1) no false contamination message when jq is absent"
  has '^Memory readiness: gated' "$out_n1" && no "(n1) a missing jq failed toward 'gated' on an applied repo" || ok "(n1) the verdict is not 'gated' when jq is merely absent"
  hasF 'PRESERVED' "$out_n1" && ok "(n1) the output says HONESTLY that the negation was PRESERVED, not re-verified" || no "(n1) the preservation is silent — the user cannot tell the gate did not run"

  # (n2) ALREADY APPLIED + jq PRESENT BUT BROKEN. `command -v jq` tests PRESENCE, NOT FUNCTION: a jq
  # that exits non-zero makes the whole-file pass AND every per-line probe fail, so a perfectly CLEAN
  # ledger was counted entirely unparseable and the gate REFUSED. Strictly worse than (n1) — it did
  # not merely withdraw, it printed "(unparseable record at ledger line 1)" as if it were a slug.
  N2="$(mkgate)"
  mem "$N2" apply >/dev/null 2>&1
  assert_committable "$N2" "$P_LEDGER" "(n2) precondition: the clean apply un-ignored the ledger"
  N2BIN="$N2/brokenbin"; mkdir -p "$N2BIN"
  for _c in bash sh git awk grep sed cut head tail tr cmp date cp mv rm mkdir rmdir dirname basename wc cat ls sort uniq find id chmod touch expr sleep env; do
    _p="$(command -v "$_c" 2>/dev/null)" && ln -sf "$_p" "$N2BIN/$_c"
  done
  printf '#!/bin/sh\nexit 127\n' > "$N2BIN/jq"; chmod +x "$N2BIN/jq"
  # META-CHECK, in a FRESH bash (this shell has jq hashed): the stub must be FOUND and must FAIL —
  # otherwise the branch below is not the one being driven.
  if PATH="$N2BIN" bash -c 'command -v jq' >/dev/null 2>&1 && ! PATH="$N2BIN" bash -c 'printf "{}" | jq -e . >/dev/null 2>&1'; then
    ok "(n2) the broken-jq fixture is genuinely PRESENT on PATH and genuinely NON-FUNCTIONAL (the branch is really driven)"
  else
    no "(n2) the broken-jq fixture is not present-and-broken — the assertions below would be vacuous"
  fi
  out_n2="$(PATH="$N2BIN" bash "$MEM" --root "$N2" apply 2>&1)"; rc_n2=$?
  [ "$rc_n2" -eq 0 ] && ok "(n2) the broken-jq re-apply exits 0" || no "(n2) the broken-jq re-apply exited $rc_n2"
  assert_committable "$N2" "$P_LEDGER" "(n2) THE FIX: a BROKEN jq on an ALREADY-APPLIED repo PRESERVES the negation — the ledger stays committable"
  hasF 'WITHDRAWN' "$out_n2" && no "(n2) a broken jq WITHDREW the negation on a perfectly CLEAN ledger" || ok "(n2) the broken-jq re-apply does not announce a withdrawal"
  hasF 'unparseable record' "$out_n2" && no "(n2) a broken jq reported '(unparseable record ...)' against a CLEAN ledger — contamination it never observed" || ok "(n2) no false 'unparseable record' claim when jq itself is what is broken"
  hasF 'records outside the allowlist' "$out_n2" && no "(n2) the broken-jq re-apply claimed FOREIGN RECORDS it never observed" || ok "(n2) no false contamination message when jq is broken"
  has '^Memory readiness: gated' "$out_n2" && no "(n2) a broken jq failed toward 'gated' on an applied repo with a clean ledger" || ok "(n2) the verdict is not 'gated' when jq itself is broken"

  # (n3) REGRESSION CONTROL — the asymmetry must not disarm the gate. A REAL foreign record on an
  # already-applied repo must STILL withdraw the negation and name the real slug.
  N3="$(mkgate)"
  mem "$N3" apply >/dev/null 2>&1
  assert_committable "$N3" "$P_LEDGER" "(n3) precondition: the clean apply un-ignored the ledger"
  printf '{"repo": "stranger/elsewhere", "number": 9}\n' >> "$N3/$P_LEDGER"
  out_n3="$(mem "$N3" apply 2>&1)"; rc_n3=$?
  [ "$rc_n3" -eq 0 ] && ok "(n3) the contaminated re-apply exits 0" || no "(n3) the contaminated re-apply exited $rc_n3"
  assert_ignored "$N3" "$P_LEDGER" "(n3) REGRESSION CONTROL: a REAL foreign record STILL WITHDRAWS the negation — the ledger is ignored again"
  hasF 'WITHDRAWN' "$out_n3" && ok "(n3) the real-contamination path still ANNOUNCES the withdrawal" || no "(n3) the real withdrawal went silent — the asymmetry disarmed the gate"
  hasF 'stranger/elsewhere' "$out_n3" && ok "(n3) the withdrawal names the REAL observed slug" || no "(n3) the withdrawal does not name the real slug"
fi

# ============================================================================
echo "== (o) remove is LEDGER-AWARE — the third store is counted, re-ignored and named =="
# `remove` gained a THIRD tracked-count and a three-path `git rm -r --cached` hint when the ledger
# became a managed store. Groups (l)/(m)/(n) only ever drive `apply`/`check`, and group (g) predates
# the ledger — so without this group the ledger half of do_remove() is unpinned: dropping
# $LEDGER_INTENDED_PATH from either the count or the hint would leave every other assertion green.
# The count is asserted against a ledger that is REALLY `git add`ed, because a count of 0 passes
# whether or not the code looks at the ledger at all.
if [ -z "$JQ" ]; then
  ok "(o) jq unavailable — the ledger-aware remove group is skipped (pass)"
else
  Oo="$(mkgate)"
  mem "$Oo" apply >/dev/null 2>&1
  assert_committable "$Oo" "$P_LEDGER" "(o) precondition: the clean apply un-ignored the ledger"
  # REALLY track it — this is what makes the count assertion non-vacuous.
  git -C "$Oo" add -- "$P_LEDGER" >/dev/null 2>&1
  n_tracked_o="$(git -C "$Oo" ls-files -- "$P_LEDGER" | wc -l | tr -d ' ')"
  [ "${n_tracked_o:-0}" -eq 1 ] && ok "(o) fixture precondition: the ledger is genuinely TRACKED (git ls-files = 1), so a 0 count cannot pass trivially" || no "(o) the ledger is not tracked in the fixture (got $n_tracked_o) — the count assertion below would be vacuous"
  out_o="$(mem "$Oo" remove 2>&1)"; rc_o=$?
  [ "$rc_o" -eq 0 ] && ok "(o) remove exits 0 on a ledger-applied repo" || no "(o) remove exited $rc_o on a ledger-applied repo"
  # EVERY TEXT ASSERTION BELOW IS SCOPED TO THE PRE-`== verify ==` HALF. do_remove() ends by calling
  # render_report, which prints its OWN "tracked today:" line naming all three stores — matching the
  # whole output would therefore stay green even with the ledger deleted from remove's own warning.
  # (Proven: mutating out only remove's ledger count left the unscoped form 294/0.)
  pre_o="${out_o%%== verify ==*}"
  [ "$pre_o" != "$out_o" ] && ok "(o) the remove-specific half of the output was isolated from the trailing verify report" || no "(o) could not split remove's own output from its '== verify ==' report — the text assertions below would not be remove-specific"
  # (o1) the THIRD tracked count is reported by REMOVE ITSELF, for the ledger path, non-zero.
  hasF "$P_LEDGER → 1 file(s)" "$pre_o" && ok "(o1) remove's own already-tracked warning reports the ledger count ($P_LEDGER → 1 file(s))" || no "(o1) remove's own warning does not report a tracked count for $P_LEDGER — the third store is invisible to the already-tracked warning"
  # (o2) the bare exclude is restored — asserted with a REAL git probe, never a .gitignore grep.
  # `--no-index` is REQUIRED here and is not a weakening: plain `git check-ignore` consults the index
  # and reports a TRACKED path as not-ignored regardless of the rules, which is exactly the
  # "already-tracked files stay tracked" fact this very output warns about. Without it the probe would
  # measure the fixture's `git add`, not the restored exclude. The untracked control below is probed
  # with the ordinary helper, so both forms are exercised.
  if git -C "$Oo" check-ignore -q --no-index -- "$P_LEDGER" >/dev/null 2>&1; then
    ok "(o2) after remove the ledger is IGNORED again by the rules (the negation is gone, future tracking stopped)"
  else
    no "(o2) after remove the ledger is still committable by the rules — the bare exclude was not restored"
  fi
  assert_ignored "$Oo" "$P_MEM"    "(o2) after remove the memory store is ignored again too"
  # (o3) the remediation copy names ALL THREE stores, not just the two memory ones.
  hasF "git rm -r --cached .claude/agent-memory .supervisor/memory $P_LEDGER" "$pre_o" && ok "(o3) the 'git rm -r --cached' hint names all THREE stores including the ledger" || no "(o3) the git rm hint omits the ledger — the user would leave the third store tracked"
  hasi 'All THREE stores are covered' "$pre_o" && ok "(o3) remove states that all THREE stores are covered by the managed block" || no "(o3) remove does not state that the third store is covered"
fi

# ============================================================================
# (p) ONE ALLOWLIST, TWO CONSUMERS.
#
# `setup-memory.sh`'s allowlist now has a SECOND consumer: validate-entry.sh's cross-repo write-time
# check, which asks this script for the list rather than parsing any layer itself. This group is the
# drift alarm for that arrangement — it moves the list ONCE and asserts BOTH behaviours move.
#
# WHY TWO PRECEDENCE LAYERS AND NOT ONE. Moving the list via $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST alone
# is satisfiable by a DUPLICATE PARSER inside validate-entry.sh: that env var is layer 2 of four, and
# a second parser reading it would agree here and diverge everywhere else. The live value in this
# repo comes from layer 3 (`.supervisor/config.json`), the layer a duplicate env parser cannot see at
# all — so the group asserts both, and layer 3 is asserted through a `--root` FIXTURE REPO whose
# config disagrees with its own git remote, which additionally proves the `--root` really reaches the
# resolver instead of the checked-out repo's own state.
#
# R0 — THE LIVE ALLOWLIST IS NEVER TOUCHED, AND NO FOREIGN SLUG EVER ENTERS IT. Adding a foreign slug
# to this repo's own allowlist would make `apply` judge foreign ledger records clean and EMIT the
# negation that un-ignores .supervisor/postmortem/results.jsonl — publishing another repo's churn
# analysis from this PUBLIC repo. Every fixture below is either a per-invocation env var or a
# `--root` temp repo, and the tail of the group re-checks the live config byte-for-byte.
# ============================================================================
echo "== (p) AC5 — ONE allowlist, TWO consumers: the cross-repo check and the ledger filter =="
# $TEST_SETUP_MEMORY_VALIDATE_ENTRY exists so this group's MUTATION CONTROL is reproducible by hand
# rather than asserted in prose. Point it at a mutated copy of validate-entry.sh and re-run:
#   · a copy whose allowlist loader DROPS the `--root` forwarding, or
#   · a copy that parses $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST itself instead of delegating
# both leave every (p/L2) assertion GREEN and turn the (p/L3) ones RED — which is the entire reason
# this group asserts two precedence layers instead of the one the env var reaches.
VE="${TEST_SETUP_MEMORY_VALIDATE_ENTRY:-$HERE/validate-entry.sh}"
CFG_LIVE="$PLUGIN_REPO/.supervisor/config.json"
CFG_LIVE_SUM_BEFORE="$(sum "$CFG_LIVE")"
CFG_LIVE_EXISTED=0; [ -f "$CFG_LIVE" ] && CFG_LIVE_EXISTED=1

# consumer A — the cross-repo write-time check. Echoes its verdict (0 pass / 1 refuse / 2 could not
# examine). VALIDATE_ENTRY_SETUP_MEMORY pins the ONE resolver to the script under test, so a stray
# CLAUDE_PLUGIN_ROOT in the developer's environment cannot point this at a different setup-memory.sh.
xrepo() {   # <entry-text> [--root <dir>]
  local e="$1"; shift
  VALIDATE_ENTRY_SETUP_MEMORY="$MEM" bash "$VE" cross-repo --entry "$e" "$@" >/dev/null 2>&1
  echo $?
}

# xrepo_noenv — the same, with $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST SCRUBBED from the child environment
# so precedence layer 3 is genuinely reached. The scrub lives INSIDE the helper on purpose: `env` can
# only exec an external command, so an `env -u … xrepo …` call site would fail to find the shell
# FUNCTION, yield an EMPTY verdict, and every `[ "$v" = "0" ]` written against it would compare
# against "" — a whole group of assertions that can never pass and never say why.
xrepo_noenv() {   # <entry-text> [--root <dir>]
  local e="$1"; shift
  env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST VALIDATE_ENTRY_SETUP_MEMORY="$MEM" \
    bash "$VE" cross-repo --entry "$e" "$@" >/dev/null 2>&1
  echo $?
}

one_allowlist_two_consumers() {
  if [ -z "$JQ" ]; then
    ok "(p) jq unavailable — the one-allowlist/two-consumers group is skipped (pass)"
    return 0
  fi
  if [ ! -f "$VE" ]; then
    no "(p) validate-entry.sh is missing at $VE — the second consumer does not exist, so AC5 cannot be discharged"
    return 0
  fi

  local d led v_alpha v_beta v_remote out n
  local E_ALPHA="the fixture-org/alpha rollout is recorded in this entry"
  local E_BETA="the fixture-org/beta rollout is recorded in this entry"
  local E_REMOTE="the acme/widget repo rollout is recorded in this entry"

  d="$(newgit https://github.com/acme/widget.git)"
  led="$d/ledger.jsonl"
  cat > "$led" <<'LEDGER'
{"repo":"fixture-org/alpha","number":1,"review_rounds":2}
{"repo":"fixture-org/beta","number":2,"review_rounds":5}
LEDGER

  # ---------------------------------------------------------------------------
  # LAYER 2 — the process-global env var. It reaches both consumers with NO root override, and
  # touches no file, so both calls below are deliberately made WITHOUT --root.
  # ---------------------------------------------------------------------------
  v_alpha="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/alpha" xrepo "$E_ALPHA")"
  v_beta="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/alpha" xrepo "$E_BETA")"
  [ "$v_alpha" = "0" ] && ok "(p/L2) consumer A: an entry citing the ALLOWLISTED slug PASSES (verdict 0)" || no "(p/L2) consumer A refused an allowlisted slug (verdict $v_alpha)"
  [ "$v_beta" = "1" ] && ok "(p/L2) consumer A: an entry citing a slug OUTSIDE the list is REFUSED (verdict 1 — examined and violating, never 2)" || no "(p/L2) consumer A verdict on a foreign slug was $v_beta, expected 1"
  out="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/alpha" bash "$MEM" filter-ledger --ledger "$led" 2>/dev/null)"
  n="$(ledger_count "$out")"
  [ "$n" = "1" ] && ok "(p/L2) consumer B: the ledger filter retains 1 of 2 records under the same list" || no "(p/L2) consumer B retained $n records, expected 1"
  ledger_has_repo "$out" "fixture-org/alpha" && ok "(p/L2) consumer B kept the allowlisted record" || no "(p/L2) consumer B dropped the allowlisted record"
  ledger_has_repo "$out" "fixture-org/beta" && no "(p/L2) consumer B leaked the non-allowlisted record" || ok "(p/L2) consumer B excluded the non-allowlisted record"

  # MOVE THE LIST ONCE — both behaviours must move together.
  v_alpha="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/beta" xrepo "$E_ALPHA")"
  v_beta="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/beta" xrepo "$E_BETA")"
  [ "$v_beta" = "0" ] && ok "(p/L2) THE LIST MOVED: consumer A now PASSES the slug it refused a moment ago" || no "(p/L2) consumer A did not follow the moved list (verdict $v_beta on the newly-allowed slug)"
  [ "$v_alpha" = "1" ] && ok "(p/L2) THE LIST MOVED: consumer A now REFUSES the slug it passed a moment ago" || no "(p/L2) consumer A still passed the now-foreign slug (verdict $v_alpha)"
  out="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/beta" bash "$MEM" filter-ledger --ledger "$led" 2>/dev/null)"
  ledger_has_repo "$out" "fixture-org/beta" && ok "(p/L2) THE LIST MOVED: consumer B now retains the record it dropped a moment ago" || no "(p/L2) consumer B did not follow the moved list"
  ledger_has_repo "$out" "fixture-org/alpha" && no "(p/L2) consumer B still retains the now-foreign record — the two consumers have diverged" || ok "(p/L2) THE LIST MOVED: consumer B now drops the record it kept a moment ago — ONE list, BOTH consumers"

  # ---------------------------------------------------------------------------
  # LAYER 3 — .supervisor/config.json inside a --root FIXTURE REPO. This is the layer the live value
  # actually comes from, and the one an env-var-only parser is blind to. `env -u` is load-bearing:
  # layer 2 outranks layer 3, so a developer with the variable exported would otherwise never reach
  # the config at all and this half would silently re-test layer 2.
  # ---------------------------------------------------------------------------
  mkdir -p "$d/.supervisor" || setup_fail "(p) could not create the fixture .supervisor dir"
  printf '{"setup_memory":{"repo_allowlist":["fixture-org/alpha"]}}\n' > "$d/.supervisor/config.json"
  # PRECONDITION: the config must genuinely BEAT the fixture's own git remote, or the assertions
  # below would be satisfied by layer 4 and would prove nothing about layer 3.
  out="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$MEM" --root "$d" allowlist 2>/dev/null)"
  if [ "$out" = "fixture-org/alpha" ]; then
    ok "(p/L3) PRECONDITION: the fixture's config allowlist BEATS its own git remote (acme/widget) — layer 3 is genuinely what resolves"
  else
    no "(p/L3) the fixture did not resolve to its config value (got: $out) — the layer-3 assertions below would be testing layer 4"
  fi
  v_alpha="$(xrepo_noenv "$E_ALPHA" --root "$d")"
  v_beta="$(xrepo_noenv "$E_BETA" --root "$d")"
  v_remote="$(xrepo_noenv "$E_REMOTE" --root "$d")"
  [ "$v_alpha" = "0" ] && ok "(p/L3) consumer A reads the FIXTURE REPO's config through --root: the config-listed slug PASSES" || no "(p/L3) consumer A did not see the fixture config (verdict $v_alpha on the config-listed slug) — --root is not reaching the resolver"
  [ "$v_beta" = "1" ] && ok "(p/L3) consumer A REFUSES a slug absent from the fixture config" || no "(p/L3) consumer A verdict $v_beta on a slug outside the fixture config, expected 1"
  # The sharpest --root assertion: the fixture's OWN REMOTE is refused, so consumer A is reading the
  # config layer and not falling back to a remote (its own, or this checkout's).
  [ "$v_remote" = "1" ] && ok "(p/L3) consumer A REFUSES the fixture's own git-remote slug — proof it read the config layer, not the remote default" || no "(p/L3) consumer A passed the fixture's remote slug (verdict $v_remote) — it is resolving layer 4, not the config"
  out="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$MEM" --root "$d" filter-ledger --ledger "$led" 2>/dev/null)"
  ledger_has_repo "$out" "fixture-org/alpha" && ok "(p/L3) consumer B reads the same config layer and keeps the config-listed record" || no "(p/L3) consumer B did not follow the config layer"
  ledger_has_repo "$out" "fixture-org/beta" && no "(p/L3) consumer B leaked a record outside the config allowlist" || ok "(p/L3) consumer B excludes the record outside the config allowlist"

  # MOVE THE CONFIG LIST ONCE — both behaviours must move together at layer 3 too.
  printf '{"setup_memory":{"repo_allowlist":["fixture-org/beta"]}}\n' > "$d/.supervisor/config.json"
  v_alpha="$(xrepo_noenv "$E_ALPHA" --root "$d")"
  v_beta="$(xrepo_noenv "$E_BETA" --root "$d")"
  [ "$v_beta" = "0" ] && ok "(p/L3) THE CONFIG LIST MOVED: consumer A now PASSES the slug it refused" || no "(p/L3) consumer A did not follow the moved config list (verdict $v_beta)"
  [ "$v_alpha" = "1" ] && ok "(p/L3) THE CONFIG LIST MOVED: consumer A now REFUSES the slug it passed" || no "(p/L3) consumer A still passed the now-foreign slug (verdict $v_alpha)"
  out="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$MEM" --root "$d" filter-ledger --ledger "$led" 2>/dev/null)"
  ledger_has_repo "$out" "fixture-org/beta" && ok "(p/L3) THE CONFIG LIST MOVED: consumer B now retains the record it dropped" || no "(p/L3) consumer B did not follow the moved config list"
  ledger_has_repo "$out" "fixture-org/alpha" && no "(p/L3) consumer B still retains the now-foreign record at layer 3 — the two consumers have diverged on the layer an env-var parser cannot see" || ok "(p/L3) THE CONFIG LIST MOVED: consumer B drops it too — ONE list, BOTH consumers, on the layer a duplicate env parser is blind to"

  # THE SCRUB ITSELF, PINNED. Every layer-3 assertion above is only about layer 3 if the env var
  # really was removed from the child. Prove it directly: EXPORT a contradicting layer-2 value and
  # show the fixture's config (now `fixture-org/beta`) still decides the verdict.
  local v_scrub
  v_scrub="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/alpha" xrepo_noenv "$E_ALPHA" --root "$d")"
  [ "$v_scrub" = "1" ] && ok "(p/L3) the env-var scrub is real: an EXPORTED layer-2 value does not reach the child, so the fixture's config still decides — the layer-3 assertions above are about layer 3" || no "(p/L3) an exported layer-2 value leaked into the child (verdict $v_scrub) — the layer-3 assertions above were silently re-testing layer 2"

  # ---------------------------------------------------------------------------
  # NEGATIVE CONTROL — the shipped PUBLICATION GATE is not weakened by any of the above. With a
  # FOREIGN record in the ledger, `apply` in a --root fixture repo must still WITHHOLD the ledger
  # negation and NAME the offending slug. This is the property R0 exists to protect.
  # ---------------------------------------------------------------------------
  local g out_g
  g="$(mkgate)"
  mem "$g" apply >/dev/null 2>&1
  assert_committable "$g" "$P_LEDGER" "(p/neg) precondition: the fixture's ledger is committable while clean, so the withholding below is a real state change"
  printf '{"schema_version": 1, "repo": "otherco/othersvc", "number": 124}\n' >> "$g/$P_LEDGER"
  out_g="$(mem "$g" apply 2>&1)"
  assert_ignored "$g" "$P_LEDGER" "(p/neg) with a FOREIGN record present, apply still WITHHOLDS the ledger negation — the publication gate is intact"
  hasF 'otherco/othersvc' "$out_g" && ok "(p/neg) the withholding NAMES the offending slug" || no "(p/neg) the refusal does not name the offending slug"
  assert_committable "$g" "$P_MEM" "(p/neg) and only the ledger is withheld — the memory stores stay applied"
}
one_allowlist_two_consumers

# R0, re-checked mechanically rather than asserted in prose.
if [ "$CFG_LIVE_EXISTED" -eq 1 ]; then
  [ "$(sum "$CFG_LIVE")" = "$CFG_LIVE_SUM_BEFORE" ] && ok "(p) R0: the plugin repo's own .supervisor/config.json is BYTE-IDENTICAL after the group" || no "(p) R0 VIOLATED: THE SUITE MUTATED THE LIVE .supervisor/config.json"
else
  [ ! -f "$CFG_LIVE" ] && ok "(p) R0: the plugin repo had no .supervisor/config.json before the group and still has none" || no "(p) R0 VIOLATED: the suite CREATED a live .supervisor/config.json"
fi
if [ -f "$CFG_LIVE" ] && grep -qE 'otherco|fixture-org' "$CFG_LIVE" 2>/dev/null; then
  no "(p) R0 VIOLATED: a FOREIGN fixture slug reached the live allowlist — apply would now publish another repo's churn analysis"
else
  ok "(p) R0: no foreign fixture slug (otherco / fixture-org) is present in the live allowlist"
fi

# ============================================================================
echo "== (k) the suite never touched the plugin repo's own .gitignore =="
PLUGIN_GI_SUM_AFTER="$(sum "$PLUGIN_GI")"
[ "$PLUGIN_GI_SUM_BEFORE" = "$PLUGIN_GI_SUM_AFTER" ] && ok "(k) $PLUGIN_GI is byte-identical before and after the whole suite" || no "(k) THE SUITE MUTATED THE PLUGIN REPO'S OWN .gitignore"
[ -z "$(ls "$PLUGIN_REPO"/.gitignore.backup.* 2>/dev/null)" ] && ok "(k) no .gitignore.backup.* left in the plugin repo root" || no "(k) the suite left a .gitignore backup in the plugin repo root"

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
