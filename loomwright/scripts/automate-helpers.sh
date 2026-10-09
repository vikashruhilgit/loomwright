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
# never a source-repo or git mutation. The ONE carve-out: `trail-pr`/`closeout`/`closeout-others`/`trail-unstage`/`trail-gate`/`finalize-empty`
# (and the read-only `sidecar-check` beside them) are delegated to the sibling
# `automate-trail.sh`, which is a git/`gh pr create` mutator bounded to this
# run's trail branch, this PR's local branch/worktree, and — in the primary
# checkout — index-only entries for this run's own trail paths plus closeout's
# (and trail-gate's PICK-time) `git checkout <base>` + `git pull --ff-only` sync (never a commit, reset or
# stash there) — never `gh pr merge`. A second, narrower carve-out:
# `dismissed-drafts`/`dismissed-decide`/`dismissed-pending` (and the read-only
# `dismissed-cost`) are delegated to the
# sibling `automate-dismissed.sh`, which writes ONLY this run's dismissed-finding
# drafts under `.supervisor/requirements/proposed/` (through propose-common.sh's
# `pc_guarded_write`), its gitignored `<run_id>.dismissed-decisions` ledger and
# one `## Progress` line per decision — never git, never `gh`. A third carve-out
# (parallel-automate/05, reached ONLY by `/automate --parallel N>1` — never by the
# sequential loop): `lane-create`/`lane-launch`/`relay-hook`/`lane-answer`/
# `lane-remove`/`lane-convert-ready`/`lane-info`/`init-check`/`pick-guard`/`branch-check` and the
# observers `lane-status`/`lane-feed`/`lane-readiness` and the park notifier `lane-park-notify` are
# delegated to the sibling `automate-lanes.sh`, which clones lanes under `<primary>-lanes/`, launches/resumes
# them headless, writes the lane table sidecar, the lane inbox and the advisory
# `<run_id>.merge-readiness.md` report (never a merge),
# and removes a lane only through its own fail-CLOSED refusals — never `gh pr merge`,
# never a force-push, never a write into a launched lane beyond the exceptions the
# automate-lanes.sh header's `Files` block lists (the authority — not restated here).
# UNCOUNTED by the
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
#   current-escalation <runfile_path> --cause <c> [--check <c> --run-id <id> --attempt <n> --sha <sha>]  # automate-followups/31: the ONLY writer of ## Current's `- escalation_cause: <cause> | check: … | run_id: … | attempt: … | sha: …` line (after `- pause_reason:`, else at the end of the block; replaced if present; `--cause null` removes it); cause enum check_pending|check_red_unrelated|check_red|findings|other|null; an omitted field is `null`; refusal (unknown cause, `|`/newline, non-numeric run id/attempt) = exit 1, file byte-unchanged; identical values ⇒ `current-escalation: unchanged`
#   current-wave     <runfile_path> --wave <k|null> [--items <i1,i2,…>]  # parallel-automate/05 (--parallel N>1 parent only): the ONLY writer of ## Current's `- wave: <k> | items: <i1>, <i2>` line (replaced if present, else appended at the block end; `--wave null` removes it); refusal (non-positive-integer wave, `|`/newline, --items with null) = exit 1, file byte-unchanged; identical values ⇒ `current-wave: unchanged`
#   current-rebuild  <runfile_path>                     # §4 RECONCILE repair: ## Current item null/absent — or `done` and not the LAST picked item — + a `picked` Progress line ⇒ item from the LAST picked line (must be a Queue row), pr ONLY from a later `ran /autonomous` line, branch via one gh pr view; always status running; one `current_rebuilt: … state <s>` line (printed + appended); set and not done (or done = the last picked item) ⇒ `skipped — ## Current set`
#   remaining        <runfile_path>                     # §3 count of "- [ ]" lines only
#   ceiling-check    <runfile_path> <max_tokens> [--root <checkout>]  # §6 PICK-time token-ceiling check via read-token-ledger.sh --run-id; prints OK/PARK, always exits 0
#   resolve-folder   <dir>                              # §2 list *.md not done and not proposed|parked
#   resolve-backlog  <backlog.md>                       # §2 dependency-ordered items honoring done/✅ markers AND the referenced file's own ## Status: done stamp (is_done); dir-fallback path also skips proposed|parked, per is_not_ready
#   resume-glob      <automate_dir> [--finalize]        # §4 (--finalize: run finalize-empty on each candidate first, list the rest; finalize lines on stderr) list run files (is_run_file: a "# Automate Run:" title line anywhere — BOM/0-3-space indent/whitespace/case tolerant, RUN_TITLE_ERE) not "## Status: done"; §6 result sidecars never listed because they carry no such line
#   reconcile-item   <pr_url> <belief>                  # §4 belief vs gh/git truth -> corrected state
#   gate-eval        <pr_url> <ctx.json>                # §10 MERGE|PARK fail-closed trusted-merge gate (conditions enumerated in skills/automate-loop/SKILL.md §10; cond 6 = classify-risk.sh high_risk, cond 7 = rules-gate-verdict.sh, NO override)
#   learning-emit    <ledger_path> <flags...>           # §6 step 3 fail-safe (always exit 0) engine-native ground-truth POSTMORTEM_RESULT line; idempotent on run_id+item+pr_url+source+completeness (a degraded emit never blocks a later complete one)
#   brief-repair     <item> <pr_url>                    # §6 steps 1/5 fail-safe (always exit 0) evidence-positive brief lifecycle repair: `gh pr view` says MERGED (or a non-empty mergedAt) ⇒ sibling reconcile-jobs.sh --repair --evidence <item>=<pr_url>; prints ONE line for ## Progress
#   escalation-cause <pr_url> --sha <sha>              # automate-followups/31: fail-SAFE READ-ONLY classifier (always exit 0) of why a drain ESCALATED — one `escalation_cause: <check_pending|check_red_unrelated|check_red|other> check=<name|null> run_id=<id|null> attempt=<n|null> sha=<sha>` line from a `wait-for-checks.sh --bound 0 --names` snapshot; red is examined before pending; check_red_unrelated only when every failed step of every red check ran nothing but plain `bash <path>/test-*.sh` commands whose test files and tested `<stem>.sh` are all outside the PR's changed files (full rule: the automate-helpers.d/escalation.sh header); every unreadable case ⇒ check_red (fail CLOSED); never reruns, merges, pushes or approves
#   reconcile-status <requirements_root> [--apply]      # queue-hygiene/01: dry-run-default requirement `## Status:` reconciler — a `pending`/absent-status *.md under <requirements_root> (skips `00-*`, `_*`, `README*`, `operator-run/`) whose PR is MERGED (state via reconcile-item) and whose body cites the file's repo-relative path, OR whose head branch matches the slug on its `.supervisor/jobs/done/` brief (never the engine's own `chore/<run_id>-trail-<n>` PR, never a PR whose changed files are ALL under `.supervisor/`, and never a body citation from a PR whose own diff adds or modifies that requirement file; an unreadable or incomplete diff is no evidence), is stamped the §6 shape byte-for-byte; a `.supervisor/automate/*.md` Queue row carrying `# abandoned:` and naming a requirement stamps `done_with_escalation — ABANDONED (<row verbatim>)`; NEVER downgrades an existing `done`/`done_with_escalation`; prints one `plan\t…` row per file it WOULD stamp (or `stamped\t…` under `--apply`) plus one `info\t…` row per `brief-shipped` file (never promoted); writes nothing without `--apply`.
#   sidecar-check    <path>                             # §6 trail: delegated to automate-trail.sh — `ok <path>` / `fail <path>: <reason>` (RESULT_SCHEMAS key-table shape check of a result sidecar); always exits 0
#   trail-pr         <runfile> [--reason <reason>]      # §6 "Trail PR after merge and at run end": delegated to automate-trail.sh — called only by closeout, at ## Status: done, and on a skip/abandon check-off (never at a park — except §14's lane wave end, --reason wave-end, and lane-remove --abandon, --reason abandoned, run inside the lane through the same evidence gate); commits this run's explicit trail paths as ONE PR off fresh origin/main, a done-stamped requirement/done brief only when its PR reads merged; one line (opened|pushed|skipped); always exits 0
#   closeout         <runfile> <item> <pr_url> [--session-id <sid>]  # §6 post-merge close-out: delegated to automate-trail.sh; always exits 0
#   closeout-classify [--run <id> --item <p> --pr <u>] [--record <rf>]  # §6 step 1 close-out leftover gate: reads ONE closeout invocation's output on stdin, classifies its `closeout: ` lines against CLOSEOUT_TABLE (only the partial-removal form `removed — worktree …; kept …` is forced to a leftover; an unknown line is a leftover) ⇒ `complete` or one `leftover\t<run>\t<item>\t<pr>\t<step>\t<detail>` row per leftover; --record appends `closeout: nothing to close out — <item>` (once per item per run) on a complete close-out that changed nothing; exit 0 (usage error 1)
#   closeout-others  <automate_dir> [--record <runfile>]  # §4 start order: delegated to automate-trail.sh — closeout of every OTHER run whose ## Current names a not-done item with a merged PR (own lock, own trail; mode-off trail-unstage), its classify answer, and one `cross-run closeout <run_id> <item>: …` record line (no PR URL) appended to --record's run file; always exits 0
#   finalize-empty   <runfile>                          # §3/§4 step 1: delegated to automate-trail.sh — a paused / awaiting_go / remaining-0 / ## Current status-done run ⇒ run lock, `## Status: done` + pause_reason null, `auto-finalized` Progress line, trail-pr --reason done, mode-off trail-unstage; else one `skipped — <reason>` line; always exits 0
#   dismissed-drafts <runfile> <item> <pr_url> [--after-fix-now]  # §6 "Dismissed-findings decision step (before the park)": delegated to automate-dismissed.sh — one propose-only draft per dismissed finding over the threshold (+ one undecided summary draft per item) in proposed/, content-addressed names, decisions never reset; TSV `draft` rows + one summary line; always exits 0
#   dismissed-decide <runfile> <draft_path> <fix-now|follow-up|drop>  # §6 decision step / next PICK: delegated to automate-dismissed.sh — records the decision in <run_id>.dismissed-decisions, rewrites (follow-up) or deletes (drop/fix-now) the draft, one Progress line; refuses a foreign path; always exits 0
#   dismissed-pending <runfile>                         # §6 step 1 PICK: delegated to automate-dismissed.sh — count of this run's undecided drafts, or `unknown` (treated as non-zero); always exits 0
#   dismissed-cost <runfile>                            # §6 decision step 2: delegated to automate-dismissed.sh, READ-ONLY advisory — ONE `fix_now_cost: <estimate> (<basis>)` line from this repo's recorded fix-now re-drains, else a labelled baseline; always exits 0
#   trail-unstage    <runfile>                          # §6 step 1 PICK (before RUN): delegated to automate-trail.sh — drops the trail-path index entries trail-pr staged so the next item's commit cannot sweep them; one line; always exits 0
#   trail-gate       <runfile>                          # §6 step 1 PICK (after RECONCILE, before trail-unstage) / §8: delegated to automate-trail.sh — `PARK — trail PR open <url>` while this run's trail PR is open (or its state is unreadable: fail CLOSED); else `clear — …` after syncing the primary onto the base branch (closeout's sync); one line; always exits 0
#   meta-entry       [--root <checkout>]                # §"Branch mode": the FIRST action of every /automate entry (a bare/empty/option-shaped --root value ⇒ `failed`) — reads `setup-memory.sh mode` itself (no caller input can assert the mode) and, when on, runs `meta-sync.sh pull`; ONE line `meta-entry: off|pulled <branch>|failed — <reason>`; writes nothing under .supervisor/automate/; always exits 0
#   meta-push-failed <runfile>                          # §"Branch mode": read-only — prints the first line of this run's gitignored `<run_id>.meta-push-failed` marker (a failed mode-on trail push), or nothing; always exits 0
#   plan-waves       <runfile|dir|item-list> --max N [--explain] [--root <checkout>]  # parallel-automate/04: READ-ONLY wave planner — `## Depends on` / `## Touches` (strict grammar) + <root>/.agent/companions.json expansion ⇒ `wave <k>: …` + `blocked <item>: …` lines (`--explain`, parallel-automate/10: then one `explain <item> (wave <k>):` block per placed item not in wave 1); exit 1 + empty stdout on usage / item not found / unknown dependency / cycle / companions_malformed; called ONLY by `--parallel N>1` (item 05), never by the sequential loop
#   plan-waves       <item|dir|runfile|item-list> --lint [--root <checkout>]  # parallel-automate/10: READ-ONLY lint of both sections with the planner's OWN parser — one `<item>: Touches <verdict>; Depends on <verdict>` line per item + two count lines; exit 1 when any section is missing/unparsable (a sole `unknown` Touches is `ok (declared unknown)`); never needs --max
#   lane-create      <parent_runfile> <item> <n> [--parallel N] [--max-tokens T]  # parallel-automate/05 (--parallel N>1 only): delegated to automate-lanes.sh — clone at <primary>-lanes/<run_id>/L<n>/ (origin before fetch), carried configs, .supervisor/lane.json, one-line backlog, relay hooks
#   lane-launch      <lane_dir> --owner-command '<cmd>' [--resume-run <run_id> | --continue]  # parallel-automate/05: delegated to automate-lanes.sh — detached headless launch/resume; no owner command ⇒ `BLOCKED` (exit 3); load/memory admission ⇒ `HELD` (exit 4)
#   relay-hook                                          # parallel-automate/05: delegated to automate-lanes.sh — the lane's PreToolUse/PermissionRequest[AskUserQuestion] hook (stdin: hook JSON) ⇒ inbox question file + defer
#   lane-answer      <lane_dir> <tool_use_id> --owner-command '<cmd>' [--via <client>]  # parallel-automate/05: delegated to automate-lanes.sh — validates the answer against the question's own labels, records it, resumes the lane (HELD ⇒ kept coordinator-side as answer_pending, last write wins); `lane-answer <lane_dir> --deliver-pending --owner-command '<cmd>'` delivers a kept answer (the coordinator's poll)
#   lane-remove      <lane_dir> [--stop] [--abandon]    # parallel-automate/05: delegated to automate-lanes.sh — guarded removal (fail-CLOSED refusals; salvages first)
#   lane-convert-ready <lane_dir>                       # parallel-automate/05: delegated to automate-lanes.sh — wave end: a stopped lane's ready_for_release ⇒ awaiting_merge (current-set) + metadata push (its non-claim files by exact list, the rest through trail-pr --reason wave-end's evidence gate); refusal exit 1, failed push exit 2
#   lane-info        [--root <dir>]                     # parallel-automate/05: delegated to automate-lanes.sh — prints .supervisor/lane.json; exit 1 when absent (not a lane)
#   init-check       --parallel N [--auto-merge]        # parallel-automate/05: delegated to automate-lanes.sh — INIT refusals: `ok` | `refuse: <reason>` (exit 1)
#   pick-guard       <automate_dir>                     # parallel-automate/05: delegated to automate-lanes.sh — PICK guard: `ok` | `refuse: live_lane <run_id> <lane>` (exit 1)
#   branch-check     <lane_dir> <branch>                # parallel-automate/05: delegated to automate-lanes.sh — remote branch-name check; prints the name to use (suffix -L<n>) or refuses
#   lane-status      [<parent_runfile>] [--json] [--watch] [--leaks [--snapshot]] [--resources | --tokens]  # parallel-automate/05: delegated to automate-lanes.sh — one line per lane (state, item, PR, question, CI slot, readiness); --json adds machine state; fail-SAFE observer (exit 0)
#   lane-feed        <lane_dir|L<n>> [--follow]         # parallel-automate/05: delegated to automate-lanes.sh — readable narration of the lane's stream log
#   lane-readiness   <lane_dir|L<n>>                    # parallel-automate/05: delegated to automate-lanes.sh — writes <run_id>.merge-readiness.md (PASS/FAIL/NOT-RUN per check; advisory, never merges)
#   lane-park-notify <runfile>                          # parallel-automate/24: delegated to automate-lanes.sh — a lane's ready_for_release park notify: desktop + `automate_ready_for_release` webhook ("do not merge yet — wave open"), both fail-SAFE, + one ## Progress line naming what each channel actually delivered; always exits 0
#
# Exit codes: 0 success; 1 generic failure; 2 abort (malformed pre-existing config, §7);
# 3 progress-append's `current_not_set` guard (the line WAS appended; ## Current was never set).
# (learning-emit, brief-repair, reconcile-status, escalation-cause, meta-entry and meta-push-failed are the fail-SAFE
# exceptions: they ALWAYS exit 0 — never die/abort; meta-entry's verdict line carries the outcome.)
#
# TEST SEAM (tests only — never set it in a real run): LOOMWRIGHT_META_SYNC_BIN names the meta-sync
# script `meta-entry` invokes (default: the sibling meta-sync.sh). (automate-lanes.sh forwards its own
# meta-sync path to `trail-pr` through it — the same sibling in a real run; see _lanes_meta_trail.)
# It selects WHICH pull runs, never the mode — the mode is always read from `setup-memory.sh mode`.
# test-automate-helpers.sh uses it for mutation control (i): a pull stand-in that exits 0 on a fetch
# failure must turn its "abort, nothing created" assertion red.

