#!/usr/bin/env bash
# lane-policy.sh — the lane GATE CATALOG and the human-stamped POLICY ANSWERS for routine lane
# questions (parallel-automate/21 Part B, "fleet operations").
#
# A lane (skills/automate-loop/SKILL.md §14) relays every question its engine asks to the owner. Most
# are decisions; some are formalities the owner answers the same way every time. This script lets a
# HUMAN pre-answer the formalities, and only those, by an EXACT LOOKUP — never a model judgement:
#
#   catalog   the ONE authoritative gate table: one TSV row per engine ask-tool gate,
#             `code<TAB>policy<TAB>labels-joined-by-|<TAB>purpose`. `policy` is one of three tiers:
#             `allowed` (a policy may answer it), `auto` (gate-auto.sh applies the row's `!` label
#             without asking unless one of its escalation triggers fires; a policy may answer it only
#             when `_lp_policy_answerable` says so) or `human-only` (never answered by policy or by
#             gate-auto.sh, whatever a policy file says).
#             loomwright/docs/LANE_GATES.md mirrors it (regenerate the mirror with `catalog --markdown`);
#             test-lane-policy.sh fails when the two differ. Every code is at most 12 characters (the
#             ask tool's `header` limit, commands/dreaming.md). The engine asks EVERY gate — `allowed`,
#             `auto` and human-only alike — with `header` = its code and the catalog's exact labels (a
#             `(Recommended)` marker is allowed and stripped before comparison); `decide` never answers a
#             human-only code, so the code only names the gate. A label ending in `?` is OPTIONAL: the
#             ask offers either every label or only the non-`?` ones (LP-SAVE on a PASS that used the
#             last Plan Review attempt: no attempt is left to Refine or Edit), never another subset; the
#             `?` is not part of the label. A label ending in `!` is the AUTO label of an `auto` row (the
#             one label gate-auto.sh applies): exactly one per `auto` row and none on any other row; the
#             `!` is not part of the label either, and `catalog --markdown` keeps both markers raw.
#             check-gate-headers.sh fails an engine ask (prose or a
#             next-step emitter) that names a gate without its code, or its code without its labels.
#   wave-set  the per-wave owner answer set: writes <dir of parent_runfile>/<run_id>.wave-policy.json
#             `{"schema_version":1,"run_id":…,"answers":{code:label},"set_at":…}` and one parent
#             `## Progress` line `wave policy: <code>=<label>, …`. Refuses (exit 1, NOTHING written) a
#             code that is not policy-answerable (`_lp_policy_answerable`), a label that is not one of that code's catalog labels, a code
#             given twice with different labels, or a parent file that is not a run file. Called by the
#             coordinator ONLY with the owner's own answers at wave planning. HONEST LIMIT: the file is
#             not owner-authenticated — the same trust level as automate-lanes.sh's answer-pending file.
#             It REPLACES any earlier wave policy of the same run. NOT concurrency-safe: it takes no lock
#             and progress-append is an unlocked read-modify-rename, so two simultaneous calls can lose
#             one Progress line (the record then disagrees with the installed file). The ONE caller is
#             the coordinator, once, at wave planning — never run it concurrently.
#   resolve   merges the STAMPED project policy (.agent/lane-policy.json) and the wave policy (the wave
#             wins per code), keeps only policy-answerable codes with valid labels, reports and drops anything
#             else (`lane-policy: dropped <source> <code> — <reason>` on stderr), and prints ONE JSON
#             object: {"policy_sha": <sha256 of the canonical answers, or null when empty>,
#             "sources": [{"kind":"project"|"wave","path":…}], "answers": {code: label}}.
#             `lane-create` (automate-lanes.sh) runs it in the PRIMARY and carries the result into the
#             lane's lane.json as `policy` (null when `answers` is empty). Canonical answers = the
#             compact, key-sorted JSON text of the answers object (`jq -cS .`), hashed without a
#             trailing newline.
#   decide    prints `{"0":"<label>",…}` when EVERY question in the call has a catalog code (its
#             `header`) that is policy-answerable (`_lp_policy_answerable`), a single-select option list whose labels — with
#             `(Recommended)` stripped — equal that code's catalog labels as a set (or, for a row with
#             `?` labels, exactly its non-`?` labels), and a policy answer
#             for that code. The printed label is the QUESTION'S OWN option label (marker included), so
#             it passes automate-lanes.sh's `_lanes_validate_answers` unchanged. Otherwise — one
#             uncoded / human-only / mismatched question, no policy, a malformed policy, a policy whose
#             `policy_sha` does not match its answers, or ANY error — it prints `human`. Never a partial
#             answer. `<question_json>` is a file path or a JSON literal: a questions array,
#             `{"questions":[…]}` (the lane's inbox question file), or the hook payload
#             `{"tool_input":{"questions":[…]}}`. `--policy-json <file>` is a lane.json (its `policy`
#             key is read) or a bare `resolve` object.
#
# WHEN THE PROJECT POLICY COUNTS AS STAMPED (B3 — the existing rules-check.sh stamp valve,
# skills/rules/SKILL.md §8 / §8.1; there is NO second valve). ALL must hold, read in the PRIMARY:
#   (i)   `rules-check.sh --list-selected` lists the id `lane-policy` (a must-rule with a check);
#   (ii)  every `.agent/rules/*.json` object with id `lane-policy` carries a `binds` array containing
#         `.agent/lane-policy.json` — read with jq as DATA only; no check is ever executed here;
#   (iii) the policy file is git-TRACKED (rules-check.sh hashes an untracked bound path as the constant
#         `INVALID`, so an untracked file's CONTENT would not be covered by the stamp);
#   (iv)  `rules-check.sh --stamp-state` prints `stamp<TAB>match` (the live set, bound file content
#         included, is the set a human confirmed on this machine).
# Any failure ⇒ `lane-policy: project policy ignored — <reason>` on stderr and NO project answer is
# used (never partially applied). Editing the policy file, the rule, any other selected must-rule, or
# deleting the stamp therefore turns project policy answers OFF until a human re-runs
# `/rules check --confirm`. A lane cannot verify the stamp itself (it is keyed per clone), so this runs
# at `lane-create` in the primary and the lane only reads the carried result: removing the stamp takes
# effect at the NEXT lane-create; a lane already created keeps the policy it was given.
#
# POLICY ANSWERABILITY (D1) is decided by ONE helper, `_lp_policy_answerable` (a jq definition every
# check below uses): an `allowed` code, or an `auto` code not listed in `_LP_POLICY_EXEMPT`. The three
# `auto` codes that were `allowed` before the tier existed (AUT-RESUME, AUT-QUEUE, LP-SAVE) therefore
# stay policy-answerable exactly as before; LP-SAVE-NOTE (exempt) was never policy-answerable and stays
# refused, so an escalated LP-SAVE-NOTE ask can never be answered by a policy. `human-only` is never.
#
# Codes are checked against the catalog THREE times: at wave-set, at resolve, and again at decide (the
# `answerable($h; $row) | not` line in lp_decide is the one test-lane-policy.sh's mutation control removes).
#
# Usage:
#   lane-policy.sh catalog [--markdown]
#   lane-policy.sh wave-set <parent_runfile> <code>=<label> [<code>=<label> …]
#   lane-policy.sh resolve <parent_runfile> [--root <primary>]
#   lane-policy.sh decide <question_json> [--policy-json <file>]
# Exit:   catalog 0 · wave-set 0 written / 1 refused (nothing written) · resolve 0 always (fail-safe
#         toward an EMPTY policy) · decide 0 always (its stdout IS the decision; `human` on any error) ·
#         2 = usage error (decide still prints `human`).
# Needs:  jq (absent ⇒ resolve prints the empty policy, decide prints `human`, wave-set refuses).
# Seams:  LOOMWRIGHT_LANE_POLICY_RULES_CHECK (rules-check.sh path), LOOMWRIGHT_LANE_POLICY_HELPERS
#         (automate-helpers.sh path, for progress-append).

