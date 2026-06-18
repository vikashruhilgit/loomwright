#!/usr/bin/env bash
# test-read-postmortem.sh — self-tests for the fail-safe ADVISORY churn-ledger reader.
# (New file — Learning Loop Phase 4 churn-ledger read side; mirrors test-read-lessons.sh.)
# Runs in isolated temp git repos (never touches the real .supervisor/postmortem).
# Exit 0 = all pass, 1 = any failure.
#
# Covers:
#   1. query path overlapping a churn entry → output names recurring class / flow_stage
#   2. query path with NO overlap → no actionable churn (empty-state line, no false hit)
#   3. empty/absent corpus → exit 0, quiet
#   4. OLD line without changed_paths present in corpus → skipped silently, no error
#   5. jq masked off PATH → exit 0, quiet (missing-tool fail-safe)
#   6. exit code is 0 in every case (asserted inline per case)
#   + stdin path source, self_heal_miss surfacing, malformed line tolerance, advisory banner.
#   + repo scoping: when CUR_REPO resolves from a remote, only same-repo entries contribute
#     (a same-path entry from another repo must NOT produce a false cross-repo churn hit).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
READ="$HERE/read-postmortem.sh"
CORPUS=".supervisor/postmortem/results.jsonl"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

newrepo() { local d; d="$(mktemp -d)"; ( cd "$d" && git init -q && git config user.email t@t && git config user.name t && echo i>f && git add f && git commit -qm i ); printf '%s' "$d"; }

# Build a fixture corpus into $1/.supervisor/postmortem/results.jsonl.
# Lines:
#  - guard.ts churned twice (validation-parity / falsy-coercion), one self_heal_miss=true
#  - app.ts churned once (count-drift, worker stage)
#  - an OLD line with NO changed_paths (must be tolerated, contributes nothing)
#  - a line touching only unrelated.ts
write_fixture() {
  local repo="$1"; mkdir -p "$repo/.supervisor/postmortem"
  {
    jq -cn '{schema_version:1, number:1, repo:"o/r", branch:"b1", pr_url:"u1",
             changed_paths:["src/auth/guard.ts","src/shared/util.ts"],
             categories:[{round:1,class:"validation-parity",self_heal_miss:true,flow_stage:"self_heal",evidence:"x"}],
             self_heal_misses:1, flow_stages:{self_heal:1}, summary:"s1"}'
    jq -cn '{schema_version:1, number:2, repo:"o/r", branch:"b2", pr_url:"u2",
             changed_paths:["src/auth/guard.ts"],
             categories:[{round:1,class:"falsy-coercion",self_heal_miss:false,flow_stage:"worker",evidence:"y"}],
             self_heal_misses:0, flow_stages:{worker:1}, summary:"s2"}'
    jq -cn '{schema_version:1, number:3, repo:"o/r", branch:"b3", pr_url:"u3",
             changed_paths:["src/app.ts"],
             categories:[{round:1,class:"count-drift",self_heal_miss:false,flow_stage:"worker",evidence:"z"}],
             self_heal_misses:0, flow_stages:{worker:1}, summary:"s3"}'
    # OLD line: NO changed_paths field at all.
    jq -cn '{schema_version:1, number:4, repo:"o/r", branch:"b4", pr_url:"u4",
             categories:[{round:1,class:"legacy-class",self_heal_miss:false,flow_stage:"launch_pad",evidence:"old"}],
             self_heal_misses:0, flow_stages:{launch_pad:1}, summary:"s4-old"}'
    # Unrelated path only.
    jq -cn '{schema_version:1, number:5, repo:"o/r", branch:"b5", pr_url:"u5",
             changed_paths:["src/unrelated.ts"],
             categories:[{round:1,class:"other",self_heal_miss:false,flow_stage:"worker",evidence:"q"}],
             self_heal_misses:0, flow_stages:{worker:1}, summary:"s5"}'
    # Single-entry, EMPTY-categories line: matches src/lonely.ts in exactly ONE corpus entry,
    # and carries categories:[] so classes/stages have nothing to aggregate. Exercises BOTH the
    # singular "entry" pluralization (ENTRIES=1) and the "(none recorded)" classes/stages fallback.
    jq -cn '{schema_version:1, number:6, repo:"o/r", branch:"b6", pr_url:"u6",
             changed_paths:["src/lonely.ts"],
             categories:[],
             self_heal_misses:0, flow_stages:{}, summary:"s6"}'
  } > "$repo/$CORPUS"
}

