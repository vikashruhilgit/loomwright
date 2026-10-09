#!/usr/bin/env bash
# automate-trail.sh — the `/automate` engine's post-park lifecycle MUTATORS.
# PROTOCOL AUTHORITY: `skills/automate-loop/SKILL.md` §6 "Trail PR after merge
# and at run end" (and §1.5's rows for each subcommand). trail-pr is called only
# by closeout (after its merge evidence gate), at `## Status: done`, and on a
# skip/abandon check-off — never at a park (§14's lane wave end and
# `lane-remove --abandon` run it inside a parked lane; the same gate); its _evidence_gate drops a
# done-stamped requirement / done brief whose PR is not merged regardless. Dispatched from
# `automate-helpers.sh` (`exec bash "$(dirname "$0")/automate-trail.sh" <subcmd>`)
# so the helper itself stays read-only toward git; THIS script is the carve-out.
#
# SCOPE OF ITS MUTATIONS (the whole list — anything else is a bug):
#   * `trail-pr` commits ONLY this run's explicit trail paths, from a temporary
#     `git worktree` off fresh origin/<default branch> (or off this run's open
#     trail branch), pushes ONLY to `chore/<run_id>-trail-<n>` (never forced),
#     opens/reuses ONE PR via `gh pr create`, stages the trail-branch-tip blobs
#     of every path that branch changes in the primary checkout's index (see
#     "Checkout contract" below), and records them in the gitignored
#     `<run_id>.trail-staged` beside the run file.
#   * BRANCH MODE (`setup-memory.sh mode` = `on <branch>`; SKILL §"Branch mode"): `trail-pr`
#     opens NO PR and creates no trail worktree — it runs `meta-sync.sh push --paths-from` with
#     the same evidence-gated candidate list (the gitignore drop skipped), and on failure appends
#     one `meta-push FAILED:` Progress line, notifies, and writes the gitignored
#     `<run_id>.meta-push-failed` marker; `trail-unstage` and closeout's re-stage are skipped.
#     Mode off ⇒ everything below is unchanged.
#   * `trail-unstage` only drops this run's trail-path index entries
#     (`git restore --staged -- <path>`); working copies are never touched.
#   * `trail-gate` (PICK) reads this run's open trail PRs; only when none is
#     open does it run closeout's step-4 sync (_sync_primary: re-stage the
#     landed recorded trail blobs, `git checkout <base>`, `git pull --ff-only`).
#   * `closeout` removes ONLY this PR's head-branch worktrees (HEAD == the PR's
#     headRefOid AND clean after `worktree-salvage.sh`) and that local branch
#     (`git branch -D`, only when its tip == the PR's headRefOid), switches the primary to the base branch
#     and `git pull --ff-only`s it (first re-staging the recorded trail blobs
#     that landed upstream — index only), appends the requirement stamp, checks the
#     Queue item off, and calls trail-pr. It NEVER commits in the primary.
#   * `finalize-empty` (under `run-lock.sh --owner automate-finalize:<run_id>`)
#     rewrites ONLY a closed-out run's `## Status: paused` → `done` and its
#     `## Current` `pause_reason` → `null` (`current-set` on a staged copy, then
#     one validated runfile-write), appends
#     two Progress lines, calls trail-pr `--reason done` and — branch mode off —
#     trail-unstage for that run. Nothing else.
#   * `closeout-others` runs `closeout` (and, branch mode off, `trail-unstage`)
#     for OTHER runs' merged in-flight items and appends ONE record line to the
#     --record run file. Nothing else.
#   * Neither subcommand merges anything (the sole merge executor is `automate-helpers.sh
#     gate-eval`, SKILL §11), trail-pr never calls `run-lock.sh` (closeout takes it around steps 3–7);
#     neither runs `git reset`,
#     `git stash`, `git add -A`/`git add .`, or a force push.
#
# Subcommands:
#   sidecar-check <path>
#       One line: `ok <path>` or `fail <path>: <reason>`. Locates the LAST
#       REVIEW_HEAL_RESULT / SUPERVISOR_RESULT block with result_block_parser.py
#       and checks its keys against the tables below (required keys, no
#       non-schema key, canonical `channels_scanned`, `risk_classification`
#       carries `reasons`). A file that cannot be checked is a `fail`.
#   trail-pr <runfile> [--reason <reason>]
#       One line: `trail-pr: opened <url>` | `trail-pr: pushed <url>` |
#       `trail-pr: skipped — <reason>`. Sidecars that fail `sidecar-check` are
#       excluded and named INSIDE that same line (`; excluded <path> — <reason>`),
#       and so is a done-stamped requirement / done brief whose PR is not merged
#       (`; excluded <path> — pr not merged`, _evidence_gate),
#       so the loop can append it to `## Progress` with one progress-append.
#   closeout <runfile> <item> <pr_url> [--session-id <sid>]
#       The post-merge close-out (SKILL §6 "Post-merge close-out"): evidence
#       gate, brief repair, squash-safe worktree/branch cleanup, base-branch
#       sync, requirement stamp, Queue check-off, trail-pr. One line per step
#       (`closeout: <verb> — …`, brief-repair/trail-pr lines passed through);
#       idempotent; steps 3–7 run under run-lock.sh (re-enters a PICK lock via
#       --session-id; releases with --owner only).
#   trail-unstage <runfile>
#       One line: `trail-unstage: unstaged <n> path(s) — <paths>` |
#       `trail-unstage: skipped — <reason>` (`nothing staged` when clean). Run at
#       PICK, before RUN: drops the trail entries trail-pr staged so the next
#       item's branch + commit cannot sweep them.
#   finalize-empty <runfile>
#       `finalize-empty: finalized <runfile>` + the trail-pr (+ trail-unstage)
#       line, or ONE `finalize-empty: skipped — <reason>` line. Finalizes ONLY a
#       paused / awaiting_go / remaining-0 / `## Current` status-done run (the
#       state closeout leaves after the last check-off); SKILL §4 step 1 runs it
#       through `automate-helpers.sh resume-glob <dir> --finalize`. In a lane
#       clone (`.supervisor/lane.json` present, parallel-automate/05) any run but
#       the lane's own ⇒ `skipped — lane clone (not this lane's run)`.
#   closeout-others <automate_dir> [--record <runfile>]
#       The cross-run close-out (SKILL §4 "Start order"): closeout of every OTHER
#       run whose ## Current names a not-done item with a merged PR, mode-off
#       trail-unstage, that closeout's closeout-classify answer, one
#       `closeout-others: record(ed) — cross-run closeout <run_id> <item>: …` line
#       (no PR URL). Untouched runs print nothing. In a lane clone ONE line
#       `closeout-others: skipped — lane clone` (the coordinator closes other runs
#       out once, in the primary — parallel-automate/05 Scope 3 amendment).
#   trail-gate <runfile>
#       One line: `trail-gate: PARK — trail PR open <url>…` |
#       `trail-gate: PARK — <unreadable reason>` | `trail-gate: clear — no open
#       trail PR; synced — <base> at <sha>` | `…; sync skipped — <reason>`. Run
#       at PICK after RECONCILE, before trail-unstage: the single-open-PR
#       invariant counts this run's own trail PR (SKILL §8); fail-CLOSED read.
#
# CHECKOUT CONTRACT (decision 4 of the post-park-lifecycle brief, proved by the
# post-merge-pull legs of test-automate-trail.sh): after a successful push, AND
# on the no-diff "already up to date" skip against an open trail PR, trail-pr
# sets the primary checkout's INDEX entry of EVERY path the trail branch changes
# (every push on it, not only the latest delta) to that path's blob at the trail
# branch tip (`git update-index --add --cacheinfo`; never the working copy),
# recording each in `<run_id>.trail-staged`, and leaves working copies untouched. A later plain `git checkout main && git pull` then
# fast-forwards over those paths (index == incoming blob), and bytes that exist
# only locally BY DESIGN — Progress lines the live run file gained after the
# push, other runs' postmortem ledger lines — survive as ordinary unstaged
# modifications. Those staged entries WOULD ride along in any commit made from
# the primary index (`git checkout -b` carries them; a plain `git commit`
# commits the whole index), so the loop runs `trail-unstage` at PICK, before
# the next commit-producing phase, and `closeout` re-applies the contract at
# its own pull for the recorded blobs that have landed upstream. The next
# trail-pr (the next closeout, skip/abandon check-off or run end) re-stages every path its open trail PR
# carries, including ones an earlier PICK dropped. trail-unstage clears the
# union of the record and today's candidates. Honest limits: between a PICK and
# the next trail-pr, a HAND-run `git pull` over a merged trail PR refuses
# (closeout's sync does not); a trail PR closed unmerged leaves its entries
# staged until the next PICK's trail-unstage. The trail branch is NEVER
# rebased: once origin/<default branch> moves the postmortem ledger (another
# run's trail PR, a postmortem line) after this run's trail branch was cut, a
# later push/no-diff re-trail stages the trail-TIP ledger blob, which lacks
# main's new line — the trail PR then conflicts at the ledger's EOF, and both a
# hand pull and closeout's sync refuse (fail-safe: no reset, nothing lost);
# resolve the trail PR by hand. When closeout's `git pull --ff-only` refuses,
# the entries it re-staged are put back to their prior index state
# (_restore_prior), so a refused sync leaves the index as it found it.
# Queue-derived candidates are restricted to `.supervisor/requirements/**.md`:
# a Queue item naming any other path is never committed by the trail.
#
# Always exits 0 (a runtime side-effect emitter — CLAUDE.md §"Failure-Mode
# Invariants"). bash 3.2 / BSD-userland safe. Seams: LOOMWRIGHT_GH_BIN,
# LOOMWRIGHT_JQ_BIN (same as automate-helpers.sh).

set -uo pipefail

GH="${LOOMWRIGHT_GH_BIN:-gh}"
JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

