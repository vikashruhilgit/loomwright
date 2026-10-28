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
# _trail_sidecar_code <sidecar-check fail reason> — #618: the reason as a fixed plugin token for the
# script event (never the reason text, which names keys and paths): the phrasings come from
# sidecar.sh / result_nested_keys.py; anything else is the catch-all sidecar_invalid. DRIFT: these
# patterns match that text — test-script-event-telemetry.sh S8 (c2) drives every branch with the REAL
# sidecar-check output, so a reworded reason turns it red; update both in the same change.
_trail_sidecar_code() {
  case "$1" in
    *"missing required key"*) echo sidecar_missing_key ;;
    *"non-schema key"*) echo sidecar_non_schema_key ;;
    *"is not a mapping"*|*"is not a list"*) echo sidecar_wrong_shape ;;
    *"file not found"*|*"unreadable"*|*"parse error"*|*"no REVIEW_HEAL_RESULT or SUPERVISOR_RESULT block"*) echo sidecar_unreadable ;;
    *) echo sidecar_invalid ;;
  esac
}
# _trail_event <outcome> <code> [--count k=n] — #618: an opt-in telemetry script event from this checkout.
_trail_event() {
  local root; root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  bash "$HERE/emit-script-event.sh" --root "$root" automate-trail trail-pr "$@" >/dev/null 2>&1 </dev/null || true
}
# _trail_report_shape — #618: report what the LAST _trail_candidates call found about the run's
# result sidecars. Called by the two trail-pr paths only (trail_pr, _trail_meta_push), never from
# _trail_candidates itself: that builder is shared with trail-unstage, trail-gate and closeout's
# sync step, which would re-send (and mislabel as trail-pr) the same result on every close-out.
TRAIL_SC_N=0; TRAIL_SC_CODES=""
_trail_report_shape() {
  local c
  if [ -n "$TRAIL_SC_CODES" ]; then
    for c in $TRAIL_SC_CODES; do _trail_event warn "$c"; done
  elif [ "$TRAIL_SC_N" -gt 0 ]; then
    # every result sidecar passed ⇒ close any open shape thread; the evidence gate's
    # `pr not merged` exclusions are expected and never reported
    _trail_event pass sidecars_ok --count "sidecars=$TRAIL_SC_N"
  fi
  return 0
}
# _trail_sidecars <sc_dir> <run_id> — this run's phase result sidecars, one path per line: every regular
# top-level `<sc_dir>/<run_id>.<phase>-result.md`. DERIVED from the naming rule the phase sessions write
# by (automate-lanes.d/phase.sh, the PH_SIDECAR case: launch-pad · supervisor · drain → review-heal),
# never a hand list: wave 7 (run automate-2026-10-15-163325, L21–L24) lost `<run_id>.launch-pad-result.md`
# because the list here named only the two older sidecars, so lane-remove refused `local_ahead 1` until
# a hand meta push. test-automate-lanes.sh AP pins phase.sh's names to this glob.
_trail_sidecars() {
  local p
  for p in "$1/$2".*-result.md; do
    case "${p#"$1/$2".}" in */*|*.*-result.md) continue ;; esac   # `<run_id>.<kind>-result.md` only
    [ -f "$p" ] && [ ! -L "$p" ] && printf '%s\n' "$p"
  done
  return 0
}
_trail_candidates() {
  local rf_rel="$1" run_id="$2"
  local cands="" p q item
  TRAIL_EXCLUDED=""; TRAIL_SC_N=0; TRAIL_SC_CODES=""
  cands="$rf_rel"
  local sc_dir; sc_dir="$(dirname "$rf_rel")"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    # sidecar-check types two blocks (REVIEW_HEAL_RESULT / SUPERVISOR_RESULT); any other phase sidecar
    # (LAUNCH_PAD_RESULT) has no key table there, carries no done claim, and rides as written — its
    # consumer (automate-next-step.sh's launch-pad report) validates it when it reads it.
    case "$p" in
      *.review-heal-result.md|*.supervisor-result.md) ;;
      *) cands="$cands"$'\n'"$p"; continue ;;
    esac
    TRAIL_SC_N=$((TRAIL_SC_N + 1))
    q="$(sidecar_check "$p")"
    case "$q" in
      "ok $p") cands="$cands"$'\n'"$p" ;;
      *) TRAIL_EXCLUDED="$TRAIL_EXCLUDED; excluded $p — ${q#"fail $p: "}"
         TRAIL_SC_CODES="${TRAIL_SC_CODES:+$TRAIL_SC_CODES }$(_trail_sidecar_code "${q#"fail $p: "}")" ;;
    esac
  done <<EOF
$(_trail_sidecars "$sc_dir" "$run_id")
EOF
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
# run's phase result sidecars (the two sidecar-checked names, present or not, ∪
# _trail_sidecars) ∪ every path in `<run_id>.trail-staged` (written only
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
  TRAIL_OWNED="$TRAIL_OWNED"$'\n'"$(_trail_sidecars "$sc_dir" "$run_id")"
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
  _trail_candidates "$rf_rel" "$run_id"; _trail_report_shape
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
  _trail_candidates "$rf_rel" "$run_id"; _trail_report_shape
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

  # The base comes from the ONE resolver (resolve-base-branch.sh); on failure its stdout is empty and
  # its first stderr line is the status token, so the combined capture is that token.
  local base_branch
  if ! base_branch="$(bash "$HERE/resolve-base-branch.sh" --repo "$root" 2>&1 </dev/null)"; then
    echo "$skip_prefix ${base_branch%%$'\n'*}$excluded"; return 0
  fi

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

