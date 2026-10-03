# 02 — Curation cadence: last-run record, session-end reminder, and readiness-aware output

## Problem
The plugin has two halves. One writes things down automatically — every session, PR review, and
worker result is logged with no human involved. The other checks whether what's written is still
true — and that half **only runs when the user personally types a command**.

There is no record of when it last ran. `/dreaming`, `/insights`, and `/pr-postmortem` leave no
last-run trace anywhere (verified: no `.supervisor/dreaming*` artifact, no `last_run` field in
`commands/dreaming.md`). Consequences:
- The noticing depends on the user remembering, and the evidence says it is thin and irregular.
  Measured agent-memory write cadence (mtime, `find -exec stat -t %Y-%m-%d`, sorted numerically):
  **2026-08-04, 2026-07-06, 2026-06-26** — three writes in roughly six weeks, all to a single
  store (`code-reviewer`), none to the other five.
  > **Corrected 2026-08-06.** An earlier draft of this item claimed the last write was
  > **2026-06-26**. That was wrong: it came from `ls -lT | sort | tail`, which sorts month *names*
  > alphabetically (`Aug` < `Jul` < `Jun`), so the August entry was hidden. The point survives in
  > weaker form — the cadence is thin, not dead — and the claim is now stated as measured. Use
  > numeric-sortable dates for any mtime comparison; this is the same BSD/GNU date-handling class
  > already recorded in project lessons.
- A user cannot tell whether running a command now is worthwhile. Running `/dreaming` over 3 new
  findings is noise; running it over 47 is overdue — and today both look identical from outside.
- The commands' output does not say what the run *achieved* or what it will improve, so there is no
  feedback loop that would earn the next run.

## Goal
One durable record of curation cadence; a session-end reminder that carries the **pending count**
(not just a date); and readiness-aware output from all three commands, including an honest
"too early — wait" answer.

## Scope

1. **DERIVE two of the three last-run times; store only the one that cannot be derived.**
   An earlier draft proposed a `curation-state.json` holding `last_run` for all three. Two of those
   would be a **restatement of a fact whose authoritative source already exists** — precisely what
   this repo's one existing rule forbids (`.agent/rules/process.json`: *"a claim lives in exactly ONE
   authoritative place… every other surface derives it at read time"*). Verify each source below
   rather than trusting this table:

   | Command | Last-run source | Action |
   |---|---|---|
   | `/insights` | mtime of `.supervisor/insights/dashboard.md` | **derive** |
   | `/pr-postmortem` | max `.ts` in `.supervisor/postmortem/results.jsonl` | **derive** |
   | `/dreaming` | writes only via the sole writers, so `.supervisor/memory/` mtime reports the last run **that accepted something** — a run where everything was rejected is invisible | **record** |

   So the stored record shrinks to `/dreaming` alone, and exists specifically to capture the
   ran-but-wrote-nothing case. Keep it minimal and **local** (operational cadence, not judgment —
   state that rationale in its header). Absent or malformed ⇒ "never run", never an error, exit 0.

   If a later change gives `/dreaming` its own durable artifact, this record should be retired in
   favour of deriving from that too — note the condition so it does not outlive its reason.

2. **Pending-count computation** — a read-only probe that derives each `*_since` count from data
   already on disk: session logs newer than `last_run`, ledger records newer than `last_run`, merged
   PRs absent from the ledger. Fail-safe: any unreadable input yields `unknown`, never a crash and
   never a fabricated zero.

3. **Session-end reminder.** Surface one line where the user will see it, carrying the count —
   `last dreaming: 34 days ago · 47 new findings since`. The **count is the motivating signal**; a
   bare date is not. Follow the existing SessionStart-nudge conventions (one line, debounced,
   hook-neutral, never blocking) and suppress entirely when nothing is pending. Choose the seam
   deliberately: `SessionStart` already runs `session-resume.sh` + `stamp-requirement-status.sh`,
   and a `Stop` hook exists — verify which actually reaches the user before wiring, do not assume.

4. **Readiness gate in each command.** On invocation, each of the three reports its own readiness
   and may decline: *"only 3 findings since last run — a meaningful pass needs ~15; run anyway with
   `--force`."* Thresholds documented and configurable; declining is advisory, never an error exit.
   **The `~15` is an unvalidated starting guess, not a derived threshold** — say so in the config
   file and in the docs. It should be revisited once item 02 has recorded a few real cadences; do
   not let a placeholder number acquire authority by being restated (the exact failure class this
   queue targets).

