#!/usr/bin/env bash
# automate-helpers.sh — pure, deterministic, testable helpers for the `/automate`
# generic automation engine. The PROTOCOL AUTHORITY is
# `skills/automate-loop/SKILL.md` — every contract implemented here conforms to a
# named section there (§ refs in each subcommand's comment). The run-file layout
# matches `docs/RESULT_SCHEMAS.md §AUTOMATE_RUN` and the brief's "The run file
# (the contract)" template.
#
# This script is a library of SUBCOMMANDS the inline `/automate` loop shells out
# to (wired in `skills/automate-loop/SKILL.md` §1.5 + the inline "execute via
# automate-helpers.sh" pointers at §3/§4/§7/§10, and referenced from
# `commands/automate.md`) for the few pieces of logic that benefit from being
# scriptable + self-tested (config suppress/restore, atomic run-file writes,
# append-only Progress, resume reconcile, the trusted auto-merge gate) — so the
# TESTED code is the EXECUTED code (one implementation, not a prose re-spec). It
# is READ-ONLY toward the work it
# drives — it never edits source repos, never runs git mutations of its own, and
# (outside the explicitly-stubbed `gate-eval` MERGE branch) never calls
# `gh pr merge` — and `brief-repair`, whose only write is the brief lifecycle
# move performed by `reconcile-jobs.sh --repair` under `.supervisor/jobs/`,
# never a source-repo or git mutation. The ONE carve-out: `trail-pr`/`closeout`/`trail-unstage`/`trail-gate`
# (and the read-only `sidecar-check` beside them) are delegated to the sibling
# `automate-trail.sh`, which is a git/`gh pr create` mutator bounded to this
# run's trail branch, this PR's local branch/worktree, and — in the primary
# checkout — index-only entries for this run's own trail paths plus closeout's
# (and trail-gate's PICK-time) `git checkout <base>` + `git pull --ff-only` sync (never a commit, reset or
# stash there) — never `gh pr merge`. A second, narrower carve-out:
# `dismissed-drafts`/`dismissed-decide`/`dismissed-pending` are delegated to the
# sibling `automate-dismissed.sh`, which writes ONLY this run's dismissed-finding
# drafts under `.supervisor/requirements/proposed/` (through propose-common.sh's
# `pc_guarded_write`), its gitignored `<run_id>.dismissed-decisions` ledger and
# one `## Progress` line per decision — never git, never `gh`. UNCOUNTED by the
# doc-currency gate (it is a plain script, not an agent/command/skill/hook).
#
# Subcommands:
#   config-suppress  <config_path> <backup_path>      # §7 backup byte-for-byte, set auto_review=false; malformed ⇒ abort
#   config-restore   <config_path> <backup_path>      # §7 overwrite-from-backup OR delete-if-absent; deletes backup
#   config-orig      <config_path> [<backup_path>]     # §7 prints true|false|absent (the ORIGINAL auto_review); pass the backup once suppress has run
#   runfile-write    <runfile_path> < CONTENT          # §3 atomic temp+rename write, validated before rename: refuses (exit 1, file unchanged) empty / no title / no "## Status:" / no "## Queue" / dropped Progress prefix
#   progress-append  <runfile_path> <line>             # §3 append-only ## Progress (never rewrites prior lines); refuses a file with no "# Automate Run:" title; exit 3 + `current_not_set: <line>` on stderr (line still appended) when a `picked `/`ran /autonomous`/`owned drain started` line meets a null ## Current item, or `picked <X>` meets a different non-done item
#   queue-checkoff   <runfile_path> <item> [reason] [mark]  # §3/§5 flip - [ ] -> - [x] (optional "# <skipped|abandoned>: reason"; mark default skipped); refuses a file with no title
#   current-set      <runfile_path> [--item <path|null> --status <s|null>] [--pr <url|null>] [--branch <b|null>] [--pause-reason <r>]  # §3 the ONLY writer of ## Current's item/pause_reason lines: item form (both --item/--status; null only both-null) or run-level form (--pause-reason only); enum-validated; a changed --item resets an omitted pr/branch to null; refusal = exit 1, file byte-unchanged; identical values ⇒ `current-set: unchanged`
#   current-rebuild  <runfile_path>                     # §4 RECONCILE repair: ## Current item null/absent + a `picked` Progress line ⇒ item from the LAST picked line (must be a Queue row), pr ONLY from a later `ran /autonomous` line, branch via one gh pr view; always status running; one `current_rebuilt: … state <s>` line (printed + appended); already set ⇒ `skipped — ## Current set`
#   remaining        <runfile_path>                     # §3 count of "- [ ]" lines only
#   ceiling-check    <runfile_path> <max_tokens> [--root <checkout>]  # §6 PICK-time token-ceiling check via read-token-ledger.sh --run-id; prints OK/PARK, always exits 0
#   resolve-folder   <dir>                              # §2 list *.md not done and not proposed|parked
#   resolve-backlog  <backlog.md>                       # §2 dependency-ordered items honoring done/✅ markers AND the referenced file's own ## Status: done stamp (is_done); dir-fallback path also skips proposed|parked, per is_not_ready
#   resume-glob      <automate_dir>                     # §4 list run files (is_run_file: a "# Automate Run:" title line anywhere — BOM/0-3-space indent/whitespace/case tolerant, RUN_TITLE_ERE) not "## Status: done"; §6 result sidecars never listed because they carry no such line
#   reconcile-item   <pr_url> <belief>                  # §4 belief vs gh/git truth -> corrected state
#   gate-eval        <pr_url> <ctx.json>                # §10 MERGE|PARK fail-closed trusted-merge gate (conditions enumerated in skills/automate-loop/SKILL.md §10; cond 6 = classify-risk.sh high_risk, cond 7 = rules-gate-verdict.sh, NO override)
#   learning-emit    <ledger_path> <flags...>           # §6 step 3 fail-safe (always exit 0) engine-native ground-truth POSTMORTEM_RESULT line; idempotent on run_id+item+pr_url+source+completeness (a degraded emit never blocks a later complete one)
#   brief-repair     <item> <pr_url>                    # §6 steps 1/5 fail-safe (always exit 0) evidence-positive brief lifecycle repair: `gh pr view` says MERGED (or a non-empty mergedAt) ⇒ sibling reconcile-jobs.sh --repair --evidence <item>=<pr_url>; prints ONE line for ## Progress
#   reconcile-status <requirements_root> [--apply]      # queue-hygiene/01: dry-run-default requirement `## Status:` reconciler — a `pending`/absent-status *.md under <requirements_root> (skips `00-*`, `_*`, `README*`, `operator-run/`) whose PR is MERGED (state via reconcile-item) and whose body cites the file's repo-relative path, OR whose head branch matches the slug on its `.supervisor/jobs/done/` brief (never the engine's own `chore/<run_id>-trail-<n>` PR, never a PR whose changed files are ALL under `.supervisor/`, and never a body citation from a PR whose own diff adds or modifies that requirement file; an unreadable or incomplete diff is no evidence), is stamped the §6 shape byte-for-byte; a `.supervisor/automate/*.md` Queue row carrying `# abandoned:` and naming a requirement stamps `done_with_escalation — ABANDONED (<row verbatim>)`; NEVER downgrades an existing `done`/`done_with_escalation`; prints one `plan\t…` row per file it WOULD stamp (or `stamped\t…` under `--apply`) plus one `info\t…` row per `brief-shipped` file (never promoted); writes nothing without `--apply`.
#   sidecar-check    <path>                             # §6 trail: delegated to automate-trail.sh — `ok <path>` / `fail <path>: <reason>` (RESULT_SCHEMAS key-table shape check of a result sidecar); always exits 0
#   trail-pr         <runfile> [--reason <reason>]      # §6 "Trail PR after merge and at run end": delegated to automate-trail.sh — called only by closeout, at ## Status: done, and on a skip/abandon check-off (never at a park); commits this run's explicit trail paths as ONE PR off fresh origin/main, a done-stamped requirement/done brief only when its PR reads merged; one line (opened|pushed|skipped); always exits 0
#   closeout         <runfile> <item> <pr_url> [--session-id <sid>]  # §6 post-merge close-out: delegated to automate-trail.sh; always exits 0
#   dismissed-drafts <runfile> <item> <pr_url> [--after-fix-now]  # §6 "Dismissed-findings decision step (before the park)": delegated to automate-dismissed.sh — one propose-only draft per dismissed finding over the threshold (+ one undecided summary draft per item) in proposed/, content-addressed names, decisions never reset; TSV `draft` rows + one summary line; always exits 0
#   dismissed-decide <runfile> <draft_path> <fix-now|follow-up|drop>  # §6 decision step / next PICK: delegated to automate-dismissed.sh — records the decision in <run_id>.dismissed-decisions, rewrites (follow-up) or deletes (drop/fix-now) the draft, one Progress line; refuses a foreign path; always exits 0
#   dismissed-pending <runfile>                         # §6 step 1 PICK: delegated to automate-dismissed.sh — count of this run's undecided drafts, or `unknown` (treated as non-zero); always exits 0
#   trail-unstage    <runfile>                          # §6 step 1 PICK (before RUN): delegated to automate-trail.sh — drops the trail-path index entries trail-pr staged so the next item's commit cannot sweep them; one line; always exits 0
#   trail-gate       <runfile>                          # §6 step 1 PICK (after RECONCILE, before trail-unstage) / §8: delegated to automate-trail.sh — `PARK — trail PR open <url>` while this run's trail PR is open (or its state is unreadable: fail CLOSED); else `clear — …` after syncing the primary onto the base branch (closeout's sync); one line; always exits 0
#   meta-entry       [--root <checkout>]                # §"Branch mode": the FIRST action of every /automate entry (a bare/empty/option-shaped --root value ⇒ `failed`) — reads `setup-memory.sh mode` itself (no caller input can assert the mode) and, when on, runs `meta-sync.sh pull`; ONE line `meta-entry: off|pulled <branch>|failed — <reason>`; writes nothing under .supervisor/automate/; always exits 0
#   meta-push-failed <runfile>                          # §"Branch mode": read-only — prints the first line of this run's gitignored `<run_id>.meta-push-failed` marker (a failed mode-on trail push), or nothing; always exits 0
#   plan-waves       <runfile|dir|item-list> --max N [--explain] [--root <checkout>]  # parallel-automate/04: READ-ONLY wave planner — `## Depends on` / `## Touches` (strict grammar) + <root>/.agent/companions.json expansion ⇒ `wave <k>: …` + `blocked <item>: …` lines (`--explain`, parallel-automate/10: then one `explain <item> (wave <k>):` block per placed item not in wave 1); exit 1 + empty stdout on usage / item not found / unknown dependency / cycle / companions_malformed; called ONLY by `--parallel N>1` (item 05), never by the sequential loop
#   plan-waves       <item|dir|runfile|item-list> --lint [--root <checkout>]  # parallel-automate/10: READ-ONLY lint of both sections with the planner's OWN parser — one `<item>: Touches <verdict>; Depends on <verdict>` line per item + two count lines; exit 1 when any section is missing/unparsable (a sole `unknown` Touches is `ok (declared unknown)`); never needs --max
#
# Exit codes: 0 success; 1 generic failure; 2 abort (malformed pre-existing config, §7);
# 3 progress-append's `current_not_set` guard (the line WAS appended; ## Current was never set).
# (learning-emit, brief-repair, reconcile-status, meta-entry and meta-push-failed are the fail-SAFE
# exceptions: they ALWAYS exit 0 — never die/abort; meta-entry's verdict line carries the outcome.)
#
# TEST SEAM (tests only — never set it in a real run): LOOMWRIGHT_META_SYNC_BIN names the meta-sync
# script `meta-entry` invokes (default: the sibling meta-sync.sh). It selects WHICH pull runs, never
# the mode — the mode is always read from `setup-memory.sh mode`. test-automate-helpers.sh uses it
# for mutation control (i): a pull stand-in that exits 0 on a fetch failure must turn its
# "abort, nothing created" assertion red.

set -euo pipefail

JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
GH="${LOOMWRIGHT_GH_BIN:-gh}"

NL_CHAR='
'

die()   { echo "automate-helpers: $*" >&2; exit 1; }
abort() { echo "automate-helpers: ABORT: $*" >&2; exit 2; }

# --------------------------------------------------------------------------- #
# §7 — config suppress / restore (byte-for-byte; absent-delete; malformed-abort)
# --------------------------------------------------------------------------- #

# config-suppress <config_path> <backup_path>
# Backs up an existing config byte-for-byte to <backup_path>, then writes a config
# with .auto_review=false. If the config is ABSENT, no backup is made (absence is
# recorded by config-restore's marker semantics) and a minimal {"auto_review":false}
# is written. A MALFORMED pre-existing config ⇒ ABORT (exit 2) — never clobber a
# hand-edited config (SKILL §7 "malformed-abort"; Anti-Pattern).
config_suppress() {
  local cfg="$1" bak="$2"
  if [ -f "$cfg" ]; then
    # Validate JSON before touching anything.
    if ! "$JQ" -e . "$cfg" >/dev/null 2>&1; then
      abort "pre-existing config is not valid JSON: $cfg"
    fi
    # Byte-for-byte backup (cp preserves exact bytes).
    cp "$cfg" "$bak"
    # Merge auto_review=false into the existing object (atomic temp+rename).
    local tmp; tmp="$(mktemp "${cfg}.XXXXXX")"
    "$JQ" '.auto_review = false' "$cfg" > "$tmp"
    mv -f "$tmp" "$cfg"
  else
    # Originally absent: write a marker backup so restore knows to DELETE on restore.
    printf '__ABSENT__\n' > "$bak"
    printf '{"auto_review":false}\n' > "$cfg"
  fi
}

# config-restore <config_path> <backup_path>
# Restores config from the backup, OR DELETES config if it was originally absent
# (backup holds the __ABSENT__ marker). Deletes the transient backup on success.
# Never leaves a partial config.json (SKILL §7 "absent-delete").
config_restore() {
  local cfg="$1" bak="$2"
  [ -f "$bak" ] || die "no backup to restore: $bak"
  if [ "$(head -n1 "$bak")" = "__ABSENT__" ]; then
    rm -f "$cfg"
  else
    # Atomic restore (temp+rename) so a crash mid-restore can't half-write.
    local tmp; tmp="$(mktemp "${cfg}.XXXXXX")"
    cp "$bak" "$tmp"
    mv -f "$tmp" "$cfg"
  fi
  rm -f "$bak"
}

# config-orig <config_path> [<backup_path>]
# Prints the auto_review_original value to record in ## Run Config: true|false|absent.
#
# CALL-ORDER (§7): the contract sequence is backup -> suppress -> record, so this is
# normally called AFTER config_suppress has rewritten the live config to
# auto_review:false — at which point the LIVE file reports "false" for every original
# and only the byte-for-byte backup still holds the truth. So when <backup_path>
# exists we read THE BACKUP; otherwise we fall back to the live config (the
# pre-suppress call order, where the live config IS the original). The answer is
# therefore the same in either call order. Losing the true/false/absent distinction
# by reading the wrong FILE would defeat the same care the value-extraction below
# takes to avoid losing it by using the wrong OPERATOR.
#
# A backup path that is GIVEN but MISSING falls back to the live config; it does NOT
# abort the way a MALFORMED backup does (they are different kinds of event: malformed
# can never be legitimate, missing is the normal state of a correct PRE-suppress 2-arg
# call, and aborting on it would re-introduce call-order dependence in the other
# direction). The residual: if the backup is lost AFTER suppress (stale/reused run_id,
# partial cleanup, a race with a concurrent restore) the fallback reports the SUPPRESSED
# value as the original. The helper cannot distinguish that from the pre-suppress call —
# both are "2 args, no backup on disk" — so only the CALLER can prevent it, by recording
# the original before deleting the backup. Both arms pinned in test §A7f; SKILL.md §7.
config_orig() {
  local cfg="$1" bak="${2:-}" src
  if [ -n "$bak" ] && [ -f "$bak" ]; then
    # The __ABSENT__ marker means there was no pre-existing config at suppress time.
    if [ "$(head -n1 "$bak")" = "__ABSENT__" ]; then echo "absent"; return 0; fi
    src="$bak"
  else
    src="$cfg"
  fi
  if [ ! -f "$src" ]; then echo "absent"; return 0; fi
  if ! "$JQ" -e . "$src" >/dev/null 2>&1; then abort "config to read the original from is not valid JSON: $src"; fi
  # NB: use an explicit null/has() check, NOT `.auto_review // "absent"` — the `//`
  # operator is FALSY-triggered, so a genuine `false` would collapse to "absent",
  # making a recorded false original indistinguishable from no config (the same
  # falsy-coercion hazard documented in gate_eval §10). Emit true|false|absent
  # faithfully so ## Run Config records the real original.
  local v; v="$("$JQ" -r 'if has("auto_review") and (.auto_review != null) then .auto_review else "absent" end' "$src")"
  echo "$v"
}

# --------------------------------------------------------------------------- #
# §3 — run-file atomic write + append-only Progress + queue check-off
# --------------------------------------------------------------------------- #

# _progress_block <file> — the lines under the `## Progress` heading, up to the
# next `## ` heading (the heading itself excluded). Empty when there is none.
_progress_block() {
  awk '/^## Progress/ { p=1; next } p && /^## / { p=0 } p' "$1"
}

# _runfile_refusal <staged> <current> <full|title> — prints WHY <staged> must not
# be renamed over <current> (nothing when it may). SKILL §3 "Crash-safety
# contract" → "Validate before rename" is the spec: `full` (runfile-write) checks
# non-empty + `# Automate Run:` title + `## Status:` + `## Queue`; `title` (the
# in-place mutators, whose input was already checked to be a run file) checks
# non-empty + title only, so a hand-edited run file missing a section still takes
# progress lines. Both modes require the staged `## Progress` block to start with
# <current>'s block line-for-line when <current> is a run file — the APPEND-ONLY
# rule, enforced against a generator that died part-way and dropped the tail.
_runfile_refusal() {
  local staged="$1" cur="$2" mode="$3"
  if [ ! -s "$staged" ]; then echo "empty content"; return 0; fi
  if ! is_run_file "$staged"; then echo "content lacks the '# Automate Run:' title line"; return 0; fi
  if [ "$mode" = "full" ]; then
    grep -qE '^## Status:' "$staged" || { echo "content lacks a '## Status:' line"; return 0; }
    grep -qE '^## Queue' "$staged"   || { echo "content lacks the '## Queue' heading"; return 0; }
  fi
  if [ -f "$cur" ] && is_run_file "$cur"; then
    local old_blk new_blk n
    old_blk="$(mktemp "${staged}.old.XXXXXX")"; new_blk="$(mktemp "${staged}.new.XXXXXX")"
    _progress_block "$cur" > "$old_blk"
    n=$(( $(wc -l < "$old_blk") ))
    # n=0 (no prior Progress) is trivially a prefix — and BSD `head -n 0` is an
    # error, not an empty read. Otherwise two plain file reads, no
    # `producer | head` pipe: under pipefail an early head exit can SIGPIPE the
    # producer and fail a correct comparison.
    if [ "$n" -gt 0 ]; then
      _progress_block "$staged" > "$new_blk"
      if ! head -n "$n" "$new_blk" | cmp -s "$old_blk" -; then
        echo "content does not keep the existing ## Progress block ($n line(s)) as its prefix — Progress is append-only"
      fi
    fi
    rm -f "$old_blk" "$new_blk"
  fi
  return 0
}

# _runfile_install <staged> <out> <full|title> <verb> — validate, then rename.
# On refusal: remove <staged>, leave <out> byte-unchanged, exit 1 via die.
_runfile_install() {
  local staged="$1" out="$2" mode="$3" verb="$4" why
  why="$(_runfile_refusal "$staged" "$out" "$mode")"
  if [ -n "$why" ]; then
    rm -f "$staged"
    die "$verb: refused — $why; $out left unchanged [runfile_write_refused]"
  fi
  mv -f "$staged" "$out"
}

# runfile-write <runfile_path>   (content on stdin)
# Atomic write: stage to a temp file in the same dir, VALIDATE (SKILL §3
# "Validate before rename"), then rename into place. The helper cannot see the
# exit status of whatever generated its stdin (`awk … "$RF" | runfile-write "$RF"`
# with a failing awk delivers EOF and nothing else), so the payload itself is
# the only evidence — an empty or structureless one is refused, never installed.
runfile_write() {
  local out="$1" dir tmp
  dir="$(dirname "$out")"
  mkdir -p "$dir"
  tmp="$(mktemp "${out}.XXXXXX")"
  cat > "$tmp" || { rm -f "$tmp"; die "runfile-write: could not stage stdin; $out left unchanged"; }
  _runfile_install "$tmp" "$out" full runfile-write
}

# progress-append <runfile_path> <line>
# Appends ONE line under "## Progress" WITHOUT rewriting any existing line. We
# rebuild the file via atomic write but the prior Progress lines are copied
# verbatim and the new line is inserted at the END of the Progress block — the
# invariant tested is "no prior Progress line is ever altered or dropped".
progress_append() {
  local out="$1" line="$2"
  [ -f "$out" ] || die "run file not found: $out"
  # A file without the run-file title is not a run file (an emptied one, a
  # sidecar, a wrong path) — appending would fabricate a titleless `## Progress`
  # stub that `remaining` reads as 0 and `resume-glob` never lists (SKILL §3).
  is_run_file "$out" || die "progress-append: refused — $out has no '# Automate Run:' title line (not a run file); left unchanged [runfile_write_refused]"
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  # Pass the new line via the ENVIRONMENT (not awk -v): awk's -v assignment
  # interprets backslash escapes in the value, which would mangle a path/line
  # containing a literal backslash. ENVIRON[...] is read verbatim.
  AH_NEWLINE="- $line" awk '
    BEGIN { in_prog=0; appended=0; seen_prog=0; newline=ENVIRON["AH_NEWLINE"] }
    /^## Progress/ { print; in_prog=1; seen_prog=1; next }
    /^## / {
      if (in_prog && !appended) { print newline; appended=1; in_prog=0 }
      print; next
    }
    { print }
    # Fallback: if the (title-checked) run file had NO "## Progress" section,
    # create one rather than silently dropping the event (defensive — the
    # template always includes the section). A NON-run file never gets here.
    END {
      if (!appended) {
        if (!seen_prog) print "## Progress"
        print newline
      }
    }
  ' "$out" > "$tmp" || { rm -f "$tmp"; die "progress-append: rewrite failed; $out left unchanged"; }
  _runfile_install "$tmp" "$out" title progress-append
  _progress_current_guard "$out" "$line"
}

