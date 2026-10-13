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
# Mirrors test-build-handoff.sh convention: pass/fail counters, ok()/no() helpers, a
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
#   (ma) the tracked request file .agent/meta-allowlist.txt (layer 4, beside the remote default): a
#        same-id slug is GRANTED, a different-id slug is ignored + named on stderr + refused by the
#        ledger filter; a failing or absent gh grants nothing (config.json entries still are);
#        layers 1–3 win with the file unread and ZERO gh calls; malformed entries never reach gh;
#        a filesystem-path origin grants nothing; a NON-github.com origin (https, scp, ssh://)
#        grants nothing with ZERO gh calls; a hung gh is killed at the bound, grants nothing and
#        leaves no process or temp file — and so is a child gh leaves on the pipe (one that
#        ignores TERM, or one an exit-0 gh never waited for); no file / own-slug-only ⇒ ZERO gh
#        calls; stdout stays the list; origin's URL is read EXACTLY ONCE per resolution and slug
#        and host agree across https / ssh:// / scp / scheme-less forms (a git shim counts the
#        reads); an existing-but-unreadable request file (mode 000, a directory) is named on
#        stderr and grants nothing. gh is a recording PATH stub (no network); thirteen sed/awk
#        mutants (id comparison, failure guards, stderr, shape check, eager lookup, layer order,
#        host check, single origin read, unreadable-file line, overrun check, group signal, group
#        poll, entry cap) each turn their leg red, gated on non-empty + changed + `bash -n`-clean
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
#        nothing; no commit/index/HEAD is ever touched; only read-only git subcommands are used;
#        the code references HOME only inside do_consent (the ONE user-scope write — group (cs))
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
#   (vb) `valid-branch <name>`: exit 0 iff the ONE valid_branch_name predicate accepts (accept, `off`,
#        `HEAD`, `@`, a `-`-leading name, an invalid ref …), one stderr reason line on refusal, no
#        file changed; its verdict agrees with `apply --branch-mode`, and a refuse-all mutant of
#        the predicate turns its accept red (it calls the predicate, never a copy)
#   (k)  the suite never touched the plugin repo's own .gitignore
#   (cs) `consent grant | decline | status` (af36-03): the user-scope learning-store consent record —
#        status prints `none` / `granted` / `declined` (one line); grant / decline write EXACTLY one
#        file, the user-scope record CONSENT_FILE_REL names (nothing under the repo, no other
#        HOME file), keyed by origin's owner/repo (a filesystem-path origin: the literal URL), other
#        repos' entries preserved; no origin -> `none` and nothing written; a malformed record is
#        never clobbered; a bad action writes nothing; status / check / mode write nothing; the
#        branch-mode disclosure names the learning stores and the consent ask; mutation control: a
#        writer aimed at the repo root instead of $HOME turns the containment assertion red
#
# EVERY LEDGER ASSERTION IN THIS FILE USES jq, NEVER grep. A findings ledger mixes compact
# (`"repo":"x"`) and spaced (`"repo": "x"`) JSON — this plugin's own ledger carries one spaced
# record among 88 — so `grep -c '"repo":"owner/name"'` silently under-counts AND a foreign record
# appended in the spaced form evades a compact grep entirely. The ledger_count / ledger_has_repo
# helpers below are the only sanctioned way to assert on ledger content here.

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
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
  mkdir -p "$d/.claude/agent-memory/loomwright-loomwright-code-reviewer" "$d/.supervisor/memory" \
           "$d/.claude/worktrees/busy-darwin" "$d/.supervisor/logs"
  echo "# MEMORY"  > "$d/.claude/agent-memory/loomwright-loomwright-code-reviewer/MEMORY.md"
  echo '{"p":1}'   > "$d/.claude/agent-memory/loomwright-loomwright-code-reviewer/.provenance.jsonl"
  echo "# LESSONS" > "$d/.supervisor/memory/LESSONS.md"
  echo '{"p":1}'   > "$d/.supervisor/memory/.lessons-provenance.jsonl"
  echo "wt"        > "$d/.claude/worktrees/busy-darwin/README.md"
  echo '{}'        > "$d/.claude/settings.local.json"
  echo '{}'        > "$d/.supervisor/logs/session.jsonl"
}

P_MEM=".claude/agent-memory/loomwright-loomwright-code-reviewer/MEMORY.md"
P_MEM_DOT=".claude/agent-memory/loomwright-loomwright-code-reviewer/.provenance.jsonl"
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
assert_committable "$Ab" ".claude/agent-memory/loomwright-loomwright-worker/notes/deep.md" "(b) after apply a DEEPLY nested agent-memory file is committable"
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
echo "== (ma) the tracked request file .agent/meta-allowlist.txt — it REQUESTS, only a gh id match GRANTS =="
# WHY: .supervisor/config.json is gitignored, so a fresh clone resolves the allowlist to the remote
# alone and refuses every pre-rename record. The tracked request file travels — so it must never
# GRANT on its own (the ledger collects records about OTHER repos; a granting committed list would
# let whoever controls the file publish them). Granted only when `gh api repos/<slug> --jq .id`
# equals origin's id. NO NETWORK: `gh` is a recording stub on PATH (every invocation appended to
# $MA_LOG), and the absent-gh legs run on a hermetic PATH of symlinks that has no gh at all.
MA_D="$(mkfix)"
mkdir -p "$MA_D/bin"
cat > "$MA_D/bin/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_STUB_LOG"
if [ -n "${GH_STUB_FAIL:-}" ]; then echo "gh: stub failure (not logged in)" >&2; exit 1; fi
# A HUNG gh: `exec` so the stub IS the sleep — the bound's kill reaches it, and a leaked process
# is findable by its unique duration.
if [ -n "${GH_STUB_HANG:-}" ]; then exec sleep "$GH_STUB_HANG"; fi
p="$(printf '%s' "$2" | tr 'A-Z' 'a-z')"
case "$p" in
  repos/acme/widget|repos/acme/old-name) echo 101 ;;   # old-name: the rename redirect, SAME id
  repos/stranger/elsewhere) echo 202 ;;                # a DIFFERENT repository
  *) echo "gh: HTTP 404: Not Found" >&2; exit 1 ;;
