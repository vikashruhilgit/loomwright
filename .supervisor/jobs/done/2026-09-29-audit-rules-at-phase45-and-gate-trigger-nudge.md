# Supervisor Job: Re-validate the rules store at every Phase 4.5 run (advisory `rules_audit:` line) and nudge when the parked item-08 CI offer becomes actionable (`rules_gate_trigger:`)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager (worktree `.claude/worktrees/loomwright-automate-resume-adf48d`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean; branch `claude/loomwright-automate-resume-adf48d` == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (installed plugin cache is 15.108.4, repo is 15.111.0 — the inlined workflow bodies predate item 07; code under test is the repo's own `loomwright/`)
- **Source requirement:** .supervisor/requirements/automate-followups/09-audit-rules-at-phase45-and-gate-trigger-nudge.md
- **Base commit:** 059f5e4

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash scripts + skill/command markdown + docs. Must stay macOS bash 3.2 / BSD-userland compatible. |
| 2 | Dependency Availability | GO | No new dependency. Reuses `audit-rules.sh` (on `main`, exit contract 0/1/2) and the item-07 helper shape (`rules-gate-verdict.sh`: one deterministic always-exit-0 wrapper the prose calls). |
| 3 | Architecture Fit | GO | `audit-rules.sh` executes nothing, so an unattended Phase 4.5 caller carries zero code-execution risk (`skills/rules/SKILL.md` §11.2 already says "safe for any unattended caller"). The trigger is computed ONCE, inside the engine, so `/rules audit` (a thin caller) and Phase 4.5 print the same line from one implementation. |
| 4 | Scope vs Supervisor Capability | GO | ~11 files (2 created). Below the context-bound threshold — one subtask. Earlier items in this queue hit the 40-turn worker limit; resume via SendMessage on a turn-limit, never respawn. |
| 5 | Hard Blockers | GO | None. The live store holds 3 advisory rules, 0 `must` (re-verified 2026-09-29: `audit-rules.sh` rc 0, `STANDING rules audited: 3 (of which must: 0)`), and `.supervisor/requirements/proposed/automate-followups-08-setup-rules-ci-offer.md` exists — so the trigger is correctly silent on the live repo, and every trigger/finding state is exercised against sandbox fixtures. |

**Overall Verdict:** GO

## Task
**Goal:** Phase 4.5 re-runs the read-only `audit-rules.sh` over the PR's rule store once per run and reports exactly one advisory `rules_audit: clean | findings <n> (<kinds>) | unexamined` line (could-not-examine is NEVER `clean`); and whenever the store holds ≥1 standing `must` rule with a non-empty `check` while the parked `proposed/automate-followups-08-…` file still exists, both `/rules audit` and Phase 4.5 print one `rules_gate_trigger:` line naming that file. Nothing gates, nothing executes a rule `check`, nothing writes.

**Problem Statement:** `validate-entry.sh`'s correctness checks run once, at `/rules add` time; `audit-rules.sh` re-runs them plus the store-wide checks, but only when a human types `/rules audit` — no runtime seam calls it (`grep -c audit-rules loomwright/skills/self-heal-advisory/SKILL.md` = 0 at base). And parked item 08's revisit trigger ("the first `must` rule with a `check`") is watched by nothing: `/propose` never reads the rules store or hand-authored `proposed/` docs.

## Design decisions (settled here so the worker does not choose)
1. **The trigger lives in `audit-rules.sh` itself — one implementation, two callers.**
   - Add a constant near the top (after `PROG=`): the repo-relative path `.supervisor/requirements/proposed/automate-followups-08-setup-rules-ci-offer.md`, resolved against the script's `$ROOT` (after the existing `cd "$ROOT"`).
   - Count **K** = STANDING rules (the same set the existing `STANDING rules audited: N (of which must: M)` line counts — find the variable the script already uses; do NOT build a second rule enumeration) whose `enforcement` is `"must"` AND whose `check` is a JSON string containing at least one non-whitespace character. This is exactly the complement, among `must` rules, of the `no_mechanism` condition — reuse the SAME null/whitespace predicate `no_mechanism` uses (one predicate, not a re-derived copy).
   - When **K ≥ 1 AND** `test -f "$ROOT/<that path>"`: print a new report section **immediately before `## Store integrity`**:
     ```
     ## Revisit triggers

     rules_gate_trigger: <K> must rule(s) now carry a check — .supervisor/requirements/proposed/automate-followups-08-setup-rules-ci-offer.md is now actionable (promotion is a human moving it out of proposed/, see its Revisit trigger)

     ```
     The `rules_gate_trigger:` line starts at column 0 and appears at most once.
   - Otherwise print NOTHING new — no heading, no line (the report for a non-triggering store is byte-identical to base apart from nothing).
   - The trigger **never changes the exit status, `n_block`, `n_adv` or `n_unk`**, and the script only `test -f`s the proposed file: it never opens, reads, stamps, moves or edits it. It never executes a `check` (the K predicate is a static string test, exactly like `no_mechanism`).
   - Header comment: one short paragraph "REVISIT TRIGGER (automate-followups/09)" stating the condition, that it is read-only and never exit-bearing, and that generalising it into a watcher over every hand-authored `proposed/` doc is a recorded possible follow-up, deliberately not built here.
