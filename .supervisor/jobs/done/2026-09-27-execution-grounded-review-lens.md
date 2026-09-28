# Supervisor Job: Runtime defects get an executing lens by default — label the static CI bot (`execution: none`), make the Phase 4.5 reviewer reproduce load-bearing claims in a scratch dir

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** branch main == origin/main (ebd4de7); code tree clean. Uncommitted `.supervisor/` trail only (the item-01 requirement close-out stamp + one postmortem ledger line + untracked run/brief artifacts) — none are in this brief's lanes and none may be committed on the feature branch.
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (three stale `.claude/worktrees/*` session worktrees from other sessions exist — do not touch them; the runtime plugin cache is 15.106.2 == repo version, so a SPAWNED `loomwright:code-reviewer` runs the INSTALLED §5, not this branch's edit — see AC-R)
- **Source requirement:** .supervisor/requirements/automate-followups/02-ci-review-bot-cannot-execute.md
- **Base commit:** ebd4de7872f2308ecbf06acb13f5e048a537a066

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown prompt/skill edits + one YAML prompt string + one bash seam test. |
| 2 | Dependency Availability | GO | No new dependency. `mktemp -d` is POSIX. |
| 3 | Architecture Fit | GO | Keeps the two-lens contract (AGENT_GUIDELINES §"Review Counter-Pressure Rule"); adds no pass, only states each lens's execution capability. Allowlist NOT widened (owner decision). |
| 4 | Scope vs Supervisor Capability | GO | ~12 files, one coherent contract change ⇒ single subtask. |
| 5 | Hard Blockers | CAUTION | The PR modifies `.github/workflows/claude-code-review.yml`, so `claude-code-action` self-skips on it (exits 0, posts nothing). Part 1 cannot verify itself on this PR; the drain's Earned Fallback Review (`no_review_lens_posted`) supplies the second lens. |

**Overall Verdict:** CAUTION (proceed; finding carried to Risk Assessment)

## Task
**Goal:** A runtime-only defect has a lens that EXECUTES by default: the Phase 4.5 reviewer writes and runs a minimal adversarial repro (in a `mktemp -d` scratch dir OUTSIDE the checkout, driving the REAL changed scripts) for every load-bearing correctness/security claim, without a human hand-writing that instruction into the spawn prompt. And a static-only `claude-review` green can no longer read as runtime verification: every posted CI review carries a fixed `execution: none` line, and every place that consumes that lens says it is static-only.

**Problem Statement:** On PR #267 (commit 53c0992) the `claude-review` bot reported no findings ("verified statically" — its allowlist forbids executing scripts, deliberately), while Phase 4.5 failed the same SHA with 4 HIGH, each reproduced by execution. Those HIGHs were caught only because the `/automate` main thread hand-added "REPRODUCE by executing in a `mktemp -d` scratch dir" to that one spawn prompt. The standing contract (`agents/code-reviewer.md` §5) only says to type-check and run existing tests — which were green on 53c0992 — so the default reviewer would have passed #267 exactly like the bot.

## Design decisions (settled here so the worker does not choose for the owner)
1. **Ship Parts 1 and 2 in ONE PR** (not split). The single-open-PR invariant of the calling `/automate` run allows one PR per item, and the drain's Earned Fallback Review already covers the workflow-PR bot self-skip. Part 1's live marker is verified on the NEXT non-workflow PR (recorded under "Not verified").
2. **The marker is the LAST line of every posted `claude-review` comment, exactly:** `execution: none — static review; this reviewer cannot run code in CI, so runtime behavior is NOT verified by this review.` The machine-readable key is the line prefix `execution: none` (line-anchored). It goes LAST so it does not collide with the existing mandated first line `Reviewed <sha>: no new findings`. Add it to the workflow prompt's existing "EVERY completed run posts exactly one comment" paragraph, and state it applies to finding-bearing comments too. The "Assert a review was actually posted" step is NOT changed (the marker is informational, never a gate — a missing marker must not turn CI red).
3. **The allowlist is NOT widened** (owner rejected options 2 and 3). No `Bash(...)` entry is added.
4. **Repro-by-default is scoped to Phase 4.5 via an explicit spawn directive — the gate covers ONLY the NEW behavior.** `agents/code-reviewer.md` §5 gains the scratch-dir repro procedure, applied ONLY when the spawn prompt carries the new **EXECUTION DIRECTIVE** line. The §5 gate sentence reads, in substance: *"Without the EXECUTION DIRECTIVE, do not author or run new adversarial repro scripts; the rest of §5 (type-check, the existing tests that cover the diff, `unverified`) is unchanged."* Spawn-path coverage: Phase 4.5 single-voter review (self-heal-advisory Part 2 Task) and the multi-voter code-reviewer respawn ("spawn prompt verbatim as above") CARRY it; of the two per-lens multi-voter **refute** spawns (self-heal-advisory §"Multi-voter verification" point 2), ONLY the refute spawn sent to the **code-reviewer lens** carries it (same trust level as Phase 4.5); the **voter-lens** refute (default `loomwright:red-team-reviewer` Task, or an external provider via `lens-run.sh` when `VOTER_PROVIDER` is set) does NOT — §5's procedure is meaningless to red-team-reviewer, and a third-party CLI must never be told to execute code; the standalone `/review-pr` default loop (review-heal Step 2 / `agents/review-pr.md`) and the drain's Earned Fallback Review do NOT carry it and are NOT edited. Rationale for the scope: Phase 4.5 reviews a branch authored in this same local run (same trust as the worker that wrote it), while a `/review-pr <url>` may target an untrusted fork PR. **Known pre-existing exposure — flagged, NOT fixed here (out of scope):** today's §5 already runs "the specific existing tests that cover the diff", which on a fork PR under standalone `/review-pr` are PR-authored code. This item neither widens nor closes that; the PR body lists it as a follow-up for the owner, and a one-line honest-limit note is added next to the §5 gate sentence.
5. **§5 repro procedure (the wording the worker writes; mirror the ad-hoc #267 instruction):** the reviewer has NO Write/Edit tool (frontmatter `disallowedTools`), so §5 says explicitly that repro files are created with Bash (heredoc) inside the scratch dir — never "I cannot build a repro, mark unverified" for want of a Write tool. For each **load-bearing** correctness or security claim in the diff (the same "load-bearing" test §5 already defines), write and run a minimal ADVERSARIAL repro — try to make the claim false (bypass, ambient-env precedence, malformed/invalid input, empty/whitespace, repo-wide scope, re-run/idempotency) — in a scratch dir created with `mktemp -d` OUTSIDE the checkout, invoking the REAL changed scripts from the checkout by absolute path against scratch fixtures (a scratch `git init` repo when the script needs one). **This is a NAMED, NARROW CARVE-OUT from the read-only contract, not a fit inside it** — the existing text forbids it literally in TWO places: the §5 "Mutation guardrails" paragraph ("NEVER run any command that mutates the working tree, writes artifacts, or changes shared state", "Bash is inspection-only", "temp files") and the Critical Rules bullet "Read-only via Bash too" ("never use Bash to modify files or git state"). Add the SAME carve-out sentence to BOTH, in substance: *"Sole exception: under the EXECUTION DIRECTIVE, Bash may create, write and `rm` files ONLY inside a `mktemp -d` scratch dir the reviewer itself created outside the checkout; the working tree, git state and shared state remain read-only, and the `git status --porcelain` before/after check still runs against the checkout."* Every other guardrail sentence stays as is. A repro that would need to write INSIDE the repo is reported `unverified` per §5's existing rule. No network, no secrets, no `sudo`; `rm -rf` only the scratch dir it created. Each load-bearing claim ends as `reproduced: <defect>` (a finding, severity per the existing rule, with the repro command in `description`/`suggestion`), `held: <what was tried>` (in the summary), or `unverified` (bound to the verdict exactly as §5 already binds it).
6. **EXECUTION DIRECTIVE line** in `skills/self-heal-advisory/SKILL.md` Part 2 §"Review-and-fix loop" spawn prompt — an EVERY-iteration line (like ANTI-OVERLAP, not conditional on an advisory being non-empty), placed after ANTI-OVERLAP (before PRIOR-CHURN — does not disturb the HOUSE-RULES → BRIEF-CONFORMANCE → DEVIATIONS adjacency pinned by the existing seam tests). It MUST state its own scope against the existing "you execute nothing" wording: the directive governs §5 load-bearing claims ONLY; the BRIEF-CONFORMANCE and DEVIATIONS verdicts (and §5a) stay diff-text-only — narrow those parentheticals to "for these verdicts" if needed so the prompt never says an unscoped "execute nothing" next to "execute repros". carrying the §5 procedure by reference ("apply `agents/code-reviewer.md` §5's scratch-dir adversarial repro to every load-bearing claim — this directive is what enables it") plus the one-line summary of what to do, so the reviewer is told even if its agent file is an older install. Do not restate §5's full procedure in the skill (reference-don't-restate, R5).
7. **Static-only labelling of the consumers** (requirement AC "wherever consumed"): Before editing, the worker greps `claude-review` across `loomwright/{skills,commands,docs}` and adds the static-only clause wherever the bot is presented as a review lens / verification; mentions that only concern spend, billing or token accounting (e.g. `commands/supervisor.md`, `commands/automate.md` `--max-tokens` rows, `ARCHITECTURE_CONTRACTS.md` token-ceiling, `PITFALLS.md` ledger) are out of scope and listed as checked in the PR body. Minimum set: (a) `skills/review-heal/SKILL.md` — one short paragraph in §U1 (or immediately after the Earned Fallback subsection) stating that a `claude-review` comment carrying `execution: none` is a STATIC lens: the drain may count it as "a review lens posted" (the Earned Fallback trigger is UNCHANGED), but READY reasoning, the drain's terminal PR comment and its notification text must say "CI review lens: static-only (execution: none)" and never present its "no findings" as runtime verification. No new `REVIEW_HEAL_RESULT` field (flag, don't add — the PR body names this as a considered-and-declined option). (b) `AGENT_GUIDELINES.md` §"Review Counter-Pressure Rule" lens table: the CI row states it is static-only (`execution: none` — reads, never runs); the Phase 4.5 row adds that it executes scratch-dir repros of load-bearing claims (its second information advantage). (c) `CLAUDE.md` §"Failure-Mode Invariants" two-lenses paragraph: one clause noting the CI lens is static-only and Phase 4.5 is the executing lens.
8. **Token budget:** `code-reviewer` is 23838 / 25131 live (1293 headroom). Re-measure after the edit with `scripts/check-token-budget.sh`; if breached, raise per the measured + ~10% rule in BOTH `loomwright/docs/prompt-token-budgets.json` and `docs/ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" with a Re-measure log entry. If NOT breached, leave both files untouched.
9. **Seam test (mechanical, anti-drift):** new `loomwright/scripts/test-execution-directive-seam.sh` (auto-included by CI's `loomwright/scripts/test-*.sh` glob) asserting: the EXECUTION DIRECTIVE line exists in the self-heal-advisory spawn prompt; `agents/code-reviewer.md` contains `mktemp -d`, the directive-gated scope sentence, and the scratch-dir carve-out in BOTH the §5 guardrail paragraph and the Critical Rules "Read-only via Bash too" bullet (asserting both name the same scope); the workflow prompt contains the exact `execution: none` marker sentence; the review-heal SKILL names `static-only`. Each assertion needs a mutation control (delete the line in a temp copy ⇒ the assertion fails), following `test-brief-conformance-seam.sh`'s shape.

## Acceptance Criteria
- [ ] **AC1** — `agents/code-reviewer.md` §5 instructs scratch-dir adversarial repro for load-bearing claims per decision 5 (files written via Bash heredoc), carries decision 5's identical scratch-dir carve-out sentence in BOTH the §5 "Mutation guardrails" paragraph AND the Critical Rules "Read-only via Bash too" bullet (every other guardrail sentence unchanged), keeps "needs to write inside the repo ⇒ `unverified`", and carries decision 4's gate sentence (only NEW repro behavior is gated; rest of §5 unchanged) plus the pre-existing-exposure honest-limit note.
- [ ] **AC2** — `skills/self-heal-advisory/SKILL.md` Part 2 §"Review-and-fix loop" spawn prompt carries the every-iteration EXECUTION DIRECTIVE line per decision 6 (scratch dir outside the working tree; scoped to §5 load-bearing claims, brief-conformance/deviations verdicts stay diff-text-only), and the multi-voter refute spawn wording carries it too (decision 4). Existing seam tests (`test-brief-conformance-seam.sh`, `test-deviations-advisory-seam.sh`) stay green.
- [ ] **AC3** — `.github/workflows/claude-code-review.yml` prompt mandates the exact marker line of decision 2 as the last line of every posted comment (finding-bearing and no-findings alike); the allowlist (`claude_args`) and the assert step are byte-unchanged.
- [ ] **AC4** — consumers state static-only status per decision 7 (a) review-heal, (b) AGENT_GUIDELINES lens table, (c) CLAUDE.md clause; no new `REVIEW_HEAL_RESULT` field; Earned Fallback trigger unchanged.
- [ ] **AC5** — `loomwright/scripts/test-execution-directive-seam.sh` exists, passes, and each assertion has a validated mutation control (mutant non-empty + differs from original + `bash -n`/readable before trusting the result).
- [ ] **AC6 (versioning)** — `self-heal-advisory` and `review-heal` SKILL frontmatter version + `lastUpdated` bumped with matching `SKILLS_INDEX.md` rows (check-skills-index-sync green); plugin version bump in `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` + one CHANGELOG paragraph; counts unchanged (14 agents / 24 commands / 42 skills; `hooks.json` byte-unchanged).
- [ ] **AC7 (full loop green)** — `loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh` + `scripts/check-doc-currency.sh` + `scripts/check-skills-index-sync.sh` + `scripts/check-token-budget.sh` + `loomwright/scripts/test-citation-drift.sh` (decision 8 governs any budget raise).
- [ ] **AC-R (regression evidence — load-bearing; executed by the SUPERVISOR main thread, not the worker, because a worker has no Task tool):** after the worker completes: precheck `git cat-file -e 53c0992^{commit}`; create a detached scratch `git worktree` at `53c0992`; spawn ONE review whose instructions are THIS BRANCH's edited `agents/code-reviewer.md` body (a `general-purpose` agent given that file's content verbatim — a `loomwright:code-reviewer` spawn would load the INSTALLED 15.106.2 §5, not this branch's), constrained to the real reviewer's tool set: it MUST NOT use Write, Edit, NotebookEdit or Task and creates every scratch file via Bash heredoc in its `mktemp -d` dir. Its task text is THIS BRANCH's default Phase 4.5 spawn prompt filled as: BASE_BRANCH=main, feature_branch = the detached worktree at 53c0992, ALL conditional advisory lines omitted (PRIOR-CHURN, HOUSE-RULES, BRIEF-CONFORMANCE, DEVIATIONS) — so the EXECUTION DIRECTIVE is the only variable, with NO other hand-added repro instruction; diff scope `53c0992^1...53c0992`. PASS iff it reports the replay-laundering HIGH (ambient `RULES_CHECK_CONFIRM=1` beating `--if-stamped`) as reproduced by execution. Record the result (and which of the other 3 HIGHs it also reproduced) in the PR body. If it does not report it, the contract change is not strong enough — strengthen the wording and re-run once before escalating.
- [ ] **Invariants** — no allowlist widening; `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` still resolves to the same 5 surfaces; no new agent/command/skill/hook; reviewer still never mutates the working tree.

## Non-goals
- No change to the `gh pr merge --squash` single-executor invariant or the auto-merge gate.
- No widening of the `claude-review` allowlist (options 2 and 3 rejected).
- No repro execution outside Phase 4.5 (standalone `/review-pr`, drain fallback review) — decision 4.
- No new `REVIEW_HEAL_RESULT` / `CODE_REVIEW_RESULT` field; no change to the Earned Fallback trigger.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Static-only marker on the CI lens + directive-gated scratch-dir repro in the Phase 4.5 reviewer, consumer labelling, seam test, version bump | AC1–AC7, Invariants (AC-R is Supervisor-executed) | 10 modify (+2 conditional), 1 create | quality-checklist, unit-testing | LAUNCHABLE |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/agents/code-reviewer.md", name: "mktemp -d"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "EXECUTION DIRECTIVE"}
  - {kind: "symbol", path: ".github/workflows/claude-code-review.yml", name: "execution: none"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "static-only"}
  - {kind: "file", path: "loomwright/scripts/test-execution-directive-seam.sh"}
requires: []
lanes:
  - ".github/workflows/claude-code-review.yml"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/scripts/test-execution-directive-seam.sh"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "AGENT_GUIDELINES.md"
  - "CLAUDE.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis
single-agent (no fan-out)
- **Recommended workers:** 1
- **Estimated batches:** 1

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1

## File Impact Map
| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| CI lens (Part 1) | `.github/workflows/claude-code-review.yml` (prompt paragraph only) | — | HIGH |
| executing lens (Part 2) | `loomwright/agents/code-reviewer.md` (§5), `loomwright/skills/self-heal-advisory/SKILL.md` (Part 2 spawn prompt) | — | HIGH |
| consumers | `loomwright/skills/review-heal/SKILL.md`, `AGENT_GUIDELINES.md`, `CLAUDE.md` | — | HIGH |
| tests | — | `loomwright/scripts/test-execution-directive-seam.sh` | HIGH |
| release / budget | `loomwright/skills/SKILLS_INDEX.md`, `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`; conditionally `loomwright/docs/prompt-token-budgets.json` + `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (decision 8) | — | HIGH / MEDIUM (budget files only if breached) |

