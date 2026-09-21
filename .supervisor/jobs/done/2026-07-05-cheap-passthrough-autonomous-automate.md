# Supervisor Job: Wire `--cheap` cost-profile passthrough into `/autonomous` and `/automate`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean; current branch `feature/rules-enforcement-3b-ii` (open PR #88, unrelated rules-enforcement work)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (see Configuration — base-branch note)
- **Plugin version:** 15.1.0 → **15.2.0** (this change)

## Task
**Goal:** Make `--cheap` a real, forwarded flag on `/autonomous` and `/automate` so the Sonnet cost profile propagates through the full nesting chain `/automate → /autonomous → /supervisor`. Today `/supervisor --cheap` is fully wired, but `/autonomous` documents `--cheap` as an inert no-op (unknown flags not forwarded) and `/automate` has no cost-profile handling at all. This is a **flag-plumbing + doc-currency** change only — the Supervisor cost-profile engine (INIT parse → `cost_profile=cheap` → `model:"sonnet"` on every Task spawn → state persistence/resume-hydration) is reused **unchanged**.

### Explicit non-goals (do NOT do)
- **No new phases or steps** in Supervisor, autonomous-loop, or automate-loop. The forward set is *extended*, not restructured.
- **No changes to the Supervisor cost-profile mechanism** (`agents/supervisor.md` cost_profile logic, Context-Keeper config, spawn overrides) — it already works; only *reach* it from the two outer loops.
- **No agent/command/skill/hook count change** (stays 14 / 21 / 57 / 21). **No `schema_version` bump.**
- **No changes to Launch Pad** — `--cheap` is not a Launch Pad concern (Launch Pad spawns only Plan Reviewer).

## Acceptance Criteria
- [ ] Given `/autonomous "<req>" --cheap`, when the loop reaches EXECUTE step 1 and inlines `/supervisor job: ...`, then `--cheap` is appended to that invocation **in every iteration** (single- and multi-iteration; stacked and non-stacked), alongside the existing `--base-branch` / `--non-interactive` forwards.
- [ ] Given `/automate ... --cheap`, when the engine's RUN step (§6 step 2) invokes `/autonomous --single-iteration --requirement <path>`, then `--cheap` is passed through to that inner `/autonomous` call (which in turn forwards it to `/supervisor` per the criterion above).
- [ ] Given no `--cheap` flag, when either loop runs, then behavior is byte-for-byte unchanged (default `inherit` / no cost_profile in the forwarded command) — this flag is strictly additive and opt-in.
- [ ] Given the change lands, when a reader consults `commands/autonomous.md`, then the two "**not forwarded** / **no effect**" `--cheap` notes (current lines ~46 and ~61) are **replaced** with accurate "forwarded to the inlined `/supervisor`" wording, and a `--cheap` row is present in the Parameters table. The `--skip-preflight-sync` note (line ~63) must be updated so it no longer claims parity with `--cheap` ("Like `--cheap`, ... not forwarded") — `--skip-preflight-sync` remains unforwarded, so reword to stand on its own.
- [ ] Given the change lands, when a reader consults the CLAUDE.md "Common Pitfalls" section, then the `### /autonomous --cheap is unsupported in v1` entry (lines ~285–286) is **rewritten** to describe the now-supported behavior (or removed and replaced with a one-line "supported since v15.2.0" note).
- [ ] Given the change lands, when `/automate`'s Parameters table and usage examples are read, then a `--cheap` passthrough row + usage-example line exist, mirroring the existing `--notify` / `--non-interactive-fallback` passthrough entries.
- [ ] Given the change lands, when `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` run, then both PASS with version 15.2.0 and unchanged counts (14/21/57/21).
- [ ] Given the forward chain is documented, when the autonomous-loop and automate-loop skill "passthrough / auto-forwarded flags" enumerations are read, then `--cheap` appears in both, and each cross-links `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles" for the Haiku-session caveat (do not restate the caveat — defer to the single source).

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Autonomous `--cheap` forwarding (INIT parse + EXECUTE step 1 forward set + command docs) | 2 modify | LAUNCHABLE |
| 2 | Automate `--cheap` passthrough (§6 RUN step + §11 passthrough + command docs) | 2 modify | BLOCKED (by #1) |
| 3 | Version bump 15.2.0 + doc currency + CLAUDE.md pitfall rewrite + CHANGELOG | 4-6 modify | BLOCKED (by #1, #2) |

### Subtask 1 — Autonomous `--cheap` forwarding
```yaml
provides:
  - {kind: symbol, path: "loomwright/skills/autonomous-loop/SKILL.md", name: "--cheap forward in EXECUTE step 1"}
  - {kind: symbol, path: "loomwright/commands/autonomous.md", name: "--cheap Parameters row"}
