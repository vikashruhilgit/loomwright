#!/usr/bin/env bash
# supervisor-next-step.sh — the inline Supervisor's step driver (automate-speed/11). It owns the
# deterministic sequencing and bookkeeping of Supervisor Phases 0 INIT, 1 ACQUIRE, 1.5 PRE-FLIGHT SYNC
# and 2 PLAN, the Supervisor-side routing of Phase 3 EXECUTE and Phase 4 FINALIZE up to the hand-over to
# Phase 4.5 (which stays prose), and hands the main thread exactly ONE instruction per call
# in automate-speed/06's instruction schema — `{"do":"spawn",…}` / `{"do":"ask",…}` / `{"do":"park",…}`
# / `{"do":"done",…}` — on stdout. The model does what the instruction says and reports back with
# `--result <json>`. The instruction shape, every `step` and `what` value and the `--result` shapes are
# documented in `docs/result-schemas/supervisor-result.md` §"supervisor next-step instruction" (the
# shared `do` enum is `docs/result-schemas/automate-run.md` §"next-step instruction"'s). The protocol it
# executes stays the phase skills' (`skills/supervisor-config/SKILL.md`, `skills/preflight-sync/SKILL.md`,
# `agents/supervisor.md` Phases 1–4, `skills/async-orchestration/SKILL.md` Part 2): this script
# sequences, it never re-specifies a judgment.
#
# USAGE
#   supervisor-next-step.sh --session-id <sid> --job <brief> [--non-interactive] [--subagent] [--cheap]
#                           [--max-tokens N] [--base-branch B] [--branch <feature branch>]
#                           [--skip-preflight-sync] [--skip-children-check] [--sequential]
#                           [--max-workers N] [--root <checkout>]
#   supervisor-next-step.sh --session-id <sid> [--result <json> | --result-file <f>] [--root <checkout>]
#   The first form is the Phase 0 entry, called once per job after Phase 0 step 0's run-lock acquire
#   (which stays the model's — this driver never acquires or releases the run lock). Its flags persist
#   in the sidecar for the rest of the job; the second form answers the pending instruction (`--result`)
#   or, with no `--result`, RE-PRINTS it verbatim and writes nothing (idempotent). An entry for the SAME
#   job while a `spawn` / `ask` of it is pending re-prints that instruction too. `--subagent` is the
#   Can't-ask rule's "subagent context counts as the flag": it implies `--non-interactive` and records
#   the flag's source as `subagent_context`. `--branch` overrides the default feature branch
#   `feature/<brief basename without its YYYY-MM-DD- prefix>`.
#
# STEPS — each is ONE `case` arm of sn_dispatch (the strings inventory homes cite as
#   `script:supervisor-next-step.sh <step>`):
#   init            Phase 0: the `.supervisor/` bootstrap, the job move `pending/` → `in-progress/`, the
#                   run's config (a flag, else the brief's `## Configuration` `Mode:` / `Workers:` /
#                   `Base Branch:`, else the default), the test-integrity guard arm, and ONE
#                   Context-Keeper spawn carrying `initialize`, the two
#                   crash-recovery `clear_flag`s (`base_mismatch_detected`, `non_interactive`), the
#                   `non_interactive` / `max_tokens` `set_flag`s when given, and `guard_armed: …`
#   acquire         Phase 1: the idempotent branch guard (fetch + checkout + pull the base; an existing
#                   branch is reused ONLY when its tip equals the base tip, else the
#                   `acquire_branch_collision` park); the `/autonomous` `state.json` ACQUIRE fields
#   preflight       Phase 1.5 entry: `--skip-preflight-sync` ⇒ the `preflight_skipped` record; else the
#                   classification spawn (the classification itself is the model's judgment)
#   preflight-route the classification report: CLEAR ⇒ `preflight_clear`; UNVERIFIED ⇒ straight to PLAN;
#                   OVERLAP / SUPERSEDED ⇒ the SUP-OVERLAP ask, or under `--non-interactive` the
#                   `preflight_overlap_detected` park (job → `failed/`)
#   preflight-answer the SUP-OVERLAP answer: proceed-anyway / revise-scope / abort ⇒ its record; a
#                   `cant_ask` answer takes the `--non-interactive` branch
#   preflight-stop  after the revise-scope / abort record: the checkpoint park, or the abort park
#                   (job → `failed/`)
#   plan            Phase 2: the job brief's `## Subtask Structure` ids are the plan (a brief pre-answers
#                   PLAN — no orchestrator spawn) and go straight to path selection; a brief whose table
#                   names no subtask id gets the orchestrator spawn
#   plan-result     the orchestrator's subtask list ⇒ path selection. Path selection (both routes): 1
#                   subtask ⇒ single-agent; sequential mode (`--sequential` or the brief's `Mode:
#                   sequential`) and more ⇒ sequential; else parallel —
#                   `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold"
#   execute         Phase 3 entry: the execute-manager spawn (parallel) or the worker spawn for the next
#                   subtask (single-agent / sequential)
#   execute-result  Phase 3 routing of the spawn's answer. Parallel: the EXECUTE_RESULT / EXECUTE_CHECKPOINT
#                   block (parsed by result_block_parser.py) — complete ⇒ FINALIZE; partial ⇒ FINALIZE the
#                   completed subset, the failures carried to the hand-over; all failed ⇒ checkpoint;
#                   adjudication ⇒ the SUP-ADJ-GAP / SUP-ADJ-LANE ask (by adjudication_kind), or under the
#                   Can't-ask rule `adjudication_required_non_interactive: <kind>` with NO option picked;
#                   any other checkpoint / a crash ⇒ checkpoint. Inline: the worker's gate report — passed ⇒
#                   the next subtask or FINALIZE, paused ⇒ checkpoint
#   execute-answer  the adjudication answer: C ⇒ the job fails (inter_subtask_gap | lane_collision); A / B /
#                   D ⇒ recorded, then execute-resume
#   execute-resume  the fresh Execute Manager spawn that applies the chosen option
#   execute-stop    after a Phase 3 stop's record: its park
#   finalize        Phase 4 pre-merge safety gate points 1–4 (a failed point ⇒ the reason logged, the job to
#                   failed/; a missing worktree / branch ⇒ checkpoint)
#   finalize-children  point 5 before any merge: check-children-settled.sh --all; unsettled ⇒ the
#                   SUP-CHILDREN ask, or `children_unsettled: <ids>` under the Can't-ask rule;
#                   --skip-children-check ⇒ the user_skipped_children_check record
#   finalize-children-answer  proceed anyway (recorded as the skip) / investigate (checkpoint) / abort
#   finalize-merge  the merge spawn (Part 2 steps 2–5.5 are the model's: commits, merges, cleanup, re-fold)
#   finalize-merged the merge report: a conflict STOPs (checkpoint), a refused re-fold aborts
#                   (release_refold_refused)
#   finalize-marker guard-finalize-publish.sh write-marker — the publish spawn is printed only after it
#                   exits 0; an unsettled child there takes the point-5 route, any other refusal checkpoints
#   finalize-stop   after a FINALIZE stop's record: its park
#   publish         step 6: the push + PR spawn
#   pr-verify       step 6.5: the PR's baseRefName through gh — equal ⇒ handover; different ⇒
#                   set_flag base_mismatch_detected; a gh failure ⇒ ONE retry, then the SUP-GH-RETRY ask
#                   or, under the Can't-ask rule, the flag (gh_unavailable_non_interactive)
#   pr-verify-answer  retry / skip-verify-once (user_skipped_base_verify) / abort (the flag)
#   handover        `done`: the hand-over to Phase 4.5 (its base-mismatch cleanup when the flag was set)
#
# WRITES. The driver NEVER writes `.supervisor/state.md`: Context-Keeper is the sole writer of its
# Decisions Log / Worker Results / Error Log / Checkpoint / Phase Flags, and `## Session` is
# `scripts/build-state.sh`'s. Every flag and decision it decides is a `context-keeper` spawn carrying the
# exact operation text, answered by `--result {"confirmed": true}`. It writes only: the `.supervisor/`
# directories (and, only when git does not already ignore `.supervisor/`'s contents, a `.supervisor/` line
# appended to `.gitignore`, as Phase 0 step 4 does — a `/setup memory` managed block counts), the job brief's
# lifecycle moves, the git branch, the matching `/autonomous` `state.json`'s two ACQUIRE fields (jq,
# temp + rename; skipped when no single active session matches), and its own sidecar. A failed write is
# SURFACED — stderr names it, no instruction is printed, the exit code is 1 and the sidecar stays at the
# failing step, so the next call (no `--result`) retries it.
#
# SIDECAR. `.supervisor/logs/<sid>.supervisor-next-step.json` (gitignored with `.supervisor/`) holds the
# job's flags, the instruction last printed (verbatim), the step its answer goes to, and the run's
# context (branch, preflight report, subtasks, path).
#
# SIDE EFFECTS that cannot run hermetically go through overridable command lines (word-split):
#   SUPERVISOR_NEXT_STEP_GUARD_CMD   default `bash guard-arm.sh arm supervisor` (Phase 0 step 7)
#   `gh` — LOOMWRIGHT_GH_BIN overrides it, as in every helper (step 6.5's `pr view --json baseRefName`)
#   SUPERVISOR_NEXT_STEP_RETRY_SECONDS  step 6.5's wait before its one retry (default 5; 0 in tests)
# Point 5 and the marker run the real check-children-settled.sh and guard-finalize-publish.sh
# write-marker (called, never edited); the Phase 3 blocks are read by result_block_parser.py (python3).
# TEST SEAM (tests only — never set in a real run): SUPERVISOR_NEXT_STEP_FROM=<step> starts at <step>
# (a golden case that begins mid-run, with a seeded sidecar); `--result`, if given, is that step's input.
#
# Exit codes: 0 an instruction printed; 1 a write / helper failure (surfaced, retried by the next call);
# 2 usage error, a `--result` that does not answer what is pending, or a named refusal on stderr
# (`session_id_missing`, `session_id_malformed`, `job_not_found`, `run_ended`, `nothing_pending`, a
# malformed report) — nothing written.
#
# Honest limits: the resume path (`--continue` and its fail-closed Resume validation gate), the INIT
# config questions (a `job:` brief pre-answers them), the run-lock acquire / release and the Phase 4.5
# flags stay prose. Phase 3 on the inline paths: the per-subtask gates (record_worker_result,
# verify-provides.sh, the pin-mutation gate, the --agent-id join, the inline adjudication of a disk gap)
# and the Sequential Path's per-subtask token-ceiling check stay the model's — the driver routes the
# gate outcome it is handed. The Execute Manager's own poll loop is its own. FINALIZE point 4 reads
# "at or ahead of base" (the base tip is an ancestor of the feature branch): before the merges the branch
# equals the base tip on every path, so "strictly ahead" could not hold there. The commits (step 5) are
# printed before write-marker because the marker binds HEAD — a commit after it would be denied. The driver trusts a well-formed classification / subtask report exactly as the
# model would have acted on it. A failed `git fetch` / `git pull` of the base is reported on stderr and
# recorded in the sidecar (`base_sync`); the guard then compares against the local base tip, as the
# prose snippet does. bash 3.2 + BSD userland + jq.

set -uo pipefail
# Brace expansion OFF: bash 3.2 (macOS /bin/bash) brace-expands the SOURCE text of a double-quoted
# "$(...)" passed as a command argument (an assignment is safe), single quotes notwithstanding - so a jq
# program's {a: x, b: y} reached jq split into words. This script never uses brace expansion (every
# {n,m} in it is a regex quantifier), so it is switched off rather than worked around per call site.
# (Several jq string literals also spell the quote and brace characters as jq \uXXXX escapes - harmless,
# the printed text is the same.)
set +B

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JQ="${JQ:-jq}"

sn_usage() { sed -n 's/^#   supervisor-next-step.sh /supervisor-next-step.sh /p' "${BASH_SOURCE[0]}"; }
sn_die2() { echo "supervisor-next-step: $*" >&2; exit 2; }
sn_err() { echo "supervisor-next-step: $*" >&2; }
sn_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

command -v "$JQ" >/dev/null 2>&1 || { sn_err "jq not on PATH"; exit 1; }

