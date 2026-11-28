# Loomwright checks a brief's `verify:` lines with Selvedge, and a mistyped check prefix is never run as shell

## Status: open

> Phase 3, item 09 of the approved plan `qa-split/00-plan.md` (rev 2, owner-approved 2026-11-12). Phase 3
> may start: the Phase 2 gate was met on 2026-11-26 (held-out report for selvedge 0.12.1, PR #992:
> known-FAIL 85, false-PASS 0/85, abstention 25/235). Decisions: D4 (CLI discovery), D14 (advisory;
> verdict → ground-truth mapping; counts always shown), D15 (the `verify:` seam and its trust rule),
> D18 (unknown prefix root fix).

## Why

Two things are wrong today in how Loomwright reads a brief's `## Executable Acceptance` lines
(`loomwright/scripts/exec-acceptance-lib.sh`, `classify_kind`):

1. **A mistyped or unknown prefix runs as a shell command.** The last arm is `*) printf 'cmd\n'`, so
   `verfy: the cart total updates` (or `verify:` today, before it has an arm) is hashed into the brief's
   stamp and, once stamped, executed by `run-ground-truth.sh` as the literal shell text. Any future kind
   name can hit the same hole (plan D18, red team C7).
2. **Nothing in Loomwright calls Selvedge.** `qa-executor:` lines are recognised but deferred
   (`unverified`, reason `qa_executor_dispatch_deferred_m2b_1b`) and spawn nothing. The plan's §2 traces
   the old QA's zero runs to exactly this: no caller. Selvedge is now measured and passed the Phase 3
   gate, so it can be the caller's target.

The ground-truth fold also shows "1 PASS + 1 can't tell" as a plain `pass` (red team C3). For `verify:`
checks that would hide every BLOCKED and NOT_VERIFIABLE verdict behind a green word.

## Story

**As the** owner running Loomwright on a project with a UI,
**I want** a brief's `verify:` lines to be checked by Selvedge in Phase 4.5, with a typo'd prefix
refused instead of run,
**so that** acceptance criteria about what a user sees get an evidenced verdict on the PR without me
running anything by hand, and no check line can turn into a shell command by accident.

## Scope

One PR, three parts, all in the same few files (`exec-acceptance-lib.sh`, `run-ground-truth.sh`,
their tests and the docs that copy the kind list):

- **Part A: unknown prefix (D18).** A line whose first word is a prefix (`<word>:` followed by a space
  or the end of the line, where `<word>` is a letter followed by letters, digits, `-` or `_`) and is not
  a known kind classifies as `unknown_kind`. It is never hashed and never run. A bare line with no such
  prefix stays a shell command, as today.
- **Part B: the `verify:` kind (D4, D15).** `verify: <criterion text>`. `qa-executor: <text>` is read
  as the same kind, so no existing line changes meaning. All `verify:` lines of one ground-truth run are
  checked in ONE Selvedge run (owner choice, 2026-11-27). Loomwright finds the CLI through
  `SELVEDGE_BIN`, then `command -v selvedge`, and drives it through its public commands only (criteria →
  plan → freeze → run → verdict), reading `selvedge.json` from the base branch. It never imports or
  reads Selvedge's files.
- **Part C: showing the result (D14, D15e).** `verify:` lines enter the stamp hash, Plan Review lists
  them at LOW, and wherever the ground-truth result is shown, `verify:` checks print their counts.

## Acceptance criteria

**Part A: unknown prefix**
- [ ] Given a brief line `frobnicate: x`, when `run-ground-truth.sh --brief` runs, then that check is
  `unverified` with reason `unknown_kind`, nothing is executed (a marker file the line would create is
  absent afterwards), and the line is not part of `exec_acceptance_hash`.
- [ ] Given a brief whose only Executable Acceptance line is `frobnicate: x`, when
  `exec-acceptance-hash.sh` runs, then it prints `none`.
- [ ] Given a bare shell line with no prefix (`bash scripts/x.sh`, `npm test -- --grep "a: b"`), when
  classified, then it is still `cmd`, hashed and stamp-gated exactly as today.
- [ ] Given a line that starts with a known kind (`cmd:`, `corpus-task:`, `rule:`, `verify:`,
  `qa-executor:`), when classified, then its kind is unchanged by Part A.
- [ ] Given Plan Review reads a brief with an `unknown_kind` line, when it runs Criterion 14, then it
  raises one `executable_acceptance` issue naming the line and saying it will not run.

**Part B: the `verify:` kind**
- [ ] Given `verify: <text>` and `qa-executor: <text>` lines, when classified, then both are `verify`,
  and a test pins that `qa-executor:` keeps working as the same kind.
