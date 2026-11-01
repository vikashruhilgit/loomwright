# Phase 4.5 re-reviews converge on what the last fix changed

## Status: pending

> From the 2026-11-01 review of Anthropic's "How the Claude Code team does code review"
> (https://claude.dev/blog/solving-code-review-at-anthropic/) and the AI Labs video built on it. The article's
> convergence measures took first-round passes from 65% to 78% and cut mean reviews per PR from 2.08 to 1.32.
> Loomwright already has the round cap, fix-the-class and the anti-churn guardrail; this item adds the two it lacks:
> diff-scoped re-review after round 1 and never repeating a finding already handled.

**As a** plugin owner running `/automate` and `/supervisor`,
**I want** each Phase 4.5 heal round after the first to review what the previous fix changed, without re-reporting
findings that round already fixed or dismissed,
**so that** heal rounds converge faster and cost less, and run time stops growing with the size of the whole PR.

## Evidence (measured 2026-11-01, re-verify: main moves)

1. **Rounds.** `docs/evidence/review-gate-rounds.md` (automate-speed/23, PR #607): items on plugin ≥ 17.2.0 had
   heal fix rounds 0/1/2/3 = 1/3/7/5 of 16. An item that PASSes after 2 fix rounds ran 3 full reviews. Recorded
   Phase 4.5 durations: 32m, 1h 7m, 1h 14m, 2h 27m. `.supervisor/postmortem/results.jsonl`, 43 items since
   2026-10-14: 14 at 3 rounds, 12 at 2, 13 at 1, 3 at 0.
2. **Every round reviews the whole PR.** The Phase 4.5 reviewer prompt in `loomwright/skills/self-heal-advisory/SKILL.md`
   sets the scope to `git diff origin/$BASE_BRANCH...HEAD` on every iteration and says "look for everything". The
   ANTI-OVERLAP line only covers issues already fixed on the branch. Dismissed findings are not handed back to the
   next round.
3. **What late rounds fix.** `git blame` on the lines that the 38 `fix: address review feedback (iteration 2|3)`
   commits since 2026-10-15 modified: 408 lines (65%) were written by an earlier review-fix commit, 221 (35%) by the
   original build. Another 136 hunks only add lines and can't be attributed. Method: for each such commit, `git
   diff -U0 <c>^ <c>` (excluding `changelog.d/` and `*/evidence/*`), then `git blame` each modified range at `<c>^`,
   and class each line by whether its authoring commit's subject contains "address review feedback". It counts lines,
   not findings, and an "earlier fix" includes round-1 fixes being hardened. Re-derive before relying on it.
4. **Quality is not the problem.** Post-heal misses (`self_heal_misses > 0`) appear on 3 of those 43 items, so this
   item must keep catch rate flat while cutting cost. It must not trade catch rate for speed.

## Owner decision (2026-11-01, this session)

- **D1 — re-review scope for rounds ≥ 2: whole touched files.** The scope is every file the previous round's fix
  commit(s) changed, reviewed in full, and nothing else. It is not just the changed hunks, which is Anthropic's
  design (rejected: 35% of late-round fix lines repair original-build code, and whole-file scope keeps those inside
  touched files). It is also not the full PR diff, today's behaviour.

## Scope

### Part A — record each heal round's findings (makes the effect measurable)
- At each iteration, Phase 4.5 appends one record per actionable or dismissed finding to a per-run, gitignored
  file under `.supervisor/` (path chosen by the brief, listed in Touches' owning schema doc). The record holds
  iteration, the reviewed HEAD sha, the fingerprint triple `{file, issue_category, rule}` already defined by
  `skills/review-heal/SKILL.md` §"Anti-Churn Guardrail", severity, and outcome (`fixed` | `dismissed` | `remaining`).
  It holds no finding prose (telemetry rule: plugin facts only).
- Written by a script, not by prompt prose. Fail-SAFE: a write failure logs and never stops the heal loop.

### Part B — scope rounds ≥ 2 to the files the last fix touched, and never repeat
- A new deterministic helper, `loomwright/scripts/heal-review-scope.sh`, takes the previous round's reviewed sha and
  HEAD and prints the review scope: the files changed in `<prev_sha>..HEAD`, minus deleted files. Round 1 prints
  `full` and keeps today's scope byte for byte. An empty result is a fallback to `full`, never an empty review.
- From round 2 on, the reviewer prompt gets that file list as its scope, and must read each file whole. It still
  uses the full PR diff as read-only context to understand intent, but reports findings only in the listed files.
- Every round gets a DO-NOT-REPORT block built from Part A's records: fingerprints already `fixed` or `dismissed`
  in this run. A finding matching one is dropped before it reaches the fix task, and is counted.
- **Fail-CLOSED toward the full review:** if the helper errors, prints nothing, the previous sha is missing or not
  an ancestor of HEAD (rebase, force-push, base sync), or the fix commit is a merge, that round uses today's full
  scope and records `scope_fallback: <reason>`. A broken scope never shrinks a review.
- `--max-rounds`/`max_heal_iterations`, fix-the-class, the anti-churn guardrail and the EXECUTION DIRECTIVE stay as
  they are. Pin mutations stay once per code state (automate-speed/02).

### Part C — ship in shadow mode first (test without trusting it)
- One config key, `heal_review_scope` in `.supervisor/config.json`, resolved like every other Supervisor config key
  (`skills/supervisor-config/SKILL.md`): `shadow` (the shipped default) | `files` | `full`. Unknown or malformed ⇒
  `full`.
- **`shadow`:** rounds ≥ 2 still run today's full-scope review, so findings and fixes are byte-for-byte what they
  are without this item. The helper still runs, and each round's Part A records add `would_scope: [files]` plus,
  per finding, `in_would_scope: true|false`. The DO-NOT-REPORT suppression runs in shadow too, as a count only
  (`would_suppress`). Nothing is dropped.
- **`files`:** Part B's behaviour. **`full`:** today's behaviour with no helper call, the kill switch.
- **Promotion is the owner's call, from evidence:** `heal-review-scope.sh --shadow-report [--since <sha>]` reads the
  Part A records and prints, over every round ≥ 2 in shadow: total findings, how many fell outside the would-be
  scope (each with its fingerprint and PR), how many would have been suppressed as repeats, and the review minutes
  the scoped rounds would have skipped (from round durations). The owner flips the key to `files` when the
  outside-scope count is acceptable. This item never flips it.

## Acceptance criteria

**Happy path**
- [ ] Given round 1 of a Phase 4.5 loop, when the reviewer is spawned, then its scope is the full
      `origin/$BASE_BRANCH...HEAD` diff, unchanged from today.
- [ ] Given `heal_review_scope: files` and round 2 after a fix commit that changed files X and Y, when the reviewer
      is spawned, then its scope names exactly X and Y, each to be read whole, and the prompt says to report only
      findings in them.
- [ ] Given `heal_review_scope: files` and a finding fingerprint fixed in round 1, when round 2's reviewer reports
      the same fingerprint, then it is dropped before the fix task and counted in the round's record as
      `suppressed_repeat`.
- [ ] Given no `heal_review_scope` key (the shipped default, `shadow`), when round 2 runs, then the reviewer's
      prompt and the fix task's input are identical to `full`, and the round's records carry `would_scope`,
      `in_would_scope` per finding and `would_suppress`.
- [ ] Given shadow records from several items, when `heal-review-scope.sh --shadow-report` runs, then it prints the
      total, the outside-scope findings with fingerprint and PR, the would-suppress count and the skipped review
      minutes. It writes nothing.
- [ ] Given `heal_review_scope: full` or an unknown value, when any round runs, then the helper is not called and
      the round is today's full review.
- [ ] Given `heal_review_scope: files` and a finding dismissed in round 1, when it is reported again, then it is
      suppressed the same way and stays in `heal_dismissed` exactly once.
- [ ] Given any heal round, when it ends, then Part A's file holds one record per finding with all listed fields.

**Edge cases**
- [ ] Given the previous reviewed sha is not an ancestor of HEAD, when round N starts, then the round runs the full
      scope and records `scope_fallback: not_ancestor`.
- [ ] Given the fix commit only deleted files or left no file to scope, when round N starts, then the round runs
      the full scope and records `scope_fallback: empty_scope`. A deletion can break references elsewhere, so an
      empty scope never skips a review.
- [ ] Given stacked mode (`STACKED=true`), when round ≥ 2 runs, then the same file scoping applies inside the
      stacked diff.

**Error scenarios**
- [ ] Given `heal-review-scope.sh` is missing or exits non-zero, when round N starts, then the full scope is used
      and `scope_fallback: helper_error` recorded. The loop never stops on this.
- [ ] Given Part A's record write fails, when the round continues, then the loop is unaffected and one
      `record_decision` line names the failure.

## Validation (must pass before merge)
1. `loomwright/scripts/test-heal-review-scope.sh`: round 1 → `full`; a two-commit scratch repo → exactly the
   changed files; deleted file excluded; non-ancestor → fallback; merge fix commit → fallback; deletion-only → fallback.
   Each case runs as a mutation control: the test must fail when the helper is edited to return `full` always.
2. A prompt-seam test (pattern: `scripts/test-execution-directive-seam.sh`) proves the round ≥ 2 prompt under
   `files` carries the scope block and the DO-NOT-REPORT block, and that round 1 under every mode, and every round
   under `shadow` and `full`, has a prompt byte-identical to today's.
2a. **Pre-release run, no deployment:** one real `/automate` item run headless with `claude -p --plugin-dir <this
   branch>/loomwright` (it loads only the checkout's copy; see the plugin-dir memory) in `shadow` mode. The PR body
   pastes the item's Part A records and the `--shadow-report` output. If no round ≥ 2 happened, it says so and runs
   a second item.
3. Token budgets updated for the edited skill and agent (`docs/prompt-token-budgets.json` plus the mirror rows).
4. `bash scripts/check-version-bump.sh` passes; `bash scripts/ci-local.sh --affected` is green.

## Measurements (after merge, not a merge gate)
- Shadow phase: run `--shadow-report` after at least 8 items with a round ≥ 2. That is the promotion evidence.
- After the owner flips to `files`: re-run automate-speed/23's report on at least 8 more merged items.
  Target: median Phase 4.5 duration down, share of items at max rounds down, and `self_heal_misses` plus CI
  `review_rounds` per item **not up**. If misses rise, revisit D1 rather than raise the round cap.
- From Part A's records: share of round ≥ 2 findings suppressed as repeats, and share of rounds that fell back.
- Frozen commit: the "before" group is every item merged at or before main `5fadddb` (main when this item was
  written); the "after" group starts at this PR's merge commit.

```
git log --oneline -1 5fadddb
```

## Non-goals
- Changing round 1, the round cap, the fix floor, the CI `claude-review` lens or the `/review-pr` drain.
- Hunk-only scoping (rejected in D1).
- Risk tiers that change review depth (considered and not queued; see the plan doc).

## Assumptions
- Most original-build misses that late rounds find sit in files the previous fix touched. Not measured. Shadow
  mode (Part C) measures exactly this before any review is narrowed: `in_would_scope: false` findings are the ones
  `files` mode would have missed.
- The fingerprint triple is stable enough across rounds to match a repeat. If it isn't, suppression under-fires,
  which is safe because it only makes the review report more.

## Risks
| Risk | Impact | Mitigation |
|---|---|---|
| A real bug outside the touched files goes unreported by Phase 4.5 | reaches the CI lens or the owner | round 1 stays full; CI lens unchanged; the Measurements gate watches misses |
| Over-eager repeat suppression hides a regression a fix reintroduced | a reintroduced bug ships | suppress only on exact fingerprint match, and only for fingerprints whose fix commit is still in HEAD's history |
| Prompt grows instead of shrinking | slower reviews | the blocks are lists from a script; token budget gate applies |

## Depends on
none

## Touches
loomwright/skills/self-heal-advisory
loomwright/skills/supervisor-config/SKILL.md
loomwright/agents/code-reviewer.md
loomwright/scripts/heal-review-scope.sh
loomwright/scripts/test-heal-review-scope.sh
loomwright/docs/result-schemas/supervisor-result.md
loomwright/docs/prompt-token-budgets.json
loomwright/docs/ARCHITECTURE_CONTRACTS.md
scripts/test-execution-directive-seam.sh
changelog.d/phase45-converging-re-review.md