# _progress_current_guard <runfile> <line> — the D2 `current_not_set` guard (SKILL
# §3 "`## Current` moves only through `current-set`"). Runs AFTER a successful
# append, so the line is always recorded (loud, never lossy). A line that says an
# item is in flight — `[<one token> ]picked …`, `ran /autonomous…`, `owned drain
# started…` — while `## Current`'s item is `null`, empty or absent means the engine
# skipped `current-set`: print `current_not_set: <line>` to stderr and exit 3
# (distinct from the refusal exit 1). A `picked <X>` line while `## Current` names a
# DIFFERENT non-null item whose status is not `done` exits 3 the same way (PICK
# skipped `current-set` on a later item). `parked …` is deliberately NOT guarded: a
# run-level park on a fresh run legitimately has a null item. <X> is the first
# whitespace-delimited token after `picked ` with trailing `;`/`,` stripped; both
# sides are compared after stripping a leading `./`.
_progress_current_guard() {
  local out="$1" line="$2"
  local re_g='^([^ ]+ )?(picked |ran /autonomous|owned drain started)'
  local re_p='^([^ ]+ )?picked ([^ ]+)'
  [[ "$line" =~ $re_g ]] || return 0
  local cl ci cs x
  cl="$(_current_item_line "$out")"
  ci="$(_current_field "$cl" item)"
  if [ -z "$ci" ] || [ "$ci" = "null" ]; then
    echo "current_not_set: $line" >&2; exit 3
  fi
  [[ "$line" =~ $re_p ]] || return 0
  x="${BASH_REMATCH[2]}"
  while :; do case "$x" in *";"|*",") x="${x%?}" ;; *) break ;; esac; done
  [ -n "$x" ] || return 0
  cs="$(_current_field "$cl" status)"
  if [ "${x#./}" != "${ci#./}" ] && [ "$cs" != "done" ]; then
    echo "current_not_set: $line" >&2; exit 3
  fi
  return 0
}

# --------------------------------------------------------------------------- #
# §3 — `## Current` moves only through a helper (current-set / current-rebuild)
# --------------------------------------------------------------------------- #

# The documented enums (docs/RESULT_SCHEMAS.md §AUTOMATE_RUN "`## Current` fields";
# SKILL §3 template). Space-delimited so a `case " $ENUM " in *" $v "*)` test is exact.
CURRENT_STATUS_ENUM=" running awaiting_merge escalated failed rate_limit drain_died done "
CURRENT_PAUSE_ENUM=" awaiting_merge awaiting_go escalated limit_reached resume_ambiguous rate_limit drain_died token_ceiling run_lock_held meta_unreachable trail_pr_open closeout_leftover null "

# _current_item_line <runfile> — the FIRST `- item: ` line inside `## Current`, or nothing.
_current_item_line() {
  awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- item: /{print; exit}' "$1" 2>/dev/null || true
}

# _current_reason_line <runfile> — the FIRST `- pause_reason:` line inside `## Current`, or nothing.
_current_reason_line() {
  awk '/^## Current/{c=1;next} /^## /{c=0} c && /^- pause_reason:/{print; exit}' "$1" 2>/dev/null || true
}

# _current_field <item_line> <key> — the value of `<key>: <value>` in a
# `- item: … | status: … | pr: … | branch: …` line (fields split on " | ", the
# same split closeout's `_co_field` uses). Prints nothing when the key is absent.
_current_field() {
  local rest="${1#- }" key="$2" f
  [ -n "$1" ] || return 0
  while :; do
    case "$rest" in
      *" | "*) f="${rest%% | *}"; rest="${rest#* | }" ;;
      *) f="$rest"; rest="" ;;
    esac
    case "$f" in "$key: "*) printf '%s' "${f#"$key: "}"; return 0 ;; esac
    [ -n "$rest" ] || return 0
  done
}

# _current_build_line <old_line> <item> <status> <has_pr> <pr> <has_branch> <branch>
# Rebuilds the item line field-by-field: item/status (and pr/branch when given)
# replace their values in place, every other field keeps its text and position, a
# missing field is appended in template order. No old line ⇒ the template order.
_current_build_line() {
  local old="$1" item="$2" st="$3" hp="$4" pr="$5" hb="$6" br="$7"
  local rest f out="" si=0 ss=0 sp=0 sb=0
  if [ -n "$old" ]; then
    rest="${old#- }"
    while :; do
      case "$rest" in
        *" | "*) f="${rest%% | *}"; rest="${rest#* | }" ;;
        *) f="$rest"; rest="" ;;
      esac
      case "$f" in
        "item: "*) f="item: $item"; si=1 ;;
        "status: "*) f="status: $st"; ss=1 ;;
        "pr: "*) if [ "$hp" = 1 ]; then f="pr: $pr"; fi; sp=1 ;;
        "branch: "*) if [ "$hb" = 1 ]; then f="branch: $br"; fi; sb=1 ;;
      esac
      out="${out:+$out | }$f"
      [ -n "$rest" ] || break
    done
  fi
  if [ "$si" = 0 ]; then out="item: $item${out:+ | $out}"; fi
  if [ "$ss" = 0 ]; then out="$out | status: $st"; fi
  if [ "$sp" = 0 ] && [ "$hp" = 1 ]; then out="$out | pr: $pr"; fi
  if [ "$sb" = 0 ] && [ "$hb" = 1 ]; then out="$out | branch: $br"; fi
  printf -- '- %s\n' "$out"
}

# current-set <runfile> [--item <path|null> --status <s|null>] [--pr <url|null>]
#             [--branch <b|null>] [--pause-reason <r>]
# SKILL §3 "`## Current` moves only through `current-set`" is the spec. Two legal forms:
#   ITEM form      — --item AND --status (the literal `null` only when BOTH are
#                    `null`: "nothing in flight"); --pr/--branch/--pause-reason optional.
#   RUN-LEVEL form — neither --item nor --status; --pause-reason required; no
#                    --pr/--branch (a run-level park never touches the item line).
# Rewrites ONLY the `## Current` block's first `- item:` line (item form) and/or its
# `- pause_reason:` line (appended to the block when absent); every other line of
# the file is byte-unchanged. pr/branch retention: when --item equals the line's
# current item (compared after a leading `./` strip) an omitted --pr/--branch keeps
# the stored value; when --item CHANGES, an omitted --pr/--branch resets to `null`
# (never carry the previous item's PR into a new one). The item is stored exactly
# as passed. Refusals (exit 1, file byte-unchanged): an unknown status/pause_reason,
# a half-null item form, an item form missing --item or --status, a run-level form
# missing --pause-reason (or carrying --pr/--branch), an empty value or one holding
# `|` or a newline, a missing/non-run file, a file with no `## Current` heading.
# Values reach awk through the ENVIRONMENT (never awk -v — SKILL Anti-Patterns); the
# write goes through `_runfile_install … full` (runfile-write's validation).
# Idempotent: values already present ⇒ `current-set: unchanged`, nothing written.
current_set() {
  local out="${1:-}"
  [ "$#" -gt 0 ] && shift
  local CS="current-set: refused —"
  [ -n "$out" ] || die "$CS usage: current-set <runfile> [--item <path|null> --status <s|null>] [--pr <url|null>] [--branch <b|null>] [--pause-reason <r>]"
  local item="" st="" pr="" br="" reason="" hi=0 hs=0 hp=0 hb=0 hr=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --item|--status|--pr|--branch|--pause-reason)
        [ "$#" -ge 2 ] || die "$CS $1 needs a value; $out left unchanged"
        case "$1" in
          --item) item="$2"; hi=1 ;;
          --status) st="$2"; hs=1 ;;
          --pr) pr="$2"; hp=1 ;;
          --branch) br="$2"; hb=1 ;;
          --pause-reason) reason="$2"; hr=1 ;;
        esac
        case "$2" in
          "") die "$CS $1 value is empty; $out left unchanged" ;;
          *"|"*|*"$NL_CHAR"*) die "$CS $1 value contains '|' or a newline; $out left unchanged" ;;
        esac
        shift 2 ;;
      *) die "$CS unknown argument '$1'; $out left unchanged" ;;
    esac
  done
  if [ "$hi" != "$hs" ]; then
    die "$CS the item form needs both --item and --status; $out left unchanged"
  fi
  if [ "$hi" = 0 ]; then
    [ "$hr" = 1 ] || die "$CS the run-level form needs --pause-reason; $out left unchanged"
    if [ "$hp" = 1 ] || [ "$hb" = 1 ]; then die "$CS --pr/--branch need the item form (--item + --status); $out left unchanged"; fi
  else
    if { [ "$item" = null ] && [ "$st" != null ]; } || { [ "$item" != null ] && [ "$st" = null ]; }; then
      die "$CS half-null item form (--item $item --status $st) — 'null' only when both are null; $out left unchanged"
    fi
    if [ "$st" != null ]; then
      case "$CURRENT_STATUS_ENUM" in *" $st "*) ;; *) die "$CS unknown status '$st'; $out left unchanged" ;; esac
    fi
  fi
  if [ "$hr" = 1 ]; then
    case "$CURRENT_PAUSE_ENUM" in *" $reason "*) ;; *) die "$CS unknown pause_reason '$reason'; $out left unchanged" ;; esac
  fi
  [ -f "$out" ] || die "$CS run file not found: $out"
  is_run_file "$out" || die "$CS not a run file (no '# Automate Run:' title): $out; left unchanged [runfile_write_refused]"
  grep -q '^## Current' "$out" || die "$CS no '## Current' heading in $out; left unchanged"

  local old_line new_line="" old_reason new_reason="" change=0
  old_line="$(_current_item_line "$out")"
  if [ "$hi" = 1 ]; then
    local old_item; old_item="$(_current_field "$old_line" item)"
    if [ "${old_item#./}" != "${item#./}" ]; then
      if [ "$hp" = 0 ]; then pr=null; hp=1; fi
      if [ "$hb" = 0 ]; then br=null; hb=1; fi
    fi
    new_line="$(_current_build_line "$old_line" "$item" "$st" "$hp" "$pr" "$hb" "$br")"
    [ "$new_line" = "$old_line" ] || change=1
  fi
  if [ "$hr" = 1 ]; then
    old_reason="$(_current_reason_line "$out")"
    new_reason="- pause_reason: $reason"
    [ "$new_reason" = "$old_reason" ] || change=1
  fi
  if [ "$change" = 0 ]; then echo "current-set: unchanged"; return 0; fi

  local have_item=0; [ -n "$old_line" ] && have_item=1
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  CS_ITEM_ON="$hi" CS_NEW_ITEM="$new_line" CS_HAVE_ITEM="$have_item" \
  CS_REASON_ON="$hr" CS_NEW_REASON="$new_reason" awk '
    BEGIN { ion=ENVIRON["CS_ITEM_ON"]; nitem=ENVIRON["CS_NEW_ITEM"]; have=ENVIRON["CS_HAVE_ITEM"]
            ron=ENVIRON["CS_REASON_ON"]; nreason=ENVIRON["CS_NEW_REASON"] }
    /^## Current/ && !seen {
      seen=1; c=1; print
      if (ion == 1 && have != 1) { print nitem; idone=1 }
      next
    }
    /^## / {
      if (c && ron == 1 && !rdone) { print nreason; rdone=1 }
      c=0; print; next
    }
    c && ion == 1 && !idone && /^- item: / { print nitem; idone=1; next }
    c && ron == 1 && !rdone && /^- pause_reason:/ { print nreason; rdone=1; next }
    { print }
    END { if (c && ron == 1 && !rdone) print nreason }
  ' "$out" > "$tmp" || { rm -f "$tmp"; die "current-set: rewrite failed; $out left unchanged"; }
  _runfile_install "$tmp" "$out" full current-set
  echo "current-set: written"
}

# current-rebuild <runfile> — SKILL §4 RECONCILE repair for a `## Current` an
# engine never set (lane w1-10: one creation write, then Progress-only updates).
# Acts ONLY when `## Current`'s item is null/empty/absent AND `## Progress` has a
# `picked ` line. Item: from the LAST Progress line matching `^- ([^ ]+ )?picked `
# — the first whitespace-delimited token after `picked `, trailing `;`/`,` stripped
# — and it must be a Queue row (`- [ ] <item>` or `- [x] <item>…`). PR: ONLY from a
# `ran /autonomous` line AFTER that last `picked` line (its first
# `https?://…/pull/<n>` token) — never from any other Progress line (closeout step
# lines, `cross-run closeout` lines, trail and reconcile-status lines carry OTHER
# PRs' URLs). Branch: one `gh pr view <pr> --json headRefName,state,mergedAt`.
# Status: ALWAYS `running` (OPEN, MERGED, CLOSED or unreadable) — a rebuild never
# claims awaiting_merge/READY/escalated and never triggers a close-out; the
# observed state is named in the line for the owner. Writes via current-set, then
# progress-appends and prints `current_rebuilt: <item> pr <url|null> state
# <OPEN|MERGED|CLOSED|unknown|none>` (`none` = no PR found). Already set ⇒
# `current-rebuild: skipped — ## Current set`. Exit 0 except a refused write (1).
current_rebuild() {
  local out="${1:-}" R="current-rebuild: skipped —"
  [ -n "$out" ] || die "current-rebuild: refused — usage: current-rebuild <runfile>"
  [ -f "$out" ] || die "current-rebuild: refused — run file not found: $out"
  is_run_file "$out" || die "current-rebuild: refused — not a run file (no '# Automate Run:' title): $out; left unchanged [runfile_write_refused]"
  local ci; ci="$(_current_field "$(_current_item_line "$out")" item)"
  if [ -n "$ci" ] && [ "$ci" != null ]; then echo "$R ## Current set"; return 0; fi
  local picked_ln item
  picked_ln="$(_progress_block "$out" | awk '/^- ([^ ]+ )?picked /{n=NR; l=$0} END{if (n) print n "\t" l}')"
  if [ -z "$picked_ln" ]; then echo "$R no picked line in ## Progress"; return 0; fi
  local tab=$'\t'
  local pnum="${picked_ln%%"$tab"*}" pline="${picked_ln#*"$tab"}" re_p='^- ([^ ]+ )?picked ([^ ]+)'
  if [[ "$pline" =~ $re_p ]]; then item="${BASH_REMATCH[2]}"; else item=""; fi
  while :; do case "$item" in *";"|*",") item="${item%?}" ;; *) break ;; esac; done
  if [ -z "$item" ] || ! AH_ITEM="$item" awk '
      BEGIN { it=ENVIRON["AH_ITEM"] }
      /^## Queue/ { q=1; next } /^## / { q=0 }
      q && ($0 == "- [ ] " it || $0 == "- [x] " it || index($0, "- [x] " it " ")==1) { f=1 }
      END { exit !f }' "$out"; then
    echo "$R picked item not in Queue"; return 0
  fi
  local pr
  pr="$(_progress_block "$out" | PN="$pnum" awk '
    NR > ENVIRON["PN"]+0 && /^- ([^ ]+ )?ran \/autonomous/ {
      if (match($0, /https?:\/\/[^ ]*\/pull\/[0-9]+/)) u=substr($0, RSTART, RLENGTH)
    }
    END { if (u != "") print u }')"
  local state="none" branch="null"
  if [ -n "$pr" ]; then
    local view s m h
    state="unknown"
    if view="$("$GH" pr view "$pr" --json headRefName,state,mergedAt 2>/dev/null)"; then
      s="$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null || true)"
      m="$(printf '%s' "$view" | "$JQ" -r '.mergedAt // empty' 2>/dev/null || true)"
      h="$(printf '%s' "$view" | "$JQ" -r '.headRefName // empty' 2>/dev/null || true)"
      if [ "$s" = MERGED ] || [ -n "$m" ]; then state=MERGED
      elif [ "$s" = OPEN ] || [ "$s" = CLOSED ]; then state="$s"; fi
      case "$h" in ""|*"|"*|*" "*) ;; *) branch="$h" ;; esac
    fi
  else
    pr=null
  fi
  current_set "$out" --item "$item" --status running --pr "$pr" --branch "$branch" >/dev/null
  local msg="current_rebuilt: $item pr $pr state $state"
  progress_append "$out" "$msg"
  echo "$msg"
}

# queue-checkoff <runfile_path> <item> [reason] [mark]
# Flips "- [ ] <item>" to "- [x] <item>". With a reason, writes the excluded form
# "- [x] <item>  # <mark>: <reason>" where <mark> is "skipped" (default) or
# "abandoned" (§5 — both are checked-off so the item is never re-picked and does not
# block ## Status: done). Atomic write. Idempotent on already-checked items
# (leaves them untouched).
queue_checkoff() {
  local out="$1" item="$2" reason="${3:-}" mark="${4:-skipped}"
  case "$mark" in skipped|abandoned) ;; *) die "queue-checkoff: mark must be skipped|abandoned (got '$mark')" ;; esac
  [ -f "$out" ] || die "run file not found: $out"
  is_run_file "$out" || die "queue-checkoff: refused — $out has no '# Automate Run:' title line (not a run file); left unchanged [runfile_write_refused]"
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  # Pass item/reason via the ENVIRONMENT (not awk -v): -v interprets backslash
  # escapes in the value, which would mangle a path/reason containing a literal
  # backslash. ENVIRON[...] is read verbatim.
  AH_ITEM="$item" AH_REASON="$reason" AH_MARK="$mark" awk '
    BEGIN { item=ENVIRON["AH_ITEM"]; reason=ENVIRON["AH_REASON"]; mark=ENVIRON["AH_MARK"] }
    {
      line=$0
      # Match an unchecked queue line whose payload (after "- [ ] ") equals item.
      if (line ~ /^- \[ \] /) {
        payload=substr(line, 7)
        if (payload == item) {
          if (reason != "")
            print "- [x] " item "  # " mark ": " reason
          else
            print "- [x] " item
          next
        }
      }
      print line
    }
  ' "$out" > "$tmp" || { rm -f "$tmp"; die "queue-checkoff: rewrite failed; $out left unchanged"; }
  _runfile_install "$tmp" "$out" title queue-checkoff
}

# remaining <runfile_path>
# Counts ONLY unchecked "- [ ]" lines (skipped/checked items excluded), so a
# skipped item never blocks ## Status: done (§3/§5).
remaining() {
  local out="$1"
  [ -f "$out" ] || die "run file not found: $out"
  grep -c '^- \[ \] ' "$out" || true
}

# ceiling-check <runfile_path> <max_tokens> [--root <checkout>]
# §6 step 1 PICK-time token ceiling. Sums the run's ledger via
# `read-token-ledger.sh --run-id <runfile>` (§1.5) and compares its TOTAL
# against <max_tokens>. Always prints exactly ONE line and returns 0 (a PARK
# is a normal, expected outcome here — same fail-CLOSED-but-never-crash
# convention gate_eval already uses, never a shell failure the caller has to
# special-case):
#   "OK total=<n> max=<n>"                          — under the ceiling, proceed
#   "PARK: token_ceiling total=<n> max=<n>"          — strictly exceeding the ceiling (total > max; exactly at max is OK)
#   "PARK: ledger_unreadable"                        — reader could not sum anything
# This is the load-bearing seam mutation-control targets (test-automate-helpers.sh
# §"ceiling-check"): a ledger reader that always reports 0 real tokens must
# never let this print "OK" when the true spend is over <max_tokens>.
ceiling_check() {
  local out="$1" max="$2" root=""
  shift 2 2>/dev/null || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) root="${2:-.}"; shift 2 2>/dev/null || shift ;;
      *) shift ;;
    esac
  done
  [ -f "$out" ] || die "run file not found: $out"
  case "$max" in
    ''|*[!0-9]*) die "ceiling-check: max_tokens must be a non-negative integer (got '$max')" ;;
  esac
  local reader="$(dirname "$0")/read-token-ledger.sh"
  local args=(--run-id "$out")
  [ -n "$root" ] && args+=(--root "$root")
  local ledger_out=""
  if [ -x "$reader" ] || [ -f "$reader" ]; then
    ledger_out="$(bash "$reader" "${args[@]}" 2>/dev/null || true)"
  fi
  # Here-string / built-in regex, never `printf | grep -q` or `| head -1`: under
  # `set -euo pipefail` an early-exiting reader (grep -q on its first match,
  # head -1) can SIGPIPE the producer and fail the pipeline on a correct answer.
  if [ -z "$ledger_out" ] || grep -q 'LEDGER_UNREADABLE=1' <<<"$ledger_out"; then
    echo "PARK: ledger_unreadable"
    return 0
  fi
  local total="" re_total='TOTAL=([0-9]+)'
  if [[ "$ledger_out" =~ $re_total ]]; then total="${BASH_REMATCH[1]}"; fi
  if [ -z "$total" ]; then
    echo "PARK: ledger_unreadable"
    return 0
  fi
  if [ "$total" -gt "$max" ]; then
    echo "PARK: token_ceiling total=${total} max=${max}"
    return 0
  fi
  echo "OK total=${total} max=${max}"
  return 0
}

# --------------------------------------------------------------------------- #
# §2 — folder / backlog-doc resolvers
# --------------------------------------------------------------------------- #