# --------------------------------------------------------------------------- #
# sidecar-check
# --------------------------------------------------------------------------- #
sidecar_check() {
  local path="${1:-}" out
  if [ -z "$path" ]; then echo "fail : missing argument"; return 0; fi
  if [ ! -f "$path" ] || [ ! -r "$path" ]; then echo "fail $path: file not found"; return 0; fi
  if ! command -v python3 >/dev/null 2>&1; then echo "fail $path: python3 unavailable"; return 0; fi
  out="$(python3 - "$HERE" "$path" <<'PY' 2>/dev/null
import sys
here, path = sys.argv[1], sys.argv[2]
sys.path.insert(0, here)

def say(msg):
    print(msg)
    sys.exit(0)

try:
    import result_block_parser as R
except Exception as exc:  # pragma: no cover - defensive
    say("fail %s: parser unavailable (%s)" % (path, exc))

# REVIEW_HEAL_RESULT key tables — mirror docs/RESULT_SCHEMAS.md §REVIEW_HEAL_RESULT
# ("Schema v1" / "Schema v2" blocks). Update together with that section.
# `rounds` is REQUIRED for v2 here although the schema block marks only the first
# seven fields required: the --until-mergeable drain always emits it (its value is
# read from the scripts/drain-rounds.sh ledger), and the hand-rebuilt item-10
# sidecar dropped it (the #303 drift this check exists to catch).
RH_V1_REQUIRED = ["schema_version", "decision", "iterations", "issues_fixed",
                  "remaining_issues", "pr_url", "notified"]
RH_V2_REQUIRED = RH_V1_REQUIRED + ["rounds"]
RH_V2_ALLOWED = set(RH_V2_REQUIRED + [
    "max_rounds", "fix_cycles", "churn_rounds", "repeat_check_failure",
    "unresolved_bot_feedback", "postmortem_churn_threshold",
    "postmortem_dispatched", "channels_scanned", "findings_validated",
    "findings_dismissed", "checks_waited", "termination_reason",
    "severity_floor", "sub_floor_fixed", "rejected_instruction_like",
    "dismissed", "rules_gate", "checks_untrusted",
    # automate-followups/31: the escalation cause (present only on ESCALATED).
    "escalation_cause", "escalation_check", "escalation_run_id",
    "escalation_attempt", "escalation_sha"])
RH_V1_ALLOWED = set(RH_V1_REQUIRED)
# channels_scanned vocabulary — mirrors skills/review-heal/SKILL.md
# §"Step U1 — All-Channel Read" (RESULT_SCHEMAS lists channels only as "e.g.").
CHANNELS = set(["reviews", "latestReviews", "reviewThreads", "issue_comments",
                "check_outputs"])

# SUPERVISOR_RESULT key tables — mirror docs/RESULT_SCHEMAS.md §SUPERVISOR_RESULT
# (the yaml block). validate-supervisor-result.py exposes only main(), so there is
# no importable table to reuse. `error` is required only when status == failed.
SUP_REQUIRED = ["schema_version", "task_id", "status", "pr_url", "branch",
                "subtasks_completed", "subtasks_failed", "heal_loop_ran",
                "heal_iterations", "heal_decision", "heal_fixable_issues_fixed",
                "heal_remaining_issues", "summary"]
SUP_ALLOWED = set(SUP_REQUIRED + [
    "error", "cost_profile", "rubric_score", "branch_base", "pr_state",
    "contract_conformance", "benchmark_result", "ground_truth",
    "preflight_sync", "knowledge_sources_used", "until_mergeable_dispatched",
    "until_mergeable_log", "risk_classification", "heal_dismissed",
    "heal_first_decision", "heal_new_findings"])

try:
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
except Exception as exc:
    say("fail %s: unreadable (%s)" % (path, exc))

name, block = R.find_last_named_block(text, ("REVIEW_HEAL_RESULT", "SUPERVISOR_RESULT"))
if block is None:
    say("fail %s: no REVIEW_HEAL_RESULT or SUPERVISOR_RESULT block" % path)
fields, errors = R.parse_block(block)
if errors:
    say("fail %s: %s parse error (%s)" % (path, name, errors[0]))

sv, _bad = R.as_int(fields.get("schema_version"))
if name == "REVIEW_HEAL_RESULT":
    if sv == 1:
        required, allowed = RH_V1_REQUIRED, RH_V1_ALLOWED
    elif sv == 2:
        required, allowed = RH_V2_REQUIRED, RH_V2_ALLOWED
    else:
        say("fail %s: REVIEW_HEAL_RESULT schema_version must be 1 or 2" % path)
else:
    if sv != 1:
        say("fail %s: SUPERVISOR_RESULT schema_version must be 1" % path)
    required, allowed = SUP_REQUIRED, SUP_ALLOWED
    if R.as_text(fields.get("status")).strip() == "failed":
        required = required + ["error"]

for key in required:
    if not R.present(fields, key):
        say("fail %s: %s missing required key %s" % (path, name, key))
for key in fields:
    if key not in allowed:
        say("fail %s: %s carries non-schema key %s" % (path, name, key))

if name == "REVIEW_HEAL_RESULT" and R.present(fields, "channels_scanned"):
    chans = fields.get("channels_scanned")
    if not isinstance(chans, list):
        say("fail %s: channels_scanned is not a list" % path)
    for c in chans:
        if R.as_text(c) not in CHANNELS:
            say("fail %s: non-canonical channels_scanned token %s" % (path, R.as_text(c)))

if name == "SUPERVISOR_RESULT" and R.present(fields, "risk_classification"):
    rc = fields.get("risk_classification")
    if not isinstance(rc, dict) or "reasons" not in rc:
        say("fail %s: risk_classification present without reasons" % path)

say("ok %s" % path)
PY
)"
  case "$out" in
    "ok $path"|"fail $path: "*) printf '%s\n' "$out" ;;
    *) echo "fail $path: checker error" ;;
  esac
  return 0
}

# --------------------------------------------------------------------------- #
# trail-pr
# --------------------------------------------------------------------------- #
TRAIL_WT=""
TRAIL_ROOT=""
TRAIL_TMP=""
trail_cleanup() {
  if [ -n "$TRAIL_WT" ] && [ -d "$TRAIL_WT" ]; then
    bash "$HERE/worktree-salvage.sh" "$TRAIL_WT" --reason "automate trail-pr teardown" >/dev/null 2>&1
    git -C "$TRAIL_ROOT" worktree remove --force "$TRAIL_WT" >/dev/null 2>&1
    rm -rf "$TRAIL_WT" 2>/dev/null
    git -C "$TRAIL_ROOT" worktree prune >/dev/null 2>&1
  fi
  [ -n "$TRAIL_TMP" ] && rm -rf "$TRAIL_TMP" 2>/dev/null
  TRAIL_WT=""; TRAIL_TMP=""
  return 0
}

# _in_list <needle> <newline-separated list>
_in_list() {
  local n="$1" x
  while IFS= read -r x; do [ "$x" = "$n" ] && return 0; done <<EOF
$2
EOF
  return 1
}

# _trail_candidates <rf_rel> <run_id> — run from the checkout root. Computes this
# run's trail paths (explicit; never -A / .) into TRAIL_KEPT (newline list, not
# gitignored) and the failing-sidecar exclusions into TRAIL_EXCLUDED. Shared by
# trail-pr (what to commit) and, via _trail_owned, by trail-unstage and closeout.
TRAIL_LEDGER=".supervisor/postmortem/results.jsonl"
DRAFT_DIR=".supervisor/requirements/proposed"

# _trail_is_run_draft <run_id> <path> — 0 when <path> is "$DRAFT_DIR/<name>" and <name> is a
# dismissed-finding draft of <run_id>: its own (`<run_id>--*--dismissed-*.md`) or a lane's
# (`<run_id>-L<digits>--*--dismissed-*.md`). The lane form uses the SAME digits-only definition as
# automate-dismissed.sh's _dismissed_lane_id, so `<run_id>-L2x--…` is never a lane draft (the bare
# glob `-L[0-9]*--` would accept it). Every lane-draft match in this file goes through here.
_trail_is_run_draft() {
  local rid="$1" n rest num
  case "$2" in "$DRAFT_DIR/"*) n="${2#"$DRAFT_DIR/"}" ;; *) return 1 ;; esac
  case "$n" in
    "$rid"--*--dismissed-*.md) return 0 ;;
    "$rid"-L[0-9]*--*--dismissed-*.md) ;;
    *) return 1 ;;
  esac
  rest="${n#"$rid"-L}"; num="${rest%%--*}"
  case "$num" in ""|*[!0-9]*) return 1 ;; esac
  return 0
}
TRAIL_KEPT=""
TRAIL_EXCLUDED=""
TRAIL_SKIP_IGNORE_DROP=0   # 1 only on the branch-mode push path (_trail_meta_push)
_trail_candidates() {
  local rf_rel="$1" run_id="$2"
  local cands="" p q item
  TRAIL_EXCLUDED=""
  cands="$rf_rel"
  local sc_dir; sc_dir="$(dirname "$rf_rel")"
  for p in "$sc_dir/$run_id.review-heal-result.md" "$sc_dir/$run_id.supervisor-result.md"; do
    [ -f "$p" ] || continue
    q="$(sidecar_check "$p")"
    case "$q" in
      "ok $p") cands="$cands"$'\n'"$p" ;;
      *) TRAIL_EXCLUDED="$TRAIL_EXCLUDED; excluded $p — ${q#"fail $p: "}" ;;
    esac
  done
  local queue
  queue="$(awk '/^## Queue/{q=1;next} /^## /{q=0} q && /^- \[[ xX]\] /{sub(/^- \[[ xX]\] /,""); sub(/[[:space:]]+#.*$/,""); sub(/[[:space:]]+$/,""); print}' "$rf_rel" 2>/dev/null)"
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    case "$item" in /*|*..*) continue ;; esac
    p="${item#./}"
    # Only a requirement file is trail: a Queue item naming any other tracked
    # path (a source file) would commit that file's local WIP into the trail PR.
    case "$p" in .supervisor/requirements/*.md) ;; *) continue ;; esac
    [ -f "$p" ] && cands="$cands"$'\n'"$p"
  done <<EOF
$queue
EOF
  if [ -r "$HERE/brief-pointer.sh" ]; then
    # shellcheck source=/dev/null
    . "$HERE/brief-pointer.sh"
    local brief ptr
    for brief in .supervisor/jobs/done/*.md .supervisor/jobs/failed/*.md; do
      [ -f "$brief" ] || continue
      ptr="$(brief_requirement_pointer "$brief" 2>/dev/null)" || continue
      [ -n "$ptr" ] || continue
      if _in_list "$ptr" "$queue" || _in_list "./$ptr" "$queue"; then cands="$cands"$'\n'"$brief"; fi
    done
  fi
  [ -f "$TRAIL_LEDGER" ] && cands="$cands"$'\n'"$TRAIL_LEDGER"
  # This run's dismissed-finding drafts (automate-dismissed.sh dismissed-drafts):
  # propose-only requirement files with no done heading (every finding line is
  # `> `-quoted), so the evidence gate never calls gh for them. A dropped /
  # fix-now draft is deleted on disk and so is no longer a candidate.
  # A `--parallel` parent also carries its lanes' drafts (`<run_id>-L<n>--…`,
  # mirroring automate-dismissed.sh's _dismissed_lane_drafts — parallel-automate/05).
  for p in "$DRAFT_DIR/$run_id"--*--dismissed-*.md "$DRAFT_DIR/$run_id"-L[0-9]*--*--dismissed-*.md; do
    _trail_is_run_draft "$run_id" "$p" || continue
    [ -f "$p" ] && [ ! -L "$p" ] && cands="$cands"$'\n'"$p"
  done

  # Drop gitignored candidates (this is how the ledger's repo-allowlist is honoured).
  TRAIL_KEPT=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    _in_list "$p" "$TRAIL_KEPT" && continue
    [ "$TRAIL_SKIP_IGNORE_DROP" = 1 ] || { git check-ignore -q -- "$p" 2>/dev/null && continue; }
    TRAIL_KEPT="${TRAIL_KEPT:+$TRAIL_KEPT$'\n'}$p"
  done <<EOF
$cands
EOF

  return 0
}

# _done_prs <requirement-file> — the gate's view of a requirement, keyed on the
# SAME predicate as automate-helpers.sh `is_done` (a `^## Status:` heading
# reading done / done_with_escalation, sentinel or not): prints one line per such
# heading block — the first `https?://…/pull/<n>` token of each `- **PR:**`
# line in it (an annotated value like `<url> (merged by …)` yields the URL), or
# `-` when the block names no parseable PR. The ONE exemption is the exact
# heading `automate-helpers.sh reconcile-status --apply` writes for an owner's
# `# abandoned:` Queue row — `## Status: done_with_escalation — ABANDONED
# (- [x] <path>  # abandoned: <reason>)`, em dash byte-exact (passed in as
# $'\xe2\x80\x94', never a source literal, so no locale or editor can shift it):
# an owner decision, not a shipped-work claim, so it prints nothing. Any other
# heading merely containing "ABANDONED" is a done claim like any other. Prints
# nothing for a requirement with no done heading. A block runs to the next
# `## ` heading or EOF. The PR token excludes markdown link punctuation
# (`[]()<>`), so `[<url>](<url>)` and `<url>` yield the bare URL.
AB_PREFIX="## Status: done_with_escalation "$'\xe2\x80\x94'" ABANDONED (- [x] "
_done_prs() {
  awk -v ab="$AB_PREFIX" '
    function flush() { if (inb && !seen) print "-"; inb = 0; seen = 0 }
    /^## Status:[[:space:]]*done(_with_escalation)?([^A-Za-z0-9_]|$)/ {
      flush()
      if (!(index($0, ab) == 1 && $0 ~ /  # abandoned: .*\)[[:space:]]*$/)) { inb = 1; seen = 0 }
      next
    }
    inb && /^## / { flush(); next }
    inb && /^- \*\*PR:\*\*/ {
      if (match($0, /https?:\/\/[^][:space:]()<>]+\/pull\/[0-9]+/)) print substr($0, RSTART, RLENGTH); else print "-"
      seen = 1; next
    }
    END { flush() }
  ' "$1" 2>/dev/null
}

