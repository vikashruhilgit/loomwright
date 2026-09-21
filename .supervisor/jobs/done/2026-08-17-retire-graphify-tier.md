# Supervisor Job: Retire the graphify/bridge tier and split D9 by regenerability

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — banner is the v15.35.0 dreaming-triage entry)
- **Git:** dirty (1 file — `.supervisor/postmortem/results.jsonl`, the engine-native learning line PR #147's drain emitted; committed store, unrelated to this work), branch: main @ c7f084f == origin/main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (dirty ledger line above; multiple pre-existing worktrees from earlier runs — none on this item's base)
- **Source requirement:** `.supervisor/requirements/twin-loop/06-retire-graph-and-split-d9.md`

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | removal + doc work in the same bash/markdown substrate; harness commit is a verbatim file copy |
| 2 | Dependency Availability | GO | every surface named below exists and was read this session; the harness closure (`validate.py` + `validate_gen.py` + `reposcan_multi.py`, 386 lines) is on disk in `.supervisor/scratch/code-graph-spike/` |
| 3 | Architecture Fit | GO | the enrichment ladder is designed for rung removal — every consumer already silent-no-ops on the absent graph, so unwiring formalizes measured reality |
| 4 | Scope vs Supervisor Capability | CAUTION | ~30 touched files exceeds the single-subtask default on the `context-bound` predicate — split into 3 sequential subtasks, see `## Configuration` |
| 5 | Hard Blockers | GO | no credentials, no migration, no missing module |

**Overall Verdict:** CAUTION (scope) — proceeding with a 3-subtask split.

## Task
**Goal:** Remove the graphify/bridge tier cleanly (scripts, five live seams, and the `/setup` twin module that exists solely to bootstrap it), replace D9's blanket no-auto-delete rule with a split keyed on regenerability, banner-mark the spike evidence without deleting it, and commit the validation harness so the stated reversal condition is actually citable from a fresh clone.

**Problem Statement:**
Measured 2026-08-06 and re-verified today: `graphify-out/graph.json` is absent (built once 2026-06-22, gitignored, never rebuilt), `.supervisor/bridge/bridge.json` survives as a 255-commits-stale orphan, `read-bridge.sh` emits nothing against it, and `brain_context` appears 0 times across all session logs — not one run ever recorded consuming the tier. The tier's own north-star doc named the exact hazard it fell into ("the staleness trap"). The 71% Step-4 gate score has no control arm (every strict hit is anchored by a shared file a plain path join would also have found), and the tier targets `missing_context` (1.9% of own-repo misses, one single miss) while `convention_mismatch` (66% own-repo) is served better by the committed rules substrate items 03–05 shipped. The maintenance model — expensive deliberate rebuild, gitignored, silent degradation — is the disease; this item removes it and encodes the lesson as a regenerability rule.

### Measured corrections to the requirement (verified this session — do NOT plan against the requirement's wording)

1. **`twin-graph.sh` and `test-twin-graph.sh` are NOT graphify-tier scripts and are RETAINED.** The requirement's script-disposition list lumps them in by name. Read on disk: `twin-graph.sh` is the blast-radius helper for the **System Twin contract store** (`.supervisor/twin/`), reads via `read-system-contract.sh`, never touches `graphify-out/` or the bridge, has live consumers (`agents/launch-pad.md`, `docs/RESULT_SCHEMAS.md` §SYSTEM_CONTRACT), and its test was actively modified in v15.33.0. Deleting it would break a live, unrelated subsystem. Disposition: RETAIN, untouched, reason recorded.
2. **The tier has FIVE live seams, not three, plus a bootstrap module the requirement never names, plus four passive committed surfaces.** Beyond the requirement's three (brain-context, self-heal-advisory §1d, launch-pad), the sweep finds: `agents/code-reviewer.md:278` (brain-consult bullet) + `:556–562` (reachable-tag passage) and `skills/context-setup/SKILL.md:88` (step 4.5 `GRAPH_PRESENT` detection). `scripts/setup-twin.sh` + `test-setup-twin.sh` + the `/setup` **twin module** (`commands/setup.md` + `skills/setup/SKILL.md` registry row + `README.md`/`agent-help.md` mentions) exist solely to bootstrap the tier being retired — AC1 is unsatisfiable while they stand; they retire with the tier (settled decision (b)). Four **passive** surfaces also hit the sweep and get annotations, not removals: `docs/POINTER_AUDIT.md:48` (AC9b), the two `scripts/brain-baseline-corpus/` files (AC9c), and `scripts/validate-entry.sh:1038`'s frozen incident comment (AC13 category). *(The four passive surfaces were surfaced by Plan Review attempt 1, which falsified this correction's original "exactly five seams" claim — recorded rather than silently absorbed.)*
3. **The harness is a 3-file closure, not 2.** `validate.py` and `validate_gen.py` both `import reposcan_multi` — committing only the two named files ships an unrunnable harness, repeating the exact unreachability error the requirement warns about. The committed set is all three, plus a README stating the external deps (`tree-sitter`, `tree-sitter-typescript`, invoked via `uv run --with …`).
4. **The D9 variant sweep mostly resolves to "traced, correctly unchanged".** The `flag-only, never auto-delete` strings in `build-insights.sh` / `test-insights.sh` are claims about the **distilled** stores (rules, orientation, lessons), which under the new split remain "No auto-delete" — they stay true and are NOT edited. `README.md:17` is a frozen historical changelog quote (left per the frozen-example-value convention). The only surface carrying the blanket form as a live rule is `FINAL_STATE_GOAL.md:40` itself.

## Acceptance Criteria

- [ ] **AC1** Given the orphaned local artifacts `.supervisor/bridge/{bridge.json,bridge.md}`, when Subtask 1 completes, then they are deleted from the working machine (gitignored — no diff; the deletion is recorded in the PR body and Progress, not the diff) and no committed path in the repo reads `.supervisor/bridge/` or `graphify-out/` any longer.
- [ ] **AC2** Given the script set, when Subtask 1 completes, then `build-bridge.sh`, `build-bridge.py`, `read-bridge.sh`, `test-build-bridge.sh`, `setup-twin.sh`, `test-setup-twin.sh` are **deleted** (`git rm`), and `twin-graph.sh` + `test-twin-graph.sh` are **byte-untouched** (measured correction 1).
- [ ] **AC3** Given the five live seams, when each is unwired, then: `skills/brain-context/SKILL.md`'s ladder reads memos → repo-map → nothing (graphify rung + "Bridge read" section removed, a short retirement note with the reason left in place); `skills/self-heal-advisory/SKILL.md`'s §"Area-knowledge advisory (graph-community bridge)" and the Phase 4.5 step-1d bridge read are removed (the `prior_churn` and `house_rules` enrichments are untouched); `agents/launch-pad.md` loses action 0c, the Phase 3 brain-consult bullet, and Phase 5 action 4b; `agents/code-reviewer.md` loses its brain-consult bullet (line 278) **and** its reachable-tag passage (lines 556–562, which document `brain_context` as reachable "only when the optional brain-context consult fires" — removing the consult without this passage ships a self-contradicting agent prompt); `skills/context-setup/SKILL.md` loses the step-4.5 graph detection. **Ladder fallback traced, not assumed:** for each removed consult, the worker states in the commit/PR body why every caller's success path is byte-identical (each reader was already a self-gating no-op with the graph absent).
- [ ] **AC4** Given the `/setup` twin module, when Subtask 1 completes, then `commands/setup.md` carries no `## Module: twin` section, no twin row in the status dashboard, no twin subcommand parameter — one line noting the module was retired with the tier (deliberate omission, matching the file's own style) — and `skills/setup/SKILL.md` loses the `twin` registry row and the twin sanctioned-write checklist item **in the same change** (that file's own rule). Subtask 3 sweeps the remaining twin-module mentions in `README.md` (3 live sites: 114, 184, 215 — line 47 is a frozen changelog quote and §502–532 is the **retained** System Twin contract store, both untouched) and `commands/agent-help.md` (module list at :799 + `/setup twin` example at :805 — the tree line at :1115 belongs to the retained System Twin `/obsidian` surface and is untouched), and the module count stated anywhere ("9 modules") is decremented.
- [ ] **AC5** Given the convention comments citing deleted scripts ("mirrors read-bridge.sh", "mirrors test-build-bridge.sh", "parity with read-bridge.sh", "mirrors setup-twin.sh / build-bridge.sh"), when Subtask 1 completes, then each is re-anchored to a **surviving** exemplar (`read-postmortem.sh` / `read-rules.sh` / an existing test) or reworded — enumerated set: `read-rules.sh`, `read-orientation.sh`, `build-repo-map.sh`, `build-handoff.sh`, `build-loop-evidence.sh`, `setup-memory.sh`, `test-build-handoff.sh`, `test-set-otel-resource-attrs.sh`, `skills/rules/SKILL.md` (§injection-safety comparison + two reader-idiom mentions). A comment pointing at a deleted file is this repo's recorded "claim no check backs" class; the sweep is part of the removal, not cosmetic.
- [ ] **AC6** Given `FINAL_STATE_GOAL.md:40` (D9), when Subtask 2 completes, then D9 is **amended, not silently rewritten**: the original blanket sentence is kept struck-through or quoted inside the amendment, the regenerability table from the requirement (Derived → auto-delete freely; Distilled → never) is recorded with its reasoning, and the amendment is dated. The variant sweep records measured correction 4's trace: which `flag-only` surfaces were checked and why they correctly stand.
- [ ] **AC7** Given `CODE_GRAPH_OWNERSHIP.md` and `LOCAL_TWIN_PATH.md`, when Subtask 2 completes, then each carries a status banner marking the tier RETIRED with the reason (maintenance model), the missing-control-arm finding, and a pointer to the reversal condition — and **no evidence content is deleted** (the ⚠️-corrected retracted claims stay).
- [ ] **AC8** Given the reversal condition, when Subtask 2 completes, then `loomwright/docs/SPIKES/code-graph-harness/` exists containing `validate.py`, `validate_gen.py`, `reposcan_multi.py` (copied **verbatim** from `.supervisor/scratch/code-graph-spike/` — byte-identical, provenance stated in the README, not in edited headers) plus a `README.md` stating: what the harness validates (edge precision + ranking validity against an independent import-graph ground truth), its external deps and invocation, and the reversal condition itself — any revival must be a **cheap incremental refresh** and must pass this harness. The condition thereby cites only committed files.
- [ ] **AC9** Given `docs/RESULT_SCHEMAS.md`, when Subtask 2 completes, then the v14.46.0 bridge note under `knowledge_sources_used` is annotated as retired (historical note kept, marked no-longer-live), the `brain_context` tag itself **stays in the open-set vocabulary** (open set, no schema change — annotated as having no live plugin-side emitter after this change), and the `twin-graph.sh` mentions are untouched (retained script).
- [ ] **AC9b** Given `docs/POINTER_AUDIT.md` row 10 (line 48), when Subtask 2 completes, then the row is annotated: `read-bridge.sh` and the `{area_knowledge summary}` enrichment line it cites are retired by this change (the row's claim about `read-postmortem.sh` / `read-rules.sh` stays live). A point-in-time audit register that asserts a retired reader is live is exactly the "claim no check backs" class — annotate, don't delete the historical row.
- [ ] **AC9c** Given `loomwright/scripts/brain-baseline-corpus/q1-what-calls-read-lessons.md` and `q2-blast-radius-read-bridge.md`, when Subtask 2 completes, then each carries a one-line header note that it was authored against the retired graphify tier (q2's whole subject is `read-bridge.sh`; q1:5 pins `graphify-out/graph.json`) and is retained as evaluation-corpus evidence — content otherwise intact.
- [ ] **AC10** Given the release surface, when Subtask 3 completes, then version is 15.35.0 → **15.36.0** in `plugin.json` + `.claude-plugin/marketplace.json` (descriptions updated **in place**, no appended clause), `CHANGELOG.md` gains the top entry (naming the user-facing removal of `/setup twin` prominently, not as a footnote), CLAUDE.md's Latest-change banner is replaced (version-free, count-free per its own rule), and **counts are UNCHANGED 14 agents / 21 commands / 41 skills / 24 hooks** — no agent/command/skill/hook file is added or removed by this change (deleted scripts are uncounted plain scripts; `brain-context` remains a skill, rewritten).
- [ ] **AC11** Given the full CI suite, when it runs after each subtask's commit and at the end, then every `test-*.sh` is green (the glob shrinks by two deleted tests — dynamic, no pinned count to update — verified by grepping ci.yml for any hardcoded test count first), `check-doc-currency.sh` is green, and no `15.35.0` string survives outside `CHANGELOG.md`.
- [ ] **AC12** Given the single-executor invariant grep `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "`, when run after this change, then it still resolves to exactly the 5 sanctioned surfaces.
- [ ] **AC13** Given the five-term sweep `git grep -nE 'read-bridge|build-bridge|graphify-out|bridge\.json|GRAPH_PRESENT'` (committed files, `CHANGELOG.md` and `.supervisor/` excluded), when the PR is complete, then every remaining hit is one of: a spike/SPIKES doc (banner-marked or historical), the frozen README changelog quote, the committed harness's own files/README, the banner-marked brain-baseline-corpus files (AC9c), the annotated POINTER_AUDIT row (AC9b), `loomwright/scripts/validate-entry.sh:1038`'s frozen measured-incident comment (it records that a `graphify-out/graph.json` citation was **refused as a dead reference** — a claim that stays true, indeed truer, after retirement), or `.gitignore`'s inert `graphify-out/` line (settled decision (e)) — and the PR body **enumerates each surviving hit with its reason**.

## Outcomes Rubric
- Tier removed at every seam, ladder fallback behaviour unchanged
- Script disposition explicit, CI consistent
- D9 split recorded with reasoning, old form swept including variants
- Evidence docs preserved and banner-marked, not deleted
- Reversal condition stated (incremental refresh + harness), not left implicit, and the harness it
  cites is reachable from a fresh clone — or the condition is restated without citing gitignored files

## Settled owner decisions (the worker MUST NOT re-litigate these)

- **(a) `twin-graph.sh` + `test-twin-graph.sh` are RETAINED, untouched.** Contract-store helper, not graphify tier (measured correction 1). The requirement's list is overruled by what the file actually reads.
- **(b) `setup-twin.sh`, `test-setup-twin.sh`, and the `/setup` twin module are RETIRED WITH the tier.** Their sole purpose is bootstrapping the retired tier; leaving them ships a bootstrap for nothing and makes AC1 unsatisfiable. This is a user-facing feature removal and is stated prominently in the CHANGELOG entry, not buried.
- **(c) The harness is COMMITTED (requirement's preferred arm) as a frozen 3-file closure under `docs/SPIKES/code-graph-harness/`** — NOT under `loomwright/scripts/` (it is not plugin runtime: no token budget applies, the ci.yml `test-*.sh` glob must not pick it up, and it must not imply operational support). Copies are verbatim; the README carries provenance and deps.
- **(d) The distilled-store `flag-only` surfaces are NOT edited** (measured correction 4) — under the new D9 they are the "Distilled → No" row and remain true. The trace is recorded in the D9 amendment.
- **(e) `.gitignore`'s `graphify-out/` line REMAINS.** The external `graphify` CLI can still be run by a user; the line is inert, cheap protection against accidentally committing its output. Stated in AC13's enumeration.
- **(f) Version 15.35.0 → 15.36.0; counts unchanged 14/21/41/24.**
- **(g) Skill frontmatter version bumps and their `SKILLS_INDEX.md` rows land in Subtask 3, together.** Subtask 1 rewrites SKILL.md bodies but leaves frontmatter `version:` untouched, so `check-skills-index-sync.sh` (a hard CI gate) stays green after Subtask 1's commit; Subtask 3 bumps the changed skills' versions and the matching index rows in one commit. This keeps `SKILLS_INDEX.md` owned by exactly one lane.
- **(h) The external-brain path (`LOOMWRIGHT_BRAIN_ROOT` detection + wiki query order) retires WITH the rung.** The measured fact that settles the tier — `brain_context` appears 0 times across all session logs — covers the whole rung, external path included; the wiki path has no separate consumer and no separate measurement. Any revival (graph or external brain) is governed by the same reversal condition (AC8). Named in the CHANGELOG entry, not silently dropped.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create/delete) | Status |
|---|-------|---------------------------|-----------------------------------|--------|
| 1 | Tier removal: scripts, five seams, setup module, comment re-anchoring | AC1, AC2, AC3, AC4 (plugin half), AC5 | 16 modify, 0 create, 6 delete | LAUNCHABLE |
| 2 | The record: D9 amendment, banners, committed harness, schema + register annotations | AC6, AC7, AC8, AC9, AC9b, AC9c | 7 modify, 4 create | LAUNCHABLE |
| 3 | Release surface: version, CHANGELOG, banner, README/agent-help sweep, skill version bumps | AC4 (release half), AC10, AC11, AC12, AC13 | 12 modify, 0 create | BLOCKED (by #1, #2) |

### Subtask contracts

```yaml
# Subtask 1 — tier removal (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/skills/brain-context/SKILL.md", name: "repo-map → nothing"}      # 0-hit today; the rewritten ladder line
  - {kind: "symbol", path: "loomwright/skills/brain-context/SKILL.md", name: "graphify tier retired"}    # the retirement note
  - {kind: "symbol", path: "loomwright/commands/setup.md", name: "twin module was retired"}              # the deliberate-omission line
requires: []
lanes:
  - "loomwright/scripts/build-bridge.sh"
  - "loomwright/scripts/build-bridge.py"
  - "loomwright/scripts/read-bridge.sh"
  - "loomwright/scripts/test-build-bridge.sh"
  - "loomwright/scripts/setup-twin.sh"
  - "loomwright/scripts/test-setup-twin.sh"
  - "loomwright/scripts/read-rules.sh"
  - "loomwright/scripts/read-orientation.sh"
  - "loomwright/scripts/build-repo-map.sh"
  - "loomwright/scripts/build-handoff.sh"
  - "loomwright/scripts/build-loop-evidence.sh"
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/test-build-handoff.sh"
  - "loomwright/scripts/test-set-otel-resource-attrs.sh"
  - "loomwright/skills/brain-context/SKILL.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/context-setup/SKILL.md"
  - "loomwright/skills/rules/SKILL.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/commands/setup.md"
external_requires: []

# Subtask 2 — the record (LAUNCHABLE; lanes disjoint from #1)
provides:
  - {kind: "file",   path: "loomwright/docs/SPIKES/code-graph-harness/validate.py"}
  - {kind: "file",   path: "loomwright/docs/SPIKES/code-graph-harness/validate_gen.py"}
  - {kind: "file",   path: "loomwright/docs/SPIKES/code-graph-harness/reposcan_multi.py"}
  - {kind: "file",   path: "loomwright/docs/SPIKES/code-graph-harness/README.md"}
  - {kind: "symbol", path: "loomwright/docs/SPIKES/FINAL_STATE_GOAL.md", name: "regenerability"}          # 0-hit today
  - {kind: "symbol", path: "loomwright/docs/SPIKES/CODE_GRAPH_OWNERSHIP.md", name: "TIER RETIRED"}       # 0-hit today
  - {kind: "symbol", path: "loomwright/docs/SPIKES/LOCAL_TWIN_PATH.md", name: "TIER RETIRED"}            # 0-hit today
requires: []
lanes:
  - "loomwright/docs/SPIKES/FINAL_STATE_GOAL.md"
  - "loomwright/docs/SPIKES/CODE_GRAPH_OWNERSHIP.md"
  - "loomwright/docs/SPIKES/LOCAL_TWIN_PATH.md"
  - "loomwright/docs/SPIKES/code-graph-harness/validate.py"
  - "loomwright/docs/SPIKES/code-graph-harness/validate_gen.py"
  - "loomwright/docs/SPIKES/code-graph-harness/reposcan_multi.py"
  - "loomwright/docs/SPIKES/code-graph-harness/README.md"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/docs/POINTER_AUDIT.md"
  - "loomwright/scripts/brain-baseline-corpus/q1-what-calls-read-lessons.md"
  - "loomwright/scripts/brain-baseline-corpus/q2-blast-radius-read-bridge.md"
external_requires:
  - "source files in .supervisor/scratch/code-graph-spike/ (verified present this session; gitignored, so the copy must happen from the main checkout — a worktree does NOT contain them)"

# Subtask 3 — release surface (BLOCKED by #1 and #2)
provides:
  - {kind: "symbol", path: "CHANGELOG.md", name: "15.36.0"}                                              # 0-hit today
  - {kind: "symbol", path: "CLAUDE.md",    name: "regenerability split"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/skills/brain-context/SKILL.md", name: "repo-map → nothing"}
  - {from: "2", kind: "file",   path: "loomwright/docs/SPIKES/code-graph-harness/README.md"}
lanes:
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "CLAUDE.md"
  - "README.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/skills/brain-context/SKILL.md"       # frontmatter version bump ONLY (decision (g)); body owned by Subtask 1 — sequential sharing, ordered pair 1→3
  - "loomwright/skills/self-heal-advisory/SKILL.md"  # frontmatter version bump ONLY (decision (g))
  - "loomwright/skills/context-setup/SKILL.md"       # frontmatter version bump ONLY (decision (g))
  - "loomwright/skills/rules/SKILL.md"               # frontmatter version bump ONLY (decision (g))
  - "loomwright/skills/setup/SKILL.md"               # frontmatter version bump ONLY (decision (g))
external_requires: []
```

> **Lane note.** The only mutually-unreachable pair is (1, 2) and their lanes are disjoint. The five SKILL.md paths appear in both Subtask 1 (body) and Subtask 3 (frontmatter version only) — a **declared sequential sharing** on the ordered pair 1→3, which the Lane Declaration Schema explicitly permits. Preservation discipline: after its frontmatter-only edit to `brain-context/SKILL.md`, Subtask 3 re-verifies Subtask 1's provides tokens (`repo-map → nothing`, `graphify tier retired`) still resolve — sequential sharing grants visibility, not preservation. `skills/setup/SKILL.md` sits in Subtask 1's lanes because that file's own rule requires the registry row and the `commands/setup.md` flow change in the same change.

> **Worktree hazard, stated up front (recorded lesson `gitignored-scratch-absent-in-worktrees`):** Subtask 2's source files live under gitignored `.supervisor/scratch/`, which does NOT exist in a fresh worktree. If workers run in worktrees, Subtask 2 must copy from the absolute main-checkout path `~/Documents/work/AI/ai-agent-manager/.supervisor/scratch/code-graph-spike/`. On the Single-Agent Path (no worktree) this is moot.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┐
            ├──→ Subtask 3
Subtask 2 ──┘
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | NO — mutually unreachable, lanes disjoint |
| Subtask 1 | Subtask 3 | none | YES (dependency) |
| Subtask 2 | Subtask 3 | none | YES (dependency) |

### Batch Plan
- **Batch 1:** Subtask 1, Subtask 2 (sequential with 1 worker)
- **Batch 2:** Subtask 3
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/brain-context/SKILL.md` (the file being rewritten — read first), `skills/quality-checklist/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md` |
| 3 | `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Deleting `twin-graph.sh` because the requirement lists it, breaking the live contract-store subsystem | HIGH | Measured correction 1 + settled decision (a) + AC2's byte-untouched assertion |
| A committed path still reading a deleted script (the sweep misses a consumer) | HIGH | AC13's five-term grep with per-hit enumeration in the PR body; AC5's enumerated comment sweep; the `verify-consumer-contract` lesson applies — read each hit, don't count them |
| The harness committed unrunnable (missing `reposcan_multi.py`) | HIGH | Measured correction 3 pins the 3-file closure; AC8 names all three files |
| Editing the distilled-store `flag-only` surfaces the split does NOT change, churning correct code | MEDIUM | Settled decision (d): traced-and-stated, not edited |
| Doc-currency / count drift (module count "9 modules", version strings, README enumerations) | MEDIUM | AC4's release-half enumerates the exact sites; AC10/AC11 run the gates; grep the OLD value repo-wide per CLAUDE.md discipline |
| `outputs_verified` self-satisfiable — most of this item's work is absence-shaped and a provide can only express a positive token | MEDIUM | Positive tokens chosen for the *replacement* content (ladder line, retirement notes, banners); the absence assertions live in AC13's enumerated grep, which the Supervisor re-runs on disk at Phase 4 — not taken from worker self-report |
| Scope exceeds single-subtask default (~30 files) — the Feasibility CAUTION, mirrored here | MEDIUM | `context-bound` split into 3 subtasks, 2 batches |
| Concurrent writers on this shared checkout (recurred in this run's history) | MEDIUM | Verified before ACQUIRE this tick (reflog idle since 11:05 pull, no open PRs); re-verify before FINALIZE; park rather than fight a live writer |
| Removing a shipped user-facing module (`/setup twin`) reads as silent feature loss | MEDIUM | Decision (b): CHANGELOG names the removal prominently; setup.md carries the deliberate-omission line |

## Configuration
- **Workers:** 1
- **Mode:** sequential (deliberate — Batch 1 holds two LAUNCHABLE subtasks serialized under 1 worker; the gitignored-scratch worktree hazard is the recorded reason for not fanning out)
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-17-retire-graphify-tier.md
```

---

## Outcome

- **Status:** completed
- **Session:** inline `/supervisor job:` on the main thread (driven by `/automate --resume`), 2026-08-17
- **Branch:** `feature/retire-graphify-tier` (base `main` @ `c7f084f`)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/149 (OPEN — never merged; safe-mode engine parks awaiting_merge)
- **Version:** 15.35.0 → 15.36.0
- **preflight_sync:** clear
- **Path:** Sequential (3 subtasks, 1 worker each, 2 batches) — no worktrees (ST2's gitignored-scratch source was the recorded reason)
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 2
- **heal_remaining_issues:** 0 BLOCKING/HIGH; 1 LOW carried as accept-as-is (build-repo-map.sh:124 prune entry, decision-(e)-consistent)
- **rubric_score:** 5/5
- **until_mergeable_dispatched:** false (suppressed by the /automate engine's config toggle — the engine owns ONE inline drain instead)

### Commits
| SHA | What |
|---|---|
| `d2e54c9` | 1 — tier removal: 6 scripts deleted, 5 seams unwired, /setup twin retired, comment re-anchoring (−2408 lines) |
| `29d701a` | 2 — D9 regenerability amendment, TIER RETIRED banners, byte-verbatim 3-file harness + README, register annotations |
| `4682275` | 3 — v15.36.0 release surface, README/agent-help sweep, 5 skill version bumps + SKILLS_INDEX in lockstep |
| `692692f` | heal 1 — the prose references the five-term grep could not see (supervisor.md enumeration, rules.md mirror, half-swept rules SKILL, + class sweep) |

### Verification (re-verified by the Supervisor on disk, not taken from worker self-report)
- 60/60 local CI suites green; doc-currency / skills-index-sync / command-sync / contract-parity / token-budget / validate-version / citation-drift (26/26) all green
- Counts unchanged 14/21/41/24; no `15.35.0` outside CHANGELOG.md; single-executor grep still exactly 5 surfaces
- twin-graph.sh + test-twin-graph.sh byte-untouched (`git diff main...HEAD` empty on both) — the measured correction held
- Harness cmp-verified byte-identical to its scratch source; closure self-contained (only external dep tree-sitter, stated)
- Five-term sweep + prose-term sweep both fully enumerated; every survivor an adjudicated intentional mention

### Notes for the record
- Worker 1 hit its turn limit once and was resumed via SendMessage per the standing lesson (respawn would have redone the seam analysis).
- Three test headers outside the brief's enumeration pointed at deleted test-setup-twin.sh — re-anchored, reported out-of-lane (record-only on the sequential path), not silently absorbed.
- The heal review's one fix-class was exactly the brief's own HIGH risk ("sweep misses a consumer") in its prose form: mechanical grep terms cannot match prose references. The prose-term sweep is the reusable prevention.
