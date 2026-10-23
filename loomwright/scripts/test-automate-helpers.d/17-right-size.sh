# =============================================================================
echo "== RZ. right-size + merge-items (parallel-automate/18b; hermetic trees under mktemp -d, --root = the tree) =="
# Every tree is built here or copied from fixtures/right-size/ (README there: provenance + edits); no leg
# reads the live .supervisor/requirements/. Section letters: RZ (right-size), MI (merge-items).
RZ="$(mktemp -d)"; RZ="$(cd "$RZ" && pwd -P)"
RZ_FIX="$HERE/fixtures/right-size"
RZ_MUT="$(dirname "$H")/rz-mutant.sh"
rz_is() { if [ "$2" = "$3" ]; then ok "$1"; else no "$1 — got '$(printf '%s' "$2" | tr '\n' '|')', want '$(printf '%s' "$3" | tr '\n' '|')'"; fi; }
# rz_run <helper> <args...> — stdout RZ_OUT, stderr RZ_ERR, exit RZ_RC
rz_run() {
  local h="$1"; shift
  RZ_RC=0; RZ_OUT="$(bash "$h" "$@" 2>"$RZ/err")" || RZ_RC=$?
  RZ_ERR="$(cat "$RZ/err")"
}
# rz_item <tree> <path under .supervisor/requirements> <status|-> <Depends body|-> <Touches body|-> [extra body]
# (bodies through printf %b; '-' omits the section). Every item has 2 scope items and 1 criterion.
rz_item() {
  local f="$1/.supervisor/requirements/$2"
  mkdir -p "$(dirname "$f")"
  {
    echo "# $(basename "$2" .md)"
    if [ "$3" != - ]; then echo; echo "## Status: $3"; fi
    echo; echo "## Scope"; echo "1. first"; echo "2. second"; echo "   - nested, not counted"
    echo; echo "## Acceptance criteria"; echo "- holds"
    if [ -n "${6:-}" ]; then echo; printf '%b\n' "$6"; fi
    if [ "$4" != - ]; then echo; echo "## Depends on"; printf '%b\n' "$4"; fi
    if [ "$5" != - ]; then echo; echo "## Touches"; printf '%b\n' "$5"; fi
  } > "$f"
}
rz_files() { local i; for i in $(seq -w 1 "$2"); do printf '%s/f%s.sh\\n' "$1" "$i"; done; }   # <dir> <n> — n Touches lines
# rz_mut <out> <anchor> <replacement|__DELETE__> — a COPY of the bundle with the FIRST line containing
# <anchor> replaced (or deleted); rz_mut_check <label> <anchor> <replacement|__DELETE__> <scenario_fn>
# <expected> — trusted only when the anchor is unique, the mutant non-empty, different and `bash -n`
# clean; it must then make <scenario_fn> print something other than <expected> (its leg turns red).
rz_mut() {
  RZ_A="$2" RZ_R="$3" awk 'BEGIN { a = ENVIRON["RZ_A"]; r = ENVIRON["RZ_R"] }
    !d && index($0, a) { d = 1; if (r == "__DELETE__") next; print r; next } { print }' "$H" > "$1"
}
rz_mut_check() {
  local got
  rz_mut "$RZ_MUT" "$2" "$3"
  if [ "$(grep -cF -- "$2" "$H")" = 1 ] && [ -s "$RZ_MUT" ] && ! cmp -s "$H" "$RZ_MUT" && bash -n "$RZ_MUT" 2>/dev/null; then
    got="$("$4" "$RZ_MUT")"
    if [ "$got" != "$5" ]; then ok "RZ mutant ($1) turns its leg red"; else no "RZ mutant ($1) did NOT discriminate: '$got'"; fi
  else
    no "RZ mutant ($1) not gated (anchor not unique, mutant empty, identical, or bash -n failed)"
  fi
  rm -f "$RZ_MUT"
}

# ---- RZ1 (AC1) small ⇒ ranked merge candidates; the companion rule adds the 3rd file and the shared one.
T1="$RZ/t1"; mkdir -p "$T1/.agent"
printf '{"schema_version":1,"companions":[{"when":"x/agents/*.md","add":["x/INDEX.md"]}]}\n' > "$T1/.agent/companions.json"
rz_item "$T1" q/01-item.md pending none 'x/agents/a.md\nx/lib/u.sh'
rz_item "$T1" q/02-sib.md pending none 'x/INDEX.md'
rz_item "$T1" q/03-plain.md pending none 'y/z.sh'
rz_item "$T1" q/04-extra.md pending none 'y/w.sh'
rz_item "$T1" other/05-far.md pending none 'x/agents/a.md\nx/lib/u.sh\nx/q'
T1_ITEM="$T1/.supervisor/requirements/q/01-item.md"
E_RZ1='q/01-item: small (3 files, 2 scope items, 1 criteria) — merge candidates: other/05-far (3 shared files), q/02-sib (1 shared files, same folder), q/03-plain (0 shared files, same folder)'
rz_s1() { rz_run "$1" right-size "$T1_ITEM" --root "$T1"; printf 'rc=%s %s' "$RZ_RC" "$RZ_OUT"; }
rz_is "RZ1 a 3-file small item names ranked candidates: most shared files first, then same folder, capped at 3 (q/04-extra cut)" "$(rz_s1 "$H")" "rc=0 $E_RZ1"
# a companion rule lifts a 3-declared-file item to 4 ⇒ ok (without the expansion it would read small)
T1B="$RZ/t1b"; mkdir -p "$T1B/.agent"; cp "$T1/.agent/companions.json" "$T1B/.agent/"
rz_item "$T1B" r/01-lift.md pending none 'x/agents/b.md\np/1.sh\np/2.sh'
rz_s1b() { rz_run "$1" right-size "$T1B/.supervisor/requirements/r/01-lift.md" --root "$T1B"; printf 'rc=%s %s' "$RZ_RC" "$RZ_OUT"; }
E_RZ1B='rc=0 r/01-lift: ok (4 files, 2 scope items, 1 criteria)'
rz_is "RZ1b the companion pass counts: 3 declared + 1 companion file = 4 ⇒ ok, not small" "$(rz_s1b "$H")" "$E_RZ1B"
# the count rule: a directory entry counts the regular files under it, a file under two entries once,
# an entry that does not exist yet 1
T1C="$RZ/t1c"; mkdir -p "$T1C/dd/sub"; for f in 1 2 3 4; do : > "$T1C/dd/f$f.sh"; done; : > "$T1C/dd/sub/g.sh"; mkdir -p "$T1C/empty"
rz_item "$T1C" c/01-dir.md pending none 'dd/\ndd/f1.sh\nempty/\nnope/x.sh'
rz_run "$H" right-size "$T1C/.supervisor/requirements/c/01-dir.md" --root "$T1C"
rz_is "RZ1c count rule: dd/ (5 files under it) + dd/f1.sh (already counted) + empty/ (1) + nope/x.sh (absent, 1) = 7" "rc=$RZ_RC $RZ_OUT" "rc=0 c/01-dir: ok (7 files, 2 scope items, 1 criteria)"

