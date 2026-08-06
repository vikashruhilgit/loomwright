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
#   (c)  dotfile sidecars (.provenance.jsonl / .lessons-provenance.jsonl) commit — asserted
#        explicitly and separately from the `**` globs
#   (d)  allowlist: stored as a JSON ARRAY (never a string); a renamed repo retains records under
#        BOTH slugs; a foreign-repo record is excluded; a fresh install defaults to the remote
#   (e)  idempotency: a second apply is a no-op that writes nothing (.gitignore AND config
#        byte-identical, no second backup)
#   (f)  absent / unparseable .gitignore: change nothing, say why, no partial write, no backup
#   (g)  remove: block gone, byte-exact round-trip, and the output states plainly that git history
#        retains anything already pushed + that already-tracked files need `git rm --cached`
#   (h)  the consent disclosure (what becomes version-controlled) is printed BEFORE applying
#   (i)  write containment: only .gitignore(+backup) and .supervisor/config.json; `check` writes
#        nothing; no commit/index/HEAD is ever touched; only read-only git subcommands are used
#   (j)  fail-safe: every subcommand exits 0, including on a non-git root and a bad flag
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

# ============================================================================
echo "== (e) idempotency — a second apply is a no-op that writes NOTHING =="
Ee="$(newgit https://github.com/acme/widget.git)"
printf '# junk\n.claude/\n.supervisor/\n' > "$Ee/.gitignore"
mem "$Ee" apply >/dev/null 2>&1
gi1="$(sum "$Ee/.gitignore")"
cfg1="$(sum "$Ee/.supervisor/config.json" 2>/dev/null || echo none)"
bk1="$(ls "$Ee"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' ')"
out_e="$(mem "$Ee" apply 2>&1)"; rc_e=$?
gi2="$(sum "$Ee/.gitignore")"
cfg2="$(sum "$Ee/.supervisor/config.json" 2>/dev/null || echo none)"
bk2="$(ls "$Ee"/.gitignore.backup.* 2>/dev/null | wc -l | tr -d ' ')"
[ "$rc_e" -eq 0 ] && ok "(e) second apply exits 0" || no "(e) second apply non-zero ($rc_e)"
hasi 'already configured' "$out_e" && ok "(e) second apply reports 'already configured'" || no "(e) second apply did not report 'already configured'"
[ "$gi1" = "$gi2" ] && ok "(e) .gitignore byte-identical after the second apply (nothing written)" || no "(e) second apply MUTATED .gitignore"
[ "$cfg1" = "$cfg2" ] && ok "(e) .supervisor/config.json byte-identical after the second apply" || no "(e) second apply MUTATED the config"
[ "$bk1" = "$bk2" ] && ok "(e) no second backup file created by the no-op apply ($bk2 total)" || no "(e) the no-op apply still wrote a backup ($bk1 → $bk2)"
c1="$(mem "$Ee" check 2>/dev/null)"; c2="$(mem "$Ee" check 2>/dev/null)"
[ "$c1" = "$c2" ] && ok "(e) check stdout byte-identical across two runs" || no "(e) check stdout differed between runs"

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
bash "$MEM" --help >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "(j) --help exits 0" || no "(j) --help exits $rc"
# check on a non-git root must degrade to 'unknown', never crash or claim a status it did not probe
chk_j="$(mem "$Jj" check 2>/dev/null)"
has 'unknown' "$chk_j" && ok "(j) a non-git root reports ignore status as 'unknown' (never an unprobed claim)" || no "(j) non-git root did not report 'unknown'"
has '^  .gitignore:        absent' "$chk_j" && ok "(j) a missing .gitignore is reported as 'absent'" || no "(j) missing .gitignore not reported as absent"

# ============================================================================
echo "== (k) the suite never touched the plugin repo's own .gitignore =="
PLUGIN_GI_SUM_AFTER="$(sum "$PLUGIN_GI")"
[ "$PLUGIN_GI_SUM_BEFORE" = "$PLUGIN_GI_SUM_AFTER" ] && ok "(k) $PLUGIN_GI is byte-identical before and after the whole suite" || no "(k) THE SUITE MUTATED THE PLUGIN REPO'S OWN .gitignore"
[ -z "$(ls "$PLUGIN_REPO"/.gitignore.backup.* 2>/dev/null)" ] && ok "(k) no .gitignore.backup.* left in the plugin repo root" || no "(k) the suite left a .gitignore backup in the plugin repo root"

# ============================================================================
echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
