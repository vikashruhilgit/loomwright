# Supervisor Job: `/obsidian` — Full Linked Vault projection (decoupled, read-only)

> Plan Review: revised v2 after attempt-1 FAIL (3 findings, all valid).
> v2 changes: (HIGH) the `agent-help.md` `Slash commands (14)→(15)` bump is now owned by **ST3** (which already edits that file), so every count surface has an owner and `check-doc-currency.sh` passes; (MED) ST4 explicitly enumerates every remaining count surface incl. the dated `README.md:19` line; (LOW) sparse-tolerance generalized to ANY absent source (twin dir, LESSONS.md, logs, memory), not just the twin dir.

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager (plugin's own repo)
- **CLAUDE.md:** ✓ Found, fresh (v14.10.0)
- **Git:** branch `main`; only `.claude/` untracked (local settings/agent-memory — unrelated). `git pull` if behind origin before running.
- **GitHub CLI:** ✓ Authenticated · **Worktrees:** none orphaned
- **Blockers:** 0 | **Warnings:** 1 (on `main` — Supervisor branches)
- **legacy_brief:** false

## Task
**Goal:** Add a **`/obsidian`** command + **`scripts/build-vault.sh`** that projects this project's accumulated knowledge into an Obsidian-ready **Full Linked Vault** in a **configurable common destination dir**, so multiple projects share one vault. It is a **read-only downstream projection**: reads `.supervisor/twin/contracts/`, `.supervisor/logs/*.jsonl`, `.supervisor/memory/{PROJECT_MEMORY,LESSONS}.md`; writes **only** to the external vault; **modifies no agent/command/script and is never read back by any agent.** Obsidian is a projection, never a dependency.

## Acceptance Criteria
- [ ] **Decoupling (hard):** `build-vault.sh` + `obsidian.md` only **read** source artifacts and **write** to the vault dir. They modify **zero** source-of-truth files (no agent, `/insights`, `build-insights.sh`, `supervisor.md`); no agent ever reads the vault. The engine behaves identically with or without the vault.
- [ ] **Destination + opt-in:** dest from `AI_AGENT_MANAGER_OBSIDIAN_VAULT` env (or a `.supervisor/`-style config file). **When unset → no-op + notice; never writes outside the repo unopted.** Per-project subfolder `$VAULT/<project-slug>/` (slug = repo dir name, env-overridable); a run **never touches another project's folder**.
- [ ] **Idempotent / stateless ledger:** each run fully re-derives this project's subfolder; a note is written **only when its content hash differs** from the on-disk file (reuse the `write-system-contract.sh` content-hash dedup). The vault folder **is** the ledger — no separate manifest. Re-run with no source change → zero writes.
- [ ] **Sparse-tolerant (load-bearing, generalized):** with **any** source absent or empty — the `.supervisor/twin/` dir, `.supervisor/memory/LESSONS.md`, the logs, or `PROJECT_MEMORY.md` (verified today: `.supervisor/twin/` and `LESSONS.md` do NOT exist) — it emits a valid vault (the missing section omitted or near-empty) and **never errors / always exits 0**.
- [ ] **Full linked layout:** index/MOC note; Twin contracts as linked notes with `[[dependency]]` edges (graph view = blast radius); per-run notes from logs; **when present**, LESSONS + PROJECT_MEMORY notes; cross-links runs↔contracts↔lessons.
- [ ] **Anti-rebloat + currency:** adds exactly **one command (14→15)**; **no** new agent/hook/skill; new scripts self-tested; **`scripts/check-doc-currency.sh` passes with the new count** (every gate-scanned count surface bumped — owners assigned in ST3/ST4 below).

## Subtask Structure

### ST1 — `build-vault.sh` generator  [blocks all]
**Files:** `ai-agent-manager-plugin/scripts/build-vault.sh` (create).
**Work:** config/dest resolution (env `AI_AGENT_MANAGER_OBSIDIAN_VAULT` + optional config file + no-op-when-unset), project-slug subfolder, read sources (twin contracts *possibly absent*, logs, memory/lessons *possibly absent*), emit the full linked vault, content-hash idempotent writes, generalized sparse-tolerance (any source absent → valid vault, exit 0), write-only-to-dest, never touch other projects' folders, read-only on sources.
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/scripts/build-vault.sh, name: build_vault_script}
  - {kind: contract, path: ai-agent-manager-plugin/scripts/build-vault.sh, name: vault_iface}
requires: []
```

### ST2 — `test-build-vault.sh` self-test  [dep ST1]
**Files:** `ai-agent-manager-plugin/scripts/test-build-vault.sh` (create).
**Work:** mirror `test-system-contract.sh`. Assert: env-unset → no-op; **any source absent (twin dir absent AND LESSONS.md absent) → valid vault, exit 0**; idempotent (no rewrite on unchanged); per-project isolation (never writes a sibling project's folder); writes only under dest.
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/scripts/test-build-vault.sh, name: build_vault_selftest}
requires:
  - {kind: file, name: build_vault_script, from: ST1}
  - {kind: contract, name: vault_iface, from: ST1}
```

### ST3 — `/obsidian` command + agent-help (incl. its count bump)  [dep ST1]
**Files:** `ai-agent-manager-plugin/commands/obsidian.md` (create), `ai-agent-manager-plugin/commands/agent-help.md` (modify).
**Work:** `obsidian.md` wraps `build-vault.sh`, documents env/config + the no-op-when-unset behavior, carries the read-only/propose-only banner and "no data leaves your machine" note (like `/insights`). In `agent-help.md`: **add the `/obsidian` entry AND bump `Slash commands (14)`→`(15)` at line ~970** (this file is gate-scanned by `check-doc-currency.sh`; ST3 owns it so no other subtask touches it).
```yaml
provides:
  - {kind: file, path: ai-agent-manager-plugin/commands/obsidian.md, name: obsidian_command}
  - {kind: capability, path: ai-agent-manager-plugin/commands/agent-help.md, name: agent_help_entry_and_count}
requires:
  - {kind: file, name: build_vault_script, from: ST1}
  - {kind: contract, name: vault_iface, from: ST1}
```

