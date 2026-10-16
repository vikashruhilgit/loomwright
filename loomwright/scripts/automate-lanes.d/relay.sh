# _lanes_hook_root <cwd> — prints the lane checkout a hook's cwd belongs to; returns 1 when none.
# A question asked from a worker's linked worktree (../{repo}-{task_id}-{slug}: OUTSIDE the lane dir,
# no lane.json) must still reach the LANE's inbox, so the cwd's own toplevel is not enough: the lane is
# the MAIN checkout of the cwd's repository, the parent of its git common dir. `--path-format=absolute`
# needs git >= 2.31; an older git (no absolute answer) is asked again from the toplevel, where its
# relative answer resolves unambiguously. Candidates, first holding a non-empty lane.json wins: that
# main checkout, the cwd's toplevel, the cwd itself.
_lanes_hook_root() {
  local cwd="$1" top gcd main="" c nl
  nl="$(printf '\nx')"; nl="${nl%x}"
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"
  gcd="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  case "$gcd" in *"$nl"*|"") gcd="" ;; /*) ;; *) gcd="" ;; esac
  if [ -z "$gcd" ] && [ -n "$top" ]; then
    gcd="$(git -C "$top" rev-parse --git-common-dir 2>/dev/null)"
    case "$gcd" in *"$nl"*|"") gcd="" ;; /*) ;; *) gcd="$(cd "$top" 2>/dev/null && cd "$gcd" 2>/dev/null && pwd -P)" ;; esac
  fi
  [ -n "$gcd" ] && [ "$(basename "$gcd")" = .git ] && main="$(dirname "$gcd")"
  for c in "$main" "$top" "$cwd"; do
    [ -n "$c" ] && [ -s "$c/.supervisor/lane.json" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

# ==================================================================================================
# relay-hook — PreToolUse[AskUserQuestion]: answer recorded ⇒ allow + updatedInput, else record + defer.
#              PermissionRequest[AskUserQuestion] (bundled call, defer ignored) ⇒ deny with a re-ask.
lanes_relay_hook() {
  local in ev cwd root id q a
  in="$(cat)"
  ev="$(jq -r '.hook_event_name // empty' <<<"$in" 2>/dev/null)"
  if [ "$ev" = "PermissionRequest" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"AskUserQuestion must be the ONLY tool call in its turn (the answer is relayed to the owner). Call AskUserQuestion again, alone, in a turn of its own."}}}'
    return 0
  fi
  [ "$ev" = "PreToolUse" ] || { echo '{}'; return 0; }
  cwd="$(jq -r '.cwd // empty' <<<"$in" 2>/dev/null)"; [ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
  root="$(_lanes_hook_root "$cwd")" || { echo '{}'; return 0; }   # HOOK-ROOT
  [ -s "$root/.supervisor/lane.json" ] || { echo '{}'; return 0; }
  id="$(jq -r '.tool_use_id // empty' <<<"$in" 2>/dev/null)"
  case "$id" in ''|*[!A-Za-z0-9_-]*) echo '{}'; return 0 ;; esac
  q="$root/.supervisor/inbox/questions/$id.json"; a="$root/.supervisor/inbox/answers/$id.json"
  mkdir -p "$(dirname "$q")" "$(dirname "$a")" 2>/dev/null
  if [ ! -s "$a" ]; then
    jq -c --arg at "$(now_utc)" '{id: .tool_use_id, asked_at: $at, questions: .tool_input.questions}' <<<"$in" > "$q.tmp.$$" \
      && mv "$q.tmp.$$" "$q" && _lanes_supersede_older "$root" "$id"
    # No policy answer (policy null, `human`, any error) ⇒ exactly the pre-policy defer.
    _lanes_policy_apply "$root" "$q" "$a" \
      || { echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"defer"}}'; return 0; }
  fi
  jq -c --slurpfile ans "$a" '
    ($ans[0].answers) as $A | ($ans[0].note) as $N
    | {hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow",
        permissionDecisionReason: (if $ans[0].source == "policy"
          then "answered by the stamped lane policy (gate \($ans[0].gate // "?"), policy_sha \(($ans[0].policy_sha // "?")[0:12])) via automate-lanes.sh relay-hook"
          else "answered by the owner via automate-lanes.sh lane-answer" end),
        updatedInput: ({questions: .tool_input.questions, answers: $A}
          + (if ($N // "") == "" then {} else {annotations: ($A | with_entries(.value = {notes: $N}))} end))}}' <<<"$in"
}

# _lanes_policy_apply <lane_root> <question_file> <answer_file> — B6: the lane's OWN hook applies a
# policy answer. Returns 1 (caller defers to the human, unchanged) unless lane.json carries a `policy`
# object, `lane-policy.sh decide` answers EVERY question of the call, that answer passes
# _lanes_validate_answers (the owner's own validator) and the answer file is written. The answer file
# mirrors lane-answer's shape with `source: "policy"`, `policy_sha`, `gate` (the call's catalog codes,
# comma-joined) and `via: "policy"`. The `## Progress` line is fail-SAFE: a failed append never blocks
# the answer (the answer file is the record the lane reads).
_lanes_policy_apply() {
  local root="$1" q="$2" af="$3" lj="$1/.supervisor/lane.json" dec ain out sha gate run line
  jq -e '(.policy | type) == "object"' "$lj" >/dev/null 2>&1 || return 1
  [ -s "$q" ] || return 1
  dec="$(bash "$POLICY" decide "$q" --policy-json "$lj" 2>/dev/null </dev/null)" || return 1
  jq -e 'type == "object" and length > 0' >/dev/null 2>&1 <<<"$dec" || return 1   # `human` ⇒ the owner
  ain="$(jq -c '{answers: .}' <<<"$dec" 2>/dev/null)" || return 1
  out="$(_lanes_validate_answers "$q" "$ain")" || return 1
  jq -e 'type == "object" and length > 0' >/dev/null 2>&1 <<<"$out" || return 1
  sha="$(jq -r '.policy.policy_sha // empty' "$lj" 2>/dev/null)"; [ -n "$sha" ] || return 1
  gate="$(jq -r '[.questions[]?.header // "?"] | join(",")' "$q" 2>/dev/null)" || return 1
  # source: "policy" — the policy writer's shape; lane-answer's human writer stays byte-identical.
  if ! { jq -n --argjson a "$out" --arg sha "$sha" --arg gate "$gate" --arg at "$(now_utc)" \
      '{answers: $a, note: null, source: "policy", policy_sha: $sha, gate: $gate, via: "policy", at: $at}' > "$af.tmp.$$" \
      && mv "$af.tmp.$$" "$af"; }; then
    rm -f "$af.tmp.$$"; return 1
  fi
  run="$(jq -r '.run_id // empty' "$lj" 2>/dev/null)"
  case "$run" in ''|*/*|.*) return 0 ;; esac
  line="policy answer: $(jq -r --argjson a "$out" '[.questions[] | "\(.header // "?") → \($a[.question] // "?")"] | join(", ")' "$q" 2>/dev/null) (policy_sha ${sha:0:12})"
  bash "$HELPERS" progress-append "$root/.supervisor/automate/$run.md" "$line" >/dev/null 2>&1 || true
  return 0
}

