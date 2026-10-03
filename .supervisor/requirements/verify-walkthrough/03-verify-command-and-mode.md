# 03 — `/verify <ticket>`: command, `verify-walkthrough` skill, qa-executor `--verify` mode

## Problem
No surface verifies a ticket against the running app. `## Executable Acceptance` → `run-ground-truth.sh` is
`cmd:`/`corpus-task:` only; `/qa-executor` crawls the whole app from discovery, never from a ticket's
acceptance criteria, and forbids form submission; Phase 4.5 and CI review read the diff. The owner's ask —
"run the app, walk through it, fill the form, check the implementation" — has no home. Decision V1 (00):
this is a command + skill with qa-executor as the executor in a new mode, not a 15th agent.

## Goal
`/verify <ticket>` reads one ticket's acceptance criteria, starts the app from the 01 contract, walks each
criterion in the real app with Playwright, and records one of four verdicts per criterion with evidence
(02). Advisory only (V6).

## Scope
1. **`commands/verify.md`** — `/verify <path> [--branch <name>] [--cheap]`. Main-thread steps (the ones a
   subagent cannot do): resolve ticket kind (`requirement` = `.supervisor/requirements/**/*.md` with
   Given/When/Then bullets; `brief` = `.supervisor/jobs/**/*.md` with `## Acceptance Criteria`); run
   `read-verify.sh` — empty stdout ⇒ print the named absence + the `propose-verify.sh` line and STOP;
   `verify-env.sh assert-non-prod` ⇒ fail CLOSED on non-zero; `git diff --stat origin/<base>...<branch>` for
   the diff summary; create the run dir + `run_start` line; spawn qa-executor with `--verify <run_dir>`;
   on return, `summary-build` and print `summary.md`. Namespaced form `/loomwright:verify` documented for
   headless use (memory `namespaced-slash-command-required-headless`).
2. **`skills/verify-walkthrough/SKILL.md`** — protocol authority (preloaded into qa-executor's `skills:`
   list ONLY for the `--verify` path if the budget allows; otherwise Read on demand at mode entry, like
   `preflight-sync`). Contents: (a) AC extraction rules for both ticket kinds, `ac_id` = ordinal within the
   ticket; (b) AC → Playwright step derivation: role-based locators, strict assertions, follow-up GET after
   any mutation (all from `qa-test-patterns` — reference, do not restate); (c) **the four verdicts** — `PASS`
   (every Then observed), `FAIL` (a Then contradicted; `classification` + `reason` + artifact mandatory),
   `BLOCKED` (could not reach the When: auth, env, seed — `ENVIRONMENT_ISSUE`), `NOT_VERIFIABLE` (the AC is not
   observable through the app: load, timing, "no double-booking under concurrency", internal-only effects —
   `reason` names why; **a PASS is never emitted for an AC whose Then was not observed**); (d) the
   mutation carve-out (V7): form submit / create / update / delete are allowed in `--verify` mode only, after
   `assert-non-prod` passed in this run, with `seed` before and `reset` after when the contract declares them;
   payment / logout / account-delete stay forbidden everywhere; (e) evidence per AC: screenshot at the Then,
   Playwright trace, any non-2xx response body; (f) budget: reuse qa-executor's tool-call budget (`--verify`
   = 80 default), checkpoint = the evidence lines already written (a run killed mid-way loses nothing recorded).
3. **`agents/qa-executor.md` `--verify <run_dir>` mode** — a new top-level branch after Phase 2/3: skips
   SESSION PLANNING, DISCOVER-ALL, STRATEGY, GENERATE-SUITE, STRATEGIST AUDIT; runs env start via
   `verify-env.sh start`, the walkthrough per §2, appends via `verify-helpers.sh evidence-append`, runs
   `verify-env.sh stop`. The L1 Critical Rules block gains one sentence pointing at the carve-out — the
   discovery rule itself is unchanged. Emits a `VERIFY_RESULT` block (schema in `RESULT_SCHEMAS.md`, counts
   DERIVED by calling `summary-build`, never tallied by the agent) so the SubagentStop validators have
   something to parse. `commands/qa-executor.md` flag prose synced in the same commit
   (`scripts/check-command-sync.sh` misses table prose — memory `agent-command-mirror-drift-on-fixes`).
4. **Playwright only, from Bash.** Own headless Chromium; `--headed` only for the sign-in step (04). No
   `Claude_Browser` / computer-use MCP references anywhere in the skill or agent (portability seam).
5. **Tests.** `scripts/test-verify-walkthrough.sh`: AC extraction fixtures for both ticket kinds (a
   requirement file with 3 Given/When/Then bullets; a brief with a `## Acceptance Criteria` list); an AC
   phrased as "under 200 concurrent users" must derive `NOT_VERIFIABLE` in the fixture verdict table; the
   command's absent-store path stops before any `verify-env.sh` call (assert by a tee'd call log);
   `assert-non-prod` failure stops before `start`. Token budget re-measured (`check-token-budget.sh`).
6. **Docs/counts:** `SKILLS_INDEX.md`, `commands/agent-help.md`, `README.md` command table, `plugin.json` +
   `marketplace.json` description counts in place (+1 command, +1 skill), CHANGELOG entry, `docs/HOOKS.md`
   only if a hook row changes (none expected).

## Non-goals
No auth pause (04), no drafts/notify (05), no impact pass (06), no queue (07). No new agent role. No change
to any gate, `heal_decision`, or merge path. No change to qa-executor's non-`--verify` behaviour (its
existing test fixtures must stay byte-identical in outcome).

## Acceptance criteria
- `/verify <requirement>` on a project with no `.agent/verify.json` prints the named absence and the
  bootstrap command, and no process is started (call log empty).
- On a fixture app (static server + one form that POSTs and renders the value) with a 2-AC requirement, the
  run produces exactly two `ac` lines with verdicts `PASS`/`PASS`, each with a screenshot artifact path that
  exists, and `summary.md` shows 2/0/0/0.
- Break the fixture form (render the wrong value): the second AC becomes `FAIL` with `classification: REAL_BUG`,
  a non-empty `reason`, and a response-body artifact; the summary shows 1/1/0/0. **Mutation control:** this
  is the assertion that proves verdicts come from observation — it must fail if the walkthrough is stubbed.
- An AC whose Then is not observable derives `NOT_VERIFIABLE` with a reason; `PASS` count is unaffected.
- With `non_prod_assert` failing, the run stops with `non_prod_assert_failed` and writes only `run_start` +
  `env` lines — no `ac` line, no app start.
- qa-executor's existing (non-verify) fixtures pass unchanged; budget and doc-currency and command-sync green.

## Outcomes Rubric
- Ticket → per-AC verdicts from observation, evidence attached
- `NOT_VERIFIABLE` used where the Then is unobservable; never a fake PASS
- Mutations gated on non-prod proof; L1 discovery rule byte-unchanged
- Playwright-from-Bash only; no Desktop-only browser dependency
- Counts derived, never agent-tallied; advisory, nothing gated
- Command ↔ agent prose synced; budgets/counts/docs green

## Status: done (PR #223, merge 83764bd)
- **Completed:** 2026-09-15T01:36:22Z (PR merge time; stamp backfilled 2026-09-26 — it had been left `pending`)
- **Brief:** .supervisor/jobs/done/2026-09-14-verify-command-and-mode.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/223

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-09-14T18:31:14Z
- **Brief:** .supervisor/jobs/done/2026-09-14-verify-command-and-mode.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/223