requires: []   # foundation of the forward chain — no intra-brief dependency
```
- **Files (verified to exist):**
  - `loomwright/skills/autonomous-loop/SKILL.md` — (a) INIT: parse/recognize `--cheap` and carry it as run state; (b) EXECUTE step 1 (~lines 265–290, the `/supervisor job: ... --base-branch ...` invocation): append `--cheap` to the inlined `/supervisor` command when the flag was passed at INIT. (c) **CREATE the "Auto-forwarded flags" subsection in EXECUTE step 1** — it is currently a DANGLING reference (cited at SKILL.md ~94 and ~714 and autonomous.md ~57/~63 but never defined; only scattered `--base-branch` / `--non-interactive` bullets exist). The new named subsection enumerates all three with their conditions: `--base-branch` (stacked multi-iter, iter > 1), `--non-interactive` (when `--non-interactive-fallback` at INIT), `--cheap` (when passed at INIT). This also corrects the pre-existing inaccuracy that the loop forwards "ONLY `--non-interactive`" (it already conditionally forwards `--base-branch`). (d) **Line ~715 flag-forwarding note** (inside the Phase 1.5 CI fail-closed bullet): currently reads "forwards ONLY `--non-interactive` ... does not forward `--skip-preflight-sync` (same as `--cheap` — unknown flags are not passed through)" — rewrite so `--cheap` is listed as FORWARDED and is no longer grouped with `--skip-preflight-sync`. (e) **Cross-References footer** (~line 805, the `commands/supervisor.md` row: "v14 `--base-branch` + `--non-interactive` flags surface here") — add `--cheap`.
  - `loomwright/commands/autonomous.md` — add `--cheap` Parameters row; add a `--cheap` usage-example line to the Usage block (parity with the automate AC); **rewrite** the two notes at ~line 46 (Cost-profile note) and ~line 61 (`--cheap` interaction note) to state it IS now forwarded; **reword** the ~line 63 `--skip-preflight-sync` note so it no longer asserts parity with `--cheap`.
- **Contract:** forwarding is unconditional-when-flag-present across single/multi-iteration and stacked/non-stacked. Do not gate `--cheap` on `--non-interactive-fallback` (that gate governs only the `--non-interactive` forward). Cross-link the Haiku caveat to `docs/ARCHITECTURE_CONTRACTS.md` §"Cost Profiles"; do not restate it.
- **Skills:** `skills/autonomous-loop/SKILL.md` is the authority being edited; consult `agents/supervisor.md` §"--cheap"/`cost_profile` only to confirm the receiving contract (read-only).

### Subtask 2 — Automate `--cheap` passthrough
```yaml
provides:
  - {kind: symbol, path: "loomwright/skills/automate-loop/SKILL.md", name: "--cheap passthrough in §6 RUN step"}
  - {kind: symbol, path: "loomwright/commands/automate.md", name: "--cheap passthrough Parameters row"}
requires:
  # the inner /autonomous must actually forward --cheap for automate's passthrough to be end-to-end functional
  - {from: "1", kind: symbol, path: "loomwright/skills/autonomous-loop/SKILL.md", name: "--cheap forward in EXECUTE step 1"}
```
- **Files (verified to exist):**
  - `loomwright/skills/automate-loop/SKILL.md` — §6 step 2 RUN invocation (`/autonomous --single-iteration --requirement <path>`): append `--cheap` when passed to `/automate`. Add `--cheap` to the §11 passthrough enumeration and ALL "passthrough" mention sites: ~207 (§6 termination prose), ~328 (passthrough bullet), **~346–347 (§12 invocation-surface flag examples — add a `/automate ... --cheap` line alongside the `--notify` / `--non-interactive-fallback` examples)**, ~405 (Quality Gates passthrough list). Follow the existing `--notify` passthrough as the exact template.
  - `loomwright/commands/automate.md` — add `--cheap` Parameters-table passthrough row (mirror the `--notify` row at ~line 55) + a usage-example line near the ~line 36–37 passthrough examples. The Parameters row must state the resume semantics: `--cheap` is passthrough-only and NOT persisted in the run file's `## Run Config` (same as `--notify` / `--non-interactive-fallback`) — re-pass it on each `/automate --resume` or `/loop` tick.
