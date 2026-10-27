# Evidence — configurable base branch (one resolver)

Branch: `feature/base-branch-configurable`. The one resolver is `loomwright/scripts/resolve-base-branch.sh`
(precedence: `--flag` > brief `- **Base Branch:**` > `.supervisor/config.json .base_branch` > origin/HEAD after
one `git remote set-head origin -a` > `gh` default branch > fail closed `base_branch_unresolved`).

## AC15 — prompt-layer grep

Command, run from the repo root on the integrated tree (Subtasks 1–6):

```sh
grep -rnE "origin/main|checkout main" loomwright/agents loomwright/skills loomwright/commands
```

Full output:

```text
```

(no lines; grep exit status 1)

Remaining hits and their justification: **none remain.** The last hit was the rejected-alternative sentence in
`loomwright/skills/automate-loop/per-item-loop.md` (`trail_pr_open` bullet, option (a): refresh a READY-but-BEHIND
PR "by merging `origin/main`"). It now reads `origin/<base>`, because the option it rejects applies to whatever
base the run resolved.

### Related wording outside the grep's patterns

`default \`main\`` does not match the AC15 patterns, but it is the same claim. Command:

```sh
grep -rnE 'default `main`|base default `main`' loomwright/agents loomwright/skills loomwright/commands
```

Output and the justification for each line:

```text
loomwright/agents/review-pr.md:69:The single input is the **PR URL**. The review scope is the PR diff: `git diff <base>...HEAD` for the PR's base branch (default `main`).
loomwright/skills/review-heal/SKILL.md:101:- The review scope is the PR diff: `git diff <base>...HEAD` for the PR's base branch (default `main`). The reviewer is told to scope to exactly this diff.
loomwright/commands/review-pr.md:17:| `<pr-url>` | Yes | — | The full URL of an existing PR. The review scope is the PR diff (`git diff <base>...HEAD`, base default `main`). |
```

- `agents/review-pr.md:69`: kept on purpose. This is a review-heal surface. AC10 requires that no review-heal
  file is modified, because `/review-pr` takes its base from the PR's own `baseRefName` and never calls the
  resolver. The parenthetical is the prose default for a PR whose base cannot be read.
- `skills/review-heal/SKILL.md:101`: same reason (AC10). This is the same sentence in the skill the agent loads.
- `commands/review-pr.md:17`: same reason (AC10). This is the same sentence in the command's parameter table.

The three files change together in a later review-heal change, or not at all.

## Residual wording fixed by the integration subtask

Subtasks 1, 4 and 5 handed these over because no subtask owned them. Each now points at the resolver:

| File | Before | After |
|------|--------|-------|
| `loomwright/skills/automate-loop/per-item-loop.md` (option (a) of the `trail_pr_open` bullet) | by merging `origin/main` | by merging `origin/<base>` |
| `loomwright/skills/autonomous-loop/multi-iteration.md` (`Base Branch:` paragraph) | Supervisor's Phase 0 defaults to `main` | resolves the base through `scripts/resolve-base-branch.sh` |
| `loomwright/docs/loop-inventory/launch-pad-autonomous.md` LP-358 (action cell of the row above) | Supervisor defaults to main | Supervisor resolves the base via resolve-base-branch.sh |
| `loomwright/docs/supervisor-legacy-phases.md` (Phase 0 summary) | `--base-branch`, default `main` | `--base-branch`, else `scripts/resolve-base-branch.sh` |
| `loomwright/docs/rationale/supervisor.md` (flags line) | `--base-branch <name>` (default `main`) | (default: `scripts/resolve-base-branch.sh`) |
| `loomwright/docs/result-schemas/supervisor-result.md` (`risk_classification` comment) | `classify-risk.sh "$BASE_BRANCH" HEAD` | `classify-risk.sh "origin/$BASE_BRANCH" HEAD` (matches `agents/supervisor.md` and `skills/self-heal-advisory/completion-tail.md`) |

## Known residuals, deliberately not changed here

- `loomwright/scripts/automate-helpers.sh` `gate-eval` condition 6 runs `classify-risk.sh main <live head_sha>`,
  and `skills/automate-loop/modes-and-merge-gate.md` condition 6 documents the same call. This is a hardcoded
  base inside the sanctioned `--auto-merge` executor. AC9 does not list it as a consumer, and the brief does not
  assign it to any lane. It fails CLOSED: a missing local `main` makes the diff unclassifiable, so the gate
  parks with `high_risk_diff` and never merges. On a repo with a non-`main` base it can still classify against
  the wrong range. The guard does not flag it, because the literal is a positional argument, not an assignment
  or fallback. Recommended follow-up: pass the PR's own `baseRefName`, which the gate already reads live, as
  `origin/<baseRefName>`.