# ---- RZ2 (AC2) never a parked / proposed / proposed/ / done / operator-run / cycle-forming candidate.
T2="$RZ/t2"; mkdir -p "$T2"
rz_item "$T2" solo/01-item.md pending '../mid/07-c.md' 's/a.sh\ns/b.sh'
rz_item "$T2" solo/02-parked.md parked none 's/a.sh'
rz_item "$T2" solo/03-proposed.md proposed none 's/a.sh'
rz_item "$T2" solo/04-done.md done none 's/a.sh'
rz_item "$T2" solo/operator-run/05-op.md pending none 's/a.sh'
rz_item "$T2" proposed/06-draft.md - none 's/a.sh'
rz_item "$T2" mid/07-c.md done '../solo/08-cyc.md' 'm/x.sh'
rz_item "$T2" solo/08-cyc.md pending none 's/b.sh'
T2_ITEM="$T2/.supervisor/requirements/solo/01-item.md"
E_RZ2='rc=0 solo/01-item: small (2 files, 2 scope items, 1 criteria) — merge candidates: none'
rz_s2() { rz_run "$1" right-size "$T2_ITEM" --root "$T2"; printf 'rc=%s %s' "$RZ_RC" "$RZ_OUT"; }
rz_is "RZ2 parked, proposed, proposed/, done, operator-run/ siblings sharing files and a cycle-former (01 → done 07 → 08) are never named ⇒ 'merge candidates: none'" "$(rz_s2 "$H")" "$E_RZ2"
# the filter is not suppressing everything: an eligible sharer and a direct dependent (a direct edge collapses)
T2B="$RZ/t2b"; cp -R "$T2" "$T2B"
rz_item "$T2B" solo/09-ok.md pending none 's/a.sh'
rz_item "$T2B" solo/10-direct.md pending '01' 'z/z.sh'
rz_run "$H" right-size "$T2B/.supervisor/requirements/solo/01-item.md" --root "$T2B"
rz_is "RZ2b with an eligible sharer and a direct dependent added, only they are named (same chain marked)" "rc=$RZ_RC $RZ_OUT" \
  'rc=0 solo/01-item: small (2 files, 2 scope items, 1 criteria) — merge candidates: solo/09-ok (1 shared files, same folder), solo/10-direct (0 shared files, same chain, same folder)'

# ---- RZ3 (AC3) large by files, by parts, by both; the boundaries stay ok.
T3="$RZ/t3"; mkdir -p "$T3"
rz_item "$T3" l/01-files31.md pending none "$(rz_files a 31)"
rz_item "$T3" l/02-files30.md pending none "$(rz_files b 30)"
RZ_P8="$(for p in A B C D E F G H; do printf '## Part %s — p\\nx\\n\\n' "$p"; done)"
RZ_P7="$(for p in A B C D E F G; do printf '## Part %s — p\\nx\\n\\n' "$p"; done)"
rz_item "$T3" l/03-parts8.md pending none 'c/1.sh\nc/2.sh\nc/3.sh\nc/4.sh' "$RZ_P8"
rz_item "$T3" l/04-parts7.md pending none 'd/1.sh\nd/2.sh\nd/3.sh\nd/4.sh' "$RZ_P7\n\`\`\`\n## Part H — fenced, not counted\n\`\`\`\n### Part I — H3, not counted"
rz_item "$T3" l/05-both.md pending none "$(rz_files e 35)" "$RZ_P8"
rz_run "$H" right-size "$T3/.supervisor/requirements/l" --root "$T3"
rz_is "RZ3 31 files / 8 parts / both ⇒ large naming each cause + 'split by Part'; 30 files and 7 parts (fenced and H3 Part headings not counted) stay ok" "rc=$RZ_RC $RZ_OUT" "rc=0 l/01-files31: large (31 files) — will not fit one PR: split by Part
l/02-files30: ok (30 files, 2 scope items, 1 criteria)
l/03-parts8: large (8 parts) — will not fit one PR: split by Part
l/04-parts7: ok (4 files, 2 scope items, 1 criteria)
l/05-both: large (35 files, 8 parts) — will not fit one PR: split by Part"