esac
GH
chmod +x "$MA_D/bin/gh"
MA_LOG="$MA_D/gh.log"
# A PATH with every tool setup-memory.sh's allowlist path uses EXCEPT gh (CI's ubuntu image and a
# Homebrew mac both ship a real gh in a directory that also holds git/awk, so dropping one
# directory is not enough): a hermetic dir of symlinks, as test-meta-sync.sh builds for no-jq.
MA_NOGH="$MA_D/nogh-bin"; mkdir -p "$MA_NOGH"
for t in bash sh git cat dirname sed awk mktemp rm mkdir tr sort grep env cksum date wc cut head \
         tail jq cp mv ls printf test true false; do
  tp="$(command -v "$t" 2>/dev/null)"
  case "$tp" in /*) ln -sf "$tp" "$MA_NOGH/$t" ;; esac
done
MA_NOGH_PATH="${HERMETIC_SHIM_DIR:+$HERMETIC_SHIM_DIR:}$MA_NOGH"
{ [ -z "$(PATH="$MA_NOGH_PATH" command -v gh)" ] && [ -n "$(PATH="$MA_NOGH_PATH" command -v git)" ]; } \
  || setup_fail "(ma) the no-gh PATH must have git and no gh"
MA_SUT="$MEM"
# ma_run <dir> [VAR=value ...] — `allowlist` on the gh-stub PATH, env allowlist scrubbed; sets
# MA_OUT (stdout), MA_ERR (stderr) and MA_CALLS (gh invocations, one per line).
ma_run() {
  local d="$1"; shift
  : > "$MA_LOG"
  env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" PATH="$MA_D/bin:$PATH" "$@" \
    bash "$MA_SUT" --root "$d" allowlist > "$MA_D/out" 2> "$MA_D/err"
  MA_OUT="$(cat "$MA_D/out")"; MA_ERR="$(cat "$MA_D/err")"; MA_CALLS="$(cat "$MA_LOG")"
}
# ma_run_nogh <dir> — the same on the hermetic PATH with NO gh at all.
ma_run_nogh() {
  : > "$MA_LOG"
  env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST PATH="$MA_NOGH_PATH" "$MA_NOGH/bash" "$MA_SUT" --root "$1" allowlist \
    > "$MA_D/out" 2> "$MA_D/err"
  MA_OUT="$(cat "$MA_D/out")"; MA_ERR="$(cat "$MA_D/err")"; MA_CALLS="$(cat "$MA_LOG")"
}
# ma_stdout_is_list — 0 iff every stdout line is an owner/repo slug (no status text leaked in).
ma_stdout_is_list() {
  local l
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    printf '%s\n' "$l" | env LC_ALL=C grep -Eq '^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$' || return 1
  done <<EOF_MA
$MA_OUT
EOF_MA
  return 0
}
ma_req() { mkdir -p "$1/.agent"; printf '%s\n' "${@:2}" > "$1/.agent/meta-allowlist.txt"; }
ma_ncalls() { [ -n "$MA_CALLS" ] && printf '%s\n' "$MA_CALLS" | wc -l | tr -d ' ' || echo 0; }

# (ma1) A9 — NO request file ⇒ ZERO gh calls on a GitHub-shaped origin.
MA1="$(newgit https://github.com/acme/widget.git)"
ma_run "$MA1"
{ [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ]; } \
  && ok "(ma1) A9: no request file ⇒ the remote alone and ZERO gh calls (lazy lookup)" \
  || no "(ma1) A9: no request file made gh calls or changed the list (out: $MA_OUT; gh: $MA_CALLS)"
# (ma2) A9 + A5 — a file holding only origin's own slug (any case), comments and blanks ⇒ ZERO calls.
MA2="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA2" '# requested slugs' '' '   ' 'ACME/Widget' '  acme/widget  ' '# trailing comment'
ma_run "$MA2"
{ [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ]; } \
  && ok "(ma2) A9/A5: own slug (case-insensitive) + comments + blanks ⇒ granted with ZERO gh calls" \
  || no "(ma2) A9/A5: own-slug-only request file made gh calls or changed the list (out: $MA_OUT; gh: $MA_CALLS)"
hasF 'allowlist: granted ACME/Widget — current remote' "$MA_ERR" \
  && ok "(ma2) the own slug's grant is named on stderr" || no "(ma2) own-slug status missing (err: $MA_ERR)"
hasF '# source: default (current git remote)' "$MA_ERR" && ! hasF 'request file' "$(printf '%s\n' "$MA_ERR" | grep '^# source:')" \
  && ok "(ma2) the # source: line does not credit the request file when it contributed nothing" \
  || no "(ma2) wrong # source: line (err: $MA_ERR)"

# (ma3) THE GRANT AND THE REFUSAL — same-id slug granted, different-id slug ignored + named.
MA3="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA3" '# request' 'acme/old-name' 'stranger/elsewhere'
ma_run "$MA3"
[ "$MA_OUT" = "$(printf 'acme/widget\nacme/old-name')" ] \
  && ok "(ma3) A1: the same-id (renamed) slug acme/old-name is GRANTED beside the remote" \
  || no "(ma3) A1: same-id slug not granted (out: $MA_OUT; err: $MA_ERR)"
# THE A2 assertion — the one the id-comparison mutant below must turn red.
ma3_a2() { ! hasF 'stranger/elsewhere' "$MA_OUT" && hasF 'allowlist: ignored stranger/elsewhere — not this repository' "$MA_ERR"; }
ma3_a2 && ok "(ma3) A2: the different-id slug is NOT granted and is named: 'allowlist: ignored stranger/elsewhere — not this repository'" \
  || no "(ma3) A2: different-id slug granted or not named (out: $MA_OUT; err: $MA_ERR)"
# A6 — stdout is the list and nothing else; the status lines are on stderr.
ma_stdout_is_list && ! hasF 'allowlist:' "$MA_OUT" \
  && ok "(ma3) A6: stdout stays one owner/repo per line — no status text leaked into the list" \
  || no "(ma3) A6: status text reached STDOUT, where meta-sync.sh/validate-entry.sh read it as entries (out: $MA_OUT)"
src_ma3="$(printf '%s\n' "$MA_ERR" | grep '^# source:')"
{ hasF 'default (current git remote)' "$src_ma3" && hasF '.agent/meta-allowlist.txt' "$src_ma3"; } \
  && ok "(ma3) A6: the # source: line names the request file AND keeps 'default (current git remote)'" \
  || no "(ma3) A6: # source: line wrong (got: $src_ma3)"
n_origin="$(printf '%s\n' "$MA_CALLS" | grep -c 'repos/acme/widget ' || true)"
{ [ "$n_origin" = "1" ] && [ "$(ma_ncalls)" = "3" ]; } \
  && ok "(ma3) origin's id looked up exactly ONCE per call (3 gh calls for 2 entries)" \
  || no "(ma3) gh call count wrong (origin lookups $n_origin; calls: $(printf '%s' "$MA_CALLS" | tr '\n' '|'))"
# The scrub consumer: filter-ledger (the same resolver meta-sync.sh's push scrub reads) refuses the
# different-id slug's record and keeps the granted old slug's record.
cat > "$MA3/ledger.jsonl" <<'LEDGER'
{"repo":"acme/old-name","number":1}
{"repo":"stranger/elsewhere","number":2}
LEDGER
ma3_led="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" PATH="$MA_D/bin:$PATH" bash "$MEM" --root "$MA3" filter-ledger --ledger "$MA3/ledger.jsonl" 2>/dev/null)"
if [ -z "$JQ" ]; then
  ok "(ma3) jq unavailable — the ledger-filter consumer leg is skipped (pass)"
else
  { ledger_has_repo "$ma3_led" "acme/old-name" && ! ledger_has_repo "$ma3_led" "stranger/elsewhere"; } \
    && ok "(ma3) A2: the ledger filter keeps the granted old slug's record and REFUSES the different-id slug's" \
    || no "(ma3) A2: ledger filter verdict wrong (kept: $ma3_led)"
fi

# (ma4) A3 — a FAILING gh grants NOTHING from the request file and says why.
ma_run "$MA3" GH_STUB_FAIL=1
{ [ "$MA_OUT" = "acme/widget" ] && hasF 'allowlist: ignored acme/old-name — gh could not resolve origin acme/widget' "$MA_ERR"; } \
  && ok "(ma4) A3: failing gh ⇒ no request entry granted (remote alone) and the reason is named" \
  || no "(ma4) A3: failing gh granted an entry or named no reason (out: $MA_OUT; err: $MA_ERR)"
# (ma5) A3 — an ABSENT gh grants nothing either, and says why.
ma_run_nogh "$MA3"
{ [ "$MA_OUT" = "acme/widget" ] && hasF 'allowlist: ignored acme/old-name — gh is not installed' "$MA_ERR"; } \
  && ok "(ma5) A3: absent gh ⇒ no request entry granted (remote alone) and the reason is named" \
  || no "(ma5) A3: absent gh granted an entry or named no reason (out: $MA_OUT; err: $MA_ERR)"

# (ma6) A4 + A3 — layers 1–3 win as before: the request file is NOT read and gh is NEVER called.
if [ -z "$JQ" ]; then
  ok "(ma6) jq unavailable — the config-layer legs are skipped (pass)"
else
  MA6="$(newgit https://github.com/acme/widget.git)"
  ma_req "$MA6" 'acme/old-name' 'stranger/elsewhere'
  mkdir -p "$MA6/.supervisor"; printf '{"setup_memory":{"repo_allowlist":["acme/widget","fixture-org/kept"]}}\n' > "$MA6/.supervisor/config.json"
  ma_run "$MA6"
  ma6_a4() { [ "$MA_OUT" = "$(printf 'acme/widget\nfixture-org/kept')" ] && [ -z "$MA_CALLS" ] && ! hasF 'allowlist:' "$MA_ERR"; }
  ma6_a4 && ok "(ma6) A4: a present config.json wins — the request file is not read and ZERO gh calls" \
    || no "(ma6) A4: config layer did not win cleanly (out: $MA_OUT; gh: $MA_CALLS; err: $MA_ERR)"
  ma_run_nogh "$MA6"
  [ "$MA_OUT" = "$(printf 'acme/widget\nfixture-org/kept')" ] \
    && ok "(ma6) A3: with gh absent, config.json entries are still granted" \
    || no "(ma6) A3: config entries lost when gh is absent (out: $MA_OUT)"
fi
ma_run "$MA3" LOOMWRIGHT_MEMORY_REPO_ALLOWLIST=acme/only
{ [ "$MA_OUT" = "acme/only" ] && [ -z "$MA_CALLS" ]; } \
  && ok "(ma6) A4: the env layer wins — request file not read, ZERO gh calls" \
  || no "(ma6) A4: env layer did not win cleanly (out: $MA_OUT; gh: $MA_CALLS)"
: > "$MA_LOG"
ma6_flag="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" PATH="$MA_D/bin:$PATH" bash "$MEM" --root "$MA3" --allow acme/flag allowlist 2>/dev/null)"
{ [ "$ma6_flag" = "acme/flag" ] && [ ! -s "$MA_LOG" ]; } \
  && ok "(ma6) A4: --allow wins — request file not read, ZERO gh calls" \
  || no "(ma6) A4: --allow layer did not win cleanly (out: $ma6_flag; gh: $(cat "$MA_LOG"))"

# (ma7) A5 — a malformed entry is NEVER passed to gh and is named as ignored.
MA7="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA7" 'not-a-slug' 'a/b/c' '../x' 'owner/repo name' '$(touch pwned)/x' 'stranger/elsewhere'
ma_run "$MA7"
ma7_a5() {
  [ "$(ma_ncalls)" = "2" ] && hasF 'repos/acme/widget ' "$MA_CALLS" && hasF 'repos/stranger/elsewhere ' "$MA_CALLS" || return 1
  ! hasF 'not-a-slug' "$MA_CALLS" && ! hasF 'a/b/c' "$MA_CALLS" && ! hasF '../x' "$MA_CALLS" \
    && ! hasF 'repo name' "$MA_CALLS" && ! hasF 'pwned' "$MA_CALLS"
}
ma7_a5 && ok "(ma7) A5: malformed entries never reach gh (only origin + the well-formed entry were looked up)" \
  || no "(ma7) A5: a malformed entry reached gh (calls: $(printf '%s' "$MA_CALLS" | tr '\n' '|'))"
{ hasF 'allowlist: ignored not-a-slug — not an owner/repo slug' "$MA_ERR" && hasF 'allowlist: ignored a/b/c — not an owner/repo slug' "$MA_ERR" \
  && hasF 'allowlist: ignored ../x — not an owner/repo slug' "$MA_ERR" && [ "$MA_OUT" = "acme/widget" ] && [ ! -e "$MA7/pwned" ]; } \
  && ok "(ma7) A5: each malformed entry is named as ignored; none granted; nothing executed" \
  || no "(ma7) A5: malformed entries not named or granted (out: $MA_OUT; err: $MA_ERR)"

# (ma8) A5 — a filesystem-path origin grants NO request entry and makes NO gh call.
MA8="$(newgit /Users/someone/parent-dir/myrepo)"
ma_req "$MA8" 'acme/old-name'
ma_run "$MA8"
{ [ -z "$MA_OUT" ] && [ -z "$MA_CALLS" ] && hasF 'allowlist: ignored acme/old-name — origin has no owner/repo slug' "$MA_ERR"; } \
  && ok "(ma8) A5: a filesystem-path origin grants nothing, calls no gh, and says why" \
  || no "(ma8) A5: filesystem-path origin granted or called gh (out: $MA_OUT; gh: $MA_CALLS; err: $MA_ERR)"

# (ma9) a NON-github.com origin grants NOTHING and makes ZERO gh calls. `gh api` defaults to
# github.com, so for a GitLab / GHE origin it would compare two github.com NAMESAKES: the stub
# answers acme/widget and acme/old-name with the SAME id 101, which a host-blind check would grant.
MA9_OK=1; MA9_DETAIL=""
ma9_leg() {
  local u d
  MA9_OK=1; MA9_DETAIL=""
  for u in https://gitlab.com/acme/widget.git git@ghe.corp.example:acme/widget.git ssh://git@bitbucket.org/acme/widget.git; do
    d="$(newgit "$u")"
    ma_req "$d" 'acme/old-name'
    ma_run "$d"
    if ! { [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ] \
           && hasF 'allowlist: ignored acme/old-name — origin is not on github.com' "$MA_ERR"; }; then
      MA9_OK=0; MA9_DETAIL="$MA9_DETAIL [$u: out=$(printf '%s' "$MA_OUT" | tr '\n' ' ') gh=$(printf '%s' "$MA_CALLS" | tr '\n' '|')]"
    fi
  done
  [ "$MA9_OK" = 1 ]
}
ma9_leg && ok "(ma9) non-github.com origins (https gitlab, scp GHE, ssh:// bitbucket) grant nothing, call no gh, and say why" \
  || no "(ma9) a non-github.com origin granted a same-id namesake or called gh:$MA9_DETAIL"
# ... and the host match is case-insensitive and accepts the scp / ssh:// github.com forms.
MA9G=1
for u in https://GitHub.COM/acme/widget.git git@github.com:acme/widget.git ssh://git@github.com/acme/widget.git; do
  d="$(newgit "$u")"; ma_req "$d" 'acme/old-name'; ma_run "$d"
  [ "$MA_OUT" = "$(printf 'acme/widget\nacme/old-name')" ] || MA9G=0
done
[ "$MA9G" = 1 ] && ok "(ma9) github.com origins in https (any case), scp and ssh:// form still grant the same-id slug" \
  || no "(ma9) the host check rejected a github.com origin form (last out: $MA_OUT; err: $MA_ERR)"

# (ma10) a HUNG gh is BOUNDED: killed after LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT seconds, treated as gh
# failing (nothing granted, reason named), no further gh call after the overrun, no sleeping child
# left behind, and nothing written to TMPDIR (the runner is file-free — `allowlist` writes nothing).
MA10="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA10" 'acme/old-name' 'stranger/elsewhere'
MA10_TMP="$MA_D/ma10-tmpdir"; mkdir -p "$MA10_TMP"
# A per-run duration (7.<pid>) and an anchored pattern, so a concurrent run of this suite in another
# checkout can never be mistaken for a leak here.
MA10_HANG="7.$$"
MA10_PAT="^sleep 7\\.$$\$"
ma10_leg() {
  local t0 t1
  t0="$(date +%s)"
  ma_run "$MA10" LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT=1 GH_STUB_HANG="$MA10_HANG" TMPDIR="$MA10_TMP"
  t1="$(date +%s)"
  MA10_ELAPSED=$((t1 - t0))
  [ "$MA_OUT" = "acme/widget" ] && [ "$MA10_ELAPSED" -lt 5 ] && [ "$(ma_ncalls)" = "1" ] \
    && hasF 'allowlist: ignored acme/old-name — gh timed out after 1s resolving origin acme/widget' "$MA_ERR" \
    && hasF 'allowlist: ignored stranger/elsewhere — gh timed out after 1s resolving origin' "$MA_ERR"
}
MA10_ELAPSED=""
ma10_leg && ok "(ma10) a hung gh is killed at the 1s bound (${MA10_ELAPSED}s total), grants nothing, names why, and is not asked again" \
  || no "(ma10) a hung gh was not bounded or granted something (elapsed ${MA10_ELAPSED}s; out: $MA_OUT; gh: $(printf '%s' "$MA_CALLS" | tr '\n' '|'); err: $MA_ERR)"
{ ! pgrep -f "$MA10_PAT" >/dev/null 2>&1 && [ -z "$(ls -A "$MA10_TMP" 2>/dev/null)" ]; } \
  && ok "(ma10) the killed gh was reaped (no 'sleep $MA10_HANG' left running) and no temp file was left in TMPDIR" \
  || no "(ma10) the bounded runner leaked a process or a temp file (procs: $(pgrep -f "$MA10_PAT" | tr '\n' ' '); tmp: $(ls -A "$MA10_TMP" 2>/dev/null | tr '\n' ' '))"
pkill -f "$MA10_PAT" 2>/dev/null || true
# A hang on an ENTRY lookup (origin answers) is bounded too, and stops further lookups.
cat > "$MA_D/bin-entryhang-gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_STUB_LOG"
case "$2" in
  repos/acme/widget) echo 101 ;;
  *) exec sleep "$GH_STUB_HANG" ;;
esac
GH
mkdir -p "$MA_D/bin-entryhang"; mv "$MA_D/bin-entryhang-gh" "$MA_D/bin-entryhang/gh"; chmod +x "$MA_D/bin-entryhang/gh"
: > "$MA_LOG"
env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" GH_STUB_HANG="$MA10_HANG" LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT=1 \
  TMPDIR="$MA10_TMP" PATH="$MA_D/bin-entryhang:$PATH" bash "$MEM" --root "$MA10" allowlist > "$MA_D/out" 2> "$MA_D/err"
MA_OUT="$(cat "$MA_D/out")"; MA_ERR="$(cat "$MA_D/err")"; MA_CALLS="$(cat "$MA_LOG")"
{ [ "$MA_OUT" = "acme/widget" ] && [ "$(ma_ncalls)" = "2" ] \
  && hasF 'allowlist: ignored acme/old-name — gh timed out after 1s' "$MA_ERR" \
  && hasF 'allowlist: ignored stranger/elsewhere — gh timed out after 1s' "$MA_ERR" \
  && ! pgrep -f "$MA10_PAT" >/dev/null 2>&1 && [ -z "$(ls -A "$MA10_TMP" 2>/dev/null)" ]; } \
  && ok "(ma10) a hung ENTRY lookup is bounded, grants nothing, and stops further gh calls (2 calls: origin + one entry)" \
  || no "(ma10) a hung entry lookup was not bounded cleanly (out: $MA_OUT; gh: $(printf '%s' "$MA_CALLS" | tr '\n' '|'); err: $MA_ERR)"
pkill -f "$MA10_PAT" 2>/dev/null || true

# (ma13) the bound holds on the PIPE, not just gh's pid: anything gh forks inherits the capture
# pipe, so a child left behind must be killed at the bound too. (a) gh dies on TERM but its child
# IGNORES TERM and is re-parented once gh is reaped; (b) gh EXITS 0 at once, printing the matching
# id, and leaves a child holding the pipe. Both must finish inside the bound + the 1s TERM grace,
# grant nothing (a gh whose group outlives the bound is a timeout, its output discarded) and leave
# no child running. Per-run sleep durations (8.1<pid> / 8.2<pid>) are the leak markers.
MA13="$(newgit https://github.com/acme/widget.git)"
ma_req "$MA13" 'acme/old-name'
MA13A_HANG="8.1$$"; MA13A_PAT="^sleep 8\\.1$$\$"
MA13B_HANG="8.2$$"; MA13B_PAT="^sleep 8\\.2$$\$"
mkdir -p "$MA_D/bin-orphan-term" "$MA_D/bin-orphan-exit0"
cat > "$MA_D/bin-orphan-term/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_STUB_LOG"
( trap '' TERM; exec sleep "$GH_STUB_HANG" ) &
wait
GH
cat > "$MA_D/bin-orphan-exit0/gh" <<'GH'
#!/bin/sh
printf '%s\n' "$*" >> "$GH_STUB_LOG"
( sleep "$GH_STUB_HANG" ) &
echo 101
exit 0
GH
chmod +x "$MA_D/bin-orphan-term/gh" "$MA_D/bin-orphan-exit0/gh"
# ma13_leg <bin-dir> <hang> <pattern> — 0 iff bounded (< 5s), nothing granted, timeout named, one
# gh call, no child left. Sets MA13_ELAPSED.
ma13_leg() {
  local t0 t1
  : > "$MA_LOG"
  t0="$(date +%s)"
  env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST GH_STUB_LOG="$MA_LOG" GH_STUB_HANG="$2" LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT=1 \
    TMPDIR="$MA10_TMP" PATH="$1:$PATH" bash "$MA_SUT" --root "$MA13" allowlist > "$MA_D/out" 2> "$MA_D/err"
  t1="$(date +%s)"
  MA13_ELAPSED=$((t1 - t0))
  MA_OUT="$(cat "$MA_D/out")"; MA_ERR="$(cat "$MA_D/err")"; MA_CALLS="$(cat "$MA_LOG")"
  [ "$MA_OUT" = "acme/widget" ] && [ "$MA13_ELAPSED" -lt 5 ] && [ "$(ma_ncalls)" = "1" ] \
    && hasF 'allowlist: ignored acme/old-name — gh timed out after 1s resolving origin acme/widget' "$MA_ERR" \
    && ! hasF 'Terminated' "$MA_ERR" && ! pgrep -f "$3" >/dev/null 2>&1 \
    && [ -z "$(ls -A "$MA10_TMP" 2>/dev/null)" ]
}
MA13_ELAPSED=""
ma13_leg "$MA_D/bin-orphan-term" "$MA13A_HANG" "$MA13A_PAT" \
  && ok "(ma13) a TERM-ignoring child of a killed gh is killed with it: bounded (${MA13_ELAPSED}s), nothing granted, no 'sleep $MA13A_HANG' left" \
  || no "(ma13) a TERM-ignoring child outlived the bound or leaked (elapsed ${MA13_ELAPSED}s; out: $MA_OUT; procs: $(pgrep -f "$MA13A_PAT" | tr '\n' ' '); err: $MA_ERR)"
pkill -f "$MA13A_PAT" 2>/dev/null || true
ma13_leg "$MA_D/bin-orphan-exit0" "$MA13B_HANG" "$MA13B_PAT" \
  && ok "(ma13) a gh that exits 0 leaving a child on the pipe is bounded (${MA13_ELAPSED}s), counted as a timeout (its id not granted), no 'sleep $MA13B_HANG' left" \
  || no "(ma13) an exit-0 gh's lingering child was not bounded or its id was granted (elapsed ${MA13_ELAPSED}s; out: $MA_OUT; procs: $(pgrep -f "$MA13B_PAT" | tr '\n' ' '); err: $MA_ERR)"
pkill -f "$MA13B_PAT" 2>/dev/null || true

# (ma11) the WORK the request file drives is CAPPED, not just each call: 25 non-own entries (the
# first one the same-id old slug) ⇒ at most cap + 1 = 21 gh calls (origin + 20 entries), the same-id
# entry still granted in file order, and each of the 5 entries past the cap named and never passed to gh.
MA11="$(newgit https://github.com/acme/widget.git)"
MA11_ENTRIES="acme/old-name"; i=2
while [ "$i" -le 25 ]; do MA11_ENTRIES="$MA11_ENTRIES
fill-org/repo-$i"; i=$((i + 1)); done
mkdir -p "$MA11/.agent"; printf '%s\n' "$MA11_ENTRIES" > "$MA11/.agent/meta-allowlist.txt"
ma11_leg() {
  local j
  ma_run "$MA11"
  [ "$(ma_ncalls)" -le 21 ] && [ "$MA_OUT" = "$(printf 'acme/widget\nacme/old-name')" ] || return 1
  [ "$(printf '%s\n' "$MA_ERR" | grep -c 'over the 20-entry cap')" = "5" ] || return 1
  for j in 21 22 23 24 25; do
    hasF "allowlist: ignored fill-org/repo-$j — over the 20-entry cap" "$MA_ERR" || return 1
    ! hasF "repos/fill-org/repo-$j " "$MA_CALLS" || return 1
  done
  return 0
}
ma11_leg && ok "(ma11) 25 request entries ⇒ $(ma_ncalls) gh calls (cap 20 + origin), same-id slug still granted, the 5 over-cap entries named and never passed to gh" \
  || no "(ma11) the request file drove uncapped gh work or mis-named the over-cap entries (calls: $(ma_ncalls); out: $MA_OUT; err: $(printf '%s' "$MA_ERR" | tail -n 6 | tr '\n' '|'))"
# ... the env override is clamped: 0 / junk fall back to the default, a huge value to the ceiling.
ma_run "$MA11" LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES=3
{ [ "$(ma_ncalls)" = "4" ] && hasF 'allowlist: ignored fill-org/repo-5 — over the 3-entry cap' "$MA_ERR"; } \
  && ok "(ma11) LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES=3 ⇒ 4 gh calls, entry 5 named over the 3-entry cap" \
  || no "(ma11) the cap override was not honoured (calls: $(ma_ncalls); err: $(printf '%s' "$MA_ERR" | tail -n 3 | tr '\n' '|'))"
ma_run "$MA11" LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES=999999999999999999999999
{ [ "$(ma_ncalls)" = "26" ] && ! hasF 'entry cap' "$MA_ERR"; } \
  && ok "(ma11) an oversized override is clamped to the ceiling (100), not overflowed: all 25 entries compared" \
  || no "(ma11) oversized cap override mishandled (calls: $(ma_ncalls); err: $(printf '%s' "$MA_ERR" | tail -n 3 | tr '\n' '|'))"
# ... and READING is capped too: an entry past line 200 is never read (zero gh calls), named once.
MA12="$(newgit https://github.com/acme/widget.git)"
mkdir -p "$MA12/.agent"
awk 'BEGIN { for (i = 1; i <= 200; i++) print "# filler " i; print "acme/old-name" }' > "$MA12/.agent/meta-allowlist.txt"
ma_run "$MA12"
{ [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ] \
  && [ "$(printf '%s\n' "$MA_ERR" | grep -c 'allowlist: stopped reading .agent/meta-allowlist.txt after 200 lines')" = "1" ]; } \
  && ok "(ma11) a line past the 200-line read cap is never read or passed to gh, and the stop is named once" \
  || no "(ma11) the read cap did not hold (out: $MA_OUT; gh: $MA_CALLS; err: $(printf '%s' "$MA_ERR" | tail -n 2 | tr '\n' '|'))"

# (ma14) ONE origin read per resolution, ONE parse for slug AND host. A git shim on PATH logs every
# `remote get-url` and execs the real git. Each URL form must resolve the slug (acme/widget), gate
# on the host it came from (github.com forms grant the same-id acme/old-name; a scheme-less gitlab
# origin grants nothing with zero gh calls), and read origin's URL EXACTLY ONCE — the request file
# needs both slug and host, so two parsers would read twice.
MA_GITC="$MA_D/bin-gitcount"; mkdir -p "$MA_GITC"
MA_REAL_GIT="$(command -v git)"
printf '#!/bin/sh\ncase " $* " in *" remote get-url "*) printf "%%s\\n" "$*" >> "$GIT_COUNT_LOG" ;; esac\nexec "%s" "$@"\n' \
  "$MA_REAL_GIT" > "$MA_GITC/git"
chmod +x "$MA_GITC/git"
MA_GITLOG="$MA_D/git-count.log"
MA14_DETAIL=""
ma14_leg() {
  local u d want n
  MA14_DETAIL=""
  for u in https://github.com/acme/widget.git ssh://git@github.com:22/acme/widget.git git@github.com:acme/widget.git \
           github.com/acme/widget https://user:tok@GitHub.com:443/acme/widget.git gitlab.com/acme/widget; do
    d="$(newgit "$u")"; ma_req "$d" 'acme/old-name'
    : > "$MA_GITLOG"
    ma_run "$d" PATH="$MA_GITC:$MA_D/bin:$PATH" GIT_COUNT_LOG="$MA_GITLOG"
    n="$(grep -c 'remote get-url' "$MA_GITLOG" 2>/dev/null || true)"
    case "$u" in
      gitlab.com/*) want="acme/widget"
        { [ -z "$MA_CALLS" ] && hasF 'allowlist: ignored acme/old-name — origin is not on github.com' "$MA_ERR"; } \
          || MA14_DETAIL="$MA14_DETAIL [$u: host gate wrong gh=$(printf '%s' "$MA_CALLS" | tr '\n' '|')]" ;;
      *) want="$(printf 'acme/widget\nacme/old-name')" ;;
    esac
    [ "$MA_OUT" = "$want" ] || MA14_DETAIL="$MA14_DETAIL [$u: out=$(printf '%s' "$MA_OUT" | tr '\n' ' ')]"
    [ "$n" = "1" ] || MA14_DETAIL="$MA14_DETAIL [$u: $n origin reads]"
  done
  [ -z "$MA14_DETAIL" ]
}
ma14_leg && ok "(ma14) https / ssh:// / scp / scheme-less / userinfo+port origins: slug and host agree, and origin is read EXACTLY ONCE per resolution" \
  || no "(ma14) slug/host disagreed or origin was read more than once:$MA14_DETAIL"

# (ma15) a request file that EXISTS but cannot be read (mode 000, or a directory at that path) is
# NAMED on stderr and grants nothing; an ABSENT file stays silent (ma1's fixture, re-run).
MA15_DETAIL=""
ma15_leg() {
  local d
  MA15_DETAIL=""
  d="$(newgit https://github.com/acme/widget.git)"; ma_req "$d" 'acme/old-name'; chmod 000 "$d/.agent/meta-allowlist.txt"
  if [ -r "$d/.agent/meta-allowlist.txt" ]; then
    MA15_ROOT=1   # running as root: mode 000 is still readable, so only the directory case is meaningful
  else
    ma_run "$d"
    { [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ] \
      && hasF 'allowlist: ignored .agent/meta-allowlist.txt — not readable' "$MA_ERR"; } || MA15_DETAIL="$MA15_DETAIL [mode 000: out=$MA_OUT err=$MA_ERR]"
  fi
  chmod 600 "$d/.agent/meta-allowlist.txt"
  d="$(newgit https://github.com/acme/widget.git)"; mkdir -p "$d/.agent/meta-allowlist.txt"
  ma_run "$d"
  { [ "$MA_OUT" = "acme/widget" ] && [ -z "$MA_CALLS" ] \
    && hasF 'allowlist: ignored .agent/meta-allowlist.txt — not readable' "$MA_ERR"; } || MA15_DETAIL="$MA15_DETAIL [directory: out=$MA_OUT err=$MA_ERR]"
  ma_run "$MA1"
  hasF 'not readable' "$MA_ERR" && MA15_DETAIL="$MA15_DETAIL [absent file was named: $MA_ERR]"
  [ -z "$MA15_DETAIL" ]
}
MA15_ROOT=0
ma15_leg && ok "(ma15) an unreadable request file (mode 000$([ "$MA15_ROOT" = 1 ] && printf ' skipped — root'), a directory) is named on stderr and grants nothing; an absent one stays silent" \
  || no "(ma15) an unreadable request file was skipped silently or granted something:$MA15_DETAIL"

# Mutation controls — each gated on the mutant being NON-EMPTY, DIFFERENT from the original and
# `bash -n`-clean (an unapplied or broken mutant would otherwise "pass" silently).
# ma_mutant <name> <sed-expr> → prints the mutant path, status 1 when the gate fails.
ma_mutant() {
  local m="$MA_D/mut-$1.sh"
  sed -e "$2" "$MEM" > "$m" 2>/dev/null || return 1
  [ -s "$m" ] && ! cmp -s "$MEM" "$m" && bash -n "$m" 2>/dev/null || return 1
  printf '%s' "$m"
}
# ma_mutant_awk <name> <exact-line> <line-to-insert-before-it>
ma_mutant_awk() {
  local m="$MA_D/mut-$1.sh"
  awk -v t="$2" -v ins="$3" '$0 == t { print ins } { print }' "$MEM" > "$m" 2>/dev/null || return 1
  [ -s "$m" ] && ! cmp -s "$MEM" "$m" && bash -n "$m" 2>/dev/null || return 1
  printf '%s' "$m"
}
# The A3 / A5 sed programs, read from quoted heredocs so no shell quoting touches them (`read -d ''`,
# not `$(cat <<…)`: bash 3.2 mis-parses a heredoc holding an unbalanced `)` inside `$( )`).
MA_SED_A3=""; IFS= read -r -d '' MA_SED_A3 <<'SED'
s/if \[ "\$origin_state" != "ok" \]; then/if false; then/
s/^      ''|\*\[!0-9\]\*)$/      __mutant_never__)/
SED
MA_SED_A5=""; IFS= read -r -d '' MA_SED_A5 <<'SED'
s/^    if ! printf /    if false \&\& printf /
s@^    case "/\$e/" in \*/\./\*|\*/\.\./\*)$@    case "/$e/" in __mutant_never__)@
SED
# (A2) the id comparison removed ⇒ every well-formed entry granted ⇒ the A2 leg must turn red.
if M="$(ma_mutant a2 's/if \[ "\$id" = "\$origin_id" \]; then/if true; then/')"; then
  MA_SUT="$M"; ma_run "$MA3"; MA_SUT="$MEM"
  ma3_a2 && no "(ma-mut A2) REFUTED: with the id comparison removed the A2 leg still passes — it is not load-bearing" \
    || ok "(ma-mut A2) removing the id comparison grants stranger/elsewhere, so the A2 leg turns red"
