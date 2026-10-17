echo "== 67. learning stores in the managed set (af36-03 AC1): both closed lists move together =="
# ---- learning-store helpers (af36-03) ----
# grant <clone> [grant|decline] — this world's user-scope consent record (scratch HOME; the key is
# the world's origin URL, a filesystem path, so every clone of one world shares it).
grant() { bash "$HERE/setup-memory.sh" --root "$W/$1" consent "${2:-grant}" >/dev/null 2>&1; }
TW=".supervisor/twin"; TP=".supervisor/twin/.provenance.jsonl"; TC=".supervisor/twin/contracts"
EV=".supervisor/eval/results.jsonl"; EB=".supervisor/eval/brain-baseline.jsonl"
PR=".supervisor/agent-memory-proposals"
tsha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
# twin_add <clone> <id> <body> — a contract plus a chain-valid `add` entry, by read-system-contract.sh's
# rules (prev_hash GENESIS, then the sha256 of the previous raw line; content_hash = sha256 of the body).
twin_add() {
  local d="$W/$1/$TW" prev="GENESIS" ch
  mkdir -p "$d/contracts"
  printf '%s\n' "$3" > "$d/contracts/$2.md"
  ch="$(tsha < "$d/contracts/$2.md")"
  [ -s "$d/.provenance.jsonl" ] && prev="$(grep -v '^$' "$d/.provenance.jsonl" | tail -n 1 | tr -d '\n' | tsha)"
  printf '{"subsystem":"%s","prev_hash":"%s","content_hash":"%s","source":"fixture","action":"add","written_at":"2026-10-13T00:00:00Z"}\n' "$2" "$prev" "$ch" >> "$d/.provenance.jsonl"
}
twin_sig() { git --git-dir="$W/origin.git" ls-tree -r "refs/heads/$BR" -- "$TW" 2>/dev/null; }
# br_inject <path> <content> — a commit on the branch adding <path> (plumbing in the bare origin),
# standing in for a sibling whose push did not run the pair rule.
br_inject() {
  local G="$W/origin.git" blob t c idx="$W/inject.idx"
  blob="$(printf '%s\n' "$2" | git --git-dir="$G" hash-object -w --stdin)" || return 1
  rm -f "$idx"
  GIT_INDEX_FILE="$idx" git --git-dir="$G" read-tree "refs/heads/$BR" || return 1
  GIT_INDEX_FILE="$idx" git --git-dir="$G" update-index --add --cacheinfo 100644 "$blob" "$1" || return 1
  t="$(GIT_INDEX_FILE="$idx" git --git-dir="$G" write-tree)" || return 1
  c="$(git --git-dir="$G" commit-tree "$t" -p "refs/heads/$BR" -m inject)" || return 1
  git --git-dir="$G" update-ref "refs/heads/$BR" "$c"
}
has_line() { grep -qxF -- "$1" < <(printf '%s\n' "$OUT"); }
# twin_pair — A and B synced on a twin set (contract c1 + its chain), a proposal, both eval files and
# a run-history file; consent granted for the world.
twin_pair() {
  mkworld; clone A; clone B
  ms A init
  grant A
  twin_add A c1 "SYSTEM_CONTRACT: c1"
  put A "$PR/p1.md" "proposal one"
  put A "$EV" '{"run":1}'; put A "$EB" '{"base":1}'
  put A "$RQ/x.md" "x v1"
  ms A push
  ms B pull
}

mkworld; clone A
ms A init
twin_add A c1 "SYSTEM_CONTRACT: c1"
put A "$PR/p1.md" "proposal"; put A "$EV" '{"run":1}'; put A "$EB" '{"base":1}'
put A "$RQ/x.md" "x"; put A ".supervisor/automate/automate-1.dismissed-decisions" "$(printf 'd.md\tdrop\t2026-10-08T00:00:00Z')"
# look-alikes that must NOT be managed
put A "$TC/sub/nested.md" "nested"; put A "$PR/sub/nested.md" "nested"
put A ".supervisor/eval/other.jsonl" "{}"; put A "$TW/other.jsonl" "{}"; put A "$TW/README.md" "readme"
put A ".supervisor/worker-summaries/1.md" "worker summary"; put A ".supervisor/worker-summaries/S1.md" "worker summary"
AC1_EXP="$(printf '%s\n' "$RQ/x.md" ".supervisor/agent-memory-proposals/p1.md" ".supervisor/automate/automate-1.dismissed-decisions" \
  "$EB" "$EV" "$TP" "$TC/c1.md" | env LC_ALL=C sort)"
