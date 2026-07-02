# W-NEW-3 Spike (v2 — end-to-end) — stacked-branches ancestry verification

**Status:** open follow-up after v14.0.0 release (PR #12). Original v1 spike PASSED in isolation but missed the connected bug chain that landed iter N+1's branch off `main` instead of off `iterations[N].branch`. The v2 spike below exercises the full production path through Supervisor's Phase 1 → Phase 4 → Phase 4.5, which is the path the original chain ran through.

## Why v1 wasn't enough

The v1 spike spawned `code-reviewer` and `rubric-grader` against a **manually-built** stacked fixture (`feature/spike-test` with one commit + `feature/spike-test-child` with one commit on top). Both agents correctly honored the inline `DIFF-SCOPE OVERRIDE` directive and computed `git diff feature/spike-test...HEAD`, never falling back to `origin/main`. The PASS was real for that contract.

What v1 did not test:

- That `agents/supervisor.md` Phase 1 step 4 actually uses `$BASE_BRANCH` as the `git checkout` source. (It didn't — the bug.)
- That `skills/autonomous-loop/SKILL.md` EXECUTE step 1 actually passes `--base-branch` to Supervisor. (It didn't — the bug.)
- That the Signal-1 stacked-mode refined-requirement template tells Launch Pad to write `Base Branch: feature/iter{N}` into the brief. (It didn't — the bug.)

Because the v1 fixture was hand-built with the correct stacked ancestry, the reviewers got a valid stacked diff to review. The bug only manifested when Supervisor itself constructed the iter N+1 branch — at which point the branch was rooted on `main`, the PR opened with `--base feature/iter1`, and the resulting GitHub diff was nonsense (iter1's commits appeared as removals, iter2's commits as additions).

## v2 spike procedure

**Prerequisite:** the BASE_BRANCH end-to-end fix from commit `14a9c40` is on the branch under test (verify with `grep -n 'BASE_BRANCH="${BASE_BRANCH:-main}"' loomwright/agents/supervisor.md` — should match Phase 1 step 4, line ~209).

**Setup:** clean working tree on `main`. A working `gh` auth. No `.supervisor/jobs/pending/*.md` files (the autonomous-loop's `ls`-diff brief-save detection trips on stale pending briefs — see `commands/autonomous.md` "single-session-only" caveat).

**Step 1 — small rubric requirement.** Write a 2–3 item rubric that obviously can't be satisfied in one iteration:

```bash
mkdir -p .supervisor/requirements
cat > .supervisor/requirements/spike-w-new-3-v2.md <<'EOF'
Add a CLI flag `--banner` to scripts/check-command-sync.sh that prints a single-line banner when set.

## Outcomes Rubric

1. `bash scripts/check-command-sync.sh --banner` prints exactly one line to stdout starting with the literal token "[SYNC]".
2. The flag is documented in the script's `--help` output (or the script's header comment if no `--help` exists).
3. The change is covered by a smoke test in `scripts/` or `tests/` that runs the new flag and asserts on the "[SYNC]" prefix.
EOF
```

Item 3 (smoke test) is the deliberate over-scope — Launch Pad will likely scope iter 1 around items 1+2, leaving item 3 to trigger Signal 1's rubric gate.

**Step 2 — run the autonomous loop, 2-iteration cap.**

```bash
/autonomous --requirement .supervisor/requirements/spike-w-new-3-v2.md --max-iterations 2
```

- Phase 6 save: pick `save`.
- Plan Review FAIL × N (if any): proceed per the loop's existing flow.
- Supervisor adjudication (if any): pick the option that lets the iteration finish. The spike isn't testing adjudication — it's testing branch ancestry.
- Iter 1 completes, opens PR. Rubric Grader scores < 3/3 (assuming Launch Pad scoped to items 1+2).
- **Signal 1 rubric gate fires.** Pick `continue-to-next-iteration` (the v14 default-mode option).
- Iter 2 runs. Launch Pad writes a new brief that **must** contain `Base Branch: feature/<iter-1-branch-name>` in its `## Configuration` block (verify after Phase 6 save: `grep "Base Branch:" .supervisor/jobs/pending/*.md` before picking save, OR retrieve from `.supervisor/jobs/in-progress/` after save). Supervisor's Phase 0 echoes `BASE_BRANCH=feature/<iter-1-branch-name>`. Phase 1 step 4 `git checkout`s that branch. Phase 4 opens PR with `--base feature/<iter-1-branch-name>`. Phase 4.5 self-verify confirms the PR's `baseRefName` matches.

**Step 3 — ancestry verification (the actual PASS criterion).**

```bash
# Replace <iter1-branch> and <iter2-branch> with the actual branch names from
# the AUTONOMOUS_RUN summary's iterations[] table.
ITER1_BRANCH="$(jq -r '.iterations[0].branch' .supervisor/autonomous/<session_id>/state.json)"
ITER2_BRANCH="$(jq -r '.iterations[1].branch' .supervisor/autonomous/<session_id>/state.json)"
ITER2_PR_URL="$(jq -r '.iterations[1].pr_url' .supervisor/autonomous/<session_id>/state.json)"

echo "iter1 branch: $ITER1_BRANCH"
echo "iter2 branch: $ITER2_BRANCH"
echo "iter2 PR:     $ITER2_PR_URL"

# Check A: iter2's PR is opened against iter1's branch (NOT main)
gh pr view "$ITER2_PR_URL" --json baseRefName,headRefName
# Expect baseRefName == iter1 branch name, NOT "main"

# Check B: iter2's branch ancestry includes iter1's tip
ITER1_TIP="$(git rev-parse "refs/heads/$ITER1_BRANCH")"
git merge-base --is-ancestor "$ITER1_TIP" "refs/heads/$ITER2_BRANCH" && echo "PASS — iter1 is ancestor of iter2" || echo "FAIL — iter1 NOT ancestor of iter2 (v1 bug regressed)"

# Check C: the diff iter2's PR shows on GitHub matches the expected scope
# (only iter2's new commits, not iter1's commits as deletions)
git diff "$ITER1_BRANCH...$ITER2_BRANCH" --stat
# Expect only files iter2 actually touched. If iter1's files show up as
# negative deltas, that's the bug.
```

**PASS criterion (all three must hold):**

- Check A: `baseRefName` for iter 2's PR is iter 1's branch name, not `main`.
- Check B: `git merge-base --is-ancestor "$ITER1_TIP" "$ITER2_BRANCH"` exits 0.
- Check C: `git diff $ITER1_BRANCH...$ITER2_BRANCH --stat` shows ONLY files that iter 2 actually touched. Iter 1's files MUST NOT appear as negative line counts.

**FAIL responses:**

- Check A FAIL: the `gh pr create --base` call in Supervisor Phase 4 step 6 isn't reading `$BASE_BRANCH` correctly. Inspect the spawn-time argv that EXECUTE step 1 built and confirm `--base-branch <iter1-branch>` was actually passed.
- Check B FAIL: Phase 1 step 4's `git checkout` is regressed (`git checkout main` is back). Inspect `agents/supervisor.md` Phase 1 step 4 — the BASE_BRANCH variable must be the source of the checkout, not a hardcoded `main`.
- Check C FAIL but A+B PASS: iter 2's branch is correctly stacked but its diff scope is wrong. This is a downstream concern, likely in `gh pr create --base` arg handling or in the merge-base resolution; investigate Phase 4.5 reviewer's actual command invocation.

**Cleanup after a successful spike run:**

```bash
gh pr close "$ITER1_PR_URL" --comment "spike cleanup"  # if the loop didn't already close it
gh pr close "$ITER2_PR_URL" --comment "spike cleanup"
git branch -D "$ITER1_BRANCH" "$ITER2_BRANCH"
rm .supervisor/requirements/spike-w-new-3-v2.md
rm .supervisor/jobs/done/<iter-1-brief>.md .supervisor/jobs/done/<iter-2-brief>.md
git push origin --delete "$ITER1_BRANCH" "$ITER2_BRANCH" || true
```

## Cost note

This spike is **not free** — it runs two full Launch Pad + Supervisor iterations on a real (if small) requirement, two Phase 4.5 self-heal loops, and may trigger Phase 5.5 plan-review retries. Budget ~10–15 minutes of session time and the corresponding API cost. Run before each v14.x release that touches stacked-iteration code paths (`agents/supervisor.md` Phase 0/1/4/4.5, `skills/autonomous-loop/SKILL.md` EXECUTE/EVALUATE/Signal-1). Skip for releases that only touch unrelated surfaces.

## Why this isn't an automated test

Two reasons. First, the spike depends on interactive user choices at the Phase 6 save gate and the Signal-1 rubric gate — `--non-interactive-fallback` fails these closed and aborts the loop, so the path under test is the interactive one. Second, the spike's value comes from observing the actual `gh pr view` / `git rev-parse` outputs against the real GitHub state, which a sandboxed unit test can't substitute for. A semi-automated harness that drives the gates with scripted AskUserQuestion answers is a future option; v14 ships with the manual procedure documented here.

## Cross-references

- `agents/supervisor.md` Phase 1 step 4 — the `git checkout "$BASE_BRANCH"` line under test
- `agents/supervisor.md` Phase 4 step 6 — `gh pr create --base "$BASE_BRANCH"` self-verify
- `agents/supervisor.md` Phase 4.5 step 5 — base-mismatch cleanup completion tail
- `skills/autonomous-loop/SKILL.md` EXECUTE step 1 — `--base-branch` passthrough
- `skills/autonomous-loop/SKILL.md` Signal 1 stacked-mode refined-requirement template — the Launch Pad inline directive that writes `Base Branch:` into the brief
- PR #12 hotfix commit `14a9c40` — the fix this spike verifies
