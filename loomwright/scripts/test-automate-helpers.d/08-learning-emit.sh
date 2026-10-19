# =============================================================================
echo "== F. learning-emit (engine-native ground-truth POSTMORTEM_RESULT line) =="

# F1. happy path fix_cycles>0 → exactly ONE drain_churn categories[] entry,
#     review_rounds == fix_cycles, valid JSON, source==automate_drain, changed_paths populated.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 42 --pr-url "$PR" --run-id "run1" --item "item-a" \
  --fix-cycles 3 --drain-result READY \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --changed-paths-json '["src/a.ts","src/b.ts"]' --additions 10 --deletions 2 --changed-files 2 \
  --summary "automate drain churn"
if [ -f "$LED" ] && [ "$(wc -l < "$LED" | tr -d ' ')" = "1" ] \
   && jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.source' "$LED")" = "automate_drain" ] \
   && [ "$(jq -r '.review_rounds' "$LED")" = "3" ] \
   && [ "$(jq -r '.categories | length' "$LED")" = "1" ] \
   && [ "$(jq -r '.categories[0].class' "$LED")" = "drain_churn" ] \
   && [ "$(jq -r '.categories[0].round' "$LED")" = "3" ] \
   && [ "$(jq -r '.changed_paths | length' "$LED")" = "2" ] \
   && [ "$(jq -r '.flow_stages.self_heal' "$LED")" = "3" ] \
   && [ "$(jq -r '.schema_version' "$LED")" = "1" ]; then
  ok "happy path fix_cycles>0: one drain_churn entry, review_rounds==fix_cycles, changed_paths populated, valid JSON"
else
  no "happy-path wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F2. fix_cycles==0 non-escalated → categories: [] AND review_rounds: 0 (zero-rule; NO synthetic entry).
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 43 --pr-url "$PR" --run-id "run2" --item "item-b" \
  --fix-cycles 0 --drain-result READY \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --changed-paths-json '["src/c.ts"]' --additions 1 --deletions 0 --changed-files 1 \
  --summary "clean merge"
if jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.categories | length' "$LED")" = "0" ] \
   && [ "$(jq -r '.review_rounds' "$LED")" = "0" ] \
   && [ "$(jq -r '.flow_stages.self_heal' "$LED")" = "0" ]; then
  ok "zero-rule: fix_cycles==0 non-escalated ⇒ categories:[] AND review_rounds:0 (no fake churn)"
else
  no "zero-rule wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F3. zero-cycle ESCALATED (fix_cycles==0, drain_result==ESCALATED) → review_rounds:1 + ONE drain_escalation entry.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 44 --pr-url "$PR" --run-id "run3" --item "item-c" \
  --fix-cycles 0 --drain-result ESCALATED \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --changed-paths-json '["src/d.ts"]' --additions 5 --deletions 5 --changed-files 1 \
  --summary "escalated before any fix cycle"
if jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.review_rounds' "$LED")" = "1" ] \
   && [ "$(jq -r '.categories | length' "$LED")" = "1" ] \
   && [ "$(jq -r '.categories[0].class' "$LED")" = "drain_escalation" ] \
   && [ "$(jq -r '.categories[0].round' "$LED")" = "1" ] \
   && [ "$(jq -r '.flow_stages.self_heal' "$LED")" = "1" ]; then
  ok "zero-cycle ESCALATED: review_rounds:1 + ONE drain_escalation entry"
else
  no "zero-cycle-escalated wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F4. idempotency: two calls with the SAME run_id+item+pr_url+source → ledger has exactly ONE line.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
for i in 1 2; do
  bash "$H" learning-emit "$LED" \
    --repo "acme/widgets" --number 45 --pr-url "$PR" --run-id "run4" --item "item-d" \
    --fix-cycles 2 --drain-result READY \
    --repeat-check-failure false --unresolved-bot-feedback false \
    --changed-paths-json '["src/e.ts"]' --additions 3 --deletions 1 --changed-files 1 \
    --summary "dup attempt"
done
if [ "$(wc -l < "$LED" | tr -d ' ')" = "1" ]; then
  ok "idempotency: duplicate run_id+item+pr_url+source key ⇒ exactly ONE line"
else
  no "idempotency wrong (lines=$(wc -l < "$LED" 2>/dev/null | tr -d ' '))"
fi
rm -rf "$WD"

# F5. missing-field degrade (omit --changed-paths-json) → still exit 0, line written with changed_paths: [].
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
run_h bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 46 --pr-url "$PR" --run-id "run5" --item "item-e" \
  --fix-cycles 1 --drain-result READY \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --summary "no changed-paths arg"
if [ "$RUN_RC" -eq 0 ] && jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.changed_paths | length' "$LED")" = "0" ] \
   && [ "$(jq -r '.changed_paths | type' "$LED")" = "array" ]; then
  ok "missing-field degrade: exit 0, line written, changed_paths:[]"
else
  no "missing-field-degrade wrong (rc=$RUN_RC line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F6. jq-absent → exit 0, NO write (point LOOMWRIGHT_JQ_BIN at a nonexistent binary).
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
run_h env LOOMWRIGHT_JQ_BIN="$WD/no-such-jq-binary" bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 47 --pr-url "$PR" --run-id "run6" --item "item-f" \
  --fix-cycles 1 --drain-result READY --summary "jq absent"
if [ "$RUN_RC" -eq 0 ] && [ ! -f "$LED" ]; then
  ok "jq-absent: exit 0, NO write"
else
  no "jq-absent wrong (rc=$RUN_RC led-exists=$([ -f "$LED" ] && echo y || echo n))"
fi
rm -rf "$WD"

# F7. fetch-fail degrade → changed_paths: [] AND additions/deletions/changed_files are integer 0 (NOT null).
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
# Simulate the loop's degraded call: changed_paths_json defaults to [], size fields to 0.
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 48 --pr-url "$PR" --run-id "run7" --item "item-g" \
  --fix-cycles 0 --drain-result READY \
  --changed-paths-json '[]' --additions 0 --deletions 0 --changed-files 0 \
  --summary "fetch failed, degraded"
if jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.changed_paths | length' "$LED")" = "0" ] \
   && [ "$(jq -r '.additions | type' "$LED")" = "number" ] \
   && [ "$(jq -r '.additions' "$LED")" = "0" ] \
   && [ "$(jq -r '.deletions' "$LED")" = "0" ] \
   && [ "$(jq -r '.changed_files' "$LED")" = "0" ]; then
  ok "fetch-fail degrade: changed_paths:[], additions/deletions/changed_files integer 0 (not null)"
else
  no "fetch-fail-degrade wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F8. injection-safe: --summary / --pr-url with ";, $(...), quotes → still valid single-line JSON, value verbatim.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
INJ_SUMMARY='evil"; rm -rf / $(touch /tmp/pwned) `id` end'
INJ_URL='https://github.com/a/b/pull/1"; echo hacked #'
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 49 --pr-url "$INJ_URL" --run-id "run8" --item "item-h" \
  --fix-cycles 1 --drain-result READY \
  --changed-paths-json '["src/x.ts"]' --additions 1 --deletions 0 --changed-files 1 \
  --summary "$INJ_SUMMARY"
if [ "$(wc -l < "$LED" | tr -d ' ')" = "1" ] && jq -e . "$LED" >/dev/null 2>&1 \
   && [ "$(jq -r '.summary' "$LED")" = "$INJ_SUMMARY" ] \
   && [ "$(jq -r '.pr_url' "$LED")" = "$INJ_URL" ] \
   && [ ! -f /tmp/pwned ]; then
  ok "injection-safe: malicious summary/pr_url preserved verbatim, still valid single-line JSON"
else
  no "injection-safe wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -f /tmp/pwned
rm -rf "$WD"

# F9. self_heal_misses derivation: repeat_check_failure=true → self_heal_misses:1 and entry self_heal_miss:true.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 50 --pr-url "$PR" --run-id "run9" --item "item-i" \
  --fix-cycles 2 --drain-result READY \
  --repeat-check-failure true --unresolved-bot-feedback false \
  --changed-paths-json '["src/y.ts"]' --additions 4 --deletions 2 --changed-files 1 \
  --summary "repeat check failure"
if [ "$(jq -r '.self_heal_misses' "$LED")" = "1" ] \
   && [ "$(jq -r '.categories[0].self_heal_miss' "$LED")" = "true" ]; then
  ok "self_heal_misses: repeat_check_failure=true ⇒ self_heal_misses:1 + entry self_heal_miss:true"
else
  no "self_heal_misses wrong (line='$(cat "$LED" 2>/dev/null)')"
fi
rm -rf "$WD"