else no "(ma-mut A2) could not build the mutant (empty, unchanged or bash -n failed) — inconclusive"; fi
# (A3) the gh-failure guards dropped ⇒ "" = "" grants on a failing gh ⇒ (ma4) must turn red.
if M="$(ma_mutant a3 "$MA_SED_A3")"; then
  MA_SUT="$M"; ma_run "$MA3" GH_STUB_FAIL=1; MA_SUT="$MEM"
  [ "$MA_OUT" = "acme/widget" ] && no "(ma-mut A3) REFUTED: with the failure guards dropped a failing gh still grants nothing — (ma4) is not load-bearing" \
    || ok "(ma-mut A3) dropping the gh-failure guards grants on a failing gh, so (ma4) turns red (out: $(printf '%s' "$MA_OUT" | tr '\n' ' '))"
else no "(ma-mut A3) could not build the mutant — inconclusive"; fi
# (A6) the `>&2` dropped from the 'not this repository' line ⇒ (ma3)'s stdout-is-the-list leg red.
if M="$(ma_mutant a6 's/\(echo "allowlist: ignored \$e — not this repository"\) >&2/\1/')"; then
  MA_SUT="$M"; ma_run "$MA3"; MA_SUT="$MEM"
  ma_stdout_is_list && no "(ma-mut A6) REFUTED: status on stdout still reads as a clean list" \
    || ok "(ma-mut A6) a status line on stdout is caught by the A6 leg"
else no "(ma-mut A6) could not build the mutant — inconclusive"; fi
# (A5) the owner/repo shape check dropped ⇒ malformed entries reach gh ⇒ (ma7) red.
if M="$(ma_mutant a5 "$MA_SED_A5")"; then
  MA_SUT="$M"; ma_run "$MA7"; MA_SUT="$MEM"
  ma7_a5 && no "(ma-mut A5) REFUTED: without the shape check malformed entries still never reach gh" \
    || ok "(ma-mut A5) without the shape check a malformed entry reaches gh, so (ma7) turns red"
else no "(ma-mut A5) could not build the mutant — inconclusive"; fi
# (A9) origin's id looked up EAGERLY at the top of the layer ⇒ (ma1)'s zero-call leg red.
if M="$(ma_mutant_awk a9 '  [ -f "$f" ] && [ -r "$f" ] || return 0' '  [ -n "$own" ] && gh api "repos/$own" --jq .id </dev/null >/dev/null 2>&1')"; then
  MA_SUT="$M"; ma_run "$MA1"; MA_SUT="$MEM"
  [ -z "$MA_CALLS" ] && no "(ma-mut A9) REFUTED: an eager origin lookup still made zero gh calls" \
    || ok "(ma-mut A9) an eager origin lookup makes a gh call with no request file, so (ma1) turns red"
else no "(ma-mut A9) could not build the mutant — inconclusive"; fi
# (HOST) the github.com host check dropped ⇒ a GitLab/GHE origin compares github.com namesakes and
# grants acme/old-name ⇒ (ma9) must turn red.
if M="$(ma_mutant host 's/^      elif \[ "\$ORIGIN_HOST" != "github.com" \]; then$/      elif false; then/')"; then
  MA_SUT="$M"; ma9_leg; MA9_RC=$?; MA_SUT="$MEM"
  [ "$MA9_RC" -eq 0 ] && no "(ma-mut HOST) REFUTED: without the host check a non-github.com origin still grants nothing — (ma9) is not load-bearing" \
    || ok "(ma-mut HOST) dropping the github.com host check grants a namesake for a non-github origin, so (ma9) turns red"
else no "(ma-mut HOST) could not build the mutant — inconclusive"; fi
# (ONE-READ) the host gate re-resolves origin lazily (a second `git remote get-url`) ⇒ (ma14) red.
if M="$(ma_mutant oneread 's/^      elif \[ "\$ORIGIN_HOST" != "github.com" \]; then$/      elif resolve_origin; [ "$ORIGIN_HOST" != "github.com" ]; then/')"; then
  MA_SUT="$M"; ma14_leg; MA14_RC=$?; MA_SUT="$MEM"
  [ "$MA14_RC" -eq 0 ] && no "(ma-mut ONE-READ) REFUTED: a second origin read still counted as one — (ma14) is not load-bearing" \
    || ok "(ma-mut ONE-READ) re-reading origin for the host gate makes 2 reads, so (ma14) turns red"
else no "(ma-mut ONE-READ) could not build the mutant — inconclusive"; fi
# (UNREADABLE) the unreadable-file status line dropped ⇒ the skip is silent again ⇒ (ma15) red.
if M="$(ma_mutant unreadable 's/^  if \[ -e "\$f" \] && ! .*; then$/  if false; then/')"; then
  MA_SUT="$M"; ma15_leg; MA15_RC=$?; MA_SUT="$MEM"
  [ "$MA15_RC" -eq 0 ] && no "(ma-mut UNREADABLE) REFUTED: without the status line an unreadable request file is still named — (ma15) is not load-bearing" \
    || ok "(ma-mut UNREADABLE) dropping the status line skips an unreadable request file silently, so (ma15) turns red"
else no "(ma-mut UNREADABLE) could not build the mutant — inconclusive"; fi
# (BOUND) the overrun check dropped ⇒ the runner waits out the hung gh ⇒ (ma10)'s bound leg red.
if M="$(ma_mutant bound 's/^          if \[ "\$ticks" -ge "\$max" \]; then$/          if false; then/')"; then
  MA_SUT="$M"; ma10_leg; MA10_RC=$?; MA_SUT="$MEM"
  pkill -f "$MA10_PAT" 2>/dev/null || true
  [ "$MA10_RC" -eq 0 ] && no "(ma-mut BOUND) REFUTED: without the overrun check the hung gh still finished inside the bound — (ma10) is not load-bearing" \
    || ok "(ma-mut BOUND) without the overrun check the hung gh is waited out (${MA10_ELAPSED}s), so (ma10) turns red"
else no "(ma-mut BOUND) could not build the mutant — inconclusive"; fi
# (GROUP-KILL) TERM/KILL sent to gh's pid instead of its group ⇒ the TERM-ignoring child survives
# and holds the pipe ⇒ (ma13)'s (a) leg red.
if M="$(ma_mutant groupkill 's/kill -TERM -- "-\$gpid" 2>\/dev\/null$/kill -TERM "$gpid" 2>\/dev\/null/;s/kill -KILL -- "-\$gpid" 2>\/dev\/null$/kill -KILL "$gpid" 2>\/dev\/null/')"; then
  MA_SUT="$M"; ma13_leg "$MA_D/bin-orphan-term" "$MA13A_HANG" "$MA13A_PAT"; MA13_RC=$?; MA_SUT="$MEM"
  pkill -f "$MA13A_PAT" 2>/dev/null || true
  [ "$MA13_RC" -eq 0 ] && no "(ma-mut GROUP-KILL) REFUTED: signalling gh's pid alone still bounded the TERM-ignoring child — (ma13a) is not load-bearing" \
    || ok "(ma-mut GROUP-KILL) signalling gh's pid instead of its group leaves the child on the pipe (${MA13_ELAPSED}s), so (ma13a) turns red"
else no "(ma-mut GROUP-KILL) could not build the mutant — inconclusive"; fi
# (GROUP-POLL) the watchdog polls gh's pid instead of its group ⇒ it stops when gh exits 0 and
# nothing bounds the lingering child ⇒ (ma13)'s (b) leg red.
if M="$(ma_mutant grouppoll 's/^        while kill -0 -- "-\$gpid" 2>\/dev\/null; do$/        while kill -0 "$gpid" 2>\/dev\/null; do/')"; then
  MA_SUT="$M"; ma13_leg "$MA_D/bin-orphan-exit0" "$MA13B_HANG" "$MA13B_PAT"; MA13_RC=$?; MA_SUT="$MEM"
  pkill -f "$MA13B_PAT" 2>/dev/null || true
  [ "$MA13_RC" -eq 0 ] && no "(ma-mut GROUP-POLL) REFUTED: polling gh's pid alone still bounded the exit-0 gh's child — (ma13b) is not load-bearing" \
    || ok "(ma-mut GROUP-POLL) polling gh's pid instead of its group stops at gh's exit and the child holds the pipe (${MA13_ELAPSED}s), so (ma13b) turns red"
else no "(ma-mut GROUP-POLL) could not build the mutant — inconclusive"; fi
# (CAP) the comparison cap dropped ⇒ every entry reaches gh ⇒ (ma11)'s cap leg red.
if M="$(ma_mutant cap 's/^    if \[ "\$compared" -ge "\$cap" \]; then$/    if false; then/')"; then
  MA_SUT="$M"; ma11_leg; MA11_RC=$?; MA_SUT="$MEM"
  [ "$MA11_RC" -eq 0 ] && no "(ma-mut CAP) REFUTED: without the cap 25 entries still made at most cap+1 gh calls — (ma11) is not load-bearing" \
    || ok "(ma-mut CAP) without the cap every entry reaches gh ($(ma_ncalls) calls), so (ma11) turns red"
else no "(ma-mut CAP) could not build the mutant — inconclusive"; fi
# (A4) the request-file layer moved ABOVE the config layer ⇒ (ma6)'s config-wins leg red.
if [ -n "$JQ" ]; then
  if M="$(ma_mutant_awk a4 '  if [ -z "$out" ] && command -v jq >/dev/null 2>&1 && [ -f "$CFG" ]; then' '  [ -z "$out" ] && out="$(meta_allowlist_grants "$(remote_slug)")"')"; then
    MA_SUT="$M"; ma_run "$MA6"; MA_SUT="$MEM"
    ma6_a4 && no "(ma-mut A4) REFUTED: with the request layer above config the A4 leg still passes" \
      || ok "(ma-mut A4) moving the request layer above config reads it and calls gh, so (ma6) turns red"
  else no "(ma-mut A4) could not build the mutant — inconclusive"; fi
fi

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
if sleep 0.05 2>/dev/null; then   # fixed-sleep-ok: capability probe (does this sleep take fractions?), not a wait
  gate_unit=0.05; gate_max=1200; else gate_unit=1; gate_max=60; fi
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
[ "$(env LC_ALL=C tr -d '\000' < "$F8/.gitignore" | wc -c)" -lt "$(wc -c < "$F8/.gitignore")" ] \
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
before_i="$(cd "$Ii" && find . -not -path './.git/*' -not -name '.git' | env LC_ALL=C sort)"
mem "$Ii" check >/dev/null 2>&1
after_i="$(cd "$Ii" && find . -not -path './.git/*' -not -name '.git' | env LC_ALL=C sort)"
[ "$before_i" = "$after_i" ] && ok "(i1) check created no files at all (read-only)" || no "(i1) check created or removed files"
# (i2) apply touches only the sanctioned paths — anything else under the root is a containment breach.
head_before="$(git -C "$Ii" rev-parse HEAD 2>/dev/null)"
idx_before="$(git -C "$Ii" diff --cached --name-only 2>/dev/null | env LC_ALL=C sort)"
mem "$Ii" apply >/dev/null 2>&1
unexpected="$(cd "$Ii" && find . -not -path './.git/*' -not -name '.git' -type f \
  ! -name '.gitignore' ! -name '.gitignore.backup.*' ! -name 'seed.txt' \
  ! -path './.supervisor/config.json' \
  ! -path './.claude/agent-memory/*' ! -path './.supervisor/memory/*' \
  ! -path './.claude/worktrees/*' ! -name 'settings.local.json' ! -path './.supervisor/logs/*' \
  | env LC_ALL=C sort)"
