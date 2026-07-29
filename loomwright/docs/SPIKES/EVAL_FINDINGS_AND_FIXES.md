# Eval-derived findings and fixes

**Date:** 2026-07-28
**Provenance:** produced while executing `FABLE_PARITY_EVAL.md` corpus entry #1
(`vikashruhilgit/ntfs-tool` `03-tree-and-find.md`, base `5df1ded`). Three arms attempted, ~$160
spent. Every claim below carries a `file:line` citation or a run measurement — **nothing here is
inferred from memory.** Where a claim was checked and turned out wrong, the correction is recorded
rather than the claim removed.

Sibling records: `FABLE_PARITY_EVAL.md` (the pre-registered protocol + Results),
`SDK_RUNNER_SPIKE.md` (the layer item 1 addresses), `NORTH_STAR_DIRECTION.md`.

> **Extended 2026-07-28 (same day, follow-on session).** Items **4e, 4f, 4g and Fix 7** were added
> after a structural audit of the prompt/hook/review surfaces. They are additive — no existing
> finding, number, or ordering rationale was altered. Each carries its own `file:line` citation and
> was verified against the working tree, not inferred. Overlap check performed against
> `.supervisor/requirements/token-economy/` (items 01–06) before adding: none of the four duplicate a
> shipped or pending item there.

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

> **STATUS 2026-07-28:** steps (a), (b), and (c) below **SHIPPED** in **v15.15.0** via `feature/single-agent-default` — the decomposition default is inverted (ONE subtask default, split requires one of three
> named reasons, single home `skills/supervisor-readiness/SKILL.md` §"Decomposition Threshold"), a true
> Single-Agent Path exists in `agents/supervisor.md` (one worker, all criteria, one context, no per-subtask
> Code Reviewer — Phase 4.5 is the sole review), and it is a threshold (above it, worktrees/Execute
> Manager/per-subtask review are byte-identical to before). See `CHANGELOG.md` v15.15.0 for the full list of
> synced surfaces. **Correction to the problem table below, found during planning:** the *"stated 5×"* count
> for the mandatory-paired-review rule in `agents/orchestrator.md` was wrong — re-counted by anchor-phrase
> grep at plan time, the true count in the pre-change file was **12×** (lines 45, 54, 81, 91, 155, 156, 157,
> 187, 195, 207, 208, 398), not 5. Recorded here rather than silently rewritten.

**Highest value. This is the 6.4×.**

### Problem

Three rules combine to guarantee fan-out, and nothing opposes them:

| Location | Rule | Effect |
|---|---|---|
| `skills/supervisor-readiness/SKILL.md:359` | *"Map each criterion to exactly one subtask"* | acceptance criteria **manufacture** subtasks |
| `agents/orchestrator.md:54, 81, 155, 156, 187` | *"Every task includes mandatory code review subtask"* (stated 5×; **corrected 2026-07-28 — true count was 12×**, see STATUS note above) | **doubles** whatever the above produced |
| `agents/supervisor.md:216, 253` | Fast path fires only `If ≤ 1 subtask OR --sequential` | fast path is **unreachable** for any multi-criterion requirement |

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

> **STATUS 2026-07-28:** steps 1 and 2 below (wave materialization + tolerant parser) **SHIPPED and
> MERGED** via PR #111 (carried into main by PR #113's merge). Remaining Fix 2 work: the **arm-3
> re-run** (recorded as a second row beside the abort row) and the **Launch Pad id-determinism**
> defect. The owner's standing decision: the SDK runner is the chosen substrate — fix it, don't cut
> it; see `FINAL_STATE_GOAL.md`.

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

### 4d. Split `self-heal-advisory` before routing anything — EVALUATED AND REJECTED (2026-07-29)

**Status: rejected on measurement, not deferred.** The proposal below is preserved as originally
written; the correction follows it. Recorded here rather than deleted so the reasoning is auditable
and item 07 does not inherit a dead precondition.

> *As originally written:* "110,714 bytes / 1,015 lines. Part 1 (advisory machinery) starts line 45;
> Part 2 (the loop protocol) starts line 508. Phase 4.5 needs **Part 2** and currently reads the
> whole file, per heal iteration. Split at 508. Route-before-split just pulls the same bulk through
> a different door."

**Why it was rejected.** Every load-bearing clause of that premise is wrong or overstated. Measured
2026-07-29 against `loomwright/skills/self-heal-advisory/SKILL.md` as it stands after 4b landed:

| Claim | Measured reality |
|---|---|
| "Phase 4.5 needs **Part 2**" | **Part 2 invokes all ten Part 1 sections.** Its steps **1c / 1d / 1e** each read *"run the … step from **Part 1** of this skill"* verbatim, and it calls back again at §"System Twin advisory checks" (*"protocol in Part 1 of this skill"*, which pulls in §Post-review advisory checks and its three children), §"Contract builder", §"Advisory Twin delta line", and §"Hard-signal dual emission". The ten Part 1 sections are §Prior-churn advisory, §Area-knowledge advisory, §House-rules advisory, §Post-review advisory checks, §Contract-conformance check, §Benchmark run, §Ground-truth execution, §Contract builder (WRITE path), §Advisory Twin delta line, §Hard-signal dual emission. **There is no Part 1 material Phase 4.5 does not use.** |
| "reads the whole file, **per heal iteration**" | The Read happens **once at phase entry**, not per iteration — `agents/supervisor.md` Phase 4.5 §"Protocol authority (read at phase entry)", corroborated by Part 2 step 1a and by `commands/supervisor.md` on the inline path. |
| "110,714 bytes / 1,015 lines" | **112,455 bytes / 1,016 lines** (`wc -c` / `wc -l`, 2026-07-29). The figure had already drifted when written and drifts again on every edit — which is why the sizes here carry a measurement date. |
| implied saving | Part 2 (from the `# Part 2 — Phase 4.5 SELF_HEAL Loop Protocol` heading to EOF) is **73,142 bytes / 509 lines — 65% of the file**. Part 1 proper is 36,645 bytes / 463 lines. So even a clean split defers a minority of **one** read. |

Consequence: the sub-fix's own acceptance criterion — *"Phase 4.5 reads only Part 2 post-split
(verified by the Read call sites)"* — is **not satisfiable** without also moving the Part 1
procedures Part 2 calls, which is the split undone. 4d is dropped from the Fix 4 batch; 4a, 4b and
4e landed without it.

> **Citation convention for this section.** Part 1 / Part 2 material is cited by **section name, not
> absolute line number**. `self-heal-advisory/SKILL.md` is a 1,000+-line file under active edit; the
> original 4d text pinned "line 508" and "line 45" and both were already at risk, per the repo's own
> *absolute line-ref drift in prose edits* lesson.

### 4e. Six hooks spend a model call to do schema validation

**Status: LANDED alongside 4a/4b in the Fix 4 cheap batch (2026-07-29); ships in the next release.**
(No version number is asserted here: at the time of writing `plugin.json` still reads 15.16.0 and the
bump is a later subtask of the same batch.) Five of the six mechanical prompt validators — `worker`,
`execute-manager`, `supervisor-runner`, `qa-executor`, `plan-reviewer` — were converted to
`type: command` scripts (a shared `result_block_parser.py` plus five per-schema validators, all
exit-0-by-contract). The **`code-reviewer` prompt hook was deliberately retained** per the caveat at
the end of this section: its cross-field + severity-cap logic is richer than presence-checking, and
it is now the one remaining prompt validator on a `SubagentStop` matcher. Hook count unchanged (type
conversions, not additions); the saving is **runtime model calls avoided**, not prompt-inventory
bytes.

> The measurement below is a **frozen as-measured snapshot** from the original spike and is
> deliberately NOT restated to post-change values — it records what was true when the finding was
> made.

`hooks.json` holds **22 entries across 10 events. Eight are `type: prompt`** — each one a model call
carrying the finishing agent's transcript, at a 30s timeout. Six of the eight assert nothing but the
presence and shape of a JSON result block:

| Matcher | Asserts |
|---|---|
| `SubagentStop[worker]` | `WORKER_RESULT` has `schema_version`, `task_id`, `status`, `files_modified` |
| `SubagentStop[code-reviewer]` | `CODE_REVIEW_RESULT` v3 fields + issue categories |
| `SubagentStop[execute-manager]` | `EXECUTE_RESULT` / `EXECUTE_CHECKPOINT` |
| `SubagentStop[supervisor-runner]` | `SUPERVISOR_RESULT` outcome, subtask statuses, PR URL |
| `SubagentStop[qa-executor]` | `QA_RESULT` counts + summary |
| `SubagentStop[plan-reviewer]` | `PLAN_REVIEW_RESULT` decision + issues |

The remaining two match on `*` — `Stop` (identify the agent from its own system prompt, then check
its result block) and `TaskCompleted` — so they fire far more broadly than the six above.

**The counter-example is already in this repo.** `SubagentStop[launch-pad-runner]` runs
`scripts/validate-launch-pad-result.py` as `type: command` and validates
`LAUNCH_PAD_RESULT` deterministically, for zero tokens, exiting 0 by contract. That is the same job.

On the 10-cold-start run measured above, the six fire roughly 13–14 times.