set -uo pipefail   # NO `set -e`: every failure path is an explicit refusal or a `human`.

PROG="lane-policy.sh"
LP_TAG="lane-policy"   # the prefix of every policy report line (`lane-policy: project policy ignored — …`)
LP_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LP_RULES_CHECK="${LOOMWRIGHT_LANE_POLICY_RULES_CHECK:-$LP_SCRIPT_DIR/rules-check.sh}"
LP_HELPERS="${LOOMWRIGHT_LANE_POLICY_HELPERS:-$LP_SCRIPT_DIR/automate-helpers.sh}"
LP_POLICY_REL=".agent/lane-policy.json"
LP_RULE_ID="lane-policy"

_lp_usage() { awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$LP_SCRIPT_DIR/lane-policy.sh"; }
_lp_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ==================================================================================================
# THE GATE CATALOG — the ONE authority. One `_lp_row code policy labels purpose` per engine ask-tool
# gate (the engine = /automate, /autonomous, and the Launch Pad, Supervisor and Product Owner flows
# they inline), plus /backlog --verify's per-item stamp asks and /janitor's act ask. Labels are joined by `|`; no field may contain a tab, a newline or (outside labels) a
# `|`. `(free text)` marks a gate whose answer is free-form — such a gate can never be `allowed` or
# `auto`. A trailing `?` marks an optional label and a trailing `!` the auto label of an `auto` row (see
# `catalog` above); neither marker is ever part of the label itself.
# Adding, removing or relabelling a row: regenerate loomwright/docs/LANE_GATES.md's table in the SAME
# change (`lane-policy.sh catalog --markdown`), or test-lane-policy.sh fails.
# ==================================================================================================
_lp_row() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; }
_lp_catalog_rows() {
  _lp_row AUT-RESUME   auto       'Continue!|Start new|Archive' \
    '/automate start finds an incomplete run (automate-loop SKILL §4 step 4); auto only with one incomplete run and no rebuilt ## Current, risk read from its open PR diff'
  _lp_row AUT-QUEUE    auto       'Process!|Stop' \
    '/automate Queue confirm before processing (automate-loop SKILL §2 "--limit N"); auto with no risk read (no item is picked yet)'
  _lp_row AUT-SUMMARY  allowed    'Keep summary|Drop summary' \
    '/automate keep or drop a LOW/INFO summary draft — the fallback only: dismissed-drafts recorded follow-up automatically on every summary draft (drop one by deleting it from proposed/), so this asks only when that auto-keep was refused (§6 dismissed-findings decision step and the PICK-time ask)'
  _lp_row LP-SAVE      auto       'Save and exit!|Refine further?|Edit sections?|Discard' \
    'Launch Pad Phase 6 save on a Plan Review PASS with zero issues (Refine / Edit only while a review attempt is left); auto unless the File Impact Map paths are high-risk'
  _lp_row SUP-CHILDREN allowed    'proceed anyway|investigate|abort' \
    'Supervisor FINALIZE Point 5 children unsettled (async-orchestration SKILL)'
  _lp_row AUT-SOURCE   human-only '(free text)' \
    'bare /automate: what do you want to automate?'
  _lp_row AUT-PENDING  human-only 'Follow-up (keep draft)|Drop' \
    '/automate PICK-time decision on a per-finding dismissed draft — the fallback only: PICK records every undecided draft follow-up automatically, so this asks only about a draft whose automatic follow-up was refused (§6 dismissed-findings decision step)'
  _lp_row AUT-DISMISS  human-only 'Fix none (follow-up all)|Fix all listed on this PR|Fix selected on this PR?' \
    '/automate ONE batched ask at the park over the MEDIUM+ per-finding dismissed drafts while a fix-now re-drain is available (every other draft is followed up with no question); Fix selected names the draft numbers in the answer note and is offered only when two or more are listed (§6 dismissed-findings decision step)'
  _lp_row AUT-LEFTOVER human-only 'Clean up now?|Keep and continue|Stop' \
    '/automate close-out leftover gate (cleans up or deletes; Clean up now is offered only when a cleanup is possible)'
  _lp_row AUT-WAIVE    human-only 'Waive this step|Keep parked' \
    '/automate READY park: waive a running-system Validation step validation-gate reports unrun (owner words from the answer note; cannot ask ⇒ stays escalated, validation_unrun)'
  _lp_row PO-ASSUME    human-only 'Proceed anyway|Refine requirements|Abort' \
    'Product Owner assumption-check soft gate, pre-persist house-rule check and missing-proof (no Validation) flag (/automate prompt intake)'
  _lp_row PO-RULE-MUST human-only 'Refine requirements|Change the rule via /rules|Abort' \
    'Product Owner pre-persist house-rule check on a must-rule conflict (no override option: a must rule is never overridden)'
  _lp_row LP-CLARIFY   human-only '(free text)' \
    'Launch Pad Phase 2 clarification'
  _lp_row LP-NO-GO     human-only 'Override and continue|Revise goal|Abort' \
    'Launch Pad Phase 2.5 feasibility NO-GO'
  _lp_row LP-SCOPE     human-only 'Extend Touches|Revise plan|Stop' \
    'Launch Pad Phase 6, before the save question: ONE ask listing every brief path outside the item Touches (automate-lanes.sh scope-outside); Extend records them in the brief ## Scope widening section; human-only by owner decision; cannot ask ⇒ scope_widening_non_interactive, nothing saved'
  _lp_row LP-SAVE-NOTE auto       'Save and exit!|Refine further?|Edit sections?|Discard' \
    'Launch Pad Phase 6 save on a Plan Review PASS that carries any issue or note (Refine / Edit only while a review attempt is left); auto by owner decision unless an issue is MEDIUM or higher or the File Impact Map paths are high-risk, never answered by a policy'
  _lp_row LP-NEEDHUMAN human-only 'Override and save|Refine further?|Discard' \
    'Plan Review NEEDS_HUMAN, or any MEDIUM-or-higher finding (Refine only while a review attempt is left)'
  _lp_row LP-EXEC-ACC  human-only 'approve-and-stamp|strip-cmd-bullets|discard' \
    'Launch Pad executable-acceptance stamp'
  _lp_row LP-RULE-OVR  human-only 'record-override|honor-rule|discard' \
    'Launch Pad Plan Review 17c: an AC contradicts an advisory house rule with no owner override (owner words from the answer note; cannot ask ⇒ rule_conflict_non_interactive)'
  _lp_row LP-FAIL      human-only 'Refine offline|Discard' \
    'Plan Review FAIL after the third attempt'
  _lp_row LP-MEMORY    human-only '(free text)' \
    'Launch Pad project-memory candidate facts'
  _lp_row SUP-INIT     human-only '(free text)' \
    'Supervisor INIT config (max workers, task)'
  _lp_row SUP-OVERLAP  human-only 'proceed-anyway|revise-scope|abort' \
    'Supervisor Phase 1.5 pre-flight OVERLAP or SUPERSEDED'
  _lp_row SUP-ADJ-GAP  human-only 'A: Re-queue producer|B: Insert remediation subtask|C: Exit to Launch Pad|D: Update consumer brief' \
    'Supervisor EXECUTE adjudication: an output gap (requires_gap)'
  _lp_row SUP-ADJ-LANE human-only "A: Re-queue writer with the sibling lane excluded|B: Serialize the pair (add a requires edge)|C: Exit to Launch Pad|D: Widen the writer's declared lane" \
    'Supervisor EXECUTE adjudication: a lane collision (lane_collision)'
  _lp_row SUP-GH-RETRY human-only 'retry|skip-verify-once|abort' \
    'Supervisor FINALIZE PR-base verification after gh failed twice'
  _lp_row AN-RUBRIC    human-only 'continue-to-next-iteration|merge-and-continue|stop-here|force-continue-anyway' \
    '/autonomous rubric gate between iterations (merges or continues)'
  _lp_row AN-NO-RUBRIC human-only 'continue|stop' \
    '/autonomous no-rubric gate'
  _lp_row AN-MERGE-VFY human-only 'merge-and-continue|stop-here|force-continue-anyway' \
    '/autonomous merge-verify re-prompt'
  _lp_row AN-PR-BASE   human-only 'retry|skip-verify-once|abort' \
    '/autonomous PR-base verification after gh failed twice'
  _lp_row AN-ESCALATED human-only '(free text)' \
    '/autonomous review-heal ESCALATED'
  _lp_row BL-VERIFY    human-only 'Stamp done?|Stamp done with escalation?|Abandon|Skip' \
    '/backlog --verify per-item stamp of an item with no merge evidence (the stamp options only when a merged PR is named; cannot ask ⇒ verify_requires_owner, nothing stamped)'
  _lp_row BL-CONFLICT  human-only 'Abandon|Keep open|Skip' \
    '/backlog --verify per-item settle of a conflict item (an abandoned/skipped Queue row vs its own pending/ready; cannot ask ⇒ verify_requires_owner, nothing stamped)'
  _lp_row JAN-ACT      human-only '(free text)' \
    '/janitor: which actionable report rows to act on (multi-select, nothing pre-selected), and the second confirmation before a force-unlock; cannot ask ⇒ report only, nothing acted on'
}