# ==================================================================================================
# lane-answer <lane_dir> <tool_use_id> --owner-command '<cmd>' [--via <client>]  (stdin: answers JSON)
# lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>'
#
# A HELD answer is never lost (parallel-automate/23 F2): when admission holds the resume (exit 4), the
# VALIDATED answers, the note and `via` — never an owner command — are kept coordinator-side in
# <primary>/.supervisor/automate/<parent_run_id>.<lane>.answer-pending.json and nothing is written
# into the lane. lane-status only SHOWS that lane as `answer_pending`. Delivery is the second form,
# run by the coordinator's `/automate --resume <run_id>` poll with the command the owner typed in
# THAT session: it re-runs the full _lanes_gate (authority, liveness, regime, admission) and re-checks
# the stored answers against the recorded question's labels AND the lane's still-deferred tool_use_id
# (a mismatch refuses and discards the pending file). Honest limit: the re-check proves the stored
# answer is a VALID label for the question still pending — not that the owner chose it. That is the
# same trust level as the lane inbox's answer file relay-hook reads; the pending file is not
# owner-authenticated, which is why it can never carry, or stand in for, an owner command. One pending
# file per lane, last write wins: a second HELD lane-answer for the same question replaces the first
# (how the owner corrects a kept answer). A discard leaves the question unanswered, so lane-status
# reads that lane awaiting_input again — never held_for_load. A resume refused for a missing gate
# opt-out (launch contract 3a) keeps the validated answer pending the same way (exit 3, not 4).
_lanes_pending_file() { printf '%s' "$LN_PRIMARY/.supervisor/automate/$LN_PARENT.$LN_LANE.answer-pending.json"; }

