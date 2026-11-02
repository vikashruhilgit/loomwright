# Evidence — Phase 4.5 reviewer replays its own past misses

Source requirement: `.supervisor/requirements/2026-11-01-092115-phase-4-5-reviewer-replays-its-own-past-misses.md`.
Suite: `loomwright/evals/phase45-reviewer/` (procedure, layout and honest limits in its `README.md`). Corpus
builder: `loomwright/scripts/build-reviewer-replay-case.sh`. Expectation table:
`docs/evidence/phase45-reviewer-corpus.tsv`. CI leg: `loomwright/scripts/test-build-reviewer-replay-case.sh`. Base
commit `26eda742b616a339f971b34b5b7d8740c9654851` (`origin/main` when this run started). macOS.

## The command

Run from the repository root. It is model-backed, on-demand only, and spends the runner's Claude credential (one
reviewer spawn per case). It never runs in CI.

```bash
bash loomwright/evals/phase45-reviewer/lib/run.sh
```

It prints one row per case, then `caught: X/Y`, `unstageable: <n>`, `no_reply: <n>`, `noise: <sum> BLOCKING/HIGH on
<m> controls`, and the model, wall clock, turns and cost. CI runs only the model-free selftest
(`bash loomwright/evals/phase45-reviewer/lib/selftest.sh`) as leg E of the builder's test.

## Corpus minimum (owner decision, Launch Pad, 2026-11-01)

- **At least 5 owner-confirmed miss cases and at least 2 clean controls.**
- **Confirmation route: park for the owner.** This run shipped the builder, the suite, the selftest, the CI leg, the
  docs and the two controls. It ran the builder for miss candidates in dry-run mode only and never passed `--confirm`
  for a miss case. The miss cases and the model-backed baseline are added by the owner in a follow-up session on the
  same PR, which stays open until then.

## Candidates the builder printed at the base commit

`bash loomwright/scripts/build-reviewer-replay-case.sh --list --since 2026-10-14`, run at base `26eda742b616`
(`origin/main`). The window matches the Launch Pad probe. Verbatim:

```
candidates on origin/main (26eda742b616) since 2026-10-14 — proposals only; the owner confirms each case

| kind | pr | merge | base | pre_drain_head | later | overlap | expected_file | ledger |
|---|---|---|---|---|---|---|---|---|
| control | 770 | 934628940667 | 5fadddb6237b | 4d573969c6c9 | 0 | 0 | — | shm=0 |
| control | 764 | a3e8ed5cc0b0 | c8fe7b485a74 | 5431951196b4 | 0 | 0 | — | shm=0 |
| miss | 752 | c8fe7b485a74 | ef981491bdb6 | 08b797a9e8f1 | 1 | 3 | `loomwright/docs/PITFALLS.md` | shm=0 |
| miss | 746 | 9c384150e879 | b0109dd49f49 | 257fddb9252e | 1 | 8 | `changelog.d/provider-routing-readonly-seats.md` | shm=0 |
| control | 741 | 4ce7b6fc94c1 | 304adac5dd09 | 96313030ecad | 0 | 0 | — | - |
| miss | 721 | 64207040a639 | 84d9023b2d75 | 164527da3ed2 | 2 | 1 | `loomwright/scripts/test-classify-risk.sh` | - |
| miss | 713 | 80fe4129b581 | d251729d3b41 | 1582fc64c48f | 1 | 2 | `loomwright/scripts/module-shape-facts.sh` | shm=1 |
| miss | 711 | d251729d3b41 | ec67b6765239 | d12e504ad89e | 13 | 2 | `loomwright/scripts/session-resume.sh` | - |
| miss | 685 | 237adab3f71e | 29967f686890 | 7fad78a3e61a | 36 | 1 | `docs/evidence/tr09b-overlap-map-and-scan-cadence.md` | - |
| control | 651 | 6f18ef79fd1e | e1f51ed6710f | fc0bf90fecc1 | 0 | 0 | — | shm=0 |
| miss | 641 | ea0c452dfee0 | ee3d7ea3bb06 | cb96c3b16cd3 | 28 | 5 | `loomwright/docs/vendor-coupling-manifest.json` | - |
| miss | 631 | ee3d7ea3bb06 | 626f35fab857 | 0d8eff7ca4a0 | 16 | 3 | `loomwright/commands/agent-help.md` | - |
| miss | 606 | 3a03dfa66d7d | a8819a38100d | ce24faff9e16 | 24 | 7 | `loomwright/docs/vendor-coupling-manifest.json` | - |
| miss | 594 | 785cc84c763a | c7d4f9a77032 | a16cf355b8e3 | 2 | 2 | `docs/evidence/as07-next-step-drain-and-run.md` | shm=0 |
| miss | 582 | c7d4f9a77032 | e2327712af6e | 5d782747e7c9 | 33 | 2 | `loomwright/docs/vendor-coupling-manifest.json` | - |
| miss | 567 | f2017f1ffa1f | f5c2d0e23fb7 | c9e36ec73a14 | 37 | 2 | `loomwright/docs/ARCHITECTURE_CONTRACTS.md` | - |
| miss | 555 | 514781c794da | 3d0ab990e83b | 028cbed6b8e3 | 1 | 2 | `loomwright/scripts/automate-trail.sh` | shm=0 |
| miss | 548 | 3d0ab990e83b | ef3d47b0fba8 | 06ce6f59617b | 1 | 1 | `loomwright/scripts/test-automate-lanes.sh` | shm=0 |

candidates: miss=14 control=4 (of 75 PR merges scanned)
```