set -euo pipefail

JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
GH="${LOOMWRIGHT_GH_BIN:-gh}"

NL_CHAR='
'

die()   { echo "automate-helpers: $*" >&2; exit 1; }
abort() { echo "automate-helpers: ABORT: $*" >&2; exit 2; }

# >>> family-file loader (_ah_source / _ah_bundle) — dispatcher-only, belongs to no family
# The helper families live in automate-helpers.d/<name>.sh (parallel-automate/11). Each is sourced
# by ONE `_ah_source <name>` line between `# >>> automate-helpers.d/<name>.sh` and
# `# <<< automate-helpers.d/<name>.sh` markers, at the position its text held when this was a
# single file, so `_ah_bundle` (this script with each such line replaced by the family's text)
# reproduces that file's line order. `--help` greps the bundle (the subcommand list above plus a
# few `#   ` comment lines inside the families), and test-automate-helpers.sh runs it as one file.
# Listed by name, never globbed: a stray file in automate-helpers.d/ is never sourced.
# A missing or unreadable family file fails CLOSED (exit 1, the file named), never a silent no-op.
# `$0` stays this dispatcher, so every `$(dirname "$0")` sibling lookup is unchanged.
_ah_source() {
  local _ah_f
  _ah_f="$(dirname "$0")/automate-helpers.d/$1.sh"
  { [ -f "$_ah_f" ] && [ -r "$_ah_f" ]; } || die "missing family file: automate-helpers.d/$1.sh"
  . "$_ah_f"
}
# _ah_bundle [<dispatcher>] — print <dispatcher> (default: this script) with every `_ah_source <name>`
# line replaced by automate-helpers.d/<name>.sh read from beside it. Self-contained (the test harness
# evals this one function): a missing, unreadable or empty family file prints one stderr line naming
# it and exits 1.
_ah_bundle() {
  local _ah_d="${1:-$0}"
  AH_FAM="$(dirname "$_ah_d")/automate-helpers.d" awk '
    /^_ah_source [a-z][a-z-]*$/ {
      f = ENVIRON["AH_FAM"] "/" $2 ".sh"; n = 0
      while ((r = (getline l < f)) > 0) { print l; n++ }
      close(f)
      if (r < 0 || n == 0) { print "automate-helpers: missing family file: automate-helpers.d/" $2 ".sh" > "/dev/stderr"; exit 1 }
      next
    }
    { print }
  ' "$_ah_d"
}

