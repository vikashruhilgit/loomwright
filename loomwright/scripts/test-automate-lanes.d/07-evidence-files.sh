declare -F tal_pgrep >/dev/null && [ -n "${T:-}" ] && [ -d "$T" ] || { echo "${BASH_SOURCE[0]##*/}: run via test-automate-lanes.sh, never standalone (its kills need the suite's \$T)" >&2; exit 2; }
# ---- EV: the Validation reader's evidence files (automate-lanes.d/evidence.sh) --------------------------------
# A step the PR body leaves NOT-RUN is looked up in the docs/evidence/*.md files the PR adds or changes; only a
# declared `Verdict: <PASS|FAIL|NOT-RUN> for Validation <n>` line (column 0, outside a fence) counts. Every leg
# runs validation-gate (or lane-readiness) against its own `gh` stub, $T/ev-gh, through LOOMWRIGHT_GH_BIN:
#   pr view <pr> --json body | body,headRefOid   the body in $EV_BODY
#   pr view <pr> --json headRefOid,files         the changed paths in $EV_CHANGED, head $EV_SHA
#   api repos/o/r/contents/docs/evidence?ref=$EV_SHA   the listing of $EV_TREE/docs/evidence/
#   api -H 'Accept: application/vnd.github.raw' repos/o/r/contents/<path>?ref=$EV_SHA   the file's text
# Any other call (another ref included) exits 1. EV_FAIL=view|list|read makes that call fail. Every call is
# logged to $EV_CALLS. Groups: EV1 AC1 · EV2 AC2 · EV3 AC3 · EV4 AC4 · EV5 AC5 · EV6 AC6 · EV7 AC7 · EV8 AC8 ·
# EV9 AC9 · EV10 AC10 · EV11 AC11 · EV12 no file lookup where none belongs · EV13 the brief's Pin mutations
# (each one-line mutant built from $SB, gated: anchor once, non-empty, differs, bash -n).
EV="$T/ev7"; EVT="$T/ev7-tree"; mkdir -p "$EV/.supervisor/automate" "$EV/reqs" "$EVT/docs/evidence"
EVRF="$EV/.supervisor/automate/ev.md"; EVPR=https://github.com/o/r/pull/7
export EV_SHA=0123456789abcdef0123456789abcdef01234567 EV_CALLS="$T/ev.calls" EV_CHANGED="$T/ev.changed" EV_BODY="$T/ev.body" EV_TREE="$EVT"
printf '# Automate Run: ev\n## Status: running\n\n## Current\n- item: reqs/one.md | status: running | pr: %s | branch: f\n- pause_reason: null\n\n## Progress\n- 2026-11-03T09:00:00Z picked reqs/one.md\n' "$EVPR" > "$EVRF"
printf '# one\n## Validation (must pass before merge)\n1. **Baseline:** the suite on base and branch.\n2. **Running system:** run it for real.\n## Notes\n' > "$EV/reqs/one.md"
printf '# two\n## Validation (must pass before merge)\n1. **Baseline:** the suite.\n2. **Running system — load:** three clones.\n3. **Running system — merge:** one real merge.\n' > "$EV/reqs/two.md"
printf '# dup\n## Validation\n1. **Running system:** a.\n1. **Running system — again:** b.\n' > "$EV/reqs/dup.md"
printf '# static\n## Validation\n1. **Baseline:** the suite.\n' > "$EV/reqs/static.md"
cat > "$T/ev-gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*" >> "$EV_CALLS"
if [ "$1 $2" = "pr view" ]; then
  case "$*" in
    *"--json headRefOid,files") [ "${EV_FAIL:-}" = view ] && exit 1
      jq -n --rawfile c "$EV_CHANGED" --arg s "$EV_SHA" '{headRefOid: $s, files: [$c | split("\n")[] | select(. != "") | {path: ., additions: 1, deletions: 0}]}' ;;
    *"--json body,headRefOid") jq -n --rawfile b "$EV_BODY" --arg s "$EV_SHA" '{body: $b, headRefOid: $s}' ;;
    *"--json body") jq -n --rawfile b "$EV_BODY" '{body: $b}' ;;
    *) exit 1 ;;
  esac
  exit 0