# _outcome_prs <brief-file> — every PR a done/ brief's Outcome section names.
# The section opens at an `## Outcome` / `### Outcome` heading — whitespace
# after the hashes, then whitespace, a colon or end of line after the word
# (`## Outcome — ESCALATED`, `## Outcome:`; never `## Outcomes Rubric`,
# `##Outcome` or `## Outcome-ish`) — and runs
# to the next H1–H3 heading. One line per `- **PR:**` line (its first
# `…/pull/<n>` token, or `-`), and `-` for a section naming no PR at all (fail
# closed). Prints nothing for a brief with no Outcome section.
_outcome_prs() {
  awk '
    function flush() { if (o && !seen) print "-"; o = 0; seen = 0 }
    /^(##|###)[[:space:]]+Outcome([[:space:]:]|$)/ { flush(); o = 1; seen = 0; next }
    o && /^(#|##|###)[[:space:]]/ { flush(); next }
    o && /^- \*\*PR:\*\*/ {
      if (match($0, /https?:\/\/[^][:space:]()<>]+\/pull\/[0-9]+/)) print substr($0, RSTART, RLENGTH); else print "-"
      seen = 1; next
    }
    END { flush() }
  ' "$1" 2>/dev/null
}

# _gate_keep <trail-path> <file-to-read> — 0 when the content of <file-to-read>
# (the path's working copy, or a blob written to a temp file) may ride under
# <trail-path>; 1 when it carries a done claim whose PR is not verifiably
# merged. `.supervisor/requirements/**.md` → _done_prs; `.supervisor/jobs/done/*.md`
# → _outcome_prs; any other path → 0. Every named PR must read `merged` via
# `automate-helpers.sh reconcile-item` (cached per URL in GATE_CACHE); `-`,
# OPEN, CLOSED or an unreadable forge ⇒ 1 (fail closed).
GATE_CACHE=""
_gate_keep() {
  local p="$1" f="$2" prs u st hit tab=$'\t' verdict=0
  case "$p" in
    .supervisor/requirements/*.md) prs="$(_done_prs "$f")" ;;
    .supervisor/jobs/done/*.md)    prs="$(_outcome_prs "$f")" ;;
    *) return 0 ;;
  esac
  [ -n "$prs" ] || return 0
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    case "$u" in
      http://*/pull/*|https://*/pull/*)
        hit="$(printf '%s' "$GATE_CACHE" | awk -F'\t' -v u="$u" '$1 == u {print $2; exit}')"
        if [ -n "$hit" ]; then st="$hit"; else
          st="$(bash "$HERE/automate-helpers.sh" reconcile-item "$u" 2>/dev/null | tail -n1)"
          [ -n "$st" ] || st="unreadable"
          GATE_CACHE="$GATE_CACHE$u$tab$st"$'\n'
        fi ;;
      *) st="unreadable" ;;
    esac
    [ "$st" = "merged" ] || verdict=1
  done <<GATEPRS
$prs
GATEPRS
  return "$verdict"
}

# _evidence_gate — trail_pr only (never trail-unstage / closeout's owned set:
# it calls gh). A trail must never commit a done claim for unmerged work: a
# TRAIL_KEPT requirement or done/ brief failing _gate_keep is dropped, named
# (`; excluded <path> — pr not merged`) and recorded in TRAIL_GATED, which
# trail_pr uses to RETRACT such a claim an earlier push left on a reused trail
# branch, and which _stage_tip never stages. Always returns 0.
TRAIL_GATED=""
_evidence_gate() {
  local p kept_new=""
  TRAIL_GATED=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if _gate_keep "$p" "$p"; then
      kept_new="${kept_new:+$kept_new$'\n'}$p"
    else
      TRAIL_EXCLUDED="$TRAIL_EXCLUDED; excluded $p — pr not merged"
      TRAIL_GATED="${TRAIL_GATED:+$TRAIL_GATED$'\n'}$p"
    fi
  done <<GATEKEPT
$TRAIL_KEPT
GATEKEPT
  TRAIL_KEPT="$kept_new"
  return 0
}

# _trail_owned <rf_rel> <run_id> — run from the checkout root. The ONE
# "is this dirty/staged path this run's own trail?" set, shared by trail-unstage
# and closeout step 4: today's candidates (_trail_candidates → TRAIL_KEPT) ∪ the
# run's two sidecar paths ∪ every path in `<run_id>.trail-staged` (written only
# by _stage_tip from this run's own pushed trail tip). The record matters because
# _stage_tip stages every merge-base..tip path, including ones no longer among
# today's candidates (a sidecar now failing its check, a Queue item edited out).
# Sets TRAIL_OWNED (newline list; also refreshes TRAIL_KEPT/TRAIL_EXCLUDED).
TRAIL_OWNED=""
_trail_owned() {
  local rf_rel="$1" run_id="$2" sc_dir
  sc_dir="$(dirname "$rf_rel")"
  _trail_candidates "$rf_rel" "$run_id"
  TRAIL_OWNED="$TRAIL_KEPT"$'\n'"$sc_dir/$run_id.review-heal-result.md"$'\n'"$sc_dir/$run_id.supervisor-result.md"
  [ -f "$sc_dir/$run_id.trail-staged" ] && TRAIL_OWNED="$TRAIL_OWNED"$'\n'"$(cut -f1 "$sc_dir/$run_id.trail-staged" 2>/dev/null)"
  return 0
}

# _stage_tip <tip> <base_ref> <record> — the checkout contract, applied from the
# trail branch TIP (never the working copy): for EVERY path the trail branch
# changes (`git diff --name-only <merge-base of base_ref and tip> <tip>` — every
# push on this branch, not only the latest delta) whose tip blob differs from
# <base_ref> (= origin/<default branch>), set the primary INDEX entry to that
# tip blob and record path/mode/blob in <record>. Skipped per path when HEAD already carries that blob (nothing for a
# pull to bring; a staged user change on that path is left alone); the index
# write is skipped when it already holds the blob (idempotent). Working copies
# are never touched. Always returns 0.
_stage_tip() {
  local tip="$1" base="$2" rec="$3" paths mb p ent mode_bits blob rec_line
  [ -n "$tip" ] || return 0
  mb="$(git merge-base "$base" "$tip" 2>/dev/null)" || return 0
  [ -n "$mb" ] || return 0
  paths="$(git diff --name-only --no-renames "$mb" "$tip" 2>/dev/null)" || return 0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    ent="$(git ls-tree "$tip" -- "$p" 2>/dev/null)"
    mode_bits="${ent%% *}"; blob="$(printf '%s' "$ent" | awk '{print $3}')"
    [ -n "$blob" ] || continue
    # Never stage a gate-excluded path (a done claim for unmerged work).
    _in_list "$p" "$TRAIL_GATED" && continue
    [ "$(git rev-parse -q --verify "$base:$p" 2>/dev/null)" = "$blob" ] && continue
    [ "$(git rev-parse -q --verify "HEAD:$p" 2>/dev/null)" = "$blob" ] && continue
    if [ "$(git ls-files -s -- "$p" 2>/dev/null | awk 'NR==1{print $2}')" != "$blob" ]; then
      git update-index --add --cacheinfo "$mode_bits,$blob,$p" >/dev/null 2>&1
    fi
    rec_line="$(printf '%s\t%s\t%s' "$p" "$mode_bits" "$blob")"
    grep -qxF -- "$rec_line" "$rec" 2>/dev/null || printf '%s\n' "$rec_line" >> "$rec" 2>/dev/null
  done <<EOF
$paths
EOF
  return 0
}

# _branch_mode <root> — the ONE reader (`setup-memory.sh mode`): off | on <branch> | unknown <reason>.
# A copy of this script WITHOUT its sibling reader (a stripped test/spy copy) reads `off` — unless
# the checkout's .gitignore carries mode-line text at all (the bare `loomwright-meta-branch` token,
# so an indented or no-space near-miss counts too), which is then `unknown` (loud), never off.
# FAIL-CLOSED on the answer's SHAPE: only an exact `off` or `on <non-empty>` passes through; empty
# output (a crashed reader) or anything unrecognised becomes `unknown …`, never off.
_branch_mode() {
  local m
  if [ ! -r "$HERE/setup-memory.sh" ]; then
    if grep -qF 'loomwright-meta-branch' "$1/.gitignore" 2>/dev/null; then
      echo "unknown setup-memory.sh is missing beside automate-trail.sh"
    else
      echo "off"
    fi
    return 0
  fi
  m="$(bash "$HERE/setup-memory.sh" --root "$1" mode 2>/dev/null | head -n1)"
  [ -n "$m" ] || m="unknown setup-memory.sh mode printed nothing"
  case "$m" in
    off|"on "?*|"unknown "*) ;;
    *) m="unknown setup-memory.sh mode printed '$m'" ;;
  esac
  printf '%s\n' "$m"
}

# _trail_meta_fail <rf_abs> <marker> <reason> <full> — the LOUD failure path (SKILL §"Branch mode"):
# one `meta-push FAILED:` Progress line on the run file itself, the fail-safe notify pair, and
# the gitignored marker (first line = UTC timestamp + reason, then meta-sync's full output).
_trail_meta_fail() {
  local rf="$1" mk="$2" why="$3" full="$4" ts payload msg
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  bash "$HERE/automate-helpers.sh" progress-append "$rf" "meta-push FAILED: $why" >/dev/null 2>&1 || true
  { printf '%s %s\n' "$ts" "$why"; [ -n "$full" ] && printf '%s\n' "$full"; } > "$mk" 2>/dev/null || true
  msg="automate trail: meta-push FAILED — $why"
  payload="$("$JQ" -cn --arg m "$msg" '{hook_event_name:"Notification",notification_type:"automate_meta_push",message:$m}' 2>/dev/null)"
  [ -n "$payload" ] && printf '%s' "$payload" | bash "$HERE/notify-desktop.sh" >/dev/null 2>&1 </dev/null
  bash "$HERE/send-webhook.sh" --event-type gate --gate-type automate_meta_push --context "$msg" >/dev/null 2>&1 </dev/null
  return 0
}

# _trail_meta_push <mode> <rf_rel> <rf_abs> <run_id> <reason> — branch-mode trail-pr (cwd = root).
# Same candidates + evidence gate as the PR path, EXCEPT the gitignore drop (after the migration
# every run-history path is ignored, so keeping it would push nothing). The ledger rides as a
# whole file (meta-sync line-unions it and its scrub rule (a) refuses a foreign `.repo`). This
# run's dropped dismissed drafts — absent on disk, last decision drop / fix-now / moved — are
# listed too, so meta-sync's `L absent, R == B` rule deletes them on the branch. One line; exit 0.
_trail_meta_push() {
  local bm="$1" rf_rel="$2" rf_abs="$3" run_id="$4" reason="$5"
  local mk; mk="$(dirname "$rf_abs")/$run_id.meta-push-failed"
  case "$bm" in
    "on "*) ;;
    *) local why="mode ${bm}"
       _trail_meta_fail "$rf_abs" "$mk" "$why" ""
       echo "trail-pr: meta-push FAILED — $why"; return 0 ;;
  esac
  local branch="${bm#on }"
  TRAIL_SKIP_IGNORE_DROP=1
  _trail_candidates "$rf_rel" "$run_id"
  TRAIL_SKIP_IGNORE_DROP=0
  _evidence_gate
  local excluded="$TRAIL_EXCLUDED" list dl dn dd dp
  list="$TRAIL_KEPT"
  dl="$(dirname "$rf_rel")/$run_id.dismissed-decisions"
  if [ -f "$dl" ]; then
    while IFS= read -r dn; do
      [ -n "$dn" ] || continue
      dp="$DRAFT_DIR/$dn"
      _trail_is_run_draft "$run_id" "$dp" || continue
      case "$dn" in */*) continue ;; esac
      [ -e "$dp" ] && continue
      _in_list "$dp" "$list" && continue
      dd="$(awk -F'\t' -v n="$dn" '$1 == n { d = $2 } END { print d }' "$dl" 2>/dev/null)"
      case "$dd" in drop|fix-now|moved) list="${list:+$list$'\n'}$dp" ;; esac
    done <<DLIST
$(cut -f1 "$dl" 2>/dev/null | env LC_ALL=C sort -u)
DLIST
  fi
  local lf out rc=0 why
  lf="$(mktemp "${TMPDIR:-/tmp}/automate-trail-meta.XXXXXX" 2>/dev/null)" || { echo "trail-pr: skipped — mktemp failed$excluded"; return 0; }
  printf '%s\n' "$list" > "$lf"
  out="$(bash "${LOOMWRIGHT_META_SYNC_BIN:-$HERE/meta-sync.sh}" push --branch "$branch" --root "$PWD" --paths-from "$lf" --message "chore(supervisor): $run_id trail ($reason)" 2>&1)" || rc=$?
  rm -f "$lf"
  if [ "$rc" -eq 0 ]; then
    rm -f "$mk"
    case "$out" in
      *"meta_sync: no_changes"*) echo "trail-pr: skipped — meta no_changes$excluded" ;;
      *) echo "trail-pr: meta-pushed $branch$excluded" ;;
    esac
    return 0
  fi
  # A scrub hit prints one `meta_sync: scrub <path>: <rule>` line per hit: the first rides in the
  # reason, the full list in the marker. Otherwise the first meta_sync line is the reason.
  why="$(printf '%s\n' "$out" | sed -n 's/^meta_sync: \(scrub .*\)$/\1/p' | head -n1)"
  [ -n "$why" ] || why="$(printf '%s\n' "$out" | sed -n 's/^meta_sync: //p' | head -n1)"
  [ -n "$why" ] || why="meta-sync.sh push exited $rc"
  _trail_meta_fail "$rf_abs" "$mk" "$why" "$(printf '%s\n' "$out" | grep '^meta_sync: ')"
  echo "trail-pr: meta-push FAILED — $why$excluded"
  return 0
}

