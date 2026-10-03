# Supervisor Job: Fable-parity — Agent SDK spike (Phase 3 loop port) + multi-voter heal + baseline-eval scaffold (v15.8.0)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — v15.6.0 banner; plugin.json already at 15.7.0 after PR #98)
- **Git:** clean, branch: main @ ddb73f2
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Worktrees:** main only (no orphans)
- **Blockers:** 0 | **Warnings:** 1 (Part A runner requires Node runtime at *use* time — spike is quarantined, so not a repo blocker)
- **Source requirement:** .supervisor/requirements/review-remediation/09-fable-parity-sdk-spike.md

## Task
**Goal:** Close the prompt-vs-code orchestration gap in the smallest falsifiable way: (A) a quarantined Agent SDK spike porting ONLY Execute Manager's Phase 3 poll loop to TypeScript with schema-forced worker/reviewer results, behind an opt-in fail-closed `--sdk-runner` Supervisor seam; (B) an opt-in `--multi-voter-heal` Phase 4.5 verification upgrade (independent code-reviewer + red-team-reviewer votes, second-opinion refute check before fixing); (C) per-stage model/effort routing notes + `--cheap` table row; (D) a pre-registered FABLE_PARITY_EVAL.md scaffold (decision rule + empty 5×3 table — runs are post-merge, mirroring ADVISORY_LOOP_EVAL.md's OAuth-constraint precedent); plus roadmap P2-11 verdict update from DEFERRED to the spike outcome. Version v15.8.0.

**MVP scoping note (explicit deviation, carried as risk R1):** the requirement's "measured token/latency comparison", the 5×3 eval **runs**, and Part B's "≥1 real run showing a refuted finding NOT fixed" demonstration (which naturally belongs to the post-merge eval arm-3 runs) are deferred to post-merge execution of the pre-registered protocol — same pattern item 08 shipped (`ADVISORY_LOOP_EVAL.md`: "pre-registered — paired runs pending"). The spike doc's GO/NO-GO is therefore **provisional** (capability-parity-based, from the doc-verified SDK matrix + the dry-run port), with the live comparison as the confirm step recorded in the doc itself.

## Verified SDK capability matrix (input for Subtask 1 + spike doc — doc-verified 2026-07-07 via claude-code-guide, NOT memory)
| # | Capability | Status | Mechanism |
|---|---|---|---|
| 1 | Programmatic subagent spawn, concurrent | SUPPORTED | `agents` dict of AgentDefinition in ClaudeAgentOptions; parent gets final message; https://code.claude.com/docs/en/agent-sdk/subagents.md |
| 2 | Schema-forced structured output | SUPPORTED | `output_format: {type:"json_schema", schema}` per `query()` (top-level result; per-worker schemas ⇒ run one query() per worker/reviewer); retries + `error_max_structured_output_retries`; https://code.claude.com/docs/en/agent-sdk/structured-outputs.md |
| 3 | Session streaming + resume | SUPPORTED | `resume: sessionId`; async-generator streaming; subagent transcripts persist |
| 4 | Hook interop | PARTIAL | SDK `hooks` option (callbacks, PreToolUse/SubagentStop/etc.); settings hooks fire iff `settingSources` includes `"project"`; **plugin hooks.json firing for SDK-spawned workers = NEEDS VERIFICATION — record as spike finding, not assumed** |
| 5 | TS vs Python maturity | NEEDS VERIFICATION | Docs treat both equally; TS bundles the CC binary → **pick TypeScript, reason recorded** |
| 6 | Per-agent model + effort | SUPPORTED | AgentDefinition `model` (incl. `inherit`) + `effort` (`low..max`) |
| 7 | Worktree/sandbox isolation | PARTIAL | No native sandbox; SDK runs in cwd — external `git worktree` per worker (matches our existing design); per-query `cwd` |