> **This is Fix 3's thesis applied to validation.** Fix 3 measured hooks firing 560 times while
> agent-instructed events landed 6 — *"hooks fire because the runtime fires them."* The same
> asymmetry says a hook that merely checks field presence should be a script, not a prompt. Unlike
> 4a, this one does **not** inherit the adherence problem: it removes an instruction rather than
> adding one.

**Caveat before converting all six:** the `code-reviewer` prompt is 3,120 chars and runs cross-field
+ severity-cap checks that are richer than presence-checking. Convert the five mechanical ones first;
port the reviewer's severity-cap logic to script deliberately, or leave it as the one prompt hook
that earns its call.

### 4f. Route skills instead of preloading them — and the A/B is already built

The Supervisor exists on two paths, and only one of them preloads:

| Path | Preloaded via frontmatter | Read on demand |
|---|---|---|
| `--agent loomwright:supervisor-runner` | **7 skills** (`agents/supervisor.md` frontmatter) | 4 (`supervisor-config`, `preflight-sync`, `async-orchestration`, `self-heal-advisory`) |
| inline `/supervisor` — **the recommended path** | none | 5 at phase entry |

Same workflow, same phases, both shipping. **The inline path is the existing proof that preloading
is not required.**

**Concrete double-pay on the agent path:** `async-orchestration` appears in the frontmatter
`skills:` list *and* is `Read` at Phase 4 entry — **9,078 proxy tokens paid twice** in one context.
**Caveat (verified after first writing this):** the double-load is *documented as intentional* —
`agents/supervisor.md` Phase 4 §"Protocol authority (read at phase entry)" calls the Phase-4 Read "a
refresh guarantee for compressed contexts, not the first load." (Cited by section name per §4d's
convention note; the original `:336` pin had already drifted — that sentence now sits at `:361` and
line 336 is an unrelated "Re-queue producer" bullet.) So this is a stated trade-off against context
compaction, not an oversight; the fix must argue the trade-off (routing + re-Read-on-compaction beats always-preload), not report a bug.

**Fix:** replace the frontmatter `skills:` block on `supervisor-runner` with the phase-entry `Read`
calls the inline path already uses. Preloading guarantees payment; a routed read makes it
conditional on the phase actually being reached — and a run that ends at Phase 3 never pays for
Phase 4.5's protocol at all.

**Ordering: no precondition — 4f is independent of 4d** (corrected 2026-07-29; this previously read
*"strictly after 4d — routing an unsplit 110,714-byte skill changes when it is paid, not how much"*).
That sentence modelled `self-heal-advisory` as a 4f routing target. **It is not one.**
`agents/supervisor.md` frontmatter preloads exactly the seven skills the table above counts, and
they are `workflow-management`, `async-orchestration`, `state-management`, `context-summarization`,
`supervisor-readiness`, `commit`, `quality-checklist`. `self-heal-advisory` is **absent** from that
list and is already read-on-demand at Phase 4.5 entry on **both** the agent and inline paths — as
this section's own table shows, in the "Read on demand" column of both rows. There is nothing for 4f
to route it *from*. 4f's actual double-pay is **`async-orchestration` at 9,078 proxy tokens**, the
one skill that is both frontmatter-preloaded and Read at Phase 4 entry — and its size is unaffected
by anything 4d proposed. **4d has since been evaluated and rejected** (§4d above), which strands
nothing here: item 07 is unblocked.

### 4g. Brief staleness is never checked — only remote overlap is

Phase 1.5 PRE-FLIGHT SYNC reconciles the *requested work* against remote state and classifies
CLEAR / OVERLAP / SUPERSEDED (`skills/preflight-sync/SKILL.md`). It never asks whether **the brief
itself** has gone stale between Launch Pad writing it and Supervisor executing it.

It also cannot: Launch Pad records `source_requirement` as a path (`agents/launch-pad.md:149`,
emitted at `:469`) but **stamps no base commit**, so there is no anchor to measure drift from.

**Fix, in the order the dependency requires:**

1. Launch Pad Phase 5 PACKAGE stamps `- **Base commit:** {sha}` beside the existing
   `- **Source requirement:**` line under `## Environment`.
2. Phase 1.5 gains a **fourth signal** keyed on churn over the anticipated file set — which
   preflight-sync already computes for its file-intersection test:
   ```bash
   git log --oneline "$BRIEF_BASE_SHA"..origin/"$BASE_BRANCH" -- $ANTICIPATED_PATHS | wc -l
   ```

**Use churn, not elapsed time.** A three-week-old brief against an untouched subsystem is fine; a
two-hour-old brief against one someone just refactored is not. The clock measures the wrong thing,
and the file-set intersection is already there.

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

## Fix 7 — The review layer has no counter-pressure either