fi
[ "$1" = api ] || exit 1
if [ "$2" = -H ]; then
  [ "${EV_FAIL:-}" = read ] && exit 1
  [ "$3" = "Accept: application/vnd.github.raw" ] || exit 1
  case "$4" in "repos/o/r/contents/"*"?ref=$EV_SHA") ;; *) exit 1 ;; esac
  p="${4#repos/o/r/contents/}"; p="${p%%\?*}"; [ -f "$EV_TREE/$p" ] || exit 1; cat "$EV_TREE/$p"; exit 0
fi
[ "${EV_FAIL:-}" = list ] && exit 1
[ "$2" = "repos/o/r/contents/docs/evidence?ref=$EV_SHA" ] || exit 1
for f in "$EV_TREE"/docs/evidence/*; do
  [ -e "$f" ] || continue; t=file; [ -d "$f" ] && t=dir
  jq -n --arg n "${f##*/}" --arg t "$t" '{name: $n, path: ("docs/evidence/" + $n), type: $t}'
done | jq -s .
EOF
chmod +x "$T/ev-gh"
# ev_set <body> <changed paths (space-separated)> [<file>=<text> …] — one leg's PR: its body, its changed-file
# list and the docs/evidence/ tree at its head (printf-escaped texts); the call log emptied.
ev_set() {
  local kv; printf "$1" > "$EV_BODY"; printf '%s\n' $2 > "$EV_CHANGED"; shift 2
  rm -rf "$EVT/docs/evidence"; mkdir -p "$EVT/docs/evidence"
  for kv in "$@"; do printf "${kv#*=}" > "$EVT/docs/evidence/${kv%%=*}"; done
  : > "$EV_CALLS"
}
ev() { LOOMWRIGHT_GH_BIN="$T/ev-gh" LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" bash "${EV_S:-$S}" validation-gate "$EVRF" "${1:-reqs/one.md}" "${2-$EVPR}" 2>&1; }
ev_rows() { ( export LOOMWRIGHT_GH_BIN="$T/ev-gh"; . "${EV_S:-$S}"; d="$(mktemp -d)"; _lanes_validation_rows "$EV/$1" "$EV_BODY" 1 "$EVPR" "$d/ev"; rm -rf "$d" ) 2>/dev/null | cut -f1,4,5; }
EVFIX=' — add `Verdict: PASS for Validation 2` and the fenced output to the step'"'"'s docs/evidence/ file in this PR'
EVOK='# Evidence (Validation 2)\n\nVerdict: PASS for Validation 2\n\n```\n$ run it\npassed: 3 failed: 0\n```\n'
EVSHA7="${EV_SHA:0:7}"
check "EV0 fixture: the stub answers the changed-file list" \
  "$(ev_set '' 'docs/evidence/x.md'; LOOMWRIGHT_GH_BIN="$T/ev-gh" "$T/ev-gh" pr view "$EVPR" --json headRefOid,files | jq -c '[.headRefOid, [.files[].path]]')" "[\"$EV_SHA\",[\"docs/evidence/x.md\"]]"

# EV1 AC1: a declared PASS + fenced output in a file the PR changes ⇒ ok, naming the file.
EV1_WANT="validation-gate: ok — 1 running-system step(s) evidenced (V2 in docs/evidence/x.md)"
ev_set '## Summary\nNothing pasted here.\n' 'docs/evidence/x.md src/a.sh' "x.md=$EVOK"
out="$(ev)"; rc=$?
check "EV1 AC1 declared PASS + fenced output in a changed docs/evidence/ file ⇒ ok naming the file, exit 0" "$rc|$out" "0|$EV1_WANT"
check "EV1b … read at the PR head: the listing and the raw read carry ?ref=<headRefOid>, once each" \
  "$(grep -c "?ref=$EV_SHA\$" "$EV_CALLS" | tr -d ' '):$(grep -c 'vnd.github.raw repos/o/r/contents/docs/evidence/x.md' "$EV_CALLS" | tr -d ' ')" "2:1"
check "EV1c an ok with no file-evidenced step prints exactly today's line" \
  "$(ev_set 'Validation 1\n```\nok\n```\nValidation 2\n```\nran\n```\n' 'docs/evidence/x.md' "x.md=$EVOK"; ev)" "validation-gate: ok — 1 running-system step(s) evidenced"

# EV2 AC2: the declared verdict outranks the words in the output (a fixture expected to FAIL).
EVFAILOUT='# Evidence\n\nVerdict: PASS for Validation 2\n\n```\ndecision: FAIL\nFAIL - leg x (expected)\n```\n'
ev_set '' 'docs/evidence/x.md' "x.md=$EVFAILOUT"
check "EV2 AC2 FAIL inside the fenced output, declared PASS ⇒ still evidenced" "$(ev)" "$EV1_WANT"

# EV3 AC3: a step the PR body evidences is decided by the body alone — byte-identical, no extra gh call.
ev_set 'Validation 1\n```\npassed: 5\n```\nValidation 2 — run for real:\n```\npeak load 3.1\n```\n' 'docs/evidence/x.md' \
  "x.md=# E\n\nVerdict: FAIL for Validation 2\n\n\`\`\`\nx\n\`\`\`\n"
out="$(ev)"
check "EV3 AC3 body-evidenced step ⇒ today's ok line, byte for byte" "$out" "validation-gate: ok — 1 running-system step(s) evidenced"
check "EV3b … and the evidence files cost no gh call (only the body read)" "$(cat "$EV_CALLS")" "gh pr view $EVPR --json body"
ev_set 'Validation 1\n```\npassed: 5\n```\nValidation 2\n```\nFAIL - the load test\n```\n' 'docs/evidence/x.md' "x.md=$EVOK"
check "EV3c a body FAIL is final: a file declaring PASS never overrides it, and is never fetched" \
  "$(ev)|$(grep -c 'headRefOid,files' "$EV_CALLS" | tr -d ' ')" "validation-gate: unrun — V2 Running system: pasted output shows FAIL|0"

# EV4 AC4: lane-readiness reads the same rows (the one shared reader) — result and evidence source match.
EVP=automate-2026-11-03-090000; EVL="$T/ev7-lanes/$EVP/L1"; mkdir -p "$EVL/.supervisor/automate" "$EVL/reqs" "$T/ev7-primary"
jq -n --arg p "$T/ev7-primary" --arg r "$EVP" '{lane: "L1", run_id: ($r + "-L1"), parent_run_id: $r, primary: $p}' > "$EVL/.supervisor/lane.json"
printf -- '- [ ] reqs/one.md\n' > "$EVL/.supervisor/lane-backlog.md"; cp "$EV/reqs/one.md" "$EVL/reqs/one.md"
printf '# Automate Run: %s-L1\n\n## Current\n- item: reqs/one.md | status: awaiting_merge | pr: %s | branch: f\n- pause_reason: ready_for_release\n\n## Progress\n- 2026-11-03T09:00:00Z picked reqs/one.md\n' "$EVP" "$EVPR" > "$EVL/.supervisor/automate/$EVP-L1.md"
EVRD="$EVL/.supervisor/automate/$EVP-L1.merge-readiness.md"
ev_rd() { LOOMWRIGHT_GH_BIN="$T/ev-gh" bash "${EV_S:-$S}" lane-readiness "$EVL" >/dev/null 2>&1; grep '^  - V2 ' "$EVRD" 2>/dev/null; }
ev_set '' 'docs/evidence/x.md' "x.md=$EVOK"
rd="$(ev_rd)"; gv="$(ev)"
check "EV4 AC4 lane-readiness's V2 row: PASS, the evidence file named" "$rd" "  - V2 Running system: PASS — declared PASS with fenced output in docs/evidence/x.md"
check "EV4b … the same step and file validation-gate names" "${gv##*(}" "V2 in ${rd##* in })"
ev_set '' 'docs/evidence/x.md' "x.md=# E\n\nVerdict: NOT-RUN for Validation 2\n\n\`\`\`\nx\n\`\`\`\n"
rd="$(ev_rd)"; gv="$(ev)"
check "EV4c … and a non-PASS row carries validation-gate's exact evidence text" "${rd#  - V2 Running system: NOT-RUN — }" "${gv#validation-gate: unrun — V2 Running system: }"

# EV5 AC5: a declared PASS in a file the PR does NOT change is never used.
EV5_WANT="validation-gate: unrun — V2 Running system: no evidence in the PR body; no changed docs/evidence/ file declares Validation 2 (docs/evidence/other.md: no declared verdict line)$EVFIX"
ev_set '' 'docs/evidence/other.md' "x.md=$EVOK" 'other.md=# Other\n\n```\nunrelated\n```\n'
check "EV5 AC5 a declared PASS in an unchanged file is not used ⇒ unrun" "$(ev)" "$EV5_WANT"

# EV6 AC6: a file with no declared verdict line (PR #802's shape) evidences no step, and is named.
EV802='# Validation 4 — the gate on a real run (V4)\n\n## Validation 4\n\n```\nvalidation-gate: ok\n```\n'
EV6_WANT="validation-gate: unrun — V2 Running system: no evidence in the PR body; no changed docs/evidence/ file declares Validation 2 (docs/evidence/x.md: no declared verdict line)$EVFIX"
ev_set '' 'docs/evidence/x.md' "x.md=$EV802"
check "EV6 AC6 headings and (V<n>) never declare: the file is named as having no declared verdict line" "$(ev)" "$EV6_WANT"
ev_set '' 'docs/evidence/x.md' 'x.md=# E\n\n```\nVerdict: PASS for Validation 2\n```\n  Verdict: PASS for Validation 2\nVerdict: PASS for V2\nVerdict: pass for Validation 2\nVerdict: PASS for Validation 2 (see below)\n'
check "EV6b a Verdict line inside a fence, indented, or off the form declares nothing" "$(ev)" "$EV6_WANT"
ev_set '' 'src/a.sh docs/evidence/sub/y.md' "x.md=$EVOK"
check "EV6c the PR changes no docs/evidence/*.md file ⇒ unrun naming that, and no listing call" \
  "$(ev)|$(grep -c 'contents/docs/evidence' "$EV_CALLS" | tr -d ' ')" \
  "validation-gate: unrun — V2 Running system: no evidence in the PR body; the PR adds or changes no docs/evidence/*.md file$EVFIX|0"

# EV7 AC7: a file declaring one step evidences only that step.
ev_set '' 'docs/evidence/x.md' 'x.md=# E\n\nVerdict: PASS for Validation 3\n\n```\nmerged\n```\n'
has "EV7 AC7 two Running system steps, the file declares V3 only ⇒ unrun naming V2" "$(ev reqs/two.md)" \
  "validation-gate: unrun — V2 Running system — load: no evidence in the PR body; no changed docs/evidence/ file declares Validation 2"
check "EV7b … the shared reader's rows: V2 NOT-RUN, V3 PASS from the file" "$(ev_rows reqs/two.md | cut -f1,2 | tr '\t\n' ':,')" "1:NOT-RUN,2:NOT-RUN,3:PASS,"
ev_set '' 'docs/evidence/x.md' 'x.md=# E\n\nVerdict: PASS for Validation 2\nVerdict: PASS for Validation 3\n\n```\nboth ran\n```\n'
check "EV7c one file declaring both steps ⇒ ok naming each" "$(ev reqs/two.md)" \
  "validation-gate: ok — 2 running-system step(s) evidenced (V2 in docs/evidence/x.md, V3 in docs/evidence/x.md)"

# EV8 AC8: a declared verdict that is not a pass.
ev_set '' 'docs/evidence/x.md' "x.md=# E\n\nVerdict: FAIL for Validation 2\n\n\`\`\`\nboom\n\`\`\`\n"
check "EV8 AC8 declared FAIL ⇒ FAIL naming the file (unrun)" "$(ev)" "validation-gate: unrun — V2 Running system: no evidence in the PR body; docs/evidence/x.md: declared FAIL"
ev_set '' 'docs/evidence/x.md' "x.md=# E\n\nVerdict: NOT-RUN for Validation 2\n\n\`\`\`\nnot yet\n\`\`\`\n"
check "EV8b declared NOT-RUN ⇒ NOT-RUN naming the file" "$(ev)" "validation-gate: unrun — V2 Running system: no evidence in the PR body; docs/evidence/x.md: declared NOT-RUN$EVFIX"
ev_set '' 'docs/evidence/a.md docs/evidence/b.md' "a.md=$EVOK" "b.md=# B\n\nVerdict: FAIL for Validation 2\n\n\`\`\`\nboom\n\`\`\`\n"
check "EV8c several files declaring one step: the worst declared result wins, naming its file" "$(ev)" \
  "validation-gate: unrun — V2 Running system: no evidence in the PR body; docs/evidence/b.md: declared FAIL"
ev_set '' 'docs/evidence/a.md docs/evidence/b.md' "a.md=$EVOK" "b.md=# B\n\nVerdict: NOT-RUN for Validation 2\n"
check "EV8d … NOT-RUN outranks PASS" "$(ev)" "validation-gate: unrun — V2 Running system: no evidence in the PR body; docs/evidence/b.md: declared NOT-RUN$EVFIX"

# EV9 AC9: a declared PASS with no fenced output.
ev_set '' 'docs/evidence/x.md' 'x.md=# E\n\nVerdict: PASS for Validation 2\n\nIt ran fine.\n'
check "EV9 AC9 declared PASS, no fenced output ⇒ NOT-RUN \"declared but no output\", naming the file" "$(ev)" \
  "validation-gate: unrun — V2 Running system: no evidence in the PR body; docs/evidence/x.md: declared but no output$EVFIX"

# EV10 AC10: anything unreadable fails CLOSED — NOT-RUN with the reason, one line, exit 0.
EV10_WANT="validation-gate: unrun — V2 Running system: no evidence in the PR body; evidence files unreadable: the PR's changed-file list ($EVPR)$EVFIX"
ev_set '' 'docs/evidence/x.md' "x.md=$EVOK"
out="$(EV_FAIL=view ev)"; rc=$?
check "EV10 AC10 the changed-file list unreadable ⇒ NOT-RUN with the reason, ONE line, exit 0" "$rc|$(printf '%s\n' "$out" | wc -l | tr -d ' ')|$out" "0|1|$EV10_WANT"
check "EV10b the docs/evidence/ listing unreadable ⇒ NOT-RUN with the reason" "$(EV_FAIL=list ev)" \
  "validation-gate: unrun — V2 Running system: no evidence in the PR body; evidence files unreadable: the docs/evidence/ listing at $EVSHA7$EVFIX"
check "EV10c a candidate file unreadable ⇒ NOT-RUN with the reason (an unread file never counts)" "$(EV_FAIL=read ev)" \
  "validation-gate: unrun — V2 Running system: no evidence in the PR body; evidence files unreadable: docs/evidence/x.md at $EVSHA7$EVFIX"
ev_set '' 'docs/evidence/x.md' "x.md=$EVOK"
out="$(ev reqs/one.md https://x/pull/7)"
check "EV10d a PR value that is not a https://github.com/<o>/<r>/pull/<n> URL ⇒ NOT-RUN, no evidence gh call" \
  "$out|$(grep -cE 'headRefOid,files|gh api' "$EV_CALLS" | tr -d ' ')" \
  "validation-gate: unrun — V2 Running system: no evidence in the PR body; evidence files unreadable: the PR value is not a https://github.com/<owner>/<repo>/pull/<n> URL$EVFIX|0"
: > "$EV_CALLS"
check "EV10e no PR ⇒ NOT-RUN on both halves, no gh call at all" "$(ev reqs/one.md "")|$(wc -l < "$EV_CALLS" | tr -d ' ')" \
  "validation-gate: unrun — V2 Running system: PR body unreadable: no PR recorded; evidence files unreadable: no PR recorded$EVFIX|0"
ev_set '' 'docs/evidence/x.md docs/evidence/a;b.md' "x.md=$EVOK" 'a;b.md=Verdict: FAIL for Validation 2\n'
check "EV10f a candidate name outside [A-Za-z0-9._-] is never read ⇒ NOT-RUN with the reason" "$(ev)" \
  "validation-gate: unrun — V2 Running system: no evidence in the PR body; evidence files unreadable: a file name outside A-Z a-z 0-9 . _ - in docs/evidence/$EVFIX"
ev_set '' 'docs/evidence/x.md' "x.md=$EVOK"
check "EV10g lane-readiness: the changed-file list unreadable ⇒ the V2 row NOT-RUN with the same reason" \
  "$(EV_FAIL=view ev_rd)" "  - V2 Running system: NOT-RUN — no evidence in the PR body; evidence files unreadable: the PR's changed-file list ($EVPR)$EVFIX"

# EV11 AC11: an unrun step's remedy points at the evidence file, never at the PR body.
ev_voc=""
for o in "$EV5_WANT" "$EV6_WANT" "$EV10_WANT" "$(ev_set '' 'docs/evidence/x.md' 'x.md=# E\n\nVerdict: PASS for Validation 2\n'; ev)"; do
  case "$o" in *"$EVFIX") ;; *) ev_voc="$ev_voc [no remedy: $o]" ;; esac
  case "${o##*— add }" in *"PR body"*|*paste*) ev_voc="$ev_voc [remedy names the PR body: $o]" ;; esac