# is_done <file> — true when the file carries a terminal close-out stamp on its
# `## Status:` HEADING line. Both terminal values count: `done_with_escalation`
# work still SHIPPED, so re-picking it would redo merged work. (The `\b` after a
# bare `done` does NOT match `done_with_escalation` — `_` is a word character —
# which is why the escalated arm is spelled out rather than left to the boundary.)
# Authority for what the completion tail writes here: skills/self-heal-advisory/SKILL.md
# step 2.5, which stamps the value ON this heading for exactly this reason.
is_done() { grep -qE '^## Status:[[:space:]]*done(_with_escalation)?\b' "$1" 2>/dev/null; }

# is_not_ready <file> — true when the file carries a not-ready-to-run stamp on
# its `## Status:` HEADING line (`proposed` or `parked`). This is a SEPARATE
# predicate from `is_done` and MUST NOT be folded into it (decision H2):
# `is_done` is shared with `resume-glob`, whose run files use a DIFFERENT
# status vocabulary (`running|paused|done`, per docs/RESULT_SCHEMAS.md
# §AUTOMATE_RUN) — a run file stamped `## Status: paused` must never be
# treated as not-ready, so `is_not_ready` is called ONLY from `resolve_folder`
# and `resolve_backlog_dir`, never from `resume_glob`.
is_not_ready() { grep -qE '^## Status:[[:space:]]*(proposed|parked)\b' "$1" 2>/dev/null; }

# is_run_file <file> — true when the file carries the `/automate` run-file title
# line `# Automate Run:` (docs/RESULT_SCHEMAS.md §AUTOMATE_RUN; the H1 every run
# file is written with). A SHAPE check, not a filename rule: the per-run result
# sidecars `<run_id>.review-heal-result.md` / `<run_id>.supervisor-result.md`
# (skills/automate-loop/SKILL.md §6 steps 2-3) share this directory and the `.md`
# extension but are verbatim `## REVIEW_HEAL_RESULT` / `## SUPERVISOR_RESULT`
# blocks with no such line, so they — and any future sidecar — are never taken
# for a run. Line-anchored ANYWHERE in the file, deliberately not "line 1 only":
# a leading blank line or front-matter must never hide a real incomplete run from
# RESUME (hiding a run is the worse failure).
#
# Tolerated title forms (RUN_TITLE_ERE, automate-followups/19) — the line may
# differ from the exact `# Automate Run:` only in:
#   D1 letter case — `# automate run:` matches (no sidecar carries the phrase,
#      and a miss hides a run);
#   D2 a leading UTF-8 BOM (bytes EF BB BF) — built with printf octal because
#      BSD grep ERE has no `\x` escape, and matched under `env LC_ALL=C` so the
#      bytes compare as bytes in every locale;
#   D3 0-3 leading spaces — the CommonMark ATX-heading limit. 4+ spaces or a
#      leading tab is an indented CODE BLOCK, not a heading: a sidecar or
#      requirement quoting `    # Automate Run: x` must never be listed (that
#      would re-create the `resume_ambiguous` failure automate-followups/03 fixed);
#   D4 whitespace — zero-or-more spaces/tabs between `#` and `Automate`,
#      one-or-more between `Automate` and `Run`, zero-or-more before `:`.
#      Exactly ONE `#`: `## Automate Run:` (an H2) is not a run file.
# build-handoff.sh's AUTOMATE title reader carries a mirrored copy of these two
# assignments (it does not source this file) — change both together.
#
# Callers (every one shares this predicate, so a tolerated title is accepted by
# all of them): `resume_glob` (the RESUME list); the `runfile-write` validator
# `_runfile_refusal` (the staged-content check AND the existing-file check that
# arms the append-only Progress rule); `progress_append` and `queue_checkoff`
# (their target pre-checks); and `plan_waves` (its run-file-vs-item-list input
# branch). Requirement files are not run files, so `resolve_folder` /
# `resolve_backlog*` never call it (same scoping discipline as `is_not_ready`,
# decision H2).
_RUN_TITLE_BOM="$(printf '\357\273\277')"
RUN_TITLE_ERE="^(${_RUN_TITLE_BOM})? {0,3}#[[:blank:]]*[Aa][Uu][Tt][Oo][Mm][Aa][Tt][Ee][[:blank:]]+[Rr][Uu][Nn][[:blank:]]*:"
is_run_file() { env LC_ALL=C grep -qE "$RUN_TITLE_ERE" "$1" 2>/dev/null; }

# resolve-folder <dir> — every *.md NOT marked "## Status: done" and not
# "## Status: proposed|parked" (sorted).
resolve_folder() {
  local dir="$1" f
  [ -d "$dir" ] || die "folder not found: $dir"
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_done "$f" && continue
    is_not_ready "$f" && continue
    echo "$f"
  done | env LC_ALL=C sort
}

# resolve-backlog <backlog.md> — emit items in DOCUMENTED build order, honoring
# done/✅ markers (SKILL §2 "Backlog-doc source"). We parse "- [ ] <path>" /
# "- [x] <path>" checklist lines (the documented order = file order) and emit
# only the not-done ones. Done is read from TWO places, either one excludes:
#   (1) the line — a checked "[x]" box, a "✅", or an inline "# Status: done";
#   (2) the file the line names — its own `## Status: done|done_with_escalation`
#       heading (`is_done`, the predicate resolve-folder and the dir fallback
#       use). This is the evidence-gated truth: `closeout` writes that stamp
#       after reading the PR MERGED, and the engine never ticks the backlog doc
#       (human-owned), so without (2) every merged item is re-queued by the next
#       `--backlog` run. Resolved by `_backlog_item_file`: an unresolvable path is
#       NOT read and the line stays listed (fail toward listing).
# _BACKLOG.md-absent ⇒ fall back to dir scan.
# SCOPE BOUNDARY (deliberate, not an oversight): a checklist line here names a
# path directly, which is a human's explicit inclusion decision for that line.
# So the NOT-READY stamp (`## Status: proposed|parked`, `is_not_ready`) is
# honoured ONLY on the dir-fallback path below (`resolve_backlog_dir`), never
# when a checklist line directly names an existing file. The DONE stamp is
# different — nobody includes merged work on purpose — so (2) applies here.
# _backlog_item_file <payload> <backlog.md> — the file a checklist payload names,
# for the read-only `is_done` check above, or nothing. Tried as written (relative
# to the cwd — the repo root the loop runs from — or absolute), then relative to
# the backlog doc's directory. Same safety rules as the dir fallback, which only
# ever reads `*.md` entries: the candidate must end in `.md` and be a regular
# file (`-f` follows a symlink to a regular file, exactly as the dir fallback's
# glob does). A leading `-` is defused with `./` so `grep` never takes it as an
# option. Anything else — empty, missing, a directory, a non-`*.md` — prints
# nothing, and the caller keeps the line listed.
_backlog_item_file() {
  local p="$1" doc="$2" c
  case "$p" in *.md) ;; *) return 0 ;; esac
  for c in "$p" "$(dirname "$doc")/$p"; do
    case "$c" in /*) ;; *) c="./$c" ;; esac
    if [ -f "$c" ]; then printf '%s\n' "$c"; return 0; fi
    case "$p" in /*) return 0 ;; esac   # absolute: no doc-relative retry
  done
  return 0
}

resolve_backlog() {
  local doc="$1"
  if [ ! -f "$doc" ]; then
    # Fallback: scan the directory the path points into by ## Status: stamp.
    local d; d="$(dirname "$doc")"
    [ -d "$d" ] && resolve_backlog_dir "$d"
    return 0
  fi
  # Preserve documented order; emit not-done checklist items.
  while IFS= read -r line; do
    case "$line" in
      "- [x] "*|"- [X] "*) continue ;;          # checked ⇒ done
      "- [ ] "*)
        # NOTE: '[' and ']' are glob metachars in parameter-expansion patterns,
        # so strip the fixed 6-char "- [ ] " prefix by offset, not by '#- [ ] '.
        local payload="${line:6}"
        case "$payload" in
          *"✅"*) continue ;;                    # explicit done marker
          *"# Status: done"*|*"## Status: done"*) continue ;;
        esac
        # strip any trailing inline comment / marker, keep the item token
        payload="${payload%%  #*}"
        local item_file
        item_file="$(_backlog_item_file "$payload" "$doc")"
        if [ -n "$item_file" ] && is_done "$item_file"; then continue; fi   # (2) file stamp
        echo "$payload"
        ;;
    esac
  done < "$doc"
}

# resolve_backlog_dir <dir> — fallback ordering by directory order over *.md,
# excluding ## Status: done files and ## Status: proposed|parked files.
resolve_backlog_dir() {
  local dir="$1" f
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_done "$f" && continue
    is_not_ready "$f" && continue
    echo "$f"
  done | env LC_ALL=C sort
}

# --------------------------------------------------------------------------- #
# §4 — resume: glob + reconcile (run-file is BELIEF; git/gh is TRUTH)
# --------------------------------------------------------------------------- #

# resume-glob <automate_dir> — list RUN FILES (is_run_file: they carry the
# `# Automate Run:` title line) that are NOT marked "## Status: done". A *.md
# without that title — the §6 steps 2-3 result sidecars
# (`<run_id>.review-heal-result.md`, `<run_id>.supervisor-result.md`), transient
# or committed — is skipped BEFORE the done check, so it is never reported as an
# incomplete run (it has no `## Status:` line, so `is_done` alone would list it,
# and >1 listed run fails RESUME closed as `resume_ambiguous`).
resume_glob() {
  local dir="$1" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_run_file "$f" || continue
    is_done "$f" && continue
    echo "$f"
  done | env LC_ALL=C sort
}

# reconcile-item <pr_url> <belief> — reconcile a single in-flight item's BELIEF
# (the checkbox/Current status the run file remembers) against GROUND TRUTH via
# gh/git. Prints the CORRECTED state, one of:
#   merged          — PR is MERGED (gh state==MERGED or mergedAt non-null);
#                     item should be "- [x]" regardless of what the file believed.
#   awaiting_merge  — PR is OPEN/unmerged; item stays awaiting_merge even if the
#                     file believed it checked (a premature check-off).
#   gone            — PR is CLOSED-unmerged (neither merged nor open).
# Reconcile ALWAYS prefers ground truth (SKILL §4 / Anti-Pattern: never trust a
# checkbox without reconciling). `gh` is stubbable via the LOOMWRIGHT_GH_BIN
# env override.
#
# SCOPE: this helper resolves the gh-PR-STATE half of reconcile only (merged /
# open / closed-unmerged). The complementary git-branch-LANDED corroboration that
# SKILL §4 lists ("Branch landed? `git branch --contains <sha>`") is performed by
# the loop itself, not here — wiring git into this helper would need stub fixtures
# out of scope for the pure-logic library. So this returning `merged`/`gone` is
# the gh half; it is NOT incomplete.
reconcile_item() {
  # <belief> is accepted for call-site symmetry with the run file's remembered
  # status (SKILL §1.5 signature) but is INTENTIONALLY IGNORED — ground truth
  # (gh/git) always wins (SKILL §4), so it never influences the result.
  local url="$1" belief="${2:-}"
  : "${belief:-}"   # referenced only to mark it deliberately unused
  local view state merged
  if ! view="$("$GH" pr view "$url" --json state,mergedAt 2>/dev/null)"; then
    # Unreadable ⇒ fail closed to the safe non-merged belief.
    echo "awaiting_merge"; return 0
  fi
  state="$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null || true)"
  merged="$(printf '%s' "$view" | "$JQ" -r '.mergedAt // empty' 2>/dev/null || true)"
  if [ "$state" = "MERGED" ] || [ -n "$merged" ]; then
    echo "merged"; return 0
  fi
  if [ "$state" = "OPEN" ]; then
    echo "awaiting_merge"; return 0
  fi
  # CLOSED-unmerged or unknown.
  echo "gone"
}

# --------------------------------------------------------------------------- #
# §10 — trusted auto-merge gate (conditions enumerated in skills/automate-loop/SKILL.md §10; fail CLOSED, SELF-RESOLVING)
# --------------------------------------------------------------------------- #

# _ge_result_field <file> <field> — bounded grep/awk extraction of one scalar
# field's value from the LAST `REVIEW_HEAL_RESULT` block in <file> (markdown
# `## REVIEW_HEAL_RESULT` / `- field: value` bullet form, OR YAML
# `REVIEW_HEAL_RESULT:` / `  field: value` form — "last block wins", mirroring
# result_block_parser.py's own convention). result_block_parser.py exposes NO
# CLI (it is a library; its `__main__` guard prints a usage notice and exits 0
# — checked before writing this), so this is the bounded grep/awk fallback the
# brief sanctions. Prints the trimmed scalar (surrounding double-quotes
# stripped), or nothing when the field/file/block is absent.
_ge_result_field() {
  local file="$1" field="$2"
  [ -f "$file" ] || return 0
  awk -v field="$field" '
    BEGIN { in_block = 0; val = "" }
    /^##[ \t]*REVIEW_HEAL_RESULT[ \t]*$/ { in_block = 1; val = ""; next }
    /^REVIEW_HEAL_RESULT:[ \t]*$/        { in_block = 1; val = ""; next }
    in_block && /^##[ \t]/                        { in_block = 0 }
    in_block && /^[A-Za-z_][A-Za-z0-9_]*:[ \t]*$/  { in_block = 0 }
    in_block {
      line = $0
      sub(/^[ \t]*-[ \t]*/, "", line)
      sub(/^[ \t]+/, "", line)
      if (line ~ ("^" field "[ \t]*:")) {
        sub(("^" field "[ \t]*:[ \t]*"), "", line)
        sub(/[ \t]+#.*$/, "", line)
        gsub(/^"/, "", line)
        gsub(/"$/, "", line)
        val = line
      }
    }
    END { print val }
  ' "$file"
}

# _ge_pr_parts <pr_url> — "owner\trepo\tnumber" parsed from a
# https://github.com/<owner>/<repo>/pull/<n> URL, or three empty fields when
# the URL does not match (the caller's subsequent gh/api calls then target a
# malformed path and fail closed on their own — no separate error path needed).
_ge_pr_parts() {
  local url="$1" rest ownerrepo number owner repo
  case "$url" in
    *github.com/*/*/pull/*)
      rest="${url#*github.com/}"
      ownerrepo="${rest%%/pull/*}"
      number="${rest#*/pull/}"
      number="${number%%[!0-9]*}"
      owner="${ownerrepo%%/*}"
      repo="${ownerrepo#*/}"
      printf '%s\t%s\t%s\n' "$owner" "$repo" "$number"
      ;;
    *)
      printf '\t\t\n'
      ;;
  esac
}

