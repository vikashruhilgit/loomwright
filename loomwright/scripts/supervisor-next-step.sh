#!/usr/bin/env bash
# supervisor-next-step.sh — the inline Supervisor's step driver (automate-speed/11). It owns the
# deterministic sequencing and bookkeeping of Supervisor Phases 0 INIT, 1 ACQUIRE, 1.5 PRE-FLIGHT SYNC
# and 2 PLAN (and the Phase 3 entry spawn), and hands the main thread exactly ONE instruction per call
# in automate-speed/06's instruction schema — `{"do":"spawn",…}` / `{"do":"ask",…}` / `{"do":"park",…}`
# / `{"do":"done",…}` — on stdout. The model does what the instruction says and reports back with
# `--result <json>`. The instruction shape, every `step` and `what` value and the `--result` shapes are
# documented in `docs/result-schemas/supervisor-result.md` §"supervisor next-step instruction" (the
# shared `do` enum is `docs/result-schemas/automate-run.md` §"next-step instruction"'s). The protocol it
# executes stays the phase skills' (`skills/supervisor-config/SKILL.md`, `skills/preflight-sync/SKILL.md`,
# `agents/supervisor.md` Phases 1–2): this script sequences, it never re-specifies a judgment.
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
#
# WRITES. The driver NEVER writes `.supervisor/state.md`: Context-Keeper is the sole writer of its
# Decisions Log / Worker Results / Error Log / Checkpoint / Phase Flags, and `## Session` is
# `scripts/build-state.sh`'s. Every flag and decision it decides is a `context-keeper` spawn carrying the
# exact operation text, answered by `--result {"confirmed": true}`. It writes only: the `.supervisor/`
# directories (and the `.supervisor/` line of `.gitignore`, as Phase 0 step 4 does), the job brief's
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
#   `gh` — LOOMWRIGHT_GH_BIN overrides it, as in every helper (no Phase 0–2 step calls it)
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
# flags stay prose. The driver trusts a well-formed classification / subtask report exactly as the
# model would have acted on it. A failed `git fetch` / `git pull` of the base is reported on stderr and
# recorded in the sidecar (`base_sync`); the guard then compares against the local base tip, as the
# prose snippet does. bash 3.2 + BSD userland + jq.

set -uo pipefail

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
    then: "--result {\"confirmed\": true} once Context-Keeper applied every op, in order"}')"
}
# sn_ask <step> <gate> <cant_ask status> <question> <answer step> — options and header from the ONE
# catalog (`lane-policy.sh catalog`): header = the code only for an `allowed` gate, "" for a human-only one
sn_ask() {
  local row pol labels hdr opts
  row="$(bash "$HERE/lane-policy.sh" catalog 2>/dev/null | awk -F'\t' -v c="$2" '$1 == c { print; exit }')"
  [ -n "$row" ] || { sn_fail "lane-policy.sh catalog has no $2 row — cannot ask"; return 1; }
  pol="$(printf '%s' "$row" | cut -f2)"; labels="$(printf '%s' "$row" | cut -f3)"
  if [ "$pol" = allowed ]; then hdr="$2"; else hdr=""; fi
  opts="$("$JQ" -cn --arg l "$labels" '$l | split("|")')"
  st_setj ask_options "$opts"; st_set answer_arm "$5"
  sn_emit ask "$1" "$("$JQ" -cn --arg g "$2" --arg h "$hdr" --arg q "$4" --arg c "$3" --argjson o "$opts" \
    '{gate: $g, question: $q, header: $h, options: $o, cant_ask: $c,
      questions: [{question: $q, header: $h, options: $o}],
      answer_with: "--result {\"answers\": [<one option label>], \"note\": \"<free text, optional>\"}; when the ask tool is unavailable --result {\"cant_ask\": true}"}')"
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
  local jp b t title ops gc ge gd ni_src mode maxw cost bm bw bb base
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
  grep -qxF '.supervisor/' .gitignore 2>/dev/null || printf '%s\n' '.supervisor/' >> .gitignore \
    || { sn_fail "cannot append .supervisor/ to .gitignore"; return 1; }
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
    invocation: "Read ${CLAUDE_PLUGIN_ROOT}/skills/preflight-sync/SKILL.md and run its actions 2-5 (gather remote state, the anticipated file set, classify, stacked-iteration scoping) inside its tool-call budget; do not act on the classification, report it",
    then: "--result {\"classification\": \"CLEAR|OVERLAP|SUPERSEDED|UNVERIFIED\", \"version\": \"<canonical version>\", \"base_tip\": \"<base tip sha>\", \"citations\": \"<the overlapping commits / PRs and the intersecting paths — OVERLAP and SUPERSEDED>\", \"advisory\": \"<churn_since_brief / premise_check notes, optional>\", \"warning\": \"<the one tooling warning — UNVERIFIED>\"}"}')"
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
    + (if $ch == "true" then {model: "sonnet"} else {} end)
    + {then: "--result {\"subtasks\": [{\"id\": \"<subtask id>\", \"title\": \"<title>\"}, …]} — the plan, in order"}')"
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
        + (if $ch == "true" then {model: "sonnet"} else {} end)
        + {then: "--result {\"result\": \"<the EXECUTE_RESULT block, verbatim>\"}"}')" ;;
    single-agent|sequential)
      i="$(st seq_index)"; [ -n "$i" ] || i=0
      id="$(printf '%s' "$(st subtasks)" | "$JQ" -r --argjson i "$i" '.[$i] // empty')"
      [ -n "$id" ] || { sn_fail "execute: no subtask at index $i"; return 1; }
      sn_spawn execute worker execute-result "$("$JQ" -cn --arg p "$p" --arg b "$(st job)" --arg id "$id" --arg r "$ROOT" \
        --arg ps "$(st plan_source)" --arg ch "$ch" '{agent: "loomwright:worker", path: $p, plan_source: $ps, subtask: $id, brief: $b,
          brief_note: "read only your subtask'"'"'s sections", worktree: $r}
        + (if $ch == "true" then {model: "sonnet"} else {} end)
        + {then: "--result {\"result\": \"<the WORKER_RESULT block, verbatim>\"}"}')" ;;
    *) sn_fail "execute: no execution path selected (plan-result has not run)"; return 1 ;;
  esac
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
  exit 0
fi
SN_STATE="$SN_SAVED"
sn_err "internal: step '$arm' neither printed an instruction nor named a next step"
exit 1