2. **A deterministic always-exit-0 helper, not prompt-side parsing — new `loomwright/scripts/rules-audit-line.sh`.** Same shape as `rules-gate-verdict.sh` (item 07): the Phase 4.5 prose calls the helper; the model never parses the audit report itself. This is what makes the three-state mapping and its mutation control CI-testable.
   - Usage: `rules-audit-line.sh [--root <tree>]`; `--root` defaults to `.`. Resolves `audit-rules.sh` as a SIBLING via `$(cd "$(dirname "$0")" && pwd)` (CDPATH-safe: `CDPATH= cd …`), never from `PATH`. Runs it as `bash "$HERE/audit-rules.sh" --root "<tree>" </dev/null`, capturing stdout and the exit code; the audit's stderr is discarded.
   - **Always exits 0** (a fail-SAFE advisory emitter wrapping a fail-CLOSED engine — CLAUDE.md §"Failure-Mode Invariants"). stdout is EXACTLY one or two lines, nothing else.
   - **Line 1 — ALLOW-LISTED mapping (never a deny-list):**
     - `rules_audit: clean` ONLY when rc == 0 AND the report contains the exact whole line `## Findings — BLOCKING (0)`.
     - `rules_audit: findings <n> (<kinds>)` ONLY when rc == 1 AND the report contains exactly one whole line `## Findings — BLOCKING (<n>)` with integer n ≥ 1. `<kinds>` = the sorted, de-duplicated `[kind]` tokens from lines matching `^  \[[a-z_]+\] ` that lie between that BLOCKING header and the next line starting `## `, joined with `, ` (e.g. `findings 1 (no_mechanism)`). If no kind token parses, `<kinds>` is `unparsed`.
     - `rules_audit: unexamined` for EVERYTHING else: rc 2, any other rc, the engine absent/unreadable, empty stdout, the header missing or duplicated, or rc and header disagreeing (rc 0 with BLOCKING (3); rc 1 with BLOCKING (0)).
     - The clean predicate must be ONE line of code carrying the comment `# CLEAN-PREDICATE` so the mutation control (AC4) can target it with a single `sed` edit.
   - **Line 2 (optional):** if the report contains a line starting `rules_gate_trigger: ` at column 0, echo the FIRST such line verbatim as line 2, in any line-1 state. Otherwise print no second line.
   - The helper contains no `bash -c`, no `eval`, no reference to `rules-check.sh`, no `.agent/rules` path and no `jq` read of a `check` field (grep-pinned, AC7). It never writes.
