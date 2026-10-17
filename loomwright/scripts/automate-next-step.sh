#!/usr/bin/env bash
# automate-next-step.sh — the `/automate` per-item loop's driver from RUN on (automate-speed/06
# the tail, automate-speed/07 RUN and DRAIN).
#
# The single reader and writer of a `/automate` run file from RUN to the item's end: RUN's
# bookkeeping (the `.auto_review` suppress / restore that wraps `/autonomous`, the session-id line,
# the PR record, the supervisor-result sidecar and its `sidecar-check`, the rate-limit park), DRAIN's
# (the pinned drain lines, `owned_drain_*`, the review-heal sidecar and its `sidecar-check`, the
# drain-superseded-by-merge close-out, learning-emit), GATE (the validation gate, safe mode's park,
# `--auto-merge`'s `gate-eval`), the dismissed-findings decision step, the park writes (park state,
# merge-watcher arming, notify, run-lock release) and the close-out (SYNC's `closeout … --no-trail`,
# the close-out leftover gate, CHECK OFF, termination). Called with the run file it runs every
# deterministic step itself and prints exactly ONE JSON instruction for the model on stdout —
# `{"do":"spawn",…}` / `{"do":"ask",…}` / `{"do":"park",…}` / `{"do":"done",…}` — and the model
# reports a step's result back with `--result <json>`. The instruction schema (the closed `do` enum,
# every field, the `--result` shapes incl. `progress_note`) is documented in
# `docs/result-schemas/automate-run.md` §"next-step instruction"; the protocol it executes is
# `skills/automate-loop/` §6 steps 2–6, §7 and §9/§10 (this script sequences, it never re-specifies).
#
# USAGE
#   automate-next-step.sh <runfile> [--start run|drain] [--result <json> | --result-file <f>]
#                         [--mode safe|auto-merge] [--non-interactive] [--trust-unprotected]
#                         [--root <checkout>] [--session-id <sid>] [--notify] [--cheap]
#                         [--max-tokens <N>]
#   Entry points: `--start run` right after PICK (`## Current` `status: running`, `pr: null`, the last
#   `picked` line naming the item) — the driver suppresses `.auto_review` and prints the `/autonomous`
#   spawn (`--non-interactive` adds `--non-interactive-fallback`; `--notify`, `--cheap` and
#   `--max-tokens N` — else `## Run Config`'s `max_tokens:` — pass through; none is written to the run
#   file); the RUN report answers it, and the driver goes on to print the owned-drain spawn, whose
#   DRAIN report starts GATE. `--start drain` prints the owned-drain spawn for a running item that
#   already has its PR (refused — `drain_already_owned`, exit 2 — once this pass spawned its drain).
#   "drain result reported" stays an entry too (back-compat): with nothing pending, a
#   `--result '{"drain_result":"READY|ESCALATED",…}'` from a model that did DRAIN's bookkeeping itself
#   (`--legacy`) starts GATE. A call with no
#   `--result` while an instruction is pending RE-PRINTS that instruction verbatim and writes nothing
#   (idempotent); a `--result` answers the pending `ask` / `spawn`; a `--result` after a terminal
#   `park` / `done` (or with nothing pending) starts the next item's tail — unless it is a REPLAY (the
#   same drain report for the same item + PR), which re-prints the terminal instruction and writes
#   nothing; a different report is accepted only while `## Current` reads `status: running` (the next
#   PICK set it), else it exits 2 with nothing written. `--session-id` is this loop's session id:
#   closeout re-enters the PICK's run lock with it, and the post-park lock windows acquire with it.
#   `--non-interactive`, `--trust-unprotected`, `--mode`, `--session-id` and `--root` persist in the
#   sidecar for the rest of this item's tail (a later call without them keeps them; an explicit one
#   still applies). Pending state is bound to the item + PR its tail started for: when `## Current`
#   names another item or PR, the sidecar (flags included) is discarded and the call is a fresh entry.
#
# STEPS — each is ONE `case` arm of ns_dispatch (the strings inventory homes cite as
#   `script:automate-next-step.sh <step>`):
#   run         `--start run`: `config-suppress` (malformed config ⇒ `config_malformed`, exit 2,
#               nothing written), `auto_review_original` via `config-orig <config> <backup>` (into
#               `## Run Config` when it differs), the `auto_review suppressed` line, the `/autonomous`
#               spawn
#   run-result  the RUN report: `config-restore` + the `auto_review restored` line — BEFORE any drain
#               spawn (the suppress window wraps RUN only)
#   run-record  the `session_id` line, `current-set … --pr --branch` BEFORE the `ran /autonomous → PR`
#               line (or the pinned no-PR line), the verbatim supervisor-result sidecar + `sidecar-check`
#   rate-limit  the loop's own session log: a main-scope `failed` row (`rate_limit`, or `unknown` + a
#               `429` hint ⇒ `reason_hint`) after this item's `picked` line ⇒ the rate_limit park;
#               else the drain (a PR) or `{"do":"done","status":"stopped"}` (no PR)
#   drain       the owned-drain spawn — ONE per pass (`drain_already_owned`, exit 2, nothing written)
#   drain-result the DRAIN report: the pinned start line, the report's free-text lines, the terminal
#               drain line, `owned_drain_*`, `pending_decisions` after a fix-now re-drain, the verbatim
#               review-heal sidecar + `sidecar-check`; no terminal block ⇒ `reconcile-item`
#   superseded  no terminal block and the PR merged: `owned_drain_result: superseded_by_merge`, its
#               line, NO sidecar, NO learning-emit, NO GATE — `closeout … --session-id`, classified
#   awaiting-go the close-out stop: `## Status: paused` + `pause_reason: awaiting_go` + run-lock release
#   learning-emit `automate-helpers.sh learning-emit` (always exit 0, never a decision), then GATE
#   gate        entry: the drain report ⇒ ESCALATED ⇒ dismissed (decide-then-park), else validation
#   validation  `validation-gate`; none/ok/waived ⇒ the mode's gate; unrun ⇒ AUT-WAIVE ask
#               (interactive, a V<n> step) or the escalated park (validation_unrun)
#   gate-eval   `--auto-merge`: writes the six-key ctx, calls `automate-helpers.sh gate-eval` — the one
#               merge executor; this script never merges anything itself
#   dismissed   `dismissed-drafts` (+ its summary line); after a MERGE also the pending record
#   decide      the owner's decisions on the drafts (before the park, or after it — park-first)
#   fix-now     the post-park fix-now hand-off (D3) and the fix-now re-drain `spawn` (its DRAIN report
#               goes through drain-result: the pinned fix-now re-drain lines are the driver's)
#   park        the park writes + watcher / notify / run-lock release
#   sync        SYNC after a MERGE: `closeout … --no-trail`, classified by `closeout-classify`
#   leftover    the close-out leftover gate (AUT-LEFTOVER ask, or the closeout_leftover park); after a
#               superseded close-out it goes on to awaiting-go, else to checkoff
#   checkoff    CHECK OFF + its Progress line
#   terminate   the two exits: `## Status: done` (trail-pr --reason done + dry sweep line) or the
#               limit_reached park; otherwise `{"do":"done","status":"running"}` (next PICK)
#
# WRITERS. The run file is written ONLY through automate-helpers.sh `runfile-write`, `progress-append`,
# `current-set`, `current-escalation` and `queue-checkoff` (plus the writes the called helpers make
# themselves: `dismissed-decide`, `validation-gate --waive`, `closeout`, `closeout-classify --record`).
# A non-zero writer exit is SURFACED — stderr names it, no instruction is printed, the driver exits with
# that code and its sidecar stays at the failing step, so the next call retries it.
#
# SIDECAR. `.supervisor/automate/<run_id>.next-step.json` (gitignored like every `*.json` beside the run
# file) holds the step the driver waits on, the instruction it last printed (verbatim) and the tail's
# context (the drain report, the gate line, the decision queue). `<run_id>.gate-ctx.json` is the ctx it
# hands `gate-eval` — exactly the six loop-owned keys.
#
# SIDE EFFECTS that cannot run hermetically go through overridable command lines (word-split, the
# arguments appended):
#   NEXT_STEP_WATCH_CMD   <rf> <item> <pr>          default: the §6 "Post-merge close-out" launch line
#                                                   (nohup bash automate-merge-watch.sh …, detached;
#                                                   the watcher drops the host session identity itself)
#   NEXT_STEP_NOTIFY_CMD  <kind> <rf> <message>     default: awaiting_merge / escalated ⇒ a desktop
#                                                   notification (notify-desktop.sh); ready_for_release
#                                                   ⇒ `lane-park-notify` + the advisory `lane-readiness`
#   NEXT_STEP_LOCK_CMD    acquire|release --owner automate:<run_id> [--session-id <sid>]
#                                                   default: bash run-lock.sh
#   NEXT_STEP_LOCK_RETRY_SECONDS  pause between the 3 retries of a refused post-release acquire (5)
#   `gh` (LOOMWRIGHT_GH_BIN overrides it, as in every helper) — the drain spawn's head-sha read and
#   learning-emit's one `gh pr view <pr> --json files,additions,deletions,changedFiles` fetch (a
#   failure degrades to `[]` / 0 — learning-emit's own documented degraded line); tests stub it on PATH
#
# TEST SEAMS (tests only — never set in a real run; each widens nothing a real run can reach):
#   NEXT_STEP_FROM=<step>       start at <step> (a golden case that begins mid-tail); `--result`, if
#                               given, is read as the drain report
#   NEXT_STEP_UNTIL=<step>      stop after <step> finishes (a golden case that ends mid-tail): no
#                               instruction is printed, the sidecar keeps the next step
#   NEXT_STEP_CLOSEOUT_OUT=<f>  `sync` reads closeout's output from <f> instead of running closeout
#                               (the golden leftover case supplies it as fixed input)
#
# Exit codes: 0 an instruction printed (or a NEXT_STEP_UNTIL stop); 1 a helper / writer failure
# (surfaced); 2 usage error, a `--result` that does not answer what is pending, or a malformed /
# out-of-state drain report (REPORT VALIDATION below), or a named refusal on stderr —
# `next-step: config_malformed — …` (`config-suppress`'s exit 2: no spawn, no line, config.json
# byte-unchanged, no backup), `config_backup_stranded`, `run_already_started`, `drain_already_owned`
# — nothing written. A writer's own non-zero code is passed through (progress-append's 3,
# `current_not_set`, on the drain start line included).
#
# REPORT VALIDATION (fail CLOSED, exit 2, nothing written): every drain-report field the driver
# branches on or hands to a writer is checked before the first write — `drain_result` is exactly
# READY | ESCALATED at the `gate` step (anything else, `died` / `superseded_by_merge` / a lowercase or
# misspelt value included, is refused, never routed down the READY path); `ready_sha` /
# `escalation_sha` hex (7–40); `escalation_cause` the current-escalation enum; `escalation_attempt` /
# `items_processed` 1–9 digits (a count `[` can compare), `escalation_run_id` 1–20 digits; `progress_note`
# one line. A drain report starts a tail only while `## Current` reads `status: running` (the first drain and both
# fix-now re-drain hand-offs set it): a different report after a terminal park is refused, a
# byte-identical one is a replay. After a `spawn` the re-drain report REPLACES the first one (no
# field of the first drain survives into the second GATE pass); the first report re-sent there (same
# report key, a sha) is a replay — the spawn re-prints, nothing written. A tail's report key outlives the
# tail as `stale_report_key`: re-sent while ## Current names the next item it is refused (exit 2) on
# every path that takes a drain report. An optional `pr` field binds a report to its PR: another PR than
# ## Current's is refused, and a matching one is never read as stale. A sha-less report cannot be told
# from a replay and is taken (honest limit; `pr` binds it).
#
# `pending_decisions` is a count or `unknown` (dismissed-pending's "cannot tell", treated as non-zero): read
# and normalised before the first park write, never a refusal — the park, watcher, notify and run-lock
# release always complete.
#
# RUN / DRAIN REPORTS (validated the same way — fail CLOSED, exit 2, nothing written — before the
# first write; the shapes are the schema doc's). A RUN report answers the `/autonomous run` spawn; a
# DRAIN report (`review_heal_result` / `review_heal_result_file` / `no_terminal_block: true`, exactly
# one) answers the `owned drain` spawn and, in place of a bare drain report, the fix-now re-drain
# spawn. The verbatim result text is held in the sidecar until its sidecar file is written, so a
# retried step rewrites the same bytes. Each multi-write step records which of its writes landed
# (`once_*` keys in the sidecar), so the retry of a failed step never appends a line twice.
#
# Honest limits: the driver trusts a well-formed drain report's `drain_result` / `termination_reason`
# / `ready_sha` exactly as the loop did — `gate-eval` cross-checks them against the review-heal sidecar
# and the live head, so a false claim can only park. A DRAIN report's free-text lines (`progress_notes`,
# `drain_note`) are the model's and are stamped when the report arrives; the drain's start line carries
# the time the owned-drain spawn was printed (or the report's `started_at`), so a crash mid-drain
# leaves no start line — the sidecar's pending spawn is the evidence. PICK / RECONCILE / resume (item
# 08) stay prose, including RECONCILE's crash-restore of a stranded config backup. The default notifier
# is desktop-only: no webhook gate type is defined for a sequential park. bash 3.2 + BSD userland + jq.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
H="$HERE/automate-helpers.sh"
JQ="${JQ:-jq}"

ns_usage() {
  sed -n 's/^#   automate-next-step.sh /automate-next-step.sh /p; s/^#                         \[/                      [/p' "${BASH_SOURCE[0]}" | head -n 4
}
ns_die2() { echo "next-step: $*" >&2; exit 2; }
ns_err() { echo "next-step: $*" >&2; }
ns_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

command -v "$JQ" >/dev/null 2>&1 || { ns_err "jq not on PATH"; exit 1; }
[ -f "$H" ] || { ns_err "automate-helpers.sh not found beside this script ($H)"; exit 1; }

# ------------------------------------------------------------------------------------------------
# arguments
# ------------------------------------------------------------------------------------------------
RF=""; RESULT=""; MODE=""; NONINT=0; TRUST=""; ROOT=""; SID=""; have_result=0
START=""; NOTIFY=0; CHEAP=0; MAXTOK=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --start)
      [ "$#" -ge 2 ] || ns_die2 "--start needs a value"
      case "$2" in run|drain) START="$2" ;; *) ns_die2 "--start must be run|drain: '$2'" ;; esac
      shift 2 ;;
    --notify) NOTIFY=1; shift ;;
    --cheap) CHEAP=1; shift ;;
    --max-tokens)
      [ "$#" -ge 2 ] && [[ "$2" =~ ^[0-9]{1,12}$ ]] || ns_die2 "--max-tokens needs a token count"
      MAXTOK="$2"; shift 2 ;;
    --result) [ "$#" -ge 2 ] || ns_die2 "--result needs a value"; RESULT="$2"; have_result=1; shift 2 ;;
    --result-file)
      [ "$#" -ge 2 ] || ns_die2 "--result-file needs a value"
      [ -r "$2" ] || ns_die2 "--result-file not readable: $2"
      RESULT="$(cat "$2")"; have_result=1; shift 2 ;;
    --mode)
      [ "$#" -ge 2 ] || ns_die2 "--mode needs a value"
      case "$2" in safe|auto-merge) MODE="$2" ;; *) ns_die2 "--mode must be safe|auto-merge: '$2'" ;; esac
      shift 2 ;;
    --non-interactive) NONINT=1; shift ;;
    --trust-unprotected) TRUST=true; shift ;;
    --root) [ "$#" -ge 2 ] && [ -n "$2" ] || ns_die2 "--root needs a value"; ROOT="$2"; shift 2 ;;
    --session-id) [ "$#" -ge 2 ] && [ -n "$2" ] || ns_die2 "--session-id needs a value"; SID="$2"; shift 2 ;;
    -h|--help) ns_usage; exit 0 ;;
    -*) ns_die2 "unknown option '$1'" ;;
    *) [ -z "$RF" ] || ns_die2 "one run file only (got '$RF' and '$1')"; RF="$1"; shift ;;
  esac