# _lanes_validate_answers <question_file> <input JSON> — prints {<question>: "<label[,label…]>"} or
# fails with the refusal text: exactly the question's own option labels (multiSelect: comma-joined,
# every way of cutting the answer at its commas into known labels is tried — a label may itself
# contain a comma — exactly one cut ⇒ accepted; none ⇒ unknown label, refusing the whole answer;
# more than one ⇒ ambiguous).
_lanes_validate_answers() {
  jq -c --argjson in "$2" '
    def cuts($labels): if length == 0 then [[]] else
      [range(1; length + 1) as $k | (.[0:$k] | join(",") | sub("^ +"; "") | sub(" +$"; "")) as $h
        | select(any($labels[]; . == $h)) | (.[$k:] | cuts($labels))[] | [$h] + .] end;
    .questions as $qs | ($qs | length) as $n
    | if ($in.answers | type) != "object" then error("an answer is one of the question'"'"'s own option labels per question (a note alone is never the decision)") else . end
    | if ([$in.answers | keys[]] | map(tonumber? // -1) | sort) != [range(0; $n)] then error("need exactly one answer for each of the \($n) question(s)") else . end
    | reduce range(0; $n) as $i ({}; ($in.answers[($i | tostring)]) as $a
        | [$qs[$i].options[].label] as $labels
        | (if ($a | type) != "string" then []
           elif $qs[$i].multiSelect != true then [$a]
           elif any($labels[]; . == $a) then [$a]
           else ($a | split(",") | cuts($labels)) as $c
             | if ($c | length) > 1 then error("question \($i + 1): \"\($a)\" is ambiguous — its labels contain commas and it splits into known labels \($c | length) ways (\($c | map(map("\"" + . + "\"") | join(" + ")) | join(" | "))), so no one reading can be chosen") else ($c[0] // []) end
           end) as $parts
        | if ($parts | length) == 0 or any($parts[]; . as $p | ($labels | index($p)) == null)
          then error("question \($i + 1): \"\($a)\" is not one of its options\(if $qs[$i].multiSelect == true then " (multiSelect: comma-joined labels)" else "" end)")
          else . end
        | . + {($qs[$i].question): ($parts | join(","))})' "$1" 2>&1
}

# _lanes_answer_parked <tool_use_id> — 0 when the lane's last result parked on exactly that deferred
# question (prints it), else prints the refusal reason and returns 1.
_lanes_answer_parked() {
  local last; last="$(_lanes_last_result "$LN_LOG")"
  [ "$(jq -r '.stop_reason // empty' <<<"$last" 2>/dev/null)" = "tool_deferred" ] || { echo "$LN_LANE did not park on a question"; return 1; }
  [ "$(jq -r '.deferred_tool_use.id // empty' <<<"$last" 2>/dev/null)" = "$1" ] || { echo "$LN_LANE is parked on another question"; return 1; }
  printf '%s' "$last"
}

