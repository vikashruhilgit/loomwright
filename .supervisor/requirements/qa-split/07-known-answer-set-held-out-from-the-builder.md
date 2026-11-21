# A known-answer set of 200+ criteria, split by defect, with the held-out answers kept away from the engine's builder

## Status: done
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/968

> Phase 2, item 07 of `qa-split/00-plan.md` (rev 2, approved 2026-11-12). Decision D16; non-goal N7; Q7.
> Phase 1's "done when" holds (06c merged, #939). Phase 2 is time-boxed to 3 weeks, shared with item 08.

**As the** owner deciding whether Selvedge's verdicts can be trusted,
**I want** a fixed set of acceptance criteria whose right answers are known in advance, written by someone
other than the engine's builder, with most of the answers hidden from that builder,
**so that** item 08 can measure how often Selvedge says PASS on broken work, and the number can't be tuned
toward.

## Why

Rev 1's accuracy claim had no denominator, no N and a self-written fixture (red team F4). A verdict tool
is only worth running if its PASS can be believed, and that has to be measured on cases its builder never
saw. Q7 needs at least 60 held-out known-FAIL criteria for a 5% point estimate to mean anything.

## Scope

- **Source (a), planted defects.** A separate Claude session, started in a folder that holds only a copy
  of the sample app (`selvedge/tests/fixtures/app-server.mjs` and what it serves) and no Selvedge source,
  prompts, tests or docs, writes defect variants of that app, each with the criteria a reviewer would
  write for the feature. The session is named in the set's README (its session id and start date), and its
  brief is committed so the separation can be checked.
- **Source (b), real bugs.** From `personal/sports-management` history: for a merged bug-fix PR, the
  criterion comes from that PR, and the known answer is FAIL on the fix commit's parent and PASS on the fix
  commit. Each entry records the repo, both commit SHAs and the PR number. Only criteria checkable on
  localhost web count (D12); a bug that can't be revived or isn't checkable that way is listed as skipped,
  with the reason.
- **Non-defect criteria** (known answer PASS): criteria for behaviour that works, on the same apps and
  commits, so a tool that says FAIL to everything also scores badly.
- **Split** tuning 40% / held-out 60% **by underlying defect**: every criterion from one bug or one planted
  defect lands on the same side. The split is recorded with the seed or rule that made it.
- **Storage.** The tuning set (criteria, app variants or commit refs, answers) is committed under
  `selvedge/eval/`. The held-out answers **and the held-out planted app variants** live outside this repo
  (default `~/.claude/selvedge-eval/held-out/`, overridable by one env var). The repo commits the held-out
  criteria and real-bug commit refs, plus a sha256 manifest of every held-out file kept outside, so the
  outside copy can't be swapped without notice.
- **Re-verify `claude plugin eval`'s reported limits** (no custom-code graders; a sandbox that can't read
  the browser cache under `~`) on the installed CLI, and record the result. This decides only whether
  item 08 may optionally use it for a with/without-plugin comparison.

## Acceptance criteria

- [ ] Given the finished set, when its answers are counted, then there are at least 100 known-FAIL and at
      least 100 known-PASS criteria, and at least 30 of the known-FAIL criteria come from real
      sports-management bugs.
- [ ] Given the split, when the held-out side is counted, then it holds at least 60 known-FAIL criteria
      (Q7's floor), and no defect has criteria on both sides; a test in `selvedge/tests/` fails if a
      defect id appears on both sides.
- [ ] Given a fresh clone of this repo, when it is searched, then no held-out answer and no held-out
      planted app variant is in it; a test fails if a held-out answer file is committed.
- [ ] Given the outside held-out folder, when one byte of any file in it changes, then the committed sha256
      manifest check reports that file by name.
- [ ] Given the planted-defect author session, when its brief and start folder are read, then the folder
      held no Selvedge source, prompt, test or doc, and the set's README names the session.
- [ ] Given a real-bug entry, when it is read, then it names the repo, the parent and fix SHAs and the PR,
      and a skipped bug carries its reason.
- [ ] Given the installed `claude` CLI, when `claude plugin eval`'s grader and sandbox limits are tried,
      then each limit is recorded as confirmed or not, with the command that showed it.

## Non-goals

- Running Selvedge on the set or scoring it (item 08).
- Native targets (Phase 2b, after Phase 5).
- Using `claude plugin eval` as the scorer (D16: optional comparison only).
- Fixing any sports-management bug the history work turns up.

## Owner decisions

- 2026-11-20 (Vikash): held-out answers live **outside the repo, with a sha256 manifest committed in it**
  (chosen over committed-encrypted and committed-plain).
- 2026-11-20 (Vikash): **at least 30** of the known-FAIL criteria come from real sports-management bugs;
  planted defects fill the rest.
- 2026-11-21 (Vikash, at `/automate` run automate-2026-11-21-045321): this item's own run does **NOT**
  write source (a) planted defects — the builder must not author them. The owner starts that separate
  session by hand. This run delivers source (b), the non-defect criteria, the split / no-leak / manifest
  tooling and tests (built to accept planted-defect entries added later), the set's count command and
  README (with an empty slot naming the planted-defect session to come), and the `claude plugin eval`
  re-check. The count criteria that need planted defects (≥100 FAIL overall, ≥60 held-out FAIL) are
  reported as measured, not forced; the PR says which remain open until the planted set lands.

## Priority: Phase 2 (gates Phase 3)

**Rationale:** item 08 has nothing to score without it, and the Phase 3 seam waits on 08's gate.

## Assumptions

- The held-out planted app variants must be hidden along with the answers: a variant's code is the answer
  (a diff against the sample app shows the defect). Real-bug commits stay readable in sports-management's
  history; that leak is accepted and named in Risks.
- 30 real-bug criteria are reachable: sports-management has ~880 commits whose subject starts with `fix`
  and 200+ merged `fix` PRs, but each needs its parent commit running with local Supabase, and many will
  not be web-checkable.
- The "separate session" can be enforced by its start folder and brief; there is no stronger isolation
  on this machine.

## Dependencies

- Depends on: Phase 1 done (06c, #939).
- Blocks: item 08.

## Risks

- Reviving old sports-management commits (migrations, Supabase versions, env) may eat the time-box.
  Mitigation: the 30 floor; a skipped bug is recorded, not forced.
- Real-bug answers can be found in sports-management's public history by a builder who goes looking.
  The set's README says so.
- The outside folder is single-machine. If it is lost, the held-out set must be rebuilt; the README
  states how to back it up.

## Validation (must pass before merge)

1. **Static — selvedge gate:** `bash selvedge/tests/run.sh` passes, including the new split, no-leak and
   manifest tests; `bash scripts/ci-local.sh --affected` green.
2. **Running system — the counts and the leak check:** on this machine, the set's count command prints
   ≥100 FAIL / ≥100 PASS / ≥30 real-bug FAIL / ≥60 held-out FAIL, and the manifest check passes against
   the outside folder, then fails naming the file after one byte of a held-out file is changed.

## Depends on

none

## Touches

selvedge/eval
selvedge/tests/test-eval-set.sh
selvedge/README.md
selvedge/CHANGELOG.md
selvedge/.claude-plugin/plugin.json
.claude-plugin/marketplace.json

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-11-21T17:36:36Z
- **Brief:** .supervisor/jobs/done/2026-11-21-qa-split-07-known-answer-set.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/968