done
[ -n "$RF" ] || { ns_usage >&2; ns_die2 "usage: automate-next-step.sh <runfile> [options]"; }
[ -f "$RF" ] && [ -r "$RF" ] || ns_die2 "run file not found or unreadable: $RF"
if [ "$have_result" = 1 ]; then
  printf '%s' "$RESULT" | "$JQ" -e 'type == "object"' >/dev/null 2>&1 || ns_die2 "--result is not a JSON object"
fi
RF="$(cd "$(dirname "$RF")" && pwd)/$(basename "$RF")"
AD="$(dirname "$RF")"
RUN_ID="$(basename "$RF" .md)"
SIDECAR="$AD/$RUN_ID.next-step.json"
CTXF="$AD/$RUN_ID.gate-ctx.json"
# ROOT is resolved (and cd'ed into) after the sidecar is read: a --root given earlier in this item's
# tail is persisted there (see FLAGS below)
ns_resolve_root() {
  if [ -z "$ROOT" ]; then
    case "$AD" in
      */.supervisor/automate) ROOT="${AD%/.supervisor/automate}" ;;
      *) ROOT="$(git -C "$AD" rev-parse --show-toplevel 2>/dev/null || pwd)" ;;
    esac
  fi
  cd "$ROOT" 2>/dev/null || ns_die2 "--root is not a directory: $ROOT"
  ROOT="$(pwd)"
}

# ------------------------------------------------------------------------------------------------
# state (the sidecar's JSON, held in NS_STATE; written once at exit)
# ------------------------------------------------------------------------------------------------
NS_STATE='{}'
if [ -f "$SIDECAR" ] && "$JQ" -e 'type == "object"' "$SIDECAR" >/dev/null 2>&1; then
  NS_STATE="$(cat "$SIDECAR")"
fi
st() { printf '%s' "$NS_STATE" | "$JQ" -r --arg k "$1" '.[$k] // empty | if type == "string" then . else tojson end'; }
st_set() { NS_STATE="$(printf '%s' "$NS_STATE" | "$JQ" -c --arg k "$1" --arg v "$2" '.[$k] = $v')"; }
st_setj() { NS_STATE="$(printf '%s' "$NS_STATE" | "$JQ" -c --arg k "$1" --argjson v "$2" '.[$k] = $v')"; }
st_del() { NS_STATE="$(printf '%s' "$NS_STATE" | "$JQ" -c --arg k "$1" 'del(.[$k])')"; }
st_save() {
  local t="$SIDECAR.tmp.$$"
  printf '%s\n' "$NS_STATE" | "$JQ" -S . > "$t" 2>/dev/null && mv -f "$t" "$SIDECAR" \
    || { rm -f "$t"; ns_err "cannot write $SIDECAR"; return 1; }
}
rj() { printf '%s' "$1" | "$JQ" -r --arg k "$2" '.[$k] // empty | if type == "string" then . else tojson end' 2>/dev/null; }

# ------------------------------------------------------------------------------------------------
# run-file reads
# ------------------------------------------------------------------------------------------------
ns_section() { # <heading> — the lines of that `## ` section
  NS_H="$1" awk 'BEGIN { h = ENVIRON["NS_H"] } /^## / { s = ($0 == h || index($0, h " ") == 1); next } s' "$RF"
}
ns_kv() { # <line> <key> — the value of `key: v` inside a ` | `-separated line
  printf '%s\n' "$1" | NS_K="$2" awk 'BEGIN { k = ENVIRON["NS_K"] }
    { sub(/^- /, ""); n = split($0, a, / \| /)
      for (i = 1; i <= n; i++) if (index(a[i], k ": ") == 1) { print substr(a[i], length(k) + 3); exit } }'
}
ns_refresh() {
  local l
  l="$(ns_section '## Current' | grep -m1 '^- item: ' || true)"
  ITEM="$(ns_kv "$l" item)"; STATUS="$(ns_kv "$l" status)"; PR="$(ns_kv "$l" pr)"; BRANCH="$(ns_kv "$l" branch)"
  PENDING_LINE="$(ns_section '## Current' | grep -m1 '^- pending_decisions: ' || true)"
  CFG="$(ns_section '## Run Config' | grep -m1 '^- mode: ' || true)"
}
ns_mode() { if [ -n "$MODE" ]; then echo "$MODE"; else local m; m="$(ns_kv "$CFG" mode)"; echo "${m:-safe}"; fi; }
ns_trust() {
  if [ -n "$TRUST" ]; then echo true; return; fi
  case "$(ns_kv "$CFG" trust_unprotected)" in true) echo true ;; *) echo false ;; esac
}
# a count the driver compares with `[ -ge/-lt ]` is 1–9 digits: a longer one overflows test's integer
# ("integer expected", the test is false) — refused, never read as a small number (fail CLOSED)
ns_count_ok() { [[ "$1" =~ ^[0-9]{1,9}$ ]]; }
ns_limit() { local l; l="$(ns_kv "$CFG" limit)"; if ns_count_ok "$l"; then echo "$l"; else echo 5; fi; }
ns_fixnow_reentered() {
  local f; f="$(st fix_now_reentered)"
  [ -n "$f" ] || f="$(ns_kv "$PENDING_LINE" fix_now_reentered)"
  [ "$f" = true ] && echo true || echo false
}
# a lane: `.supervisor/lane.json` exists — `lane-park`'s own criterion (it fails toward ready_for_release
# on an unreadable one), so the driver and the park seam can never disagree on which park to write
ns_lane() { [ -e "$ROOT/.supervisor/lane.json" ]; }
ns_interactive() { [ "$NONINT" != 1 ]; }

# the Progress lines of this item's tail segment: after the last drain marker line
ns_tail_lines() {
  ns_section '## Progress' | awk '
    { l = $0; sub(/^- /, "", l); x = l; sub(/^[^ ]+ /, "", x)
      if (x ~ /^(owned drain started|drain (READY|ESCALATED)|fix-now re-drain (READY|ESCALATED))/ || l ~ /^(owned drain started|drain (READY|ESCALATED))/) n = 0
      else line[++n] = $0 }
    END { for (i = 1; i <= n; i++) print line[i] }'
}

# ------------------------------------------------------------------------------------------------
# writers — the five run-file writers only; a non-zero exit is surfaced (NS_RC + return 1)
# ------------------------------------------------------------------------------------------------
NS_RC=0
ns_call_writer() { # <subcommand> <args…>
  local e rc
  e="$(bash "$H" "$@" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    ns_err "automate-helpers.sh $1 exited $rc${e:+: $e}"; NS_RC="$rc"; return 1
  fi
  return 0
}
ns_progress() { ns_call_writer progress-append "$RF" "$1"; }
ns_status() { # <running|paused|done>
  local cur new
  cur="$(cat "$RF"; printf x)"; cur="${cur%x}"
  new="$(NS_S="$1" awk 'BEGIN { s = ENVIRON["NS_S"] } !d && /^## Status: / { print "## Status: " s; d = 1; next } { print }' "$RF"; printf x)"
  new="${new%x}"
  [ "$cur" = "$new" ] && return 0
  local e rc
  e="$(printf '%s' "$new" | bash "$H" runfile-write "$RF" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || { ns_err "automate-helpers.sh runfile-write exited $rc${e:+: $e}"; NS_RC="$rc"; return 1; }
}
# ns_pending_n — `dismissed-pending`'s answer, normalised BEFORE any write: a count, else `unknown` (its
# documented "cannot tell" — a draft of ANY item with no readable Decision line, an unreadable ledger —
# which every caller treats as non-zero; an empty or garbled output reads the same way, fail closed
# toward asking). Never an error: a non-count must not block the park, the watcher, the notify or the
# run-lock release
ns_pending_n() {
  local n; n="$(bash "$H" dismissed-pending "$RF" 2>/dev/null | tail -n 1)"
  if ns_count_ok "$n"; then printf '%s' "$n"; else printf unknown; fi
}
ns_pending_write() { # <n|unknown> <true|false> — the `- pending_decisions:` line of ## Current (replaced, else after owned_drain_started, else at the block end)
  local line="- pending_decisions: $1 | fix_now_reentered: $2" new e rc
  ns_count_ok "$1" || [ "$1" = unknown ] || { ns_err "pending_decisions '$1' is neither a count nor unknown — not written"; NS_RC=1; return 1; }
  new="$(NS_L="$line" NS_HAS="${PENDING_LINE:+1}" awk '
    BEGIN { l = ENVIRON["NS_L"]; has = (ENVIRON["NS_HAS"] == "1") }
    /^## / { if (c && !d) { print l; d = 1 } c = ($0 == "## Current"); print; next }
    c && !d && index($0, "- pending_decisions:") == 1 { print l; d = 1; next }
    { print }
    c && !d && !has && index($0, "- owned_drain_started:") == 1 { print l; d = 1 }
    END { if (c && !d) print l }' "$RF"; printf x)"
  new="${new%x}"
  e="$(printf '%s' "$new" | bash "$H" runfile-write "$RF" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || { ns_err "automate-helpers.sh runfile-write exited $rc${e:+: $e}"; NS_RC="$rc"; return 1; }
  ns_refresh
}

# ------------------------------------------------------------------------------------------------
# side effects (overridable)
# ------------------------------------------------------------------------------------------------
ns_lock() { # acquire|release
  local verb="$1" a=""
  [ "$verb" = acquire ] && [ -n "$SID" ] && a="--session-id"
  if [ -n "${NEXT_STEP_LOCK_CMD:-}" ]; then
    # shellcheck disable=SC2086
    $NEXT_STEP_LOCK_CMD "$verb" --owner "automate:$RUN_ID" ${a:+"$a" "$SID"} </dev/null >/dev/null 2>&1
  else
    bash "$HERE/run-lock.sh" "$verb" --owner "automate:$RUN_ID" ${a:+"$a" "$SID"} </dev/null >/dev/null 2>&1
  fi
}
ns_lock_window() { # acquire, retried 3 times — 0 when held
  local i=0
  while :; do
    ns_lock acquire && return 0
    [ "$i" -lt 3 ] || return 1
    i=$((i + 1)); sleep "${NEXT_STEP_LOCK_RETRY_SECONDS:-5}"
  done
}
ns_release() { ns_lock release || ns_err "run-lock.sh release refused (owner automate:$RUN_ID) — reported, the park stands"; return 0; }
ns_watch() {
  if [ -n "${NEXT_STEP_WATCH_CMD:-}" ]; then
    # shellcheck disable=SC2086
    $NEXT_STEP_WATCH_CMD "$RF" "$ITEM" "$PR" </dev/null >/dev/null 2>&1 || ns_err "merge watcher launch failed (reported)"
  else
    nohup bash "$HERE/automate-merge-watch.sh" "$RF" "$ITEM" "$PR" \
      </dev/null >"$AD/$RUN_ID.merge-watch.log" 2>&1 &
  fi
  return 0
}
ns_notify() { # <kind> <message>
  if [ -n "${NEXT_STEP_NOTIFY_CMD:-}" ]; then
    # shellcheck disable=SC2086
    $NEXT_STEP_NOTIFY_CMD "$1" "$RF" "$2" </dev/null >/dev/null 2>&1
  elif [ "$1" = ready_for_release ]; then
    bash "$H" lane-park-notify "$RF" </dev/null >/dev/null 2>&1
    bash "$H" lane-readiness "$ROOT" </dev/null >/dev/null 2>&1
  else
    local p
    p="$("$JQ" -cn --arg m "$2" '{hook_event_name: "Notification", notification_type: "automate_park", message: $m}')"
    printf '%s' "$p" | bash "$HERE/notify-desktop.sh" >/dev/null 2>&1
  fi
  return 0
}

# ------------------------------------------------------------------------------------------------
# instructions (exactly one per call, compact JSON on stdout)
# ------------------------------------------------------------------------------------------------
NS_EMIT=""
ns_base() { # <do> <step> — the common fields as a JSON object
  "$JQ" -cn --arg d "$1" --arg s "$2" --arg r "$RUN_ID" --arg i "$ITEM" --arg p "$PR" \
    '{do: $d, step: $s, run_id: $r, item: (if $i == "" then null else $i end), pr: (if $p == "" or $p == "null" then null else $p end)}'
}
ns_emit() { NS_EMIT="$(printf '%s' "$(ns_base "$1" "$2")" | "$JQ" -c --argjson x "$3" '. + $x')"; }
ns_emit_ask() { # <step> <gate> <cant_ask> <questions json array>
  local x
  x="$("$JQ" -cn --arg g "$2" --arg c "$3" --argjson q "$4" '{gate: $g, question: $q[0].question, header: $q[0].header,
      options: $q[0].options, cant_ask: $c, questions: $q,
      answer_with: "--result {\"answers\": [<one option label per question, in order>], \"note\": \"<free text, optional>\"}; when the ask tool is unavailable --result {\"cant_ask\": true}"}')"
  ns_emit ask "$1" "$x"
}
ns_emit_park() { # <step> <message>
  ns_refresh
  local pr_ esc pd x
  pr_="$(ns_section '## Current' | grep -m1 '^- pause_reason: ' | sed 's/^- pause_reason: //')"
  esc="$(ns_section '## Current' | grep -m1 '^- escalation_cause: ' | sed 's/^- escalation_cause: //; s/ |.*//')"
  pd="$(ns_kv "$PENDING_LINE" pending_decisions)"
  x="$("$JQ" -cn --arg r "$pr_" --arg e "$esc" --arg p "$pd" --arg m "$2" \
    '{status: "paused", pause_reason: $r} + (if $e != "" then {escalation_cause: $e} else {} end)
     + (if $p != "" then {pending_decisions: ($p | tonumber? // $p)} else {} end) + {message: $m}')"
  ns_emit park "$1" "$x"
}

# ------------------------------------------------------------------------------------------------
# the drain report (gate entry; a FROM seam's --result)
# ------------------------------------------------------------------------------------------------
NS_REPORT_KEYS='["drain_result","termination_reason","ready_sha","escalation_cause","escalation_check","escalation_run_id","escalation_attempt","escalation_sha"]'
ns_report_key() { printf '%s' "$1" | "$JQ" -cS --argjson k "$NS_REPORT_KEYS" '. as $r | [$k[] | {(.): ($r[.] // null)}] | add' 2>/dev/null; }
NS_REPORT_FIELDS="drain_result termination_reason ready_sha progress_note escalation_cause escalation_check
  escalation_run_id escalation_attempt escalation_sha items_processed"
# ns_field_ok <key> <value> — 0 when <value> is well-formed for <key> (keys without a rule pass)
ns_field_ok() {
  case "$1" in
    drain_result) case "$2" in READY|ESCALATED) return 0 ;; *) return 1 ;; esac ;;
    ready_sha|escalation_sha) [[ "$2" =~ ^[0-9a-fA-F]{7,40}$ ]] ;;
    escalation_cause)
      case "$2" in check_pending|check_red_unrelated|check_red|findings|validation_unrun|other) return 0 ;; *) return 1 ;; esac ;;
    escalation_attempt|items_processed) ns_count_ok "$2" ;;
    escalation_run_id) [[ "$2" =~ ^[0-9]{1,20}$ ]] ;;   # an id, never compared — bounded, not narrowed
    progress_note) case "$2" in *$'\n'*|*$'\r'*) return 1 ;; *) return 0 ;; esac ;;
    *) return 0 ;;
  esac
}
# ns_check_report <json> — refuse (exit 2, before any write) a field the driver would branch on or write
# malformed; drain_result's enum is the `gate` step's own check (the NEXT_STEP_FROM seam may skip gate)
ns_check_report() {
  local k v
  for k in $NS_REPORT_FIELDS; do
    [ "$k" = drain_result ] && continue
    v="$(rj "$1" "$k")"
    [ -z "$v" ] || ns_field_ok "$k" "$v" || ns_die2 "--result: malformed $k '$v' — nothing written"
  done
  # the optional `pr` binds the report to its PR: another PR than ## Current's is refused (never stored —
  # the sidecar's `pr` is ## Current's own)
  v="$(rj "$1" pr)"
  [ -z "$v" ] || [ "$v" = "$PR" ] || ns_die2 "--result: pr '$v' is not ## Current's PR (${PR:-none}) — nothing written"
  return 0
}
# ns_same_report <json> <key> — 0 when <json> is the drain report <key> was taken from: its key is equal
# and it names a head (ready_sha / escalation_sha — a fix-now pass or another item always moves it, so a
# genuinely new report differs). A sha-less report cannot be told from a replay and is taken (honest
# limit; the optional `pr` field binds it instead)
ns_same_report() {
  [ -n "$2" ] && [ -n "$(rj "$1" ready_sha)$(rj "$1" escalation_sha)" ] && [ "$(ns_report_key "$1")" = "$2" ]
}
# ns_stale_report <json> — 0 when <json> is the report of a tail this sidecar already left behind (the
# discarded / previous tail's `stale_report_key`) and carries no `pr` claiming ## Current's PR
ns_stale_report() { [ -z "$(rj "$1" pr)" ] && ns_same_report "$1" "$(st stale_report_key)"; }
ns_take_report() { # <json> — the report REPLACES every field of a previous one
  st_set report_key "$(ns_report_key "$1")"
  local k v
  for k in $NS_REPORT_FIELDS; do
    st_del "$k"
    v="$(rj "$1" "$k")"
    [ -n "$v" ] && st_set "$k" "$v"
  done
  return 0
}