**Fix 1's sibling.** Fix 1 shows nothing opposes subtask fan-out. The same is true of review passes:
every reviewing layer was added independently, each defaults ON, and no rule anywhere says a later
pass should skip what an earlier one already covered. 4b adds that sentence for Phase 4.5 vs
per-subtask review; this is the rest of the surface.

**What runs by default on one PR, verified:**

| # | Pass | Default | Citation |
|---|---|---|---|
| 1 | per-subtask `code-reviewer`, one per subtask | on | Fix 1 above (5 spawns on the measured run) |
| 2 | Phase 4.5 `code-reviewer` on the integrated diff | on unless `--skip-self-heal` | `agents/supervisor.md:361` |
| 3 | detached `/review-pr --until-mergeable` drain | **on** — `auto_until_mergeable` default `true` | `commands/supervisor.md:60` |
| 4 | CI `claude-review` | on `opened, synchronize, ready_for_review, reopened` | `.github/workflows/claude-code-review.yml` |

**Be precise about which of these is duplication.** Pass 3 has two jobs: it re-reviews the diff
*and* it drains external channels (CI checks, bot threads, review comments). **The channel-draining
is not duplicative — it is the healing arm for pass 4.** Its own diff review, layered on top of pass
2's, is. So the real finding is: **two LLM reviews of the same diff before a human sees it (2 and
3's review half), plus a third independent one in CI whose findings 3 then heals.**

**Two qualifiers that stop this being a clean cut:**

- `claude-code-action` **skips itself on any PR touching a workflow file** and still exits 0 — a
  green check with zero comments. So pass 4 is not reliably present, and a PR that modifies CI can
  never be reviewed by it.
- The drain can **exit before a slow CI review posts** — the dispatch marker means *dispatched*, not
  *completed*. Dropping pass 3 without confirming pass 4 actually posted would remove the only thing
  that heals CI findings.

### Fix

**Two independent lenses, not four passes.** Keep pass 2 (sees working tree + brief + rubric) and
pass 4 (independent context, sees only the PR — different information, therefore different
findings). Drop pass 1 per Fix 1's deterministic gate. Reduce pass 3 to its **drain-only** role:
heal what pass 4 raised, skip its own redundant diff review.

**Verify before cutting anything:** assert on posted comments and reviews
(`gh pr view <n> --json comments,reviews`), never on run conclusion — a green `claude-review` is not
evidence a review happened.

**Measure it afterwards.** `/pr-postmortem` already classifies review rounds into six root-cause
classes into `.supervisor/postmortem/results.jsonl`. Whether dropping a pass raised the defect rate
is answerable from data already being collected — don't argue it.

> **Counter-pressure, not deletion — same shape as Fix 1(c).** Review count is not review quality:
> four passes with the same lens over the same diff find the same things four times. Two passes with
> *different information* find different things. The goal is a stated rule about when a pass is
> owed, which is what the plugin has never had.

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
| 3 | **Fix 4a/4b/4e** | Cheap, verified, low risk. 4e removes model calls rather than adding instructions. **Corrected 2026-07-29:** this row read *"Fix 4a/4b/4d/4e … 4d unblocks 4f"*. **4d was evaluated and REJECTED** on measurement and never unblocked anything — see §4d |
| 4 | **Fix 7** — review counter-pressure | Fix 1's sibling and partly subsumed by it (pass 1 dies with Fix 1). Do the pass-3 reduction after, once the drain's CI-healing role is confirmed live |
| 5 | **Fix 5** — one arm-2 run on corpus entry 3 | Decides whether the eval can continue at all, for ~$60 |
| 6 | **Fix 2** — finish + re-measure the SDK runner | Real work with uncertain payoff; do it after Fix 1, since Fix 1 may reduce how much Phase 3 orchestration is left to optimise |
| 7 | **Fix 4f** — route instead of preload | Fixes the `async-orchestration` double-pay in the same change. **Corrected 2026-07-29:** this row read *"Strictly after 4d."* — a void precondition (`self-heal-advisory` is not a 4f routing target); step 7 has no precondition, see §4f |
| 8 | **Fix 4g** — brief staleness signal | Two-part (Launch Pad stamp, then preflight signal); no value until the stamp exists |
| 9 | **Fix 4c** — unify tools lists | Plugin-wide frontmatter change; own PR |

> **Fix 1 before Fix 2 is load-bearing.** If Fix 1 collapses most runs to a single agent, the SDK
> runner is optimising a fan-out path that fires far less often — which changes whether finishing it
> is worth the effort at all.

> **Fix 1 before Fix 7, for the same reason.** Fix 1's deterministic per-subtask gate already removes
> review pass 1. Sequencing Fix 7 first would cut a pass that Fix 1 is about to delete anyway, and
> would leave the harder judgment — how much of the drain to keep — decided without knowing how much
> fan-out survives.
