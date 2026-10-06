# --------------------------------------------------------------------------- #
# queue-hygiene/01 — reconcile-status: requirement `## Status:` from ground
# truth (a merged PR, an owner `# abandoned:` decision), dry-run by default.
# --------------------------------------------------------------------------- #
#
# WHY THIS EXISTS. `/automate`'s per-item loop is the ONLY writer of a
# requirement's `## Status: done` line (SKILL.md §6). Every other way a PR
# reaches main — a hand `gh pr merge`, the GitHub UI, a bare `/supervisor`, an
# owner-merged `/review-pr` heal — leaves the requirement untouched, so
# `is_done()` still treats it as pending and `resolve-folder`/`resolve-backlog`
# re-offer already-shipped work. This closes that gap the same way
# `reconcile-jobs.sh --repair-merged` closes the sibling brief-lifecycle gap:
# read ground truth back, never infer it.
#
# EVIDENCE, for a *.md this script does NOT already consider `is_done()`:
#   (a) PR-BODY CITATION — a `gh pr list --state merged --search <rel-path>`
#       hit whose body (fetched with ONE more `gh pr view`) contains the
#       file's own repo-relative path, literally — and whose diff does NOT
#       itself add or modify that file (see NEVER EVIDENCE below).
#   (b) BRANCH-SLUG — when this requirement has an associated
#       `.supervisor/jobs/done/<brief>.md` (found by the SAME reverse
#       `## Source requirement:` pointer scan `stamp-requirement-status.sh`
#       runs, via the shared `brief-pointer.sh`), that brief's own `- **PR:**`
#       Outcome line is tried as a candidate FIRST, and a merged candidate's
#       `headRefName` ending in the brief's date-stripped filename slug is
#       accepted as a match when the body citation is absent.
# NEVER EVIDENCE: the engine's own trail PRs (`chore/<run_id>-trail-<n>`,
# _rs_is_trail_branch). A trail PR's body lists every path it commits — the
# run's Queue requirements and its dismissed-finding drafts under `proposed/` —
# so a body citation there says "this file was committed", never "this work
# shipped" (run automate-2026-10-01-142337: proposed/ drafts read "would stamp
# done (PR #321)", #321 being trail PR chore/automate-2026-09-30-054439-trail-2).
# The trail branch is one instance of a general rule, enforced on the PR's DIFF
# (`files`/`changedFiles` from the same `gh pr view`), not on its branch name:
#   - a PR whose diff ADDED or MODIFIED <rel> itself gets no body-citation
#     credit — its body names the file because it commits the file, which is
#     "queued" or "committed", never "shipped" (2026-10-03: PR #359,
#     chore/meta-scrub-cleanup, added meta-sync-followups/04 as `## Status:
#     pending` and listed it in its body; the dry run read "would stamp done
#     (PR #359)", which `--apply` would have made permanent and `is_done` would
#     then have hidden from every later `resolve-folder`);
#   - a PR whose changed files ALL sit under `.supervisor/` is never evidence on
#     either path — state, briefs and run history are not an implementation;
#   - a diff that cannot be read in full (`gh` failing, `changedFiles` 0 or
#     absent, or fewer paths than `changedFiles` from both `pr view`'s 100-file
#     page and the paginated REST fallback) is no evidence (fail closed: a
#     missed stamp is recoverable, a false one silently drops queued work).
# PR STATE is resolved EXCLUSIVELY through `reconcile_item` (merged|open|gone)
# — this is not a second gh-state parser; the extra `gh pr view` call here
# reads ADDITIONAL fields (body, mergeCommit, headRefName) on a candidate
# `reconcile_item` has ALREADY confirmed merged.
#
# NEVER DOWNGRADES: `is_done()` gates every file before ANY evidence is
# gathered, so a `done`/`done_with_escalation` file is never even read past
# that check — this function does not distinguish "no evidence" from "already
# done" in its write path because the caller-side gate makes the second case
# structurally unreachable here.
#
# DRY RUN BY DEFAULT. Without --apply, nothing under <requirements_root> (or
# the matched `.supervisor/automate/*.md` / `.supervisor/jobs/done/*.md`) is
# ever opened for writing — only `--apply` calls the two stamp-writers.
#
# OUTPUT (tab-separated, one row per line, mirrors reconcile-jobs.sh
# --porcelain's convention):
#   plan\t<repo-relative file>\t<status line the file would get>\t<evidence>
#   stamped\t<repo-relative file>\t<status line just written>\t<evidence>
#   info\t<repo-relative file>\tbrief-shipped\t<job path> (<PR url or "no PR recorded">)
#
# FAIL-SAFE (`set +e` below): a network hiccup, an unreadable brief, or a
# malformed run-file row degrades that ONE candidate to "no evidence" — it
# never aborts the whole pass. This is a read-mostly reconciliation pass, not
# a correctness gate (CLAUDE.md bimodal invariant).