5. **Richer run output.** Each run prints: when it last ran · what changed since · what it produced
   this time · **what that will improve**. Ground the last part in real data rather than a slogan —
   e.g. `/dreaming`: *"12 findings → 4 rule proposals, targeting convention_mismatch (66% of your
   self-heal misses)."*

6. **`/insights` may run automatically; the other two may not.** `build-insights.sh` was measured at
   **4.8 s** — acceptable for an async or scheduled run, too slow for a blocking `SessionStart`, and
   wasteful on every trivial session. `/dreaming` and `/pr-postmortem` cost a real session and stay
   explicitly triggered, with the reminder doing the noticing. Re-measure the runtime rather than
   trusting this figure.

## Non-goals
No auto-running of `/dreaming` or `/pr-postmortem`. No writes to any curated store. No new gates —
the reminder and readiness signals are advisory throughout and never block a session, a PR, or a
`heal_decision`.

## Acceptance criteria
- `curation-state.json` is written by all three commands; absent/malformed ⇒ "never run", exit 0.
- Pending counts are computed from real on-disk data and verified against a hand-counted fixture.
- The session-end reminder renders with a real count on this repo, suppresses when nothing is
  pending, and is proven to reach the user at the seam chosen (demonstrated, not assumed).
- Each command declines a too-early run with a reason, and `--force` overrides it — both paths tested.
- Each run's output states last-run, delta, produced, and expected improvement.
- Every new script always exits 0 on every failure path, including missing/corrupt inputs, and has an
  Ubuntu-clean `test-*.sh`.
- Doc-currency / count gates green.

## Outcomes Rubric
- One durable cadence record, fail-safe on absent/malformed
- Reminder carries the pending count and demonstrably reaches the user
- Readiness declines a too-early run; `--force` path tested
- Output explains what the run achieved and what it improves
- `/insights` automation decision justified by a re-measured runtime, not the quoted one

## Follow-up shipped 2026-08-09 (v15.30.0) — three units collapsed into one

Three design gaps survived three rounds of plan review on PR #134 because the readiness gate, the
consumption window and the record lived in different files and **nothing asserted a relationship
between them**. All three were one root cause: one quantity expressed in three units — readiness as
*files newer than a wall-clock stamp*, consumption as *the N most-recent files* (`--sessions`,
default 5), the record as *wall-clock now*. Every conversion lost information.

1. **The record had to become a SET, not a watermark.** This item's §1 says "record", and the
   obvious reading — a `last_run` timestamp — is *provably insufficient*, which is worth stating
   because it is not obvious. `/dreaming` consumes the most-recent N, so what it leaves behind is
   the **older** tail; "pending = newer than T" cannot count an older tail at any T. `T = now`
   retired 56 unread logs here; `T = oldest consumed` re-counts the batch just read and still misses
   the tail. `record dreaming <session_id>…` now stores what was consumed, keyed under
   `.dreaming.consumed.logs` so **item 05's second intake source is a sibling key, not a migration**.
2. **The readiness line names the window** that will drain the count, pinned to `commands/dreaming.md`
   by a cross-file test — the assertion whose absence caused this.
3. **§2's "pending count" now counts reflection signal, not files.** Measured: 29 of 62 logs were
   pure `token_ledger`/`subtask_complete` (~96% of corpus bytes, 0% of signal) — a 1.9× overstatement.
   `/dreaming` and `/insights` get **different** predicates because their consumers genuinely differ.

**These belong to item 02, not item 05** — verified by reading 05 rather than assuming. Item 05 is
output-side (triage → rules → PR) and depends on 03+04; these are intake-side, and the silent-loss
bug fires on the *first* real `/dreaming` run, so it could not wait behind that dependency chain.
The one coupling is handled above (the per-source key).

**Bearing on §4's threshold revisit:** the `~15` guess was being compared against a number that was
both wrong (files, not signal) and non-draining. Any cadence recorded before v15.30.0 is not a valid
input to re-deriving it.

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-08-09-curation-cadence.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
Note the follow-up above: criterion "pending counts verified against a hand-counted fixture" passed in
v15.29.0 while counting the wrong unit — a hand-counted fixture confirms arithmetic, not that the
quantity is the one the consumer acts on.