done
check "EV11 AC11 every evidence-file unrun ends in the remedy (verdict line + fenced output in the docs/evidence/ file), never the PR body" "${ev_voc:-none}" none

# EV12: no evidence-file lookup where none belongs.
ev_set '' 'docs/evidence/x.md' 'x.md=# E\n\nVerdict: PASS for Validation 1\n\n```\nx\n```\n'
check "EV12 a duplicate-number row stays fail-CLOSED NOT-RUN (no lookup: the number is ambiguous)" "$(ev reqs/dup.md)" \
  "validation-gate: unrun — V1 Running system: entry number 1 is not unique in the item's ## Validation section (renumber the item)"
check "EV12b … and no evidence gh call was made for it" "$(grep -c 'headRefOid,files' "$EV_CALLS" | tr -d ' ')" 0
ev_set '' 'docs/evidence/x.md' "x.md=$EVOK"
check "EV12c no running-system step ⇒ none, with no gh call at all" "$(ev reqs/static.md)|$(wc -l < "$EV_CALLS" | tr -d ' ')" \
  "validation-gate: none — no running-system step in reqs/static.md|0"
cp "$EVRF" "$T/ev-rf.bak"
out="$(LOOMWRIGHT_GH_BIN="$T/ev-gh" LOOMWRIGHT_LANES_HELPERS="$HERE/automate-helpers.sh" bash "$S" validation-gate "$EVRF" reqs/one.md "$EVPR" --waive 2 --words "owner words" 2>&1)"
check "EV12d the waiver path reads no PR and no evidence file (no gh call)" "$out|$(wc -l < "$EV_CALLS" | tr -d ' ')" "validation-gate: waiver recorded — V2 Running system|0"
cp "$T/ev-rf.bak" "$EVRF"

