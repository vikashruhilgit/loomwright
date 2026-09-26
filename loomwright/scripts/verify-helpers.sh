#!/usr/bin/env bash
# verify-helpers.sh — the `/verify` evidence store's ONLY writer and ONLY deriver. Schema authority:
# `docs/RESULT_SCHEMAS.md §VERIFY_EVIDENCE` (layout of `.supervisor/verify/<run_id>/`, the line
# shape, the latest-per-ac_id rule, the `rejected.jsonl` wrapper). Modelled on `automate-helpers.sh`
# (subcommand dispatch, diag to stderr, jq-only JSON construction, atomic temp+mv for derived files).
#
# WHY THIS EXISTS. The QA lane's accounting layer failed because an agent WROTE the roll-up: a
# `failed` scope was reported `completed`, and the summary was overwritten per scope. Here a fact is
# appended exactly once, only after `validate-verify-evidence.py` (sibling path, never a plugin-root
# variable — this file is vendor-neutral core) exits 0; every human-readable summary is DERIVED from
# the lines by `summary-build` on every append; a total can only be computed, never written.
#
# Subcommands:
#   run-id             <slug>              # prints `verify-<YYYYMMDDTHHMMSSZ>-<slug>`; slug lower-cased, [^a-z0-9] runs collapsed to one `-`, edge dashes trimmed
#   evidence-append    <run_dir> <json|->  # compact-to-one-line, validate, then ONE `>>` write; refused input is wrapped RAW into <run_dir>/rejected.jsonl (exit 1); regenerates summary.md (a derivation failure is named on stderr, exit stays 0 — the fact IS stored)
#   summary-build      <run_dir>           # the ONLY reader of evidence.jsonl: derives <run_dir>/summary.md (atomic temp+mv) with a `derived_from:` trailer
#   first-unverdicted  <run_dir>           # prints the first `ac_id` (acs.json order) not yet GENUINELY verdicted — a FORCED pause-verdict (latest ac line reason session_expired / run_paused_session_expired) does NOT count, so it re-opens on resume; else nothing; exit 0 either way ("fully verdicted" is not an error)
#   impact-summary-render <run_dir>        # item 06: renders the "## Impact pass" section (separate table + counts from the ticket ones) — called by summary-build on every append, also directly testable
#   spec-sources-render    <run_dir>       # token-economy 07: derives the ONE `spec sources: replayed n · authored n · re-derived n` line from evidence.jsonl (replayed = distinct ac_ids with a `spec_replay` line; authored = ticket-scope `ac` ids with NO `spec_replay` line whose latest verdict is not NOT_VERIFIABLE — see spec_sources_render; re-derived = count of `spec_rederived` lines) — called by summary-build on every append, also directly testable; sits BESIDE impact-summary-render's table, never inside it
#
# Item 07 (`/verify --folder <dir>` multi-ticket queue) subcommands — the ONLY sanctioned writer of
# `.supervisor/verify/queue-*.md`; protocol authority: `skills/verify-walkthrough/SKILL.md` §"Multi-
# ticket queue", schema: `docs/RESULT_SCHEMAS.md` §VERIFY_QUEUE. Modelled on `automate-helpers.sh`'s
# §3 run-file primitives (`runfile-write` / `progress-append` / `queue-checkoff` / `remaining`) with
# ONE addition `queue-write` carries that automate's `runfile-write` does not: a LINE-COUNT GUARD
# before every rewrite (memory: `runfile-write-accepts-empty-stdin` — a piped rewrite that errors can
# atomically empty a run file). `verify-run.sh`'s `queue-reconcile-item` (git/evidence access lives
# there, not here) calls these four for every mutation; nothing else ever writes the queue file.
#   queue-write            <queue_path>  (content on stdin)  # atomic temp+rename; REFUSES (exit 1, file byte-unchanged) when the existing file is non-empty and the new content has FEWER lines
#   queue-progress-append  <queue_path> <line>                # append-only ## Progress — same shape as automate-helpers.sh progress-append
#   queue-checkoff         <queue_path> <item> [suffix]        # flip "- [ ] <item>" -> "- [x] <item>  <suffix>" (suffix printed verbatim, e.g. "verdict: PASS:1 ..." or "# stale: head moved a->b"); idempotent on an already-checked item
#   queue-remaining        <queue_path>                        # COMPUTED count of "- [ ]" Queue lines only
#
# Exit codes: 0 success; 1 refused / generic failure; 2 usage.
# Dependencies: bash 3.2+, jq, python3 (the validator; absent ⇒ every append is REFUSED as
# `validator_unavailable`, never let through), `shasum -a 256` or `sha256sum` (trailer hash).

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$HERE/validate-verify-evidence.py"