[ -z "$unexpected" ] && ok "(i2) apply wrote ONLY .gitignore, its backup, and .supervisor/config.json" || no "(i2) apply wrote unexpected files: $(tr '\n' ' ' <<< "$unexpected")"
[ ! -e "$Ii/.claude/settings.json" ] && ok "(i2) no <root>/.claude/settings.json written" || no "(i2) apply wrote <root>/.claude/settings.json"
# (i3) nothing was staged, committed, or otherwise pushed into git — behavioural, not a grep.
mem "$Ii" remove >/dev/null 2>&1
head_after="$(git -C "$Ii" rev-parse HEAD 2>/dev/null)"
idx_after="$(git -C "$Ii" diff --cached --name-only 2>/dev/null | env LC_ALL=C sort)"
[ "$head_before" = "$head_after" ] && ok "(i3) HEAD unchanged across apply+remove (nothing committed)" || no "(i3) HEAD MOVED — the helper committed something"
[ "$idx_before" = "$idx_after" ] && ok "(i3) the git index is unchanged across apply+remove (nothing staged)" || no "(i3) the helper STAGED files (index changed)"
# (i4) static corroboration: every git invocation in the helper is read-only. Extracted from the
# actual `git -C "<dir>" <subcommand>` call sites, NOT a bare `git rm` text grep — the helper's
# user-facing copy legitimately QUOTES `git rm -r --cached` as guidance, and a text grep would
# false-positive on that prose.
git_subs="$(grep -oE 'git -C "[^"]*" [a-z-]+' "$MEM" | awk '{print $NF}' | env LC_ALL=C sort -u | tr '\n' ' ')"
case "$git_subs" in
  *add*|*commit*|*rm*|*push*|*reset*|*checkout*|*stash*)
    no "(i4) a mutating git subcommand is invoked by setup-memory.sh: $git_subs" ;;
  *)
    ok "(i4) only read-only git subcommands are invoked: $git_subs" ;;
esac
# The WRITE-CONTAINMENT INVARIANT's ONE amendment (af36-03): the user-scope consent record. So the
# code may reference HOME ONLY inside do_consent (the record's sole writer/reader) — never in any
# other code line; comment lines may name the record's path. Group (cs) proves the behaviour (grant
# writes exactly that one file); this static leg pins WHERE the reference may live.
mem_src="$(awk '/^do_consent\(\) \{$/ { inc = 1 } inc && /^}$/ { inc = 0; next } !inc && $0 !~ /^[[:space:]]*#/' "$MEM")"
hasF 'HOME' "$mem_src" && no "(i4) setup-memory.sh references \$HOME outside do_consent (must never write under ~/.claude/ except the consent record)" || ok "(i4) setup-memory.sh references \$HOME only inside do_consent (the one user-scope write)"
hasF 'HOME' "$(awk '/^do_consent\(\) \{$/ { inc = 1 } inc { print } inc && /^}$/ { exit }' "$MEM")" && ok "(i4) do_consent is where the HOME reference lives (the scan above is not vacuous)" || no "(i4) do_consent was not found — the HOME scan scoped nothing"

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
    printf '{"schema_version": 1, "ts": "2026-08-04T14:06:03Z", "repo": "otherhub/otherrepo", "number": 124}\n' >> "$d/$P_LEDGER"
    n_grep="$(grep -cF '"repo":"otherhub/otherrepo"' "$d/$P_LEDGER" 2>/dev/null || true)"; [ -n "$n_grep" ] || n_grep=0
    n_jq="$(jq -s 'map(select(.repo == "otherhub/otherrepo")) | length' "$d/$P_LEDGER" 2>/dev/null)"
    if [ "${n_grep:-0}" -eq 0 ] && [ "$n_jq" = "1" ]; then
      ok "(l2) THE EVASION IS REAL: a compact-form grep sees 0 spaced-form foreign records where jq sees 1 — this is why every ledger assertion here is jq"
    else
      no "(l2) the spaced-form evasion fixture did not behave as claimed (grep=$n_grep, jq=$n_jq) — the gate assertion below would be vacuous"
    fi
    out="$(mem "$d" apply 2>&1)"; rc=$?
    [ "$rc" -eq 0 ] && ok "(l2) apply STILL EXITS 0 on the refusal path (fail-closed in the WRITE dimension, never in the exit status)" || no "(l2) apply exited $rc on the refusal path — the FAIL-SAFE CONTRACT is broken"
    assert_ignored     "$d" "$P_LEDGER" "(l2) the gate REFUSED: the ledger is IGNORED again, so the spaced-form foreign record cannot be published"
    assert_committable "$d" "$P_MEM"    "(l2) the two memory stores stay APPLIED while only the ledger is withheld"
    hasF 'otherhub/otherrepo' "$out" && ok "(l2) the refusal NAMES the offending slug" || no "(l2) the refusal does not name the offending slug"
    # ...and removing the record makes the gate PASS again — red↔green both proven, so the gate keys
    # on the record and not on some incidental property of the fixture.
    jq -c 'select(.repo != "otherhub/otherrepo")' "$d/$P_LEDGER" > "$d/ledger.clean" 2>/dev/null && mv "$d/ledger.clean" "$d/$P_LEDGER"
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
  printf '{"repo":"otherhub/otherrepo","number":7}\n' >> "$Mg/$P_LEDGER"
  out_m="$(mem "$Mg" apply 2>&1)"; rc_m=$?
  [ "$rc_m" -eq 0 ] && ok "(m) apply exits 0 on the gated path" || no "(m) apply exited $rc_m on the gated path"
  has '^Memory readiness: gated' "$out_m" && ok "(m) the verdict is the THIRD class 'gated'" || no "(m) the verdict is not 'gated' (got: $(grep '^Memory readiness:' <<< "$out_m" | head -n1))"
  has '^Memory readiness: not configured' "$out_m" && no "(m) a CORRECT refusal reported as 'not configured' — the destructive mis-classification this class exists to prevent" || ok "(m) the refusal is NOT reported as 'not configured'"
  hasi 'comment out the rule named above' "$out_m" && no "(m) THE DESTRUCTIVE UNDER-INCLUSION COPY was printed for a gated repo — it points at this module's own '.supervisor/*' line" || ok "(m) the misleading under-inclusion copy is NOT printed on the gated path"
  hasF 'otherhub/otherrepo' "$out_m" && ok "(m) the gated warning NAMES the offending slug" || no "(m) the gated warning names no slug"
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

# consumer A — the cross-repo write-time check. Echoes its VERDICT ON THE SLUG: 1 = this entry cites
# a repository outside the resolved allowlist, 0 = it does not.
#
# THAT VERDICT IS READ OFF THE REPORT, NOT OFF THE EXIT STATUS, and the difference is the point of
# this helper rather than an implementation detail. cross-repo is now an ADVISORY check: it reports
# on stderr and returns 0 on every path (validate-entry.sh's header records the six measured rounds
# of false refusals that bought that). Its exit status therefore no longer distinguishes anything,
# and a status-based helper here would have returned 0 for every entry and silently turned this
# whole group — the AC5 "one list, two consumers" parity proof — into assertions that can only pass.
# What the group actually needs is unchanged and still observable: whether the ONE resolved list
# moved BOTH consumers. So consumer A's answer is now "did it name this slug as foreign", which is
# the same question the exit status used to answer, asked of the surface that still answers it.
# VALIDATE_ENTRY_SETUP_MEMORY pins the ONE resolver to the script under test, so a stray
# CLAUDE_PLUGIN_ROOT in the developer's environment cannot point this at a different setup-memory.sh.
xrepo() {   # <entry-text> [--root <dir>]
  local e="$1"; shift
  local err; err="$(VALIDATE_ENTRY_SETUP_MEMORY="$MEM" bash "$VE" cross-repo --entry "$e" "$@" 2>&1 >/dev/null)"
  case "$err" in *"ADVISORY_CROSS_REPO"*) echo 1 ;; *) echo 0 ;; esac
}

# xrepo_noenv — the same, with $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST SCRUBBED from the child environment
# so precedence layer 3 is genuinely reached. The scrub lives INSIDE the helper on purpose: `env` can
# only exec an external command, so an `env -u … xrepo …` call site would fail to find the shell
# FUNCTION, yield an EMPTY verdict, and every `[ "$v" = "0" ]` written against it would compare
# against "" — a whole group of assertions that can never pass and never say why.
xrepo_noenv() {   # <entry-text> [--root <dir>]
  local e="$1"; shift
  local err; err="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST VALIDATE_ENTRY_SETUP_MEMORY="$MEM" \
    bash "$VE" cross-repo --entry "$e" "$@" 2>&1 >/dev/null)"
  case "$err" in *"ADVISORY_CROSS_REPO"*) echo 1 ;; *) echo 0 ;; esac
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
  [ "$v_alpha" = "0" ] && ok "(p/L2) consumer A: an entry citing the ALLOWLISTED slug PASSES (verdict 0)" || no "(p/L2) consumer A reported an allowlisted slug as foreign (verdict $v_alpha)"
  [ "$v_beta" = "1" ] && ok "(p/L2) consumer A: an entry citing a slug OUTSIDE the list is REPORTED as foreign (verdict 1)" || no "(p/L2) consumer A verdict on a foreign slug was $v_beta, expected 1"
  out="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/alpha" bash "$MEM" filter-ledger --ledger "$led" 2>/dev/null)"
  n="$(ledger_count "$out")"
  [ "$n" = "1" ] && ok "(p/L2) consumer B: the ledger filter retains 1 of 2 records under the same list" || no "(p/L2) consumer B retained $n records, expected 1"
  ledger_has_repo "$out" "fixture-org/alpha" && ok "(p/L2) consumer B kept the allowlisted record" || no "(p/L2) consumer B dropped the allowlisted record"
  ledger_has_repo "$out" "fixture-org/beta" && no "(p/L2) consumer B leaked the non-allowlisted record" || ok "(p/L2) consumer B excluded the non-allowlisted record"

  # MOVE THE LIST ONCE — both behaviours must move together.
  v_alpha="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/beta" xrepo "$E_ALPHA")"
  v_beta="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/beta" xrepo "$E_BETA")"
  [ "$v_beta" = "0" ] && ok "(p/L2) THE LIST MOVED: consumer A now passes the slug it reported a moment ago" || no "(p/L2) consumer A did not follow the moved list (verdict $v_beta on the newly-allowed slug)"
  [ "$v_alpha" = "1" ] && ok "(p/L2) THE LIST MOVED: consumer A now REPORTS the slug it passed a moment ago" || no "(p/L2) consumer A still passed the now-foreign slug (verdict $v_alpha)"
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
  [ "$v_beta" = "1" ] && ok "(p/L3) consumer A REPORTS a slug absent from the fixture config" || no "(p/L3) consumer A verdict $v_beta on a slug outside the fixture config, expected 1"
  # The sharpest --root assertion: the fixture's OWN REMOTE is refused, so consumer A is reading the
  # config layer and not falling back to a remote (its own, or this checkout's).
  [ "$v_remote" = "1" ] && ok "(p/L3) consumer A REPORTS the fixture's own git-remote slug — proof it read the config layer, not the remote default" || no "(p/L3) consumer A passed the fixture's remote slug (verdict $v_remote) — it is resolving layer 4, not the config"
  out="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$MEM" --root "$d" filter-ledger --ledger "$led" 2>/dev/null)"
  ledger_has_repo "$out" "fixture-org/alpha" && ok "(p/L3) consumer B reads the same config layer and keeps the config-listed record" || no "(p/L3) consumer B did not follow the config layer"
  ledger_has_repo "$out" "fixture-org/beta" && no "(p/L3) consumer B leaked a record outside the config allowlist" || ok "(p/L3) consumer B excludes the record outside the config allowlist"

  # MOVE THE CONFIG LIST ONCE — both behaviours must move together at layer 3 too.
  printf '{"setup_memory":{"repo_allowlist":["fixture-org/beta"]}}\n' > "$d/.supervisor/config.json"
  v_alpha="$(xrepo_noenv "$E_ALPHA" --root "$d")"
  v_beta="$(xrepo_noenv "$E_BETA" --root "$d")"
  [ "$v_beta" = "0" ] && ok "(p/L3) THE CONFIG LIST MOVED: consumer A now passes the slug it reported" || no "(p/L3) consumer A did not follow the moved config list (verdict $v_beta)"
  [ "$v_alpha" = "1" ] && ok "(p/L3) THE CONFIG LIST MOVED: consumer A now REPORTS the slug it passed" || no "(p/L3) consumer A still passed the now-foreign slug (verdict $v_alpha)"
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
  printf '{"schema_version": 1, "repo": "otherhub/otherrepo", "number": 124}\n' >> "$g/$P_LEDGER"
  out_g="$(mem "$g" apply 2>&1)"
  assert_ignored "$g" "$P_LEDGER" "(p/neg) with a FOREIGN record present, apply still WITHHOLDS the ledger negation — the publication gate is intact"
  hasF 'otherhub/otherrepo' "$out_g" && ok "(p/neg) the withholding NAMES the offending slug" || no "(p/neg) the refusal does not name the offending slug"
  assert_committable "$g" "$P_MEM" "(p/neg) and only the ledger is withheld — the memory stores stay applied"
}
one_allowlist_two_consumers

# R0, re-checked mechanically rather than asserted in prose.
if [ "$CFG_LIVE_EXISTED" -eq 1 ]; then
  [ "$(sum "$CFG_LIVE")" = "$CFG_LIVE_SUM_BEFORE" ] && ok "(p) R0: the plugin repo's own .supervisor/config.json is BYTE-IDENTICAL after the group" || no "(p) R0 VIOLATED: THE SUITE MUTATED THE LIVE .supervisor/config.json"
else
  [ ! -f "$CFG_LIVE" ] && ok "(p) R0: the plugin repo had no .supervisor/config.json before the group and still has none" || no "(p) R0 VIOLATED: the suite CREATED a live .supervisor/config.json"
fi
if [ -f "$CFG_LIVE" ] && grep -qE 'otherhub|fixture-org' "$CFG_LIVE" 2>/dev/null; then
  no "(p) R0 VIOLATED: a FOREIGN fixture slug reached the live allowlist — apply would now publish another repo's churn analysis"
else
  ok "(p) R0: no foreign fixture slug (otherhub / fixture-org) is present in the live allowlist"
fi

# ============================================================================
echo "== (t) the judgement TRAIL (v15.84.0): requirements + jobs/done|failed + automate/*.md are committable; in-flight, sidecars and nested .supervisor/ stay ignored =="
# WHY: 2026-09-21 — 144 requirement files, 116 done briefs and every /automate run file existed on
# exactly one laptop, while the repo's stated thesis is a Twin that ACCUMULATES judgement. The
# block gains the trail; this group pins each path both ways and proves the `!` lines are dead
# without the `.supervisor/*` line above them (the same silent-failure class as group (a)).
P_REQ=".supervisor/requirements/queue/01-item.md"
P_REQ_NESTED=".supervisor/requirements/queue/.supervisor/logs/telemetry.log"
P_SUB_NESTED="probes/.supervisor/.rules-nudge-shown"
P_DONE=".supervisor/jobs/done/2026-01-01-brief.md"
P_FAILED=".supervisor/jobs/failed/2026-01-01-brief.md"
P_INPROG=".supervisor/jobs/in-progress/2026-01-01-brief.md"
P_PENDING=".supervisor/jobs/pending/2026-01-01-brief.md"
P_RUN=".supervisor/automate/automate-2026-01-01-000000.md"
P_RUN_SIDECAR=".supervisor/automate/automate-2026-01-01-000000.config-backup.json"
Tt="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Tt"
printf '.supervisor/\n' > "$Tt/.gitignore"
out_t="$(mem "$Tt" apply 2>&1)"; rc_t=$?
[ "$rc_t" -eq 0 ] && ok "(t) apply exits 0" || no "(t) apply non-zero ($rc_t): $out_t"
# INTENDED — one assertion per path.
assert_committable "$Tt" "$P_REQ"    "(t) after apply $P_REQ is committable"
assert_committable "$Tt" ".supervisor/requirements/queue/operator-run/08-item.md" "(t) a requirement in a nested subfolder is committable (directory re-include is recursive)"
assert_committable "$Tt" "$P_DONE"   "(t) after apply $P_DONE is committable"
assert_committable "$Tt" "$P_FAILED" "(t) after apply $P_FAILED is committable"
assert_committable "$Tt" "$P_RUN"    "(t) after apply $P_RUN is committable"
# UNINTENDED — one assertion per path, never a bulk claim.
assert_ignored "$Tt" "$P_INPROG"      "(t) $P_INPROG stays ignored (in-flight state)"
assert_ignored "$Tt" "$P_PENDING"     "(t) $P_PENDING stays ignored (in-flight state)"
assert_ignored "$Tt" "$P_RUN_SIDECAR" "(t) $P_RUN_SIDECAR stays ignored (transient sidecar)"
assert_ignored "$Tt" "$P_REQ_NESTED"  "(t) $P_REQ_NESTED stays ignored (hook junk nested in a requirements folder)"
assert_ignored "$Tt" "$P_SUB_NESTED"  "(t) $P_SUB_NESTED stays ignored (hook junk nested in an arbitrary project subfolder)"
assert_ignored "$Tt" "a/b/.supervisor/logs/x.jsonl" "(t) a .supervisor/ nested two levels below an ordinary folder stays ignored"
# The nested rule must not reach the ROOT store: it stays committable (the reason `*/**/` and not `**/`).
assert_committable "$Tt" ".supervisor/memory/LESSONS.md" "(t) the ROOT store .supervisor/memory/LESSONS.md stays committable under the nested rule"
assert_ignored "$Tt" ".supervisor/state.md" "(t) .supervisor/state.md stays ignored (live run state)"
assert_ignored "$Tt" "$P_LOGS"        "(t) $P_LOGS stays ignored"
# The probes in the script itself must agree with these assertions, or `check` would report a
# configured repo as partial/not-configured.
chk_t="$(mem "$Tt" check 2>/dev/null)"
has '^Memory readiness: configured' "$chk_t" && ok "(t) check verdict = configured with the trail lines in place" || no "(t) check verdict after trail apply: $(grep '^Memory readiness' <<< "$chk_t")"
# Negative control 1: the `!` lines are DEAD without `.supervisor/*` above them.
Tn="$(newgit)"; seed_stores "$Tn"
printf '.supervisor/\n!.supervisor/requirements/\n!.supervisor/jobs/\n.supervisor/jobs/*\n!.supervisor/jobs/done/\n' > "$Tn/.gitignore"
assert_ignored "$Tn" "$P_REQ"  "(t-neg1) bare '.supervisor/' + '!.supervisor/requirements/' STILL ignores $P_REQ — the negation is dead, as the block comment claims"
assert_ignored "$Tn" "$P_DONE" "(t-neg1) same for $P_DONE"
# Negative control 2 (mutant): drop the nested-.supervisor exclude from the block ⇒ the junk
# becomes committable — proving (t)'s nested assertion holds the line, not the seed layout.
Tm="$(mkfix)"; sed '/^\*\/\*\*\/\.supervisor\/$/d' "$MEM" > "$Tm/setup-memory.sh"
if cmp -s "$MEM" "$Tm/setup-memory.sh"; then no "(t-mut) mutant sed changed nothing"; else
  Tx="$(newgit https://github.com/acme/widget.git)"; seed_stores "$Tx"; printf '.supervisor/\n' > "$Tx/.gitignore"
  bash "$Tm/setup-memory.sh" --root "$Tx" apply >/dev/null 2>&1
  if ignored "$Tx" "$P_REQ_NESTED"; then no "(t-mut) mutant without the nested exclude still ignores $P_REQ_NESTED — the assertion is vacuous"; else ok "(t-mut) without the nested exclude line the hook junk WOULD be committed — the line is load-bearing"; fi
  if ignored "$Tx" "$P_SUB_NESTED"; then no "(t-mut) mutant without the nested exclude still ignores $P_SUB_NESTED — the assertion is vacuous"; else ok "(t-mut) without the nested exclude line $P_SUB_NESTED WOULD be committed (the studio exposure)"; fi
