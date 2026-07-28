# Eval-derived findings and fixes

**Date:** 2026-07-28
**Provenance:** produced while executing `FABLE_PARITY_EVAL.md` corpus entry #1
(`vikashruhilgit/ntfs-tool` `03-tree-and-find.md`, base `5df1ded`). Three arms attempted, ~$160
spent. Every claim below carries a `file:line` citation or a run measurement — **nothing here is
inferred from memory.** Where a claim was checked and turned out wrong, the correction is recorded
rather than the claim removed.

Sibling records: `FABLE_PARITY_EVAL.md` (the pre-registered protocol + Results),
`SDK_RUNNER_SPIKE.md` (the layer item 1 addresses), `NORTH_STAR_DIRECTION.md`.

---

## The evidence in one table

| | Arm 1 (bare Claude Code) | Arm 2 (Loomwright default) |
|---|---|---|
| `post_merge_defects` (BLOCKING+HIGH `new`) | **0** | **0** |
| other `new` findings | 2 MED, 3 LOW | 4 MED, 6 LOW |
| diff | 1,838 ins / 12 files | 1,656 ins / 10 files |
| tests | 286 + 35 green | 272 + 32 green |
| wall clock | **41 min** | **~3 hours** |
| cost | **$9.70** | **$61.76** |
| agents spawned | 1 | ~12 (5 workers + 5 reviewers + orchestrator + EM) |