# ------------------------------------------------------------------------------------------------
# arguments
# ------------------------------------------------------------------------------------------------
JOB_ARG=""; SID=""; ROOT=""; RESULT=""; have_result=0; flag_given=0
F_NONINT=0; F_SUBAGENT=0; F_CHEAP=0; F_MAXTOK=""; F_BASE=""; F_BRANCH=""; F_SKIP_PF=0; F_SKIP_CH=0
F_SEQ=0; F_MAXW=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --session-id) [ "$#" -ge 2 ] && [ -n "$2" ] || sn_die2 "session_id_missing — --session-id needs a value"; SID="$2"; shift 2 ;;
    --job) [ "$#" -ge 2 ] && [ -n "$2" ] || sn_die2 "--job needs a brief path"; JOB_ARG="$2"; shift 2 ;;
    --result) [ "$#" -ge 2 ] || sn_die2 "--result needs a value"; RESULT="$2"; have_result=1; shift 2 ;;
    --result-file)
      [ "$#" -ge 2 ] && [ -r "$2" ] || sn_die2 "--result-file needs a readable file"
      RESULT="$(cat "$2")"; have_result=1; shift 2 ;;
    --root) [ "$#" -ge 2 ] && [ -n "$2" ] || sn_die2 "--root needs a value"; ROOT="$2"; shift 2 ;;
    --non-interactive) F_NONINT=1; flag_given=1; shift ;;
    --subagent) F_SUBAGENT=1; F_NONINT=1; flag_given=1; shift ;;
    --cheap) F_CHEAP=1; flag_given=1; shift ;;
    --max-tokens)
      [ "$#" -ge 2 ] && [[ "$2" =~ ^[0-9]{1,12}$ ]] || sn_die2 "--max-tokens needs a token count"
      F_MAXTOK="$2"; flag_given=1; shift 2 ;;
    --base-branch) [ "$#" -ge 2 ] && [ -n "$2" ] || sn_die2 "--base-branch needs a value"; F_BASE="$2"; flag_given=1; shift 2 ;;
    --branch) [ "$#" -ge 2 ] && [ -n "$2" ] || sn_die2 "--branch needs a value"; F_BRANCH="$2"; flag_given=1; shift 2 ;;
    --skip-preflight-sync) F_SKIP_PF=1; flag_given=1; shift ;;
    --skip-children-check) F_SKIP_CH=1; flag_given=1; shift ;;
    --sequential) F_SEQ=1; flag_given=1; shift ;;
    --max-workers)
      [ "$#" -ge 2 ] && [[ "$2" =~ ^[1-9][0-9]?$ ]] || sn_die2 "--max-workers needs a count 1-99"
      F_MAXW="$2"; flag_given=1; shift 2 ;;
    -h|--help) sn_usage; exit 0 ;;
    *) sn_die2 "unknown argument '$1'" ;;
  esac
done
[ -n "$SID" ] || { sn_usage >&2; sn_die2 "session_id_missing — every call names this run's --session-id"; }
[[ "$SID" =~ ^[A-Za-z0-9._:-]{1,128}$ ]] && [ "$SID" != . ] && [ "$SID" != .. ] \
  || sn_die2 "session_id_malformed — '$SID'"
if [ "$have_result" = 1 ]; then
  printf '%s' "$RESULT" | "$JQ" -e 'type == "object"' >/dev/null 2>&1 || sn_die2 "--result is not a JSON object"
fi
[ -z "$JOB_ARG" ] || [ "$have_result" = 0 ] || sn_die2 "--job starts a run; --result answers its pending instruction — not both"
[ "$flag_given" = 0 ] || [ -n "$JOB_ARG" ] || sn_die2 "run flags are given once, with --job (they persist in the sidecar)"

if [ -z "$ROOT" ]; then ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; fi
cd "$ROOT" 2>/dev/null || sn_die2 "--root is not a directory: $ROOT"
ROOT="$(pwd -P)"   # physical: an absolute --job under a symlinked path (macOS /var → /private/var) still matches
for b in "$F_BASE" "$F_BRANCH"; do
  [ -z "$b" ] || git check-ref-format --branch "$b" >/dev/null 2>&1 || sn_die2 "not a valid branch name: '$b'"
done
SIDECAR="$ROOT/.supervisor/logs/$SID.supervisor-next-step.json"

# ------------------------------------------------------------------------------------------------
# state (the sidecar's JSON, held in SN_STATE; written once at exit)
# ------------------------------------------------------------------------------------------------
SN_STATE='{}'
if [ -f "$SIDECAR" ] && "$JQ" -e 'type == "object"' "$SIDECAR" >/dev/null 2>&1; then
  SN_STATE="$(cat "$SIDECAR")"
fi
st() { printf '%s' "$SN_STATE" | "$JQ" -r --arg k "$1" '.[$k] // empty | if type == "string" then . else tojson end'; }
st_set() { SN_STATE="$(printf '%s' "$SN_STATE" | "$JQ" -c --arg k "$1" --arg v "$2" '.[$k] = $v')"; }
st_setj() { SN_STATE="$(printf '%s' "$SN_STATE" | "$JQ" -c --arg k "$1" --argjson v "$2" '.[$k] = $v')"; }
st_del() { SN_STATE="$(printf '%s' "$SN_STATE" | "$JQ" -c --arg k "$1" 'del(.[$k])')"; }
fl() { printf '%s' "$SN_STATE" | "$JQ" -r --arg k "$1" '.flags[$k] // empty | tostring'; }
st_save() {
  local t="$SIDECAR.tmp.$$"
  mkdir -p "$(dirname "$SIDECAR")" 2>/dev/null
  printf '%s\n' "$SN_STATE" | "$JQ" -S . > "$t" 2>/dev/null && mv -f "$t" "$SIDECAR" \
    || { rm -f "$t"; sn_err "cannot write $SIDECAR"; return 1; }
}
rj() { printf '%s' "$1" | "$JQ" -r --arg k "$2" '.[$k] // empty | if type == "string" then . else tojson end' 2>/dev/null; }

SN_RC=0
sn_refuse() { sn_err "$*"; SN_RC=2; return 1; }   # input refused before any write of this step
# sn_event <outcome> <code> — #618: an opt-in telemetry script event (docs/TELEMETRY.md "What the engine
# reports") from this checkout; fire-and-forget — it never changes what this call prints or returns.
sn_event() { bash "$HERE/emit-script-event.sh" --root "$ROOT" supervisor-next-step run "$1" "$2" >/dev/null 2>&1 </dev/null || true; }
sn_fail() { sn_err "$*"; SN_RC=1; return 1; }     # a write / helper failure, surfaced

# ------------------------------------------------------------------------------------------------
# instructions (exactly one per call, compact JSON on stdout)
# ------------------------------------------------------------------------------------------------
SN_EMIT=""
SN_ACQUIRED=0   # set by acquire: the instruction printed in that call also carries branch_action (+ base_sync)
sn_emit() { # <do> <step> <extra json>
  local acq='{}'
  [ "$SN_ACQUIRED" = 1 ] && acq="$("$JQ" -cn --arg a "$(st branch_action)" --arg s "$(st base_sync)" \
    '{branch_action: $a} + (if $s != "ok" then {base_sync: $s} else {} end)')"
  SN_EMIT="$("$JQ" -cn --arg d "$1" --arg s "$2" --arg sid "$SID" --arg j "$(st job)" --arg b "$(st branch)" --argjson x "$3" \
    --argjson acq "$acq" '{do: $d, step: $s, session_id: $sid, job: (if $j == "" then null else $j end),
      branch: (if $b == "" then null else $b end)} + $acq + $x')"
}
# sn_spawn <step> <what> <answer step> <extra json> — the --result answering it goes to <answer step>
sn_spawn() {
  st_set answer_arm "$3"
  sn_emit spawn "$1" "$("$JQ" -cn --arg w "$2" --argjson x "$4" '{what: $w} + $x')"
}
# sn_ck <step> <answer step> <ops json array> — ONE Context-Keeper spawn applying <ops> in order
sn_ck() {
  sn_spawn "$1" context-keeper "$2" "$("$JQ" -cn --argjson o "$3" '{agent: "loomwright:context-keeper",
    state_file: ".supervisor/state.md", ops: $o,
    then: "--result \u007b\u0022confirmed\u0022: true\u007d once Context-Keeper applied every op, in order"}')"
}
# sn_ask <step> <gate> <cant_ask status> <question> <answer step> — options and header from the ONE
# catalog (`lane-policy.sh catalog`): header = the gate's code, human-only gates included (decide never
# answers a human-only code; an empty header hid which gate a relayed question was — wave 7)
sn_ask() {
  local row labels hdr opts
  row="$(bash "$HERE/lane-policy.sh" catalog 2>/dev/null | awk -F'\t' -v c="$2" '$1 == c { print; exit }')"
  [ -n "$row" ] || { sn_fail "lane-policy.sh catalog has no $2 row — cannot ask"; return 1; }
  labels="$(printf '%s' "$row" | cut -f3)"; hdr="$2"
  opts="$("$JQ" -cn --arg l "$labels" '$l | split("|") | map(sub("\\?$"; ""))')"
  st_setj ask_options "$opts"; st_set answer_arm "$5"
  sn_emit ask "$1" "$("$JQ" -cn --arg g "$2" --arg h "$hdr" --arg q "$4" --arg c "$3" --argjson o "$opts" \
    '{gate: $g, question: $q, header: $h, options: $o, cant_ask: $c,
      questions: [{question: $q, header: $h, options: $o}],
      answer_with: "--result \u007b\u0022answers\u0022: [<one option label>], \u0022note\u0022: \u0022<free text, optional>\u0022\u007d; when the ask tool is unavailable --result \u007b\u0022cant_ask\u0022: true\u007d"}')"
}
# sn_park <step> <status> <error> <message> — the run stops here; the model emits its SUPERVISOR_RESULT
sn_park() {
  sn_emit park "$1" "$("$JQ" -cn --arg s "$2" --arg e "$3" --arg m "$4" --arg p "$(st preflight_sync)" \
    '{status: $s} + (if $e != "" then {error: $e} else {} end)
     + {preflight_sync: (if $p == "" then null else $p end), message: $m}')"
}

# Context-Keeper operation text (the call form the phase skills print)
sn_op_clear() { printf 'Context-Keeper(operation: clear_flag, key: "%s")' "$1"; }
sn_op_set() { printf 'Context-Keeper(operation: set_flag, key: "%s", value: %s)' "$1" "$2"; }
sn_op_decision() { # <phase> <decision> <rationale>
  printf 'Context-Keeper(operation: record_decision, phase: %s, decision: "%s", rationale: %s)' \
    "$1" "$2" "$("$JQ" -cn --arg r "$3" '$r')"
}
sn_ops() { "$JQ" -cn '$ARGS.positional' --args "$@"; }