fi

echo "== (bm) branch mode: --branch-mode <branch>|off, plain-apply preservation, the one 'mode' reader =="
# Branch mode (skills/automate-loop/SKILL.md §"Branch mode"): the block omits every run-history
# re-include and carries ONE mode line; a plain apply preserves it; `mode` is the only reader.
MLINE='# loomwright-meta-branch: '
Bm="$(newgit https://github.com/acme/widget.git)"; seed_stores "$Bm"; printf 'node_modules/\n.supervisor/\n' > "$Bm/.gitignore"
Bo="$(newgit https://github.com/acme/widget.git)"; seed_stores "$Bo"; printf 'node_modules/\n.supervisor/\n' > "$Bo/.gitignore"
m0="$(mem "$Bm" mode 2>/dev/null)"
[ "$m0" = "off" ] && ok "(bm) mode with no managed block prints 'off'" || no "(bm) mode with no block: '$m0'"
s0="$(sum "$Bm/.gitignore")"
o="$(mem "$Bm" apply --branch-mode 2>/dev/null)"
if has 'requires a value' "$o" && [ "$(sum "$Bm/.gitignore")" = "$s0" ] && [ -z "$(ls "$Bm"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(bm) bare --branch-mode is a usage error and writes nothing"; else no "(bm) bare --branch-mode: $o"; fi
o="$(mem "$Bm" apply --branch-mode 'bad..name' 2>/dev/null)"
if has 'apply: ABORTED — invalid --branch-mode branch name' "$o" && [ "$(sum "$Bm/.gitignore")" = "$s0" ]; then ok "(bm) an invalid branch name (check-ref-format) is refused with nothing written"; else no "(bm) invalid branch name: $o"; fi
o="$(mem "$Bm" check --branch-mode x 2>/dev/null)"
if has 'applies only to' "$o" && [ "$(sum "$Bm/.gitignore")" = "$s0" ]; then ok "(bm) --branch-mode with a non-apply subcommand is refused"; else no "(bm) --branch-mode on check: $o"; fi
o="$(mem "$Bm" apply --branch-mode loomwright-meta 2>/dev/null)"
has '^apply: applied (branch mode: loomwright-meta)' "$o" && ok "(bm) apply --branch-mode X reports the branch-mode write" || no "(bm) apply --branch-mode headline: $(grep '^apply' <<< "$o")"
blk="$(sed -n "/>>> loomwright \/setup memory BEGIN/,/<<< loomwright \/setup memory END/p" "$Bm/.gitignore")"
[ "$(grep -c "^${MLINE}loomwright-meta\$" <<< "$blk")" = 1 ] && ok "(bm) the block carries exactly ONE mode line '${MLINE}loomwright-meta'" || no "(bm) mode line count in block: $(grep -c "^$MLINE" <<< "$blk")"
for l in '!.supervisor/requirements/' '!.supervisor/jobs/' '.supervisor/jobs/*' '!.supervisor/jobs/done/' '!.supervisor/jobs/failed/' '!.supervisor/automate/' '.supervisor/automate/*' '!.supervisor/automate/*.md' '!.supervisor/postmortem/' '.supervisor/postmortem/*' '!.supervisor/postmortem/results.jsonl'; do
  if grep -qxF -- "$l" <<< "$blk"; then no "(bm) branch-mode block still carries run-history line '$l'"; else ok "(bm) branch-mode block omits '$l'"; fi
done
for l in '.claude/*' '!.claude/agent-memory/' '.supervisor/*' '!.supervisor/memory/' '*/**/.supervisor/'; do
  grep -qxF -- "$l" <<< "$blk" && ok "(bm) branch-mode block keeps '$l'" || no "(bm) branch-mode block lost '$l'"
done
grep -q 'judgement TRAIL' <<< "$blk" && no "(bm) branch-mode block still claims the trail is committed" || ok "(bm) branch-mode block drops the 'judgement TRAIL' committed-on-purpose claim"
assert_committable "$Bm" "$P_MEM" "(bm) $P_MEM stays committable in branch mode"
assert_committable "$Bm" "$P_LES" "(bm) $P_LES stays committable in branch mode"
assert_ignored "$Bm" "$P_REQ"  "(bm) $P_REQ is ignored in branch mode (on the metadata branch)"
assert_ignored "$Bm" "$P_DONE" "(bm) $P_DONE is ignored in branch mode"
assert_ignored "$Bm" ".supervisor/automate/automate-2026-01-01-000000.md" "(bm) automate run file is ignored in branch mode"
assert_ignored "$Bm" "$P_LEDGER" "(bm) the ledger is ignored in branch mode"
m1="$(mem "$Bm" mode 2>/dev/null)"
[ "$m1" = "on loomwright-meta" ] && ok "(bm) mode prints 'on loomwright-meta'" || no "(bm) mode after apply: '$m1'"
c1="$(mem "$Bm" check 2>/dev/null)"
has '^Memory readiness: configured' "$c1" && ok "(bm) check reads a branch-mode block as configured (no drift)" || no "(bm) check verdict in branch mode: $(grep '^Memory readiness' <<< "$c1")"
s1="$(sum "$Bm/.gitignore")"
o="$(mem "$Bm" apply 2>/dev/null)"
if [ "$(sum "$Bm/.gitignore")" = "$s1" ] && has '^apply: no-op' "$o"; then ok "(bm) a plain apply PRESERVES the mode line (byte-identical no-op)"; else no "(bm) plain apply rewrote the branch-mode block: $(grep '^apply' <<< "$o")"; fi
mem "$Bm" apply --branch-mode off >/dev/null 2>&1
mem "$Bo" apply >/dev/null 2>&1
if cmp -s "$Bm/.gitignore" "$Bo/.gitignore"; then ok "(bm) apply --branch-mode off restores the default block byte-for-byte"; else no "(bm) --branch-mode off differs from a default apply"; fi
[ "$(mem "$Bm" mode 2>/dev/null)" = "off" ] && ok "(bm) mode prints 'off' after --branch-mode off" || no "(bm) mode after off"
mem "$Bm" apply --branch-mode loomwright-meta >/dev/null 2>&1
mem "$Bm" remove >/dev/null 2>&1
if grep -qF '>>> loomwright /setup memory BEGIN' "$Bm/.gitignore" || grep -qF "$MLINE" "$Bm/.gitignore"; then no "(bm) remove left the block or the mode line"; else ok "(bm) remove deletes the whole block, mode line included"; fi
[ "$(mem "$Bm" mode 2>/dev/null)" = "off" ] && ok "(bm) mode prints 'off' after remove" || no "(bm) mode after remove"
# The three unknown shapes.
Bu="$(newgit)"; printf '.supervisor/\n' > "$Bu/.gitignore"; mem "$Bu" apply --branch-mode loomwright-meta >/dev/null 2>&1
awk -v m="${MLINE}other" '{print} index($0, "# loomwright-meta-branch: ") == 1 {print m}' "$Bu/.gitignore" > "$Bu/g" && mv "$Bu/g" "$Bu/.gitignore"
mu="$(mem "$Bu" mode 2>/dev/null)"
case "$mu" in "unknown "*) ok "(bm) two mode lines ⇒ mode prints 'unknown …' ($mu)" ;; *) no "(bm) two mode lines ⇒ '$mu'" ;; esac
su="$(sum "$Bu/.gitignore")"; o="$(mem "$Bu" apply 2>/dev/null)"
if has '^apply: ABORTED' "$o" && [ "$(sum "$Bu/.gitignore")" = "$su" ]; then ok "(bm) a plain apply on an unknown mode is refused (nothing written)"; else no "(bm) plain apply on unknown mode: $(grep '^apply' <<< "$o")"; fi
Bi="$(newgit)"; printf '.supervisor/\n' > "$Bi/.gitignore"; mem "$Bi" apply --branch-mode loomwright-meta >/dev/null 2>&1
sed 's/^# loomwright-meta-branch: loomwright-meta$/# loomwright-meta-branch: bad..name/' "$Bi/.gitignore" > "$Bi/g" && mv "$Bi/g" "$Bi/.gitignore"
mi="$(mem "$Bi" mode 2>/dev/null)"
case "$mi" in "unknown "*) ok "(bm) an invalid branch in the mode line ⇒ 'unknown …' ($mi)" ;; *) no "(bm) invalid mode-line branch ⇒ '$mi'" ;; esac
Bd="$(newgit)"; printf '.supervisor/\n' > "$Bd/.gitignore"; mem "$Bd" apply --branch-mode loomwright-meta >/dev/null 2>&1
# Via a temp file: GNU grep refuses a file that is both its input and its output (BSD grep allows it).
grep -F '>>> loomwright /setup memory BEGIN' "$Bd/.gitignore" > "$Bd/dup" && cat "$Bd/dup" >> "$Bd/.gitignore" && rm -f "$Bd/dup"
md="$(mem "$Bd" mode 2>/dev/null)"
case "$md" in "unknown unparseable"*) ok "(bm) a sentinel-sanity failure ⇒ 'unknown …' ($md)" ;; *) no "(bm) duplicated sentinel ⇒ '$md'" ;; esac
[ "$(mem "$Bd" mode 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && ok "(bm) mode always prints exactly ONE line" || no "(bm) mode printed more than one line"

echo "== (bm-r) the mode READER decides 'off' from CONTENT, never from the writer's rewrite-safety gate =="
# A repo that NEVER opted in (no mode-line text anywhere) must read `off` even when its .gitignore
# is one apply would refuse to rewrite (read-only, conflict-marked, NUL bytes, not a regular file):
# `unknown` ABORTs /automate entry (meta-entry) and fails trail-pr, so a writer-gate verdict leaking
# into the reader turns every such repo's run into a failure. `unknown` stays for the cases where a
# mode line could exist: an unreadable file, or mode-line text inside a structurally broken file.
bmr_mode() { mem "$1" mode 2>/dev/null; }
Br="$(newgit)"; printf 'node_modules/\n.supervisor/\n' > "$Br/.gitignore"; chmod 444 "$Br/.gitignore"
[ "$(bmr_mode "$Br")" = "off" ] && ok "(bm-r) no mode line + read-only .gitignore ⇒ 'off'" || no "(bm-r) read-only, never opted in ⇒ '$(bmr_mode "$Br")'"
chmod 644 "$Br/.gitignore"
Bc="$(newgit)"; printf 'node_modules/\n<<<<<<< HEAD\na/\n=======\nb/\n>>>>>>> other\n' > "$Bc/.gitignore"
[ "$(bmr_mode "$Bc")" = "off" ] && ok "(bm-r) no mode line + conflict markers ⇒ 'off'" || no "(bm-r) conflict-marked, never opted in ⇒ '$(bmr_mode "$Bc")'"
Bn="$(newgit)"; printf 'node_modules/\nx\000y\n' > "$Bn/.gitignore"
[ "$(bmr_mode "$Bn")" = "off" ] && ok "(bm-r) no mode line + NUL bytes ⇒ 'off'" || no "(bm-r) NUL bytes, never opted in ⇒ '$(bmr_mode "$Bn")'"
Bk="$(newgit)"; mkdir "$Bk/.gitignore"
[ "$(bmr_mode "$Bk")" = "off" ] && ok "(bm-r) .gitignore is a directory (no content) ⇒ 'off'" || no "(bm-r) directory .gitignore ⇒ '$(bmr_mode "$Bk")'"
# Opted in + read-only: writability is irrelevant to a reader — the mode is still readable.
Bro="$(newgit)"; printf '.supervisor/\n' > "$Bro/.gitignore"; mem "$Bro" apply --branch-mode loomwright-meta >/dev/null 2>&1; chmod 444 "$Bro/.gitignore"
[ "$(bmr_mode "$Bro")" = "on loomwright-meta" ] && ok "(bm-r) branch-mode block + read-only .gitignore ⇒ 'on loomwright-meta'" || no "(bm-r) read-only branch-mode ⇒ '$(bmr_mode "$Bro")'"
sro="$(sum "$Bro/.gitignore")"; o="$(mem "$Bro" apply 2>/dev/null)"
if has '^apply: ABORTED' "$o" && [ "$(sum "$Bro/.gitignore")" = "$sro" ]; then ok "(bm-r) the WRITER still refuses a read-only .gitignore (gate unchanged for apply)"; else no "(bm-r) apply on read-only: $(grep '^apply' <<< "$o")"; fi
chmod 644 "$Bro/.gitignore"
# Opted in + structurally broken: a mode line could be one side of a conflict ⇒ stays loud.
Bco="$(newgit)"; printf '.supervisor/\n' > "$Bco/.gitignore"; mem "$Bco" apply --branch-mode loomwright-meta >/dev/null 2>&1
printf '<<<<<<< HEAD\na/\n=======\nb/\n>>>>>>> other\n' >> "$Bco/.gitignore"
case "$(bmr_mode "$Bco")" in "unknown unparseable: .gitignore contains unresolved git conflict markers") ok "(bm-r) mode line + conflict markers ⇒ 'unknown …' (loud)" ;; *) no "(bm-r) mode line + conflict ⇒ '$(bmr_mode "$Bco")'" ;; esac
# Unreadable: a mode line cannot be ruled out, so 'off' would be a claim about content never read.
if [ "$(id -u)" = 0 ]; then
  ok "(bm-r) running as root — the chmod-000 unreadable fixture is skipped (root bypasses mode bits)"
else
  Bur="$(newgit)"; printf 'node_modules/\n' > "$Bur/.gitignore"; chmod 000 "$Bur/.gitignore"
  case "$(bmr_mode "$Bur")" in "unknown .gitignore is not readable"*) ok "(bm-r) unreadable .gitignore ⇒ 'unknown …' (cannot rule a mode line out)" ;; *) no "(bm-r) unreadable ⇒ '$(bmr_mode "$Bur")'" ;; esac
  chmod 644 "$Bur/.gitignore"
fi
# A no-opt-in odd file must leave the plain-apply/check paths exactly as before: apply still aborts on
# the writer gate (conflict markers), nothing written.
sc="$(sum "$Bc/.gitignore")"; o="$(mem "$Bc" apply 2>/dev/null)"
if has '^apply: ABORTED — unparseable: .gitignore contains unresolved git conflict markers' "$o" && [ "$(sum "$Bc/.gitignore")" = "$sc" ]; then ok "(bm-r) apply on a conflict-marked never-opted-in file still aborts on the writer gate"; else no "(bm-r) apply on conflict-marked: $(grep '^apply' <<< "$o")"; fi
# Mutation control: a copy whose read_mode consults the WRITER's gate (the pre-fix shape) MUST turn
# the conflict-marked 'off' assertion red — proves the assertion above is load-bearing.
BMR_MUT="$(mktemp -d)"
sed -e 's/^  grep -qF -- "\$MODE_PREFIX" "\$GI" 2>\/dev\/null || rc=\$?$/  :/' \
    -e 's/gate="\$(gitignore_gate read)"/gate="$(gitignore_gate)"/' "$MEM" > "$BMR_MUT/setup-memory.sh"