## Acceptance Criteria
- [ ] `loomwright/docs/SPIKES/SDK_RUNNER_SPIKE.md` exists with: the 7-row capability matrix above (with doc URLs), a parity matrix (what ported cleanly / what the SDK cannot do / needs-verification incl. plugin-hooks.json firing), the TS-vs-Python choice + reason, token/latency comparison section (dry-run numbers now; live comparison marked pending with exact run instructions), and a **provisional GO/NO-GO** with the confirm condition stated.
- [ ] `loomwright/sdk-spike/` contains a TypeScript runner that, given a Supervisor-Ready Brief path, parses the subtask list, creates a git worktree per LAUNCHABLE subtask, runs one `query()` per worker with `output_format` json_schema derived from WORKER_RESULT v2 field shapes (schema_version preserved), polls deterministically in code, runs a reviewer `query()` per completed worker against CODE_REVIEW_RESULT v3 shapes, and emits an EXECUTE_RESULT-equivalent block — plus a `--dry-run` mode (no API calls; mocked agent responses) exercised by a self-test script that passes offline.
- [ ] `--sdk-runner` opt-in flag documented in `commands/supervisor.md` + `agents/supervisor.md` Phase 3 (+ `skills/supervisor-config/SKILL.md` flag table): default OFF; when passed, Phase 3 shells out to the spike runner instead of Task-spawning execute-manager; **fail CLOSED** (abort with clear error) if `node`/runner absent; zero change to the default path (byte-identical behavior with flag off).
- [ ] `--multi-voter-heal` (+ `.supervisor/config.json` `.multi_voter_heal`), default OFF, documented in `skills/self-heal-advisory/SKILL.md` Part 2 + `commands/supervisor.md` + `agents/supervisor.md` + `supervisor-config`: when ON, Phase 4.5 spawns code-reviewer AND red-team-reviewer as independent parallel reviewers on the integrated diff; a BLOCKING/HIGH `new` finding triggers a fix ONLY if the other lens fails to refute it; refuted findings logged not fixed; per-run `findings_raised`/`findings_refuted`/`findings_fixed` recorded in SUPERVISOR_RESULT `summary` (additive prose, no schema bump); interaction with standalone `--red-team/--no-red-team` advisory lens documented in ONE place (self-heal-advisory) and cross-referenced; heal_decision semantics/bounds/never-merge unchanged.
- [ ] Part C: `docs/ARCHITECTURE_CONTRACTS.md` §Cost Profiles gains a `phase45-multi-voter-verification` row (default inherit; `--cheap` override documented); recommended-model/effort comment added to code-reviewer + red-team-reviewer frontmatter as comments (no `model:` value changes — `inherit` stays).
- [ ] `loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md` exists, mirroring ADVISORY_LOOP_EVAL.md's shape: question, pre-committed decision rule verbatim from the requirement (SDK runner graduates to v16 only if arm 3 beats arm 2 on defects or rounds without >1.5× token cost; Loomwright must beat bare Claude Code or losing layers get cut), pre-registered metrics, protocol (5 requirements × 3 arms, scratch branches only, no PRs to main), and an EMPTY results table with run-pending status.
- [ ] `docs/IMPROVEMENTS_ROADMAP.md` item 11 verdict updated from DEFERRED to `SPIKED (v15.8.0) — provisional GO/NO-GO per SDK_RUNNER_SPIKE.md; graduation gated on FABLE_PARITY_EVAL.md` — sweep ALL THREE mentions: the line-8 header summary, the line-289 verdict block, AND the summary-table row near line 456.
- [ ] Version bump to 15.8.0 (plugin.json + marketplace.json description in-place edit, CHANGELOG entry, CLAUDE.md banner rotation — two most recent releases only); counts UNCHANGED 14 agents / 21 commands / 41 skills / 22 hooks (sdk-spike is quarantined, uncounted); `scripts/check-doc-currency.sh`, `check-skills-index-sync.sh`, `check-command-sync.sh`, `validate-version.sh` all green.