# ------------------------------------------------------------------------------------------------
# reads
# ------------------------------------------------------------------------------------------------
sn_one_line() { case "$1" in *$'\n'*|*$'\r'*) return 1 ;; *) [ "${#1}" -le 2000 ] ;; esac; }
# sn_check_strings <json> <field…> — each present field a one-line string (≤ 2000 chars)
sn_check_strings() {
  local r="$1" k v; shift
  for k in "$@"; do
    printf '%s' "$r" | "$JQ" -e --arg k "$k" '.[$k] == null or (.[$k] | type) == "string"' >/dev/null 2>&1 \
      || { sn_refuse "--result: $k must be a string — nothing written"; return 1; }
    v="$(rj "$r" "$k")"
    sn_one_line "$v" || { sn_refuse "--result: $k must be one line of at most 2000 characters — nothing written"; return 1; }
  done
}
# sn_answer <json> — sets SN_ANS to the label of a one-question ask's answer (`answers[0]` or `answer`),
# checked against the options the ask printed; `cant_ask` for {"cant_ask": true}. Never call it in a
# command substitution: its refusal code (SN_RC=2) must reach the dispatcher
SN_ANS=""
sn_answer() {
  local a
  SN_ANS=""
  if [ "$(rj "$1" cant_ask)" = true ]; then SN_ANS=cant_ask; return 0; fi
  a="$(printf '%s' "$1" | "$JQ" -r 'if (.answers | type) == "array" then (if (.answers | length) == 1 then .answers[0] else empty end) else (.answer // empty) end | strings' 2>/dev/null)"
  [ -n "$a" ] || { sn_refuse "--result: one answer expected ({\"answers\": [<label>]}) — nothing written"; return 1; }
  printf '%s' "$(st ask_options)" | "$JQ" -e --arg a "$a" 'index($a) != null' >/dev/null 2>&1 \
    || { sn_refuse "--result: '$a' is not one of the ask's options $(st ask_options) — nothing written"; return 1; }
  SN_ANS="$a"
}
sn_job_base() { local j; j="$(st job)"; printf '%s' "${j##*/}"; }
# sn_brief_conf <field> <brief> — the value of `- **<field>:** <v>` inside the brief's `## Configuration`
# (its first word, backticks dropped)
sn_brief_conf() {
  SN_F="- **$1:**" awk 'BEGIN { f = ENVIRON["SN_F"] }
    /^## / { s = ($0 == "## Configuration"); next }
    s && index($0, f) == 1 { v = substr($0, length(f) + 1); gsub(/`/, "", v); sub(/^[ \t]+/, "", v); sub(/[ \t].*/, "", v); print v; exit }' "$2" 2>/dev/null
}
# sn_brief_subtasks <brief> — the ids of the brief's `## Subtask Structure` table, in order, as a JSON
# array (the first cell of each data row; the header and separator rows skipped); empty when none parse
sn_brief_subtasks() {
  awk '/^## / { s = ($0 == "## Subtask Structure"); next }
    s && /^\|/ && !/^\|[ :|-]+$/ { c = $0; sub(/^\|[ \t]*/, "", c); sub(/[ \t]*\|.*/, "", c); print c }' "$1" 2>/dev/null \
    | "$JQ" -R -s -c 'split("\n") | map(select(test("^[A-Za-z0-9._-]{1,64}$"))) | if length == 0 then empty else . end' 2>/dev/null
}

# sn_job_fail — the job brief to `failed/` (from `in-progress/` or `pending/`); other layouts stay put
sn_job_fail() {
  local j b t; j="$(st job)"; b="${j##*/}"
  case "$j" in
    .supervisor/jobs/in-progress/*|.supervisor/jobs/pending/*)
      t=".supervisor/jobs/failed/$b"
      mkdir -p .supervisor/jobs/failed && mv -f "$j" "$t" 2>/dev/null || { sn_fail "cannot move $j to $t"; return 1; }
      st_set job "$t" ;;
  esac
  return 0
}

# ================================================================================================
# steps
# ================================================================================================

# init — Phase 0 (skills/supervisor-config/SKILL.md steps 4–7 and the 5a preamble's flag records)
sn_init() {
  local jp b t title ops gc ge gd ni_src mode maxw cost bm bw bb base gi gp
  jp="$JOB_ARG"
  case "$jp" in
    /*) t="$(cd "$(dirname "$jp")" 2>/dev/null && pwd -P)"; [ -z "$t" ] || jp="$t/${jp##*/}" ;;
  esac
  case "$jp" in "$ROOT"/*) jp="${jp#"$ROOT"/}" ;; esac
  jp="${jp#./}"
  b="${jp##*/}"
  if [ ! -f "$jp" ]; then
    # a re-entry after the move names the pending path the owner first gave
    if [ -f ".supervisor/jobs/in-progress/$b" ]; then jp=".supervisor/jobs/in-progress/$b"
    else sn_refuse "job_not_found — no brief at '$JOB_ARG' (nor in .supervisor/jobs/in-progress/)"; return 1; fi
  fi
  # step 4: the .supervisor/ bootstrap
  mkdir -p .supervisor/history .supervisor/jobs/pending .supervisor/jobs/in-progress .supervisor/jobs/done \
    .supervisor/jobs/failed .supervisor/logs || { sn_fail "cannot create the .supervisor/ directories"; return 1; }
  # `.supervisor/` must stay ignored: a bare line, or `/setup memory`'s managed block (`.supervisor/*` +
  # `!.supervisor/memory/`, no bare line — a bare line appended after it re-ignores the memory store and
  # dirties the tracked .gitignore, #615). So ask git, not the file text, about two child paths
  # (`.supervisor` itself is not reliably reported): both ignored ⇒ nothing to write; either not ⇒
  # append; any other exit (128 outside a repo, 127 with no git) ⇒ the exact-line test
  gi=ignored
  for gp in .supervisor/state.md .supervisor/logs/x.json; do
    git check-ignore -q --no-index "$gp" >/dev/null 2>&1
    case "$?" in 0) ;; 1) gi=append ;; *) gi=fallback; break ;; esac
  done
  if [ "$gi" = fallback ] && grep -qxF '.supervisor/' .gitignore 2>/dev/null; then gi=ignored; fi
  if [ "$gi" != ignored ]; then
    { [ ! -s .gitignore ] || [ -z "$(tail -c 1 .gitignore)" ] || printf '\n' >> .gitignore; } \
      && printf '%s\n' '.supervisor/' >> .gitignore || { sn_fail "cannot append .supervisor/ to .gitignore"; return 1; }
  fi
  # step 6: pending/ → in-progress/ (a brief outside pending/ — the old flat layout — stays where it is)
  case "$jp" in
    .supervisor/jobs/pending/*)
      t=".supervisor/jobs/in-progress/$b"
      [ ! -e "$t" ] || { sn_fail "job_move_target_exists — $t already exists; inspect it before re-running"; return 1; }
      mv "$jp" "$t" || { sn_fail "cannot move $jp to $t"; return 1; }
      jp="$t" ;;
  esac
  st_set job "$jp"
  st_set task_id "${b%.md}"
  title="$(sed -n 's/^# Supervisor Job: *//p' "$jp" | head -n 1)"
  [ -n "$title" ] || title="$(sed -n 's/^# *//p' "$jp" | head -n 1)"
  st_set title "${title:-${b%.md}}"
  # step 7: arm the test-integrity guard — a failed arm is recorded, never fatal
  if [ -n "${SUPERVISOR_NEXT_STEP_GUARD_CMD:-}" ]; then
    # shellcheck disable=SC2086
    ge="$($SUPERVISOR_NEXT_STEP_GUARD_CMD </dev/null 2>&1 >/dev/null)"; gc=$?
  else
    ge="$(bash "$HERE/guard-arm.sh" arm supervisor </dev/null 2>&1 >/dev/null)"; gc=$?
  fi
  ge="$(printf '%s' "$ge" | head -n 1)"
  if [ "$gc" -eq 0 ]; then gd="guard_armed: ok"; else gd="guard_armed: failed: ${ge:-exit $gc}"; fi
  # step 5 + the 5a preamble: initialize, the clear-on-start crash-recovery flags, the re-armed flags
  # the run's config: a flag wins, else the brief's `## Configuration` (Launch Pad pre-answers the INIT
  # questions: `- **Mode:** sequential`, `- **Workers:** N`, `- **Base Branch:** B`), else the default
  bm="$(sn_brief_conf Mode "$jp")"; bw="$(sn_brief_conf Workers "$jp")"; bb="$(sn_brief_conf 'Base Branch' "$jp")"
  if [ "$(fl sequential)" = true ] || [ "$bm" = sequential ]; then mode=sequential; maxw=1
  else
    mode=parallel; maxw="$(fl max_workers)"
    [ -n "$maxw" ] || { [[ "$bw" =~ ^[1-9][0-9]?$ ]] && maxw="$bw"; } || maxw=2
  fi
  if [ "$(fl cheap)" = true ]; then cost=cheap; else cost=default; fi
  base="$(fl base_branch)"
  if [ -z "$base" ] && [ -n "$bb" ] && git check-ref-format --branch "$bb" >/dev/null 2>&1; then base="$bb"; fi
  [ -n "$base" ] || base=main
  st_set mode "$mode"; st_setj max_workers "$maxw"; st_set cost_profile "$cost"; st_set base_branch "$base"
  set -- "$(printf 'Context-Keeper(operation: initialize, config: %s, session: %s)' \
      "$("$JQ" -cn --argjson w "$maxw" --arg m "$mode" --arg c "$cost" '{max_workers: $w, mode: $m, cost_profile: $c}')" \
      "$("$JQ" -cn --arg s "$SID" --arg t "$(st task_id)" '{session_id: $s, task_id: $t}')")" \
    "$(sn_op_clear base_mismatch_detected)" "$(sn_op_clear non_interactive)"
  if [ "$(fl non_interactive)" = true ]; then
    if [ "$(fl subagent)" = true ]; then ni_src=subagent_context; else ni_src=supervisor_flag; fi
    set -- "$@" "$(sn_op_set non_interactive "$("$JQ" -cn --arg t "$(sn_ts)" --arg s "$ni_src" '{set_at: $t, source: $s}')")"
  fi
  if [ -n "$(fl max_tokens)" ]; then
    set -- "$@" "$(sn_op_set max_tokens "$("$JQ" -cn --argjson n "$(fl max_tokens)" --arg t "$(sn_ts)" '{limit: $n, set_at: $t}')")"
  fi
  set -- "$@" "$(sn_op_decision INIT "$gd" "guard-arm.sh arm supervisor exited $gc")"
  ops="$(sn_ops "$@")"
  sn_ck init acquire "$ops"
}

# acquire — Phase 1 step 4 (agents/supervisor.md): the idempotent branch guard, then the /autonomous
# state.json ACQUIRE fields (commands/supervisor.md §"Inline-path canonical state writes")
sn_acquire() {
  local base br btip tip e sync=ok
  base="$(st base_branch)"; [ -n "$base" ] || base=main
  br="$(fl branch)"
  if [ -z "$br" ]; then br="$(st task_id)"; br="feature/$(printf '%s' "$br" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//')"; fi
  git check-ref-format --branch "$br" >/dev/null 2>&1 || { sn_fail "the feature branch '$br' is not a valid branch name — pass --branch"; return 1; }
  git fetch -q origin "$base" >/dev/null 2>&1 || sync=fetch_failed
  e="$(git checkout -q "$base" 2>&1)" || { sn_fail "git checkout $base failed: $(printf '%s' "$e" | head -n 2 | tr '\n' ' ')"; return 1; }
  if [ "$sync" = ok ]; then git pull -q --ff-only origin "$base" >/dev/null 2>&1 || sync=pull_failed; fi
  [ "$sync" = ok ] || sn_err "base sync: $sync — the branch guard compares against the local $base tip"
  st_set base_sync "$sync"
  tip="$(git rev-parse --verify --quiet "$base^{commit}")" || { sn_fail "the base branch '$base' does not resolve"; return 1; }
  if git rev-parse --verify --quiet "refs/heads/$br" >/dev/null; then
    btip="$(git rev-parse "refs/heads/$br")"
    if [ "$btip" != "$tip" ]; then
      # UNSAFE to reuse silently (unattributable commits): never check out, never delete — STOP
      sn_park acquire failed "acquire_branch_collision: $br diverges from $base tip" \
        "branch '$br' already exists and is NOT identical to $base tip ($btip vs $tip). Inspect: git log $br --oneline -5 ; git diff $base...$br --stat. Then resume it yourself if it is your crashed run, delete/rename it if disposable, or pass a different --branch. Nothing was acquired; the job file stays where it is."
      return 0
    fi
    e="$(git checkout -q "$br" 2>&1)" || { sn_fail "git checkout $br failed: $e"; return 1; }
    st_set branch_action REUSED
  else
    e="$(git checkout -q -b "$br" 2>&1)" || { sn_fail "git checkout -b $br failed: $e"; return 1; }
    st_set branch_action CREATED
  fi
  st_set branch "$br"; SN_ACQUIRED=1
  sn_state_json "$br"
  NEXT=preflight
}