# ---- RZ4 (AC4) right_size_small from <root>/.supervisor/config.json; bad values read the default (3).
T4="$RZ/t4"; mkdir -p "$T4"
rz_item "$T4" k/01-four.md pending none 'k/1.sh\nk/2.sh\nk/3.sh\nk/4.sh'
rz_s4() { rz_run "$1" right-size "$T4/.supervisor/requirements/k/01-four.md" --root "$T4"; printf 'rc=%s %s' "$RZ_RC" "$RZ_OUT"; }
E_RZ4_OK='rc=0 k/01-four: ok (4 files, 2 scope items, 1 criteria)'
E_RZ4_SMALL='rc=0 k/01-four: small (4 files, 2 scope items, 1 criteria) — merge candidates: none'
rz_is "RZ4 no config ⇒ the default 3 ⇒ a 4-file item is ok" "$(rz_s4 "$H")" "$E_RZ4_OK"
printf '{"right_size_small": 5}\n' > "$T4/.supervisor/config.json"
rz_is "RZ4 {\"right_size_small\": 5} ⇒ the same 4-file item is small" "$(rz_s4 "$H")" "$E_RZ4_SMALL"
RZ4_BAD=""
for v in '{ not json' '[1]' '{"right_size_small": "5"}' '{"right_size_small": -1}' '{"right_size_small": 4.5}' '{"right_size_small": null}' '{"right_size_small": 5}{"right_size_small": 5}'; do
  printf '%s\n' "$v" > "$T4/.supervisor/config.json"
  [ "$(rz_s4 "$H")" = "$E_RZ4_OK" ] || RZ4_BAD="$RZ4_BAD [$v]"
done
rz_is "RZ4 malformed / non-object / string / negative / non-integer / null / two-document config ⇒ the default, exit 0, never an abort" "${RZ4_BAD:-none}" none
rm -f "$T4/.supervisor/config.json"

