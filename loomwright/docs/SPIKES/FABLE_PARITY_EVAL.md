# Fable-Parity Eval — pre-registered protocol

**Status:** pre-registered — runs pending (post-merge)
**Date:** 2026-07-07
**Provenance:** Fable-parity job (v15.8.0). This is the measurement half of the fable-parity spike —
the same north-star discipline as `ADVISORY_LOOP_EVAL.md` ("earn every bit of surface area with
evidence" — `NORTH_STAR_DIRECTION.md`): the spike shipped a quarantined SDK runner
(`loomwright/sdk-spike/`, opt-in via `--sdk-runner`) and an opt-in multi-voter Phase 4.5
verification (`--multi-voter-heal`); this doc pre-registers HOW we will measure whether either layer
— or the Loomwright orchestration stack itself — earns its keep, BEFORE any run is executed.
Sibling records: `SDK_RUNNER_SPIKE.md` (the capability-parity half + provisional GO/NO-GO),
`ADVISORY_LOOP_EVAL.md` (the pre-register-then-run precedent), `CODE_GRAPH_OWNERSHIP.md`
(build the harness, let the numbers decide).

---

## Question

Does the Loomwright stack measurably beat bare Claude Code on real requirements — and do the two
new opt-in layers (SDK runner, multi-voter heal) measurably beat the Loomwright default? Or is any
of these layers orchestration weight with no effect?

## Decision rule (pre-committed, stated before any run — verbatim from the requirement)

**5 requirements × 3 arms** — (1) bare Claude Code, (2) Loomwright default, (3) Loomwright +
`--sdk-runner` + `--multi-voter-heal`; **metrics:** review rounds to READY, heal_iterations,
post-merge defect findings from an independent `/code-reviewer` pass, wall tokens.

- **The SDK runner graduates to v16 ONLY if arm 3 beats arm 2 on defects or rounds without >1.5×
  token cost.** Otherwise the spike is cut (`sdk-spike/` deleted, `--sdk-runner` seam removed —
  per `SDK_RUNNER_SPIKE.md`'s provisional GO/NO-GO).
- **Loomwright must beat arm 1 (bare Claude Code) or the losing layers get cut** — per-layer: a
  layer that does not move its metric is removed, not defended.

No third outcome. "It feels better" does not count; only the metrics below count.

## Pre-registered metrics (declared BEFORE any run)

| Metric | Source | Direction |
|---|---|---|
| Review rounds to READY | POSTMORTEM_RESULT `review_rounds` / `REVIEW_HEAL_RESULT` `fix_cycles` (arm 1: manual count of review→fix cycles on the scratch branch) | lower is better |
| Phase 4.5 `heal_iterations` | SUPERVISOR_RESULT / `session_end` JSONL (arm 1: n/a — record `-`) | lower is better |
| Post-merge defect findings | ONE independent `/code-reviewer` pass on each arm's final scratch-branch diff (same reviewer configuration for all 3 arms of a requirement); count of BLOCKING + HIGH `new` findings | lower is better |
| Wall tokens | Session usage totals (session JSONL for arms 2–3; the session's own usage reporting for arm 1) | lower is better; arm 3 vs arm 2 capped at 1.5× by the decision rule |

Secondary observables (recorded, not decision inputs): `heal_decision`, `rubric_score` where the
brief has an `## Outcomes Rubric`, arm-3 `findings_raised`/`findings_refuted`/`findings_fixed`
counters (from `SUPERVISOR_RESULT.summary`), wall-clock notes.
**No metric may be added after the first run;** a metric may only be dropped with a written reason
in this file.

> **Amendment (amended 2026-07-18, before any run — additive):** **token-cost-per-subtask** is
> added as a RECORDED secondary observable for arm-3 runs: the additive per-subtask `token_usage`
> object on the SDK runner's EXECUTE_RESULT-equivalent output (worker + reviewer `usage` fields
> aggregated per subtask, plus `total_cost_usd` / `num_turns`; `proxy: true` labels synthesized
> dry-run values — real token counts are never invented). This observable is **explicitly NOT a
> decision input** — the pre-committed decision rule above (including the 1.5× arm-3-vs-arm-2
> wall-token cap) is byte-unchanged by this amendment, and the Results table below was verified
> still EMPTY at amendment time. Recorded per the pre-registration discipline: amendments are
> additive, datestamped, and made strictly before the first run.

## Protocol

1. **Corpus selection:** pick **5 requirements** (small-to-medium, orchestration-shaped — multi-file
   with at least one dependency between subtasks, so the Phase 3 loop is actually exercised); reuse
   completed historical requirements from `.supervisor/jobs/done/` where possible. **At least ONE of
   the 5 MUST have a REAL cross-subtask file dependency** (a dependent subtask that reads/imports a
   file the producer subtask creates) — the SDK runner's known live-mode gap is that `requires` only
   delays SPAWN ORDER: dependents branch from the feature branch and do NOT see producer commits
   (no Step 2a dependency materialization; `SDK_RUNNER_SPIKE.md` residual divergence 3). The corpus
   must surface that gap in the measured arm-3 comparison, not leave it theoretical.
2. **Arms (3 per requirement, 15 runs total):**
   - **Arm 1 — bare Claude Code:** the requirement text given directly to a plain session (no
     Loomwright commands), implemented on a scratch branch.
   - **Arm 2 — Loomwright default:** in-session `/autonomous` (or `/launch-pad` + `/supervisor`) with
     default flags.
   - **Arm 3 — Loomwright + `--sdk-runner` + `--multi-voter-heal`:** same as arm 2 with both opt-in
     layers ON (requires the spike runner built: `cd loomwright/sdk-spike && npm install && npm run
     build`).
3. **Isolation:** scratch branches only — **NO PRs to main from eval runs**; same base commit for
   all 3 arms of a requirement; eval branches deleted after metric extraction.
4. **Harness choice:** prefer **in-session `/autonomous`** over any API-based harness — the
   OAuth-token constraint precedent (the plugin runs on the operator's OAuth session; a headless API
   harness would need a separate API key that is not assumed to exist; same rationale as
   `ADVISORY_LOOP_EVAL.md` protocol step 5).
5. **Part-B demonstration (folded into arm-3 runs):** across the five arm-3 runs, capture **≥1 real
   refuted-finding-not-fixed demonstration** — a BLOCKING/HIGH `new` finding raised by one voter,
   refuted by the other lens, and verifiably LOGGED-not-fixed (the `findings_refuted` counter in
   `SUPERVISOR_RESULT.summary` + the finding's absence from the fix commits). This is the
   requirement's deferred "≥1 real run showing a refuted finding NOT fixed" evidence for
   `--multi-voter-heal`; if no organic refutation occurs in 5 runs, record that fact — do not
   manufacture one. **Confirm item:** for every refuted finding captured, also verify it
   **surfaced to a human** — either the run ended `ESCALATED` or the finding is logged in the PR
   record (Outcome block / `SUPERVISOR_RESULT.summary`), never silently dropped. A refuted-but-
   genuine finding vanishing without a human-visible trace is the specific failure mode the
   refute rule introduces; a demonstration that only shows "not fixed" without showing "still
   surfaced" is incomplete evidence.
6. **Budget:** **15 runs = 5 requirements × 3 arms, hard cap.** If the cap is hit before the corpus
   completes, report what exists — do not extend silently.
7. **Recording:** one row per run in the results table below, filled at run time, never
   retroactively edited (append a correction row instead).

## Corpus

> ### ⚠️ SUPERSEDED — the corpus below is retained for the record, NOT for execution
>
> **Amended 2026-07-27, before any run.** The Loomwright-history corpus in this section is
> **superseded** by §"Corpus v2 (active)" further down. It is kept verbatim because the *reason*
> it was replaced is itself a finding worth preserving. Three defects, all discovered by probing
> rather than reasoning:
>
> 1. **Solution leakage.** Re-implementing Loomwright's own merged history means the running
>    plugin already *contains* the answer the agent is asked to build. No pinning scheme fully
>    removes this — it is inherent to using your own history as the corpus.
> 2. **Arm 3 impossible on 4 of 5 entries.** `--sdk-runner` and `--multi-voter-heal` were
>    introduced in **v15.8.0**, but four base commits predate it (v15.0.0 / v14.27.0 / v14.41.0 /
>    v14.48.0 — verified by grepping `commands/supervisor.md` at each SHA). Under base-commit
>    pinning, arm 3 would run at **n=1**, making the SDK-runner verdict `INSUFFICIENT DATA` by
>    construction.
> 3. **The plugin directory was renamed** (`ai-agent-manager-plugin/` → `loomwright/`), so a single
>    hardcoded `--plugin-dir` path is wrong for the three older entries.
>
> **Consequence:** the "plugin-version policy" open decision recorded in §Amendment history is
> **RESOLVED by this swap, not by choosing between its options** — Corpus v2's work is genuinely
> unimplemented, so there is nothing to leak, no rewind, and every arm runs one fixed plugin
> version with arm 3 available throughout.

Five requirements selected from `.supervisor/jobs/done/`. Selection criteria per §Protocol step 1:
small-to-medium, orchestration-shaped (multi-subtask, Phase 3 loop exercised), at least one with a
real cross-subtask file dependency. All base commits verified reachable via `git cat-file -t`.

| # | Slug | Brief | Base commit | PR | Subtasks | Cross-subtask dependency | Selection rationale |
|---|------|-------|-------------|-----|----------|--------------------------|---------------------|
| 1 | curation-anti-rot | `2026-07-23-curation-anti-rot.md` | `f55380b` | #106 | 6 (3 LAUNCHABLE batch 1 + 3 batch 2) | **YES — ST-4 requires ST-3's `write-lessons.sh supersede` verb** (kind: subcommand); ST-5a requires ST-1/ST-2 interface shapes for docs | Most recent (v15.14.0), multi-batch, largest subtask count; dependency-materialization gap will surface if arm-3's SDK runner cannot merge ST-3 into ST-4's worktree |
| 2 | rules-enforcement | `2026-07-01-rules-enforcement.md` | `872cc81` | #88 | 4 (ST-2 BLOCKED by ST-1) | **YES — ST-2 shares `commands/rules.md` with ST-1** (kind: symbol); ST-3/ST-4 advisory wiring reads ST-1's `add-rule.sh` | Multi-seam wiring (3 advisory integration points across agents/commands/scripts); BLOCKED subtask exercises dependency ordering |
| 3 | learning-loop-phase1-2 | `auto-2026-06-17-040909-learning-loop-phase1-2.md` | `516687a` | #61 | 4 (all LAUNCHABLE) | No — parallel independent subtasks | Tests fully parallel orchestration (4 independent agent-prompt edits); no dependency ordering needed; baseline for "does the orchestration add value over sequential?" |
| 4 | review-drain-worktree-isolation | `2026-06-21-review-drain-worktree-isolation.md` | `142319e` | #75 | 3 (ST-3 BLOCKED by ST-1+ST-2) | **YES — ST-3 depends on ST-1+ST-2 for accurate version bump** | Multi-dependency (ST-3 requires TWO providers); 8-file modification in ST-1 with lifecycle/cleanup/failure-injection gates |
| 5 | handoff-digest | `2026-06-28-handoff-digest.md` | `49868b1` | #82 | 4 (ST-2 BLOCKED by ST-1) | YES — ST-2 tests ST-1's `build-handoff.sh` output | Create-then-test pattern (engine + fixture-driven test); new file creation (not just modification); mirrors the `/insights` deterministic-assembler idiom |

**Dependency-materialization gap coverage (§Protocol step 1 hard requirement):** corpus entries #1
(curation-anti-rot), #2 (rules-enforcement), and #5 (handoff-digest) each have a real cross-subtask
file dependency where a dependent subtask reads/invokes a file the producer subtask creates or
modifies. Under arm 3 (SDK runner), the known residual divergence 3 (`SDK_RUNNER_SPIKE.md`) means
these dependents will branch from the feature branch without the producer's commits — the eval must
surface whether this causes test failures or incorrect output in the measured comparison. Entries #1
and #2 are the **primary** carriers because the dependent subtask directly calls a new subcommand /
symbol the producer introduces (immediate crash on absence); #5's ST-2 tests ST-1's output file
(create-then-test — a genuine materialization case, but failure is a test assertion rather than a
missing-symbol crash, so it's a softer signal). #4's dependency is coordination/ordering (version
bump accuracy), not file materialization.

## Corpus v2 (ACTIVE — amended 2026-07-27, before any run)

**Repository: `vikashruhilgit/ntfs-tool`** — a Swift NTFS read/write toolkit (NTFSCore library +
`ntfsctl` CLI + FSKit extension + menu-bar app), 155 commits, fully owned by the operator.
**Single base commit for every arm of every requirement: `5df1ded`** (`origin/main`,
2026-07-27). All arms run **plugin v15.14.0**.

Why this corpus resolves what the superseded one could not:

| Problem with Corpus v1 | Status under Corpus v2 |
|---|---|
| Solution leakage — plugin contains the merged answer | **Gone.** The plugin has no NTFS implementation; the work is genuinely unbuilt. |
| Arm 3 impossible on 4/5 entries (flags postdate base commits) | **Gone.** One base commit at plugin v15.14.0 ⇒ `--sdk-runner` + `--multi-voter-heal` available on all 5. |
| Plugin-dir rename across base commits | **Gone.** No rewind; one path. |
| Version confound between arms | **Gone.** Version is constant by construction, so an ablation differs from arm 2 by exactly one lever. |

Requirements are the five in `docs/backlog/pending-followups/` on `ntfs-tool@main`. **Each was
verified open against source, not taken from the project's own backlog prose** — that check
mattered: two other STATUS.md items claimed pending were already implemented, and a third
(`renameItem`) was wrong in three separate places.

| # | Requirement | Doc | Verified open by | Subtask shape | Cross-subtask dependency |
|---|---|---|---|---|---|
| 1 | `ntfsctl tree` + `find` | `03-tree-and-find.md` | neither in `ntfsctl.swift:17` `subcommands:` | 3 (walker → 2 consumers) | **YES — strongest.** ST-2 (`tree`) and ST-3 (`find`) both *call* the shared recursive walker ST-1 creates. Consumers cannot compile until the producer lands. |
| 2 | Streaming `$Bitmap` reader | `02-streaming-bitmap.md` | `Bitmap.swift:12` holds whole `Data` blob | 3-4 (core + consumers + tests) | **YES.** Allocator (`findFreeRun`, `_allocHint`, `allocateIndexClusters`) and `RunlistBitmapAudit` all consume the changed API. |
| 3 | `NTFSError` structured model | `05-ntfserror-model.md` | flat enum; `isOverflowDescription` (`Volume.swift:6081`) string-matches | 3-4 (model + migration + tests) | **YES.** Every `catch … where isOverflowDescription(desc)` site must migrate to the new `kind` in lockstep with the model. |
| 4 | `cp --resume` | `01-cp-resume.md` | no `resume` symbol in `Cp.swift` | 2-3 (flag + compare + tests) | Moderate — tests depend on the comparison helper. |
| 5 | FSKit `createLink` | `04-fskit-link-callbacks.md` | `NTFSVolume.swift:389` returns `posixError(EROFS)` | 2-3 | Moderate — errno mapping + oracle validation depend on the write path. |

**Dependency-materialization gap coverage (§Protocol step 1 hard requirement — satisfied):**
entry **1** is the cleanest instance the eval has had. `tree` and `find` are separate subtasks that
*import and call* a walker a third subtask creates, so under arm 3 the SDK runner's residual
divergence 3 (`SDK_RUNNER_SPIKE.md` — dependents branch from the feature branch without producer
commits) produces a **compile failure**, not a subtle behavioural difference. Entries 2 and 3 are
secondary carriers. This is a stronger signal than Corpus v1 offered, where the dependency was a
new subcommand's *runtime* absence.

**Metric availability check (done, not assumed):** `ntfs-tool` has `ci.yml`, `release.yml`, and —
as of 2026-07-27 — a working `claude-code-review.yml`, so `review_rounds_to_READY` has a real
independent review signal. Getting that reviewer to actually post took four config fixes
(`pull-requests: write` + `concurrency`; `--comment` + `issues: write` + `fetch-depth: 0`;
`--allowed-tools` + `actions: read`; an instruction preamble around the slash command) — **each of
which failed GREEN**. Before trusting this metric during a run, assert on posted comments
(`gh pr view <n> --json comments`), never on the check's conclusion.

**Pre-flight additions learned the hard way (add to the runbook's checklist):**
- **GitHub Actions spending limit.** A burst of `claude-code-review` runs (~$0.50 and 20+ turns
  each) exhausted the account limit mid-session on 2026-07-27 and failed every subsequent job in
  ~2s at startup. 17-25 eval runs are far heavier. Check headroom before starting, and note that
  a **public** repo gets free Actions minutes (`ntfs-tool` was made public for this reason).
- **Branch protection.** `loomwright@main` requires 1 approving review + `ci`; an author cannot
  approve their own PR, so an unattended run will park at `BLOCKED`. Verify the eval repo's
  protection (`gh api repos/<o>/<r>/branches/main/protection`) before assuming a PR can land.

## Execution Runbook

Step-by-step instructions for executing each arm. All runs use the same base commit per requirement
(column "Base commit" in the Corpus table above).

### Scratch branch naming

```
eval/<slug>/arm-<N>[-<variant>]
```

Examples: `eval/curation-anti-rot/arm-1-bare`, `eval/rules-enforcement/arm-2-default`,
`eval/handoff-digest/arm-3-extras`, `eval/curation-anti-rot/arm-ablation-a-no-qa-rules`.

### Per-requirement arm execution

For each of the 5 corpus requirements, execute 3 arms from the same base commit.

> **Eval-specific flags (all Loomwright arms):** every `/supervisor` invocation below passes
> `--skip-preflight-sync` (the corpus re-implements already-merged work — Phase 1.5 would classify
> it as SUPERSEDED and halt) and `--base-branch eval/<slug>/arm-N` (prevents FINALIZE from creating
> a PR to `main` — the eval's own Isolation protocol says "NO PRs to main"). The branch MUST be
> pushed to origin before `/supervisor` runs — ACQUIRE does `git fetch origin "$BASE_BRANCH"` and
> FINALIZE does `gh pr create --base "$BASE_BRANCH"`, both of which require a remote ref. The
> created PR targets the eval scratch branch itself; both the branch and the throwaway PR are
> deleted after metric extraction (see Isolation protocol).

> **Plugin version control (MANDATORY — all Loomwright arms):** this eval re-implements
> Loomwright's *own* history, so the plugin the agent runs is part of the experimental condition,
> not a fixed background. **Every** Loomwright arm (2, 3, and both ablations) MUST launch with
> `--plugin-dir` pointed at the eval branch checkout:
>
> ```bash
> # With the eval branch checked out at <base-commit>:
> claude --plugin-dir <absolute-path-to-this-checkout>/loomwright
> ```
>
> Note the path is the **nested plugin dir** (`<checkout>/loomwright`), not the marketplace-wrapper
> repo root. `--plugin-dir` loads the plugin from disk **for that session only**.
>
> This is load-bearing for two reasons, and skipping it invalidates the arm:
> 1. **Version constancy.** The arm must run the plugin as of its own base commit. Because
>    `--plugin-dir` is session-scoped and reads the working tree, every arm of a requirement runs
>    the same version, and an ablation differs from its arm-2 baseline by the removed lever ONLY.
> 2. **Solution leakage.** Any globally-installed plugin is at `main`, which already *contains* the
>    merged work the corpus requirement asks the agent to re-implement — letting it read the
>    finished answer out of its own preloaded skills/agent prompts. Pointing at `<base-commit>`
>    restores the pre-merge state.
>
> **Why NOT `/plugin install loomwright@atelier` (verified 2026-07-27, do not reintroduce):** an
> earlier draft of this runbook mandated a global uninstall/reinstall to pin the version. That is
> **broken and must not be used.** On the maintainer's machine `claude plugin marketplace list`
> shows `atelier` is **Git-remote-backed** (`github.com/vikashruhilgit/loomwright.git`), not a
> local path — so the reinstall pulls the remote default branch and silently discards **both** the
> base-commit pin and any ablation edits. The same probe found the CLI-scope install stale and
> disabled (`loomwright@atelier` v15.9.0, `Status: ✘ disabled`) while the desktop session was
> actually running v15.14.0 from a separate session-scoped path — three divergent surfaces, none
> of which the reinstall reliably controls. `--plugin-dir` sidesteps all three.
>
> **Corollary — no cleanup step is needed.** Because `--plugin-dir` never mutates the global
> install, an ablated plugin cannot leak into a later arm or a later requirement. There is no
> shared `${CLAUDE_PLUGIN_ROOT}` to restore between arms.
>
> **Arm 1 precondition (assert, don't assume):** arm 1 must run with **no** Loomwright loaded —
> which means omitting `--plugin-dir` *and* confirming no globally-enabled install is present.
> Verify before the first arm-1 run:
>
> ```bash
> claude plugin list | grep -A3 loomwright   # must be absent, or Status: ✘ disabled
> ```
>
> If it is enabled, disable it for the duration of the eval (`claude plugin disable loomwright`)
> and record that in the run notes — an arm-1 that silently had the plugin loaded invalidates the
> baseline every other arm is measured against.

> **Do NOT "simplify" the arms back to `/autonomous`.** §Protocol step 4 expresses a preference for
> the in-session `/autonomous` path, and every Loomwright arm below deliberately uses the manual
> `/launch-pad + /supervisor` two-step instead. This is not drift: the manual path is still fully
> in-session, and it is the only way to pass the eval-critical flags. `/autonomous` forwards
> **exactly** `--base-branch`, `--non-interactive`, `--cheap` (`commands/autonomous.md`) — it
> silently drops `--skip-preflight-sync` (⇒ Phase 1.5 halts the run as SUPERSEDED) and, for arm 3,
> `--sdk-runner` / `--multi-voter-heal` (⇒ arm 3 silently degrades into an arm-2 duplicate).

**Arm 1 — Bare Claude Code (no Loomwright)**

```bash
git checkout -b eval/<slug>/arm-1-bare <base-commit>
# Start a plain Claude Code session (no plugin commands):
claude
# Paste the requirement text from the brief's ## Task / ## Goal section.
# NOTE: arm 1 receives the raw requirement goal only (not the full Launch Pad brief),
# because the eval measures the FULL Loomwright stack including Launch Pad's planning.
# This input asymmetry is intentional — document it if adjusting the protocol.
# Implement on this branch. Do NOT use /supervisor, /launch-pad, or any Loomwright commands.
# When done, record metrics (see Recording Protocol below) and exit.
```

**Arm 2 — Loomwright default**

```bash
git checkout -b eval/<slug>/arm-2-default <base-commit>
git push -u origin eval/<slug>/arm-2-default
# Start a Claude Code session with the plugin PINNED to this base commit
# (see "Plugin version control" above — a global install would be at main and
# would already contain the merged answer):
claude --plugin-dir <absolute-path-to-this-checkout>/loomwright
# Run the standard Loomwright flow with eval-specific flags:
/launch-pad
# (paste the requirement, let it produce a brief, then:)
/supervisor job: .supervisor/jobs/pending/<saved-brief> --skip-preflight-sync --base-branch eval/<slug>/arm-2-default
# Record metrics and exit.
```

**Arm 3 — Loomwright + SDK runner + multi-voter heal**

```bash
# Pre-requisite: build the SDK spike runner (once per machine):
cd loomwright/sdk-spike && npm install --no-audit --no-fund && npm run build && cd -

git checkout -b eval/<slug>/arm-3-extras <base-commit>
git push -u origin eval/<slug>/arm-3-extras
# Plugin PINNED to this base commit (see "Plugin version control" above):
claude --plugin-dir <absolute-path-to-this-checkout>/loomwright
# NOTE: /autonomous does NOT forward --sdk-runner or --multi-voter-heal (it forwards
# only --base-branch, --non-interactive, --cheap). Use the manual two-step path:
/launch-pad
# (paste the requirement, let it produce a brief, then:)
/supervisor job: .supervisor/jobs/pending/<saved-brief> --sdk-runner --multi-voter-heal --skip-preflight-sync --base-branch eval/<slug>/arm-3-extras
# Record metrics and exit.
```

> **Known gap (arm 3):** the SDK runner's residual divergence 3 (`SDK_RUNNER_SPIKE.md`) means
> dependent subtasks branch from the feature branch, not from producer output. For corpus entries
> #1, #2, and #5 (which have real cross-subtask file dependencies), arm-3 runs may surface test
> failures or incorrect output that the default path (arm 2) avoids via sequential worktree merges.
> This is the gap the eval is designed to measure.

### Ablation arms (additive amendment — budgeted separately from §Protocol step 6)

Each ablation arm modifies ONE lever. Execute from the same base commit as the corresponding
requirement's base arms. Use arm-2 (Loomwright default) as the baseline — the ablation removes one
layer from the default stack.

**Ablation (a) — minus QA rule libraries**

Replace `qa-test-patterns/SKILL.md`, `qa-gates/SKILL.md`, and `qa-strategy/SKILL.md` (combined
~1,900 lines) with a single ~50-line intent document that states the testing goals without
prescriptive patterns. The QA Executor's **behavioral prompt body** and Phase 3 execution are
unchanged — the only edit to `agents/qa-executor.md` is swapping the `skills:` preload list in its
frontmatter to point at `qa-intent` instead of the three libraries. This keeps the ablation on a
single lever (the rule libraries), not the agent's instructions.

```bash
git checkout -b eval/<slug>/arm-ablation-a-no-qa-rules <base-commit>
# Create the replacement intent doc:
mkdir -p loomwright/skills/qa-intent
cat > loomwright/skills/qa-intent/SKILL.md << 'INTENT'
---
name: qa-intent
version: 1.0.0
description: Lightweight QA intent (ablation — replaces qa-test-patterns + qa-gates + qa-strategy)
---
# QA Intent
Test the implementation against the acceptance criteria. Use Playwright for E2E tests where
applicable. Verify: (1) golden path works, (2) edge cases don't crash, (3) no regressions in
existing tests. Prefer integration tests over unit tests for orchestration-shaped requirements.
INTENT
# Update qa-executor agent frontmatter to preload qa-intent instead of the three libraries.
# CRITICAL: commit + push the ablation edits BEFORE starting the session.
# Skills are preloaded from ${CLAUDE_PLUGIN_ROOT} (the install dir), not the checkout,
# and Supervisor workers run in worktrees created from the pushed branch tip — uncommitted
# edits never reach either surface.
git add loomwright/skills/qa-intent/ loomwright/agents/qa-executor.md
git commit -m "eval(ablation-a): replace QA rule libraries with intent doc"
git push -u origin eval/<slug>/arm-ablation-a-no-qa-rules
# Launch with --plugin-dir so the session loads the ablation edits from this branch.
# This is the SAME mandated pin as "Plugin version control" above — pointing at the
# eval checkout pins the base-commit version AND applies the ablation edits in one step:
claude --plugin-dir <absolute-path-to-this-checkout>/loomwright
# Now run the standard Loomwright flow with eval-specific flags:
/launch-pad
# (paste the requirement, let it produce a brief, then:)
/supervisor job: .supervisor/jobs/pending/<saved-brief> --skip-preflight-sync --base-branch eval/<slug>/arm-ablation-a-no-qa-rules
```

> **Note:** ablation (a) creates a transient `qa-intent` skill that is NOT registered in
> `SKILLS_INDEX.md` or counted in the plugin skill tally — it exists only on the eval branch
> and is discarded after recording. Do not bump skill counts for it.

**Incident-class regression check (ablation a):** the QA rule libraries encode test-isolation
patterns, infrastructure-aware fixtures (Mailpit/MailHog), and budget zones (80/110/60). Watch for:
tests that leak state across runs, missing infrastructure detection, or budget exhaustion causing
premature test-suite termination.

> **Ablation (b) — minus prompt-hook schema validators:** deferred from round 1. If budget permits
> after (a) and (c), add this arm per the original requirement §Scope item 2(b).

**Ablation (c) — minus magic budgets/caps**

Convert hardcoded numeric budgets (Supervisor 50-call, Execute Manager 60-call, QA Executor
80/110/60, worker turn limits) to soft defaults the model may override with stated reasoning.
Modify the agent prompts to present each budget as "default N, override with justification."

```bash
git checkout -b eval/<slug>/arm-ablation-c-soft-budgets <base-commit>
# Edit agent prompts to soften budgets:
# - agents/supervisor.md: "budget: 50 tool calls" → "default budget: 50 tool calls (override with
#   stated reasoning if a phase requires more)"
# - agents/execute-manager.md: similar for 60-call budget
# - agents/qa-executor.md: similar for 80/110/60 zones
# CRITICAL: commit + push the ablation edits BEFORE starting the session.
# Skills are preloaded from ${CLAUDE_PLUGIN_ROOT} (the install dir), not the checkout,
# and Supervisor workers run in worktrees created from the pushed branch tip — uncommitted
# edits never reach either surface.
git add loomwright/agents/supervisor.md loomwright/agents/execute-manager.md loomwright/agents/qa-executor.md
git commit -m "eval(ablation-c): soften magic budgets to overridable defaults"
git push -u origin eval/<slug>/arm-ablation-c-soft-budgets
# Launch with --plugin-dir so the session loads the ablation edits from this branch.
# This is the SAME mandated pin as "Plugin version control" above — pointing at the
# eval checkout pins the base-commit version AND applies the ablation edits in one step:
claude --plugin-dir <absolute-path-to-this-checkout>/loomwright
# Now run with eval-specific flags:
/launch-pad
# (paste the requirement, let it produce a brief, then:)
/supervisor job: .supervisor/jobs/pending/<saved-brief> --skip-preflight-sync --base-branch eval/<slug>/arm-ablation-c-soft-budgets
```

**Incident-class regression check (ablation c):** magic budgets prevent runaway token spend and
context exhaustion. Watch for: sessions that consume >2× the default arm's wall tokens, phases
that loop without terminating, or context-window exhaustion causing mid-task failures.

### Recording protocol

After each arm completes, extract and record the pre-registered metrics:

| Metric | Arm 1 (bare) source | Arm 2/3 (Loomwright) source |
|--------|--------------------|-----------------------------|
| `review_rounds_to_READY` | Manual count of review→fix cycles on the scratch branch (count commits that are fix responses to review feedback) | `POSTMORTEM_RESULT.review_rounds` in `.supervisor/postmortem/results.jsonl`, OR `REVIEW_HEAL_RESULT.fix_cycles` from the drain log. **Note:** these are produced by the until-mergeable review drain / `/pr-postmortem`, not by Supervisor's core Phase 4.5. The eval arms use manual `/launch-pad + /supervisor` (no `/autonomous`), so the default `auto_review` dispatch must fire after FINALIZE creates the PR, OR the operator must run `/review-pr --until-mergeable <pr-url>` manually on the throwaway PR. If neither runs, this cell will be blank — record `N/A (no drain)` and fall back to manual commit-count. **`READY` is unreachable by default on eval branches — pass `--required-checks all-non-neutral`:** the dispatch itself is NOT base-gated (verified: neither `dispatch-pr-review.sh` nor `hook-dispatch-on-pr-create.sh` filters on the PR's base), so the drain does fire for a non-`main`-base PR. But `review-heal` §U2 fails **CLOSED** when branch-protection metadata is unavailable, and *"no branch protection"* is explicitly one of those cases — an `eval/<slug>/arm-N` scratch branch has none, so the drain exits `ESCALATED` and never emits `READY`. `fix_cycles` is still populated (rounds run before the escalation), so the metric is recoverable either way; record the terminal decision alongside it. To make `READY` reachable, run the drain manually with the documented escape hatch: `/review-pr <pr-url> --until-mergeable --required-checks all-non-neutral`. |
| `heal_iterations` | N/A — record `-` | `SUPERVISOR_RESULT.heal_iterations` in `.supervisor/logs/{session_id}.jsonl` (event `session_end`) |
| `post_merge_defects` | Run ONE independent `/code-reviewer` pass on the arm's final branch diff (`git diff <base>..<arm-branch>`) — count BLOCKING + HIGH `new` findings | Same — run the SAME `/code-reviewer` configuration on each arm's diff for a fair comparison |
| `wall_tokens` | Session usage total (Claude Code reports this at session end) | `token_ledger` event in `.supervisor/logs/{session_id}.jsonl` (field `token_proxy_transcript_bytes` when `proxy: true`, or real token counts when available) |

**Secondary observables** (recorded, not decision inputs): `heal_decision`, `rubric_score` (where
the brief has an `## Outcomes Rubric`), arm-3 `findings_raised`/`findings_refuted`/`findings_fixed`
counters (from `SUPERVISOR_RESULT.summary`), wall-clock notes,
`token-cost-per-subtask` (arm-3 only, per the 2026-07-18 amendment).

### Isolation protocol

1. All eval work happens on scratch branches — **NO PRs to main from eval runs**.
2. Same base commit for all 3 arms of a requirement (enforced by the Corpus table above).
3. After metrics are extracted and recorded in the Results table, close throwaway PRs and delete
   eval branches (local + remote):
   ```bash
   # ⚠️ REPLACE <slug> THROUGHOUT BEFORE RUNNING — this block is not executable as pasted.
   # Step off the eval branches first — `git branch -D` refuses to delete the checked-out branch:
   git checkout main
   # Close throwaway PRs and capture their head branches for cleanup:
   head_branches=()
   for arm in arm-2-default arm-3-extras arm-ablation-a-no-qa-rules arm-ablation-c-soft-budgets; do
     for pr in $(gh pr list --base "eval/<slug>/$arm" --state open --json number,headRefName \
       --jq '.[] | "\(.number):\(.headRefName)"'); do
       num="${pr%%:*}"; head="${pr#*:}"
       gh pr close "$num" --comment "Eval throwaway PR — metrics extracted"
       head_branches+=("$head")
     done
   done
   # Delete local branches (arm-1 is local-only; Loomwright arms pushed for --base-branch):
   git branch -D eval/<slug>/arm-1-bare eval/<slug>/arm-2-default eval/<slug>/arm-3-extras \
     eval/<slug>/arm-ablation-a-no-qa-rules eval/<slug>/arm-ablation-c-soft-budgets
   # Delete Supervisor's feature-branch heads (created by ACQUIRE, pushed by FINALIZE):
   for h in "${head_branches[@]}"; do git branch -D "$h" 2>/dev/null; done
   # Delete remote branches — eval base branches + Supervisor head branches:
   git push origin --delete eval/<slug>/arm-2-default eval/<slug>/arm-3-extras \
     eval/<slug>/arm-ablation-a-no-qa-rules eval/<slug>/arm-ablation-c-soft-budgets \
     "${head_branches[@]}"
   ```
4. Eval session logs in `.supervisor/logs/` and `.supervisor/jobs/` artifacts are retained for
   audit but are not merged to main.
5. **Plugin state needs no cleanup — by construction.** Because every Loomwright arm launches with
   session-scoped `--plugin-dir` (§"Plugin version control") and never installs globally, an
   ablated or base-commit-pinned plugin **cannot** persist into the next arm or the next
   requirement. There is no shared install dir to restore and no ordering rule to remember.
   > This replaces an earlier draft that mandated a per-arm global uninstall/reinstall plus an
   > "ablations last" ordering rule. Both were mitigations for a shared-install hazard that
   > `--plugin-dir` removes outright — and the reinstall itself was independently broken (see
   > §"Why NOT `/plugin install loomwright@atelier`"). Do not reintroduce either.

   The one piece of global state still worth asserting is the **arm-1 baseline**: confirm no
   globally-enabled Loomwright is present before each arm-1 run (`claude plugin list | grep -A3
   loomwright`). Do **not** infer plugin state from `~/.claude/plugins/cache/` — it retains stale
   leftovers and disagreed with both the CLI-scope install and the running desktop session when
   this was probed.

### Re-run protocol (standing — per original requirement §Scope item 4)

Re-run the ablation set on every major model release (e.g., Claude 5 → Claude 6). Use the same
corpus, same base commits, same metrics. Compare cross-model results to detect release-dependent
verdicts. If a layer that was CUT on model N becomes competitive on model N+1, record the finding
but do NOT re-add the layer without a fresh eval cycle (pre-register the re-add hypothesis first).
A `model-capability` configuration knob is a possible follow-up ONLY if re-run results show
release-dependent verdicts — do not build it speculatively.

## Results (per-run — rows filled AT RUN TIME; no metric added after first run)

| requirement | arm | review_rounds_to_READY | heal_iterations | post_merge_defects | wall_tokens | notes |
|---|---|---|---|---|---|---|
| tree-and-find | 3 (SDK runner + multi-voter) | **ABORTED — could not execute** | n/a (never reached Phase 4.5) | n/a | out 18,130 · cache-create 92,811 · cache-read 2,324,039 · $2.62 (LP 6.97 + Supervisor 2.62 = **$9.59** spent to establish non-viability) | Phase 3 abort, 32 turns, 4m31s. Two independent blockers: brief parser drops all dependency edges (non-numeric ids + comment-style keys) ⇒ 2 and 3 spawned concurrently onto the same file; and no dependency materialization ⇒ dependents cannot compile. **Verdict: SDK runner CUT.** `--multi-voter-heal` never ran — remains unmeasured, NOT cut. |
| tree-and-find | 2 (Loomwright default) | drain `ESCALATED` — structurally unreachable `READY` on an unprotected base (predicted by §Recording protocol); drain `fix_cycles` 0; Phase 4.5 `heal_iterations` 0 + 1 out-of-loop review-driven fix commit `3dda850` | 0 | 0 | out 90,473 · cache-create 526,110 · cache-read 15,191,782 · **$61.76** (LP 7.68 + Supervisor 43.63 + resume 10.45) — see METRIC DEFECT note: token columns under-count sub-agents, cost is the valid comparator | PR [#58](https://github.com/vikashruhilgit/ntfs-tool/pull/58), head `3dda850`, 1,656 ins / 10 files. `heal_decision: PASS`, `rubric_score: 6/6`. Reviewer PASS — 0 BLOCKING, 0 HIGH, 4 MEDIUM/new, 6 LOW/new. Ran as 3 sessions (Launch Pad → Supervisor → `--resume`); the middle one stalled mid-FINALIZE and was recovered by explicit re-invocation, not re-run. Two earlier prompt-design attempts discarded (see void-runs note). |
| tree-and-find | 1 (bare) | N/A (no drain — branch never pushed, no reviewer in loop) | - | 0 | out 82,290 · cache-create 172,468 · cache-read 11,830,096 · in 176 · $9.70 | commit `4406708`, 98 turns, 41m04s. 1,838 ins / 12 files (impl 759, tests 1,027). Tests green: NTFSCore 286 (2 skipped, 0 fail), ntfsctl 35 (0 fail). Reviewer PASS — 0 BLOCKING, 0 HIGH, 2 MEDIUM/new, 3 LOW/new, 1 LOW/pre-existing. Baseline cleanliness VERIFIED by session-start-time (transcript born 20:05:27 vs `settings.json` disable 19:54:36). |

> **Arm 2 (tree-and-find) — NOT COMPLETED, no row. Blocked by a structural incompatibility
> between Supervisor and headless `claude -p`.** Recorded here because the blocker is a finding,
> not a mishap. Supervisor reached Phase 4 FINALIZE, merged all 5 subtask branches
> (`52944d1`, 8 files, +1623/−4, worktrees cleaned), then started the integrated test suite as a
> **background task, armed a watcher, and ended its turn** stating *"I'll resume automatically when
> the suite finishes."* In an interactive session it would be re-invoked when that task completed;
> under `claude -p` there is no next turn, so the session ended mid-FINALIZE. It **never pushed,
> never opened the PR, and never ran Phase 4.5** — so `review_rounds_to_READY`, `heal_iterations`,
> and `rubric_score` are all unobtainable for this run. It did not hit the turn cap (29 of 500).
> Cost: $43.63, 2h35m.
>
> **Follow-up durability note.** The requirement files this section points at live under
> `.supervisor/requirements/`, which is **gitignored** (`.gitignore:35`) — they are local working
> artifacts, not repo-visible records, and a reader cloning this repo will not find them. The
> durable record of each defect is the narrative in this section plus its PR. Defect 2 shipped as
> a fix (see PR "fix(resume): reconcile state against git ground truth"); the write-side follow-up
> it recommends is `one-writer-derived-state.md`, whose substance is summarised in that PR's
> description so it survives independently of the untracked file.
>
> **Compounding defect — resume is unsafe, not merely unavailable.** `.supervisor/state.md` was
> left at `phase: ACQUIRE` with all five subtasks `PENDING`, despite all five being complete and
> merged. Context-Keeper never advanced it. A `/supervisor --continue` would therefore restore a
> belief of "no work done" and re-execute the entire job. This is a real defect independent of the
> eval: **a crash between EXECUTE and FINALIZE leaves an un-resumable session whose state file
> actively lies about progress.** Worth its own follow-up requirement **for the write-side fix**;
> the read-side reconciliation already shipped (see the durability note above). The two are
> deliberately separate, not two names for one thing: **`supervisor-resume-state-lies.md`** is the
> read-side guard — detect the lie at resume time and refuse (shipped). **`one-writer-derived-state.md`**
> is the write-side redesign — stop the lie being written at all, by replacing six prompt-instructed
> bookkeeping mechanisms with one hook-triggered writer and deriving `state.md` from an append-only
> log. Shipping the first does not close the second.
>
> **CORRECTED 2026-07-28 — arm 2 subsequently COMPLETED; see its Results row.** The claim below
> ("Loomwright arms must run interactively") was **too strong** and is superseded. The session did
> not fail; it was *waiting*. `claude -p --resume <session_id> "Continue"` supplies exactly the
> re-invocation an interactive session would have supplied automatically, and the stalled run then
> pushed, opened PR #58, and completed Phase 4.5 normally (45 turns, 23 min, $10.45).
>
> **Corrected rule:** Loomwright arms CAN run headless, but a headless run is **not fire-and-forget**
> — whenever Supervisor backgrounds work and yields, the operator must re-invoke with `--resume`.
> Detect the state by polling the branch/PR rather than assuming completion: the process exits 0
> with `subtype: "success"` while the job is objectively unfinished, so **exit status is not a
> completion signal here.**
>
> The underlying defect stands and is unchanged: Supervisor's dispatch-then-poll design assumes
> re-invocation that `claude -p` does not provide on its own.
>
> ~~**Consequence for the protocol:** the "arms execute headless" amendment above holds for arm 1
> (bare Claude Code has no async-orchestration pattern) but does **NOT** hold for any Loomwright
> arm. Arms 2, 3, and both ablations depend on Supervisor's background-dispatch-then-poll design,
> which requires a session that gets re-invoked. **Loomwright arms must run interactively.**~~

> **Void runs retained (arm 2, not rows).** Two earlier arm-2 attempts failed on prompt design
> before the run above. (1) `arm-2-VOID-launchpad-executed` (`121d4e6`) — with the operational tail
> reduced to *"Commit your work on the current branch when done."*, **Launch Pad implemented and
> committed the work inline instead of producing a brief**, violating its own documented plan-only
> contract ($11.15). (2) An earlier attempt whose tail also carried *"Do not push. Do not open a PR
> against main."* planned correctly but baked that constraint into the brief as risk R8, which
> would have suppressed FINALIZE's PR and silently voided `review_rounds_to_READY` ($5.86).
> Removing the operational tail entirely produced correct plan-only behaviour ($7.68). Across the
> three variants behaviour tracked the prompt rather than varying randomly, but at n=1 per variant
> that is an observation, not a demonstrated mechanism. **Protocol consequence:** Loomwright arms
> receive the requirement body ONLY — any commit/push/PR instruction either leaks into the brief as
> a constraint or trips the plan/execute boundary. Arm 1 keeps its operational tail because nothing
> else will commit for it; the requirement body is byte-identical across arms (verified by `diff`).

### Arm 3 (tree-and-find) — ABORTED at Phase 3. SDK runner **cannot execute** the brief.

Not a run that failed; a run that **could not start**, for two independent reasons the agent
established by reading `sdk-spike/src/runner.ts:315-399` rather than inferring. Cost $2.62, 32
turns, 4m31s. No commits, no PR, `--multi-voter-heal` never reached.

**Blocker 1 — the brief parser silently discards every dependency edge.** The runner's contract
(`test/fixtures/mini-brief.md`) expects numeric ids and `subtask_N:` YAML keys. A real Launch Pad
brief matches on none of three axes:

| Runner expects | Launch Pad emits | Effect |
|---|---|---|
| `/^\|\s*(\d+)\s*\|/` table rows | `\| 1a \|`, `\| 1b \|` | rows dropped entirely — the walker is assigned to nobody |
| `subtask_<digits>:` YAML keys | `# Subtask 1a — …` comments | `current` never set ⇒ **all `provides`/`requires` discarded** ⇒ every subtask parses `requires: []` |
| `from: 1` (unquoted int) | `from: "1a"` | third break, moot given the above |

Consequence observed live: with every edge gone, **everything looked launchable** and subtasks 2 and
3 were spawned concurrently — both editing `ntfsctl.swift`'s `subcommands:` array, precisely the
overlap the brief serialized. This is a **silent correctness failure, not a crash**: on a brief
whose subtasks happen to touch disjoint files it would appear to work while providing no ordering
guarantee at all.

> **CORRECTION (2026-07-28, same day) — blocker 1 is NON-DETERMINISM, not a fixed format mismatch.**
> Checked after the fact: the arm-**2** brief, produced from the *byte-identical* prompt for the
> *same* requirement, used purely **numeric** ids (`1`–`5`, confirmed by its `subtask: N` commits),
> which the runner's parser **would have accepted**. The arm-3 brief mixed both schemes
> (`1`–`5` in one table, `1a`/`1b` in another). So Launch Pad does **not** emit a stable id scheme
> across runs, and the runner's parser therefore succeeds or **silently discards the entire
> dependency graph depending on which brief you happened to get**. That is worse than a permanent
> mismatch — a permanent one fails every time and gets noticed — but it is a *different claim* than
> "Launch Pad's format is incompatible", and the original wording overstated it. **Blocker 1 alone
> would NOT justify the CUT**; it justifies "unreliable". The CUT rests on blocker 2.

**Blocker 2 — no dependency materialization (residual divergence 3), fatal independently, and
INDEPENDENT of id format.** The
spike documents it: *"`requires` only delays spawn order, not visibility — a dependent worktree
branches from the feature branch and does NOT see producer commits."* Subtasks 2 and 3 both consume
subtask 1a's `DirectoryWalker.swift`, so dependent worktrees branch from a tree lacking the walker
and **cannot compile**. Fixing the id parsing would not rescue the run.

**This is exactly what §Protocol step 1 required the corpus to surface** — "must surface that gap in
the measured arm-3 comparison, not leave it theoretical." It is now measured.

**Two behaviours worth crediting:** the runner honoured its "NEVER silently falls back to the default
path" contract, and Supervisor **stopped for a human decision instead of auto-picking** a fallback
that would have quietly changed what arm 3 measures. Both are the fail-closed discipline working.

**State clean:** runner killed (exit 144), both worktrees removed, `sdk-spike/subtask-2/-3` branches
deleted, no committed work, uncommitted partial preserved to `scratchpad/aborted-sdk-run/`, brief in
`jobs/in-progress/`, root cause checkpointed.

#### Verdict — SDK runner: **CUT** (per the pre-committed decision rule)

> *"The SDK runner graduates to v16 ONLY if arm 3 beats arm 2 on defects or rounds without >1.5×
> token cost. Otherwise the spike is cut."*

It does not beat arm 2 on anything: it cannot execute a serial, dependency-carrying Launch Pad brief
— **the normal shape of Launch Pad output**, not an edge case. n=1 on the corpus, but this is a
*structural* incapacity rather than a metric shortfall, which is stronger evidence than a numeric
comparison would have been. The cost clause never even engages.

**What the verdict does and does not rest on (stated precisely, after the blocker-1 correction):**

- **Rests on blocker 2** — no dependency materialization. Documented by the spike itself, independent
  of id format, and fatal for any brief whose subtasks consume each other's files. §Protocol step 1
  *required* the corpus to contain such a brief precisely so this would be measured rather than
  assumed.
- **Does NOT rest on blocker 1** — the parser non-determinism is an "unreliable" finding, not a
  "cannot work" one. Recorded, but not load-bearing for the CUT.
- **Honest scope of the claim:** the runner was never shown to fail on a brief with numeric ids AND
  no cross-subtask file dependencies. It may well work there. The CUT says it cannot do the
  orchestration-shaped work Loomwright exists to do — not that it fails universally.
- **Falsifiable:** one arm-3 run on a numeric-id, dependency-free brief that completes cleanly would
  narrow this verdict to "unsuitable for dependency-carrying work" rather than CUT. That run was not
  performed. Anyone re-opening this should run it before re-adding the layer.

Per §Scope item 5 of the originating requirement, a CUT verdict becomes a follow-up stub: remove
`sdk-spike/` and the `--sdk-runner` seam (`SUPERVISOR_RESULT`, `supervisor-config`, the flag row in
`commands/supervisor.md`). **Not performed here** — this item is verdicts-only.

> **`--multi-voter-heal` remains UNMEASURED.** It never ran, because arm 3 aborted in Phase 3 before
> Phase 4.5. The decision rule is explicitly **per-layer** ("a layer that does not move its metric is
> removed"), so the SDK runner's structural failure must NOT be recorded as a verdict against
> multi-voter heal. Isolating it needs one additive run — arm 2's configuration plus
> `--multi-voter-heal` alone. Recorded as pending, not inferred.

### Preliminary reading — tree-and-find, arms 1 vs 2 (n=1 requirement; NOT a verdict)

| | Arm 1 (bare) | Arm 2 (Loomwright) |
|---|---|---|
| cost (incl. sub-agents) | **$9.70** | **$61.76** (LP 7.68 + Sup 43.63 + resume 10.45) |
| `post_merge_defects` (BLOCKING+HIGH `new`) | **0** | **0** |
| other `new` findings | 2 MED + 3 LOW | 4 MED + 6 LOW |
| diff | 1,838 ins / 12 files | 1,656 ins / 10 files |
| `heal_iterations` | – | 0 (`heal_decision: PASS`, rubric 6/6) |
| review-driven fix commits | 0 | 1 (`3dda850`, doc-drift, out-of-loop) |

**On the pre-registered metric the two arms TIE at 0, while arm 2 costs 6.4×.** Arm 2 also carried
more sub-blocking findings (10 vs 5 `new`) on a *smaller* diff. Three caveats before anyone reads a
verdict into that:

1. **n=1 requirement.** The decision rule needs the corpus, not one entry.
2. **`post_merge_defects` had zero discriminating power here.** Both arms produced work with no
   BLOCKING or HIGH findings, so the metric could not separate them at all. A metric that returns
   0/0 is not evidence of parity — it is evidence the threshold is too coarse for requirements this
   size. **Do NOT add a metric** (pre-registration forbids it); record the limitation and let the
   remaining corpus entries show whether 0/0 is systematic.
3. **What arm 2 bought is not in the metrics.** Its reviewer caught a doc-drift cluster arm 1 had no
   mechanism to catch — `CLI.md` still advertising this exact feature as "future work", a README
   subcommand count off by two, a missing CHANGELOG entry. Real defects, all below the BLOCKING/HIGH
   line the metric counts. Whether that is worth 6.4× is exactly the question, and the current
   metric set cannot answer it.

> **METRIC DEFECT — `wall_tokens` under-counts multi-agent arms by ~6× (recorded, not fixed).** The
> pre-registered source is "session usage totals", but the `usage` object counts only the
> orchestrating thread. Arm 2's Supervisor session reports 14,756 output tokens against $43.63 —
> the orchestrator, 5 workers, 5 reviewers, Phase 4.5 reviewer and rubric grader are all absent from
> the token counts while fully present in `total_cost_usd`. Naively compared, output tokens show
> arm 2 at **1.1×** arm 1 (90,473 vs 82,290) while cost shows **6.4×**. The 1.1× is an artifact and
> would have produced a badly wrong verdict. **Cost is the valid comparator for multi-agent arms;
> the token columns are recorded for the record only.** Not corrected in-flight — the
> pre-registration forbids changing a metric after the first run.

**Measurement instrument (identical across all arms).** `post_merge_defects` is produced by one
headless `/loomwright:code-reviewer` pass with the plugin pinned via `--plugin-dir`, prompt held
byte-identical in `reviewer-prompt.txt`, scoped to `git diff 5df1ded..HEAD`, counting `new`
findings at BLOCKING + HIGH. Arm-1 instrument cost: $2.47 / 27 turns (not counted in the arm's own
`wall_tokens`).

### Amendments — recorded at run time (additive; original protocol byte-preserved above)

| date | amendment | pre-registration preserved? |
|---|---|---|
| 2026-07-27 | **Arms execute headless** via `claude -p … --output-format json` rather than an interactive session, applied **uniformly to every arm**. Reason: the operator drives the eval through an assistant that cannot type into a terminal or IDE (computer-use grants those "click" tier). Side benefit: `wall_tokens` comes from the returned `usage` object rather than a human reading `/cost`. | Yes — §Question, §Decision rule, §Pre-registered metrics and §Corpus unchanged; only the *session mode* changed, held constant across arms. |
| 2026-07-27 | **Arm-1 precondition strengthened.** The runbook's check (`claude plugin list \| grep -A3 loomwright`) is **necessary but not sufficient** — it says nothing about *when* the session started, and plugins load at session start, so `claude plugin disable` does not affect an already-running session. New rule: assert the plugin was disabled **before** session start, verifiable after the fact by comparing the session transcript's birth time (`stat -f %SB ~/.claude/projects/<encoded-cwd>/<sid>.jsonl`) against `~/.claude/settings.json` mtime. Grepping a transcript for `loomwright` proves it was never *invoked*, not that it was never *loaded*. | Yes — tightens an existing precondition, adds no metric. |
| 2026-07-27 | **Enablement is user-scope and shared** — `~/.claude/settings.json` → `enabledPlugins["loomwright@atelier"]` is read by BOTH the desktop app and a bare CLI `claude` (all processes run `--setting-sources=user,project,local`). "The plugin is only installed in the desktop app" is false and must not be assumed. Verified by probe: a session started with the flag `true` lists `loomwright:*` commands; one started after it flipped to `false` does not. | Yes — corrects a factual premise in §"Plugin version control". |

**Discarded run retained as a side observation (NOT a Results row).** The first arm-1 attempt
(`eval/tree-and-find/arm-1-CONTAMINATED-plugin-loaded`, commit `69feda2`) ran ~37 min with the
plugin **loaded but never invoked** (0 `loomwright` occurrences in its transcript). It is excluded
because `wall_tokens` is inflated by construction when the plugin's prompt inventory rides in every
turn. Kept because the comparison is interesting: 1,658 ins / 10 files (impl 505, tests 1,079;
ratio 2.14) vs the clean baseline's 1,838 / 12 (impl 759, tests 1,027; ratio 1.35). Test *volume*
is near-identical — the ratio gap is a denominator effect from the clean run factoring out
`Glob.swift` / `FileName.swift` / `WalkTarget.swift`. The one suggestive behavioural difference:
the contaminated run also stamped `STATUS.md` and the backlog overview as done, which resembles
Loomwright's completion-tail discipline. Corpus v2 makes solution leakage impossible either way.

## Outcome

_Pending. To be filled after the 15 runs, followed by the decision-rule verdict per layer:
SDK runner graduates to v16 OR is cut; each Loomwright layer that fails to beat arm 1 is cut._

## Per-layer verdict (EMPTY until runs execute — closed 3-value enum, no third outcome)

One row per layer under test. **`verdict` is a closed enum: `KEEP` | `CUT` | `INSUFFICIENT DATA`.**
The pre-committed decision rule (§"Decision rule") admits no fourth value — in particular there is
no "keep with caveats" and no "defer". A layer that did not move its metric is `CUT`, not defended.

- **`KEEP`** requires naming the metric that moved *and* the magnitude, cited from the Results table.
- **`CUT`** requires a follow-up requirement stub to exist before this row is final (§Scope item 5;
  no deletions are performed in this item — verdicts only).
- **`INSUFFICIENT DATA`** is legitimate ONLY when the run cap was hit or an arm failed to execute;
  it must name what would resolve it. It is not a way to avoid cutting a layer.

| Layer under test | Arms compared | Metric that moved (cite Results row) | Magnitude | Verdict | Follow-up stub (CUT only) |
|---|---|---|---|---|---|
| SDK runner | arm 2 vs arm 3 | | | | |
| Multi-voter heal | arm 2 vs arm 3 | | | | |
| QA rule libraries (~1,904 lines) | arm 2 vs ablation (a) | | | | |
| Magic budgets / caps | arm 2 vs ablation (c) | | | | |
| Whole Loomwright stack | arm 1 vs arm 2 | | | | |

> **Arm-3 confound (record, do not silently split):** arm 3 moves **two** levers at once (SDK runner
> AND multi-voter heal), so an arm-2-vs-arm-3 delta cannot by itself attribute the change to either
> row above. If the delta is non-zero, both rows are `INSUFFICIENT DATA` pending a single-lever
> follow-up arm — not a split guess. This is a known limitation of the pre-registered 3-arm shape,
> surfaced here rather than resolved by inference.

## Incident-class regression log (EMPTY until ablation arms execute)

§Scope item 3: incident-derived guards are **tested, not presumed** — an ablation that removes a
guard must watch for the original incident class recurring, and *a guard that still prevents its
incident KEEPS regardless of metric movement* (empirical incident data overrides the Bitter Lesson
prior). One row per ablated guard; the watch criteria are defined per-arm in §"Ablation arms".

| Ablated guard | Arm | Incident class watched for | Recurred? | Evidence | Effect on verdict |
|---|---|---|---|---|---|
| QA rule libraries | ablation (a) | State leaking across test runs; missing infrastructure detection (Mailpit/MailHog); budget exhaustion terminating the suite early | | | |
| Magic budgets / caps | ablation (c) | Session >2× default arm's wall tokens; non-terminating phase loop; context-window exhaustion mid-task | | | |

> **Precedence rule:** if `Recurred? = YES`, the layer is `KEEP` in the verdict table even when its
> pre-registered metric did not move. Record the incident evidence in both tables.

## Amendment history

Pre-registration discipline (§Protocol): amendments are **additive only**, recorded with a date,
and never weaken the original protocol. The original §Question → §Protocol text is byte-unchanged
above; verify with:

```bash
# Scope the check to the pre-registered region (§Question → §Protocol). The whole-file form
# reports deletions once runs begin — filling the Results table necessarily replaces its "EMPTY
# until runs execute" header and its empty placeholder row — and a reader running the unscoped
# command would get a false "the protocol was weakened" signal.
awk '/^## Question/{p=1} /^## Corpus/{p=0} p' <this file>   # the region that must not change
git diff origin/main...HEAD -- <this file> | grep -c '^-[^-]'   # whole-file: 0 BEFORE first run only
```

**Once runs have started, only the §Question → §Protocol region carries the byte-unchanged
guarantee.** Deletions below §Corpus (Results header, placeholder rows) are expected and do not
indicate a weakened pre-registration.

> **Run-time amendments live in a second table** — §Results → "Amendments — recorded at run time".
> They are kept separate because they cannot claim `EMPTY (verified)` in the last column below (by
> definition a run had already executed). Read both tables for the complete amendment log.

| Date | Amendment | Additive? | Results table state at amendment time |
|---|---|---|---|
| 2026-07-18 | Added `token-cost-per-subtask` as an arm-3 secondary observable (§"Pre-registered metrics") | Yes — new observable, no metric removed or redefined | EMPTY (verified) |
| 2026-07-24 | Added §Corpus (5 requirements + base commits) and §"Execution Runbook" (3 base arms + ablation arms (a)/(c); (b) deferred and recorded) | Yes — operationalizes the existing protocol; no protocol text altered | EMPTY (verified) |
| 2026-07-27 | Replaced the arm plugin-pinning mechanism with session-scoped `--plugin-dir` after empirically falsifying the global uninstall/reinstall path (§"Why NOT `/plugin install loomwright@atelier`"); added §"Per-layer verdict", §"Incident-class regression log", and this history | Yes — corrects an execution mechanism and adds recording surfaces; no metric, arm, or decision rule changed | EMPTY (verified) |
| 2026-07-27 | **Corpus swapped to `vikashruhilgit/ntfs-tool` (§"Corpus v2")**, single base commit `5df1ded`, all arms at plugin v15.14.0. Corpus v1 marked SUPERSEDED and retained verbatim with its three defects recorded. Added the metric-availability check and two pre-flight items (Actions spending limit, branch protection) | Yes — §Question, §Decision rule, §Pre-registered metrics and §Protocol are byte-unchanged; only *which* requirements are measured changed, and the v1 table is retained rather than deleted | EMPTY (verified) |

> **Not yet amended — open decision before the first run.** §Scope item 2 requires "≥2 single-lever
> ablation arms" but does not pin *how many requirements* each ablation runs against. The runbook
> says ablations execute "from the same base commit as the corresponding requirement's base arms"
> without fixing the set. Both readings are live: **2 ablation runs total** (~17 sessions) or
> **2 arms × 5 requirements** (~25 sessions). Ablations are budgeted separately from the 15-run hard
> cap either way. **Decide and record this as an amendment BEFORE the first ablation run** — pinning
> it afterward is a retroactive protocol edit, which the pre-registration forbids.

> ### ✅ RESOLVED by the Corpus v2 swap — retained for the record
>
> The blocker below was **dissolved, not decided**: none of its three options (A/B/C) was chosen.
> Moving to a corpus of genuinely-unimplemented work removed the conflict at its source — there is
> no rewind, so no version to pin, no leakage, and arm 3 is available on all five entries. Kept
> because the *mechanism* of the conflict is worth remembering: pinning the plugin to a historical
> base commit silently un-provisions any flag introduced after it.
>
> **BLOCKER — open decision before ANY run: plugin-version policy vs arm 3 (found 2026-07-27).**
> §"Plugin version control" pins each arm's plugin to its requirement's **base commit**. But
> `--sdk-runner` and `--multi-voter-heal` were introduced in **v15.8.0**, and 4 of the 5 corpus
> base commits predate it — so arm 3 is **impossible** for them under base-commit pinning:
>
> | Corpus | Base commit | Plugin dir at that commit | Version | Arm 3 supported |
> |---|---|---|---|---|
> | #1 curation-anti-rot | `f55380b` | `loomwright/` | v15.13.0 | **yes** |
> | #2 rules-enforcement | `872cc81` | `loomwright/` | v15.0.0 | no |
> | #3 learning-loop-phase1-2 | `516687a` | `ai-agent-manager-plugin/` | v14.27.0 | no |
> | #4 review-drain-worktree-isolation | `142319e` | `ai-agent-manager-plugin/` | v14.41.0 | no |
> | #5 handoff-digest | `49868b1` | `ai-agent-manager-plugin/` | v14.48.0 | no |
>
> Note also the **plugin directory was renamed** (`ai-agent-manager-plugin/` → `loomwright/`), so
> the `--plugin-dir <checkout>/loomwright` path in the arm blocks is wrong for entries #3–#5 under
> base-commit pinning — the path must follow the commit.
>
> Resolve by choosing ONE policy and recording it as an amendment **before the first run**:
> - **(A) Single fixed plugin version for the whole eval** (recommended) — pin every arm of every
>   requirement to one recorded plugin SHA at ≥ v15.8.0 (e.g. current `main`). Arm 3 becomes
>   executable across the full corpus; version stops being a variable entirely, so an ablation
>   differs from its arm-2 baseline by exactly one lever. Cost: the harness is newer than the
>   working tree, so a Loomwright arm *could* read post-merge code out of the plugin dir. That
>   leakage applies **uniformly to all Loomwright arms**, so arm-2-vs-arm-3 and
>   arm-2-vs-ablation (the comparisons that drive the per-layer verdicts) stay clean; only
>   **arm-1-vs-arm-2** carries the asymmetry — record it as a stated limitation.
> - **(B) Keep base-commit pinning, drop arm 3 to n=1** — only corpus #1 gets an arm 3. Preserves
>   zero leakage; guts arm-3 statistical power and leaves the SDK-runner verdict at
>   `INSUFFICIENT DATA` by construction.
> - **(C) Change the corpus off Loomwright's own history** — eliminates leakage at the root and is
>   the strongest science, but is a substantial protocol change (new corpus, new base commits, new
>   selection rationale) and re-opens §Corpus.