> **Validator-owned surfaces:** AC7 depends on `check-doc-currency.sh` / `check-skills-index-sync.sh` / `check-token-budget.sh`; their scanned surfaces for this change are the version/count claims in `plugin.json`, `marketplace.json`, `CHANGELOG.md`, `SKILLS_INDEX.md`, and the budget JSON + ARCHITECTURE_CONTRACTS mirror row — all already in the map.

## Skill References
| Skill | Justification |
|---|---|
| quality-checklist | Standard pre/post-implementation gates; the Self-Heal Miss-Class Checklist (restated-list drift across the lens table / CLAUDE.md / review-heal). |
| unit-testing | New seam test with per-assertion mutation controls. |

## Risk Assessment
| Risk | Impact | Source | Mitigation |
|---|---|---|---|
| **Repro-by-default executes attacker code** if the directive leaks into `/review-pr` on an untrusted fork PR or the drain fallback. | HIGH | Design (decision 4) | Directive-gated §5; the seam test asserts the gate sentence exists; the drain fallback / standalone spawn prompts are NOT edited to carry the directive. |
| **Contract too weak to change behavior** (the reviewer still only runs existing tests). | HIGH | Requirement (load-bearing AC) | AC-R re-runs the #267 review with the default prompt and requires the replay-laundering HIGH reproduced by execution. |
| **Prior churn on these exact paths** (`prompt-token-budgets.json` 14, `self-heal-advisory/SKILL.md` 13, `code-reviewer.md` 9, `review-heal/SKILL.md` 5 entries; classes drain_churn, convention_mismatch, quality_gap; `self_heal_miss` recurred). | HIGH | Prior churn (postmortem ledger) | Watch convention_mismatch between §5, the spawn directive, review-heal and the lens table (same marker string, same scope rule everywhere); grep the old lens-table wording repo-wide. |
| Workflow-touching PR ⇒ `claude-review` self-skips on this PR (green, no comment). | MEDIUM | Feasibility (Phase 2.5) | Drain's Earned Fallback Review supplies the second lens; Part 1 marker verified on the next non-workflow PR ("Not verified"). |
| `code-reviewer` token budget breach (1293 headroom). | MEDIUM | Budget | Decision 8 re-measure + raise with log entry only if breached. |
| AC-R emulation gap: a `general-purpose` agent given the edited agent body is not byte-identical to an installed `loomwright:code-reviewer` (no frontmatter-preloaded skills; broader default tool set). | MEDIUM | Runtime (installed plugin is the pre-change 15.106.2) + Plan Review | AC-R forbids Write/Edit/NotebookEdit/Task to match `disallowedTools`; state the emulation + constraint in the PR body; full live confirmation after release on the next Phase 4.5 run. |
| Pre-existing: standalone `/review-pr` on an untrusted fork PR already runs PR-authored existing tests via today's §5. | MEDIUM | Plan Review (attempt 1) | Out of scope — not widened, not closed; flagged in §5 honest-limit note and the PR body as an owner follow-up. |
| Reviewer refuses to build repros because the read-only contract (§5 guardrail + Critical Rules "Read-only via Bash too") literally forbids file writes. | HIGH | Plan Review (attempt 2) | Decision 5 named carve-out in BOTH places; seam test asserts both; AC-R exercises it. |
| Unscoped "you execute nothing" (BRIEF-CONFORMANCE line, §5a) contradicting the new directive. | MEDIUM | Plan Review (attempt 1) | Decision 6 scoping requirement + AC2. |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-27-execution-grounded-review-lens.md