trail_pr() {
  local runfile="" reason="trail"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason) reason="${2:-trail}"; shift 2 || shift ;;
      *) [ -z "$runfile" ] && runfile="$1"; shift ;;
    esac
  done
  [ -n "$reason" ] || reason="trail"
  local skip_prefix="trail-pr: skipped —"
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo "$skip_prefix run file not found"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$skip_prefix git unavailable"; return 0; fi
  if ! command -v "$GH" >/dev/null 2>&1; then echo "$skip_prefix gh unavailable"; return 0; fi
  if ! command -v "$JQ" >/dev/null 2>&1; then echo "$skip_prefix jq unavailable"; return 0; fi

  local rf_dir rf_abs root rf_rel run_id
  rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "$skip_prefix run file not found"; return 0; }
  rf_abs="$rf_dir/$(basename "$runfile")"
  root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$skip_prefix not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  case "$rf_abs" in "$root"/*) rf_rel="${rf_abs#"$root"/}" ;; *) echo "$skip_prefix run file outside the checkout"; return 0 ;; esac
  run_id="$(basename "$runfile" .md)"
  TRAIL_ROOT="$root"
  cd "$root" || { echo "$skip_prefix cannot enter checkout"; return 0; }

  # ---- branch mode: push to the metadata branch instead of opening a PR -----
  local bm; bm="$(_branch_mode "$root")"
  if [ "$bm" != "off" ]; then
    _trail_meta_push "$bm" "$rf_rel" "$rf_abs" "$run_id" "$reason"
    return 0
  fi

  # ---- candidate paths (explicit; never -A / .) ----------------------------
  _trail_candidates "$rf_rel" "$run_id"
  # Evidence-gated stamps: a done-stamped requirement / done brief rides only
  # when its PR reads merged (never a done claim for unmerged work).
  _evidence_gate
  local excluded="$TRAIL_EXCLUDED" kept="$TRAIL_KEPT" ledger="$TRAIL_LEDGER" p

  # ---- idempotency: this run's trail PRs -----------------------------------
  local prefix="chore/$run_id-trail-" list open_branch open_url maxn
  list="$("$GH" pr list --state all --search "head:chore/$run_id-trail" --limit 100 --json number,url,state,headRefName 2>/dev/null)"
  if [ $? -ne 0 ] || ! printf '%s' "$list" | "$JQ" -e 'type == "array"' >/dev/null 2>&1; then
    echo "$skip_prefix gh pr list failed$excluded"; return 0
  fi
  local sel='[.[] | select((.headRefName // "") | startswith($p)) | select((.headRefName | ltrimstr($p)) | test("^[0-9]+$")) | . + {n: (.headRefName | ltrimstr($p) | tonumber)}]'
  open_branch="$(printf '%s' "$list" | "$JQ" -r --arg p "$prefix" "$sel"' | map(select(.state == "OPEN")) | sort_by(.n) | last | .headRefName // empty' 2>/dev/null)"
  open_url="$(printf '%s' "$list" | "$JQ" -r --arg p "$prefix" "$sel"' | map(select(.state == "OPEN")) | sort_by(.n) | last | .url // empty' 2>/dev/null)"
  maxn="$(printf '%s' "$list" | "$JQ" -r --arg p "$prefix" "$sel"' | map(.n) | max // 0' 2>/dev/null)"
  case "$maxn" in ''|*[!0-9]*) maxn=0 ;; esac

  local base_branch
  base_branch="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  base_branch="${base_branch#origin/}"
  [ -n "$base_branch" ] || base_branch="main"

  if ! git fetch -q origin >/dev/null 2>&1; then echo "$skip_prefix git fetch failed$excluded"; return 0; fi

  local branch mode url="" base_ref orphan=0
  if [ -n "$open_branch" ]; then
    branch="$open_branch"; mode="pushed"; url="$open_url"
    base_ref="refs/remotes/origin/$branch"
    if ! git rev-parse -q --verify "$base_ref^{commit}" >/dev/null 2>&1; then
      echo "$skip_prefix open trail PR branch $branch missing on remote$excluded"; return 0
    fi
  else
    branch="$prefix$((maxn + 1))"; mode="opened"
    if git ls-remote --exit-code --heads origin "refs/heads/$branch" >/dev/null 2>&1; then
      orphan=1; base_ref="refs/remotes/origin/$branch"   # crash between push and PR-open
      git fetch -q origin "+refs/heads/$branch:$base_ref" >/dev/null 2>&1
    else
      base_ref="refs/remotes/origin/$base_branch"
    fi
    if ! git rev-parse -q --verify "$base_ref^{commit}" >/dev/null 2>&1; then
      echo "$skip_prefix base $base_ref unavailable$excluded"; return 0
    fi
  fi

  # ---- which candidates differ from the trail base -------------------------
  TRAIL_TMP="$(mktemp -d "${TMPDIR:-/tmp}/automate-trail-tmp.XXXXXX" 2>/dev/null)"
  if [ -z "$TRAIL_TMP" ]; then echo "$skip_prefix mktemp failed$excluded"; return 0; fi
  trap trail_cleanup EXIT
  local changed="" lblob bblob src
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    src="$p"
    if [ "$p" = "$ledger" ]; then
      # base copy + ONLY this run's lines (automate_key prefix or run_id), never the whole local file
      src="$TRAIL_TMP/ledger"
      git show "$base_ref:$p" > "$src" 2>/dev/null || : > "$src"
      if [ -s "$src" ] && [ -n "$(tail -c1 "$src")" ]; then printf '\n' >> "$src"; fi
      local mine line
      mine="$("$JQ" -rR --arg r "$run_id" '(try fromjson catch null) as $o | select(($o | type) == "object") | select((($o.automate_key // "") | tostring | startswith($r + "\u001f")) or ($o.run_id == $r)) | .' "$p" 2>/dev/null)"
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        grep -qxF -- "$line" "$src" 2>/dev/null || printf '%s\n' "$line" >> "$src"
      done <<EOF
$mine
EOF
    fi
    lblob="$(git hash-object --path "$p" -- "$src" 2>/dev/null)"
    bblob="$(git rev-parse -q --verify "$base_ref:$p" 2>/dev/null)"
    [ -n "$lblob" ] && [ "$lblob" != "$bblob" ] && changed="${changed:+$changed$'\n'}$p"
  done <<EOF
$kept
EOF

  local title="chore(supervisor): $run_id trail ($reason)"
  local rec origin_base="refs/remotes/origin/$base_branch"
  rec="$(dirname "$rf_rel")/$run_id.trail-staged"

  # ---- retract: a gate-excluded path whose blob at the REUSED trail branch's
  # tip (e.g. from a v15.114.0/.1 park-time push) differs from origin/<default>'s
  # CURRENT blob and itself fails the gate is put back to origin/<default>'s
  # version (removed when main lacks it) in this commit, so the branch tip never
  # keeps a done stamp for unmerged work; named as `; retracted <path>`. The
  # comparison is against main's current blob, not the fork point, so a path
  # main changed after the fork that the trail branch never touched also counts
  # when its (old) tip blob fails the gate — harmless: the tip becomes main's
  # version. A transient gh failure fails such a claim closed too (see SKILL §6).
  local retract="" retracted="" retract_old="" rb
  if [ "$base_ref" != "$origin_base" ] && [ -n "$TRAIL_GATED" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      rb="$(git rev-parse -q --verify "$base_ref:$p" 2>/dev/null)"
      [ -n "$rb" ] || continue
      [ "$rb" = "$(git rev-parse -q --verify "$origin_base:$p" 2>/dev/null)" ] && continue
      if git cat-file blob "$rb" > "$TRAIL_TMP/retract" 2>/dev/null && _gate_keep "$p" "$TRAIL_TMP/retract"; then continue; fi
      retract="${retract:+$retract$'\n'}$p"
      retract_old="$retract_old$p"$'\t'"$rb"$'\n'   # the retracted blob, pinned now: the push below moves base_ref
      retracted="$retracted; retracted $p"
    done <<RETRACT
$TRAIL_GATED
RETRACT
  fi
  excluded="$excluded$retracted"

  # ---- retract a DROPPED dismissed draft from a REUSED (open or orphaned)
  # trail branch: an undecided draft can ride a pushed trail commit (no ask
  # under --non-interactive-fallback, at an --auto-merge MERGE, or when the
  # watcher's closeout runs first). A path matching this run's draft glob that
  # the branch TIP carries (or <run_id>.trail-staged records), that is ABSENT on
  # disk, and whose <run_id>.dismissed-decisions last row reads drop / fix-now
  # (or `moved`: an UNDECIDED draft automate-dismissed.sh retired because its
  # finding moved to the other bucket — the finding rides in its new draft) is
  # `git rm`'d from the tip and dropped from the primary index — named
  # `; retracted <path>`. No ledger row ⇒ left alone (never guess). Never on a
  # fresh branch cut from origin/<default>, and never when origin/<default>
  # already carries the same blob (that draft is main's content: the owner's
  # hand delete — see SKILL §6).
  local dretract="" dretract_old="" dl dp dn dd
  dl="$(dirname "$rf_rel")/$run_id.dismissed-decisions"
  if [ "$base_ref" != "$origin_base" ] && [ -f "$dl" ]; then
    while IFS= read -r dp; do
      [ -n "$dp" ] || continue
      _trail_is_run_draft "$run_id" "$dp" || continue
      _in_list "$dp" "$dretract" && continue
      [ -e "$dp" ] && continue
      dn="${dp##*/}"
      dd="$(awk -F'\t' -v n="$dn" '$1 == n { d = $2 } END { print d }' "$dl" 2>/dev/null)"
      case "$dd" in drop|fix-now|moved) ;; *) continue ;; esac
      rb="$(git rev-parse -q --verify "$base_ref:$dp" 2>/dev/null)"
      [ -n "$rb" ] || continue
      [ "$rb" = "$(git rev-parse -q --verify "$origin_base:$dp" 2>/dev/null)" ] && continue
      dretract="${dretract:+$dretract$'\n'}$dp"
      dretract_old="$dretract_old$dp"$'\t'"$rb"$'\n'
      excluded="$excluded; retracted $dp"
    done <<DRETRACT
$(git ls-tree -r --name-only "$base_ref" -- "$DRAFT_DIR" 2>/dev/null)
$([ -f "$rec" ] && cut -f1 "$rec" 2>/dev/null)
DRETRACT
  fi

  if [ -z "$changed" ] && [ -z "$retract" ] && [ -z "$dretract" ] && [ "$orphan" -eq 0 ]; then
    # Nothing new to push, but an open trail branch still carries earlier pushes
    # whose index entries a PICK trail-unstage may have dropped: re-apply the
    # contract from that branch tip.
    [ "$mode" = "pushed" ] && _stage_tip "$base_ref" "$origin_base" "$rec"
    trail_cleanup; trap - EXIT
    echo "$skip_prefix trail already up to date$excluded"; return 0
  fi

  if [ -n "$changed" ] || [ -n "$retract" ] || [ -n "$dretract" ]; then
    TRAIL_WT="$TRAIL_TMP/wt"
    if ! git worktree add -q --detach "$TRAIL_WT" "$base_ref" >/dev/null 2>&1; then
      TRAIL_WT=""; trail_cleanup; trap - EXIT
      echo "$skip_prefix git worktree add failed$excluded"; return 0
    fi
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      mkdir -p "$TRAIL_WT/$(dirname "$p")"
      if [ "$p" = "$ledger" ]; then cp "$TRAIL_TMP/ledger" "$TRAIL_WT/$p"; else cp "$p" "$TRAIL_WT/$p"; fi
      git -C "$TRAIL_WT" add -- "$p" >/dev/null 2>&1
    done <<EOF
$changed
EOF
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if git rev-parse -q --verify "$origin_base:$p" >/dev/null 2>&1; then
        git -C "$TRAIL_WT" checkout -q "$origin_base" -- "$p" >/dev/null 2>&1
      else
        git -C "$TRAIL_WT" rm -q --cached --ignore-unmatch -- "$p" >/dev/null 2>&1
        rm -f "$TRAIL_WT/$p"
      fi
    done <<RETRACT
$retract
RETRACT
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      git -C "$TRAIL_WT" rm -q --ignore-unmatch -- "$p" >/dev/null 2>&1
    done <<DRETRACT