# _rs_project_root <requirements_root_abs> — the directory holding
# `.supervisor/` that <requirements_root_abs> sits under (normally its
# grandparent: `<proj>/.supervisor/requirements` -> `<proj>`). Falls back to a
# walk-up so a differently-nested fixture still resolves; falls back to the
# root itself when no `.supervisor/` ancestor exists (jobs/done + automate
# scans then simply find nothing, which is the safe degrade).
_rs_project_root() {
  local abs="$1" parent
  parent="$(dirname "$abs")"
  if [ "$(basename "$parent")" = ".supervisor" ]; then
    dirname "$parent"; return 0
  fi
  local cur="$abs"
  while [ -n "$cur" ] && [ "$cur" != "/" ]; do
    if [ -d "$cur/.supervisor" ]; then printf '%s' "$cur"; return 0; fi
    cur="$(dirname "$cur")"
  done
  printf '%s' "$abs"
}

# _rs_skip_path <abs_file> — the Scope §1 exclusion list: an index file, a
# leading-underscore file, a README, or anything under an `operator-run/`
# subfolder (the `/automate` engine's own worked-by-hand pile, never
# reconciled mechanically).
_rs_skip_path() {
  local f="$1" base; base="$(basename "$f")"
  case "$base" in 00-*|_*|README*) return 0 ;; esac
  case "$f" in */operator-run/*) return 0 ;; esac
  return 1
}

# _rs_load_brief_pointer — source the sibling brief-pointer.sh (THE one
# Source-requirement parser; see its header) if not already loaded; absent
# helper degrades to "no reverse pointer ever resolves", never an abort —
# same fail-safe posture stamp-requirement-status.sh and reconcile-jobs.sh
# both already carry for this exact sibling.
_rs_load_brief_pointer() {
  command -v brief_requirement_pointer >/dev/null 2>&1 && return 0
  local d; d="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
  [ -r "$d/brief-pointer.sh" ] && . "$d/brief-pointer.sh"
  if ! command -v brief_requirement_pointer >/dev/null 2>&1; then
    brief_requirement_pointer() { return 1; }
  fi
}

# _rs_outcome_pr <brief> — the `- **PR:**` line's URL from a done/ brief's
# `## Outcome` block, or empty.
_rs_outcome_pr() {
  grep -m1 -E '^- \*\*PR:\*\*[[:space:]]*' "$1" 2>/dev/null \
    | sed -E 's/^-[[:space:]]*\*\*PR:\*\*[[:space:]]*//'
}

# _rs_brief_slug <brief_path> — the brief's own filename with a leading
# `YYYY-MM-DD-` date stripped and `.md` removed (mirrors
# reconcile-jobs.sh's vcs_merge_for_brief slug convention).
_rs_brief_slug() {
  local base; base="$(basename "$1" .md)"
  case "$base" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-?*) printf '%s' "${base:11}" ;;
    *) printf '%s' "$base" ;;
  esac
}

