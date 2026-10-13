# --help usage (the `#:  ` lines): this family's segment of automate-helpers.sh --help, assembled
# by the dispatcher's _ah_usage in _AH_HELP_SEGMENTS order; fixture: fixtures/automate-helpers-help/reconcile-status.golden.
#:  reconcile-status <requirements_root> [--apply]      # queue-hygiene/01: dry-run-default requirement `## Status:` reconciler — a not-done *.md under <requirements_root>, other than a `proposed`/`parked` one (is_not_ready) (skips `00-*`, `_*`, `README*`, `operator-run/`, top-level `<slug>-plan.md` task plans) whose PR is MERGED (state via reconcile-item) and whose body cites the file's path (with or without the `.supervisor/requirements/` prefix and `.md`) on an `Implements`/`Closes`/`Resolves`/`Fixes`/`Ships`/`Lands`/`Requirement:`/`Source requirement:` line, before that line's first `;` or `. `, OR whose head branch matches the slug on its `.supervisor/jobs/done/` brief (never the engine's own `chore/<run_id>-trail-<n>` PR, never a PR whose changed files are ALL under `.supervisor/`, and never a body citation from a PR whose own diff adds or modifies that requirement file; an unreadable or incomplete diff is no evidence), is stamped the §6 shape byte-for-byte; a `.supervisor/automate/*.md` Queue row carrying `# abandoned:` and naming a requirement stamps `done_with_escalation — ABANDONED (<row verbatim>)`; NEVER downgrades an existing `done`/`done_with_escalation`; a `## Status: brief-shipped` file (stamp-requirement-status.sh's job-landed heading) is held to the SAME evidence and gets the stamp APPENDED under that heading, never rewriting it, and without evidence is only listed; prints one `plan\t…` row per file it WOULD stamp (or `stamped\t…` under `--apply`) plus one `info\t…` row per `brief-shipped` file it does not stamp; writes nothing without `--apply`.

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
#   (a) IMPLEMENTS-LINE CITATION — a `gh pr list --state merged --search
#       <short ref>` hit whose body (fetched with ONE more `gh pr view`) cites
#       the file on an IMPLEMENTS-shaped line (_rs_implements_cites) — and whose
#       diff does NOT itself add or modify that file (see NEVER EVIDENCE below).
#       The <short ref> is the repo-relative path with any
#       `.supervisor/requirements/` prefix and `.md` suffix dropped
#       (`automate-followups/27-brief-closed-…`): GitHub search returns NOTHING
#       for the full path of PR #484's requirement, while the short form finds
#       it and every full-path citation too.
#       WHY NOT ANY MENTION. A body names requirement paths for many reasons
#       besides implementing them. On 2026-10-11 the any-mention rule planned
#       five false `done` stamps: PR #470 (the pa/22 split) listed af/36, af/39
#       and pa/18 in a `plan-waves` example; PR #482 named the
#       `proposed/twin-remediation-11` follow-up draft it was filing; PR #457
#       named the task plan it failed to push. `--apply` would have made them
#       permanent and `is_done` would have hidden the three pending items from
#       every later intake. A citation now counts only on a line that OPENS
#       with an implements verb, and only in that line's first clause — so
#       "Implements X; unblocks Y" credits X alone. Honest limit: a verb line
#       that names an unrelated path in its first clause ("Fixes the bug that
#       blocked `qh/03-x`") still counts; a PR with no verb line gets no
#       stamp at all, which is the recoverable direction.
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
# BRIEF-SHIPPED (owner decision 2026-10-13, reversing queue-hygiene/01's "listed,
# never promoted" non-goal). `stamp-requirement-status.sh` writes `## Status:
# brief-shipped` on a status-less requirement once its brief reaches
# `.supervisor/jobs/done/` — at PR open, before any merge — so the heading proves
# the job ran, not that it shipped. It is held to EXACTLY the evidence above (no
# looser path: a landed brief is never evidence on its own) and, on a match, gets
# the §6 done shape APPENDED below its heading, which is never rewritten. With no
# evidence it is listed as an `info` row and left byte-unchanged, as before. The
# old unconditional `info` return hid every plain-run requirement from the one
# recovery path its honest limit names (#447: 27 merged-but-re-offered files).
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
#   info\t<repo-relative file>\tbrief-shipped\t<done/ brief's PR url, or "no PR recorded">
# An abandoned row's <evidence> is the repo-relative run file
# (`.supervisor/automate/<run_id>.md`).
#
# NO ABSOLUTE PATHS (automate-followups/36 B-B). Every path this prints or writes
# is repo-relative — the `- **Brief:**` line --apply stamps into a requirement file
# (`.supervisor/jobs/done/<brief>.md`, the form closeout's own stamp writes) and the
# abandoned rows' run-file field included. Requirement files and the run file the
# RESUME appends `plan` rows to travel on the metadata branch, whose meta-sync
# home-path scrub refuses an absolute `/Users/…` or `/home/…` path: the absolute
# forms failed lane metadata pushes in S3 waves 1 and 2.
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