# catalog [--markdown] — the TSV table, or the markdown table LANE_GATES.md embeds between its
# `lane-policy catalog: BEGIN/END` markers (labels in backticks, joined by ` · `).
lp_catalog() {
  case "${1:-}" in
    "") _lp_catalog_rows ;;
    --markdown)
      printf '| Code | Policy | Labels | Purpose |\n|---|---|---|---|\n'
      _lp_catalog_rows | awk -F'\t' '{
        n = split($3, l, "|"); s = ""
        for (i = 1; i <= n; i++) s = s (i > 1 ? " · " : "") "`" l[i] "`"
        printf "| `%s` | %s | %s | %s |\n", $1, $2, s, $4
      }' ;;
    *) echo "$PROG: catalog: unknown argument '$1' (usage: catalog [--markdown])" >&2; return 2 ;;
  esac
}

# _lp_catalog_json — {code: {policy, labels: [...], core: [...], purpose}}: `labels` every label with its
# optional `?` / auto `!` marker removed, `core` only the labels without `?` (also `!`-stripped; equal to
# `labels` on most rows).
_lp_catalog_json() {
  _lp_catalog_rows | jq -Rnc '[inputs | split("\t") | (.[2] | split("|")) as $l
    | {key: .[0], value: {policy: .[1], labels: ($l | map(sub("[?!]$"; ""))),
        core: ($l | map(select(endswith("?") | not) | sub("!$"; ""))), purpose: .[3]}}] | from_entries'
}

