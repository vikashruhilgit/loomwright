# 11 — Deterministic subtask ids (split out of item 05 scope-1)

**Provenance.** This is item 05's scope item 1, split out and enqueued on its own per that file's
own instruction: *"The id-determinism half IS a normal code-change item and may be split out and
automated."* The other half of item 05 (the arm-3 re-run) stays OPERATOR-RUN and is NOT in scope
here.

## Problem

Launch Pad's brief format does not pin the subtask id scheme. Given byte-identical input it
sometimes emits `1, 2, 3, 4, 5` and sometimes `1a, 1b, 2`. This is a plain defect, independent of
any evaluation or runner question — downstream consumers expect one style and unpredictable ids
cause real breakage.

Verified state of the three surfaces:

- **Producer is unpinned.** `skills/supervisor-readiness/SKILL.md:220-226` and
  `agents/launch-pad.md:409-415` both *illustrate* numeric ids in the `## Subtask Structure` table
  but neither states a **rule**, so nothing constrains the emitter. `agents/launch-pad.md:762-769`
  (the worked example) is likewise numeric-by-illustration only.
- **Consumer tolerates but does not normalize.** `sdk-spike/src/runner.ts:340` matches ids as
  `/^\|\s*(\d+[a-z]?)\s*\|.../` and `:378` / `:407` accept `subtask_1a:`, `# Subtask 1a`,
  `from: 1`, `from: "1a"`, `from: 1a`. The id is retained verbatim as parsed — an alpha-suffixed id
  stays `1a` downstream. The in-file comment at `:336-339` records the observed consequence:
  *"Launch Pad emits BOTH `1`..`N` and `1a`/`1b` for the same … which is how arm 3 ended up with
  every dependency edge missing."*
- **Fixtures disagree with each other.** `sdk-spike/test/fixtures/mini-brief.md` uses numeric
  (`1`, `2`); `sdk-spike/test/fixtures/launchpad-brief.md` uses `1a`, `1b`, `2`, `10`.

## Goal

One id scheme, stated as a rule at the producer, normalized at the parser, and locked by a test so
it cannot drift back.

## Scope

1. **Pin the scheme to numeric** (`1, 2, 3, …`) — numeric is what the runner's natural-sort
   ordering is built around and what `mini-brief.md` encodes. State it as an explicit **rule**, not
   just an illustration, in `skills/supervisor-readiness/SKILL.md` §"Subtask Structure" and mirror
   it in `agents/launch-pad.md` Phase 4 DECOMPOSE + its brief template. (Agent↔command mirror
   drift is a known trap here — sync `commands/launch-pad.md` in the same change if it carries the
   template.)
2. **Tolerate-but-normalize at the parser.** `sdk-spike/src/runner.ts` must keep accepting a
   legacy `1a`/`1b` brief (do not narrow the regexes — that would hard-fail existing briefs) but
   must **convert** an alpha-suffixed id to the pinned numeric scheme rather than carrying `1a`
   through. Normalization must be applied consistently to BOTH sides of every edge — the table id,
   the `subtask_N:` / `# Subtask N` contract key, and every `from:` reference — or dependency edges
   will dangle, which is the original arm-3 failure mode.
3. **Preserve wave ordering.** The natural-sort at `runner.ts:421-423` exists so `1 < 1a < 1b < 2 <
   10` rather than a plain string sort putting `10` before `2`. Whatever normalization is chosen
   must not reintroduce the `10`-before-`2` bug; the `10` row in `launchpad-brief.md` is the
   existing guard for this and must keep passing.
4. **Regression test.** Add a fixture test asserting (a) a legacy `1a`/`1b` brief normalizes to the
   pinned scheme with every `from:` edge still resolving, and (b) ordering with a 10+ subtask brief
   is still natural. Wire it into `sdk-spike/test/self-test.sh` so it runs with the existing suite.

## Non-goals

- No arm-3 re-run, no `FABLE_PARITY_EVAL` rows, no `--multi-voter-heal` measurement — that is item
  05's operator half and stays there.
- No change to the `provides`/`requires` contract schema itself, and no `schema_version` bump.
- Do not narrow the parser's accepted input. Tolerance is a compatibility requirement; the change
  is normalization on top of it, not replacement of it.

## Acceptance criteria

- The numeric id scheme is stated as an explicit rule at the producer surfaces, and the illustrated
  examples agree with the rule.
- The parser still accepts a legacy `1a`/`1b` brief and normalizes it, with every `from:` edge
  resolving to a real subtask after normalization (no dangling edges).
- 10+ subtask ordering is still natural (`2` before `10`), verified by a test, not by inspection.
- New fixture test runs inside `sdk-spike/test/self-test.sh` and the existing suite stays green.
- Repo-root gates all pass — enumerate them from disk (`ls scripts/check-*.sh scripts/validate-*.sh`),
  never from memory.

## Outcomes Rubric

- Numeric scheme pinned as a rule at producer surfaces, with mirrors synced
- Parser normalizes legacy alpha-suffixed ids on both sides of every edge
- Natural ordering preserved for 10+ subtasks, test-verified
- Regression test added and wired into the existing self-test suite
- Full gate set enumerated from disk and green

## Status: brief-shipped

Job `.supervisor/jobs/done/2026-08-04-subtask-id-determinism.md` completed (reconciled from the job lifecycle, not self-reported).
Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.
