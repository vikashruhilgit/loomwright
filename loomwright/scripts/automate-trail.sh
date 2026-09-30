#!/usr/bin/env bash
# automate-trail.sh — the `/automate` engine's post-park lifecycle MUTATORS.
# PROTOCOL AUTHORITY: `skills/automate-loop/SKILL.md` §6 "Trail PR at every
# park and at run end" (and §1.5's rows for each subcommand). Dispatched from
# `automate-helpers.sh` (`exec bash "$(dirname "$0")/automate-trail.sh" <subcmd>`)
# so the helper itself stays read-only toward git; THIS script is the carve-out.
#
# SCOPE OF ITS MUTATIONS (the whole list — anything else is a bug):
#   * `trail-pr` commits ONLY this run's explicit trail paths, from a temporary
#     `git worktree` off fresh origin/<default branch> (or off this run's open
#     trail branch), pushes ONLY to `chore/<run_id>-trail-<n>` (never forced),
#     opens/reuses ONE PR via `gh pr create`, and stages the COMMITTED blobs in
#     the primary checkout's index (see "Checkout contract" below).
#   * `closeout` removes ONLY this PR's head-branch worktrees (clean after
#     `worktree-salvage.sh`) and that local branch (`git branch -D`, only when
#     its tip == the PR's headRefOid), switches the primary to the base branch
#     and `git pull --ff-only`s it, appends the requirement stamp, checks the
#     Queue item off, and calls trail-pr. It NEVER commits in the primary.
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
#   trail-pr <runfile> [--reason <park_reason>]
#       One line: `trail-pr: opened <url>` | `trail-pr: pushed <url>` |
#       `trail-pr: skipped — <reason>`. Sidecars that fail `sidecar-check` are
#       excluded and named INSIDE that same line (`; excluded <path> — <reason>`),
#       so the loop can append it to `## Progress` with one progress-append.
#   closeout <runfile> <item> <pr_url> [--session-id <sid>]
#       The post-merge close-out (SKILL §6 "Post-merge close-out"): evidence
#       gate, brief repair, squash-safe worktree/branch cleanup, base-branch
#       sync, requirement stamp, Queue check-off, trail-pr. One line per step
#       (`closeout: <verb> — …`, brief-repair/trail-pr lines passed through);
#       idempotent; steps 3–7 run under run-lock.sh (re-enters a PICK lock via
#       --session-id; releases with --owner only).
#
# CHECKOUT CONTRACT (decision 4 of the post-park-lifecycle brief, proved by the
# post-merge-pull leg of test-automate-trail.sh): after a successful push,
# trail-pr sets the primary checkout's INDEX entry of every committed path to the
# exact COMMITTED blob (`git update-index --add --cacheinfo`), leaving working
# copies untouched. A later plain `git checkout main && git pull` then
# fast-forwards over those paths (index == incoming blob), and bytes that exist
# only locally BY DESIGN — Progress lines the live run file gained after the
# push, other runs' postmortem ledger lines — survive as ordinary unstaged
# modifications. Honest limits: a `git commit` made in the primary before the
# trail PR merges also commits those staged entries; a trail PR closed unmerged
# leaves them staged until `git restore --staged <path>`.
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
# read from scripts/drain-rounds.sh's ledger), and the hand-rebuilt item-10
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
    "dismissed", "rules_gate", "checks_untrusted"])
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
    "until_mergeable_log", "risk_classification", "heal_dismissed"])

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
# trail-pr (what to commit) and closeout (which dirty paths are "trail paths").
TRAIL_LEDGER=".supervisor/postmortem/results.jsonl"
TRAIL_KEPT=""
TRAIL_EXCLUDED=""
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

  # Drop gitignored candidates (this is how the ledger's repo-allowlist is honoured).
  TRAIL_KEPT=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    _in_list "$p" "$TRAIL_KEPT" && continue
    git check-ignore -q -- "$p" 2>/dev/null && continue
    TRAIL_KEPT="${TRAIL_KEPT:+$TRAIL_KEPT$'\n'}$p"
  done <<EOF
$cands
EOF

  return 0
}

trail_pr() {
  local runfile="" reason="park"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --reason) reason="${2:-park}"; shift 2 || shift ;;
      *) [ -z "$runfile" ] && runfile="$1"; shift ;;
    esac
  done
  [ -n "$reason" ] || reason="park"
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

  # ---- candidate paths (explicit; never -A / .) ----------------------------
  _trail_candidates "$rf_rel" "$run_id"
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
  if [ -z "$changed" ] && [ "$orphan" -eq 0 ]; then
    trail_cleanup; trap - EXIT
    echo "$skip_prefix trail already up to date$excluded"; return 0
  fi

  if [ -n "$changed" ]; then
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
    if ! git -C "$TRAIL_WT" commit -q -m "$title" >/dev/null 2>&1; then
      trail_cleanup; trap - EXIT
      echo "$skip_prefix git commit failed$excluded"; return 0
    fi
    if ! git -C "$TRAIL_WT" push -q origin "HEAD:refs/heads/$branch" >/dev/null 2>&1; then
      trail_cleanup; trap - EXIT
      echo "$skip_prefix git push to $branch failed$excluded"; return 0
    fi
    # Checkout contract: stage the COMMITTED blob of each path in the primary index.
    local ent mode_bits blob
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      ent="$(git -C "$TRAIL_WT" ls-tree HEAD -- "$p" 2>/dev/null)"
      mode_bits="${ent%% *}"; blob="$(printf '%s' "$ent" | awk '{print $3}')"
      [ -n "$blob" ] && git update-index --add --cacheinfo "$mode_bits,$blob,$p" >/dev/null 2>&1
    done <<EOF