- **Contract:** pure passthrough — the engine does NOT interpret `--cheap` itself, only forwards it to the inner `/autonomous` on the RUN step. NOT stored in run-file `## Run Config` (matches the existing flag-persistence convention — do not extend Run Config). No interaction with the `.auto_review` suppress contract, the owned drain, or the trusted-merge gate.

### Subtask 3 — Version bump + doc currency + pitfall rewrite
```yaml
provides:
  - {kind: symbol, path: "loomwright/.claude-plugin/plugin.json", name: "version 15.2.0"}
  - {kind: symbol, path: ".claude-plugin/marketplace.json", name: "version 15.2.0"}
requires:
  # docs describe the landed behavior from ST1 + ST2
  - {from: "1", kind: symbol, path: "loomwright/commands/autonomous.md", name: "--cheap Parameters row"}
  - {from: "2", kind: symbol, path: "loomwright/commands/automate.md", name: "--cheap passthrough Parameters row"}
```
- **Files (verified to exist):**
  - `loomwright/.claude-plugin/plugin.json` — `version` 15.1.0 → 15.2.0; update the `vX.Y.Z` string + keep counts in the `description` **in place** (anti-rebloat: do NOT append a new version clause — replace the version token; counts 14/21/57/21 unchanged).
  - `.claude-plugin/marketplace.json` — **two edits, both required:** (a) bump `.plugins[0].version` (line 11) `15.1.0` → `15.2.0` — this is **gate-critical**: `scripts/validate-version.sh` (lines 27–35) FAILS the build on any parity mismatch between marketplace `.plugins[0].version` and `plugin.json .version`; and (b) update the `Loomwright v15.1.0` → `v15.2.0` headline token in the `description` (scanned by `check-doc-currency.sh`). Do NOT bump only the description token and leave `.plugins[0].version` stale.
  - `CLAUDE.md` — (a) add/refresh the top banner for v15.2.0 (short, additive; keep only two most-recent release notes per the CLAUDE.md convention — the v15.0.0 banner may roll off to CHANGELOG); (b) **rewrite** the `### /autonomous --cheap is unsupported in v1` pitfall (lines ~285–286) to reflect the now-supported forwarding.
  - `CHANGELOG.md` — prepend a v15.2.0 entry.
  - `loomwright/commands/agent-help.md` (~line 936) — optional: add one line noting `/autonomous` and `/automate` now forward `--cheap`.
  - `README.md` — only if it currently asserts `--cheap` is supervisor-only (grep first; edit only if a stale claim exists).
- **Contract:** run `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` and confirm PASS. Do NOT "fix" illustrative/frozen example version tokens (per CLAUDE.md §"Adding or Modifying Agents" — sample `plugin_version` placeholders are deliberately version-agnostic). Grep the OLD version `15.1.0` repo-wide for current-claim occurrences that the gate does not scan (phase/budget enumerations excepted per CLAUDE.md guidance).