## Plan Review: PASS (attempt 3/3)
- Non-blocking advisories (carried to the worker spawn, brief unmutated): (M) drop "Sole" from the carve-out sentence — code-reviewer.md already writes one .supervisor/agent-memory-proposals/ file; (M) reconcile the §5 heading "non-mutating only", lead sentence and the "write artifacts ⇒ unverified" line with the scratch-dir carve-out; (L) AC2 = code-reviewer-lens refute only; (L) optional seam-test pin of the refute-lens scope.

## Outcome
- **Status:** completed
- **Completed:** 2026-09-27T18:23:02Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/281
- **Branch:** feature/automate-followups-02-execution-grounded-review-lens
- **Files changed:** 15
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** EXECUTION DIRECTIVE + scratch-dir repro in code-reviewer §5 (Phase 4.5 only), execution: none marker on the CI review, static-only labelling, seam test 34/34; AC-R run 2 PASS (run 1 missed the laundering HIGH → §5 precedence-chain sentence); Phase 4.5 PASS iter 1 with 5 non-gating advisories addressed in b9fccfb. Known red: test-lessons.sh (pre-existing on main).

## Not verified
- **live claude-review comment carrying execution: none** — workflow-touching PR self-skips; verify on the next non-workflow PR (subtask 1)
- **installed-agent Phase 4.5 repro under the directive** — plugin cache still 15.106.2; AC-R used a general-purpose emulation (subtask 1)
- **drain READY/comment/notification text using the static-only label** — prose only (subtask 1)
