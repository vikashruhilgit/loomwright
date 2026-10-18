# ---- consent disclosure (the exact copy the command layer must show BEFORE applying) --------
print_consent_disclosure() {
  # BRANCH MODE (the block apply writes / check reads names a metadata branch): the default copy
  # below would promise that run history and the ledger become committable here — false for this
  # block. Only the two memory stores are un-ignored; everything else is the branch's.
  if [ -n "${EFFECTIVE_BRANCH:-}" ]; then
    print_consent_disclosure_branch_mode
    return 0
  fi
  cat <<'DISCLOSURE'
What becomes VERSION-CONTROLLED if you apply this:
  · .claude/agent-memory/**   — every agent's persistent store (MEMORY.md + entry files +
                                 .provenance.jsonl sidecars)
  · .supervisor/memory/**     — distilled LESSONS.md / PROJECT_MEMORY.md + their
                                 .lessons-provenance.jsonl sidecars
  · .supervisor/requirements/** — the intake: every requirement file a queue was built from
  · .supervisor/jobs/done/**, .supervisor/jobs/failed/** — every brief that reached a terminal
                                 state (pending/ and in-progress/ stay ignored: in-flight state)
  · .supervisor/automate/*.md — one run file per /automate run (queue, per-item outcome,
                                 park reasons); the *.config-backup.json sidecars stay ignored
  · .supervisor/postmortem/results.jsonl — the findings ledger (PR-churn analysis), and ONLY this
                                 one file; everything else under .supervisor/postmortem/ stays
                                 ignored. GATED: it is un-ignored only while every record's
                                 `.repo` is inside this repo's allowlist. If any record is not,
                                 the negation is WITHHELD, the offending slugs are named, and
                                 readiness reports `gated`.
                                 The allowlist seeded into .supervisor/config.json (gitignored,
                                 it does not travel) is the current remote PLUS the GRANTED
                                 entries of the tracked request file .agent/meta-allowlist.txt —
                                 an entry there is only a REQUEST, granted only when
                                 `gh api repos/<slug> --jq .id` equals origin's id (a renamed
                                 repo's old slug), and only for a github.com origin. gh is
                                 OPTIONAL: missing, failing or past its time bound
                                 (LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT, default 10s), no request
                                 entry is granted. At most 20 request entries are checked
                                 (LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES); later ones are not granted.
These are COMMITTED IN PLACE — nothing is moved, symlinked or copied, so every agent keeps
reading its store from the same path it uses today.

Read this before saying yes:
  · Committing publishes. Agent memory can contain proprietary architecture, internal service
    names, client detail, or anything an agent inferred while working. It travels wherever the
    repo travels — a PUBLIC repo publishes it to everyone, and so does any fork or clone.
  · Removal does NOT unpublish. `/setup memory remove` stops FUTURE tracking; anything already
    committed and pushed stays in git history and on every remote that has it.
  · Writes become working-tree changes. Once tracked, memory writes show in `git status` and can
    be swept into an unrelated commit by `git add -A`; MEMORY.md becomes a merge-conflict surface
    when parallel workers write it.
  · THE LEDGER IS CROSS-REPO BY CONSTRUCTION. A `/pr-postmortem` append lands in the CURRENT
    working `.supervisor/`, never in the analysed repo's, so a ledger accumulates records
    belonging to OTHER repos. The allowlist gate refuses to un-ignore a ledger holding any such
    record — but it is evaluated AT APPLY TIME ONLY. A ledger that gains a foreign record AFTER a
    clean apply stays un-ignored until the next apply, and a routine `git add -A` can commit it in
    between. Run `setup-memory.sh filter-ledger --ledger .supervisor/postmortem/results.jsonl`
    before you commit. The gate is not complete coverage, and it does not look at finding TEXT —
    only at each record's `.repo` field.
  · THE TRAIL IS PROSE, AND PROSE IS NOT GATED. Requirement files and briefs are written by
    people and agents about THIS repo, but they quote whatever was on screen: another repo's
    name and PR numbers, a login line from a CLI, an absolute path with your username. The
    allowlist gate reads the ledger's `.repo` field and nothing else — it does not read a brief.
    Skim `.supervisor/requirements/` and `.supervisor/jobs/done/` before the first commit of a
    PUBLIC repo; `grep -rEn "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[a-z]{2,}" .supervisor/requirements
    .supervisor/jobs` finds the e-mail case.
What stays IGNORED (unchanged): .claude/worktrees/, .claude/settings.local.json,
.supervisor/logs/, .supervisor/jobs/pending/ and in-progress/, .supervisor/automate/*.config-backup.json,
any `.supervisor/` tree nested inside a requirements folder, every file under
.supervisor/postmortem/ OTHER than results.jsonl, and everything else under .claude/ and
.supervisor/ — the third store is that ONE FILE, not a directory, so nothing else in
.supervisor/postmortem/ is included by it.
DISCLOSURE
}

# print_consent_disclosure_branch_mode — the BRANCH-MODE disclosure. The branch name is printed with
# printf, never interpolated into a heredoc (a ref may legally carry characters a shell would act on).
print_consent_disclosure_branch_mode() {
  printf 'What becomes VERSION-CONTROLLED if you apply this (BRANCH MODE — metadata branch `%s`):\n' "$EFFECTIVE_BRANCH"
  cat <<'DISCLOSURE'
  · .claude/agent-memory/**   — every agent's persistent store (MEMORY.md + entry files +
                                 .provenance.jsonl sidecars)
  · .supervisor/memory/**     — distilled LESSONS.md / PROJECT_MEMORY.md + their
                                 .lessons-provenance.jsonl sidecars
These are COMMITTED IN PLACE — nothing is moved, symlinked or copied, so every agent keeps
reading its store from the same path it uses today.
DISCLOSURE
  printf 'Run history is NOT committed on this branch. .supervisor/requirements/**, .supervisor/jobs/done/**,\n'
  printf '.supervisor/jobs/failed/**, .supervisor/automate/*.md and the findings ledger\n'
  printf '.supervisor/postmortem/results.jsonl stay IGNORED here — meta-sync.sh syncs them to the metadata\n'
  printf 'branch `%s`, so there is nothing to commit for run history on this branch (and the\n' "$EFFECTIVE_BRANCH"
  cat <<'DISCLOSURE'
repo-allowlist ledger gate does not apply: the ledger is never un-ignored here).
Run history ALREADY committed on this branch stays tracked — switching only rewrites .gitignore.
Untracking it is a separate, deliberate operator step (migrate-branch-mode.sh plan), never this
helper: it never runs git add / git rm / git commit.
meta-sync.sh's push scrub still refuses any ledger record or forge slug outside the repo
allowlist. .supervisor/config.json (gitignored) does not travel; on a clone without it the
allowlist is the current remote PLUS the GRANTED entries of the tracked request file
.agent/meta-allowlist.txt — an entry there is only a REQUEST, granted only when
`gh api repos/<slug> --jq .id` equals origin's id, and only for a github.com origin. gh is
OPTIONAL: missing, failing or past its time bound (LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT, default 10s),
no request entry is granted and the scrub uses the remote alone. At most 20 request entries are
checked (LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES); later ones are not granted.

Read this before saying yes:
  · Committing publishes. Agent memory can contain proprietary architecture, internal service
    names, client detail, or anything an agent inferred while working. It travels wherever the
    repo travels — a PUBLIC repo publishes it to everyone, and so does any fork or clone.
  · Removal does NOT unpublish. `/setup memory remove` stops FUTURE tracking; anything already
    committed and pushed stays in git history and on every remote that has it.
  · Writes become working-tree changes. Once tracked, memory writes show in `git status` and can
    be swept into an unrelated commit by `git add -A`; MEMORY.md becomes a merge-conflict surface
    when parallel workers write it.
  · The metadata branch publishes too. Every remote that receives it gets the run history on it,
    and requirement files and briefs quote whatever was on screen.
LEARNING STORES — a SEPARATE consent, asked once after this apply. meta-sync.sh can also carry
  · .supervisor/twin/contracts/*.md + .supervisor/twin/.provenance.jsonl — System Twin contracts
                                 and their provenance chain
  · .supervisor/agent-memory-proposals/*.md — proposed agent-memory entries
  · .supervisor/eval/results.jsonl, .supervisor/eval/brain-baseline.jsonl — eval history
to the metadata branch. They hold the agents' internal reasoning about this codebase, and the
push scrub only pattern-checks them (e-mail, home paths, tokens, forge slugs, deny patterns) — it
cannot recognise proprietary prose. They are published ONLY when you record consent for this repo
(`setup-memory.sh consent grant`; `consent decline` records a no; `consent status` reads it). The
record lives in your user scope, ~/.claude/loomwright/meta-sync-consent.json, keyed by this repo's
origin — a repo file can never grant it. Without a `granted` record every push skips them and names
each one (`learning_skipped`); a pull still brings them in from the branch. A learning-store file
this repo TRACKS in git is left to git: no pull or push touches it (`learning_tracked`).
What stays IGNORED here: .claude/worktrees/, .claude/settings.local.json, .supervisor/logs/,
.supervisor/jobs/pending/ and in-progress/, every run-history path above (the ledger included),
any nested `.supervisor/` tree, and everything else under .claude/ and .supervisor/.
DISCLOSURE
}

# ---- report render (shared by check + apply/remove verify) ------------------
#
# render_report also PUBLISHES its conclusion into three globals so a caller can react to it without
# re-deriving (or re-guessing) the verdict:
#   $REPORT_VERDICT             — the readiness verdict string
#   $REPORT_BLOCKED_INTENDED    — newline-separated INTENDED paths that came back `ignored`
#                                 (UNDER-inclusion: a surviving exclude beats the negation)
#   $REPORT_LEAKED_UNINTENDED   — newline-separated UNINTENDED paths that came back `committable`
#                                 (OVER-inclusion: an over-broad `!` re-include; the `partial` case)
#   $REPORT_GATED / $REPORT_GATED_SLUGS
#                               — yes/no plus the offending repo slugs when the findings-ledger gate
#                                 REFUSED (the `gated` case: deliberately withheld, repo contaminated)
#
# THREE FAILURE MODES NOW, AND NONE OF THEM MAY SHARE COPY. `not configured` is UNDER-inclusion,
# `partial` is OVER-inclusion, and `gated` is a DELIBERATE withholding — a correct outcome, not a
# defect in the ignore rules. Handing a gated repo the under-inclusion remedy ("comment out the
# surviving exclude") would tell the user to delete this module's OWN `.supervisor/*` line, which is
# precisely the wrong fix. Hence the dedicated verdict class and the dedicated warning branch.
# The two lists are DISJOINT failure modes with opposite remedies, which is exactly why they are
# published separately — warn_if_not_configured() must never hand out under-inclusion guidance
# ("comment out the surviving exclude") for an over-inclusion failure, where there is no surviving
# exclude to name and commenting one out would make it worse.
# This must run in the CURRENT shell — every existing call site already does.
REPORT_VERDICT=""
REPORT_BLOCKED_INTENDED=""
REPORT_LEAKED_UNINTENDED=""
REPORT_GATED=""
REPORT_GATED_SLUGS=""
# $REPORT_UNEXAMINED / $REPORT_UNEXAMINED_REASON — yes/no plus the could-not-examine reasons. HELD
# SEPARATELY FROM $REPORT_GATED_SLUGS ON PURPOSE: those are observed foreign repo slugs and these are
# "we could not look". They take DIFFERENT remedies — `filter-ledger` is right for a foreign record
# and actively destructive for an unreadable ledger (`filter-ledger > tmp && mv tmp ledger` on a file
# jq cannot open truncates it to zero bytes).
REPORT_UNEXAMINED=""
REPORT_UNEXAMINED_REASON=""

render_report() {
  local gate mb p st _r intended_ok=yes unintended_ok=yes probed=0 unknowns=0

  REPORT_VERDICT=""
  REPORT_BLOCKED_INTENDED=""
  REPORT_LEAKED_UNINTENDED=""
  REPORT_GATED="no"
  REPORT_GATED_SLUGS=""
  REPORT_UNEXAMINED="no"
  REPORT_UNEXAMINED_REASON=""

  gate="$(gitignore_gate)"
  mb="$(managed_block_present)"

  echo "Memory store report for: $repo"
  echo "  .gitignore:        $gate"
  echo "  managed block:     $([ "$mb" = "yes" ] && echo present || echo absent)"

  # BRANCH MODE (the mode of the file ON DISK, via the one reader): the run-history probes — and the
  # findings ledger — move from the must-be-committable set to the must-stay-ignored set, so a
  # branch-mode block reads as `configured`, not as drift. Keyed on the DISK mode, never on
  # $EFFECTIVE_BRANCH, so the post-write verify of `apply --branch-mode off` / `remove` reports the
  # block that is actually there. The ledger gate is NOT consulted in branch mode: the block never
  # un-ignores the ledger, so `gated` (and its filter-ledger remedy) would describe a write that
  # cannot happen.
  local r_intended="$INTENDED_PATHS" r_unintended="$UNINTENDED_PATHS" r_mode r_branch=""
  r_mode="$(normalize_mode "$(read_mode)")"
  case "$r_mode" in
    off) ;;
    unknown*)
      echo "  branch mode:       $r_mode (a plain apply will refuse — re-run apply with --branch-mode <branch> or --branch-mode off)" ;;
    "on "*)
      r_branch="${r_mode#on }"
      echo "  branch mode:       $r_mode (run history is synced to that branch and stays ignored here)"
      r_intended="$(printf '%s\n' "$INTENDED_PATHS" | grep -vE '^\.supervisor/(requirements|jobs|automate)/')"
      r_unintended="$UNINTENDED_PATHS
$(printf '%s\n' "$INTENDED_PATHS" | grep -E '^\.supervisor/(requirements|jobs|automate)/')
$LEDGER_INTENDED_PATH" ;;
  esac
  echo "  intended (must be committable):"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    st="$(ignore_status "$p")"
    printf '    %-56s %s\n' "$p" "$st"
    probed=$((probed + 1))
    [ "$st" = "unknown" ] && unknowns=$((unknowns + 1))
    [ "$st" = "committable" ] || intended_ok=no
    if [ "$st" = "ignored" ]; then
      REPORT_BLOCKED_INTENDED="${REPORT_BLOCKED_INTENDED}${p}
"
    fi
  done <<EOF
$r_intended
EOF

  # THE THIRD STORE — probed ONLY when the ledger gate PASSES. When it refuses, the ledger is
  # deliberately withheld and must NOT be counted as a blocked intended path (that would make a
  # CORRECT refusal report as `not configured` and emit the destructive under-inclusion remedy).
  # When jq is absent nothing was evaluated, so nothing is claimed either way. And when the negation
  # is PRESERVED (already in the block, gate could not examine the ledger) it IS probed — the line is
  # really there and really governs git — but the report says plainly that it was not re-verified.
  # In branch mode the ledger is listed here for honesty only; it is PROBED in the ignored set below.
  if [ -n "$r_branch" ]; then
    printf '    %-56s %s\n' "$LEDGER_INTENDED_PATH" "branch mode — on $r_branch, stays ignored here"
  elif ledger_negation_in_block; then
    st="$(ignore_status "$LEDGER_INTENDED_PATH")"
    printf '    %-56s %s\n' "$LEDGER_INTENDED_PATH" "$st"
    probed=$((probed + 1))
    [ "$st" = "unknown" ] && unknowns=$((unknowns + 1))
    [ "$st" = "committable" ] || intended_ok=no
    if [ "$st" = "ignored" ]; then
      REPORT_BLOCKED_INTENDED="${REPORT_BLOCKED_INTENDED}${LEDGER_INTENDED_PATH}
"
    fi
    if ! ledger_gate_permits_negation; then
      REPORT_UNEXAMINED="yes"
      REPORT_UNEXAMINED_REASON="$LEDGER_UNEXAMINED_REASON"
      echo "      ^ PRESERVED, not re-verified — the gate could not examine the ledger this run:"
      while IFS= read -r _r; do
        [ -n "$_r" ] || continue
        echo "        · $_r"
      done <<EOF
$LEDGER_UNEXAMINED_REASON
EOF
      echo "        Nothing new is published (this negation was already in place); re-run once the"
      echo "        ledger is readable and jq works to re-verify it."
    fi
  elif ledger_gate_warrants_withdrawal; then
    REPORT_GATED="yes"
    REPORT_GATED_SLUGS="$LEDGER_FOREIGN_SLUGS"
    printf '    %-56s %s\n' "$LEDGER_INTENDED_PATH" "GATED — withheld (records outside the allowlist)"
  elif ledger_gate_blocks_foreign_records; then
    # REFUSED, but on a could-not-examine basis. Withheld all the same (never publish what was not
    # checked) — the copy just may not name slugs it never saw.
    REPORT_GATED="yes"
    REPORT_GATED_SLUGS=""
    REPORT_UNEXAMINED="yes"
    REPORT_UNEXAMINED_REASON="$LEDGER_UNEXAMINED_REASON"
    printf '    %-56s %s\n' "$LEDGER_INTENDED_PATH" "GATED — withheld (the gate could not examine the ledger)"
  else
    printf '    %-56s %s\n' "$LEDGER_INTENDED_PATH" "not probed (jq unavailable — gate not evaluated)"
  fi

  echo "  unintended (must stay ignored):"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    st="$(ignore_status "$p")"
    printf '    %-56s %s\n' "$p" "$st"
    probed=$((probed + 1))
    [ "$st" = "unknown" ] && unknowns=$((unknowns + 1))
    [ "$st" = "ignored" ] || unintended_ok=no
    if [ "$st" = "committable" ]; then
      REPORT_LEAKED_UNINTENDED="${REPORT_LEAKED_UNINTENDED}${p}
"
    fi
  done <<EOF
$r_unintended
EOF

  echo "  tracked today:     .claude/agent-memory/ → $(tracked_count '.claude/agent-memory') file(s), .supervisor/memory/ → $(tracked_count '.supervisor/memory') file(s), $LEDGER_INTENDED_PATH → $(tracked_count "$LEDGER_INTENDED_PATH") file(s)"

  load_allowlist   # in-shell (not a subshell) so $ALLOWLIST_SOURCE is real, not stale
  if [ -n "$ALLOWLIST" ]; then
    echo "  allowlist:         $(printf '%s' "$ALLOWLIST" | tr '\n' ' ') [source: $ALLOWLIST_SOURCE]"
  else
    echo "  allowlist:         (empty) [source: $ALLOWLIST_SOURCE]"
  fi

  # UNKNOWN DOMINATES. Off a git repo every `git check-ignore` returns 128 → every cell is
  # `unknown`, which makes intended_ok=no AND unintended_ok=no and would fall through to
  # `partial (an unintended path is committable …)` — a claim about a state that was never
  # probed. Nothing here may assert an unprobed status, so say so instead.
  local verdict
  if [ "$probed" -gt 0 ] && [ "$unknowns" -eq "$probed" ]; then
    verdict="unknown (not a git repo — ignore status could not be probed)"
    REPORT_BLOCKED_INTENDED=""
    REPORT_LEAKED_UNINTENDED=""
  elif [ "$REPORT_GATED" = "yes" ]; then
    # THE THIRD CLASS. NOT `configured` (the ledger is deliberately withheld) and NOT
    # `not configured` (nothing about the ignore rules is wrong — the repo's LEDGER is contaminated).
    if [ -n "$REPORT_GATED_SLUGS" ]; then
      verdict="gated (the findings ledger is WITHHELD — records outside the allowlist: $(printf '%s' "$REPORT_GATED_SLUGS" | tr '\n' ' '))"
    else
      # NO SLUGS TO NAME — the gate could not examine the ledger. Withheld all the same, but the
      # verdict must not invent contamination it never observed.
      verdict="gated (the findings ledger is WITHHELD — the gate could not examine it: $(printf '%s' "$REPORT_UNEXAMINED_REASON" | tr '\n' ' '))"
    fi
  elif [ "$intended_ok" = "yes" ] && [ "$unintended_ok" = "yes" ]; then
    verdict="configured"
  elif [ "$intended_ok" = "no" ] && [ "$unintended_ok" = "yes" ]; then
    verdict="not configured"
  else
    verdict="partial (an unintended path is committable — review the ignore rules by hand)"
  fi
  REPORT_VERDICT="$verdict"
  echo "Memory readiness: $verdict"
}

# After a write (or a no-op re-apply) the `apply: applied` headline on its own reads as
# unqualified success — but a pre-existing pattern this rewriter does not neutralise (a
# `.claude/agent-memory/**`, a rule in a PARENT .gitignore, or the global excludesfile) can still
# win for the intended paths, leaving a silently dead negation. Qualify the headline, and name the
# rule that actually wins from a REAL probe (`git check-ignore -v`) rather than guessing at it.
#
# THE TWO FAILURE MODES ARE OPPOSITES AND MUST NOT SHARE COPY. `not configured` is UNDER-inclusion
# (an intended path is still ignored → a surviving exclude wins) and its remedy is to comment out or
# re-order that exclude. `partial` is OVER-inclusion (an UNINTENDED path became committable → an
# over-broad `!` re-include wins) and its remedy is to NARROW the re-include; there is no surviving
# exclude to name, so the under-inclusion copy would print a bullet list of nothing and then tell the
# user to comment out a rule that does not exist and whose removal would leak MORE. Hence the
# dedicated branch below, pinned by test-setup-memory.sh group (b4).
#
# print_path_rules <newline-separated paths> — one path per bullet with the pattern that ACTUALLY
# wins for it, from a REAL `git check-ignore -v -n` probe, never a guess. `-n` is required for the
# over-inclusion list: without it check-ignore prints nothing for a path it does not ignore. A path
# that matches NO pattern at all comes back as a bare `::` record, which is reported as such.
print_path_rules() {
  local paths="$1" p src
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    src="$(git -C "$repo" check-ignore -v -n -- "$p" 2>/dev/null | head -n1)"
    case "$src" in
      ''|'::'*) src="(no pattern matches it at all — nothing is ignoring it)" ;;
    esac
    echo "         $p"
    echo "             <- $src"
  done <<EOF
$paths
EOF
}
