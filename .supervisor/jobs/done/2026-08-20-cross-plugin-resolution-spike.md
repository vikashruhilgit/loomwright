# Supervisor Job: Empirically resolve the three cross-plugin resolution unknowns and ship a dated, re-runnable decision record

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — last touched 2026-08-17, current release banner matches `plugin.json` 15.36.0)
- **Git:** dirty (2 files: `.supervisor/postmortem/results.jsonl` modified, `loomwright/docs/SPIKES/IMPECCABLE_TEARDOWN.md` untracked), branch: main, in sync with origin/main (0 ahead / 0 behind)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit; scopes gist, read:org, repo, workflow)
- **Blockers:** 0 | **Warnings:** 3
- **Source requirement:** `.supervisor/requirements/selvedge-extraction/01-cross-plugin-resolution-spike.md`
- **Base commit:** 3d27a1bbf4671d37c862ccb2de421373a999ca2c

**Warnings detail (none blocking):**
1. Working tree dirty (2 files). Neither is in this brief's lanes; both are pre-existing and unrelated.
2. 9 registered worktrees, 2 of them `prunable`. Pre-existing; not created by this run.
3. **Source-doc provenance unverified** — the source requirement is uncommitted because `.gitignore:78` ignores `.supervisor/*` wholesale. This is structural (every requirement file in this repo is gitignored), not a draft-vs-truth risk. Recorded rather than escalated. It is also precisely why AC6 insists the *findings* doc live under `loomwright/docs/` — verified commitable: `git check-ignore` does not match `loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md`.

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | The spike's only "stack" is the `claude` CLI plus bash/markdown. `claude --version` → **2.1.228 (Claude Code)**; `claude plugin --help` resolves with `marketplace`, `install`, `uninstall`, `list`, `details`, `validate` subcommands. Verified by execution, not inferred. |
| 2 | Dependency Availability | GO | Every subcommand the probe needs exists and is non-interactive: `claude plugin marketplace add <source>` documents `<source>` as "a URL, **path**, or GitHub repo" and accepts `--scope user\|project\|local`; `claude plugin install <name>@<marketplace> --scope local`; `claude plugin uninstall`; `claude plugin marketplace remove`. No new third-party dependency is introduced. |
| 3 | Architecture Fit | GO | The deliverable is a committed evidence doc plus a re-runnable probe fixture under `loomwright/docs/SPIKES/`, matching the precedent CLAUDE.md's current release banner sets for `docs/SPIKES/code-graph-harness/` ("committed verbatim as a runnable closure … any revival must pass it"). The probe marketplace is registered by path at `local` scope and never enters `.claude-plugin/marketplace.json`. |
| 4 | Scope vs Supervisor Capability | GO | One coherent deliverable (one findings doc + one small probe fixture directory), far under the Decomposition Threshold's `context-bound` bound (> 12 files / > 800 lines) and with no second file-disjoint group of ≥ 3 files, so `genuine-parallelism` does not fire either. Single subtask. |
| 5 | Hard Blockers | CAUTION | No hard blocker, but one real constraint and one real side effect. **(a) Registration constraint:** a newly installed plugin's agents/skills/hooks do not register in the session that installed it, and a Supervisor worker is a Task subagent of the dispatching session — so the worker **cannot** spawn the probe agent in-process. Every probe must therefore be observed from a **fresh `claude -p`** process. This was measured before dispatch and is recorded as a dated `## Method note` in the source requirement. **(b) Side effect:** the probe mutates plugin-manager state. Constrained to `--scope local` by owner decision (below), and teardown is promoted to a first-class, asserted acceptance criterion rather than a closing courtesy. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Empirically answer the three cross-plugin resolution unknowns (`skills:` preload across plugins, `${CLAUDE_PLUGIN_ROOT}` inside a second plugin's `hooks.json`, and `Task(subagent_type:)` from a loomwright surface to a second-plugin agent) by running a throwaway probe plugin, and ship a dated, version-stamped, re-runnable decision record — moving no QA asset.

**Problem Statement:**
The `selvedge` extraction needs a companion-plugin model in which selvedge may depend on loomwright-owned shared assets instead of vendoring copies. Every one of the six downstream slices assumes three cross-plugin resolutions work, and **none has ever been exercised in this repo** — `stackpack`, the only prior spin-off, ships 18 skills and zero agents, commands, hooks, or scripts, so it is a precedent for none of the three.