- [ ] Given two `verify:` lines and a reachable Selvedge, when ground truth runs, then exactly one
  Selvedge run folder is created, and each line gets its own per-check result taken from that run's
  `verdict.json`.
- [ ] Given a Selvedge verdict per criterion, when mapped, then PASS → `pass`, FAIL → `fail`, and
  BLOCKED or NOT_VERIFIABLE → `unverified` carrying Selvedge's reason (for example
  `unverified (NOT_VERIFIABLE material_assumption)`).
- [ ] Given neither `SELVEDGE_BIN` nor `selvedge` on `PATH`, when a `verify:` line is checked, then it
  is `unverified` with reason `verify_plugin_absent`, and the runner still exits 0.
- [ ] Given Selvedge exits with a refusal or its run folder has no readable `verdict.json`, when mapped,
  then every `verify:` line is `unverified` with a named reason, never `pass`.
- [ ] Given `--no-cmd` / `GROUND_TRUTH_NO_CMD=1` (unattended `/automate`), when ground truth runs, then
  `verify:` lines are still checked (D15a: a step plan has no shell), while `cmd:` lines stay disabled
  as today.
- [ ] Given a PR branch that edits `selvedge.json`, when Loomwright runs Selvedge, then Selvedge is told
  to read `selvedge.json` from the base branch, so the PR's edit has no effect (D15b).
- [ ] Given unapproved env hooks in the target repo, when Selvedge runs, then the result is
  `unverified (BLOCKED env_hooks_unapproved)`; Loomwright never approves a hook itself (D15c).

**Part C: showing the result**
- [ ] Given a brief with `verify:` lines, when `exec-acceptance-hash.sh` runs, then the `verify:` lines
  (in their stripped form) are part of the hash, and editing one changes the hash.
- [ ] Given a brief with `verify:` lines and no stamp, when ground truth runs, then the `verify:` lines
  still run: the stamp gates `cmd:` lines only.
- [ ] Given Plan Review reads a brief with `verify:` lines, when it runs Criterion 14, then it lists
  them at LOW with what they will check, and they never by themselves make the decision NEEDS_HUMAN.
- [ ] Given a run with 1 `verify:` PASS and 1 `verify:` NOT_VERIFIABLE, when the ground-truth result is
  shown (the Phase 4.5 finding and the PR body's ground-truth line), then it reads with the counts, for
  example `verify 1 PASS · 1 NOT_VERIFIABLE`, never a bare `pass`; a test pins this.
- [ ] Given any `verify:` FAIL, when Phase 4.5 finishes, then `heal_decision` is unchanged by it, no fix
  iteration starts because of it, and `gate-eval` still has seven conditions (a test asserts both).
- [ ] Given the kind list (`cmd`, `corpus-task`, `rule`, `verify`, plus `unknown_kind`) is copied in
  the runner's header, `exec-acceptance-lib.sh`'s header, `plan-reviewer.md`, `launch-pad.md` and
  `docs/result-schemas/ground-truth-json.md`, when this PR lands, then every copy says the same thing
  (house rule: a restated list changes in the same change as its authority).

## Non-goals

- Launch Pad writing `verify:` lines for UI criteria, and the PR body's verdict counts section (item 10).
- The CI GitHub Action (item 10b).
- Letting a `verify:` FAIL start a fix iteration (Q6 (b), revisited at Phase 5 with data).
- Replaying a frozen plan on later self-heal iterations instead of planning again (a cost follow-up,
  see Risks).
- Changing how the ground-truth fold treats any kind other than `verify` (D14).

## Owner decisions

- 2026-11-12 (Vikash): rev 2 approved: D4, D14, D15, D18 as written in `00-plan.md`; Q6 (a): FAILs stay
  advisory in Phase 3.
- 2026-11-27 (Vikash): a `verify:` line holds the criterion text, and all `verify:` lines of one
  ground-truth run go into ONE Selvedge run (`/loomwright:product-owner` session, PO-ASSUME question).
- 2026-11-28 (Vikash, `/automate` scope gate after Launch Pad stopped on `scope_widening_non_interactive`):
  extend `## Touches` with the 4 paths the plan needs: `loomwright/scripts/ground-truth-verify.sh` (the
  Selvedge driver as its own module, since the runner is 693 lines), `docs/evidence/qa-split-09-verify-kind.md`,
  `loomwright/docs/loop-inventory/supervisor.md` and `loomwright/docs/loop-inventory/launch-pad-autonomous.md`.
- 2026-11-28 (Vikash): the merge does NOT wait for a Selvedge release. Checked on 2026-11-27: selvedge 0.12.1
  `run` reads `selvedge.json` from the run folder's checkout (`selvedge/lib/runner/run.mjs`,
  `loadConfig({ cwd: runDir })`, no `--base`), so D15b holds at plan time only. This PR ships with that gap
  named in the evidence file and the PR body as an open item (a later, separate Selvedge fix); Loomwright
  still never works around it and never passes an unsupported flag to `run`. Merge through `/automate`'s
  auto-merge gate once review and fixes are clean. The open item's fix is the Selvedge requirement
  `.supervisor/requirements/2026-11-28-081548-selvedge-run-reads-selvedge-json-from-the-base-the-plan-was-frozen-against.md`.