if cmp -s "$MEM" "$BMR_MUT/setup-memory.sh"; then
  no "(bm-r) mutation control: the patch changed nothing — control inconclusive"
elif [ "$(bash "$BMR_MUT/setup-memory.sh" --root "$Bc" mode 2>/dev/null)" = "off" ]; then
  no "(bm-r) mutation control REFUTED: a reader on the writer's gate still reads 'off' for a conflict-marked file"
else
  ok "(bm-r) mutation control: a reader on the writer's gate reads '$(bash "$BMR_MUT/setup-memory.sh" --root "$Bc" mode 2>/dev/null)' — the 'off' assertion is load-bearing"
fi
rm -rf "$BMR_MUT"

echo "== (bm-v) branch names: option-shaped / reserved values refused; the accepted set is the INTERSECTION =="
# A name is valid only when it passes `git check-ref-format --branch` UNCHANGED, meta-sync.sh's own
# `git check-ref-format refs/heads/<name>`, and is not option-shaped / HEAD / @ (valid_branch_name).
# The review repro: `apply --branch-mode --root X` swallowed `--root` as the branch and wrote the
# mode line into the CWD repo's .gitignore — it must be a usage error with NOTHING written anywhere.
Bvc="$(newgit)"; printf 'node_modules/\n.supervisor/\n' > "$Bvc/.gitignore"
Bvt="$(newgit)"; printf 'node_modules/\n.supervisor/\n' > "$Bvt/.gitignore"
svc="$(sum "$Bvc/.gitignore")"; svt="$(sum "$Bvt/.gitignore")"
o="$(cd "$Bvc" && bash "$MEM" apply --branch-mode --root "$Bvt" 2>/dev/null)"; rc_v=$?
if has 'requires a value' "$o" && has "option-shaped '--root'" "$o"; then ok "(bm-v) 'apply --branch-mode --root X' is a usage error naming the option-shaped value"; else no "(bm-v) --branch-mode --root X: $o"; fi
[ "$rc_v" -eq 0 ] && ok "(bm-v) the usage error still exits 0 (fail-safe)" || no "(bm-v) --branch-mode --root X exited $rc_v"
if [ "$(sum "$Bvc/.gitignore")" = "$svc" ] && [ -z "$(ls "$Bvc"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(bm-v) nothing written to the CWD repo's .gitignore (the reproduced bug)"; else no "(bm-v) --branch-mode --root X wrote the CWD repo's .gitignore"; fi
if [ "$(sum "$Bvt/.gitignore")" = "$svt" ] && [ -z "$(ls "$Bvt"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(bm-v) nothing written to the target's .gitignore either"; else no "(bm-v) --branch-mode --root X wrote the target's .gitignore"; fi
if grep -qF "$MLINE" "$Bvc/.gitignore" "$Bvt/.gitignore"; then no "(bm-v) a mode line was recorded by --branch-mode --root X"; else ok "(bm-v) no mode line recorded in either repo"; fi
o="$(mem "$Bvt" apply --branch-mode -h 2>/dev/null)"
if has "option-shaped '-h'" "$o" && [ "$(sum "$Bvt/.gitignore")" = "$svt" ]; then ok "(bm-v) '--branch-mode -h' is refused as option-shaped (never prints help, nothing written)"; else no "(bm-v) --branch-mode -h: $o"; fi
for bad in HEAD '@{-1}' '@' 'a..b'; do
  o="$(mem "$Bvt" apply --branch-mode "$bad" 2>/dev/null)"
  if has 'apply: ABORTED — invalid --branch-mode branch name' "$o" && [ "$(sum "$Bvt/.gitignore")" = "$svt" ] && [ -z "$(ls "$Bvt"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(bm-v) '--branch-mode $bad' is refused with nothing written"; else no "(bm-v) --branch-mode $bad: $o"; fi
done
# @{-N} would EXPAND under a cwd-relative --branch (to the previously checked-out branch) — run
# from a repo where it resolves, so the refusal cannot rest on "no previous branch" alone.
( cd "$Bvt" && git checkout -q -b vprev && git checkout -q - ) >/dev/null 2>&1
o="$(cd "$Bvt" && bash "$MEM" --root "$Bvt" apply --branch-mode '@{-1}' 2>/dev/null)"
if has 'apply: ABORTED — invalid --branch-mode branch name' "$o" && [ "$(sum "$Bvt/.gitignore")" = "$svt" ]; then ok "(bm-v) '@{-1}' is refused even where it expands to a real branch"; else no "(bm-v) resolvable @{-1}: $o"; fi
# The verdict never depends on the caller's cwd: from a DELETED cwd (where a cwd-relative
# `git check-ref-format --branch` dies with "Unable to read current working directory") a valid
# recorded mode still reads `on <branch>` and check still reads it as configured.
Bdc="$(newgit)"; printf '.supervisor/\n' > "$Bdc/.gitignore"; mem "$Bdc" apply --branch-mode loomwright-meta >/dev/null 2>&1
DCWD="$(mkfix)"
mdc="$(cd "$DCWD" && rmdir "$DCWD" && bash "$MEM" --root "$Bdc" mode 2>/dev/null)"
[ "$mdc" = "on loomwright-meta" ] && ok "(bm-v) from a deleted cwd a valid mode line still reads 'on loomwright-meta'" || no "(bm-v) deleted cwd ⇒ '$mdc'"
DCWD="$(mkfix)"
cdc="$(cd "$DCWD" && rmdir "$DCWD" && bash "$MEM" --root "$Bdc" check 2>/dev/null)"
has '^Memory readiness: configured' "$cdc" && ok "(bm-v) from a deleted cwd check still reads the branch-mode block as configured" || no "(bm-v) deleted cwd check: $(grep '^Memory readiness' <<< "$cdc")"
# A hand-written option-shaped / reserved mode line reads `unknown` (never `on -x`), and a plain
# apply on it aborts with nothing written.
for hb in '-x' 'HEAD' '--root'; do
  Bh="$(newgit)"; printf '.supervisor/\n' > "$Bh/.gitignore"; mem "$Bh" apply --branch-mode loomwright-meta >/dev/null 2>&1
  awk -v m="${MLINE}${hb}" 'index($0, "# loomwright-meta-branch: ") == 1 { print m; next } { print }' "$Bh/.gitignore" > "$Bh/g" && mv "$Bh/g" "$Bh/.gitignore"
  mh="$(mem "$Bh" mode 2>/dev/null)"
  [ "$mh" = "unknown invalid branch name '$hb' in the mode line" ] && ok "(bm-v) a hand-written '${MLINE}${hb}' line reads '$mh'" || no "(bm-v) mode line '$hb' ⇒ '$mh'"
  sh="$(sum "$Bh/.gitignore")"; o="$(mem "$Bh" apply 2>/dev/null)"
  if has '^apply: ABORTED' "$o" && [ "$(sum "$Bh/.gitignore")" = "$sh" ]; then ok "(bm-v) a plain apply on the '$hb' mode line is refused (nothing written)"; else no "(bm-v) plain apply on '$hb' mode line: $(grep '^apply' <<< "$o")"; fi
done
# A CRLF mode line is never silently stripped: it reads unknown and the reason SHOWS the \r.
Bcr="$(newgit)"; printf '.supervisor/\n' > "$Bcr/.gitignore"; mem "$Bcr" apply --branch-mode loomwright-meta >/dev/null 2>&1
awk 'index($0, "# loomwright-meta-branch: ") == 1 { printf "%s\r\n", $0; next } { print }' "$Bcr/.gitignore" > "$Bcr/g" && mv "$Bcr/g" "$Bcr/.gitignore"
mcr="$(mem "$Bcr" mode 2>/dev/null)"
[ "$mcr" = "unknown invalid branch name 'loomwright-meta\r' in the mode line" ] && ok "(bm-v) a CRLF mode line reads unknown and names the carriage return as a literal '\\r'" || no "(bm-v) CRLF mode line ⇒ '$mcr'"
# Previously-valid realistic names still round-trip: apply → mode on <name> → plain apply no-op.
for good in loomwright-meta meta/run-history feature/x_y-1 off-branch; do
  Bg="$(newgit)"; printf 'node_modules/\n.supervisor/\n' > "$Bg/.gitignore"
  o="$(mem "$Bg" apply --branch-mode "$good" 2>/dev/null)"
  has "^apply: applied (branch mode: $good)" "$o" && ok "(bm-v) '--branch-mode $good' is accepted" || no "(bm-v) --branch-mode $good: $(grep '^apply' <<< "$o")"
  [ "$(mem "$Bg" mode 2>/dev/null)" = "on $good" ] && ok "(bm-v) mode reads 'on $good'" || no "(bm-v) mode after $good: '$(mem "$Bg" mode 2>/dev/null)'"
  sg="$(sum "$Bg/.gitignore")"; o="$(mem "$Bg" apply 2>/dev/null)"
  if [ "$(sum "$Bg/.gitignore")" = "$sg" ] && has '^apply: no-op' "$o"; then ok "(bm-v) a plain apply preserves '$good' (byte-identical no-op)"; else no "(bm-v) plain apply on '$good': $(grep '^apply' <<< "$o")"; fi
done

echo "== (bm-f) the mode answer is FAIL-CLOSED: empty / malformed / unrecognised never reads 'off' =="
# Review (iteration 3): the writer mapped ANY answer that was not `on <b>` to mode off, and the reader
# turned an EMPTY mode value or a near-miss mode line (indented, no space after the colon) into
# `off` — so a plain apply silently rewrote a branch-mode block as the default one (mode line gone,
# run history re-included). Only an exact `off` or a valid `on <b>` may pass; everything else is
# `unknown …`, and a plain apply on `unknown` aborts with nothing written.
bmf_fix() { local d; d="$(newgit)"; printf '.supervisor/\n' > "$d/.gitignore"; mem "$d" apply --branch-mode loomwright-meta >/dev/null 2>&1; printf '%s\n' "$d"; }
bmf_sub() { awk -v m="$2" 'index($0, "# loomwright-meta-branch: ") == 1 { print m; next } { print }' "$1/.gitignore" > "$1/g" && mv "$1/g" "$1/.gitignore"; }
bmf_nbk() { ls "$1"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' '; }
bmf_refused() {  # <script> <repo> <label> — plain apply ABORTs, .gitignore byte-identical, no NEW backup
  local s0 b0 o; s0="$(sum "$2/.gitignore")"; b0="$(bmf_nbk "$2")"; o="$(bash "$1" --root "$2" apply 2>/dev/null)"
  if has '^apply: ABORTED — the managed block' "$o" && [ "$(sum "$2/.gitignore")" = "$s0" ] && [ "$(bmf_nbk "$2")" = "$b0" ]; then ok "(bm-f) $3: a plain apply is refused, .gitignore unchanged, no new backup"; else no "(bm-f) $3: plain apply: $(grep '^apply' <<< "$o")"; fi
}
# (1) EMPTY branch value inside the sentinels.
Bfe="$(bmf_fix)"; bmf_sub "$Bfe" "$MLINE"
mfe="$(mem "$Bfe" mode 2>/dev/null)"
[ "$mfe" = "unknown invalid branch name '' in the mode line" ] && ok "(bm-f) an EMPTY mode-line branch reads '$mfe'" || no "(bm-f) empty mode-line branch ⇒ '$mfe'"
bmf_refused "$MEM" "$Bfe" "empty mode-line branch"
has '^  branch mode:       unknown invalid branch name' "$(mem "$Bfe" check 2>/dev/null)" && ok "(bm-f) check names the unknown mode (never silent)" || no "(bm-f) check on an empty mode-line branch printed no unknown mode line"
# (2) near-miss shapes inside the sentinels: indented, no space after the colon, bare colon.
for nm in "  ${MLINE}loomwright-meta" '# loomwright-meta-branch:loomwright-meta' '# loomwright-meta-branch:'; do
  Bfn="$(bmf_fix)"; bmf_sub "$Bfn" "$nm"
  mfn="$(mem "$Bfn" mode 2>/dev/null)"
  case "$mfn" in "unknown a malformed mode line in the managed block"*) ok "(bm-f) near-miss '$nm' reads 'unknown …'" ;; *) no "(bm-f) near-miss '$nm' ⇒ '$mfn'" ;; esac
  bmf_refused "$MEM" "$Bfn" "near-miss '$nm'"
done
# (3) the never-opted-in invariant holds for mode text OUTSIDE the sentinels, exact or near-miss.
Bfo="$(newgit)"; printf 'node_modules/\n%sx\n# loomwright-meta-branch:y\n  %sz\n' "$MLINE" "$MLINE" > "$Bfo/.gitignore"
[ "$(mem "$Bfo" mode 2>/dev/null)" = "off" ] && ok "(bm-f) mode text only OUTSIDE the sentinels (no block) ⇒ 'off'" || no "(bm-f) outside-only, no block ⇒ '$(mem "$Bfo" mode 2>/dev/null)'"
mem "$Bfo" apply >/dev/null 2>&1
[ "$(mem "$Bfo" mode 2>/dev/null)" = "off" ] && ok "(bm-f) mode text only OUTSIDE a default block ⇒ 'off'" || no "(bm-f) outside-only, default block ⇒ '$(mem "$Bfo" mode 2>/dev/null)'"
sfo="$(sum "$Bfo/.gitignore")"; o="$(mem "$Bfo" apply 2>/dev/null)"
if has '^apply: no-op' "$o" && [ "$(sum "$Bfo/.gitignore")" = "$sfo" ]; then ok "(bm-f) a plain re-apply there is still a byte-identical no-op"; else no "(bm-f) re-apply with outside-only mode text: $(grep '^apply' <<< "$o")"; fi
# (4) a crashed / garbage reader: stub read_mode in a scratch copy (the review's repro).
BMF_D="$(mktemp -d)"
bmf_stub() { awk -v s="$2" '/^resolve_effective_branch$/ { print s } { print }' "$MEM" > "$BMF_D/$1.sh"; }
bmf_stub empty 'read_mode() { return 0; }'
bmf_stub garbage 'read_mode() { echo garbage; }'
bmf_stub onempty 'read_mode() { echo "on "; }'
for st in empty garbage onempty; do
  Bfs="$(bmf_fix)"
  mfs="$(bash "$BMF_D/$st.sh" --root "$Bfs" mode 2>/dev/null)"
  case "$mfs" in "unknown mode reader returned"*) ok "(bm-f) stubbed reader ($st) ⇒ mode prints '$mfs'" ;; *) no "(bm-f) stubbed reader ($st) ⇒ mode '$mfs'" ;; esac
  bmf_refused "$BMF_D/$st.sh" "$Bfs" "stubbed reader ($st)"