# gate-eval <pr_url> <ctx.json> [--root <checkout>]
# SELF-RESOLVING decision over the trusted-merge conditions (red-team-hardening item 03;
# the authoritative enumeration is skills/automate-loop/SKILL.md §10):
# the gate re-derives every condition it can from LIVE ground truth (`gh`,
# GraphQL, `classify-risk.sh`, and two artifact-file reads) instead of trusting
# a model-authored value — a caller can no longer hand the gate a fabricated
# verdict for any of conditions 2 through 7. Prints "MERGE" and EXECUTES
# `gh pr merge --squash <url>` ONLY when EVERY condition holds; otherwise prints
# "PARK: <reason>" and returns 0 (a PARK is a normal, expected outcome — fail
# CLOSED, never crash).
#
# ctx.json shape — SHRUNK to exactly what only the drain/caller can know (every
# other former key is now GATE-OWNED and REFUSED if present — see below):
#   {
#     "drain_result": "READY|ESCALATED",           # cond 1 — the owned drain's terminal decision
#     "termination_reason": "converged|bound_hit|sub_floor_converged|ci_untrusted",  # cond 1b
#        # A "sub_floor_converged" drain skipped its final all-channel re-scan, so it is NOT
#        # merge-eligible. "ci_untrusted" (ci-trust-probe-01) always pairs with drain_result ==
#        # "ESCALATED" (never "READY" — scripts/ci-run-probe.sh classifying a required check
#        # untrusted_infra still blocks READY, review-heal/SKILL.md §"READY redefinition"), so a
#        # well-formed ctx already PARKs via cond 1's plain drain_result != "READY" check below.
#        # Condition 1c (below, immediately after 1b) is a SEPARATE, DELIBERATE defense-in-depth
#        # PARK for this value specifically — bot review (PR #266) correctly flagged an earlier
#        # draft of this comment as self-contradicting, since it claimed "no code change needed"
#        # for the exact branch the same diff adds. Read with an explicit has()/!= null check:
#        # missing/null ⇒ PARK.
#     "ready_sha": "<sha>",                         # cond 2 — the drain's claim, cross-checked
#        # against the LIVE `gh pr view --json headRefOid` (never trusted alone).
#     "trust_unprotected": true|false,              # cond 4 override — a legitimate operator flag,
#        # NOT a fact the gate can observe, so it stays a ctx input.
#     "review_heal_result_path": "<path>",          # cond 1/1b cross-check — a file containing the
#        # verbatim REVIEW_HEAL_RESULT block the owned drain emitted; drain_result/termination_reason
#        # above MUST match the block's own decision/termination_reason, or the gate PARKs — the
#        # drain's self-report is corroborated against the artifact it actually wrote, never trusted blind.
#     "supervisor_result_path": "<path>"            # cond 5 rubric — a file containing a
#        # `rubric_score: N/M` line (the Supervisor Phase 4.5 SUPERVISOR_RESULT record). The gate
#        # parses it itself; N==M ⇒ satisfied, no such line ⇒ "na" (not a blocker), unreadable file ⇒ PARK.
#   }
#
# GATE-OWNED KEYS — REFUSED, NEVER TRUSTED. The ctx keys below now name
# conditions the gate computes itself. If ANY of them is present in ctx.json --
# REGARDLESS of the value it carries — the gate PARKs with
# `ctx_carries_gate_owned_key` BEFORE evaluating anything else: `high_risk`,
# `risk_reasons`, `head_sha`, `base`, `review_decision`,
# `unresolved_human_thread`, `protection_enforceable`, `checks_green`,
# `rubric_satisfied`, `rules_gate`, `rules_ok`, `rules_check`. A caller attempting to hand the gate a pre-computed
# verdict for a gate-owned condition is refused, never silently accepted.
#
# Self-resolution per condition (all fail CLOSED — any read failure ⇒ PARK):
#   cond 2  `gh pr view <url> --json headRefOid,baseRefName,statusCheckRollup` (this combined
#           call also feeds cond 5's checks — mirrors review-heal/SKILL.md §U1(a)'s own combined
#           read). Live `headRefOid` must equal ctx's `ready_sha`; live `baseRefName` must be `main`.
#   cond 3  a SEPARATE `gh pr view <url> --json reviewDecision` call (kept apart from cond 2's read
#           so a reviewDecision-specific failure parks on its OWN named reason,
#           `review_decision_unreadable`, rather than being masked by cond 2's `head_sha_moved`
#           firing first on a combined-call failure) — null ⇒ "none", unreadable ⇒ "unreadable" —
#           PLUS the review-threads GraphQL query — adapted from review-heal/SKILL.md §U1(b) (same
#           query minus the unused `body` field) — to compute the unresolved-human-thread blocker: any unresolved thread
#           whose first-comment actor is NOT in the trusted-actor set
#           (`${HOME}/.claude/loomwright/trusted-actors.json`, red-team-hardening item 01 — same
#           fail-CLOSED "absent file ⇒ nobody trusted" resolution as `wrap-external-text.sh`, no
#           `bot_author_re` fallback here) blocks; `hasNextPage` (truncated >100 threads) blocks;
#           any GraphQL read error blocks.
#   cond 4  `gh api repos/<owner>/<repo>/branches/main/protection` — a 404 ⇒ unprotected (false);
#           ANY OTHER error ⇒ `protection_unreadable` (PARK). `trust_unprotected` stays a ctx input
#           (an operator flag, not an observable fact).
#   cond 5  required-check greenness from the SAME protection payload's required-context list
#           (review-heal/SKILL.md §U2's discovery recipe) cross-referenced against the combined
#           call's `statusCheckRollup`. Rubric satisfaction is now a FILE READ: ctx's
#           `supervisor_result_path` is parsed for a `rubric_score: N/M` line by THIS gate (never
#           asserted by a caller) — N==M ⇒ satisfied, absent line ⇒ "na" (not a blocker), unreadable
#           file ⇒ PARK.
#   cond 6  the gate ITSELF invokes `"$(dirname "$0")/classify-risk.sh" main <live head_sha>
#           --root <root>` and reads `.high_risk`/`.reasons` from its own output — no ctx input of
#           any kind feeds this condition any more. NO override of any kind (owner decision R5):
#           not `--trust-unprotected` (cond 4 only), not a config key, not an exclude list.
#   cond 7  evaluated AFTER cond 6. PIN FIRST (automate-followups/16), before the helper runs:
#           `git -C <root> rev-parse HEAD` must equal the live head SHA cond 2 confirmed, else
#           `rules_gate_head_mismatch` (a non-checkout root / unreadable or empty HEAD parks the
#           same way — never a match); then `git status --porcelain -uall`, read from the repo top
#           level, must list nothing outside `.supervisor/` and `.claude/agent-memory/` (tracked
#           edits, staged changes and untracked non-ignored files all count; gitignored files do
#           not), else `rules_gate_dirty_tree` (a failing `git status` parks the same way).
#           Local-only git state cannot hide dirt: a tracked file flagged assume-unchanged or
#           skip-worktree (`git ls-files -v`) parks; ignored-ness is judged from per-directory
#           `.gitignore` files plus the USER's global excludes file (`core.excludesFile` from
#           `git config --global --includes`, else `$XDG_CONFIG_HOME/git/ignore` /
#           `~/.config/git/ignore`; absolute, and PHYSICALLY outside the checkout only —
#           symlinks and directory aliases resolved, ancestors compared by device + inode), so
#           `.git/info/exclude` and a repo-local or env-injected `core.excludesFile` cannot hide
#           an untracked file, and an untracked `.gitignore` git reads (outside an ignored
#           directory) parks; the GIT_CONFIG_* env injection family is unset and fsmonitor /
#           untracked-cache are off; a root whose top level cannot be read parks. SUBMODULES:
#           the status read runs with `--ignore-submodules=none` (a committed `.gitmodules`
#           `ignore = all` cannot hide a dirty submodule or one checked out at a commit other
#           than the recorded one), and every checked-out submodule gets the same reads,
#           recursively. Both are fail-CLOSED with NO override; the helper is not called on a
#           checkout that fails either. Honest limits: a rule `binds` path under one of the two
#           excluded engine-owned paths is not covered by the cleanliness pin, and settings in
#           the repo's own `.git/config` that redefine a modification (`core.fileMode=false`,
#           `core.autocrlf`, clean filters) are honoured as configured; a globally-ignored file
#           is trusted not to be a bound file, and a HARD link from the global excludes path to
#           an in-repo file is not detected (symlinks and aliases are); an un-initialised
#           submodule (no `.git`) is not descended into, and a submodule path git must quote
#           parks; the untracked-`.gitignore` park relies on `ls-files -o -i --directory`
#           listing the contents of a directory no rule ignores rather than collapsing it
#           (git 2.54 / 2.55 list them; the R11f harness precondition asserts it); a tool
#           cache's self-ignoring `*` .gitignore (.pytest_cache/, .venv/) parks unless a
#           committed or global ignore covers its directory. Fix hint for
#           a clean-checkout `rules_gate_dirty_tree`: a committed or global ignore line (never
#           `.git/info/exclude`). Normal path: the owned inline `/review-pr`
#           drain checks the PR branch out on the main-thread checkout, so `<root>` is at the PR
#           head when GATE runs. Then the gate ITSELF invokes `"$(dirname "$0")/rules-gate-verdict.sh"
#           --root <root>` (sibling lookup, never PATH) and reads `.verdict` with an explicit
#           has() + `type == "string"` check. AFFIRMATIVE test: `ok` or `none` (nothing countable
#           to verify, D3) ⇒ holds; anything else PARKs with a named reason — `fail` ⇒
#           `rules_check_failed (<up to 3 countable ids, "; ">)`, `unresolved` ⇒
#           `rules_check_unresolved (<ids>)`, `unstamped` ⇒ `rules_unstamped (<text>)` where the
#           text follows the helper's optional `unstamped_reason` (message only — the park is keyed
#           on the verdict): `countable_set_drift` ⇒ `countable rule set changed since the last
#           /rules check --confirm on this machine`, `legacy_stamp` ⇒ `the stamp predates the
#           recorded countable rule set; re-run /rules check --confirm on this machine`, anything
#           else (never_confirmed / missing / unknown) ⇒ `<n> countable must-check(s) never
#           confirmed on this machine` (when the helper answers `unstamped`: skills/automate-loop/
#           SKILL.md §10 condition 7, D3's middle form), `cmd_disabled` ⇒
#           `rules_cmd_disabled`, and `unreadable` / helper absent / non-zero exit / non-JSON /
#           missing or non-string `.verdict` / any unrecognised verdict ⇒ `rules_gate_unreadable`.
#           No ctx input feeds it (`rules_gate`/`rules_ok`/`rules_check` are refused) and NO flag,
#           config key or project file overrides it.
#
# Every PARK reason from the pre-self-resolving gate is preserved verbatim:
# ctx_unreadable, drain_not_ready, sub_floor_not_merge_eligible, head_sha_moved,
# base_not_main, review_decision_blocking, review_decision_unreadable,
# unresolved_human_thread, unprotected_branch, checks_not_green,
# rubric_unsatisfied, high_risk_diff, merge_command_failed. New reasons added by
# self-resolution: ctx_carries_gate_owned_key, review_heal_result_unreadable,
# drain_result_mismatch, protection_unreadable, supervisor_result_unreadable.
# New reason added by ci-trust-probe-01: ci_untrusted_not_merge_eligible (an
# explicit, unconditional defense-in-depth PARK for termination_reason ==
# "ci_untrusted" — see cond 1b below; a well-formed ctx already PARKs via
# drain_not_ready since a real drain never pairs ci_untrusted with READY, but
# this guard also catches a hypothetically-corrupted ctx that claims READY
# anyway, exactly like the pre-existing sub_floor_converged guard it sits
# beside). New reasons added by condition 7 (rule-enforcement-at-review-and-merge):
# rules_check_failed, rules_check_unresolved, rules_unstamped, rules_cmd_disabled,
# rules_gate_unreadable. New reasons added by condition 7's checkout pin
# (automate-followups/16, evaluated before the helper call): rules_gate_head_mismatch,
# rules_gate_dirty_tree.
gate_eval() {
  local url="$1" ctx="$2"
  shift 2 2>/dev/null || true
  local root="."
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) root="${2:-.}"; shift 2 2>/dev/null || shift ;;
      *)      shift ;;
    esac
  done

  [ -f "$ctx" ] || die "ctx not found: $ctx"
  if ! "$JQ" -e . "$ctx" >/dev/null 2>&1; then
    echo "PARK: ctx_unreadable"; return 0
  fi

  # GATE-OWNED KEY REFUSAL — checked FIRST, before any other read. A ctx that
  # still tries to hand the gate a pre-computed verdict for a now-gate-owned
  # condition is refused outright, regardless of the value it carries.
  local _ge_k
  for _ge_k in high_risk risk_reasons head_sha base review_decision \
               unresolved_human_thread protection_enforceable checks_green rubric_satisfied \
               rules_gate rules_ok rules_check; do
    if "$JQ" -e --arg k "$_ge_k" 'has($k)' "$ctx" >/dev/null 2>&1; then
      echo "PARK: ctx_carries_gate_owned_key"; return 0
    fi
  done

  # NB: a bash function definition is always global — there is no `local` function
  # scoping — so J() lives until gate_eval returns and the next call redefines it;
  # no `local J` (which would only declare an unused local var of that name).
  J() { "$JQ" -r "$1 // \"__MISSING__\"" "$ctx"; }

  # Condition 1 — owned drain == READY.
  local drain_result; drain_result="$(J '.drain_result')"
  if [ "$drain_result" != "READY" ]; then
    echo "PARK: drain_not_ready"; return 0
  fi

  # Condition 1b — a `sub_floor_converged` READY is NOT auto-merge-eligible (AC9,
  # drain-bounding-earned-checks). Read WITHOUT the falsy-coercing `//` — an
  # explicit has()/!=null check so a legitimate string value is never coerced away.
  local tr
  tr="$("$JQ" -r 'if has("termination_reason") and (.termination_reason != null) then .termination_reason else "__MISSING__" end' "$ctx")"
  if [ "$tr" = "__MISSING__" ] || [ "$tr" = "sub_floor_converged" ]; then
    echo "PARK: sub_floor_not_merge_eligible"; return 0
  fi

  # Condition 1c (ci-trust-probe-01) — `ci_untrusted` is NEVER merge-eligible,
  # under ANY drain_result value. A well-formed ctx already PARKs above via
  # cond 1 (`drain_not_ready`) — a real drain never pairs `ci_untrusted` with
  # `READY` (an untrusted_infra required check still blocks READY,
  # review-heal/SKILL.md §"READY redefinition"). This explicit, unconditional
  # check is defense-in-depth against a hypothetically-corrupted ctx that
  # claims `drain_result: "READY"` anyway — exactly the same shape of guard
  # as cond 1b's `sub_floor_converged` check immediately above.
  if [ "$tr" = "ci_untrusted" ]; then
    echo "PARK: ci_untrusted_not_merge_eligible"; return 0
  fi

  # Condition 1 cross-check — the drain's OWN self-report (drain_result /
  # termination_reason above) must match the REVIEW_HEAL_RESULT artifact it
  # actually wrote, never be trusted as a bare assertion.
  local rhrp; rhrp="$(J '.review_heal_result_path')"
  if [ "$rhrp" = "__MISSING__" ] || [ ! -f "$rhrp" ]; then
    echo "PARK: review_heal_result_unreadable"; return 0
  fi
  local art_decision art_tr
  art_decision="$(_ge_result_field "$rhrp" "decision")"
  art_tr="$(_ge_result_field "$rhrp" "termination_reason")"
  if [ -z "$art_decision" ] || [ "$art_decision" != "$drain_result" ] \
     || [ -z "$art_tr" ] || [ "$art_tr" != "$tr" ]; then
    echo "PARK: drain_result_mismatch"; return 0
  fi

  # ---- `gh pr view` read #1 feeds conditions 2 (headRefOid/baseRefName) and
  # 5 (statusCheckRollup) — a combined multi-field read (mirrors review-heal/
  # SKILL.md §U1(a)'s own combined read). A total read failure fails EVERY
  # dependent field closed (empty/unreadable defaults below), never partially
  # trusted. `cmd || rc=$?` (not `x="$(cmd)"; rc=$?`) — under `set -e` a plain
  # (non-`local`) assignment whose RHS command substitution fails ABORTS THE
  # SCRIPT before the next statement ever runs (the exit-status-lost-across-
  # subshells trap, but in the OPPOSITE direction: here the failure is very
  # much seen, just fatally). Folding the failure into an `||` list keeps it a
  # normal, inspectable value.
  local pv pv_rc=0
  pv="$("$GH" pr view "$url" --json headRefOid,baseRefName,statusCheckRollup 2>/dev/null)" || pv_rc=$?
  local pv_ok=0
  printf '%s' "$pv" | "$JQ" -e . >/dev/null 2>&1 && [ "$pv_rc" -eq 0 ] && pv_ok=1
  local live_head="" live_base="" rollup_json="[]"
  if [ "$pv_ok" -eq 1 ]; then
    live_head="$(printf '%s' "$pv" | "$JQ" -r '.headRefOid // empty')"
    live_base="$(printf '%s' "$pv" | "$JQ" -r '.baseRefName // empty')"
    rollup_json="$(printf '%s' "$pv" | "$JQ" -c '.statusCheckRollup // []')"
  fi

  # ---- `gh pr view` read #2 feeds condition 3's reviewDecision — kept as its
  # OWN call (not folded into read #1) so a reviewDecision-specific read
  # failure PARKs on its own named reason (`review_decision_unreadable`)
  # rather than being masked by cond 2's `head_sha_moved`, which would fire
  # first on a combined-call failure and make this reason unreachable.
  local pv2 pv2_rc=0 rd="unreadable"
  pv2="$("$GH" pr view "$url" --json reviewDecision 2>/dev/null)" || pv2_rc=$?
  if [ "$pv2_rc" -eq 0 ] && printf '%s' "$pv2" | "$JQ" -e . >/dev/null 2>&1; then
    rd="$(printf '%s' "$pv2" | "$JQ" -r 'if has("reviewDecision") and (.reviewDecision != null) then .reviewDecision else "none" end')"
  fi

  # Condition 2 — live head SHA matches the drain's `ready_sha` claim, AND base == main.
  local ready_sha; ready_sha="$(J '.ready_sha')"
  if [ "$ready_sha" = "__MISSING__" ] || [ -z "$live_head" ] || [ "$ready_sha" != "$live_head" ]; then
    echo "PARK: head_sha_moved"; return 0
  fi
  if [ "$live_base" != "main" ]; then
    echo "PARK: base_not_main"; return 0
  fi

  # Condition 3 — reviewDecision not blocking AND no unresolved human/untrusted thread.
  case "$rd" in
    CHANGES_REQUESTED|REVIEW_REQUIRED)   echo "PARK: review_decision_blocking"; return 0 ;;
    APPROVED|none)                       : ;;   # acceptable -- defer protection judgment to cond 4
    *)                                    echo "PARK: review_decision_unreadable"; return 0 ;;
  esac

  # Review-threads GraphQL query — adapted from review-heal/SKILL.md §U1(b) (same
  # query minus the unused `body` field this gate never reads). `hasNextPage`
  # (truncated >100 threads) or any read error ⇒ fail CLOSED (treated as an
  # unresolved blocking thread).
  local parts owner repo number
  parts="$(_ge_pr_parts "$url")"
  IFS=$'\t' read -r owner repo number <<GEPARTS
