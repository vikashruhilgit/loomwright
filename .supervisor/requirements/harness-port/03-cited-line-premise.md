# 03 — Cited-line premise check (Launch Pad Phase 3 + Supervisor Phase 1.5 signal (d)), advisory


## Problem
Nothing checks whether a defect a goal or requirement describes is still visible at the `path:line` it cites.
`skills/preflight-sync/SKILL.md` classifies CLEAR/OVERLAP/SUPERSEDED from file overlap (a), merged-equivalent (b)
and churn count (c) only. A brief can be planned against a premise a merged commit already changed — the same
family as the v13.1.0→v14.0.0 stale-branch incident, one level down (the file is right, the line is stale).

## Goal
Every `path:line` reference in the goal/requirement is resolved against `origin/$BASE_BRANCH`, a ±4-line excerpt is
judged by the running model, and the verdict is recorded in the brief and in the Phase 1.5 summary — **advisory by
construction**: it cannot change CLEAR/OVERLAP/SUPERSEDED, cannot cause `unverified`, cannot move PASS → NEEDS_HUMAN
on its own, and is byte-absent when the input cites nothing.

## Scope
1. **Reference extraction (shared wording in both surfaces).** A ref is a token matching
   `<path>:<digits>` where `<path>` contains a `/` OR ends in `.<ext>` (1–8 alnum chars) immediately before the
   `:` — the PATH predicate rejects `2026-01-01T10:00`, `host:8080`, `ratio 3:1`, `12:15 UTC`. Optional
   `-<digits>` range suffix accepted (use the first line). Strip trailing markdown punctuation. Deduplicate.
2. **Resolution.** `git show "origin/$BASE_BRANCH:<path>"`; when `<path>` is partial, resolve by UNIQUE suffix
   match against `git ls-tree -r --name-only "origin/$BASE_BRANCH"` — zero or >1 matches ⇒ `resolves: no`. Capture
   lines `N-4..N+4`. If the described defect/phrase is not in the window, search that file once for the ticket's
   named symbol or quoted phrase before judging (a moved line is `HOLDS (moved to <line>)`, not STALE).
3. **Judgment** is made by the running model from the excerpt alone — no sub-agent, no external CLI:
   `HOLDS` (the described condition is present), `STALE` (the file exists, the condition is absent from the window
   and the symbol/phrase search finds nothing), `UNCLEAR` (cannot tell from the excerpt). `resolves: no` rows carry
   `premise: UNCLEAR`.
4. **Honest age column (decision H6).** Each row carries `as of: tip <git log -1 --format=%cr origin/$BASE_BRANCH>,
   fetched <age>` where `<age>` is derived portably from `find .git/FETCH_HEAD -mmin +1440` (⇒ `>1d`) /
   `-mmin +60` (⇒ `>1h`) / else `<1h`; when `.git/FETCH_HEAD` is absent, `fetched: never`. Launch Pad adds NO
   `git fetch` — it makes no network calls today and this item does not change that. No `stat`, no `date -d`/`-j`.
5. **`loomwright/agents/launch-pad.md` Phase 3 ANALYZE** — new action (append after the last existing action; do
   not renumber): run steps 1–4 over the goal string / resolved requirement file; when ≥1 ref, emit
   `### Cited-line premise check` under the Phase 3 output with a table `ref | resolves | premise | deciding line
   | as of`; when 0 refs, emit NOTHING (no heading, no "none" line — same wording as `Source requirement`). Carry
   any STALE row to Phase 5 Risk Assessment as a MEDIUM row `source: "Cited-line premise (Phase 3)"` — a RISK row,
   not a Plan Reviewer finding. Update the `## Output Format (Complete Example)` only if an example is added;
   otherwise leave it.
6. **`loomwright/skills/supervisor-readiness/SKILL.md`** brief template: document the optional
   `### Cited-line premise check` subsection (under the Phase-3-derived section the template already has) with
   the omit-when-empty rule.