# POLICY ANSWERABILITY (D1) — the ONE rule wave-set, resolve (_lp_filter) and decide apply. An `auto` code
# listed here is never policy-answerable (space-separated; the owner moved LP-SAVE-NOTE to the `auto`
# tier only, never to policy). No call site restates this list.
_LP_POLICY_EXEMPT="LP-SAVE-NOTE"
# _lp_policy_answerable — prints the jq definition `answerable($code; $row)`: true for an `allowed` row,
# or an `auto` row whose code is not in _LP_POLICY_EXEMPT; false for anything else (human-only, null).
_lp_policy_answerable() {
  local ex="" c
  for c in $_LP_POLICY_EXEMPT; do
    case "$c" in *[!A-Z0-9-]*) printf 'def answerable($code; $row): false;\n'; return 0 ;; esac   # never fail open
    ex="${ex:+$ex,}\"$c\""
  done
  printf 'def answerable($code; $row): ($row != null) and (($row.policy == "allowed") or ($row.policy == "auto" and ([%s] | any(.[]; . == $code) | not)));\n' "$ex"
}

# _lp_sha256_str <text> — sha256 hex of <text> (no trailing newline added); empty when no hasher.
# The same fallback chain rules-check.sh uses (shasum -a 256 -> sha256sum -> openssl dgst).
_lp_sha256_str() {
  if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256 2>/dev/null | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then printf '%s' "$1" | sha256sum 2>/dev/null | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then printf '%s' "$1" | openssl dgst -sha256 2>/dev/null | awk '{print $NF}'
  fi
}