# sn_state_json <branch> — the ONE active /autonomous state.json whose current_brief_path basename is
# this job's: current_branch + current_status "running" (jq, temp + rename). No match, several matches or
# any error ⇒ a logged no-op — best-effort, never gates the run
sn_state_json() {
  local f b n=0 hit="" t
  b="$(sn_job_base)"
  for f in .supervisor/autonomous/*/state.json; do
    [ -f "$f" ] || continue
    if "$JQ" -e --arg b "$b" '((.current_brief_path // "") | split("/") | last) == $b and (.ended_at // null) == null' "$f" >/dev/null 2>&1; then
      n=$((n + 1)); hit="$f"
    fi
  done
  [ "$n" -gt 0 ] || return 0
  if [ "$n" -gt 1 ]; then sn_err "autonomous state.json: $n active sessions name $b — ambiguous, skipped"; return 0; fi
  t="$hit.tmp.$$"
  if "$JQ" --arg br "$1" '.current_branch = $br | .current_status = "running"' "$hit" > "$t" 2>/dev/null && mv -f "$t" "$hit"; then
    st_set autonomous_state "$hit"
  else
    rm -f "$t"; sn_err "autonomous state.json: update of $hit failed — skipped (best-effort)"
  fi
  return 0
}

# preflight — Phase 1.5 entry (skills/preflight-sync/SKILL.md action 1, or actions 2–5 handed to the model)
sn_preflight() {
  if [ "$(fl skip_preflight_sync)" = true ]; then
    st_set preflight_sync skipped
    sn_ck preflight plan "$(sn_ops "$(sn_op_decision PRE_FLIGHT_SYNC preflight_skipped "--skip-preflight-sync flag")")"
    return 0
  fi
  sn_spawn preflight preflight-sync preflight-route "$("$JQ" -cn --arg b "$(st base_branch)" '{base_branch: $b,
    invocation: "Read skills/preflight-sync/SKILL.md (under the plugin install root) and run its actions 2-5 (gather remote state, the anticipated file set, classify, stacked-iteration scoping) inside its tool-call budget; do not act on the classification, report it",
    then: "--result \u007b\u0022classification\u0022: \u0022CLEAR|OVERLAP|SUPERSEDED|UNVERIFIED\u0022, \u0022version\u0022: \u0022<canonical version>\u0022, \u0022base_tip\u0022: \u0022<base tip sha>\u0022, \u0022citations\u0022: \u0022<the overlapping commits / PRs and the intersecting paths — OVERLAP and SUPERSEDED>\u0022, \u0022advisory\u0022: \u0022<churn_since_brief / premise_check notes, optional>\u0022, \u0022warning\u0022: \u0022<the one tooling warning — UNVERIFIED>\u0022\u007d"}')"
}

# preflight-route — the classification report (action 6)
sn_preflight_route() {
  local r="$ANSWER" c v t a cit
  c="$(rj "$r" classification)"
  case "$c" in CLEAR|OVERLAP|SUPERSEDED|UNVERIFIED) ;; *) sn_refuse "--result: classification must be CLEAR|OVERLAP|SUPERSEDED|UNVERIFIED (got '$c') — nothing written"; return 1 ;; esac
  sn_check_strings "$r" version base_tip citations advisory warning || return 1
  v="$(rj "$r" version)"; t="$(rj "$r" base_tip)"; a="$(rj "$r" advisory)"; cit="$(rj "$r" citations)"
  case "$c" in
    CLEAR)
      [ -n "$v" ] || { sn_refuse "--result: a CLEAR report names the canonical version — nothing written"; return 1; }
      [[ "$t" =~ ^[0-9a-fA-F]{7,40}$ ]] || { sn_refuse "--result: a CLEAR report names the base tip sha (got '$t') — nothing written"; return 1; } ;;
    OVERLAP|SUPERSEDED)
      [ -n "$cit" ] || { sn_refuse "--result: an $c report cites the commits / PRs and the intersecting paths — nothing written"; return 1; } ;;
  esac
  st_set preflight_class "$c"; st_set preflight_citations "$cit"
  case "$c" in
    CLEAR)
      st_set preflight_sync clear
      sn_ck preflight-route plan "$(sn_ops "$(sn_op_decision PRE_FLIGHT_SYNC preflight_clear "version=$v, base_tip=$t, no overlap${a:+; $a}")")" ;;
    UNVERIFIED)
      # graceful degradation: one warning (the model's), preflight_sync = unverified, continue to PLAN
      st_set preflight_sync unverified
      st_set preflight_warning "$(rj "$r" warning)"
      NEXT=plan ;;
    *)
      if [ "$(fl non_interactive)" = true ]; then sn_preflight_fail_closed
      else
        sn_ask preflight-route SUP-OVERLAP preflight_overlap_detected \
          "Pre-flight sync classified this task $c: $cit. Proceed anyway, revise the scope (checkpoint), or abort?" preflight-answer
      fi ;;
  esac
}

# OVERLAP / SUPERSEDED that cannot ask (--non-interactive, a subagent, or a cant_ask answer): fail CLOSED
sn_preflight_fail_closed() {
  sn_job_fail || return 1
  sn_park preflight-route failed preflight_overlap_detected \
    "$(st preflight_class) cannot be asked (--non-interactive, a subagent, or a cant_ask answer) and fails closed — only --skip-preflight-sync proceeds past it: $(st preflight_citations). No worker spawned; the job brief is in failed/."
}

# preflight-answer — the SUP-OVERLAP answer
sn_preflight_answer() {
  local a c cit d
  sn_answer "$ANSWER" || return 1
  a="$SN_ANS"
  c="$(st preflight_class)"; cit="$(st preflight_citations)"
  case "$a" in
    cant_ask) sn_preflight_fail_closed ;;
    proceed-anyway)
      if [ "$c" = SUPERSEDED ]; then st_set preflight_sync superseded_proceed; d=preflight_superseded_proceed
      else st_set preflight_sync overlap_proceed; d=preflight_overlap_proceed; fi
      sn_ck preflight-answer plan "$(sn_ops "$(sn_op_decision PRE_FLIGHT_SYNC "$d" "$cit")")" ;;
    revise-scope)
      st_set preflight_stop revise
      sn_ck preflight-answer preflight-stop "$(sn_ops "$(sn_op_decision PRE_FLIGHT_SYNC preflight_revise_scope "$cit")")" ;;
    abort)
      st_set preflight_stop abort
      sn_ck preflight-answer preflight-stop "$(sn_ops "$(sn_op_decision PRE_FLIGHT_SYNC preflight_abort "$c — $cit")")" ;;
    *) sn_fail "internal: unrouted SUP-OVERLAP label '$a'"; return 1 ;;
  esac
}

# preflight-stop — after the revise-scope / abort record
sn_preflight_stop() {
  case "$(st preflight_stop)" in
    revise)
      sn_park preflight-stop checkpoint "" \
        "revise-scope: no worker spawned; the feature branch $(st branch) is kept. Re-invoke /supervisor with the narrowed task (reuse the branch, or delete it first if the new scope needs another name); Phase 1.5 re-evaluates the revised scope." ;;
    abort)
      sn_job_fail || return 1
      sn_park preflight-stop failed "preflight_overlap_detected: $(st preflight_class) — $(st preflight_citations)" \
        "aborted at the pre-flight gate: no worker spawned; the job brief is in failed/." ;;
    *) sn_fail "preflight-stop: no revise-scope / abort decision recorded in the sidecar"; return 1 ;;
  esac
}

# plan — Phase 2. A `job:` brief pre-answers PLAN: its `## Subtask Structure` table (a required section)
# is the plan, and no orchestrator is spawned. Only a brief whose table names no subtask id gets the
# orchestrator spawn (action 1 — pointers, never pasted brief bodies)
sn_plan() {
  local n ids
  ids="$(sn_brief_subtasks "$(st job)")"
  if [ -n "$ids" ]; then
    st_set plan_source brief
    sn_select_path "$ids"
    return 0
  fi
  n="$(awk '/^## / { s = ($0 == "## Acceptance Criteria") ; next } s && /^- \[[ xX]\] / { c++ } END { print c + 0 }' "$(st job)" 2>/dev/null)"
  sn_spawn plan orchestrator plan-result "$("$JQ" -cn --arg g "$(st task_id): $(st title)" --arg b "$(st job)" \
    --arg c "${n:-0} acceptance criteria — read the brief's ## Acceptance Criteria" --arg p "$(st preflight_sync)" \
    --arg w "$(st preflight_warning)" --arg ch "$(fl cheap)" '{agent: "loomwright:orchestrator", goal: $g, brief: $b,
      brief_note: "read only the sections you need", criteria: $c,
      preflight_sync: (if $p == "" then null else $p end)}
    + (if $w != "" then {preflight_warning: $w} else {} end)
    + (if $ch == "true" then {cost_profile: "cheap"} else {} end)
    + {then: "--result \u007b\u0022subtasks\u0022: [\u007b\u0022id\u0022: \u0022<subtask id>\u0022, \u0022title\u0022: \u0022<title>\u0022\u007d, …]\u007d — the plan, in order"}')"
}

# plan-result — Phase 2 action 4: path selection by subtask count
sn_plan_result() {
  local r="$ANSWER" ids
  ids="$(printf '%s' "$r" | "$JQ" -c '.subtasks | if type == "array" and length >= 1 and length <= 50
      then [.[] | if type == "string" then . elif type == "object" then (.id | strings) else empty end] else empty end' 2>/dev/null)"
  [ -n "$ids" ] || { sn_refuse "--result: subtasks must be an array of 1-50 {\"id\": …} entries — nothing written"; return 1; }
  printf '%s' "$ids" | "$JQ" -e --argjson n "$(printf '%s' "$r" | "$JQ" '.subtasks | length')" \
    'length == $n and (unique | length) == $n and all(.[]; test("^[A-Za-z0-9._-]{1,64}$"))' >/dev/null 2>&1 \
    || { sn_refuse "--result: every subtask carries a unique id of [A-Za-z0-9._-] (1-64) — nothing written"; return 1; }
  st_set plan_source orchestrator
  sn_select_path "$ids"
}

# sn_select_path <ids json> — action 4 (`skills/supervisor-readiness/SKILL.md` §"Decomposition
# Threshold"): exactly 1 subtask ⇒ single-agent; sequential mode with more ⇒ sequential; else parallel.
# No path spawns a per-subtask reviewer
sn_select_path() {
  local n p
  n="$(printf '%s' "$1" | "$JQ" 'length')"
  if [ "$n" -eq 1 ]; then p=single-agent
  elif [ "$(st mode)" = sequential ]; then p=sequential
  else p=parallel; fi
  st_setj subtasks "$1"; st_set path "$p"; st_setj seq_index 0
  NEXT=execute
}

# execute — Phase 3 entry: the spawn the selected path runs (its result is routed by the Phase 3 steps)
sn_execute() {
  local p i id ch
  p="$(st path)"; ch="$(fl cheap)"
  case "$p" in
    parallel)
      sn_spawn execute execute-manager execute-result "$("$JQ" -cn --arg b "$(st job)" --argjson s "$(st subtasks)" \
        --argjson w "$(st max_workers)" --arg base "$(st base_branch)" --arg ps "$(st plan_source)" --arg ch "$ch" \
        '{agent: "loomwright:execute-manager", path: "parallel", plan_source: $ps, brief: $b,
          brief_note: "read only the sections you need", subtasks: $s, max_workers: $w, base_branch: $base}
        + (if $ch == "true" then {cost_profile: "cheap"} else {} end)
        + {then: "--result \u007b\u0022result\u0022: \u0022<the EXECUTE_RESULT or EXECUTE_CHECKPOINT block, verbatim>\u0022\u007d; when the Execute Manager returned neither block (a crash), --result \u007b\u0022crashed\u0022: true, \u0022error\u0022: \u0022<what the Task call returned, one line>\u0022\u007d"}')" ;;
    single-agent|sequential)
      i="$(st seq_index)"; [ -n "$i" ] || i=0
      id="$(printf '%s' "$(st subtasks)" | "$JQ" -r --argjson i "$i" '.[$i] // empty')"
      [ -n "$id" ] || { sn_fail "execute: no subtask at index $i"; return 1; }
      sn_spawn execute worker execute-result "$("$JQ" -cn --arg p "$p" --arg b "$(st job)" --arg id "$id" --arg r "$ROOT" \
        --arg ps "$(st plan_source)" --arg ch "$ch" '{agent: "loomwright:worker", path: $p, plan_source: $ps, subtask: $id, brief: $b,
          brief_note: "read only your subtask\u0027s sections", worktree: $r}
        + (if $ch == "true" then {cost_profile: "cheap"} else {} end)
        + {gates: "record the WORKER_RESULT via Context-Keeper record_worker_result (with its out_of_lane, deviations and not_verified), then run the per-subtask gates of agents/supervisor.md Single-Agent Path steps 3-3b (verify-provides.sh on disk, the pin-mutation gate, the check-children-settled.sh --agent-id join)",
           then: "--result \u007b\u0022subtask\u0022: \u0022<id>\u0022, \u0022agent_id\u0022: \u0022<the Task-returned id>\u0022, \u0022status\u0022: \u0022<the WORKER_RESULT status>\u0022, \u0022gates\u0022: \u0022passed|paused\u0022, \u0022reason\u0022: \u0022<one line — why the gates paused>\u0022\u007d"}')" ;;
    *) sn_fail "execute: no execution path selected (plan-result has not run)"; return 1 ;;
  esac
}

# ------------------------------------------------------------------------------------------------
# Phase 3 / Phase 4 helpers
# ------------------------------------------------------------------------------------------------
sn_gh() { "${LOOMWRIGHT_GH_BIN:-gh}" "$@" </dev/null 2>/dev/null; }
sn_jstr() { "$JQ" -cn --arg s "$1" '$s'; }   # a JSON string literal
sn_op_error() { # <phase> <error> <resolution> — Context-Keeper's record_error (retry 0/0: a gate, not a retry)
  printf 'Context-Keeper(operation: record_error, phase: %s, error: %s, retry: 0/0, resolution: %s)' \
    "$1" "$(sn_jstr "$2")" "$(sn_jstr "$3")"
}
# sn_block <text> <name…> — the LAST named result block of <text>, parsed by THE shared parser of the
# result-block validators (result_block_parser.py — never a restated copy) into
# {"name", "fields", "errors"}; {"name": null} when <text> carries none. Non-zero when python3 / the
# parser cannot run
sn_block() {
  local t="$1"; shift
  printf '%s' "$t" | python3 -I -c 'import json, sys
sys.path.insert(0, sys.argv[1])
from result_block_parser import find_last_named_block, parse_block
name, block = find_last_named_block(sys.stdin.read(), sys.argv[2:])
if name is None:
    print(json.dumps({"name": None}))
else:
    fields, errors = parse_block(block)
    print(json.dumps({"name": name, "fields": fields, "errors": errors}))' "$HERE" "$@" 2>/dev/null
}
sn_true() { case "$1" in true|True|TRUE) return 0 ;; *) return 1 ;; esac; }
SN_NL='
'
SN_TAB="$(printf '\t')"
# sn_in_lines <needle> <newline-separated list> — an exact line match
sn_in_lines() { case "$SN_NL$2$SN_NL" in *"$SN_NL$1$SN_NL"*) return 0 ;; *) return 1 ;; esac; }
# sn_ck_stop <step> <stop arm> <ops json> <status> <error> <message> <0|1 move the job to failed/> —
# the Context-Keeper record of a stop, then (its confirmation answering) the stop arm's park
sn_ck_stop() {
  st_setj stop "$("$JQ" -cn --arg s "$4" --arg e "$5" --arg m "$6" --argjson j "$7" \
    '{status: $s, error: $e, message: $m, fail_job: ($j == 1)}')"
  sn_ck "$1" "$2" "$3"
}
# sn_stop <step> — the execute-stop / finalize-stop arm: the recorded stop's park
sn_stop() {
  local s; s="$(st stop)"
  [ -n "$s" ] || { sn_fail "$1: no stop recorded in the sidecar"; return 1; }
  if [ "$(printf '%s' "$s" | "$JQ" -r '.fail_job')" = true ]; then sn_job_fail || return 1; fi
  sn_park "$1" "$(printf '%s' "$s" | "$JQ" -r '.status')" "$(printf '%s' "$s" | "$JQ" -r '.error')" \
    "$(printf '%s' "$s" | "$JQ" -r '.message')"
}
# sn_physical <path> — the physical absolute path of an existing directory (relative = from the root)
sn_physical() { ( cd "$1" 2>/dev/null && pwd -P ); }

# ------------------------------------------------------------------------------------------------
# Phase 3 — the Supervisor-side routing of the spawn's answer (agents/supervisor.md §"Phase 3")
# ------------------------------------------------------------------------------------------------

# execute-result — the answer to the execute / execute-resume spawn
sn_execute_result() {
  case "$(st path)" in
    parallel) sn_execute_result_parallel ;;
    single-agent|sequential) sn_execute_result_inline ;;
    *) sn_fail "execute-result: no execution path selected"; return 1 ;;
  esac
}

# the Execute Manager's EXECUTE_RESULT / EXECUTE_CHECKPOINT (or its crash). EXECUTE_RESULT has no
# top-level status: `subtasks_failed` non-empty ⇔ escalation, `subtasks_completed` empty ⇔ all failed
sn_execute_result_parallel() {
  local r="$ANSWER" e b name f
  if [ "$(rj "$r" crashed)" = true ]; then
    sn_check_strings "$r" error || return 1
    e="$(rj "$r" error)"
    [ -n "$e" ] || { sn_refuse "--result: a crash report names the error — nothing written"; return 1; }
    sn_execute_crash "$e"; return
  fi
  printf '%s' "$r" | "$JQ" -e '(.result | type) == "string" and (.result | length) > 0' >/dev/null 2>&1 \
    || { sn_refuse "--result: {\"result\": \"<the EXECUTE_RESULT or EXECUTE_CHECKPOINT block>\"} or {\"crashed\": true, \"error\": …} — nothing written"; return 1; }
  b="$(sn_block "$(rj "$r" result)" EXECUTE_RESULT EXECUTE_CHECKPOINT)"
  [ -n "$b" ] || { sn_refuse "python3 / result_block_parser.py could not run — the block is unread; nothing written"; return 1; }
  name="$(printf '%s' "$b" | "$JQ" -r '.name // empty')"
  [ -n "$name" ] || { sn_refuse "--result: no EXECUTE_RESULT / EXECUTE_CHECKPOINT block in .result (an Execute Manager that returned none is reported as {\"crashed\": true, …}) — nothing written"; return 1; }
  if printf '%s' "$b" | "$JQ" -e '.errors | length > 0' >/dev/null; then
    sn_refuse "--result: the $name block does not parse: $(printf '%s' "$b" | "$JQ" -r '.errors | join("; ")') — nothing written"; return 1
  fi
  f="$(printf '%s' "$b" | "$JQ" -c '.fields')"
  case "$name" in
    EXECUTE_RESULT) sn_route_result "$f" ;;
    *) sn_route_checkpoint "$f" ;;
  esac
}

sn_route_result() {
  local f="$1" er nc nf
  printf '%s' "$f" | "$JQ" -e '(.subtasks_completed | type) == "array" and (.merge_order | type) == "array"
      and (.worktrees | type) == "array" and (.summary | type) == "string"
      and ((.subtasks_failed // []) | type) == "array"
      and all(.subtasks_completed[], .worktrees[], (.subtasks_failed // [])[]; type == "object")
      and all(.merge_order[]; type == "string")' >/dev/null 2>&1 \
    || { sn_refuse "--result: an EXECUTE_RESULT carries subtasks_completed, worktrees, merge_order (lists) and summary — nothing written"; return 1; }
  er="$(printf '%s' "$f" | "$JQ" -c '{completed: [.subtasks_completed[] | {task_id, status, branch, review_decision}],
      failed: [(.subtasks_failed // [])[] | {task_id, error}], merge_order,
      worktrees: [.worktrees[] | {task_id, path, branch, status}], branches: ((.branches // []) | map(strings)), summary}')"
  nc="$(printf '%s' "$er" | "$JQ" '.completed | length')"; nf="$(printf '%s' "$er" | "$JQ" '.failed | length')"
  [ "$nc" -gt 0 ] || [ "$nf" -gt 0 ] || { sn_refuse "--result: an EXECUTE_RESULT with no completed and no failed subtask — nothing written"; return 1; }
  st_setj exec_result "$er"
  if [ "$nc" -eq 0 ]; then
    # all-failed escalation: checkpoint, report with the resume command — nothing to merge
    sn_ck_stop execute-result execute-stop "$(sn_ops "$(sn_op_error EXECUTE \
        "all subtasks failed: $(printf '%s' "$er" | "$JQ" -r '[.failed[] | "\(.task_id) (\(.error // "no error"))"] | join("; ")')" \
        "checkpoint — nothing to merge")")" checkpoint "" \
      "EXECUTE ended with every subtask failed ($(printf '%s' "$er" | "$JQ" -r '[.failed[].task_id] | join(", ")')): nothing to merge, no PR. Resume with /supervisor --continue task: $(st task_id) once the failures are addressed." 0
    return 0
  fi
  # complete, or a partial escalation: FINALIZE the completed subset per merge_order, then report the
  # failed subtasks as an escalation in the same run (carried to the hand-over)
  [ "$nf" -gt 0 ] && st_setj escalation "$(printf '%s' "$er" | "$JQ" -c '.failed')"
  NEXT=finalize
}

sn_route_checkpoint() {
  local f="$1"
  printf '%s' "$f" | "$JQ" -e '(.completed_so_far | type) == "array" and (.remaining | type) == "array"
      and (.remaining | length) > 0 and (.reason | type) == "string" and (.resume_context | type) == "object"' >/dev/null 2>&1 \
    || { sn_refuse "--result: an EXECUTE_CHECKPOINT carries completed_so_far, a non-empty remaining, resume_context and reason — nothing written"; return 1; }
  st_setj exec_checkpoint "$(printf '%s' "$f" | "$JQ" -c '{completed_so_far: [.completed_so_far[] | if type == "object" then .task_id else . end],
      remaining: [.remaining[] | if type == "object" then .task_id else . end], resume_context, reason}')"
  if sn_true "$(printf '%s' "$f" | "$JQ" -r '.adjudication_required // "" | tostring')"; then
    sn_adjudicate "$f"; return
  fi
  # a budget / partial checkpoint: checkpoint via Context-Keeper and stop with the resume command
  sn_ck_stop execute-result execute-stop "$(sn_ops "$(sn_op_decision EXECUTE "execute_checkpoint: $(printf '%s' "$f" | "$JQ" -r '.reason')" \
      "$(printf '%s' "$f" | "$JQ" -r '"completed: \([.completed_so_far[] | if type == "object" then .task_id else . end] | join(", ")); remaining: \([.remaining[] | if type == "object" then .task_id else . end] | join(", "))"')")")" \
    checkpoint "" "The Execute Manager checkpointed ($(printf '%s' "$f" | "$JQ" -r '.reason')). Resume with /supervisor --continue task: $(st task_id): merge the completed subset now (FINALIZE with the subset) or continue with a fresh Execute Manager for the remaining subtasks." 0
}

# sn_adjudicate <checkpoint fields> — branch on adjudication_kind (absent ⇒ requires_gap), never on the
# reason prose; the options are the gate catalog's (`lane-policy.sh catalog`), and NO option is ever
# picked here: an interactive run asks, a run that cannot ask records the checkpoint and parks
sn_adjudicate() {
  local f="$1" kind gate ev
  kind="$(printf '%s' "$f" | "$JQ" -r '.adjudication_kind // "requires_gap"')"
  case "$kind" in
    requires_gap)
      gate=SUP-ADJ-GAP
      ev="$(printf '%s' "$f" | "$JQ" -r '[(.missing_outputs // [])[] | objects | "\(.item) (producer \(.producing_subtask), check \(.check_run))"] | join("; ")')" ;;
    lane_collision)
      gate=SUP-ADJ-LANE
      ev="$(printf '%s' "$f" | "$JQ" -r '[(.colliding_lanes // [])[] | objects | "\(.path) (lane owner \(.owning_subtask), writer \(.this_subtask))"] | join("; ")')" ;;
    *) sn_refuse "--result: adjudication_kind must be requires_gap or lane_collision (got '$kind') — nothing written"; return 1 ;;
  esac
  [ -n "$ev" ] || { sn_refuse "--result: adjudication_required: true with no evidence array (missing_outputs / colliding_lanes) — nothing written"; return 1; }
  st_set adj_kind "$kind"; st_set adj_evidence "$ev"
  if [ "$(fl non_interactive)" = true ]; then sn_adj_cant_ask execute-result; return; fi
  sn_ask execute-result "$gate" adjudication_required_non_interactive \
    "The Execute Manager paused EXECUTE for an adjudication ($kind): $ev. Reason: $(printf '%s' "$f" | "$JQ" -r '.reason'). Each option has different irreversible consequences (agents/supervisor.md §\"Adjudication Handling\") — which one?" execute-answer
}
# the Can't-ask branch: pick NO option — checkpoint via Context-Keeper, then the failed park; the brief
# STAYS in in-progress/ (a resumable checkpoint — the failed/ move is Option C's)
sn_adj_cant_ask() {
  local k="$(st adj_kind)" g opts
  if [ "$k" = lane_collision ]; then g=SUP-ADJ-LANE; else g=SUP-ADJ-GAP; fi
  opts="$(bash "$HERE/lane-policy.sh" catalog 2>/dev/null | awk -F'\t' -v c="$g" '$1 == c { print $3; exit }' | sed 's/|/; /g')"
  sn_ck_stop "$1" execute-stop "$(sn_ops "$(sn_op_decision EXECUTE "adjudication_required_non_interactive: $k" \
      "no option picked — $(st adj_evidence); options: $opts")")" failed "adjudication_required_non_interactive: $k" \
    "An adjudication ($k) cannot be asked (--non-interactive, a subagent, or a cant_ask answer); no option was picked. Evidence: $(st adj_evidence). Options for a human to resume from: $opts. The job brief stays in in-progress/." 0
}

# execute-answer — the adjudication answer: C exits (job → failed/, the kind's Option-C reason);
# A / B / D are recorded, then a fresh Execute Manager applies them (execute-resume)
sn_execute_answer() {
  local a k reason
  sn_answer "$ANSWER" || return 1
  a="$SN_ANS"; k="$(st adj_kind)"
  case "$a" in
    cant_ask) sn_adj_cant_ask execute-answer ;;
    "C: "*)
      if [ "$k" = lane_collision ]; then reason=lane_collision; else reason=inter_subtask_gap; fi
      sn_ck_stop execute-answer execute-stop "$(sn_ops "$(sn_op_decision EXECUTE "adjudication $k: $a" "$(st adj_evidence)")")" \
        failed "$reason" "Option C: the job is failed with reason $reason and the brief moved to failed/. Rerun /launch-pad to fix the brief." 1 ;;
    "A: "*|"B: "*|"D: "*)
      st_set adj_choice "$a"
      sn_ck execute-answer execute-resume "$(sn_ops "$(sn_op_decision EXECUTE "adjudication $k: $a" "$(st adj_evidence)")")" ;;
    *) sn_fail "internal: unrouted adjudication label '$a'"; return 1 ;;
  esac
}

# execute-resume — the fresh Execute Manager that applies the chosen option (A / B / D)
sn_execute_resume() {
  local a="$(st adj_choice)"
  sn_spawn execute-resume execute-manager execute-result "$("$JQ" -cn --arg b "$(st job)" --argjson w "$(st max_workers)" \
    --arg base "$(st base_branch)" --arg k "$(st adj_kind)" --arg c "$a" --arg ev "$(st adj_evidence)" \
    --argjson ck "$(st exec_checkpoint)" --arg ch "$(fl cheap)" '{agent: "loomwright:execute-manager", path: "parallel", resume: true,
      brief: $b, brief_note: "read only the sections you need", max_workers: $w, base_branch: $base,
      adjudication: {kind: $k, choice: $c, evidence: $ev},
      apply: "agents/supervisor.md §\u0022Adjudication Handling\u0022 step 4, \($k) \($c | split(":")[0]): apply it (a brief or plan edit is yours, recorded via Context-Keeper record_decision), then this Execute Manager resumes",
      completed_so_far: $ck.completed_so_far, remaining: $ck.remaining, resume_context: $ck.resume_context}
    + (if $ch == "true" then {cost_profile: "cheap"} else {} end)
    + {then: "--result \u007b\u0022result\u0022: \u0022<the EXECUTE_RESULT or EXECUTE_CHECKPOINT block, verbatim>\u0022\u007d; when the Execute Manager returned neither block (a crash), --result \u007b\u0022crashed\u0022: true, \u0022error\u0022: \u0022<what the Task call returned, one line>\u0022\u007d"}')"
}

# an Execute Manager crash: checkpoint, report the worktree state, stop with the resume command
sn_execute_crash() {
  local wts
  wts="$(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p' | while IFS= read -r p; do
      [ "$(sn_physical "$p")" = "$ROOT" ] || printf '%s\n' "$p"; done | "$JQ" -R -s -c 'split("\n") | map(select(length > 0))')"
  st_setj crash_worktrees "${wts:-[]}"
  sn_ck_stop execute-result execute-stop "$(sn_ops "$(sn_op_error EXECUTE "execute-manager crash: $1" "checkpoint — worktrees left in place")")" \
    checkpoint "" "The Execute Manager crashed ($1). Worktrees left in place: $(printf '%s' "${wts:-[]}" | "$JQ" -r 'if length == 0 then "none" else join(", ") end'). Resume with /supervisor --continue task: $(st task_id)." 0
}

# the Single-Agent / Sequential worker's report (the per-subtask gates ran in the model, as the spawn said)
sn_execute_result_inline() {
  local r="$ANSWER" i id want g s ag cur
  sn_check_strings "$r" subtask agent_id status gates reason || return 1
  i="$(st seq_index)"; [ -n "$i" ] || i=0
  want="$(printf '%s' "$(st subtasks)" | "$JQ" -r --argjson i "$i" '.[$i] // empty')"
  id="$(rj "$r" subtask)"; g="$(rj "$r" gates)"; s="$(rj "$r" status)"; ag="$(rj "$r" agent_id)"
  [ "$id" = "$want" ] || { sn_refuse "--result: this answer is for subtask '$want' (got '$id') — nothing written"; return 1; }
  [[ "$ag" =~ ^[A-Za-z0-9_-]{1,128}$ ]] || { sn_refuse "--result: agent_id is the worker's Task-returned id — nothing written"; return 1; }
  case "$g" in
    passed)
      [ "$s" = completed ] || { sn_refuse "--result: gates passed needs status completed (a partial / failed worker is retried or paused per the per-subtask gates — report gates paused) — nothing written"; return 1; }
      cur="$(st inline_results)"; [ -n "$cur" ] || cur='[]'
      st_setj inline_results "$(printf '%s' "$cur" | "$JQ" -c --arg id "$id" --arg a "$ag" --arg s "$s" '. + [{subtask: $id, agent_id: $a, status: $s}]')"
      if [ $((i + 1)) -lt "$(printf '%s' "$(st subtasks)" | "$JQ" 'length')" ]; then st_setj seq_index $((i + 1)); NEXT=execute
      else NEXT=finalize; fi ;;
    paused)
      [ -n "$(rj "$r" reason)" ] || { sn_refuse "--result: a paused gate names its reason — nothing written"; return 1; }
      sn_park execute-result checkpoint "" \
        "Subtask $id paused at its per-subtask gate: $(rj "$r" reason). Nothing merged. Resume with /supervisor --continue task: $(st task_id)." ;;
    *) sn_refuse "--result: gates must be passed or paused (got '$g') — nothing written"; return 1 ;;
  esac
}

# ------------------------------------------------------------------------------------------------
# Phase 4 FINALIZE (skills/async-orchestration/SKILL.md Part 2 — the driver runs the gate points and
# the self-verify; the merges, commits and the publish are the model's, printed as spawns)
# ------------------------------------------------------------------------------------------------

# finalize — pre-merge safety gate points 1–4 (ALL must pass before any merge). A failed point ⇒ the
# reason is logged and the job moves to failed/; a missing worktree / branch ⇒ checkpoint with resume
sn_finalize() {
  local er br base bad miss orph noch p wt b reg ers rp line st_
  br="$(st branch)"; base="$(st base_branch)"
  if [ "$(st path)" = parallel ]; then
    er="$(st exec_result)"
    # point 1 — every WORKER_RESULT in the merge set completed: each completed entry says completed and
    # every merge_order branch belongs to one
    bad="$(printf '%s' "$er" | "$JQ" -r '([.completed[] | select(.status != "completed") | "\(.task_id) status \(.status)"]
      + [.merge_order[] as $b | select(([.completed[].branch] | index($b)) == null) | "\($b) is not a completed subtask\u0027s branch"]) | join("; ")')"
    [ -z "$bad" ] || { sn_premerge_fail 1 "all WORKER_RESULT statuses completed" "$bad"; return; }
    # point 2 — the per-subtask gate decision is PASS (review_decision reports the deterministic
    # outputs_verified gate since no per-subtask reviewer runs)
    bad="$(printf '%s' "$er" | "$JQ" -r '[.completed[] | select(.review_decision != "PASS") | "\(.task_id) review_decision \(.review_decision)"] | join("; ")')"
    [ -z "$bad" ] || { sn_premerge_fail 2 "all per-subtask gate decisions PASS" "$bad"; return; }
    # point 3 — no orphaned worktrees; every worktree / branch the result names exists and has changes.
    # Paths compare physically (macOS /var → /private/var); membership is a newline-list match, never a
    # `| grep -q` (under pipefail its early exit SIGPIPEs the writer and reads as a miss)
    reg=""; ers=""; miss=""; orph=""; noch=""
    while IFS="$SN_TAB" read -r wt b; do
      [ -n "$wt" ] || continue
      rp="$(sn_physical "$wt")"; [ -n "$rp" ] && reg="$reg$rp$SN_TAB$b$SN_NL"
    done <<EOF
$(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{p = substr($0, 10)} /^branch refs\/heads\//{print p "\t" substr($0, 19)}')
EOF
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      p="$(printf '%s' "$line" | "$JQ" -r '.path // empty')"; st_="$(printf '%s' "$line" | "$JQ" -r '.status // empty')"
      rp="$(sn_physical "$p")"; [ -n "$rp" ] && ers="$ers$rp$SN_NL"
      [ "$st_" = cleaned ] && continue
      if [ -z "$rp" ] || ! sn_in_lines "$rp" "$(printf '%s' "$reg" | cut -f1)"; then miss="$miss${miss:+; }worktree $p"; fi
    done <<EOF
$(printf '%s' "$er" | "$JQ" -c '.worktrees[]')
EOF
    while IFS= read -r b; do
      [ -n "$b" ] || continue
      git rev-parse --verify --quiet "refs/heads/$b" >/dev/null || { miss="$miss${miss:+; }branch $b"; continue; }
      wt="$(printf '%s' "$er" | "$JQ" -r --arg b "$b" '[.worktrees[] | select(.branch == $b) | .path][0] // empty')"
      if [ -z "$wt" ] || { [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] && [ "$(git rev-list --count "$br..$b" 2>/dev/null || echo 0)" = 0 ]; }; then
        noch="$noch${noch:+; }$b"
      fi
    done <<EOF
$(printf '%s' "$er" | "$JQ" -r '.merge_order[]')
EOF
    while IFS="$SN_TAB" read -r rp b; do
      [ -n "$rp" ] && [ "$rp" != "$ROOT" ] || continue
      printf '%s' "$er" | "$JQ" -e --arg b "$b" '(.merge_order + .branches + [.worktrees[].branch] + [.completed[].branch]) | index($b) != null' >/dev/null || continue
      sn_in_lines "$rp" "$ers" || orph="$orph${orph:+; }$rp ($b)"
    done <<EOF
$reg
EOF
    [ -z "$orph" ] || { sn_premerge_fail 3 "no orphaned worktrees" "not accounted for in EXECUTE_RESULT: $orph"; return; }
    if [ -n "$miss$noch" ]; then
      sn_ck_stop finalize finalize-stop "$(sn_ops "$(sn_op_error FINALIZE "pre-merge verification: ${miss:+missing $miss}${miss:+${noch:+; }}${noch:+no changes on $noch}" \
          "checkpoint — nothing merged; resume with /supervisor --continue")")" checkpoint "" \
        "Pre-merge verification failed (${miss:+missing $miss}${miss:+${noch:+; }}${noch:+no changes on $noch}). Nothing merged. Report it, then resume with /supervisor --continue task: $(st task_id)." 0
      return 0
    fi
  else
    # the inline paths: every subtask's gates passed with status completed (points 2 and 3 are vacuous:
    # no per-subtask reviewer, no worktrees)
    bad="$(printf '%s' "$(st inline_results)" | "$JQ" -r '[(if type == "array" then .[] else empty end) | select(.status != "completed") | "\(.subtask) status \(.status)"] | join("; ")' 2>/dev/null)"
    [ -z "$bad" ] || { sn_premerge_fail 1 "all WORKER_RESULT statuses completed" "$bad"; return; }
  fi
  # point 4 — the feature branch exists and holds the base tip (it is at or ahead of base)
  if ! git rev-parse --verify --quiet "refs/heads/$br" >/dev/null; then
    sn_premerge_fail 4 "feature branch exists and is ahead of base" "branch $br does not exist"; return
  fi
  if ! git merge-base --is-ancestor "$base" "$br" 2>/dev/null; then
    sn_premerge_fail 4 "feature branch exists and is ahead of base" "$br does not contain the $base tip"; return
  fi
  st_set premerge passed
  NEXT=finalize-children
}
# sn_premerge_fail <point> <name> <detail> — log the reason, abort the merge, the job to failed/
sn_premerge_fail() {
  local e="pre-merge safety gate point $1 ($2) failed: $3"
  sn_ck_stop finalize finalize-stop "$(sn_ops "$(sn_op_error FINALIZE "$e" "merge aborted; job moved to failed/")")" \
    failed "$e" "The pre-merge safety gate failed at point $1 ($2): $3. Nothing was merged; the job brief is in failed/." 1
}

# finalize-children — point 5 before any merge: check-children-settled.sh --all (the ONE join), plus
# one --expect-id per worker id this driver was handed (write-marker re-runs it with state.md's
# `## Worker Results` ids before the publish)
sn_finalize_children() {
  local res s ex=() a
  if [ "$(fl skip_children_check)" = true ]; then
    st_set children_check skipped
    sn_ck finalize-children finalize-merge "$(sn_ops "$(sn_op_decision FINALIZE user_skipped_children_check "--skip-children-check flag")")"
    return 0
  fi
  while IFS= read -r a; do [ -n "$a" ] && ex[${#ex[@]}]=--expect-id && ex[${#ex[@]}]="$a"; done <<EOF
$(printf '%s' "$(st inline_results)" | "$JQ" -r 'if type == "array" then .[].agent_id else empty end' 2>/dev/null)
EOF
  res="$(bash "$HERE/check-children-settled.sh" --log ".supervisor/logs/$SID.jsonl" --all ${ex[@]+"${ex[@]}"} 2>/dev/null)"
  s="$(printf '%s' "$res" | "$JQ" -r '.status // empty' 2>/dev/null)"
  case "$s" in
    settled|no_identity_rows) st_set children_check "$s"; NEXT=finalize-merge ;;
    *) [ -n "$res" ] || res='{}'; st_set children_from finalize-children; sn_children_unsettled finalize-children "$res" ;;
  esac
}
# sn_children_unsettled <step> <check json> — unsettled / unverifiable: the SUP-CHILDREN ask, or under
# the Can't-ask rule the fail-closed `children_unsettled: <ids>` park (job → failed/)
sn_children_unsettled() {
  local ids extra
  ids="$(printf '%s' "$2" | "$JQ" -r '(.unsettled_agent_ids // []) | join(",")' 2>/dev/null)"
  [ -n "$ids" ] || ids="none named (check status $(printf '%s' "$2" | "$JQ" -r '.status // "unverifiable"' 2>/dev/null)$(printf '%s' "$2" | "$JQ" -r 'if .reason then ": " + .reason else "" end' 2>/dev/null))"
  extra="$(printf '%s' "$2" | "$JQ" -r '[if ((.ended_without_result_ids // []) | length) > 0 then "ended without a result: " + (.ended_without_result_ids | join(",")) else empty end,
      if ((.rejected_stop_ids // []) | length) > 0 then "rejected stops: " + (.rejected_stop_ids | join(",")) else empty end] | join("; ")' 2>/dev/null)"
  st_set children_ids "$ids"; st_set children_extra "$extra"
  if [ "$(fl non_interactive)" = true ]; then sn_children_fail_closed "$1"; return; fi
  sn_ask "$1" SUP-CHILDREN children_unsettled \
    "FINALIZE point 5: not every spawned child settled — unsettled: $ids${extra:+ ($extra)}. Proceed anyway (recorded as user_skipped_children_check), investigate (checkpoint; send an unsettled agent a message to resume it), or abort?" finalize-children-answer
}
sn_children_fail_closed() {
  local e="children_unsettled: $(st children_ids)"
  sn_ck_stop "$1" finalize-stop "$(sn_ops "$(sn_op_error FINALIZE "$e${2:+ ($2)}" "nothing published; job moved to failed/")")" failed "$e" \
    "FINALIZE point 5 stopped the run (${2:-it cannot be asked: --non-interactive, a subagent, or a cant_ask answer — fail closed}): unsettled $(st children_ids)$( [ -n "$(st children_extra)" ] && printf ' (%s)' "$(st children_extra)"). Nothing was published; the job brief is in failed/." 1
}
# finalize-children-answer — the SUP-CHILDREN answer
sn_finalize_children_answer() {
  local from
  sn_answer "$ANSWER" || return 1
  from="$(st children_from)"
  case "$SN_ANS" in
    cant_ask) sn_children_fail_closed finalize-children-answer ;;
    "proceed anyway")
      st_set children_check skipped
      if [ "$from" = finalize-marker ]; then st_set children_next finalize-marker; else st_set children_next finalize-merge; fi
      sn_ck finalize-children-answer "$(st children_next)" "$(sn_ops "$(sn_op_decision FINALIZE user_skipped_children_check \
        "SUP-CHILDREN proceed anyway — unsettled: $(st children_ids)")")" ;;
    investigate)
      sn_park finalize-children-answer checkpoint "" \
        "Investigate the unsettled children ($(st children_ids)) — send an unsettled agent a message to resume it rather than re-running cold. Nothing was published$( [ "$from" = finalize-marker ] && printf ' (the merges are on %s)' "$(st branch)"). Resume with /supervisor --continue task: $(st task_id)." ;;
    abort) sn_children_fail_closed finalize-children-answer "the owner chose abort" ;;
    *) sn_fail "internal: unrouted SUP-CHILDREN label '$SN_ANS'"; return 1 ;;
  esac
}

# finalize-merge — steps 2–5.5 are the model's (commit the worktrees, merge in merge_order — a conflict
# is a STOP, never force-resolved — salvage then remove each worktree, the commits, the release re-fold)
sn_finalize_merge() {
  local p="$(st path)" proc
  if [ "$p" = parallel ]; then
    proc="skills/async-orchestration/SKILL.md Part 2 steps 2-5.5: commit each worktree in merge_order, check out the feature branch and merge each branch with --no-ff in merge_order (a conflict is a STOP — never force-resolve; report it), salvage then remove each worktree (worktree-salvage.sh as its own statement), create the commits per skills/commit/SKILL.md, then run release-refold.sh. Do not push."
  else
    proc="skills/async-orchestration/SKILL.md Part 2 steps 5-5.5 (no worktrees on this path): create the commits on the feature branch per skills/commit/SKILL.md, then run release-refold.sh. Do not push."
  fi
  sn_spawn finalize-merge finalize-merge finalize-merged "$("$JQ" -cn --arg p "$p" --arg br "$(st branch)" --arg base "$(st base_branch)" \
    --arg proc "$proc" --argjson er "$(st exec_result | grep . || echo null)" '{path: $p, feature_branch: $br, base_branch: $base}
    + (if $er == null then {} else {merge_order: $er.merge_order, worktrees: [$er.worktrees[] | {task_id, path, branch, status}]} end)
    + {procedure: $proc,
       then: "--result \u007b\u0022merged\u0022: [\u0022<branch>\u0022, …], \u0022conflict\u0022: null, \u0022refold\u0022: \u0022ok\u0022\u007d; at a merge conflict \u0022conflict\u0022: \u007b\u0022branch\u0022: \u0022<branch>\u0022, \u0022files\u0022: [\u0022<path>\u0022, …]\u007d; when release-refold.sh exits non-zero \u0022refold\u0022: \u0022refused\u0022 with \u0022refold_reason\u0022: \u0022<its printed reason>\u0022"}')"
}

# finalize-merged — the merge report: a conflict STOPs (checkpoint with the merged / not-merged lists),
# a refused re-fold aborts FINALIZE before the push (release_refold_refused, job → failed/)
sn_finalize_merged() {
  local r="$ANSWER" mo merged left cb cf rf
  printf '%s' "$r" | "$JQ" -e '((.merged // []) | type == "array" and all(.[]; type == "string"))
      and (.conflict == null or ((.conflict | type) == "object" and (.conflict.branch | type) == "string"
        and (.conflict.files | type) == "array" and all(.conflict.files[]; type == "string")))' >/dev/null 2>&1 \
    || { sn_refuse "--result: {\"merged\": [<branch>…], \"conflict\": null|{\"branch\", \"files\": […]}, \"refold\": \"ok\"|\"refused\"} — nothing written"; return 1; }
  sn_check_strings "$r" refold refold_reason || return 1
  merged="$(printf '%s' "$r" | "$JQ" -c '.merged // []')"
  mo="$(printf '%s' "$(st exec_result)" | "$JQ" -c '.merge_order' 2>/dev/null)"; [ -n "$mo" ] || mo='[]'
  if [ "$(printf '%s' "$r" | "$JQ" -r '.conflict == null')" = false ]; then
    cb="$(printf '%s' "$r" | "$JQ" -r '.conflict.branch')"; cf="$(printf '%s' "$r" | "$JQ" -r '.conflict.files | join(", ")')"
    left="$("$JQ" -cn --argjson m "$mo" --argjson d "$merged" '$m - $d' | "$JQ" -r 'join(", ")')"
    sn_ck_stop finalize-merged finalize-stop "$(sn_ops "$(sn_op_error FINALIZE "merge conflict: $cb: $cf" \
        "STOP — never force-resolved; merged: $(printf '%s' "$merged" | "$JQ" -r 'join(", ")'); not merged: $left")")" checkpoint "" \
      "Merge conflict merging $cb ($cf) — STOP, never force-resolved. Already merged: $(printf '%s' "$merged" | "$JQ" -r 'if length == 0 then "none" else join(", ") end'); not yet merged: ${left:-none}. Resolve it, then resume with /supervisor --continue task: $(st task_id)." 0
    return 0
  fi
  rf="$(rj "$r" refold)"
  case "$rf" in
    refused)
      sn_ck_stop finalize-merged finalize-stop "$(sn_ops "$(sn_op_error FINALIZE "release_refold_refused: $(rj "$r" refold_reason)" "no push, no PR; job moved to failed/")")" \
        failed release_refold_refused "release-refold.sh refused ($(rj "$r" refold_reason)): no push, no PR; the job brief is in failed/. Release the run lock on this abort exit." 1
      return 0 ;;
    ok) ;;
    *) sn_refuse "--result: refold must be ok or refused (got '$rf') — nothing written"; return 1 ;;
  esac
  if [ "$(st path)" = parallel ] && [ "$merged" != "$mo" ]; then
    sn_refuse "--result: merged must be every merge_order branch in order ($mo) unless a conflict stopped it — nothing written"; return 1
  fi
  NEXT=finalize-marker
}

# finalize-marker — FINALIZE point 5 by mechanism: guard-finalize-publish.sh write-marker (the ONLY
# writer of the finalize-gate marker; it re-runs the children check with state.md's `## Worker
# Results` ids and binds the marker to HEAD). The publish instruction is printed only after it exits 0
sn_finalize_marker() {
  local cur out rc reason args=()
  cur="$(git symbolic-ref --short -q HEAD 2>/dev/null)"
  [ "$cur" = "$(st branch)" ] || { sn_fail "the checkout is on '${cur:-a detached HEAD}', not the feature branch $(st branch) — check it out, then call again with no --result"; return 1; }
  [ "$(st children_check)" = skipped ] && args=(--skip-children-check)
  out="$(CLAUDE_PROJECT_DIR="$ROOT" bash "$HERE/guard-finalize-publish.sh" write-marker ${args[@]+"${args[@]}"} </dev/null 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    st_set marker_children_check "$(printf '%s' "$out" | "$JQ" -r '.children_check // empty' 2>/dev/null)"
    NEXT=publish; return 0
  fi
  reason="$(printf '%s' "$out" | "$JQ" -r '.reason // empty' 2>/dev/null)"
  case "$reason" in
    children_*)
      st_set children_from finalize-marker
      sn_children_unsettled finalize-marker "$(printf '%s' "$out" | "$JQ" -c '.children // {}' 2>/dev/null || echo '{}')" ;;
    *)
      sn_park finalize-marker checkpoint "" \
        "guard-finalize-publish.sh write-marker refused (${reason:-exit $rc}): no finalize-gate marker, nothing published. Fix the cause (worker_results_unparsed: check the workers, then --skip-children-check is the escape), then resume with /supervisor --continue task: $(st task_id)." ;;
  esac
}

# publish — step 6, printed only after write-marker exited 0 (this call or an earlier one)
sn_publish() {
  sn_spawn publish finalize-publish pr-verify "$("$JQ" -cn --arg br "$(st branch)" --arg base "$(st base_branch)" \
    --arg t "$(st task_id): $(st title)" --arg cc "$(st marker_children_check)" '{feature_branch: $br, base_branch: $base,
      commands: ["git push -u origin \($br)", "gh pr create --base \($base) --title \($t | @sh) --body-file <the PR body>"],
      pr_body: "skills/async-orchestration/SKILL.md Part 2 PR Body Template (its ## Evidence and ## Not verified sections only when they apply)",
      children_check: $cc,
      note: "the finalize-gate marker names the current HEAD: commit nothing before the push (a moved HEAD is denied by guard-finalize-publish.sh; re-run its write-marker first)",
      then: "--result \u007b\u0022pr_url\u0022: \u0022<the URL gh pr create printed>\u0022\u007d; when the push or gh pr create failed, --result \u007b\u0022publish_failed\u0022: \u0022<one line>\u0022\u007d"}')"
}

# pr-verify — step 6.5, the PR-base self-verify: gh pr view --json baseRefName; a first gh failure ⇒
# ONE retry after SUPERVISOR_NEXT_STEP_RETRY_SECONDS; a second ⇒ the SUP-GH-RETRY ask, or under the
# Can't-ask rule the base_mismatch_detected flag (gh_unavailable_non_interactive)
sn_pr_verify() {
  local r="$ANSWER" u
  sn_check_strings "$r" pr_url publish_failed || return 1
  if [ -n "$(rj "$r" publish_failed)" ]; then
    sn_park pr-verify checkpoint "" \
      "The publish failed ($(rj "$r" publish_failed)): no PR to verify. Fix it (re-run guard-finalize-publish.sh write-marker if HEAD moved), then resume with /supervisor --continue task: $(st task_id)."
    return 0
  fi
  u="$(rj "$r" pr_url)"
  [[ "$u" =~ ^https?://[^[:space:]]+/pull/[0-9]+$ ]] || { sn_refuse "--result: pr_url must be the PR URL gh pr create printed (got '$u') — nothing written"; return 1; }
  st_set pr_url "$u"
  if sn_pr_base_read; then sn_pr_compare pr-verify; return; fi
  sleep "$(sn_retry_seconds)"
  if sn_pr_base_read; then sn_pr_compare pr-verify; return; fi
  if [ "$(fl non_interactive)" = true ]; then sn_pr_flag pr-verify "" gh_unavailable_non_interactive; return; fi
  sn_ask pr-verify SUP-GH-RETRY gh_unavailable_non_interactive \
    "gh pr view failed twice reading the base of $u (expected $(st base_branch)). Retry once more, skip the verification once (recorded as user_skipped_base_verify), or abort (base_mismatch_detected → the Phase 4.5 cleanup)?" pr-verify-answer
}
sn_retry_seconds() { local s="${SUPERVISOR_NEXT_STEP_RETRY_SECONDS:-5}"; [[ "$s" =~ ^[0-9]{1,3}$ ]] || s=5; printf '%s' "$s"; }
# sn_pr_base_read — PR_BASE = the PR's baseRefName; non-zero on a gh failure or an empty answer
PR_BASE=""
sn_pr_base_read() {
  local rc
  PR_BASE="$(sn_gh pr view "$(st pr_url)" --json baseRefName --jq .baseRefName)"; rc=$?
  PR_BASE="$(printf '%s' "$PR_BASE" | head -n 1 | tr -d '\r')"
  [ "$rc" -eq 0 ] && [ -n "$PR_BASE" ]
}
sn_pr_compare() {
  if [ "$PR_BASE" = "$(st base_branch)" ]; then st_set base_verify verified; NEXT=handover
  else sn_pr_flag "$1" "$PR_BASE" phase4_self_verify; fi
}
# sn_pr_flag <step> <actual or ""> <reason> — set base_mismatch_detected (once) as a Context-Keeper op;
# its confirmation goes to the hand-over, which routes to the Phase 4.5 base-mismatch cleanup
sn_pr_flag() {
  st_set base_verify "$3"
  sn_ck "$1" handover "$(sn_ops "$(sn_op_set base_mismatch_detected "$("$JQ" -cn --arg e "$(st base_branch)" --arg a "$2" \
    --arg u "$(st pr_url)" --arg t "$(sn_ts)" --arg r "$3" '{expected: $e, actual: (if $a == "" then null else $a end),
      pr_url: $u, detected_at: $t, reason: $r}')")")"
}
# pr-verify-answer — the SUP-GH-RETRY answer
sn_pr_verify_answer() {
  sn_answer "$ANSWER" || return 1
  case "$SN_ANS" in
    cant_ask) sn_pr_flag pr-verify-answer "" gh_unavailable_non_interactive ;;
    retry)
      if sn_pr_base_read; then sn_pr_compare pr-verify-answer
      else sn_pr_flag pr-verify-answer "" user_aborted_gh_retry; fi ;;
    skip-verify-once)
      st_set base_verify skipped
      sn_ck pr-verify-answer handover "$(sn_ops "$(sn_op_decision FINALIZE user_skipped_base_verify "gh repeatedly unavailable")")" ;;
    abort) sn_pr_flag pr-verify-answer "" user_aborted_gh_retry ;;
    *) sn_fail "internal: unrouted SUP-GH-RETRY label '$SN_ANS'"; return 1 ;;
  esac
}

# handover — FINALIZE is done: the hand-over to Phase 4.5 (the task is NOT yet completed and the job is
# NOT yet moved — Phase 4.5's completion tail does both). A set base_mismatch_detected flag routes to
# its base-mismatch cleanup, the single SUPERVISOR_RESULT emission point of that path
sn_handover() {
  local bv mm
  bv="$(st base_verify)"
  case "$bv" in verified|skipped) mm=false ;; *) mm=true ;; esac
  sn_emit done handover "$("$JQ" -cn --arg u "$(st pr_url)" --arg bv "$bv" --argjson mm "$mm" --arg cc "$(st marker_children_check)" \
    --arg ps "$(st preflight_sync)" --arg pw "$(st preflight_warning)" --argjson esc "$(st escalation | grep . || echo null)" \
    --arg base "$(st base_branch)" '{next: "phase-4.5", pr_url: $u, base_verify: $bv, base_mismatch_detected: $mm,
      children_check: $cc, preflight_sync: (if $ps == "" then null else $ps end)}
    + (if $pw != "" then {preflight_warning: $pw} else {} end)
    + (if $esc != null then {escalation: {subtasks_failed: $esc}} else {} end)
    + {message: ((if $mm then "base_mismatch_detected is set (\($bv)): run Phase 4.5 base-mismatch cleanup (skills/self-heal-advisory/SKILL.md Part 2), the single SUPERVISOR_RESULT emission point of this path"
        else "FINALIZE complete: \($u) against \($base) (base \($bv)). Run Phase 4.5 SELF_HEAL; its completion tail marks the task completed and moves the job" end)
        + (if $esc != null then "; report the failed subtasks (\([$esc[].task_id] | join(", "))) as an escalation in this run" else "" end)
        + (if $ps == "unverified" then "; preflight_sync is unverified — carry the warning" else "" end))}')"
}

# ================================================================================================
# dispatch
# ================================================================================================
sn_dispatch() {
  case "$1" in
    init) sn_init ;;
    acquire) sn_acquire ;;
    preflight) sn_preflight ;;
    preflight-route) sn_preflight_route ;;
    preflight-answer) sn_preflight_answer ;;
    preflight-stop) sn_preflight_stop ;;
    plan) sn_plan ;;
    plan-result) sn_plan_result ;;
    execute) sn_execute ;;
    execute-result) sn_execute_result ;;
    execute-answer) sn_execute_answer ;;
    execute-resume) sn_execute_resume ;;
    execute-stop) sn_stop execute-stop ;;
    finalize) sn_finalize ;;
    finalize-children) sn_finalize_children ;;
    finalize-children-answer) sn_finalize_children_answer ;;
    finalize-merge) sn_finalize_merge ;;
    finalize-merged) sn_finalize_merged ;;
    finalize-marker) sn_finalize_marker ;;
    finalize-stop) sn_stop finalize-stop ;;
    publish) sn_publish ;;
    pr-verify) sn_pr_verify ;;
    pr-verify-answer) sn_pr_verify_answer ;;
    handover) sn_handover ;;
    *) sn_err "no step '$1' (nothing routes this answer yet)"; SN_RC=2; return 1 ;;
  esac
}

NEXT=""; ANSWER=""
pending="$(st pending_text)"
pending_do="$(printf '%s' "$pending" | "$JQ" -r '.do // empty' 2>/dev/null)"
if [ -n "${SUPERVISOR_NEXT_STEP_FROM:-}" ]; then
  NEXT="$SUPERVISOR_NEXT_STEP_FROM"; ANSWER="$RESULT"
elif [ -n "$JOB_ARG" ]; then
  # the same job's spawn / ask still pending ⇒ re-print it (idempotent); anything else is a fresh run
  if [ -n "$pending" ] && [ "$(sn_job_base)" = "${JOB_ARG##*/}" ]; then
    case "$pending_do" in spawn|ask) printf '%s\n' "$pending"; exit 0 ;; esac
  fi
  [ -z "$pending" ] || case "$pending_do" in spawn|ask)
    sn_err "the sidecar's pending $pending_do belongs to $(sn_job_base) — discarded, $JOB_ARG starts a fresh run" ;; esac
  SN_STATE="$("$JQ" -cn --argjson ni "$F_NONINT" --argjson sa "$F_SUBAGENT" --argjson ch "$F_CHEAP" --arg mt "$F_MAXTOK" \
    --arg bb "$F_BASE" --arg br "$F_BRANCH" --argjson pf "$F_SKIP_PF" --argjson cc "$F_SKIP_CH" --argjson sq "$F_SEQ" \
    --arg mw "$F_MAXW" --arg root "$ROOT" '{flags: ({non_interactive: ($ni == 1), subagent: ($sa == 1), cheap: ($ch == 1),
      skip_preflight_sync: ($pf == 1), skip_children_check: ($cc == 1), sequential: ($sq == 1), root: $root}
      + (if $mt != "" then {max_tokens: ($mt | tonumber)} else {} end)
      + (if $bb != "" then {base_branch: $bb} else {} end)
      + (if $br != "" then {branch: $br} else {} end)
      + (if $mw != "" then {max_workers: ($mw | tonumber)} else {} end))}')"
  NEXT=init