- `loomwright/skills/autonomous-loop/multi-iteration.md` still says that iteration 1 and `--no-stacked-branches`
  iterations branch from `main` (the `--no-stacked-branches` bullet, the two PR-base-verification skip
  conditions and the merge-and-continue prompt). The LP-378, LP-379 and LP-496 `q:` anchors quote this wording.
  The AC15 grep does not match it, and it is outside every lane of this change. A follow-up should change it to
  "the resolved base" and update those anchors in the same change.
- `loomwright/docs/rationale/subagents.md` keeps the earlier Plan Reviewer Criterion 13 text ("defaults to
  `main`") inside its quoted `~~~~text` block. It is a frozen quote in a rationale archive, not a runtime prompt.
- `loomwright/docs/result-schemas/schema-versioning.md` keeps `classify-risk.sh "$BASE_BRANCH" HEAD` in its
  v15.72.0 history entry. That entry records what that release shipped.

## AC11 — regrowth guard

`bash loomwright/scripts/test-base-branch-single-resolver.sh` scans every non-test `*.sh` under
`loomwright/scripts/`. Its rules are `origin-head`, `set-head`, `main-assign`, `main-default`, `main-echo` and
`origin-main`. It applies a per-rule allowlist, and each allowlist entry carries a reason:

- `resolve-base-branch.sh` (all rules): the resolver itself.
- `send-telemetry-core.sh` (`origin-head`): the telemetry target-ref comparison. It is a fail-SAFE emitter that
  keys a feedback thread, not a base consumer.
- `eval-corpus/review-churn-canary/check.sh` (`main-assign`): `-c init.defaultBranch=main` names the first
  branch of the throwaway fixture repo that the corpus check creates.
- `automate-lanes.d/create.sh` (`set-head`): re-points a fresh `--local` clone's inherited origin/HEAD. The base
  was already resolved in the primary.

An entry that stops matching is reported as STALE and fails the guard. Built-in mutation controls append each
of the following to a scratch copy of `automate-trail.d/trail-pr.sh`, and the guard must catch each one: the
inline `symbolic-ref … || echo main` line, `base=main`, `base="main"`, `base_branch="main"`, `BASE_REF="main"`,
`default_branch=main`, `${b:-main}`, `${base_ref:=main}`, an `origin/main` probe and `remote set-head`. A commented form and unrelated `main` words must not
be caught. Every mutant must be non-empty, differ from the original and pass `bash -n`.

Brief pin-mutation check: I re-added `[ -n "$base_branch" ] || base_branch="main"` to the real
`automate-trail.d/trail-pr.sh`, then restored it with `git checkout`. The guard exited 1 with
`automate-trail.d/trail-pr.sh:504:main-assign:  [ -n "$base_branch" ] || base_branch="main"`.

Out of scope by design: the root `scripts/check-*.sh` gates diff against `origin/main` for this plugin repo's
own release checks. They are not base-branch consumers of a user project.

## AC24 — full `bash scripts/ci-local.sh` (local, macOS)

On the integrated tree, 184 of 185 self-tests and every ci.yml gate pass. One suite is red:
`loomwright/scripts/test-automate-lanes.sh` (passed 1017, failed 42). The 42 failing case ids are the relay-hook
and inbox cases J3 J4 K1b K5 K7–K11 K15 K16 X2 X4–X7 X9 AD4 AD4b–AD4f AD10 AD11 AD11b AD11c AD12 AD12d AD12e AD12g
AD12h AM1–AM7 AM7b AM11 AM12. They are byte-identical to the failing ids of the same suite run on a detached
worktree of the base commit `84d9023` (passed 1012, failed 42). They are therefore pre-existing on this machine
and not caused by this change. A typical failure is a lane inbox question file under `/private/var/folders/…` that
was never written. The cause was not investigated, because it is out of scope. CI is the arbiter for this suite.

Repaired backstop pins (by fixture or test change, never by a script fallback):

- `test-janitor-report.sh`: the fixture has no origin, so `sweep.sh` now reports `base_branch_unresolved`. The
  fixture now gets a `.supervisor/config.json` `base_branch`.
- `test-setup-module-registry.sh`: four pipes into `grep -q` were rewritten for `test-no-pipefail-grep-q.sh`.