# _lp_filter <catalog_json> <source> <answers_json> — {kept: {code: label}, dropped: ["<reason>", …]}.
# The resolve-time catalog check: a code not in the catalog, a code that is not policy-answerable
# (human-only, or a policy-exempt auto code), or a label that is not one of the code's catalog labels is
# dropped and reported.
_lp_filter() {
  jq -cn --argjson cat "$1" --arg src "$2" --argjson a "$3" "$(_lp_policy_answerable)"'
    $a | to_entries | reduce .[] as $e ({kept: {}, dropped: []};
      ($cat[$e.key]) as $row
      | if $row == null then .dropped += ["\($src) \($e.key) — not a catalog code"]
        elif (answerable($e.key; $row) | not)
          then .dropped += ["\($src) \($e.key) — \($row.policy) (never answered by policy)"]
        elif (($e.value | type) != "string") or (any($row.labels[]; . == $e.value) | not)
          then .dropped += ["\($src) \($e.key)=\($e.value | tostring) — not one of its catalog labels"]
        else .kept[$e.key] = $e.value end)'
}

# ==================================================================================================
# wave-set <parent_runfile> <code>=<label> …
# ==================================================================================================
lp_wave_set() {
  _ws_refuse() { echo "$PROG: wave-set refused — $1 (nothing written)" >&2; return 1; }
  local rf="${1:-}" run_id dir wf tmp pairs result errs line p
  [ -n "$rf" ] || { echo "$PROG: usage: wave-set <parent_runfile> <code>=<label> [<code>=<label> …]" >&2; return 2; }
  shift
  [ "$#" -gt 0 ] || { _ws_refuse "no <code>=<label> pair given"; return 1; }
  command -v jq >/dev/null 2>&1 || { _ws_refuse "jq unavailable"; return 1; }
  [ -f "$rf" ] || { _ws_refuse "parent run file not found: $rf"; return 1; }
  case "$rf" in *.md) ;; *) _ws_refuse "parent run file is not a .md run file: $rf"; return 1 ;; esac
  run_id="$(basename "$rf" .md)"
  pairs='[]'
  for p in "$@"; do
    case "$p" in *=*) ;; *) _ws_refuse "'$p' is not <code>=<label>"; return 1 ;; esac
    pairs="$(jq -c --arg c "${p%%=*}" --arg l "${p#*=}" '. + [[$c, $l]]' <<<"$pairs")" \
      || { _ws_refuse "cannot encode '$p'"; return 1; }
  done
  # The wave-set catalog check (one of three: wave-set, resolve, decide).
  result="$(jq -cn --argjson cat "$(_lp_catalog_json)" --argjson p "$pairs" "$(_lp_policy_answerable)"'
    reduce $p[] as $x ({answers: {}, order: [], errors: []};
      ($x[0]) as $c | ($x[1]) as $l | ($cat[$c]) as $row
      | if $row == null then .errors += ["\($c): not a catalog code"]
        elif (answerable($c; $row) | not) then .errors += ["\($c): \($row.policy) — never answered by policy"]
        elif (any($row.labels[]; . == $l) | not)
          then .errors += ["\($c)=\($l): not one of its catalog labels (\($row.labels | join(" | ")))"]
        elif (.answers[$c] != null) and (.answers[$c] != $l) then .errors += ["\($c): given twice with different labels"]
        elif .answers[$c] != null then .
        else .answers[$c] = $l | .order += [$c] end)')" \
    || { _ws_refuse "could not evaluate the pairs"; return 1; }
  errs="$(jq -r '.errors | join("; ")' <<<"$result")"
  [ -z "$errs" ] || { _ws_refuse "$errs"; return 1; }
  line="wave policy: $(jq -r '. as $r | [.order[] | "\(.)=\($r.answers[.])"] | join(", ")' <<<"$result")"
  dir="$(dirname "$rf")"; wf="$dir/$run_id.wave-policy.json"
  tmp="$(mktemp "$wf.XXXXXX" 2>/dev/null)" || { _ws_refuse "cannot create a temp file beside $wf"; return 1; }
  if ! jq -n --arg rid "$run_id" --argjson a "$(jq -c '.answers' <<<"$result")" --arg at "$(_lp_now)" \
       '{schema_version: 1, run_id: $rid, answers: $a, set_at: $at}' > "$tmp" 2>/dev/null; then
    rm -f "$tmp"; _ws_refuse "cannot write $wf"; return 1
  fi
  # The Progress line FIRST (progress-append refuses a non-run file and leaves it unchanged): a refusal
  # there removes the staged file, so a wave policy never exists without its run-file record.
  if ! bash "$LP_HELPERS" progress-append "$rf" "$line" >/dev/null; then
    rm -f "$tmp"; _ws_refuse "progress-append failed on $rf"; return 1
  fi
  mv -f "$tmp" "$wf" 2>/dev/null || { rm -f "$tmp"; echo "$PROG: wave-set: install of $wf FAILED after the Progress line was appended — no wave policy is in force" >&2; return 1; }
  printf 'wave-set: wrote %s — %s\n' "$wf" "$line"
}

