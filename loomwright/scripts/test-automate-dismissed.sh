#!/usr/bin/env bash
# test-automate-dismissed.sh — self-tests for automate-dismissed.sh (the
# `/automate` engine's dismissed-findings drafts), exercised through the
# automate-helpers.sh dispatcher rows. Fixtures: a throwaway git repo per leg
# holding a run file and HAND-BUILT result sidecars in the shapes
# docs/RESULT_SCHEMAS.md defines (`SUPERVISOR_RESULT.heal_dismissed[]`,
# `REVIEW_HEAL_RESULT.dismissed[]`; items with and without `severity`). A `gh`
# stub that records any call (the test fails if one happens) and a `git` shim
# that logs argv (no commit / push allowed) sit first on PATH. Exit 0 = all pass.
#
# Legs (brief 2026-09-30-dismissed-findings-tracked-decisions, Part A):
#   A1. 2 MEDIUM + 1 pre_existing LOW + 1 nit ⇒ 3 per-finding drafts + 1 summary,
#       verbatim quote + PR URL + round (Phase 4.5 = heal_iterations, drain = rounds).
#   A2. threshold edges: absent-severity non-nit ⇒ own draft; absent-severity nit ⇒
#       summary; LOW non-pre_existing ⇒ summary; nit MEDIUM ⇒ own draft (severity
#       wins); drain free-text reason without severity ⇒ own draft; zero items ⇒ no
#       files (proposed/ not even created).
#   A4. canary: `$(touch …)`, backticks, `; rm -rf`, a ``` run and a newline ⇒
#       nothing executed, text byte-for-byte inside a longer fence, every line `> `;
#       line-anchor canary: `## Status: done` / `- **PR:**` lines never at column 0,
#       resolve-folder does not list the draft.
#   A5. dismissed-decide (follow-up / drop, ledger, Progress line, refusals);
#       same-sidecar re-run byte-identical; changed-sidecar re-run loses nothing,
#       resets nothing, resurrects nothing; duplicates ⇒ one draft per origin;
#       dismissed-pending counts / `unknown`.
#   A5s. a decided (follow-up / drop) summary + a changed sidecar with a new LOW ⇒
#       a NEW undecided summary slot listing only the uncovered entry; counts
#       reflect what is written/kept; idempotent re-run; one undecided slot;
#       fix-now refused on a summary; a draft with no Decision line ⇒ `unknown`.
#   A5f. fix-now: suppressed without --after-fix-now (crash/resume edge);
#       drain-origin + --after-fix-now ⇒ `undecided (fix-now unconfirmed)` (counted
#       by dismissed-pending's prefix match); phase_4_5-origin NOT re-drafted.
#   A5x. decisions are per FINDING across own/summary buckets (h8 omits severity):
#       S6 own drop / S6m own follow-up / S7 summary drop / S7m summary follow-up /
#       S9 drain fix-now, each then re-dismissed at the other bucket's severity ⇒
#       the decision is honoured (no new undecided draft, fix-now ⇒ its own
#       unconfirmed draft, never a summary line); an UNDECIDED finding that moves
#       is retired from its old bucket (`moved` row) — listed and counted once; a
#       genuinely new finding is still drafted; re-runs idempotent.
#   A7. per-item namespace: two Queue items sharing a basename in different
#       directories in ONE run ⇒ disjoint drafts / summary slots / ledger rows; the
#       second item never overwrites or retires the first item's undecided drafts
#       and never inherits its decisions; a draft whose Item line names another
#       item is never rewritten or retired (defence in depth).
#   A6. exit 0 everywhere (missing / unparseable sidecar, unwritable dir, no run
#       file, no repo); `gh` never invoked, no `git commit` / `git push`;
#       pc_guarded_write is load-bearing (mutation control: PROPOSE_COMMON_SH at a
#       copy with the marked guard block deleted turns the refusal legs red).
#   B. (Part B) SKILL-text legs — the prose the inline loop executes: the decision
#       subsection exists and precedes the park write + the watcher arm on every park
#       path (safe-mode, fail-closed --auto-merge, escalated, GATE step 4);
#       --non-interactive-fallback asks nothing and records pending_decisions; the
#       PICK ask precedes RECONCILE's closeout and offers Follow-up / Drop only;
#       fix-now bounds + honest limits; every restating single-drain surface carries
#       the fix-now qualifier (targeted per surface, not a blanket grep); the
#       optional `severity` key in the schema + all three producers; the §1.5 rows,
#       §3 / AUTOMATE_RUN `## Current` line; the proposed/ README template and the
#       committed README are byte-identical.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
H="$HERE/automate-helpers.sh"
SUT="$HERE/automate-dismissed.sh"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

TOP="$(mktemp -d "${TMPDIR:-/tmp}/test-automate-dismissed.XXXXXX")"
TOP="$(cd "$TOP" && pwd -P)"
cleanup_all() { chmod -R u+rwx "$TOP" 2>/dev/null; rm -rf "$TOP"; }
trap cleanup_all EXIT

# ---- PATH stubs: gh (must never run) + a logging git shim --------------------
REAL_GIT="$(command -v git)"
STUB="$TOP/bin"; mkdir -p "$STUB"
printf '#!/usr/bin/env bash\necho "gh $*" >> "%s/gh-called"\nexit 1\n' "$TOP" > "$STUB/gh"
printf '#!/usr/bin/env bash\necho "$*" >> "%s/git.log"\nexec "%s" "$@"\n' "$TOP" "$REAL_GIT" > "$STUB/git"
chmod +x "$STUB/gh" "$STUB/git"
export PATH="$STUB:$PATH"
export LOOMWRIGHT_GH_BIN="$STUB/gh"
unset PROPOSE_COMMON_SH

PRURL="https://github.com/acme/widgets/pull/42"
ITEM=".supervisor/requirements/f/01-a.md"
RUN_ID="automate-2026-01-01-000000"
# ih6 <item> — first 6 hex of sha1(full Queue item path): the per-item namespace key.
ih6() { printf '%s' "$1" | python3 -c 'import hashlib,sys; print(hashlib.sha1(sys.stdin.buffer.read()).hexdigest()[:6])'; }
NS="$RUN_ID--01-a-$(ih6 "$ITEM")"   # this item's draft-name namespace