# _rs_strip_trailing_status <file> <tmp> — copy every line of <file> to <tmp>
# EXCEPT a bare `## Status: pending` heading (the stale line a stamp replaces;
# SKILL §1.5/queue-hygiene AC-2 "stale trailing pending line is removed").
_rs_strip_trailing_status() {
  grep -vE '^## Status:[[:space:]]*pending[[:space:]]*$' "$1" > "$2" 2>/dev/null
}

# _rs_find_done_brief <rel_path> <jobs_done_dir> — echo the ONE
# `.supervisor/jobs/done/*.md` brief whose `## Source requirement:` pointer is
# EXACTLY <rel_path> (first match wins — mirrors stamp-requirement-status.sh's
# own "only the FIRST matching line" rule at the field level, applied here at
# the file level). Prints nothing when none matches.
_rs_find_done_brief() {
  local rel="$1" dir="$2" b ptr
  [ -d "$dir" ] || return 0
  for b in "$dir"/*.md; do
    [ -f "$b" ] || continue
    ptr="$(brief_requirement_pointer "$b" 2>/dev/null)"
    if [ "$ptr" = "$rel" ]; then printf '%s' "$b"; return 0; fi
  done
  return 0
}

# _rs_is_trail_branch <headRefName> — 0 when the branch has the shape trail-pr
# names its branches with (`chore/<run_id>-trail-<n>`, n numeric); such a PR is
# never evidence for _rs_evidence_for, on either the body-citation or the
# branch-slug path.
_rs_is_trail_branch() {
  printf '%s' "$1" | grep -qE '^chore/.+-trail-[0-9]+$'
}

# _rs_pr_changed_paths <pr_url> <view_json> — print the PR's changed paths, one
# per line, and return 0 ONLY when the list is complete (its length equals the
# view's `changedFiles`, and that is > 0). `gh pr view --json files` returns at
# most 100 entries (a 384-file PR reads 100), so a longer diff is re-read through
# the paginated REST endpoint; anything still short — or any read failing —
# returns 1 and the caller treats the candidate as no evidence (fail closed).
_rs_pr_changed_paths() {
  local url="$1" view="$2" want paths n host owner repo num
  want="$(printf '%s' "$view" | "$JQ" -r '.changedFiles // empty' 2>/dev/null)"
  case "$want" in ''|*[!0-9]*|0) return 1 ;; esac
  paths="$(printf '%s' "$view" | "$JQ" -r '.files[]?.path // empty' 2>/dev/null)"
  n=0; [ -n "$paths" ] && n="$(printf '%s\n' "$paths" | wc -l | tr -d ' ')"
  if [ "$n" -ne "$want" ]; then
    [[ "$url" =~ ^https?://([^/]+)/([^/]+)/([^/]+)/pull/([0-9]+) ]] || return 1
    host="${BASH_REMATCH[1]}"; owner="${BASH_REMATCH[2]}"; repo="${BASH_REMATCH[3]}"; num="${BASH_REMATCH[4]}"
    paths="$("$GH" api --hostname "$host" --paginate "repos/$owner/$repo/pulls/$num/files" --jq '.[].filename' 2>/dev/null)" || return 1
    n=0; [ -n "$paths" ] && n="$(printf '%s\n' "$paths" | wc -l | tr -d ' ')"
    [ "$n" -eq "$want" ] || return 1
  fi
  printf '%s\n' "$paths"
}

# _rs_evidence_for <abs_file> <rel_path> <done_brief|""> — echo
# "<pr_url>\t<pr_number>\t<sha7>\t<justification>" for the first candidate PR
# that is MERGED (via reconcile_item) AND either cites <rel_path> in its body
# or (when <done_brief> is non-empty) has a headRefName ending in that
# brief's slug. Echoes nothing when no candidate matches.
_rs_evidence_for() {
  local rel="$1" done_brief="$2" candidates="" c seen=$'\x1f'
  [ -n "${3:-}" ] && candidates="$3"$'\n'
  local search_json
  search_json="$("$GH" pr list --state merged --search "$rel" --json url --limit 5 2>/dev/null)"
  if [ -n "$search_json" ]; then
    local urls; urls="$(printf '%s' "$search_json" | "$JQ" -r '.[]?.url // empty' 2>/dev/null)"
    [ -n "$urls" ] && candidates="${candidates}${urls}"$'\n'
  fi
  [ -n "$candidates" ] || return 0

  local slug=""
  [ -n "$done_brief" ] && slug="$(_rs_brief_slug "$done_brief")"

  while IFS= read -r c; do
    [ -n "$c" ] || continue
    case "$seen" in *$'\x1f'"$c"$'\x1f'*) continue ;; esac
    seen="${seen}${c}"$'\x1f'
    local state; state="$(reconcile_item "$c" "" 2>/dev/null)"
    [ "$state" = "merged" ] || continue
    local view num body oid headref paths
    view="$("$GH" pr view "$c" --json number,body,mergeCommit,headRefName,files,changedFiles 2>/dev/null)"
    [ -n "$view" ] || continue
    num="$(printf '%s' "$view" | "$JQ" -r '.number // empty' 2>/dev/null)"
    body="$(printf '%s' "$view" | "$JQ" -r '.body // empty' 2>/dev/null)"
    oid="$(printf '%s' "$view" | "$JQ" -r '.mergeCommit.oid // empty' 2>/dev/null)"
    headref="$(printf '%s' "$view" | "$JQ" -r '.headRefName // empty' 2>/dev/null)"
    _rs_is_trail_branch "$headref" && continue
    paths="$(_rs_pr_changed_paths "$c" "$view")" || continue
    grep -qv '^\.supervisor/' <<<"$paths" || continue
    local justification=""
    case "$body" in *"$rel"*) grep -qxF -- "$rel" <<<"$paths" || justification="PR body cites $rel" ;; esac
    if [ -z "$justification" ] && [ -n "$slug" ]; then
      case "$headref" in *"$slug") justification="head branch '$headref' matches brief slug '$slug'" ;; esac
    fi
    [ -n "$justification" ] || continue
    [ -n "$oid" ] || oid="unknown"
    printf '%s\t%s\t%s\t%s' "$c" "${num:-0}" "${oid:0:7}" "$justification"
    return 0
  done <<RS_CANDIDATES
$candidates
RS_CANDIDATES
  return 0
}

# _rs_process_file <abs_file> <proj_root> <jobs_done_dir> <apply>
_rs_process_file() {
  local f="$1" proj_root="$2" jobs_done="$3" apply="$4" rel status_hdr
  rel="${f#"$proj_root"/}"
  status_hdr="$(grep -m1 -E '^## Status:' "$f" 2>/dev/null)"

  # brief-shipped: LISTED, never promoted (Scope §4 / Non-goals).
  case "$status_hdr" in
    *brief-shipped*)
      local db pr
      db="$(_rs_find_done_brief "$rel" "$jobs_done")"
      pr=""
      [ -n "$db" ] && pr="$(_rs_outcome_pr "$db")"
      printf 'info\t%s\tbrief-shipped\t%s\n' "$rel" "${pr:-no PR recorded}"
      return 0
      ;;
  esac

  local done_brief; done_brief="$(_rs_find_done_brief "$rel" "$jobs_done")"
  local seed=""
  [ -n "$done_brief" ] && seed="$(_rs_outcome_pr "$done_brief")"
  local evidence; evidence="$(_rs_evidence_for "$rel" "$done_brief" "$seed")"
  [ -n "$evidence" ] || return 0

  local url num sha just status_line
  IFS=$'\t' read -r url num sha just <<RS_EV
$evidence
RS_EV
  status_line="done (PR #${num}, merge ${sha})"

  if [ "$apply" -eq 1 ]; then
    local tmp; tmp="$(mktemp "${f}.XXXXXX")"
    _rs_strip_trailing_status "$f" "$tmp"
    {
      printf '\n## Status: %s\n' "$status_line"
      printf -- '- **Completed:** %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
      printf -- '- **Brief:** %s\n' "${done_brief:-unknown}"
      printf -- '- **PR:** %s\n' "$url"
    } >> "$tmp"
    mv -f "$tmp" "$f"
    printf 'stamped\t%s\t%s\t%s\n' "$rel" "$status_line" "$just"
  else
    printf 'plan\t%s\t%s\t%s\n' "$rel" "$status_line" "$just"
  fi
  return 0
}

# _rs_process_abandoned <requirements_root_abs> <proj_root> <automate_dir> <apply>
# One Queue row `- [x] <req-path>  # abandoned: <reason>` per requirement is
# ground truth for an owner decision (SKILL.md §5). Every row is scanned;
# only a row whose path resolves to a real, not-yet-done, in-scope requirement
# file stamps anything — a row naming a requirement outside
# <requirements_root_abs> (a different queue-hygiene run over a subfolder) is
# left alone.
_rs_process_abandoned() {
  local root_abs="$1" proj_root="$2" automate_dir="$3" apply="$4"
  [ -d "$automate_dir" ] || return 0
  local af line
  for af in "$automate_dir"/*.md; do
    [ -f "$af" ] || continue
    while IFS= read -r line; do
      case "$line" in
        "- [x] "*"  # abandoned: "*)
          local payload reqpath fabs
          payload="${line:6}"
          reqpath="${payload%%  #*}"
          case "$reqpath" in
            .supervisor/requirements/*) ;;
            *) continue ;;
          esac
          fabs="$proj_root/$reqpath"
          [ -f "$fabs" ] || continue
          case "$fabs" in "$root_abs"/*|"$root_abs") ;; *) continue ;; esac
          _rs_skip_path "$fabs" && continue
          is_done "$fabs" && continue
          if [ "$apply" -eq 1 ]; then
            local tmp; tmp="$(mktemp "${fabs}.XXXXXX")"
            _rs_strip_trailing_status "$fabs" "$tmp"
            printf '\n## Status: done_with_escalation \xe2\x80\x94 ABANDONED (%s)\n' "$line" >> "$tmp"
            mv -f "$tmp" "$fabs"
            printf 'stamped\t%s\tdone_with_escalation \xe2\x80\x94 ABANDONED\t%s\n' "$reqpath" "$af"
          else
            printf 'plan\t%s\tdone_with_escalation \xe2\x80\x94 ABANDONED\t%s\n' "$reqpath" "$af"
          fi
          ;;
      esac
    done < "$af"
  done
  return 0
}

# reconcile-status <requirements_root> [--apply]
reconcile_status() {
  set +e   # FAIL-SAFE: one candidate's gh hiccup degrades to "no evidence", never an abort.
  local root="${1:-}" apply=0
  [ -n "$root" ] || { echo "automate-helpers: reconcile-status: requirements root required" >&2; return 1; }
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in --apply) apply=1 ;; esac
    shift
  done
  [ -d "$root" ] || { echo "automate-helpers: reconcile-status: root not found: $root" >&2; return 1; }

  _rs_load_brief_pointer

  local root_abs proj_root jobs_done automate_dir
  root_abs="$(cd "$root" 2>/dev/null && pwd -P)"; [ -n "$root_abs" ] || root_abs="$root"
  proj_root="$(_rs_project_root "$root_abs")"
  jobs_done="$proj_root/.supervisor/jobs/done"
  automate_dir="$proj_root/.supervisor/automate"

  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _rs_skip_path "$f" && continue
    is_done "$f" && continue
    _rs_process_file "$f" "$proj_root" "$jobs_done" "$apply"
  done < <(find "$root_abs" -type f -name '*.md' 2>/dev/null | env LC_ALL=C sort)

  _rs_process_abandoned "$root_abs" "$proj_root" "$automate_dir" "$apply"
  return 0
}