## File Impact Map (verified paths; confidence)
| File | Action | Conf | Subtask |
|---|---|---|---|
| loomwright/sdk-spike/package.json, tsconfig.json, src/runner.ts, src/schemas.ts, src/dry-run-fixtures/*, test/self-test.sh, README.md | create | MEDIUM (new dir; shapes derived from docs/RESULT_SCHEMAS.md) | 1 |
| loomwright/commands/supervisor.md | modify (2 flag rows: `--sdk-runner`, `--multi-voter-heal`) | HIGH | 2,3 |
| loomwright/agents/supervisor.md | modify (Phase 3 branch stanza; Phase 4.5 flag mention) | HIGH | 2,3 |
| loomwright/skills/supervisor-config/SKILL.md | modify (flag/defaults table) | HIGH | 2,3 |
| loomwright/skills/self-heal-advisory/SKILL.md | modify (Part 2 multi-voter protocol + red-team interaction note) | HIGH | 3 |
| loomwright/docs/ARCHITECTURE_CONTRACTS.md | modify (Cost Profiles row) | HIGH | 4 |
| loomwright/agents/code-reviewer.md, loomwright/agents/red-team-reviewer.md | modify (frontmatter comment only) | HIGH | 4 |
| loomwright/docs/SPIKES/SDK_RUNNER_SPIKE.md, loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md | create | HIGH | 5 |
| loomwright/docs/IMPROVEMENTS_ROADMAP.md | modify (item 11 verdict + header summary) | HIGH | 5 |
| loomwright/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, CHANGELOG.md, CLAUDE.md, README.md (if version headline) | modify | HIGH | 5 |
| loomwright/docs/RESULT_SCHEMAS.md | modify (SUPERVISOR_RESULT summary note: multi-voter counters are prose-additive, no bump) | HIGH | 3 |

## Subtask Structure
| # | Title | Est. files | Status |
|---|---|---|---|
| 1 | SDK spike runner + dry-run self-test (quarantined `loomwright/sdk-spike/`) | 7 create | LAUNCHABLE |
| 2 | `--sdk-runner` fail-closed Phase 3 seam (prompt-only) | 3 modify | BLOCKED (by #1) |
| 3 | `--multi-voter-heal` Phase 4.5 multi-voter protocol (prompt-only) | 5 modify | BLOCKED (by #2, file overlap on supervisor.md pair + supervisor-config) |
| 4 | Cost-profile row + frontmatter routing comments | 3 modify | BLOCKED (by #3, semantic dependency: names the multi-voter verification stage #3 defines) |
| 5 | Spike doc + eval scaffold + roadmap verdict + v15.8.0 release sweep | 2 create, ~6 modify | BLOCKED (by #4) |

### Subtask contracts
```yaml
subtask_1:
  provides:
    - {kind: file, path: loomwright/sdk-spike/src/runner.ts}
    - {kind: file, path: loomwright/sdk-spike/src/schemas.ts}
    - {kind: file, path: loomwright/sdk-spike/test/self-test.sh}
    - {kind: file, path: loomwright/sdk-spike/README.md, name: "runner CLI contract: node dist/runner.js --brief <path> [--dry-run]"}
  requires: []
subtask_2:
  provides:
    - {kind: file, path: loomwright/commands/supervisor.md, name: "--sdk-runner flag row"}
    - {kind: file, path: loomwright/agents/supervisor.md, name: "Phase 3 --sdk-runner branch stanza"}
    - {kind: file, path: loomwright/skills/supervisor-config/SKILL.md, name: "--sdk-runner flag-table row"}
  requires:
    - {from: 1, kind: file, path: loomwright/sdk-spike/README.md, name: "runner CLI contract"}
subtask_3:
  provides:
    - {kind: file, path: loomwright/skills/self-heal-advisory/SKILL.md, name: "Part 2 §Multi-voter verification (authority incl. --red-team interaction)"}
    - {kind: file, path: loomwright/commands/supervisor.md, name: "--multi-voter-heal flag row"}
    - {kind: file, path: loomwright/agents/supervisor.md, name: "Phase 4.5 multi-voter mention"}
    - {kind: file, path: loomwright/skills/supervisor-config/SKILL.md, name: "--multi-voter-heal / .multi_voter_heal row"}
    - {kind: file, path: loomwright/docs/RESULT_SCHEMAS.md, name: "SUPERVISOR_RESULT summary note (counters prose-additive)"}
  requires:
    - {from: 2, kind: file, path: loomwright/commands/supervisor.md, name: "--sdk-runner flag row"}  # same-file ordering
subtask_4:
  provides:
    - {kind: file, path: loomwright/docs/ARCHITECTURE_CONTRACTS.md, name: "Cost Profiles row: phase45-multi-voter-verification"}
    - {kind: file, path: loomwright/agents/code-reviewer.md, name: "frontmatter routing comment"}
    - {kind: file, path: loomwright/agents/red-team-reviewer.md, name: "frontmatter routing comment"}
  requires:
    - {from: 3, kind: file, path: loomwright/skills/self-heal-advisory/SKILL.md, name: "Part 2 §Multi-voter verification"}  # the row documents this stage
subtask_5:
  provides:
    - {kind: file, path: loomwright/docs/SPIKES/SDK_RUNNER_SPIKE.md}
    - {kind: file, path: loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md}
    - {kind: file, path: loomwright/docs/IMPROVEMENTS_ROADMAP.md, name: "item 11 verdict update"}
    - {kind: file, path: loomwright/.claude-plugin/plugin.json, name: "version 15.8.0"}
  requires:
    - {from: 1, kind: file, path: loomwright/sdk-spike/README.md, name: "parity findings input to spike doc"}
    - {from: 3, kind: file, path: loomwright/skills/self-heal-advisory/SKILL.md, name: "multi-voter authority section referenced by CHANGELOG"}
    - {from: 4, kind: file, path: loomwright/docs/ARCHITECTURE_CONTRACTS.md, name: "Cost Profiles row referenced by CHANGELOG"}
```

## Skill References
| Subtask | Skills |
|---|---|
| 1 | None applicable in-plugin (tech-stack skills moved to stackpack@atelier in v15.6.0 — install `/plugin install stackpack@atelier` for TS references if desired); derive schemas from `docs/RESULT_SCHEMAS.md`; `skills/unit-testing/SKILL.md` for the self-test shape |
| 2 | `skills/supervisor-config/SKILL.md` (flag table conventions), `skills/async-orchestration/SKILL.md` Part 2 (Phase 3/4 seam context) |
| 3 | `skills/self-heal-advisory/SKILL.md` (Part 2 is the section being extended), `skills/supervisor-config/SKILL.md` |
| 4 | `docs/ARCHITECTURE_CONTRACTS.md` §Cost Profiles (authority being extended) |
| 5 | `skills/quality-checklist/SKILL.md` (release sweep gates), `skills/commit/SKILL.md` |

## Parallelism Analysis
- Batch 1: Subtask 1 (solo — nothing else touches sdk-spike/)
- Batches 2–5: Subtasks 2 → 3 → 4 → 5 sequential (2/3/4 share commands/supervisor.md + agents/supervisor.md + supervisor-config; 5 needs all outcomes)
- Recommended workers: 1 (effectively sequential; fast-path per subtask acceptable)

## Configuration
- Base Branch: main
- Suggested branch: feature/fable-parity-sdk-spike
- Max workers: 1 | Heal iterations: 3 (default)

## Risk Assessment
| Risk | Sev | Source | Mitigation |
|---|---|---|---|
| R1: "measured token/latency comparison" + eval runs deferred to post-merge (provisional GO/NO-GO) | MED | MVP scoping (Phase 2.5 CAUTION) | Deviation stated verbatim in spike doc + brief; pre-registered protocol makes the confirm step mechanical; mirrors item-08 precedent |
| R2: plugin hooks.json firing for SDK-spawned workers unverified | MED | Feasibility (Phase 2.5) | Recorded as NEEDS VERIFICATION spike finding (requirement explicitly allows: "this is a spike finding, not a bug"); runner self-validates schemas regardless |
| R3: prompt-surface edits to supervisor.md pair risk mirror drift (agent↔command sync) | MED | past lesson (agent-command-mirror-drift) | Subtasks 2/3 edit BOTH files + supervisor-config in the same subtask; check-command-sync.sh in CI |
| R4: multi-voter flag semantics colliding with `--red-team` lens | MED | requirement | Single authority section in self-heal-advisory Part 2; command table cross-references it |
| R5: sdk-spike accidentally entering counted plugin surface | LOW | constraints | No plugin.json/SKILLS_INDEX/manifest references; doc-currency counts unchanged; spike README states quarantine |
| R6: SDK API drift between doc-verify and implementation | LOW | Feasibility | Every capability claim in spike doc cites the doc URL + 2026-07-07 verify date |

## Out of scope (from requirement)
Full v16 SDK rewrite; porting phases other than 3; forcing non-inherit models; result schema_version bumps; agent-teams integration; running the 5×3 eval or live token/latency arms in this PR.

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-07-07-fable-parity-sdk-spike.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/99
- **Branch:** feature/fable-parity-sdk-spike (17d6df3)
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0
- **heal_remaining_issues:** 0
- **rubric_score:** null (no Outcomes Rubric in brief)
- **Subtasks:** 5/5 completed (2 review-fix rounds: subtask 1 HIGH lifecycle, subtask 2 HIGHs FINALIZE-delta + plugin-root paths)
- **Until-mergeable dispatched:** false (suppressed — /automate owns the drain)