# <<< family-file loader
# >>> automate-helpers.d/config.sh
_ah_source config
# <<< automate-helpers.d/config.sh
# >>> automate-helpers.d/runfile.sh
_ah_source runfile
# <<< automate-helpers.d/runfile.sh
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

# >>> automate-helpers.d/intake.sh
_ah_source intake
# <<< automate-helpers.d/intake.sh
# >>> automate-helpers.d/resume.sh
_ah_source resume
# <<< automate-helpers.d/resume.sh
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

# >>> automate-helpers.d/learning.sh
_ah_source learning
# <<< automate-helpers.d/learning.sh
# >>> automate-helpers.d/reconcile-status.sh
_ah_source reconcile-status
# <<< automate-helpers.d/reconcile-status.sh
# >>> automate-helpers.d/escalation.sh
_ah_source escalation
# <<< automate-helpers.d/escalation.sh
# --------------------------------------------------------------------------- #
# dispatch
# --------------------------------------------------------------------------- #

# >>> automate-helpers.d/meta.sh
_ah_source meta
# <<< automate-helpers.d/meta.sh
# >>> automate-helpers.d/plan-waves.sh
_ah_source plan-waves
# <<< automate-helpers.d/plan-waves.sh
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
    current-escalation) current_escalation "$@" ;;
    current-wave)    current_wave "$@" ;;
    escalation-cause) escalation_cause "$@" ;;
    closeout-classify) closeout_classify "$@" ;;
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
    finalize-empty) exec bash "$(dirname "$0")/automate-trail.sh" "$cmd" "$@" ;;
    closeout-others) exec bash "$(dirname "$0")/automate-trail.sh" "$cmd" "$@" ;;
    # Dismissed-finding drafts (propose-only writes, never git) — the sibling
    # automate-dismissed.sh, the second carve-out named in the header.
    dismissed-drafts)  exec bash "$(dirname "$0")/automate-dismissed.sh" "$cmd" "$@" ;;
    dismissed-decide)  exec bash "$(dirname "$0")/automate-dismissed.sh" "$cmd" "$@" ;;
    dismissed-pending) exec bash "$(dirname "$0")/automate-dismissed.sh" "$cmd" "$@" ;;
    dismissed-cost)    exec bash "$(dirname "$0")/automate-dismissed.sh" "$cmd" "$@" ;;
    # Lane lifecycle for `/automate --parallel N>1` only — the sibling
    # automate-lanes.sh, the third carve-out named in the header.
    lane-create|lane-launch|relay-hook|lane-answer|lane-remove) exec bash "$(dirname "$0")/automate-lanes.sh" "$cmd" "$@" ;;
    lane-convert-ready) exec bash "$(dirname "$0")/automate-lanes.sh" "$cmd" "$@" ;;
    lane-info|init-check|pick-guard|branch-check) exec bash "$(dirname "$0")/automate-lanes.sh" "$cmd" "$@" ;;
    lane-status|lane-feed|lane-readiness|lane-park-notify) exec bash "$(dirname "$0")/automate-lanes.sh" "$cmd" "$@" ;;
    ""|-h|--help)
      _ah_bundle | grep -E '^#   [a-z]' | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