$dretract
DRETRACT
    if ! git -C "$TRAIL_WT" commit -q -m "$title" >/dev/null 2>&1; then
      trail_cleanup; trap - EXIT
      echo "$skip_prefix git commit failed$excluded"; return 0
    fi
    if ! git -C "$TRAIL_WT" push -q origin "HEAD:refs/heads/$branch" >/dev/null 2>&1; then
      trail_cleanup; trap - EXIT
      echo "$skip_prefix git push to $branch failed$excluded"; return 0
    fi
    # Checkout contract: stage, from the pushed trail TIP, EVERY path the
    # trail PR changes (not only this push's delta: an earlier push's entries
    # may have been dropped by a PICK trail-unstage) and record each blob in the
    # run's trail-staged record; closeout re-stages a recorded blob that has
    # LANDED upstream right before its pull.
    _stage_tip "$(git -C "$TRAIL_WT" rev-parse -q --verify HEAD 2>/dev/null)" "$origin_base" "$rec"
    # A retracted claim an earlier trail-pr staged in the primary index is
    # dropped from it too (index only; the working copy is never touched).
    while IFS=$'\t' read -r p rb; do
      [ -n "$p" ] && [ -n "$rb" ] || continue
      [ "$(git ls-files -s -- "$p" 2>/dev/null | awk 'NR==1{print $2}')" = "$rb" ] \
        && git restore --staged -- "$p" >/dev/null 2>&1
    done <<RETRACT
$retract_old$dretract_old
RETRACT
  elif [ "$orphan" -eq 1 ]; then
    _stage_tip "$base_ref" "$origin_base" "$rec"
  fi

  if [ "$mode" = "opened" ]; then
    local body out pl
    pl="$(printf '%s\n' "${changed:-(no new commit; opening the PR for an already-pushed branch)}" | sed 's/^/- /')"
    [ -n "$retract" ] && pl="$pl
$(printf '%s\n' "$retract" | sed 's/^/- retracted (done claim for unmerged work): /')"
    [ -n "$dretract" ] && pl="$pl
$(printf '%s\n' "$dretract" | sed 's/^/- retracted (dismissed draft dropped): /')"
    body="Run trail for \`/automate\` run \`$run_id\` (reason: \`$reason\`), committed by \`automate-trail.sh trail-pr\` from explicit paths only:

$pl

The engine never merges this PR; a human does."
    out="$("$GH" pr create --base "$base_branch" --head "$branch" --title "$title" --body "$body" 2>/dev/null)"
    url="$(printf '%s\n' "$out" | grep -Eo 'https?://[^[:space:]]+' | tail -n1)"
    if [ -z "$url" ]; then
      local view
      view="$("$GH" pr view "$branch" --json url,state 2>/dev/null)"
      if [ "$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null)" = "OPEN" ]; then
        url="$(printf '%s' "$view" | "$JQ" -r '.url // empty' 2>/dev/null)"; mode="pushed"
      fi
    fi
    if [ -z "$url" ]; then
      trail_cleanup; trap - EXIT
      echo "$skip_prefix gh pr create failed (branch $branch pushed; the next trail-pr opens its PR)$excluded"; return 0
    fi
  fi
  trail_cleanup; trap - EXIT
  echo "trail-pr: $mode $url$excluded"
  return 0
}

# --------------------------------------------------------------------------- #
# trail-unstage
# --------------------------------------------------------------------------- #
# trail-unstage <runfile> — PICK-time (SKILL §6 step 1, after RECONCILE's
# closeout, before RUN). Drops the index entries trail-pr staged under the
# checkout contract (`git restore --staged -- <path>`, working copies untouched)
# so the next item's `git checkout -b` + commit cannot sweep them into its PR.
# Only this run's trail paths (+ its two sidecars, + every path in its
# `<run_id>.trail-staged` record) that differ from HEAD in the index are touched. Safe to drop: the committed bytes live on the trail branch,
# and trail-pr records them in `<run_id>.trail-staged`, from which closeout
# re-stages a landed blob right before its pull. One line; always exit 0.
trail_unstage() {
  local runfile="${1:-}" S="trail-unstage: skipped —"
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo "$S run file not found"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$S git unavailable"; return 0; fi
  local rf_dir rf_abs root rf_rel run_id
  rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "$S run file not found"; return 0; }
  rf_abs="$rf_dir/$(basename "$runfile")"
  root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$S not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  case "$rf_abs" in "$root"/*) rf_rel="${rf_abs#"$root"/}" ;; *) echo "$S run file outside the checkout"; return 0 ;; esac
  run_id="$(basename "$runfile" .md)"
  cd "$root" || { echo "$S cannot enter checkout"; return 0; }
  # Branch mode stages nothing (trail-pr pushes to the metadata branch), so there is nothing to drop.
  case "$(_branch_mode "$root")" in "on "*) echo "$S branch mode"; return 0 ;; esac
  # Today's candidates ∪ sidecars ∪ the trail-staged record (_trail_owned).
  _trail_owned "$rf_rel" "$run_id"
  local p paths="$TRAIL_OWNED" staged="" n=0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    _in_list "$p" "$staged" && continue
    [ -n "$(git diff --cached --name-only -- "$p" 2>/dev/null)" ] || continue
    staged="${staged:+$staged$'\n'}$p"
  done <<EOF
$paths
EOF
  if [ -z "$staged" ]; then echo "$S nothing staged"; return 0; fi
  local done_l="" fail_l=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if git restore --staged -- "$p" >/dev/null 2>&1 && [ -z "$(git diff --cached --name-only -- "$p" 2>/dev/null)" ]; then
      done_l="${done_l:+$done_l, }$p"; n=$((n + 1))
    else
      fail_l="${fail_l:+$fail_l, }$p"
    fi
  done <<EOF
$staged
EOF
  if [ -n "$fail_l" ]; then
    echo "trail-unstage: unstaged $n path(s)${done_l:+ — $done_l}; FAILED $fail_l"
  else
    echo "trail-unstage: unstaged $n path(s) — $done_l"
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# trail-gate (PICK, after RECONCILE, before trail-unstage — SKILL §8)
# --------------------------------------------------------------------------- #
# trail-gate <runfile> — the single-open-PR invariant counts this run's own
# trail PR. One line, always exit 0:
#   trail-gate: PARK — trail PR open <url>[, <url>…] (merge or close it, then --resume)
#   trail-gate: PARK — <why the trail PR state could not be read>
#   trail-gate: clear — no open trail PR; synced — <base> at <sha>
#   trail-gate: clear — no open trail PR; sync skipped — <reason>
# WHY: closeout opens the trail PR after the item's merge; when the owner gave
# the next go first and merged the trail PR while the next item's PR was open,
# that merge moved the base under it, and with `strict` required checks the
# item PR read BEHIND and could not merge (run automate-2026-10-01-142337,
# trail PR #345 under PR #347). With the trail PR merged before the PICK, the
# next item branches off a base that already carries it. A PARK is fail-CLOSED:
# anything that stops the read (gh/jq/git missing, a failed `gh pr list`, a
# run file it cannot resolve) parks — the gate cannot tell an open trail PR
# from none. Once clear, it syncs the primary onto the base branch with
# closeout's own _sync_primary (re-staging the recorded trail blobs that landed
# first), so the merged trail fast-forwards and the next item branches off a
# base that carries it — before this gate nothing synced at PICK and a hand
# pull after trail-unstage refused. A sync refusal is reported, never a park.
trail_gate() {
  local runfile="${1:-}" K="trail-gate: PARK —" C="trail-gate: clear — no open trail PR;"
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo "$K run file not found"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$K git unavailable"; return 0; fi
  if ! command -v "$GH" >/dev/null 2>&1; then echo "$K gh unavailable"; return 0; fi
  if ! command -v "$JQ" >/dev/null 2>&1; then echo "$K jq unavailable"; return 0; fi
  local rf_dir rf_abs root rf_rel run_id
  rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "$K run file not found"; return 0; }
  rf_abs="$rf_dir/$(basename "$runfile")"
  root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$K not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  case "$rf_abs" in "$root"/*) rf_rel="${rf_abs#"$root"/}" ;; *) echo "$K run file outside the checkout"; return 0 ;; esac
  run_id="$(basename "$runfile" .md)"
  cd "$root" || { echo "$K cannot enter checkout"; return 0; }

  # The same lookup trail-pr uses to find (and reuse) this run's trail PRs.
  local prefix="chore/$run_id-trail-" list open
  list="$("$GH" pr list --state open --search "head:chore/$run_id-trail" --limit 100 --json url,state,headRefName 2>/dev/null)"
  if [ $? -ne 0 ] || ! printf '%s' "$list" | "$JQ" -e 'type == "array"' >/dev/null 2>&1; then
    echo "$K trail PR state unreadable (gh pr list failed)"; return 0
  fi
  if ! open="$(printf '%s' "$list" | "$JQ" -r --arg p "$prefix" '[.[] | select((.state // "") == "OPEN") | select((.headRefName // "") | startswith($p)) | select((.headRefName | ltrimstr($p)) | test("^[0-9]+$")) | .url] | join(", ")' 2>/dev/null)"; then
    echo "$K trail PR state unreadable (jq failed)"; return 0
  fi
  if [ -n "$open" ]; then
    echo "$K trail PR open $open (merge or close it, then --resume)"; return 0
  fi

  local base_branch bm=off
  base_branch="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  base_branch="${base_branch#origin/}"
  [ -n "$base_branch" ] || base_branch="main"
  case "$(_branch_mode "$root")" in "on "*) bm=on ;; esac
  if _sync_primary "$rf_rel" "$run_id" "$base_branch" "" "$bm"; then
    echo "$C synced — $base_branch at $(git rev-parse --short HEAD 2>/dev/null)"
  else
    echo "$C sync skipped — $SYNC_SKIP"
  fi
  return 0
}

# _restage_landed <record> <ref> — closeout step 4, immediately before the pull:
# for each recorded trail blob (path/mode/blob, written by trail-pr) that <ref>
# (the fetched origin/<base>) now carries at that path, and that HEAD does not,
# set the index entry to that blob — the checkout contract, re-applied at the
# one moment it is needed, only for bytes this run itself committed and that
# have landed upstream. Never touches the working copy. Always returns 0.
# Every entry it overwrites is remembered in RESTAGE_PRIOR (path TAB mode TAB
# blob, or path TAB - TAB - when the index had no stage-0 entry), so a refused
# pull can put the index back exactly as it was (_restore_prior).
RESTAGE_PRIOR=""
_restage_landed() {
  local rec="$1" ref="$2" path mode blob up prior tab=$'\t'
  RESTAGE_PRIOR=""
  [ -f "$rec" ] || return 0
  while IFS=$'\t' read -r path mode blob; do
    [ -n "$path" ] && [ -n "$blob" ] || continue
    up="$(git rev-parse -q --verify "$ref:$path" 2>/dev/null)"
    [ "$up" = "$blob" ] || continue
    [ "$(git rev-parse -q --verify "HEAD:$path" 2>/dev/null)" = "$blob" ] && continue
    prior="$(git ls-files -s -- "$path" 2>/dev/null | awk '$3 == "0" {print $1 "\t" $2; exit}')"
    [ -n "$prior" ] && [ "${prior#*"$tab"}" = "$blob" ] && continue
    if git update-index --add --cacheinfo "$mode,$blob,$path" >/dev/null 2>&1; then
      [ -n "$prior" ] || prior="-${tab}-"
      RESTAGE_PRIOR="${RESTAGE_PRIOR:+$RESTAGE_PRIOR$'\n'}$path$tab$prior"
    fi
  done < "$rec"
  return 0
}

# _restore_prior — undo _restage_landed after a refused `git pull --ff-only`
# (git refuses before it touches the index): each overwritten entry goes back
# to its recorded mode/blob, and an entry that did not exist is dropped from
# the index again (`--force-remove`, index only — the working copy is never
# touched). Returns 0; prints nothing.
_restore_prior() {
  local path mode blob
  [ -n "$RESTAGE_PRIOR" ] || return 0
  while IFS=$'\t' read -r path mode blob; do
    [ -n "$path" ] || continue
    if [ "$mode" = "-" ]; then
      git update-index --force-remove -- "$path" >/dev/null 2>&1
    else
      git update-index --cacheinfo "$mode,$blob,$path" >/dev/null 2>&1
    fi
  done <<EOF
$RESTAGE_PRIOR
EOF
  RESTAGE_PRIOR=""
  return 0
}

# _sync_primary <rf_rel> <run_id> <base_branch> <head_ref|""> <branch_mode on|off>
# — switch the primary checkout (cwd) onto <base_branch> and `git pull
# --ff-only` it. Shared by closeout step 4 and trail-gate (the PICK-time sync).
# Returns 0 when it pulled; 1 with SYNC_SKIP set to the reason otherwise (an
# `already synced` answer is a skip too). <head_ref> is the one other branch
# the primary may be on (closeout: the merged PR's head; trail-gate: none).
# This run's own trail paths (_trail_owned — the SAME set trail-unstage drops:
# today's candidates ∪ sidecars ∪ every path _stage_tip staged in this index,
# recorded in `<run_id>.trail-staged`) never count as "uncommitted changes";
# anything else tracked and modified refuses the sync. Untracked files do not
# refuse it (git itself refuses a pull that would overwrite one). Never a
# reset, a stash or a commit.
SYNC_SKIP=""
_sync_primary() {
  local rf_rel="$1" run_id="$2" base_branch="$3" head_ref="$4" bm="$5" cur outside p
  SYNC_SKIP=""
  cur="$(git symbolic-ref -q --short HEAD 2>/dev/null)"
  _trail_owned "$rf_rel" "$run_id"
  outside=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    p="${p:3}"; p="${p#\"}"; p="${p%\"}"
    _in_list "$p" "$TRAIL_OWNED" || outside="${outside:+$outside, }$p"
  done <<STATUS
$(git status --porcelain --untracked-files=no 2>/dev/null)
STATUS
  if [ -z "$cur" ]; then
    SYNC_SKIP="primary checkout is on a detached HEAD"
  elif [ "$cur" != "$base_branch" ] && [ -z "$head_ref" ]; then
    SYNC_SKIP="primary checkout is on $cur, not $base_branch"
  elif [ "$cur" != "$base_branch" ] && [ "$cur" != "$head_ref" ]; then
    SYNC_SKIP="primary checkout is on $cur (neither $base_branch nor the PR head)"
  elif [ -n "$outside" ]; then
    SYNC_SKIP="uncommitted changes outside the trail paths ($outside)"
  elif ! git fetch -q origin >/dev/null 2>&1; then
    SYNC_SKIP="git fetch failed"
  elif [ "$cur" = "$base_branch" ] && [ "$(git rev-parse -q --verify HEAD 2>/dev/null)" = "$(git rev-parse -q --verify "refs/remotes/origin/$base_branch" 2>/dev/null)" ]; then
    SYNC_SKIP="already synced ($base_branch at origin/$base_branch)"
  elif [ "$cur" != "$base_branch" ] && ! git checkout -q "$base_branch" >/dev/null 2>&1; then
    SYNC_SKIP="git checkout $base_branch refused"
  # Two-command elif list, deliberately: `_restage_landed` runs only once every
  # guard above has passed (never on a refused sync), and its status is ignored
  # (`;`) — only the pull's status decides this branch.
  # Branch mode: trail-pr never staged anything (no .trail-staged record), so nothing is re-staged.
  elif { [ "$bm" = on ] || _restage_landed "$(dirname "$rf_rel")/$run_id.trail-staged" "refs/remotes/origin/$base_branch"; };
       ! git pull -q --ff-only origin "$base_branch" >/dev/null 2>&1; then
    # A refused pull must not leave the re-staged trail blobs in the index
    # (they would ride along in the next commit made from the primary).
    _restore_prior
    SYNC_SKIP="git pull --ff-only refused (no reset attempted)"
  else
    return 0
  fi
  return 1
}

# --------------------------------------------------------------------------- #
# closeout
# --------------------------------------------------------------------------- #
# closeout <runfile> <item> <pr_url> [--session-id <sid>]
# The post-merge close-out (SKILL §6 "Post-merge close-out"). Deterministic,
# idempotent, fail-SAFE. Every output line is `closeout: <verb> — <detail>`
# (verb ∈ removed|synced|stamped|checked|reconciled|skipped), except the
# brief-repair and trail-pr lines, which are passed through verbatim. Execution
# order: evidence gate → brief repair → [run lock] 3a worktrees → 4 sync → 3b
# branch → 5 stamp → check off → 7b reconcile ## Current → ## Progress →
# trail-pr → [release]. It never ticks `_BACKLOG.md` (human-owned; the step-5
# stamp is what `resolve-backlog` reads — SKILL §2). The check-off runs BEFORE
# the trail so the trail PR records the closed-out item; the trail line is
# printed but never appended to ## Progress (appending it would leave the run
# file one line ahead of the trail, so every re-run would push again). The step
# lines reach ## Progress only when an ITEM step changed something (removed /
# stamped / checked / reconciled, or a non-skip brief repair); a `synced` line
# alone never appends, so a re-run after the trail PR merged leaves the run
# file byte-identical and its trail reads `skipped — trail already up to date`.
# NEVER: commits in the primary checkout, `git reset`, `git stash`, `git branch
# -d` / ancestry inference, touches another branch or worktree, merges anything.
CO_ROOT=""
CO_OWNER=""
CO_LOCKED=0
co_release() {
  if [ "$CO_LOCKED" -eq 1 ] && [ -n "$CO_OWNER" ]; then
    # --owner ONLY: never forward --session-id to release (run-lock.sh releases on
    # EITHER match, which would drop an outer PICK lock we merely re-entered).
    bash "$HERE/run-lock.sh" release --owner "$CO_OWNER" --root "$CO_ROOT" >/dev/null 2>&1
  fi
  CO_LOCKED=0
  return 0
}

# _co_current <rf_rel> <item> <pr_url> — closeout step 7b. Prints ONE line.
# Rewrites `## Current` for the item just closed out — the `- item:` line's
# `status:` field to `done`, the `- pause_reason:` line to `awaiting_go` when
# `## Status: paused` (`null` otherwise: a running loop is not paused) — ONLY
# when that line names THIS item AND THIS pr, and only after the Queue reads
# `- [x] <item>` (a failed check-off must not leave Current saying done while
# the Queue says queued). A `## Current` naming another item/PR is never
# touched: the merge watcher can fire after the owner already --resumed and a
# later item was picked. Every other line is byte-unchanged; `## Status` is
# never rewritten. The write goes through `automate-helpers.sh current-set`
# (validated atomic rename through runfile-write's `_runfile_install … full`,
# SKILL §3) — never a `generator | runfile-write` pipe, whose failing generator
# the helper cannot see.
_co_current() {
  local rf="$1" item="$2" pr="$3" S="closeout: skipped —"
  if ! grep -qxF -- "- [x] $item" "$rf" 2>/dev/null; then
    echo "$S ## Current not reconciled ($item not checked off)"; return 0
  fi
  local cur_line cur_raw cur_item cur_pr cur_status cur_reason run_status want
  cur_line="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- item: /{print; exit}' "$rf" 2>/dev/null)"
  if [ -z "$cur_line" ]; then echo "$S no ## Current item line"; return 0; fi
  _co_field() { printf '%s\n' "$cur_line" | awk -v k="$1" 'BEGIN{FS=" [|] "} {sub(/^- /,""); for(i=1;i<=NF;i++) if (index($i, k ": ")==1) {print substr($i, length(k)+3); exit}}'; }
  cur_raw="$(_co_field item)"; cur_item="${cur_raw#./}"
  cur_pr="$(_co_field pr)"; cur_status="$(_co_field status)"
  if [ "$cur_item" != "$item" ] || [ "$cur_pr" != "$pr" ]; then
    echo "$S ## Current is ${cur_item:-?} (${cur_pr:-no pr}), not this item/PR"; return 0
  fi
  run_status="$(sed -n 's/^## Status:[[:space:]]*\([A-Za-z_]*\).*/\1/p' "$rf" | head -n1)"
  if [ "$run_status" = "paused" ]; then want="awaiting_go"; else want="null"; fi
  cur_reason="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- pause_reason:/{sub(/^- pause_reason:[[:space:]]*/,""); sub(/[[:space:]]+$/,""); print; exit}' "$rf" 2>/dev/null)"
  if [ "$cur_status" = "done" ] && [ "$cur_reason" = "$want" ]; then
    echo "$S ## Current already done"; return 0
  fi
  # The write goes through `automate-helpers.sh current-set` (SKILL §3 "`## Current`
  # moves only through `current-set`"): the RAW stored item of the CURRENT line (not
  # the `./`-stripped comparison value), status done, the wanted pause_reason — the
  # item is unchanged, so current-set keeps the line's pr/branch and every other line.
  if bash "$HERE/automate-helpers.sh" current-set "$rf" --item "$cur_raw" --status done --pause-reason "$want" >/dev/null 2>&1; then
    echo "closeout: reconciled — ## Current $item status done, pause_reason $want"
  else
    echo "$S ## Current runfile-write refused"
  fi
  return 0
}