done
has '^  branch mode:       unknown mode reader returned' "$(bash "$BMF_D/empty.sh" --root "$Bfs" check 2>/dev/null)" && ok "(bm-f) check with a crashed reader names the unknown mode" || no "(bm-f) check with a crashed reader is silent about the mode"
# Mutation controls — each restores ONE pre-fix shape in a scratch copy and MUST turn the matching
# assertion above red (a copy the patch did not change is reported inconclusive, never green).
bmf_mut() {  # <name> <label> <repo> <expect-mode-not> ; runs plain apply, reports whether it was refused
  local s0 o
  if cmp -s "$MEM" "$BMF_D/$1.sh"; then no "(bm-f) mutation control '$2': the patch changed nothing — inconclusive"; return; fi
  s0="$(sum "$3/.gitignore")"; o="$(bash "$BMF_D/$1.sh" --root "$3" apply 2>/dev/null)"
  if [ "$(sum "$3/.gitignore")" != "$s0" ] && ! has '^apply: ABORTED' "$o"; then ok "(bm-f) mutation control '$2': the pre-fix shape REWRITES the branch-mode block — the assertion is load-bearing"; else no "(bm-f) mutation control '$2' REFUTED: the pre-fix shape still refuses ($(grep '^apply' <<< "$o"))"; fi
}
# (a) the old catch-all: an unrecognised answer resolves to off.
{ awk '/^resolve_effective_branch$/ { print "read_mode() { return 0; }"; print "normalize_mode() { case \"$1\" in \"on \"*|unknown*) printf \"%s\\n\" \"$1\" ;; *) echo off ;; esac; }" } { print }' "$MEM"; } > "$BMF_D/m_catchall.sh"
bmf_mut m_catchall "old catch-all (empty reader ⇒ off)" "$(bmf_fix)"
# (b) the old reader: no per-match marker, so an EMPTY value is empty output ⇒ off.
sed -e 's/print "L" substr(\$0, length(m) + 1); next/print substr($0, length(m) + 1); next/' -e 's/b="\${lines#L}"/b="$lines"/' "$MEM" > "$BMF_D/m_nomarker.sh"
Bfm="$(bmf_fix)"; bmf_sub "$Bfm" "$MLINE"; bmf_mut m_nomarker "no per-match marker (empty value ⇒ off)" "$Bfm"
# (c) the old reader: in-block near-miss lines are not flagged.
grep -v 'inblk && index(\$0, t) > 0 { print "X" }' "$MEM" > "$BMF_D/m_nonearmiss.sh"
Bfm="$(bmf_fix)"; bmf_sub "$Bfm" "  ${MLINE}loomwright-meta"; bmf_mut m_nonearmiss "near-miss not flagged (indented ⇒ off)" "$Bfm"
# (d) the old pre-check: only the exact prefix (with its trailing space) is searched for.
grep -v 'then rc=0; grep -qF -- "\$MODE_TOKEN"' "$MEM" > "$BMF_D/m_prefixonly.sh"
Bfm="$(bmf_fix)"; bmf_sub "$Bfm" '# loomwright-meta-branch:loomwright-meta'; bmf_mut m_prefixonly "prefix-only pre-check (no-space ⇒ off)" "$Bfm"
rm -rf "$BMF_D"
# (5) the reader must not crash in its subshell: a temporary LC_ALL on a command inside a command
# substitution SEGFAULTs Homebrew bash 5.3 on macOS a few percent of the time (dispose_temporary_env
# → setlocale → CoreFoundation after fork), and a crashed reader is now — correctly — `unknown`. So
# read_mode carries no `LC_ALL=` prefix at all; pinned structurally (the crash itself is flaky).
# The same shape is banned repo-wide by scripts/check-locale-prefix.sh (CI gate); this pin is the
# reader's local, stricter form (no LC_ALL= at all, not even through env).
if awk '/^read_mode\(\) \{/ { f = 1 } f && /^}/ { exit } f && !/^[ \t]*#/ && /LC_ALL=/ { bad = 1 } END { exit !bad }' "$MEM"; then no "(bm-f) read_mode carries an LC_ALL= temp-env prefix (crash-prone in a subshell)"; else ok "(bm-f) read_mode carries no LC_ALL= temp-env prefix"; fi
# (6) the realistic round trip is untouched: mode on → plain apply byte-identical no-op → mode on.
Bfr="$(bmf_fix)"; sfr="$(sum "$Bfr/.gitignore")"; o="$(mem "$Bfr" apply 2>/dev/null)"
if has '^apply: no-op' "$o" && [ "$(sum "$Bfr/.gitignore")" = "$sfr" ] && [ "$(mem "$Bfr" mode 2>/dev/null)" = "on loomwright-meta" ]; then ok "(bm-f) a valid branch-mode block still round-trips (plain apply no-op, mode on)"; else no "(bm-f) valid round trip: $(grep '^apply' <<< "$o")"; fi
# (7) a MULTI-LINE reader answer whose first line is a valid `on <b>`: the `on ` arm must apply the
# same one-line rule as the catch-all — exactly ONE `unknown …` line, never `on x`, never two lines.
BML_D="$(mktemp -d)"
awk '/^resolve_effective_branch$/ { print "read_mode() { printf '"'"'on x\\nextra\\n'"'"'; }" } { print }' "$MEM" > "$BML_D/multiline.sh"
Bml="$(bmf_fix)"; mml="$(bash "$BML_D/multiline.sh" --root "$Bml" mode 2>/dev/null)"
[ "$(printf '%s\n' "$mml" | wc -l | tr -d ' ')" = 1 ] && ok "(bm-f) stubbed two-line reader ('on x' + 'extra') ⇒ mode prints exactly ONE line" || no "(bm-f) stubbed two-line reader ⇒ mode printed $(printf '%s\n' "$mml" | wc -l | tr -d ' ') lines: $mml"
case "$mml" in "unknown "*) ok "(bm-f) stubbed two-line reader ⇒ 'unknown …' ($mml)" ;; *) no "(bm-f) stubbed two-line reader ⇒ '$mml' (must be unknown, never on x)" ;; esac
rm -rf "$BML_D"

echo "== (fn) owner fix-now: branch-mode check wording, option-shaped flag values, reserved 'off', scoped reader =="
# (fn-1) BRANCH MODE: `check` reports the ledger honestly and PROBES it in the must-stay-ignored set;
# the disclosure and apply's Next: hint describe the branch-mode block. Seeded with a FOREIGN ledger
# record on purpose: the block never un-ignores the ledger here, so `gated` (and its filter-ledger
# remedy) would describe a write that cannot happen.
fn_unint() { awk '/^  unintended \(must stay ignored\):/ { f = 1; next } /^  tracked today:/ { f = 0 } f' <<< "$1"; }
fn_int()   { awk '/^  intended \(must be committable\):/ { f = 1; next } /^  unintended / { f = 0 } f' <<< "$1"; }
fn_bm_fixture() { local d; d="$(newgit https://github.com/acme/widgets.git)"; printf '.supervisor/\n' > "$d/.gitignore"
  mkdir -p "$d/.supervisor/postmortem"; printf '{"repo":"acme/widgets"}\n{"repo": "other/secret"}\n' > "$d/.supervisor/postmortem/results.jsonl"; printf '%s' "$d"; }
fn_check_assert() {  # <script> <label> — 0 when every branch-mode check expectation holds
  local d o; d="$(fn_bm_fixture)"; bash "$1" --root "$d" apply --branch-mode loomwright-meta >/dev/null 2>&1
  o="$(bash "$1" --root "$d" check 2>/dev/null)"
  hasF '.supervisor/postmortem/results.jsonl                     branch mode — on loomwright-meta, stays ignored here' "$(fn_int "$o")" \
    && hasF '.supervisor/postmortem/results.jsonl                     ignored' "$(fn_unint "$o")" \
    && ! hasF 'not probed (jq unavailable' "$o" && ! hasF 'GATED' "$o" \
    && hasF 'Memory readiness: configured' "$o"
}
if fn_check_assert "$MEM"; then ok "(fn-1) branch-mode check: ledger listed as 'branch mode — on loomwright-meta, stays ignored here', probed 'ignored' in the must-stay-ignored set, readiness configured (never gated / never 'jq unavailable')"; else no "(fn-1) branch-mode check ledger wording/probe"; fi
Bfn="$(fn_bm_fixture)"; oa="$(mem "$Bfn" apply --branch-mode loomwright-meta 2>/dev/null)"; oc="$(mem "$Bfn" check 2>/dev/null)"
for o_lbl in "apply:$oa" "check:$oc"; do
  lbl="${o_lbl%%:*}"; o="${o_lbl#*:}"
  if hasF 'What becomes VERSION-CONTROLLED if you apply this (BRANCH MODE — metadata branch `loomwright-meta`):' "$o" \
     && hasF 'so there is nothing to commit for run history on this branch' "$o" \
     && hasF 'Untracking it is a separate, deliberate operator step (migrate-branch-mode.sh plan), never this' "$o" \
     && ! hasF '.supervisor/requirements/** — the intake' "$o" && ! hasF 'GATED: it is un-ignored only while' "$o"; then
    ok "(fn-1) $lbl prints the BRANCH-MODE disclosure (memory stores only; run history on the metadata branch; untracking starts at migrate-branch-mode.sh plan, not this helper)"
  else no "(fn-1) $lbl disclosure still describes the default block"; fi
done
if hasF '  git status --short .claude/agent-memory .supervisor/memory' "$oa" && ! hasF '.supervisor/memory .supervisor/requirements' "$oa" \
   && hasF "Run history lives on the metadata branch 'loomwright-meta' (meta-sync.sh)," "$oa" \
   && hasF 'not on this branch — there is nothing to commit for it here.' "$oa" && hasF '(migrate-branch-mode.sh plan), never this' "$oa"; then
  ok "(fn-1) apply --branch-mode Next: hint names only the two memory stores and says run history lives on the metadata branch"
else no "(fn-1) apply --branch-mode Next: hint: $(grep -A5 '^Next:' <<< "$oa")"; fi
o="$(mem "$Bfn" apply 2>/dev/null)"
if has '^apply: no-op — already configured (the managed block' "$o" && ! hasF 'GATED' "$o"; then ok "(fn-1) plain re-apply in branch mode with a foreign ledger: plain no-op headline, never 'GATED'"; else no "(fn-1) branch-mode no-op headline: $(grep '^apply' <<< "$o")"; fi
o="$(mem "$Bfn" remove 2>/dev/null)"
! hasF 'not probed (jq unavailable' "$o" && ok "(fn-1) remove from branch mode: the verify report never claims 'jq unavailable' (reads the file it just wrote)" || no "(fn-1) remove from branch mode still reports 'not probed (jq unavailable …)'"
# Mode OFF keeps the default copy (byte identity vs origin/main is proven out-of-band with cmp).
Bfo2="$(newgit https://github.com/acme/widgets.git)"; printf '.supervisor/\n' > "$Bfo2/.gitignore"; o="$(mem "$Bfo2" check 2>/dev/null)"
if has '^What becomes VERSION-CONTROLLED if you apply this:$' "$o" && ! hasF 'branch mode' "$o"; then ok "(fn-1) mode off: default disclosure, no branch-mode wording anywhere in check"; else no "(fn-1) mode off check carries branch-mode wording"; fi
# Mutation self-check: a copy that never records the disk branch makes the (fn-1) check assertion fail.
FN_D="$(mktemp -d)"
sed 's/^      r_branch="\${r_mode#on }"$/      :/' "$MEM" > "$FN_D/mut1.sh"
if cmp -s "$MEM" "$FN_D/mut1.sh"; then no "(fn-1) mutation self-check: the patch changed nothing — inconclusive"
elif fn_check_assert "$FN_D/mut1.sh"; then no "(fn-1) mutation self-check: the branch-mode check assertion is VACUOUS (passes without r_branch)"
else ok "(fn-1) mutation self-check: dropping the disk-branch capture fails the branch-mode check assertion"; fi

# (fn-2) --root / --ledger / --allow: an EMPTY or option-shaped value is a usage error — exit 0,
# stderr names the flag, NOTHING written. --root is run with the cwd inside a fixture so a silent
# fall-back to the cwd repo would show up as a written .gitignore there.
for fv in "--root|-x" "--root|--branch-mode" "--root|" "--ledger|-x" "--ledger|" "--allow|-x" "--allow|--root" "--allow|"; do
  fl="${fv%%|*}"; vv="${fv#*|}"
  Dfv="$(newgit https://github.com/acme/widgets.git)"; printf '.supervisor/\n' > "$Dfv/.gitignore"; s0="$(sum "$Dfv/.gitignore")"
  if [ "$fl" = "--root" ]; then
    err="$(cd "$Dfv" && bash "$MEM" "$fl" "$vv" apply 2>&1 >/dev/null)"; rc=$?
  else
    err="$(bash "$MEM" --root "$Dfv" "$fl" "$vv" apply 2>&1 >/dev/null)"; rc=$?
  fi
  if [ "$rc" = 0 ] && hasF "setup-memory: $fl requires" "$err" && hasF 'Nothing was written.' "$err" \
     && [ "$(sum "$Dfv/.gitignore")" = "$s0" ] && [ -z "$(ls "$Dfv"/.gitignore.backup.* 2>/dev/null)" ] && [ ! -e "$Dfv/.supervisor/config.json" ]; then
    ok "(fn-2) '$fl ${vv:-<empty>}' is a usage error: exit 0, stderr names it, nothing written"
  else no "(fn-2) '$fl ${vv:-<empty>}': rc=$rc err='$err'"; fi