diag()  { echo "verify-helpers: $*" >&2; }
die()   { diag "$*"; exit 1; }
usage() { diag "usage: $*"; exit 2; }

# sha256_of <file> — `shasum -a 256` first (macOS ships no sha256sum), `sha256sum` fallback.
sha256_of() {
  local f="$1" h=""
  if command -v shasum >/dev/null 2>&1; then
    h="$(shasum -a 256 "$f" | cut -d' ' -f1)"
  elif command -v sha256sum >/dev/null 2>&1; then
    h="$(sha256sum "$f" | cut -d' ' -f1)"
  fi
  [ -n "$h" ] || die "neither shasum nor sha256sum is available — cannot derive the trailer hash"
  printf '%s\n' "$h"
}

# --------------------------------------------------------------------------- #
# run-id <slug>
# --------------------------------------------------------------------------- #
run_id() {
  local raw="${1:-}" slug
  [ -n "$raw" ] || usage "run-id <slug>"
  slug="$(printf '%s' "$raw" | tr 'A-Z' 'a-z' | sed 's/[^a-z0-9]\{1,\}/-/g; s/^-\{1,\}//; s/-\{1,\}$//')"
  [ -n "$slug" ] || die "run-id: slug '$raw' normalises to nothing"
  printf 'verify-%s-%s\n' "$(date -u +%Y%m%dT%H%M%SZ)" "$slug"
}

# --------------------------------------------------------------------------- #
# evidence-append <run_dir> <json|->
# --------------------------------------------------------------------------- #
# The ONLY writer of the store, and it NEVER READS the store file — derivation belongs to
# summary_build (a separate function, the only reader). The function body names the store file on
# exactly ONE line: the single `printf … >>` write (the shell's `>>` is O_APPEND, so two concurrent
# appenders never interleave bytes and there is no read-modify-write window). Validator status is
# captured as `$?` in the statement AFTER the substitution — `local x="$(…)"` or `if ! x=$(…)` would
# lose it, and a lost status is exactly how an invalid fact would reach the store. The record is
# canonicalised to one compact line BEFORE validation, so the validated bytes ARE the stored bytes.
evidence_append() {
  local run_dir="${1:-}" input="${2:-}" json line out rc reason ts
  { [ -n "$run_dir" ] && [ -n "$input" ]; } || usage "evidence-append <run_dir> <json|->"
  if [ "$input" = "-" ]; then json="$(cat)"; else json="$input"; fi
  [ -n "$json" ] || die "evidence-append: empty record"
  mkdir -p "$run_dir/artifacts" || die "evidence-append: cannot create $run_dir/artifacts"
  # Canonicalise to ONE compact line BEFORE validating, so the bytes validated are the bytes stored.
  # `json.loads` accepts a pretty-printed (multi-line) record, and writing that verbatim would put N
  # physical lines in the store for one fact — breaking one-object-per-line, the `derived_from:` count
  # and the store's own file-mode re-validation. `jq -cs` reduces exactly ONE JSON value to its
  # compact form; anything else (not JSON, two concatenated values) is left RAW so the validator
  # refuses it with its own reason and `rejected.jsonl` still carries the input verbatim.
  line="$(printf '%s' "$json" | jq -cs 'if length == 1 then .[0] else error("not exactly one JSON value") end' 2>/dev/null)" || line="$json"
  out="$(python3 "$VALIDATOR" --line "$line" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$line" >> "$run_dir/evidence.jsonl" || die "evidence-append: append failed"
    # Derivation runs in a SUBSHELL: every failure inside summary_build is a `die` (exit 1), and in
    # THIS process that would turn a successful append into exit 1 — indistinguishable from a refusal,
    # so a caller retrying on rc 1 would replay the append and duplicate the fact. The fact is stored;
    # the derivation failure is named on stderr and the exit status stays 0.
    ( summary_build "$run_dir" ) || diag "evidence-append: summary-build failed after a successful append (the record IS stored; run summary-build on $run_dir to see why)"
    verify_notify_dispatch "$run_dir" "$line" || true
    return 0
  fi
  case "$rc" in
    1)   reason="$(printf '%s' "$out" | jq -r '.reason // empty' 2>/dev/null)"
         [ -n "$reason" ] || reason="validator_rejected" ;;
    127) reason="validator_unavailable" ;;
    *)   reason="validator_error:$rc" ;;
  esac
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -cn --arg ts "$ts" --arg reason "$reason" --arg line "$json" \
    '{rejected_at:$ts,reason:$reason,line:$line}' >> "$run_dir/rejected.jsonl" \
    || die "evidence-append: could not record the refusal in $run_dir/rejected.jsonl"
  diag "evidence-append: REFUSED ($reason) — recorded in $run_dir/rejected.jsonl"
  return 1
}