# _rs_skip_path <abs_file> <proj_root> — the Scope §1 exclusion list: an index
# file, a leading-underscore file, a README, anything under an `operator-run/`
# subfolder (the `/automate` engine's own worked-by-hand pile, never
# reconciled mechanically), or an Orchestrator task plan — a top-level
# `.supervisor/requirements/<slug>-plan.md` (agents/orchestrator.md writes
# them there; the same definition automate-lanes.sh's wave-end push uses).
# A task plan is a work breakdown, not a requirement: PR #457 named one in its
# body and the dry run planned a `done` stamp for it.
_rs_skip_path() {
  local f="$1" proj_root="${2:-}" base; base="$(basename "$f")"
  case "$base" in 00-*|_*|README*) return 0 ;; esac
  case "$f" in */operator-run/*) return 0 ;; esac
  if [ -n "$proj_root" ] && [ "$(dirname "$f")" = "$proj_root/.supervisor/requirements" ]; then
    case "$base" in *-plan.md) return 0 ;; esac
  fi
  return 1
}

# _rs_short_ref <rel_path> — <rel_path> without a leading
# `.supervisor/requirements/` and a trailing `.md`: the form both the
# candidate search and _rs_implements_cites match on.
_rs_short_ref() {
  local r="${1#.supervisor/requirements/}"
  printf '%s' "${r%.md}"
}

# _rs_implements_cites <body> <short_ref> — 0 when some line of <body> cites
# <short_ref> as the work it implements:
#   - the line, after leading whitespace, list/quote markers (`-`, `*`, `+`,
#     `>`) and `**` bold markers, OPENS with Implements, Closes, Resolves,
#     Fixes, Ships, Lands, `Requirement:` or `Source requirement:` (any case);
#   - the citation sits in the line's first clause — the text before its first
#     `;` or `.`-then-whitespace (so `.supervisor` and `.md` never end it);
#   - with every `.supervisor/requirements/` prefix removed from that clause,
#     <short_ref> appears on a path boundary: not preceded by a path character
#     (`[A-Za-z0-9_./-]`), and followed — after an optional `.md` — by end of
#     clause, a sentence-final `.`, or a character that cannot continue a slug.
# The body travels through ENVIRON, never an awk -v (which would interpret its
# backslashes) or a here-string line split.
_rs_implements_cites() {
  RS_BODY="$1" RS_SHORT="$2" awk 'BEGIN {
    s = ENVIRON["RS_SHORT"]; sl = length(s)
    if (sl == 0) exit 1
    n = split(ENVIRON["RS_BODY"], L, "\n")
    for (i = 1; i <= n; i++) {
      line = L[i]
      sub(/\r$/, "", line)
      gsub(/\*\*/, "", line)
      sub(/^[ \t]*([-*+>][ \t]+)*/, "", line)
      low = tolower(line)
      if (low !~ /^(implements|closes|resolves|fixes|ships|lands)([^a-z]|$)/ \
          && low !~ /^(source )?requirement:/) continue
      if (match(line, /;|\.[ \t]/)) line = substr(line, 1, RSTART - 1)
      gsub(/\.supervisor\/requirements\//, "", line)
      off = 0
      while ((p = index(substr(line, off + 1), s)) > 0) {
        at = off + p
        before = (at > 1) ? substr(line, at - 1, 1) : ""
        after = substr(line, at + sl)
        if (substr(after, 1, 3) == ".md") after = substr(after, 4)
        a = substr(after, 1, 1); a2 = substr(after, 2, 1)
        if (before !~ /[A-Za-z0-9_.\/-]/ \
            && a !~ /[A-Za-z0-9_\/-]/ \
            && !(a == "." && a2 ~ /[A-Za-z0-9]/)) exit 0
        off = at
      }
    }
    exit 1
  }'
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
# A `## Status: brief-shipped` heading and its two-line note are deliberately
# KEPT: the done stamp is appended below them (the same append-only shape
# `closeout` leaves on such a file), so the record shows the job landed first and
# the merge was proven later; `is_done` matches the appended heading anywhere.
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
  local short; short="$(_rs_short_ref "$rel")"
  search_json="$("$GH" pr list --state merged --search "$short" --json url --limit 5 2>/dev/null)"
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
    if _rs_implements_cites "$body" "$short"; then
      grep -qxF -- "$rel" <<<"$paths" || justification="PR body cites $rel"
    fi
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

  # brief-shipped (stamp-requirement-status.sh's "job landed, ACs unverified"
  # heading) takes the SAME evidence path as every other not-done heading below,
  # and is only LISTED (`info`) when that path finds no merged PR. Until
  # 2026-10-13 it returned here with the `info` row unconditionally (the
  # queue-hygiene/01 "listed, never promoted" non-goal) — and since that heading
  # lands on every status-less requirement whose brief reaches `done/`, the early
  # return hid exactly the plain-`/supervisor` requirements whose only recovery
  # path is this script (27 merged-but-re-offered files in the owner's checkout;
  # #447). The bar is unchanged: a landed brief alone still proves nothing, only
  # a merged PR does, so promotion needs what a `pending` file needs.
  local shipped=0
  case "$status_hdr" in *brief-shipped*) shipped=1 ;; esac

  # A not-ready item (`is_not_ready`: a `proposed` draft or a `parked` item) is
  # an owner decision, never reconciled: PR #482's body named a `## Status:
  # proposed` draft and the dry run planned `done` for it. Every other not-done
  # heading (`pending`, `in-progress`, a free-text `in review — …`,
  # `brief-shipped`, none) stays promotable. A brief-shipped file the owner also
  # marked not-ready keeps its `info` row.
  local done_brief; done_brief="$(_rs_find_done_brief "$rel" "$jobs_done")"
  local seed=""
  [ -n "$done_brief" ] && seed="$(_rs_outcome_pr "$done_brief")"
  local evidence=""
  is_not_ready "$f" || evidence="$(_rs_evidence_for "$rel" "$done_brief" "$seed")"
  if [ -z "$evidence" ]; then
    [ "$shipped" -eq 1 ] && printf 'info\t%s\tbrief-shipped\t%s\n' "$rel" "${seed:-no PR recorded}"
    return 0
  fi

  local url num sha just status_line
  IFS=$'\t' read -r url num sha just <<RS_EV
