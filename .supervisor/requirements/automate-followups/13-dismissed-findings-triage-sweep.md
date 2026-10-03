# 13 — One-time triage sweep: re-check every dismissed finding from run automate-2026-09-26-115755 against `main`, fix what is still open and cheap, draft the rest

## Status: pending

> **Origin (2026-09-29).** Companion to item 12. Item 12 stops NEW dismissed findings from being lost; this item
> recovers the ones already lost. A scan of the `<!-- loomwright:dismissed -->` comments on every PR in run
> `automate-2026-09-26-115755` found ~19 dismissed findings that no requirement, memory or run file tracks, plus
> four follow-ups surfaced during item 10's close-out. Later items may already have fixed some of them — this is
> UNVERIFIED, which is why the sweep re-checks each one against `main` before acting.

## Problem
Findings that a reviewer (Phase 4.5 `code-reviewer` or the `claude-review` bot) raised but that fell below the fix
floor were posted as PR comments and then forgotten. At least one real inaccuracy is already on `main` (the
v15.113.0 CHANGELOG entry). Nobody knows which of the rest are still true.

## Goal
Every finding below is classified against `main` as **still-open / already-fixed / not-a-defect**, with evidence;
the still-open ones are either fixed in this item (when small and inside one lane) or written as a draft in
`proposed/` for a human to promote. The owner signs off the classification before any fix lands.

## The findings (verbatim text lives in each PR's dismissed-findings comment — quote from there, not from here)

**PR #288 — item 03 (resume-glob / `is_run_file`)**
1. `is_run_file` matches only the exact `^# Automate Run:` form; a run file whose title differs in
   whitespace/case/BOM is hidden from RESUME (and `build-handoff.sh` reads the same predicate).
2. SKILL §3 / `RESULT_SCHEMAS` §AUTOMATE_RUN say sidecars are *never* listed; that holds only while a sidecar carries
   no `# Automate Run:` line anywhere (the title is matched anywhere in the file) — wording overclaims.

**PR #296 — item 07 (rules that gate)**
3. `gate-eval` condition 7 judges the working tree at `--root` without pinning `HEAD == live_head` or a clean tree.
4. "Sole gating signal" / "`heal_decision` derives ONLY from `CODE_REVIEW_RESULT`" still stated on
   `commands/supervisor.md` (`--red-team`, `--multi-voter-heal` rows), `docs/FAILURE_ESCALATION.md` and a
   self-heal-advisory R1 parenthetical — stale since the rules co-gate.
5. CLAUDE.md D3 sentence ("unstamped parks only when ≥1 countable must-check exists") predates the countable-set
   drift park (e6f90eb).
6. A `fail` that turns `unstamped` mid-loop (fixer edits a bound file) is silently cleared at Phase 4.5 / drain,
   while the merge gate still parks `rules_unstamped`.
7. `rules_unstamped` PARK text says "never confirmed" / can print "0 countable" in the drift case.
8. Phase 4.5 `rules_check_line` has no `cmd_disabled` branch for an ambient `RULES_CHECK_NO_CMD=1`.
9. `automate-loop` §10 cond-7 dormancy limit doesn't mention corrupt-store ⇒ unreadable / drifted stamp ⇒ unstamped
   with zero countable rules.
10. CLAUDE.md restates "ALL SEVEN" while secondary surfaces were converted to pointers (count claim — house rule).
11. AC9(b) literal wording vs the stronger two-mutant implementation (owner acknowledgement only — likely drop).

**PR #301 — item 10 (rules reach every review)**
12. **CHANGELOG v15.113.0 overclaims** "every round of the owned `--until-mergeable` drain" spawned a rule-blind
    reviewer; the drain is heal-only (only the Earned Fallback Review spawns one, at most once per run). Known to
    be on `main` — fix.
13. `test-rules-seams.sh` (B) pins `rules-check.sh` only; an `audit-rules.sh` mention in `agents/code-reviewer.md`
    would pass (AC3's second half unpinned).
14. Step 4a in `agents/code-reviewer.md` adds `REVIEW.md` to the subordination clause while saying "same contract as
    Phase 4.5, by pointer" (Phase 4.5 names CLAUDE.md only) — nit.
15. `session-resume.sh`'s real reader call (`bash "$reader"`) never names `read-rules.sh`, so (C) never inspects the
    ONLY seam that executes the reader (pre-existing, MEDIUM).
16. `seam_c_is_sink` requires `| bash`/`| sh` with a space — `|bash`, `| zsh`, `|& bash`, `. <(…)` pass (pre-existing).

**Surfaced during item 10's close-out (not in a PR comment)**
17. Telemetry issue #302 counted `high: 1, medium: 0, low: 0` for a review that raised 1 HIGH + 1 MEDIUM + 1 LOW +
    1 nit — the telemetry scorer appears to drop non-HIGH findings (untraced; investigate the SubagentStop telemetry
    path before calling it a bug). Also decide whether the four open `[Telemetry] code-reviewer … Failed: true`
    issues (#282, #287, #297, #302) — each a review that correctly caught a defect — should be closed.
18. (Sidecar shape check — folded into item 11 scope (c); listed here only so the sweep does not re-draft it.)

(PR #299's one dismissed MEDIUM was already fixed in d3fa40f on owner direction — exclude.)

## Scope
- **(a) Classify** each of 1–17 against `origin/main`: still-open / already-fixed (cite the commit) / not-a-defect
  (cite why). Present the table to the owner via `AskUserQuestion` for sign-off before fixing anything.
- **(b) Fix now** the still-open items that are doc/prose-only or a test-only change in one lane (expected: 2, 4, 5,
  7, 9, 10, 12, 13, 14, 16 if still open), in ONE PR, with version bump + CHANGELOG per the release convention.
- **(c) Draft** the rest (expected: 1, 3, 6, 8, 15, 17 — behavioural or security-relevant) as individual files in
  `.supervisor/requirements/proposed/`, each quoting its finding and PR, for the owner to promote.

## Acceptance criteria
- [ ] A classification table covering all 17 items, each with evidence (file + descriptive anchor or commit SHA),
      approved by the owner before any fix commit.
- [ ] Item 12 (CHANGELOG) is corrected on `main`.
- [ ] Every "fix now" item is fixed in one PR; its own checks (doc-currency, citation-drift, `test-rules-seams.sh`,
      command-sync) green; full test loop green.
- [ ] Every "still-open but not fixed" item exists as a `proposed/` draft; nothing is enqueued automatically.
- [ ] Each "already-fixed"/"not-a-defect" verdict names its evidence — none is asserted from memory.

## Out of scope
- Other runs' dismissed findings (earlier `/automate` runs) — decide after this sweep whether a wider sweep is worth it.
- The engine mechanism (item 12) and the trail step (item 11).

## Risks
- **Stale premises.** Items 2–10 came from reviews of now-merged code that later items touched; each must be
  re-read on `main`, not assumed.
- **Scope creep.** Behavioural findings (3, 6, 15) are tempting to fix inline; they go to `proposed/` unless the
  owner explicitly promotes them in the sign-off.

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-01T02:21:42Z
- **Brief:** .supervisor/jobs/done/2026-10-01-dismissed-findings-triage-sweep.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/319