7. **`loomwright/skills/preflight-sync/SKILL.md`** — signal **(d)**, placed after (c), ADVISORY ONLY with the same
   sentence structure (c) uses ("MUST NOT, by itself, change the CLEAR | OVERLAP | SUPERSEDED classification …
   never turns a CLEAR into an OVERLAP, never triggers the AskUserQuestion soft-gate, never contributes to a
   `preflight_overlap_detected` abort"). Ordering + budget rule (decision H5): (d) runs LAST, after (a), (b), the
   corroboration control and (c); it is ONE batched Bash call (a single `for ref in …; do git show …; done`
   loop); if fewer than 1 call of the ≤6 budget remains it is SKIPPED silently and the summary says
   `premise_check=skipped_budget`; it can never be the cause of `preflight_sync = unverified`. Record the row
   count in the summary/Decisions Log rationale (e.g. `premise_check=3 refs, 1 STALE`).
8. **`loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Supervisor Phase 1.5 PRE-FLIGHT SYNC budget":** add the (d)
   call to the accounting (common path unchanged when no refs; +1 when refs exist and budget allows).
9. **`loomwright/agents/plan-reviewer.md` Criterion 1** — one sub-check sentence (no new criterion, no renumber):
   when the brief has a `### Cited-line premise check` with a STALE row, record a **LOW** `file_path` finding
   naming the ref; the text states verbatim: "A STALE premise row is advisory; on its own it never moves the
   decision from PASS to NEEDS_HUMAN or FAIL." Re-measure plan-reviewer (777 headroom).
10. **Docs:** CHANGELOG paragraph; version bump; `check-doc-currency.sh` green.

## Non-goals
No `git fetch` in Launch Pad. No change to the CLEAR/OVERLAP/SUPERSEDED inputs (a)/(b). No new agent, no new
sub-agent spawn. No change to Plan Reviewer's Decision Matrix. No attempt to re-resolve refs inside code fences.

## Acceptance criteria
- Fixture goal citing `loomwright/scripts/automate-helpers.sh:244` with the description "matches only done" ⇒ HOLDS
  row; the same goal against a fixture repo where the line was removed ⇒ STALE row with both age fields.
- Fixture goal containing only `2026-01-01T10:00`, `host:8080`, `3:1`, `12:15 UTC` ⇒ no rows, no heading.
- **Byte-identity:** a goal with zero refs produces a brief identical to `origin/main`'s Launch Pad output for the
  same goal, modulo `Base commit` (fixture diff test recorded in the PR body with the diff command used).
- Phase 1.5: with 5 refs and a budget already at 5 calls, the summary shows `premise_check=skipped_budget` and
  `preflight_sync` is whatever (a)/(b) produced — never `unverified` because of (d). Trace both paths in the PR.
- `grep -n 'never moves the decision from PASS to NEEDS_HUMAN' loomwright/agents/plan-reviewer.md` = 1;
  Criterion count stays 16; Decision Matrix unchanged vs `origin/main`.
- `grep -nE 'git fetch' loomwright/agents/launch-pad.md` → 0; `grep -nE 'stat -|date -d|date -j' <changed files>` → 0.
- `check-token-budget.sh`, `check-doc-currency.sh`, full test loop + root checks green.

## Verified premises (re-check before starting)
- `preflight-sync/SKILL.md`: Bounded budget paragraph (≤6 calls; cap reached ⇒ `unverified`); signals (a)/(b)
  and the advisory-only (c) wording; the corroboration-control accounting.
- `launch-pad.md` Phase 3 action list (0, 0a, 0b, 1–9), Phase 5 step 3a `Source requirement` wording, and the
  absence of any `git fetch`.
- `plan-reviewer.md` Criterion 1 body + Decision Matrix rows ("Only MEDIUM/LOW issues, but design approach is
  ambiguous → NEEDS_HUMAN").
- FETCH_HEAD-mtime ≠ `%cr` tip age (observed 14:10 vs "5 hours ago" on 2026-09-21).

## Status: done (PR #262, merge 076a18c)
- **Completed:** 2026-09-26T02:14:56Z
- **Brief:** .supervisor/jobs/done/2026-09-24-cited-line-premise.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/262
