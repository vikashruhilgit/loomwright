# 05 — A FAIL goes somewhere: `proposed/` drafts + `--notify`

## Problem
"Notify and record" is the easy half. The recorded failure mode is that nothing *acts*: the QA lane found 25
blocking bugs on a real app and `BUG-NC-001` was still unfixed five months later because QA was standalone
with no consumer (memory `qa-l1-validated-on-sports-management`). The repo already has the right sink —
`/propose` writes evidence-carrying requirement drafts to `.supervisor/requirements/proposed/` that a human
promotes into an `/automate` queue; it never enqueues. Decision V3 (00) routes `/verify` failures there.

## Goal
Every `FAIL` (and every `issue` line) from a verify run becomes a draft requirement a human can promote with
one `mv`, carrying the evidence lines it rests on; the human is told immediately when the run wants them.

## Scope
1. **`scripts/propose-from-verify.sh <run_dir>`** — a third `/propose` basis alongside `propose-work.sh`
   (ledger) and `propose-domain.sh`. Reads `evidence.jsonl` only; writes ONLY under
   `.supervisor/requirements/proposed/` through the same `guarded_write()` (extract it to a shared helper if
   it is currently inline — do not copy it). One draft per FAIL `ac` line and per `issue` line, filename
   `verify-<run_id>-<ac_id|issue-N>-<slug>.md`, sections: `## Problem` (the AC verbatim + what was observed),
   `## Evidence` (mandatory: the `evidence.jsonl` line numbers, artifact paths, ticket path, branch + head sha,
   `classification`), `## Suggested acceptance` (the original AC, unchanged), `## Status: proposed`.
   `DISCOVERY_GAP` / `ENVIRONMENT_ISSUE` classifications are NOT drafted — they are the run's problem, not the
   app's; they stay in the summary. Idempotent on `(run_id, ac_id)`: re-running does not duplicate.
2. **`/propose --from-verify <run_id>`** flag in `commands/propose.md` + the skill, mirroring `--domain`'s
   wiring; and `commands/verify.md` calls it automatically at run end **when ≥1 FAIL exists** (drafts are
   derived artifacts under D9's regenerability split — safe to write unasked; nothing is enqueued).
3. **Notify.** `--notify` on `/verify` posts via `scripts/send-webhook.sh` (fail-SAFE, exit 0) at exactly
   three events: `needs_auth` pause, first `FAIL`, `run_end`. Payload = the same gate-event shape
   `/autonomous --notify` uses plus `run_id`, `ticket`, derived counts. Also `notify-desktop.sh` at
   `needs_auth` (the human must act). Passthrough flag, not persisted (same convention as `/automate --notify`).
4. **Tests.** `scripts/test-propose-from-verify.sh`: fixture run with 2 FAIL + 1 BLOCKED + 1 issue ⇒ exactly
   3 drafts, each `## Evidence` cites ≥1 real line number that resolves to a line with that `ac_id`; the
   BLOCKED line yields no draft; re-run ⇒ still 3 files; a draft is written nowhere but `proposed/` (assert via
   a find diff of the tree); `send-webhook.sh` invoked ≤3 times on a run with 5 FAILs (assert with a stub
   webhook binary counting calls). Mutation control: strip the `## Evidence` section from the writer and the
   suite must fail.

## Non-goals
Never enqueues, never dispatches `/automate`, never opens a PR or issue, never merges. No Jira/Linear
write-back (Phase 2 — the MCPs exist but a draft file is the v1 contract). No change to `propose-work.sh`'s
own basis or thresholds.

## Acceptance criteria
- After a run with one FAIL, exactly one file exists under `.supervisor/requirements/proposed/` matching
  `verify-<run_id>-*`, its `## Evidence` names the `evidence.jsonl` line and artifact, and
  `automate-helpers.sh resolve-folder .supervisor/requirements/proposed` is NOT how it gets picked up (the
  README/skill say so, as `/propose` already does).
- A run with only BLOCKED / NOT_VERIFIABLE writes no draft and says so in `summary.md`.
- `--notify` with `LOOMWRIGHT_WEBHOOK_URL` unset exits 0 and the run is unaffected.
- The `/propose` positive-form invariant grep (`gh pr merge --squash` — CLAUDE.md) is unchanged: this item adds
  zero executor surfaces.

## Outcomes Rubric
- FAIL ⇒ draft with cited evidence; nothing without evidence
- Run-problems (DISCOVERY_GAP / ENVIRONMENT_ISSUE) never become app-work drafts
- Idempotent, single write path, never enqueued
- Notify at three named events, fail-safe, passthrough
- Merge/enqueue invariants untouched

## Status: done