$changed
EOF
  fi

  if [ "$mode" = "opened" ]; then
    local body out pl
    pl="$(printf '%s\n' "${changed:-(no new commit; opening the PR for an already-pushed branch)}" | sed 's/^/- /')"
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
# closeout
# --------------------------------------------------------------------------- #
# closeout <runfile> <item> <pr_url> [--session-id <sid>]
# The post-merge close-out (SKILL §6 "Post-merge close-out"). Deterministic,
# idempotent, fail-SAFE. Every output line is `closeout: <verb> — <detail>`
# (verb ∈ removed|synced|stamped|checked|skipped), except the brief-repair and
# trail-pr lines, which are passed through verbatim. Execution order: evidence
# gate → brief repair → [run lock] 3a worktrees → 4 sync → 3b branch → 5 stamp
# → check off + ## Progress → trail-pr → [release]. The check-off runs BEFORE
# the trail so the trail PR records the closed-out item; the trail line is
# printed but never appended to ## Progress (appending it would leave the run
# file one line ahead of the trail, so every re-run would push again).
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

  # ---- 3a. worktrees on the PR's head branch (never the primary) ------------
  local wt_line="" wt_list wt salv dirty wrem="" wkeep=""
  if [ -z "$head_ref" ] || [ -z "$head_oid" ]; then
    wt_line="$S head branch unresolved (gh pr view headRefName/headRefOid failed)"; head_ref=""
  elif [ "$head_ref" = "$base_branch" ]; then
    wt_line="$S head branch is the base branch"; head_ref=""
  else
    wt_list="$(git worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$head_ref" '
      /^worktree /{p=substr($0,10); n++} /^branch /{ if (n>1 && substr($0,8)==b) print p }')"
    while IFS= read -r wt; do
      [ -n "$wt" ] || continue
      [ "$(cd "$wt" 2>/dev/null && pwd -P)" = "$root" ] && continue
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

  # ---- 4. sync the primary onto the base branch ------------------------------
  # Trail paths (the SAME set trail-pr commits — including the ones it staged in
  # this index under its checkout contract) never count as "uncommitted
  # changes"; anything else tracked and modified refuses the sync. Untracked
  # files do not refuse it (git itself refuses a pull that would overwrite one).
  local sy cur outside p
  cur="$(git symbolic-ref -q --short HEAD 2>/dev/null)"
  _trail_candidates "$rf_rel" "$run_id"
  outside=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    p="${p:3}"; p="${p#\"}"; p="${p%\"}"
    _in_list "$p" "$TRAIL_KEPT" || outside="${outside:+$outside, }$p"
  done <<STATUS
$(git status --porcelain --untracked-files=no 2>/dev/null)
STATUS
  if [ -z "$cur" ]; then
    sy="$S primary checkout is on a detached HEAD"
  elif [ "$cur" != "$base_branch" ] && [ "$cur" != "$head_ref" ]; then
    sy="$S primary checkout is on $cur (neither $base_branch nor the PR head)"
  elif [ -n "$outside" ]; then
    sy="$S uncommitted changes outside the trail paths ($outside)"
  elif ! git fetch -q origin >/dev/null 2>&1; then
    sy="$S git fetch failed"
  elif [ "$cur" = "$base_branch" ] && [ "$(git rev-parse -q --verify HEAD 2>/dev/null)" = "$(git rev-parse -q --verify "refs/remotes/origin/$base_branch" 2>/dev/null)" ]; then
    sy="$S already synced ($base_branch at origin/$base_branch)"
  elif [ "$cur" != "$base_branch" ] && ! git checkout -q "$base_branch" >/dev/null 2>&1; then
    sy="$S git checkout $base_branch refused"
  elif ! git pull -q --ff-only origin "$base_branch" >/dev/null 2>&1; then
    sy="$S git pull --ff-only refused (no reset attempted)"
  else
    sy="closeout: synced — $base_branch at $(git rev-parse --short HEAD 2>/dev/null)"; did=1
  fi
  echo "$sy"; lines="$lines"$'\n'"$sy"

  # ---- 3b. the local head branch (after sync; squash-safe tip check) --------
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

  # ---- 5. requirement stamp (PASS shape — self-heal-advisory completion tail) --
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

  # ---- 7. check off (NO reason argument — a reason writes `# skipped: …`) ----
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
  if [ "$did" -eq 1 ]; then
    local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      bash "$HLP" progress-append "$rf_rel" "$ts closeout $pr_url: $l" >/dev/null 2>&1
    done <<PROGRESS
$lines
PROGRESS
  fi

  # ---- 6. trail (via the dispatcher — a stub-able, spy-visible call) --------
  l="$(bash "$HLP" trail-pr "$rf_abs" --reason closeout 2>/dev/null | tail -n1)"
  echo "${l:-trail-pr: skipped — no output}"

  co_release; trap - EXIT
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
    ""|-h|--help)  grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /' ;;
    *) echo "automate-trail: unknown subcommand: $cmd" >&2 ;;
  esac
  return 0
}

main "$@"
exit 0