### ST4 — docs, version, currency (all OTHER count surfaces)  [dep ST1-3]
**Files:** `ai-agent-manager-plugin/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.claude-plugin/README.md`, `CLAUDE.md`, `README.md`, `CHANGELOG.md` (modify). **(Does NOT touch `agent-help.md` — ST3 owns that.)**
**Work:** version bump + CHANGELOG entry + README/CLAUDE banner, and bump the command count `14→15` on **every remaining gate-scanned surface**, explicitly:
- `plugin.json:~4` and `marketplace.json:~10` — `14 slash commands` in the description
- `.claude-plugin/README.md:~9` (`14 slash commands`) and `:~390` (`Slash commands (14)`)
- `CLAUDE.md:~49` — `14 slash commands`
- `README.md:~19` — `14 slash commands` **(bump even though it sits in a dated `NEW in v14.0.0` line — the count pattern is NOT version-anchored, so the gate still flags it)**
Then confirm **`scripts/check-doc-currency.sh` passes** (run from repo root; it lives at the wrapper-root `scripts/`, not the plugin's).
```yaml
provides:
  - {kind: capability, path: CHANGELOG.md, name: release_notes}
requires:
  - {kind: file, name: obsidian_command, from: ST3}
  - {kind: capability, name: agent_help_entry_and_count, from: ST3}
  - {kind: file, name: build_vault_script, from: ST1}
```

## Parallelism Analysis
- **Batch 1:** ST1 · **Batch 2:** ST2 ∥ ST3 (disjoint: `test-build-vault.sh` vs `obsidian.md`+`agent-help.md`) · **Batch 3:** ST4 (does not touch `agent-help.md`, so no overlap with ST3)
- **Recommended workers:** 2

## Skill References
- **ST1:** `skills/state-management/SKILL.md`, `skills/quality-checklist/SKILL.md`
- **ST2:** `skills/quality-checklist/SKILL.md`
- **ST3:** `skills/quality-checklist/SKILL.md`
- **ST4:** `skills/claude-md-validation/SKILL.md`, `skills/quality-checklist/SKILL.md`

## Risk Assessment
| Risk | Severity | Source | Mitigation |
|---|---|---|---|
| `.supervisor/twin/` AND `LESSONS.md` absent today → empty sections on first run | MED | Feasibility 2.5 (verified absent) | Generalized sparse-tolerance hard AC; ST2 asserts absent-twin + absent-LESSONS → valid vault, exit 0 |
| Writes **outside the repo** (novel for this plugin) | MED | Feasibility 2.5 | Opt-in only (no-op when unset); validate dest; write only under `$VAULT/<slug>/`; never modify/delete outside own subfolder |
| Decoupling violation (worker "wires" obsidian into the engine) | MED | design | Hard AC: read-only on sources, modifies no agent/insights/supervisor; Code Reviewer consistency-audit catches |
| Doc-currency ownership gap (the attempt-1 FAIL) | MED | Plan Review v1 | ST3 owns `agent-help.md` count; ST4 owns all other count surfaces incl. the dated `README.md:19`; ST4 runs the gate last |
| Idempotency bug → spurious rewrites/drift | LOW | design | Per-note content-hash compare (reuse `write-system-contract.sh`); ST2 asserts no-rewrite-on-unchanged |
| Anti-rebloat | LOW | CLAUDE.md | +1 command intentional (only count change); no new agent/hook/skill |

## Configuration
- **Mode:** parallel (2 workers) · **Cost:** default · **Branch:** `feature/obsidian-vault`
- **References:** `commands/insights.md` (Obsidian/Dataview + read-only banner precedent), `scripts/{build-insights,write-system-contract,read-system-contract}.sh` (patterns to mirror), `scripts/test-system-contract.sh` (self-test pattern), `.supervisor/telemetry-consent.json` (config-file precedent).

## Handoff
```
# In a NEW session running v14.10.0 (reinstall the plugin first, per CLAUDE.md "test locally"):
#   /plugin uninstall …  &&  /plugin install …   → then a fresh session
/supervisor job: .supervisor/jobs/pending/2026-06-05-obsidian-vault.md --base-branch main
# NOTE: this run is ALSO the first live System Twin exercise — Phase 4.5 writes the first contracts as a byproduct.
```

## Outcome
- **Status:** completed
- **Completed:** 2026-06-04T20:38:29Z
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/27
- **Branch:** feature/obsidian-vault
- **Files changed:** 10
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1 (review NEEDS_HUMAN: MEDIUM slug-containment escape → fixed → re-review PASS)
- **Heal fixable issues fixed:** 1
- **Heal remaining issues:** 0
- **Rubric:** null (brief has no `## Outcomes Rubric` section)
- **Contract conformance:** skipped (twin store was absent at review time)
- **Benchmark:** pass (selftest_pass_count=4)
- **System Twin (first live write):** 2 contracts written via write-system-contract.sh (build-vault.sh, obsidian.md) — advisory, gitignored
- **Summary:** Added /obsidian + scripts/build-vault.sh (read-only Full Linked Obsidian Vault projection) + test-build-vault.sh (22 assertions) + /obsidian command doc + v14.11.0 docs/currency (14→15 commands). 4/4 subtasks merged; self-heal fixed 1 containment issue in 1 iteration; final PASS. All 3 doc gates green.