3. **Phase 4.5 seam — `loomwright/skills/self-heal-advisory/SKILL.md` Part 1.** Add a new subsection `### Rules-store audit (automate-followups/09 — advisory, NEVER gates)` immediately after the §"Rules-check replay" rules bullets (before `### Contract builder`). Contents:
   - Runs **ONCE per Phase 4.5 run**, at the same post-review advisory point as the other Part 1 post-review checks (NOT per review-and-fix iteration — it lints the store, and the item deliberately adds no loop coupling). Invocation: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/rules-audit-line.sh" --root <the feature-branch checkout>`.
   - `rules_audit_line` = stdout line 1 if it starts with `rules_audit: `, else `rules_audit: unexamined` (an absent/garbled helper never reads as clean). `rules_gate_trigger_line` = stdout line 2 if it starts with `rules_gate_trigger: `, else none.
   - An explicit state trace for all three states (`clean`, `findings <n> (<kinds>)`, `unexamined`), each stating **`heal_decision` is unchanged**, nothing enters Part 2's findings or the review-and-fix loop, and nothing escalates — matching the §"Rules-check replay" wording style. State why no `$NO_CMD_FLAG` / stamp interplay exists: the audit executes nothing.
   - `record_decision(phase: SELF_HEAL, decision: rules_audit_line [+ "; " + rules_gate_trigger_line], rationale: "read-only store audit (audit-rules.sh via rules-audit-line.sh)")`.
   - Completion tail: add a step **8** right after step 7 ("Rules-check replay line") that surfaces `rules_audit_line` (and `rules_gate_trigger_line` when present) in the Phase 4.5 report alongside step 7's line — Phase 4.5 report only, NOT the PR body, NO nested `SUPERVISOR_RESULT` field, NO flat `session_end` field (same placement contract step 7 states).
   - Never put `--confirm` on a line that mentions `rules-check.sh`; the new text need not mention `rules-check.sh` at all (`test-rules-seams.sh` seam (B) greps this file).
