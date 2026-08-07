#!/usr/bin/env bash
# test-setup-memory.sh — STATIC, fixture-driven self-tests for setup-memory.sh (the `/setup memory`
# module engine: gitignore negation `check` / `apply` / `remove` + the repo allowlist and its
# ledger filter). STATIC ONLY: no network, no Docker, no GitHub — so it runs on the plugin's
# Ubuntu CI like every other test-*.sh (auto-registered by ci.yml's test-*.sh glob).
# Exit 0 = all pass, 1 = any failure.
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
#   (k)  the suite never touched the plugin repo's own .gitignore

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
FIXTURE_ROOT="$(mktemp -d)"
cleanup() { [ -n "${FIXTURE_ROOT:-}" ] && rm -rf "$FIXTURE_ROOT" 2>/dev/null; }
trap cleanup EXIT
FIXN=0
# All fixtures live UNDER one scratch root, so the trap cleans them even though mkfix runs in a
# command substitution (a `FIXTURES+=(...)` array there would be lost with the subshell).
mkfix() { FIXN=$((FIXN+1)); local d="$FIXTURE_ROOT/fix-$FIXN-$RANDOM"; mkdir -p "$d"; printf '%s' "$d"; }

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
  printf '%s' "$d"
}

mem() { bash "$MEM" --root "$1" "${@:2}"; }

# ignored <dir> <path> → 0 when git ignores it, 1 when it is committable.
ignored() { git -C "$1" check-ignore -q -- "$2" >/dev/null 2>&1; }

# assert_ignored / assert_committable — ONE assertion per path (never a bulk claim).
assert_ignored()     { if ignored "$1" "$2"; then ok "$3"; else no "$3 (got: committable)"; fi; }
assert_committable() { if ignored "$1" "$2"; then no "$3 (got: ignored)"; else ok "$3"; fi; }

sum() { cksum < "$1" 2>/dev/null; }

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
  n_both="$(grep -c '"repo"' <<< "$both")"
  [ "$n_both" -eq 2 ] && ok "(d3) rename case: records under BOTH slugs retained (2 of 4)" || no "(d3) rename case retained $n_both records, expected 2"
  hasF '"acme/old-name"' "$both" && ok "(d3) the PRE-RENAME slug's record is retained (a live-remote filter would have dropped it)" || no "(d3) pre-rename record dropped"
  hasF '"acme/widget"'   "$both" && ok "(d3) the current slug's record is retained" || no "(d3) current-slug record dropped"
  # (d4) a record OUTSIDE the allowlist is excluded.
  hasF 'stranger/elsewhere' "$both" && no "(d4) a foreign-repo record leaked through the filter" || ok "(d4) foreign-repo record 'stranger/elsewhere' excluded"
  hasF '"number":4' "$both" && no "(d4) a record with NO .repo leaked through (unattributable must be excluded)" || ok "(d4) record with no .repo excluded (unattributable → not retained)"
  # (d5) the live-remote default alone drops the pre-rename half — the documented hazard, asserted.
  only_remote="$(mem "$D3" filter-ledger --ledger "$D3/ledger.jsonl" 2>/dev/null)"
  hasF '"acme/old-name"' "$only_remote" && no "(d5) remote-only allowlist unexpectedly retained the pre-rename record" || ok "(d5) remote-only allowlist DROPS the pre-rename record — this is exactly why the allowlist is a list"
  hasF '"acme/widget"' "$only_remote" && ok "(d5) remote-only allowlist still retains the current slug" || no "(d5) remote-only allowlist retained nothing at all"
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
  hasF '"number":99' "$robust" && ok "(d8) records AFTER the malformed line are still retained (per-line fallback works)" || no "(d8) the malformed line swallowed the rest of the ledger"
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
ln -s real-gitignore.txt "$F5/.gitignore"
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
mkdir "$F6/.gitignore"
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
  printf '# editor\n*.swp\n.claude/\n' > "$F7/.gitignore"
  before_f7="$(sum "$F7/.gitignore")"
  chmod 000 "$F7/.gitignore"
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
printf '.claude/\nbin\000ary\n' > "$F8/.gitignore"
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
echo "== (k) the suite never touched the plugin repo's own .gitignore =="
PLUGIN_GI_SUM_AFTER="$(sum "$PLUGIN_GI")"
[ "$PLUGIN_GI_SUM_BEFORE" = "$PLUGIN_GI_SUM_AFTER" ] && ok "(k) $PLUGIN_GI is byte-identical before and after the whole suite" || no "(k) THE SUITE MUTATED THE PLUGIN REPO'S OWN .gitignore"
[ -z "$(ls "$PLUGIN_REPO"/.gitignore.backup.* 2>/dev/null)" ] && ok "(k) no .gitignore.backup.* left in the plugin repo root" || no "(k) the suite left a .gitignore backup in the plugin repo root"

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