ms A list-managed
{ [ "$RC" -eq 0 ] && [ "$OUT" = "$AC1_EXP" ]; }
check $? "list-managed lists the twin contract + .provenance.jsonl, the proposal and both eval files — no nested / look-alike / worker-summaries path (rc=$RC: $(printf '%s' "$OUT" | tr '\n' '|'))"
AC1_LM="$OUT"
ms A list-managed --run-history
{ [ "$RC" -eq 0 ] && [ "$OUT" = "$(printf '%s\n' "$RQ/x.md" ".supervisor/automate/automate-1.dismissed-decisions" | env LC_ALL=C sort)" ]; }
check $? "list-managed --run-history drops every learning-store path (the dismissed ledger stays run history) (got: $(printf '%s' "$OUT" | tr '\n' '|'))"
grant A
ms A push
{ [ "$RC" -eq 0 ] && [ "$(br_names | env LC_ALL=C sort)" = "$AC1_EXP" ]; }
check $? "a consented whole-set push publishes exactly the managed set, nothing else (rc=$RC: $(br_names | tr '\n' '|'))"
OUT="$(bash "$SCRIPT" list-managed --tree "refs/heads/$BR" --root "$W/origin.git" 2>&1)"; RC=$?
{ [ "$RC" -eq 0 ] && [ "$OUT" = "$AC1_EXP" ]; }; check $? "list-managed --tree <branch> lists the branch tree's managed entries (rc=$RC)"
OUT="$(bash "$SCRIPT" list-managed --tree "refs/heads/$BR" --run-history --root "$W/origin.git" 2>&1)"; RC=$?
{ [ "$RC" -eq 0 ] && ! grep -q 'twin\|eval\|proposals' <<<"$OUT" && grep -qx "$RQ/x.md" <<<"$OUT"; }; check $? "list-managed --tree --run-history: run history only (rc=$RC)"
ms A list-managed --tracked --tree HEAD
[ "$RC" -eq 1 ]; check $? "--tracked with --tree is a usage error (rc=$RC)"
ms A status --run-history
[ "$RC" -eq 1 ]; check $? "--run-history on status is a usage error (rc=$RC)"
ms A push --learning
[ "$RC" -eq 1 ]; check $? "--learning on push is a usage error (rc=$RC)"
# symlinks and newline names under the new roots fail closed, exactly like the old roots
mkworld; clone A; ms A init
mkdir -p "$W/elsewhere" "$W/A/$TW"; echo x > "$W/elsewhere/c9.md"; ln -s "$W/elsewhere" "$W/A/$TC"
ms A list-managed
{ [ "$RC" -eq 1 ] && grep -q "meta_sync: symlink $TC" <<<"$OUT"; }; check $? "a symlinked twin/contracts folder fails closed, named (rc=$RC: $OUT)"
ms A push
{ [ "$RC" -eq 1 ] && [ -z "$(br_names)" ]; }; check $? "push refuses over it too, nothing published (rc=$RC)"
rm -f "$W/A/$TC"; mkdir -p "$W/A/$TC" "$W/A/.supervisor/eval"
ln -s "$W/elsewhere/c9.md" "$W/A/.supervisor/eval/results.jsonl"
ms A list-managed
{ [ "$RC" -eq 1 ] && grep -q "meta_sync: symlink $EV" <<<"$OUT"; }; check $? "a symlinked eval/results.jsonl (a managed file) fails closed (rc=$RC)"
rm -f "$W/A/$EV"
nlname="$(printf 'bad\nname.md')"; mkdir -p "$W/A/$PR"; echo x > "$W/A/$PR/$nlname"
ms A list-managed
{ [ "$RC" -eq 1 ] && grep -q 'newline_in_path' <<<"$OUT"; }; check $? "a newline name under agent-memory-proposals/ fails closed (rc=$RC)"

echo "== 68. mutation control: worker-summaries in is_managed must turn (67) red =="
MUT_WS="$TROOT/mutant-ws"
if build_mutant "$MUT_WS" 's/^is_managed() {$/is_managed() { case "$1" in .supervisor\/worker-summaries\/*.md) return 0 ;; esac  # mutant ws/' '# mutant ws'; then
  mkworld; clone A; ms A init
  twin_add A c1 "SYSTEM_CONTRACT: c1"
  put A "$PR/p1.md" "proposal"; put A "$EV" '{"run":1}'; put A "$EB" '{"base":1}'
  put A "$RQ/x.md" "x"; put A ".supervisor/automate/automate-1.dismissed-decisions" "$(printf 'd.md\tdrop\t2026-10-08T00:00:00Z')"
  put A ".supervisor/worker-summaries/1.md" "worker summary"
  # the mutant manages worker-summaries/ but its root is never enumerated; a tracked copy shows it
  git -C "$W/A" add -f ".supervisor/worker-summaries/1.md" >/dev/null 2>&1
  OUT="$(bash "$MUT_WS/meta-sync.sh" list-managed --tracked --root "$W/A" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && grep -qx ".supervisor/worker-summaries/1.md" <<<"$OUT"; then
    OUT2="$(bash "$SCRIPT" list-managed --tracked --root "$W/A" 2>&1)"
    if grep -q 'worker-summaries' <<<"$OUT2"; then no "mutation control (ws): the SHIPPED script lists worker-summaries too"; else ok "mutation control (ws): the mutant manages worker-summaries/1.md, the shipped script does not — the AC1 exclusion is load-bearing"; fi
  else
    no "mutation control (ws): the mutant failed for another reason (rc=$RC: $OUT) — control inconclusive"
  fi
else
  no "mutation control (ws): could not build the mutant — control inconclusive"
fi

echo "== 69. twin pair rule (AC2): a contract without its chain-valid add refuses the twin set on the side being written =="
twin_pair
sig0="$(twin_sig)"
printf 'SYSTEM_CONTRACT: rogue\n' > "$W/A/$TC/rogue.md"        # no provenance entry
put A "$RQ/y.md" "y run history"
ms A push
{ [ "$RC" -eq 0 ] && has_line "meta_sync: twin_refused $TC/rogue.md: no chain-valid add provenance entry" \
  && [ "$(twin_sig)" = "$sig0" ] && ! br_has "$TC/rogue.md" && [ "$(br_show "$RQ/y.md")" = "y run history" ]; }
