#!/usr/bin/env bash
# test-check-prompt-history-refs.sh — self-test for scripts/check-prompt-history-refs.sh.
#
# Fully offline, deterministic, macOS bash 3.2 safe. Every case builds its own throwaway git
# fixture tree under a temp dir and drives the gate with --root / --baseline; the real repo is
# only read by the LIVE REPO case. The reference patterns are NOT restated here: the gate's own
# HISTORY_REF_PATTERNS is the one definition, and every case asserts the gate's verdict on
# fixture text. Fixture commits carry their own identity and no signing, so no case depends on
# the developer's git config or on an origin remote.
#
# Cases (by category — assertion counts are intentionally not restated in docs):
#   P.  PATTERNS — one true positive per pattern, the `#NNN` negative guards (entity, anchor,
#       one digit) and the version guard, each counted through --write-baseline
#   A1. a new `#123` in a runtime prompt ⇒ exit 1, file + `path:line: #123` printed
#   A1b BASE-COPY FILTER — only references the base copy lacks are printed; without a base,
#       every reference is printed and labelled
#   A2. `#123` under loomwright/docs/rationale/, loomwright/docs/ (outside command-parts/) and
#       CHANGELOG.md ⇒ exit 0; under loomwright/docs/command-parts/<stem>/ ⇒ exit 1 (scanned)
#   A3. count below its entry ⇒ exit 0 + `lower the baseline`
#   A4. RAISE CHECK — a raised entry, a total rise from a new entry, a move-only
#       redistribution (passes), an unresolvable base (skip; ERROR under require-base), the
#       bootstrap skip (exit 0 even under require-base), a malformed / non-integer base
#       baseline (ERROR), and the default merge-base origin/main base
#   A5. FAIL-CLOSED ERRORS — missing / malformed baseline, non-integer, negative and string
#       entries, a missing entry, an orphan entry, an empty / missing scanned dir, a symlink
#       under a scanned dir, --write-baseline refusing to write on an error, an unknown flag
#   A6. FROZEN EXAMPLE LINES — a sample session_end record, a "plugin_version" key and a
#       sample POSTMORTEM_RESULT line count 0; the same date on a plain line counts 1
#   A7. LIVE REPO — the committed baseline equals the live counts (exit 0, no lower line)
#   A9. CI WIRING — ci.yml fetches a dedicated base ref, sets require-base, runs both scripts

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"
set -uo pipefail
# CI runs this test inside the gate's own step, whose env sets these; every case sets its own.
unset PROMPT_HISTORY_REFS_BASE PROMPT_HISTORY_REFS_REQUIRE_BASE

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
GATE="$repo_root/scripts/check-prompt-history-refs.sh"
[ -f "$GATE" ] || { echo "FAIL: gate not found at $GATE" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq required" >&2; exit 1; }

pass=0
fail=0
check() { # check "name" expected_exit actual_exit
  if [ "$2" -eq "$3" ]; then pass=$((pass+1)); echo "ok   - $1 (exit $3)"; else
    fail=$((fail+1)); echo "FAIL - $1 (expected exit $2, got $3)"; fi
}
contains() { # contains "name" haystack needle
  case "$2" in *"$3"*) pass=$((pass+1)); echo "ok   - $1";; *) fail=$((fail+1)); echo "FAIL - $1 (missing: $3)";; esac
}
lacks() { # lacks "name" haystack needle
  case "$2" in *"$3"*) fail=$((fail+1)); echo "FAIL - $1 (unexpected: $3)";; *) pass=$((pass+1)); echo "ok   - $1";; esac
}
equals() { # equals "name" expected actual
  if [ "$2" = "$3" ]; then pass=$((pass+1)); echo "ok   - $1 ($3)"; else
    fail=$((fail+1)); echo "FAIL - $1 (expected '$2', got '$3')"; fi
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/prompt-history-refs-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

BL_REL="loomwright/docs/prompt-history-refs-baseline.json"

# mk_tree <dir> — a fixture work tree holding one *.md in each scanned dir, plus a rationale
# file; no baseline, not committed.
mk_tree() {
  local d="$1"
  mkdir -p "$d/loomwright/agents" "$d/loomwright/commands" "$d/loomwright/skills/s" \
           "$d/loomwright/docs/command-parts/c" "$d/loomwright/docs/rationale"
  printf '# agent x\nplain prose.\n' > "$d/loomwright/agents/x.md"
  printf '# command c\nplain prose.\n' > "$d/loomwright/commands/c.md"
  printf '# skill s\nplain prose.\n' > "$d/loomwright/skills/s/SKILL.md"
  printf '# part\nplain prose.\n' > "$d/loomwright/docs/command-parts/c/part.md"
  printf '# rationale\nplain prose.\n' > "$d/loomwright/docs/rationale/r.md"
  ( cd "$d" && git -c init.defaultBranch=main init -q . ) >/dev/null 2>&1
}
commit_all() { ( cd "$1" && git add -A && git -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m "$2" ) >/dev/null 2>&1; }
write_bl() { bash "$GATE" --root "$1" --write-baseline >/dev/null 2>&1; }
# set_entry <tree> <path> <json value> — edit one baseline entry in place.
set_entry() {
  jq --arg p "$2" --argjson v "$3" '.files[$p] = $v' "$1/$BL_REL" > "$1/$BL_REL.tmp" && mv "$1/$BL_REL.tmp" "$1/$BL_REL"
}
OUT=""; RC=0
run_gate() { # run_gate <tree> [VAR=value ...] — runs the gate in a clean env plus the given vars
  local t="$1"; shift
  OUT="$(env -u PROMPT_HISTORY_REFS_BASE -u PROMPT_HISTORY_REFS_REQUIRE_BASE "$@" bash "$GATE" --root "$t" 2>&1)"; RC=$?
}
count_of() { # count_of <tree> <path> -> the gate's count for one file
  bash "$GATE" --root "$1" --baseline "$TMP/count.json" --write-baseline >/dev/null 2>&1 || { echo "gate-error"; return; }
  jq -r --arg p "$2" '.files[$p] // "absent"' "$TMP/count.json"
}

# ---------------------------------------------------------------------------------------------
# P — patterns (one true positive each, and the guards)
P="$TMP/p"; mk_tree "$P"
cnt() { printf '%s\n' "$1" > "$P/loomwright/agents/x.md"; count_of "$P" loomwright/agents/x.md; }
equals "P1 #NNN counts"                           1 "$(cnt 'the case seen on #123 stays')"
equals "P1 #NNN at line start counts"             1 "$(cnt '#4567 at the start')"
equals "P2 <queue>/<NN> counts"                   1 "$(cnt 'see automate-speed/26 for it')"
equals "P2 <queue>/<NN> letter suffix counts"     1 "$(cnt 'see harness-port/03b for it')"
equals "P3 YYYY-MM-DD counts"                     1 "$(cnt 'measured on 2026-10-15 here')"
equals "P4 item NN counts (case-insensitive)"     1 "$(cnt 'Item 18 locks it')"
equals "P4 item NN letter suffix counts"          1 "$(cnt 'the item 08a fix')"
equals "P5 vX.Y.Z counts"                         1 "$(cnt 'since v15.10.0 it holds')"
equals "P6 #NNN guard: HTML entity is not counted" 0 "$(cnt 'an entity &#123; here')"
equals "P6 #NNN guard: anchor foo#12 is not counted" 0 "$(cnt 'see foo#12 here')"
equals "P6 #NNN guard: one digit is not counted"  0 "$(cnt 'step #1 only')"
equals "P7 vX.Y.Z guard: after a letter is not counted" 0 "$(cnt 'the xv1.2.3 token')"
equals "P7 vX.Y.Z guard: two parts are not counted" 0 "$(cnt 'version v1.2 only')"
equals "P8 several references on one line each count" 3 "$(cnt 'from #12 via #13 to v1.2.3')"
equals "P9 plain prose counts 0"                  0 "$(cnt 'plain prose with no history')"

# ---------------------------------------------------------------------------------------------
# A1 — a new #123 in a runtime prompt
A="$TMP/a1"; mk_tree "$A"; write_bl "$A"; commit_all "$A" base
A_SHA="$(git -C "$A" rev-parse HEAD)"
printf 'line one\nthe case seen on #123\n' >> "$A/loomwright/agents/x.md"
run_gate "$A" PROMPT_HISTORY_REFS_BASE="$A_SHA"
check    "A1 a new #123 in a runtime prompt exits 1" 1 "$RC"
contains "A1 output names the file" "$OUT" "ABOVE BASELINE: loomwright/agents/x.md"
contains "A1 output prints the #123 line as path:line: token" "$OUT" "loomwright/agents/x.md:4: #123"

# A1b — the base-copy filter
B="$TMP/a1b"; mk_tree "$B"; printf 'an old one #100\n' >> "$B/loomwright/agents/x.md"
write_bl "$B"; commit_all "$B" base
B_SHA="$(git -C "$B" rev-parse HEAD)"
printf 'a new one #123\n' >> "$B/loomwright/agents/x.md"
run_gate "$B" PROMPT_HISTORY_REFS_BASE="$B_SHA"
check    "A1b base resolves: exits 1" 1 "$RC"
contains "A1b the added reference is printed" "$OUT" "loomwright/agents/x.md:4: #123"
lacks    "A1b the reference the base copy already had is not printed" "$OUT" "loomwright/agents/x.md:3: #100"
run_gate "$B" PROMPT_HISTORY_REFS_BASE=refs/does-not-exist
check    "A1b no base: still exits 1" 1 "$RC"
contains "A1b no base: the output says every reference is shown" "$OUT" "base unavailable — showing every reference"
contains "A1b no base: the old reference is printed too" "$OUT" "loomwright/agents/x.md:3: #100"
contains "A1b no base: the new reference is printed" "$OUT" "loomwright/agents/x.md:4: #123"
# a file new since the base: every reference it carries is new
printf 'new prompt #321\n' > "$B/loomwright/agents/y.md"
git -C "$B" checkout -q -- loomwright/agents/x.md
set_entry "$B" loomwright/agents/y.md 0
run_gate "$B" PROMPT_HISTORY_REFS_BASE="$B_SHA"
check    "A1b a new file above its entry exits 1" 1 "$RC"
contains "A1b a new file: says the file is new since the base" "$OUT" "the file is new since"
contains "A1b a new file: its reference is printed" "$OUT" "loomwright/agents/y.md:1: #321"

# ---------------------------------------------------------------------------------------------
# A2 — references outside the scanned set pass; command-parts is scanned
C="$TMP/a2"; mk_tree "$C"; write_bl "$C"; commit_all "$C" base
printf 'the case seen on #123\n' >> "$C/loomwright/docs/rationale/r.md"
run_gate "$C"; check "A2 #123 under loomwright/docs/rationale/ exits 0" 0 "$RC"
git -C "$C" checkout -q -- .
printf 'the case seen on #123\n' > "$C/loomwright/docs/notes.md"
run_gate "$C"; check "A2 #123 under loomwright/docs/ (outside command-parts/) exits 0" 0 "$RC"
rm -f "$C/loomwright/docs/notes.md"
printf 'the case seen on #123\n' > "$C/CHANGELOG.md"
run_gate "$C"; check "A2 #123 in CHANGELOG.md exits 0" 0 "$RC"
rm -f "$C/CHANGELOG.md"
printf 'the case seen on #123\n' >> "$C/loomwright/docs/command-parts/c/part.md"
run_gate "$C"; check "A2 #123 under loomwright/docs/command-parts/<stem>/ exits 1 (scanned)" 1 "$RC"
contains "A2 command-parts: the part is named" "$OUT" "ABOVE BASELINE: loomwright/docs/command-parts/c/part.md"

# ---------------------------------------------------------------------------------------------
# A3 — a count below its entry
D="$TMP/a3"; mk_tree "$D"; printf 'an old one #100\n' >> "$D/loomwright/agents/x.md"
write_bl "$D"; commit_all "$D" base
printf '# agent x\nplain prose.\n' > "$D/loomwright/agents/x.md"
run_gate "$D"
check    "A3 a count below its entry exits 0" 0 "$RC"
contains "A3 prints lower the baseline with the file and new count" "$OUT" "lower the baseline: loomwright/agents/x.md 1 -> 0"

# ---------------------------------------------------------------------------------------------
# A4 — raise check
E="$TMP/a4"; mk_tree "$E"; write_bl "$E"; commit_all "$E" base
E_SHA="$(git -C "$E" rev-parse HEAD)"
printf 'the case seen on #123\n' >> "$E/loomwright/agents/x.md"
set_entry "$E" loomwright/agents/x.md 1
run_gate "$E" PROMPT_HISTORY_REFS_BASE="$E_SHA"
check    "A4 a raised entry exits 1" 1 "$RC"
contains "A4 prints baseline rose for the entry" "$OUT" "baseline rose: loomwright/agents/x.md 0 -> 1"
lacks    "A4 the per-file count itself is within the raised entry" "$OUT" "ABOVE BASELINE"
run_gate "$E" PROMPT_HISTORY_REFS_BASE="$E_SHA" PROMPT_HISTORY_REFS_REQUIRE_BASE=1
check    "A4 a raised entry exits 1 under require-base too" 1 "$RC"

# total rise from a new entry
git -C "$E" checkout -q -- .
printf 'the case seen on #123\n' > "$E/loomwright/agents/y.md"
set_entry "$E" loomwright/agents/y.md 1
run_gate "$E" PROMPT_HISTORY_REFS_BASE="$E_SHA"
check    "A4 a new entry pushing the total above base exits 1" 1 "$RC"
contains "A4 prints baseline total rose" "$OUT" "baseline total rose: 0 -> 1"
lacks    "A4 a new entry is not reported as a raised entry" "$OUT" "baseline rose: loomwright/agents/y.md"
rm -f "$E/loomwright/agents/y.md"; git -C "$E" checkout -q -- .

# move-only redistribution passes
F="$TMP/a4r"; mk_tree "$F"; printf 'an old one #100\n' >> "$F/loomwright/agents/x.md"
write_bl "$F"; commit_all "$F" base
F_SHA="$(git -C "$F" rev-parse HEAD)"
printf '# agent x\nplain prose.\n' > "$F/loomwright/agents/x.md"
printf 'moved here #100\n' > "$F/loomwright/agents/y.md"
set_entry "$F" loomwright/agents/x.md 0
set_entry "$F" loomwright/agents/y.md 1
run_gate "$F" PROMPT_HISTORY_REFS_BASE="$F_SHA" PROMPT_HISTORY_REFS_REQUIRE_BASE=1
check    "A4 a move-only split (total unchanged) exits 0" 0 "$RC"
contains "A4 the raise check executed" "$OUT" "raise_check: executed against $F_SHA"
contains "A4 the raise check reports the unchanged total" "$OUT" "baseline total 1 -> 1"

# unresolvable base
run_gate "$E" PROMPT_HISTORY_REFS_BASE=refs/does-not-exist
check    "A4 an unresolvable base passes" 0 "$RC"
contains "A4 an unresolvable base prints raise_check: skipped" "$OUT" "raise_check: skipped (no base:"
run_gate "$E" PROMPT_HISTORY_REFS_BASE=refs/does-not-exist PROMPT_HISTORY_REFS_REQUIRE_BASE=1
check    "A4 an unresolvable base under require-base exits 1" 1 "$RC"
contains "A4 the require-base ERROR names the variable" "$OUT" "PROMPT_HISTORY_REFS_REQUIRE_BASE=1 demands the raise check run here"
run_gate "$E" PROMPT_HISTORY_REFS_REQUIRE_BASE=1
check    "A4 no origin/main and no override under require-base exits 1" 1 "$RC"
mkdir -p "$TMP/nogit"; cp -R "$E/loomwright" "$TMP/nogit/"
run_gate "$TMP/nogit"
check    "A4 a root outside any git work tree passes" 0 "$RC"
contains "A4 a root outside any git work tree prints the skip" "$OUT" "raise_check: skipped (root is not inside a git work tree)"

# default base: merge-base origin/main HEAD
git -C "$E" update-ref refs/remotes/origin/main "$E_SHA"
run_gate "$E"
check    "A4 the default base (merge-base origin/main HEAD) resolves" 0 "$RC"
contains "A4 the default base is named" "$OUT" "raise_check: executed against merge-base origin/main HEAD"

# bootstrap: the base resolves but has no baseline file
G="$TMP/a4b"; mk_tree "$G"; commit_all "$G" base-without-baseline
G_SHA="$(git -C "$G" rev-parse HEAD)"
write_bl "$G"
run_gate "$G" PROMPT_HISTORY_REFS_BASE="$G_SHA" PROMPT_HISTORY_REFS_REQUIRE_BASE=1
check    "A4 bootstrap (no baseline at base) exits 0 under require-base" 0 "$RC"
contains "A4 bootstrap prints the bootstrap skip" "$OUT" "raise_check: skipped (no baseline at base — bootstrap)"
lacks    "A4 bootstrap is not an ERROR" "$OUT" "ERROR"

# malformed base baseline
H="$TMP/a4m"; mk_tree "$H"; printf '{not json\n' > "$H/$BL_REL"; commit_all "$H" base-malformed
H_SHA="$(git -C "$H" rev-parse HEAD)"
write_bl "$H"
run_gate "$H" PROMPT_HISTORY_REFS_BASE="$H_SHA"
check    "A4 a malformed base baseline exits 1" 1 "$RC"
contains "A4 a malformed base baseline is an ERROR naming the base copy" "$OUT" "the base baseline ($H_SHA:$BL_REL) could not be read as JSON"
I="$TMP/a4n"; mk_tree "$I"; write_bl "$I"; set_entry "$I" loomwright/agents/x.md '"0"'; commit_all "$I" base-string-entry
I_SHA="$(git -C "$I" rev-parse HEAD)"
write_bl "$I"
run_gate "$I" PROMPT_HISTORY_REFS_BASE="$I_SHA"
check    "A4 a non-integer entry in the base baseline exits 1" 1 "$RC"
contains "A4 a non-integer base entry is an ERROR" "$OUT" "the base baseline ($I_SHA:$BL_REL) holds a non-integer or negative entry"

# ---------------------------------------------------------------------------------------------
# A5 — fail-closed errors
J="$TMP/a5"; mk_tree "$J"; write_bl "$J"; commit_all "$J" base
cp "$J/$BL_REL" "$TMP/a5-good.json"
restore_j() { cp "$TMP/a5-good.json" "$J/$BL_REL"; }

printf '{"files": {' > "$J/$BL_REL"
run_gate "$J"; check "A5 a malformed baseline exits 1" 1 "$RC"
contains "A5 a malformed baseline is an ERROR naming the cause" "$OUT" "ERROR: baseline is malformed JSON"
printf '[1, 2]\n' > "$J/$BL_REL"
run_gate "$J"; check "A5 a baseline that is not {files:{}} exits 1" 1 "$RC"
contains "A5 a wrong-shaped baseline is an ERROR" "$OUT" "ERROR: baseline is malformed JSON or not"
restore_j

for v in 1.5 '"3"' -1 null; do
  restore_j; set_entry "$J" loomwright/agents/x.md "$v"
  run_gate "$J"; check "A5 entry value $v exits 1" 1 "$RC"
  contains "A5 entry value $v is an ERROR naming the entry" "$OUT" "ERROR: non-integer or negative baseline entry: loomwright/agents/x.md"
done
restore_j

jq 'del(.files["loomwright/agents/x.md"])' "$TMP/a5-good.json" > "$J/$BL_REL"
run_gate "$J"; check "A5 a scanned file with no entry exits 1" 1 "$RC"
contains "A5 a missing entry is an ERROR naming the file" "$OUT" "ERROR: no baseline entry for scanned file loomwright/agents/x.md"
restore_j

set_entry "$J" loomwright/agents/gone.md 0
run_gate "$J"; check "A5 an orphan entry exits 1" 1 "$RC"
contains "A5 an orphan entry is an ERROR naming it" "$OUT" "ERROR: orphan baseline entry: loomwright/agents/gone.md"
restore_j

rm -f "$J/$BL_REL"
run_gate "$J"; check "A5 a missing baseline exits 1" 1 "$RC"
contains "A5 a missing baseline is an ERROR" "$OUT" "ERROR: baseline file missing"
restore_j

rm -f "$J/loomwright/commands/c.md"
run_gate "$J"; check "A5 an empty scanned dir exits 1" 1 "$RC"
contains "A5 an empty scanned dir is an ERROR naming it" "$OUT" "ERROR: scanned dir has no *.md files: loomwright/commands"
OUTW="$(bash "$GATE" --root "$J" --baseline "$TMP/never.json" --write-baseline 2>&1)"; RCW=$?
check    "A5 --write-baseline refuses to write on an error" 1 "$RCW"
[ ! -f "$TMP/never.json" ]; check "A5 --write-baseline left no file behind" 0 $?
git -C "$J" checkout -q -- .

rm -rf "$J/loomwright/docs/command-parts"
run_gate "$J"; check "A5 a missing scanned dir exits 1" 1 "$RC"
contains "A5 a missing scanned dir is an ERROR naming it" "$OUT" "ERROR: scanned dir missing (or a symlink): loomwright/docs/command-parts"
git -C "$J" checkout -q -- .

ln -s ../commands/c.md "$J/loomwright/agents/link.md"
run_gate "$J"; check "A5 a symlink under a scanned dir exits 1" 1 "$RC"
contains "A5 a symlink is an ERROR" "$OUT" "ERROR: symlink under scanned dir loomwright/agents"
rm -f "$J/loomwright/agents/link.md"

OUT="$(bash "$GATE" --root "$J" --bogus 2>&1)"; RC=$?
check    "A5 an unknown flag exits 1" 1 "$RC"
run_gate "$J"; check "A5 control: the restored fixture exits 0" 0 "$RC"

# ---------------------------------------------------------------------------------------------
# A6 — frozen example lines count 0
K="$TMP/a6"; mk_tree "$K"
x="$K/loomwright/agents/x.md"
printf '%s\n' '{"ts":"2026-03-09T14:34:00Z","event":"session_end","type":"session_end","plugin_version":"14.24.0"}' > "$x"
equals "A6 a sample session_end record counts 0" 0 "$(count_of "$K" loomwright/agents/x.md)"
printf '%s\n' '{"ts": "2026-03-09T14:34:00Z", "event" : "session_end"}' > "$x"
equals "A6 a session_end record with spacing counts 0" 0 "$(count_of "$K" loomwright/agents/x.md)"
printf '%s\n' '  "plugin_version": "14.24.0",' > "$x"
equals "A6 a \"plugin_version\" line counts 0" 0 "$(count_of "$K" loomwright/agents/x.md)"
printf '%s\n' '{"schema_version":1,"ts":"2026-06-10T12:00:00Z","review_rounds":4,"pr_url":"https://github.com/o/r/pull/43"}' > "$x"
equals "A6 a sample POSTMORTEM_RESULT record counts 0" 0 "$(count_of "$K" loomwright/agents/x.md)"
printf '%s\n' 'it was measured on 2026-03-09 by hand' > "$x"
equals "A6 control: the same date on a plain line counts 1" 1 "$(count_of "$K" loomwright/agents/x.md)"

# ---------------------------------------------------------------------------------------------
# A7 — live repo: the committed baseline equals the live counts
OUT="$(env -u PROMPT_HISTORY_REFS_BASE -u PROMPT_HISTORY_REFS_REQUIRE_BASE bash "$GATE" 2>&1)"; RC=$?
check "A7 the live repo passes" 0 "$RC"
lacks "A7 the live repo prints no lower-the-baseline line" "$OUT" "lower the baseline"

# ---------------------------------------------------------------------------------------------
# A9 — ci.yml wiring (ci-local.sh derives its gates from these lines)
CI="$repo_root/.github/workflows/ci.yml"
step="$(awk '/- name: Check prompt history references/ { on = 1; print; next } on && /^      - name:/ { exit } on { print }' "$CI")"
contains "A9 ci.yml has the history-reference step" "$step" "- name: Check prompt history references"
contains "A9 the step fetches main into a dedicated ref" "$step" "git fetch --no-tags --depth=1 origin +refs/heads/main:refs/prompt-history-refs/base"
contains "A9 the step points the base at that ref" "$step" "PROMPT_HISTORY_REFS_BASE: refs/prompt-history-refs/base"
contains "A9 the step sets require-base" "$step" 'PROMPT_HISTORY_REFS_REQUIRE_BASE: "1"'
contains "A9 the step runs the self-test" "$step" "bash scripts/test-check-prompt-history-refs.sh"
contains "A9 the step runs the gate" "$step" "bash scripts/check-prompt-history-refs.sh"
lacks    "A9 the step carries no || true" "$step" "|| true"

echo "---------------------------------------------------------------------------"
echo "test-check-prompt-history-refs: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
