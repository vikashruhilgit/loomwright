# --help usage (the `#:  ` lines): this family's segment of automate-helpers.sh --help, assembled
# by the dispatcher's _ah_usage in _AH_HELP_SEGMENTS order; fixture: fixtures/automate-helpers-help/reconcile-status.golden.
#:  reconcile-status <requirements_root> [--apply]      # queue-hygiene/01: dry-run-default requirement `## Status:` reconciler — a not-done *.md under <requirements_root>, other than a `proposed`/`parked` one (is_not_ready) (skips `00-*`, `_*`, `README*`, `operator-run/`, top-level `<slug>-plan.md` task plans) whose PR is MERGED (state via reconcile-item) and whose body cites the file's path (with or without the `.supervisor/requirements/` prefix and `.md`) on an `Implements`/`Closes`/`Resolves`/`Fixes`/`Ships`/`Lands`/`Requirement:`/`Source requirement:` line, before that line's first `;` or `. `, OR whose head branch matches the slug on its `.supervisor/jobs/done/` brief (never the engine's own `chore/<run_id>-trail-<n>` PR, never a PR whose changed files are ALL under `.supervisor/`, and never a body citation from a PR whose own diff adds or modifies that requirement file; an unreadable or incomplete diff is no evidence), is stamped the §6 shape byte-for-byte; a `.supervisor/automate/*.md` Queue row carrying `# abandoned:` and naming a requirement stamps `done_with_escalation — ABANDONED (<row verbatim>)` — never one whose FIRST `## Status:` line is explicit `pending`/`ready` (owner decision D-conflict-1: such an item reads `conflict` until the owner settles it; a `conflict` one gets an `info\t…\tconflict\t<run file>` row instead); NEVER downgrades an existing `done`/`done_with_escalation`; a `## Status: brief-shipped` file (stamp-requirement-status.sh's job-landed heading) is held to the SAME evidence and gets the stamp APPENDED under that heading, never rewriting it, and without evidence is only listed; prints one `plan\t…` row per file it WOULD stamp (or `stamped\t…` under `--apply`) plus one `info\t…` row per `brief-shipped` file it does not stamp, plus one `unverified\t<subject>\t<reason>` row per GitHub read that failed (a pass with such a row is not a clean pass; exit stays 0); writes nothing without `--apply`.

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
#   (a) IMPLEMENTS-LINE CITATION — a merged PR (from the ONE per-pass read,
#       COST below) whose title or body mentions the file's <short ref>, whose
#       body cites it on an IMPLEMENTS-shaped line (_rs_implements_cites) — and
#       whose diff does NOT itself add or modify that file (see NEVER EVIDENCE
#       below). The <short ref> is the repo-relative path with any
#       `.supervisor/requirements/` prefix and `.md` suffix dropped
#       (`automate-followups/27-brief-closed-…`): PR #484 cited only that short
#       form, so matching the full path would miss it.
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
#       accepted as a match when the body citation is absent. A merged PR not
#       recorded on the brief must also be a GitHub search hit for the <short ref>
#       (_rs_slug_confirmed): the index behind that search covers more than a PR's
#       title and body, so it cannot be reproduced from the merged-PR read.
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
# PR STATE: a row of the `--state merged` read is merged by construction; the one
# candidate that can sit outside it, a done/ brief's recorded PR, is resolved
# through `reconcile_item` (merged|open|gone) — this is not a second gh-state
# parser.
#
# COST. A pass must not grow with the folder through a per-file GitHub or
# per-file-times-per-brief cost. On the owner's checkout (2026-11-05: 474 files,
# 252 done/ briefs, 569 merged PRs) the pass took 7:19 and 5:53 of that was
# local: _rs_find_done_brief re-parsed every brief for every not-done file. So:
#   - the briefs are parsed ONCE per pass (RS_BRIEF_INDEX);
#   - merged PRs are read ONCE per pass, on the first file that needs them
#     (_rs_load_merged_prs), replacing a `pr list --search` per file. That read
#     also lifts the old five-hit cap, so a citing PR can no longer fall off it;
#   - a search runs only for a file with an unrecorded merged PR on a
#     slug-matching branch, the one answer the read cannot give;
#   - a PR's diff is read only when its citation or branch already qualifies it.
# What remains per file is a handful of local processes. The read itself grows
# with the repo's merged PRs (about one GraphQL page per 100).
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
# --porcelain's convention; plan/stamped/info rows lead, unverified rows close):
#   plan\t<repo-relative file>\t<status line the file would get>\t<evidence>
#   stamped\t<repo-relative file>\t<status line just written>\t<evidence>
#   info\t<repo-relative file>\tbrief-shipped\t<done/ brief's PR url, or "no PR recorded">
#   info\t<repo-relative file>\tconflict\t<repo-relative run file of the `# abandoned:` row>
#   unverified\t<merged-pr-list or PR url>\t<reason>
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
# a correctness gate (CLAUDE.md bimodal invariant), so it still exits 0.
# But a throttled `gh` used to read exactly like a clean scan: every search
# failed, no rows, exit 0, and stale statuses stayed invisible. A failed GitHub
# read now prints an `unverified` row, which ns_reconcile_status carries into
# `## Progress`. A missed stamp stays recoverable; an unnoticed miss was not.

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