elif [ "$have_result" = 0 ]; then
  if [ -n "$pending" ]; then printf '%s\n' "$pending"; exit 0; fi
  NEXT="$(st failed)"   # a step that failed (surfaced) is retried
  [ -n "$NEXT" ] || sn_die2 "nothing_pending — start a run with --job <brief>"
else
  case "$pending_do" in
    spawn|ask) NEXT="$(st answer_arm)"; ANSWER="$RESULT" ;;
    park|done) sn_die2 "run_ended — the run stopped at '$(printf '%s' "$pending" | "$JQ" -r '.step')' ($pending_do); start a new job with --job" ;;
    *) sn_die2 "nothing_pending — no instruction awaits a --result (start a run with --job <brief>)" ;;
  esac
  [ -n "$NEXT" ] || sn_die2 "nothing_pending — the pending $pending_do names no answer step"
  # a --result answering the Context-Keeper spawn is its confirmation, checked before any step runs
  if [ "$(printf '%s' "$pending" | "$JQ" -r '.what // empty')" = context-keeper ]; then
    [ "$(rj "$RESULT" confirmed)" = true ] || sn_die2 "--result: the Context-Keeper spawn is answered by {\"confirmed\": true} — nothing written"
    ANSWER=""
  fi
fi

SN_SAVED="$SN_STATE"
st_del pending_text; st_del failed; st_del answer_arm