**Loomwright cost 6.4× and took 4× longer for the same measured defect outcome.** It did catch a
doc-drift cluster arm 1 had no mechanism to find (`CLI.md` advertising this exact feature as "future
work", a README subcommand count off by two, a missing CHANGELOG entry) — all of it *below* the
BLOCKING/HIGH line the metric counts.

**n=1, and this requirement favours the bare arm** (well-specified, purely additive, no migration
across existing call sites). The migrations — corpus entries 2 and 3 — are where fan-out should earn
its cost, and they were not run. **Nothing below should be read as "parallelism is worthless."**

---

## Fix 1 — Decomposition has no counter-pressure, and there is no single-agent path

**Highest value. This is the 6.4×.**

### Problem

Three rules combine to guarantee fan-out, and nothing opposes them:

| Location | Rule | Effect |
|---|---|---|
| `skills/supervisor-readiness/SKILL.md:359` | *"Map each criterion to exactly one subtask"* | acceptance criteria **manufacture** subtasks |
| `agents/orchestrator.md:54, 81, 155, 156, 187` | *"Every task includes mandatory code review subtask"* (stated 5×) | **doubles** whatever the above produced |
| `agents/supervisor.md:19` | Fast path fires only `If ≤ 1 subtask OR --sequential` | fast path is **unreachable** for any multi-criterion requirement |

7 acceptance criteria → 5 implementation subtasks → 5 paired review subtasks → **10 agent cold
starts**. Each starts with an empty context and re-reads the same files. That re-acquisition — not
prompt overhead — is where the 6.4× goes. Five `code-reviewer` spawns alone are
5 × 22,118 = **110,590 tokens of reviewer prompt floor** before a line of code is read
(`docs/prompt-token-budgets.json`).

**Verified absent:** grep of `agents/orchestrator.md`, `agents/launch-pad-runner.md`, and
`skills/async-orchestration/SKILL.md` for *context window / fits in context / one context / context
budget* returns only `async-orchestration:369 "## Context Budget During EXECUTE"` — which is the
Execute Manager's own **tool-call** budget during the poll loop, not whether the work fits one
agent. **No phase ever asks "could one agent do this?"**

**`--sequential` does NOT fix it** (corrected mid-investigation — I assumed it would). The fast-path
body still spawns per-subtask agents:

```
1. For each subtask (in order):
   - Spawn implementation worker (blocking)
   - Spawn Code Reviewer (blocking)
2. Skip all worktree logic and Execute Manager delegation
```

It skips worktrees and the Execute Manager agent; it still pays all 10 cold starts. **There is
currently no mode in the plugin that reads the codebase once and completes the job in one context.**

### Fix

**(a) Invert the decomposition default.** Replace "map each criterion to exactly one subtask" with:
default to **one** subtask; split only for a stated concrete reason — two subtasks would edit the
same file, the work exceeds one context, or there is genuine parallelism to exploit. Acceptance
criteria become a *checklist for one worker*, not a subtask generator.

**(b) Add a true single-agent path.** One worker executes all subtasks in one context, then **one**
review of the integrated result. This does not exist today in any mode.

**(c) Make it a threshold, not a removal.** Isolation is real insurance — it stops one worker's
mistake contaminating siblings. Fan out above a bound (file count / estimated context / detected
file conflicts), stay single-agent below it.

**Risk:** loses per-subtask isolation below the threshold. Mitigate with the deterministic
per-subtask gate that already exists — `outputs_verified` (`agents/execute-manager.md:222`) gates
before any reviewer spawns — plus tests/lint/LSP on the branch. Those cost zero tokens.

**Verification:** re-run arm 2 on `tree-and-find` with the widened path, same base commit. Target:
arm-1-like cost and wall clock, retaining the plan review, the PR, and the doc-drift catch.

---

## Fix 2 — Finish the SDK runner instead of cutting it

**Correction to an earlier verdict in `FABLE_PARITY_EVAL.md`.** Arm 3 aborted, and the CUT recorded
there is correct *under the pre-committed rule* — but the rule measured an **unfinished artifact**,
not the approach. The root cause is two fixable gaps, both read from source:

**Blocker A — the parser silently discards every dependency edge** (`sdk-spike/src/runner.ts`):

```ts
328:  /^\|\s*(\d+)\s*\|([^|]+)\|[^|]*\|([^|]+)\|/   // id MUST be \d+  → "1a" dropped
362:  /^subtask_(\d+):/                              // YAML key shape  → "# Subtask 1a" no match
385:  /\bfrom:\s*(\d+)/                              // unquoted int    → from: "1a" no match
```

If line 362 never matches, `current` stays `null`, and both the `provides`/`requires` handlers
(373, 382) guard on `current` — so every edge is dropped **with no warning**. Observed live:
subtasks 2 and 3 spawned concurrently onto the same file the brief serialized.

**Blocker B — dependency ordering is implemented, visibility is not.** The wave scheduler is correct
(`runner.ts:141-151` — a subtask launches only when all `requires` producers are `completed`), but:

```ts
431:  git(repoRoot, "worktree", "add", "-b", branch, wtPath, featureBranch);
```

Every worktree branches from `featureBranch`, unconditionally. `commitWorktree` (446) commits to the
per-subtask branch, and the runner **never merges between waves** — it only records
`mergeOrder.push(branch)` (117) and defers merging to the caller (its own comment, 168). So a
dependent waits for its producer to finish and still cannot see a line it wrote.

### Fix

1. **Merge completed subtask branches into `featureBranch` at the end of each wave**, before the next
   wave's worktrees are created. Line 431 then works unchanged. *The conflict handling is the real
   work* — that is exactly where the pre-merge safety gate spends its effort, and `tree-and-find` hits
   it (subtasks 2 and 3 both touch `ntfsctl.swift`).
2. **Make the parser tolerant** of non-numeric ids and the `# Subtask 1a` key form.
3. **Re-run arm 3** on the same corpus entry and base commit; record as a **second row**, leaving the
   abort row intact. "Fix until it passes" is how a pre-registered experiment gets laundered — both
   attempts stay visible.

**Separately:** Launch Pad's id scheme is **non-deterministic across runs** — the arm-2 brief used
numeric ids (`1`–`5`, confirmed by its `subtask: N` commits), the arm-3 brief mixed `1`–`5` with
`1a`/`1b`, from a byte-identical prompt. That is a defect on Launch Pad's side regardless of the
runner.

---

## Fix 3 — One writer for progress state, derived views, delete the other five

**Owner insight, 2026-07-28, with measurement behind it.**

Progress is recorded by **six** prompt-instructed mechanisms: Context-Keeper `set_task`/
`update_phase`, the Supervisor inline `## Session` write, `set_subtasks`, Execute Manager's
`queue_ck_update`/`flush_ck_batch`, the Session Logging catalog, and `checkpoint`/`record_decision`.

**Measured miss rate across this repo's session logs:**

| Event | Count | Written by |
|---|---|---|
| `token_ledger` | **560** | hook |
| `phase_transition` | 6 | agent |
| `agent_result` | 4 | agent |
| `agent_spawn` / `subtask_complete` | 3 / 3 | agent |

One session should emit 5–6 `phase_transition` events alone; 11+ sessions produced six total. Hooks
fire because the runtime fires them; instructions compete with the task for attention and lose
exactly when the task is hard.

**Consequence, observed:** on 2026-07-27 all 5 subtasks were merged while `.supervisor/state.md`
read `phase: ACQUIRE` with every subtask `PENDING`. `--continue` would have re-executed the whole
job. **The read-side guard shipped** (`scripts/reconcile-resume-state.sh`, PR #110) — it detects the
lie at resume and refuses with `resume_state_stale`. It does **not** stop the lie being written.

### Fix

1. **One writer, and it is a hook.** Extend the existing `SubagentStop`/worker hook to append one
   `subtask_complete` event to the session JSONL — modelled on `emit-token-ledger.sh`, which has
   proven the pattern 560 times. (Payload shape is `last_assistant_message` +
   `agent_transcript_path`, **not** `result_block`.)
2. **`state.md` becomes derived** — projected from the append-only log on demand. An append-only log
   has no write conflicts, which **sidesteps the Context-Keeper sole-writer contract rather than
   fighting it.**
3. **Delete the other five.** ~200 lines of bookkeeping prose across `supervisor.md`,
   `execute-manager.md`, `context-keeper.md`, and `state-management/SKILL.md`, inside a **258,110
   proxy-token** prompt inventory billed on every spawn. A surviving instruction re-introduces the
   miss rate — deprecating is not enough.
4. **Prove it.** Re-run the event-count measurement after the change.

---

## Fix 4 — Cheap, verified, low risk

### 4a. Leaf agents cannot see their own budget

```
agents/worker.md:6           maxTurns: 40      prose: NONE
agents/code-reviewer.md:14   maxTurns: 40      prose: NONE
agents/supervisor.md:87      "Budget: 50 tool calls"    ← in prose
agents/execute-manager.md:82 "Budget: 60 tool calls"    ← in prose
```

Orchestration roles know their ceiling; leaf roles don't — backwards, since leaves are what you
spawn ten of. Two frontmatter values into prose.

> **Caveat, stated because Fix 3 is in this same document:** this is *another instruction*, and it
> inherits the ~90% adherence problem measured above. The harness already enforces `maxTurns`;
> telling the agent is advisory. Worth doing because it is nearly free — do **not** expect it to
> change behaviour.

### 4b. Anti-overlap rule for Phase 4.5

The heal bound is visible (`max_heal_iterations` in the loop pseudocode), but there is no rule
saying *don't re-derive what a prior gate already found*. One sentence; directly reduces the
Phase-4.5-re-reviews-what-per-subtask-review-found duplication.

### 4c. Unify `tools:` lists to enable any cross-agent caching

**13 distinct `tools:` lists across 14 agents** (only `orchestrator` and `qa-strategist` match).
Render order is `tools` → `system` → `messages`, so different agent types **diverge at byte 0** and
share no cache prefix, structurally.

**This reorders v15.13.0's shared-agent-prefix work:** that block sits *after* tools in render order,
so **it cannot buy cross-agent sharing until the tool lists match.** Unify to a superset first, and
the shared prefix then extends a shared span instead of being decorative. (Caveat: minimum cacheable
prefix is 512 tokens — a small tools block may not clear the floor alone; the shared prefix stacked
behind it is what gets over.)

### 4d. Split `self-heal-advisory` before routing anything

110,714 bytes / 1,015 lines. Part 1 (advisory machinery) starts line 45; Part 2 (the loop protocol)
starts line 508. Phase 4.5 needs **Part 2** and currently reads the whole file, per heal iteration.
Split at 508. Route-before-split just pulls the same bulk through a different door.

---

## Fix 5 — Measurement defects (record; do not silently patch)

**5a. `post_merge_defects` has no discriminating power at this requirement size.** Both arms scored
0 — not because they are equal, but because a competent model on a well-specified 1,700-line
requirement produces no BLOCKING/HIGH defects in *either* arm. The threshold sits above the entire
signal range.

**5b. `wall_tokens` under-counts multi-agent arms ~6×.** The `usage` object counts only the
orchestrating thread; workers and reviewers appear in `total_cost_usd` but not in token counts. Arm 2
reads **1.1×** arm 1 on output tokens and **6.4×** on cost. Naive comparison would have produced a
badly wrong verdict. **Cost is the valid comparator for multi-agent arms.**

**The pre-registration forbids adding a metric after the first run.** So either (i) amend it with a
written reason — noting that amending a live experiment to get a measurable answer is exactly the
move a motivated experimenter makes, so it must be recorded loudly; or (ii) pick corpus entries where
defects appear above the threshold. Entries 2 and 3 are *migrations* across existing call sites,
where a missed site is a genuine defect, unlike `tree-and-find` which was purely additive.

**Cheapest next experiment:** one arm-2 run on corpus entry 3 (~$60), purely to answer *"does Phase
4.5 ever fire on this corpus?"* If it returns `heal_iterations: 0` again, stop — the corpus cannot
measure quality layers, and that is worth more than four more rows of zeros.

---

## Fix 6 — Operational findings worth encoding

**6a. `exit 0` is not a completion signal.** Arm 2's Supervisor reached FINALIZE, backgrounded the
test suite, ended its turn expecting re-invocation, and returned `subtype: "success"`,
`is_error: false` — with no push, no PR, and Phase 4.5 never run. Under `claude -p` there is no next
turn. **Corrected rule:** Loomwright arms *can* run headless, but not fire-and-forget —
`claude -p --resume <session_id> "Continue"` supplies the missing re-invocation (verified: arm 2 then
completed normally, 45 turns / 23 min). Detect state by polling branch/PR, never by exit status.

**6b. Launch Pad's plan/execute boundary is prompt-sensitive.** Across three runs on the same
requirement, behaviour tracked the operational tail: commit-instruction + prohibitions → planned;
commit-instruction alone → **implemented and committed inline**, violating its documented plan-only
contract; no operational instruction → planned correctly. n=1 per variant, so this is an observation,
not a demonstrated mechanism. **Protocol consequence:** Loomwright arms receive the requirement body
only.

**6c. `nohup`-launched runs outlive the session.** A lost task notification is not evidence the work
stopped — check `pgrep` and the branch. Same discipline as 6a.

---

## Deliberately NOT doing

- **Finishing the 5-requirement corpus as-is.** With 5a unresolved, four more requirements buy four
  more rows of zeros at $200–400.
- **Cutting `--multi-voter-heal`.** It never ran; the decision rule is per-layer, and condemning a
  layer that never executed is the exact unearned conclusion this eval exists to prevent. It operates
  only on BLOCKING/HIGH findings, and arm 2 had zero — so isolating it on *this* requirement would
  also measure nothing.
- **Deleting `sdk-spike/`.** Superseded by Fix 2.
- **Generating the CI-gate surfaces** (doc-currency, skills-index-sync, token-budget, command-sync,
  contract-parity, shared-prefix). The insight is right — six gates policing drift between surfaces
  that could be generated from one source, and CLAUDE.md already admits doc-currency "scans only
  high-confidence current-claim phrasings." But it is a quarter's work, not a fix.

---

## Suggested order

| # | Fix | Why this order |
|---|---|---|
| 1 | **Fix 1** — decomposition + single-agent path | The 6.4×. Needs no new experiment to justify; measurable against arm-1/arm-2 data already in hand |
| 2 | **Fix 3** — one writer, derived state | Deletes ~200 prompt lines *and* closes a data-loss hole. Independent of Fix 1 |
| 3 | **Fix 4a/4b/4d** | Cheap, verified, low risk. 4d unblocks any later routing work |
| 4 | **Fix 5** — one arm-2 run on corpus entry 3 | Decides whether the eval can continue at all, for ~$60 |
| 5 | **Fix 2** — finish + re-measure the SDK runner | Real work with uncertain payoff; do it after Fix 1, since Fix 1 may reduce how much Phase 3 orchestration is left to optimise |
| 6 | **Fix 4c** — unify tools lists | Plugin-wide frontmatter change; own PR |

> **Fix 1 before Fix 2 is load-bearing.** If Fix 1 collapses most runs to a single agent, the SDK
> runner is optimising a fan-out path that fires far less often — which changes whether finishing it
> is worth the effort at all.