# _rs_first_status_open <file> — true when the file's FIRST `## Status:` line is explicit `pending`
# or `ready` (the value, then the end of the line or a character that cannot continue the word:
# `pending — note` counts, `ready_for_release` and `pending-review` do not). The ONE definition of
# "explicit pending/ready": the D-conflict-1 guard in _rs_process_abandoned below and backlog.sh's
# `open` state both read it.
_rs_first_status_open() {
  local s; s="$(grep -m1 -E '^## Status:' "$1" 2>/dev/null)"
  grep -qE '^## Status:[[:space:]]*(pending|ready)([^A-Za-z0-9_-]|$)' <<<"$s"
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
# the file level). Prints nothing when none matches. Inside a reconcile_status
# pass it answers from RS_BRIEF_INDEX (_rs_index_briefs, same parser, same order).
_rs_find_done_brief() {
  local rel="$1" dir="$2" b ptr
  if [ -n "${RS_BRIEF_INDEX:-}" ]; then
    RS_REL="$rel" awk -F'\t' '$1 == ENVIRON["RS_REL"] { printf "%s", $2; exit }' "$RS_BRIEF_INDEX"
    return 0
  fi
  [ -d "$dir" ] || return 0
  for b in "$dir"/*.md; do
    [ -f "$b" ] || continue
    ptr="$(brief_requirement_pointer "$b" 2>/dev/null)"
    if [ "$ptr" = "$rel" ]; then printf '%s' "$b"; return 0; fi
  done
  return 0
}

# _rs_index_briefs <jobs_done_dir> — one `<pointer>\t<brief>` line per done/ brief
# that has a pointer, in glob order: every brief parsed once per pass.
_rs_index_briefs() {
  local dir="$1" b ptr
  [ -d "$dir" ] || return 0
  for b in "$dir"/*.md; do
    [ -f "$b" ] || continue
    ptr="$(brief_requirement_pointer "$b" 2>/dev/null)"
    [ -n "$ptr" ] && printf '%s\t%s\n' "$ptr" "$b"
  done
  return 0
}

# _rs_note_unverified <subject> <reason> — record a failed GitHub read for the
# closing `unverified` rows. Appends to a file because _rs_evidence_for runs in a
# command substitution, whose variables die with it.
_rs_note_unverified() {
  [ -n "${RS_TMP:-}" ] && printf '%s\t%s\n' "$1" "$2" >> "$RS_TMP/unverified"
  return 0
}

# _rs_load_merged_prs — the ONE merged-PR read of a pass, called on the first
# file that needs it (from the main shell, so the RS_PR_* paths survive). On
# success: RS_PR_ROWS (one compact JSON row per PR, newest first), RS_PR_URLS (the
# matching url per line), RS_PR_LINES (`<url>\t<one title or body line>`) and
# RS_PR_HEADS (`<url>\t<head branch>`, same order). A
# failed or malformed read leaves them unset: only a done/ brief's own PR can
# still be tried, and the pass carries an `unverified` row. A read as long as the
# limit may have cut older PRs off, so it is kept and flagged. gh takes the repo
# from the cwd, as the per-file search it replaces did.
_RS_PR_LIST_LIMIT=5000
_rs_load_merged_prs() {
  [ -z "${_RS_PRS_TRIED:-}" ] || return 0
  _RS_PRS_TRIED=1
  [ -n "${RS_TMP:-}" ] || return 0
  local json="$RS_TMP/merged.json" n
  if ! "$GH" pr list --state merged --limit "$_RS_PR_LIST_LIMIT" --json number,url,title,body,headRefName,mergeCommit > "$json" 2>/dev/null; then
    _rs_note_unverified merged-pr-list "gh pr list failed; no merged PR was checked"
    return 0
  fi
  n="$("$JQ" -r 'if type == "array" then length else "bad" end' "$json" 2>/dev/null)"
  case "$n" in
    ''|*[!0-9]*) _rs_note_unverified merged-pr-list "gh pr list answered unreadable JSON; no merged PR was checked"; return 0 ;;
  esac
  [ "$n" -lt "$_RS_PR_LIST_LIMIT" ] || _rs_note_unverified merged-pr-list "read stopped at the $_RS_PR_LIST_LIMIT-PR limit; older PRs were not checked"
  "$JQ" -c '.[]' "$json" > "$RS_TMP/rows" 2>/dev/null
  "$JQ" -r '.[].url' "$json" > "$RS_TMP/urls" 2>/dev/null
  "$JQ" -r '.[] | .url as $u | ((.title // ""), ((.body // "") | split("\n")[])) | "\($u)\t\(.)"' "$json" > "$RS_TMP/lines" 2>/dev/null
  "$JQ" -r '.[] | "\(.url)\t\(.headRefName // "")"' "$json" > "$RS_TMP/heads" 2>/dev/null
  RS_PR_ROWS="$RS_TMP/rows"; RS_PR_URLS="$RS_TMP/urls"; RS_PR_LINES="$RS_TMP/lines"; RS_PR_HEADS="$RS_TMP/heads"
}

# _rs_merged_row <url> — the read's JSON row for <url>; prints nothing when the
# read does not hold it.
_rs_merged_row() {
  [ -n "${RS_PR_URLS:-}" ] || return 0
  local n; n="$(grep -m1 -nxF -- "$1" "$RS_PR_URLS" 2>/dev/null)"
  [ -n "$n" ] && sed -n "${n%%:*}p" "$RS_PR_ROWS"
  return 0
}

# _rs_slug_confirmed <short_ref> <slug> <seed> — the merged PRs other than <seed>
# whose head ends in <slug> AND which GitHub search returns for <short_ref>, one
# url per line. No such head means no search. A failed search is `unverified`.
_rs_slug_confirmed() {
  local short="$1" slug="$2" seed="$3" heads hits
  [ -n "$slug" ] && [ -n "${RS_PR_HEADS:-}" ] || return 0
  heads="$(RS_SLUG="$slug" RS_SEED="$seed" awk -F'\t' '
    BEGIN { s = ENVIRON["RS_SLUG"]; sl = length(s) }
    $1 != ENVIRON["RS_SEED"] && length($2) >= sl && substr($2, length($2) - sl + 1) == s { print $1 }' "$RS_PR_HEADS")"
  [ -n "$heads" ] || return 0
  if ! hits="$("$GH" pr list --state merged --search "$short" --json url --limit 5 2>/dev/null)"; then
    _rs_note_unverified "$short" "gh search failed; a merged PR on a matching branch was not checked"
    return 0
  fi
  hits="$(printf '%s' "$hits" | "$JQ" -r '.[]?.url // empty' 2>/dev/null)"
  [ -n "$hits" ] && grep -xF -- "$hits" <<<"$heads"
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

# _rs_evidence_for <rel_path> <done_brief|""> <seed_pr|""> — echo
# "<pr_url>\t<pr_number>\t<sha7>\t<justification>" for the first candidate PR
# that is MERGED AND either cites <rel_path> in its body or (when <done_brief> is
# non-empty) has a headRefName ending in that brief's slug. Candidates: the seed,
# then every merged PR that mentions the short ref or that _rs_slug_confirmed
# returns, newest first. The slug path counts only for the seed and those. Echoes
# nothing when no candidate matches.
_rs_evidence_for() {
  local rel="$1" done_brief="$2" candidates="" c seen=$'\x1f'
  [ -n "${3:-}" ] && candidates="$3"$'\n'
  local short; short="$(_rs_short_ref "$rel")"
  local slug="" slug_ok=""
  [ -n "$done_brief" ] && slug="$(_rs_brief_slug "$done_brief")"
  if [ -n "${RS_PR_LINES:-}" ]; then
    local urls; urls="$(env LC_ALL=C grep -aF -- "$short" "$RS_PR_LINES" 2>/dev/null | cut -f1 | awk '!seen[$0]++')"
    slug_ok="$(_rs_slug_confirmed "$short" "$slug" "${3:-}")"
    [ -n "$slug_ok" ] && urls="$(RS_U="$urls"$'\n'"$slug_ok" awk -F'\t' '
      BEGIN { n = split(ENVIRON["RS_U"], U, "\n"); for (i = 1; i <= n; i++) m[U[i]] = 1 }
      $1 in m { print $1 }' "$RS_PR_HEADS")"
    [ -n "$urls" ] && candidates="${candidates}${urls}"$'\n'
  fi
  [ -n "$candidates" ] || return 0

  while IFS= read -r c; do
    [ -n "$c" ] || continue
    case "$seen" in *$'\x1f'"$c"$'\x1f'*) continue ;; esac
    seen="${seen}${c}"$'\x1f'
    local view num body oid headref paths cited=0 slug_match=0
    view="$(_rs_merged_row "$c")"
    local listed=1
    if [ -z "$view" ]; then
      listed=0
      local state; state="$(reconcile_item "$c" "" 2>/dev/null)"
      [ "$state" = "merged" ] || continue
      view="$("$GH" pr view "$c" --json number,body,mergeCommit,headRefName,files,changedFiles 2>/dev/null)"
      [ -n "$view" ] || { _rs_note_unverified "$c" "gh pr view failed; this PR was not checked"; continue; }
    fi
    num="$(printf '%s' "$view" | "$JQ" -r '.number // empty' 2>/dev/null)"
    body="$(printf '%s' "$view" | "$JQ" -r '.body // empty' 2>/dev/null)"
    oid="$(printf '%s' "$view" | "$JQ" -r '.mergeCommit.oid // empty' 2>/dev/null)"
    headref="$(printf '%s' "$view" | "$JQ" -r '.headRefName // empty' 2>/dev/null)"
    _rs_is_trail_branch "$headref" && continue
    if _rs_implements_cites "$body" "$short"; then
      cited=1
    fi
    if [ -n "$slug" ] && { [ "$c" = "${3:-}" ] || grep -qxF -- "$c" <<<"$slug_ok"; }; then
      case "$headref" in *"$slug") slug_match=1 ;; esac
    fi
    # Neither path can succeed, so no diff can change the answer: skip its read.
    [ "$cited" -eq 1 ] || [ "$slug_match" -eq 1 ] || continue
    if [ "$listed" -eq 1 ]; then
      view="$("$GH" pr view "$c" --json files,changedFiles 2>/dev/null)"
      [ -n "$view" ] || { _rs_note_unverified "$c" "gh pr view failed; this PR's diff was not read"; continue; }
    fi
    paths="$(_rs_pr_changed_paths "$c" "$view")" || continue
    grep -qv '^\.supervisor/' <<<"$paths" || continue
    local justification=""
    if [ "$cited" -eq 1 ]; then
      grep -qxF -- "$rel" <<<"$paths" || justification="PR body cites $rel"
    fi
    if [ -z "$justification" ] && [ "$slug_match" -eq 1 ]; then
      justification="head branch '$headref' matches brief slug '$slug'"
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
  _rs_load_merged_prs
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
# GUARD (owner decision D-conflict-1): a row never stamps ABANDONED on an item whose FIRST
# `## Status:` line is explicit `pending`/`ready` (_rs_first_status_open) — whether that item reads
# `conflict` or was kept open (a kept-open item's stale row must never abandon it). backlog.sh's
# shared predicate _bl_is_conflict only chooses between the `info …\tconflict` row and a silent
# skip. Every other not-done, in-scope item named by such a row (status-less, `brief-shipped`, an
# off-enum value) is stamped exactly as before.
# ONE row per item: under --apply the first stamp makes is_done true for every later row naming the
# same item; a dry run writes nothing, so it remembers the items it planned (`planned`) and skips a
# later row for one of them — the plan lists exactly what --apply would stamp.
_rs_process_abandoned() {
  local root_abs="$1" proj_root="$2" automate_dir="$3" apply="$4"
  [ -d "$automate_dir" ] || return 0
  local af af_rel line planned=$'\n'
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
          if _rs_first_status_open "$fabs"; then _bl_is_conflict "$fabs" "$reqpath" "$automate_dir" "$af" >/dev/null 2>&1 && printf 'info\t%s\tconflict\t%s\n' "$reqpath" "$af_rel"; continue; fi
          if [ "$apply" -eq 1 ]; then
            local tmp; tmp="$(mktemp "${fabs}.XXXXXX")"
            _rs_strip_trailing_status "$fabs" "$tmp"
            printf '\n## Status: done_with_escalation \xe2\x80\x94 ABANDONED (%s)\n' "$line" >> "$tmp"
            mv -f "$tmp" "$fabs"
            printf 'stamped\t%s\tdone_with_escalation \xe2\x80\x94 ABANDONED\t%s\n' "$reqpath" "$af_rel"
          else
            case "$planned" in *$'\n'"$reqpath"$'\n'*) continue ;; esac
            planned="$planned$reqpath"$'\n'
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

  # Per-pass scratch: the brief index and the merged-PR read. No scratch dir is
  # the same degrade as no read, and it says so among the closing rows.
  RS_TMP="$(mktemp -d 2>/dev/null)" || RS_TMP=""
  if [ -n "$RS_TMP" ]; then
    trap 'rm -rf "$RS_TMP"' EXIT
    _rs_index_briefs "$jobs_done" > "$RS_TMP/briefs"
    RS_BRIEF_INDEX="$RS_TMP/briefs"
  fi

  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _rs_skip_path "$f" "$proj_root" && continue
    is_done "$f" && continue
    _rs_process_file "$f" "$proj_root" "$jobs_done" "$apply"
  done < <(find "$root_abs" -type f -name '*.md' 2>/dev/null | env LC_ALL=C sort)

  _rs_process_abandoned "$root_abs" "$proj_root" "$automate_dir" "$apply"
  [ -n "$RS_TMP" ] || printf 'unverified\tmerged-pr-list\tno scratch directory; no merged PR was checked\n'
  [ -z "$RS_TMP" ] || [ ! -f "$RS_TMP/unverified" ] || awk -F'\t' '!seen[$0]++ { print "unverified\t" $1 "\t" $2 }' "$RS_TMP/unverified"
  return 0
}