4. **`/rules audit` docs.** `loomwright/commands/rules.md` §`audit` gains ONE numbered engine property (8.): the `## Revisit triggers` section and its `rules_gate_trigger:` line — condition, read-only (`test -f` only, the proposed file is never touched), never exit-bearing, and that Phase 4.5 now runs the same engine every run via `rules-audit-line.sh`. `loomwright/skills/rules/SKILL.md` §11 gains a short `### §11.7 — Revisit trigger and the Phase 4.5 caller` with the same facts, and the §11.2 table's **Caller** cell for `/rules audit` names Phase 4.5 (via `rules-audit-line.sh`) as its first unattended caller. Keep every statement `test-rules-docs.sh` block (j) pins intact (audit never executes / reads `check` as data / read-only, propose-only); run `test-rules-docs.sh` after the edit.
5. **`test-rules-seams.sh`.** At base it asserts only on `read-rules.sh` / `rules-check.sh` shapes; it holds no allowlist of which rules scripts a seam may reference. So the default is NO edit. If a run of it after decision 3 goes red, extend it deliberately with a one-line comment stating why (`audit-rules.sh` executes nothing, unlike `rules-check.sh`); otherwise say in the PR body that it needed no change and why.
6. **Release.** Minor bump 15.111.0 ⇒ 15.112.0 in `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, with a new top `CHANGELOG.md` entry (bold one-line headline in the existing style). `rules-audit-line.sh` is an uncounted plain script — no agent/command/skill/hook count changes. No agent prompt is edited, so no budget raise is expected; still run `scripts/check-token-budget.sh`. **Vendor coupling:** the new `${CLAUDE_PLUGIN_ROOT}` invocation line in `self-heal-advisory/SKILL.md` (allowance 20 at base) and any in the new helper/test will move `scripts/check-vendor-coupling.sh` counts. `git add` the new files FIRST (the gate only scans tracked files — item 06's CI went red on exactly this), run the gate, and raise the affected rows in `loomwright/docs/vendor-coupling-manifest.json` in this same change (new files need a row if they carry any token; prefer writing the new helper/test WITHOUT the tokens — resolve the sibling via `$(dirname "$0")` and let tests call it by path).

## Acceptance Criteria
- [ ] **AC1 (Phase 4.5 prose):** `skills/self-heal-advisory/SKILL.md` Part 1 has the `### Rules-store audit` subsection invoking `rules-audit-line.sh --root`, emitting exactly one `rules_audit:` line, with a state trace naming all three states (`clean`, `findings`, `unexamined`) and saying `heal_decision` is unchanged in every state; completion-tail step 8 surfaces the line. `grep -c 'audit-rules\|rules-audit-line' loomwright/skills/self-heal-advisory/SKILL.md` ≥ 1 (was 0). Pinned in the new test by a static grep, with a gated mutant (a temp copy of the SKILL with the invocation line deleted makes the pin fail — non-empty + differs-from-original + unmutated positive control, lesson fa32a308).
- [ ] **AC2 (`no_mechanism` ⇒ `findings`, store byte-identical):** a sandbox (own `git init`, own `HOME`) whose store holds a `must` rule with `check: null` ⇒ `rules-audit-line.sh --root <sandbox>` prints exactly `rules_audit: findings 1 (no_mechanism)` and exits 0; a sorted per-file content hash of the sandbox `.agent/rules/*.json` is identical before and after.
- [ ] **AC3 (clean):** an advisory-only sandbox store ⇒ exactly one line `rules_audit: clean`, exit 0. A sandbox with NO `.agent/rules/` directory ⇒ `rules_audit: clean` too (the engine reports 0 rules, rc 0 — the small-N case), exit 0.
- [ ] **AC4 (`unexamined`, never `clean`, + mutation control):** (a) `AUDIT_RULES_VALIDATOR=<nonexistent>` over an otherwise-clean store (engine rc 2) ⇒ `rules_audit: unexamined`; (b) a rule file made unreadable (`chmod 000`; skip this leg with a printed SKIP when the file is still readable afterwards, i.e. running as root) ⇒ `unexamined`; (c) a stub engine (temp copy of the helper beside a stub `audit-rules.sh`) exiting 0 but printing `## Findings — BLOCKING (3)` ⇒ `unexamined`; (d) the engine absent beside a temp copy of the helper ⇒ `unexamined`; every leg exits 0. **Mutation control:** a temp copy of the helper whose `# CLEAN-PREDICATE` line is `sed`-edited to also accept rc 2 makes leg (a) print `clean` — the test asserts the mutant is non-empty, differs from the original, and flips the verdict, while the unmutated helper prints `unexamined` on the same fixture.
- [ ] **AC5 (trigger — both surfaces):** a sandbox with ≥1 `must` rule whose `check` is a non-empty string AND the file `.supervisor/requirements/proposed/automate-followups-08-setup-rules-ci-offer.md` present ⇒ `audit-rules.sh --root <sandbox>` output contains exactly one column-0 line starting `rules_gate_trigger: 1 must rule(s) now carry a check — .supervisor/requirements/proposed/automate-followups-08-setup-rules-ci-offer.md`, and `rules-audit-line.sh --root <sandbox>` prints that same line as its second line. Negative legs: (i) 0 such rules (a `must` with `check: null`, or a `must` with a whitespace-only check, or advisory-only) ⇒ no `rules_gate_trigger` and no `## Revisit triggers` in either output; (ii) the rule present but the proposed file absent ⇒ absent in both. The trigger never changes `audit-rules.sh`'s exit code (assert rc is the same with and without the proposed file). **No execution:** the `must` rule's check is `touch <sandbox>/CANARY`; assert CANARY never exists after every leg. The proposed file's content hash is identical before and after.
- [ ] **AC6 (`/rules audit` docs):** `commands/rules.md` §`audit` and `skills/rules/SKILL.md` §11 document the `rules_gate_trigger:` line (condition, read-only, never exit-bearing) and the Phase 4.5 caller; `bash loomwright/scripts/test-rules-docs.sh` stays green.
- [ ] **AC7 (helper invariants, static):** `grep -nE 'bash -c|eval |rules-check\.sh|\.agent/rules|\.check\b' loomwright/scripts/rules-audit-line.sh` returns no code line (comment-only hits allowed), asserted in the test; `audit-rules.sh` gains no `bash -c`/`eval`/`source` of a `check` (its own no-execution canary in `test-audit-rules.sh` stays green).
- [ ] **AC8 (seam guard):** `bash loomwright/scripts/test-rules-seams.sh` passes (decision 5).
- [ ] **AC9 (release + budgets):** version 15.112.0 in `plugin.json` + `marketplace.json`; new top CHANGELOG entry; `scripts/check-doc-currency.sh`, `scripts/check-token-budget.sh` and `scripts/check-vendor-coupling.sh` (after `git add`) green.
- [ ] **AC10 (full loop green):** run under `bash`: every `loomwright/scripts/test-*.sh`, `loomwright/scripts/adapters/*/test-*.sh` and root `scripts/test-*.sh`; plus `scripts/check-vendor-coupling.sh`, `scripts/check-doc-currency.sh`, `scripts/check-command-sync.sh`, `scripts/check-skills-index-sync.sh`, `scripts/check-token-budget.sh`, `scripts/check-test-hermetic.sh`, `scripts/check-contract-parity.sh`, and `loomwright/scripts/test-citation-drift.sh`. The new test `loomwright/scripts/test-rules-audit-line.sh` sources `hermetic-test-env.sh` as its first executable line (the #290 ratchet).
- [ ] **Invariants:** `rules-check.sh` remains the only file that executes a rule `check`; `audit-rules.sh` keeps no write mode and its exit contract (0/1/2) unchanged; the new helper never writes and always exits 0; `heal_decision` / Part 2 findings / the drain / `gate-eval` are untouched (no file under `skills/review-heal/`, `skills/automate-loop/` or `scripts/automate-helpers.sh` changes); the `gh pr merge --squash` positive grep resolves to the same 5 surfaces; no new agent/command/skill/hook; no result-block field or `schema_version` change.

## Non-goals
- Any gating on audit findings or on the trigger (gating on a failing check is item 07, shipped).
- Any write mode in `audit-rules.sh`; it stays dry-run ONLY.
- Generalising (b) into a watcher for every hand-authored doc in `proposed/` — recorded as a possible follow-up in the `audit-rules.sh` header comment, not built.
- Moving, stamping or promoting `proposed/automate-followups-08-…` — promotion stays a human act.
- Running the audit per review-and-fix iteration, or feeding it to the `--until-mergeable` drain / `review-heal`.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Trigger section in `audit-rules.sh`, new `rules-audit-line.sh` + `test-rules-audit-line.sh`, Phase 4.5 seam in `self-heal-advisory/SKILL.md`, `/rules audit` docs, vendor-coupling rows, version + CHANGELOG | AC1–AC10, Invariants | ~9 modify, 2 create | unit-testing, quality-checklist | LAUNCHABLE |

## Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/scripts/rules-audit-line.sh"}
  - {kind: "file", path: "loomwright/scripts/test-rules-audit-line.sh"}
  - {kind: "symbol", path: "loomwright/scripts/rules-audit-line.sh", name: "CLEAN-PREDICATE"}
  - {kind: "symbol", path: "loomwright/scripts/audit-rules.sh", name: "rules_gate_trigger"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "rules-audit-line.sh"}
  - {kind: "symbol", path: "loomwright/commands/rules.md", name: "rules_gate_trigger"}
  - {kind: "symbol", path: "loomwright/skills/rules/SKILL.md", name: "rules_gate_trigger"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.112.0"}
requires: []
lanes:
  - "loomwright/scripts/audit-rules.sh"
  - "loomwright/scripts/rules-audit-line.sh"
  - "loomwright/scripts/test-rules-audit-line.sh"
  - "loomwright/scripts/test-rules-seams.sh"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/rules/SKILL.md"
  - "loomwright/commands/rules.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Recommended workers:** 1 (single-agent)
- **Estimated batches:** 1

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| engine + helper | `loomwright/scripts/audit-rules.sh` (trigger section + header paragraph) | `loomwright/scripts/rules-audit-line.sh`, `loomwright/scripts/test-rules-audit-line.sh` | HIGH |
| seam + docs | `loomwright/skills/self-heal-advisory/SKILL.md`, `loomwright/skills/rules/SKILL.md`, `loomwright/commands/rules.md`, `loomwright/scripts/test-rules-seams.sh` (LOW — only if it goes red, decision 5) | — | HIGH |
| release | `loomwright/docs/vendor-coupling-manifest.json` (MEDIUM — only the rows the gate says moved), `CHANGELOG.md`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | — | HIGH |

> **Validator-owned surfaces:** AC9–AC10 depend on `scripts/check-doc-currency.sh`, `scripts/check-vendor-coupling.sh`, `scripts/check-test-hermetic.sh`, `scripts/check-token-budget.sh` and `loomwright/scripts/test-citation-drift.sh`. Any pinned `file:N [pins: …]` citation into an edited file must still resolve; run the citation-drift test after the last prose edit.

## Skill References
- `skills/unit-testing/SKILL.md` (bash self-tests, sandbox `HOME` + `git init`, gated mutants)
- `skills/quality-checklist/SKILL.md`
- `skills/rules/SKILL.md` §11 (audit posture, exit contract 0/1/2, "could-not-examine is never clean") — read before writing the helper
- `loomwright/scripts/rules-gate-verdict.sh` + `loomwright/scripts/test-rules-gate-verdict.sh` (item 07: the always-exit-0 wrapper shape, allow-listed mapping, sibling resolution, stub-engine spy pattern to mirror)
- `loomwright/scripts/test-audit-rules.sh` (sandbox store fixtures, `AUDIT_RULES_VALIDATOR` degraded-helper fixtures, the no-execution canary)

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

> Advisory only (no `must` rules apply, so no `rule:` bullets). Applied here: the audit's finding-kind list and the "could-not-examine is never clean" contract stay owned by `audit-rules.sh` / `skills/rules/SKILL.md` §11 — the new Phase 4.5 prose points there rather than restating the kind list; the trigger condition is stated once in the engine header and pointed at from the docs.

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| The helper maps rc 2 (or an unknown/garbled engine answer) to `clean` — the exact fail-open §11.5 forbids | HIGH | Decision 2 allow-listed mapping (clean requires rc 0 AND the exact BLOCKING (0) header); AC4 four legs + the `# CLEAN-PREDICATE` mutation control. |
| The trigger grows an execution or write path (reads/edits the proposed file, or runs a `check` to "verify" it) | HIGH | Decision 1: `test -f` only, static K predicate shared with `no_mechanism`; AC5 CANARY + proposed-file hash; AC7 static greps. |
| The new report section perturbs existing `test-audit-rules.sh` pins | MEDIUM | Decision 1 prints nothing new when not triggering; run `test-audit-rules.sh` after the engine edit. |
| A second copy of the `no_mechanism` null/whitespace predicate drifts from the first | MEDIUM | Decision 1: reuse the same predicate (house rule on restating copies). |
| `check-vendor-coupling.sh` breach from a new `${CLAUDE_PLUGIN_ROOT}` line (item 06 CI went red this way, locally invisible before `git add`) | MEDIUM | Decision 6: `git add` new files first, run the gate, raise the manifest rows in the same change; keep tokens out of the new scripts. |
| `test-rules-seams.sh` seam (B) trips on new prose near `rules-check.sh` | LOW | Decision 3: the new subsection does not mention `rules-check.sh`; AC8. |
| `test-rules-docs.sh` block (j) regexes (audit never executes / read-only) broken by the §11 edit | LOW | Decision 4 keeps those statements; AC6 runs the test. |
| `chmod 000` leg is vacuous when CI runs as root | LOW | AC4(b) prints SKIP when the file stays readable; legs (a)/(c)/(d) carry the unexamined guarantee without permissions. |
| Worker turn limit (items 02/04/06/07 hit 40 turns) | LOW | Resume via SendMessage on a turn-limit, never respawn. |

## Configuration
- **Mode:** single-agent
- **Recommended workers:** 1
- **Estimated batches:** 1

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-09-29-audit-rules-at-phase45-and-gate-trigger-nudge.md

## Outcome
- **Status:** completed
- **Completed:** 2026-09-29T09:40:40Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/299 (merged 0587ffe, 2026-09-29)
- **Branch:** feature/automate-followups-09-audit-rules-at-phase45-and-gate-trigger-nudge
- **Files changed:** 12
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** `audit-rules.sh` gains a read-only, exit-neutral `## Revisit triggers` section (one `rules_gate_trigger:` line when ≥1 standing `must` rule carries a non-empty check AND `proposed/automate-followups-08-…` exists; reuses the `no_mechanism` predicate). New always-exit-0 `rules-audit-line.sh` maps the audit to one allow-listed `rules_audit: clean | findings <n> (<kinds>) | unexamined` line, consumed by an advisory Phase 4.5 subsection + completion-tail step 8. `/rules audit` docs updated; v15.112.0. Single subtask (worker hit the 40-turn limit once, resumed). Plan Review PASS 1/3 with 5 carried advisories. Phase 4.5 PASS on iteration 1 (execution-grounded repros held); 1 dismissed pre_existing MEDIUM (agents/supervisor.md "steps 1–6" range), then fixed on owner direction in d3fa40f (range-free pointers in agents/ + commands/supervisor.md, Phase 4.5 Output slots for the rules lines). Owned drain READY converged on 3558a28 and re-confirmed on d3fa40f, 0 fix cycles. rules_check: none · rules_audit: clean · ground truth 2/2 · risk high_risk=true.

## Not verified
- **Phase 4.5 §Rules-store audit + step 8 in a live Supervisor run** — prompt prose; static runtime-form pin + helper behaviour tests only (subtask 1)
- **The new Phase 4.5 step on the installed agent** — the installed plugin cache (15.108.4) predates it until updated (subtask 1)