closeout() {
  local runfile="" item="" pr_url="" sid=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --session-id) sid="${2:-}"; shift 2 || shift ;;
      *) if [ -z "$runfile" ]; then runfile="$1"; elif [ -z "$item" ]; then item="$1"; elif [ -z "$pr_url" ]; then pr_url="$1"; fi; shift ;;
    esac
  done
  local S="closeout: skipped —"
  if [ -z "$runfile" ] || [ -z "$item" ] || [ -z "$pr_url" ]; then echo "$S missing argument"; return 0; fi
  if [ ! -f "$runfile" ]; then echo "$S run file not found"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$S git unavailable"; return 0; fi
  if ! command -v "$JQ" >/dev/null 2>&1; then echo "$S jq unavailable"; return 0; fi
  if ! command -v "$GH" >/dev/null 2>&1 || ! "$GH" auth status >/dev/null 2>&1; then echo "$S gh unavailable"; return 0; fi

  local rf_dir rf_abs root rf_rel run_id
  rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "$S run file not found"; return 0; }
  rf_abs="$rf_dir/$(basename "$runfile")"
  root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$S not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  CO_BRANCH_MODE=off
  case "$(_branch_mode "$root")" in "on "*) CO_BRANCH_MODE=on ;; esac
  case "$rf_abs" in "$root"/*) rf_rel="${rf_abs#"$root"/}" ;; *) echo "$S run file outside the checkout"; return 0 ;; esac
  run_id="$(basename "$runfile" .md)"
  item="${item#./}"
  cd "$root" || { echo "$S cannot enter checkout"; return 0; }
  local HLP="$HERE/automate-helpers.sh"

  # ---- 1. evidence gate (prints only when it stops the close-out) -----------
  local st
  st="$(bash "$HLP" reconcile-item "$pr_url" 2>/dev/null)"
  if [ "$st" != "merged" ]; then echo "$S pr not merged (${st:-unknown})"; return 0; fi

  # ---- 2. brief repair (its own line, passed through) -----------------------
  local lines="" l did=0
  l="$(bash "$HLP" brief-repair "$item" "$pr_url" 2>/dev/null | tail -n1)"
  [ -n "$l" ] || l="brief-repair: skipped — no output"
  echo "$l"; lines="$l"
  case "$l" in *"skipped —"*) ;; *) did=1 ;; esac

  # ---- steps 3–7 under the run lock -----------------------------------------
  # The step numbers are the SKILL's labels (§6 "Post-merge close-out"); the
  # EXECUTION order is 3a → 4 → 3b → 5 → 7 → 7b → 6, and the blocks below follow it.
  CO_ROOT="$root"; CO_OWNER="automate-closeout:$run_id"
  local lk rc
  if [ -n "$sid" ]; then
    lk="$(bash "$HERE/run-lock.sh" acquire --owner "$CO_OWNER" --session-id "$sid" --root "$root" 2>/dev/null)"; rc=$?
  else
    lk="$(bash "$HERE/run-lock.sh" acquire --owner "$CO_OWNER" --root "$root" 2>/dev/null)"; rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    local holder; holder="$(printf '%s\n' "$lk" | sed -n 's/.*run_lock_held owner=\([^ ]*\).*/\1/p' | head -n1)"
    echo "$S run lock held by ${holder:-unknown}"; return 0
  fi
  CO_LOCKED=1
  trap co_release EXIT

  local view head_ref head_oid
  view="$("$GH" pr view "$pr_url" --json headRefName,headRefOid 2>/dev/null)"
  head_ref="$(printf '%s' "$view" | "$JQ" -r '.headRefName // empty' 2>/dev/null)"
  head_oid="$(printf '%s' "$view" | "$JQ" -r '.headRefOid // empty' 2>/dev/null)"

  local base_branch
  base_branch="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)"
  base_branch="${base_branch#origin/}"
  [ -n "$base_branch" ] || base_branch="main"

  # ---- 3a. worktrees on the PR's head branch (never the primary; runs 1st) --
  local wt_line="" wt_list wt salv dirty wrem="" wkeep=""
  if [ -z "$head_ref" ] || [ -z "$head_oid" ]; then
    wt_line="$S head branch unresolved (gh pr view headRefName/headRefOid failed)"; head_ref=""
  elif [ "$head_ref" = "$base_branch" ]; then
    wt_line="$S head branch is the base branch"; head_ref=""
  else
    wt_list="$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$head_ref" '
      /^worktree /{p=substr($0,10); n++} /^branch /{ if (n>1 && substr($0,8)==b) print p }')"
    local wtip
    while IFS= read -r wt; do
      [ -n "$wt" ] || continue
      [ "$(cd "$wt" 2>/dev/null && pwd -P)" = "$root" ] && continue
      # Same squash-safe tip check as 3b: `git worktree remove` (no --force)
      # still deletes GITIGNORED content, which worktree-salvage.sh skips by
      # design — so a worktree whose HEAD is not the merged head (a same-named
      # branch reused for other work) is kept, never salvaged or removed.
      wtip="$(git -C "$wt" rev-parse -q --verify HEAD 2>/dev/null)"
      if [ "$wtip" != "$head_oid" ]; then
        wkeep="${wkeep:+$wkeep, }$wt (tip ${wtip:0:12} != merged head ${head_oid:0:12})"
        continue
      fi
      salv="$(bash "$HERE/worktree-salvage.sh" "$wt" --reason "automate closeout" 2>/dev/null)"
      dirty="$(git -C "$wt" status --porcelain 2>/dev/null)"
      if [ -z "$dirty" ] && git worktree remove "$wt" >/dev/null 2>&1; then
        wrem="${wrem:+$wrem, }$wt"
      elif [ -n "$dirty" ]; then
        wkeep="${wkeep:+$wkeep, }$wt still dirty after salvage${salv:+ (salvaged to $salv)}"
      else
        wkeep="${wkeep:+$wkeep, }$wt (git worktree remove refused)"
      fi
    done <<WTLIST