# ---- RZ5 (AC5) a Touches-unknown item reads unknown (with plan-waves' reason), never small.
T5="$RZ/t5"; mkdir -p "$T5"
rz_item "$T5" u/01-missing.md pending none -
rz_item "$T5" u/02-bad.md pending none '- a.sh'
rz_item "$T5" u/03-declared.md pending none 'unknown'
RZ5_N="$(grep -nxF -- '- a.sh' "$T5/.supervisor/requirements/u/02-bad.md" | cut -d: -f1)"
rz_s5() { rz_run "$1" right-size "$T5/.supervisor/requirements/u" --root "$T5"; printf 'rc=%s %s' "$RZ_RC" "$RZ_OUT"; }
E_RZ5="rc=0 u/01-missing: unknown (Touches missing)
u/02-bad: unknown (Touches unparsable line $RZ5_N: \"- a.sh\")
u/03-declared: unknown (Touches declared unknown)"
rz_is "RZ5 missing / unparsable / declared-unknown Touches ⇒ 'unknown (Touches <plan-waves reason>)', exit 0" "$(rz_s5 "$H")" "$E_RZ5"
rz_run "$H" plan-waves "$T5/.supervisor/requirements/u/02-bad.md" --touches --root "$T5"
rz_is "RZ5 the reason text is plan-waves --touches' own" "$RZ_OUT" "unknown unparsable line $RZ5_N: \"- a.sh\""

# ---- RZ6 (AC6) plan doc built from the skill's template (extracted between its markers, never copied).
T6="$RZ/t6"; T6R="$T6/.supervisor/requirements/theme"; mkdir -p "$T6R"
awk '/<!-- plan-doc-template:begin -->/{on=1; next} /<!-- plan-doc-template:end -->/{on=0} on && !/^```/' "$HERE/../skills/user-story-writing/SKILL.md" \
  | sed -e 's#<folder>#theme#g' -e 's#01-<slug>#01-first#' -e 's#02-<slug>#02-second#' > "$T6R/_BACKLOG.md"
rz_item "$T6" theme/01-first.md pending none 'f/1.sh\nf/2.sh' '## Measurements\n- p95 under 2 s over 20 runs on a loaded machine'
rz_item "$T6" theme/02-second.md pending none 'g/1.sh' '## Measurements\n```\ngit worktree add <tmp> 7b7cb08\n```'
if [ -s "$T6R/_BACKLOG.md" ] && grep -q '^## Checklist' "$T6R/_BACKLOG.md"; then ok "RZ6 plan doc instantiated from the extracted template"; else no "RZ6 template extraction produced no plan doc"; fi
rz_run "$H" right-size "$T6R/_BACKLOG.md" --root "$T6"
rz_is "RZ6 plan doc: 'sections ok', then each checklist item's verdict; a Measurements section with no frozen sha adds one line (a fenced sha counts)" "rc=$RZ_RC $RZ_OUT" "rc=0 theme/_BACKLOG: plan doc: sections ok
theme/01-first: small (2 files, 2 scope items, 1 criteria) — merge candidates: theme/02-second (0 shared files, same folder)
theme/01-first: measurements: no frozen commit named
theme/02-second: small (1 files, 2 scope items, 1 criteria) — merge candidates: theme/01-first (0 shared files, same folder)"
grep -vxE '## Why now|## Run' "$T6R/_BACKLOG.md" > "$T6R/_BACKLOG-cut.md"
rz_run "$H" right-size "$T6R/_BACKLOG-cut.md" --root "$T6"
rz_is "RZ6 plan doc with two required sections deleted ⇒ 'plan doc: missing: Why now, Run', still exit 0" "rc=$RZ_RC $(printf '%s\n' "$RZ_OUT" | head -n1)" "rc=0 theme/_BACKLOG-cut: plan doc: missing: Why now, Run"

# the template is read at run time beside the real scripts dir: a lone copy of the helper cannot find it
mkdir -p "$RZ/lone"; cp "$H" "$RZ/lone/automate-helpers.sh"
rz_run "$RZ/lone/automate-helpers.sh" right-size "$T6R/_BACKLOG.md" --root "$T6"
rz_is "RZ6c template unreadable ⇒ 'plan doc: sections unknown (template unreadable)', items still judged, exit 0" "rc=$RZ_RC $(printf '%s\n' "$RZ_OUT" | head -n1) n=$(printf '%s\n' "$RZ_OUT" | grep -c .)" "rc=0 theme/_BACKLOG: plan doc: sections unknown (template unreadable) n=4"

# ---- RZ7 (AC7) --json: ONE array, one object per row, the documented keys and types.
RZ_KEYS='["candidates","causes","criteria","files","item","measurements","parts","plan_doc","scope_items","touches_why","verdict"]'
rz_run "$H" right-size "$T1_ITEM" --root "$T1" --json
if [ "$RZ_RC" = 0 ] && printf '%s' "$RZ_OUT" | jq -e --argjson k "$RZ_KEYS" 'type == "array" and length == 1 and (.[0] | keys == $k)
  and .[0].verdict == "small" and .[0].files == 3 and .[0].scope_items == 2 and .[0].criteria == 1 and .[0].parts == 0
  and .[0].causes == [] and .[0].plan_doc == null and .[0].measurements == null and .[0].touches_why == null
  and .[0].candidates == [{"item":"other/05-far","shared_files":3,"same_chain":false,"same_folder":false},
    {"item":"q/02-sib","shared_files":1,"same_chain":false,"same_folder":true},
    {"item":"q/03-plain","shared_files":0,"same_chain":false,"same_folder":true}]' >/dev/null 2>&1; then
  ok "RZ7 --json small item: one array, every documented key, candidates as {item, shared_files, same_chain, same_folder}"
else no "RZ7 --json small item wrong (rc=$RZ_RC): $RZ_OUT"; fi
rz_run "$H" right-size "$T6R/_BACKLOG.md" "$T6R/_BACKLOG-cut.md" "$T5/.supervisor/requirements/u/01-missing.md" "$T3/.supervisor/requirements/l/05-both.md" --root "$T6" --json
if [ "$RZ_RC" = 0 ] && printf '%s' "$RZ_OUT" | jq -e --argjson k "$RZ_KEYS" 'type == "array" and length == 8 and all(.[]; keys == $k)
  and .[0].verdict == null and .[0].plan_doc == "ok" and .[1].measurements == "no_frozen_commit" and .[2].measurements == null
  and .[3].verdict == null and .[3].plan_doc == ["Why now","Run"]
  and .[6].verdict == "unknown" and .[6].files == null and .[6].causes == ["touches_unknown"] and .[6].touches_why == "missing"
  and .[7].verdict == "large" and .[7].causes == ["files","parts"] and .[7].files == 35 and .[7].parts == 8' >/dev/null 2>&1; then
  ok "RZ7 --json over two plan docs + unknown + large: one array of 8 rows (doc rows verdict null), plan_doc ok / missing list, measurements, causes"
else no "RZ7 --json multi-row wrong (rc=$RZ_RC): $(printf '%s' "$RZ_OUT" | jq -c '[.[] | {item, verdict, plan_doc, causes}]' 2>&1)"; fi

# ---- RZ8 (AC8) usage / not found / companions_malformed ⇒ exit 1 with EMPTY stdout.
RZ8_BAD=""
rz_run "$H" right-size; [ "$RZ_RC" = 1 ] && [ -z "$RZ_OUT" ] || RZ8_BAD="$RZ8_BAD no-args"
rz_run "$H" right-size "$T1_ITEM" --bogus --root "$T1"; [ "$RZ_RC" = 1 ] && [ -z "$RZ_OUT" ] || RZ8_BAD="$RZ8_BAD bad-option"
rz_run "$H" right-size "$T1_ITEM" --root; [ "$RZ_RC" = 1 ] && [ -z "$RZ_OUT" ] || RZ8_BAD="$RZ8_BAD root-no-value"
rz_run "$H" right-size "$T1/.supervisor/requirements/q/99-nope.md" --root "$T1"; { [ "$RZ_RC" = 1 ] && [ -z "$RZ_OUT" ] && grep -qF 'item not found' <<<"$RZ_ERR"; } || RZ8_BAD="$RZ8_BAD not-found"
printf 'q/01-item.md\nq/98-gone.md\n' > "$RZ/list"
rz_run "$H" right-size "$RZ/list" --root "$T1/.supervisor/requirements"; { [ "$RZ_RC" = 1 ] && [ -z "$RZ_OUT" ]; } || RZ8_BAD="$RZ8_BAD list-entry-not-found"
LOOMWRIGHT_JQ_BIN="$RZ/no-such-jq" rz_run "$H" right-size "$T1C/.supervisor/requirements/c/01-dir.md" --root "$T1C" --json
{ [ "$RZ_RC" = 1 ] && [ -z "$RZ_OUT" ] && grep -qF 'jq not found' <<<"$RZ_ERR"; } || RZ8_BAD="$RZ8_BAD json-without-jq"
rz_is "RZ8 usage errors, a missing item / item-list entry, --json without jq ⇒ exit 1, empty stdout" "${RZ8_BAD:-none}" none
T8="$RZ/t8"; cp -R "$T1" "$T8"; printf '{"schema_version": 1, "companions": "nope"}\n' > "$T8/.agent/companions.json"
rz_s8() { rz_run "$1" right-size "$T8/.supervisor/requirements/q/01-item.md" --root "$T8"; printf 'rc=%s out=[%s] malformed=%s' "$RZ_RC" "$RZ_OUT" "$(grep -c companions_malformed <<<"$RZ_ERR")"; }
E_RZ8='rc=1 out=[] malformed=1'
rz_is "RZ8 companions_malformed ⇒ exit 1, empty stdout, the planner's reason on stderr" "$(rz_s8 "$H")" "$E_RZ8"
printf '# a comment line\n\n  .supervisor/requirements/q/01-item.md  \n' > "$RZ/list1"
rz_run "$H" right-size "$RZ/list1" --root "$T1"
rz_is "RZ8 an item list resolves against --root (same verdict as the item)" "rc=$RZ_RC $RZ_OUT" "rc=0 $E_RZ1"

# ---- RZ9 (AC9a/b) the source text's checks on committed fixture copies (fixtures/right-size/README.md).
T9="$RZ/t9"; T9M="$T9/.supervisor/requirements/meta-sync-followups"; mkdir -p "$T9M" "$T9/.agent"
cp "$RZ_FIX/ms-09.md" "$T9M/09-scrub-safe-schema-examples.md"; cp "$RZ_FIX/ms-10.md" "$T9M/10-anchor-home-path-scrub.md"
# the repo's own loomwright/agents/*.md companion rule, read from the committed table (never retyped)
jq '{schema_version: 1, companions: [.companions[] | select(.when == "loomwright/agents/*.md")]}' "$HERE/../../.agent/companions.json" > "$T9/.agent/companions.json"
if [ "$(jq '.companions | length' "$T9/.agent/companions.json" 2>/dev/null)" = 1 ]; then ok "RZ9 fixture companions table carries the repo's loomwright/agents/*.md rule"; else no "RZ9 the repo's loomwright/agents/*.md companion rule was not found"; fi
# The 2026-10-06 check predates the 3-file default: their expanded counts are 4 and 7 (ms/10's agent
# file adds two companion files), so the check reproduces at right_size_small 7; at the default both are ok.
printf '{"right_size_small": 7}\n' > "$T9/.supervisor/config.json"
rz_run "$H" right-size "$T9M" --root "$T9"
rz_is "RZ9a ms/09 + ms/10 at right_size_small 7: both small, each the other's top candidate (same folder)" "rc=$RZ_RC $RZ_OUT" "rc=0 meta-sync-followups/09-scrub-safe-schema-examples: small (4 files, 2 scope items, 3 criteria) — merge candidates: meta-sync-followups/10-anchor-home-path-scrub (0 shared files, same folder)
meta-sync-followups/10-anchor-home-path-scrub: small (7 files, 4 scope items, 4 criteria) — merge candidates: meta-sync-followups/09-scrub-safe-schema-examples (0 shared files, same folder)"
rm -f "$T9/.supervisor/config.json"
rz_run "$H" right-size "$T9M" --root "$T9"
rz_is "RZ9a' the same pair at the default threshold: both ok" "rc=$RZ_RC $RZ_OUT" "rc=0 meta-sync-followups/09-scrub-safe-schema-examples: ok (4 files, 2 scope items, 3 criteria)
meta-sync-followups/10-anchor-home-path-scrub: ok (7 files, 4 scope items, 4 criteria)"
mkdir -p "$T9/.supervisor/requirements/implementation-quality"; cp "$RZ_FIX/iq-02-shaped.md" "$T9/.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md"
rz_run "$H" right-size "$T9/.supervisor/requirements/implementation-quality/02-iq01-and-throughput-merged.md" --root "$T9"
rz_is "RZ9b the iq/02-shaped fixture: large with both causes and 'split by Part'" "rc=$RZ_RC $RZ_OUT" "rc=0 implementation-quality/02-iq01-and-throughput-merged: large (33 files, 10 parts) — will not fit one PR: split by Part"

# ---- RZ10 the fork-free basename/dirname stand-ins print what the real utilities print.
RZ10_BAD=""
for p in a/b.md /a/b/ b / // a//b// . .. /x x/ "/sp ace/f.md"; do
  [ "$(RZ_P="$p" bash -c '. "$0" >/dev/null 2>&1; _rsz_basename "$RZ_P"' "$H")" = "$(basename "$p")" ] || RZ10_BAD="$RZ10_BAD basename[$p]"
  [ "$(RZ_P="$p" bash -c '. "$0" >/dev/null 2>&1; _rsz_dirname "$RZ_P"' "$H")" = "$(dirname "$p")" ] || RZ10_BAD="$RZ10_BAD dirname[$p]"
done
for p in a/b.md .md x.md.md; do
  [ "$(RZ_P="$p" bash -c '. "$0" >/dev/null 2>&1; _rsz_basename "$RZ_P" .md' "$H")" = "$(basename "$p" .md)" ] || RZ10_BAD="$RZ10_BAD basename-suffix[$p]"
done
rz_is "RZ10 _rsz_basename / _rsz_dirname equal basename(1) / dirname(1) on every probed shape" "${RZ10_BAD:-none}" none

# ---- RZ11 read-only: right-size leaves the tree byte-identical.
RZ11_BEFORE="$(cd "$T2B" && find . -type f -exec cksum {} \; | env LC_ALL=C sort)"
rz_run "$H" right-size "$T2B/.supervisor/requirements/solo" --root "$T2B" --json
RZ11_AFTER="$(cd "$T2B" && find . -type f -exec cksum {} \; | env LC_ALL=C sort)"
rz_is "RZ11 right-size (dir input, --json) writes nothing in the tree" "rc=$RZ_RC same=$([ "$RZ11_BEFORE" = "$RZ11_AFTER" ] && echo y || echo n)" "rc=0 same=y"

# =============================================================================
# MI. merge-items (AC10–AC12)
# mi_af33 <helper> <tree> — the af/17 + af/25 → af/33 merge in a fresh tree (title and goal from the hand merge).
MI_TITLE="$(sed -n '1s/^# //p' "$RZ_FIX/af-33-merged.md")"
MI_GOAL="$(awk '/^## Goal$/ { getline; print; exit }' "$RZ_FIX/af-33-merged.md")"
mi_af33() {
  local a="$2/.supervisor/requirements/automate-followups"
  rm -rf "$2"; mkdir -p "$a"
  cp "$RZ_FIX/af-17-pre.md" "$a/17-children-settled-non-plugin-spawns.md"; cp "$RZ_FIX/af-25-pre.md" "$a/25-children-settled-before-publish.md"
  rz_run "$1" merge-items "$a/33-children-settled-gate.md" --title "$MI_TITLE" --goal "$MI_GOAL" --date 2026-10-05 --root "$2" \
    A:"$a/17-children-settled-non-plugin-spawns.md" B:"$a/25-children-settled-before-publish.md"
}
MI1="$RZ/mi1"; MI1A="$MI1/.supervisor/requirements/automate-followups"
mi_af33 "$H" "$MI1"
if [ "$RZ_RC" = 0 ] && grep -qF 'merge-items: post-check ok — 0 lost lines' <<<"$RZ_OUT" && cmp -s "$MI1A/33-children-settled-gate.md" "$RZ_FIX/merge-af33.expected.md"; then
  ok "MI1 (AC12) af/17 + af/25 ⇒ post-check reports 0 lost lines; the output equals fixtures/right-size/merge-af33.expected.md byte-for-byte"
else no "MI1 af/33 round trip wrong (rc=$RZ_RC out='$RZ_OUT' err='$RZ_ERR' diff: $(diff "$RZ_FIX/merge-af33.expected.md" "$MI1A/33-children-settled-gate.md" 2>&1 | head -5 | tr '\n' '|'))"; fi
MI_ST_A='## Status: parked (merged 2026-10-05 into automate-followups/33-children-settled-gate.md as Part A — do not run this file)'
MI_ST_B='## Status: parked (merged 2026-10-05 into automate-followups/33-children-settled-gate.md as Part B — do not run this file)'
# each original gained exactly its stamp (and the blank line after its title); nothing else changed
if [ "$(sed -n 3p "$MI1A/17-children-settled-non-plugin-spawns.md")" = "$MI_ST_A" ] && [ "$(sed -n 3p "$MI1A/25-children-settled-before-publish.md")" = "$MI_ST_B" ] \
   && awk 'NR == 2 || NR == 3 { next } { print }' "$MI1A/17-children-settled-non-plugin-spawns.md" | cmp -s - "$RZ_FIX/af-17-pre.md" \
   && awk 'NR == 2 || NR == 3 { next } { print }' "$MI1A/25-children-settled-before-publish.md" | cmp -s - "$RZ_FIX/af-25-pre.md"; then
  ok "MI1 (AC10) each original's status is the parked stamp naming the out file and its Part; nothing else in it changed"
else no "MI1 originals' stamps wrong: $(grep -h '^## Status' "$MI1A"/1*.md "$MI1A"/2*.md | tr '\n' '|')"; fi
# AC12 against the hand merge: Part B equal modulo heading depth and blank lines; Part A = the hand merge's
# Part A plus af/17's 4-line blockquote, which the hand merge dropped.
mi_norm_part() {  # <file> <label> — that Part's lines, blank lines dropped, every heading's #-run made one '#'
  MI_L="$2" awk 'BEGIN { w = "Part " ENVIRON["MI_L"] " — " }
    /^#+ Part [A-Z] — / { h = $0; sub(/^#+ /, "", h); if (index(h, w) == 1) { on = 1; next } else if (on) exit }
    on && $0 == "## Depends on" { exit }
    on && /^[ \t]*$/ { next }
    on { sub(/^#+ /, "# "); print }' "$1"
}
MI_BQ="$(grep '^> ' "$RZ_FIX/af-17-pre.md")"
MI_GA="$(mi_norm_part "$RZ_FIX/merge-af33.expected.md" A)"; MI_HA="$(mi_norm_part "$RZ_FIX/af-33-merged.md" A)"
MI_GB="$(mi_norm_part "$RZ_FIX/merge-af33.expected.md" B)"; MI_HB="$(mi_norm_part "$RZ_FIX/af-33-merged.md" B)"
if [ -n "$MI_HB" ] && [ "$MI_GB" = "$MI_HB" ]; then ok "MI1 (AC12) the produced Part B equals the hand-merged af/33's Part B modulo heading depth and blank lines"
else no "MI1 Part B differs from the hand merge: $(diff <(printf '%s\n' "$MI_HB") <(printf '%s\n' "$MI_GB") | head -4 | tr '\n' '|')"; fi
if [ "$(printf '%s\n' "$MI_BQ" | grep -c .)" = 4 ] && [ -n "$MI_HA" ] && [ "$MI_GA" = "$(printf '%s\n%s' "$MI_BQ" "$MI_HA")" ]; then
  ok "MI1 (AC12) the produced Part A = the hand merge's Part A + af/17's 4-line '> **Promoted …' / '> **Origin …' blockquote (the hand-merge line loss)"
else no "MI1 Part A is not exactly the hand merge's plus the blockquote: $(diff <(printf '%s\n%s\n' "$MI_BQ" "$MI_HA") <(printf '%s\n' "$MI_GA") | head -4 | tr '\n' '|')"; fi
if ! grep -qF 'automate-followups-17-children-settled-non-plugin-spawns.md' "$MI1A/33-children-settled-gate.md" && grep -qxF 'changelog.d/automate-followups-33-children-settled-gate.md' "$MI1A/33-children-settled-gate.md"; then
  ok "MI1 (AC11b) the originals' changelog.d fragments map to the one out fragment and the post-check accepts the remap"
else no "MI1 changelog fragment remap wrong"; fi

# MI2 (AC10) Depends on folded and every dependent re-pointed; a small hand-built tree.
mi_tree() {  # <tree> — f/01-a (deps 05) + f/02-b (deps 01) merged later; 07-dep and other/09-x depend on them
  rm -rf "$1"; mkdir -p "$1"
  rz_item "$1" f/01-a.md pending '05' 'a.sh\nchangelog.d/f-01-a.md' '## Notes\nbody line of a'
  rz_item "$1" f/02-b.md pending '01' 'b.sh\nlib/shared.sh' '## Notes\nbody line of b\n\n### Deeper\nkept'
  rz_item "$1" f/05-base.md pending none 'base.sh'
  rz_item "$1" f/07-dep.md pending '1\n02-b.md\n05' 'dep.sh'
  rz_item "$1" other/09-x.md pending '../f/02-b.md' 'x.sh'
}
mi_merge() {  # <helper> <tree> [<more args>] — merge A:01-a B:02-b into f/10-ab.md
  local h="$1" t="$2" r="$2/.supervisor/requirements"; shift 2
  rz_run "$h" merge-items "$r/f/10-ab.md" --title "10 — a and b" --goal "Both at once." --date 2026-10-22 --root "$t" "$@" A:"$r/f/01-a.md" B:"$r/f/02-b.md"
}
MI2="$RZ/mi2"; mi_tree "$MI2"; MI2R="$MI2/.supervisor/requirements"
mi_merge "$H" "$MI2"
MI2_DEP_WANT="$RZ/dep-want"; mi_tree "$MI2_DEP_WANT"; rz_item "$MI2_DEP_WANT" f/07-dep.md pending '10-ab.md\n05' 'dep.sh'; rz_item "$MI2_DEP_WANT" other/09-x.md pending '../f/10-ab.md' 'x.sh'
if [ "$RZ_RC" = 0 ] && cmp -s "$MI2R/f/07-dep.md" "$MI2_DEP_WANT/.supervisor/requirements/f/07-dep.md" && cmp -s "$MI2R/other/09-x.md" "$MI2_DEP_WANT/.supervisor/requirements/other/09-x.md" \
   && grep -qxF 'merge-items: re-pointed f/07-dep' <<<"$RZ_OUT" && grep -qxF 'merge-items: re-pointed other/09-x' <<<"$RZ_OUT"; then
  ok "MI2 dependents re-pointed: '1' → 10-ab.md, the second line naming an original dropped, '../f/02-b.md' → '../f/10-ab.md'; nothing else changed"
else no "MI2 dependents wrong (rc=$RZ_RC err='$RZ_ERR'): $(diff "$MI2_DEP_WANT/.supervisor/requirements/f/07-dep.md" "$MI2R/f/07-dep.md" 2>&1 | tr '\n' '|')"; fi
MI2_SECT="$(awk '/^## Depends on$/ { s = 1 } /^## Touches$/ { s = 2 } s' "$MI2R/f/10-ab.md")"
rz_is "MI2 merged Depends on = the originals' minus 'none' and self-references; Touches sorted unique, fragment renamed" "$MI2_SECT" '## Depends on
05

## Touches
a.sh
b.sh
changelog.d/f-10-ab.md
lib/shared.sh'
if grep -qxF '### Notes' "$MI2R/f/10-ab.md" && grep -qxF '#### Deeper' "$MI2R/f/10-ab.md" && grep -qxF '## Part B — 02-b' "$MI2R/f/10-ab.md" && ! grep -q '^## Status' "$MI2R/f/10-ab.md"; then
  ok "MI2 Parts are '## Part <X> — <original title>', original headings demoted one level, no Status line carried"
else no "MI2 Part shape wrong"; fi
rz_run "$H" plan-waves "$MI2R/f/10-ab.md" --lint --root "$MI2"
rz_is "MI2 the merged item lints clean with the planner's own parser" "rc=$RZ_RC" "rc=0"

# MI3 (AC11) the post-check: a lost body / Touches / Depends on line ⇒ exit 1 and NOTHING written.
mi_snap() { (cd "$1" && find . -type f -exec cksum {} \; | env LC_ALL=C sort); }
# mi_drop <helper> <line> — prints `rc=<rc> written=<y|n> unchanged=<y|n> named=<y|n>`
mi_drop() {
  local t="$RZ/mi3" before
  mi_tree "$t"; before="$(mi_snap "$t")"
  LOOMWRIGHT_MERGE_ITEMS_DROP="$2" mi_merge "$1" "$t"
  printf 'rc=%s written=%s unchanged=%s named=%s' "$RZ_RC" "$([ -e "$t/.supervisor/requirements/f/10-ab.md" ] && echo y || echo n)" \
    "$([ "$(mi_snap "$t")" = "$before" ] && echo y || echo n)" "$(grep -qF "lost" <<<"$RZ_ERR" && grep -qF -- "$2" <<<"$RZ_ERR" && echo y || echo n)"
}
E_MI3='rc=1 written=n unchanged=y named=y'
mi_drop_body() { mi_drop "$1" 'body line of a'; }
rz_is "MI3a a dropped body line trips the post-check: exit 1, no out file, originals and dependents byte-identical" "$(mi_drop_body "$H")" "$E_MI3"
rz_is "MI3b a dropped non-changelog Touches line trips the post-check" "$(mi_drop "$H" 'lib/shared.sh')" "$E_MI3"
rz_is "MI3c a dropped Depends on line trips the post-check" "$(mi_drop "$H" '05')" "$E_MI3"

# MI4 (AC11) refusals — exit 1 and nothing written.
mi_refuse() {  # <label> <setup fn> — the setup edits a fresh tree, the merge must refuse it untouched
  local t="$RZ/mi4" before
  mi_tree "$t"; "$2" "$t"; before="$(mi_snap "$t")"
  mi_merge "$H" "$t"
  rz_is "MI4 refuses $1: exit 1, nothing written" "rc=$RZ_RC unchanged=$([ "$(mi_snap "$t")" = "$before" ] && echo y || echo n) out=$([ -e "$t/.supervisor/requirements/f/10-ab.md" ] && echo y || echo n)" "rc=1 unchanged=y out=n"
}
mi_s_done()   { rz_item "$1" f/02-b.md done '01' 'b.sh'; }
mi_s_merged() { rz_item "$1" f/02-b.md 'parked (merged 2026-10-01 into f/99-x.md as Part A — do not run this file)' '01' 'b.sh'; }
mi_s_cycle()  { rz_item "$1" f/01-a.md pending '03' 'a.sh'; rz_item "$1" f/03-c.md pending '02-b.md' 'c.sh'; rz_item "$1" f/02-b.md pending none 'b.sh'; }
mi_s_unknown(){ rz_item "$1" f/02-b.md pending '01' 'unknown'; }
mi_s_exists() { : > "$1/.supervisor/requirements/f/10-ab.md"; }
mi_refuse "a done original" mi_s_done
mi_refuse "an already-merged original" mi_s_merged
mi_refuse "a merge that would make a cycle (01 → 03 → 02)" mi_s_cycle
mi_refuse "an original whose Touches is not known" mi_s_unknown
t="$RZ/mi4"; mi_tree "$t"; mi_s_exists "$t"; MI4_B="$(mi_snap "$t")"; mi_merge "$H" "$t"
rz_is "MI4 refuses an existing <out.md>: exit 1, nothing written" "rc=$RZ_RC unchanged=$([ "$(mi_snap "$t")" = "$MI4_B" ] && echo y || echo n)" "rc=1 unchanged=y"
t="$RZ/mi4"; mi_tree "$t"; mkdir -p "$t/.supervisor/requirements/operator-run"; rz_item "$t" operator-run/02-op.md pending none 'op.sh'; MI4_B="$(mi_snap "$t")"
rz_run "$H" merge-items "$t/.supervisor/requirements/f/10-ab.md" --title t --goal g --date 2026-10-22 --root "$t" A:"$t/.supervisor/requirements/f/01-a.md" B:"$t/.supervisor/requirements/operator-run/02-op.md"
rz_is "MI4 refuses an operator-run/ original: exit 1, nothing written" "rc=$RZ_RC unchanged=$([ "$(mi_snap "$t")" = "$MI4_B" ] && echo y || echo n)" "rc=1 unchanged=y"
t="$RZ/mi4"; mi_tree "$t"; MI4_B="$(mi_snap "$t")"
rz_run "$H" merge-items "$t/.supervisor/requirements/f/10-ab.md" --title t --goal g --root "$t" A:"$t/.supervisor/requirements/f/01-a.md"
rz_is "MI4 one original only ⇒ usage error, nothing written" "rc=$RZ_RC unchanged=$([ "$(mi_snap "$t")" = "$MI4_B" ] && echo y || echo n)" "rc=1 unchanged=y"
MI4_BAD=""; t="$RZ/mi4"; mi_tree "$t"; MI4_B="$(mi_snap "$t")"; r="$t/.supervisor/requirements"
mi_try() { rz_run "$H" merge-items "$@"; { [ "$RZ_RC" = 1 ] && [ "$(mi_snap "$t")" = "$MI4_B" ]; } || MI4_BAD="$MI4_BAD [$*]"; }
mi_try "$t/out.md" --title t --goal g --root "$t" A:"$r/f/01-a.md" B:"$r/f/02-b.md"                  # out outside the tree
mi_try "$r/f/10-ab.md" --title t --goal g --date 2026-1-2 --root "$t" A:"$r/f/01-a.md" B:"$r/f/02-b.md"  # bad --date
mi_try "$r/f/10-ab.md" --title t --goal g --root "$t" a:"$r/f/01-a.md" B:"$r/f/02-b.md"               # lower-case label
mi_try "$r/f/10-ab.md" --title t --goal g --root "$t" A:"$r/f/01-a.md" A:"$r/f/02-b.md"               # label twice
mi_try "$r/f/10-ab.md" --title t --goal g --root "$t" A:"$r/f/01-a.md" B:"$r/f/01-a.md"               # original twice
mi_try "$r/f/10-ab.md" --goal g --root "$t" A:"$r/f/01-a.md" B:"$r/f/02-b.md"                          # no --title
mi_try "$r/f/10-ab" --title t --goal g --root "$t" A:"$r/f/01-a.md" B:"$r/f/02-b.md"                   # out not *.md
rz_is "MI4 usage refusals (out outside the tree / not *.md, bad --date, bad or repeated label, repeated original, no --title) ⇒ exit 1, nothing written" "${MI4_BAD:-none}" none
# a root whose path holds a space: right-size and merge-items both work
MI5="$RZ/with space"; mi_tree "$MI5"
rz_run "$H" right-size "$MI5/.supervisor/requirements/f" --root "$MI5"
mi_merge "$H" "$MI5"
rz_is "MI5 a checkout path with a space: right-size judges the folder, merge-items merges" "rc=$RZ_RC lines=$(grep -c '^merge-items: ' <<<"$RZ_OUT") out=$([ -f "$MI5/.supervisor/requirements/f/10-ab.md" ] && echo y || echo n)" "rc=0 lines=6 out=y"

# ---- Mutation controls (AC17 i–iii, plus the cycle / unknown / propagation / already-merged pins).
rz_mut_check "(i) companion expansion dropped from the size count ⇒ RZ1 / RZ1b change" '  _pw_expand "$3.decl" "$2" "$3"   # + ONE companion pass' __DELETE__ rz_s1b "$E_RZ1B"
rz_mut_check "(i') companion expansion dropped ⇒ the AC1 shared-file ranking changes" '  _pw_expand "$3.decl" "$2" "$3"   # + ONE companion pass' __DELETE__ rz_s1 "rc=0 $E_RZ1"
rz_mut_check "(ii) parked/done exclusion dropped from the candidate pool ⇒ RZ2 names them" '    if is_done "$f" || is_not_ready "$f"; then continue; fi' __DELETE__ rz_s2 "$E_RZ2"
rz_mut_check "(iii) merge-items' lost-line post-check dropped ⇒ MI3a writes" '  cnt="$(_mi_postcheck "$_RSZ_TMP/out.md"' __DELETE__ mi_drop_body "$E_MI3"
rz_mut_check "cycle exclusion dropped ⇒ RZ2 names the cycle-former" '    if [ "$cy" = 1 ]; then k=$((k+1)); continue; fi' __DELETE__ rz_s2 "$E_RZ2"
rz_mut_check "unknown short-circuit dropped ⇒ RZ5 no longer reads unknown" '    elif [ "$st" != known ]; then verdict=unknown' __DELETE__ rz_s5 "$E_RZ5"
rz_mut_check "companions_malformed propagation dropped ⇒ RZ8 prints a verdict" '  ( _pw_load_companions "$_RSZ_ROOT" ) || exit 1' '  ( _pw_load_companions "$_RSZ_ROOT" ) || true' rz_s8 "$E_RZ8"
mi_s_merged_case() { local t="$RZ/mi5"; mi_tree "$t"; mi_s_merged "$t"; mi_merge "$1" "$t"; printf 'rc=%s' "$RZ_RC"; }
rz_mut_check "already-merged refusal dropped ⇒ MI4 merges it" 'is already merged: $f"; fi' __DELETE__ mi_s_merged_case 'rc=1'

rm -rf "$RZ"