# EV13: the brief's Pin mutations — each one-line edit turns its pin red.
# ev_mut <name> <anchor (fixed string, must occur once in $SB)> <sed program> — the mutant's path, or nothing.
ev_mut() {
  local d="$T/evmut/$1"; mkdir -p "$d"; cp "$HERE/resolve-loomwright-root.sh" "$d/" 2>/dev/null
  [ "$(grep -cF -- "$2" "$SB")" = 1 ] || return 0
  sed "$3" "$SB" > "$d/automate-lanes.sh"
  if [ -s "$d/automate-lanes.sh" ] && ! cmp -s "$SB" "$d/automate-lanes.sh" && bash -n "$d/automate-lanes.sh"; then printf '%s' "$d/automate-lanes.sh"; fi
}
# ev_red <leg> <mutant> <want> <setup + run, eval'd with EV_S set> — the mutant must NOT print <want>.
ev_red() {
  local got
  if [ -z "$2" ]; then bad "$1 mutant not built (anchor not once, empty, no difference, or bash -n failed)"; return; fi
  got="$(EV_S="$2"; eval "$4")"
  if [ "$got" != "$3" ]; then ok "$1 (mutant prints: ${got:0:160})"; else bad "$1 — the mutant still passes: the pin is vacuous"; fi
}
ev_red "EV13a the file read removed (# ev-read: content) turns EV1 red" "$(ev_mut read '# ev-read: content' '/# ev-read: content$/d')" \
  "$EV1_WANT" "ev_set '' 'docs/evidence/x.md' \"x.md=\$EVOK\"; ev"