done
err="$(bash "$MEM" --root "$Dfv" filter-ledger --ledger -x 2>&1 >/dev/null)"
hasF "got option-shaped '-x'" "$err" && ok "(fn-2) 'filter-ledger --ledger -x' names the option-shaped value" || no "(fn-2) filter-ledger --ledger -x: $err"
o="$(bash "$MEM" --root "$Dfv" --allow acme/widgets --allow owner/old-name allowlist 2>/dev/null)"
[ "$o" = "acme/widgets
owner/old-name" ] && ok "(fn-2) valid --allow values are unchanged" || no "(fn-2) valid --allow values: '$o'"

# (fn-4) `off` is RESERVED: a hand-written `off` mode line reads unknown (never `on off`, never
# silently `off`), a plain apply refuses it, and `--branch-mode off` is still the switch-off spelling.
Bro="$(bmf_fix)"; bmf_sub "$Bro" "${MLINE}off"
mro="$(mem "$Bro" mode 2>/dev/null)"
[ "$mro" = "unknown invalid branch name 'off' in the mode line" ] && ok "(fn-4) a hand-written 'off' mode line reads '$mro'" || no "(fn-4) 'off' mode line ⇒ '$mro'"
bmf_refused "$MEM" "$Bro" "reserved 'off' mode line"
o="$(mem "$Bro" apply --branch-mode off 2>/dev/null)"
if has '^apply: applied' "$o" && [ "$(mem "$Bro" mode 2>/dev/null)" = "off" ] && ! grep -qF "$MLINE" "$Bro/.gitignore"; then ok "(fn-4) '--branch-mode off' resolves it: mode 'off', no mode line recorded"; else no "(fn-4) --branch-mode off on an 'off' line: $(grep '^apply' <<< "$o")"; fi
Bon="$(bmf_fix)"; o="$(mem "$Bon" apply --branch-mode off 2>/dev/null)"
if has '^apply: applied' "$o" && [ "$(mem "$Bon" mode 2>/dev/null)" = "off" ] && ! grep -qF "$MLINE" "$Bon/.gitignore"; then ok "(fn-4) '--branch-mode off' still switches a branch-mode block off"; else no "(fn-4) --branch-mode off: $(grep '^apply' <<< "$o")"; fi
awk '/^resolve_effective_branch$/ { print "read_mode() { echo \"on off\"; }" } { print }' "$MEM" > "$FN_D/onoff.sh"
mrs="$(bash "$FN_D/onoff.sh" --root "$Bon" mode 2>/dev/null)"
[ "$mrs" = "unknown mode reader returned an invalid branch 'off'" ] && ok "(fn-4) a reader answering 'on off' normalises to '$mrs'" || no "(fn-4) 'on off' reader ⇒ '$mrs'"
hasF 'RESERVED' "$(bash "$MEM" --help 2>/dev/null)" && ok "(fn-4) --help states that 'off' is reserved" || no "(fn-4) --help is silent about the reserved 'off'"
o="$(bash "$MEM" --root "$Bon" apply --branch-mode 2>/dev/null)"
hasF 'or off (reserved — never a branch name)' "$o" && ok "(fn-4) the --branch-mode usage error states 'off' is reserved" || no "(fn-4) --branch-mode usage: $o"
hasF '**`off` is reserved**' "$(cat "$HERE/../commands/setup.md" 2>/dev/null)" && ok "(fn-4) commands/setup.md §Branch mode states 'off' is reserved" || no "(fn-4) commands/setup.md does not state 'off' is reserved"
hasF '`branch mode — on <branch>, stays ignored here`' "$(cat "$HERE/../commands/setup.md" 2>/dev/null)" && ok "(fn-1) commands/setup.md §Branch mode documents the branch-mode ledger line the helper prints" || no "(fn-1) commands/setup.md does not document the branch-mode ledger line"
sed 's/-\*|HEAD|@|off) return 1/-*|HEAD|@) return 1/' "$MEM" > "$FN_D/mut4.sh"
Bro2="$(bmf_fix)"; bmf_sub "$Bro2" "${MLINE}off"
mm="$(bash "$FN_D/mut4.sh" --root "$Bro2" mode 2>/dev/null)"
if cmp -s "$MEM" "$FN_D/mut4.sh"; then no "(fn-4) mutation self-check: the patch changed nothing — inconclusive"
elif [ "$mm" = "on off" ]; then ok "(fn-4) mutation self-check: without the reservation the 'off' line reads 'on off' (the assertion above is load-bearing)"
else no "(fn-4) mutation self-check: unreserved copy ⇒ '$mm'"; fi

# (fn-5) allowlist / filter-ledger never run read_mode: a stub that leaves a marker proves it, and the
# same stub DOES fire for check / mode (positive control). A mutant without the subcommand scope
# fires for allowlist too (the probe is not vacuous).
fn_stub() { awk -v s="read_mode() { echo called >> \"$2\"; echo off; }" '/^resolve_effective_branch$/ { print s } { print }' "$1"; }
Bsc="$(newgit https://github.com/acme/widgets.git)"; printf '.supervisor/\n' > "$Bsc/.gitignore"
mkdir -p "$Bsc/.supervisor/postmortem"; printf '{"repo":"acme/widgets"}\n' > "$Bsc/.supervisor/postmortem/results.jsonl"
fn_stub "$MEM" "$FN_D/mark" > "$FN_D/stub.sh"
for sc in "allowlist" "filter-ledger --ledger $Bsc/.supervisor/postmortem/results.jsonl"; do
  rm -f "$FN_D/mark"
  # shellcheck disable=SC2086
  bash "$FN_D/stub.sh" --root "$Bsc" $sc >/dev/null 2>&1
  [ ! -e "$FN_D/mark" ] && ok "(fn-5) '${sc%% *}' never runs read_mode" || no "(fn-5) '${sc%% *}' ran read_mode $(wc -l < "$FN_D/mark" | tr -d ' ')x"
done
for sc in check mode; do
  rm -f "$FN_D/mark"; bash "$FN_D/stub.sh" --root "$Bsc" "$sc" >/dev/null 2>&1
  [ -s "$FN_D/mark" ] && ok "(fn-5) positive control: '$sc' does run read_mode" || no "(fn-5) positive control: '$sc' never ran read_mode (the probe is blind)"
done
grep -v '^  case "\$SUBCMD" in apply|check|mode) ;; \*) return 0 ;; esac$' "$MEM" > "$FN_D/mut5.sh"
fn_stub "$FN_D/mut5.sh" "$FN_D/mark" > "$FN_D/stub5.sh"; rm -f "$FN_D/mark"; bash "$FN_D/stub5.sh" --root "$Bsc" allowlist >/dev/null 2>&1
if cmp -s "$MEM" "$FN_D/mut5.sh"; then no "(fn-5) mutation self-check: the patch changed nothing — inconclusive"
elif [ -s "$FN_D/mark" ]; then ok "(fn-5) mutation self-check: without the subcommand scope 'allowlist' runs read_mode (the probe is load-bearing)"
else no "(fn-5) mutation self-check: unscoped copy still shows no read_mode for allowlist"; fi
rm -rf "$FN_D"

echo "== (vb) valid-branch <name>: the SAME valid_branch_name predicate apply uses, exit code = answer, writes nothing =="
# A caller (migrate-branch-mode.sh) must vet a branch name BEFORE anything is written; `apply`
# exits 0 on a refusal, so only this predicate's exit code can answer. It must be the one
# predicate `apply --branch-mode` uses (a copy could drift), and it must write nothing.
Vb="$(newgit https://github.com/acme/widgets.git)"; printf 'node_modules/\n.supervisor/\n' > "$Vb/.gitignore"
vb_snap() { (cd "$1" && find . -path ./.git -prune -o -type f -print | env LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done; git status --porcelain; git rev-parse HEAD) 2>/dev/null; }
vb_before="$(vb_snap "$Vb")"
# vb_run <name> — run valid-branch with the fixture as BOTH the cwd and --root; sets VB_RC / VB_ERR / VB_OUT.
vb_run() { VB_ERR="$(cd "$Vb" && bash "$MEM" --root "$Vb" valid-branch "$1" 2>&1 >"$FIXTURE_ROOT/vb.out")"; VB_RC=$?; VB_OUT="$(cat "$FIXTURE_ROOT/vb.out")"; }
for good in loomwright-meta team-meta lane/z; do
  vb_run "$good"
  if [ "$VB_RC" -eq 0 ] && [ -z "$VB_ERR" ] && [ -z "$VB_OUT" ]; then ok "(vb) '$good' is accepted: exit 0, silent"; else no "(vb) '$good' ⇒ rc=$VB_RC err='$VB_ERR' out='$VB_OUT'"; fi
done
for bad in off HEAD @ -x --root 'a..b' '@{-1}' 'bad name' ''; do
  vb_run "$bad"
  nl="$(printf '%s\n' "$VB_ERR" | awk 'END { print NR }')"
  if [ "$VB_RC" -eq 1 ] && [ "$nl" -eq 1 ] && hasF "valid-branch: '$bad' is not a valid metadata branch name" "$VB_ERR" && [ -z "$VB_OUT" ]; then ok "(vb) '$bad' is refused: exit 1, ONE reason line on stderr"; else no "(vb) '$bad' ⇒ rc=$VB_RC lines=$nl err='$VB_ERR' out='$VB_OUT'"; fi
done
VB_ERR="$(bash "$MEM" --root "$Vb" valid-branch 2>&1 >/dev/null)"; VB_RC=$?
[ "$VB_RC" -eq 1 ] && ok "(vb) a missing name is refused (exit 1)" || no "(vb) missing name ⇒ rc=$VB_RC ($VB_ERR)"
VB_ERR="$(bash "$MEM" --root "$Vb" valid-branch loomwright-meta --branch-mode loomwright-meta 2>&1 >/dev/null)"; VB_RC=$?
if [ "$VB_RC" -eq 1 ] && hasF 'valid-branch takes only a name' "$VB_ERR"; then ok "(vb) a flag it could only ignore (--branch-mode) is refused (exit 1)"; else no "(vb) valid-branch + --branch-mode ⇒ rc=$VB_RC ($VB_ERR)"; fi
[ "$(vb_snap "$Vb")" = "$vb_before" ] && ok "(vb) no file changed: every fixture file, git status and HEAD byte-identical" || no "(vb) valid-branch changed the fixture"
if [ ! -e "$Vb/.supervisor/config.json" ] && [ -z "$(ls "$Vb"/.gitignore.backup.* 2>/dev/null)" ]; then ok "(vb) no .supervisor/config.json and no .gitignore.backup.* were created"; else no "(vb) valid-branch left a config or a backup"; fi
# Parity with the writer: for the names apply's predicate judges, valid-branch's verdict equals
# whether `apply --branch-mode <name>` records the mode line (a fresh fixture per name).
for nm in loomwright-meta team-meta HEAD @ 'a..b' '@{-1}'; do
  bash "$MEM" valid-branch "$nm" 2>/dev/null; vrc=$?
  Vp="$(newgit)"; printf '.supervisor/\n' > "$Vp/.gitignore"; mem "$Vp" apply --branch-mode "$nm" >/dev/null 2>&1
  if grep -qxF -e "${MLINE}${nm}" "$Vp/.gitignore"; then arc=0; else arc=1; fi
  if [ "$vrc" -eq "$arc" ]; then ok "(vb) parity: valid-branch '$nm' (rc=$vrc) agrees with apply --branch-mode (mode line recorded: rc=$arc)"; else no "(vb) parity broken for '$nm': valid-branch rc=$vrc, apply recorded rc=$arc"; fi
done
# Same predicate, never a copy: exactly one definition, and a mutant whose valid_branch_name
# refuses everything turns valid-branch's accept red (the subcommand really calls it).
vbdefs="$(grep -c '^valid_branch_name() {$' "$MEM")"
[ "$vbdefs" -eq 1 ] && ok "(vb) setup-memory.sh defines valid_branch_name exactly once" || no "(vb) valid_branch_name is defined $vbdefs times"
VB_D="$(mkfix)"
sed 's/^valid_branch_name() {$/valid_branch_name() { return 1/' "$MEM" > "$VB_D/mut.sh"
bash "$VB_D/mut.sh" valid-branch loomwright-meta >/dev/null 2>&1; mrc=$?
if cmp -s "$MEM" "$VB_D/mut.sh"; then no "(vb) mutation self-check: the patch changed nothing — inconclusive"
elif [ "$mrc" -eq 1 ]; then ok "(vb) mutation self-check: a refuse-all valid_branch_name makes valid-branch refuse 'loomwright-meta' (it calls the one predicate)"
else no "(vb) mutation self-check: a refuse-all predicate still accepted (rc=$mrc) — valid-branch does not call valid_branch_name"; fi
rm -rf "$VB_D"

# ============================================================================
echo "== (am) the agent-memory probe path uses the naming of the stores this repo really tracks =="
# setup-memory.sh probes one agent-memory store for committability. A probe in a naming form the
# host never creates (the old `loomwright:supervisor`) still passes the gitignore probe while
# naming a directory that cannot exist. So the probe is pinned to the form of the stores this repo
# tracks: it must start with the longest common prefix of the tracked store names and carry no ':'.
# The prefix is derived from `git ls-files`, never typed here, so a future rename of the real
# stores moves the expectation with it. A built-in mutant (the colon form) proves the check bites.
AM_REL="$(dirname "$(dirname "$P_MEM")")"   # the agent-memory root, taken from the fixture constant
# store_names: the first path segment under $AM_REL of every line that starts with it (indent allowed).
store_names() {
  awk -v r="$AM_REL/" '{ sub(/^[ \t]+/, "") } index($0, r) == 1 { s = substr($0, length(r) + 1); sub(/\/.*/, "", s); if (s != "") print s }' | sort -u
}
AM_STORES="$(git -C "$PLUGIN_REPO" ls-files -- "$AM_REL" 2>/dev/null | store_names)"
am_n=0; am_prefix=""
while IFS= read -r am_s; do
  [ -n "$am_s" ] || continue
  am_n=$((am_n + 1))
  if [ "$am_n" -eq 1 ]; then am_prefix="$am_s"; continue; fi
  while [ -n "$am_prefix" ] && [ "${am_s#"$am_prefix"}" = "$am_s" ]; do am_prefix="${am_prefix%?}"; done
done <<EOF_AM
$AM_STORES
EOF_AM
[ "$am_n" -ge 2 ] \
  || setup_fail "(am) needs >= 2 tracked $AM_REL/<store>/ dirs in $PLUGIN_REPO to derive the naming prefix (found $am_n)"
[ -n "$am_prefix" ] || setup_fail "(am) the tracked store names share no common prefix — cannot derive the naming form"
case "$am_prefix" in *:*) setup_fail "(am) a tracked store name carries ':' ($am_prefix) — the fixture premise is wrong" ;; esac

# am_probe_names <check-output> → the agent-memory store names the intended-paths list probes.
am_probe_names() { store_names <<< "$1"; }
# am_probe_ok <check-output> → 0 when at least one probe is named and every one has the tracked form.
am_probe_ok() {
  local names n k=0
  names="$(am_probe_names "$1")"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    k=$((k + 1))
    case "$n" in *:*) return 1 ;; esac
    [ "${n#"$am_prefix"}" != "$n" ] || return 1
  done <<EOF_AMP
$names
EOF_AMP
  [ "$k" -ge 1 ]
}

Am="$(newgit)"
seed_stores "$Am"
out_am="$(mem "$Am" check 2>&1)"
am_named="$(am_probe_names "$out_am" | tr '\n' ' ')"
[ -n "$am_named" ] && ok "(am) check lists an agent-memory probe store ($am_named)" \
  || no "(am) check output names no $AM_REL/<store>/ probe path"
if am_probe_ok "$out_am"; then
  ok "(am) the probe store ($am_named) has the tracked form '${am_prefix}<role>' and no ':'"
else
  no "(am) the probe store ($am_named) does not match the tracked store form '${am_prefix}<role>' (or carries ':')"
fi

# Mutation self-check: drop the ':' -> '-' rule (the old colon form) and the same predicate must fail.
AM_D="$(mkfix)"
sed "s/| tr ':' '-')\"; }\$/| cat)\"; }/" "$MEM" > "$AM_D/mut.sh"
out_am_mut="$(bash "$AM_D/mut.sh" --root "$Am" check 2>&1)"
if cmp -s "$MEM" "$AM_D/mut.sh"; then no "(am) mutation self-check: the patch changed nothing — inconclusive"
elif am_probe_ok "$out_am_mut"; then no "(am) mutation self-check: a colon-form probe ($(am_probe_names "$out_am_mut" | tr '\n' ' ')) still passed — the check does not bite"
else ok "(am) mutation self-check: the colon-form probe ($(am_probe_names "$out_am_mut" | tr '\n' ' ')) is rejected"; fi
rm -rf "$AM_D"

echo "== (cs) consent: the ONE user-scope write, keyed by repo, written only by grant / decline =="
CS_HOME="$(mkfix)"
CS_REC="$CS_HOME/.claude/loomwright/meta-sync-consent.json"
cs() { env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "${CS_SUT:-$MEM}" --root "$1" consent "${@:2}" 2>/dev/null; }
# tree_sig <dir> — every file under <dir> with its checksum (the containment witness)
tree_sig() { (cd "$1" && find . -type f -print | env LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }
CSG="$(newgit "https://github.com/Acme/Widget.git")"
[ "$(cs "$CSG" status)" = "none" ] && ok "(cs) no record -> status prints exactly 'none'" || no "(cs) status without a record did not print 'none'"
[ -z "$(tree_sig "$CS_HOME")" ] && ok "(cs) status wrote nothing under HOME" || no "(cs) status wrote under HOME"
csg_repo0="$(tree_sig "$CSG")"
out_cs="$(cs "$CSG" grant)"
hasF "consent: recorded granted for Acme/Widget" "$out_cs" && ok "(cs) grant reports the record keyed by origin's owner/repo" || no "(cs) grant output: $out_cs"
[ "$(tree_sig "$CS_HOME" | cut -d' ' -f1)" = "./.claude/loomwright/meta-sync-consent.json" ] \
  && ok "(cs) grant wrote EXACTLY one file, the user-scope consent record" || no "(cs) grant wrote: $(tree_sig "$CS_HOME" | cut -d' ' -f1 | tr '\n' ' ')"
[ "$(tree_sig "$CSG")" = "$csg_repo0" ] && ok "(cs) grant wrote nothing under the repo" || no "(cs) grant changed the repo tree"
[ "$(jq -r '.repos["Acme/Widget"].learning_stores' "$CS_REC" 2>/dev/null)" = "granted" ] && ok "(cs) the record holds .repos[\"Acme/Widget\"].learning_stores = granted" || no "(cs) record shape wrong: $(cat "$CS_REC" 2>/dev/null)"
[ "$(cs "$CSG" status)" = "granted" ] && ok "(cs) status reads it back as 'granted'" || no "(cs) status after grant"
cs "$CSG" decline >/dev/null
[ "$(cs "$CSG" status)" = "declined" ] && ok "(cs) decline overwrites the decision -> 'declined'" || no "(cs) status after decline"
CSP="$(newgit "$CS_HOME/elsewhere/origin.git")"
cs "$CSP" grant >/dev/null
{ [ "$(cs "$CSP" status)" = "granted" ] && [ "$(jq -r '.repos["Acme/Widget"].learning_stores' "$CS_REC")" = "declined" ] \
  && [ "$(jq -r --arg k "$CS_HOME/elsewhere/origin.git" '.repos[$k].learning_stores' "$CS_REC")" = "granted" ]; } \
  && ok "(cs) a filesystem-path origin keys by the literal URL; the other repo's entry is preserved" || no "(cs) path-origin keying: $(cat "$CS_REC")"
CSN="$(newgit)"
rec0="$(cksum < "$CS_REC")"
[ "$(cs "$CSN" status)" = "none" ] && ok "(cs) no origin -> status 'none'" || no "(cs) no-origin status"
out_csn="$(cs "$CSN" grant)"
{ hasF "NOT recorded" "$out_csn" && [ "$(cksum < "$CS_REC")" = "$rec0" ]; } && ok "(cs) no origin -> grant writes nothing and says why" || no "(cs) no-origin grant: $out_csn"
out_bad="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "$MEM" --root "$CSG" consent bogus 2>&1)"; rc_bad=$?
{ [ "$rc_bad" -eq 0 ] && hasF "Nothing was written" "$out_bad" && [ "$(cksum < "$CS_REC")" = "$rec0" ]; } && ok "(cs) a bad action is a usage line, exit 0, nothing written" || no "(cs) bad action (rc=$rc_bad): $out_bad"
for sub in check mode allowlist; do
  env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "$MEM" --root "$CSG" "$sub" >/dev/null 2>&1
done
[ "$(cksum < "$CS_REC")" = "$rec0" ] && [ "$(tree_sig "$CS_HOME" | wc -l | tr -d ' ')" = "1" ] && ok "(cs) check / mode / allowlist write nothing under HOME" || no "(cs) a read-only subcommand wrote under HOME"
printf '[1, 2]\n' > "$CS_REC"
out_mal="$(cs "$CSG" grant)"
{ hasF "NOT recorded" "$out_mal" && [ "$(cat "$CS_REC")" = "[1, 2]" ]; } && ok "(cs) a malformed record is never clobbered" || no "(cs) malformed record: $out_mal / $(cat "$CS_REC")"
case "$(cs "$CSG" status)" in "unknown "*) ok "(cs) a malformed record reads 'unknown <reason>' (publishes nothing)" ;; *) no "(cs) malformed status: $(cs "$CSG" status)" ;; esac
CSB="$(newgit "https://github.com/Acme/Widget.git")"; printf '# x\n' > "$CSB/.gitignore"
env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "$MEM" --root "$CSB" apply --branch-mode loomwright-meta >/dev/null 2>&1
out_bm="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST HOME="$CS_HOME" bash "$MEM" --root "$CSB" check 2>&1)"
{ hasF ".supervisor/twin/contracts/" "$out_bm" && hasF "setup-memory.sh consent" "$out_bm" && hasi "only pattern-checks" "$out_bm"; } \
  && ok "(cs) the branch-mode disclosure names the learning stores, the consent record and that the scrub only pattern-checks" || no "(cs) branch-mode disclosure lacks the learning-store paragraph"
# mutation control: a writer aimed at the repo root must fail the containment assertion
CS_MUT="$(mkfix)"
sed 's|file="\$HOME/\$CONSENT_FILE_REL"|file="$repo/$CONSENT_FILE_REL"|' "$MEM" > "$CS_MUT/setup-memory.sh"
if cmp -s "$MEM" "$CS_MUT/setup-memory.sh" || ! bash -n "$CS_MUT/setup-memory.sh"; then
  no "(cs) mutation control: the repo-root mutant did not build — inconclusive"
else
  CSM="$(newgit "https://github.com/Acme/Mutant.git")"; csm0="$(tree_sig "$CSM")"; home0="$(tree_sig "$CS_HOME")"
  CS_SUT="$CS_MUT/setup-memory.sh" cs "$CSM" grant >/dev/null
  if [ "$(tree_sig "$CSM")" != "$csm0" ] && [ "$(tree_sig "$CS_HOME")" = "$home0" ]; then
    ok "(cs) mutation control: the repo-root mutant writes under the repo, which the containment assertion rejects"
  else
    no "(cs) mutation control: the mutant did not write under the repo — the containment assertion does not bite"
  fi
fi

echo "== (k) the suite never touched the plugin repo's own .gitignore =="
PLUGIN_GI_SUM_AFTER="$(sum "$PLUGIN_GI")"
[ "$PLUGIN_GI_SUM_BEFORE" = "$PLUGIN_GI_SUM_AFTER" ] && ok "(k) $PLUGIN_GI is byte-identical before and after the whole suite" || no "(k) THE SUITE MUTATED THE PLUGIN REPO'S OWN .gitignore"
[ -z "$(ls "$PLUGIN_REPO"/.gitignore.backup.* 2>/dev/null)" ] && ok "(k) no .gitignore.backup.* left in the plugin repo root" || no "(k) the suite left a .gitignore backup in the plugin repo root"

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