How to read it:

- `later` counts the PR's commits after its pre-drain head, excluding `chore(release)…` ones. A large `later` (wave PRs
  #711, #685, #641, #631, #606, #582, #567) usually means base merges and lane commits, so the proposed expected
  file may not be what the drain fixed. Those candidates need the closest look.
- `overlap` is how many files of the pre-drain diff a later non-merge commit changed. `expected_file` is the one the
  most later commits changed. The owner may override it with `--file <path>` (any file of the pre-drain diff).
- `ledger` is the newest `.supervisor/postmortem/results.jsonl` row for the PR (`shm=` its `self_heal_misses`), or
  `-` when the local ledger has no row. It is an annotation only. The builder never picks a case from it.

**Dry runs.** `--pr <N>` (no `--confirm`) ran for each of the 14 miss candidates. Each exited 0, printed `base:`,
`pre_drain_head:` and `expected: {file: <the expected_file above>, severity_floor: HIGH}` followed by `dry run —
nothing written; re-run with --confirm`. `git status --porcelain --ignored` was identical before and after the 14 runs.
No miss case was confirmed.

## The two committed controls

Written by `bash loomwright/scripts/build-reviewer-replay-case.sh --pr <N> --control --confirm`, picked from the
`--list` controls above:

| Case | PR | base | pre-drain head | Why it qualifies |
|---|---|---|---|---|
| `01-control-pr651` | #651 | `e1f51ed6710f` | `fc0bf90fecc1` | The Phase 4.5 fix commit (`fix: address review feedback (iteration 1)`) is the PR's last commit, so nothing was changed after the reviewer's final round. Not reverted on main. The ledger row records `self_heal_misses: 0` and the drain `READY converged`. The diff is mid-sized (9 files). |
| `02-control-pr770` | #770 | `5fadddb6237b` | `4d573969c6c9` | The iteration-3 fix commit is the PR's last commit, and no revert is on main. The ledger row records `self_heal_misses: 0` and the drain `READY converged`. The diff is larger (37 files) and so tests noise on a wide change. |

Not picked: #764, whose ledger row records `drain ESCALATED` (not a clean finish), and #741, which has no ledger row
to corroborate it. Both controls were staged for real in a scratch sandbox through their own `scaffold.sh`:
`.eval/` held only `base_sha case-id head_sha review-prompt.md`, and `git diff --shortstat origin/main...HEAD` matched
`git diff --shortstat <base> <pre-drain head>` in this repo (9 files for #651, 37 for #770).

## Baseline

**PENDING — owner confirmation.** No model-backed number exists yet, and none is claimed. A Phase 4.5 PASS or a drain
READY on this PR does not mean the baseline is met. The work item is not done until the owner completes these steps
on this PR:

1. Confirm at least 5 miss cases. For each candidate, review the dry run (`bash
   loomwright/scripts/build-reviewer-replay-case.sh --pr <N> [--floor <floor>] [--file <path>]`), then write it with
   `… --confirm`. Each confirmation adds one case dir and one row to `docs/evidence/phase45-reviewer-corpus.tsv`.
   Commit them.
2. Run `bash loomwright/evals/phase45-reviewer/lib/selftest.sh`, then run `bash loomwright/evals/phase45-reviewer/lib/run.sh`
   on the merge commit (the PR head that will merge).
3. Check each kept trace for a read of `phase45-reviewer-corpus.tsv` or `evals/phase45-reviewer/`. Report a run that
   read either, and do not count it.
4. Record here, from the summary and the eval JSON: `caught: X/Y`, `unstageable`, `no_reply`, the controls' `noise:`
   line, the per-case rows, the model, the wall clock and the cost.
5. Replace the PENDING line above with those numbers and the commit they were measured on.

## Honest limits

- **Run-to-run variance.** Reviewer output differs between runs. Compare the same cases on both reviewers, and a
  single-case swing is not a signal on its own.
- **The corpus comes from this repo only.** Cases are merged PRs of this public repo's `main`, with a GitHub merge
  commit and a Phase 4.5 fix commit. Squash-merged PRs are never candidates.
- **The candidate rule is a heuristic.** The pre-drain head is the last `fix: address review feedback (iteration N)`
  commit, and a "miss" is a later commit that changed a file the pre-drain diff also changed. A later change can be
  a rebase, a base-merge resolution or scope creep, not a fix for something the reviewer missed. That is why the
  builder only proposes and the owner confirms each case.
- **The eval's pass/fail means "a reply was captured", not "caught".** The score is `caught: X/Y` from
  `lib/summarize.sh`, graded after the run.
- **The expectation never enters the sandbox or the plugin root, but the source checkout is reachable.** The
  expected file and floor live only in the repo-root corpus table. The sandbox gets the case id, the two shas and the
  rendered prompt. However, the reviewer could still reach the source checkout by absolute path, which holds the
  corpus table and the post-fix versions of the replayed files. That is why Baseline step 3 checks each trace for a
  read of `phase45-reviewer-corpus.tsv` or `evals/phase45-reviewer/`.
- **Reaching the agent is unverified.** No run has yet shown that the eval child can spawn the plugin's code-reviewer
  agent. If it cannot, every staged miss case reads `MISSED (no reply)` and stays in the denominator, so the failure
  is visible.