Currently the assumption is untested, and the failure mode is **silent**: CLAUDE.md §"Hook gotcha" already records that Claude Code silently ignores `hooks`, `mcpServers`, and `permissionMode` in plugin agent frontmatter, so silent-ignore is an established behaviour for this exact frontmatter block. A dropped `skills:` preload fails no gate and logs nothing; an unset `${CLAUDE_PLUGIN_ROOT}` under the plugin's `|| true` hook convention exits 0 and validates nothing. This causes the whole extraction to be planned on three guesses that would only surface as quietly-degraded QA agents and a silently-dead validation hook after the assets had already moved.

Success looks like: a committed `loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md` that records, per unknown, the probe used, the **raw observed output**, a RESOLVES / DOES NOT RESOLVE / RESOLVES WITH CAVEAT verdict, the measurement date and the Claude Code version — plus a chosen, justified fallback for every NO — with the probe itself committed alongside so the measurement can be re-run when Claude Code changes.

## Acceptance Criteria
- [ ] Given the three unknowns, when each is investigated, then each is answered by an **executed probe** and the findings doc records its **raw observed output** verbatim — not a summary, not a code/doc trace, not inference.
- [ ] Given Unknown A (cross-plugin `skills:` preload), when the probe runs, then it uses **two throwaway plugins generated inline by `run-probe.sh`** — `probe-host`, which owns a skill whose body carries a **run-scoped nonce**, and `probe-consumer`, whose agent's `skills:` frontmatter names *`probe-host`'s* skill — and the verdict "resolves" is asserted **only** on that nonce appearing in the spawned `probe-consumer` agent's output. **No tracked file is mutated by any probe.** (Rationale, and the reason this is not the obvious "inject a nonce into a loomwright skill" design: installed plugin bodies are **separate snapshots**, not live views of this checkout — verified at plan time, `claude plugin details loomwright` reports source `loomwright@atelier`, and that marketplace is its own git clone of `https://github.com/vikashruhilgit/loomwright.git` under `~/.claude/plugins/marketplaces/atelier/`. A nonce written to the repo working copy — or to a worktree, a third remove — could never reach the preloaded body, so that design's only reachable outcome is a **false DOES NOT RESOLVE**. Authoring both plugins makes mutation-target and preload-source the same file by construction.)
- [ ] Given Unknown A's primary arm returns a verdict, when it is corroborated, then a **second, strictly read-only arm** repeats the test against the **real** loomwright-owned skill `quality-checklist`: `run-probe.sh` resolves the loomwright install path the probe session actually loads, records that path **verbatim** in the findings doc, asserts a chosen marker phrase is present **in that installed body** (not in the repo copy), and checks whether it reaches the probe agent's output. This arm mutates nothing. Disagreement between the two arms is itself a recorded finding, not an error to reconcile away.
- [ ] Given the sentinel test, when `probe-consumer`'s agent is declared, then its frontmatter grants **no filesystem-read capability** (no `Read`, `Glob`, or `Grep` — following the repo's own `tools:`/`disallowedTools:` idiom in `loomwright/agents/plan-reviewer.md`), so preload is the **only** channel by which the nonce can reach its output; because `run-probe.sh` is committed and generates that frontmatter from a heredoc, the exact frontmatter is **readable in committed source**, and it is also recorded verbatim in the findings doc. Without this the sentinel result is confounded and a false RESOLVES is possible.
- [ ] Given a nonce-absent observation, when it is written up, then it is recordable as **DOES NOT RESOLVE only after** the run has demonstrated that the mutation target and the preload source are the same file (trivially true for the generated-fixture arm; established by the recorded install path for the corroboration arm). Absent that demonstration it is recorded as **UNMEASURED**, never as a NO.
- [ ] Given Unknown B (`${CLAUDE_PLUGIN_ROOT}` in a second plugin's `hooks.json`), when the probe hook fires, then the **literal expanded value** is recorded, **and** the empty/unset case is explicitly ruled in or out by writing the value in a form that distinguishes the two (e.g. `printf '[%s]
'`) to an **absolute** scratch path — because the `|| true` convention makes an unset expansion exit 0, a green run is not evidence. Absence of the output file is itself a recorded result, never an inconclusive skip.
- [ ] Given Unknown C (cross-plugin `Task(subagent_type:)`), when both the single-prefix and doubled-prefix forms are attempted from a loomwright surface, then the exact working `subagent_type` string is recorded **verbatim**, and the failing form is recorded together with its **verbatim error text**.
- [ ] Given any unknown answered NO, when the fallback is selected, then the findings doc justifies it **against the stated alternatives** — not merely lists them.
- [ ] Given every probe, when it runs, then `run-probe.sh` **tees** its stdout and stderr to a committed transcript under `loomwright/docs/SPIKES/cross-plugin-probe/transcripts/`, and **every block quoted in the findings doc appears verbatim in one of those committed transcripts** — giving a reviewer a mechanical cross-check instead of a single self-authored prose artifact. *(Honest limit, stated in the doc: this does not make fabrication impossible — one agent can author both artifacts — it makes it require two consistent ones. The only true anti-fabrication anchor is a human re-run, so the doc must also state the exact re-run command.)*
- [ ] Given the probe ran, when the run ends **by any path including failure or interrupt**, then a `trap`-based teardown has removed **both** throwaway plugins and the throwaway marketplace, and `claude plugin list` + `claude plugin marketplace list` are asserted to show neither — **and to show no loomwright registration the run did not inherit** (the run must not leave a second loomwright install behind). That raw assertion output is committed to `.../transcripts/2026-08-20-teardown.log` and quoted in the findings doc.
- [ ] Given the PR at merge, when the range-form diff `git diff --exit-code origin/main...HEAD -- loomwright/skills/ loomwright/agents/ loomwright/commands/ loomwright/hooks/` is run, then it exits clean — proving no probe write leaked into a shipped plugin surface. The **range** form is required, not `git diff -- <path>`: the working-tree-vs-index form exits 0 when a stray edit was *committed*, which is exactly the shipping case this check exists to catch. The command and its output are quoted in the findings doc.
- [ ] Given a fresh clone, when `loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md` is opened, then it is present, dated, names the Claude Code version measured against (**2.1.228**), and states the **exact re-run command** for `run-probe.sh`, so a future reader can tell whether the answer has expired and can re-measure it.
- [ ] Given a fresh clone, when `loomwright/docs/SPIKES/cross-plugin-probe/` is opened, then `README.md`, `run-probe.sh`, and the four transcripts are present and re-runnable. **The throwaway probe plugins are NOT committed** — `run-probe.sh` generates every probe artifact (both `plugin.json`s, the probe marketplace manifest, the `probe-consumer` agent `.md`, the `probe-host` skill body, and the probe `hooks.json`) inline from heredocs at run time and deletes them at teardown. This is what keeps the create-count at 7 while still making every asserted frontmatter and hook command readable in committed source.
- [ ] Given the PR at merge, when `git diff` is inspected, then `.claude-plugin/marketplace.json` is unchanged, no QA agent/command/skill/hook has moved, no `selvedge/` scaffold exists, and the agent/command/skill/hook counts in `plugin.json` are unchanged.
- [ ] Given the PR, when CI runs, then all gates are green.

## Outcomes Rubric
- Three unknowns empirically resolved, each with raw observed evidence, not inference
- Sentinel-based proof for the preload question — no self-reported "I read the skill"
- The silent-failure paths (dropped preload, unset `${CLAUDE_PLUGIN_ROOT}` under `|| true`) are
  explicitly ruled in or out rather than assumed absent
- A chosen, justified fallback exists for every NO — the queue can proceed either way
- Evidence is committed and citable from a fresh clone, dated, and version-stamped
- No QA asset moved, no count changed, repo green

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

> **Why this section is emitted even though the strict trigger does not fire.** The plugin-self authoring convention's affirmative rule fires when (a) the target is this plugin's repo **and** (b) the brief touches the doc-currency surface. (a) holds. (b) was **measured, not assumed**: `scripts/check-doc-currency.sh` (repo-root `scripts/`, *not* `loomwright/scripts/`) declares a 9-entry `FILES` array — `CLAUDE.md`, `README.md`, `AGENT_GUIDELINES.md`, `.claude-plugin/README.md`, `.claude-plugin/marketplace.json`, `$PLUGIN_JSON`, `loomwright/commands/agent-help.md`, `loomwright/docs/ARCHITECTURE.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` — and `loomwright/docs/SPIKES/` is **not** among them, so (b) is false and the strict trigger does not fire. The section is emitted anyway because the convention's rule is affirmative, not exclusive ("omit unless a plugin-bundled `corpus-task:` id genuinely matches"), both ids are plugin-bundled and verified present under `loomwright/scripts/eval-corpus/`, and both invariants genuinely must hold for this PR. The deciding reason is a recorded lesson: `contract_conformance_status` / `ground_truth` **`skipped` means UNVERIFIED, not clean**, and omitting the section would hand Phase 4.5 a `skipped` ground-truth signal that reads as green. Emitting converts an unverified axis into a verified one at negligible cost. **Machine-authored-brief trust boundary respected:** `corpus-task:` bullets only — no `cmd:`/bare-shell bullet appears in this brief.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Run the three cross-plugin probes and ship the dated findings doc + re-runnable probe fixture | All 15 | 0 modify, 7 create (no tracked file is mutated by any probe) | `skills/quality-checklist/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md"}
  - {kind: "symbol", path: "loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md", name: "## Unknown A — cross-plugin skills preload resolution"}
  - {kind: "symbol", path: "loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md", name: "## Unknown B — CLAUDE_PLUGIN_ROOT inside a second plugin hooks.json"}
  - {kind: "symbol", path: "loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md", name: "## Unknown C — cross-plugin Task subagent_type resolution"}
  - {kind: "symbol", path: "loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md", name: "## Chosen fallbacks and why"}
  - {kind: "symbol", path: "loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md", name: "## Measurement provenance and teardown"}
  - {kind: "file", path: "loomwright/docs/SPIKES/cross-plugin-probe/README.md"}
  - {kind: "file", path: "loomwright/docs/SPIKES/cross-plugin-probe/run-probe.sh"}
  - {kind: "file", path: "loomwright/docs/SPIKES/cross-plugin-probe/transcripts/2026-08-20-unknown-a.log"}
  - {kind: "file", path: "loomwright/docs/SPIKES/cross-plugin-probe/transcripts/2026-08-20-unknown-b.log"}
  - {kind: "file", path: "loomwright/docs/SPIKES/cross-plugin-probe/transcripts/2026-08-20-unknown-c.log"}
  - {kind: "file", path: "loomwright/docs/SPIKES/cross-plugin-probe/transcripts/2026-08-20-teardown.log"}
requires: []
lanes:
  - "loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md"
  - "loomwright/docs/SPIKES/cross-plugin-probe/**"
external_requires:
  - "claude CLI >= 2.1.228 with the `claude plugin` subcommand tree (marketplace add/remove, install, uninstall, list, details)"
  - "A writable plugin-manager state at `local` scope (the probe registers and removes a throwaway marketplace by path)"
```

> **Heading tokens are authored, not guessed.** All six `symbol` provides are H2 headings in a file this subtask CREATES, and they are written **without backticks or `${}`** deliberately: sibling docs under `loomwright/docs/SPIKES/` use plain `##`/`###` headings, and a token carrying backticks or a `$`-brace risks a match failure in the deterministic `outputs_verified` gate for reasons unrelated to the work being done. The worker MUST use these exact heading strings.

### Dependency Graph
```
Subtask 1 (independent — single subtask, no edges)
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | none (single subtask) | NO |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **The whole spike is fakeable.** Every unknown can be "answered" by reading code and writing a confident paragraph; nothing in CI can tell a measured verdict from an invented one. Mechanically: the deterministic `outputs_verified` gate confirms only that some headings and files exist, and **every pinned `provides` entry lives in a file this subtask itself creates** — the self-satisfiable pattern already recorded as a recurring defect in this repo. | HIGH | Three layers, none of them sufficient alone and all three stated as such. (1) The findings doc MUST quote **raw captured output** (command line + verbatim stdout/stderr); a verdict with no quoted raw output is a review FAIL, not a style nit. (2) `run-probe.sh` **tees** every probe to a committed transcript, and each quoted block must appear verbatim in one — turning a single self-authored artifact into two that must agree. (3) The doc must state the exact **re-run command**. **Honest limit, to be written into the doc itself:** one agent can author both the doc and the transcripts, so this raises the cost of fabrication rather than eliminating it — the only true anchor is a human re-run. |
| **Sentinel provenance — the obvious design is the wrong one (Plan Review, attempts 1 and 2).** Attempt 1 found that no loomwright skill carries a unique sentinel, so one must be injected. Attempt 2 then found the injection route is **unreachable**: installed plugin bodies are separate snapshots, not live views of this checkout. **Verified at plan time:** `claude plugin details loomwright` reports source `loomwright@atelier`; that marketplace lives at `~/.claude/plugins/marketplaces/atelier/` and is its own **git clone of the remote** (`origin` → `https://github.com/vikashruhilgit/loomwright.git`, currently at the same commit `3d27a1b`, so the body is byte-identical today but is a **different file on disk**). A worker in a git worktree is a third remove. A nonce written to the repo copy could therefore never reach the preloaded body — and with read tools stripped, the only reachable outcome would be a **false DOES NOT RESOLVE**, gating six downstream slices onto the wrong fallback. | HIGH | The mutation route is **removed, not patched**: `run-probe.sh` generates **two** throwaway plugins, so the nonce lives in a fixture this run authors and mutation-target == preload-source holds by construction. No tracked file is written at all, which also dissolves the restore/lane/leak surface the earlier design created. A second **read-only** arm corroborates against the real loomwright skill by resolving and recording the actual install path and asserting the marker phrase is present **in that installed body**. A dedicated AC forbids recording a nonce-absent result as DOES NOT RESOLVE until mutation-target == preload-source has been demonstrated — otherwise it is UNMEASURED. |
| **A confounded sentinel produces a false RESOLVES.** "The nonce appeared in the agent's output" proves preload only if the agent could not have read it off disk. An agent retaining `Read`/`Grep` can fetch the nonce directly. The source requirement's Method step 2 has this same hole. | HIGH | `probe-consumer`'s frontmatter grants **no filesystem-read capability**, following the repo's own `tools:` + `disallowedTools:` idiom (`loomwright/agents/plan-reviewer.md` declares the full list then subtracts down to Read/Glob/Grep — the probe subtracts those too). Because `run-probe.sh` is committed and emits that frontmatter from a heredoc, the isolation is **auditable in committed source**, not merely self-reported in prose. |
| **Probe state outlives the run.** The probe registers a marketplace and installs two plugins in the developer's plugin-manager state — a side effect no `git checkout` undoes. A crash mid-spike leaves them behind. | MEDIUM | `--scope local` only (owner decision — never `user`, never `project`); `trap`-based teardown so it runs on failure and interrupt paths, not just the happy path; and an **asserted** post-condition covering both plugins, the marketplace, **and** the absence of any loomwright registration the run did not inherit — with raw output committed to a transcript. If `local` scope turns out not to register agents/hooks, that is itself a **finding to record**, not licence to retry at `user` scope. |
| **Prior churn on the touched surface.** `read-postmortem.sh` reports 5 prior churn rounds on `loomwright/docs/SPIKES/`-adjacent paths — recurring classes `drain_churn` (3) and `convention_mismatch` (2), flow stages `self_heal` (3) / `worker` (2), no `self_heal_miss`. | MEDIUM | Source: prior churn (postmortem ledger). `convention_mismatch` on this surface historically means doc-shape drift against sibling SPIKES docs — match the existing banner/date/version-stamp conventions in `CODE_GRAPH_OWNERSHIP.md` and `FINAL_STATE_GOAL.md` rather than inventing a new layout. |
| **A partial answer reads as a full one.** If one of the three probes cannot be executed, a doc that quietly covers two and narrates the third would gate six downstream slices on a guess. | MEDIUM | Any unexecutable probe must be recorded as an explicit **UNMEASURED** verdict naming what blocked it — never as an inferred RESOLVES/DOES-NOT-RESOLVE. A partial result is an acceptable, honest outcome; a disguised one is not. |
| **Doubled-prefix expectation could bias Unknown C.** Project memory records that loomwright agents spawn as `loomwright:loomwright:<role>` and that the single-prefix form errors (verified 2026-08-08). The requirement explicitly forbids inferring selvedge's form from that pattern. | LOW | Advisory context only. Both forms must be **attempted against the probe plugin** and both outcomes recorded verbatim; the loomwright precedent may be cited as context but never substituted for the measurement. |
| Working tree carries 2 unrelated dirty files and 2 prunable worktrees at dispatch. | LOW | Neither dirty file is in this subtask's lanes; the run works in its own worktree. Recorded for provenance only. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

> **Owner decisions taken at plan time (2026-08-20), recorded so the worker does not re-litigate them:**
> 1. **Evidence shape — doc PLUS committed probe harness.** Slice 01's ACs say "delete the throwaway probe plugin; the findings doc is the deliverable", but they also require the evidence be "reachable from a fresh clone", and this repo's own graphify retirement set the precedent of committing a validation harness under `docs/SPIKES/code-graph-harness/` so the reversal condition stays re-runnable. Both hold together: nothing stays **installed**, `.claude-plugin/marketplace.json` stays **unchanged**, and the fixture lives under `loomwright/docs/SPIKES/cross-plugin-probe/` (a docs path — it adds no agent/command/skill/hook count).
> 2. **Install scope — `--scope local` only.** Never `user` (machine-global) and never `project` (would write `.claude/settings.json` into the repo and leak into the PR). A local-scope install that fails to register is a **finding**, not a trigger to escalate scope.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-20-cross-plugin-resolution-spike.md
```