# _lanes_answer_write_resume <id> <validated> <note> <via> <sid> — caller holds the launch lock and
# passed _lanes_gate: writes the lane's answer file, drops any pending copy, resumes the session.
_lanes_answer_write_resume() {
  local id="$1" out="$2" note="$3" via="$4" sid="$5" af="$LN_INBOX/answers/$1.json" rc
  if ! { jq -n --argjson a "$out" --arg note "$note" --arg via "$via" --arg at "$(now_utc)" \
      '{answers: $a, note: (if $note == "" then null else $note end), source: "human", via: $via, at: $at}' > "$af.tmp.$$" \
      && mv "$af.tmp.$$" "$af"; }; then
    rm -f "$af.tmp.$$"; _lanes_launch_unlock; die "lane-answer: cannot write the answer file"
  fi
  rm -f "$(_lanes_pending_file)"
  [ -n "$note" ] && echo "lane-answer: note recorded and delivered to the lane as an annotation (never the decision)"
  _lanes_spawn "" "$sid" "(resume after answer $id via $via)"; rc=$?
  _lanes_launch_unlock
  return "$rc"
}

lanes_answer() {
  local dir="" id="" owner="" via=cli deliver=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --owner-command) _lanes_need "$#" lane-answer "$1"; owner="$2"; shift 2 ;;
      --via) _lanes_need "$#" lane-answer "$1"; via="${2:-cli}"; shift 2 ;;
      --deliver-pending) deliver=1; shift ;;
      --without-gate-optout) LN_WITHOUT_OPTOUT=1; shift ;;
      *) if [ -z "$dir" ]; then dir="$1"; elif [ -z "$id" ]; then id="$1"; else die "lane-answer: unexpected argument '$1'"; fi; shift ;;
    esac
  done
  _lane_ctx "$dir" || die "lane-answer: not a lane: ${dir:-<none>}"
  if [ "$deliver" = 1 ]; then
    [ -z "$id" ] || die "lane-answer: --deliver-pending takes no tool_use_id (it delivers the stored one)"
    _lanes_deliver_pending "$owner"; return $?
  fi
  case "$id" in ''|*[!A-Za-z0-9_-]*) die "lane-answer: bad tool_use_id '$id'" ;; esac
  local qf="$LN_INBOX/questions/$id.json" af="$LN_INBOX/answers/$id.json" last in out rc pf sup
  if sup="$(_lanes_superseded_msg "$LN_INBOX" "$id")"; then die "lane-answer: refused — $sup"; fi
  [ -s "$qf" ] || die "lane-answer: refused — no recorded question $id"
  [ -e "$af" ] && die "lane-answer: refused — $id already answered"
  last="$(_lanes_answer_parked "$id")" || die "lane-answer: refused — $last"
  in="$(cat)"
  jq -e 'type == "object"' >/dev/null 2>&1 <<<"$in" || die "lane-answer: refused — answers are not a JSON object"
  out="$(_lanes_validate_answers "$qf" "$in")" || die "lane-answer: refused — $(sed -E 's/^jq: error \(at [^)]*\): //' <<<"$out")"
  local sid; sid="$(jq -r '.session_id // empty' <<<"$last")"; [ -n "$sid" ] || sid="$(_lanes_session_id)"
  [ -n "$sid" ] || die "lane-answer: refused — no session id to resume"
  local note; note="$(jq -r '.note // ""' <<<"$in")"
  # authority + admission BEFORE the answer is written into the lane, so a refused resume leaves
  # nothing half-written there; under the launch lock, so an overlapping answer sees it answered.
  _lanes_launch_lock || die "lane-answer: refused — $LN_LANE — launch lock busy (another launch of this lane is in flight)"
  if [ -e "$af" ]; then _lanes_launch_unlock; die "lane-answer: refused — $id already answered"; fi
  _lanes_gate "$owner" 1; rc=$?
  if [ "$rc" = 4 ] || { [ "$rc" = 3 ] && [ "$LN_GATE_OPTOUT_BLOCKED" = 1 ]; }; then
    # HELD (admission) or BLOCKED on a missing gate opt-out: keep the VALIDATED answer coordinator-side
    # — never the owner command — so the owner's answer is not lost while the resume waits.
    pf="$(_lanes_pending_file)"; case "$via" in *[!A-Za-z0-9_.-]*) via=cli ;; esac
    if jq -n -c --arg lane "$LN_LANE" --arg id "$id" --argjson a "$(jq -c '.answers' <<<"$in")" --arg note "$note" \
        --arg via "$via" --arg at "$(now_utc)" \
        '{schema_version: 1, lane: $lane, tool_use_id: $id, answers: $a, note: (if $note == "" then null else $note end), via: $via, held_at: $at}' \
        > "$pf.tmp.$$" 2>/dev/null && mv "$pf.tmp.$$" "$pf"; then
      if [ "$rc" = 3 ]; then
        echo "lane-answer: answer kept pending ($(basename "$pf")) — $LN_LANE reads answer_pending; deliver it with the opt-out set, or with --without-gate-optout (lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>' [--without-gate-optout])"
      else
        echo "lane-answer: answer kept pending ($(basename "$pf")) — $LN_LANE reads answer_pending; the next /automate --resume poll delivers it (lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>')"
      fi
    else
      rm -f "$pf.tmp.$$"; echo "lane-answer: answer NOT kept — cannot write $(basename "$pf"); re-send it at the next poll"
    fi
    _lanes_launch_unlock; return "$rc"
  fi
  [ "$rc" = 0 ] || { _lanes_launch_unlock; return "$rc"; }
  _lanes_answer_write_resume "$id" "$out" "$note" "$via" "$sid"
}