# fx <n> [run_id] — a fresh repo with a run file; sets R (repo), RF, AD, PROP.
fx() {
  local rid="${2:-$RUN_ID}"
  R="$TOP/r$1"; mkdir -p "$R/.supervisor/automate"
  "$REAL_GIT" init -q "$R"
  AD="$R/.supervisor/automate"; RF="$AD/$rid.md"; PROP="$R/.supervisor/requirements/proposed"
  printf '# Automate Run: fixture\n## Status: running\n## Queue\n- [ ] %s\n## Progress\n- t0 picked\n' "$ITEM" > "$RF"
}
# sup <heal_iterations> <flow list or empty> — the Phase 4.5 sidecar
sup() {
  { printf 'SUPERVISOR_RESULT:\n  schema_version: 1\n  status: completed\n  heal_iterations: %s\n  heal_decision: PASS\n' "$1"
    [ -n "$2" ] && printf '  heal_dismissed: %s\n' "$2"
  } > "$AD/$(basename "$RF" .md).supervisor-result.md"
}
# rh <rounds> <flow list or empty> — the owned drain's sidecar
rh() {
  { printf '## REVIEW_HEAL_RESULT\n- schema_version: 2\n- decision: READY\n- rounds: %s\n' "$1"
    [ -n "$2" ] && printf -- '- dismissed: %s\n' "$2"
  } > "$AD/$(basename "$RF" .md).review-heal-result.md"
}
drafts() { dd_out="$(bash "$H" dismissed-drafts "$RF" "$ITEM" "$PRURL" "$@" 2>&1)"; dd_rc=$?; }
nfiles() { find "$PROP" -maxdepth 1 -type f -name '*--dismissed-*.md' 2>/dev/null | wc -l | tr -d ' '; }
path_of() { printf '%s\n' "$dd_out" | awk -F'\t' -v k="$1" '$1 == "draft" && $2 == k { print $4; exit }'; }
# find the draft whose quoted body contains <text>
draft_with() { grep -lF -- "> $1" "$PROP"/*--dismissed-*.md 2>/dev/null | head -n1; }
progress_n() { grep -c '^- dismissed: ' "$RF" 2>/dev/null || true; }
tree_sum() { (cd "$PROP" 2>/dev/null && for f in *; do [ -f "$f" ] && printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }

# =============================================================================
echo "== A1. counts, verbatim quote, PR URL, round =="
fx 1
sup 2 '[{finding: "medium phase one", reason: below_severity_floor, source: code_reviewer, severity: MEDIUM}, {finding: "pre-existing low one", reason: pre_existing, source: code_reviewer, severity: LOW}, {finding: "a nit", reason: nit, source: red_team, severity: LOW}]'
rh 3 '[{finding: "drain medium one", reason: "stale: fixed in abc123", source: reviews, severity: MEDIUM}]'
drafts
[ "$dd_rc" -eq 0 ] && ok "exit 0" || no "rc=$dd_rc"
[ "$(nfiles)" = "4" ] && ok "4 files in proposed/" || no "files: $(nfiles)"
[ "$(printf '%s\n' "$dd_out" | tail -n1)" = "dismissed-drafts: 3 per-finding + 1 summary (1 listed in summary)" ] && ok "summary line: 3 per-finding + 1 summary (1 listed)" || no "summary line: $(printf '%s\n' "$dd_out" | tail -n1)"
[ "$(printf '%s\n' "$dd_out" | grep -c '^draft	')" = "4" ] && ok "one TSV draft row per file" || no "rows: $dd_out"
bad=""
for spec in "medium phase one|2|phase_4_5|MEDIUM" "pre-existing low one|2|phase_4_5|LOW" "drain medium one|3|drain|MEDIUM"; do
  t="${spec%%|*}"; rest="${spec#*|}"; rnd="${rest%%|*}"; rest="${rest#*|}"; org="${rest%%|*}"; sev="${rest#*|}"
  f="$(draft_with "$t")"
  if [ -z "$f" ]; then bad="$bad [no draft for $t]"; continue; fi
  case "$(basename "$f")" in "$NS--dismissed-"[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f].md) ;; *) bad="$bad [name $(basename "$f")]" ;; esac
  for want in "- **PR:** $PRURL" "- **Round:** $rnd" "- **Origin:** $org" "- **Severity:** $sev" "- **Decision:** undecided" "## Status: proposed" "- **Run:** $RUN_ID" "- **Item:** $ITEM" "> $t"; do
    grep -qxF -- "$want" "$f" || bad="$bad [$t lacks '$want']"
  done
  [ "$(sed -n 3p "$f")" = "## Status: proposed" ] || bad="$bad [$t: line 3 not the status stamp]"
done
[ -z "$bad" ] && ok "each per-finding draft: content-addressed name, verbatim > quote, PR URL, round, origin, severity, undecided" || no "draft content:$bad"
S1="$(path_of summary)"
if [ -n "$S1" ] && grep -qxF -- "> a nit" "$S1" && grep -qxF -- "- **Reason dismissed:** nit" "$S1" && [ "$(basename "$S1")" = "$NS--dismissed-summary.md" ]; then ok "summary draft lists the nit with its metadata"; else no "summary: $S1"; fi
grep -qF 'propose-only — nothing enqueues this file' "$S1" 2>/dev/null && ok "closing line quotes the proposed/ contract" || no "closing contract line missing"
grep -q 'reason: "stale: fixed in abc123"' "$AD/$RUN_ID.review-heal-result.md" && grep -qxF -- "- **Reason dismissed:** stale: fixed in abc123" "$(draft_with 'drain medium one')" && ok "free-text drain reason carried verbatim" || no "drain reason"

# =============================================================================
echo "== A2. threshold edges =="
fx 2
sup 1 '[{finding: "legacy no severity", reason: below_severity_floor, source: code_reviewer}, {finding: "legacy nit", reason: nit, source: code_reviewer}, {finding: "low floor", reason: below_severity_floor, source: code_reviewer, severity: LOW}, {finding: "nit but medium", reason: nit, source: code_reviewer, severity: MEDIUM}]'
rh 2 '[{finding: "drain no severity", reason: "invalid: file was deleted", source: issue_comments}]'
drafts
[ -n "$(draft_with 'legacy no severity')" ] && ok "absent severity, reason != nit ⇒ own draft (Severity: unspecified)" || no "legacy no-severity not drafted"
grep -qxF -- "- **Severity:** unspecified" "$(draft_with 'legacy no severity')" 2>/dev/null && ok "absent severity rendered as 'unspecified', never invented" || no "severity rendering"
[ -n "$(draft_with 'nit but medium')" ] && ok "nit + MEDIUM ⇒ own draft (severity wins over the nit reason)" || no "nit MEDIUM not drafted"
[ -n "$(draft_with 'drain no severity')" ] && ok "drain free-text reason, no severity ⇒ own draft (fail toward tracking)" || no "drain no-severity not drafted"
S2="$(path_of summary)"
if [ -n "$S2" ] && grep -qxF -- "> low floor" "$S2" && grep -qxF -- "> legacy nit" "$S2"; then ok "LOW non-pre_existing and absent-severity nit ⇒ summary"; else no "summary content"; fi
[ "$(printf '%s\n' "$dd_out" | tail -n1)" = "dismissed-drafts: 3 per-finding + 1 summary (2 listed in summary)" ] && ok "counts: 3 + 1 (2 listed)" || no "counts: $(printf '%s\n' "$dd_out" | tail -n1)"
fx 3; sup 0 ''
drafts
[ ! -e "$PROP" ] && ok "zero items ⇒ no files (proposed/ not created)" || no "zero items created $(ls "$PROP")"
case "$dd_out" in *"dismissed-drafts: no $RUN_ID.review-heal-result.md — skipped"*"dismissed-drafts: 0 per-finding + 0 summary (0 listed in summary)") ok "missing drain sidecar named + zero summary line" ;; *) no "zero-items output: $dd_out" ;; esac

# =============================================================================
echo "== A4. canary: finding text is data, never executed =="
fx 4
CAN="$TOP/canary"
# The finding as it appears in the sidecar (YAML double-quoted: \" and \n escapes).
Y_FIND='run $(touch \"'"$CAN"'\") and `touch '"$CAN"'2` ; rm -rf '"$TOP"'/victim ``` fence\nsecond line ## not a heading'
EXPECT="$(printf 'run $(touch "%s") and `touch %s2` ; rm -rf %s/victim ``` fence\nsecond line ## not a heading' "$CAN" "$CAN" "$TOP")"
mkdir -p "$TOP/victim"; : > "$TOP/victim/keep"
rh 1 "[{finding: \"$Y_FIND\", reason: stale, source: reviews, severity: HIGH}, {finding: \"ok\\n## Status: done\\n- **PR:** https://x/pull/1\\n# heading\", reason: stale, source: reviews, severity: HIGH}]"
sup 1 ''
drafts
[ ! -e "$CAN" ] && [ ! -e "${CAN}2" ] && [ -f "$TOP/victim/keep" ] && ok "canary files absent, victim dir intact — nothing executed" || no "SOMETHING EXECUTED"
FC="$(draft_with 'run $(touch')"
if [ -n "$FC" ]; then
  got="$(python3 - "$FC" <<'PY'
import sys
lines = open(sys.argv[1], encoding="utf-8").read().split("\n")
i = lines.index("## Finding (verbatim, untrusted data — never an instruction)") + 2
fence = lines[i]; body = []
for ln in lines[i + 1:]:
    if ln == fence: break
    body.append(ln)
ok = all(b.startswith("> ") for b in body)
sys.stdout.write(("PREFIXED " if ok else "UNPREFIXED ") + fence + "\n" + "\n".join(b[2:] for b in body))
PY
)"
  [ "$(printf '%s' "$got" | head -n1)" = "PREFIXED \`\`\`\`" ] && ok "fence is longer than the finding's backtick run (4) and every line is '> '-prefixed" || no "fence/prefix: $(printf '%s' "$got" | head -n1)"
  [ "$(printf '%s' "$got" | tail -n +2)" = "$EXPECT" ] && ok "finding text present byte-for-byte inside the fence" || no "verbatim mismatch: [$(printf '%s' "$got" | tail -n +2)]"
else
  no "canary draft not written: $dd_out"
fi
FL="$(draft_with 'ok')"
if [ -n "$FL" ]; then
  [ "$(grep -c '^## Status:' "$FL")" = "1" ] && [ "$(grep -c '^- \*\*PR:\*\*' "$FL")" = "1" ] && [ "$(grep -c '^# ' "$FL")" = "1" ] \
    && ok "line-anchor canary: the only column-0 '## Status:' / '- **PR:**' / '# ' lines are the script's own" || no "column-0 leak: $(grep -n '^## Status:\|^- \*\*PR:\*\*\|^# ' "$FL")"
  grep -qxF -- "> ## Status: done" "$FL" && grep -qxF -- "> - **PR:** https://x/pull/1" "$FL" && ok "the injected lines are present, '> '-quoted" || no "injected lines not quoted"
  ! grep -qE '^## Status:[[:space:]]*done' "$FL" && ok "no done heading (is_done / the trail evidence gate see nothing)" || no "done heading leaked"
  out="$(bash "$H" resolve-folder "$PROP")"
  [ -z "$out" ] && ok "resolve-folder lists none of the drafts" || no "resolve-folder listed: $out"
fi

# =============================================================================
echo "== A5. dismissed-decide, ledger, re-runs, duplicates, dismissed-pending =="
fx 5
SUP_A='[{finding: "alpha medium", reason: below_severity_floor, source: code_reviewer, severity: MEDIUM}, {finding: "beta high", reason: below_severity_floor, source: red_team, severity: HIGH}, {finding: "gamma pre", reason: pre_existing, source: code_reviewer, severity: INFO}, {finding: "delta low", reason: below_severity_floor, source: code_reviewer, severity: LOW}]'
sup 1 "$SUP_A"; rh 2 '[{finding: "drain epsilon", reason: stale, source: reviews}]'
drafts
FA="$(draft_with 'alpha medium')"; FB="$(draft_with 'beta high')"; FG="$(draft_with 'gamma pre')"; FE="$(draft_with 'drain epsilon')"
[ "$(bash "$H" dismissed-pending "$RF")" = "5" ] && ok "dismissed-pending counts 5 undecided (4 per-finding + summary)" || no "pending: $(bash "$H" dismissed-pending "$RF")"
p0="$(progress_n)"
out="$(bash "$H" dismissed-decide "$RF" "$FA" follow-up)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "dismissed-decide: follow-up $(basename "$FA")" ] && ok "decide follow-up: one line, exit 0" || no "decide follow-up: rc=$rc $out"
[ -f "$FA" ] && grep -qxF -- "- **Decision:** follow-up" "$FA" && [ "$(grep -c '^- \*\*Decision:\*\*' "$FA")" = "1" ] && ok "follow-up keeps the file and rewrites the Decision line" || no "follow-up file state"
out="$(bash "$H" dismissed-decide "$RF" "$FB" drop)"
[ ! -e "$FB" ] && ok "drop deletes the draft" || no "drop left the file: $out"
LED="$AD/$RUN_ID.dismissed-decisions"
[ "$(awk -F'\t' -v n="$(basename "$FA")" '$1==n{print $2}' "$LED")" = "follow-up" ] && [ "$(awk -F'\t' -v n="$(basename "$FB")" '$1==n{print $2}' "$LED")" = "drop" ] && ok "ledger keyed by draft name records both decisions" || no "ledger: $(cat "$LED" 2>/dev/null)"
[ "$(( $(progress_n) - p0 ))" = "2" ] && grep -qF -- "- dismissed: drop $(basename "$FB") — beta high" "$RF" && ok "exactly one Progress line per decision, naming the draft and the finding" || no "progress lines: $(grep '^- dismissed' "$RF")"
# refusals
p1="$(progress_n)"; l1="$(wc -l < "$LED" | tr -d ' ')"
mkdir -p "$TOP/elsewhere"; cp "$FG" "$TOP/elsewhere/$(basename "$FG")"
o1="$(bash "$H" dismissed-decide "$RF" "$TOP/elsewhere/$(basename "$FG")" drop)"
printf 'x\n' > "$PROP/other-run--01-a--dismissed-0a1b2c3d.md"
o2="$(bash "$H" dismissed-decide "$RF" "$PROP/other-run--01-a--dismissed-0a1b2c3d.md" drop)"
o3="$(bash "$H" dismissed-decide "$RF" "$FG" maybe)"
o4="$(bash "$H" dismissed-decide "$RF" "$PROP/../proposed/../../../README.md" drop)"
case "$o1|$o2|$o3|$o4" in "dismissed-decide: refused — "*"|dismissed-decide: refused — "*"|dismissed-decide: refused — "*"|dismissed-decide: refused — "*) ok "refuses: path outside proposed/, another run's draft, a bad decision, a traversal path" ;; *) no "refusals: [$o1] [$o2] [$o3] [$o4]" ;; esac
[ -f "$FG" ] && [ -f "$PROP/other-run--01-a--dismissed-0a1b2c3d.md" ] && [ "$(progress_n)" = "$p1" ] && [ "$(wc -l < "$LED" | tr -d ' ')" = "$l1" ] && ok "a refusal touches no file, no ledger row, no Progress line" || no "refusal side effects"
rm -f "$PROP/other-run--01-a--dismissed-0a1b2c3d.md"
[ "$(bash "$H" dismissed-pending "$RF")" = "3" ] && ok "dismissed-pending after follow-up + drop = 3" || no "pending: $(bash "$H" dismissed-pending "$RF")"
# same sidecars ⇒ byte-identical tree
before="$(tree_sum)"; drafts
[ "$(tree_sum)" = "$before" ] && ok "re-run with the SAME sidecars: every draft byte-identical, dropped not recreated" || no "re-run changed the tree"
# changed sidecar: reorder A + one new finding
sup 1 '[{finding: "delta low", reason: below_severity_floor, source: code_reviewer, severity: LOW}, {finding: "zeta new", reason: below_severity_floor, source: code_reviewer, severity: MEDIUM}, {finding: "gamma pre", reason: pre_existing, source: code_reviewer, severity: INFO}, {finding: "beta high", reason: below_severity_floor, source: red_team, severity: HIGH}, {finding: "alpha   medium", reason: below_severity_floor, source: code_reviewer, severity: MEDIUM}]'
cks_a="$(cksum < "$FA")"; drafts
[ -n "$(draft_with 'zeta new')" ] && ok "changed sidecar: the new finding gets a new draft" || no "new finding lost"
[ "$(cksum < "$FA")" = "$cks_a" ] && ok "changed sidecar: the follow-up decision is not reset (file untouched)" || no "follow-up draft rewritten"
[ ! -e "$FB" ] && ok "changed sidecar: the dropped draft is not resurrected" || no "dropped draft resurrected"
[ -f "$FG" ] && [ -f "$FE" ] && [ -f "$(path_of summary)" ] && ok "changed sidecar: every other finding still has its draft (nothing lost)" || no "a draft vanished"
[ "$(bash "$H" dismissed-pending "$RF")" = "4" ] && ok "dismissed-pending = 4 (3 + the new one)" || no "pending: $(bash "$H" dismissed-pending "$RF")"
# duplicates
fx 6
sup 2 '[{finding: "same  finding", reason: nit, source: code_reviewer, severity: HIGH}, {finding: "same finding ", reason: nit, source: code_reviewer, severity: HIGH}]'
rh 2 '[{finding: "same finding", reason: stale, source: reviews, severity: HIGH}, {finding: " same   finding", reason: stale, source: reviews, severity: HIGH}]'
drafts
[ "$(nfiles)" = "2" ] && [ "$(grep -l 'Origin:\*\* drain' "$PROP"/*.md | wc -l | tr -d ' ')" = "1" ] && ok "duplicates across heal iterations / drain rounds ⇒ one draft per origin" || no "duplicates: $(nfiles) files"
# dismissed-pending unknown
[ "$(bash "$H" dismissed-pending "$TOP/nope.md")" = "unknown" ] && ok "dismissed-pending: missing run file ⇒ unknown" || no "pending missing run file"
if [ "$(id -u)" != "0" ]; then
  chmod 000 "$PROP"; pu="$(bash "$H" dismissed-pending "$RF")"; prc=$?; chmod 755 "$PROP"
  [ "$pu" = "unknown" ] && [ "$prc" -eq 0 ] && ok "dismissed-pending: unreadable proposed/ ⇒ unknown, exit 0" || no "pending unreadable: $pu rc=$prc"
else
  ok "dismissed-pending unreadable leg skipped (running as root)"
fi

# =============================================================================
echo "== A5s. a decided summary never hides a below-threshold finding it did not list =="
SB="$NS--dismissed-summary"
L1='{finding: "low one", reason: below_severity_floor, source: code_reviewer, severity: LOW}'
L2='{finding: "low two", reason: nit, source: red_team, severity: LOW}'
L3='{finding: "low three", reason: below_severity_floor, source: code_reviewer, severity: INFO}'
for how in follow-up drop; do
  fx "s-$how"; sup 1 "[$L1]"; drafts
  S0="$PROP/$SB.md"
  grep -qE '^- \*\*Key:\*\* [0-9a-f]{8}$' "$S0" && ok "$how: summary entries carry a column-0 Key line" || no "$how: no Key line in summary"
  bash "$H" dismissed-decide "$RF" "$S0" "$how" >/dev/null
  [ "$(awk -F'\t' -v n="$SB.md" '$1=="summary-member" && $3==n' "$AD/$RUN_ID.dismissed-decisions" | wc -l | tr -d ' ')" = "1" ] && ok "$how: decide records one summary-member row for the one listed entry" || no "$how: ledger $(cat "$AD/$RUN_ID.dismissed-decisions")"
  c0="$( [ -f "$S0" ] && cksum < "$S0")"
  # the drain's fix-now re-pass (or any changed sidecar) adds a new LOW finding
  sup 1 "[$L1, $L2]"; drafts
  S2="$PROP/$SB-2.md"
  if [ -f "$S2" ] && grep -qxF -- "> low two" "$S2" && ! grep -qxF -- "> low one" "$S2" && grep -qxF -- "- **Decision:** undecided" "$S2"; then ok "$how: the new LOW lands in a NEW undecided summary slot (summary-2), the decided entry is not repeated"; else no "$how: new LOW not tracked: $dd_out"; fi
  if [ "$how" = follow-up ]; then
    [ "$(cksum < "$S0")" = "$c0" ] && ok "follow-up: the decided summary is untouched" || no "follow-up: decided summary rewritten"
    want="dismissed-drafts: 0 per-finding + 2 summary (2 listed in summary)"
  else
    [ ! -e "$S0" ] && ok "drop: the dropped summary is not resurrected" || no "drop: summary.md resurrected"
    want="dismissed-drafts: 0 per-finding + 1 summary (1 listed in summary)"
  fi
  [ "$(printf '%s\n' "$dd_out" | tail -n1)" = "$want" ] && ok "$how: output counts only what is written/kept ($want)" || no "$how: counts: $(printf '%s\n' "$dd_out" | tail -n1)"
  [ "$(bash "$H" dismissed-pending "$RF")" = "1" ] && ok "$how: dismissed-pending counts the new summary slot" || no "$how: pending $(bash "$H" dismissed-pending "$RF")"
  before="$(tree_sum)"; l0="$(wc -l < "$AD/$RUN_ID.dismissed-decisions" | tr -d ' ')"; drafts
  [ "$(tree_sum)" = "$before" ] && [ ! -e "$PROP/$SB-3.md" ] && [ "$(wc -l < "$AD/$RUN_ID.dismissed-decisions" | tr -d ' ')" = "$l0" ] && ok "$how: re-run is idempotent (no third summary, no ledger row)" || no "$how: re-run drift"
  sup 1 "[$L1, $L2, $L3]"; drafts
  grep -qxF -- "> low two" "$S2" && grep -qxF -- "> low three" "$S2" && [ ! -e "$PROP/$SB-3.md" ] && ok "$how: another new LOW joins the one UNDECIDED slot (never a second undecided summary)" || no "$how: undecided slot not reused"
  bash "$H" dismissed-decide "$RF" "$S2" follow-up >/dev/null
  sup 1 "[$L1, $L2, $L3, {finding: \"low four\", reason: nit, source: code_reviewer, severity: LOW}]"; drafts
  [ -f "$PROP/$SB-3.md" ] && grep -qxF -- "> low four" "$PROP/$SB-3.md" && [ "$(grep -c '^### Entry' "$PROP/$SB-3.md")" = "1" ] && ok "$how: once summary-2 is decided too, the next new LOW opens summary-3 with only itself" || no "$how: summary-3: $dd_out"
done
# fix-now is refused on a summary draft (Keep / Drop only)
fx s-fix; sup 1 "[$L1]"; drafts
o="$(bash "$H" dismissed-decide "$RF" "$PROP/$SB.md" fix-now)"
case "$o" in "dismissed-decide: refused — "*) ok "fix-now on a summary draft is refused" ;; *) no "fix-now on summary: $o" ;; esac
[ -f "$PROP/$SB.md" ] && [ ! -e "$AD/$RUN_ID.dismissed-decisions" ] && ok "the refusal deletes nothing and writes no ledger row" || no "summary fix-now refusal side effects"
# dismissed-pending: a this-run draft with no readable Decision line ⇒ unknown
printf '# Dismissed finding: hand-edited\n\n## Status: proposed\n' > "$PROP/$NS--dismissed-deadbeef.md"
[ "$(bash "$H" dismissed-pending "$RF")" = "unknown" ] && ok "dismissed-pending: a draft without a Decision line ⇒ unknown (fail closed)" || no "pending no-decision: $(bash "$H" dismissed-pending "$RF")"

# =============================================================================
echo "== A5f. fix-now: unconfirmed re-draft (drain only, --after-fix-now only) =="
fx 7
sup 1 '[{finding: "phase fix me", reason: below_severity_floor, source: code_reviewer, severity: MEDIUM}]'
rh 1 '[{finding: "drain fix me", reason: stale, source: reviews, severity: MEDIUM}]'
drafts
FD="$(draft_with 'drain fix me')"; FP="$(draft_with 'phase fix me')"
bash "$H" dismissed-decide "$RF" "$FD" fix-now >/dev/null; bash "$H" dismissed-decide "$RF" "$FP" fix-now >/dev/null
[ ! -e "$FD" ] && [ ! -e "$FP" ] && ok "fix-now deletes both drafts" || no "fix-now left a draft"
drafts
[ ! -e "$FD" ] && [ ! -e "$FP" ] && ok "re-run WITHOUT --after-fix-now (crash/resume on the old sidecar) re-drafts nothing" || no "re-drafted without the flag"
rh 2 '[{finding: "drain fix me", reason: "still stale", source: reviews, severity: MEDIUM}]'
drafts --after-fix-now
if [ -f "$FD" ] && grep -qxF -- "- **Decision:** undecided (fix-now unconfirmed)" "$FD"; then ok "re-dismissed drain-origin fix-now ⇒ re-written 'undecided (fix-now unconfirmed)'"; else no "unconfirmed re-draft missing: $dd_out"; fi
[ "$(awk -F'\t' -v n="$(basename "$FD")" '$1==n{d=$2} END{print d}' "$AD/$RUN_ID.dismissed-decisions")" = "fix-now-unconfirmed" ] && ok "ledger row fix-now-unconfirmed appended" || no "ledger: $(cat "$AD/$RUN_ID.dismissed-decisions")"
[ ! -e "$FP" ] && ok "NEGATIVE: phase_4_5-origin fix-now with an unchanged supervisor sidecar is NOT re-drafted" || no "phase_4_5 fix-now re-drafted"
[ "$(bash "$H" dismissed-pending "$RF")" = "1" ] && ok "dismissed-pending counts the unconfirmed draft (prefix match on 'undecided')" || no "pending: $(bash "$H" dismissed-pending "$RF")"
c1="$(cksum < "$FD")"; l1="$(wc -l < "$AD/$RUN_ID.dismissed-decisions" | tr -d ' ')"
drafts --after-fix-now
[ "$(cksum < "$FD")" = "$c1" ] && [ "$(wc -l < "$AD/$RUN_ID.dismissed-decisions" | tr -d ' ')" = "$l1" ] && ok "unconfirmed re-run is byte-identical and appends no second ledger row" || no "unconfirmed re-run drift"
bash "$H" dismissed-decide "$RF" "$FD" follow-up >/dev/null
grep -qxF -- "- **Decision:** follow-up" "$FD" && [ "$(bash "$H" dismissed-pending "$RF")" = "0" ] && ok "the repeat answer (follow-up) settles it" || no "repeat answer"

# =============================================================================
echo "== A5x. decisions are per FINDING, across own/summary buckets =="
# h8 omits severity, so a rewritten sidecar can move one finding between its own
# draft and a summary. mv_ <SEV> — the same finding at another severity.
mv_() { printf '{finding: "mover", reason: below_severity_floor, source: code_reviewer, severity: %s}' "$1"; }
NEWL='{finding: "brand new low", reason: nit, source: red_team, severity: LOW}'
led() { cat "$AD/$RUN_ID.dismissed-decisions" 2>/dev/null; }
last() { printf '%s\n' "$dd_out" | tail -n1; }
# S6 — own draft DROPPED, re-dismissed LOW ⇒ no summary lists it; a NEW LOW still does.
fx x6; sup 1 "[$(mv_ MEDIUM)]"; drafts; OD="$(draft_with mover)"
bash "$H" dismissed-decide "$RF" "$OD" drop >/dev/null
sup 1 "[$(mv_ LOW)]"; drafts
[ "$(nfiles)" = "0" ] && [ "$(last)" = "dismissed-drafts: 0 per-finding + 0 summary (0 listed in summary)" ] && ok "S6: dropped own draft ⇒ re-dismissed LOW is NOT re-listed in a new summary" || no "S6: $dd_out / $(ls "$PROP" 2>/dev/null)"
sup 1 "[$(mv_ LOW), $NEWL]"; drafts
[ -f "$PROP/$SB.md" ] && grep -qxF -- "> brand new low" "$PROP/$SB.md" && ! grep -qxF -- "> mover" "$PROP/$SB.md" && ok "S6: a genuinely NEW finding is still drafted (summary lists only it)" || no "S6 new finding: $dd_out"
# S6m — own draft FOLLOW-UP, re-dismissed LOW ⇒ own draft kept, no summary, not re-asked.
fx x6m; sup 1 "[$(mv_ MEDIUM)]"; drafts; OD="$(draft_with mover)"
bash "$H" dismissed-decide "$RF" "$OD" follow-up >/dev/null; c0="$(cksum < "$OD")"
sup 1 "[$(mv_ LOW)]"; drafts
[ "$(cksum < "$OD")" = "$c0" ] && [ ! -e "$PROP/$SB.md" ] && [ "$(last)" = "dismissed-drafts: 1 per-finding + 0 summary (0 listed in summary)" ] && [ "$(bash "$H" dismissed-pending "$RF")" = "0" ] && ok "S6m: follow-up own draft kept as is, no summary line, nothing pending" || no "S6m: $dd_out"
# S7 — summary DROPPED, re-dismissed MEDIUM ⇒ no new per-finding draft.
fx x7; sup 1 "[$(mv_ LOW)]"; drafts
bash "$H" dismissed-decide "$RF" "$PROP/$SB.md" drop >/dev/null
sup 1 "[$(mv_ MEDIUM)]"; drafts
[ "$(nfiles)" = "0" ] && [ "$(last)" = "dismissed-drafts: 0 per-finding + 0 summary (0 listed in summary)" ] && ok "S7: dropped summary ⇒ re-dismissed MEDIUM gets NO new undecided own draft" || no "S7: $dd_out / $(ls "$PROP" 2>/dev/null)"
# S7m — summary FOLLOW-UP, re-dismissed MEDIUM ⇒ summary kept, no own draft.
fx x7m; sup 1 "[$(mv_ LOW)]"; drafts
bash "$H" dismissed-decide "$RF" "$PROP/$SB.md" follow-up >/dev/null; c0="$(cksum < "$PROP/$SB.md")"
sup 1 "[$(mv_ MEDIUM)]"; drafts
[ "$(nfiles)" = "1" ] && [ "$(cksum < "$PROP/$SB.md")" = "$c0" ] && [ "$(last)" = "dismissed-drafts: 0 per-finding + 1 summary (1 listed in summary)" ] && [ "$(bash "$H" dismissed-pending "$RF")" = "0" ] && ok "S7m: follow-up summary inherited — kept, no own draft, nothing pending" || no "S7m: $dd_out"
# S9 — drain fix-now, re-drain dismisses it LOW ⇒ its OWN unconfirmed draft (never a summary line).
fx x9; rh 1 "[$(mv_ MEDIUM)]"; drafts; OD="$(draft_with mover)"
bash "$H" dismissed-decide "$RF" "$OD" fix-now >/dev/null
rh 2 "[$(mv_ LOW)]"; drafts
[ "$(nfiles)" = "0" ] && ok "S9: without --after-fix-now the LOW re-dismissal stays suppressed (no summary)" || no "S9 no-flag: $dd_out"
drafts --after-fix-now
if [ -f "$OD" ] && grep -qxF -- "- **Decision:** undecided (fix-now unconfirmed)" "$OD" && [ ! -e "$PROP/$SB.md" ]; then ok "S9: fix-now → re-drain LOW ⇒ own draft 'undecided (fix-now unconfirmed)', no summary entry"; else no "S9: $dd_out / $(ls "$PROP" 2>/dev/null)"; fi
[ "$(led | awk -F'\t' -v n="$(basename "$OD")" '$1==n{d=$2} END{print d}')" = "fix-now-unconfirmed" ] && [ "$(bash "$H" dismissed-pending "$RF")" = "1" ] && ok "S9: fix-now-unconfirmed ledger row, counted pending" || no "S9 ledger: $(led)"
l0="$(led | wc -l | tr -d ' ')"; drafts --after-fix-now
[ "$(led | wc -l | tr -d ' ')" = "$l0" ] && [ ! -e "$PROP/$SB.md" ] && ok "S9: re-run appends no second ledger row" || no "S9 re-run: $(led)"
# U — an UNDECIDED finding that moves is re-placed, never listed (or asked) twice.
fx xu; sup 1 "[$(mv_ MEDIUM), $NEWL]"; drafts; OD="$(draft_with mover)"
sup 1 "[$(mv_ LOW), $NEWL]"; drafts
case "$dd_out" in *"dismissed-drafts: retired $(basename "$OD") — "*) ok "U: undecided own draft retired when its finding drops below the threshold (named)" ;; *) no "U retire line: $dd_out" ;; esac
[ ! -e "$OD" ] && grep -qxF -- "> mover" "$PROP/$SB.md" && [ "$(bash "$H" dismissed-pending "$RF")" = "1" ] && ok "U: the finding is listed once (summary), one pending draft — not double-counted" || no "U placement: $(ls "$PROP")"
[ "$(led | awk -F'\t' -v n="$(basename "$OD")" '$1==n{d=$2} END{print d}')" = "moved" ] && ok "U: a 'moved' ledger row records the retirement (the trail retracts by it)" || no "U ledger: $(led)"
before="$(tree_sum)"; l0="$(led | wc -l | tr -d ' ')"; drafts
[ "$(tree_sum)" = "$before" ] && [ "$(led | wc -l | tr -d ' ')" = "$l0" ] && ok "U: re-run idempotent (no second moved row, byte-identical tree)" || no "U re-run drift: $(led)"
sup 1 "[$(mv_ MEDIUM), $NEWL]"; drafts
[ -f "$OD" ] && grep -qxF -- "- **Decision:** undecided" "$OD" && grep -qxF -- "> brand new low" "$PROP/$SB.md" && ! grep -qxF -- "> mover" "$PROP/$SB.md" && ok "U: moved back up ⇒ own draft again (moved is not a decision), summary rewritten without it" || no "U back: $dd_out"
fx xu3; sup 1 "[$(mv_ LOW)]"; drafts
sup 1 "[$(mv_ MEDIUM)]"; drafts
[ ! -e "$PROP/$SB.md" ] && [ -n "$(draft_with mover)" ] && [ "$(bash "$H" dismissed-pending "$RF")" = "1" ] && ok "U: an undecided summary whose entry moved up is retired — the own draft is the one pending" || no "U summary retire: $dd_out"
# both sidecars gone (nothing current overlaps) ⇒ the undecided summary is left alone
fx xu2; sup 1 "[$(mv_ LOW), $NEWL]"; drafts
rm -f "$AD/$RUN_ID.supervisor-result.md"; drafts
[ -f "$PROP/$SB.md" ] && grep -qxF -- "> mover" "$PROP/$SB.md" && ok "U: no current findings (sidecars missing) ⇒ the undecided summary is left alone" || no "U2: $dd_out"
sup 1 "[$(mv_ MEDIUM), $NEWL]"; drafts
bash "$H" dismissed-decide "$RF" "$(draft_with mover)" drop >/dev/null
sup 1 "[$(mv_ LOW), $NEWL]"; drafts
! grep -qxF -- "> mover" "$PROP/$SB.md" 2>/dev/null && grep -qxF -- "> brand new low" "$PROP/$SB.md" && [ ! -e "$PROP/$SB-2.md" ] && ok "U: a dropped own draft is not resurrected in the summary it once sat in" || no "U2 drop: $dd_out"

# =============================================================================
echo "== A7. per-item namespace keyed by the FULL item path (basename collision) =="
fx 10
IT1=".supervisor/requirements/f/01-a.md"; IT2=".supervisor/requirements/g/01-a.md"
NS1="$RUN_ID--01-a-$(ih6 "$IT1")"; NS2="$RUN_ID--01-a-$(ih6 "$IT2")"
[ "$NS1" != "$NS2" ] && ok "same basename, different dirs ⇒ different namespaces ($NS1 / $NS2)" || no "namespaces collide: $NS1"
dd_item() { dd_out="$(bash "$H" dismissed-drafts "$RF" "$1" "$PRURL" 2>&1)"; dd_rc=$?; }
ns_n() { find "$PROP" -maxdepth 1 -type f -name "$1--dismissed-*.md" 2>/dev/null | wc -l | tr -d ' '; }
sup 1 '[{finding: "shared medium", reason: below_severity_floor, source: code_reviewer, severity: MEDIUM}, {finding: "shared low", reason: nit, source: code_reviewer, severity: LOW}]'
dd_item "$IT1"; s1="$(cd "$PROP" && for f in "$NS1"--dismissed-*.md; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done)"
dd_item "$IT2"; o2="$dd_out"
[ "$(ns_n "$NS1")" = "2" ] && [ "$(ns_n "$NS2")" = "2" ] && [ "$(nfiles)" = "4" ] && ok "each item has its own draft + its own summary (4 files)" || no "files: ns1=$(ns_n "$NS1") ns2=$(ns_n "$NS2") all=$(nfiles)"
s1b="$(cd "$PROP" && for f in "$NS1"--dismissed-*.md; do printf '%s %s\n' "$f" "$(cksum < "$f")"; done)"
[ "$s1" = "$s1b" ] && ok "item 2's run leaves item 1's drafts byte-identical (no summary overwrite)" || no "item 1 drafts changed by item 2"
bad=""
for f in "$PROP/$NS1"--dismissed-*.md; do grep -qxF -- "- **Item:** $IT1" "$f" || bad="$bad $(basename "$f")"; done
for f in "$PROP/$NS2"--dismissed-*.md; do grep -qxF -- "- **Item:** $IT2" "$f" || bad="$bad $(basename "$f")"; done
[ -z "$bad" ] && ok "every draft's Item line names the item of its namespace" || no "Item lines:$bad"
# the finding moves to the summary for item 2 only: item 2 retires ITS own draft, never item 1's
sup 1 '[{finding: "shared medium", reason: below_severity_floor, source: code_reviewer, severity: LOW}, {finding: "shared low", reason: nit, source: code_reviewer, severity: LOW}]'
dd_item "$IT2"
case "$dd_out" in *"retired $NS2--dismissed-"*) ok "item 2 retires its own moved draft" ;; *) no "item 2 retire: $dd_out" ;; esac
case "$dd_out" in *"$NS1"*) no "item 2 touched item 1's namespace: $dd_out" ;; *) ok "item 2's output never names an item-1 draft" ;; esac
[ "$(ns_n "$NS1")" = "2" ] && [ -n "$(cd "$PROP" && grep -lxF -- '> shared medium' "$NS1"--dismissed-[0-9a-f]*.md 2>/dev/null)" ] && ok "item 1's undecided own draft survives item 2's move (not retired as moved)" || no "item 1 own draft lost"
! grep -q . < <(awk -F'\t' -v p="$NS1" 'index($1, p) == 1' "$AD/$RUN_ID.dismissed-decisions" 2>/dev/null) && ok "no ledger row for item 1 was written by item 2" || no "ledger: $(cat "$AD/$RUN_ID.dismissed-decisions")"
# decisions do not cross items: dropping item 1's summary leaves item 2's summary undecided
bash "$H" dismissed-decide "$RF" "$PROP/$NS1--dismissed-summary.md" drop >/dev/null
dd_item "$IT2"
[ -f "$PROP/$NS2--dismissed-summary.md" ] && grep -qxF -- "- **Decision:** undecided" "$PROP/$NS2--dismissed-summary.md" && grep -qxF -- "> shared low" "$PROP/$NS2--dismissed-summary.md" && ok "item 1's drop does not govern item 2's identical finding" || no "item 2 summary: $dd_out"
# defence in depth: a file at this item's draft name whose Item line names another item
fx 11
sup 1 '[{finding: "foreign one", reason: pre_existing, source: code_reviewer, severity: MEDIUM}]'
H8="$(printf 'phase_4_5\tcode_reviewer\tforeign one' | python3 -c 'import hashlib,sys; print(hashlib.sha1(sys.stdin.buffer.read()).hexdigest()[:8])')"
mkdir -p "$PROP"; FN="$PROP/$NS--dismissed-$H8.md"
printf '# Dismissed finding: other\n\n## Status: proposed\n\n- **Item:** .supervisor/requirements/zz/other.md\n- **Decision:** undecided\n' > "$FN"; c0="$(cksum < "$FN")"
drafts
[ "$(cksum < "$FN")" = "$c0" ] && case "$dd_out" in *"refused $NS--dismissed-$H8.md — it belongs to another item"*) true ;; *) false ;; esac && ok "a draft whose Item line names another item is refused, left byte-identical" || no "foreign draft: $dd_out"
sup 1 '[{finding: "foreign one", reason: nit, source: code_reviewer, severity: LOW}]'; drafts
[ -f "$FN" ] && [ "$(cksum < "$FN")" = "$c0" ] && ok "a foreign draft is never retired as moved" || no "foreign draft retired: $dd_out"

# =============================================================================
echo "== A8. an EXISTING but unreadable ledger: skipped, nothing written / retired / appended =="
h8of() { printf '%s\t%s\t%s' "$1" "$2" "$3" | python3 -c 'import hashlib,sys; print(hashlib.sha1(sys.stdin.buffer.read()).hexdigest()[:8])'; }
ul_setup() { # <fixture> — a follow-up own draft + a dropped summary, then a sidecar that would move the follow-up finding
  fx "$1"; sup 1 "[$(mv_ MEDIUM), $NEWL]"; drafts; UO="$(draft_with mover)"
  bash "$H" dismissed-decide "$RF" "$UO" follow-up >/dev/null
  bash "$H" dismissed-decide "$RF" "$PROP/$SB.md" drop >/dev/null
  sup 1 "[$(mv_ LOW), $NEWL, {finding: \"another low\", reason: nit, source: code_reviewer, severity: LOW}]"
  LED="$AD/$RUN_ID.dismissed-decisions"
}
ul_assert() { # <label> — after the ledger was made unreadable; LC = its cksum taken just before
  local before p0 o
  before="$(tree_sum)"; p0="$(progress_n)"
  drafts
  [ "$dd_rc" -eq 0 ] && [ "$dd_out" = "dismissed-drafts: skipped — unreadable ledger $LED" ] && ok "$1: ONE 'skipped — unreadable ledger <path>' line, exit 0" || no "$1: out=[$dd_out] rc=$dd_rc"
  [ "$(tree_sum)" = "$before" ] && [ -f "$UO" ] && [ ! -e "$PROP/$SB.md" ] && ok "$1: zero file changes (follow-up draft kept, dropped summary NOT resurrected, nothing retired)" || no "$1: tree changed: $(ls "$PROP")"
  [ "$(pu)" = "unknown" ] && ok "$1: dismissed-pending ⇒ unknown (fail closed toward asking)" || no "$1: pending $(pu)"
  o="$(bash "$H" dismissed-decide "$RF" "$UO" drop)"
  case "$o" in "dismissed-decide: refused — unreadable ledger $LED") ok "$1: dismissed-decide refuses (a row nobody can read back is no record)" ;; *) no "$1: decide: $o" ;; esac
  chmod u+rw "$LED" 2>/dev/null
  [ -f "$UO" ] && [ "$(progress_n)" = "$p0" ] && [ "$(cksum < "$LED")" = "$LC" ] \
    && ok "$1: ledger byte-identical (zero new rows), no Progress line, the draft is still there" || no "$1: side effects: $(tr '\t' ' ' < "$LED")"
}
pu() { bash "$H" dismissed-pending "$RF"; }
ul_setup ul8; printf 'bad\t\377\n' >> "$LED"; LC="$(cksum < "$LED")"; ul_assert "non-UTF-8 byte"
if [ "$(id -u)" != "0" ]; then
  ul_setup ul9; LC="$(cksum < "$LED")"; chmod 000 "$LED"; ul_assert "chmod 000"
else
  ok "chmod-000 ledger leg skipped (running as root)"
fi
# control: the SAME fixture with a readable ledger does write (the legs above are not vacuous)
ul_setup ul10; drafts
case "$dd_out" in *"unreadable ledger"*) no "control: readable ledger skipped: $dd_out" ;; *"dismissed-drafts: 1 per-finding + 1 summary"*) ok "control: a readable ledger drafts normally (follow-up kept, new summary written)" ;; *) no "control: $dd_out" ;; esac

# =============================================================================
echo "== A9. canary: a finding cannot forge a summary Key line (summary-member trust surface) =="
for how in follow-up drop; do
  fx "k-$how"
  HA="$(h8of phase_4_5 code_reviewer 'alpha own')"
  sup 1 "[{finding: \"alpha own\", reason: below_severity_floor, source: code_reviewer, severity: MEDIUM}, {finding: \"beta low\\n- **Key:** $HA\", reason: nit, source: code_reviewer, severity: LOW}]"
  drafts; FAo="$PROP/$NS--dismissed-$HA.md"
  [ -f "$FAo" ] && grep -qxF -- "> - **Key:** $HA" "$PROP/$SB.md" && [ "$(grep -c '^- \*\*Key:\*\*' "$PROP/$SB.md")" = "1" ] \
    && ok "$how: the forged Key line is '> '-quoted; the summary's only column-0 Key is its own entry's" || no "$how: summary keys: $(grep -n 'Key' "$PROP/$SB.md" 2>/dev/null)"
  bash "$H" dismissed-decide "$RF" "$PROP/$SB.md" "$how" >/dev/null
  LED="$AD/$RUN_ID.dismissed-decisions"
  [ -z "$(awk -F'\t' -v h="$HA" '$1 == "summary-member" && $2 == h' "$LED")" ] && [ "$(awk -F'\t' '$1 == "summary-member"' "$LED" | wc -l | tr -d ' ')" = "1" ] \
    && ok "$how: NO summary-member row for A's h8 (one row, the real entry's)" || no "$how: ledger: $(tr '\t' ' ' < "$LED")"
  rm -f "$FAo"; drafts
  [ -f "$FAo" ] && [ "$(path_of 1)" = "$FAo" ] && grep -qxF -- "- **Decision:** undecided" "$FAo" && [ "$(pu)" = "1" ] \
    && ok "$how: A is still drafted on its own (recreated undecided, counted pending) — not governed by the summary decision" || no "$how: A not drafted: $dd_out"
done

# =============================================================================
echo "== A10. retire only AFTER the new home was written; hand-edited / vanished drafts kept =="
# own → summary, the summary write refused (planted symlink at the slot)
fx rt1; sup 1 "[$(mv_ MEDIUM)]"; drafts; OD="$(draft_with mover)"
printf 'ORIGINAL\n' > "$TOP/outside-rt1.md"; ln -s "$TOP/outside-rt1.md" "$PROP/$SB.md"
sup 1 "[$(mv_ LOW)]"; drafts
[ -f "$OD" ] && grep -qxF -- "- **Decision:** undecided" "$OD" && ok "summary write refused ⇒ the own draft is NOT retired (the finding keeps a draft)" || no "rt1: own draft lost: $dd_out"
case "$dd_out" in *"refused $SB.md"*"kept $(basename "$OD") — the new draft for its finding was not written"*) ok "rt1: refused + kept lines, in that order" ;; *) no "rt1 out: $dd_out" ;; esac
[ -z "$(led | awk -F'\t' '$2 == "moved"')" ] && [ "$(cat "$TOP/outside-rt1.md")" = "ORIGINAL" ] && ok "rt1: no moved row, the symlink target untouched" || no "rt1 ledger: $(led)"
rm -f "$PROP/$SB.md"; drafts
[ ! -e "$OD" ] && grep -qxF -- "> mover" "$PROP/$SB.md" && ok "rt1: once the slot is writable, the move completes (summary written, own draft retired)" || no "rt1 recovery: $dd_out"
# summary → own, the own write refused (planted symlink at the own name)
fx rt2; sup 1 "[$(mv_ LOW)]"; drafts
ON="$PROP/$NS--dismissed-$(h8of phase_4_5 code_reviewer mover).md"
printf 'ORIGINAL\n' > "$TOP/outside-rt2.md"; ln -s "$TOP/outside-rt2.md" "$ON"
sup 1 "[$(mv_ MEDIUM)]"; drafts
[ -f "$PROP/$SB.md" ] && grep -qxF -- "> mover" "$PROP/$SB.md" && [ -z "$(led | awk -F'\t' '$2 == "moved"')" ] && [ "$(cat "$TOP/outside-rt2.md")" = "ORIGINAL" ] \
  && ok "rt2: own write refused ⇒ the undecided summary is NOT retired, no moved row" || no "rt2: $dd_out"
# a hand-edited (decided on disk, no ledger row) own draft is kept, reported
fx rt3; sup 1 "[$(mv_ MEDIUM)]"; drafts; OD="$(draft_with mover)"
awk '/^- \*\*Decision:\*\* /{ print "- **Decision:** follow-up (by hand)"; next } { print }' "$OD" > "$OD.tmp" && mv "$OD.tmp" "$OD"; c0="$(cksum < "$OD")"
sup 1 "[$(mv_ LOW)]"; drafts
[ -f "$OD" ] && [ "$(cksum < "$OD")" = "$c0" ] && ok "rt3: a hand-edited decided own draft is kept byte-identical" || no "rt3: $dd_out"
case "$dd_out" in *"kept $(basename "$OD") — its on-disk Decision is not undecided"*) ok "rt3: reported with a kept line" ;; *) no "rt3 out: $dd_out" ;; esac
[ -z "$(led | awk -F'\t' '$2 == "moved"')" ] && ok "rt3: no moved row" || no "rt3 ledger: $(led)"
# an undecided summary listing an entry that VANISHED from the sidecars is not retired
fx rt4; sup 1 "[$(mv_ LOW), {finding: \"vanisher\", reason: nit, source: code_reviewer, severity: LOW}]"; drafts
sup 1 "[$(mv_ MEDIUM)]"; drafts
[ -f "$PROP/$SB.md" ] && grep -qxF -- "> vanisher" "$PROP/$SB.md" && [ -n "$(draft_with mover)" ] && ok "rt4: a summary listing a vanished entry stays (its only record) — asked about, never lost" || no "rt4: $dd_out"

# =============================================================================
echo "== A6. fail-safe exits, no gh / git commit / git push, pc_guarded_write load-bearing =="
fx 8
sup 1 '[{finding: "fine one", reason: below_severity_floor, source: code_reviewer, severity: HIGH}]'
printf '## REVIEW_HEAL_RESULT\n- rounds: 1\n- dismissed: [{finding: "x"\n' > "$AD/$RUN_ID.review-heal-result.md"
drafts
[ "$dd_rc" -eq 0 ] && case "$dd_out" in *"dismissed-drafts: unreadable $AD/$RUN_ID.review-heal-result.md"*) true ;; *) false ;; esac && ok "unparseable sidecar ⇒ 'unreadable <path>' line, exit 0" || no "unparseable: rc=$dd_rc $dd_out"
[ -n "$(draft_with 'fine one')" ] && ok "the readable sidecar is still drafted" || no "readable sidecar dropped"
out="$(bash "$H" dismissed-drafts "$TOP/nope.md" "$ITEM" "$PRURL")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "dismissed-drafts: skipped — run file not found" ] && ok "missing run file ⇒ one skipped line, exit 0" || no "missing run file: $rc $out"
mkdir -p "$TOP/norepo"; cp "$RF" "$TOP/norepo/x.md"
out="$(GIT_CEILING_DIRECTORIES="$TOP" bash "$H" dismissed-drafts "$TOP/norepo/x.md" "$ITEM" "$PRURL")"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "dismissed-drafts: skipped — repo root not found" ] && ok "no repo ⇒ 'repo root not found', exit 0" || no "no repo: $rc $out"
if [ "$(id -u)" != "0" ]; then
  fx 9; sup 1 '[{finding: "cannot write me", reason: pre_existing, source: code_reviewer}]'
  mkdir -p "$PROP"; chmod 555 "$PROP"; drafts; chmod 755 "$PROP"
  [ "$dd_rc" -eq 0 ] && [ "$(nfiles)" = "0" ] && case "$dd_out" in *"dismissed-drafts: refused $NS--dismissed-"*"dismissed-drafts: 0 per-finding + 0 summary (0 listed in summary)") true ;; *) false ;; esac \
    && ok "unwritable proposed/ ⇒ refused line, 0 written, exit 0" || no "unwritable: rc=$dd_rc $dd_out"
  o="$(bash "$H" dismissed-decide "$RF" "$PROP/x" drop)"; [ $? -eq 0 ] && ok "decide never exits non-zero ($o)" || no "decide rc"
else
  ok "unwritable-dir leg skipped (running as root)"
fi
[ ! -e "$TOP/gh-called" ] && ok "gh was never invoked by any subcommand" || no "gh invoked: $(cat "$TOP/gh-called")"
if grep -qE '^(commit|push)( |$)|(^| )(commit|push) ' "$TOP/git.log" 2>/dev/null; then no "git commit/push invoked: $(grep -E 'commit|push' "$TOP/git.log")"; else ok "no git commit / git push (git used only for rev-parse: $(grep -c 'rev-parse --show-toplevel' "$TOP/git.log" 2>/dev/null) call(s))"; fi

# ---- pc_guarded_write mutation control --------------------------------------
# Draft names are built from basenames + hex (run_id, item stem, item-path hash, h8), so a `/` can
# never reach the guard; the two inputs the guard alone refuses are a dot-leading
# name (a run file named `.evil.md`) and a planted SYMLINK at a draft's name.
# Both legs must be green against the real propose-common.sh and turn RED when
# PROPOSE_COMMON_SH points at a copy with the marked guard block deleted.
MUT="$TOP/mutant-common.sh"
sed '/>>> WRITE-PATH GUARD/,/<<< END WRITE-PATH GUARD/d' "$HERE/propose-common.sh" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$MUT" "$HERE/propose-common.sh" && bash -n "$MUT"; then
  ok "built a valid guard-deleted mutant of propose-common.sh"
  guard_legs() { # <label> [<common>] — sets G_DOT (1 = escaped) and G_LINK (1 = replaced)
    local c="${2:-}"
    fx "g$1" ".evil"
    sup 1 '[{finding: "dot name", reason: pre_existing, source: code_reviewer}]'
    if [ -n "$c" ]; then PROPOSE_COMMON_SH="$c" bash "$H" dismissed-drafts "$RF" "$ITEM" "$PRURL" >/dev/null 2>&1
    else bash "$H" dismissed-drafts "$RF" "$ITEM" "$PRURL" >/dev/null 2>&1; fi
    G_DOT=0; [ "$(find "$PROP" -maxdepth 1 -name '.evil--*' 2>/dev/null | wc -l | tr -d ' ')" != "0" ] && G_DOT=1
    fx "l$1"
    sup 1 '[{finding: "link name", reason: pre_existing, source: code_reviewer}]'
    drafts; local lp; lp="$(path_of 1)"; rm -f "$lp"
    printf 'ORIGINAL\n' > "$TOP/outside-$1.md"; ln -s "$TOP/outside-$1.md" "$lp"
    if [ -n "$c" ]; then PROPOSE_COMMON_SH="$c" bash "$H" dismissed-drafts "$RF" "$ITEM" "$PRURL" >/dev/null 2>&1
    else bash "$H" dismissed-drafts "$RF" "$ITEM" "$PRURL" >/dev/null 2>&1; fi
    G_LINK=0; [ ! -L "$lp" ] && G_LINK=1
    [ "$(cat "$TOP/outside-$1.md")" = "ORIGINAL" ] || G_LINK=2
  }
  guard_legs real
  [ "$G_DOT" = 0 ] && ok "real guard: a dot-leading draft name is refused" || no "real guard let a dot name through"
  [ "$G_LINK" = 0 ] && ok "real guard: a planted symlink at a draft name is refused and left in place" || no "real guard: symlink leg G_LINK=$G_LINK"
  guard_legs mut "$MUT"
  [ "$G_DOT" = 1 ] && ok "MUTATION CONTROL: without the guard the dot name is written (dot leg turns red)" || no "mutant still refused the dot name — control uncontrolled"
  [ "$G_LINK" = 1 ] && ok "MUTATION CONTROL: without the guard the planted symlink is replaced (symlink leg turns red)" || no "mutant symlink leg G_LINK=$G_LINK — control uncontrolled"
else
  no "could not build the guard-deleted mutant"
fi

# ---- B. SKILL-text legs (Part B prose) ---------------------------------------
REPO="$(cd "$HERE/../.." && pwd)"
SK="$REPO/loomwright/skills/automate-loop/SKILL.md"
RS="$REPO/loomwright/docs/RESULT_SCHEMAS.md"
QUAL="at most one owner-requested fix-now re-drain per item"
SUBH="### Dismissed-findings decision step (before the park)"
# first_line <file> <fixed anchor> — the first line containing the anchor (empty if none)
first_line() { grep -F -m1 -- "$2" "$1" 2>/dev/null || true; }
# ln_of <file> <fixed anchor> — its line number (0 if none)
ln_of() { local n; n="$(grep -nF -m1 -- "$2" "$1" 2>/dev/null)"; n="${n%%:*}"; echo "${n:-0}"; }
# before <line> <a> <b> — a occurs in line, and before b (which also occurs)
before() {
  case "$1" in *"$2"*) ;; *) return 1 ;; esac
  case "$1" in *"$3"*) ;; *) return 1 ;; esac
  local pa="${1%%"$2"*}" pb="${1%%"$3"*}"
  [ "${#pa}" -lt "${#pb}" ]
}
sub_body() { awk -v h="$SUBH" '$0 == h { f = 1; next } f && /^### / { exit } f { print }' "$SK"; }
SUBF="$TOP/subsection.md"; sub_body > "$SUBF"

grep -qxF -- "$SUBH" "$SK" && ok "B: SKILL carries the subsection heading" || no "B: SKILL lacks '$SUBH'"
s_ask="$(ln_of "$SUBF" "2. **Interactive**")"; s_park="$(ln_of "$SUBF" "4. Only then write the park state")"
[ "$s_ask" -gt 0 ] && [ "$s_park" -gt "$s_ask" ] && ok "B: the ask (step 2) precedes the park write (step 4) in the subsection" || no "B: subsection order ask=$s_ask park=$s_park"
L="$(first_line "$SUBF" "4. Only then write the park state")"
before "$L" "Only then write the park state" "merge-watcher arming" && ok "B: the watcher is armed only after the park write" || no "B: step 4 does not order park write before watcher arm"
L="$(first_line "$SK" "4. **GATE**")"
before "$L" "Dismissed-findings decision step (before the park)" "merge watcher is armed" && ok "B: GATE step 4 runs the decision step before any park/watcher" || no "B: GATE step 4 lacks the before-park decision step"
L="$(first_line "$SK" "**Safe mode (default):**")"
before "$L" "Dismissed-findings decision step (before the park)" "arm the merge watcher" && ok "B: §9 safe-mode park runs the decision step before arming the watcher" || no "B: §9 safe-mode bullet order"
L="$(first_line "$SK" "otherwise fail **CLOSED** → park + notify")"
case "$L" in *"Dismissed-findings decision step (before the park)"*) ok "B: §9 fail-closed --auto-merge park runs the decision step" ;; *) no "B: §9 --auto-merge park lacks the decision step" ;; esac
L="$(first_line "$SK" "**\`ESCALATED\` never merges and PARKS the run**")"
before "$L" "Dismissed-findings decision step (before the park)" "## Status: paused" && ok "B: §9 escalated park runs the decision step before the park write" || no "B: §9 escalated bullet order"
L="$(first_line "$SUBF" "**Under \`--non-interactive-fallback\`**")"
case "$L" in *"asks nothing"*"pending_decisions"*) ok "B: --non-interactive-fallback asks nothing and records pending_decisions" ;; *) no "B: non-interactive sentence missing" ;; esac
L="$(first_line "$SK" "**PICK-time pending-decisions ask")"
case "$L" in *"BEFORE RECONCILE's \`closeout\`"*"**Follow-up (keep draft)** / **Drop** ONLY"*"fix-now is offered only at the park"*) ok "B: PICK ask precedes RECONCILE's closeout, Follow-up / Drop only" ;; *) no "B: PICK-time ask paragraph wrong" ;; esac
case "$L" in *"Fix now on this PR"*) no "B: PICK ask must never offer Fix now" ;; *) ok "B: PICK ask offers no Fix-now option" ;; esac
p_ask="$(ln_of "$SK" "**PICK-time pending-decisions ask")"; p_rec="$(ln_of "$SK" "1. **RECONCILE**")"; p_run="$(ln_of "$SK" "2. **RUN**")"
[ "$p_ask" -gt "$p_rec" ] && [ "$p_ask" -lt "$p_run" ] && ok "B: the PICK ask sits inside §6 step 1 (PICK), before RUN" || no "B: PICK ask placement rec=$p_rec ask=$p_ask run=$p_run"
for want in "at most ONCE per item" "2 × \`--max-rounds\`" "FIRST drain only" "a re-drain \`ESCALATED\` turns the park into \`escalated\`" "undecided (fix-now unconfirmed)" "This is drain-origin ONLY" "\`--after-fix-now\`" "EXTERNAL_TEXT envelope"; do
  grep -qF -- "$want" "$SUBF" && ok "B: subsection states: $want" || no "B: subsection lacks: $want"
done
# single-drain qualifier, per restating surface (targeted — the unrelated "exactly ONE line/executor" claims stay)
while IFS='|' read -r f anchor; do
  L="$(first_line "$REPO/$f" "$anchor")"
  if [ -z "$L" ]; then no "B: single-drain anchor not found in $f: $anchor"
  else case "$L" in *"$QUAL"*) ok "B: single-drain qualifier on $f ($anchor)" ;; *) no "B: unqualified single-drain claim in $f ($anchor)" ;; esac; fi
done <<'SURF'
loomwright/skills/automate-loop/SKILL.md|3. **DRAIN** — own **exactly ONE** inline
loomwright/skills/automate-loop/SKILL.md|suppresses the default dispatch and owns exactly ONE inline drain
loomwright/skills/automate-loop/SKILL.md|After suppression, DRAIN owns **exactly ONE** inline
loomwright/skills/automate-loop/SKILL.md|- **Double until-mergeable drain.**
loomwright/skills/automate-loop/SKILL.md|- Single drain: `.auto_review:false` set before
loomwright/docs/RESULT_SCHEMAS.md|| `suppressed_default_dispatch` | `true` |
loomwright/commands/automate.md|4. **Per-item loop.**
README.md|- **Single drain, single open PR:**
CLAUDE.md|**`/automate` single-drain ownership
SURF
unq=0
for f in loomwright/skills/automate-loop/SKILL.md loomwright/docs/RESULT_SCHEMAS.md loomwright/commands/automate.md README.md CLAUDE.md; do
  while IFS= read -r L; do
    case "$L" in *"$QUAL"*) ;; *) unq=$((unq+1)); echo "    unqualified: $f: ${L:0:120}" ;; esac
  done <<EOF2
$(grep -E 'exactly ONE\*\* inline|exactly ONE inline|ONE owned inline|ONE inline `/review-pr' "$REPO/$f" 2>/dev/null)
EOF2
done
[ "$unq" -eq 0 ] && ok "B: no drain-ownership line on any restating surface lacks the qualifier" || no "B: $unq unqualified drain-ownership line(s)"
# optional severity: schema + three producers
n="$(grep -cF 'severity?: string}]' "$RS" 2>/dev/null)"; [ "${n:-0}" -ge 2 ] && ok "B: RESULT_SCHEMAS field lines carry optional severity (heal_dismissed + dismissed)" || no "B: RESULT_SCHEMAS severity field lines: ${n:-0}"
grep -qF '`[{finding, reason, source, severity?}]`' "$RS" && ok "B: REVIEW_HEAL_RESULT table row carries severity?" || no "B: dismissed table row lacks severity?"
grep -qF 'severity: i.severity' "$REPO/loomwright/skills/self-heal-advisory/SKILL.md" && ok "B: self-heal-advisory Part 2 producer carries severity" || no "B: self-heal-advisory producer lacks severity"
grep -qF '({severity: stated_severity(f)} if stated_severity(f) else {})' "$REPO/loomwright/skills/review-heal/SKILL.md" && ok "B: review-heal §U3.5 main pass carries severity only when stated" || no "B: review-heal main pass severity"
grep -qF 'severity: f.severity}' "$REPO/loomwright/skills/review-heal/SKILL.md" && ok "B: review-heal Earned Fallback pass carries f.severity" || no "B: review-heal fallback severity"
grep -qF -- '- **<finding>** — <reason> (<source>)' "$REPO/loomwright/skills/review-heal/SKILL.md" && ok "B: marker-comment bullet format unchanged" || no "B: marker-comment bullet format changed"
# §1.5 rows, §3 + AUTOMATE_RUN ## Current line
for sc in dismissed-drafts dismissed-decide dismissed-pending; do
  grep -qF "| \`$sc\` |" "$SK" && ok "B: §1.5 row for $sc" || no "B: §1.5 lacks a $sc row"
done
grep -qF -- '- pending_decisions: <n> | fix_now_reentered: <true|false>' "$SK" && ok "B: §3 template carries the pending_decisions line" || no "B: §3 template lacks pending_decisions"
grep -qF -- '- pending_decisions: <n> | fix_now_reentered: <true|false>' "$RS" && ok "B: AUTOMATE_RUN template carries the pending_decisions line" || no "B: AUTOMATE_RUN lacks pending_decisions"
# proposed/ README: the generator template and the committed file are byte-identical
PW="$REPO/loomwright/scripts/propose-work.sh"
awk "/^printf '%s\\\\n' \\\\\$/{f=1} f{print} /guarded_write \"README.md\"/{exit}" "$PW" | sed '$d' | sed '$s/ \\$//' > "$TOP/readme-tpl.sh"
bash "$TOP/readme-tpl.sh" > "$TOP/readme-gen.md" 2>/dev/null
# Compared against a frozen fixture copy, not the live proposed/README.md: the live file is run
# history and is absent in a branch-mode repo (skills/automate-loop/SKILL.md §"Branch mode").
if [ -s "$TOP/readme-gen.md" ] && cmp -s "$TOP/readme-gen.md" "$REPO/loomwright/scripts/fixtures/proposed-readme/README.md"; then
  ok "B: committed proposed/README.md == propose-work.sh template, byte for byte"
else no "B: proposed/README.md differs from the propose-work.sh template"; fi
grep -qF -- '--dismissed-*.md` drafts for dismissed review findings' "$TOP/readme-gen.md" && ok "B: README template names the second writer" || no "B: README template lacks the second writer"

echo "== A11. ## Depends on / ## Touches sections (parallel-automate/10): lint-clean, identity-stable =="
fx 11
mkdir -p "$R/src"; : > "$R/src/real.sh"; : > "$R/README.md"
sup 1 '[{finding: "bug in src/real.sh and src/gone.sh; also /etc/passwd, ../x.sh and a//b.sh", reason: below_severity_floor, source: "src/real.sh:12", severity: HIGH}, {finding: "plain prose only, no file", reason: below_severity_floor, source: code_reviewer, severity: MEDIUM}, {finding: "low in README.md.", reason: nit, source: red_team, severity: LOW}, {finding: "another low", reason: nit, source: red_team, severity: LOW}]'
drafts
F1="$(draft_with "bug in src/real.sh")"; F2="$(draft_with "plain prose only")"; FS="$(draft_with "low in README.md.")"
between() { awk '/^- \*\*Decision:\*\* /{p=1; next} /^## Findings? \(verbatim/{exit} p' "$1"; }
if [ -n "$F1" ] && [ "$(between "$F1")" = "$(printf '\n## Depends on\nnone\n\n## Touches\nsrc/real.sh\n')" ]; then
  ok "A11 per-finding: Depends on none + Touches = the existing named file only (src/gone.sh absent; /etc/passwd, ../x.sh, a//b.sh refused), before ## Finding"
else no "A11 per-finding sections: $(between "${F1:-/dev/null}" | tr '\n' '|')"; fi
[ -n "$F2" ] && [ "$(between "$F2")" = "$(printf '\n## Depends on\nnone\n\n## Touches\nunknown\n')" ] && ok "A11 per-finding naming no file: Touches unknown" || no "A11 no-file sections: $(between "${F2:-/dev/null}" | tr '\n' '|')"
case "$FS" in *--dismissed-summary.md) ok "A11 the LOW nits landed in the summary draft" ;; *) no "A11 summary draft not found: '$FS'" ;; esac
[ -n "$FS" ] && [ "$(between "$FS")" = "$(printf '\n## Depends on\nnone\n\n## Touches\nREADME.md\n')" ] && ok "A11 summary: Touches = union of the listed entries' existing paths, before ## Findings" || no "A11 summary sections: $(between "${FS:-/dev/null}" | tr '\n' '|')"
bad=""
for f in "$F1" "$F2" "$FS"; do
  [ -n "$f" ] || { bad="$bad [missing draft]"; continue; }
  lo="$(bash "$H" plan-waves "$f" --lint --root "$R" 2>/dev/null)"; lrc=$?
  case "$(printf '%s\n' "$lo" | head -n1)" in
    *": Touches ok; Depends on ok"|*": Touches ok (declared unknown); Depends on ok") [ "$lrc" -eq 0 ] || bad="$bad [$(basename "$f") rc=$lrc]" ;;
    *) bad="$bad [$(basename "$f"): $(printf '%s' "$lo" | head -n1)]" ;;
  esac
done
[ -z "$bad" ] && ok "A11 plan-waves --lint reports every draft (per-finding and summary) ok / ok (declared unknown), exit 0" || no "A11 lint:$bad"
# Identity: the sections never feed the name or a decision. Decide follow-up on F1, then remove the
# files both drafts name and re-run: F1 is KEPT under the same name with the same decision; the
# undecided summary is rewritten under the SAME name (Touches now unknown); no draft is added or lost.
LEDGER="$AD/$RUN_ID.dismissed-decisions"
bash "$H" dismissed-decide "$RF" "$F1" follow-up >/dev/null 2>&1
n_before="$(nfiles)"; led_before="$(cat "$LEDGER" 2>/dev/null)"; f1_before="$(cksum < "$F1")"
rm -f "$R/src/real.sh" "$R/README.md"
drafts
[ "$(nfiles)" = "$n_before" ] && [ -f "$F1" ] && [ -f "$FS" ] && ok "A11 named files removed ⇒ same draft names, none added or lost ($n_before)" || no "A11 names changed: $(ls "$PROP")"
[ "$(cat "$LEDGER" 2>/dev/null)" = "$led_before" ] && [ "$(awk -F'\t' -v n="$(basename "$F1")" '$1 == n { d = $2 } END { print d }' "$LEDGER")" = follow-up ] \
  && ok "A11 ledger untouched and F1's decision still follow-up after the re-render" || no "A11 ledger changed: $(tr '\n' '|' < "$LEDGER")"
[ "$(cksum < "$F1")" = "$f1_before" ] && ok "A11 a decided (follow-up) draft is kept byte-for-byte, never re-rendered" || no "A11 follow-up draft rewritten"
grep -qxF 'unknown' "$FS" && ! grep -qxF 'README.md' "$FS" && ok "A11 the undecided summary re-renders Touches unknown under the same name" || no "A11 summary not re-rendered: $(between "$FS" | tr '\n' '|')"

echo "== A12. Touches containment: symlinks and .git never reach Touches (mirrors test-propose-from-verify.sh) =="
# touches_of's CONTAINMENT rule (extractor-only — the planner's --lint grammar is unaffected, so the
# test-automate-helpers.sh X7 drift test does not cover it; this section and the matching one in
# test-propose-from-verify.sh do, with the same fixture set). Decision under test for an in-repo
# symlink: a symlinked DIRECTORY resolving inside the root is accepted as written (indir/app.ts); a
# symlinked FILE is rejected wherever it points, inside (inlink.ts) or outside (flink.txt).
fx 12
OUTSIDE12="$TOP/outside12"; mkdir -p "$OUTSIDE12" "$R/src"; : > "$OUTSIDE12/secret.txt"; : > "$R/src/app.ts"
ln -s "$OUTSIDE12" "$R/lnk"; ln -s "$OUTSIDE12/secret.txt" "$R/flink.txt"
ln -s src/app.ts "$R/inlink.ts"; ln -s src "$R/indir"
"$REAL_GIT" -C "$R" add lnk flink.txt inlink.ts indir src/app.ts >/dev/null 2>&1
sup 1 '[{finding: "bug: src/app.ts lnk/secret.txt flink.txt inlink.ts indir/app.ts .git/config .GIT/config .git/HEAD", reason: below_severity_floor, source: code_reviewer, severity: HIGH}]'
drafts
F12="$(draft_with "bug: src/app.ts")"
T12="$(awk '/^## Touches$/{p=1; next} p && /^## /{exit} p && NF' "${F12:-/dev/null}")"
t12_has() { grep -qxF -- "$1" <<<"$T12"; }
[ -n "$F12" ] || no "A12 draft not written: $dd_out"
t12_has src/app.ts && ok "A12 containment (e): a normal existing path is still accepted" || no "A12 normal path dropped: Touches '$T12'"
! t12_has lnk/secret.txt && ok "A12 containment (a): a file under a symlink to an OUTSIDE dir is rejected" || no "A12 containment (a): lnk/secret.txt leaked into Touches: '$T12'"
! t12_has flink.txt && ok "A12 containment (b): a symlinked FILE pointing outside is rejected" || no "A12 containment (b): flink.txt leaked into Touches: '$T12'"
! t12_has inlink.ts && t12_has indir/app.ts && ok "A12 containment (c): in-repo symlinked file rejected, in-repo symlinked dir accepted as written" || no "A12 containment (c): in-repo symlink handling: '$T12'"
! t12_has .git/config && ! t12_has .GIT/config && ! t12_has .git/HEAD && ok "A12 containment (d): .git/ paths are rejected (any case)" || no "A12 containment (d): .git path leaked into Touches: '$T12'"
[ "$T12" = "$(printf 'indir/app.ts\nsrc/app.ts')" ] && ok "A12 Touches is exactly the two contained paths" || no "A12 Touches set: '$(tr '\n' '|' <<<"$T12")'"

echo
echo "test-automate-dismissed: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