echo "== 1. query path overlapping a churn entry =="
TMP="$(newrepo)"; write_fixture "$TMP"
out="$( cd "$TMP" && bash "$READ" "src/auth/guard.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 on hit" || no "non-zero exit on hit ($rc)"
echo "$out" | grep -q "subordinate to CLAUDE.md" && ok "advisory banner present" || no "advisory banner missing"
echo "$out" | grep -q "src/auth/guard.ts" && ok "names the churned path" || no "churned path not named"
echo "$out" | grep -q "validation-parity" && ok "surfaces recurring class validation-parity" || no "class validation-parity missing"
echo "$out" | grep -q "falsy-coercion" && ok "surfaces recurring class falsy-coercion" || no "class falsy-coercion missing"
echo "$out" | grep -qE "flow stages:.*(self_heal|worker)" && ok "surfaces flow_stage(s)" || no "flow_stage missing"
echo "$out" | grep -qi "self_heal_miss in prior rounds: yes" && ok "surfaces self_heal_miss=yes" || no "self_heal_miss not surfaced"
# guard.ts appears in entries 1 and 2 → ROUNDS should be 2, ENTRIES 2.
echo "$out" | grep -qE "prior churn rounds: 2" && ok "round count = 2 for guard.ts" || no "round count wrong"
rm -rf "$TMP"

echo "== 2. query path with NO overlap =="
TMP="$(newrepo)"; write_fixture "$TMP"
out="$( cd "$TMP" && bash "$READ" "src/never/touched.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 on no-overlap" || no "non-zero exit on no-overlap ($rc)"
echo "$out" | grep -q "no prior churn recorded for the touched paths" && ok "empty-state line emitted" || no "empty-state line missing"
echo "$out" | grep -q "validation-parity" && no "false hit: unrelated class leaked" || ok "no false hit"
rm -rf "$TMP"

echo "== 3. empty/absent corpus → exit 0, quiet =="
TMP="$(newrepo)"   # no fixture written → corpus absent
out="$( cd "$TMP" && bash "$READ" "src/auth/guard.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with absent corpus" || no "non-zero exit absent corpus ($rc)"
[ -z "$out" ] && ok "quiet (no output) with absent corpus" || no "produced output with absent corpus"
# Now an EMPTY corpus file.
mkdir -p "$TMP/.supervisor/postmortem"; : > "$TMP/$CORPUS"
out2="$( cd "$TMP" && bash "$READ" "src/auth/guard.ts" 2>/dev/null )"; rc2=$?
[ "$rc2" -eq 0 ] && ok "exit 0 with empty corpus" || no "non-zero exit empty corpus ($rc2)"
[ -z "$out2" ] && ok "quiet (no output) with empty corpus" || no "produced output with empty corpus"
rm -rf "$TMP"

echo "== 4. OLD line without changed_paths tolerated (skipped silently) =="
TMP="$(newrepo)"; write_fixture "$TMP"
# Query the OLD line's class path-agnostically: it has NO changed_paths, so it must NOT hit
# for ANY path. Confirm querying app.ts (a real hit) does NOT surface the OLD line's class.
out="$( cd "$TMP" && bash "$READ" "src/app.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with OLD line in corpus" || no "non-zero exit with OLD line ($rc)"
echo "$out" | grep -q "count-drift" && ok "real hit (app.ts → count-drift) still surfaced" || no "real hit lost"
echo "$out" | grep -q "legacy-class" && no "OLD no-changed_paths line wrongly contributed" || ok "OLD line skipped silently (no contribution)"
rm -rf "$TMP"

echo "== 4b. malformed JSONL line tolerated (skipped element-locally) =="
TMP="$(newrepo)"; write_fixture "$TMP"
printf '%s\n' 'this is { not json at all' >> "$TMP/$CORPUS"
printf '%s\n' '' >> "$TMP/$CORPUS"   # blank line too
out="$( cd "$TMP" && bash "$READ" "src/auth/guard.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 despite malformed/blank lines" || no "non-zero exit with malformed lines ($rc)"
echo "$out" | grep -q "validation-parity" && ok "valid lines still parsed past malformed line" || no "malformed line aborted parse"
rm -rf "$TMP"