# ==================================================================================================
# resolve <parent_runfile> [--root <primary>]
# ==================================================================================================

# _lp_project_answers <root> — prints the project policy's raw answers object (compact) ONLY when it
# counts as stamped (header, conditions i–iv); otherwise prints nothing and reports why on stderr. An
# absent policy file is silent (no policy, nothing to report).
_lp_project_answers() {
  local root="$1" f ids rules_dir binds_ok state tab
  f="$root/$LP_POLICY_REL"
  [ -e "$f" ] || return 0
  _pp_ignore() { echo "$LP_TAG: project policy ignored — $1" >&2; }
  # (i) a selected must-rule `lane-policy` — rules-check.sh's own listing, never a second parser.
  ids="$(cd "$root" 2>/dev/null && bash "$LP_RULES_CHECK" --list-selected 2>/dev/null </dev/null)"
  grep -qxF -- "$LP_RULE_ID" <<<"$ids" \
    || { _pp_ignore "no selected must-rule with id $LP_RULE_ID (rules-check.sh --list-selected)"; return 0; }
  # (ii) every `lane-policy` object binds the policy file — DATA only (the check is never run).
  rules_dir="$root/.agent/rules"
  binds_ok="$(env LC_ALL=C find "$rules_dir" -maxdepth 1 -type f -name '*.json' 2>/dev/null | env LC_ALL=C sort \
    | while IFS= read -r rfile; do
        [ -n "$rfile" ] || continue
        jq -c --arg id "$LP_RULE_ID" --arg p "$LP_POLICY_REL" '
          if type == "array" then [.[] | select(type == "object" and .id == $id)
            | ((.binds | type) == "array" and any(.binds[]; . == $p))] else [] end' "$rfile" 2>/dev/null </dev/null
      done | jq -s 'add // [] | (length > 0 and all)' 2>/dev/null)"
  [ "$binds_ok" = "true" ] \
    || { _pp_ignore "rule $LP_RULE_ID does not bind $LP_POLICY_REL (its binds array must name it)"; return 0; }
  # (iii) tracked — an untracked bound path hashes as INVALID, so its content would not be stamped.
  git -C "$root" --literal-pathspecs ls-files --error-unmatch -- "$LP_POLICY_REL" >/dev/null 2>&1 </dev/null \
    || { _pp_ignore "$LP_POLICY_REL is not git-tracked (the stamp covers tracked content only)"; return 0; }
  # (iv) the live set (bound content included) is the stamped one.
  state="$(cd "$root" 2>/dev/null && bash "$LP_RULES_CHECK" --stamp-state 2>/dev/null </dev/null)"
  tab="$(printf '\t')"
  if [ "$state" != "stamp${tab}match" ]; then
    state="${state#stamp"$tab"}"; [ -n "$state" ] || state="unreadable"
    _pp_ignore "rules stamp $state (not a match — a human re-runs /rules check --confirm)"; return 0
  fi
  jq -ce 'if type == "object" and .schema_version == 1 and (.answers | type) == "object" then .answers
          else error("shape") end' "$f" 2>/dev/null \
    || { _pp_ignore "$LP_POLICY_REL is malformed (want {\"schema_version\":1,\"answers\":{…}})"; return 0; }
}