check $? "push: twin_refused names the rogue contract, the branch's twin set is byte-unchanged, run history still pushes, exit 0 (rc=$RC: $OUT)"
AC2_PUSH_OUT="$OUT"
# pull side: the branch gains an unprovenanced contract (a sibling that skipped the rule) + run history
br_inject "$TC/rogue2.md" "SYSTEM_CONTRACT: rogue2" && br_inject "$RQ/z.md" "z from branch"
twinB0="$(cd "$W/B" && find .supervisor/twin -type f | env LC_ALL=C sort | xargs cksum)"
ms B pull
{ [ "$RC" -eq 0 ] && has_line "meta_sync: twin_refused $TC/rogue2.md: no chain-valid add provenance entry" \
  && [ ! -e "$W/B/$TC/rogue2.md" ] && [ "$(get B "$RQ/z.md")" = "z from branch" ] \
  && [ "$(cd "$W/B" && find .supervisor/twin -type f | env LC_ALL=C sort | xargs cksum)" = "$twinB0" ]; }
check $? "pull: twin_refused names the branch's rogue contract, nothing of the twin set written locally, run history still pulled, exit 0 (rc=$RC: $OUT)"

echo "== 70. mutation control: a pair check that always passes must turn (69) red =="
MUT_PAIR="$TROOT/mutant-pair"
if build_mutant "$MUT_PAIR" 's/^twin_pair_check() {$/twin_pair_check() { return 0  # mutant pair/' '# mutant pair'; then
  twin_pair
  printf 'SYSTEM_CONTRACT: rogue\n' > "$W/A/$TC/rogue.md"; put A "$RQ/y.md" "y run history"
  OUT="$(bash "$MUT_PAIR/meta-sync.sh" push --root "$W/A" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && br_has "$TC/rogue.md"; then ok "mutation control (pair): without the pair check the rogue contract reaches the branch — (69) is load-bearing"
  else no "mutation control (pair): the mutant failed for another reason (rc=$RC: $OUT) — control inconclusive"; fi
else
  no "mutation control (pair): could not build the mutant — control inconclusive"
fi

echo "== 71. provenance fork (AC3): both sides appended -> the twin set is refused (never a union), run history syncs =="
# fork_world — A appends c2 and pushes; B (synced before) appends c3 without pulling.
fork_world() {
  twin_pair
  twin_add A c2 "SYSTEM_CONTRACT: c2"; put A "$RQ/from-a.md" "from A"
  ms A push
  twin_add B c3 "SYSTEM_CONTRACT: c3"; put B "$RQ/from-b.md" "from B"
}
fork_world
provB0="$(cat "$W/B/$TP")"
ms B pull
{ [ "$RC" -eq 0 ] && has_line "meta_sync: twin_refused $TP: conflict" && [ "$(cat "$W/B/$TP")" = "$provB0" ] \
  && [ ! -e "$W/B/$TC/c2.md" ] && [ "$(get B "$RQ/from-a.md")" = "from A" ]; }
check $? "pull: twin_refused names .provenance.jsonl as a conflict, no line-union, nothing of the twin set written, run history pulled, exit 0 (rc=$RC: $OUT)"
sig0="$(twin_sig)"
ms B push
{ [ "$RC" -eq 0 ] && has_line "meta_sync: twin_refused $TP: conflict" && [ "$(twin_sig)" = "$sig0" ] && [ "$(br_show "$RQ/from-b.md")" = "from B" ]; }
check $? "push: the fork is refused again, the branch's twin set byte-unchanged, run history pushed, exit 0 (rc=$RC: $OUT)"
ms B status
{ [ "$RC" -eq 0 ] && [ "$OUT" = "synced $(br_tip) on $BR" ]; }; check $? "status's first line ignores the twin fork (got '$OUT')"
ms B status --learning
{ [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "learning: conflict 1; consent granted" ]; }; check $? "status --learning reports the fork on its own line (got: $(printf '%s' "$OUT" | tr '\n' '|'))"

echo "== 72. mutation control: provenance in the union-path predicate must turn (71) red =="
MUT_PU="$TROOT/mutant-prov-union"
if build_mutant "$MUT_PU" 's/^      if (p == ledger) return 1$/      if (p == ledger || p == ".supervisor\/twin\/.provenance.jsonl") return 1  # mutant prov-union/' '# mutant prov-union'; then
  fork_world
  OUT="$(bash "$MUT_PU/meta-sync.sh" pull --root "$W/B" 2>&1)"; RC=$?
  if ! has_line "meta_sync: twin_refused $TP: conflict"; then ok "mutation control (prov-union): a unioned provenance is no longer reported as a conflict — (71) is load-bearing (rc=$RC)"
  else no "mutation control (prov-union): the mutant still reported the conflict — control inconclusive"; fi
else
  no "mutation control (prov-union): could not build the mutant — control inconclusive"
fi

echo "== 73. meta-base after a twin-set refusal (AC3b): twin paths keep their previous entry; a whole-set push re-refuses =="
fork_world
base_tree() { head -n 1 "$W/$1/.git/meta-base"; }
prov_blob_before="$(git -C "$W/B" rev-parse "$(base_tree B):$TP" 2>/dev/null)"
ms B pull
{ [ "$RC" -eq 0 ] && [ "$(git -C "$W/B" rev-parse "$(base_tree B):$TP" 2>/dev/null)" = "$prov_blob_before" ] \
  && ! git -C "$W/B" cat-file -e "$(base_tree B):$TC/c2.md" 2>/dev/null \
  && [ "$(git -C "$W/B" rev-parse "$(base_tree B):$RQ/from-a.md" 2>/dev/null)" = "$(git --git-dir="$W/origin.git" rev-parse "refs/heads/$BR:$RQ/from-a.md")" ]; }