# F10. read-postmortem.sh visibility (reasoned via the reader's OWN selection jq):
#      read-postmortem.sh:159 [pins: `changed_paths overlap the query set`] keeps a corpus
#      line iff (a) repo matches the reader's
#      current repo case-insensitively WHEN the reader's repo is determinable, AND (b) its
#      changed_paths overlaps the query path set; then it counts each categories[] element as
#      one prior-churn round. We replicate BOTH predicates faithfully (an earlier version of
#      this test omitted the repo clause — PR #77 review finding #3 — so it could not have
#      caught an empty-repo line being dropped; that blind spot is closed below + in F11).
# reader_select <ledger> <query_path> <cur_repo>  -> JSON array of {rounds} for matching lines.
reader_select() {
  jq -R 'fromjson? // empty' "$1" \
    | jq -s --arg q "$2" --arg cur_repo "$3" '
        [ .[]
          | . as $e
          | select($cur_repo == "" or ((($e.repo) // "") | ascii_downcase) == ($cur_repo | ascii_downcase))
          | select(((($e.changed_paths) // []) | map(select(. == $q)) | length) > 0)
          | {rounds: ((($e.categories) // []) | length)}
        ]' 2>/dev/null
}
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 51 --pr-url "$PR" --run-id "run10" --item "item-j" \
  --fix-cycles 2 --drain-result READY \
  --repeat-check-failure false --unresolved-bot-feedback false \
  --changed-paths-json '["src/visible.ts"]' --additions 3 --deletions 1 --changed-files 1 \
  --summary "visible to reader"
# F10a: matching repo (exact + case-insensitive) AND path overlap ⇒ 1 hit, 1 round.
HITS="$(reader_select "$LED" "src/visible.ts" "acme/widgets")"
HITS_CI="$(reader_select "$LED" "src/visible.ts" "ACME/Widgets")"
if [ "$(printf '%s' "$HITS" | jq 'length')" = "1" ] \
   && [ "$(printf '%s' "$HITS" | jq '.[0].rounds')" = "1" ] \
   && [ "$(printf '%s' "$HITS_CI" | jq 'length')" = "1" ]; then
  ok "read-postmortem visibility: automate_drain line IS a prior-churn hit (repo match (case-insensitive) + changed_paths overlap + 1 categories round)"
else
  no "read-postmortem visibility wrong (hits='$HITS' hits_ci='$HITS_CI')"
fi
rm -rf "$WD"

# F11. --repo is load-bearing for visibility (the PR #77 finding #1 failure mode): a line
#      emitted with an EMPTY --repo carries repo:"" (NOT null) and is DROPPED by the reader
#      whenever the reader's repo resolves — yet stays visible only when the reader's repo is
#      undeterminable (cur_repo=="", the vacuously-true arm). This is the regression guard that
#      would have surfaced finding #1.
WD="$(mktemp -d)"; LED="$WD/results.jsonl"
bash "$H" learning-emit "$LED" \
  --repo "" --number 52 --pr-url "$PR" --run-id "run11" --item "item-k" \
  --fix-cycles 1 --drain-result READY \
  --changed-paths-json '["src/visible.ts"]' --additions 1 --deletions 0 --changed-files 1 \
  --summary "empty repo"
EMITTED_REPO="$(tail -1 "$LED" | jq -r '.repo')"
DROPPED="$(reader_select "$LED" "src/visible.ts" "acme/widgets" | jq 'length')"
KEPT_WHEN_UNDET="$(reader_select "$LED" "src/visible.ts" "" | jq 'length')"
if [ "$EMITTED_REPO" = "" ] \
   && [ "$DROPPED" = "0" ] \
   && [ "$KEPT_WHEN_UNDET" = "1" ]; then
  ok "read-postmortem visibility: empty --repo emits repo:\"\" and is DROPPED when the reader's repo resolves (--repo is load-bearing)"
else
  no "empty-repo visibility wrong (emitted_repo='$EMITTED_REPO' dropped='$DROPPED' kept_when_undet='$KEPT_WHEN_UNDET')"
fi
rm -rf "$WD"

# F12. DEGRADED-then-CORRECTIVE emit (the PR #126 defect). A first emit that degraded
#      (the single `gh pr view` fetch failed, or the caller omitted the fetch args)
#      writes changed_paths:[] — a line PERMANENTLY INVISIBLE to read-postmortem.sh.
#      Before the degradation-aware key, that line poisoned the automate_key and every
#      later complete emit was silently skipped. Asserted against the REAL
#      read-postmortem.sh (NOT the reader_select jq mirror, which could drift from the
#      reader it models) inside a throwaway git repo whose origin remote makes the
#      reader's CUR_REPO resolve, so repo scoping is exercised too.
WD="$(mktemp -d)"
( cd "$WD" && git init -q && git config user.email t@t && git config user.name t \
    && git remote add origin https://github.com/acme/widgets.git \
    && echo i > f && git add f && git commit -qm i ) >/dev/null 2>&1
LED="$WD/.supervisor/postmortem/results.jsonl"
READ_PM="$HERE/read-postmortem.sh"

# 1st emit: DEGRADED — no --changed-paths-json / --number / size args (fetch failed).
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --pr-url "$PR" --run-id "run12" --item "item-l" \
  --fix-cycles 4 --drain-result READY \
  --repeat-check-failure true --unresolved-bot-feedback false \
  --summary "degraded: gh pr view failed"
# 2nd emit: CORRECTIVE — same run_id+item+pr_url+source, now WITH the real data.
bash "$H" learning-emit "$LED" \
  --repo "acme/widgets" --number 126 --pr-url "$PR" --run-id "run12" --item "item-l" \
  --fix-cycles 4 --drain-result READY \
  --repeat-check-failure true --unresolved-bot-feedback false \
  --changed-paths-json '["src/corrected.ts"]' --additions 9 --deletions 3 --changed-files 1 \
  --summary "corrective: full data"

# The load-bearing assertion: the REAL reader now returns a prior-churn hit for the path,
# and the ledger carries exactly ONE complete (visible) line — no duplicate good lines.
READER_OUT="$( cd "$WD" && bash "$READ_PM" "src/corrected.ts" 2>/dev/null )"
N_COMPLETE="$(jq -R 'fromjson? // empty' "$LED" 2>/dev/null \
  | jq -s '[ .[] | select(((.changed_paths // []) | length) > 0) ] | length' 2>/dev/null)"
if grep -q "src/corrected.ts" < <(printf '%s' "$READER_OUT") && [ "$N_COMPLETE" = "1" ]; then
  ok "degraded-then-corrective: corrective emit NOT skipped and read-postmortem.sh returns it (exactly ONE complete line)"
else
  no "degraded-then-corrective wrong (reader_out='$READER_OUT' n_complete='$N_COMPLETE' ledger='$(cat "$LED" 2>/dev/null)')"
fi

# F12b. MUTATION CONTROL — proves F12 is load-bearing, not vacuously green. Pre-seed a
#       ledger with the OLD (pre-discriminator) degraded key shape, i.e. byte-for-byte
#       what the buggy version wrote for PR #126. Under the old "any key match ⇒ skip"
#       rule the corrective emit is suppressed and the reader stays silent forever;
#       under the fix the legacy degraded line is a match that does NOT block a complete
#       emit. BEFORE must be empty and AFTER must hit — if the skip rule ever regresses,
#       this case flips to FAIL.
WD2="$(mktemp -d)"
( cd "$WD2" && git init -q && git config user.email t@t && git config user.name t \
    && git remote add origin https://github.com/acme/widgets.git \
    && echo i > f && git add f && git commit -qm i ) >/dev/null 2>&1
LED2="$WD2/.supervisor/postmortem/results.jsonl"; mkdir -p "$(dirname "$LED2")"
LEGACY_KEY="$(jq -rn --arg a run13 --arg b item-m --arg c "$PR" --arg d automate_drain \
  '[$a,$b,$c,$d] | join("\u001f")')"
NOW_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -cn --arg k "$LEGACY_KEY" --arg u "$PR" --arg ts "$NOW_TS" \
  '{schema_version:1, ts:$ts, repo:"acme/widgets", number:0, review_rounds:4,
    categories:[{round:4,class:"drain_churn",self_heal_miss:true,flow_stage:"self_heal",evidence:"legacy"}],
    self_heal_misses:1, changed_paths:[], pr_url:$u,
    source:"automate_drain", automate_key:$k}' > "$LED2"
BEFORE="$( cd "$WD2" && bash "$READ_PM" "src/corrected.ts" 2>/dev/null )"
bash "$H" learning-emit "$LED2" \
  --repo "acme/widgets" --number 126 --pr-url "$PR" --run-id "run13" --item "item-m" \
  --fix-cycles 4 --drain-result READY \
  --repeat-check-failure true --unresolved-bot-feedback false \
  --changed-paths-json '["src/corrected.ts"]' --additions 9 --deletions 3 --changed-files 1 \
  --summary "corrective over a LEGACY degraded key"
AFTER="$( cd "$WD2" && bash "$READ_PM" "src/corrected.ts" 2>/dev/null )"
if [ -z "$BEFORE" ] && grep -q "src/corrected.ts" < <(printf '%s' "$AFTER"); then
  ok "mutation control: a LEGACY (pre-discriminator) degraded key is invisible BEFORE and correctable AFTER (skip rule is load-bearing)"
else
  no "legacy-degraded correction wrong (before='$BEFORE' after='$AFTER' ledger='$(cat "$LED2" 2>/dev/null)')"
fi

# F12c. No-regression on the two skip arms the fix must NOT loosen: a DEGRADED emit
#       AFTER a complete one must be skipped (never regress a good line to an invisible
#       one), and a second COMPLETE emit must be skipped (at most one good line).
bash "$H" learning-emit "$LED2" \
  --repo "acme/widgets" --pr-url "$PR" --run-id "run13" --item "item-m" \
  --fix-cycles 4 --drain-result READY --summary "late degraded retry"
bash "$H" learning-emit "$LED2" \
  --repo "acme/widgets" --number 126 --pr-url "$PR" --run-id "run13" --item "item-m" \
  --fix-cycles 4 --drain-result READY \
  --changed-paths-json '["src/corrected.ts"]' --additions 9 --deletions 3 --changed-files 1 \
  --summary "duplicate complete"
if [ "$(wc -l < "$LED2" | tr -d ' ')" = "2" ]; then
  ok "no-regression: degraded-after-complete AND complete-after-complete are both skipped (ledger stays at 2 lines)"
else
  no "skip-arm regression (lines=$(wc -l < "$LED2" 2>/dev/null | tr -d ' ') ledger='$(cat "$LED2" 2>/dev/null)')"
fi
rm -rf "$WD" "$WD2"

# F13. The REALISTIC degraded shape: --number IS passed. F12/F12b/F12c all degrade by
#      omitting --number, which matches the helper's internal default but NOT the real
#      /automate invocation: skills/automate-loop/SKILL.md 6 derives `repo` AND `number`
#      from pr_url in the "inputs the engine already holds" bullet, BEFORE and independent
#      of "the ONE added fetch" that is the thing that actually degrades. So a
#      contract-compliant degraded emit carries the REAL number, and the degraded and
#      corrective lines SHARE the repo#number key that build-loop-evidence.sh and
#      measure-heal-signal.py join on. Pins that the correction still lands in that shape
#      (the earlier "number:0 quarantines the degraded line" rationale was wrong).
WD3="$(mktemp -d)"
( cd "$WD3" && git init -q && git config user.email t@t && git config user.name t \
    && git remote add origin https://github.com/acme/widgets.git \
    && echo i > f && git add f && git commit -qm i ) >/dev/null 2>&1
LED3="$WD3/.supervisor/postmortem/results.jsonl"
# Degraded, but WITH the pr_url-derived --number (only the fetch-dependent args degrade).
bash "$H" learning-emit "$LED3" \
  --repo "acme/widgets" --number 77 --pr-url "$PR" --run-id "run14" --item "item-n" \
  --fix-cycles 2 --drain-result READY \
  --changed-paths-json '[]' --additions 0 --deletions 0 --changed-files 0 \
  --summary "degraded WITH real number"
# Corrective, after a resume that added fix cycles (2 -> 5): the floor RISES.
bash "$H" learning-emit "$LED3" \
  --repo "acme/widgets" --number 77 --pr-url "$PR" --run-id "run14" --item "item-n" \
  --fix-cycles 5 --drain-result READY \
  --changed-paths-json '["src/shared.ts"]' --additions 7 --deletions 2 --changed-files 1 \
  --summary "corrective WITH real number"
N3="$(wc -l < "$LED3" | tr -d ' ')"
SAME_KEY="$(jq -R 'fromjson? // empty' "$LED3" 2>/dev/null \
  | jq -s '[ .[] | ((.repo|ascii_downcase) + "#" + (.number|tostring)) ] | unique | length' 2>/dev/null)"
VIS3="$( cd "$WD3" && bash "$READ_PM" "src/shared.ts" 2>/dev/null )"
if [ "$N3" = "2" ] && [ "$SAME_KEY" = "1" ] && grep -q "src/shared.ts" < <(printf '%s' "$VIS3"); then
  ok "realistic degraded shape (--number passed): correction still appends, both lines SHARE repo#number, reader returns the complete one"
else
  no "realistic-degraded wrong (lines='$N3' distinct_repo_number_keys='$SAME_KEY' reader='$VIS3')"
fi

# F13b. The downstream consequence of F13, shown at the EMIT site: with both lines under ONE
#       repo#number key, a first-wins join reports the STALE lower review_rounds. Append order
#       is degraded(2) then complete(5), so `head -1` yields 2 and floor-raising yields 5.
#       SCOPE — read this before trusting it: the jq below is a hand-copied MIRROR of
#       build-loop-evidence.sh's projection + representative pick, and a mirror can silently
#       drift from the script it models (the exact objection F12 raises against reader_select).
#       It is kept only to make the trap legible next to the emit it originates from. The
#       AUTHORITATIVE regression net for that join is test-build-loop-evidence.sh case (13),
#       which drives the REAL builder over a two-line fixture; if this mirror and case (13)
#       ever disagree, case (13) is right.
PMPROJ="$(jq -R 'fromjson? // empty' "$LED3" 2>/dev/null | jq -c '
  { key: (((.repo // "") | tostring | ascii_downcase) + "#" + ((.number // "") | tostring)),
    review_rounds: (.review_rounds // null), ts: ((.ts // "") | tostring) }')"
FIRST_WINS="$(printf '%s\n' "$PMPROJ" | head -1 | jq -r '.review_rounds')"
FLOOR_WINS="$(printf '%s\n' "$PMPROJ" | jq -s -r 'max_by([(.review_rounds // -1), (.ts // "")]) | .review_rounds')"
if [ "$FIRST_WINS" = "2" ] && [ "$FLOOR_WINS" = "5" ]; then
  ok "floor-raising join is load-bearing: first-wins would report the STALE 2, max-review_rounds reports the true 5"
else
  no "floor-raising join wrong (first_wins='$FIRST_WINS' floor_wins='$FLOOR_WINS')"
fi
rm -rf "$WD3"

# F13c. A second DEGRADED emit when ONLY a degraded line exists (no complete line yet).
#       F12c exercises the degraded skip arm only in a ledger that ALSO holds a complete
#       line, so this pins the arm in isolation: still exactly one line, still no duplicate
#       invisible entry.
WD4="$(mktemp -d)"; LED4="$WD4/results.jsonl"
for i in 1 2; do
  bash "$H" learning-emit "$LED4" \
    --repo "acme/widgets" --number 78 --pr-url "$PR" --run-id "run15" --item "item-o" \
    --fix-cycles 1 --drain-result READY --summary "degraded twice"
done
if [ "$(wc -l < "$LED4" | tr -d ' ')" = "1" ]; then
  ok "degraded-after-degraded (no complete line present): skipped ⇒ exactly ONE line"
else
  no "degraded-twice wrong (lines=$(wc -l < "$LED4" 2>/dev/null | tr -d ' '))"
fi
rm -rf "$WD4"

# F13d. changed_paths of only EMPTY strings is DEGRADED, not complete. An empty string is
#       not a usable path — read-postmortem.sh drops empty query paths before matching, so
#       `[""]` is exactly as invisible as `[]`. Classing it complete would re-open this very
#       defect: an unusable line permanently blocking its own correction.
WD5="$(mktemp -d)"; LED5="$WD5/results.jsonl"
bash "$H" learning-emit "$LED5" \
  --repo "acme/widgets" --number 79 --pr-url "$PR" --run-id "run16" --item "item-p" \
  --fix-cycles 1 --drain-result READY --changed-paths-json '[""]' --summary "empty-string path"
bash "$H" learning-emit "$LED5" \
  --repo "acme/widgets" --number 79 --pr-url "$PR" --run-id "run16" --item "item-p" \
  --fix-cycles 1 --drain-result READY --changed-paths-json '["src/real.ts"]' --summary "corrective"
if [ "$(wc -l < "$LED5" | tr -d ' ')" = "2" ] \
   && [ "$(tail -1 "$LED5" | jq -r '.changed_paths[0]')" = "src/real.ts" ]; then
  ok "empty-string-only changed_paths is DEGRADED (not complete) — it cannot block its own correction"
else
  no "empty-string-path classification wrong (lines=$(wc -l < "$LED5" 2>/dev/null | tr -d ' ') ledger='$(cat "$LED5" 2>/dev/null)')"
fi
rm -rf "$WD5"

# F14–F19. --self-heal-rounds (the Phase 4.5 self-heal churn the PR absorbed BEFORE the
#          drain; the OBSERVED SUPERVISOR_RESULT.heal_iterations). The PR #267 shape:
#          self-heal round 1 FAIL → fix → round 2 PASS, drain 0 fix cycles — before this
#          flag the line read review_rounds:0 + categories:[] and the reader called the
#          most-churned area clean. Every visibility claim below runs the REAL
#          read-postmortem.sh (not the reader_select mirror) in a throwaway repo whose
#          origin resolves to the emitted line's repo, ledger at the reader's default path.
SHR_PR="https://github.com/acme/widgets/pull/267"
SHR_ITEM=".supervisor/requirements/automate-followups/01-learning-emit-counts-self-heal-rounds.md"
# shr_emit <helper> <ledger> <run_id> [extra learning-emit args...] — the AC1 base call.
shr_emit() {
  local helper="$1" led="$2" rid="$3"; shift 3
  bash "$helper" learning-emit "$led" \
    --repo "acme/widgets" --number 267 --pr-url "$SHR_PR" --run-id "$rid" --item "$SHR_ITEM" \
    --repeat-check-failure false --unresolved-bot-feedback false \
    --changed-paths-json '["src/heal.ts","src/other.ts"]' --additions 5 --deletions 1 --changed-files 2 \
    --plugin-version 9.9.9 --branch feat/x "$@"
}
# shr_repo — a throwaway git repo whose origin makes the reader's CUR_REPO acme/widgets.
shr_repo() {
  local d; d="$(mktemp -d)"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t \
      && git remote add origin https://github.com/acme/widgets.git \
      && echo i > f && git add f && git commit -qm i ) >/dev/null 2>&1
  printf '%s' "$d"
}
# shr_ac1_holds <helper> — 0 iff the AC1 claim holds for <helper>: the emitted line carries
# self_heal_rounds:2 + review_rounds:0 + exactly one self_heal_churn{round:2} entry, AND the
# REAL reader prints `self_heal_churn (1)` on its classes line and `1` on its rounds line.
# Parametrised on the helper so the F19 mutant is judged by the identical predicate.
SHR_OUT=""; SHR_LINE=""
shr_ac1_holds() {
  local helper="$1" d led
  d="$(shr_repo)"; led="$d/.supervisor/postmortem/results.jsonl"
  shr_emit "$helper" "$led" "run-shr-ac1" --self-heal-rounds 2 --fix-cycles 0 --drain-result READY
  SHR_LINE="$(cat "$led" 2>/dev/null)"
  SHR_OUT="$( cd "$d" && bash "$READ_PM" "src/heal.ts" 2>/dev/null )"
  rm -rf "$d"
  [ "$(printf '%s' "$SHR_LINE" | jq -r '.self_heal_rounds' 2>/dev/null)" = "2" ] || return 1
  [ "$(printf '%s' "$SHR_LINE" | jq -r '.review_rounds' 2>/dev/null)" = "0" ] || return 1
  [ "$(printf '%s' "$SHR_LINE" | jq -c '[.categories[] | {class, round}]' 2>/dev/null)" \
      = '[{"class":"self_heal_churn","round":2}]' ] || return 1
  grep -qxF -- "- recurring root-cause classes: self_heal_churn (1)" < <(printf '%s\n' "$SHR_OUT") || return 1
  grep -qE -- '^- prior churn rounds: 1 \(' < <(printf '%s\n' "$SHR_OUT") || return 1
  return 0
}

# F14 (AC1). self-heal 2, drain 0 ⇒ self_heal_rounds:2, review_rounds:0, ONE self_heal_churn
#      entry — and the REAL reader surfaces it as a prior-churn hit (the false-0 closed).
if shr_ac1_holds "$H"; then
  ok "self-heal-rounds: --self-heal-rounds 2 + drain 0 ⇒ self_heal_rounds:2, review_rounds:0, one self_heal_churn(round 2); REAL reader prints 'self_heal_churn (1)' + rounds 1"
else
  no "self-heal-rounds AC1 wrong (line='$SHR_LINE' reader='$SHR_OUT')"
fi

# F15 (AC2). BACK-COMPAT PIN: the same call WITHOUT the flag is byte-identical (after
#      deleting ts) to the PRE-CHANGE helper's line, and carries no self_heal_rounds key.
#      Frozen golden = `git show 05ad3057a9628992e7f7fbf6f3f62868ca97f85a:loomwright/scripts/automate-helpers.sh`
#      run on these exact args, piped through `jq -c 'del(.ts)'` (the pinned base commit,
#      never a moving origin/main). A frozen literal, so a shallow CI clone that lacks the
#      base commit still enforces it; when the base commit IS reachable the live base helper
#      is ALSO run as a cross-check that the golden was transcribed correctly.
SHR_GOLDEN='{"schema_version":1,"repo":"acme/widgets","number":267,"agent_generated_guess":true,"review_rounds":0,"additions":5,"deletions":1,"changed_files":2,"categories":[],"self_heal_misses":0,"flow_stages":{"launch_pad":0,"worker":0,"self_heal":0,"unknowable":0},"summary":"automate drain: no churn","plugin_version":"9.9.9","pr_url":"https://github.com/acme/widgets/pull/267","branch":"feat/x","changed_paths":["src/heal.ts","src/other.ts"],"brief_path":null,"job_path":null,"source":"automate_drain","automate_key":"run-shr-ac2\u001f.supervisor/requirements/automate-followups/01-learning-emit-counts-self-heal-rounds.md\u001fhttps://github.com/acme/widgets/pull/267\u001fautomate_drain\u001fcomplete"}'
WD6="$(mktemp -d)"
shr_emit "$H" "$WD6/new.jsonl" "run-shr-ac2" --fix-cycles 0 --drain-result READY
NEW_NOFLAG="$(jq -c 'del(.ts)' "$WD6/new.jsonl" 2>/dev/null)"
HAS_KEY="$(jq -r 'has("self_heal_rounds")' "$WD6/new.jsonl" 2>/dev/null)"
BASE_REV="05ad3057a9628992e7f7fbf6f3f62868ca97f85a"
BASE_XCHECK="skipped (base commit not reachable — frozen golden is authoritative)"
if git -C "$HERE" cat-file -e "$BASE_REV^{commit}" 2>/dev/null \
   && git -C "$HERE" show "$BASE_REV:loomwright/scripts/automate-helpers.sh" > "$WD6/base-helpers.sh" 2>/dev/null \
   && [ -s "$WD6/base-helpers.sh" ]; then
  shr_emit "$WD6/base-helpers.sh" "$WD6/base.jsonl" "run-shr-ac2" --fix-cycles 0 --drain-result READY
  if [ "$(jq -c 'del(.ts)' "$WD6/base.jsonl" 2>/dev/null)" = "$SHR_GOLDEN" ]; then
    BASE_XCHECK="ok"
  else
    BASE_XCHECK="MISMATCH"
  fi
fi
if [ "$NEW_NOFLAG" = "$SHR_GOLDEN" ] && [ "$HAS_KEY" = "false" ] && [ "$BASE_XCHECK" != "MISMATCH" ]; then
  ok "self-heal-rounds back-compat: no flag ⇒ byte-identical (minus ts) to the pre-change helper's line, no self_heal_rounds key (live base cross-check: $BASE_XCHECK)"
else
  no "self-heal-rounds back-compat wrong (has_key='$HAS_KEY' base_xcheck='$BASE_XCHECK' new='$NEW_NOFLAG')"
fi
rm -rf "$WD6"

# F16 (AC3). normalization is fail-SAFE: abc / -1 / 1.5 / "" ⇒ exit 0, line emitted,
#      self_heal_rounds:0, NO self_heal_churn entry. And the restated zero-rule: an explicit
#      0 with drain 0 READY ⇒ self_heal_rounds:0, review_rounds:0, categories:[] exactly.
SHR_BAD=""
for v in "abc" "-1" "1.5" ""; do
  WD7="$(mktemp -d)"; LED7="$WD7/results.jsonl"
  run_h shr_emit "$H" "$LED7" "run-shr-ac3" --self-heal-rounds "$v" --fix-cycles 0 --drain-result READY
  if [ "$RUN_RC" -ne 0 ] || [ "$(wc -l < "$LED7" 2>/dev/null | tr -d ' ')" != "1" ] \
     || [ "$(jq -r '.self_heal_rounds' "$LED7" 2>/dev/null)" != "0" ] \
     || [ "$(jq -r '[.categories[] | select(.class == "self_heal_churn")] | length' "$LED7" 2>/dev/null)" != "0" ]; then
    SHR_BAD="$SHR_BAD [v='$v' rc=$RUN_RC line=$(cat "$LED7" 2>/dev/null)]"
  fi
  rm -rf "$WD7"
done
WD7="$(mktemp -d)"; LED7="$WD7/results.jsonl"
shr_emit "$H" "$LED7" "run-shr-ac3z" --self-heal-rounds 0 --fix-cycles 0 --drain-result READY
if [ -z "$SHR_BAD" ] \
   && [ "$(jq -r '.self_heal_rounds' "$LED7")" = "0" ] \
   && [ "$(jq -r '.review_rounds' "$LED7")" = "0" ] \
   && [ "$(jq -c '.categories' "$LED7")" = "[]" ]; then
  ok "self-heal-rounds normalization: abc/-1/1.5/\"\" ⇒ exit 0 + self_heal_rounds:0 + no self_heal_churn; explicit 0 + drain 0 ⇒ categories:[] exactly (zero-rule)"
else
  no "self-heal-rounds normalization/zero-rule wrong (bad=$SHR_BAD zero_line='$(cat "$LED7" 2>/dev/null)')"
fi
rm -rf "$WD7"

# F16b. surrounding whitespace is trimmed before the digit check (a grep/awk-extracted
#       " 2" / "2 " / "3\n" must NOT be silently recorded as 0 — the false-0 this item
#       exists to prevent); INTERNAL whitespace ("1 2") and whitespace-only still ⇒ 0.
SHR_WS_BAD=""
for pair in " 2|2" "2 |2" $'3\n|3' $'\t4 |4' "1 2|0" "  |0"; do
  v="${pair%|*}"; want="${pair##*|}"
  WD7="$(mktemp -d)"; LED7="$WD7/results.jsonl"
  run_h shr_emit "$H" "$LED7" "run-shr-ws" --self-heal-rounds "$v" --fix-cycles 0 --drain-result READY
  got="$(jq -r '.self_heal_rounds' "$LED7" 2>/dev/null)"
  if [ "$RUN_RC" -ne 0 ] || [ "$got" != "$want" ]; then
    SHR_WS_BAD="$SHR_WS_BAD [v='$v' want=$want got=$got rc=$RUN_RC]"
  fi
  rm -rf "$WD7"
done
if [ -z "$SHR_WS_BAD" ]; then
  ok "self-heal-rounds trims surrounding whitespace (' 2'/'2 '/'3\\n'/tab ⇒ value) while internal/whitespace-only ⇒ 0"
else
  no "self-heal-rounds whitespace handling wrong:$SHR_WS_BAD"
fi

# F17 (AC3b + AC4). ordering — self-heal precedes the drain, and review_rounds stays
#      DRAIN-ONLY. 1 + zero-cycle ESCALATED ⇒ [self_heal_churn(1), drain_escalation(1)],
#      review_rounds:1. 1 + fix_cycles 3 READY ⇒ [self_heal_churn(1), drain_churn(3)],
#      review_rounds:3, and the REAL reader's rounds line reports 2.
WD8="$(mktemp -d)"; LED8="$WD8/esc.jsonl"
shr_emit "$H" "$LED8" "run-shr-ac3b" --self-heal-rounds 1 --fix-cycles 0 --drain-result ESCALATED
D8="$(shr_repo)"; LED8B="$D8/.supervisor/postmortem/results.jsonl"
shr_emit "$H" "$LED8B" "run-shr-ac4" --self-heal-rounds 1 --fix-cycles 3 --drain-result READY
READ8="$( cd "$D8" && bash "$READ_PM" "src/heal.ts" 2>/dev/null )"
if [ "$(jq -r '.review_rounds' "$LED8")" = "1" ] \
   && [ "$(jq -r '.self_heal_rounds' "$LED8")" = "1" ] \
   && [ "$(jq -c '[.categories[] | {class, round}]' "$LED8")" = '[{"class":"self_heal_churn","round":1},{"class":"drain_escalation","round":1}]' ] \
   && [ "$(jq -r '.review_rounds' "$LED8B")" = "3" ] \
   && [ "$(jq -r '.self_heal_rounds' "$LED8B")" = "1" ] \
   && [ "$(jq -r '.flow_stages.self_heal' "$LED8B")" = "3" ] \
   && [ "$(jq -c '[.categories[] | {class, round}]' "$LED8B")" = '[{"class":"self_heal_churn","round":1},{"class":"drain_churn","round":3}]' ] \
   && grep -qE -- '^- prior churn rounds: 2 \(' < <(printf '%s\n' "$READ8") \
   && grep -qF "self_heal_churn (1)" < <(grep -E -- '^- recurring root-cause classes: ' < <(printf '%s\n' "$READ8")) \
   && grep -qF "drain_churn (1)" < <(grep -E -- '^- recurring root-cause classes: ' < <(printf '%s\n' "$READ8")); then
  ok "self-heal-rounds ordering: self_heal_churn precedes drain_escalation/drain_churn; review_rounds + flow_stages.self_heal stay drain-only; REAL reader rounds 2"
else
  no "self-heal-rounds ordering wrong (esc='$(cat "$LED8" 2>/dev/null)' combined='$(cat "$LED8B" 2>/dev/null)' reader='$READ8')"
fi
rm -rf "$WD8" "$D8"

# F18 (AC5). idempotency: the automate_key is byte-identical with and without the flag,
#      and a re-entry for the same run/item/PR writes nothing new — in BOTH orders.
WD9="$(mktemp -d)"
shr_emit "$H" "$WD9/a.jsonl" "run-shr-ac5" --self-heal-rounds 2 --fix-cycles 1 --drain-result READY
shr_emit "$H" "$WD9/b.jsonl" "run-shr-ac5" --fix-cycles 1 --drain-result READY
KEY_A="$(jq -r '.automate_key' "$WD9/a.jsonl" 2>/dev/null)"
KEY_B="$(jq -r '.automate_key' "$WD9/b.jsonl" 2>/dev/null)"
# a.jsonl already holds the WITH-flag line: re-enter with AND without the flag.
shr_emit "$H" "$WD9/a.jsonl" "run-shr-ac5" --self-heal-rounds 2 --fix-cycles 1 --drain-result READY
shr_emit "$H" "$WD9/a.jsonl" "run-shr-ac5" --fix-cycles 1 --drain-result READY
# b.jsonl already holds the WITHOUT-flag line: re-enter WITH the flag.
shr_emit "$H" "$WD9/b.jsonl" "run-shr-ac5" --self-heal-rounds 2 --fix-cycles 1 --drain-result READY
if [ -n "$KEY_A" ] && [ "$KEY_A" = "$KEY_B" ] \
   && [ "$(wc -l < "$WD9/a.jsonl" | tr -d ' ')" = "1" ] \
   && [ "$(wc -l < "$WD9/b.jsonl" | tr -d ' ')" = "1" ]; then
  ok "self-heal-rounds idempotency: automate_key identical with/without the flag; re-entry (either order) writes nothing new"
else
  no "self-heal-rounds idempotency wrong (key_a='$KEY_A' key_b='$KEY_B' a_lines=$(wc -l < "$WD9/a.jsonl" | tr -d ' ') b_lines=$(wc -l < "$WD9/b.jsonl" | tr -d ' '))"
fi
rm -rf "$WD9"

# F19 (AC6). MUTATION CONTROL — proves F14 is load-bearing: a COPY of the helper whose
#      parsed --self-heal-rounds value is never plumbed into the record (the jq arg is
#      forced to 0) must FAIL the identical shr_ac1_holds predicate. The mutant is trusted
#      only when non-empty, differs from the original, and passes `bash -n` (lesson
#      fa32a308: an unvalidated mutant that silently equals the original, or does not
#      parse, "fails" for the wrong reason and proves nothing).
WD10="$(mktemp -d)"; MUT="$WD10/automate-helpers.sh"
sed 's/--argjson shr "\$shr_json"/--argjson shr 0/' "$H" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$H" "$MUT" && bash -n "$MUT" 2>/dev/null \
   && [ "$(grep -c -- '--argjson shr 0' "$MUT")" = "1" ]; then
  if shr_ac1_holds "$MUT"; then
    no "self-heal-rounds mutation control: F14's predicate still PASSES against a mutant that never plumbs the value (vacuous)"
  elif shr_ac1_holds "$H"; then
    ok "self-heal-rounds mutation control: a validated mutant (value forced to 0) FAILS the F14 predicate while the real helper passes it"
  else
    no "self-heal-rounds mutation control: real helper no longer passes the F14 predicate"
  fi
else
  no "self-heal-rounds mutation control: mutant invalid (empty / identical to original / bash -n failed / anchor not found)"
fi
rm -rf "$WD10"

# F20. flag-first call (ledger path omitted) — the ledger path is the FIRST positional, so
#      `learning-emit --repo …` used to append the line to a file literally named `--repo`
#      in the cwd (seen in lane clones and the primary checkout: `--repo`, `--run-id`,
#      `--help`). Each such call must exit 0, leave the cwd EMPTY, and print exactly ONE
#      stderr line naming the expected call shape; a ledger-first call still appends one line.
# le_flag_first_holds <helper> — 0 iff every flag-first/empty-ledger case holds.
le_flag_first_holds() {
  local helper="$1" c d err rc
  for c in repo run-id help empty; do
    d="$(mktemp -d)"
    case "$c" in
      repo)   err="$( cd "$d" && bash "$helper" learning-emit --repo acme/widgets --pr-url "$PR" --run-id run-ff --item item-ff 2>&1 >/dev/null )"; rc=$? ;;
      run-id) err="$( cd "$d" && bash "$helper" learning-emit --run-id run-ff --repo acme/widgets --pr-url "$PR" --item item-ff 2>&1 >/dev/null )"; rc=$? ;;
      help)   err="$( cd "$d" && bash "$helper" learning-emit --help 2>&1 >/dev/null )"; rc=$? ;;
      empty)  err="$( cd "$d" && bash "$helper" learning-emit "" --repo acme/widgets --pr-url "$PR" --run-id run-ff --item item-ff 2>&1 >/dev/null )"; rc=$? ;;
    esac
    if [ "$rc" -ne 0 ] || [ -n "$(ls -A "$d")" ] \
       || [ "$(printf '%s' "$err" | grep -c '')" != "1" ] \
       || [ "$(printf '%s' "$err" | grep -cF 'learning-emit <ledger_path> --repo')" != "1" ]; then
      LE_FF_WHY="case=$c rc=$rc cwd='$(ls -A "$d" | tr '\n' ' ')' stderr='$err'"
      rm -rf "$d"; return 1
    fi
    rm -rf "$d"
  done
  return 0
}
LE_FF_WHY=""
if le_flag_first_holds "$H"; then
  ok "flag-first learning-emit (--repo / --run-id / --help / empty first arg): exit 0, cwd unchanged, ONE stderr usage line"
else
  no "flag-first learning-emit wrote or misreported ($LE_FF_WHY)"
fi
WD11="$(mktemp -d)"
( cd "$WD11" && bash "$H" learning-emit results.jsonl --repo acme/widgets --pr-url "$PR" --run-id run-ff --item item-ff )
if [ "$(ls -A "$WD11")" = "results.jsonl" ] && [ "$(wc -l < "$WD11/results.jsonl" | tr -d ' ')" = "1" ]; then
  ok "ledger-first learning-emit still appends exactly ONE line (and nothing else in the cwd)"
else
  no "ledger-first learning-emit wrong (cwd='$(ls -A "$WD11" | tr '\n' ' ')')"
fi
rm -rf "$WD11"
# Mutation control: a validated copy of the bundle whose refusal pattern can never match
# must FAIL the predicate (else F20 is vacuous).
WD12="$(mktemp -d)"; MUT="$WD12/automate-helpers.sh"
sed "s/''|-\*)   # not a ledger path/__never__)   # not a ledger path/" "$H" > "$MUT"
if [ -s "$MUT" ] && ! cmp -s "$H" "$MUT" && bash -n "$MUT" 2>/dev/null \
   && [ "$(grep -c '__never__)   # not a ledger path' "$MUT")" = "1" ]; then
  if le_flag_first_holds "$MUT"; then
    no "flag-first mutation control: the predicate still PASSES with the refusal disabled (vacuous)"
  else
    ok "flag-first mutation control: a mutant with the refusal disabled FAILS the F20 predicate"
  fi
else
  no "flag-first mutation control: mutant invalid (empty / identical to original / bash -n failed / anchor not found)"
fi
rm -rf "$WD12"