$evidence
RS_EV
  status_line="done (PR #${num}, merge ${sha})"

  if [ "$apply" -eq 1 ]; then
    local tmp brief_rel=""; tmp="$(mktemp "${f}.XXXXXX")"
    [ -n "$done_brief" ] && brief_rel="${done_brief#"$proj_root"/}"
    _rs_strip_trailing_status "$f" "$tmp"
    {
      printf '\n## Status: %s\n' "$status_line"
      printf -- '- **Completed:** %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
      printf -- '- **Brief:** %s\n' "${brief_rel:-unknown}"
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
  local af af_rel line
  for af in "$automate_dir"/*.md; do
    [ -f "$af" ] || continue
    af_rel="${af#"$proj_root"/}"   # repo-relative in every printed row (no home path)
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
          _rs_skip_path "$fabs" "$proj_root" && continue
          is_done "$fabs" && continue
          if [ "$apply" -eq 1 ]; then
            local tmp; tmp="$(mktemp "${fabs}.XXXXXX")"
            _rs_strip_trailing_status "$fabs" "$tmp"
            printf '\n## Status: done_with_escalation \xe2\x80\x94 ABANDONED (%s)\n' "$line" >> "$tmp"
            mv -f "$tmp" "$fabs"
            printf 'stamped\t%s\tdone_with_escalation \xe2\x80\x94 ABANDONED\t%s\n' "$reqpath" "$af_rel"
          else
            printf 'plan\t%s\tdone_with_escalation \xe2\x80\x94 ABANDONED\t%s\n' "$reqpath" "$af_rel"
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
    _rs_skip_path "$f" "$proj_root" && continue
    is_done "$f" && continue
    _rs_process_file "$f" "$proj_root" "$jobs_done" "$apply"
  done < <(find "$root_abs" -type f -name '*.md' 2>/dev/null | env LC_ALL=C sort)

  _rs_process_abandoned "$root_abs" "$proj_root" "$automate_dir" "$apply"
  return 0
}