$parts
GEPARTS
  local gql gql_rc=0
  gql="$("$GH" api graphql -f query='
  query($owner:String!,$repo:String!,$number:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$number){
        reviewThreads(first:100){
          pageInfo{ hasNextPage }
          nodes{ isResolved comments(first:1){ nodes{ author{ login __typename } } } }
        }
      }
    }
  }' -F owner="$owner" -F repo="$repo" -F number="$number" 2>/dev/null)" || gql_rc=$?

  local uht="true"
  if [ "$gql_rc" -eq 0 ] && printf '%s' "$gql" | "$JQ" -e '.data.repository.pullRequest.reviewThreads' >/dev/null 2>&1; then
    # Explicit == false check (NOT the falsy-coercing `//`, which would map a
    # genuine `false` to the "true" default and silently defeat the truncation
    # guard — the same trap `config_orig`/`unresolved_human_thread` avoid).
    local hasNext; hasNext="$(printf '%s' "$gql" | "$JQ" -r 'if .data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage == false then "false" else "true" end')"
    if [ "$hasNext" = "false" ]; then
      # Trusted-actor set (red-team-hardening item 01) — same fail-CLOSED resolution
      # as wrap-external-text.sh: absent/unreadable/malformed file ⇒ EMPTY set =>
      # every actor is "not in the trusted set" ⇒ blocking. No bot_author_re fallback here.
      local trusted_file trusted_json='[]'
      trusted_file="${HOME:-}/.claude/loomwright/trusted-actors.json"
      if [ -n "$trusted_file" ] && [ -r "$trusted_file" ]; then
        local _t; _t="$("$JQ" -c '.' "$trusted_file" 2>/dev/null || true)"
        if [ -n "$_t" ] && printf '%s' "$_t" | "$JQ" -e 'type=="array"' >/dev/null 2>&1; then
          trusted_json="$_t"
        fi
      fi
      local blocking
      blocking="$(printf '%s' "$gql" | "$JQ" -r --argjson trusted "$trusted_json" '
        [ .data.repository.pullRequest.reviewThreads.nodes[]?
          | select(.isResolved == false)
          | (.comments.nodes[0].author.login // "") as $login
          | select( ($trusted | index($login)) == null )
        ] | length > 0
      ' 2>/dev/null)"
      [ "$blocking" = "false" ] && uht="false"
    fi
  fi
  if [ "$uht" != "false" ]; then
    echo "PARK: unresolved_human_thread"; return 0
  fi

  # Condition 4 — enforceable branch protection OR --trust-unprotected. A 404
  # means genuinely unprotected (false); ANY OTHER error is unreadable ⇒ PARK
  # (never silently treated as either protected or unprotected).
  local prot_raw prot_rc=0 protection_enforceable="false" required_contexts_json="[]"
  prot_raw="$("$GH" api "repos/$owner/$repo/branches/main/protection" 2>&1)" || prot_rc=$?
  if [ "$prot_rc" -ne 0 ]; then
    case "$prot_raw" in
      *"404"*|*"Not Found"*) protection_enforceable="false" ;;
      *)                     echo "PARK: protection_unreadable"; return 0 ;;
    esac
  else
    if printf '%s' "$prot_raw" | "$JQ" -e . >/dev/null 2>&1; then
      protection_enforceable="$(printf '%s' "$prot_raw" | "$JQ" -r '
        ( ((.required_pull_request_reviews.required_approving_review_count // 0) >= 1)
          or (((.required_status_checks.contexts // []) | length) > 0)
          or (((.required_status_checks.checks // []) | length) > 0) )
      ' 2>/dev/null)"
      required_contexts_json="$(printf '%s' "$prot_raw" | "$JQ" -c '
        ( (.required_status_checks.contexts // []) + ((.required_status_checks.checks // []) | map(.context)) ) | unique
      ' 2>/dev/null)"
      [ -n "$required_contexts_json" ] || required_contexts_json="[]"
    else
      echo "PARK: protection_unreadable"; return 0
    fi
  fi
  local trust; trust="$(J '.trust_unprotected')"
  if [ "$protection_enforceable" != "true" ] && [ "$trust" != "true" ]; then
    echo "PARK: unprotected_branch"; return 0
  fi

  # Condition 5 — required checks green (discovery recipe: review-heal/SKILL.md §U2,
  # here sourced from the SAME branch-protection payload cond 4 already fetched)
  # AND rubric satisfied (na = not a blocker, now a FILE read — never caller-asserted).
  local checks_green
  checks_green="$(printf '%s' "$rollup_json" | "$JQ" -r --argjson req "$required_contexts_json" '
    . as $rollup
    | ( ($req | length) == 0 ) or
      ( all($req[]; . as $name
          | ( $rollup | map(select((.name // .context // "") == $name))
              | any( ( ((.conclusion // "") | ascii_downcase) as $c
                       | ((.state // "") | ascii_downcase) as $s
                       | ($c == "success" or $c == "neutral" or $s == "success") ) ) )
        ) )
  ' 2>/dev/null)"
  if [ "$checks_green" != "true" ]; then
    echo "PARK: checks_not_green"; return 0
  fi

  local srp; srp="$(J '.supervisor_result_path')"
  if [ "$srp" = "__MISSING__" ] || [ ! -f "$srp" ]; then
    echo "PARK: supervisor_result_unreadable"; return 0
  fi
  local rubric_line rub
  rubric_line="$(grep -m1 -E 'rubric_score:[[:space:]]*[0-9]+/[0-9]+' "$srp" 2>/dev/null || true)"
  if [ -z "$rubric_line" ]; then
    rub="na"
  else
    local rub_n rub_m
    rub_n="$(printf '%s' "$rubric_line" | sed -E 's/.*rubric_score:[[:space:]]*([0-9]+)\/([0-9]+).*/\1/')"
    rub_m="$(printf '%s' "$rubric_line" | sed -E 's/.*rubric_score:[[:space:]]*([0-9]+)\/([0-9]+).*/\2/')"
    if [ -n "$rub_n" ] && [ "$rub_n" = "$rub_m" ]; then rub="true"; else rub="false"; fi
  fi
  if [ "$rub" != "true" ] && [ "$rub" != "na" ]; then
    echo "PARK: rubric_unsatisfied"; return 0
  fi

  # Condition 6 — NOT a high-risk diff (owner decision R5: NO override, of ANY kind).
  # The gate ITSELF invokes classify-risk.sh on the live head SHA it just confirmed
  # in cond 2 — no ctx input feeds this condition any more. Read in EXACTLY the
  # cond-3 `unresolved_human_thread` shape: an explicit has() + `type == "boolean"`
  # check, PARK unless the value is the JSON boolean `false`.
  local risk_bin; risk_bin="$(dirname "$0")/classify-risk.sh"
  local risk_json=""
  if [ -r "$risk_bin" ]; then
    risk_json="$(bash "$risk_bin" main "$live_head" --root "$root" 2>/dev/null)"
  fi
  local hr rr
  if [ -n "$risk_json" ] && printf '%s' "$risk_json" | "$JQ" -e . >/dev/null 2>&1; then
    hr="$(printf '%s' "$risk_json" | "$JQ" -r 'if has("high_risk") and ((.high_risk|type) == "boolean") then (.high_risk|tostring) else "__MISSING__" end')"
    rr="$(printf '%s' "$risk_json" | "$JQ" -r 'if has("reasons") and ((.reasons|type) == "array") then (.reasons | map(tostring) | .[:3] | join("; ")) else "" end')"
  else
    hr="__MISSING__"; rr=""
  fi
  if [ "$hr" != "false" ]; then
    [ -z "$rr" ] && rr="no risk_reasons recorded"
    echo "PARK: high_risk_diff ($rr)"; return 0
  fi

  # Condition 7 — no stamped, gate-COUNTABLE `must`-rule check is failing
  # (rule-enforcement-at-review-and-merge, owner decisions D1–D4). Evaluated AFTER
  # cond 6 so every earlier PARK reason keeps its precedence. Same posture as
  # cond 6: the gate ITSELF invokes its sibling `rules-gate-verdict.sh` (never
  # PATH) on the checkout it was handed — no ctx input feeds this condition
  # (`rules_gate`/`rules_ok`/`rules_check` are refused above) and NO flag, config
  # key or project file overrides it. `.verdict` is read with an explicit
  # has() + `type == "string"` check; `rules_ok` is computed in the AFFIRMATIVE
  # form (`ok`, or `none` = nothing countable to verify, D3 — the cond-5 `na`
  # precedent) and the single test is `!= "true"` — never a `= "false"` test, so
  # any verdict this code does not recognise parks.
  #
  # PIN FIRST (automate-followups/16) — the verdict is only trusted for the bytes
  # being merged, so BEFORE the helper runs, the `--root` checkout must be AT the
  # live head SHA cond 2 confirmed and have no uncommitted change outside the two
  # engine-owned paths. Both checks fail CLOSED with NO override; neither runs the
  # helper on a checkout it is about to distrust. Every git call:
  #   - takes the `cmd || rc=$?` shape (see the helper-call comment below);
  #   - runs with the repo-redirect and pathspec-mode env vars UNSET — a stray
  #     GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE would make the pin judge a different
  #     repo than the files the helper reads at `$root`, and GIT_LITERAL_PATHSPECS
  #     would turn the `:(exclude)` magic into literal paths.
  # The porcelain read runs from the REPO TOP LEVEL with a plain `.` positive
  # pathspec, so a subdirectory `--root` still sees dirt anywhere in the tree,
  # the excludes stay anchored at the top (a nested `x/.supervisor/` is dirt),
  # and if magic were ever read literally the failure is over-strict (the excludes
  # stop excluding), never a fail-open match-nothing positive like `:(top)`.
  # `-uall` is explicit so a repo's `status.showUntrackedFiles=no` cannot hide
  # untracked files: untracked non-ignored files count as dirt (a bound check can
  # read them), gitignored ones do not.
  # LOCAL-ONLY GIT STATE MUST NOT HIDE DIRT (review iteration 1). `git status` trusts
  # state that lives only on this machine, so three more reads close it:
  #   - `ls-files -v`: a tracked file flagged assume-unchanged (lowercase tag) or
  #     skip-worktree (`S`/`s`) is never compared to the worktree by `git status`, so
  #     an edit to it is invisible — ANY such flag parks (a sparse checkout therefore
  #     parks too; `core.ignoreStat` sets the same flag).
  #   - ignored-ness is judged from per-directory `.gitignore` files plus the USER's
  #     global excludes file (`ls-files -o --exclude-per-directory=.gitignore
  #     --exclude-from=<global>`, no `--exclude-standard`), so `.git/info/exclude` and a
  #     repo-local or env-injected `core.excludesFile` cannot hide an untracked file. Tracked
  #     `.gitignore`s are already proven unmodified by the two reads above. The global file
  #     (review iteration 2) is the same user-scope trust anchor as the user running the
  #     gate, and how Claude Code itself ignores its `settings.local.json`; refusing it
  #     parked every clean checkout holding a globally-only-ignored file (.DS_Store, .idea/,
  #     settings.local.json). Honest limit: a globally-ignored file is TRUSTED not to be a
  #     bound file; the env that runs the gate (HOME / XDG_CONFIG_HOME) chooses that file,
  #     as it already chooses PATH and so `git` itself.
  #   - an UNTRACKED `.gitignore` git actually reads (one in a directory the rules do
  #     not already ignore) is itself non-committed ignore state — a self-ignoring one
  #     (`*`) hides its whole directory from both reads. `--directory` collapses a
  #     directory that is ignored as a whole (node_modules/, .venv/) without descending,
  #     so one nested in an ignored directory is never listed and never parks. Assumed
  #     git behaviour (honest limit): a directory NO rule ignores, whose contents are all
  #     ignored by its own `.gitignore`, is listed with its contents (`evil/` AND
  #     `evil/.gitignore`) rather than collapsed — true on git 2.54 / 2.55, asserted by the
  #     R11f harness precondition so a collapsing git turns CI red. Liveness
  #     cost (kept, by design): a tool cache that writes its own `*` .gitignore
  #     (.pytest_cache/, .mypy_cache/, .ruff_cache/, a Python 3.13 .venv/) parks unless that
  #     directory is ignored by a committed `.gitignore` or the user's global ignore — the
  #     fix is one such ignore line, since the park cannot tell a cache from a hiding file.
  # `_ge_git` also unsets the env config-injection family (GIT_CONFIG_PARAMETERS /
  # GIT_CONFIG_COUNT / GIT_CONFIG_GLOBAL / GIT_CONFIG_SYSTEM / GIT_CONFIG) so a caller's
  # environment cannot relax the reads (e.g. `core.fileMode=false`), and pins
  # `core.fsmonitor=false` / `core.untrackedCache=false` so a cached or hook-supplied
  # "nothing changed" answer is never trusted; `--no-optional-locks` keeps `git status`
  # from opportunistically rewriting the index, so the gate writes nothing and never
  # contends for `index.lock` with a concurrent git process (GIT_OPTIONAL_LOCKS=0 is inherited
  # by the per-submodule `git status` children too, so no submodule index is refreshed either).
  # Submodules: `_ge_subs_clean` below. Honest limit: settings in the repo's
  # OWN `.git/config` that change what git calls a modification (`core.fileMode=false`,
  # `core.autocrlf`, clean filters) are honoured as configured.
  # Every read here-strings its output into `grep -q` (never a pipe: under pipefail
  # an early grep exit could SIGPIPE the producer and read as "no match").
  _ge_git() {
    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_COMMON_DIR \
        -u GIT_LITERAL_PATHSPECS -u GIT_GLOB_PATHSPECS -u GIT_NOGLOB_PATHSPECS -u GIT_ICASE_PATHSPECS \
        -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_CONFIG_GLOBAL -u GIT_CONFIG_SYSTEM -u GIT_CONFIG \
        git --no-optional-locks -c core.fsmonitor=false -c core.untrackedCache=false "$@" </dev/null
  }
  # _ge_phys <abs-path> — the PHYSICAL path git would open (owner fix-now B3): a symlinked
  # final component is followed (bounded, like the kernel's ELOOP) and the directory part is
  # resolved with `cd -P`/`pwd -P`, so `/tmp` vs `/private/tmp` style aliases and a symlink
  # that points back into the checkout cannot pass for "outside". Plain `readlink` (no `-f`)
  # and `cd -P` only — BSD and GNU alike. Non-absolute or unresolvable ⇒ fails (refused).
  _ge_phys() {
    local p="$1" n=0 t d b
    case "$p" in /*) ;; *) return 1 ;; esac
    while [ -L "$p" ]; do
      n=$((n + 1)); [ "$n" -le 40 ] || return 1
      t="$(readlink "$p" 2>/dev/null)" || return 1
      [ -n "$t" ] || return 1
      case "$t" in /*) p="$t" ;; *) p="$(dirname "$p")/$t" ;; esac
    done
    d="$(dirname "$p")"; b="$(basename "$p")"
    case "$b" in ""|.|..|/) return 1 ;; esac
    d="$(CDPATH='' cd -P -- "$d" 2>/dev/null && pwd -P)" || return 1
    case "$d" in /*) ;; *) return 1 ;; esac
    if [ "$d" = "/" ]; then printf '/%s' "$b"; else printf '%s/%s' "$d" "$b"; fi
  }
  # _ge_inside <physical-path> <top> — 0 iff the path's directory IS <top> or lies beneath
  # it. Ancestors are compared with `-ef` (device + inode), so a case-variant, firmlink or
  # bind-mount spelling of the checkout is still the checkout.
  _ge_inside() {
    local d n=0; d="$(dirname "$1")"
    while :; do
      [ "$d" -ef "$2" ] && return 0
      case "$d" in /|"") return 1 ;; esac
      d="$(dirname "$d")"; n=$((n + 1)); [ "$n" -le 256 ] || return 0
    done
  }
  # _ge_subs_clean <dir> <depth> <pathspec...> — SUBMODULES (owner fix-now B1). The top-level
  # status runs with `--ignore-submodules=none` (overriding a committed `.gitmodules`
  # `submodule.<n>.ignore` and `diff.ignoreSubmodules`), so a submodule with modified or
  # untracked content, or checked out at a commit other than the one recorded, is dirt. A
  # submodule's OWN local-only state (its `info/exclude`, assume-unchanged / skip-worktree
  # flags, a self-ignoring untracked `.gitignore`) would still hide dirt from that status, so
  # every checked-out submodule gets the same four reads as the top level, recursively
  # (depth-capped). Returns 0 iff all are clean; any failed read, a submodule path git had to
  # quote, a `.git` that does not resolve to that directory, or the depth cap ⇒ non-zero. A
  # gitlink with no `.git` at all is an un-initialised submodule (its files are absent, not
  # altered) and is not descended into.
  _ge_subs_clean() {
    local d="$1" depth="$2"; shift 2
    [ "$depth" -lt 8 ] || return 1
    local st="" st_rc=0 ent sp sd sd_p sd_top="" sd_rc=0 out="" out_rc=0 ge_tab=$'\t' subs; subs=()
    st="$(_ge_git -C "$d" -c core.quotePath=false ls-files -s -- "$@" 2>/dev/null)" || st_rc=$?
    [ "$st_rc" -eq 0 ] || return 1
    while IFS= read -r ent; do
      case "$ent" in 160000\ *) ;; *) continue ;; esac
      sp="${ent#*"$ge_tab"}"
      case "$sp" in \"*|"$ent") return 1 ;; esac
      subs[${#subs[@]}]="$sp"
    done <<<"$st"
    [ "${#subs[@]}" -gt 0 ] || return 0
    for sp in "${subs[@]}"; do
      sd="$d/$sp"
      { [ -e "$sd/.git" ] || [ -L "$sd/.git" ]; } || continue
      sd_p="$(CDPATH='' cd -P -- "$sd" 2>/dev/null && pwd -P)" || return 1
      sd_rc=0; sd_top="$(_ge_git -C "$sd_p" rev-parse --show-toplevel 2>/dev/null)" || sd_rc=$?
      { [ "$sd_rc" -eq 0 ] && [ -n "$sd_top" ] && [ "$sd_top" -ef "$sd_p" ]; } || return 1
      out_rc=0; out="$(_ge_git -C "$sd_p" status --porcelain -uall --ignore-submodules=none -- . 2>/dev/null)" || out_rc=$?
      { [ "$out_rc" -eq 0 ] && [ -z "$out" ]; } || return 1
      out_rc=0; out="$(_ge_git -C "$sd_p" ls-files -v -- . 2>/dev/null)" || out_rc=$?
      [ "$out_rc" -eq 0 ] || return 1
      if grep -q '^[a-zS] ' <<<"$out"; then return 1; fi
      out_rc=0; out="$(_ge_git -C "$sd_p" ls-files -o ${ge_xargs[@]+"${ge_xargs[@]}"} --exclude-per-directory=.gitignore -- . 2>/dev/null)" || out_rc=$?
      { [ "$out_rc" -eq 0 ] && [ -z "$out" ]; } || return 1
      out_rc=0; out="$(_ge_git -C "$sd_p" ls-files -o -i --directory ${ge_xargs[@]+"${ge_xargs[@]}"} --exclude-per-directory=.gitignore -- . 2>/dev/null)" || out_rc=$?
      [ "$out_rc" -eq 0 ] || return 1
      if grep -qE '(^|/)\.gitignore"?$' <<<"$out"; then return 1; fi
      _ge_subs_clean "$sd_p" $((depth + 1)) . || return 1
    done
    return 0
  }
  local root_head="" root_head_rc=0
  root_head="$(_ge_git -C "$root" rev-parse --verify -q HEAD 2>/dev/null)" || root_head_rc=$?
  if [ "$root_head_rc" -ne 0 ] || [ -z "$root_head" ] || [ "$root_head" != "$live_head" ]; then
    echo "PARK: rules_gate_head_mismatch"; return 0
  fi
  local root_top="" root_top_rc=0 root_dirt="" root_dirt_rc=0
  local root_flags="" root_flags_rc=0 root_unt="" root_unt_rc=0 root_ign="" root_ign_rc=0 root_subs_rc=0
  local ge_ps; ge_ps=(. ':(exclude).supervisor' ':(exclude).claude/agent-memory')  # one pathspec set, all four reads
  local ge_xf="" ge_xf_p="" ge_xf_rc=0 ge_xargs; ge_xargs=()
  root_top="$(_ge_git -C "$root" rev-parse --show-toplevel 2>/dev/null)" || root_top_rc=$?
  if [ "$root_top_rc" -eq 0 ] && [ -n "$root_top" ]; then
    root_top="$(CDPATH='' cd -P -- "$root_top" 2>/dev/null && pwd -P)" || root_top=""
  fi
  if [ "$root_top_rc" -eq 0 ] && [ -n "$root_top" ]; then
    # USER-SCOPE global excludes (review iteration 2): resolved exactly as git does for the
    # user — `core.excludesFile` from the user's own global config (`--global --includes`,
    # so an `[include]` / `[includeIf]` in it is followed as git itself follows it; `--path`
    # expands `~/`; the GIT_CONFIG_* injection family is still unset by `_ge_git`), else the
    # default `$XDG_CONFIG_HOME/git/ignore` / `$HOME/.config/git/ignore` — and fed to the
    # untracked reads as `--exclude-from`. Only an absolute path to a readable regular file
    # whose PHYSICAL location (`_ge_phys`: symlinks and directory aliases resolved) is
    # OUTSIDE this checkout (`_ge_inside`: device + inode ancestor walk) is honoured, and git
    # is handed that resolved path; a relative, unresolvable or in-repo path would make repo
    # bytes an ignore source and is refused. `.git/info/exclude`, a repo-local
    # `core.excludesFile` and the system config are still never read. rc 1 = key unset; any
    # other failure parks.
    ge_xf="$(_ge_git -C "$root_top" config --global --includes --path --get core.excludesFile 2>/dev/null)" || ge_xf_rc=$?
    if [ "$ge_xf_rc" -eq 1 ]; then
      ge_xf_rc=0
      if [ -n "${XDG_CONFIG_HOME:-}" ]; then ge_xf="$XDG_CONFIG_HOME/git/ignore"
      elif [ -n "${HOME:-}" ]; then ge_xf="$HOME/.config/git/ignore"
      else ge_xf=""; fi
    fi
    if [ -n "$ge_xf" ]; then
      ge_xf_p="$(_ge_phys "$ge_xf")" || ge_xf_p=""
      if [ -z "$ge_xf_p" ] || _ge_inside "$ge_xf_p" "$root_top"; then ge_xf=""; else ge_xf="$ge_xf_p"; fi
    fi
    if [ -n "$ge_xf" ] && [ -f "$ge_xf" ] && [ -r "$ge_xf" ]; then ge_xargs=("--exclude-from=$ge_xf"); fi
    root_dirt="$(_ge_git -C "$root_top" status --porcelain -uall --ignore-submodules=none -- "${ge_ps[@]}" 2>/dev/null)" || root_dirt_rc=$?
    root_flags="$(_ge_git -C "$root_top" ls-files -v -- "${ge_ps[@]}" 2>/dev/null)" || root_flags_rc=$?
    root_unt="$(_ge_git -C "$root_top" ls-files -o ${ge_xargs[@]+"${ge_xargs[@]}"} --exclude-per-directory=.gitignore -- "${ge_ps[@]}" 2>/dev/null)" || root_unt_rc=$?
    root_ign="$(_ge_git -C "$root_top" ls-files -o -i --directory ${ge_xargs[@]+"${ge_xargs[@]}"} --exclude-per-directory=.gitignore -- "${ge_ps[@]}" 2>/dev/null)" || root_ign_rc=$?
    _ge_subs_clean "$root_top" 0 "${ge_ps[@]}" || root_subs_rc=$?
    [ "$ge_xf_rc" -eq 0 ] || root_unt_rc="$ge_xf_rc"
  else
    root_dirt_rc=1
  fi
  if [ "$root_dirt_rc" -ne 0 ] || [ -n "$root_dirt" ]; then
    echo "PARK: rules_gate_dirty_tree"; return 0
  fi
  if [ "$root_flags_rc" -ne 0 ] || grep -q '^[a-zS] ' <<<"$root_flags"; then
    echo "PARK: rules_gate_dirty_tree"; return 0
  fi
  if [ "$root_unt_rc" -ne 0 ] || [ -n "$root_unt" ]; then
    echo "PARK: rules_gate_dirty_tree"; return 0
  fi
  if [ "$root_ign_rc" -ne 0 ] || grep -qE '(^|/)\.gitignore"?$' <<<"$root_ign"; then
    echo "PARK: rules_gate_dirty_tree"; return 0
  fi
  if [ "$root_subs_rc" -ne 0 ]; then
    echo "PARK: rules_gate_dirty_tree"; return 0
  fi

  local rules_bin; rules_bin="$(dirname "$0")/rules-gate-verdict.sh"
  # `cmd || rc=$?` (the cond-2 read's shape): under `set -e` a failing command
  # substitution in a plain assignment would abort the gate with NO line printed.
  # The helper's contract is "always exit 0", so a non-zero exit is unreadable.
  local rules_json="" rules_rc=0
  if [ -r "$rules_bin" ]; then
    rules_json="$(bash "$rules_bin" --root "$root" </dev/null 2>/dev/null)" || rules_rc=$?
  fi
  local rv="__MISSING__"
  if [ "$rules_rc" -eq 0 ] && [ -n "$rules_json" ] && printf '%s' "$rules_json" | "$JQ" -e 'type == "object"' >/dev/null 2>&1; then
    rv="$(printf '%s' "$rules_json" | "$JQ" -r 'if has("verdict") and ((.verdict|type) == "string") then .verdict else "__MISSING__" end' 2>/dev/null)" || rv="__MISSING__"
    [ -n "$rv" ] || rv="__MISSING__"
  fi
  local rules_ok="false"
  case "$rv" in
    ok|none) rules_ok="true" ;;
  esac
  if [ "$rules_ok" != "true" ]; then
    # _ge_rules_ids <field> — up to 3 ids of <field> that are also COUNTABLE (an
    # advisory id never names a gate blocker), joined by "; ", one line, as data.
    _ge_rules_ids() {
      printf '%s' "$rules_json" | "$JQ" -r --arg f "$1" '
        ([ (.countable // [])[]? | select(type == "string") ]) as $c
        | [ (.[$f] // [])[]? | select(type == "string") | . as $i | select(any($c[]; . == $i)) ]
        | .[:3] | map(gsub("[[:cntrl:]]"; "")) | join("; ")' 2>/dev/null
    }
    local rids
    case "$rv" in
      fail)
        rids="$(_ge_rules_ids failing)" || rids=""; [ -n "$rids" ] || rids="no failing ids recorded"
        echo "PARK: rules_check_failed ($rids)"; return 0 ;;
      unresolved)
        rids="$(_ge_rules_ids unresolved)" || rids=""; [ -n "$rids" ] || rids="no unresolved ids recorded"
        echo "PARK: rules_check_unresolved ($rids)"; return 0 ;;
      unstamped)
        # D3 middle form: the helper answers `unstamped` ONLY when countable != [] or
        # the countable set drifted from the stamp's recorded one (an unstamped store
        # with zero countable ids and no drift is already `none` above).
        local rn; rn="$(printf '%s' "$rules_json" | "$JQ" -r '[ (.countable // [])[]? | select(type == "string") ] | length' 2>/dev/null)" || rn=""
        case "$rn" in ''|*[!0-9]*) rn="?" ;; esac
        # WHY it is unstamped (the helper's optional `unstamped_reason`) only picks the
        # message text — the PARK itself is keyed on the verdict, so a missing or unknown
        # reason still parks, with the never-confirmed text. The drift/legacy texts carry no
        # live count: drift can empty the live countable set (a stamped failing rule
        # demoted away), and "0 … never confirmed" would read as nothing to confirm.
        local ur; ur="$(printf '%s' "$rules_json" | "$JQ" -r 'if (.unstamped_reason|type) == "string" then .unstamped_reason else "" end' 2>/dev/null)" || ur=""
        case "$ur" in
          countable_set_drift)
            echo "PARK: rules_unstamped (countable rule set changed since the last /rules check --confirm on this machine)"; return 0 ;;
          legacy_stamp)
            echo "PARK: rules_unstamped (the stamp predates the recorded countable rule set; re-run /rules check --confirm on this machine)"; return 0 ;;
        esac
        echo "PARK: rules_unstamped (${rn} countable must-check(s) never confirmed on this machine)"; return 0 ;;
      cmd_disabled)
        echo "PARK: rules_cmd_disabled"; return 0 ;;
      *)
        # unreadable, helper absent, non-JSON output, missing/non-string verdict,
        # or any verdict string this gate does not recognise.
        echo "PARK: rules_gate_unreadable"; return 0 ;;
    esac
  fi

  # ALL conditions hold — the ONLY sanctioned `gh pr merge --squash` in the plugin (§11).
  if "$GH" pr merge --squash "$url" >/dev/null 2>&1; then
    echo "MERGE"; return 0
  fi
  echo "PARK: merge_command_failed"; return 0
}

# --------------------------------------------------------------------------- #
# §6 step 3 — engine-native ground-truth learning line (fail-SAFE, jq-only,
#             idempotent). Emits ONE full valid schema_version:1 POSTMORTEM_RESULT
#             per processed PR (merged OR parked) from data the engine already
#             holds (REVIEW_HEAL_RESULT fix_cycles/repeat_check_failure/
#             unresolved_bot_feedback/drain_result + SUPERVISOR_RESULT
#             repo/number/pr_url/branch) plus a single `gh pr view` for
#             changed_paths + integer size fields. NO /pr-postmortem gather, so no
#             GitHub-blind false-0. Additive `source:"automate_drain"` +
#             `automate_key` discriminate it from a github_postmortem line.
# --------------------------------------------------------------------------- #

# learning-emit <ledger_path> --repo <r> --number <n> --pr-url <url> --run-id <id>
#   --item <item> --fix-cycles <n> --drain-result <READY|ESCALATED>
#   --repeat-check-failure <true|false> --unresolved-bot-feedback <true|false>
#   --changed-paths-json <json-array> --additions <n> --deletions <n>
#   --changed-files <n> --summary <text> [--plugin-version <v>] [--ts <iso>]
#   [--branch <b>] [--source <s>] [--self-heal-rounds <n>]
#
# --self-heal-rounds <n> — the Phase 4.5 self-heal churn that happened BEFORE the
# PR reached the drain. <n> is the OBSERVED count, `SUPERVISOR_RESULT.heal_iterations`,
# never the configured `/supervisor --heal-iterations` MAXIMUM bound (default 3) —
# which is exactly why the flag is not named `--heal-iterations`: passing the bound
# would record fake churn. Contract (decisions 1–8 of the
# 2026-09-26-learning-emit-self-heal-rounds brief; authority for the field mapping
# is docs/RESULT_SCHEMAS.md POSTMORTEM_RESULT §"`source: \"automate_drain\"` variant"):
#   1. `review_rounds` keeps its DRAIN-ONLY meaning (effective_review_rounds, below).
#      build-loop-evidence.sh / measure-heal-signal.py join on it floor-raising, so
#      folding self-heal into it would silently change historical comparisons.
#   2. Additive integer `self_heal_rounds`, emitted ONLY when the flag was passed
#      (any value). Omit the flag ⇒ the line is byte-identical to the pre-flag one.
#      Normalization: a non-negative integer passes through; anything else
#      (non-numeric, negative, fractional, empty) ⇒ 0 — never a non-zero exit.
#      Surrounding whitespace is trimmed FIRST (`" 2"`/`"2\n"` from a grep/awk
#      extraction ⇒ 2), so a padded value is never silently recorded as 0.
#   3. `self_heal_rounds > 0` adds ONE `categories[]` entry
#      {round: n, class: "self_heal_churn", self_heal_miss: false,
#       flow_stage: "self_heal", evidence: "Phase 4.5 self-heal, heal_iterations=<n>"},
#      placed BEFORE any drain entry (self-heal precedes the drain). A healed finding
#      is a catch, not a miss ⇒ self_heal_miss:false. read-postmortem.sh counts each
#      element as one round and groups by .class, so it needs no change.
#   4. Zero-rule restated: `categories: []` iff effective_review_rounds == 0 AND
#      self_heal_rounds == 0 (absent counts as 0) — at most ONE drain entry plus at
#      most ONE self_heal_churn entry. Still no fake churn: self-heal churn is real.
#   5. Default summary unchanged when self_heal_rounds is absent/0; when > 0 it
#      appends "; self-heal: <n> round(s)". A caller --summary is emitted verbatim.
#   6. The idempotency key (run_id|item|pr_url|source|completeness) is UNCHANGED —
#      self_heal_rounds is not part of it.
#   7. (flag name — see the first paragraph above.)
#   8. `flow_stages.self_heal` keeps counting DRAIN rounds only; self-heal churn
#      appears only in `self_heal_rounds` and `categories[]` (this widens the known
#      counter-vs-categories disagreement build-floor.sh reports as
#      flow_stage_counter_disagreements, confined to automate_drain lines).
#
# FAIL-SAFE: this is one of the two subcommands (with brief-repair) that must
# NEVER die/abort — it runs inside the per-item loop as an advisory side-effect
# and a failure must NEVER gate the engine. We `set +e` at the top (this lib is `set -euo pipefail`) so any failing
# command (jq absent, unwritable ledger, bad JSON, missing arg) degrades to a
# no-op / degraded line and returns 0 — same posture as dispatch-pr-postmortem.sh /
# send-webhook.sh.
learning_emit() {
  set +e   # FAIL-SAFE: always exit 0; never die/abort inside the per-item loop.

  local ledger="${1:-}"; shift || true
  [ -n "$ledger" ] || return 0

  # Defaults.
  local repo="" number="0" pr_url="" run_id="" item=""
  local fix_cycles="0" drain_result="" repeat_check_failure="false" unresolved_bot_feedback="false"
  local changed_paths_json="[]" additions="0" deletions="0" changed_files="0"
  local summary="" plugin_version="" ts="" branch="" source="automate_drain"
  local shr_given="0" shr_raw=""

  # Parse named flags defensively — an unknown/short flag is ignored, never fatal.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)                    repo="${2:-}"; shift 2 || shift ;;
      --number)                  number="${2:-0}"; shift 2 || shift ;;
      --pr-url)                  pr_url="${2:-}"; shift 2 || shift ;;
      --run-id)                  run_id="${2:-}"; shift 2 || shift ;;
      --item)                    item="${2:-}"; shift 2 || shift ;;
      --fix-cycles)              fix_cycles="${2:-0}"; shift 2 || shift ;;
      --drain-result)            drain_result="${2:-}"; shift 2 || shift ;;
      --repeat-check-failure)    repeat_check_failure="${2:-false}"; shift 2 || shift ;;
      --unresolved-bot-feedback) unresolved_bot_feedback="${2:-false}"; shift 2 || shift ;;
      --changed-paths-json)      changed_paths_json="${2:-[]}"; shift 2 || shift ;;
      --additions)               additions="${2:-0}"; shift 2 || shift ;;
      --deletions)               deletions="${2:-0}"; shift 2 || shift ;;
      --changed-files)           changed_files="${2:-0}"; shift 2 || shift ;;
      --summary)                 summary="${2:-}"; shift 2 || shift ;;
      --plugin-version)          plugin_version="${2:-}"; shift 2 || shift ;;
      --ts)                      ts="${2:-}"; shift 2 || shift ;;
      --branch)                  branch="${2:-}"; shift 2 || shift ;;
      --source)                  source="${2:-automate_drain}"; shift 2 || shift ;;
      --self-heal-rounds)        shr_given="1"; shr_raw="${2:-}"; shift 2 || shift ;;
      *)                         shift ;;   # unknown flag: ignore, never fatal
    esac
  done

  # jq-absent guard: degrade to no-op (NO write) if jq isn't runnable.
  command -v "$JQ" >/dev/null 2>&1 || return 0

  [ -n "$source" ] || source="automate_drain"
  [ -n "$ts" ] || ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  [ -n "$changed_paths_json" ] || changed_paths_json="[]"

  # Normalize changed_paths ONCE (the same shape the record below embeds) so the
  # completeness discriminator and the emitted field can never disagree.
  local cp_clean
  cp_clean="$( printf '%s' "$changed_paths_json" \
    | "$JQ" -c 'if type=="array" then map(select(type=="string")) else [] end' 2>/dev/null )"
  [ -n "$cp_clean" ] || cp_clean="[]"

  # self_heal_rounds (decision 2): JSON `null` ⇒ the flag was NOT passed ⇒ the field
  # is omitted and the line stays byte-identical to the pre-flag shape. When passed,
  # ONLY a string of ASCII digits survives; everything else (empty, `-1`, `1.5`,
  # `abc`) normalizes to 0. An explicit digit check, NOT a bare `tonumber? // 0`
  # (which would accept `-1` and `1.5`). Surrounding whitespace is trimmed first —
  # prefix/suffix parameter expansion only (bash 3.2-safe; never the O(n²)
  # `${var//[[:space:]]/}` global substitution), and INTERNAL whitespace (`"1 2"`)
  # still normalizes to 0.
  local shr_json="null"
  if [ "$shr_given" = "1" ]; then
    shr_raw="${shr_raw#"${shr_raw%%[![:space:]]*}"}"
    shr_raw="${shr_raw%"${shr_raw##*[![:space:]]}"}"
    case "$shr_raw" in
      ''|*[!0-9]*) shr_json="0" ;;
      *) shr_json="$( printf '%s' "$shr_raw" | "$JQ" -R 'tonumber? // 0' 2>/dev/null )"
         [ -n "$shr_json" ] || shr_json="0" ;;
    esac
  fi

  # DEGRADED-EMIT DESIGN — option (b): the idempotency key is degradation-aware.
  #
  # A line with `changed_paths: []` is PERMANENTLY INVISIBLE to read-postmortem.sh
  # (its overlap filter can never match an empty array). Before this, a FIRST emit
  # that degraded — the single `gh pr view --json files,...` fetch failed, or the
  # caller omitted the fetch args — poisoned the key and silently skipped every
  # later emit that DID carry the data. Silent invisibility is the exact failure
  # this feature exists to prevent.
  #
  # Fix: the key carries a `complete`|`degraded` discriminator, so a degraded line
  # does not block a later complete one. Exactly-once still holds per (key, state),
  # and at most ONE complete line is ever written per run/item/pr/source.
  #
  # Why not the alternatives:
  #   (a) supersede the degraded line via curate-postmortem.sh — unusable here. Its
  #       `target_key` matches a data line's `automate_key` OR `pr_url`, so a record
  #       aimed at the degraded line would ALSO hide the corrective line (same
  #       pr_url); and it is human-gated on --confirm, so it can never run inside
  #       the per-item loop. It stays the manual, human-driven curation path.
  #   (c) refuse to emit a degraded line at all — throws away the honest
  #       `review_rounds` / `self_heal_misses` churn signal on every fetch failure
  #       and breaks the documented always-emit fail-safe contract.
  #
  # The degraded line is left in place. It stays invisible to read-postmortem.sh
  # (empty changed_paths), but do NOT assume it is quarantined downstream: `repo` and
  # `number` are derived from pr_url INDEPENDENTLY of the fetch that degrades
  # (skills/automate-loop/SKILL.md §6), so a contract-compliant caller emits the
  # degraded line with the REAL number — `number: 0` only happens when --number is
  # omitted altogether. The degraded and corrective lines therefore SHARE the
  # repo#number key that build-loop-evidence.sh and measure-heal-signal.py join on.
  # Both pick floor-raising (max review_rounds, tie-break latest ts), so the richer
  # line wins and the pair cannot report a stale low count. Ledger stays append-only;
  # no new writer.
  # COMPLETE requires at least one NON-EMPTY path. An empty string is not a usable
  # path — read-postmortem.sh drops empty query paths before matching, so a
  # `changed_paths: [""]` line is just as invisible as `[]`. Classing it complete
  # would re-open this very defect: an unusable line blocking its own correction.
  local completeness="degraded"
  if printf '%s' "$cp_clean" | "$JQ" -e 'any(.[]; . != "")' >/dev/null 2>&1; then
    completeness="complete"
  fi

  # Deterministic idempotency key: run_id|item|pr_url|source|completeness joined on
  # the ASCII Unit Separator (U+001F, written as the \u001f jq escape — NOT an empty
  # join; a raw 0x1F byte renders invisibly in diffs/cat and reads as join("")). The
  # separator closes the boundary-ambiguity collision class (e.g. run_id="a",
  # item="bc" vs "ab","c" would collide under an empty join). Built jq-only so a
  # field containing spaces/quotes can't break the scan; U+001F never appears in a
  # repo slug / URL / run-id, so the join is exact.
  local base key
  base="$("$JQ" -rn --arg a "$run_id" --arg b "$item" --arg c "$pr_url" --arg d "$source" \
    '[$a,$b,$c,$d] | join("\u001f")' 2>/dev/null)"
  [ -n "$base" ] || return 0
  key="$("$JQ" -rn --arg b "$base" --arg s "$completeness" '[$b,$s] | join("\u001f")' 2>/dev/null)"
  [ -n "$key" ] || return 0

  # Idempotency skip. A "match" is an existing line whose automate_key is this base
  # (a LEGACY pre-discriminator line) or this base plus a discriminator suffix. Skip when:
  #   - an exact-key line already exists (plain re-entry). NOT redundant with the two
  #     arms below: they judge completeness from the line's OWN changed_paths, so a line
  #     whose key suffix and payload disagree (hand-edited, or a truncated write) would
  #     otherwise slip past and be appended twice. This arm keys on identity alone, OR
  #   - this emit is DEGRADED and any match exists  (never regress an existing good
  #     line, and never write a second invisible line), OR
  #   - this emit is COMPLETE and a complete match exists      (at most one good line;
  #     this arm also keeps a LEGACY complete line idempotent under the new key shape).
  # The one newly-permitted append is COMPLETE-after-DEGRADED — the correction.
  if [ -f "$ledger" ]; then
    if "$JQ" -R 'fromjson? // empty' "$ledger" 2>/dev/null \
         | "$JQ" -e -s --arg k "$key" --arg base "$base" --arg state "$completeness" '
             [ .[]
               | select(type == "object")
               | ((.automate_key // "") | if type == "string" then . else "" end) as $ak
               | select($ak == $base or ($ak | startswith($base + "\u001f")))
               # `complete` MUST use the same rule as the discriminator above (at least
               # one NON-EMPTY path), not merely `length > 0`. A `[""]` line is degraded
               # by the discriminator, so if this arm judged it complete it would block
               # the very correction the discriminator just permitted.
               | { ak: $ak,
                   complete: ((((.changed_paths // []) | type) == "array")
                              and ((.changed_paths // []) | any(.[]?; . != ""))) }
             ] as $m
             | ($m | any(.ak == $k))
               or (($state == "degraded") and (($m | length) > 0))
               or (($state == "complete") and ($m | any(.complete)))
           ' >/dev/null 2>&1; then
      return 0   # already recorded for this run/item/pr/source/state — exactly-once.
    fi
  fi

  # Build the record jq-only (--arg / --argjson ONLY — no string interpolation of
  # any PR-supplied text; injection-safe, same contract as pr-postmortem-gather.sh).
  # All churn logic (effective_review_rounds, the categories[] zero-rule,
  # self_heal_misses, flow_stages) is computed INSIDE jq so it is a single source
  # of truth and the zero-rule holds exactly.
  local line
  line="$("$JQ" -cn \
    --arg ts "$ts" \
    --arg repo "$repo" \
    --argjson number "$( printf '%s' "$number"      | "$JQ" -R 'tonumber? // 0' )" \
    --argjson fix_cycles "$( printf '%s' "$fix_cycles" | "$JQ" -R 'tonumber? // 0' )" \
    --arg drain_result "$drain_result" \
    --arg repeat_check_failure "$repeat_check_failure" \
    --arg unresolved_bot_feedback "$unresolved_bot_feedback" \
    --argjson additions "$( printf '%s' "$additions"      | "$JQ" -R 'tonumber? // 0' )" \
    --argjson deletions "$( printf '%s' "$deletions"      | "$JQ" -R 'tonumber? // 0' )" \
    --argjson changed_files "$( printf '%s' "$changed_files" | "$JQ" -R 'tonumber? // 0' )" \
    --arg summary "$summary" \
    --arg plugin_version "$plugin_version" \
    --arg pr_url "$pr_url" \
    --arg branch "$branch" \
    --arg source "$source" \
    --arg automate_key "$key" \
    --argjson cp_raw "$cp_clean" \
    --argjson shr "$shr_json" \
    '
    # changed_paths: keep only an array of strings, else [].
    ( if ($cp_raw | type) == "array" then ($cp_raw | map(select(type=="string"))) else [] end ) as $changed_paths
    # self_heal_misses ← 1 if repeat_check_failure OR unresolved_bot_feedback.
    | ( if ($repeat_check_failure == "true") or ($unresolved_bot_feedback == "true") then 1 else 0 end ) as $shm
    # effective_review_rounds — mirror the categories[] branch order exactly so the
    # two never disagree (and an unreachable negative fix_cycles clamps to 0/1, never
    # a negative review_rounds): fix_cycles>0 -> fix_cycles; else ESCALATED -> 1; else 0.
    | ( if $fix_cycles > 0 then $fix_cycles elif $drain_result == "ESCALATED" then 1 else 0 end ) as $err
    # categories[] zero-rule (read-postmortem counts each element as one round):
    #   fix_cycles>0           -> one drain_churn entry {round: fix_cycles}
    #   fix_cycles==0 ESCALATED -> one drain_escalation entry {round: 1}
    #   fix_cycles==0 non-esc  -> no drain entry (NEVER a synthetic one — no fake churn)
    # plus, BEFORE any drain entry, one self_heal_churn entry iff self_heal_rounds > 0.
    # So `categories: []` iff effective_review_rounds == 0 AND self_heal_rounds == 0
    # ($shr null = flag absent = 0).
    | ( if $shr == null then 0 else $shr end ) as $shrn
    | ( if $shrn > 0 then
          [ { round: $shrn, class: "self_heal_churn", self_heal_miss: false,
              flow_stage: "self_heal",
              evidence: ("Phase 4.5 self-heal, heal_iterations=" + ($shrn|tostring)) } ]
        else
          []
        end ) as $self_heal_categories
    | ( if $fix_cycles > 0 then
          [ { round: $fix_cycles, class: "drain_churn", self_heal_miss: ($shm > 0),
              flow_stage: "self_heal",
              evidence: ("until-mergeable drain, decision=" + (if $drain_result=="" then "READY" else $drain_result end) + ", fix_cycles=" + ($fix_cycles|tostring)) } ]
        elif $drain_result == "ESCALATED" then
          [ { round: 1, class: "drain_escalation", self_heal_miss: ($shm > 0),
              flow_stage: "self_heal",
              evidence: "until-mergeable drain escalated before any fix cycle" } ]
        else
          []
        end ) as $drain_categories
    | ($self_heal_categories + $drain_categories) as $categories
    # self_heal_rounds sits right after review_rounds, and ONLY when the flag was
    # passed — built by object concatenation so the flag-absent line keeps the exact
    # pre-flag key order (byte-identical, decision 2).
    | {
        schema_version: 1,
        ts: $ts,
        repo: $repo,
        number: $number,
        agent_generated_guess: true,
        review_rounds: $err
      }
      + (if $shr == null then {} else { self_heal_rounds: $shr } end)
      + {
        additions: $additions,
        deletions: $deletions,
        changed_files: $changed_files,
        categories: $categories,
        self_heal_misses: $shm,
        # flow_stages.self_heal counts DRAIN rounds only (decision 8).
        flow_stages: { launch_pad: 0, worker: 0, self_heal: $err, unknowable: 0 },
        summary: (if $summary == "" then
                    ("automate drain: " + (if $err==0 then "no churn" else (($err|tostring) + " round(s)") end)
                     + (if $shrn > 0 then ("; self-heal: " + ($shrn|tostring) + " round(s)") else "" end))
                  else $summary end),
        plugin_version: (if $plugin_version == "" then "unknown" else $plugin_version end),
        pr_url: (if $pr_url == "" then null else $pr_url end),
        branch: (if $branch == "" then null else $branch end),
        changed_paths: $changed_paths,
        brief_path: null,
        job_path: null,
        source: $source,
        automate_key: $automate_key
      }
    ' 2>/dev/null)"

  # If the record didn't build (jq error), degrade to a no-op rather than write junk.
  [ -n "$line" ] || return 0

  # Append atomically (append-only — never rewrite the ledger). Create dir best-effort.
  mkdir -p "$(dirname "$ledger")" 2>/dev/null
  printf '%s\n' "$line" >> "$ledger" 2>/dev/null

  return 0
}

# --------------------------------------------------------------------------- #
# §6 steps 1 & 5 — brief-repair (fail-SAFE, evidence-positive, ONE mover)
# --------------------------------------------------------------------------- #

# brief-repair <item> <pr_url>
#
# The engine-side seam for repairing a stranded brief on the strongest evidence
# there is: the engine itself watched the PR merge (its --auto-merge gate merged
# it at §6 step 5 SYNC, or RESUME reconcile found an item parked awaiting_merge
# now merged at §6 step 1). It re-reads merge state from the forge (evidence-
# POSITIVE: only `state == MERGED` or a non-empty `mergedAt` proceeds; every
# failure to read is a skip, never a repair) and then hands the evidence to the
# SIBLING `reconcile-jobs.sh --repair --porcelain --evidence <item>=<pr_url>`,
# which stays the ONE mover — this helper moves nothing itself. The reconciler
# scopes the repair to that key and refuses an ambiguous match (two in-progress
# briefs with the same pointer), so this helper cannot attribute a PR to a
# stranded earlier attempt.
#
# Prints EXACTLY one stdout line for the loop to `progress-append` verbatim:
#   brief-repair: repaired <brief_path> → <done_path> (<pr_url>)
#   brief-repair: skipped — <reason>
# Each gate has its own reason so the Progress line says WHICH gate stopped it.
#
# FAIL-SAFE (same posture as learning-emit): `set +e` first; ALWAYS returns 0;
# never die/abort; `set -u` stays on so every expansion carries a default.
# Never reads or writes the run file, never touches ## Queue / ## Current, and
# never calls `gh pr merge` (the sole executor stays gate-eval, §11).
# The reconciler is found by the plain `dirname "$0"` sibling lookup the scripts
# already use (this file is held at allowance 0 by check-vendor-coupling.sh).
brief_repair() {
  set +e   # FAIL-SAFE: always exit 0; never die/abort inside the per-item loop.

  local item="${1:-}" pr_url="${2:-}"
  if [ -z "$item" ] || [ -z "$pr_url" ]; then
    echo "brief-repair: skipped — missing argument"; return 0
  fi

  # (a′) lexical gate — belt-and-braces: the reconciler would ignore a junk
  # value anyway, but this keeps the forge call from ever being made for junk.
  local malformed=0
  case "$item" in
    /*|*..*)                     malformed=1 ;;
    .supervisor/requirements/?*) ;;
    *)                           malformed=1 ;;
  esac
  # Built-in ERE match, not `printf | grep -q`: under pipefail a `grep -q` can
  # fail via SIGPIPE even on a match (recorded trap).
  [[ "$pr_url" =~ ^https?://[^[:space:]]+/pull/[0-9]+$ ]] || malformed=1
  if [ "$malformed" -eq 1 ]; then
    echo "brief-repair: skipped — malformed item or pr_url"; return 0
  fi

  # (b)–(e) evidence-positive forge read.
  if ! command -v "$GH" >/dev/null 2>&1; then
    echo "brief-repair: skipped — gh unavailable"; return 0
  fi
  local view state merged
  view="$("$GH" pr view "$pr_url" --json state,mergedAt 2>/dev/null)"
  if [ $? -ne 0 ]; then
    echo "brief-repair: skipped — gh pr view failed"; return 0
  fi
  if ! printf '%s' "$view" | "$JQ" -e '.state' >/dev/null 2>&1; then
    echo "brief-repair: skipped — gh output unparseable"; return 0
  fi
  state="$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null)"
  merged="$(printf '%s' "$view" | "$JQ" -r '.mergedAt // empty' 2>/dev/null)"
  if [ "$state" != "MERGED" ] && [ -z "$merged" ]; then
    echo "brief-repair: skipped — PR not merged (state=${state:-unknown})"; return 0
  fi

  # (f) the sibling reconciler — the ONE mover.
  local recon
  recon="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/reconcile-jobs.sh"
  if [ ! -r "$recon" ]; then
    echo "brief-repair: skipped — reconciler unavailable"; return 0
  fi

  # (g) run it; stderr (refusal reasons) is discarded — the rows are the trace.
  local rows
  rows="$(bash "$recon" --repair --porcelain --evidence "${item}=${pr_url}" 2>/dev/null)"

  # (h) scan the rows in precedence order. Capture-then-test throughout: no
  # `producer | grep -q` (SIGPIPE under pipefail can fail it even on a match).
  local st path ev brief_hit="" amb_n="" refused=0
  while IFS=$'\t' read -r st path ev; do
    [ -n "${st:-}" ] || continue
    case "$st" in
      repaired)
        case "${ev:-}" in *"$pr_url"*) [ -n "$brief_hit" ] || brief_hit="$path" ;; esac ;;
      unknown)
        case "${ev:-}" in
          "ambiguous: "*" point at ${item} "*|"ambiguous: "*" point at ${item}")
            [ -n "$amb_n" ] || amb_n="$(printf '%s' "$ev" | sed -n 's/^ambiguous: \([0-9][0-9]*\) .*/\1/p')" ;;
        esac ;;
      stranded_merged)
        case "${ev:-}" in "automate engine supplied "*"$pr_url"*) refused=1 ;; esac ;;
    esac
  done <<EOF
$rows
EOF

  if [ -n "$brief_hit" ]; then
    echo "brief-repair: repaired ${brief_hit} → .supervisor/jobs/done/$(basename "$brief_hit") (${pr_url})"
  elif [ -n "$amb_n" ]; then
    echo "brief-repair: skipped — ambiguous match (${amb_n} briefs point at ${item})"
  elif [ "$refused" -eq 1 ]; then
    echo "brief-repair: skipped — reconciler refused the move (destination exists, ## Outcome present, or write failure — re-run reconcile-jobs.sh --repair --evidence <item>=<pr_url> by hand for the reason)"
  else
    echo "brief-repair: skipped — no in-progress brief matches ${item}"
  fi
  return 0
}

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

# --------------------------------------------------------------------------- #
# dispatch
# --------------------------------------------------------------------------- #

# --------------------------------------------------------------------------- #
# §"Branch mode" — meta-entry (pull BEFORE the first read) + meta-push-failed
# --------------------------------------------------------------------------- #

# _meta_root [<root>] — the checkout meta-sync.sh resolves: the given root, else the FIRST
# `git worktree list --porcelain` entry (the primary checkout), else $PWD. Mirrors meta-sync.sh's
# own "resolve root" block so the mode is read from the same .gitignore meta-sync syncs.
_meta_root() {
  local r="${1:-}" top
  if [ -z "$r" ]; then
    r="$(git worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
    if [ -n "$r" ] && [ -d "$r" ]; then
      top="$(git -C "$r" rev-parse --path-format=absolute --show-toplevel 2>/dev/null || true)"
      [ "$top" = "$r" ] || r=""
    fi
    [ -n "$r" ] || r="$PWD"
  fi
  printf '%s\n' "$r"
}

# meta-entry [--root <checkout>] — ONE verdict line, ALWAYS exit 0:
#   meta-entry: off                              mode off — proceed exactly as today, no network
#   meta-entry: pulled <branch>                  mode on, `meta-sync.sh pull --branch <branch>` exited 0
#   meta-entry: failed — <reason>                mode on, pull exited non-zero (meta-sync's own text:
#                                                no_remote_branch / conflict <path> / fetch_failed …)
#   meta-entry: failed — mode unknown (<reason>) `setup-memory.sh mode` said unknown
# It creates and writes NOTHING under .supervisor/automate/ (meta-sync's pull writes only the
# managed run-history files it syncs). The SKILL maps `failed` to ABORT (no run file targeted) or a
# `meta_unreachable` park (an existing local run file targeted by --resume <id>).
meta_entry() {
  local root="" here mode branch out rc reason ms
  while [ $# -gt 0 ]; do
    case "$1" in
      --root)
        # A missing, empty or option-shaped value is a misinvocation, never "use the default root":
        # `--root --x` would otherwise read the mode of a non-existent checkout as `off` and skip
        # the pull silently. Fail-safe like every other path here: one `failed` line, exit 0.
        case "${2:-}" in
          ""|-*) echo "meta-entry: failed — --root requires a checkout path (got '${2:-}')"; return 0 ;;
        esac
        root="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  here="$(cd "$(dirname "$0")" && pwd)"
  root="$(_meta_root "$root")"
  mode="$(bash "$here/setup-memory.sh" --root "$root" mode 2>/dev/null | head -n1 || true)"
  case "$mode" in
    off) echo "meta-entry: off"; return 0 ;;
    "on "?*) branch="${mode#on }" ;;
    "unknown "*) echo "meta-entry: failed — mode unknown (${mode#unknown })"; return 0 ;;
    *) echo "meta-entry: failed — mode unknown (setup-memory.sh mode printed '${mode}')"; return 0 ;;
  esac
  ms="${LOOMWRIGHT_META_SYNC_BIN:-$here/meta-sync.sh}"
  rc=0
  out="$(bash "$ms" pull --branch "$branch" --root "$root" 2>&1)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "meta-entry: pulled $branch"
    return 0
  fi
  # meta-sync's own lines (conflict <path> / no_remote_branch / fetch_failed …), joined.
  reason="$(printf '%s\n' "$out" | sed -n 's/^meta_sync: //p' | awk 'NF { printf "%s%s", (n++ ? "; " : ""), $0 }')"
  [ -n "$reason" ] || reason="meta-sync.sh pull exited $rc"
  echo "meta-entry: failed — $reason"
  return 0
}

# meta-push-failed <runfile> — read-only. Prints the first line (UTC timestamp + reason) of this
# run's gitignored `<run_id>.meta-push-failed` marker, written by a failed mode-on trail-pr push
# and removed by the next successful one; prints nothing when absent. ALWAYS exit 0.
meta_push_failed() {
  local rf="${1:-}" m
  [ -n "$rf" ] || return 0
  # An option-shaped <runfile> is a misinvocation (dirname/basename would read it as a flag).
  case "$rf" in -*) return 0 ;; esac
  m="$(dirname "$rf")/$(basename "$rf" .md).meta-push-failed"
  [ -f "$m" ] || return 0
  head -n1 "$m" 2>/dev/null || true
  return 0
}

# --------------------------------------------------------------------------- #
# plan-waves — read-only wave planner (parallel-automate/04). Its ONLY caller is the
# `--parallel N>1` coordinator (item 05); the sequential loop never calls it, and it is
# never called when N = 1 (`--max 1` is NOT queue order once an item depends on a
# later-numbered one, so the guarantee is by not calling it).
# --------------------------------------------------------------------------- #
#
# plan-waves <runfile|dir|item-list> --max N [--root <checkout>]
# Input: a run file (is_run_file) ⇒ the plan set is its unchecked `- [ ]` Queue rows, and its
# checked rows say which dependencies are merged-done; a directory ⇒ resolve_folder's output;
# any other regular file ⇒ one item path per non-blank, non-`#` line. Queue rows and item-list
# lines are resolved against --root (default `git rev-parse --show-toplevel`, else $PWD).
#
# Grammar (outside ``` fences; a section runs to the next `# `/`## ` heading; blank lines ignored):
#   `## Touches`    — one repo-relative path per line, chars [A-Za-z0-9._/@+-] only, no leading
#                     `/`, no `.` or `..` segment, no `//`; trailing `/` = directory; the sole line
#                     `unknown` = not known. Missing, empty, duplicated, `unknown`-mixed or ANY
#                     bad line ⇒ the WHOLE section is unknown ⇒ the item runs ALONE.
#   `## Depends on` — `none` (sole line), a 1-3 digit id (resolved to the single `NN-*.md` in the
#                     dependent's own directory, numeric equality), or a `*.md` path relative to
#                     the dependent's directory. A section that does not parse = a MISSING one ⇒
#                     the item depends on EVERY earlier plan-set item (input order).
# Every comparison (plan-set membership, Queue lookup, cycles) uses the PHYSICAL absolute path.
# A dependency outside the plan set must be merged-done: a plain `- [x]` Queue row (run-file
# input) or a done `## Status:` line on ANY heading (is_done) — an ABANDONED stamp, and a
# `# skipped:` / `# abandoned:` Queue row mark, win over a done stamp (Phase 4.5 stamps before merge).
# Companion expansion: <root>/.agent/companions.json (strict shape, read with jq) adds paths to
# an item's Touches set — ONE pass, added paths are not re-expanded; `when` is an unquoted,
# case-sensitive bash `case` pattern for a FILE entry (a `"new": true` rule only when the file is
# absent under <root>; `when` and `add` obey the Touches path rules — no leading `/`, no `//`, no
# `.`/`..` segment — so a literal comparison never misses a non-canonical spelling); a DIRECTORY entry `D/` fires a rule when the rule's literal prefix (the
# `when` text before its first glob character) starts with `D/` or `D/` starts with it. Absent ⇒
# one stderr note, no expansion; malformed (or jq missing) ⇒ exit 1 `companions_malformed`.
# Intersection is literal prefix on normalized entries (trailing `/` stripped): a == b, or one
# starts with the other plus `/`. Waves fill greedily in input order, at most N items, no two
# intersecting, an unknown-Touches item alone in its wave.
# Output (stdout, only after the WHOLE plan is computed): `wave <k>: <item> …` lines then one
# `blocked <item>: <why>` per unplaced item; exit 0. Exit 1 with NOTHING on stdout on usage
# errors, `item not found: <item>` (a plan-set entry — Queue row, item-list line or resolve-folder
# result — names no file on disk), an unknown dependency, a dependency cycle, or companions_malformed.
# READ-ONLY: writes only its own `mktemp -d` dir (trap-removed); the only git call is
# `rev-parse --show-toplevel`; never `gh`.
#
# --explain (parallel-automate/10) — same inputs, same `wave`/`blocked` lines and exit codes; then,
# for every PLACED item not in wave 1 (wave order, then input order), `explain <item> (wave <k>):`
# and one indented line per distinct reason it stayed out of an earlier wave, recorded where the
# wave loop made the decision: `conflicts with <item> on <path> (declared)` /
# `conflicts with <item> on <path> (companion: <when>)` (the contained path of the intersecting
# pair; companion when either side's entry came from a companion rule), `depends on <item>`,
# `runs alone: Touches unknown (missing)` / `(unparsable line <N>: "<text>")` / `(declared unknown)`,
# `runs alone: Depends on missing ⇒ depends on every earlier item`, `wave <w> full (--max <N>)`,
# `wave <w> runs <item> alone (Touches unknown)`. A blocked item's reason is its `blocked` line.
# --lint (parallel-automate/10) — `<item|dir|runfile|item-list> --lint`: a directory ⇒
# resolve_folder's output; a run file ⇒ its unchecked Queue rows; any other `*.md` ⇒ that ONE item;
# any other file ⇒ an item list. `--max` is not needed (ignored when given). Per item ONE line
# `<item>: Touches <v>; Depends on <v>`, <v> = `ok` | `ok (declared unknown)` (Touches only) |
# `missing section` | `line <N>: "<text>" — <reason>` [` (+<k> more)`], N = 1-based line in the
# item file; then `<k> of <n> items will run alone: <items|none>` (Touches not known) and
# `<m> of <n> items depend on every earlier item: <items|none>` (Depends on missing). Exit 1 when
# ANY section of ANY item is missing or unparsable, else 0; exit 1 + empty stdout on usage /
# item not found. The verdict is a by-product of the SAME awk pass the planner reads
# (_pw_touches / _pw_depends with a diag file), so lint `ok` ⇔ the planner reads the section as known.

_PW_TMP=""
_PW_EXPLAIN=0
_pw_fail()  { echo "plan-waves: $*" >&2; exit 1; }
_pw_usage() { echo "plan-waves: ${1:-bad usage}" >&2; echo "usage: automate-helpers.sh plan-waves <runfile|dir|item-list> --max N [--explain] [--root <checkout>]" >&2; echo "       automate-helpers.sh plan-waves <item|dir|runfile|item-list> --lint [--root <checkout>]" >&2; exit 1; }

# _pw_abs <path> — "<physical dir>/<basename>"; non-zero when the directory does not exist.
_pw_abs() {
  local d
  d="$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$d" "$(basename "$1")"
}

# The section parsers. ONE awk pass per section yields BOTH the planner's verdict (stdout, byte-for-
# byte what the planner has always read) and — only when a diag file is given — its diagnosis
# (the --lint / --explain view): `ok`, `declared` (Touches: the sole `unknown`), `missing`, or one
# `bad<TAB><line N><TAB><reason><TAB><text>` row per offending line in line order. Every verdict
# that is not `known`/`none`/ids and not missing/declared carries at least one `bad` row, so the
# lint verdict and the planner's verdict cannot disagree (there is no second grammar to drift).
# Shared awk helpers: _pw_diag records a row; _pw_flush sorts rows by line and writes them.
_PW_AWK_DIAG='
  function _pw_diag(ln, r, s) { if (DG == "") return; gsub(/\t/, " ", s); nd++; DL[nd] = ln; DR[nd] = r; DT[nd] = s }
  function _pw_flush(   a, b, t) {
    for (a = 2; a <= nd; a++) for (b = a; b > 1 && DL[b - 1] > DL[b]; b--) {
      t = DL[b]; DL[b] = DL[b - 1]; DL[b - 1] = t; t = DR[b]; DR[b] = DR[b - 1]; DR[b - 1] = t
      t = DT[b]; DT[b] = DT[b - 1]; DT[b - 1] = t }
    for (a = 1; a <= nd; a++) printf "bad\t%d\t%s\t%s\n", DL[a], DR[a], DT[a] > DG
  }'

# _pw_touches <file> [diag file] — prints `unknown`, or `known` then one RAW entry per line.
# The Touches path grammar on its PW_TOUCHES_GRAMMAR line (charset [A-Za-z0-9._/@+-], no leading `/`,
# no `//`, no `.`/`..` segment) is hand-copied, sharing no code, in automate-dismissed.sh (the
# PATH_TOK / BAD_SEG regexes beside touches_of) and propose-from-verify.sh (vt_touches); change all
# three together — test-automate-helpers.sh §X7 feeds one token set through all three and fails on drift.
_pw_touches() {
  PW_DG="${2:-}" env LC_ALL=C awk "$_PW_AWK_DIAG"'
    # _pw_why — the lint reason for a line the grammar below rejects (diagnosis only; the
    # accept/reject decision is the single PW_TOUCHES_GRAMMAR line, never this function).
    function _pw_why(s,   t) {
      if (s ~ /^- /) return "\"- \" bullet"
      if (index(s, "`")) return "backticks"
      if (s ~ /[()]/) return "parenthetical/prose"
      if (index(s, ",")) return "comma list"
      t = s; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
      if (t != s && t !~ /[ \t]/) return "leading/trailing whitespace"
      if (s ~ /[ \t]/) return "parenthetical/prose"
      if (s ~ /^\//) return "leading /"
      if (s ~ /\/\//) return "//"
      if (s ~ /(^|\/)\.\.?(\/|$)/) return ". or .. segment"
      return "character outside [A-Za-z0-9._/@+-]"
    }
    BEGIN { DG = ENVIRON["PW_DG"]; fence = 0; insec = 0; count = 0; n = 0; bad = 0; unk = 0; nd = 0 }
    /^```/ { fence = !fence; if (insec) { bad = 1; _pw_diag(NR, "fenced block inside the section", $0) }; next }
    !fence && (/^# / || /^## /) { insec = 0; if ($0 == "## Touches") { count++; insec = 1; if (count == 1) hl = NR; else _pw_diag(NR, "duplicated section", $0) }; next }
    !insec { next }
    /^[ \t]*$/ { next }
    $0 == "unknown" { unk = 1; if (!ul) ul = NR; next }
    !/^[A-Za-z0-9._\/@+-]+$/ || /^\// || /\/\// || /(^|\/)\.\.?(\/|$)/ { bad = 1; _pw_diag(NR, _pw_why($0), $0); next }   # PW_TOUCHES_GRAMMAR
    { E[++n] = $0 }
    END {
      if (count == 0) { if (DG != "") print "missing" > DG; print "unknown"; exit }   # PW_MISSING_TOUCHES: a missing section runs alone, never an empty set
      if (count > 1 || bad || unk || n == 0) {
        if (DG != "") {
          if (count == 1 && !bad && n == 0 && unk) print "declared" > DG
          else {
            if (unk && n > 0) _pw_diag(ul, "unknown mixed with paths", "unknown")
            if (count == 1 && !bad && n == 0 && !unk) _pw_diag(hl, "empty section", "## Touches")
            _pw_flush()
          }
        }
        print "unknown"; exit
      }
      if (DG != "") print "ok" > DG
      print "known"; for (i = 1; i <= n; i++) print E[i]
    }' "$1"
}

# _pw_depends <file> [diag file] — prints `missing` (absent or unparseable), `none`, or one id/path per line.
_pw_depends() {
  PW_DG="${2:-}" env LC_ALL=C awk "$_PW_AWK_DIAG"'
    BEGIN { DG = ENVIRON["PW_DG"]; fence = 0; insec = 0; count = 0; n = 0; nn = 0; bad = 0; nd = 0 }
    /^```/ { fence = !fence; if (insec) { bad = 1; _pw_diag(NR, "fenced block inside the section", $0) }; next }
    !fence && (/^# / || /^## /) { insec = 0; if ($0 == "## Depends on") { count++; insec = 1; if (count == 1) hl = NR; else _pw_diag(NR, "duplicated section", $0) }; next }
    !insec { next }
    /^[ \t]*$/ { next }
    $0 == "none" { nn++; if (nn == 1) n1 = NR; if (nn == 2) n2 = NR; next }
    /^[0-9][0-9]?[0-9]?$/ { D[++n] = $0; next }
    /^[A-Za-z0-9._\/@+-]+\.md$/ && !/^\// && !/\/\// { D[++n] = $0; next }
    { bad = 1; _pw_diag(NR, "not an id or *.md path", $0) }
    END {
      if (count != 1 || bad || (nn && (n || nn > 1)) || (!nn && !n)) {
        if (DG != "") {
          if (count == 0) print "missing" > DG
          else {
            if (count == 1 && !bad && !nn && !n) _pw_diag(hl, "empty section", "## Depends on")
            if (nn > 1) _pw_diag(n2, "none repeated", "none")
            if (nn && n) _pw_diag(n1, "none mixed with ids", "none")
            _pw_flush()
          }
        }
        print "missing"; exit
      }
      if (DG != "") print "ok" > DG
      if (nn) { print "none"; exit }
      for (i = 1; i <= n; i++) print D[i]
    }' "$1"
}

# _pw_verdict <diag file> — the lint verdict text for one section; exit 0 when it is
# `ok` / `ok (declared unknown)`, 1 when the section is missing or unparsable.
_pw_verdict() {
  local first
  first="$(head -n1 "$1" 2>/dev/null)"
  case "$first" in
    ok) echo ok; return 0 ;;
    declared) echo "ok (declared unknown)"; return 0 ;;
    missing) echo "missing section"; return 1 ;;
  esac
  env LC_ALL=C awk -F '\t' 'NR == 1 { printf "line %s: \"%s\" — %s", $2, $4, $3 }
    END { if (NR > 1) printf " (+%d more)", NR - 1; printf "\n" }' "$1"
  return 1
}

# _pw_touches_why <diag file> — the parenthesised reason in `runs alone: Touches unknown (<why>)`.
_pw_touches_why() {
  case "$(head -n1 "$1" 2>/dev/null)" in
    missing) echo missing ;;
    declared) echo "declared unknown" ;;
    *) env LC_ALL=C awk -F '\t' 'NR == 1 { printf "unparsable line %s: \"%s\"\n", $2, $4; exit }' "$1" ;;
  esac
}

# _pw_resolve_dep <dependent abs path> <id> — prints the dependency's physical absolute path;
# non-zero unless it names exactly one existing regular *.md file.
_pw_resolve_dep() {
  local dir id="$2" f b p hit="" n=0
  dir="$(dirname "$1")"
  case "$id" in
    *.md) f="$dir/$id"; [ -f "$f" ] || return 1; _pw_abs "$f"; return $? ;;
  esac
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"; p="${b%%-*}"
    [ "$p" != "$b" ] || continue
    case "$p" in ""|*[!0-9]*) continue ;; esac
    [ "${#p}" -le 9 ] || continue
    [ "$((10#$p))" -eq "$((10#$id))" ] || continue
    n=$((n+1)); hit="$f"
  done
  [ "$n" -eq 1 ] || return 1
  _pw_abs "$hit"
}

# _pw_abandoned <file> — true when ANY `## Status:` line carries the ABANDONED close-out stamp.
_pw_abandoned() {
  awk 'index($0, "## Status:") == 1 && index($0, "done_with_escalation — ABANDONED") { f = 1 } END { exit f ? 0 : 1 }' "$1" 2>/dev/null
}

# _pw_dep_state <abs path> — `done` | `never <skipped|abandoned>` | `notready <parked|proposed>` | `pending`.
_pw_dep_state() {
  local f="$1" row
  row="$(PW_K="$f" awk -F '\t' '$2 == ENVIRON["PW_K"] { print $1; exit }' "$_PW_TMP/checked")"
  if _pw_abandoned "$f"; then echo "never abandoned"; return 0; fi
  # The owner's Queue row mark outranks the (gitignored) file stamp: Phase 4.5 writes
  # done / done_with_escalation BEFORE any merge, so a `# skipped:` / `# abandoned:` row over a
  # done stamp still never landed.
  case "$row" in skipped|abandoned) echo "never $row"; return 0 ;; esac
  if [ "$row" = done ] || is_done "$f"; then echo done; return 0; fi
  if is_not_ready "$f"; then
    if grep -qE '^## Status:[[:space:]]*parked\b' "$f"; then echo "notready parked"; else echo "notready proposed"; fi
    return 0
  fi
  echo pending
}

# _pw_load_companions <root> — writes $_PW_TMP/rules: `<when>\t<0|1 new>\t<add path>` per add path.
_pw_load_companions() {
  local cf="$1/.agent/companions.json"
  : > "$_PW_TMP/rules"
  if [ ! -e "$cf" ]; then
    echo "plan-waves: no $cf — no companion expansion" >&2
    return 0
  fi
  command -v "$JQ" >/dev/null 2>&1 || _pw_fail "companions_malformed jq not found (needed to read $cf)"
  # `-s` slurps every JSON document into one array and the shape check demands EXACTLY one:
  # `jq -e` alone exits on the LAST document only, so a malformed first document followed by a
  # valid one would pass and have its rules loaded.
  "$JQ" -se '
    length == 1 and (.[0] |
    type == "object" and ((keys - ["companions", "schema_version"]) | length) == 0
    and .schema_version == 1 and (.companions | type) == "array"
    and all(.companions[];
      type == "object" and ((keys - ["add", "new", "when"]) | length) == 0
      and (.when | type) == "string" and (.when | test("^[A-Za-z0-9._/@+*?\\[\\]!-]+$"))
      and (.when | test("^/|//|(^|/)\\.\\.?(/|$)") | not)
      and (.add | type) == "array" and (.add | length) > 0
      and all(.add[]; type == "string" and test("^[A-Za-z0-9._/@+-]+$")
        and (test("^/|//|(^|/)\\.\\.?(/|$)") | not))
      and ((has("new") | not) or .new == true)))' "$cf" >/dev/null 2>&1 \
    || _pw_fail "companions_malformed $cf is not {\"schema_version\":1,\"companions\":[{\"when\":<glob>,[\"new\":true,]\"add\":[<path>,…]},…]}"
  "$JQ" -sr '.[0].companions[] | . as $r | .add[] | [$r.when, (if $r.new then "1" else "0" end), .] | @tsv' "$cf" > "$_PW_TMP/rules" 2>/dev/null \
    || _pw_fail "companions_malformed $cf could not be read"
}

# _pw_expand <raw entries file> <root> <out> — normalized (trailing `/` stripped), sorted, unique
# Touches set plus ONE pass of companion additions.
# Under --explain it also writes <out>.why: `<entry>\t<declared | companion: <when>>` per entry of
# <out> (declared wins when an entry is both), so a conflict can name the rule that added it.
_pw_expand() {
  local e d w nw a pfx tab
  tab="$(printf '\t')"
  : > "$3.raw"; : > "$3.prov"
  while IFS= read -r e; do
    d="${e%/}"
    printf '%s\n' "$d" >> "$3.raw"
    if [ "$_PW_EXPLAIN" = 1 ]; then printf '%s\tdeclared\n' "$d" >> "$3.prov"; fi
    while IFS="$tab" read -r w nw a; do
      if [ "$d" != "$e" ]; then
        pfx="${w%%[*?[]*}"
        case "$pfx" in
          "$d/"*) ;;
          *) case "$d/" in "$pfx"*) ;; *) continue ;; esac ;;
        esac
      else
        # shellcheck disable=SC2254 # unquoted on purpose: `when` is a glob
        case "$e" in $w) ;; *) continue ;; esac
        if [ "$nw" = 1 ] && [ -e "$2/$e" ]; then continue; fi
      fi
      printf '%s\n' "${a%/}" >> "$3.raw"
      if [ "$_PW_EXPLAIN" = 1 ]; then printf '%s\tcompanion: %s\n' "${a%/}" "$w" >> "$3.prov"; fi
    done < "$_PW_TMP/rules"
  done < "$1"
  env LC_ALL=C sort -u "$3.raw" > "$3"
  if [ "$_PW_EXPLAIN" = 1 ]; then
    env LC_ALL=C awk -F '\t' '!($1 in P) || $2 == "declared" { P[$1] = $2 } END { for (p in P) print p "\t" P[p] }' "$3.prov" \
      | env LC_ALL=C sort > "$3.why"
  fi
}