first_arm=1
while [ -n "$NEXT" ]; do
  arm="$NEXT"; NEXT=""
  st_set last_arm "$arm"
  if ! sn_dispatch "$arm"; then
    # exit 2 = refused before this call's first write: the sidecar (and its pending instruction) stays as
    # it was. A later arm refusing ran after earlier arms of this call wrote — a surfaced failure
    if [ "$first_arm" = 1 ] && [ "$SN_RC" = 2 ]; then exit 2; fi
    SN_STATE="$(printf '%s' "$SN_STATE" | "$JQ" -c --arg a "$arm" '.failed = $a | del(.pending_text)')"
    st_save
    # a surfaced failure of a dispatch arm — any refusal past this call's first write included; the
    # code is the arm (a step name from sn_dispatch's case list), never the message text
    case "$arm" in ''|*[!a-z-]*) ;; *) sn_event fail "$arm-failed" ;; esac
    [ "$SN_RC" = 2 ] && SN_RC=1
    [ "$SN_RC" -ne 0 ] || SN_RC=1
    exit "$SN_RC"
  fi
  first_arm=0
  [ -n "$SN_EMIT" ] && break
done

if [ -n "$SN_EMIT" ]; then
  st_set pending_text "$SN_EMIT"
  st_save || exit 1
  printf '%s\n' "$SN_EMIT"
  # the run reached handover (FINALIZE done) ⇒ close this checkout's open supervisor-next-step threads
  [ "$arm" != handover ] || sn_event pass ok
  exit 0
fi
SN_STATE="$SN_SAVED"
sn_err "internal: step '$arm' neither printed an instruction nor named a next step"
exit 1
