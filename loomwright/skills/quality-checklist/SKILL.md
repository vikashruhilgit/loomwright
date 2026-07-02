---
name: quality-checklist
description: Pre-task and post-task quality gates extracted from AGENT_GUIDELINES.md. Use when starting implementation, during development, or before completing code review.
allowed-tools: Read
version: "1.2.0"
lastUpdated: "2026-06-27"
---

# Quality Checklist Skill

Pre-task and post-task quality gates (extracted from AGENT_GUIDELINES.md).

## Pre-Task Checklist

Before starting implementation:

- [ ] Task clearly defined (Beads task, Supervisor-Ready Brief, or equivalent source with acceptance criteria)
- [ ] Dependencies checked (blocks, subtasks)
- [ ] Related CLAUDE.md patterns understood
- [ ] Test strategy defined (unit/integration/e2e)
- [ ] Framework-specific skills identified
- [ ] Token budget estimated (Context7 needed?)

## Implementation Checklist

During development:

- [ ] Follow CLAUDE.md patterns
- [ ] Use existing code patterns (don't reinvent)
- [ ] Type safety: no implicit `any`
- [ ] Test coverage ≥ 80%
- [ ] No secrets/PII in code or logs
- [ ] Input validation at system boundaries
- [ ] Error handling documented
- [ ] Performance considered (profile if needed)
- [ ] **Read-before-write verification** — before asserting any exact shape (command/API/dispatch/spawn/flag/file:line), consumer contract ("feeds Y for free" / "Y-compatible"), or absence ("X is missing"), opened the authoritative source and confirmed it (whole predicate / required-field list / a second tool for absence). Before writing something that depends on another artifact, verified that specific dependency's current state. "Pretty sure" → verify. (See AGENT_GUIDELINES.md → "Read-Before-Write Verification Gate".)

## Post-Task Checklist (Code Review Gate)

Before marking complete:

- [ ] Tests pass (unit + integration)
- [ ] No linting/type errors (`npm run lint`, `npm run type-check`)
- [ ] Code follows existing patterns
- [ ] Changes minimal and focused (surgical)
- [ ] Coverage ≥ 80%; no regressions
- [ ] No secrets, debug code, console.logs
- [ ] Docs/comments updated
- [ ] Input validation in place
- [ ] Related CLAUDE.md patterns reflected

## Code Quality Standards

### 1. Quality First
- **Principle:** Thorough, well-tested, correct solutions; proven approaches
- **Check:** Does code solve the stated problem completely?
- **Test:** Write test case for each acceptance criterion

### 2. Surgical Changes
- **Principle:** Only modify what's necessary; fix one thing at a time
- **Check:** Are there unrelated changes (formatting, refactoring)?
- **Impact:** Smaller diffs = easier review + less regressions

### 3. Pattern Consistency
- **Principle:** Use existing patterns; learn codebase before implementing
- **Check:** Does code match existing service/controller/guard patterns?
- **Reference:** Point to similar code in same repo

### 4. Type Safety
- **Principle:** Strictest checking; no implicit `any`
- **Check:** All variables typed explicitly
- **Tools:** TypeScript strict mode, ESLint no-implicit-any

### 5. Security
- **Principle:** No secrets/PII in code/logs; validate inputs
- **Check:**
  - No hardcoded API keys, passwords, tokens
  - Env vars for secrets
  - Input validation at boundaries
  - Error messages don't leak sensitive info

### 6. Performance
- **Principle:** Profile before/after; document tradeoffs
- **Check:** No obvious N+1 queries, loops, or inefficiencies
- **Benchmark:** If modifying hot path, include timing data

## Review Decision Matrix

| Finding | Type | Action |
|---------|------|--------|
| Missing test case | FAIL | Request test addition |
| Hardcoded secret | FAIL | Reject, require env var |
| Pattern mismatch | FAIL | Request alignment |
| Performance issue | FAIL | Request optimization |
| Minor style issue | PASS (issue reported) | MEDIUM/LOW never gates; reported in the result |
| Good security practice | PASS | Approve |
| Tests + docs complete | PASS | Approve |

## Gate Outcomes

### ✓ PASS
- All checks complete
- No blockers
- Ready to merge/close task

### ✗ FAIL
- Blocking issue found (test, security, pattern)
- Developer must fix
- Re-run review after changes

### ≈ NEEDS_HUMAN
- Genuine design ambiguity / architectural disagreement the reviewer cannot adjudicate
- NOT for ordinary MEDIUM/LOW findings — those are reported under a PASS
- Human decides the open question
- Issue created for tracking (BD-XXX if Beads is active, otherwise recorded in review output)

## Repo Consistency Checks (for plugin / prompt / doc reviews)

These checks apply to reviews that touch trigger surfaces (`loomwright/agents/`, `loomwright/commands/`, `loomwright/skills/`, `loomwright/docs/`, `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `loomwright/hooks/hooks.json`, `CLAUDE.md`, `README.md`, `loomwright/skills/SKILLS_INDEX.md`, `.supervisor/jobs/`). The Code Reviewer enters `consistency_audit` mode and runs these in addition to the standard gates. See the full trigger table in `loomwright/agents/code-reviewer.md` → "Review Modes & Scope Expansion".

### Authoritative vs advisory sources

- **Authoritative (drift = BLOCKING/HIGH):** `loomwright/.claude-plugin/plugin.json#version`, `.claude-plugin/marketplace.json#plugins[].version` (must equal `plugin.json#version`, enforced by `scripts/validate-version.sh`), `CLAUDE.md` current-version lines (`- **Version:** X.Y.Z` and `plugin.json (vX.Y.Z)`).
- **Secondary (drift = MEDIUM advisory):** `README.md`, `.claude-plugin/README.md`, `plugin.json#description`, `marketplace.json#description`.
- **Ignored (not drift):** archival/changelog references like "since v10.0.0", "v10.3 feasibility gates", "schema v9.0.0". Frontmatter `hooks:` parity is LOW/doc-only (Claude Code ignores plugin-agent frontmatter hooks at runtime).

### Checks

- [ ] **Mirrored prompt alignment** — `loomwright/commands/{name}.md` carries the thin-wrapper sentinel and does not re-embed canonical sections (`## Role:`, `### Review Decision Matrix`, `### Close Review Task`, `### Pre-Review Checklist` as H3, `# Code Reviewer Agent Prompt`). Drift kind: `mirrored_prompt`.
- [ ] **Version consistency (authoritative)** — all three authoritative surfaces equal. Drift kind: `version_authoritative`.
- [ ] **Version consistency (secondary)** — README / CLAUDE.md / descriptions' current-version claims match authoritative. Historical refs ignored. Drift kind: `version_secondary` (capped at MEDIUM).
- [ ] **Count consistency** — counts of agents (`loomwright/agents/*.md`), skills (`loomwright/skills/*/SKILL.md`), commands (`loomwright/commands/*.md`), and hooks (sum of leaf matcher entries across all event buckets in `loomwright/hooks/hooks.json` — NOT top-level bucket count) match claims in `plugin.json#description`, `marketplace.json#description`, `CLAUDE.md` File Counts block, `SKILLS_INDEX.md` header. Drift kind: `count` (capped at MEDIUM).
- [ ] **Workflow consistency** — agent prompt behavior matches `loomwright/commands/{name}.md` usage + `CLAUDE.md` role section + `loomwright/commands/agent-help.md` for *currently active* claims. Drift kind: `workflow`.
- [ ] **Hooks parity (advisory)** — `loomwright/hooks/hooks.json` entries vs `CLAUDE.md` hooks table. Mismatches with agent frontmatter `hooks:` are LOW/doc-only. Drift kind: `hooks_parity` (capped at LOW).

### Severity caps for drift

| drift_kind | Cap | May trigger FAIL? |
|---|---|---|
| `version_authoritative`, `mirrored_prompt`, `workflow` | none | yes (HIGH/BLOCKING allowed) |
| `count`, `version_secondary` | MEDIUM | no |
| `hooks_parity`, `wording` | LOW | no |

The plugin hook enforces these caps — an issue violating a cap is rejected at Stop time.

## Self-Heal Miss-Class Checklist (Supervisor Phase 4.5 — repo-agnostic)

Applied by the Code Reviewer during Supervisor Phase 4.5 self-heal (and any standalone `/review-pr` heal). Unlike the **Repo Consistency Checks** above — which only fire on this plugin's own trigger surfaces — these classes are **repo-agnostic**: they catch the issue classes that historically only surfaced across 3–6 rounds of post-PR human review, on external app repos as well as this one. The holistic re-run of a diff-scoped reviewer inherits the same blind spots it had per-subtask; this checklist is the *different lens* that breaks that loop. Advisory severity follows the standard matrix — a `new` HIGH/BLOCKING instance FAILs the heal review; lesser instances are reported. It never introduces a new gate.

Check each class against the integrated diff:

- [ ] **Adversarial-input handling (negative / zero / overflow / empty / replay / concurrent).** Every changed code path that consumes input or mutates state is interrogated against hostile / edge inputs — negative or zero quantities, empty / `null` / absent values, max / overflow, replayed (double-submit / retried / redelivered) calls against run-once or idempotent operations, and concurrent execution (check-then-act races, double-grant). Class signal: a new amount / quantity / state-mutation / resource-grant path with no guard against ≤ 0, replay, or concurrent double-execution.
- [ ] **Validation parity (backend mirrors frontend).** Every rule a frontend/client schema enforces (required, min/max, enum, format, length) has an equivalent server-side / API-boundary check. A field validated only in the browser is unvalidated. Class signal: a new frontend Zod/Yup/form rule with no matching backend guard.
- [ ] **No falsy coercion on numeric (or boolean) fields.** `value || default` / `if (!count)` silently swallows a legitimate `0` (and `false`, `""`). Use `value ?? default` / explicit `=== undefined` / `== null` checks for fields where zero/empty is valid. Class signal: `||`, `!x`, or truthiness guards applied to a quantity, price, count, offset, or index.
- [ ] **No positional args to an options-object function.** When a function takes a single options object (`fn({ a, b })`), every call site passes an object — never positional args (`fn(a, b)`), and never in the wrong key order. Class signal: a call site whose argument shape doesn't match the callee's signature.
- [ ] **Branch coverage for new conditionals.** Every new `if`/`else`/`switch`/ternary/error path introduced by the diff has at least one test exercising each branch (success AND failure). Class signal: a new conditional or early-return with no corresponding test.
- [ ] **Count / version / restated-list drift.** When the change alters a count (N agents/commands/items), a version string, a mirrored prompt, or any restated list, EVERY place that restates that count/version/list is updated in the same change. Class signal: a number/version/canonical name that appears in more than one file, changed in one but not the others.
- [ ] **Cross-reference precision drift.** When the change moves, renames, or removes a target, EVERY "see X" / `file:line` / canonical-name cross-reference that pointed at it is updated in the same change so it still points where it claims. Class signal: a reference whose target moved, was renamed, or no longer exists.

**Language-adaptation note (keeps this repo-agnostic):** the *classes* are language-agnostic, but the inline `Class signal` examples are illustrative and JS/TS-flavored (`||`/`??`, `if (!x)`, Zod/Yup, `fn({ ... })`). On a non-JS repo, map each signal to the target language's equivalent — e.g. Python `or` / `if not x` / `is None` / `**kwargs`; Go zero-value checks / functional-options structs; Rust `Option` / builder structs — and don't treat the literal JS tokens as exhaustive.

**Fix-the-class rule (pairs with Supervisor Phase 4.5 fixer):** when any instance above is flagged, the fixer sweeps the whole diff for the same class and fixes all occurrences — the reviewer samples, the fixer sweeps. See `agents/supervisor.md` Phase 4.5 fix-iteration step.

**Correctness-severity rule (pairs with the diff-review fix floor).** When a class above is a confirmed correctness / security / behavior regression introduced by the diff, label it **HIGH or BLOCKING** (not MEDIUM/LOW) so Phase 4.5 / the default `/review-pr` loop actually fix it — the fix floor only addresses `new` + BLOCKING/HIGH. MEDIUM/LOW stay for maintainability / polish. This is the severity-assignment rule mirrored from `agents/code-reviewer.md`'s "Flag Issues by Severity" step; it does NOT touch the `drift` severity caps.

## Token Cost

- Checklist invocation: 60 tokens
- Framework-specific variations: 100-200 tokens
- Repo consistency section (audit mode only): +150 tokens
- Self-Heal Miss-Class Checklist (Phase 4.5 / review-pr heal only): +180 tokens
- Total: ~250-400 tokens
- Context7: Not required