# --------------------------------------------------------------------------- #
# impact-summary-render <run_dir>
# --------------------------------------------------------------------------- #
# Renders item 06's "## Impact pass" section of summary.md - a SEPARATE table and a SEPARATE
# PASS/FAIL/BLOCKED/NOT_VERIFIABLE counts line from the ticket ones above it; an impact-scope verdict
# never contributes to the ticket row `summary_build` computes. Called by `summary_build` on every
# append (never by an agent directly) but reads evidence.jsonl independently so it can be exercised
# and tested standalone. `$impact_ev == null` (the impact pass never ran for this run - `--no-impact`,
# or the run has not reached it yet) prints one advisory line and nothing else.
impact_summary_render() {
  local run_dir="${1:-}" src
  [ -n "$run_dir" ] || usage "impact-summary-render <run_dir>"
  src="$run_dir/evidence.jsonl"
  [ -f "$src" ] || src=/dev/null
  jq -rs '
    def esc: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
    def show: if . == null then "—" else esc end;
    def latest_by(f): group_by(f) | map(max_by(._i)) | sort_by(._i);
    (to_entries | map(.value + {_i: .key})) as $L
    | ([$L[] | select(.event == "ac" and .scope == "impact")] | latest_by(.ac_id)) as $impact_acs
    | ([$L[] | select(.event == "impact_surfaces")] | last) as $impact_ev
    | def icnt(v): [$impact_acs[] | select(.verdict == v)] | length;
    if $impact_ev == null and ($impact_acs | length) == 0 then
      "## Impact pass\n_impact pass not run for this run (--no-impact, or the pass has not reached this run yet)_"
    else
      (($impact_ev.surfaces // {}) | to_entries | map(select((.value // []) | length > 0)) | length) as $n_diff
      | (($impact_ev.brief_surfaces // []) | length) as $n_brief
      | ([$impact_acs[] | select(((.source // "") | test("^prior_ac:")))] | length) as $n_prior
      | ($impact_ev.limit // 0) as $lim
      | ([
          "## Impact pass",
          "impact pass: \($n_diff) surfaces from diff, \($n_brief) from brief, \($n_prior) prior ACs (limit \($lim))",
          ""
        ]
        + (if ($impact_acs | length) == 0 then ["_no impact-scope verdicts recorded_"] else
            ["| id | verdict | classification | source | reason |", "|---|---|---|---|---|"]
            + [$impact_acs[] | "| \(.ac_id | show) | \(.verdict | show) | \(.classification | show) | \(if .source == null then "—" else (.source | esc) end) | \(.reason | show) |"]
          end)
        + [""]
        + ["impact — PASS: \(icnt("PASS")) · FAIL: \(icnt("FAIL")) · BLOCKED: \(icnt("BLOCKED")) · NOT_VERIFIABLE: \(icnt("NOT_VERIFIABLE")) · total: \($impact_acs | length)"]
        + (if (($impact_ev.unmapped // []) | length) == 0 then [] else ["- unmapped: \(($impact_ev.unmapped // []) | join(", "))"] end)
        | join("\n"))
    end
  ' "$src"
}

# --------------------------------------------------------------------------- #
# spec-sources-render <run_dir>
# --------------------------------------------------------------------------- #
# token-economy 07 — derives the ONE `spec sources: replayed n · authored n · re-derived n` line from
# evidence.jsonl (never tallied by the agent, never a filesystem scan). Called by summary_build on
# every append but reads evidence.jsonl independently so it can be exercised and tested standalone —
# the SAME "also directly testable" convention impact_summary_render already uses.
#   replayed   = count of DISTINCT ac_ids carrying a `spec_replay` line (one line per replay, but an
#                ac_id is counted once even if it were somehow replayed more than once)
#   authored   = ticket-scope `ac` ids with NO `spec_replay` line for that id, EXCLUDING ids whose
#                latest ticket-scope verdict is NOT_VERIFIABLE — that verdict is only ever written by
#                the browser-less `verify-run.sh verdict` path (walk never emits it), so no spec was
#                authored for it (PR #269 review). An ac_id that has NOT yet reached a verdict at all is
#                neither authored nor counted here; it surfaces once its own `ac` line lands. HONEST
#                LIMIT: a BLOCKED id still counts — evidence cannot tell walk's `no_spec` BLOCKED or a
#                browser-less `verdict … BLOCKED` (no spec) apart from a spec that ran and was BLOCKED.
#   re-derived = count of `spec_rederived` lines (bounded to <= replayed by construction, per the
#                owning brief's Design step 3 — never re-checked here, this is a pure derivation)
spec_sources_render() {
  local run_dir="${1:-}" src
  [ -n "$run_dir" ] || usage "spec-sources-render <run_dir>"
  src="$run_dir/evidence.jsonl"
  [ -f "$src" ] || src=/dev/null
  jq -rs '
    ([.[] | select(.event == "ac" and .scope == "ticket")] | group_by(.ac_id) | map(last)
      | map(select(.verdict != "NOT_VERIFIABLE")) | map(.ac_id)) as $ticket_ids
    | ([.[] | select(.event == "spec_replay") | .ac_id] | unique) as $replayed_ids
    | ($replayed_ids | length) as $replayed
    | ([$ticket_ids[] | select(. as $i | ($replayed_ids | index($i)) == null)] | length) as $authored
    | ([.[] | select(.event == "spec_rederived")] | length) as $rederived
    | "spec sources: replayed \($replayed) · authored \($authored) · re-derived \($rederived)"
  ' "$src"
}

# --------------------------------------------------------------------------- #
# summary-build <run_dir>
# --------------------------------------------------------------------------- #
# The ONLY reader of evidence.jsonl and the ONLY writer of summary.md. `jq -s` over the file (absent
# or empty ⇒ a "0 lines" summary — the hash is of /dev/null, never skipped). Latest-per-ac_id and
# latest-per-env-step are computed by input order (`_i` index, `max_by`), never by timestamp. The
# counts row is COMPUTED over the latest-per-ac_id set. Written to `summary.md.tmp.$$` then `mv -f`,
# so a crash never leaves a half summary. No agent ever writes this file.
summary_build() {
  local run_dir="${1:-}" src body tmp n hash rc impact_section spec_sources_line
  [ -n "$run_dir" ] || usage "summary-build <run_dir>"
  mkdir -p "$run_dir" || die "summary-build: cannot create $run_dir"
  src="$run_dir/evidence.jsonl"
  [ -f "$src" ] || src=/dev/null
  tmp="$run_dir/summary.md.tmp.$$"
  impact_section="$(impact_summary_render "$run_dir")"
  spec_sources_line="$(spec_sources_render "$run_dir")"
  body="$(jq -rs --arg impact_section "$impact_section" --arg spec_sources_line "$spec_sources_line" '
    def esc: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
    def show: if . == null then "—" else esc end;
    def listish: if (. == null) or (. == []) then "—" else (map(tostring) | join(", ") | esc) end;
    def latest_by(f): group_by(f) | map(max_by(._i)) | sort_by(._i);
    (to_entries | map(.value + {_i: .key})) as $L
    | ([$L[] | select(.event == "run_start")] | last) as $rs
    | (if $rs != null then $rs.run_id elif ($L | length) > 0 then $L[-1].run_id else "(none)" end) as $run_id
    | ([$L[] | select(.event == "env")] | latest_by(.step)) as $env
    | ([$L[] | select(.event == "auth")] | last) as $auth
    | ([$L[] | select(.event == "ac")] | latest_by(.ac_id)) as $all_acs
    | ([$L[] | select(.event == "ac" and .scope == "ticket")] | latest_by(.ac_id)) as $acs
    | ([$L[] | select(.event == "spec_replay") | .ac_id] | unique) as $replayed_ids
    | [$L[] | select(.event == "issue")] as $issues
    | [$L[] | select(.event == "pause" or .event == "resume")] as $pr
    | ([$L[] | select(.event == "run_end")] | last) as $re
    | ([$L[] | select(.event == "ac" or .event == "issue") | (.artifacts // [])[] | tostring] | unique) as $arts
    | def cnt(v): [$acs[] | select(.verdict == v)] | length;
    [
      "# Verify run \($run_id) — summary",
      "> DERIVED by `verify-helpers.sh summary-build` from evidence.jsonl on every append — do not edit; edits are overwritten.",
      "",
      "## Run",
      (if $rs == null then "_no run_start line_" else
        "- ticket: \($rs.ticket_path | show) (\($rs.ticket_kind | show))",
        "- branch: \($rs.branch | show)",
        "- head_sha: \($rs.head_sha | show) · base_sha: \($rs.base_sha | show)",
        "- env_contract_hash: \(if $rs.env_contract_hash == null then "(none)" else ($rs.env_contract_hash | esc) end)"
      end),
      "",
      "## Environment (latest line per step)",
      (if ($env | length) == 0 then "_no env lines_" else
        "| step | outcome | reason |",
        "|---|---|---|",
        ($env[] | "| \(.step | show) | \(.outcome | show) | \(.reason | show) |")
      end),
      "",
      "## Auth",
      (if $auth == null then "_no auth line_" else "- state: \($auth.state | show)" end),
      "",
      "## Acceptance criteria (ticket scope only, latest line per ac_id)",
      # AC12 (token-economy 07): the replayed column marks every ac_id with a spec_replay line — so
      # a replayed spec that FAILS (never re-derived, per the own-assertion rule) is visibly a
      # replay rather than a silent authored FAIL.
      (if ($acs | length) == 0 then "_no ticket-scope ac lines_" else
        "| ac_id | scope | verdict | classification | reason | artifacts | replayed |",
        "|---|---|---|---|---|---|---|",
        ($acs[] | .ac_id as $row_id | "| \(.ac_id | show) | \(.scope | show) | \(.verdict | show) | \(.classification | show) | \(.reason | show) | \(.artifacts | listish) | \(if ($replayed_ids | index($row_id)) != null then "replayed" else "—" end) |")
      end),
      "",
      "PASS: \(cnt("PASS")) · FAIL: \(cnt("FAIL")) · BLOCKED: \(cnt("BLOCKED")) · NOT_VERIFIABLE: \(cnt("NOT_VERIFIABLE")) · total: \($acs | length)",
      $spec_sources_line,
      "",
      $impact_section,
      "",
      "## Issues",
      (if ($issues | length) == 0 then "_none_" else
        ($issues[] | "- [\(.severity | show)] \(.text | show)\(if .route == null then "" else " (route: \(.route | esc))" end)")
      end),
      "",
      "## Proposals",
      # Evidence-driven, never a filesystem scan of .supervisor/requirements/proposed/: whether a
      # draft is EXPECTED is fully determined by which ac/issue lines qualify (FAIL+REAL_BUG acs,
      # every issue line - the same rule propose-from-verify.sh applies), so this regenerates
      # correctly on every append with no dependency on propose-from-verify.sh having run yet.
      # This is what makes a BLOCKED/NOT_VERIFIABLE-only run state "no draft was written" truthfully
      # (AC2 of the verify-fail-sink-and-notify job) without this script ever touching proposed/.
      (([$all_acs[] | select(.verdict == "FAIL" and .classification == "REAL_BUG")]) as $draftable_acs
       | (($draftable_acs | length) + ($issues | length)) as $n_expected_drafts
       | if $n_expected_drafts == 0 then
           "_no draft is expected — only BLOCKED / NOT_VERIFIABLE verdicts (or FAIL lines classified DISCOVERY_GAP / ENVIRONMENT_ISSUE) were recorded; `/propose --from-verify` writes nothing for this run_"
         else
           "\($n_expected_drafts) draft(s) expected under `.supervisor/requirements/proposed/` (`verify-\($run_id)-*`) — run `/propose --from-verify \($run_id)` to write them:",
           ($draftable_acs[] | "- FAIL \(.ac_id | show): \(.text | show)"),
           ($issues[] | "- issue: \(.text | show)")
         end),
      "",
      "## Pauses / resumes",
      (if ($pr | length) == 0 then "_none_" else ($pr[] | "- \(.ts | show) \(.event): \(.reason | show)") end),
      "",
      "## Artifacts",
      (if ($arts | length) == 0 then "_none_" else ($arts[] | "- \(esc)") end),
      "",
      "## Run end",
      (if $re == null then "_no run_end line_" else "- status: \($re.status | show) at \($re.ts | show)" end),
      ""
    ] | .[]
  ' "$src")"
  rc=$?
  [ "$rc" -eq 0 ] || die "summary-build: jq could not derive the summary from $src (rc=$rc)"
  n=$(( $(wc -l < "$src") ))
  hash="$(sha256_of "$src")" || exit 1
  {
    printf '%s\n' "$body"
    printf 'derived_from: %s lines, sha256 %s\n' "$n" "$hash"
  } > "$tmp" || die "summary-build: cannot write $tmp"
  mv -f "$tmp" "$run_dir/summary.md" || die "summary-build: cannot move $tmp into place"
}

# --------------------------------------------------------------------------- #
# first-unverdicted <run_dir>
# --------------------------------------------------------------------------- #
# AC6 (`/verify --resume`'s resume-position derivation) + the item-04 FIX for the session-expiry
# resume path. Reads `<run_dir>/acs.json` for the ORDERED `ac_id` list, and `evidence.jsonl` for the
# done-set: the `ac_id`s whose LATEST `{event:ac}` line (input order — the same `latest_by` idiom
# `summary_build` / `walk_block_remaining` already use, never timestamp) is a GENUINE verdict. A
# FORCED pause-verdict — `reason` is `session_expired` or `run_paused_session_expired`, the two
# reasons `verify-run.sh walk`'s AC5 expiry override (and ONLY that override — `walk_apply_expiry_
# override`) ever writes — does NOT count as "already verdicted": without this exclusion, EVERY
# ac_id from the pause point onward already carries a forced line the moment a session expires, this
# function would report "nothing left" (empty stdout), and a resumed run would have no defined set of
# ACs to re-author specs for, permanently stranding the pause. Every other verdict — a real PASS /
# FAIL / a BLOCKED for any OTHER reason / NOT_VERIFIABLE — still counts as done, per AC6's original
# contract: a genuinely-decided AC is never re-run on resume, only the forced ones re-open. Prints the
# first `ac_id` from the ordered list NOT in the done-set; prints NOTHING when every `ac_id` is
# genuinely covered — a distinct, documented "nothing left" signal, never a nonzero exit, since full
# coverage is a normal state, not an error.
first_unverdicted() {
  local run_dir="${1:-}" done_ids
  [ -n "$run_dir" ] || usage "first-unverdicted <run_dir>"
  [ -f "$run_dir/acs.json" ] || die "first-unverdicted: no acs.json in $run_dir — run preflight first [acs_missing]"
  done_ids="[]"
  if [ -f "$run_dir/evidence.jsonl" ]; then
    done_ids="$(jq -cs '
      def latest_by(f): group_by(f) | map(max_by(._i)) | sort_by(._i);
      (to_entries | map(.value + {_i: .key})) as $L
      | ([$L[] | select(.event == "ac")] | latest_by(.ac_id)) as $latest
      | [$latest[] | select(((.reason // "") as $r | $r != "session_expired" and $r != "run_paused_session_expired")) | .ac_id]
    ' "$run_dir/evidence.jsonl" 2>/dev/null)"
  fi
  [ -n "$done_ids" ] || done_ids="[]"
  jq -r --argjson done "$done_ids" \
    '[.acs[].ac_id | select(. as $i | ($done | index($i)) == null)] | first // empty' \
    "$run_dir/acs.json"
}

# --------------------------------------------------------------------------- #
# Notify - three named events (needs_auth pause, first FAIL, run_end), all wired from
# evidence_append (the STORE's sole writer), never from commands/verify.md's main-thread Report
# step and never from a re-implementation inside verify-run.sh. Two reasons this lives here:
#   1. evidence_append is the ONE place every evidence line - however it got minted, by
#      preflight_cmd, auth_check_cmd/pause_cmd, verdict_cmd, walk_append_ac, or finish_cmd - passes
#      through before it is durably stored. Hooking any one of those call sites individually would
#      mean re-deriving "is this a pause/needs_auth line, an ac/FAIL line, a run_end line" in
#      several places; hooking the sole writer means once.
#   2. `/verify`'s VERIFY MODE runs its walk/auth-check/finish calls inside a Task-spawned
#      qa-executor subagent (see commands/verify.md, agents/qa-executor.md) - a SEPARATE process
#      with no shared shell state with the `/verify` main thread that parsed `--notify`. An env
#      var exported in the main thread's Bash call would not reliably reach that subagent's own
#      Bash calls. A FILESYSTEM marker under the run dir crosses that boundary for free: both the
#      main thread and the executor read/write the same `<run_dir>/`, regardless of which process
#      is running. `verify-run.sh preflight --notify` and `verify-run.sh notify-enable <run_dir>`
#      are the two places that CREATE `<run_dir>/.notify-enabled`; this file only ever READS it.
#
# Each of the three events is guarded by its OWN once-only marker file so a resumed or retried run
# can never re-fire an event that already fired for this run_dir.
# --------------------------------------------------------------------------- #

# verify_notify_enabled <run_dir> - true iff this run opted into --notify.
verify_notify_enabled() { [ -f "$1/.notify-enabled" ]; }

# verify_notify_once <run_dir> <once_marker_basename> <gate_type> <context> [desktop_message]
# Fires `send-webhook.sh --event-type gate` at most once per <once_marker_basename> under
# <run_dir>, and - only when a fifth argument is given - a synthetic Notification-shaped payload
# into `notify-desktop.sh` for an OS-native banner. Both wrappers are already fail-SAFE (always
# exit 0 per their own headers; docs/RESULT_SCHEMAS.md and docs/TELEMETRY.md describe their
# contracts, unchanged here) - this function additionally never lets either call's status escape,
# since a notify failure must never fail the evidence append it rides in on.
#
# The desktop banner is fired as a `Notification`-shaped payload (not `PreToolUse[AskUserQuestion]`
# - `/verify` never calls AskUserQuestion) with an UNRECOGNISED `notification_type`, which
# `notify-desktop.sh` maps to its generic "Claude Code" title and, more importantly, is EXEMPT from
# that script's `LOOMWRIGHT_NOTIFY_SCOPE=plugin` scope gate (that gate only inspects
# `PreToolUse` events - see notify-desktop.sh's dispatch). Using the `PreToolUse[AskUserQuestion]`
# shape instead would route through `is_plugin_context()`, whose transcript-marker regex does not
# list `/verify` among the recognised slash commands, and would silently swallow the banner on a
# standalone `/verify` invocation outside a Supervisor/autonomous session - exactly the case this
# notification exists for.
verify_notify_once() {
  local run_dir="$1" marker="$2" gate_type="$3" context="$4" desktop_msg="${5:-}"
  verify_notify_enabled "$run_dir" || return 0
  [ -e "$run_dir/$marker" ] && return 0
  : > "$run_dir/$marker" 2>/dev/null
  local sender="$HERE/send-webhook.sh"
  if [ -f "$sender" ]; then
    bash "$sender" --event-type gate --gate-type "$gate_type" --context "$context" >/dev/null 2>&1 || true
  fi
  if [ -n "$desktop_msg" ]; then
    local notifier="$HERE/notify-desktop.sh"
    if [ -f "$notifier" ] && command -v jq >/dev/null 2>&1; then
      jq -cn --arg m "$desktop_msg" \
        '{hook_event_name: "Notification", notification_type: "verify_needs_auth", message: $m}' 2>/dev/null \
        | bash "$notifier" >/dev/null 2>&1 || true
    fi
  fi
  return 0
}

# verify_notify_dispatch <run_dir> <line> - inspects the JUST-APPENDED compact JSON <line> and
# fires AT MOST ONE of the three named events, best-effort. Always returns 0 - never allowed to
# turn a successful append into a failure.
verify_notify_dispatch() {
  local run_dir="$1" line="$2" event reason verdict run_id ticket status counts_row
  verify_notify_enabled "$run_dir" || return 0
  command -v jq >/dev/null 2>&1 || return 0
  event="$(printf '%s' "$line" | jq -r '.event // empty' 2>/dev/null)"
  [ -n "$event" ] || return 0
  run_id="$(printf '%s' "$line" | jq -r '.run_id // empty' 2>/dev/null)"
  ticket=""
  [ -f "$run_dir/evidence.jsonl" ] && ticket="$(jq -r 'select(.event == "run_start") | .ticket_path' "$run_dir/evidence.jsonl" 2>/dev/null | head -1)"
  counts_row="$(grep '^PASS: ' "$run_dir/summary.md" 2>/dev/null | head -1)"
  case "$event" in
    pause)
      reason="$(printf '%s' "$line" | jq -r '.reason // empty' 2>/dev/null)"
      [ "$reason" = "needs_auth" ] || return 0
      verify_notify_once "$run_dir" ".notified-needs_auth" "verify_needs_auth" \
        "run_id=$run_id ticket=$ticket reason=needs_auth - /verify is paused for a human sign-in; resume with /verify --resume $run_id" \
        "/verify run $run_id needs a human sign-in (ticket: $ticket)"
      ;;
    ac)
      verdict="$(printf '%s' "$line" | jq -r '.verdict // empty' 2>/dev/null)"
      [ "$verdict" = "FAIL" ] || return 0
      verify_notify_once "$run_dir" ".notified-first_fail" "verify_first_fail" \
        "run_id=$run_id ticket=$ticket first FAIL recorded; ${counts_row:-counts unavailable yet}"
      ;;
    run_end)
      status="$(printf '%s' "$line" | jq -r '.status // empty' 2>/dev/null)"
      verify_notify_once "$run_dir" ".notified-run_end" "verify_run_end" \
        "run_id=$run_id ticket=$ticket status=$status; ${counts_row:-counts unavailable}"
      ;;
    *) return 0 ;;
  esac
  return 0
}


# --------------------------------------------------------------------------- #
# Item 07 — multi-ticket queue writers (`.supervisor/verify/queue-*.md`)
# --------------------------------------------------------------------------- #

# queue-write <queue_path>   (content on stdin)
# Atomic temp+rename write, GUARDED against silently shrinking the ONLY copy of
# queue resume state: stdin is captured to a temp file FIRST (byte-exact — no
# subshell strips a trailing newline), and if <queue_path> already exists and is
# non-empty, the write is REFUSED (exit 1, nothing touched, <queue_path> stays
# byte-unchanged) when the new content has FEWER lines than the existing file —
# an empty or truncated rewrite (a crashed generator, a pipeline that errored
# mid-stream) must never overwrite a longer file (memory:
# runfile-write-accepts-empty-stdin). A same-or-more-lines rewrite (the normal
# case — flipping ## Status, editing ## Current, inserting a re-queued item)
# proceeds exactly like automate-helpers.sh's runfile-write.
queue_write() {
  local out="${1:-}" dir tmp old_n new_n
  [ -n "$out" ] || usage "queue-write <queue_path>"
  dir="$(dirname "$out")"
  mkdir -p "$dir" || die "queue-write: cannot create $dir"
  tmp="$(mktemp "${out}.XXXXXX")" || die "queue-write: mktemp failed"
  cat > "$tmp"
  if [ -f "$out" ] && [ -s "$out" ]; then
    old_n=$(( $(wc -l < "$out") ))
    new_n=$(( $(wc -l < "$tmp") ))
    if [ "$new_n" -lt "$old_n" ]; then
      diag "queue-write: refusing to shrink $out ($old_n -> $new_n lines) — write NOT applied [queue_write_shrink_refused]"
      rm -f "$tmp"
      return 1
    fi
  fi
  mv -f "$tmp" "$out"
}

# queue-progress-append <queue_path> <line>
# Appends ONE line under "## Progress" WITHOUT rewriting any existing line —
# byte-for-byte the same awk idiom as automate-helpers.sh's progress-append
# (ENVIRON, never awk -v, so a backslash in the line is never mangled), applied
# to the queue file's own "## Progress" section.
queue_progress_append() {
  local out="${1:-}" line="${2:-}"
  { [ -n "$out" ] && [ -n "$line" ]; } || usage "queue-progress-append <queue_path> <line>"
  [ -f "$out" ] || die "queue-progress-append: queue file not found: $out"
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  VH_NEWLINE="- $line" awk '
    BEGIN { in_prog=0; appended=0; seen_prog=0; newline=ENVIRON["VH_NEWLINE"] }
    /^## Progress/ { print; in_prog=1; seen_prog=1; next }
    /^## / {
      if (in_prog && !appended) { print newline; appended=1; in_prog=0 }
      print; next
    }
    { print }
    END {
      if (!appended) {
        if (!seen_prog) print "## Progress"
        print newline
      }
    }
  ' "$out" > "$tmp"
  mv -f "$tmp" "$out"
}

# queue-checkoff <queue_path> <item> [suffix]
# Flips "- [ ] <item>" -> "- [x] <item>" (or, with a suffix, "- [x] <item>  <suffix>",
# printed VERBATIM — e.g. "verdict: PASS:1 FAIL:0 BLOCKED:0 NOT_VERIFIABLE:0 total:1"
# or "# stale: head moved <old>-><new>"). <item> must match the queue line's
# payload EXACTLY (everything after "- [ ] "). Atomic write; idempotent on an
# already-checked item (no "- [ ] <item>" line left to match, so the file is
# rewritten byte-identical).
queue_checkoff() {
  local out="${1:-}" item="${2:-}" suffix="${3:-}"
  { [ -n "$out" ] && [ -n "$item" ]; } || usage "queue-checkoff <queue_path> <item> [suffix]"
  [ -f "$out" ] || die "queue-checkoff: queue file not found: $out"
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  VH_ITEM="$item" VH_SUFFIX="$suffix" awk '
    BEGIN { item=ENVIRON["VH_ITEM"]; suffix=ENVIRON["VH_SUFFIX"] }
    {
      line=$0
      if (line ~ /^- \[ \] /) {
        payload=substr(line, 7)
        if (payload == item) {
          if (suffix != "")
            print "- [x] " item "  " suffix
          else
            print "- [x] " item
          next
        }
      }
      print line
    }
  ' "$out" > "$tmp"
  mv -f "$tmp" "$out"
}

# queue-remaining <queue_path>
# COMPUTED count of unchecked "- [ ]" Queue lines only (never a stored field) —
# same convention as automate-helpers.sh's remaining.
queue_remaining() {
  local out="${1:-}"
  [ -n "$out" ] || usage "queue-remaining <queue_path>"
  [ -f "$out" ] || die "queue-remaining: queue file not found: $out"
  grep -c '^- \[ \] ' "$out" || true
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    run-id)             run_id "$@" ;;
    evidence-append)    evidence_append "$@" ;;
    summary-build)      summary_build "$@" ;;
    first-unverdicted)  first_unverdicted "$@" ;;
    impact-summary-render) impact_summary_render "$@" ;;
    spec-sources-render)   spec_sources_render "$@" ;;
    queue-write)            queue_write "$@" ;;
    queue-progress-append)  queue_progress_append "$@" ;;
    queue-checkoff)         queue_checkoff "$@" ;;
    queue-remaining)        queue_remaining "$@" ;;
    ""|-h|--help)
      grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