## Priority: MVP

**Rationale:** first item of Phase 3. Items 10 and 10b build on the `verify:` kind, and Phase 5's 60-day
dogfood clock starts when this item ships.

## Assumptions

- Selvedge's public CLI already covers the chain: `criteria from-text` (stdin, one criterion per line),
  `plan <criteria.json>` (default planner `claude -p`), `plan --freeze`, `run`, `verdict`; confirmed from
  `selvedge help` on 2026-11-27. The base-branch read uses Selvedge's own `--base <ref>`, which
  `env check`, `plan`, `plan --validate` and `plan --freeze` accept; `run`'s help lists no `--base`.
  The worker confirms that `run` does not re-read the PR head's `selvedge.json` (or that the frozen plan
  carries the base-branch origins). If it does re-read it, that is a Selvedge fix, released on its own.
  It is not a Loomwright workaround. Confirmed 2026-11-27 that 0.12.1 `run` does re-read it; per the
  2026-11-28 owner decision this PR does not wait for that fix (it records the gap as an open item).
- The target app is already running when Phase 4.5 runs; when it is not, Selvedge reports BLOCKED and
  the line is `unverified` (advisory, never a failure of the run).
- The prefix grammar in Part A does not match a real bare command in any current brief. Checked by
  running the new classifier over the briefs in `.supervisor/jobs/done/` before merge.

## Risks

- **Cost per self-heal iteration.** Ground truth runs once per Phase 4.5 iteration, and each run plans
  again with a model. Heal has gone 3/3 iterations on most items since 2026-10-12, so a brief with
  `verify:` lines may plan three times. Selvedge's budget (BLOCKED `budget_exceeded`) caps one run;
  replaying the first frozen plan is the follow-up if the cost shows up.
- **Time.** The runner has no per-check timeout today, and a plan plus a browser run takes minutes.
  Selvedge's own budget bounds the plan step.
- **Prompt injection at plan time.** The planner reads the page. Bounded by Selvedge's step plan (no
  shell), its origin allowlist and its validation (plan §9); not eliminated.

## Validation (must pass before merge)

1. **Static — the affected suites:** `bash scripts/ci-local.sh --affected` passes, including
   `test-run-ground-truth.sh` and `test-exec-acceptance-hash.sh` with the new legs (unknown prefix never
   run, `verify_plugin_absent`, one run for two lines, the counts line, `qa-executor:` alias, no-stamp
   `verify:` still runs, `gate-eval` still seven conditions). The `verify:` legs use a stub `SELVEDGE_BIN`
   that writes a fixed `verdict.json`.
2. **Static — the manifest:** `check-qa-removal-manifest.sh --expect 12` still passes, with its
   `qa-executor:` keep rows updated to the alias wording.
3. **Running system — a real Selvedge run:** `run-ground-truth.sh --brief <a brief with two verify:
   lines>` against Selvedge's bundled sample app (`selvedge sample-app`) prints one result per line
   from one Selvedge run folder, with the counts line. The output is pasted in the PR.

## Depends on
none

## Touches
loomwright/scripts/exec-acceptance-lib.sh
loomwright/scripts/run-ground-truth.sh
loomwright/scripts/exec-acceptance-hash.sh
loomwright/scripts/test-run-ground-truth.sh
loomwright/scripts/test-exec-acceptance-hash.sh
loomwright/scripts/test-rule-conformance-seam.sh
loomwright/agents/plan-reviewer.md
loomwright/agents/launch-pad.md
loomwright/skills/self-heal-advisory/completion-tail.md
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/docs/result-schemas/ground-truth-json.md
loomwright/docs/result-schemas/supervisor-result.md
loomwright/docs/RESULT_SCHEMAS.md
loomwright/docs/qa-removal-manifest.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
loomwright/scripts/ground-truth-verify.sh
docs/evidence/qa-split-09-verify-kind.md
loomwright/docs/loop-inventory/supervisor.md
loomwright/docs/loop-inventory/launch-pad-autonomous.md
changelog.d

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-28T05:37:39Z
- **Brief:** .supervisor/jobs/done/2026-11-28-qa09-verify-kind-unknown-prefix.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/995
