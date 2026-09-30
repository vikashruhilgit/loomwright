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
#   * It never merges anything (the sole merge executor is `automate-helpers.sh
#     gate-eval`, SKILL §11), never calls `run-lock.sh`, never runs `git reset`,
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
#   (closeout is dispatched here too by automate-helpers.sh; it is added by the
#    next change — until then it reports an unknown-subcommand line.)
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
  local cands="" excluded="" p q item
  cands="$rf_rel"
  local sc_dir; sc_dir="$(dirname "$rf_rel")"
  for p in "$sc_dir/$run_id.review-heal-result.md" "$sc_dir/$run_id.supervisor-result.md"; do
    [ -f "$p" ] || continue
    q="$(sidecar_check "$p")"
    case "$q" in
      "ok $p") cands="$cands"$'\n'"$p" ;;
      *) excluded="$excluded; excluded $p — ${q#"fail $p: "}" ;;
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
  local ledger=".supervisor/postmortem/results.jsonl"
  [ -f "$ledger" ] && cands="$cands"$'\n'"$ledger"

  # Drop gitignored candidates (this is how the ledger's repo-allowlist is honoured).
  local kept=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    _in_list "$p" "$kept" && continue
    git check-ignore -q -- "$p" 2>/dev/null && continue
    kept="${kept:+$kept$'\n'}$p"
  done <<EOF
$cands
EOF

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
# dispatch
# --------------------------------------------------------------------------- #
main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    sidecar-check) sidecar_check "$@" ;;
    trail-pr)      trail_pr "$@" ;;
    ""|-h|--help)  grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /' ;;
    *) echo "automate-trail: unknown subcommand: $cmd" >&2 ;;
  esac
  return 0
}

main "$@"
exit 0