echo "== 4c. stdin read ONLY when no args (args take precedence — no-hang contract) =="
TMP="$(newrepo)"; write_fixture "$TMP"
# (a) No args: newline-separated paths piped on stdin are used.
out="$( cd "$TMP" && printf '%s\n' "src/auth/guard.ts" | bash "$READ" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 reading paths from stdin (no args)" || no "non-zero exit stdin ($rc)"
echo "$out" | grep -q "src/auth/guard.ts" && ok "no-args: stdin path matched" || no "no-args: stdin path not matched"
# (b) Args present: stdin is IGNORED entirely. This is the regression guard for the
#     blocks-on-stdin hang — an args-bearing call must NEVER consume stdin (a path supplied
#     only via stdin must not influence the result when an arg is given), so it can never
#     hang waiting on an open-but-idle stdin in a non-TTY caller (CI / hook / inline Bash).
out2="$( cd "$TMP" && printf '%s\n' "src/auth/guard.ts" | bash "$READ" "src/app.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with args + piped stdin" || no "non-zero exit args+stdin ($rc)"
echo "$out2" | grep -q "src/app.ts" && ok "args-present: arg path matched" || no "args-present: arg path not matched"
echo "$out2" | grep -q "src/auth/guard.ts" && no "args-present: stdin path leaked (stdin NOT ignored — hang risk)" || ok "args-present: stdin ignored (no-hang contract holds)"
rm -rf "$TMP"

echo "== 4d. no paths at all → exit 0, quiet =="
TMP="$(newrepo)"; write_fixture "$TMP"
out="$( cd "$TMP" && bash "$READ" </dev/null 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with no paths" || no "non-zero exit no paths ($rc)"
[ -z "$out" ] && ok "quiet with no paths" || no "produced output with no paths"
rm -rf "$TMP"

echo "== 4e. single empty-categories hit → singular \"entry\" + \"(none recorded)\" fallback =="
TMP="$(newrepo)"; write_fixture "$TMP"
# src/lonely.ts matches exactly ONE corpus entry whose categories:[] is empty.
#  - ENTRIES=1 → the pluralization branch must render the SINGULAR word "entry" (not "entries").
#  - empty categories → classes AND stages have nothing to aggregate → "(none recorded)" fallback.
out="$( cd "$TMP" && bash "$READ" "src/lonely.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 on single empty-categories hit" || no "non-zero exit single-empty hit ($rc)"
echo "$out" | grep -q "src/lonely.ts" && ok "names the lonely churned path" || no "lonely path not named"
echo "$out" | grep -qE "1 postmortem entry\b" && ok "singular \"entry\" pluralization (ENTRIES=1)" || no "singular \"entry\" not rendered"
echo "$out" | grep -qE "1 postmortem entries" && no "rendered plural \"entries\" for a single entry" || ok "did not render plural for a single entry"
echo "$out" | grep -q "recurring root-cause classes: (none recorded)" && ok "(none recorded) fallback for classes" || no "(none recorded) classes fallback missing"
echo "$out" | grep -q "recurring flow stages: (none recorded)" && ok "(none recorded) fallback for stages" || no "(none recorded) stages fallback missing"
rm -rf "$TMP"