check $? "the refused pull's meta-base keeps the previous provenance entry, has no entry for the unreceived c2, and records run history as R (rc=$RC)"
sig0="$(twin_sig)"
ms B push
{ [ "$RC" -eq 0 ] && [ "$(twin_sig)" = "$sig0" ] && grep -q 'meta_sync: twin_refused' <<<"$OUT" && br_has "$TC/c2.md"; }
check $? "the follow-up whole-set push re-refuses: the branch's twin set is byte-unchanged (c2 not deleted, chain not overwritten) (rc=$RC: $OUT)"

echo "== 74. mutation control: recording R's tree for twin paths after a refusal must turn (73) red =="
MUT_RT="$TROOT/mutant-rt"
if build_mutant "$MUT_RT" 's/^    nb="\$(build_pull_base)" || die .*$/    nb="$RT"  # mutant rt/' '# mutant rt'; then
  fork_world
  bash "$MUT_RT/meta-sync.sh" pull --root "$W/B" >/dev/null 2>&1
  sig0="$(twin_sig)"
  OUT="$(bash "$MUT_RT/meta-sync.sh" push --root "$W/B" 2>&1)"; RC=$?
  if [ "$(twin_sig)" != "$sig0" ]; then ok "mutation control (rt): with R's tree recorded the follow-up push rewrites the branch's twin set (c2 deleted: $(br_has "$TC/c2.md" && echo no || echo yes)) — (73) is load-bearing"
  else no "mutation control (rt): the branch's twin set survived the mutant (rc=$RC: $OUT) — control inconclusive"; fi
else
  no "mutation control (rt): could not build the mutant — control inconclusive"
fi

echo "== 75. merge semantics (AC4): eval files line-union; dismissed-decisions ordered merge, the newer decision wins =="
DL=".supervisor/automate/automate-2026-10-08-000000.dismissed-decisions"
DRAFT="automate-2026-10-08-000000--01-x-abc123--dismissed-0123abcd.md"
# merge_world — A pushes a NEWER decision and an eval line; B holds an OLDER decision and another eval
# line (both unpushed), plus a summary-member row.
merge_world() {
  twin_pair
  mkdir -p "$W/A/.supervisor/automate"
  printf '%s\tfix-now\t2026-10-08T08:00:00Z\n' "$DRAFT" > "$W/A/$DL"; ms A push; ms B pull
  printf '%s\tdrop\t2026-10-08T10:00:00Z\n' "$DRAFT" >> "$W/A/$DL"
  printf '%s\n' '{"run":2}' >> "$W/A/$EV"; printf '%s\n' '{"base":2}' >> "$W/A/$EB"
  ms A push
  printf '%s\tfollow-up\t2026-10-08T09:00:00Z\nsummary-member\t0123abcd\tsummary.md\n' "$DRAFT" >> "$W/B/$DL"
  printf '%s\n' '{"run":3}' >> "$W/B/$EV"; printf '%s\n' '{"base":3}' >> "$W/B/$EB"
}
last_decision() { awk -F'\t' -v d="$DRAFT" '$1 == d { v = $2 } END { print v }' "$1"; }
merge_world
ms B pull
{ [ "$RC" -eq 0 ] && [ "$(cat "$W/B/$EV")" = "$(printf '%s\n' '{"run":1}' '{"run":2}' '{"run":3}')" ] \
  && [ "$(cat "$W/B/$EB")" = "$(printf '%s\n' '{"base":1}' '{"base":2}' '{"base":3}')" ]; }
check $? "both eval files line-union like the postmortem ledger: R's lines, then L's new ones (rc=$RC: $OUT)"
{ [ "$(last_decision "$W/B/$DL")" = "drop" ] && grep -qxF "$(printf 'summary-member\t0123abcd\tsummary.md')" "$W/B/$DL" \
  && [ "$(grep -c "^$DRAFT" "$W/B/$DL")" = "3" ]; }
check $? "dismissed-decisions: every distinct row kept, and the reader's last-row-wins yields the NEWER branch decision 'drop' over the older local 'follow-up' (got '$(last_decision "$W/B/$DL")')"
ms B push
{ [ "$RC" -eq 0 ] && [ "$(br_show "$EV")" = "$(cat "$W/B/$EV")" ] && [ "$(br_show "$DL")" = "$(cat "$W/B/$DL")" ]; }
check $? "push publishes the merged eval file and ledger (rc=$RC)"
# push-side merge (no pull first): the union the push writes to the branch is ordered too
merge_world
ms B push
{ [ "$RC" -eq 0 ] && [ "$(br_show "$DL" | awk -F'\t' -v d="$DRAFT" '$1 == d { v = $2 } END { print v }')" = "drop" ]; }
check $? "push-side ordered merge: the branch's last row for the draft is the newer 'drop' (rc=$RC)"

echo "== 76. mutation controls: plain union for dismissed-decisions, eval dropped from the predicate =="
MUT_DU="$TROOT/mutant-dismissed-union"
if build_mutant "$MUT_DU" 's/^    \.supervisor\/automate\/\*\.dismissed-decisions) ordered_merge/    __mutant_none__) ordered_merge/' '__mutant_none__) ordered_merge'; then
  merge_world
  OUT="$(bash "$MUT_DU/meta-sync.sh" pull --root "$W/B" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && [ "$(last_decision "$W/B/$DL")" = "follow-up" ]; then ok "mutation control (dismissed-union): a plain union lets the OLDER local decision win — (75) is load-bearing"
  else no "mutation control (dismissed-union): rc=$RC last='$(last_decision "$W/B/$DL")' — control inconclusive"; fi
