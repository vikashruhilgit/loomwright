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

# MEMB — setup-memory.sh as ONE file: the entry point's own _sm_bundle expansion (each
# setup-memory.d/ module inlined at its source line, automate-speed/20). Every TEXT read of the
# script in the parts below — a sed/awk/grep mutant source, its cmp -s gate, a static scan —
# reads MEMB, so it still finds the moved code and a mutant written from it is self-contained;
# every RUN still runs the real entry point $MEM. Named setup-memory.sh so a basename in a leg
# label is unchanged. Fails the whole suite if the bundle cannot be built (not attempted when $MEM
# is absent — group 0 reports that).
mkdir -p "$FIXTURE_ROOT/bundle"; MEMB="$FIXTURE_ROOT/bundle/setup-memory.sh"
if [ -f "$MEM" ]; then
  eval "$(awk '/^_sm_bundle\(\) \{$/,/^}$/' "$MEM")"
  _sm_bundle "$MEM" > "$MEMB" && [ -s "$MEMB" ] || { echo "  FAIL: could not build the setup-memory.sh bundle"; exit 1; }
fi

# ---- legs: test-setup-memory.d/<part>.sh (automate-speed/20) ------------------
# Groups 0 through (cs) moved verbatim, in base order, into test-setup-memory.d/ (their text reads
# of the script now read $MEMB, nothing else changed). Each part is sourced BY NAME (never a glob)
# at top level, so it shares this file's setup, fixtures, helpers and counters; a missing or
# unreadable part aborts the suite (exit 1, the part named) instead of silently dropping its legs.
# Group (k) stays here, after the parts: it re-checks the snapshot the setup above took.
TSM_D="$HERE/test-setup-memory.d"
tsm_part() { [ -f "$TSM_D/$1.sh" ] && [ -r "$TSM_D/$1.sh" ] || { echo "  FAIL: missing test part: test-setup-memory.d/$1.sh"; exit 1; }; }
tsm_part 01-gitignore-paths;           . "$TSM_D/01-gitignore-paths.sh"
tsm_part 02-meta-allowlist;            . "$TSM_D/02-meta-allowlist.sh"
tsm_part 03-apply-safety-ledger-gate;  . "$TSM_D/03-apply-safety-ledger-gate.sh"
tsm_part 04-verdicts-trail;            . "$TSM_D/04-verdicts-trail.sh"
tsm_part 05-branch-mode-consent;       . "$TSM_D/05-branch-mode-consent.sh"

echo "== (k) the suite never touched the plugin repo's own .gitignore =="
PLUGIN_GI_SUM_AFTER="$(sum "$PLUGIN_GI")"
[ "$PLUGIN_GI_SUM_BEFORE" = "$PLUGIN_GI_SUM_AFTER" ] && ok "(k) $PLUGIN_GI is byte-identical before and after the whole suite" || no "(k) THE SUITE MUTATED THE PLUGIN REPO'S OWN .gitignore"
[ -z "$(ls "$PLUGIN_REPO"/.gitignore.backup.* 2>/dev/null)" ] && ok "(k) no .gitignore.backup.* left in the plugin repo root" || no "(k) the suite left a .gitignore backup in the plugin repo root"

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