echo "== 4f. repo scoping: same-path entry from ANOTHER repo must NOT contribute =="
# newrepo() creates a repo with NO remote, so CUR_REPO is empty there and all the cases above
# stay fail-open (unscoped). For THIS case we set origin=https://github.com/o/r.git so
# CUR_REPO resolves to "o/r" — matching the fixtures' repo:"o/r".
TMP="$(newrepo)"; write_fixture "$TMP"
( cd "$TMP" && git remote add origin https://github.com/o/r.git )
# (a) With origin=o/r, a query path overlapping an o/r entry STILL hits (scoping keeps own repo).
out="$( cd "$TMP" && bash "$READ" "src/auth/guard.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with resolved CUR_REPO" || no "non-zero exit with resolved CUR_REPO ($rc)"
echo "$out" | grep -q "src/auth/guard.ts" && ok "own-repo (o/r) hit still surfaced under scoping" || no "own-repo hit lost under scoping"
echo "$out" | grep -q "validation-parity" && ok "own-repo class still surfaced under scoping" || no "own-repo class lost under scoping"
# (b) Append a line with the SAME changed_paths but repo:"other/repo" — it must NOT contribute.
jq -cn '{schema_version:1, number:7, repo:"other/repo", branch:"b7", pr_url:"u7",
         changed_paths:["src/cross/repo-only.ts"],
         categories:[{round:1,class:"cross-repo-leak",self_heal_miss:false,flow_stage:"worker",evidence:"x"}],
         self_heal_misses:0, flow_stages:{worker:1}, summary:"s7"}' >> "$TMP/$CORPUS"
out2="$( cd "$TMP" && bash "$READ" "src/cross/repo-only.ts" 2>/dev/null )"; rc2=$?
[ "$rc2" -eq 0 ] && ok "exit 0 querying a foreign-repo-only path" || no "non-zero exit on foreign-repo query ($rc2)"
echo "$out2" | grep -q "no prior churn recorded for the touched paths" && ok "foreign-repo entry did NOT contribute (no false cross-repo hit)" || no "foreign-repo entry leaked a false hit"
echo "$out2" | grep -q "cross-repo-leak" && no "foreign-repo class leaked under scoping" || ok "foreign-repo class correctly excluded"
rm -rf "$TMP"

echo "== 4g. repo scoping is CASE-INSENSITIVE (GitHub slugs are case-insensitive) =="
# A mixed/upper-case remote (origin → CUR_REPO="O/R") must STILL match a corpus entry recorded
# with a lower-case repo:"o/r" — case-insensitive comparison, else a legitimate same-repo
# prior-churn hit would be silently dropped. The write_fixture entries all carry repo:"o/r".
TMP="$(newrepo)"; write_fixture "$TMP"
( cd "$TMP" && git remote add origin https://github.com/O/R.git )
out="$( cd "$TMP" && bash "$READ" "src/auth/guard.ts" 2>/dev/null )"; rc=$?
[ "$rc" -eq 0 ] && ok "exit 0 with mixed-case CUR_REPO" || no "non-zero exit with mixed-case CUR_REPO ($rc)"
echo "$out" | grep -q "src/auth/guard.ts" && ok "case-insensitive: O/R hit against corpus o/r still surfaced" || no "case-insensitive same-repo hit dropped"
echo "$out" | grep -q "validation-parity" && ok "case-insensitive: own-repo class still surfaced" || no "case-insensitive class lost"
rm -rf "$TMP"

echo "== 5. jq masked off PATH → exit 0, quiet (missing-tool fail-safe) =="
TMP="$(newrepo)"; write_fixture "$TMP"
# Provide a PATH containing only a minimal toolset WITHOUT jq. We hand-pick the dirs that hold
# the coreutils/git the script needs and deliberately exclude any dir containing jq by shadowing
# it with an empty dir prepended that has a non-executable jq placeholder? Simpler + robust:
# run with a PATH that excludes jq's dir by building a temp bin with symlinks to required tools.
maskbin="$(mktemp -d)"
for t in bash sh git mktemp sort grep printf date dirname cat env sed; do
  p="$(command -v "$t" 2>/dev/null || true)"; [ -n "$p" ] && ln -sf "$p" "$maskbin/$t" 2>/dev/null || true
done
# Ensure jq is NOT reachable via $maskbin.
out="$( cd "$TMP" && PATH="$maskbin" bash "$READ" "src/auth/guard.ts" 2>/dev/null )"; rc=$?
if command -v jq >/dev/null 2>&1; then
  [ "$rc" -eq 0 ] && ok "exit 0 with jq masked off PATH" || no "non-zero exit jq-masked ($rc)"
  [ -z "$out" ] && ok "quiet when jq unavailable" || no "produced output when jq unavailable"
else
  ok "jq not installed in this env — missing-tool path is the default (skipped active mask)"
fi
rm -rf "$TMP" "$maskbin"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