else
  no "mutation control (dismissed-union): could not build the mutant — control inconclusive"
fi
MUT_EV="$TROOT/mutant-eval"
if build_mutant "$MUT_EV" 's/^      if (p == ".supervisor\/eval\/results.jsonl" || p == ".supervisor\/eval\/brain-baseline.jsonl") return 1$/      # mutant eval dropped/' '# mutant eval dropped'; then
  merge_world
  OUT="$(bash "$MUT_EV/meta-sync.sh" pull --root "$W/B" 2>&1)"; RC=$?
  if [ "$RC" -eq 1 ] && grep -q "meta_sync: conflict $EV" <<<"$OUT"; then ok "mutation control (eval): without the predicate the eval file conflicts (exit 1) — (75) is load-bearing"
  else no "mutation control (eval): rc=$RC — control inconclusive ($OUT)"; fi
else
  no "mutation control (eval): could not build the mutant — control inconclusive"
fi

echo "== 77. scrub legs per new file type (AC5): consent granted, each injected hit refuses (exit 2), nothing pushed =="
# scrub_world <path> <content> — a consented clone holding one learning file (+ a valid twin pair)
scrub_world() {
  mkworld; clone A; ms A init; grant A
  twin_add A c1 "SYSTEM_CONTRACT: c1"
  if [ -n "$1" ]; then put A "$1" "$2"; fi
}
TOK="ghp_$(printf 'a%.0s' $(seq 1 36))"
scrub_world "" ""
ms A push
{ [ "$RC" -eq 0 ] && br_has "$TC/c1.md"; }; check $? "clean control: a consented push of a clean twin pair lands (rc=$RC: $OUT)"
scrub_leg() { # scrub_leg <label> <path> <content> <rule>
  scrub_world "$2" "$3"
  ms A push
  { [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $2: $4" < <(printf '%s\n' "$OUT") && [ -z "$(br_names)" ]; }
  check $? "$1 -> exit 2 naming '$2: $4', nothing pushed (rc=$RC)"
}
scrub_leg "eval/results.jsonl with a home path" "$EV" '{"note":"/Users/alice/proj"}' home_path
scrub_leg "eval/results.jsonl with a token" "$EV" "{\"t\":\"$TOK\"}" token_github
scrub_leg "eval/brain-baseline.jsonl with a home path" "$EB" '{"p":"/home/bob/x"}' home_path
scrub_leg ".dismissed-decisions with a home path" ".supervisor/automate/automate-9.dismissed-decisions" "$(printf 'd.md\t/Users/carol/x\t2026-10-08T00:00:00Z')" home_path
scrub_leg ".dismissed-decisions with a token" ".supervisor/automate/automate-9.dismissed-decisions" "$(printf 'd.md\t%s\t2026-10-08T00:00:00Z' "$TOK")" token_github
scrub_leg "an agent-memory proposal with a home path" "$PR/p.md" "see /Users/dave/notes" home_path
scrub_world "" ""
twin_add A leaky "SYSTEM_CONTRACT: reads /Users/erin/secret"
ms A push
{ [ "$RC" -eq 2 ] && grep -qxF "meta_sync: scrub $TC/leaky.md: home_path" < <(printf '%s\n' "$OUT") && [ -z "$(br_names)" ]; }
check $? "a provenanced twin contract with a home path -> exit 2 naming it, nothing pushed (rc=$RC)"
MUT_SC="$TROOT/mutant-scrub"
if build_mutant "$MUT_SC" 's/^    \[ -n "\$p" \] || continue$/&; case "$p" in *.md|"$LEDGER_PATH") : ;; *) continue ;; esac  # mutant scrub/' '# mutant scrub'; then
  scrub_world "$EV" "{\"t\":\"$TOK\"}"
  OUT="$(bash "$MUT_SC/meta-sync.sh" push --root "$W/A" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && br_has "$EV"; then ok "mutation control (scrub): skipping non-.md candidates publishes the token — (77) is load-bearing"
  else no "mutation control (scrub): rc=$RC — control inconclusive"; fi
else
  no "mutation control (scrub): could not build the mutant — control inconclusive"
fi

echo "== 78. consent (AC6): no record / declined -> learning paths skipped and named, run history pushes; granted -> they push =="
# consent_world — a clone holding every learning store and one run-history file, consent NOT recorded
consent_world() {
  mkworld; clone A; ms A init
  twin_add A c1 "SYSTEM_CONTRACT: c1"
  put A "$PR/p1.md" "proposal"; put A "$EV" '{"run":1}'; put A "$EB" '{"base":1}'
  put A "$RQ/x.md" "x"
}
LEARN_PATHS="$(printf '%s\n' "$PR/p1.md" "$EB" "$EV" "$TP" "$TC/c1.md" | env LC_ALL=C sort)"
consent_skipped_ok() {
  local p
  [ "$RC" -eq 0 ] || return 1
  for p in $LEARN_PATHS; do has_line "meta_sync: learning_skipped $p — no consent (run /setup memory)" || return 1; done
  [ "$(br_names)" = "$RQ/x.md" ]
}
consent_world
ms A push
consent_skipped_ok; check $? "no record: every learning path named learning_skipped, only run history on the branch, exit 0 (rc=$RC: $OUT)"
ms A status --learning
{ [ "$(printf '%s\n' "$OUT" | head -n 1)" = "synced $(br_tip) on $BR" ] && [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "learning: local_ahead 5; consent none" ]; }
check $? "after a skipped push: status's first line is synced, --learning says local_ahead 5 (meta-base kept them unconsidered) (got: $(printf '%s' "$OUT" | tr '\n' '|'))"
ms A push
{ [ "$RC" -eq 0 ] && has_line "meta_sync: no_changes"; }; check $? "a second unconsented push: learning still skipped, run history has nothing -> no_changes, exit 0 (rc=$RC)"
consent_world; grant A decline
ms A push
consent_skipped_ok; check $? "declined: the same skip, exit 0 (rc=$RC)"
grant A grant
ms A push
{ [ "$RC" -eq 0 ] && [ "$(br_names | env LC_ALL=C sort)" = "$(printf '%s\n' $LEARN_PATHS "$RQ/x.md" | env LC_ALL=C sort)" ] && ! grep -q learning_skipped <<<"$OUT"; }
check $? "granted (after a declined push): the learning stores push (rc=$RC: $(br_names | tr '\n' '|'))"
# --paths-from (trail-pr's shape) never reads the record and never names a learning path
consent_world
printf '%s\n' "$RQ/x.md" > "$W/pf.list"
ms A push --paths-from "$W/pf.list"
{ [ "$RC" -eq 0 ] && ! grep -q 'learning_skipped\|twin_refused' <<<"$OUT" && [ "$(br_names)" = "$RQ/x.md" ]; }
check $? "a --paths-from push of run history is unchanged: no learning line, only the listed path (rc=$RC: $OUT)"
# pull takes learning-store paths regardless of consent
consent_world; grant A; ms A push; clone C
ms C pull
{ [ "$RC" -eq 0 ] && [ "$(get C "$PR/p1.md")" = "proposal" ] && [ -f "$W/C/$TC/c1.md" ]; }
check $? "pull takes the learning stores from the branch (consent governs publishing only) (rc=$RC)"

echo "== 79. mutation control: a consent read that always grants must turn (78) red =="
MUT_CO="$TROOT/mutant-consent"
if build_mutant "$MUT_CO" 's/^read_consent() {$/read_consent() { CONSENT=granted; return 0  # mutant consent/' '# mutant consent'; then
  consent_world
  OUT="$(bash "$MUT_CO/meta-sync.sh" push --root "$W/A" 2>&1)"; RC=$?
  if [ "$RC" -eq 0 ] && br_has "$TC/c1.md"; then ok "mutation control (consent): an always-granted read publishes the learning stores — (78) is load-bearing"
  else no "mutation control (consent): rc=$RC — control inconclusive"; fi
else
  no "mutation control (consent): could not build the mutant — control inconclusive"
fi

echo "== 80. status split (AC7): learning-only differences never change the first line =="
twin_pair
put A "$PR/p2.md" "new proposal"; printf '%s\n' '{"run":2}' >> "$W/A/$EV"
ms A status
[ "$OUT" = "synced $(br_tip) on $BR" ]; check $? "learning-only local changes: first line synced (got '$OUT')"
ms A status --paths
[ "$OUT" = "synced $(br_tip) on $BR" ]; check $? "with --paths too (got '$OUT')"
ms A status --learning
[ "$OUT" = "$(printf '%s\n' "synced $(br_tip) on $BR" "learning: local_ahead 2; consent granted")" ]; check $? "--learning adds ONE learning line (got: $(printf '%s' "$OUT" | tr '\n' '|'))"
put A "$RQ/x.md" "x v2"
ms A status --paths --learning
[ "$OUT" = "$(printf '%s\n' "local_ahead 1" "  $RQ/x.md" "learning: local_ahead 2; consent granted")" ]; check $? "a run-history change: local_ahead 1 naming only x.md, the learning line last (got: $(printf '%s' "$OUT" | tr '\n' '|'))"
ms A push; ms B status
[ "$(printf '%s\n' "$OUT")" = "remote_ahead" ]; check $? "B sees run history remote_ahead (got '$OUT')"
ms B pull; put A "$PR/p3.md" "another"; ms A push; ms B status
[ "$OUT" = "synced $(br_tip) on $BR" ]; check $? "a learning-only remote change does not print remote_ahead (got '$OUT')"

echo "== 81. mutation control: counting learning paths in the first line must turn (80) red =="
MUT_ST="$TROOT/mutant-status"
if build_mutant "$MUT_ST" 's/^  split_learning_rows || .*$/  : > "$WORK\/plan.learning"  # mutant status/' '# mutant status'; then
  twin_pair
  put A "$PR/p2.md" "new proposal"
  OUT="$(bash "$MUT_ST/meta-sync.sh" status --root "$W/A" 2>&1)"
  if [ "$OUT" = "local_ahead 1" ]; then ok "mutation control (status): the mutant prints local_ahead for a learning-only change — (80) is load-bearing"
  else no "mutation control (status): got '$OUT' — control inconclusive"; fi
else
  no "mutation control (status): could not build the mutant — control inconclusive"
fi

echo "== 82. round trip (AC8): the twin store verifies the same in a fresh clone; the other stores are byte-identical =="
mkworld; clone A; ms A init; grant A
( cd "$W/A" && printf 'SYSTEM_CONTRACT: app\ninvariants: [prints code]\n' | bash "$HERE/write-system-contract.sh" --subsystem app --source "session:fixture-0001" >/dev/null 2>&1 \
  && printf 'SYSTEM_CONTRACT: lib\ninvariants: [pure]\n' | bash "$HERE/write-system-contract.sh" --subsystem lib --source "session:fixture-0001" >/dev/null 2>&1 )
put A "$PR/p1.md" "proposal one"; put A "$EV" '{"run":1}'; put A "$EB" '{"base":1}'
mkdir -p "$W/A/.supervisor/automate"; printf '%s\tdrop\t2026-10-08T00:00:00Z\n' "$DRAFT" > "$W/A/$DL"
rsc() { (cd "$W/$1" && bash "$HERE/read-system-contract.sh" 2>/dev/null) | grep '^twin_store_status:'; }
SRC_TS="$(rsc A)"
ms A push; prc=$RC
clone F; ms F pull
{ [ "$prc" -eq 0 ] && [ "$RC" -eq 0 ] && [ "$SRC_TS" = "twin_store_status: healthy (emitted 2, dropped 0, stored 2)" ] && [ "$(rsc F)" = "$SRC_TS" ]; }
check $? "read-system-contract.sh in the fresh clone: '$(rsc F)' = the source's '$SRC_TS'"
okf=0
for p in "$PR/p1.md" "$EV" "$EB" "$DL" "$TP"; do cmp -s "$W/A/$p" "$W/F/$p" || { okf=1; echo "    differs: $p"; }; done
[ "$okf" -eq 0 ]; check $? "proposals, dismissed ledger, eval files and the provenance chain are byte-identical in the fresh clone"

echo "== 83. a tracked learning store is git's: pull and push leave it alone, run history syncs =="
# tracked_leg — A publishes $EV (consent granted) and B pulls it; B force-tracks $EV on its code
# branch with a local line while A appends another on the branch; then B pulls and pushes. 0 = the
# tracked file byte-unchanged and named, the branch copy unchanged by B's push, run history both
# ways, meta-base's $EV entry the one agreed before tracking, exit 0 throughout. Detail in TK_DETAIL.
tracked_leg() {
  local b0 r0 base_ev v1
  TK_DETAIL=""
  mkworld; clone A; clone B; ms A init; grant A
  put A "$EV" '{"run":1}'; put A "$RQ/x.md" "x"; ms A push; ms B pull
  [ "$RC" -eq 0 ] || { TK_DETAIL="setup pull rc=$RC"; return 1; }
  v1="$(git -C "$W/B" hash-object --no-filters -- "$W/B/$EV")"
  printf '%s\n' '{"run":"b-local"}' >> "$W/B/$EV"
  ( cd "$W/B" && git add -f -- "$EV" && git commit -qm "track eval" ) >/dev/null 2>&1 || { TK_DETAIL="could not track $EV"; return 1; }
  printf '%s\n' '{"run":2}' >> "$W/A/$EV"; put A "$RQ/y.md" "y"; ms A push
  [ "$RC" -eq 0 ] || { TK_DETAIL="sibling push rc=$RC"; return 1; }
  b0="$(cat "$W/B/$EV")"; r0="$(br_show "$EV")"
  ms B pull
  base_ev="$(git -C "$W/B" ls-tree "$(head -n 1 "$W/B/.git/meta-base")" -- "$EV" 2>/dev/null | awk '{print $3}')"
  TK_DETAIL="pull rc=$RC same-bytes=$([ "$(cat "$W/B/$EV")" = "$b0" ] && echo yes || echo no) y=$(get B "$RQ/y.md") porcelain='$(porcelain B | tr '\n' ' ')' base-ev=${base_ev:-none}"
  { [ "$RC" -eq 0 ] && has_line "meta_sync: learning_tracked $EV — tracked by git, left to git" \
    && [ "$(cat "$W/B/$EV")" = "$b0" ] && [ "$(get B "$RQ/y.md")" = "y" ] && [ -z "$(porcelain B)" ] \
    && [ "$base_ev" = "$v1" ]; } || return 1
  put B "$RQ/z.md" "z"; ms B push
  TK_DETAIL="$TK_DETAIL; push rc=$RC branch-ev-same=$([ "$(br_show "$EV")" = "$r0" ] && echo yes || echo no) z-on-branch=$(br_has "$RQ/z.md" && echo yes || echo no)"
  { [ "$RC" -eq 0 ] && has_line "meta_sync: learning_tracked $EV — tracked by git, left to git" \
    && ! grep -q "learning_skipped" <<<"$OUT" && [ "$(br_show "$EV")" = "$r0" ] && br_has "$RQ/z.md" \
    && [ "$(cat "$W/B/$EV")" = "$b0" ] && git -C "$W/B" ls-files --error-unmatch -- "$EV" >/dev/null 2>&1; } || return 1
  ms B status --learning
  TK_DETAIL="$TK_DETAIL; status='$(printf '%s' "$OUT" | tr '\n' '|')'"
  [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "learning: synced; consent granted; tracked 1" ]
}
tracked_leg; check $? "a tracked learning store is left to git: pull and push leave it byte-unchanged and name it, run history syncs, meta-base keeps the agreed entry ($TK_DETAIL)"

echo "== 84. mutation control: without the tracked-learning hold (83) must turn red =="
MUT_TK="$TROOT/mutant-tracked"
if build_mutant "$MUT_TK" 's/^tracked_learning_hold() {$/tracked_learning_hold() { TRACKED_N=0; return 0  # mutant tracked/' '# mutant tracked'; then
  SCRIPT="$MUT_TK/meta-sync.sh"
  if tracked_leg; then no "mutation control (tracked) REFUTED: the leg stayed green without the hold ($TK_DETAIL)"
  else ok "mutation control (tracked): without the hold the tracked file is rewritten — (83) is load-bearing ($TK_DETAIL)"; fi
  SCRIPT="$SUT"
else
  no "mutation control (tracked): could not build the mutant — control inconclusive"
fi

echo "== 85. an inherited GIT_INDEX_FILE cannot hide a tracked learning store from the hold =="
# tracked_env_leg — (83)'s world (B tracks $EV with a local line, A appends another on the branch),
# then B pulls with GIT_INDEX_FILE=/nonexistent EXPORTED: git reads a missing index as empty with
# exit 0, so a hold that honoured it would see "nothing tracked" and union into the tracked file.
# 0 = the tracked file byte-unchanged, named `learning_tracked`, `git status` clean. Detail in TE_DETAIL.
tracked_env_leg() {
  local b0
  TE_DETAIL=""
  mkworld; clone A; clone B; ms A init; grant A
  put A "$EV" '{"run":1}'; put A "$RQ/x.md" "x"; ms A push; ms B pull
  [ "$RC" -eq 0 ] || { TE_DETAIL="setup pull rc=$RC"; return 1; }
  printf '%s\n' '{"run":"b-local"}' >> "$W/B/$EV"
  ( cd "$W/B" && git add -f -- "$EV" && git commit -qm "track eval" ) >/dev/null 2>&1 || { TE_DETAIL="could not track $EV"; return 1; }
  printf '%s\n' '{"run":2}' >> "$W/A/$EV"; ms A push
  [ "$RC" -eq 0 ] || { TE_DETAIL="sibling push rc=$RC"; return 1; }
  b0="$(cat "$W/B/$EV")"
  OUT="$(export GIT_INDEX_FILE=/nonexistent; bash "$SCRIPT" pull --root "$W/B" 2>&1)"; RC=$?
  TE_DETAIL="pull rc=$RC same-bytes=$([ "$(cat "$W/B/$EV")" = "$b0" ] && echo yes || echo no) porcelain='$(porcelain B | tr '\n' ' ')' named=$(has_line "meta_sync: learning_tracked $EV — tracked by git, left to git" && echo yes || echo no)"
  [ "$(cat "$W/B/$EV")" = "$b0" ] && has_line "meta_sync: learning_tracked $EV — tracked by git, left to git" \
    && [ -z "$(porcelain B)" ]
}
tracked_env_leg; check $? "an exported GIT_INDEX_FILE=/nonexistent does not hide the tracked store: the pull leaves it byte-unchanged and names it, git status clean ($TE_DETAIL)"

echo "== 86. mutation control: a hold that honours the inherited GIT_INDEX_FILE must turn (85) red =="
MUT_TE="$TROOT/mutant-tracked-env"
if build_mutant "$MUT_TE" 's/^  env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "$ROOT" ls-files -z -- \.supervisor\/twin /  g ls-files -z -- .supervisor\/twin /' '  g ls-files -z -- .supervisor/twin '; then
  SCRIPT="$MUT_TE/meta-sync.sh"
  if tracked_env_leg; then no "mutation control (tracked env) REFUTED: the leg stayed green with the inherited index honoured ($TE_DETAIL)"
  else ok "mutation control (tracked env): honouring the inherited GIT_INDEX_FILE rewrites the tracked file — (85) is load-bearing ($TE_DETAIL)"; fi
  SCRIPT="$SUT"
else
  no "mutation control (tracked env): could not build the mutant — control inconclusive"
fi

echo "== 87. an inherited GIT_INDEX_FILE cannot empty list-managed --tracked =="
# lm_tracked_env_leg — A commits one managed path on its code branch, then runs list-managed
# --tracked with GIT_INDEX_FILE=/nonexistent EXPORTED: git reads a missing index as empty with exit
# 0, so a read that honoured it would list nothing (migrate-branch-mode.sh would see no tracked set).
# 0 = exit 0 and exactly the committed path listed. Detail in LT_DETAIL.
lm_tracked_env_leg() {
  LT_DETAIL=""
  mkworld; clone A
  put A "$RQ/t.md" "tracked"
  ( cd "$W/A" && git add -f -- "$RQ/t.md" && git commit -qm "track t" ) >/dev/null 2>&1 || { LT_DETAIL="could not track $RQ/t.md"; return 1; }
  OUT="$(export GIT_INDEX_FILE=/nonexistent; bash "$SCRIPT" list-managed --tracked --root "$W/A" 2>&1)"; RC=$?
  LT_DETAIL="rc=$RC out='$(printf '%s' "$OUT" | tr '\n' '|')'"
  [ "$RC" -eq 0 ] && [ "$OUT" = "$RQ/t.md" ]
}
lm_tracked_env_leg; check $? "an exported GIT_INDEX_FILE=/nonexistent does not empty list-managed --tracked: the committed path is listed, exit 0 ($LT_DETAIL)"

echo "== 88. mutation control: a list-managed --tracked that honours the inherited GIT_INDEX_FILE must turn (87) red =="
MUT_LT="$TROOT/mutant-lm-tracked-env"
if build_mutant "$MUT_LT" 's/^    env -u GIT_INDEX_FILE -u GIT_DIR -u GIT_WORK_TREE git -C "$ROOT" ls-files -z -- \.supervisor > /    g ls-files -z -- .supervisor > /' '    g ls-files -z -- .supervisor > '; then
  SCRIPT="$MUT_LT/meta-sync.sh"
  if lm_tracked_env_leg; then no "mutation control (list-managed tracked env) REFUTED: the leg stayed green with the inherited index honoured ($LT_DETAIL)"
  else ok "mutation control (list-managed tracked env): honouring the inherited GIT_INDEX_FILE lists nothing — (87) is load-bearing ($LT_DETAIL)"; fi
  SCRIPT="$SUT"
else
  no "mutation control (list-managed tracked env): could not build the mutant — control inconclusive"
fi