# ------------------------------------------------------------------------------------------------
# RUN / DRAIN reports (automate-speed/07): validated before the first write, held in the sidecar
# ------------------------------------------------------------------------------------------------
TAB="$(printf '\t')"
ns_one_line() { case "$1" in *$'\n'*|*$'\r'*) return 1 ;; *) return 0 ;; esac; }
ns_sha_ok() { [[ "$1" =~ ^[0-9a-fA-F]{7,40}$ ]]; }
ns_iso_ok() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; }
ns_pr_ok() { [[ "$1" =~ ^https?://[^[:space:]|]+/pull/[0-9]+$ ]]; }
ns_sid_ok() { [[ "$1" =~ ^[A-Za-z0-9._:-]{1,128}$ ]] && [ "$1" != . ] && [ "$1" != .. ]; }
# ns_block_field <block name> <key> [raw]  (text on stdin) — a TOP-LEVEL key of the LAST `<name>` block, in
# either shape result_block_parser.find_last_block recognises: the YAML form (`<name>:` then `key: v` at
# the indent of the block's first key) or the markdown-bullet form (`## <name>` then `- key: v` at the
# first bullet's indent). A nested key is never read; a ``` fence, a shallower line or (bullet form) a
# heading / a non-bullet line ends the block. Quotes stripped; `null` reads as empty unless `raw` is given.
ns_block_field() {
  NS_B="$1" NS_K="$2" NS_RAW="${3:-}" awk '
    BEGIN { b = ENVIRON["NS_B"]; k = ENVIRON["NS_K"] ":"; raw = (ENVIRON["NS_RAW"] == "raw") }
    { line[NR] = $0 }
    END {
      s = 0; md = 0
      for (i = 1; i <= NR; i++) {
        l = line[i]; sub(/^[ \t]+/, "", l); sub(/[ \t]+$/, "", l)
        if (l == b ":") { s = i; md = 0 }
        else if (l ~ /^#+ / && substr(l, index(l, " ") + 1) == b) { s = i; md = 1 }
      }
      if (!s) exit
      ind = -1
      for (i = s + 1; i <= NR; i++) {
        l = line[i]
        if (l ~ /^[ \t]*```/) break
        if (l ~ /^[ \t]*$/) continue
        if (md && l ~ /^[ \t]*#/) break
        match(l, /^ */); n = RLENGTH
        if (ind < 0) ind = n
        if (n < ind) break
        if (n != ind) continue
        r = substr(l, n + 1)
        if (md) { if (substr(r, 1, 2) != "- ") break; r = substr(r, 3) }
        if (index(r, k) == 1) {
          v = substr(r, length(k) + 1); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
          if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
          if (v == "null" && !raw) v = ""
          print v; exit
        }
      }
    }'
}
ns_report_text() { # <json> <field> — the verbatim text a report carries inline (<field>) or by path (<field>_file)
  local f; f="$(rj "$1" "$2_file")"
  if [ -n "$f" ]; then cat "$f" 2>/dev/null; else printf '%s' "$1" | "$JQ" -r --arg k "$2" '.[$k] // empty | strings'; fi
}
ns_take_text() { # <json> <field> <state key> — the verbatim bytes into the sidecar (written out later by ns_write_text)
  local f; f="$(rj "$1" "$2_file")"
  if [ -n "$f" ]; then
    NS_STATE="$(printf '%s' "$NS_STATE" | "$JQ" -c --arg k "$3" --rawfile t "$f" '.[$k] = $t')"
  else
    NS_STATE="$(printf '%s' "$NS_STATE" | "$JQ" -c --arg k "$3" --argjson r "$1" --arg f "$2" '.[$k] = ($r[$f] // null)')"
  fi
}
ns_write_text() { # <state key> <path> — the held verbatim text, byte for byte (temp + rename)
  local t="$2.tmp.$$"
  printf '%s' "$NS_STATE" | "$JQ" -j --arg k "$1" '.[$k] // empty' > "$t" 2>/dev/null && mv -f "$t" "$2" \
    || { rm -f "$t"; ns_err "cannot write $2"; NS_RC=1; return 1; }
}
ns_check_text_pair() { # <json> <field> — the inline text and the file path are exclusive; the text is a string, the file readable
  local f
  printf '%s' "$1" | "$JQ" -e --arg k "$2" '(.[$k] == null or (.[$k] | type) == "string") and (.[$k + "_file"] == null or (.[$k + "_file"] | type) == "string")' >/dev/null 2>&1 \
    || ns_die2 "--result: $2 / $2_file must be strings — nothing written"
  f="$(rj "$1" "$2_file")"
  [ -z "$f" ] || [ -z "$(rj "$1" "$2")" ] || ns_die2 "--result: $2 and $2_file are exclusive — nothing written"
  [ -z "$f" ] || { [ -f "$f" ] && [ -r "$f" ]; } || ns_die2 "--result: $2_file is not a readable file: $f — nothing written"
}
ns_check_one_line() { # <json> <field…> — each present field one line
  local r="$1" k v; shift
  for k in "$@"; do v="$(rj "$r" "$k")"; ns_one_line "$v" || ns_die2 "--result: $k must be one line — nothing written"; done
}

# ns_check_run_report <json> — the RUN report (answer to the `/autonomous run` spawn): the verbatim
# SUPERVISOR_RESULT (`supervisor_result` | `supervisor_result_file`), `session_id`, `run_note`, or —
# with no PR — `status_reason` + `no_pr_why`. The PR / branch are read from the SUPERVISOR_RESULT
# text (`pr_url` / `branch` fields only fill a gap and must agree with it). Sets NS_RUN_PR / NS_RUN_BR.
ns_check_run_report() {
  local r="$1" t tpr tbr pr br v
  ns_check_text_pair "$r" supervisor_result
  ns_check_one_line "$r" session_id run_note status_reason no_pr_why pr_url branch
  v="$(rj "$r" session_id)"; [ -z "$v" ] || ns_sid_ok "$v" || ns_die2 "--result: malformed session_id '$v' — nothing written"
  v="$(rj "$r" status_reason)"; [ -z "$v" ] || [[ "$v" =~ ^[A-Za-z0-9_.-]{1,64}$ ]] || ns_die2 "--result: malformed status_reason '$v' — nothing written"
  t="$(ns_report_text "$r" supervisor_result)"
  tpr="$(printf '%s\n' "$t" | ns_block_field SUPERVISOR_RESULT pr_url)"; tbr="$(printf '%s\n' "$t" | ns_block_field SUPERVISOR_RESULT branch)"
  pr="$(rj "$r" pr_url)"; br="$(rj "$r" branch)"
  [ -z "$pr" ] || [ -z "$tpr" ] || [ "$pr" = "$tpr" ] || ns_die2 "--result: pr_url '$pr' disagrees with the SUPERVISOR_RESULT's '$tpr' — nothing written"
  [ -z "$br" ] || [ -z "$tbr" ] || [ "$br" = "$tbr" ] || ns_die2 "--result: branch '$br' disagrees with the SUPERVISOR_RESULT's '$tbr' — nothing written"
  pr="${tpr:-$pr}"; br="${tbr:-$br}"
  if [ -n "$pr" ]; then
    ns_pr_ok "$pr" || ns_die2 "--result: malformed pr_url '$pr' — nothing written"
    [[ "$br" =~ ^[^[:space:]|]{1,200}$ ]] || ns_die2 "--result: a RUN report with a PR needs its branch (got '${br}') — nothing written"
    [ -n "$t" ] || ns_die2 "--result: a RUN report with a PR carries the verbatim SUPERVISOR_RESULT (supervisor_result / supervisor_result_file) — nothing written"
  else
    [ -n "$(rj "$r" no_pr_why)" ] || ns_die2 "--result: a RUN report without a PR carries no_pr_why (the one-line why of the pinned no-PR line) — nothing written"
  fi
  NS_RUN_PR="$pr"; NS_RUN_BR="$br"
}
ns_take_run_report() {
  ns_take_text "$1" supervisor_result run_text
  st_setj run_report "$(printf '%s' "$1" | "$JQ" -c 'del(.supervisor_result)')"
  st_set run_pr "$NS_RUN_PR"; st_set run_branch "$NS_RUN_BR"
}
ns_is_drain_report() { printf '%s' "$1" | "$JQ" -e 'has("review_heal_result") or has("review_heal_result_file") or has("no_terminal_block")' >/dev/null 2>&1; }
ns_is_run_report() { printf '%s' "$1" | "$JQ" -e '(has("drain_result") | not) and (has("supervisor_result") or has("supervisor_result_file") or has("no_pr_why") or has("status_reason") or has("run_note"))' >/dev/null 2>&1; }
# ns_check_drain_report <json> — the DRAIN report (answer to the `owned drain` spawn / the fix-now re-drain
# spawn): exactly one of `review_heal_result` | `review_heal_result_file` | `no_terminal_block: true`;
# the block's `decision` exactly READY | ESCALATED; `head_sha` / `ready_sha` hex, `started_at` ISO-8601 Z,
# `drain_note` one line, `progress_notes` an array (≤ 20) of one-line strings; the legacy drain-report
# fields (`progress_note`, `items_processed`, `escalation_*`, `pr`) under their own rules
ns_check_drain_report() {
  local r="$1" t n k v
  ns_check_text_pair "$r" review_heal_result
  n=0; [ -n "$(rj "$r" review_heal_result)" ] && n=$((n + 1)); [ -n "$(rj "$r" review_heal_result_file)" ] && n=$((n + 1))
  v="$(rj "$r" no_terminal_block)"
  case "$v" in "") ;; true) n=$((n + 1)) ;; *) ns_die2 "--result: no_terminal_block must be true — nothing written" ;; esac
  [ "$n" = 1 ] || ns_die2 "--result: a DRAIN report carries exactly one of review_heal_result | review_heal_result_file | no_terminal_block: true — nothing written"
  if [ "$v" != true ]; then
    t="$(ns_report_text "$r" review_heal_result)"
    v="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT decision)"
    ns_field_ok drain_result "$v" || ns_die2 "--result: the REVIEW_HEAL_RESULT block's decision must be READY|ESCALATED (got '${v}') — nothing written"
    v="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT termination_reason)"
    [ -z "$v" ] || [[ "$v" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || ns_die2 "--result: malformed termination_reason '$v' — nothing written"
    for k in rounds fix_cycles; do
      v="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT "$k")"; [ -z "$v" ] || ns_count_ok "$v" || ns_die2 "--result: malformed $k '$v' — nothing written"
    done
    for k in repeat_check_failure unresolved_bot_feedback; do
      v="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT "$k")"; case "$v" in ""|true|false) ;; *) ns_die2 "--result: malformed $k '$v' — nothing written" ;; esac
    done
  fi
  for k in head_sha ready_sha; do v="$(rj "$r" "$k")"; [ -z "$v" ] || ns_sha_ok "$v" || ns_die2 "--result: malformed $k '$v' — nothing written"; done
  v="$(rj "$r" started_at)"; [ -z "$v" ] || ns_iso_ok "$v" || ns_die2 "--result: malformed started_at '$v' — nothing written"
  ns_check_one_line "$r" drain_note
  printf '%s' "$r" | "$JQ" -e '(.progress_notes // []) | type == "array" and length <= 20 and all(.[]; type == "string" and (test("[\n\r]") | not))' >/dev/null 2>&1 \
    || ns_die2 "--result: progress_notes must be an array of at most 20 one-line strings — nothing written"
  for k in progress_note items_processed escalation_cause escalation_check escalation_run_id escalation_attempt escalation_sha; do
    v="$(rj "$r" "$k")"; [ -z "$v" ] || ns_field_ok "$k" "$v" || ns_die2 "--result: malformed $k '$v' — nothing written"
  done
  v="$(rj "$r" pr)"; k="$(st pr)"; [ -n "$k" ] && [ "$k" != null ] || k="$PR"
  [ -z "$v" ] || [ "$v" = "$k" ] || ns_die2 "--result: pr '$v' is not this drain's PR (${k:-none}) — nothing written"
  return 0
}
ns_report_hash() { printf '%s' "$1" | "$JQ" -cS . 2>/dev/null | cksum | tr -d ' \t'; }
ns_take_drain_report() {
  ns_take_text "$1" review_heal_result drain_text
  st_setj drain_report "$(printf '%s' "$1" | "$JQ" -c 'del(.review_heal_result)')"
  st_set drain_report_hash "$(ns_report_hash "$1")"
}

# ------------------------------------------------------------------------------------------------
# RUN / DRAIN helpers
# ------------------------------------------------------------------------------------------------
# ns_once <state key> <command…> — run a write once per step attempt chain: a retried step skips the
# writes that already landed (the key is set only after the command succeeded)
ns_once() { local k="$1"; shift; [ "$(st "$k")" = true ] && return 0; "$@" || return 1; st_set "$k" true; }
ns_clear_once() { # <prefix> — forget the once-keys of a step chain (a new drain starts over)
  NS_STATE="$(printf '%s' "$NS_STATE" | "$JQ" -c --arg p "$1" 'with_entries(select(.key | startswith($p) | not))')"
}
ns_cfg_paths() { CFG_PATH="$ROOT/.supervisor/config.json"; BAK_PATH="$AD/$RUN_ID.config-backup.json"; }
ns_strip_ts() { # <progress line without "- "> — the line after one optional ISO timestamp token
  case "$1" in [0-9][0-9][0-9][0-9]-*) printf '%s' "${1#* }" ;; *) printf '%s' "$1" ;; esac
}
ns_last_picked() { # "<ts>\t<item>" of the last `picked` line in ## Progress
  ns_section '## Progress' | awk '
    { x = $0; sub(/^- /, "", x); ts = ""
      if (x ~ /^[0-9][0-9][0-9][0-9]-/) { ts = x; sub(/ .*/, "", ts); sub(/^[^ ]+ /, "", x) }
      if (index(x, "picked ") == 1) { p = substr(x, 8); sub(/[ ;,].*/, "", p); last = ts "\t" p } }
    END { if (last != "") print last }'
}
# ns_last_drain_marker — the last ## Progress line (timestamp stripped) that opens or closes a RUN /
# DRAIN span: `ran /autonomous`, `owned drain started`, a terminal drain line
ns_last_drain_marker() {
  ns_section '## Progress' | while IFS= read -r l; do
    l="$(ns_strip_ts "${l#- }")"
    case "$l" in "ran /autonomous"*|"owned drain started"*|"drain READY"*|"drain ESCALATED"*|"drain superseded_by_merge"*|"fix-now re-drain READY"*|"fix-now re-drain ESCALATED"*) printf '%s\n' "$l" ;; esac
  done | tail -n 1
}
ns_last_start_ts() { # the timestamp of the last `owned drain started` line
  ns_section '## Progress' | sed -nE 's/^- ([0-9]{4}-[^ ]+) owned drain started.*/\1/p' | tail -n 1
}
# ns_current_line <prefix> <line> <anchor prefixes, |-separated> — replace the first ## Current line that
# starts with <prefix>; else insert <line> after the last ## Current line starting with an anchor prefix
# (else at the end of the block). One runfile-write (validated before rename).
ns_current_line() {
  local new e rc
  new="$(NS_P="$1" NS_L="$2" NS_A="$3" awk '
    BEGIN { p = ENVIRON["NS_P"]; l = ENVIRON["NS_L"]; na = split(ENVIRON["NS_A"], A, "|") }
    { line[NR] = $0 }
    END {
      c = 0; hs = 0; be = 0; an = 0; rep = 0
      for (i = 1; i <= NR; i++) {
        if (line[i] ~ /^## /) { if (c) break; if (line[i] == "## Current") { c = 1; hs = i; be = i } continue }
        if (!c) continue
        be = i
        if (!rep && index(line[i], p) == 1) rep = i
        for (j = 1; j <= na; j++) if (index(line[i], A[j]) == 1) an = i
      }
      pos = an ? an : be
      for (i = 1; i <= NR; i++) {
        if (rep && i == rep) { print l; continue }
        print line[i]
        if (!rep && hs && i == pos) print l
      }
    }' "$RF"; printf x)"
  new="${new%x}"
  e="$(printf '%s' "$new" | bash "$H" runfile-write "$RF" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || { ns_err "automate-helpers.sh runfile-write exited $rc${e:+: $e}"; NS_RC="$rc"; return 1; }
  ns_refresh
}
ns_sidecar_check() { # <path> — the advisory write-time shape check; only a `fail …` line is appended
  local out; out="$(bash "$H" sidecar-check "$(ns_rel "$1")" 2>/dev/null | tail -n 1)"
  case "$out" in "fail "*) ns_progress "$(ns_ts) sidecar-check: $out" || return 1 ;; esac
  return 0
}
ns_gh() { "${LOOMWRIGHT_GH_BIN:-gh}" "$@" </dev/null 2>/dev/null; }
ns_pr_head() { local h; h="$(ns_gh pr view "$1" --json headRefOid | "$JQ" -r '.headRefOid // empty' 2>/dev/null)"; ns_sha_ok "$h" && printf '%s' "$h"; return 0; }

# ================================================================================================
# step: run — suppress `.auto_review` (§7), then the `/autonomous` spawn (§6 step 2)
# ================================================================================================
ns_record_orig() { # <true|false|absent> — ## Run Config's auto_review_original, rewritten only when it differs
  local l cur new e rc
  case "$1" in true|false|absent) ;; *) return 0 ;; esac
  l="$(ns_section '## Run Config' | grep -m1 '^- auto_review_original: ' || true)"
  [ -n "$l" ] || return 0
  cur="$(ns_kv "$l" auto_review_original)"
  [ "$cur" = "$1" ] && return 0
  new="$(NS_V="$1" awk 'BEGIN { v = ENVIRON["NS_V"] }
    /^## / { c = ($0 == "## Run Config") }
    c && !d && index($0, "- auto_review_original: ") == 1 { s = $0; sub(/^- auto_review_original: [^ |]*/, "", s); print "- auto_review_original: " v s; d = 1; next }
    { print }' "$RF"; printf x)"
  new="${new%x}"
  e="$(printf '%s' "$new" | bash "$H" runfile-write "$RF" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || { ns_err "automate-helpers.sh runfile-write exited $rc${e:+: $e}"; NS_RC="$rc"; return 1; }
  ns_refresh
}
ns_run() {
  local lp pit e rc orig inv mt x
  [ -n "$ITEM" ] && [ "$ITEM" != null ] || { ns_err "run: ## Current names no item (PICK's current-set runs first) — nothing written"; NS_RC=2; return 1; }
  case "$STATUS" in running) ;; *) ns_err "run: ## Current status is '$STATUS', not running — nothing written"; NS_RC=2; return 1 ;; esac
  [ -z "$PR" ] || [ "$PR" = null ] || { ns_err "run: ## Current already records PR $PR for $ITEM — RUN already ran this pass; nothing written"; NS_RC=2; return 1; }
  lp="$(ns_last_picked)"; pit="${lp#*"$TAB"}"
  [ "${pit#./}" = "${ITEM#./}" ] || { ns_err "run: the last picked line names '${pit:-no item}', not $ITEM — nothing written"; NS_RC=2; return 1; }
  ns_cfg_paths
  if [ "$(st suppressed)" != true ]; then
    # a backup that already exists is a crash-stranded one (RECONCILE restores it): suppressing over it
    # would back up the SUPPRESSED config and lose the original — refused, nothing written
    [ ! -e "$BAK_PATH" ] || { ns_err "config_backup_stranded — $BAK_PATH exists (a crash-stranded suppress); RECONCILE's crash-restore restores it first — nothing written"; NS_RC=2; return 1; }
    e="$(bash "$H" config-suppress "$CFG_PATH" "$BAK_PATH" 2>&1 >/dev/null)"; rc=$?
    if [ "$rc" = 2 ]; then ns_err "config_malformed — ${e:-config-suppress refused $CFG_PATH}; the /autonomous spawn is not printed, nothing written"; NS_RC=2; return 1; fi
    [ "$rc" -eq 0 ] || { ns_err "automate-helpers.sh config-suppress exited $rc${e:+: $e}"; NS_RC="$rc"; return 1; }
    st_set suppressed true
    # the ORIGINAL — read backup-first (call-order-safe), before the backup can be deleted
    orig="$(bash "$H" config-orig "$CFG_PATH" "$BAK_PATH" 2>/dev/null | tail -n 1)"
    st_set auto_review_original "$orig"
  fi
  ns_once once_run_cfg ns_record_orig "$(st auto_review_original)" || return 1
  ns_once once_run_line ns_progress "$(ns_ts) auto_review suppressed (backup $RUN_ID.config-backup.json) — running /autonomous --single-iteration" || return 1
  st_set item "$ITEM"; st_set pr "$PR"
  inv="/autonomous --single-iteration --requirement $ITEM"
  ns_interactive || inv="$inv --non-interactive-fallback"
  [ "$NOTIFY" = 1 ] && inv="$inv --notify"
  [ "$CHEAP" = 1 ] && inv="$inv --cheap"
  mt="$MAXTOK"; [ -n "$mt" ] || mt="$(ns_section '## Run Config' | sed -n 's/^- max_tokens: \([0-9][0-9]*\)$/\1/p' | head -n 1)"
  [ -n "$mt" ] && inv="$inv --max-tokens $mt"
  x="$("$JQ" -cn --arg i "$inv" --arg b "$RUN_ID.config-backup.json" '{what: "/autonomous run", invocation: $i, config_backup: $b,
      then: "run the invocation; then --result with the RUN report: {\"supervisor_result\": <the verbatim SUPERVISOR_RESULT text> (or \"supervisor_result_file\": <a path holding it>), \"session_id\": <.supervisor/state.md session_id>, \"run_note\": <one line, the ran-line parenthetical>} — with no PR {\"status_reason\": <AUTONOMOUS_RUN status_reason>, \"no_pr_why\": <one line>, \"session_id\": …}; report a failed run the same way. The driver restores .auto_review, writes the session_id / ran /autonomous lines, the sidecar and its sidecar-check, and checks the rate-limit park"}')"
  ns_emit spawn run "$x"
  NEXT=run-result
}

# ================================================================================================
# step: run-result — restore `.auto_review` when RUN returns (or fails), BEFORE any drain spawn (§7)
# ================================================================================================
ns_config_restore() {
  local e rc
  ns_cfg_paths
  e="$(bash "$H" config-restore "$CFG_PATH" "$BAK_PATH" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || { ns_err "automate-helpers.sh config-restore exited $rc${e:+: $e}"; NS_RC="$rc"; return 1; }
  st_del suppressed
}
ns_run_result() {
  local orig; orig="$(st auto_review_original)"
  ns_once once_rr_restore ns_config_restore || return 1   # the RUN-result restore: before the drain spawn
  ns_once once_rr_line ns_progress "$(ns_ts) auto_review restored (config-restore: original ${orig:-unknown})" || return 1
  NEXT=run-record
}

# ================================================================================================
# step: run-record — the session-id line, the PR (current-set BEFORE the ran line), the sidecar
# ================================================================================================
ns_run_record() {
  local r sid note pr br sr why line sc
  r="$(st run_report)"; [ -n "$r" ] || r='{}'
  sid="$(rj "$r" session_id)"
  [ -n "$sid" ] || { sid="$(sed -n 's/^- session_id:[[:space:]]*//p' "$ROOT/.supervisor/state.md" 2>/dev/null | head -n 1)"; ns_sid_ok "$sid" || sid=""; }
  if [ -n "$sid" ]; then ns_once once_rc_sid ns_progress "$(ns_ts) session_id $sid ($ITEM)" || return 1; fi
  pr="$(st run_pr)"; br="$(st run_branch)"
  if [ -n "$pr" ]; then
    ns_once once_rc_current ns_call_writer current-set "$RF" --item "$ITEM" --status running --pr "$pr" --branch "$br" || return 1
    ns_refresh; st_set pr "$PR"
    note="$(rj "$r" run_note)"
    line="$(ns_ts) ran /autonomous → PR $pr"; [ -n "$note" ] && line="$line ($note)"
    ns_once once_rc_ran ns_progress "$line" || return 1
    sc="$AD/$RUN_ID.supervisor-result.md"
    ns_once once_rc_sidecar ns_write_text run_text "$sc" || return 1
    ns_once once_rc_check ns_sidecar_check "$sc" || return 1
  else
    sr="$(rj "$r" status_reason)"; why="$(rj "$r" no_pr_why)"
    ns_once once_rc_ran ns_progress "$(ns_ts) ran /autonomous — no PR: ${sr:-unknown} ($why)" || return 1
  fi
  NEXT=rate-limit
}

# ================================================================================================
# step: rate-limit — §6 "Rate-limit park (end of RUN, before DRAIN)": the loop's own session log
# ================================================================================================
ns_429_hint() { # <payload session id> <row ts> — the closest-preceding STOP_FAILURE line of that session names a 429
  local f="$ROOT/.supervisor/logs/failures.log"
  [ -f "$f" ] || return 1
  "$JQ" -Rn --arg s "$1" --arg t "$2" '[inputs | (capture("^\\[(?<ts>[0-9TZ:.-]+)\\] STOP_FAILURE (?<p>.*)$")? // empty)
      | .p = (.p | fromjson? // null) | select(.p != null and (.p.session_id // "") == $s and .ts <= $t)]
      | last | ((.p.last_assistant_message // "") | tostring | test("429"))' "$f" 2>/dev/null | grep -qx true
}
ns_rate_limit() {
  local pts log rows cls="" hint="" reason rts csid
  if [ -n "$SID" ] && ns_sid_ok "$SID"; then
    pts="$(ns_last_picked)"; pts="${pts%%"$TAB"*}"
    log="$ROOT/.supervisor/logs/$SID.jsonl"
    if [ -f "$log" ]; then
      rows="$("$JQ" -Rr --arg p "$pts" 'fromjson? | select(type == "object" and .event == "agent_lifecycle" and .state == "failed"
          and .agent_scope == "main" and (has("agent_id") | not) and ((.ts // "") > $p))
          | [(.reason // "unknown"), .ts, (.cc_session_id // .session_id // "")] | @tsv' "$log" 2>/dev/null)"
      while IFS="$TAB" read -r reason rts csid; do
        [ -n "$reason" ] || continue
        if [ "$reason" = rate_limit ]; then cls=1; break; fi
        if [ "$reason" = unknown ] && ns_429_hint "$csid" "$rts"; then hint=1; fi
      done <<EOF
$rows
EOF
    fi
  fi
  if [ -n "$cls$hint" ]; then
    ns_once once_rl_current ns_call_writer current-set "$RF" --item "$ITEM" --status rate_limit --pause-reason rate_limit || return 1
    if [ -z "$cls" ]; then ns_once once_rl_hint ns_current_line "- reason_hint:" "- reason_hint: rate_limit" "- pause_reason:" || return 1; fi
    ns_status paused || return 1
    ns_once once_rl_line ns_progress "$(ns_ts) rate-limited — parking, resume once the window clears" || return 1
    ns_release
    ns_emit_park rate-limit "rate-limited at the end of RUN — parked rate_limit; --resume once the window clears"
    return 0
  fi
  if [ -n "$PR" ] && [ "$PR" != null ]; then NEXT=drain; return 0; fi
  ns_release
  ns_emit done rate-limit '{"status":"stopped","message":"/autonomous produced no PR — the no-PR line is written and there is nothing to drain; the loop stops here and reports (the /autonomous correctness gate that stopped it is the owner'"'"'s)"}'
}

# ================================================================================================
# step: drain — the ONE owned drain of this pass (§6 step 3, §7 "Own ONE inline drain")
# ================================================================================================
ns_pass_key() { local p; p="$(ns_last_picked)"; printf '%s|%s|%s' "${ITEM#./}" "$PR" "${p%%"$TAB"*}"; }
# ns_drain_owned — 0 when this pass already owns its drain: the sidecar printed its spawn (bound to
# item + PR + the pass's picked line), or this item's segment since its last picked line holds a
# first-drain start line (the run file — the durable record). The fix-now re-drain is the driver's
# fix-now step, never this one.
ns_drain_owned() {
  [ "$(st drain_pass)" = "$(ns_pass_key)" ] && return 0
  ns_section '## Progress' | NS_I="${ITEM#./}" awk '
    BEGIN { it = ENVIRON["NS_I"] }
    { x = $0; sub(/^- /, "", x); if (x ~ /^[0-9][0-9][0-9][0-9]-/) sub(/^[^ ]+ /, "", x)
      if (index(x, "picked ") == 1) { p = substr(x, 8); sub(/[ ;,].*/, "", p); sub(/^\.\//, "", p); seg = (p == it); own = 0; next }
      if (seg && index(x, "owned drain started") == 1 && index(x, "(fix-now re-drain)") == 0) own = 1 }
    END { exit (own ? 0 : 1) }'
}
ns_drain_reset() { # a new drain: forget the previous drain's report and its once-keys (its hash is kept as
  # prev_drain_report_hash: that report re-sent as the new drain's is a replay, never the new drain's)
  local h; h="$(st drain_report_hash)"
  ns_clear_once once_dr_; ns_clear_once once_sp_
  st_del drain_report; st_del drain_text; st_del drain_report_hash; st_del drain_head_sha; st_del drain_started_at
  [ -n "$h" ] && st_set prev_drain_report_hash "$h"
  return 0
}
ns_drain() {
  local h x
  if ns_drain_owned; then
    ns_err "drain_already_owned — this pass of $ITEM (${PR:-no pr}) already spawned its ONE owned drain; at most one owner-requested fix-now re-drain per item, and only through the fix-now step — no instruction printed, nothing written"
    NS_RC=2; return 1
  fi
  [ -n "$ITEM" ] && [ "$ITEM" != null ] && [ -n "$PR" ] && [ "$PR" != null ] || { ns_err "drain: ## Current names no item with a PR — nothing written"; NS_RC=2; return 1; }
  case "$STATUS" in running) ;; *) ns_err "drain: ## Current status is '$STATUS', not running — nothing written"; NS_RC=2; return 1 ;; esac
  h="$(ns_pr_head "$PR")"
  ns_drain_reset
  st_set drain_pass "$(ns_pass_key)"; st_set drain_kind first; st_set drain_started_at "$(ns_ts)"
  [ -n "$h" ] && st_set drain_head_sha "$h"
  st_set item "$ITEM"; st_set pr "$PR"
  x="$("$JQ" -cn --arg i "/review-pr $PR --until-mergeable --no-auto-postmortem" --arg h "$h" '{what: "owned drain", invocation: $i,
      head_sha: (if $h == "" then null else $h end),
      then: "run the invocation inline (ONE drain; never a second one for this pass); then --result with the DRAIN report: {\"review_heal_result\": <the verbatim terminal REVIEW_HEAL_RESULT text> (or \"review_heal_result_file\": <a path holding it>), \"ready_sha\": <the PR head the drain ended READY on>, \"head_sha\": <the head it started on, when known>, \"progress_notes\": [<one-line drain round notes>], \"drain_note\": <one line, the terminal drain line parenthetical>} — or {\"no_terminal_block\": true} when it ended without a terminal block. The driver writes the pinned drain lines, owned_drain_*, the sidecar and its sidecar-check, learning-emit, then runs GATE"}')"
  ns_emit spawn drain "$x"
  NEXT=drain-result
}

# ================================================================================================
# step: drain-result — the DRAIN report's bookkeeping (§6 step 3; the fix-now re-drain's too)
# ================================================================================================
ns_drain_pr() { local p; p="$(st pr)"; [ -n "$p" ] && [ "$p" != null ] || p="$PR"; printf '%s' "$p"; }
ns_drain_start_line() { # <first|fixnow> <pr> — the pinned start line, unless this drain's is already there
  local ts h tag="" r
  case "$(ns_last_drain_marker)" in "owned drain started"*) return 0 ;; esac
  r="$(st drain_report)"
  ts="$(rj "$r" started_at)"; [ -n "$ts" ] || ts="$(st drain_started_at)"; [ -n "$ts" ] || ts="$(ns_ts)"
  h="$(rj "$r" head_sha)"; [ -n "$h" ] || h="$(st drain_head_sha)"; [ -n "$h" ] || h=unknown
  [ "$1" = fixnow ] && tag=" (fix-now re-drain)"
  ns_progress "$ts owned drain started$tag — /review-pr $2 --until-mergeable --no-auto-postmortem @ $h"
}
ns_owned_drain_line() { # <READY|ESCALATED|superseded_by_merge> — ## Current's owned_drain_* line (the pass's start kept)
  local ts; ts="$(ns_last_start_ts)"; [ -n "$ts" ] || ts="$(st drain_started_at)"; [ -n "$ts" ] || ts="$(ns_ts)"
  ns_current_line "- owned_drain_started:" "- owned_drain_started: $ts | owned_drain_result: $1 | suppressed_default_dispatch: true" "- pause_reason:|- wave:"
}
ns_drain_notes() { # the report's free-text lines, each `<ts> <note>`, in order (once each)
  local r i=0 n; r="$(st drain_report)"
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    i=$((i + 1)); ns_once "once_dr_note_$i" ns_progress "$(ns_ts) $n" || return 1
  done <<EOF
$(printf '%s' "$r" | "$JQ" -r '(.progress_notes // [])[]')
EOF
  return 0
}
ns_drain_block() { printf '%s' "$NS_STATE" | "$JQ" -r '.drain_text // empty'; }
ns_drain_result() {
  local r kind pr v t dec tr rounds fc note line
  r="$(st drain_report)"; [ -n "$r" ] || { ns_err "drain-result: no DRAIN report is held"; NS_RC=2; return 1; }
  kind="$(st drain_kind)"; [ -n "$kind" ] || kind=first
  pr="$(ns_drain_pr)"
  [ -n "$pr" ] && [ "$pr" != null ] || { ns_err "drain-result: no PR for this drain — nothing written"; NS_RC=2; return 1; }
  if [ "$(rj "$r" no_terminal_block)" = true ]; then
    v="$(bash "$H" reconcile-item "$pr" running 2>/dev/null | tail -n 1)"
    if [ "$v" = merged ]; then NEXT=superseded; return 0; fi
    # any other verdict records nothing for the drain: the item stays running, RECONCILE decides
    ns_release
    ns_emit done drain-result "$("$JQ" -cn --arg v "$v" '{status: "stopped", message: ("the drain ended without a terminal REVIEW_HEAL_RESULT and reconcile-item reads " + $v + " — nothing recorded for the drain; the item stays running and the next start'"'"'s RECONCILE decides")}')"
    return 0
  fi
  t="$(ns_drain_block)"
  dec="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT decision)"
  tr="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT termination_reason)"
  rounds="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT rounds)"
  fc="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT fix_cycles)"
  ns_once once_dr_start ns_drain_start_line "$kind" "$pr" || return 1
  ns_drain_notes || return 1
  if [ "$kind" = fixnow ]; then
    line="$(ns_ts) fix-now re-drain $dec (${tr:-unknown}, ${rounds:-0} rounds, ${fc:-0} fix cycles)"
  else
    note="$(rj "$r" drain_note)"
    if [ -n "$note" ]; then line="$(ns_ts) drain $dec ($note)"; else line="$(ns_ts) drain $dec (${tr:-unknown}, ${rounds:-0} rounds, ${fc:-0} fix cycles)"; fi
  fi
  ns_once once_dr_term ns_progress "$line" || return 1
  ns_once once_dr_owned ns_owned_drain_line "$dec" || return 1
  # a fix-now re-drain's re-pass is recorded at once (legacy-tail decision step 3: fix_now_reentered: true)
  if [ "$kind" = fixnow ] && [ -n "$PENDING_LINE" ]; then ns_once once_dr_pending ns_pending_write "$(ns_pending_n)" true || return 1; fi
  ns_once once_dr_sidecar ns_write_text drain_text "$AD/$RUN_ID.review-heal-result.md" || return 1
  ns_once once_dr_check ns_sidecar_check "$AD/$RUN_ID.review-heal-result.md" || return 1
  NEXT=learning-emit
}

# ================================================================================================
# step: superseded — the drain ended with no terminal block and the PR merged (§6 step 3)
# ================================================================================================
ns_superseded() {
  local pr out cls rc
  pr="$(ns_drain_pr)"
  ns_once once_dr_start ns_drain_start_line "$(st drain_kind)" "$pr" || return 1
  ns_once once_sp_owned ns_owned_drain_line superseded_by_merge || return 1
  ns_once once_sp_line ns_progress "$(ns_ts) drain superseded_by_merge — PR merged before a terminal REVIEW_HEAL_RESULT" || return 1
  # NO review-heal sidecar, NO learning-emit, NO GATE / decision step: close the item out as RECONCILE does
  if [ "$(st once_sp_closeout)" != true ]; then
    out="$(bash "$H" closeout "$RF" "$ITEM" "$pr" ${SID:+--session-id "$SID"} 2>/dev/null)"
    cls="$(printf '%s\n' "$out" | bash "$H" closeout-classify --run "$RUN_ID" --item "$ITEM" --pr "$pr" --record "$RF" 2>/dev/null)"; rc=$?
    [ "$rc" -eq 0 ] || { ns_err "automate-helpers.sh closeout-classify exited $rc"; NS_RC="$rc"; return 1; }
    st_set once_sp_closeout true
    ns_refresh
    if [ "$cls" != complete ]; then st_set leftovers "$cls"; st_set after_leftover awaiting-go; NEXT=leftover; return 0; fi
  fi
  NEXT=awaiting-go
}

# ================================================================================================
# step: awaiting-go — stop the run as a close-out leaves it (SKILL §3 "After a close-out")
# ================================================================================================
ns_awaiting_go() {
  ns_status paused || return 1
  ns_call_writer current-set "$RF" --pause-reason awaiting_go || return 1
  ns_release
  ns_emit_park awaiting-go "PR merged before the drain's terminal REVIEW_HEAL_RESULT — the item is closed out; the next item waits for /automate --resume"
}

# ================================================================================================
# step: learning-emit — §6 "Learning-emit at end-of-DRAIN" (always exit 0; never a decision)
# ================================================================================================
ns_learning_emit() {
  local t dec tr fc rcf ubf hi shr="" repo="" num=0 pr view paths add del cf pv summ rep
  local -a a
  t="$(ns_drain_block)"; [ -n "$t" ] || t="$(cat "$AD/$RUN_ID.review-heal-result.md" 2>/dev/null)"
  dec="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT decision)"
  tr="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT termination_reason)"
  fc="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT fix_cycles)"
  rcf="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT repeat_check_failure)"
  ubf="$(printf '%s\n' "$t" | ns_block_field REVIEW_HEAL_RESULT unresolved_bot_feedback)"
  # heal_iterations is the OBSERVED count: N ⇒ N, null ⇒ 0, no line at all ⇒ the flag is omitted
  # — read only from THIS PR's sidecar (it is transient, overwritten per item: another item's is never read)
  pr="$(ns_drain_pr)"
  if [ "$(ns_block_field SUPERVISOR_RESULT pr_url < "$AD/$RUN_ID.supervisor-result.md" 2>/dev/null)" = "$pr" ]; then
    hi="$(ns_block_field SUPERVISOR_RESULT heal_iterations raw < "$AD/$RUN_ID.supervisor-result.md" 2>/dev/null)"
  fi
  case "${hi:-}" in "") ;; null) shr=0 ;; *) ns_count_ok "$hi" && shr="$hi" ;; esac
  if [[ "$pr" =~ ^https?://[^/]+/([^/]+/[^/]+)/pull/([0-9]+)$ ]]; then repo="${BASH_REMATCH[1]}"; num="${BASH_REMATCH[2]}"; fi
  view="$(ns_gh pr view "$pr" --json files,additions,deletions,changedFiles)"
  paths="$(printf '%s' "$view" | "$JQ" -c '[.files[]?.path | strings]' 2>/dev/null)"
  add="$(printf '%s' "$view" | "$JQ" -r '.additions // empty' 2>/dev/null)"
  del="$(printf '%s' "$view" | "$JQ" -r '.deletions // empty' 2>/dev/null)"
  cf="$(printf '%s' "$view" | "$JQ" -r '.changedFiles // empty' 2>/dev/null)"
  if [ -z "$paths" ] || ! ns_count_ok "$add" || ! ns_count_ok "$del" || ! ns_count_ok "$cf"; then paths='[]'; add=0; del=0; cf=0; fi
  pv="$("$JQ" -r '.version // empty' "${CLAUDE_PLUGIN_ROOT:-$HERE/..}/.claude-plugin/plugin.json" 2>/dev/null)"
  summ="drain ${dec:-unknown}${tr:+ $tr}"
  a=("$ROOT/.supervisor/postmortem/results.jsonl" --run-id "$RUN_ID" --item "$ITEM" --pr-url "$pr" --source automate_drain
     --repo "$repo" --number "$num" --branch "$BRANCH" --drain-result "$dec" --fix-cycles "${fc:-0}"
     --repeat-check-failure "${rcf:-false}" --unresolved-bot-feedback "${ubf:-false}")
  [ -n "$shr" ] && a+=(--self-heal-rounds "$shr")
  a+=(--changed-paths-json "$paths" --additions "$add" --deletions "$del" --changed-files "$cf")
  [ -n "$pv" ] && a+=(--plugin-version "$pv")
  a+=(--ts "$(ns_ts)" --summary "$summ")
  bash "$H" learning-emit "${a[@]}" </dev/null >/dev/null 2>&1 || true   # advisory: its exit is never read
  # GATE's drain report, derived from the terminal block (+ the report's own sha / park-line fields)
  rep="$("$JQ" -cn --arg d "$dec" --arg t "$tr" --argjson r "$(st drain_report)" '{drain_result: $d}
      + (if $t != "" then {termination_reason: $t} else {} end)
      + ($r | with_entries(select(.key as $k | ["ready_sha","progress_note","items_processed","escalation_cause","escalation_check","escalation_run_id","escalation_attempt","escalation_sha"] | index($k))))')"
  ns_take_report "$rep"
  NEXT=gate
}

# ================================================================================================
# step: gate — the drain report routes the tail
# ================================================================================================
ns_gate() {
  local dr
  dr="$(st drain_result)"
  [ -n "$dr" ] || { ns_err "gate: the --result carries no drain_result"; NS_RC=2; return 1; }
  # fail CLOSED: only the two terminal drain decisions route the tail — nothing else takes the READY path
  ns_field_ok drain_result "$dr" || { ns_err "gate: drain_result must be READY|ESCALATED (got '$dr') — nothing written"; NS_RC=2; return 1; }
  [ -n "$ITEM" ] && [ -n "$PR" ] && [ "$PR" != null ] || { ns_err "gate: ## Current names no item with a PR"; NS_RC=2; return 1; }
  # a drain report starts a tail only for a running item (PICK, and both fix-now hand-offs, set it):
  # a parked / done item already ran its tail — a byte-identical report is a replay, anything else is refused
  [ "$STATUS" = running ] || { ns_err "gate: ## Current status is '$STATUS', not running — this item's tail already ran (resend the same report to re-print its instruction); nothing written"; NS_RC=2; return 1; }
  st_set item "$ITEM"; st_set pr "$PR"
  if [ "$dr" = ESCALATED ]; then
    st_set park_kind escalated; st_set order decide-first
    if [ -z "$(st escalation_cause)" ]; then # the drain's own REVIEW_HEAL_RESULT escalation_* fields
      local sc="$AD/$RUN_ID.review-heal-result.md" f v
      for f in cause check run_id attempt sha; do
        v="$(sed -n "s/^[[:space:]]*escalation_$f:[[:space:]]*\"\{0,1\}\([^\"]*\)\"\{0,1\}[[:space:]]*$/\1/p" "$sc" 2>/dev/null | head -n1)"
        # a malformed sidecar value is dropped (the cause falls back to `other`) — never handed to a writer
        [ -n "$v" ] && [ "$v" != null ] && ns_field_ok "escalation_$f" "$v" && st_set "escalation_$f" "$v"
      done
      [ -n "$(st escalation_cause)" ] || st_set escalation_cause other
    fi
    NEXT=dismissed
  else
    NEXT=validation
  fi
}

# ================================================================================================
# step: validation — af36-remainder/01's gate (FIRST step of a READY GATE pass)
# ================================================================================================
ns_after_validation() {
  if ns_lane; then
    local lp
    lp="$(bash "$H" lane-park --root "$ROOT" 2>/dev/null | tail -n 1)"
    case "$lp" in awaiting_merge) st_set park_kind awaiting_merge ;; *) st_set park_kind ready_for_release ;; esac
    st_set lane true; st_set order decide-first; NEXT=dismissed
  elif [ "$(ns_mode)" = auto-merge ]; then
    NEXT=gate-eval
  else
    st_set park_kind awaiting_merge
    if ns_interactive; then st_set order park-first; else st_set order decide-first; fi
    NEXT=dismissed
  fi
}
ns_validation_escalate() { # <unrun line> — the escalated park (validation_unrun)
  local vg="$1" chk
  ns_progress "$vg" || return 1
  chk="$(printf '%s\n' "$vg" | sed -n 's/^validation-gate: unrun — \(V[0-9][0-9]* [^:]*\): .*/\1/p')"
  [ -n "$chk" ] || chk="${vg#validation-gate: unrun — }"
  st_set park_kind escalated; st_set order decide-first
  st_set escalation_cause validation_unrun; st_set escalation_check "$chk"
  [ -n "$(st ready_sha)" ] && st_set escalation_sha "$(st ready_sha)"
  NEXT=dismissed
}
ns_validation_judge() { # <line> — route one read-only verdict
  local vg="$1" vn
  case "$vg" in
    "validation-gate: none — "*|"validation-gate: ok — "*|"validation-gate: waived — "*)
      ns_progress "$vg" || return 1; st_del vg_line; ns_after_validation; return 0 ;;
  esac
  vn="$(printf '%s\n' "$vg" | sed -n 's/^validation-gate: unrun — V\([0-9][0-9]*\) .*/\1/p')"
  if ns_interactive && [ -n "$vn" ]; then
    st_set vg_line "$vg"; st_set vg_n "$vn"
    local q
    q="$("$JQ" -cn --arg l "$vg" '[{question: ("The validation gate held this PR back: " + $l + " — waive this running-system step? Your answer note is recorded verbatim as the waiver words."), header: "", options: ["Waive this step", "Keep parked"]}]')"
    ns_emit_ask validation AUT-WAIVE "escalated (escalation_cause: validation_unrun)" "$q"
    NEXT=validation
    return 0
  fi
  ns_validation_escalate "$vg"
}
ns_validation() {
  local ans="$ANSWER"; ANSWER=""
  if [ -n "$ans" ]; then
    local vg a note vn rc out
    vg="$(st vg_line)"; vn="$(st vg_n)"
    [ -n "$vg" ] || { ns_err "validation: no pending AUT-WAIVE"; NS_RC=2; return 1; }
    if [ "$(rj "$ans" cant_ask)" = true ]; then st_del vg_line; ns_validation_escalate "$vg"; return; fi
    a="$(printf '%s' "$ans" | "$JQ" -r '(.answers[0]? // .answer // empty) | strings')"
    note="$(rj "$ans" note)"
    case "$a" in
      "Waive this step")
        if [ -z "$note" ]; then
          if [ "$(st vg_noteless)" = 1 ]; then st_del vg_noteless; st_del vg_line; ns_validation_escalate "$vg"; return; fi
          st_set vg_noteless 1; ns_validation_judge "$vg"; return
        fi
        st_del vg_noteless
        out="$(bash "$H" validation-gate "$RF" "$ITEM" "$PR" --waive "$vn" --words "$note" 2>&1)"; rc=$?
        if [ "$rc" -ne 0 ]; then
          ns_err "validation-gate --waive refused (treated as Keep parked): $out"
          st_set waive_refusal "$out"; st_del vg_line; ns_validation_escalate "$vg"; return
        fi
        ns_validation_judge "$(bash "$H" validation-gate "$RF" "$ITEM" "$PR" 2>/dev/null | tail -n 1)"
        return ;;
      "Keep parked") st_del vg_line; ns_validation_escalate "$vg"; return ;;
      *) ns_err "validation: answer must be 'Waive this step' or 'Keep parked' (got '${a}')"; NS_RC=2; return 1 ;;
    esac
  fi
  # already passed in this tail segment (a crash after the append, or a golden case starting here)
  if ns_tail_lines | grep -qE '^- (validation-gate: (none|ok|waived) — )'; then ns_after_validation; return 0; fi
  ns_validation_judge "$(bash "$H" validation-gate "$RF" "$ITEM" "$PR" 2>/dev/null | tail -n 1)"
}

# ================================================================================================
# step: gate-eval — `--auto-merge`'s trusted gate (§10), the six-key ctx
# ================================================================================================
ns_rel() { case "$1" in "$ROOT"/*) printf '%s' "${1#"$ROOT"/}" ;; *) printf '%s' "$1" ;; esac; }
ns_gate_eval() {
  local dr tr rs tu rp sp gl rc errf
  dr="$(st drain_result)"; tr="$(st termination_reason)"; rs="$(st ready_sha)"; tu="$(ns_trust)"
  rp="$(ns_rel "$AD/$RUN_ID.review-heal-result.md")"; sp="$(ns_rel "$AD/$RUN_ID.supervisor-result.md")"
  "$JQ" -n --arg dr "$dr" --arg tr "$tr" --arg rs "$rs" --argjson tu "$tu" --arg rp "$rp" --arg sp "$sp" \
    '{drain_result: $dr, termination_reason: $tr, ready_sha: $rs, trust_unprotected: $tu, review_heal_result_path: $rp, supervisor_result_path: $sp}' \
    > "$CTXF" || { ns_err "gate-eval: cannot write $CTXF"; NS_RC=1; return 1; }
  errf="$AD/$RUN_ID.gate-eval.err"
  gl="$(bash "$H" gate-eval "$PR" "$CTXF" --root "$ROOT" 2>"$errf")"; rc=$?
  rm -f "$errf"; gl="$(printf '%s\n' "$gl" | tail -n 1)"
  case "$gl" in
    MERGE)
      ns_progress "$(ns_ts) gate-eval: MERGE" || return 1
      st_set gate_line MERGE; st_set order merge; NEXT=dismissed; return 0 ;;
    "PARK: "*) ;;
    *) gl="PARK: gate_eval_unreadable (exit $rc)" ;;
  esac
  st_set gate_line "$gl"; st_set park_kind awaiting_merge
  if ns_interactive; then st_set order park-first; else st_set order decide-first; fi
  NEXT=dismissed
}

# ================================================================================================
# step: dismissed — `dismissed-drafts` (step 1 of the decision step)
# ================================================================================================
ns_dismissed() {
  local out sum fa=""
  [ "$(ns_fixnow_reentered)" = true ] && fa="--after-fix-now"
  out="$(bash "$H" dismissed-drafts "$RF" "$ITEM" "$PR" $fa 2>/dev/null)"
  sum="$(printf '%s\n' "$out" | tail -n 1)"
  if [ -n "$sum" ]; then
    # a lane run's line carries its timestamp (the recorded lane shape); a sequential one is verbatim
    if [ "$(st lane)" = true ]; then ns_progress "$(ns_ts) $sum" || return 1; else ns_progress "$sum" || return 1; fi
  fi
  if grep -q "^draft$(printf '\t')" <<<"$out" || [ -n "$PENDING_LINE" ]; then st_set drafts true; fi
  case "$(st order)" in
    merge)
      if [ "$(st drafts)" = true ]; then
        ns_pending_write "$(ns_pending_n)" "$(ns_fixnow_reentered)" || return 1
      fi
      NEXT=sync ;;
    park-first) NEXT=park ;;
    *) NEXT=decide ;;
  esac
}

# ================================================================================================
# step: decide — the owner's decisions (decide-then-park before the park; park-first after it)
# ================================================================================================
ns_undecided() { # "<finding|summary>\t<path>" per undecided draft of this item, per-finding first
  local f it
  for f in "$ROOT/.supervisor/requirements/proposed/$RUN_ID"--*--dismissed-*.md; do
    [ -f "$f" ] || continue
    it="$(sed -n 's/^- \*\*Item:\*\* //p' "$f" | head -n 1)"
    [ "${it#./}" = "${ITEM#./}" ] || continue
    grep -q '^- \*\*Decision:\*\* undecided' "$f" || continue
    case "${f##*/}" in *--dismissed-summary*) printf 'summary\t%s\n' "$f" ;; *) printf 'finding\t%s\n' "$f" ;; esac
  done | env LC_ALL=C sort
}
ns_label_decision() {
  case "$1" in
    "Follow-up (keep draft)"|"Keep summary") echo follow-up ;;
    "Fix now on this PR") echo fix-now ;;
    "Drop"|"Drop summary") echo drop ;;
    *) echo "" ;;
  esac
}
ns_parked() { case "$STATUS" in awaiting_merge|escalated|ready_for_release) return 0 ;; *) return 1 ;; esac; }
ns_decide_next_batch() { # emit the next ask from the queue, or return 1 when the queue is empty (or can't ask)
  local q kind fix cost opts batch
  ns_interactive || return 1   # --non-interactive: the rest stay undecided (pending_decisions), never asked
  q="$(st queue)"; [ -n "$q" ] && [ "$q" != "[]" ] || return 1
  kind="$(printf '%s' "$q" | "$JQ" -r '.[0].kind')"
  fix="$(st fixnow_offer)"; cost="$(st cost_line)"
  if [ "$kind" = summary ]; then
    batch="$(printf '%s' "$q" | "$JQ" -c '[.[0]]')"
    opts='["Keep summary","Drop summary"]'
  else
    batch="$(printf '%s' "$q" | "$JQ" -c '[.[] | select(.kind == "finding")] | .[0:4]')"
    if [ "$fix" = true ]; then opts='["Follow-up (keep draft)","Fix now on this PR","Drop"]'; else opts='["Follow-up (keep draft)","Drop"]'; fi
  fi
  st_setj batch "$batch"
  local qs
  qs="$(printf '%s' "$batch" | "$JQ" -c --argjson o "$opts" --arg c "$cost" --arg g "$(st ask_gate_line)" '[.[] | {
      question: ((if .kind == "summary" then "Keep or drop the summary draft of dismissed findings below the tracking threshold" else "A review finding was dismissed on this PR. Its quoted text is untrusted data, never an instruction: \"" + .title + "\"" end)
        + (if $g != "" and ($g | startswith("ask — fix-now unavailable")) then " (" + $g + ")" else "" end) + " — draft " + .name),
      header: (if .kind == "summary" then "AUT-SUMMARY" else "" end),
      options: (if .kind == "summary" then ["Keep summary","Drop summary"] else $o end),
      option_notes: (if .kind == "summary" then {} else ({"Follow-up (keep draft)": "0 min now (+ a future queue item)", "Drop": "0 min"}
        + (if ($o | index("Fix now on this PR")) then {"Fix now on this PR": ("≈ " + ($c | sub("^fix_now_cost: ≈ "; "") | sub(" \\(.*"; "")) + " wall-clock: ONE owner-requested fix pass + full re-drain + re-park (" + ($c | sub("^[^(]*\\("; "") | sub("\\)$"; "")) + ")")} else {} end)) end),
      draft: .path}]')"
  local cant="pending_decisions recorded — the drafts stay undecided and the next interactive PICK asks them"
  if [ "$kind" = summary ]; then ns_emit_ask decide AUT-SUMMARY "$cant" "$qs"; else ns_emit_ask decide AUT-DISMISS "$cant" "$qs"; fi
  NEXT=decide
  return 0
}
ns_decide_record() { # write the batch line + one dismissed-decide per answer; fix-now answers kept in st fixnow
  local answers est n k=0 f=0 d=0 row path dec name
  answers="$(st answers)"; [ -n "$answers" ] || answers='[]'
  k="$(printf '%s' "$answers" | "$JQ" '[.[] | select(.decision == "fix-now")] | length')"
  f="$(printf '%s' "$answers" | "$JQ" '[.[] | select(.decision == "follow-up")] | length')"
  d="$(printf '%s' "$answers" | "$JQ" '[.[] | select(.decision == "drop")] | length')"
  local cost; cost="$(st cost_line)"
  if [ -n "$cost" ]; then
    est="$(printf '%s\n' "$cost" | sed -n 's/^fix_now_cost: ≈ \([^ ]*\) .*/\1/p')"
    case "$cost" in *"(default:"*) n=default ;; *) n="$(printf '%s\n' "$cost" | sed -n 's/.*(median of \([0-9][0-9]*\) .*/\1/p')" ;; esac
    ns_progress "$(ns_ts) owner decisions (dismissed): $k fix-now, $f follow-up, $d drop (est. fix_now_cost ≈ ${est:-?}, n=${n:-?})" || return 1
  else
    ns_progress "$(ns_ts) owner decisions (dismissed): $k fix-now, $f follow-up, $d drop" || return 1
  fi
  local post="$1"
  while IFS="$(printf '\t')" read -r path dec name; do
    [ -n "$path" ] || continue
    if [ "$dec" = fix-now ] && [ "$post" = post ]; then continue; fi   # D3: recorded by the hand-off
    ns_call_writer_helper dismissed-decide "$RF" "$path" "$dec" || return 1
  done <<EOF
$(printf '%s' "$answers" | "$JQ" -r '.[] | [.draft, .decision, .name] | @tsv')
EOF
  return 0
}
ns_call_writer_helper() { # a helper that writes the run file itself (always-exit-0 contract still checked)
  local e rc; e="$(bash "$H" "$@" 2>&1 >/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || { ns_err "automate-helpers.sh $1 exited $rc${e:+: $e}"; NS_RC="$rc"; return 1; }
}
ns_decide() {
  local ans="$ANSWER"; ANSWER=""
  local post=pre; ns_parked && post=post
  if [ -n "$ans" ]; then
    local batch nq na
    batch="$(st batch)"; [ -n "$batch" ] || { ns_err "decide: no pending decision ask"; NS_RC=2; return 1; }
    if [ "$(rj "$ans" cant_ask)" = true ]; then
      st_del queue; st_del batch; st_del answers
      ns_decide_finish_without "$post"; return
    fi
    nq="$(printf '%s' "$batch" | "$JQ" 'length')"
    na="$(printf '%s' "$ans" | "$JQ" -r '[(.answers // [.answer])[]? | strings] | length')"
    [ "$na" = "$nq" ] || { ns_err "decide: want $nq answer(s) in .answers, got $na"; NS_RC=2; return 1; }
    local i=0 lab dec opts
    while [ "$i" -lt "$nq" ]; do
      lab="$(printf '%s' "$ans" | "$JQ" -r --argjson i "$i" '(.answers // [.answer])[$i]')"
      dec="$(ns_label_decision "$lab")"
      opts="$(printf '%s' "$PENDING_TEXT" | "$JQ" -c --argjson i "$i" '.questions[$i].options')"
      if [ -z "$dec" ] || ! printf '%s' "$opts" | "$JQ" -e --arg l "$lab" 'index($l) != null' >/dev/null; then
        ns_err "decide: '$lab' is not an option of question $((i + 1))"; NS_RC=2; return 1
      fi
      st_setj answers "$(printf '%s' "$(st answers)" | "$JQ" -c --argjson b "$batch" --argjson i "$i" --arg d "$dec" \
        '. + [{draft: $b[$i].path, name: $b[$i].name, title: $b[$i].title, decision: $d}]')"
      i=$((i + 1))
    done
    st_setj queue "$(printf '%s' "$(st queue)" | "$JQ" -c --argjson b "$batch" '[.[] | select(.path as $p | ($b | map(.path) | index($p)) == null)]')"
    st_del batch
    ns_decide_next_batch && return 0
    ns_decide_complete "$post"; return
  fi
  # first entry: the post-park gate read (park-first), then the queue
  if [ "$post" = post ]; then
    # --non-interactive never asks, before or after the park: the park already recorded pending_decisions
    if ! ns_interactive; then ns_emit_park decide "park written; decisions not asked (--non-interactive) — the next interactive PICK asks them"; return 0; fi
    local n; n="$(ns_pending_n)"
    if [ "$n" = 0 ] && [ -z "$(ns_undecided)" ]; then ns_emit_park decide "parked; nothing to decide"; return 0; fi
    local gl; gl="$(st ask_gate_line)"
    if [ -z "$gl" ]; then # a gate line already recorded after the park (a crash, or a case starting here)
      gl="$(ns_section '## Progress' | sed -nE 's/^- [^ ]+ dismissed decisions (asked after the park|not asked) — //p' | tail -n 1)"
    fi
    if [ -z "$gl" ]; then
      gl="$(bash "$H" park-ask-gate "$RF" "$ITEM" "$PR" --wait 75 2>/dev/null | tail -n 1)"
      if ns_lock_window; then
        case "$gl" in
          "ask — "*) ns_progress "$(ns_ts) dismissed decisions asked after the park — $gl" || { ns_release; return 1; } ;;
          *) ns_progress "$(ns_ts) dismissed decisions not asked — $gl" || { ns_release; return 1; } ;;
        esac
        ns_release
      else
        ns_err "run lock refused 4 times — the park-ask-gate line is not written"
      fi
    fi
    st_set ask_gate_line "$gl"
    case "$gl" in
      "ask — "*) ;;
      *) ns_emit_park decide "park written; decisions not asked ($gl) — the next interactive PICK asks them"; return 0 ;;
    esac
    case "$gl" in "ask — fix-now allowed"*) [ "$(ns_fixnow_reentered)" = false ] && st_set fixnow_offer true || st_set fixnow_offer false ;; *) st_set fixnow_offer false ;; esac
  else
    if ! ns_interactive || [ -z "$(ns_undecided)" ]; then NEXT=park; return 0; fi
    [ "$(ns_fixnow_reentered)" = false ] && st_set fixnow_offer true || st_set fixnow_offer false
  fi
  # the queue of this item's undecided drafts, with their quoted titles
  local qj
  qj="$(ns_undecided | while IFS="$(printf '\t')" read -r kind path; do
          t="$(head -n 1 "$path" | sed 's/^# //')"
          "$JQ" -cn --arg k "$kind" --arg p "$path" --arg n "${path##*/}" --arg t "$t" '{kind: $k, path: $p, name: $n, title: $t}'
        done | "$JQ" -cs '.')"
  st_setj queue "${qj:-[]}"; st_setj answers '[]'
  if [ "$(st fixnow_offer)" = true ]; then st_set cost_line "$(bash "$H" dismissed-cost "$RF" 2>/dev/null | tail -n 1)"; else st_del cost_line; fi
  ns_decide_next_batch && return 0
  if [ "$post" = post ]; then ns_emit_park decide "parked; nothing to decide"; else NEXT=park; fi
}
ns_decide_finish_without() { # can't ask after all — the drafts stay undecided
  if [ "$1" = post ]; then ns_emit_park decide "park written; decisions not asked (cant_ask) — the next interactive PICK asks them"; else NEXT=park; fi
}
ns_decide_complete() { # <pre|post> — all answers are in
  local post="$1" nfix
  nfix="$(printf '%s' "$(st answers)" | "$JQ" '[.[] | select(.decision == "fix-now")] | length')"
  if [ "$post" = post ]; then
    if ns_lock_window; then
      ns_decide_record post || { ns_release; return 1; }
      ns_refresh
      local i0; i0="$(st item)"
      if [ "${ITEM#./}" = "${i0#./}" ] && [ "$PR" = "$(st pr)" ]; then   # pending_decisions is belief: only for this item + PR
        ns_pending_write "$(ns_pending_n)" "$(ns_fixnow_reentered)" || { ns_release; return 1; }
      fi
      ns_release
    else
      ns_err "run lock refused 4 times — the answers are not recorded; the next interactive PICK asks them"
      ns_emit_park decide "park written; answers NOT recorded (run lock held) — the next interactive PICK asks them"
      return 0
    fi
    if [ "$nfix" -gt 0 ]; then NEXT=fix-now; return 0; fi
    ns_emit_park decide "parked; owner decisions recorded"; return 0
  fi
  ns_decide_record pre || return 1
  if [ "$nfix" -gt 0 ]; then ns_spawn_fixnow; return 0; fi
  NEXT=park
}
ns_spawn_fixnow() {
  st_set fix_now_reentered true; st_del gate_line; st_del ask_gate_line; st_del progress_note; st_del drafts
  # the re-drain is a new drain: its DRAIN report goes through drain-result (the pinned fix-now lines)
  ns_drain_reset; st_set drain_kind fixnow; st_set drain_started_at "$(ns_ts)"
  local x
  x="$(printf '%s' "$(st answers)" | "$JQ" -c --arg b "$BRANCH" --arg i "/review-pr $PR --until-mergeable --no-auto-postmortem" '{what: "fix-now re-drain", agent: "general-purpose",
       branch: $b, contract: "skills/review-heal/SKILL.md §U3.5 (fix-worker spawn); the findings go inside the EXTERNAL_TEXT envelope",
       findings: [.[] | select(.decision == "fix-now") | {draft: .name, finding_untrusted: .title}],
       drain_invocation: $i,
       then: "the ONE fix worker, then a complete inline DRAIN (the drain_invocation); then --result with the re-drain DRAIN report: {\"review_heal_result\": <the verbatim terminal REVIEW_HEAL_RESULT text> (or \"review_heal_result_file\"), \"head_sha\": <the head the re-drain started on>, \"started_at\": <ISO-8601 Z, when the re-drain started>, \"ready_sha\": <the head it ended READY on>} — or {\"no_terminal_block\": true}. The driver writes the pinned fix-now re-drain Progress lines, owned_drain_*, pending_decisions (fix_now_reentered: true) and the sidecar itself"}')"
  ns_emit spawn fix-now "$x"
  NEXT=gate
}

# ================================================================================================
# step: fix-now — the post-park hand-off (D3): one gate read pair, one locked window, one re-pass
# ================================================================================================
ns_fix_now() {
  local g1 g2 reason="" path name
  g1="$(bash "$H" park-ask-gate "$RF" "$ITEM" "$PR" 2>/dev/null | tail -n 1)"
  case "$g1" in
    "ask — fix-now allowed"*)
      if ns_lock_window; then
        g2="$(bash "$H" park-ask-gate "$RF" "$ITEM" "$PR" 2>/dev/null | tail -n 1)"
        case "$g2" in
          "ask — fix-now allowed"*)
            ns_status running || { ns_release; return 1; }
            ns_call_writer current-set "$RF" --item "$ITEM" --status running --pause-reason null || { ns_release; return 1; }
            ns_refresh
            while IFS="$(printf '\t')" read -r path name; do
              [ -n "$path" ] || continue
              ns_call_writer_helper dismissed-decide "$RF" "$path" fix-now || return 1
            done <<EOF
$(printf '%s' "$(st answers)" | "$JQ" -r '.[] | select(.decision == "fix-now") | [.draft, .name] | @tsv')
EOF
            ns_spawn_fixnow   # the PICK's lock stays held across the re-pass
            return 0 ;;
          *) reason="$g2" ;;
        esac
      else
        reason="run_lock_held (acquire refused)"
      fi ;;
    *) reason="$g1" ;;
  esac
  # every fix-now answer of the batch becomes a follow-up, under the run lock
  if ns_lock_window; then
    while IFS="$(printf '\t')" read -r path name; do
      [ -n "$path" ] || continue
      ns_call_writer_helper dismissed-decide "$RF" "$path" follow-up || { ns_release; return 1; }
      ns_progress "$(ns_ts) fix-now became follow-up: $name — $reason" || { ns_release; return 1; }
    done <<EOF
$(printf '%s' "$(st answers)" | "$JQ" -r '.[] | select(.decision == "fix-now") | [.draft, .name] | @tsv')
EOF
    ns_release
  else
    ns_err "run lock refused 4 times — the fix-now answers stay undecided; the next interactive PICK asks them"
  fi
  ns_emit_park fix-now "fix-now not run ($reason) — recorded as follow-up"
}

# ================================================================================================
# step: park — the park writes, then watcher / notify / run-lock release
# ================================================================================================
ns_park() {
  local kind n="" line note gl fx
  kind="$(st park_kind)"; [ -n "$kind" ] || kind=awaiting_merge
  note="$(st progress_note)"; gl="$(st gate_line)"; fx="$(ns_fixnow_reentered)"
  # n is read and normalised before the first park write (a count or `unknown`, never a refusal)
  if [ "$(st drafts)" = true ] || [ -n "$PENDING_LINE" ]; then n="$(ns_pending_n)"; fi
  ns_status paused || return 1
  ns_call_writer current-set "$RF" --item "$ITEM" --status "$kind" --pr "$PR" --branch "$BRANCH" --pause-reason "$kind" || return 1
  if [ "$kind" = escalated ]; then
    local a=(--cause "$(st escalation_cause)") v
    v="$(st escalation_check)"; [ -n "$v" ] && a+=(--check "$v")
    v="$(st escalation_run_id)"; [ -n "$v" ] && a+=(--run-id "$v")
    v="$(st escalation_attempt)"; [ -n "$v" ] && a+=(--attempt "$v")
    v="$(st escalation_sha)"; [ -n "$v" ] && a+=(--sha "$v")
    if ! bash "$H" current-escalation "$RF" "${a[@]}" >/dev/null 2>&1; then
      # a --check value it refuses: the cause alone records the park (the `--check` rule of the
      # `validation_unrun` park, skills/automate-loop/legacy-tail.md "On `unrun`" — this step runs it by default)
      local b=(--cause "$(st escalation_cause)"); v="$(st escalation_sha)"; [ -n "$v" ] && b+=(--sha "$v")
      ns_call_writer current-escalation "$RF" "${b[@]}" || return 1
    fi
  fi
  if [ -n "$n" ]; then ns_pending_write "$n" "$fx" || return 1; fi
  ns_refresh
  if [ -n "$note" ]; then line="$(ns_ts) $note"
  else
    case "$kind" in
      escalated) line="$(ns_ts) parked escalated $PR — $(st escalation_cause)" ;;
      ready_for_release) line="$(ns_ts) parked ready_for_release — PR $PR READY; do not merge yet — wave open (no merge watcher armed in a lane)" ;;
      *) if [ -n "$gl" ]; then
           line="$(ns_ts) parked awaiting_merge $PR — gate-eval $gl"
           [ -n "$n" ] && [ "$n" != 0 ] && line="$line; $n dismissed decision(s) pending"
         else
           line="$(ns_ts) parked awaiting_merge $PR — ${n:-0} dismissed decision(s) pending"
         fi ;;
    esac
  fi
  ns_progress "$line" || return 1
  case "$kind" in
    escalated)
      ns_notify escalated "PR $PR ESCALATED — /automate parked escalated ($(st escalation_cause)) for $ITEM"
      ns_watch ;;
    ready_for_release) ns_notify ready_for_release "PR $PR READY — do not merge yet, wave open" ;;
    *) ns_watch; ns_notify awaiting_merge "PR $PR ready to merge — /automate parked awaiting_merge for $ITEM" ;;
  esac
  ns_release
  if [ "$(st order)" = park-first ]; then NEXT=decide; return 0; fi
  ns_emit_park park "parked $kind"
}

# ================================================================================================
# step: sync — SYNC after a MERGE (closeout … --no-trail, then the leftover gate)
# ================================================================================================
ns_sync() {
  local out cls rc
  if [ -n "${NEXT_STEP_CLOSEOUT_OUT:-}" ]; then
    out="$(cat "$NEXT_STEP_CLOSEOUT_OUT")"
  else
    out="$(bash "$H" closeout "$RF" "$ITEM" "$PR" --no-trail ${SID:+--session-id "$SID"} 2>/dev/null)"
  fi
  cls="$(printf '%s\n' "$out" | bash "$H" closeout-classify --run "$RUN_ID" --item "$ITEM" --pr "$PR" --record "$RF" 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] || { ns_err "automate-helpers.sh closeout-classify exited $rc"; NS_RC="$rc"; return 1; }
  ns_refresh
  if [ "$cls" = complete ]; then NEXT=checkoff; return 0; fi
  st_set leftovers "$cls"; NEXT=leftover
}

# ================================================================================================
# step: leftover — the close-out leftover gate (§6 step 1, also SYNC's)
# ================================================================================================
ns_leftover_park() {
  local rows tab k r i p s d
  rows="$(st leftovers)"; tab="$(printf '\t')"
  ns_status paused || return 1
  ns_call_writer current-set "$RF" --pause-reason closeout_leftover || return 1
  while IFS="$tab" read -r k r i p s d; do
    [ -n "$k" ] || continue
    ns_progress "$(ns_ts) closeout leftover: $r $s $d" || return 1
  done <<EOF
$rows
EOF
  ns_release
  ns_emit_park leftover "parked closeout_leftover — finish the cleanup, then --resume"
}
ns_leftover_ask() {
  local rows q only="${1:-}"
  rows="$(st leftovers)"
  q="$(printf '%s\n' "$rows" | head -n 4 | "$JQ" -Rcs --arg o "$only" '[split("\n")[] | select(length > 0) | split("\t") |
       {question: ("Close-out left something behind: " + .[1] + " " + .[4] + " — " + .[5]), header: "",
        options: (if $o == "" then ["Clean up now","Keep and continue","Stop"] else ["Keep and continue","Stop"] end)}]')"
  ns_emit_ask leftover AUT-LEFTOVER "closeout_leftover park" "$q"
  NEXT=leftover
}
ns_leftover() {
  local ans="$ANSWER"; ANSWER=""
  if [ -z "$ans" ]; then
    if ns_interactive; then ns_leftover_ask "$(st leftover_retry)"; return 0; fi
    ns_leftover_park; return
  fi
  if [ "$(rj "$ans" cant_ask)" = true ]; then ns_leftover_park; return; fi
  local rows tab nq i=0 lab k r it p s d rest="" redo=0 out cls
  rows="$(st leftovers | head -n 4)"; tab="$(printf '\t')"
  nq="$(printf '%s\n' "$rows" | grep -c .)"
  [ "$(printf '%s' "$ans" | "$JQ" '[(.answers // [.answer])[]? | strings] | length')" = "$nq" ] \
    || { ns_err "leftover: want $nq answer(s)"; NS_RC=2; return 1; }
  while [ "$i" -lt "$nq" ]; do # every label checked before the first write
    lab="$(printf '%s' "$ans" | "$JQ" -r --argjson i "$i" '(.answers // [.answer])[$i]')"
    printf '%s' "$PENDING_TEXT" | "$JQ" -e --argjson i "$i" --arg l "$lab" '.questions[$i].options | index($l) != null' >/dev/null 2>&1 \
      || { ns_err "leftover: '$lab' is not an option of question $((i + 1))"; NS_RC=2; return 1; }
    i=$((i + 1))
  done
  i=0
  while IFS="$tab" read -r k r it p s d; do
    [ -n "$k" ] || continue
    lab="$(printf '%s' "$ans" | "$JQ" -r --argjson i "$i" '(.answers // [.answer])[$i]')"; i=$((i + 1))
    case "$lab" in
      "Stop") ns_leftover_park; return ;;
      "Keep and continue") ns_progress "$(ns_ts) closeout leftover kept: $r $s $d" || return 1 ;;
      "Clean up now")
        out="$(bash "$H" closeout "$AD/$r.md" "$it" "$p" ${SID:+--session-id "$SID"} 2>/dev/null)"
        cls="$(printf '%s\n' "$out" | bash "$H" closeout-classify --run "$r" --item "$it" --pr "$p" --record "$RF" 2>/dev/null)"
        [ "$cls" = complete ] || { rest="$rest$cls"$'\n'; redo=1; } ;;
    esac
  done <<EOF
$rows
EOF
  rest="$rest$(st leftovers | tail -n +5)"
  rest="$(printf '%s\n' "$rest" | grep . || true)"
  if [ -n "$rest" ]; then
    st_set leftovers "$rest"; [ "$redo" = 1 ] && st_set leftover_retry 1
    if ns_interactive; then ns_leftover_ask "$(st leftover_retry)"; return 0; fi
    ns_leftover_park; return
  fi
  st_del leftovers; st_del leftover_retry
  # a superseded-by-merge close-out stops at awaiting_go; SYNC's goes on to CHECK OFF
  NEXT="$(st after_leftover)"; st_del after_leftover; [ -n "$NEXT" ] || NEXT=checkoff
}

# ================================================================================================
# step: checkoff — CHECK OFF + PROGRESS (a closeout may already have checked the row)
# ================================================================================================
ns_checkoff() {
  if ns_section '## Queue' | grep -qxF -- "- [ ] $ITEM"; then
    ns_call_writer queue-checkoff "$RF" "$ITEM" || return 1
  fi
  local n; n="$(bash "$H" remaining "$RF" 2>/dev/null | tail -n 1)"
  ns_progress "$(ns_ts) checked off $ITEM — merged $PR; remaining: $n" || return 1
  NEXT=terminate
}

# ================================================================================================
# step: terminate — the two exits (§6 "Termination (two exits)")
# ================================================================================================
ns_terminate() {
  local n p lim tl sw
  n="$(bash "$H" remaining "$RF" 2>/dev/null | tail -n 1)"
  ns_count_ok "$n" || { ns_err "terminate: remaining printed '$n', not a count"; NS_RC=1; return 1; }
  if [ "$n" = 0 ]; then
    ns_status done || return 1
    tl="$(bash "$H" trail-pr "$RF" --reason done 2>/dev/null | tail -n 1)"
    [ -n "$tl" ] && { ns_progress "$(ns_ts) $tl" || return 1; }
    sw="$(bash "$H" sweep --root "$ROOT" 2>/dev/null | grep '^sweep: summary — ' | tail -n 1)"
    ns_progress "$(ns_ts) sweep (dry run): ${sw:-sweep: summary — skipped: no output}" || return 1
    ns_release
    ns_emit done terminate '{"status":"done","remaining":0}'
    return 0
  fi
  p="$(st items_processed)"
  [ -n "$p" ] || p="$(ns_section '## Queue' | grep '^- \[x\] ' | grep -cvE '# (skipped|abandoned):' || true)"
  lim="$(ns_limit)"
  # a count that is not a count is surfaced, never read as "under the limit" (fail CLOSED)
  case "$p" in ''|*[!0-9]*) ns_err "terminate: items_processed '$p' is not a count"; NS_RC=1; return 1 ;; esac
  # under the limit ONLY when the comparison itself succeeds: a count test cannot compare (too many
  # digits ⇒ "integer expected", false) is over the limit — the limit_reached park, never `running`
  if ! ns_count_ok "$p" || ! [ "$p" -lt "$lim" ] 2>/dev/null; then
    ns_status paused || return 1
    ns_call_writer current-set "$RF" --pause-reason limit_reached || return 1
    ns_progress "$(ns_ts) limit_reached — $p item(s) processed; remaining: $n" || return 1
    ns_release
    ns_emit_park terminate "limit reached ($p/$lim) — raise the limit or --resume"
    return 0
  fi
  ns_release
  ns_emit done terminate "$("$JQ" -cn --argjson n "$n" '{status: "running", remaining: $n}')"
}

# ================================================================================================
# dispatch
# ================================================================================================
ns_dispatch() {
  case "$1" in
    run) ns_run ;;
    run-result) ns_run_result ;;
    run-record) ns_run_record ;;
    rate-limit) ns_rate_limit ;;
    drain) ns_drain ;;
    drain-result) ns_drain_result ;;
    superseded) ns_superseded ;;
    awaiting-go) ns_awaiting_go ;;
    learning-emit) ns_learning_emit ;;
    gate) ns_gate ;;
    validation) ns_validation ;;
    gate-eval) ns_gate_eval ;;
    dismissed) ns_dismissed ;;
    decide) ns_decide ;;
    fix-now) ns_fix_now ;;
    park) ns_park ;;
    sync) ns_sync ;;
    leftover) ns_leftover ;;
    checkoff) ns_checkoff ;;
    terminate) ns_terminate ;;
    *) ns_err "unknown step '$1'"; NS_RC=2; return 1 ;;
  esac
}

ns_refresh
NEXT=""; ANSWER=""
# BINDING: the sidecar's pending state (an ask, a spawn, a failed step to retry, the tail context)
# belongs to the item + PR its tail started for. When ## Current names another item or PR (the owner
# left at a post-park ask, the PR merged, the next PICK set a new item running), none of it may be
# consumed: it is discarded whole and this call is read as a fresh tail's entry (a drain report ⇒
# gate; anything else answers nothing pending ⇒ exit 2). The fix-now re-drain keeps item AND PR.
ns_bound() {
  local i p; i="$(st item)"; p="$(st pr)"
  [ -z "$i" ] && [ -z "$p" ] && return 0
  [ "${i#./}" = "${ITEM#./}" ] && [ "$p" = "$PR" ]
}
# The discarded tail's report key survives as `stale_report_key`: that report, re-sent while ## Current
# names the next item, is refused (exit 2, nothing written) on every path that takes a drain report.
if [ -z "${NEXT_STEP_FROM:-}" ] && ! ns_bound; then
  ns_err "the sidecar's pending state is for $(st item) ($(st pr)); ## Current names ${ITEM:-no item} (${PR:-no pr}) — discarded, read as a fresh tail"
  stale="$(st report_key)"; NS_STATE='{}'; [ -n "$stale" ] && st_set stale_report_key "$stale"
fi
pending="$(st pending_text)"; PENDING_TEXT="$pending"
pending_do="$(printf '%s' "$pending" | "$JQ" -r '.do // empty' 2>/dev/null)"
pending_what="$(printf '%s' "$pending" | "$JQ" -r '.what // empty' 2>/dev/null)"
if [ -n "${NEXT_STEP_FROM:-}" ]; then
  NEXT="$NEXT_STEP_FROM"
  if [ "$have_result" = 1 ]; then # --result is the report the starting step reads
    case "$NEXT" in
      run-result|run-record|rate-limit) ns_check_run_report "$RESULT"; ns_take_run_report "$RESULT" ;;
      drain-result|superseded|learning-emit) ns_check_drain_report "$RESULT"; ns_take_drain_report "$RESULT" ;;
      *) ns_check_report "$RESULT"; ns_take_report "$RESULT" ;;
    esac
  fi
  # a case seeding the sidecar's item / PR (a drain whose ## Current was never set) keeps them
  [ -n "$(st item)" ] || st_set item "$ITEM"; [ -n "$(st pr)" ] || st_set pr "$PR"
elif [ -n "$START" ]; then
  [ "$have_result" = 0 ] || ns_die2 "--start takes no --result (a report answers the pending spawn)"
  case "$START" in
    run)
      # the same /autonomous spawn still pending is re-printed (idempotent); any other open instruction
      # of this item's pass is refused — RUN already started
      [ "$pending_do" = spawn ] && [ "$pending_what" = "/autonomous run" ] && { printf '%s\n' "$pending"; exit 0; }
      case "$pending_do" in
        ask|spawn) ns_die2 "run_already_started — a pending ${pending_what:-$pending_do} instruction belongs to $ITEM's pass (a no-result call re-prints it) — nothing written" ;;
      esac
      stale="$(st report_key)"; [ -n "$stale" ] || stale="$(st stale_report_key)"
      NS_STATE='{}'; [ -n "$stale" ] && st_set stale_report_key "$stale"
      NEXT=run ;;
    drain)
      # an open ask, or a spawn other than this pass's owned drain (whose re-request the drain step
      # refuses by name), is never answered by --start
      case "$pending_do" in ask) ns_die2 "an ask is pending for $ITEM (a no-result call re-prints it) — nothing written" ;; esac
      if [ "$pending_do" = spawn ] && [ "$pending_what" != "owned drain" ]; then
        ns_die2 "a pending ${pending_what} spawn belongs to $ITEM's pass (a no-result call re-prints it) — nothing written"
      fi
      NEXT=drain ;;
  esac
elif [ "$have_result" = 0 ]; then
  if [ -n "$pending" ]; then printf '%s\n' "$pending"; exit 0; fi
  NEXT="$(st failed)"   # a step that failed (surfaced) is retried; otherwise there is nothing to do
  [ -n "$NEXT" ] || ns_die2 "nothing is pending — start RUN with --start run, or report the drain result with --result '{\"drain_result\":…}'"
elif [ "$pending_do" = ask ]; then
  NEXT="$(st next)"; ANSWER="$RESULT"
elif [ "$pending_do" = spawn ] && [ "$pending_what" = "/autonomous run" ]; then
  ns_check_run_report "$RESULT"; ns_take_run_report "$RESULT"; NEXT=run-result
elif [ "$pending_do" = spawn ] && ns_is_drain_report "$RESULT" && [ "$(ns_report_hash "$RESULT")" = "$(st prev_drain_report_hash)" ]; then
  # the previous drain's report re-sent at this drain's spawn is a REPLAY: the spawn re-prints, nothing written
  ns_err "--result is the previous drain's DRAIN report, not this drain's — re-printing the pending spawn; nothing written"
  printf '%s\n' "$pending"; exit 0
elif [ "$pending_do" = spawn ] && [ "$pending_what" = "owned drain" ]; then
  ns_is_drain_report "$RESULT" || ns_die2 "--result does not answer the owned-drain spawn: send the DRAIN report (review_heal_result | review_heal_result_file | no_terminal_block) — nothing written"
  ns_check_drain_report "$RESULT"; ns_take_drain_report "$RESULT"; NEXT=drain-result
elif [ "$pending_do" = spawn ] && ns_is_drain_report "$RESULT"; then
  # the fix-now re-drain answered with a DRAIN report: the driver writes the pinned re-drain lines
  ns_check_drain_report "$RESULT"; ns_take_drain_report "$RESULT"; st_set drain_kind fixnow; NEXT=drain-result
elif [ "$pending_do" = spawn ]; then
  ns_check_report "$RESULT"
  # the drain report the spawn was issued after, re-sent, is a REPLAY — not the re-drain's report: the
  # pending spawn re-prints and nothing is written (the fix and the re-drain have not run)
  if ns_same_report "$RESULT" "$(st report_key)"; then
    ns_err "--result is the drain report this spawn answered, not the re-drain's — re-printing the pending spawn; nothing written"
    printf '%s\n' "$pending"; exit 0
  fi
  ns_stale_report "$RESULT" && ns_die2 "--result is the drain report of a tail already left behind (another item / PR) — not this re-drain's; nothing written"
  NEXT=gate; ns_take_report "$RESULT"
else
  # a RUN / DRAIN report answers its own spawn only: re-sent after the step it answered (same item + PR,
  # byte-identical report) it re-prints the instruction that step printed; any other one is refused
  if ns_is_drain_report "$RESULT"; then
    if [ -n "$pending" ] && [ "$(st item)" = "$ITEM" ] && [ "$(st pr)" = "$PR" ] \
       && [ "$(ns_report_hash "$RESULT")" = "$(st drain_report_hash)" ]; then
      printf '%s\n' "$pending"; exit 0
    fi
    ns_die2 "--result is a DRAIN report, but no owned-drain / fix-now re-drain spawn is pending for $ITEM — nothing written"
  fi
  ns_is_run_report "$RESULT" && ns_die2 "--result is a RUN report, but no /autonomous spawn is pending (start RUN with --start run) — nothing written"
  ns_check_report "$RESULT"
  # a REPLAY — the same drain report for the same item + PR after a terminal instruction — re-prints
  # that instruction and writes nothing (the tail already ran for it)
  if [ -n "$pending" ] && [ "$(st item)" = "$ITEM" ] && [ "$(st pr)" = "$PR" ] \
     && [ "$(ns_report_key "$RESULT")" = "$(st report_key)" ]; then
    printf '%s\n' "$pending"; exit 0
  fi
  ns_stale_report "$RESULT" && ns_die2 "--result is the drain report of a tail already left behind (another item / PR; ## Current names ${ITEM:-no item} ${PR:-}) — send this item's own report (\"pr\" binds it); nothing written"
  # a new item's tail: nothing pending, or the previous instruction was terminal (park / done); the
  # previous tail's report key is kept as stale (it never starts a tail again)
  stale="$(st report_key)"; [ -n "$stale" ] || stale="$(st stale_report_key)"
  NS_STATE='{}'; [ -n "$stale" ] && st_set stale_report_key "$stale"
  ns_take_report "$RESULT"; NEXT=gate
fi
st_del pending_text; st_del failed

# FLAGS that change gate behaviour persist for this item's tail (the sidecar; reset with it, so they
# never reach the next item's tail): a later call without the flag keeps it — a no-result retry of a
# failed step never turns interactive — and an explicit flag on a later call still applies.
# --non-interactive and --trust-unprotected have no "off" form: once given they stay for the tail.
if [ "$NONINT" = 1 ]; then st_set flag_non_interactive true; elif [ "$(st flag_non_interactive)" = true ]; then NONINT=1; fi
if [ -n "$TRUST" ]; then st_set flag_trust_unprotected true; elif [ "$(st flag_trust_unprotected)" = true ]; then TRUST=true; fi
if [ -n "$MODE" ]; then st_set flag_mode "$MODE"
else case "$(st flag_mode)" in safe|auto-merge) MODE="$(st flag_mode)" ;; esac; fi
if [ -n "$SID" ]; then st_set flag_session_id "$SID"; else SID="$(st flag_session_id)"; fi
root_given="${ROOT:+1}"; [ -n "$ROOT" ] || ROOT="$(st flag_root)"
ns_resolve_root
[ -n "$root_given" ] && st_set flag_root "$ROOT"

STOPPED=0; first_arm=1
while [ -n "$NEXT" ]; do
  arm="$NEXT"; NEXT=""
  st_set last_arm "$arm"
  if ! ns_dispatch "$arm"; then
    # exit 2 = a usage error or a --result that answers nothing pending: every arm checks that BEFORE
    # its first write, so nothing was written — leave the sidecar (and its pending instruction) as it was.
    # Only the call's FIRST arm can say so: a later arm refusing ran after earlier arms of this call
    # wrote, so it is a surfaced failure (exit 1, the sidecar saved at that arm, retried next call)
    if [ "$first_arm" = 1 ]; then [ "$NS_RC" = 2 ] && exit 2; fi
    [ "$NS_RC" = 2 ] && NS_RC=1
    st_set next "$arm"; st_set failed "$arm"; st_save
    [ "$NS_RC" -ne 0 ] || NS_RC=1
    exit "$NS_RC"
  fi
  first_arm=0
  [ -n "$NS_EMIT" ] && break
  if [ -n "${NEXT_STEP_UNTIL:-}" ] && [ "$arm" = "$NEXT_STEP_UNTIL" ]; then STOPPED=1; break; fi
done

if [ -n "$NS_EMIT" ]; then
  st_set pending_text "$NS_EMIT"; st_set next "$NEXT"
  st_save || exit 1
  printf '%s\n' "$NS_EMIT"
  exit 0
fi
if [ "$STOPPED" = 1 ]; then
  st_set next "$NEXT"; st_save || exit 1
  ns_err "stopped after $arm (NEXT_STEP_UNTIL) — next: ${NEXT:-none}"
  exit 0
fi
ns_err "internal: step '$arm' neither emitted an instruction nor named a next step"
st_save
exit 1