# _lanes_deliver_pending <owner_cmd> — the delivery form (see lanes_answer). Nothing is written into
# the lane before every re-check and the full _lanes_gate pass.
_lanes_deliver_pending() {
  local owner="$1" pf id qf af last in out sid note via rc sup
  pf="$(_lanes_pending_file)"
  [ -s "$pf" ] || die "lane-answer: refused — no pending answer for $LN_LANE ($(basename "$pf"))"
  _discard() { rm -f "$pf"; die "lane-answer: refused — the pending answer for $LN_LANE no longer matches ($1); discarded — the question is shown again"; }
  id="$(jq -r '.tool_use_id // empty' "$pf" 2>/dev/null)"
  case "$id" in ''|*[!A-Za-z0-9_-]*) _discard "bad tool_use_id" ;; esac
  [ "$(jq -r '.lane // empty' "$pf" 2>/dev/null)" = "$LN_LANE" ] || _discard "recorded for another lane"
  qf="$LN_INBOX/questions/$id.json"; af="$LN_INBOX/answers/$id.json"
  if sup="$(_lanes_superseded_msg "$LN_INBOX" "$id")"; then _discard "$sup"; fi
  [ -s "$qf" ] || _discard "no recorded question $id"
  [ -e "$af" ] && _discard "$id already answered"
  last="$(_lanes_answer_parked "$id")" || _discard "$last"
  in="$(jq -c '{answers: .answers, note: .note}' "$pf" 2>/dev/null)" || _discard "pending file unreadable"
  out="$(_lanes_validate_answers "$qf" "$in")" || _discard "$(sed -E 's/^jq: error \(at [^)]*\): //' <<<"$out")"
  note="$(jq -r '.note // ""' <<<"$in")"; via="$(jq -r '.via // "cli"' "$pf")"; case "$via" in ''|*[!A-Za-z0-9_.-]*) via=cli ;; esac
  sid="$(jq -r '.session_id // empty' <<<"$last")"; [ -n "$sid" ] || sid="$(_lanes_session_id)"
  [ -n "$sid" ] || die "lane-answer: refused — no session id to resume"
  _lanes_launch_lock || die "lane-answer: refused — $LN_LANE — launch lock busy (another launch of this lane is in flight)"
  if [ -e "$af" ]; then _lanes_launch_unlock; _discard "$id already answered"; fi
  _lanes_gate "$owner" 1; rc=$?
  if [ "$rc" != 0 ]; then
    _lanes_launch_unlock
    echo "lane-answer: pending answer kept for $LN_LANE — not delivered"
    return "$rc"
  fi
  _lanes_answer_write_resume "$id" "$out" "$note" "$via (delivered pending)" "$sid"
}