## Parallelism Analysis
- **Batch 1:** Subtask 1 (the forward-chain foundation)
- **Batch 2:** Subtask 2 (after #1 — semantic dependency on the inner forward existing)
- **Batch 3:** Subtask 3 (after #1, #2 — docs describe the landed behavior; also owns the single version bump for coherence)
- **Recommended workers:** 1 (sequential). Rationale: no file overlap between subtasks, but a tight semantic forward-chain (automate → autonomous → supervisor) plus a single shared version/doc-currency pass makes one coherent sequential worker safer and cheaper than parallel worktrees for a ~6-file additive change.

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Doc-currency gate false-positive on the version bump (unscanned surfaces) | MEDIUM | Subtask 3 greps OLD `15.1.0` repo-wide; run both CI gates locally before PR |
| "no effect"/"unsupported" wording left stale in one of the 3+ surfaces (autonomous.md ×2, CLAUDE.md pitfall, skill enumerations) | MEDIUM | Consistency-audit sweep: `grep -rn "cheap" loomwright/ CLAUDE.md` and confirm every current-claim reads "forwarded", not "not forwarded" (Code Reviewer auto-expands to consistency audit since diff touches commands/ + skills/ + metadata) |
| `--skip-preflight-sync` note breaks (it references `--cheap` parity) | LOW | Subtask 1 explicitly rewords line ~63 to stand alone |
| Forwarding accidentally gated on `--non-interactive-fallback` (copy-paste from the `--non-interactive` forward) | MEDIUM | AC explicitly requires unconditional-when-present forwarding; reviewer to state-trace the EXECUTE step 1 branch |
| Prompt-is-program regression: `--cheap` appended twice or in wrong iteration | LOW | State-trace the EXECUTE step 1 command assembly across a 2-iteration stacked run |

## Configuration
- **Base Branch:** `main` (default). ⚠️ **Warning:** this session is currently on `feature/rules-enforcement-3b-ii` (open PR #88). Start Supervisor from a clean `main`-based branch; PR #88 is unrelated (rules enforcement) so there is no overlap, but do NOT stack this on #88.
- **Change type:** additive, behavioral (new supported flag path) → minor version bump 15.1.0 → 15.2.0.
- **Counts:** unchanged 14 agents / 21 commands / 57 skills / 21 hooks. No `schema_version` bump.
- **Testing:** primarily static — `scripts/check-doc-currency.sh`, `scripts/validate-version.sh`, and a consistency grep. Optional (nice-to-have, not required): a lightweight static self-test in the spirit of `scripts/test-rules-seams.sh` asserting that both loop skills reference `--cheap` in their forward/passthrough sets — defer if it adds scope.

## Outcomes Rubric
- [ ] `skills/autonomous-loop/SKILL.md` EXECUTE step 1 appends `--cheap` to the inlined `/supervisor job:` command when the flag was passed at INIT, and `--cheap` appears in its "Auto-forwarded flags" enumeration.
- [ ] `skills/automate-loop/SKILL.md` §6 RUN step forwards `--cheap` to the inner `/autonomous --single-iteration` call, and `--cheap` is listed in the §11 passthrough set.
- [ ] `commands/autonomous.md` has a `--cheap` Parameters row and NO surviving "not forwarded"/"no effect"/"has no effect" claim about `--cheap`; the `--skip-preflight-sync` note no longer asserts `--cheap` parity.
- [ ] NO surface anywhere groups `--cheap` with unforwarded flags: `grep -rn "cheap" loomwright/ CLAUDE.md README.md` shows every current-claim mention reading "forwarded"; specifically `skills/autonomous-loop/SKILL.md` ~715 is rewritten and the EXECUTE step 1 "Auto-forwarded flags" subsection EXISTS (the previously-dangling cross-refs at SKILL.md ~94/~714 and autonomous.md ~57/~63 now resolve).
- [ ] `commands/automate.md` has a `--cheap` passthrough Parameters row and a usage-example line.
- [ ] CLAUDE.md's `### /autonomous --cheap is unsupported in v1` pitfall is rewritten to reflect supported forwarding (no surviving "unsupported in v1" claim for `--cheap`).
- [ ] `plugin.json` version is `15.2.0`; `scripts/validate-version.sh` and `scripts/check-doc-currency.sh` both PASS; counts remain 14/21/57/21.
- [ ] No changes to `agents/supervisor.md` cost-profile logic, Launch Pad, or any phase/step definition; `git diff --stat` touches only the two loop skills, the two command docs, and version/doc-currency files.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-05-cheap-passthrough-autonomous-automate.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/89 (base main, OPEN)
- **Branch:** feature/cheap-passthrough-loops
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0 (review PASS on first pass; 2 advisory MEDIUM drift items fixed in follow-up commit 7da2a3a)
- **heal_remaining_issues:** 0
- **rubric_score:** 8/8
- **Gates:** validate-version.sh PASS, check-doc-currency.sh PASS (15.2.0, counts 14/21/57/21)
- **Until-mergeable dispatched:** true
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20260706T022020Z-734ddbf4702642e1b0ff2370349313583134a1af.log