lp_resolve() {
  local rf="" root="" cat proj wave_raw wf run_id sources='[]' merged='{}' res canon sha r
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) [ "$#" -ge 2 ] || { echo "$PROG: resolve: --root needs a value" >&2; return 2; }; root="$2"; shift 2 ;;
      --*) echo "$PROG: resolve: unknown flag $1" >&2; return 2 ;;
      *) [ -z "$rf" ] || { echo "$PROG: resolve: one parent run file only" >&2; return 2; }; rf="$1"; shift ;;
    esac
  done
  [ -n "$rf" ] || { echo "$PROG: usage: resolve <parent_runfile> [--root <primary>]" >&2; return 2; }
  [ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  if ! command -v jq >/dev/null 2>&1; then
    echo "$LP_TAG: jq unavailable — no policy (every question goes to the human)" >&2
    printf '{"policy_sha":null,"sources":[],"answers":{}}\n'; return 0
  fi
  cat="$(_lp_catalog_json)"
  # Project policy (stamped only).
  proj="$(_lp_project_answers "$root")"
  if [ -n "$proj" ]; then
    res="$(_lp_filter "$cat" project "$proj")" || res='{"kept":{},"dropped":["project — could not be evaluated"]}'
    merged="$(jq -c '.kept' <<<"$res")"
    sources="$(jq -c --arg p "$LP_POLICY_REL" '. + [{kind: "project", path: $p}]' <<<"$sources")"
    jq -r '.dropped[]' <<<"$res" | while IFS= read -r r; do echo "$LP_TAG: dropped $r" >&2; done
  fi
  # Wave policy (owner-set at wave planning; same directory as the parent run file).
  run_id="$(basename "$rf" .md)"
  wf="$(dirname "$rf")/$run_id.wave-policy.json"
  if [ -e "$wf" ]; then
    wave_raw="$(jq -ce --arg rid "$run_id" 'if type == "object" and .schema_version == 1 and .run_id == $rid
        and (.answers | type) == "object" then .answers else error("shape") end' "$wf" 2>/dev/null)"
    if [ -z "$wave_raw" ]; then
      echo "$LP_TAG: wave policy ignored — $wf is malformed or names another run" >&2
    else
      res="$(_lp_filter "$cat" wave "$wave_raw")" || res='{"kept":{},"dropped":["wave — could not be evaluated"]}'
      merged="$(jq -c --argjson w "$(jq -c '.kept' <<<"$res")" '. + $w' <<<"$merged")"   # the wave wins per code
      sources="$(jq -c --arg p "$wf" '. + [{kind: "wave", path: $p}]' <<<"$sources")"
      jq -r '.dropped[]' <<<"$res" | while IFS= read -r r; do echo "$LP_TAG: dropped $r" >&2; done
    fi
  fi
  canon="$(jq -cS . <<<"$merged")"
  sha=""
  if [ "$canon" != "{}" ]; then
    sha="$(_lp_sha256_str "$canon")"
    if [ -z "$sha" ]; then
      echo "$LP_TAG: no sha256 tool — no policy (every question goes to the human)" >&2
      canon="{}"
    fi
  fi
  jq -cn --arg sha "$sha" --argjson s "$sources" --argjson a "$canon" \
    '{policy_sha: (if $sha == "" then null else $sha end), sources: $s, answers: $a}'
}