$wt_list
WTLIST
    if [ -n "$wrem" ] && [ -n "$wkeep" ]; then wt_line="closeout: removed — worktree $wrem; kept $wkeep"
    elif [ -n "$wrem" ]; then wt_line="closeout: removed — worktree $wrem"
    elif [ -n "$wkeep" ]; then wt_line="$S kept worktree $wkeep"
    else wt_line="$S already removed (no worktree on $head_ref)"
    fi
  fi
  echo "$wt_line"; lines="$lines"$'\n'"$wt_line"
  case "$wt_line" in "closeout: removed"*) did=1 ;; esac

  # ---- 4. sync the primary onto the base branch (runs 2nd, before 3b) -------
  # _sync_primary (shared with trail-gate's PICK-time sync) holds the guards,
  # the .trail-staged re-stage and the ff-only pull.
  local sy
  if _sync_primary "$rf_rel" "$run_id" "$base_branch" "$head_ref" "$CO_BRANCH_MODE"; then
    # Deliberately NOT `did=1`: a sync is checkout housekeeping, not close-out
    # progress for THIS item. `main` moves for reasons unrelated to the item —
    # most often this run's own merged trail PR — so counting it made a re-run
    # whose every item step skipped append its skip lines to ## Progress, which
    # gave trail-pr a diff and opened a fresh trail PR holding only those lines
    # (run automate-2026-10-01-142337: #329 merged → RECONCILE re-run → #330),
    # and the next re-run would do it again.
    sy="closeout: synced — $base_branch at $(git rev-parse --short HEAD 2>/dev/null)"
  else
    sy="$S $SYNC_SKIP"
  fi
  echo "$sy"; lines="$lines"$'\n'"$sy"

  # ---- 3b. the local head branch (runs 3rd, after 4; squash-safe tip check) -
  local br tip
  if [ -z "$head_ref" ]; then
    br="$S branch unresolved"
  elif ! git rev-parse -q --verify "refs/heads/$head_ref" >/dev/null 2>&1; then
    br="$S already deleted (no local $head_ref)"
  else
    tip="$(git rev-parse "refs/heads/$head_ref" 2>/dev/null)"
    if [ "$(git symbolic-ref -q --short HEAD 2>/dev/null)" = "$head_ref" ]; then
      br="$S branch checked out in primary ($head_ref)"
    elif [ "$tip" != "$head_oid" ]; then
      br="$S local tip ${tip:0:12} != merged head ${head_oid:0:12} ($head_ref kept)"
    elif git branch -D "$head_ref" >/dev/null 2>&1; then
      br="closeout: removed — branch $head_ref (tip == merged head ${head_oid:0:12})"; did=1
    else
      br="$S git branch -D $head_ref refused (checked out in a kept worktree?)"
    fi
  fi
  echo "$br"; lines="$lines"$'\n'"$br"

  # ---- 5. requirement stamp (runs 4th; PASS shape — self-heal-advisory tail) -
  local sp done_brief="" b ptr
  if [ ! -f "$item" ]; then
    sp="$S requirement $item not found"
  elif grep -qF '<!-- loomwright:requirement-closeout -->' "$item" 2>/dev/null; then
    sp="$S already stamped"
  else
    if [ -r "$HERE/brief-pointer.sh" ]; then
      # shellcheck source=/dev/null
      . "$HERE/brief-pointer.sh"
      for b in .supervisor/jobs/done/*.md; do
        [ -f "$b" ] || continue
        ptr="$(brief_requirement_pointer "$b" 2>/dev/null)" || continue
        ptr="${ptr#./}"
        [ "$ptr" = "$item" ] || continue
        if [ -z "$done_brief" ] || [ "$b" -nt "$done_brief" ]; then done_brief="$b"; fi
      done
    fi
    if [ -z "$done_brief" ]; then
      sp="$S no done brief"
    elif printf '\n<!-- loomwright:requirement-closeout -->\n## Status: done\n- **Completed:** %s\n- **Brief:** %s\n- **PR:** %s\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$done_brief" "$pr_url" >> "$item" 2>/dev/null; then
      sp="closeout: stamped — $item (## Status: done, brief $done_brief)"; did=1
    else
      sp="$S requirement not writable"
    fi
  fi
  echo "$sp"; lines="$lines"$'\n'"$sp"

  # ---- 7. check off (runs 5th, BEFORE 6 so the trail PR records it; NO reason
  #      argument — a reason writes `# skipped: …`) ------------------------------
  local ck
  if grep -qxF -- "- [ ] $item" "$rf_rel" 2>/dev/null; then
    if bash "$HLP" queue-checkoff "$rf_rel" "$item" >/dev/null 2>&1 && grep -qxF -- "- [x] $item" "$rf_rel" 2>/dev/null; then
      ck="closeout: checked — - [x] $item"; did=1
    else
      ck="$S queue-checkoff failed"
    fi
  elif grep -qF -- "- [x] $item" "$rf_rel" 2>/dev/null; then
    ck="$S already checked off"
  else
    ck="$S $item not in ## Queue"
  fi
  echo "$ck"; lines="$lines"$'\n'"$ck"

  # ---- 7b. reconcile ## Current (runs 6th, after the check-off; SKILL §3
  #      "After a close-out") ----------------------------------------------------
  local cu
  cu="$(_co_current "$rf_rel" "$item" "$pr_url")"
  case "$cu" in "closeout: reconciled"*) did=1 ;; esac
  echo "$cu"; lines="$lines"$'\n'"$cu"
  if [ "$did" -eq 1 ]; then
    local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      bash "$HLP" progress-append "$rf_rel" "$ts closeout $pr_url: $l" >/dev/null 2>&1
    done <<PROGRESS
$lines
PROGRESS
  fi

  # ---- item_timing (iq02 T04): ONE script-written event per PR, appended to the
  # item's session log (a gitignored .supervisor/logs/ file — never a trail path,
  # so trail-pr does not carry it; /insights reads it locally). IDEMPOTENT like
  # every other closeout step: a re-run (AC11, the post-trail-merge RECONCILE)
  # finds this PR's item_timing already in the log and appends nothing. SILENT
  # and fail-SAFE — closeout prints only `closeout:` lines (CLOSEOUT_TABLE), so
  # no output here, and nothing here can change a step's verb or this
  # function's exit status.
  # --item scopes the record to THIS item's Progress segment: without it a multi-item
  # run's second close-out read the first item's pick/park/drains.
  ( _pt="$(bash "$(dirname "$HLP")/phase-timing.sh" --run "$rf_abs" --item "$item" 2>/dev/null)" || exit 0
    _sid="$(printf '%s' "$_pt" | jq -r '.session_id // empty' 2>/dev/null | tr -cd 'A-Za-z0-9_-')"
    [ -n "$_sid" ] || exit 0
    _logs="$(dirname "$(dirname "$rf_abs")")/logs"; [ -d "$_logs" ] || exit 0
    _lf="$_logs/$_sid.jsonl"
    [ -f "$_lf" ] && jq -Rne --arg pr "$pr_url" '[inputs | fromjson? | select(type == "object" and .event == "item_timing" and .pr_url == (if $pr == "" then null else $pr end))] | length > 0' < "$_lf" && exit 0   # item_timing-idempotence guard: this PR's row is already logged
    _line="$(printf '%s' "$_pt" | jq -c --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg pr "$pr_url" \
      '{event:"item_timing",ts:$ts,pr_url:(if $pr=="" then null else $pr end)} + .' 2>/dev/null)" || exit 0
    [ -n "$_line" ] && { printf '%s\n' "$_line" >> "$_lf"; } 2>/dev/null
  ) >/dev/null 2>&1 || true

  # ---- 6. trail (runs LAST, after 7; via the dispatcher — stub-able, spy-visible)
  l="$(bash "$HLP" trail-pr "$rf_abs" --reason closeout 2>/dev/null | tail -n1)"
  echo "${l:-trail-pr: skipped — no output}"

  co_release; trap - EXIT
  return 0
}

# --------------------------------------------------------------------------- #
# finalize-empty (SKILL §1.5 / §3 "`done`" / §4 step 1 — `resume-glob --finalize`)
# --------------------------------------------------------------------------- #
# finalize-empty <runfile> — the second writer of `## Status: done` (the first is
# the §6 "Termination" exit of a live loop). `closeout` never writes `done`, even
# when it checks off the last Queue item: it leaves `## Status: paused`,
# `pause_reason: awaiting_go`, `## Current` item `status: done` (§3 "After a
# close-out"). This finalizes exactly that state and nothing else. Fires ONLY when
# ALL hold: `## Status: paused`, `pause_reason: awaiting_go`, `remaining` 0 (no
# `- [ ]` row), and the `## Current` item line's `status: done` — re-checked under
# the lock. Then, in order: `run-lock.sh acquire --owner automate-finalize:<run_id>`
# (held ⇒ one skipped line, nothing written); ONE validated rewrite through
# `runfile-write` (`## Status: done`, `## Current` `- pause_reason: null` — that
# line authored by `current-set --pause-reason null` on the staged copy; every
# other byte unchanged); `progress-append "<ts> auto-finalized: queue empty after
# closeout"`; `trail-pr <runfile> --reason done` (the SAME call the Queue-resolved
# termination makes) and its line appended; branch mode OFF only, `trail-unstage
# <runfile>` (this is usually a FOREIGN run finalized from the current run's RESUME:
# its staged trail blobs would ride into the current run's next commit and make
# `_sync_primary` see a dirty index); the lock released in a trap.
# Prints `finalize-empty: finalized <runfile>` + the trail (+ unstage) lines, or ONE
# `finalize-empty: skipped — <reason>` line. Always exit 0 (fail-SAFE emitter).
FE_ROOT=""
FE_OWNER=""
FE_LOCKED=0
fe_release() {
  if [ "$FE_LOCKED" -eq 1 ] && [ -n "$FE_OWNER" ]; then
    bash "$HERE/run-lock.sh" release --owner "$FE_OWNER" --root "$FE_ROOT" >/dev/null 2>&1
  fi
  FE_LOCKED=0
  return 0
}

# _fe_ineligible <runfile> — prints why the run is NOT a finalize candidate
# (nothing when it is). Read-only; the `skipped — <reason>` text.
_fe_ineligible() {
  local rf="$1" st reason n cl cs
  st="$(sed -n 's/^## Status:[[:space:]]*\([A-Za-z_]*\).*/\1/p' "$rf" 2>/dev/null | head -n1)"
  if [ "$st" != "paused" ]; then echo "not paused"; return 0; fi
  reason="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- pause_reason:/{sub(/^- pause_reason:[[:space:]]*/,""); sub(/[[:space:]]+$/,""); print; exit}' "$rf" 2>/dev/null)"
  if [ "$reason" != "awaiting_go" ]; then echo "pause_reason ${reason:-absent}, not awaiting_go"; return 0; fi
  n="$(grep -c '^- \[ \] ' "$rf" 2>/dev/null)"; n="${n:-0}"
  if [ "$n" != "0" ]; then echo "$n unchecked item(s) remain"; return 0; fi
  cl="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- item: /{print; exit}' "$rf" 2>/dev/null)"
  cs="$(printf '%s\n' "$cl" | awk 'BEGIN{FS=" [|] "} {for(i=1;i<=NF;i++) if (index($i, "status: ")==1) {print substr($i, 9); exit}}')"
  if [ "$cs" != "done" ]; then echo "## Current status ${cs:-absent}, not done"; return 0; fi
  return 0
}