# _pw_conflicts <A.why> <B.why> — one `<path>\t<provenance>` per intersecting pair (the contained,
# i.e. longer, path; `companion: <when>` when either side's entry came from a companion rule, A's first).
_pw_conflicts() {
  env LC_ALL=C awk -F '\t' 'NR == FNR { A[++na] = $1; PA[na] = $2; next }
    { for (i = 1; i <= na; i++) { a = A[i]; b = $1
        if (a == b || index(a, b "/") == 1 || index(b, a "/") == 1) {
          p = (length(b) > length(a)) ? b : a
          v = (PA[i] != "declared") ? PA[i] : $2
          print p "\t" v } } }' "$1" "$2" | env LC_ALL=C sort -u
}

# _pw_intersect <setA> <setB> — true when an entry of A equals, contains or is contained by one of B.
_pw_intersect() {
  [ -s "$1" ] && [ -s "$2" ] || return 1
  awk 'NR == FNR { A[++na] = $0; next }
       { for (i = 1; i <= na; i++) { a = A[i]; b = $0
           if (a == b || index(a, b "/") == 1 || index(b, a "/") == 1) { hit = 1; exit } } }
       END { exit hit ? 0 : 1 }' "$1" "$2"
}

plan_waves() {
  local input="" max="" root="" mode="plan" line p f a i j k n=0 st id ds placed total cnt alone ready changed left msg
  local waitj alonei members m w tv dv rc ka kd la ld tab
  local DISP=() ABS=() TS=() DEPJ=() BLK=() W=() OK=()
  tab="$(printf '\t')"
  _PW_EXPLAIN=0   # reset per call: a prior --explain in the same shell must not leak into a default run
  while [ $# -gt 0 ]; do
    case "$1" in
      --max) [ $# -ge 2 ] || _pw_usage "--max requires a value"; max="$2"; shift 2 ;;
      --root)
        case "${2:-}" in ""|-*) _pw_usage "--root requires a checkout path (got '${2:-}')" ;; esac
        root="$2"; shift 2 ;;
      --explain) [ "$mode" != lint ] || _pw_usage "--explain and --lint are separate modes"; mode=explain; shift ;;
      --lint) [ "$mode" != explain ] || _pw_usage "--explain and --lint are separate modes"; mode=lint; shift ;;
      -*) _pw_usage "unknown option $1" ;;
      *) [ -z "$input" ] || _pw_usage "more than one input ($input, $1)"; input="$1"; shift ;;
    esac
  done
  [ -n "$input" ] || _pw_usage "missing <runfile|dir|item-list>"
  [ -e "$input" ] || _pw_usage "input not found: $input"
  if [ "$mode" != lint ]; then
    case "$max" in ""|*[!0-9]*) _pw_usage "--max must be a positive integer (got '$max')" ;; esac
    [ "${#max}" -le 6 ] && [ "$((10#$max))" -ge 1 ] || _pw_usage "--max must be a positive integer (got '$max')"
    max=$((10#$max))
  fi
  [ "$mode" != explain ] || _PW_EXPLAIN=1
  if [ -z "$root" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
    [ -n "$root" ] || root="$PWD"
  fi
  root="$(cd "$root" 2>/dev/null && pwd -P)" || _pw_usage "--root is not a directory"

  _PW_TMP="$(mktemp -d)" || _pw_fail "mktemp -d failed"
  trap 'rm -rf "$_PW_TMP"' EXIT
  : > "$_PW_TMP/checked"; : > "$_PW_TMP/plan"

  # 1. The plan set, as `<display>\t<path to open>` lines.
  if [ -d "$input" ]; then
    resolve_folder "${input%/}" | while IFS= read -r line; do printf '%s\t%s\n' "$line" "$line"; done > "$_PW_TMP/plan"
  elif is_run_file "$input"; then
    env LC_ALL=C awk '
      /^## Queue[ \t]*$/ { q = 1; next }
      /^## / { q = 0 }
      !q { next }
      /^- \[ \] / { p = substr($0, 7); sub(/[ \t]+#.*$/, "", p); sub(/[ \t]+$/, "", p); print "U\t" p; next }
      /^- \[x\] / { p = substr($0, 7); m = "done"
        if (index(p, "# skipped:")) m = "skipped"; else if (index(p, "# abandoned:")) m = "abandoned"
        sub(/[ \t]+#.*$/, "", p); sub(/[ \t]+$/, "", p); print "X\t" m "\t" p }
    ' "$input" > "$_PW_TMP/queue"
    while IFS="$(printf '\t')" read -r st a p; do
      if [ "$st" = U ]; then
        case "$a" in /*) f="$a" ;; *) f="$root/$a" ;; esac
        printf '%s\t%s\n' "$a" "$f" >> "$_PW_TMP/plan"
      else
        case "$p" in /*) f="$p" ;; *) f="$root/$p" ;; esac
        f="$(_pw_abs "$f")" || continue
        printf '%s\t%s\n' "$a" "$f" >> "$_PW_TMP/checked"
      fi
    done < "$_PW_TMP/queue"
  elif [ "$mode" = lint ] && [ -f "$input" ] && case "$input" in *.md) true ;; *) false ;; esac; then
    # --lint only: a `*.md` that is not a run file is ONE item (the planner reads any non-run file
    # as an item list, unchanged).
    printf '%s\t%s\n' "$input" "$input" > "$_PW_TMP/plan"
  elif [ -f "$input" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      line="$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      case "$line" in ""|"#"*) continue ;; esac
      case "$line" in /*) f="$line" ;; *) f="$root/$line" ;; esac
      printf '%s\t%s\n' "$line" "$f" >> "$_PW_TMP/plan"
    done < "$input"
  else
    _pw_usage "input is neither a run file, a directory nor an item list: $input"
  fi

  # 1b. --lint: per item, the SAME parsers with a diag file; no dependency resolution, no waves.
  if [ "$mode" = lint ]; then
    rc=0; ka=0; kd=0; la=""; ld=""
    : > "$_PW_TMP/out"
    while IFS="$tab" read -r p f; do
      [ -f "$f" ] || _pw_fail "item not found: $p"
      _pw_touches "$f" "$_PW_TMP/tdiag.$n" > "$_PW_TMP/t.$n"
      _pw_depends "$f" "$_PW_TMP/ddiag.$n" > /dev/null
      tv="$(_pw_verdict "$_PW_TMP/tdiag.$n")" || rc=1
      dv="$(_pw_verdict "$_PW_TMP/ddiag.$n")" || rc=1
      if [ "$(head -n1 "$_PW_TMP/t.$n")" != known ]; then ka=$((ka+1)); la="${la:+$la }$p"; fi
      if [ "$(head -n1 "$_PW_TMP/ddiag.$n")" != ok ]; then kd=$((kd+1)); ld="${ld:+$ld }$p"; fi
      printf '%s: Touches %s; Depends on %s\n' "$p" "$tv" "$dv" >> "$_PW_TMP/out"
      n=$((n+1))
    done < "$_PW_TMP/plan"
    printf '%s of %s items will run alone: %s\n' "$ka" "$n" "${la:-none}" >> "$_PW_TMP/out"
    printf '%s of %s items depend on every earlier item: %s\n' "$kd" "$n" "${ld:-none}" >> "$_PW_TMP/out"
    cat "$_PW_TMP/out"
    return "$rc"
  fi

  # 2. Per item: physical path, Touches, Depends.
  while IFS="$(printf '\t')" read -r p f; do
    [ -f "$f" ] || _pw_fail "item not found: $p"
    DISP[n]="$p"; ABS[n]="$(_pw_abs "$f")"
    if [ "$_PW_EXPLAIN" = 1 ]; then _pw_touches "$f" "$_PW_TMP/tdiag.$n" > "$_PW_TMP/t.$n"; else _pw_touches "$f" > "$_PW_TMP/t.$n"; fi
    TS[n]="$(head -n1 "$_PW_TMP/t.$n")"
    sed '1d' "$_PW_TMP/t.$n" > "$_PW_TMP/raw.$n"
    _pw_depends "$f" > "$_PW_TMP/d.$n"
    n=$((n+1))
  done < "$_PW_TMP/plan"

  # 3. Dependencies: in-set edges (DEPJ, " j " list; ids in e.<i>) and out-of-set states (x.<i>).
  i=0
  while [ "$i" -lt "$n" ]; do
    DEPJ[i]=" "; : > "$_PW_TMP/e.$i"; : > "$_PW_TMP/x.$i"
    ds="$(head -n1 "$_PW_TMP/d.$i")"
    if [ "$ds" = missing ]; then
      j=0
      while [ "$j" -lt "$i" ]; do
        DEPJ[i]="${DEPJ[i]}$j "; printf '%s\t%s\n' "$j" "${DISP[j]}" >> "$_PW_TMP/e.$i"; j=$((j+1))
      done
    elif [ "$ds" != none ]; then
      while IFS= read -r id; do
        a="$(_pw_resolve_dep "${ABS[i]}" "$id")" || _pw_fail "unknown dependency $id in ${DISP[i]}"
        j=0; k=-1
        while [ "$j" -lt "$n" ]; do [ "${ABS[j]}" = "$a" ] && { k=$j; break; }; j=$((j+1)); done
        if [ "$k" -ge 0 ]; then
          DEPJ[i]="${DEPJ[i]}$k "; printf '%s\t%s\n' "$k" "$id" >> "$_PW_TMP/e.$i"
        else
          printf '%s\t%s\n' "$(_pw_dep_state "$a")" "$id" >> "$_PW_TMP/x.$i"
        fi
      done < "$_PW_TMP/d.$i"
    fi
    i=$((i+1))
  done

  # 4. Cycles (Kahn): an item resolves once every in-set dependency has; what is left is pruned of
  #    items nothing left depends on, so only the items on (or between) cycles are named.
  i=0; while [ "$i" -lt "$n" ]; do OK[i]=0; i=$((i+1)); done
  : > "$_PW_TMP/order"
  changed=1
  while [ "$changed" -eq 1 ]; do
    changed=0; i=0
    while [ "$i" -lt "$n" ]; do
      if [ "${OK[i]}" -eq 0 ]; then
        ready=1
        for j in ${DEPJ[i]}; do [ "${OK[j]}" -eq 1 ] || ready=0; done
        if [ "$ready" -eq 1 ]; then OK[i]=1; changed=1; echo "$i" >> "$_PW_TMP/order"; fi
      fi
      i=$((i+1))
    done
  done
  left=0; i=0; while [ "$i" -lt "$n" ]; do [ "${OK[i]}" -eq 1 ] || left=$((left+1)); i=$((i+1)); done
  if [ "$left" -gt 0 ]; then
    changed=1
    while [ "$changed" -eq 1 ]; do
      changed=0; i=0
      while [ "$i" -lt "$n" ]; do
        if [ "${OK[i]}" -eq 0 ]; then
          ready=0; j=0
          while [ "$j" -lt "$n" ]; do
            if [ "${OK[j]}" -eq 0 ]; then case "${DEPJ[j]}" in *" $i "*) ready=1 ;; esac; fi
            j=$((j+1))
          done
          [ "$ready" -eq 1 ] || { OK[i]=2; changed=1; }
        fi
        i=$((i+1))
      done
    done
    msg=""; i=0
    while [ "$i" -lt "$n" ]; do [ "${OK[i]}" -eq 0 ] && msg="$msg ${DISP[i]}"; i=$((i+1)); done
    _pw_fail "dependency cycle:$msg"
  fi

  # 5. Blocked (dependency order): an out-of-set dependency not merged-done, or a blocked in-set one.
  i=0; while [ "$i" -lt "$n" ]; do BLK[i]=""; W[i]=0; i=$((i+1)); done
  while IFS= read -r i; do
    while IFS="$(printf '\t')" read -r st id; do
      [ -z "${BLK[i]}" ] || break
      case "$st" in
        done) ;;
        "never "*) BLK[i]="waits on $id (${st#never } — never landed)" ;;
        "notready "*) BLK[i]="depends on ${st#notready } $id" ;;
        *) BLK[i]="waits on $id" ;;
      esac
    done < "$_PW_TMP/x.$i"
    while IFS="$(printf '\t')" read -r j id; do
      [ -z "${BLK[i]}" ] || break
      [ -z "${BLK[j]}" ] || BLK[i]="waits on $id"
    done < "$_PW_TMP/e.$i"
  done < "$_PW_TMP/order"

  # 6. Companion-expanded Touches sets for every placeable known-Touches item.
  _pw_load_companions "$root"
  total=0; i=0
  while [ "$i" -lt "$n" ]; do
    if [ -z "${BLK[i]}" ]; then
      total=$((total+1))
      [ "${TS[i]}" = known ] && _pw_expand "$_PW_TMP/raw.$i" "$root" "$_PW_TMP/s.$i"
    fi
    i=$((i+1))
  done

  # 7. Waves: greedy, input order, deps in earlier waves, <= max items, no intersection, unknown alone.
  #    Under --explain the scan does not stop at a full / alone wave (nothing more can be placed in
  #    it either way) so every unplaced item gets its reason recorded where the decision is made.
  : > "$_PW_TMP/out"
  placed=0; k=0
  while [ "$placed" -lt "$total" ]; do
    k=$((k+1)); cnt=0; alone=0; alonei=""; members=""; line=""; : > "$_PW_TMP/wave"
    i=0
    while [ "$i" -lt "$n" ]; do
      if [ -z "${BLK[i]}" ] && [ "${W[i]}" -eq 0 ]; then
        ready=1; waitj=""
        for j in ${DEPJ[i]}; do { [ "${W[j]}" -ge 1 ] && [ "${W[j]}" -lt "$k" ]; } || { ready=0; waitj="$waitj $j"; }; done
        if [ "$ready" -eq 1 ]; then
          if [ "$alone" -ne 0 ] || [ "$cnt" -ge "$max" ]; then
            [ "$_PW_EXPLAIN" = 1 ] || break
            if [ "$alone" -ne 0 ]; then
              printf 'wave %s runs %s alone (Touches unknown)\n' "$k" "${DISP[alonei]}" >> "$_PW_TMP/why.$i"
            else
              printf 'wave %s full (--max %s)\n' "$k" "$max" >> "$_PW_TMP/why.$i"
            fi
          elif [ "${TS[i]}" != known ]; then
            if [ "$cnt" -eq 0 ]; then
              W[i]=$k; alone=1; alonei=$i; cnt=1; line="${DISP[i]}"
            elif [ "$_PW_EXPLAIN" = 1 ]; then
              printf 'runs alone: Touches unknown (%s)\n' "$(_pw_touches_why "$_PW_TMP/tdiag.$i")" >> "$_PW_TMP/why.$i"
            fi
          elif [ "$cnt" -eq 0 ] || ! _pw_intersect "$_PW_TMP/s.$i" "$_PW_TMP/wave"; then
            W[i]=$k; cnt=$((cnt+1)); line="${line:+$line }${DISP[i]}"; members="$members $i"
            cat "$_PW_TMP/s.$i" >> "$_PW_TMP/wave"
          elif [ "$_PW_EXPLAIN" = 1 ]; then
            for m in $members; do
              _pw_conflicts "$_PW_TMP/s.$i.why" "$_PW_TMP/s.$m.why" | while IFS="$tab" read -r p a; do
                printf 'conflicts with %s on %s (%s)\n' "${DISP[m]}" "$p" "$a"
              done >> "$_PW_TMP/why.$i"
            done
          fi
        elif [ "$_PW_EXPLAIN" = 1 ]; then
          if [ "$(head -n1 "$_PW_TMP/d.$i")" = missing ]; then
            printf 'runs alone: Depends on missing ⇒ depends on every earlier item\n' >> "$_PW_TMP/why.$i"
          else
            for j in $waitj; do printf 'depends on %s\n' "${DISP[j]}" >> "$_PW_TMP/why.$i"; done
          fi
        fi
      fi
      i=$((i+1))
    done
    [ "$cnt" -gt 0 ] || _pw_fail "internal: no placeable item for wave $k"
    placed=$((placed+cnt))
    printf 'wave %s: %s\n' "$k" "$line" >> "$_PW_TMP/out"
  done
  i=0
  while [ "$i" -lt "$n" ]; do
    [ -z "${BLK[i]}" ] || printf 'blocked %s: %s\n' "${DISP[i]}" "${BLK[i]}" >> "$_PW_TMP/out"
    i=$((i+1))
  done
  # 8. --explain: one block per placed item not in wave 1 (wave order, then input order), each
  #    distinct reason once, in the order first recorded.
  if [ "$_PW_EXPLAIN" = 1 ]; then
    w=2
    while [ "$w" -le "$k" ]; do
      i=0
      while [ "$i" -lt "$n" ]; do
        if [ -z "${BLK[i]}" ] && [ "${W[i]}" -eq "$w" ]; then
          printf 'explain %s (wave %s):\n' "${DISP[i]}" "$w" >> "$_PW_TMP/out"
          if [ -f "$_PW_TMP/why.$i" ]; then
            awk '!seen[$0]++ { print "  " $0 }' "$_PW_TMP/why.$i" >> "$_PW_TMP/out"
          fi
        fi
        i=$((i+1))
      done
      w=$((w+1))
    done
  fi
  cat "$_PW_TMP/out"
}

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    config-suppress) config_suppress "$@" ;;
    config-restore)  config_restore "$@" ;;
    config-orig)     config_orig "$@" ;;
    runfile-write)   runfile_write "$@" ;;
    progress-append) progress_append "$@" ;;
    queue-checkoff)  queue_checkoff "$@" ;;
    current-set)     current_set "$@" ;;
    current-rebuild) current_rebuild "$@" ;;
    remaining)       remaining "$@" ;;
    ceiling-check)   ceiling_check "$@" ;;
    resolve-folder)  resolve_folder "$@" ;;
    resolve-backlog) resolve_backlog "$@" ;;
    resume-glob)     resume_glob "$@" ;;
    reconcile-item)  reconcile_item "$@" ;;
    gate-eval)       gate_eval "$@" ;;
    learning-emit)   learning_emit "$@" ;;
    brief-repair)    brief_repair "$@" ;;
    reconcile-status) reconcile_status "$@" ;;
    meta-entry)      meta_entry "$@" ;;
    meta-push-failed) meta_push_failed "$@" ;;
    plan-waves)      plan_waves "$@" ;;
    # Post-park lifecycle MUTATORS live in the sibling automate-trail.sh (the
    # read-only carve-out named in the header) — one mover per concern.
    sidecar-check|trail-pr|closeout|trail-unstage|trail-gate) exec bash "$(dirname "$0")/automate-trail.sh" "$cmd" "$@" ;;
    # Dismissed-finding drafts (propose-only writes, never git) — the sibling
    # automate-dismissed.sh, the second carve-out named in the header.
    dismissed-drafts)  exec bash "$(dirname "$0")/automate-dismissed.sh" "$cmd" "$@" ;;
    dismissed-decide)  exec bash "$(dirname "$0")/automate-dismissed.sh" "$cmd" "$@" ;;
    dismissed-pending) exec bash "$(dirname "$0")/automate-dismissed.sh" "$cmd" "$@" ;;
    ""|-h|--help)
      grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