# ==================================================================================================
# decide <question_json> [--policy-json <file>]
# ==================================================================================================
lp_decide() {
  local qarg="" pf="" qjson questions pol answers want got out
  _dh() { echo "human"; [ -z "${1:-}" ] || echo "$LP_TAG: decide → human — $1" >&2; return 0; }
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --policy-json) [ "$#" -ge 2 ] || { _dh "--policy-json needs a value"; return 2; }; pf="$2"; shift 2 ;;
      --*) _dh "unknown flag $1"; return 2 ;;
      *) [ -z "$qarg" ] || { _dh "one question argument only"; return 2; }; qarg="$1"; shift ;;
    esac
  done
  [ -n "$qarg" ] || { _dh "usage: decide <question_json> [--policy-json <file>]"; return 2; }
  command -v jq >/dev/null 2>&1 || { _dh "jq unavailable"; return 0; }
  if [ -f "$qarg" ]; then qjson="$(cat "$qarg" 2>/dev/null)"; else qjson="$qarg"; fi
  questions="$(jq -c 'if type == "array" then .
      elif type == "object" and (.questions | type) == "array" then .questions
      elif type == "object" and (.tool_input.questions | type) == "array" then .tool_input.questions
      else empty end' <<<"$qjson" 2>/dev/null)"
  [ -n "$questions" ] || { _dh "no readable questions"; return 0; }
  [ -n "$pf" ] || { _dh ""; return 0; }                       # no policy given: the human, silently
  [ -r "$pf" ] || { _dh "policy file unreadable: $pf"; return 0; }
  pol="$(jq -c 'if type == "object" and has("policy") then .policy else . end' "$pf" 2>/dev/null)"
  [ -n "$pol" ] && [ "$pol" != "null" ] || { _dh ""; return 0; }   # policy: null — no policy
  answers="$(jq -cS 'if type == "object" and (.answers | type) == "object" and (.policy_sha | type) == "string"
      then .answers else empty end' <<<"$pol" 2>/dev/null)"
  [ -n "$answers" ] || { _dh "policy is malformed (want {policy_sha, answers})"; return 0; }
  want="$(jq -r '.policy_sha' <<<"$pol")"; got="$(_lp_sha256_str "$answers")"
  [ -n "$got" ] && [ "$got" = "$want" ] || { _dh "policy_sha does not match its answers"; return 0; }
  out="$(jq -rn --argjson cat "$(_lp_catalog_json)" --argjson pol "$answers" --argjson qs "$questions" "$(_lp_policy_answerable)"'
    def strip: gsub("\\s*\\(Recommended\\)"; "") | gsub("^\\s+|\\s+$"; "");
    if ($qs | length) == 0 then "human" else
      [ $qs[] as $q
        | ($q.header // null) as $h
        | (if ($h | type) == "string" then $cat[$h] else null end) as $row
        | if $row == null then null                                   # no catalog code: always human
          elif (answerable($h; $row) | not) then null                     # THE POLICY CHECK (B9 mutation control)
          elif $q.multiSelect == true then null
          elif (($q.options | type) != "array") or any($q.options[]; (type != "object") or ((.label | type) != "string")) then null
          elif ([$q.options[].label | strip] | sort) as $ql
            | ($ql != ($row.labels | sort)) and ($ql != ($row.core | sort)) then null   # the full set or its core
          else ($pol[$h] // null) as $ans
            | if (($ans | type) != "string") or (any($row.labels[]; . == $ans) | not) then null
              else [$q.options[].label | select(strip == $ans)] as $m
                | if ($m | length) == 1 then $m[0] else null end
              end
          end ] as $r
      | if any($r[]; . == null) then "human"
        else ($r | to_entries | map({key: (.key | tostring), value: .value}) | from_entries | tojson) end
    end' 2>/dev/null)" || { _dh "evaluation error"; return 0; }
  case "$out" in
    ""|human) echo "human" ;;
    *) printf '%s\n' "$out" ;;
  esac
}

lp_main() {
  local sub="${1:-}"
  [ "$#" -gt 0 ] && shift
  case "$sub" in
    catalog)  lp_catalog "$@" ;;
    wave-set) lp_wave_set "$@" ;;
    resolve)  lp_resolve "$@" ;;
    decide)   lp_decide "$@" ;;
    -h|--help|help) _lp_usage ;;
    *) echo "$PROG: unknown subcommand '${sub}' (catalog | wave-set | resolve | decide; --help)" >&2; return 2 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then lp_main "$@"; exit $?; fi