# _in_lane_clone <root> — succeeds when <root> is a lane clone of `/automate
# --parallel N` (parallel-automate/05, D2): its `.supervisor/lane.json` marker is
# present (the file `automate-lanes.sh lane-info` prints; absent ⇒ not a lane —
# never guessed from the path or the run id).
_in_lane_clone() { [ -f "$1/.supervisor/lane.json" ]; }

# _lane_run_id <root> — the lane marker's `run_id`, or empty when absent/unreadable.
_lane_run_id() {
  [ -f "$1/.supervisor/lane.json" ] || return 0
  jq -r '.run_id // empty | strings' "$1/.supervisor/lane.json" 2>/dev/null | head -n1
}

finalize_empty() {
  local runfile="${1:-}" S="finalize-empty: skipped —"
  if [ -z "$runfile" ] || [ ! -f "$runfile" ]; then echo "$S run file not found"; return 0; fi
  local rf_dir rf_abs root rf_rel run_id why
  # Eligibility first (read-only): an ineligible run is a plain skip whatever the
  # checkout looks like, so resume-glob --finalize stays silent about it.
  why="$(_fe_ineligible "$runfile")"
  if [ -n "$why" ]; then echo "$S $why"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$S git unavailable"; return 0; fi
  rf_dir="$(cd "$(dirname "$runfile")" 2>/dev/null && pwd -P)" || { echo "$S run file not found"; return 0; }
  rf_abs="$rf_dir/$(basename "$runfile")"
  root="$(git -C "$rf_dir" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$S not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  case "$rf_abs" in "$root"/*) rf_rel="${rf_abs#"$root"/}" ;; *) echo "$S run file outside the checkout"; return 0 ;; esac
  run_id="$(basename "$runfile" .md)"
  cd "$root" || { echo "$S cannot enter checkout"; return 0; }
  # parallel-automate/05: inside a lane clone only the lane's OWN run (lane.json
  # run_id) may be finalized; another run's file (or an unreadable run_id) is refused.
  if _in_lane_clone "$root" && [ "$(_lane_run_id "$root")" != "$run_id" ]; then
    echo "$S lane clone (not this lane's run)"; return 0
  fi
  why="$(_fe_ineligible "$rf_rel")"
  if [ -n "$why" ]; then echo "$S $why"; return 0; fi
  local HLP="$HERE/automate-helpers.sh"

  FE_ROOT="$root"; FE_OWNER="automate-finalize:$run_id"
  local lk rc holder
  lk="$(bash "$HERE/run-lock.sh" acquire --owner "$FE_OWNER" --root "$root" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    holder="$(printf '%s\n' "$lk" | sed -n 's/.*run_lock_held owner=\([^ ]*\).*/\1/p' | head -n1)"
    echo "$S run lock held by ${holder:-unknown}"; return 0
  fi
  FE_LOCKED=1
  trap fe_release EXIT
  # Re-check under the lock: a closeout/PICK may have moved the file in between.
  why="$(_fe_ineligible "$rf_rel")"
  if [ -n "$why" ]; then fe_release; trap - EXIT; echo "$S $why"; return 0; fi

  # ONE validated rewrite of the real file: the first `## Status:` line's `paused`
  # → `done` (any trailing text kept) and `## Current`'s `- pause_reason:` → `null`.
  # The pause_reason line is authored by `current-set --pause-reason null` (the
  # run-level form — SKILL §3: every pause_reason write is a current-set call),
  # run against the STAGED copy so the run file still changes in one atomic
  # `runfile-write`: a failure at any step leaves it byte-unchanged and the run
  # still eligible, so a later `--finalize` retries cleanly. Staged to a file and
  # redirected — never a `generator | runfile-write` pipe (§3).
  local tmp; tmp="$(mktemp "${rf_abs}.fe.XXXXXX")" || { fe_release; trap - EXIT; echo "$S cannot stage the rewrite"; return 0; }
  if ! awk '
      !st && /^## Status:/ { sub(/^## Status:[[:space:]]*paused/, "## Status: done"); st=1; print; next }
      { print }' "$rf_rel" > "$tmp" \
     || ! grep -q '^## Status: done' "$tmp" \
     || ! bash "$HLP" current-set "$tmp" --pause-reason null >/dev/null 2>&1 \
     || ! bash "$HLP" runfile-write "$rf_rel" < "$tmp" >/dev/null 2>&1; then
    rm -f "$tmp"; fe_release; trap - EXIT
    echo "$S runfile-write refused"; return 0
  fi
  rm -f "$tmp"
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  bash "$HLP" progress-append "$rf_rel" "$ts auto-finalized: queue empty after closeout" >/dev/null 2>&1
  echo "finalize-empty: finalized $runfile"
  local l
  l="$(bash "$HLP" trail-pr "$rf_abs" --reason done 2>/dev/null | tail -n1)"
  [ -n "$l" ] || l="trail-pr: skipped — no output"
  echo "$l"
  bash "$HLP" progress-append "$rf_rel" "$ts $l" >/dev/null 2>&1
  if [ "$(_branch_mode "$root")" = "off" ]; then
    l="$(bash "$HLP" trail-unstage "$rf_abs" 2>/dev/null | tail -n1)"
    echo "${l:-trail-unstage: skipped — no output}"
  fi
  fe_release; trap - EXIT
  return 0
}

# --------------------------------------------------------------------------- #
# closeout-others (SKILL §1.5 / §4 "Start order" / §8 — the cross-run close-out)
# --------------------------------------------------------------------------- #
# closeout-others <automate_dir> [--record <runfile>] — at start, BEFORE the PICK
# lock: for every `resume-glob` run file other than --record's whose `## Current`
# item line names a non-null item, a non-null `…/pull/<n>` pr, a status other than
# `done`, and whose PR `reconcile-item` reads `merged`, runs `closeout <that
# runfile> <item> <pr>` through the dispatcher (NO --session-id: its own
# `automate-closeout:<run_id>` lock and its own trail), then — branch mode OFF only
# — `trail-unstage <that runfile>` (a foreign run's staged trail blobs would ride
# into the current run's next commit and make `_sync_primary` see a dirty index).
# Per close-out: `closeout-others: <run_id> <item> <pr>`, that closeout's lines, the
# unstage line, that closeout's own `closeout-classify` answer (`complete` or its
# `leftover` rows — classified per invocation, never interleaved), and ONE record
# line `cross-run closeout <run_id> <item>: <complete | leftover <step> — <detail>>`
# — `closeout-others: recorded — …` when appended to --record's run file,
# `closeout-others: record — …` when there is no such file yet. The record line
# carries NO PR URL (a URL in a leftover detail becomes `<url>`), so
# `current-rebuild` can never attach another run's PR. Anything else (OPEN,
# closed-unmerged, unreadable, done, null) ⇒ that run is untouched and prints
# nothing. Never touches another run's Queue beyond closeout's own check-off.
# Always exit 0.
closeout_others() {
  local dir="" rec="" S="closeout-others: skipped —"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --record) rec="${2:-}"; shift 2 || shift ;;
      *) [ -z "$dir" ] && dir="$1"; shift ;;
    esac
  done
  if [ -z "$dir" ] || [ ! -d "$dir" ]; then echo "$S automate dir not found"; return 0; fi
  if ! command -v git >/dev/null 2>&1; then echo "$S git unavailable"; return 0; fi
  local d_abs root rec_abs="" HLP="$HERE/automate-helpers.sh"
  d_abs="$(cd "$dir" 2>/dev/null && pwd -P)" || { echo "$S automate dir not found"; return 0; }
  root="$(git -C "$d_abs" rev-parse --show-toplevel 2>/dev/null)"
  if [ -z "$root" ]; then echo "$S not a git checkout"; return 0; fi
  root="$(cd "$root" && pwd -P)"
  if [ -n "$rec" ] && [ -f "$rec" ]; then
    rec_abs="$(cd "$(dirname "$rec")" 2>/dev/null && pwd -P)/$(basename "$rec")"
  fi
  cd "$root" || { echo "$S cannot enter checkout"; return 0; }
  # parallel-automate/05 (Scope 3 amendment): a lane clone never closes out other
  # runs — the coordinator does that ONCE, in the primary, before the wave launches.
  if _in_lane_clone "$root"; then echo "$S lane clone"; return 0; fi
  local bm; bm="$(_branch_mode "$root")"
  local cands f cl item pr st run_id out verdict first summ rl l tab=$'\t'
  cands="$(bash "$HLP" resume-glob "$d_abs" 2>/dev/null)"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    if [ -n "$rec_abs" ] && [ "$f" = "$rec_abs" ]; then continue; fi
    cl="$(awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- item: /{print; exit}' "$f" 2>/dev/null)"
    [ -n "$cl" ] || continue
    item="$(printf '%s\n' "$cl" | awk 'BEGIN{FS=" [|] "} {sub(/^- /,""); for(i=1;i<=NF;i++) if (index($i, "item: ")==1) {print substr($i, 7); exit}}')"
    pr="$(printf '%s\n' "$cl" | awk 'BEGIN{FS=" [|] "} {for(i=1;i<=NF;i++) if (index($i, "pr: ")==1) {print substr($i, 5); exit}}')"
    st="$(printf '%s\n' "$cl" | awk 'BEGIN{FS=" [|] "} {for(i=1;i<=NF;i++) if (index($i, "status: ")==1) {print substr($i, 9); exit}}')"
    [ -n "$item" ] && [ "$item" != null ] || continue
    case "$pr" in http://*/pull/*|https://*/pull/*) ;; *) continue ;; esac
    [ "$st" != done ] || continue
    [ "$(bash "$HLP" reconcile-item "$pr" 2>/dev/null | tail -n1)" = merged ] || continue
    run_id="$(basename "$f" .md)"
    echo "closeout-others: $run_id $item $pr"
    out="$(bash "$HLP" closeout "$f" "$item" "$pr" 2>/dev/null)"
    [ -n "$out" ] && printf '%s\n' "$out"
    if [ "$bm" = off ]; then
      l="$(bash "$HLP" trail-unstage "$f" 2>/dev/null | tail -n1)"
      echo "${l:-trail-unstage: skipped — no output}"
    fi
    verdict="$(printf '%s\n' "$out" | bash "$HLP" closeout-classify --run "$run_id" --item "$item" --pr "$pr" 2>/dev/null)"
    [ -n "$verdict" ] || verdict="leftover$tab$run_id$tab$item$tab$pr${tab}classify${tab}closeout-classify printed nothing"
    printf '%s\n' "$verdict"
    if [ "$verdict" = complete ]; then
      summ="complete"
    else
      first="$(printf '%s\n' "$verdict" | grep -m1 "^leftover$tab")"
      summ="leftover $(printf '%s' "$first" | cut -f5) — $(printf '%s' "$first" | cut -f6-)"
      summ="$(printf '%s' "$summ" | sed -E 's#https?://[^[:space:]]+#<url>#g')"
    fi
    rl="cross-run closeout $run_id $item: $summ"
    if [ -n "$rec_abs" ] && bash "$HLP" progress-append "$rec_abs" "$(date -u +%Y-%m-%dT%H:%M:%SZ) $rl" >/dev/null 2>&1; then
      echo "closeout-others: recorded — $rl"
    else
      echo "closeout-others: record — $rl"
    fi
  done <<EOF
$cands
EOF
  return 0
}

# --------------------------------------------------------------------------- #
# dispatch
# --------------------------------------------------------------------------- #
main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    sidecar-check) sidecar_check "$@" ;;
    trail-pr)      trail_pr "$@" ;;
    closeout)      closeout "$@" ;;
    trail-unstage) trail_unstage "$@" ;;
    trail-gate)    trail_gate "$@" ;;
    finalize-empty) finalize_empty "$@" ;;
    closeout-others) closeout_others "$@" ;;
    ""|-h|--help)  grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /' ;;
    *) echo "automate-trail: unknown subcommand: $cmd" >&2 ;;
  esac
  return 0
}

main "$@"
exit 0