ev_red "EV13b the changed-only filter removed (# ev-filter: changed-only) turns EV5 red" "$(ev_mut filter '# ev-filter: changed-only' '/# ev-filter: changed-only$/d')" \
  "$EV5_WANT" "ev_set '' 'docs/evidence/other.md' \"x.md=\$EVOK\" 'other.md=# Other\n\n\`\`\`\nunrelated\n\`\`\`\n'; ev"
ev_red "EV13c the FAIL-in-output exemption removed (# ev-exempt) turns EV2 red" "$(ev_mut exempt '# ev-exempt: declared verdict outranks output words' '/# ev-exempt: declared verdict outranks output words$/d')" \
  "$EV1_WANT" "ev_set '' 'docs/evidence/x.md' \"x.md=\$EVFAILOUT\"; ev"
ev_red "EV13d the unreadable-list guard removed (# ev-closed: unreadable list) turns EV10 red" "$(ev_mut closed '# ev-closed: unreadable list' '/# ev-closed: unreadable list$/d')" \
  "$EV10_WANT" "ev_set '' 'docs/evidence/x.md' \"x.md=\$EVOK\"; EV_FAIL=view ev"
ev_red "EV13e lane-readiness's reader call without its evdir turns EV4 red" \
  "$(ev_mut flip '"$pr" "$tmp/ev" > "$tmp/val"' 's#"$pr" "$tmp/ev" > "$tmp/val"#"$pr" "" > "$tmp/val"#')" \
  "  - V2 Running system: PASS — declared PASS with fenced output in docs/evidence/x.md" "ev_set '' 'docs/evidence/x.md' \"x.md=\$EVOK\"; ev_rd"
ev_red "EV13f the gate's unrun line removed turns AL1 red (05's pin of the changed unrun text)" \
  "$(ev_mut unrun 'echo "$G unrun — V$n $title: $ev"; return 0' '/^    echo "\$G unrun — V\$n \$title: \$ev"; return 0$/d')" \
  "$AL1_WANT" 'VG_S="$EV_S" vg "$VGRF" reqs/pa16.md "$VGPR"'
