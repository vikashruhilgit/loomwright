# Rationale — Subagents

Stories, history, examples and explanations moved out of the runtime prompts of the four most-spawned subagents (`agents/code-reviewer.md`, `agents/plan-reviewer.md`, `agents/execute-manager.md`, `agents/worker.md`) by automate-speed/26. Nothing here is read at runtime and nothing here is a rule: every rule stayed in a runtime prompt (`kept-as-one-line` — condensed, never dropped) or now lives in the script, hook or on-demand skill Read named as its home. Each agent section has one table row per removed line, with its home as `script:<file>` (under `loomwright/scripts/`), `hook:<hooks.json leaf>`, `on-demand:<skill path> at <step>`, or `kept-as-one-line`; moved stories follow under `###` headings, verbatim from the pre-diet prompt; and `### Preload decisions` records each original frontmatter `skills:` entry. A removed line that still reads like a rule but sits under a story heading is a duplicate of a rule the prompt kept.

## code-reviewer

| removed line (short quote) | home |
|---|---|
| frontmatter: - context7-lookup | on-demand:skills/context7-lookup/SKILL.md at Context Setup step 6 when CLAUDE.md lacks a library fact |
| frontmatter: - unit-testing | on-demand:skills/unit-testing/SKILL.md at Context Setup step 5 / Review Process step 3 when the diff touches tests |
| frontmatter: - error-handling | on-demand:skills/error-handling/SKILL.md at Context Setup step 5 / Review Process step 3 when the diff touches error paths |
| frontmatter: - monitoring-observability | on-demand:skills/monitoring-observability/SKILL.md at Context Setup step 5 / Review Process step 3 when the diff touches logging/metrics/tracing |
| §Core Principles: - **Quality gates:** Reviews block next task until PASS (no forward progress on FAIL) | kept-as-one-line |
| §Core Principles: - **Clear decisions:** Output PASS / FAIL / NEEDS_HUMAN with evidence | kept-as-one-line |
| §Core Principles: - **Beads-optional:** When `.beads/` is present and `bd --version` succeeds, use the Beads… | kept-as-one-line |
| §Core Principles: - **Bug tracking:** NEEDS_HUMAN creates dependent bug issues (when Beads is active) or rec… | kept-as-one-line |
| §Core Principles: - **Skill-driven:** Use `skills/quality-checklist/SKILL.md` criteria | kept-as-one-line |
| §Core Principles: - **Pattern validation:** Verify code follows CLAUDE.md patterns; challenge CLAUDE.md when… | kept-as-one-line |
| §Core Principles: - **Pattern detection:** Identify patterns for CLAUDE.md (proposal only) | kept-as-one-line |
| §Core Principles: - **UI consistency:** Enforce design-system components; flag raw UI or library misuse | kept-as-one-line |
| §Core Principles: - **Domain enforcement:** Map review scope to relevant skills (frontend/backend/framework) | kept-as-one-line |
| §Core Principles: - **Specific feedback:** Always file:line + code snippet + fix suggestion | kept-as-one-line |
| §Inputs: > Note: Orchestrator no longer creates review subtasks automatically at any threshold (see… | kept-as-one-line |
| §Inputs: - **Review scope:** Files/directories to review (from invocation argument, or from a human… | kept-as-one-line |
| §Inputs: - **Project context:** `CLAUDE.md` (patterns, type safety, test threshold) | kept-as-one-line |
| §Inputs: - **Review config:** Optional `REVIEW.md` (review-specific rules, severity overrides, skip… | kept-as-one-line |
| §Inputs: - **Beads task (optional):** Current review subtask (e.g., "BD-49: Code Review - JwtGuard"… | kept-as-one-line |
| §Inputs: - **Code to review:** Git changes, specific files, or commit diff | kept-as-one-line |
| §Inputs: - **Quality checklist:** `skills/quality-checklist/SKILL.md` criteria | kept-as-one-line |
| §Outputs: - **CODE_REVIEW_RESULT block (required, always emitted):** schema v3 — `review_mode` (diff… | hook:SubagentStop[loomwright:code-reviewer] validate-code-review-result.py |
| §Outputs: - **Decision:** PASS / FAIL / NEEDS_HUMAN | kept-as-one-line |
| §Outputs: - **Evidence:** Issues found with severity (BLOCKING/HIGH/MEDIUM/LOW) and category (new/pr… | kept-as-one-line |
| §Outputs: - **Fixes:** Specific suggestions with file:line + code snippets | kept-as-one-line |
| §Outputs: - **Blockers:** What must be fixed before PASS | kept-as-one-line |
| §Outputs: - **Beads comment (conditional — only when Beads is active):** Add to review subtask with … | kept-as-one-line |
| §Outputs: - **Bug issues (conditional — only when Beads is active):** Create (BD-XX) if NEEDS_HUMAN … | kept-as-one-line |
| §Outputs: - **Pattern proposals:** Flag opportunities for CLAUDE.md update | kept-as-one-line |
| §Critical Rules: - **Specific feedback:** Every issue gets file:line + suggestion | kept-as-one-line |
| §Critical Rules: - **Turn budget — 40 turns (advisory):** Your `maxTurns` ceiling is 40; budget the review … | kept-as-one-line |
| §Agent Guidelines: **Code Reviewer Responsibilities:** | kept-as-one-line |
| §Agent Guidelines: - Review code against `CLAUDE.md` patterns and `skills/quality-checklist/SKILL.md` criteri… | kept-as-one-line |
| §Agent Guidelines: - **Validate CLAUDE.md accuracy:** Check documented patterns match actual codebase; flag w… | kept-as-one-line |
| §Agent Guidelines: - **Map domain-specific skills:** Identify which skills apply (frontend-ui, error-handling… | kept-as-one-line |
| §Agent Guidelines: - **Enforce UI consistency:** For frontend code, verify design-system usage, accessibility… | kept-as-one-line |
| §Agent Guidelines: - Determine review outcome: PASS / FAIL / NEEDS_HUMAN | kept-as-one-line |
| §Agent Guidelines: - For each issue: severity (BLOCKING/HIGH/MEDIUM/LOW), category (new/pre_existing/nit/drif… | hook:SubagentStop[loomwright:code-reviewer] validate-code-review-result.py |
| §Agent Guidelines: - Flag patterns for CLAUDE.md (proposal in output, plus Beads comment when active) | kept-as-one-line |
| §Agent Guidelines: - When Beads is active and decision is NEEDS_HUMAN: create bug issues (BD-XX) that block t… | kept-as-one-line |
| §Agent Guidelines: - When Beads is active: comment on the review task with full findings | kept-as-one-line |
| §Agent Guidelines: - Always emit a CODE_REVIEW_RESULT block — it is the canonical, machine-readable output | kept-as-one-line |
| §Agent Guidelines: **Decision Definitions:** | kept-as-one-line |
| §Agent Guidelines: - **PASS:** All quality-checklist criteria met. Next task may proceed. | kept-as-one-line |
| §Agent Guidelines: - **FAIL:** Critical issues must be fixed. Developer fixes, re-run review. | kept-as-one-line |
| §Agent Guidelines: - **NEEDS_HUMAN:** Genuine design ambiguity or architectural disagreement the reviewer can… | kept-as-one-line |
| §Agent Guidelines: - When Beads is active: create bug issues (BD-XX) with `blocks=BD-[review]`; review blocke… | kept-as-one-line |
| §Agent Guidelines: - When Beads is not active: record issues in CODE_REVIEW_RESULT; callers must inspect and … | kept-as-one-line |
| §Agent Guidelines: - Human decides the open design question; callers like `/review-pr` map NEEDS_HUMAN to ESC… | kept-as-one-line |
| §Agent Guidelines: **Standard Output Format:** See `skills/agent-output/SKILL.md` | kept-as-one-line |
| §Agent Guidelines: - Context Read → Current State → Plan → Work/Results → Risks & Next Steps | kept-as-one-line |
| §Agent Guidelines: - Scope: Only code from current task (Beads task when active; invocation argument otherwis… | kept-as-one-line |
| §Agent Guidelines: - Output channels: CODE_REVIEW_RESULT block (always) + Beads comment (when active) — Decis… | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): **Before reviewing, detect whether the project uses Beads. Beads integration is optional.*… | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): 1. **Check for unstaged/staged files:** | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): git status | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): 2. **Detect Beads:** | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): # beads_active is true only when BOTH conditions hold | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): test -d .beads && bd --version >/dev/null 2>&1 | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): If both succeed: Beads is active. If either fails: Beads is not active. | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): 3. **Branch on `beads_active`:** | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): **If `beads_active` — run the Beads workflow (see `skills/beads-workflow/SKILL.md`):** | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): bd sync # Sync first | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): bd list # Check open/in-progress tasks | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): Two scenarios: | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): - **A. No Beads task exists for this review:** | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): ⚠️ No Beads task found for this work. | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): **Recommendation:** Create task to track this review: | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): `bd create "Code review - [component name]" --type subtask` | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): Continue with review anyway? (Y/n) | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): - **B. Review task exists (e.g., BD-49):** | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): bd claim BD-49 | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): bd sync # Sync so team sees you're reviewing | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): # Proceed with review... | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): # (After review complete, see "Output Decision" section below) | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): **If NOT `beads_active` — skip the Beads workflow silently:** | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): - Do not run `bd sync` or `bd list` | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): - Do not prompt the user about creating a Beads task | kept-as-one-line |
| §Detect Beads Integration (FIRST STEP): - Proceed directly to Context Setup, using the invocation argument (or git diff target) as… | kept-as-one-line |
| §Context Setup (REQUIRED): **Standard Context Setup:** See `skills/context-setup/SKILL.md` | kept-as-one-line |
| §Context Setup (REQUIRED): - Locate project (auto-detect CLAUDE.md) | kept-as-one-line |
| §Context Setup (REQUIRED): - Load and validate CLAUDE.md | kept-as-one-line |
| §Context Setup (REQUIRED): - If `beads_active`: check Beads state (`bd list`) | kept-as-one-line |
| §Context Setup (REQUIRED): - Read git history | kept-as-one-line |
| §Context Setup (REQUIRED): - Report discovery | kept-as-one-line |
| §Context Setup (REQUIRED): **Code Reviewer-Specific Additions:** | kept-as-one-line |
| §Context Setup (REQUIRED): 1. **Load Review Task (conditional on `beads_active`)** | kept-as-one-line |
| §Context Setup (REQUIRED): - If `beads_active`: get review subtask from Beads (`bd show BD-49` or similar); verify SU… | kept-as-one-line |
| §Context Setup (REQUIRED): - If not: use the invocation argument (file list, directory, or diff target) as the review… | kept-as-one-line |
| §Context Setup (REQUIRED): 2. **Load Review Configuration** | kept-as-one-line |
| §Context Setup (REQUIRED): - Check for optional `REVIEW.md` in project root | kept-as-one-line |
| §Context Setup (REQUIRED): - If present: Read review-specific rules (severity overrides, focus areas, skip patterns) | kept-as-one-line |
| §Context Setup (REQUIRED): - If absent: Fall back to CLAUDE.md patterns only | kept-as-one-line |
| §Context Setup (REQUIRED): - `REVIEW.md` takes precedence over CLAUDE.md for review-specific settings | kept-as-one-line |
| §Context Setup (REQUIRED): 5. **Load Quality Criteria** | kept-as-one-line |
| §Context Setup (REQUIRED): - Read `skills/quality-checklist/SKILL.md` → standard criteria | kept-as-one-line |
| §Context Setup (REQUIRED): - Adapt to framework if applicable: | kept-as-one-line |
| §Context Setup (REQUIRED): - Error paths: See `skills/error-handling/SKILL.md` patterns section | on-demand:skills/error-handling/SKILL.md at Context Setup step 5 |
| §Context Setup (REQUIRED): - Tests: See `skills/unit-testing/SKILL.md` patterns section | on-demand:skills/unit-testing/SKILL.md at Context Setup step 5 |
| §Context Setup (REQUIRED): - Framework-specific (NestJS, Next.js, gateways, databases): use the matching stackpack@at… | kept-as-one-line |
| §Context Setup (REQUIRED): - TypeScript: Type safety from CLAUDE.md | kept-as-one-line |
| §Context Setup (REQUIRED): 6. **Validate CLAUDE.md Accuracy** | kept-as-one-line |
| §Context Setup (REQUIRED): - Check: Do documented patterns match actual codebase behavior? | kept-as-one-line |
| §Context Setup (REQUIRED): - Example: CLAUDE.md says "use Redux" but codebase uses Context API → FLAG MISMATCH | kept-as-one-line |
| §Context Setup (REQUIRED): - Use Context7 to verify library claims (see `skills/context7-lookup/SKILL.md` for 4-tier … | on-demand:skills/context7-lookup/SKILL.md at Context Setup step 6 |
| §Context Setup (REQUIRED): - If Context7 unavailable: Use fallback tiers (cached docs → CLAUDE.md → manual verificati… | on-demand:skills/context7-lookup/SKILL.md at Context Setup step 6 |
| §Context Setup (REQUIRED): - If mismatch found: Flag as MEDIUM issue with suggested CLAUDE.md update | kept-as-one-line |
| §Context Setup (REQUIRED): - If library claims unverified: Flag with confidence level (Tier 2: MEDIUM, Tier 3: LOW, T… | kept-as-one-line |
| §Review Process: **For ALL code (backend + frontend):** | kept-as-one-line |
| §Review Process: - **CLAUDE.md Validation:** Do documented patterns match implementation? | kept-as-one-line |
| §Review Process: - Example: CLAUDE.md says "use Drizzle ORM" but code uses Prisma → FLAG | kept-as-one-line |
| §Review Process: - Example: CLAUDE.md says "test coverage ≥ 85%" but actual is 65% → FLAG | kept-as-one-line |
| §Review Process: - **Pattern Consistency:** Does code follow same approach as similar files? | kept-as-one-line |
| §Review Process: - Example: Other guards use `canActivate()`, this one uses different pattern → FLAG | kept-as-one-line |
| §Review Process: - **Design System Enforcement:** | kept-as-one-line |
| §Review Process: - Flag: Raw `<button>` when `<Button>` from design system exists | kept-as-one-line |
| §Review Process: - Flag: Inline styles when styled-components/Tailwind expected | kept-as-one-line |
| §Review Process: - Flag: Hardcoded colors instead of theme tokens | kept-as-one-line |
| §Review Process: - **Accessibility (WCAG 2.1 AA):** | kept-as-one-line |
| §Review Process: - Flag: Images without alt text | kept-as-one-line |
| §Review Process: - Flag: Icon buttons without aria-label | kept-as-one-line |
| §Review Process: - Flag: Form inputs without labels | kept-as-one-line |
| §Review Process: - Flag: A click handler on a non-interactive element with no role, `tabIndex` and Enter/Sp… | kept-as-one-line |
| §Review Process: - Flag: Color contrast < 4.5:1 (verify with contrast checker if suspicious) | kept-as-one-line |
| §Review Process: - **Responsive Design:** | kept-as-one-line |
| §Review Process: - Flag: Fixed widths instead of fluid layouts | kept-as-one-line |
| §Review Process: - Flag: Custom breakpoints instead of theme breakpoints | kept-as-one-line |
| §Review Process: - Flag: Missing mobile-first approach (if in CLAUDE.md) | kept-as-one-line |
| §Review Process: - **Component Reusability:** | kept-as-one-line |
| §Review Process: - Flag: Duplicate UI structure (3+ times) → suggest extraction | kept-as-one-line |
| §Review Process: - **Type Safety:** | kept-as-one-line |
| §Review Process: - Flag: Untyped component props | kept-as-one-line |
| §Review Process: - Flag: Missing prop interfaces | kept-as-one-line |
| §Review Process: - Always available: `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md`, `ski… | on-demand:skills/error-handling/SKILL.md at Review Process step 3 BACKEND block (with unit-testing and monitoring-observability, each with its trigger) |
| §Review Process: **BLOCKING** (critical — must fix immediately): | kept-as-one-line |
| §Review Process: - Data loss or corruption risks | kept-as-one-line |
| §Review Process: - Authentication/authorization bypass | kept-as-one-line |
| §Review Process: - Production-breaking regressions | kept-as-one-line |
| §Review Process: **HIGH** (must fix before PASS): | kept-as-one-line |
| §Review Process: - Security issues (secrets, SQL injection, validation) | kept-as-one-line |
| §Review Process: - Type errors (implicit `any`, missing types) | kept-as-one-line |
| §Review Process: - Test coverage below threshold | kept-as-one-line |
| §Review Process: - Logic errors or crashes | kept-as-one-line |
| §Review Process: - Pattern violations from CLAUDE.md | kept-as-one-line |
| §Review Process: **MEDIUM** (should fix): | kept-as-one-line |
| §Review Process: - Unclear naming | kept-as-one-line |
| §Review Process: - Incomplete error handling | kept-as-one-line |
| §Review Process: - Inefficient algorithms | kept-as-one-line |
| §Review Process: - Pattern inconsistency | kept-as-one-line |
| §Review Process: **LOW** (nice to have): | kept-as-one-line |
| §Review Process: - Style improvements | kept-as-one-line |
| §Review Process: - Refactoring opportunities | kept-as-one-line |
| §Review Process: - Helpful comments | kept-as-one-line |
| §Review Process: 8. **Provide Specific Fixes** | kept-as-one-line |
| §Review Process: - Every issue: file:line + code snippet + suggestion | kept-as-one-line |
| §Review Process: - Show before/after (brief diff) | kept-as-one-line |
| §Review Process: - Explain rationale | kept-as-one-line |
| §Review Process: - Link to relevant skill if applicable | kept-as-one-line |
| §Review Process: 9. **Check for New Patterns** | kept-as-one-line |
| §Review Process: - Does code introduce pattern not in CLAUDE.md? | kept-as-one-line |
| §Review Process: - Is it reusable and worth documenting? | kept-as-one-line |
| §Review Process: - If yes: Propose to CLAUDE.md in the review output (and in the Beads comment when Beads i… | kept-as-one-line |
| §Review Process: - Example: "Consider adding `Guard Composition with Metadata` pattern to CLAUDE.md" | kept-as-one-line |
| §Review Process: - Use `skills/pattern-detector/SKILL.md` format | kept-as-one-line |
| §Rules: - **Decision required:** Always output PASS / FAIL / NEEDS_HUMAN | hook:SubagentStop[loomwright:code-reviewer] validate-code-review-result.py |
| §Rules: - **Specific feedback:** Every issue has file:line + code snippet + suggestion | kept-as-one-line |
| §Rules: - **Type safety:** Flag ALL missing types (no exceptions) | kept-as-one-line |
| §Rules: - **Security first:** Flag all security issues (even unlikely ones) | kept-as-one-line |
| §Rules: - **Test coverage:** Check against threshold from CLAUDE.md | kept-as-one-line |
| §Rules: - **Constructive tone:** Highlight strengths + feedback | kept-as-one-line |
| §Rules: - **Pattern proposals:** Flag only (use pattern-detector.md format) | kept-as-one-line |
| §Rules: - **Verify library usage:** When reviewing code using external libraries not in CLAUDE.md,… | on-demand:skills/context7-lookup/SKILL.md at Context Setup step 6 |
| §Pre-Review Checklist: - [ ] Beads detection run (`test -d .beads && bd --version`). If active: review task loade… | kept-as-one-line |
| §Pre-Review Checklist: - [ ] CLAUDE.md patterns read and understood | kept-as-one-line |
| §Pre-Review Checklist: - [ ] **CLAUDE.md patterns validated against actual code behavior** | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Code files to review identified | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Quality criteria loaded (`skills/quality-checklist/SKILL.md`) | kept-as-one-line |
| §Pre-Review Checklist: - [ ] **Domain-specific skills identified and loaded (frontend-ui vs backend)** | kept-as-one-line |
| §Pre-Review Checklist: - [ ] **UI/design-system patterns enforced (if frontend code)** | kept-as-one-line |
| §Pre-Review Checklist: - [ ] **LSP diagnostics checked for type errors (if available)** | kept-as-one-line |
| §Pre-Review Checklist: - [ ] **Library usage verified via Context7 for unknowns** | on-demand:skills/context7-lookup/SKILL.md at Context Setup step 6 |
| §Pre-Review Checklist: - [ ] ALL files/changes reviewed thoroughly | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Decision matrix applied (PASS / FAIL / NEEDS_HUMAN) | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Every issue has file:line + suggestion | kept-as-one-line |
| §Pre-Review Checklist: - [ ] CODE_REVIEW_RESULT block drafted (always required) | kept-as-one-line |
| §Pre-Review Checklist: - [ ] If Beads is active: comment template filled out and ready to post to the review task | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Type safety issues flagged completely | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Security issues flagged and prioritized | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Testing threshold verified | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Issues have file:line, specific descriptions, suggested fixes | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Strengths highlighted (not just problems) | kept-as-one-line |
| §Pre-Review Checklist: - [ ] New patterns flagged with severity and rationale | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Severity levels accurate (BLOCKING/HIGH/MEDIUM/LOW) | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Issue categories assigned (new / pre_existing / nit / drift); drift issues include `… | kept-as-one-line |
| §Pre-Review Checklist: - [ ] Focus on current review target (Beads task scope or invocation argument) | kept-as-one-line |
| §Pre-Review Checklist: - [ ] **Trigger set evaluated:** diff/invocation paths checked against trigger surfaces; m… | kept-as-one-line |
| §Pre-Review Checklist: - [ ] **Mode selected correctly:** if `trigger_paths_detected` non-empty → `review_mode = … | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): **If `beads_active`: update the Beads task (see `skills/beads-workflow/SKILL.md`).** | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): # Add decision as comment | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): bd comment BD-49 "Decision: PASS - All criteria met. Type safety ✓, Tests ≥80% ✓, Pattern … | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): # Close the review task | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): bd close BD-49 | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): # Sync to remote (unblocks next task for team) | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): bd sync | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): **Output to user:** | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): ✅ Review complete. BD-49 closed. | kept-as-one-line |
| §Close Review Task (FINAL STEP — conditional on `beads_active`): Next task **BD-50** (Add JWT tests) is now unblocked. | kept-as-one-line |

### Review subtasks are human-authored

~~~~text
> Note: Orchestrator no longer creates review subtasks automatically at any threshold (see `agents/orchestrator.md` §"Review Gate Policy"). Any Beads review subtask referenced below is human-authored — a person can still create one manually and invoke `/code-reviewer` against it; the Beads integration itself is unchanged.

- **Review scope:** Files/directories to review (from invocation argument, or from a human-created Beads review subtask when `.beads/` is present)
- **Project context:** `CLAUDE.md` (patterns, type safety, test threshold)
- **Review config:** Optional `REVIEW.md` (review-specific rules, severity overrides, skip patterns)
- **Beads task (optional):** Current review subtask (e.g., "BD-49: Code Review - JwtGuard") — only when `.beads/` is active
- **Code to review:** Git changes, specific files, or commit diff
- **Quality checklist:** `skills/quality-checklist/SKILL.md` criteria
~~~~

### Why the audit baseline is always read

~~~~text
These are appended on top of the per-trigger adjacency list. Rationale: every audit type can surface version or count drift, so authoritative surfaces (`plugin.json` and `marketplace.json` — both must agree per `scripts/validate-version.sh`) must always be read — not only when they are the trigger themselves.
~~~~

### Beads comment template

~~~~text
```markdown
## Code Review Decision: [PASS / FAIL / NEEDS_HUMAN]

### Summary
[1-2 sentence overview of review findings]

### Issues Found
[List each issue]
- **[BLOCKING/HIGH/MEDIUM/LOW]** [file:line] — [Issue title] `[new|pre_existing|nit|drift]` `(drift_kind: ...)` *(drift_kind required only when category=drift)*
  - Details: [What's wrong and why]
  - Suggestion: [How to fix with code example]
  - Reference: [Link to quality-checklist or skill if applicable]

### Blockers (if FAIL)
- [What must be fixed before re-review]

### Bug Issues (if NEEDS_HUMAN)
- Created: BD-[XX] [Issue title] (blocks this review)
- Created: BD-[YY] [Design decision]

### Pattern Proposals
- Suggest adding "[Pattern Name]" to CLAUDE.md (see skills/pattern-detector/SKILL.md)

### Strengths
[2-3 things the code does well]
```
~~~~

### Input format examples

~~~~text

### Input Format

```markdown
/code-reviewer src/auth/      # Review a directory
/code-reviewer src/auth/jwt.guard.ts   # Review specific file
/code-reviewer              # Review git unstaged changes (default)
```

When Beads is active (auto-detected):
```bash
bd claim BD-49    # Claim review subtask
# Review implementation from BD-48
/code-reviewer src/auth/jwt.guard.ts
# Output decision comment to BD-49 (see Close Beads Task step)
```

When Beads is not active: just pass the scope as an argument; the CODE_REVIEW_RESULT block is the sole output.
~~~~

### Example decisions

~~~~text
Example short PASS decision:
```markdown
## Code Review Decision: PASS

### Summary
JwtGuard implementation meets all quality criteria.

### Issues Found
None

### Strengths
- Proper error handling with UnauthorizedException
- Type safety with JWTPayload interface
- Comprehensive test coverage (85%)
- Follows established guard patterns

### Pattern Proposals
None
```

Example NEEDS_HUMAN with bug issues (note: NEEDS_HUMAN because the reviewer cannot
adjudicate the design question — a plain MEDIUM finding alone would be PASS-with-issues):
```markdown
## Code Review Decision: NEEDS_HUMAN

### Summary
Open design decision flagged for human judgment.

### Issues Found
- **MEDIUM** src/auth/refresh.ts:8 — Retry-on-failure vs fail-fast is an architectural choice
  - Details: Both are defensible here; CLAUDE.md documents neither. The reviewer cannot adjudicate.
  - Suggestion: Decide the policy; see skills/error-handling/SKILL.md retry/fail-fast patterns

### Bug Issues
- Created: BD-52 Design Review: Error Retry Policy (blocks this review)

### Pattern Proposals
None
```

~~~~

### Close Review Task commands

~~~~text
**If `beads_active`: update the Beads task (see `skills/beads-workflow/SKILL.md`).**

```bash
# Add decision as comment
bd comment BD-49 "Decision: PASS - All criteria met. Type safety ✓, Tests ≥80% ✓, Pattern match ✓"

# Close the review task
bd close BD-49

# Sync to remote (unblocks next task for team)
bd sync
```

**Output to user:**
```markdown
✅ Review complete. BD-49 closed.

Next task **BD-50** (Add JWT tests) is now unblocked.
```
~~~~

### Integration notes

~~~~text

### Integration Notes

- Used by `/code-reviewer` command; Beads integration is auto-detected (`.beads/` + `bd --version`)
- When Beads is active: comments posted directly to review subtask (BD-XX); decision gates task progression (PASS → unblock next task)
- When Beads is not active: CODE_REVIEW_RESULT block is the decision channel; callers (e.g., Supervisor Phase 4.5 self-heal) parse it directly
- FAIL requires fixes + re-review (in both modes)
- NEEDS_HUMAN creates bug issues when Beads is active; lists them in result output when not
- Skills linked throughout (not embedded)
- Context7 called on-demand for library validation
- LSP used for real-time type diagnostics when available
- REVIEW.md loaded for project-specific review rules (optional)
~~~~

### Preload decisions

- `quality-checklist` — kept (used every spawn because Review Process step 2 checks its criteria on every review, and the self-heal lens walks its Self-Heal Miss-Class Checklist).
- `context7-lookup` — moved → Read at Context Setup step 6 when CLAUDE.md lacks a library fact the review needs (the 4-tier fallback).
- `unit-testing` — moved → Read at Context Setup step 5 (and the Review Process step 3 BACKEND block) when the diff touches tests.
- `error-handling` — moved → Read at Context Setup step 5 (and the Review Process step 3 BACKEND block) when the diff touches error paths.
- `monitoring-observability` — moved → Read at Context Setup step 5 (and the Review Process step 3 BACKEND block) when the diff touches logging, metrics or tracing code.

## plan-reviewer

| removed line (short quote) | home |
|---|---|
| §Core Principles: - **Verify, don't assume:** Check every file path, dependency, and pattern claim against t… | kept-as-one-line |
| §Core Principles: - **Structured output:** Always produce a `PLAN_REVIEW_RESULT` block with decision, issues… | kept-as-one-line |
| §Core Principles: - **Conservative judgment:** When in doubt about parallelism safety or dependency correctn… | kept-as-one-line |
| §Core Principles: - **Read-only:** Never modify files — tools are limited to Read, Glob, Grep only | kept-as-one-line |
| §Inputs: - **Brief text:** The complete Supervisor-Ready Brief assembled by Launch Pad | kept-as-one-line |
| §Inputs: - **CLAUDE.md context:** Relevant project patterns, tech stack, directory structure (max 5… | kept-as-one-line |
| §Outputs: - **PLAN_REVIEW_RESULT** block with decision (PASS/FAIL/NEEDS_HUMAN), issues array, and su… | hook:SubagentStop[loomwright:plan-reviewer] validate-plan-review-result.py |
| §Critical Rules: - **Always verify file paths** — Glob/Read every path in the File Impact Map | kept-as-one-line |
| §Critical Rules: - **Always check CLAUDE.md patterns** — Read CLAUDE.md and compare against brief's approac… | kept-as-one-line |
| §20 Review Criteria: Check ALL criteria in order. For each, note whether it passes or has issues. Criterion 11 … | kept-as-one-line |
| §1. File Path Verification: **Check:** Do ALL file paths in the File Impact Map exist in the codebase? | kept-as-one-line |
| §1. File Path Verification: - For each "modify" path: `Read` or `Glob` to confirm it exists | kept-as-one-line |
| §1. File Path Verification: - For each "create" path: verify the parent directory exists (a new `docs/evidence/` paren… | kept-as-one-line |
| §1. File Path Verification: - Flag any path that doesn't exist and isn't explicitly marked as "create" | kept-as-one-line |
| §1. File Path Verification: **Sub-check (conditional — cited-line premise staleness):** when the brief contains a `###… | kept-as-one-line |
| §2. Pattern Alignment: **Check:** Do the skill references and approach match patterns documented in CLAUDE.md? | kept-as-one-line |
| §2. Pattern Alignment: - Read CLAUDE.md (or use provided context) | kept-as-one-line |
| §2. Pattern Alignment: - Compare tech stack, directory conventions, naming patterns against the brief | kept-as-one-line |
| §2. Pattern Alignment: - Verify skill references match the project's actual framework/language | kept-as-one-line |
| §3. Acceptance Criteria Quality: **Check:** Are all acceptance criteria testable in Given/When/Then format? | kept-as-one-line |
| §3. Acceptance Criteria Quality: - Each criterion must have a clear precondition, action, and expected outcome | kept-as-one-line |
| §3. Acceptance Criteria Quality: - Flag vague criteria ("should work properly", "handles errors") | kept-as-one-line |
| §3. Acceptance Criteria Quality: - Flag missing negative/edge cases if the goal implies them | kept-as-one-line |
| §3. Acceptance Criteria Quality: **Sub-check (conditional — `## Outcomes Rubric` quality):** Run this ONLY when the brief c… | kept-as-one-line |
| §3. Acceptance Criteria Quality: - **3–7 bullets** (flag fewer than 3 or more than 7) | kept-as-one-line |
| §3. Acceptance Criteria Quality: - Each bullet is a **positive, observable assertion** — not an aspiration (e.g. "should be… | kept-as-one-line |
| §3. Acceptance Criteria Quality: - Each bullet is **diff-checkable from the PR diff alone** — no reliance on external state… | kept-as-one-line |
| §3. Acceptance Criteria Quality: **Severity if the rubric is malformed:** MEDIUM (e.g. <3 or >7 bullets, non-observable asp… | kept-as-one-line |
| §4. Subtask Decomposition: **Check:** Does subtask count honor `skills/supervisor-readiness/SKILL.md` §"Decomposition… | kept-as-one-line |
| §4. Subtask Decomposition: - \> 1 subtask requires a `- **Split reason:** <reason>` line in `## Configuration`; missi… | kept-as-one-line |
| §4. Subtask Decomposition: - **Cross-check the reason's PREDICATE, not just its label** — a well-formed token on an u… | kept-as-one-line |
| §4. Subtask Decomposition: - \> 7 subtasks still FAILs (upper bound unchanged). | kept-as-one-line |
| §4. Subtask Decomposition: - Check each subtask maps to a coherent file group; flag subtasks that mix unrelated domai… | kept-as-one-line |
| §5. Dependency Correctness: **Check:** Would executing subtasks in the stated dependency order work? | kept-as-one-line |
| §5. Dependency Correctness: - Trace the dependency graph for cycles | kept-as-one-line |
| §5. Dependency Correctness: - Verify that blocked subtasks genuinely depend on their blockers (e.g., uses types/interf… | kept-as-one-line |
| §5. Dependency Correctness: - Flag unnecessary dependencies that could be parallelized | kept-as-one-line |
| §6. Parallelism Safety: **Check:** Are LAUNCHABLE subtasks truly independent? Any hidden file overlap? | kept-as-one-line |
| §6. Parallelism Safety: - Compare file lists between all LAUNCHABLE subtasks | kept-as-one-line |
| §6. Parallelism Safety: - Check for shared config files, shared test fixtures, shared module indexes | kept-as-one-line |
| §6. Parallelism Safety: - Verify overlap matrix is complete | kept-as-one-line |
| §6. Parallelism Safety: - **Single-subtask brief:** exactly one LAUNCHABLE subtask, zero pairs to compare — this c… | kept-as-one-line |
| §7. Skill References: **Check:** Are the referenced skills appropriate for each subtask? | kept-as-one-line |
| §7. Skill References: - Verify each skill file exists: `Glob` for `skills/{name}/SKILL.md` | kept-as-one-line |
| §7. Skill References: - Check skill matches the subtask's domain (e.g., error-handling for error paths, not fron… | kept-as-one-line |
| §7. Skill References: - Flag missing skill references for obvious domains | kept-as-one-line |
| §8. Risk Assessment: **Check:** Is the risk assessment reasonable? Are HIGH-impact risks identified? | kept-as-one-line |
| §8. Risk Assessment: - Check for obvious risks not mentioned (e.g., database migrations, breaking API changes, … | kept-as-one-line |
| §8. Risk Assessment: - Verify mitigation strategies exist for HIGH risks | kept-as-one-line |
| §8. Risk Assessment: - Flag missing risk section entirely | kept-as-one-line |
| §8. Risk Assessment: - If a `## Feasibility` section is present with CAUTION findings, verify they appear in Ri… | kept-as-one-line |
| §9. Completeness: **Check:** Are all required brief sections present and filled? | kept-as-one-line |
| §9. Completeness: **How:** Verify these sections exist and are non-empty: | kept-as-one-line |
| §9. Completeness: 1. Environment | kept-as-one-line |
| §9. Completeness: 2. Task (Goal + Problem Statement) | kept-as-one-line |
| §9. Completeness: 3. Acceptance Criteria | kept-as-one-line |
| §9. Completeness: 4. Subtask Structure | kept-as-one-line |
| §9. Completeness: 5. Parallelism Analysis | kept-as-one-line |
| §9. Completeness: 6. Skill References | kept-as-one-line |
| §9. Completeness: 7. Risk Assessment | kept-as-one-line |
| §9. Completeness: 8. Configuration | kept-as-one-line |
| §9. Completeness: 9. Handoff command | kept-as-one-line |
| §9. Completeness: **Note:** The `## Feasibility` section (Launch Pad v10.3+) is **optional** — its absence i… | kept-as-one-line |
| §9. Completeness: **Note:** The `Shared local services` line (within `## Environment`) is **optional** — its… | kept-as-one-line |
| §9. Completeness: **Note (single-subtask briefs):** `Subtask Structure` and `Parallelism Analysis` remain re… | kept-as-one-line |
| §10. Configuration: **Check:** Is the recommended worker count reasonable given the parallelism analysis? | kept-as-one-line |
| §10. Configuration: - Workers should not exceed the width of the **largest parallel batch** (not just the firs… | kept-as-one-line |
| §10. Configuration: - Workers should be 1-3 (max recommended); `Workers: 1` is valid for `Mode: single-agent` | kept-as-one-line |
| §10. Configuration: - Mode should match: `single-agent` for a 1-subtask brief, `parallel` if any batch has LAU… | kept-as-one-line |
| §11. Feasibility Section (Optional): **Check:** If the brief includes a `## Feasibility` section (Launch Pad v10.3+), is it wel… | kept-as-one-line |
| §11. Feasibility Section (Optional): - **If absent: skip silently — no issue emitted** (older briefs remain valid; fully backwa… | kept-as-one-line |
| §11. Feasibility Section (Optional): - If present: verify the verdict is one of `{GO, CAUTION, NO-GO (user override)}` | kept-as-one-line |
| §11. Feasibility Section (Optional): - If present with CAUTION findings: verify they appear in Risk Assessment | kept-as-one-line |
| §11. Feasibility Section (Optional): **Severity if failed (only when section is present):** | kept-as-one-line |
| §11. Feasibility Section (Optional): - LOW if malformed structure (verdict missing/invalid) | kept-as-one-line |
| §11. Feasibility Section (Optional): - MEDIUM if CAUTION findings not reflected in Risk Assessment | kept-as-one-line |
| §11. Feasibility Section (Optional): **Rule:** Absence is never an issue. This criterion only runs when the section exists. | kept-as-one-line |
| §12. Inter-Subtask Output Contracts: - For every subtask with non-empty `requires`, verify each entry's `from` references an ex… | kept-as-one-line |
| §12. Inter-Subtask Output Contracts: - Build a dependency DAG: for each `requires` entry on consumer C with `from: P`, add edge… | kept-as-one-line |
| §12. Inter-Subtask Output Contracts: - Verify any subtask with non-empty `requires` is marked **BLOCKED** in the parallelism an… | kept-as-one-line |
| §12. Inter-Subtask Output Contracts: - Reject vague provides entries (`"adds feature"`, `"updates code"`, free-text strings wit… | kept-as-one-line |
| §12. Inter-Subtask Output Contracts: - `external_requires` items must NOT appear as `from` references in any `requires` entry (… | kept-as-one-line |
| §12. Inter-Subtask Output Contracts: - **Single-subtask briefs:** a lone subtask has no siblings — `requires: []` is correct an… | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): **Check:** If the brief's `## Configuration` block contains a `Base Branch:` line, does th… | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): - Parse the `## Configuration` block. Look for a line matching `^- \*\*Base Branch:\*\* (.… | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): - If absent: skip this criterion silently — `Base Branch:` is optional and defaults to `ma… | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): - If present with value `main`: PASS this criterion (no further check needed). | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): - If present with any other value `<branch>`: verify the branch exists by checking the loc… | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): 1. **Try unpacked ref first:** `Glob` for `.git/refs/heads/<branch>` (the path is the lite… | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): 2. **Fall back to packed-refs:** if `.git/packed-refs` exists, `Read` it and search for a … | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): 3. If neither check finds the branch → FAIL the brief with a BLOCKING issue: | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): - severity: BLOCKING | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): section: "Configuration" | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): category: missing_field | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): description: "Base Branch '<branch>' does not exist locally — autonomous-loop iter N+1 can… | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): suggestion: "Run `git branch --list <branch>` to confirm the branch exists locally. If thi… | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): **Why a `Glob`/`Read`-only check is sufficient:** Plan Reviewer is structurally read-only … | kept-as-one-line |
| §13. Base Branch Validation (v14.0.0+, conditional): **Conditional:** Absent `Base Branch:` line → skip silently. Present and value is `main` →… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): **Check:** If the brief contains a `## Executable Acceptance` section (the System Twin gro… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): - **If the `## Executable Acceptance` section is absent: skip silently — no issue emitted*… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): - If present, classify each `- ` bullet between the `## Executable Acceptance` heading and… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): - If present with **only** `corpus-task:` / `qa-executor:` / `rule:` bullets: PASS this cr… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): - If present with **≥1 `cmd:` / bare bullet:** check whether the brief's `## Configuration… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): - **Plan Reviewer is structurally read-only (no `Bash`, no execution — see `disallowedTool… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): - **No syntactically well-formed stamp line found** → emit ONE `executable_acceptance` iss… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): - **A well-formed stamp line IS found** → emit the same `executable_acceptance` issue for … | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): - **NEEDS_HUMAN escalation:** ≥1 `cmd:` / bare bullet present AND NO well-formed stamp lin… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): - LOW (advisory/visibility): ≥1 `cmd:` / bare bullet present AND a well-formed stamp line … | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): **Why machine-authored briefs should carry no `cmd:` bullets:** the Launch Pad authoring c… | kept-as-one-line |
| §14. Executable Acceptance Trust Surface (v14.19.0+, conditional; content-keyed stamp gate added — red-team-hardening item 05): **Conditional:** Absent `## Executable Acceptance` section → skip silently. Present withou… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): **Check:** If the brief asserts that one of its lists/values is the *canonical source of t… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): - **TRIGGER (gate narrowly — only fire when BOTH halves hold):** | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): 1. The brief uses explicit canonical-source phrasing — "single source of truth", "canonica… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): 2. The brief **cites a source** — a file path or location (e.g. `plugin.json`, `skills/SKI… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): - **If either half is absent: skip silently — no issue emitted** (fully backward compatibl… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): - When triggered, **read the cited source** (Plan Reviewer is structurally read-only — use… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): - Compare each value the brief claims to match against the cited source's actual content. | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): - Flag any mismatch with concrete evidence: what was checked (which source path/lines), wh… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): - If the cited source is **unreadable** (path does not exist / cannot be opened), do not f… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): - LOW (advisory/default): canonical-source claim present but source unverifiable, OR a min… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): - MEDIUM: the cited source **is** readable AND a concrete value mismatch is found (brief r… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): - BLOCKING: a verified mismatch would break a gate or contract (e.g. the brief restates a … | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): **Conditional:** Absent canonical-source claim (no canonical phrasing, or no cited source)… | kept-as-one-line |
| §15. Canonical-List / Source-of-Truth Verification (v14.31.0+, conditional): **Scope boundary (not full drift coverage):** Criterion 15 catches *claims of canonicity* … | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): **Check:** Does every subtask contract block declare a `lanes:` list, does every lane path… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): **How:** the authoritative rule this criterion validates against is `skills/supervisor-rea… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): - **Conditional gate (mirrors Criterion 12):** if the brief's Environment section declares… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): - **1. `lanes:` presence.** Every subtask with a contract block MUST declare a non-empty `… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): - **2. Path resolution.** For every lane path glob, verify it resolves: `Glob` the literal… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): - **3. Same-wave overlap (the reachability test — NOT "no direct `requires` edge").** Buil… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): - BLOCKING: a same-wave lane overlap is detected (check 3) — this is the actual divergent-… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): - HIGH: a subtask with a contract block declares no `lanes:` list at all (not even `lanes:… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): - MEDIUM: a lane path resolves to neither an existing file nor an existing parent director… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): **Conditional:** `legacy_brief: true`, or no contract blocks present → skip silently (mirr… | kept-as-one-line |
| §16. Lane Declaration Validation (v15.20.0+, conditional): **Note (visibility vs. preservation — do not over-scope this criterion):** the Lane Declar… | kept-as-one-line |
| §20. Acceptance Evidence Location (conditional): **Why:** FINALIZE writes the PR body from a fixed template before Phase 4.5 runs (`skills/… | kept-as-one-line |
| §Decision Matrix: \| Only MEDIUM/LOW issues, design approach unambiguous, AND no Criterion 14 or 17c NEEDS_HU… | kept-as-one-line |
| §Decision Matrix: \| Criterion 17c finds an advisory-rule contradiction with no well-formed `Rule override:` … | kept-as-one-line |
| §Decision Matrix: \| Criterion 14 finds ≥1 `cmd:`/bare Executable Acceptance bullet with NO well-formed `## C… | kept-as-one-line |

### Base Branch issue example and why Glob/Read suffices

~~~~text
**How:**

- Parse the `## Configuration` block. Look for a line matching `^- \*\*Base Branch:\*\* (.+)$` (or the unbolded variant `^Base Branch:\s*(.+)$`).
- If absent: skip this criterion silently — `Base Branch:` is optional and defaults to `main`. Emit no issue.
- If present with value `main`: PASS this criterion (no further check needed).
- If present with any other value `<branch>`: verify the branch exists by checking the local refs:
  1. **Try unpacked ref first:** `Glob` for `.git/refs/heads/<branch>` (the path is the literal branch name, slashes preserved). If found and `Read`-able, the branch exists locally → PASS.
  2. **Fall back to packed-refs:** if `.git/packed-refs` exists, `Read` it and search for a line ending with `refs/heads/<branch>`. If found → PASS.
  3. If neither check finds the branch → FAIL the brief with a BLOCKING issue:
     ```yaml
     - severity: BLOCKING
       section: "Configuration"
       category: missing_field
       description: "Base Branch '<branch>' does not exist locally — autonomous-loop iter N+1 cannot stack on it. Confirmed by checking .git/refs/heads/<branch> and .git/packed-refs; neither contained the branch."
       suggestion: "Run `git branch --list <branch>` to confirm the branch exists locally. If this brief is for autonomous-loop iter N+1, ensure iter N completed and its feature branch is checked out / fetched."
     ```

**Why a `Glob`/`Read`-only check is sufficient:** Plan Reviewer is structurally read-only (`disallowedTools: Bash`). The `.git/refs/heads/` directory layout and `.git/packed-refs` format are git-public and stable. A branch is either unpacked (file in `refs/heads/`) or packed (line in `packed-refs`); checking both covers every reachable local branch. Branches that exist only on the remote (not yet fetched) intentionally FAIL — autonomous-loop iter N+1 requires the parent branch to be locally checked out, so this is the correct behavior.
~~~~

### Criterion 14 severity rationale

~~~~text
**Severity if failed:**

- **NEEDS_HUMAN escalation:** ≥1 `cmd:` / bare bullet present AND NO well-formed stamp line found. The issue itself carries `severity: LOW` (the enum has no `NEEDS_HUMAN` value), but this condition forces the OVERALL `PLAN_REVIEW_RESULT.decision` to **NEEDS_HUMAN** via a dedicated Decision Matrix row (see below) — NOT via the generic BLOCKING/HIGH→FAIL mapping (FAIL would block save entirely; NEEDS_HUMAN allows explicit human override, which is the correct outcome here: a human may review the bullets right now and choose "Override and save", or Launch Pad's Phase 6 `approve-and-stamp`/`strip-cmd-bullets` flow resolves it directly).
- LOW (advisory/visibility): ≥1 `cmd:` / bare bullet present AND a well-formed stamp line exists. The decision is unaffected — the brief still saves under the normal PASS rules.

**Why machine-authored briefs should carry no `cmd:` bullets:** the Launch Pad authoring convention (`skills/supervisor-readiness/SKILL.md` §"`## Executable Acceptance`", `agents/launch-pad.md` Phase 5) directs Launch Pad to emit only `corpus-task:` bullets. A `cmd:` bullet in a Launch-Pad-authored brief is therefore an authoring-convention violation as well as a trust-surface finding — note both in the issue's `description` when you can tell the brief was machine-authored. A machine-authored brief never carries the stamp by construction, so it will hit the NEEDS_HUMAN escalation above unless a human has since approved-and-stamped it.

**Conditional:** Absent `## Executable Acceptance` section → skip silently. Present without `cmd:`/bare bullets → PASS silently. Present with `cmd:`/bare bullets AND a well-formed stamp → LOW `executable_acceptance` issue, decision unaffected. Present with `cmd:`/bare bullets and NO well-formed stamp → LOW `executable_acceptance` issue that forces decision `NEEDS_HUMAN` per the Decision Matrix.
~~~~

### Criterion 15 scope boundary

~~~~text
**Scope boundary (not full drift coverage):** Criterion 15 catches *claims of canonicity* — it fires only when a brief both uses canonical phrasing **and** cites a source. It is **not** a general count/version/restated-list drift detector: a brief that plainly restates a canonical value without asserting canonicity (e.g. "updates the 14-agent / 18-command counts in `plugin.json`") does **not** trigger it. That broader restated-value-drift class — including the kind that causes post-merge review churn — is caught by the **Code Reviewer `consistency_audit`**, `scripts/check-doc-currency.sh`, and human review, **not** by this criterion. The narrow trigger is intentional (it keeps false positives near zero); do not mistake a PASS here for "no restated-value drift anywhere."
~~~~

### Criterion 16 visibility vs preservation

~~~~text
**Note (visibility vs. preservation — do not over-scope this criterion):** the Lane Declaration Schema draws a hard line between sequential lane sharing granting *visibility* (a downstream subtask can see an upstream subtask's committed file) versus *preservation* (nothing re-verifies the upstream subtask's `provides` symbol still resolves after the downstream edit). Criterion 16 checks lane declarations and same-wave collisions only — it does NOT check preservation; that remains a manual authoring/review discipline per the schema's own explicit statement, and Plan Reviewer must not silently expand this criterion's scope to cover it.
~~~~

### Why Criterion 20 exists

~~~~text
**Why:** FINALIZE writes the PR body from a fixed template before Phase 4.5 runs (`skills/async-orchestration/finalize.md` §"PR Body Template"), and no Phase 4.5 or `/review-pr` fix task can edit it: fixers only commit to the branch. Brief conformance judges each criterion from the diff (`agents/code-reviewer.md` step 5a), and the PR body is not in the diff. A criterion that only the PR body can satisfy fails every heal round until a human edits the body by hand (#511).
~~~~

### Integration notes

~~~~text
---

## Integration Notes

- Spawned by Launch Pad agent during Phase 5.5 (not user-facing)
- Structurally read-only: tools limited to Read/Glob/Grep, Bash in disallowedTools
- No permissionMode set (ignored for plugin-distributed agents)
- Output validated by SubagentStop hook in hooks.json
- Max 3 spawns per Launch Pad session (retry on FAIL)
~~~~

### Preload decisions

- No `skills:` entries at base — nothing preloaded, nothing to move. The prompt Reads `skills/supervisor-readiness/SKILL.md` sections on demand at the criteria that name them (3, 4, 9, 16, 18, 19), unchanged.

## execute-manager

| removed line (short quote) | home |
|---|---|
| frontmatter: - state-management | on-demand:skills/state-management/SKILL.md at Step 1 item 6 when resume context is provided, or when a Context-Keeper call reports a state-file error |
| §Mission: **No per-subtask LLM reviewer is spawned above threshold (or on the Sequential Path).** Th… | kept-as-one-line |
| §Critical Rules: - **No System Twin contract WRITE here (worktree-safety invariant):** The Execute Manager … | script:write-system-contract.sh |
| §Critical Rules: │ EXECUTE MANAGER (Phase 3 Only) │ | kept-as-one-line |
| §Critical Rules: │ Owns: poll loop, worker lifecycle, CK coordination │ | kept-as-one-line |
| §Critical Rules: │ Budget: 60 tool calls │ | kept-as-one-line |
| §Critical Rules: │ No per-subtask reviewer — deterministic gate only; Phase 4.5 │ | kept-as-one-line |
| §Critical Rules: │ (Supervisor, post-FINALIZE) is the sole LLM review lens │ | kept-as-one-line |
| §Critical Rules: └──────────┬──────────────────────────────────┬─────────────────────┘ | kept-as-one-line |
| §Critical Rules: │ Context │ │ Worker A │ | kept-as-one-line |
| §Critical Rules: │ Keeper │ │ (background) │ | kept-as-one-line |
| §Critical Rules: │ (on-demand)│ │ git worktree A │ | kept-as-one-line |
| §Critical Rules: │ Worker B │ | kept-as-one-line |
| §Critical Rules: │ (background) │ | kept-as-one-line |
| §Critical Rules: │ git worktree B │ | kept-as-one-line |
| §Step 1: Parse Inputs: 6. If resume context provided: restore active worker/worktree tracking | kept-as-one-line |
| §Step 4: Poll Loop: # --- v12 outputs_verified gate (the per-subtask gate — no reviewer is | kept-as-one-line |
| §Step 4: Poll Loop: # spawned above threshold or on the Sequential Path; Phase 4.5 is the | kept-as-one-line |
| §Step 4: Poll Loop: # sole LLM gate. See agents/orchestrator.md §"Review Gate Policy" (also | kept-as-one-line |
| §Step 4: Poll Loop: # cited in this file's Mission section, which is the single citation of | kept-as-one-line |
| §Step 4: Poll Loop: # AGENT_GUIDELINES.md §"Review Counter-Pressure Rule" in this file). --- | kept-as-one-line |
| §Step 4: Poll Loop: # Parse WORKER_RESULT block from TaskOutput (or summary). It may be ABSENT | kept-as-one-line |
| §Step 4: Poll Loop: # (dead worker / turn-limit exit — after the crash retry-once in Error | kept-as-one-line |
| §Step 4: Poll Loop: # Handling has already been spent); absence is NOT a pass. | kept-as-one-line |
| §Step 4: Poll Loop: # The gate's INPUT is the TREE, not the worker's claim (v15.71.0). Re-run the | kept-as-one-line |
| §Step 4: Poll Loop: # ONE implementation of the three provides checks against the worktree the | kept-as-one-line |
| §Step 4: Poll Loop: # worker wrote to — exactly ONE extra Bash call per subtask (+1 below). | kept-as-one-line |
| §Step 4: Poll Loop: # brief_path = the SAME pointer you handed this worker at spawn: the | kept-as-one-line |
| §Step 4: Poll Loop: # in-progress brief on the `job:` path, or the `.supervisor/requirements/ | kept-as-one-line |
| §Step 4: Poll Loop: # {slug}-plan.md` plan file in `/supervisor task:` no-brief mode. | kept-as-one-line |
| §Step 4: Poll Loop: # subtask_id = the bare token after `Subtask` in the brief's contract anchor | kept-as-one-line |
| §Step 4: Poll Loop: # (`1`, `12`) — NOT the state.md task_id / Beads id / slug: any other shape | kept-as-one-line |
| §Step 4: Poll Loop: # returns subtask_not_found and checkpoints every run (stderr lists the anchors). | kept-as-one-line |
| §Step 4: Poll Loop: # Decision D1 routing (brief 2026-09-13-manager-reverifies-provides). | kept-as-one-line |
| §Step 4: Poll Loop: # brief_unreadable / subtask_not_found / jq_missing / bad_args ⇒ CHECKPOINT on EVERY | kept-as-one-line |
| §Step 4: Poll Loop: # path — a gate that cannot read its contract does not pass. | kept-as-one-line |
| §Step 4: Poll Loop: # no_contracts ⇒ CHECKPOINT on the `job:` path UNLESS the brief's | kept-as-one-line |
| §Step 4: Poll Loop: # `## Environment` declares `legacy_brief: true` (Plan Reviewer Criterion | kept-as-one-line |
| §Step 4: Poll Loop: # 12's own opt-out, reused — not a new flag). On legacy_brief and in | kept-as-one-line |
| §Step 4: Poll Loop: # no-brief mode (plan file with no contract blocks, or criteria passed | kept-as-one-line |
| §Step 4: Poll Loop: # inline with no pointer file) record it and fall through to today's | kept-as-one-line |
| §Step 4: Poll Loop: # self-report gate — nothing new gates there (owner decision R1). | kept-as-one-line |
| §Step 4: Poll Loop: # No self-report to retain AND no disk verdict — the crash retry is already | kept-as-one-line |
| §Step 4: Poll Loop: # spent (Error Handling). Never record this as "disk verified": checkpoint. | kept-as-one-line |
| §Step 4: Poll Loop: # regardless of the worker's `status` (completed / partial / failed) or of | kept-as-one-line |
| §Step 4: Poll Loop: # its outputs_gap — an item missing ON DISK escalates via the adjudication | kept-as-one-line |
| §Step 4: Poll Loop: # CHECKPOINT. Do NOT mark this subtask complete. | kept-as-one-line |
| §Step 4: Poll Loop: check_run: v.check_run // "worker self-report (Step 5.5)"} # the script's command + exit-c… | kept-as-one-line |
| §Step 4: Poll Loop: # Do NOT mark this subtask complete. Do NOT continue with this subtask. | kept-as-one-line |
| §Step 4: Poll Loop: # Supervisor will resolve adjudication and instruct next action. | kept-as-one-line |
| §Step 4: Poll Loop: # Reachable ONLY with disk.source == "verify-provides.sh" (the unverifiable + | kept-as-one-line |
| §Step 4: Poll Loop: # ABSENT cell checkpointed above). Every item present on disk but no | kept-as-one-line |
| §Step 4: Poll Loop: # WORKER_RESULT to read — never a silent no-op: record it, then continue to | kept-as-one-line |
| §Step 4: Poll Loop: # the tests/lint half of the gate with tests_run/tests_passed UNKNOWN (run the | kept-as-one-line |
| §Step 4: Poll Loop: # worktree's test/lint command via Bash yourself, +1, and forward its outcome | kept-as-one-line |
| §Step 4: Poll Loop: # in record_worker_result with error: "worker_result_absent"). | kept-as-one-line |
| §Step 4: Poll Loop: # Worker claims a gap the disk does not show — disk wins (provides_mismatch | kept-as-one-line |
| §Step 4: Poll Loop: # already recorded above): fall through to the tests/lint half; the worker's | kept-as-one-line |
| §Step 4: Poll Loop: # own status/error/tests still travel in record_worker_result unchanged. | kept-as-one-line |
| §Step 4: Poll Loop: # `partial` with NO provides gap is the Step 1 carve-out (agents/worker.md | kept-as-one-line |
| §Step 4: Poll Loop: # §"Status / outputs_gap invariant"): the worker could not read / act on its | kept-as-one-line |
| §Step 4: Poll Loop: # spec. Disk cannot contradict an unread spec, so this is NOT a disk-wins | kept-as-one-line |
| §Step 4: Poll Loop: # cell — it keeps the pre-v15.71.0 stop (both consumers agree: status != | kept-as-one-line |
| §Step 4: Poll Loop: # completed with no disk contradiction ⇒ stop). | kept-as-one-line |
| §Step 4: Poll Loop: # subtask's lanes own (rows on a sibling's code are left to Phase 4.5, which runs every ro… | kept-as-one-line |
| §Step 4: Poll Loop: # {main_checkout} = the absolute project root this Execute Manager runs in (not the worktr… | kept-as-one-line |
| §Step 4: Poll Loop: # The cache path is MAIN-CHECKOUT ABSOLUTE (`.supervisor/` does not exist inside the workt… | kept-as-one-line |
| §Step 4: Poll Loop: # PER SUBTASK: its hashes are this worktree's, so Phase 4.5's integrated run (shared | kept-as-one-line |
| §Step 4: Poll Loop: # `{stem}.tsv`) never reuses a `held` computed before a sibling's edits landed. | kept-as-one-line |
| §Step 4: Poll Loop: # <plugin root> = the same install root as the verify-provides.sh call above. Bounded: Bas… | kept-as-one-line |
| §Step 4: Poll Loop: # --- Lane-collision gate (D6, v15.20.0) — `out_of_lane` itself is a | kept-as-one-line |
| §Step 4: Poll Loop: # REPORT-ONLY field (agents/worker.md §"Output Format") and never blocks a | kept-as-one-line |
| §Step 4: Poll Loop: # subtask on its own. This check fires ONLY when an out-of-lane path lands | kept-as-one-line |
| §Step 4: Poll Loop: # inside a SIBLING subtask's declared `lanes:` AND that sibling is NOT | kept-as-one-line |
| §Step 4: Poll Loop: # reachable from this subtask in either direction in the `requires` DAG | kept-as-one-line |
| §Step 4: Poll Loop: # (the reachability test — skills/supervisor-readiness/SKILL.md | kept-as-one-line |
| §Step 4: Poll Loop: # §"Lane Declaration Schema"). A sequentially-ordered shared file (either | kept-as-one-line |
| §Step 4: Poll Loop: # subtask reachable from the other) is legal and is never flagged — this | kept-as-one-line |
| §Step 4: Poll Loop: # is the divergent-interface hazard the check exists to catch, surfaced | kept-as-one-line |
| §Step 4: Poll Loop: # through the SAME adjudication surface as the outputs_gap gate above, | kept-as-one-line |
| §Step 4: Poll Loop: # inventing no new escalation path. --- | kept-as-one-line |
| §Step 4: Poll Loop: # matching_siblings: ALL other subtasks (from the brief's Subtask | kept-as-one-line |
| §Step 4: Poll Loop: # Contracts already read at Inputs) whose declared `lanes:` contain a | kept-as-one-line |
| §Step 4: Poll Loop: # glob matching `path`. Empty if no sibling owns it (an unowned path is | kept-as-one-line |
| §Step 4: Poll Loop: # not a collision — just an out-of-lane write with no colliding owner). | kept-as-one-line |
| §Step 4: Poll Loop: # PLURAL, deliberately: Criterion 16 forbids lane overlap only between | kept-as-one-line |
| §Step 4: Poll Loop: # MUTUALLY-UNREACHABLE pairs, so two sequentially-ordered siblings may | kept-as-one-line |
| §Step 4: Poll Loop: # legally declare overlapping lanes over the same path. A third subtask | kept-as-one-line |
| §Step 4: Poll Loop: # writing that path can therefore match several owners at once, and be | kept-as-one-line |
| §Step 4: Poll Loop: # ordered against some of them but not others. Checking only the first | kept-as-one-line |
| §Step 4: Poll Loop: # match found would make escalation depend on brief/iteration order — | kept-as-one-line |
| §Step 4: Poll Loop: # implementation-defined per run. Escalate if ANY matching sibling is | kept-as-one-line |
| §Step 4: Poll Loop: # unordered relative to {subtask_id}; a single ordered owner does not | kept-as-one-line |
| §Step 4: Poll Loop: # clear the path. | kept-as-one-line |
| §Step 4: Poll Loop: direction over the requires DAG (transitive closure — the | kept-as-one-line |
| §Step 4: Poll Loop: reachability/"same-wave" test): | kept-as-one-line |
| §Step 4: Poll Loop: # COLLECT, do not emit yet. Emitting here would end the round on the | kept-as-one-line |
| §Step 4: Poll Loop: # FIRST collision found, so any remaining out_of_lane paths — and any | kept-as-one-line |
| §Step 4: Poll Loop: # second unordered owner of this same path — would be silently dropped | kept-as-one-line |
| §Step 4: Poll Loop: # from the checkpoint and only resurface on a later re-run. That also | kept-as-one-line |
| §Step 4: Poll Loop: # made WHICH collision got reported depend on iteration order, the exact | kept-as-one-line |
| §Step 4: Poll Loop: # order-dependence the plural `matching_siblings` above was introduced to | kept-as-one-line |
| §Step 4: Poll Loop: # remove. `colliding_lanes` is documented as a batchable evidence array | hook:SubagentStop[loomwright:execute-manager] validate-execute-result.py |
| §Step 4: Poll Loop: # (the lane analogue of `missing_outputs[]`); the control flow must | kept-as-one-line |
| §Step 4: Poll Loop: # actually fill it. | kept-as-one-line |
| §Step 4: Poll Loop: # Discriminator — REQUIRED here. Supervisor branches on this, never | kept-as-one-line |
| §Step 4: Poll Loop: # on the free-text `reason` (agents/supervisor.md §"Adjudication | kept-as-one-line |
| §Step 4: Poll Loop: # Handling"). Absent means `requires_gap` for pre-v15.20.0 | kept-as-one-line |
| §Step 4: Poll Loop: # checkpoints, so a lane collision MUST say so explicitly or it is | kept-as-one-line |
| §Step 4: Poll Loop: # adjudicated with the wrong option set and the wrong Option-C | kept-as-one-line |
| §Step 4: Poll Loop: # failure reason. | kept-as-one-line |
| §Step 4: Poll Loop: # Evidence array — the lane analogue of the requires-gap gate's | kept-as-one-line |
| §Step 4: Poll Loop: # `missing_outputs[]`. REQUIRED whenever adjudication_required is | kept-as-one-line |
| §Step 4: Poll Loop: # true: scripts/validate-execute-result.py rule 6a accepts EITHER | hook:SubagentStop[loomwright:execute-manager] validate-execute-result.py |
| §Step 4: Poll Loop: # missing_outputs OR colliding_lanes, and rejects a checkpoint | hook:SubagentStop[loomwright:execute-manager] validate-execute-result.py |
| §Step 4: Poll Loop: # carrying neither. (A lane collision has no producer/consumer | kept-as-one-line |
| §Step 4: Poll Loop: # `requires` edge, so it has no missing_outputs to report — emitting | kept-as-one-line |
| §Step 4: Poll Loop: # this shape without colliding_lanes made the checkpoint fail its own | hook:SubagentStop[loomwright:execute-manager] validate-execute-result.py |
| §Step 4: Poll Loop: # SubagentStop hook.) | kept-as-one-line |
| §Step 4: Poll Loop: # EVERY entry in `collisions`, not just the first — one checkpoint per | kept-as-one-line |
| §Step 4: Poll Loop: # pause, carrying the complete evidence set. | kept-as-one-line |
| §Step 4: Poll Loop: # Summarize the SET. Naming a single path/sibling here would contradict | kept-as-one-line |
| §Step 4: Poll Loop: # a multi-entry colliding_lanes above; Supervisor reads the array for | hook:SubagentStop[loomwright:execute-manager] validate-execute-result.py |
| §Step 4: Poll Loop: # specifics and this string only for the human-facing headline. | kept-as-one-line |
| §Step 4: Poll Loop: # Lane-specific options. Deliberately NOT the requires-gap gate's four | kept-as-one-line |
| §Step 4: Poll Loop: # verbatim strings: "producer", "remediation subtask whose provides | kept-as-one-line |
| §Step 4: Poll Loop: # covers the missing items", and "remove the failing requires entry" | kept-as-one-line |
| §Step 4: Poll Loop: # are all defined over a producer/consumer edge that does not exist | kept-as-one-line |
| §Step 4: Poll Loop: # here. Same A-B-C-D shape, lane semantics. | kept-as-one-line |
| §Step 4: Poll Loop: # No colliding sibling found for any out_of_lane path: fall through. | kept-as-one-line |
| §Step 4: Poll Loop: # out_of_lane -> record_worker_result -> `## Worker Results`. | kept-as-one-line |
| §Step 4: Poll Loop: # NOT an EXECUTE_RESULT field (docs/RESULT_SCHEMAS.md §EXECUTE_RESULT) | kept-as-one-line |
| §Step 4: Poll Loop: # (see record_worker_result below) but never blocks completion — a | kept-as-one-line |
| §Step 4: Poll Loop: # legitimate cross-cutting edit with no live sibling claim is not an error. | kept-as-one-line |
| §Step 4: Poll Loop: # --- Terminal-lifecycle-event join (completion authority, v15.80.0) — a | kept-as-one-line |
| §Step 4: Poll Loop: # SECOND, INDEPENDENT condition alongside the outputs_verified disk gate | kept-as-one-line |
| §Step 4: Poll Loop: # above; do NOT fold into it or reuse its record_decision strings. | kept-as-one-line |
| §Step 4: Poll Loop: # (.supervisor/requirements/orca-derived/02-completion-authority.md). | kept-as-one-line |
| §Step 4: Poll Loop: # `provides` present ON DISK (the gate above) proves the files exist; it | kept-as-one-line |
| §Step 4: Poll Loop: # says NOTHING about whether the agent that was supposed to write them | kept-as-one-line |
| §Step 4: Poll Loop: # ever actually terminated — a partial/interrupted run, a stale artifact, | kept-as-one-line |
| §Step 4: Poll Loop: # or a still-running worker whose files land early would otherwise be | kept-as-one-line |
| §Step 4: Poll Loop: # marked complete regardless. Reached ONLY when the code above did NOT | kept-as-one-line |
| §Step 4: Poll Loop: # already `skip_to_next_iteration` (missing on disk, unverifiable-and- | kept-as-one-line |
| §Step 4: Poll Loop: # unroutable, or the Step 1 partial-carve-out) — i.e. disk already says | kept-as-one-line |
| §Step 4: Poll Loop: # N/N present for {subtask_id}. | kept-as-one-line |
| §Step 4: Poll Loop: # {session_log_path} = `.supervisor/logs/{session_id}.jsonl` at the main | kept-as-one-line |
| §Step 4: Poll Loop: # checkout (`git worktree list --porcelain` first entry — the SAME file | kept-as-one-line |
| §Step 4: Poll Loop: # `emit-progress-event.sh`/`emit-agent-identity.sh` write to), using the | script:emit-progress-event.sh |
| §Step 4: Poll Loop: # session_id already recorded in this run's state file. {worker_id} is | kept-as-one-line |
| §Step 4: Poll Loop: # the SAME Task-returned id already tracked for this worker (the value | kept-as-one-line |
| §Step 4: Poll Loop: # `emit-agent-identity.sh` captured as `agent_id` on this worker's spawn). | kept-as-one-line |
| §Step 4: Poll Loop: # (Naming note: the source requirement, orca-derived/02-completion- | kept-as-one-line |
| §Step 4: Poll Loop: # authority.md, drafted this mechanism under the working name | kept-as-one-line |
| §Step 4: Poll Loop: # `outputs_verified_contradicted`; the decision string this gate actually | kept-as-one-line |
| §Step 4: Poll Loop: # records below is `provides_present_agent_unsettled`, kept distinct from | kept-as-one-line |
| §Step 4: Poll Loop: # `provides_mismatch` per that requirement's own corrected problem | kept-as-one-line |
| §Step 4: Poll Loop: # statement — see docs/RESULT_SCHEMAS.md §"Completion authority join".) | kept-as-one-line |
| §Step 4: Poll Loop: # NOT an error, NOT an escalation — the expected transient state for a | kept-as-one-line |
| §Step 4: Poll Loop: # worker whose files land before its final result message does. Do NOT | kept-as-one-line |
| §Step 4: Poll Loop: # mark this subtask complete; do NOT call record_worker_result yet. | kept-as-one-line |
| §Step 4: Poll Loop: # Re-poll: this worker is left tracked as running so the NEXT iteration | kept-as-one-line |
| §Step 4: Poll Loop: # re-checks both the disk gate and this join. | kept-as-one-line |
| §Step 4: Poll Loop: # `settle.rejected_stops > 0` (v15.83.0) names a second cause of the same | kept-as-one-line |
| §Step 4: Poll Loop: # verdict: the worker DID stop, but validate-worker-result.py rejected | kept-as-one-line |
| §Step 4: Poll Loop: # its WORKER_RESULT (`decision: block`) and the runtime told it to | kept-as-one-line |
| §Step 4: Poll Loop: # continue — the `subtask_complete` row it left is `rejected: true` and | kept-as-one-line |
| §Step 4: Poll Loop: # is NOT terminal (docs/RESULT_SCHEMAS.md §"Completion authority join"). | kept-as-one-line |
| §Step 4: Poll Loop: # Same handling: re-poll. If the verdict never clears within | kept-as-one-line |
| §Step 4: Poll Loop: # max_iterations, the worker was forced to stop at the runtime's | kept-as-one-line |
| §Step 4: Poll Loop: # continuation cap with a still-malformed result — the checkpoint that | kept-as-one-line |
| §Step 4: Poll Loop: # follows should carry rejected_stops so the operator resumes it via | kept-as-one-line |
| §Step 4: Poll Loop: # SendMessage with the validator's reason instead of re-running cold. | kept-as-one-line |
| §Step 4: Poll Loop: # `jq_missing` / `bad_args` — the join itself could not run. Fail | kept-as-one-line |
| §Step 4: Poll Loop: # CLOSED the same way an unroutable verify-provides.sh `unverifiable` | kept-as-one-line |
| §Step 4: Poll Loop: # does: do not silently treat an unrun check as a pass. | kept-as-one-line |
| §Step 4: Poll Loop: # settle.status == "settled" (provides on disk present AND a terminal row | kept-as-one-line |
| §Step 4: Poll Loop: # exists) → BOTH conditions now hold; proceed exactly as pre-this-change. | kept-as-one-line |
| §Step 4: Poll Loop: # This worker's terminal row was a `subtask_complete` with | kept-as-one-line |
| §Step 4: Poll Loop: # `result_block_present: false`, an `agent_lifecycle: failed` row, or | kept-as-one-line |
| §Step 4: Poll Loop: # (automate-followups/33) only an `agent_lifecycle: ended` row for a | kept-as-one-line |
| §Step 4: Poll Loop: # worker — e.g. a turn-limit stop on a blocking return — | kept-as-one-line |
| §Step 4: Poll Loop: # log it with the agent_id VISIBLE so an operator can SendMessage it to | kept-as-one-line |
| §Step 4: Poll Loop: # resume (memory `subagents-hit-turn-limit-resume-via-sendmessage`) | kept-as-one-line |
| §Step 4: Poll Loop: # instead of re-running the subtask cold. Record-only: this item only | kept-as-one-line |
| §Step 4: Poll Loop: # SURFACES the id, it does not implement the resume, and it does NOT | kept-as-one-line |
| §Step 4: Poll Loop: # block completion — record_worker_result below still runs unchanged. | kept-as-one-line |
| §Step 4: Poll Loop: # Record worker result (direct call — de-batched, one call per event; | kept-as-one-line |
| §Step 4: Poll Loop: # the retired batching wrapper is gone, this call is not). Forwards the | kept-as-one-line |
| §Step 4: Poll Loop: # worker's `out_of_lane`, `deviations`, AND `not_verified` fields unconditionally — | kept-as-one-line |
| §Step 4: Poll Loop: # all three are REPORT-ONLY and land in `## Worker Results`; `deviations` is later | kept-as-one-line |
| §Step 4: Poll Loop: # read by Phase 4.5's step 1g (skills/self-heal-advisory/SKILL.md) as an advisory to | kept-as-one-line |
| §Step 4: Poll Loop: # the review lens only; `not_verified` is later aggregated into the FINALIZE PR body's | kept-as-one-line |
| §Step 4: Poll Loop: # optional `## Not verified` section and the done brief's completion tail (harness-port/04… | kept-as-one-line |
| §Step 5: Output Result: Note: `review_decision: PASS` below is set once the deterministic `outputs_verified` gate | kept-as-one-line |
| §Step 5: Output Result: (plus tests/lint) has passed for that subtask — no per-subtask LLM reviewer runs above | kept-as-one-line |
| §Step 5: Output Result: threshold, so the field no longer reflects an LLM decision; it is retained verbatim here | kept-as-one-line |
| §Step 5: Output Result: because `docs/RESULT_SCHEMAS.md` (owned by a different subtask) still defines it as requir… | kept-as-one-line |
| §Progress State: Only the `## Session` block (session_id/branch/status/phase) is derived — it is written by… | script:emit-progress-event.sh |

### Why no per-subtask reviewer survives

~~~~text
**No per-subtask LLM reviewer is spawned above threshold (or on the Sequential Path).** The deterministic `outputs_verified` gate (Step 2b's pre-spawn check, and the v12 gate in the poll loop below) plus the worker's self-reported tests/lint results IS the per-subtask gate; the integrated Phase 4.5 review (run once, holistically, by the Supervisor after FINALIZE) is the sole LLM gate. This also removes the worktree-isolation cross-file false-positive class: a per-subtask reviewer cannot see sibling worktrees, so it used to produce false `NEEDS_HUMAN` on producer/consumer contracts that only Phase 4.5's merged view can actually verify. See `agents/orchestrator.md` §"Review Gate Policy" (authoritative) and `AGENT_GUIDELINES.md` §"Review Counter-Pressure Rule" for why no per-subtask lens survives here.
~~~~

### System Twin write refusal and architecture diagram

~~~~text
- **No System Twin contract WRITE here (worktree-safety invariant):** The Execute Manager and its workers run inside linked git worktrees, and `scripts/write-system-contract.sh` **refuses to run from a worktree (exit 3)** — its sole-writer / pinned-CWD guard. So neither the Execute Manager nor any worker writes `.supervisor/twin/`. The System Twin contract builder runs **only** in the Supervisor's Phase 4.5 SELF_HEAL completion tail, from the pinned repo-root CWD (the main checkout), after Phase 4 FINALIZE has removed the worktrees. See `agents/supervisor.md` §"Phase 4.5 … System Twin contract builder" and `docs/ARCHITECTURE_CONTRACTS.md` §"System Twin homing contract".

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                 EXECUTE MANAGER (Phase 3 Only)                    │
│  Owns: poll loop, worker lifecycle, CK coordination               │
│  Budget: 60 tool calls                                            │
│  No per-subtask reviewer — deterministic gate only; Phase 4.5     │
│  (Supervisor, post-FINALIZE) is the sole LLM review lens          │
└──────────┬──────────────────────────────────┬─────────────────────┘
           │                                  │
    ┌──────▼──────┐                    ┌──────▼──────────────┐
    │  Context    │                    │  Worker A            │
    │  Keeper     │                    │  (background)        │
    │  (on-demand)│                    │  git worktree A       │
    └─────────────┘                    └───────────────────────┘
                                        ┌───────────────────────┐
                                        │  Worker B             │
                                        │  (background)         │
                                        │  git worktree B       │
                                        └───────────────────────┘
```
~~~~

### Why every matching sibling is checked

~~~~text
          # matching_siblings: ALL other subtasks (from the brief's Subtask
          # Contracts already read at Inputs) whose declared `lanes:` contain a
          # glob matching `path`. Empty if no sibling owns it (an unowned path is
          # not a collision — just an out-of-lane write with no colliding owner).
          # PLURAL, deliberately: Criterion 16 forbids lane overlap only between
          # MUTUALLY-UNREACHABLE pairs, so two sequentially-ordered siblings may
          # legally declare overlapping lanes over the same path. A third subtask
          # writing that path can therefore match several owners at once, and be
          # ordered against some of them but not others. Checking only the first
          # match found would make escalation depend on brief/iteration order —
          # implementation-defined per run. Escalate if ANY matching sibling is
          # unordered relative to {subtask_id}; a single ordered owner does not
          # clear the path.
~~~~

### Why collisions are collected before emitting

~~~~text
               direction over the requires DAG (transitive closure — the
               reachability/"same-wave" test):
              # COLLECT, do not emit yet. Emitting here would end the round on the
              # FIRST collision found, so any remaining out_of_lane paths — and any
              # second unordered owner of this same path — would be silently dropped
              # from the checkpoint and only resurface on a later re-run. That also
              # made WHICH collision got reported depend on iteration order, the exact
              # order-dependence the plural `matching_siblings` above was introduced to
              # remove. `colliding_lanes` is documented as a batchable evidence array
              # (the lane analogue of `missing_outputs[]`); the control flow must
              # actually fill it.
~~~~

### Why the lane-collision discriminator and evidence array are required

~~~~text
                # Discriminator — REQUIRED here. Supervisor branches on this, never
                # on the free-text `reason` (agents/supervisor.md §"Adjudication
                # Handling"). Absent means `requires_gap` for pre-v15.20.0
                # checkpoints, so a lane collision MUST say so explicitly or it is
                # adjudicated with the wrong option set and the wrong Option-C
                # failure reason.
~~~~

### Why the lane-collision discriminator and evidence array are required (evidence)

~~~~text
                # Evidence array — the lane analogue of the requires-gap gate's
                # `missing_outputs[]`. REQUIRED whenever adjudication_required is
                # true: scripts/validate-execute-result.py rule 6a accepts EITHER
                # missing_outputs OR colliding_lanes, and rejects a checkpoint
                # carrying neither. (A lane collision has no producer/consumer
                # `requires` edge, so it has no missing_outputs to report — emitting
                # this shape without colliding_lanes made the checkpoint fail its own
                # SubagentStop hook.)
                # EVERY entry in `collisions`, not just the first — one checkpoint per
                # pause, carrying the complete evidence set.
~~~~

### Why lane-specific adjudication options

~~~~text
                # Lane-specific options. Deliberately NOT the requires-gap gate's four
                # verbatim strings: "producer", "remediation subtask whose provides
                # covers the missing items", and "remove the failing requires entry"
                # are all defined over a producer/consumer edge that does not exist
                # here. Same A-B-C-D shape, lane semantics.
~~~~

### Lane-collision fall-through and completion-authority rationale

~~~~text
        # No colliding sibling found for any out_of_lane path: fall through.
        # out_of_lane -> record_worker_result -> `## Worker Results`.
        # NOT an EXECUTE_RESULT field (docs/RESULT_SCHEMAS.md §EXECUTE_RESULT)
        # (see record_worker_result below) but never blocks completion — a
        # legitimate cross-cutting edit with no live sibling claim is not an error.

      # --- Terminal-lifecycle-event join (completion authority, v15.80.0) — a
      # SECOND, INDEPENDENT condition alongside the outputs_verified disk gate
      # above; do NOT fold into it or reuse its record_decision strings.
      # (.supervisor/requirements/orca-derived/02-completion-authority.md).
      # `provides` present ON DISK (the gate above) proves the files exist; it
      # says NOTHING about whether the agent that was supposed to write them
      # ever actually terminated — a partial/interrupted run, a stale artifact,
      # or a still-running worker whose files land early would otherwise be
      # marked complete regardless. Reached ONLY when the code above did NOT
      # already `skip_to_next_iteration` (missing on disk, unverifiable-and-
      # unroutable, or the Step 1 partial-carve-out) — i.e. disk already says
      # N/N present for {subtask_id}.
~~~~

### Completion-authority naming note

~~~~text
      # {session_log_path} = `.supervisor/logs/{session_id}.jsonl` at the main
      # checkout (`git worktree list --porcelain` first entry — the SAME file
      # `emit-progress-event.sh`/`emit-agent-identity.sh` write to), using the
      # session_id already recorded in this run's state file. {worker_id} is
      # the SAME Task-returned id already tracked for this worker (the value
      # `emit-agent-identity.sh` captured as `agent_id` on this worker's spawn).
      # (Naming note: the source requirement, orca-derived/02-completion-
      # authority.md, drafted this mechanism under the working name
      # `outputs_verified_contradicted`; the decision string this gate actually
      # records below is `provides_present_agent_unsettled`, kept distinct from
      # `provides_mismatch` per that requirement's own corrected problem
      # statement — see docs/RESULT_SCHEMAS.md §"Completion authority join".)
~~~~

### State-trace note: why the reviewer-polling arm was removed

~~~~text
      # NOTE: the `## Session` block (session_id/branch/status/phase) is
      # separately derived by the hook-triggered emitter
      # (scripts/emit-progress-event.sh, wired at the loomwright:worker
      # SubagentStop hook) and projected by scripts/build-state.sh — that
      # mechanism does NOT populate `## Worker Results`, which is what the
      # record_worker_result call above is for.

      # --- Subtask complete: outputs_verified gate PASSED, no reviewer spawned ---
      # This gate (above) plus the worker's self-reported tests/lint results
      # (already captured in `result` and forwarded via record_worker_result:
      # tests_run/tests_passed/status/error) IS the per-subtask gate — nothing
      # further to spawn or poll for this subtask. The subtask is now eligible
      # for the "Launch newly launchable subtasks" section below (dependency
      # materialization, Step 2a/2b, was already keyed on producer completion,
      # never on a reviewer decision, so removing the reviewer does not change
      # what "newly launchable" means).
      #
      # STATE-TRACE NOTE (why the old reviewer-polling arm is REMOVED, not
      # re-pointed): the v15.16.0 fix's `record_review` calls on the reviewer's
      # FAIL(attempt 3) and NEEDS_HUMAN terminal branches were bookkeeping for a
      # *reviewer decision* (PASS/FAIL/NEEDS_HUMAN) that no longer exists above
      # threshold. The deterministic gate above has only two outcomes — gap
      # (adjudication CHECKPOINT, handled above) or no-gap (this branch) — and
      # neither is a "review decision" to log via `record_review`; the adjudication
      # CHECKPOINT already carries its own reason/missing_outputs. There is no
      # equivalent terminal state to re-point those calls onto, so they are
      # deleted along with the reviewer they described. The surviving poll-loop
      # bookkeeping (`results_found`, `idle_streak`, `poll_interval`) is untouched:
      # all three are still set correctly by the worker loop above (lines setting
      # them on worker completion) and consumed by the shared idle back-off and
      # budget-check sections below, which never depended on the reviewer arm.
      # Phase 4.5 (Supervisor, post-FINALIZE, integrated review of the merged
      # feature branch) is the sole LLM gate for this diff — see
      # agents/orchestrator.md §"Review Gate Policy".
~~~~

### No per-subtask reviewer results to read

~~~~text
### No Per-Subtask Reviewer Results To Read

No reviewer is spawned per-subtask above threshold (or on the Sequential Path) — there is
no `CODE_REVIEW_RESULT` channel to read here. The `outputs_verified` gate above (parsed from
the worker's own `WORKER_RESULT`/summary) plus tests/lint IS the per-subtask gate; the
integrated Phase 4.5 review (Supervisor, post-FINALIZE) is the sole LLM gate for this diff.

~~~~

### Integration notes

~~~~text
---

## Integration Notes

- Internal agent — never invoked directly by users
- Spawned by Supervisor during Phase 3 (EXECUTE) for multi-subtask workflows
- NOT used for the Single-Agent Path — Supervisor handles it inline
- Returns compressed result to Supervisor (~200-300 tokens)
- Supervisor uses EXECUTE_RESULT data directly for Phase 4 (FINALIZE)
- On EXECUTE_CHECKPOINT: Supervisor spawns a fresh Execute Manager for remaining subtasks
- Worktree paths and branch names in output ensure worker work is never lost

~~~~

### Preload decisions

- `async-orchestration` — kept (used every spawn because the spawn, poll-loop, pre-spawn gate and adjudication protocol it defines run on every Phase 3 pass).
- `context-summarization` — kept (used every spawn because every completed worker result is compressed with its Worker Result / Execute Manager templates before it is recorded and returned).
- `state-management` — moved → Read at Step 1 item 6 when resume context is provided (its checkpoint/resume protocol and state-file schema), or when a Context-Keeper call reports a state-file error. All state writes go through Context-Keeper, so a fresh run never needs it.

## worker

| removed line (short quote) | home |
|---|---|
| §Mission: Implement a single subtask in an isolated git worktree. Operate independently, follow acce… | kept-as-one-line |
| §Mission: - **Isolated execution:** Work ONLY within the assigned worktree path | kept-as-one-line |
| §Mission: - **Criteria-driven:** Implement exactly what the acceptance criteria specify | kept-as-one-line |
| §Mission: - **Test-aware:** Run tests if test infrastructure exists in the worktree | kept-as-one-line |
| §Mission: - **Structured output:** Always produce a `WORKER_RESULT` block | kept-as-one-line |
| §Mission: - **Skill-guided:** Follow referenced skill files for implementation patterns | kept-as-one-line |
| §Mission: - **Retry-aware:** On retry, read previous issues and fix specifically | kept-as-one-line |
| §Inputs: - **Subtask ID / Task ID:** Task identifier (e.g., BD-XXa or descriptive slug) | kept-as-one-line |
| §Inputs: - **Title:** Brief description of what to implement | kept-as-one-line |
| §Inputs: - **Acceptance criteria:** A bounded (≤200-char) summary PLUS a pinned main-checkout absol… | kept-as-one-line |
| §Inputs: - **Lane declaration:** (optional — present when the brief has a Subtask Contracts block) … | kept-as-one-line |
| §Inputs: - **Context digest pointer:** (optional) a pointer to the per-job `CONTEXT_DIGEST` artifac… | kept-as-one-line |
| §Inputs: - **Session-log pointer:** the path to `.supervisor/logs/{session_id}.jsonl` (MAIN-CHECKOU… | script:checkpoint.sh |
| §Inputs: - **Subtask ordinal:** (optional) your 1-based position in the brief's subtask list, e.g. … | kept-as-one-line |
| §Inputs: - **Skill references:** Relevant SKILL.md files for guidance | kept-as-one-line |
| §Inputs: - **Retry context:** (optional) Previous review issues to address on retry | kept-as-one-line |
| §Inputs: - **Project context:** (optional) Key patterns from CLAUDE.md | kept-as-one-line |
| §Inputs: - **WORKER_RESULT block:** Structured implementation summary | kept-as-one-line |
| §Inputs: - **Modified files:** In the worktree only | kept-as-one-line |
| §Inputs: - **Test results:** If tests were run | kept-as-one-line |
| §Critical Rules: - **No agent spawning:** Don't spawn subagents — work independently | kept-as-one-line |
| §Critical Rules: - **No state file access:** Don't read/write the Supervisor state file | kept-as-one-line |
| §Critical Rules: - **No self-promotion:** Any follow-up requirement/story/task file you create carries `## … | kept-as-one-line |
| §Critical Rules: - **Shared local services are read-only:** When your spawn prompt carries a `Shared local … | kept-as-one-line |
| §Critical Rules: - **Complete or fail:** Always produce a WORKER_RESULT, even on failure | kept-as-one-line |
| §Critical Rules: - **Write summary file:** Always write `.worker-summary.md` in worktree (parallel mode) or… | kept-as-one-line |
| §Critical Rules: - **Turn budget — 100 turns (advisory):** Your `maxTurns` ceiling is 100 (sized from a mea… | kept-as-one-line |
| §Step 1: Understand Context: 1. Read the acceptance criteria carefully — open the pinned main-checkout brief path from … | kept-as-one-line |
| §Step 1: Understand Context: 2. If skill references provided, read relevant SKILL.md files | kept-as-one-line |
| §Step 1: Understand Context: 3. If project context provided, note key patterns | kept-as-one-line |
| §Step 1: Understand Context: 4. If retry context provided, understand what failed previously | kept-as-one-line |
| §Step 1: Understand Context: 1. List project structure in the worktree | kept-as-one-line |
| §Step 1: Understand Context: 2. Read files related to the subtask | kept-as-one-line |
| §Step 1: Understand Context: 3. Identify existing patterns and conventions | kept-as-one-line |
| §Step 1: Understand Context: 4. Understand the codebase before making changes | kept-as-one-line |
| §Step 3: Plan Implementation: 1. Determine what files to create/modify | kept-as-one-line |
| §Step 3: Plan Implementation: 2. Plan changes to meet each acceptance criterion | kept-as-one-line |
| §Step 3: Plan Implementation: 3. If retry: plan fixes for previously identified issues | kept-as-one-line |
| §Step 3: Plan Implementation: 4. Keep changes minimal and focused | kept-as-one-line |
| §Step 4: Implement: 1. Make changes in the worktree | kept-as-one-line |
| §Step 4: Implement: 2. Follow existing patterns and conventions | kept-as-one-line |
| §Step 4: Implement: 3. Follow referenced skill files for guidance | kept-as-one-line |
| §Step 4: Implement: 4. Ensure type safety and proper error handling | kept-as-one-line |
| §Step 4: Implement: 5. **Optional advisory checkpoints:** at any of five moments — you confirm a hypothesis, r… | script:checkpoint.sh |
| §Step 5: Verify: 1. Check for type errors (if TypeScript/typed language) | kept-as-one-line |
| §Step 5: Verify: - When available, run LSP diagnostics on your modified files and fix real type errors you … | kept-as-one-line |
| §Step 5: Verify: 2. Run tests if test infrastructure exists: | kept-as-one-line |
| §Step 5: Verify: - Check for test runner: `package.json` scripts, `pytest.ini`, `go.mod`, etc. | kept-as-one-line |
| §Step 5: Verify: - Waiting on a long run: redirect its output to a file (`> <file> 2>&1`), never pipe it in… | kept-as-one-line |
| §Step 5: Verify: - If a test fails, diagnose before you fix: add one `test: <test name> — <code wrong \| ass… | kept-as-one-line |
| §Step 5: Verify: 4. **House-rule self-check:** run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/worker-rule-selfche… | script:verify-provides.sh |
| §Step 5: Verify: 5. **Self-review before hand-back (required unless `status: failed` or `no_changes: true`)… | hook:SubagentStop[loomwright:worker] validate-worker-result.py |
| §Step 5: Verify: - `checklist` — walk `skills/quality-checklist/SKILL.md` §"Self-Heal Miss-Class Checklist"… | kept-as-one-line |
| §Step 5: Verify: - `repro` — for each load-bearing claim you introduced (a guard fires, a race is closed, a… | kept-as-one-line |
| §Step 5: Verify: - `sweep` — for every claim, count or behaviour you changed, grep the repo for the OLD wor… | kept-as-one-line |
| §Step 5: Verify: - `invariants` — re-read each entry of the brief's `## Touched-file invariants` for the fi… | kept-as-one-line |
| §Step 5: Verify: Entry shape: `{part: checklist\|repro\|sweep\|invariants, result: held\|fixed\|n/a, evidence: <… | kept-as-one-line |
| §Step 5.5: Write Self-Summary File: Write a compressed summary file to the worktree before outputting the final result: | kept-as-one-line |
| §Step 5.5: Write Self-Summary File: 1. **File location:** | kept-as-one-line |
| §Step 5.5: Write Self-Summary File: - **Parallel mode (worktree):** `{worktree_path}/.worker-summary.md` | kept-as-one-line |
| §Step 5.5: Write Self-Summary File: - **Inline mode (project root):** `.supervisor/worker-summaries/{subtask_id}.md` (create d… | kept-as-one-line |
| §Step 5.5: Write Self-Summary File: 2. **Content:** Same fields as WORKER_RESULT but max 200 tokens | kept-as-one-line |
| §Step 5.5: Write Self-Summary File: 3. **Write BEFORE** the final WORKER_RESULT output | kept-as-one-line |
| §Step 5.5: Write Self-Summary File: 4. If the file cannot be written, still output WORKER_RESULT normally and include the lite… | kept-as-one-line |
| §WORKER_SUMMARY: **Why:** The Execute Manager reads this file (~200 tokens) instead of parsing full TaskOut… | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): After the `.worker-summary.md` file has been written and BEFORE emitting the final `WORKER… | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): 1. **Re-read the subtask's `provides:` list** from the spawn brief. | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): 2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/verify-provides.sh" <pinned brief path> <your … | script:verify-provides.sh |
| §After writing the summary file: verify own `provides:` (Outputs Verification): 3. `outputs_verified` is an array of `{kind, path, name?, status: "present" \| "missing"}` … | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): 4. `outputs_gap` is a comma-separated string naming the missing items (e.g., `"src/foo.ts:… | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): 5. **Set the WORKER_RESULT `status` field** based on the verification outcome: | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): - `completed` if `outputs_gap` is empty (all promised outputs present). | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): - `partial` if `outputs_gap` is non-empty (worker did not deliver all promised outputs — i… | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): - `failed` for crash / unfixable error (unchanged from prior behavior). | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): - Exception: the Step 1 brief-unreadable case returns `partial` with `outputs_gap: ""` (se… | kept-as-one-line |
| §After writing the summary file: verify own `provides:` (Outputs Verification): If the brief has no contract block (the script says `no_contracts`), report `outputs_verif… | kept-as-one-line |
| §Step 5.65: Record out-of-lane writes (lane gate — REPORT-ONLY, D6): After Step 5.5's outputs verification, check every path you touched against your OWN subta… | kept-as-one-line |
| §Step 5.65: Record out-of-lane writes (lane gate — REPORT-ONLY, D6): 1. **Re-read your subtask's own `lanes:` list** from the spawn brief's Subtask Contracts (… | kept-as-one-line |
| §Step 5.65: Record out-of-lane writes (lane gate — REPORT-ONLY, D6): 2. **For each path in `files_modified` + `files_created` + `files_deleted`** (the same lis… | kept-as-one-line |
| §Step 5.65: Record out-of-lane writes (lane gate — REPORT-ONLY, D6): 3. **Build `out_of_lane`** as an array of the touched paths that matched NO glob in your o… | kept-as-one-line |
| §Step 5.65: Record out-of-lane writes (lane gate — REPORT-ONLY, D6): 4. **This is REPORT-ONLY and a SEPARATE field from `outputs_gap` — it NEVER influences `st… | kept-as-one-line |
| §Step 5.65: Record out-of-lane writes (lane gate — REPORT-ONLY, D6): 5. You do not need to know whether an out-of-lane path collides with a sibling's lane, or … | kept-as-one-line |
| §Step 5.6: Optional — propose project-memory candidates: OPTIONALLY populate the additive `memory_candidates` field on WORKER_RESULT with short, on… | kept-as-one-line |
| §Step 5.6: Optional — propose project-memory candidates: CRITICAL constraints: | kept-as-one-line |
| §Step 5.6: Optional — propose project-memory candidates: - **Workers run in isolated git worktrees and MUST NEVER write project memory** (never cal… | kept-as-one-line |
| §Step 5.6: Optional — propose project-memory candidates: - **Never put secrets, credentials, tokens, or PII in `memory_candidates`** — durable stru… | kept-as-one-line |
| §Step 5.6: Optional — propose project-memory candidates: - **Omit the field entirely when nothing is memory-worthy** (the common case). | kept-as-one-line |
| §Step 5.6: Optional — propose project-memory candidates: - **Also echo any `memory_candidates` into your `.worker-summary.md`** (the summary file y… | kept-as-one-line |
| §Step 5.6: Optional — propose project-memory candidates: > **Where candidates go (current scope):** proposed candidates surface in your `WORKER_RES… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: OPTIONALLY populate the additive `deviations` field on WORKER_RESULT with short, bounded s… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - `plan:` — you did something other than the subtask literally said, and why. Example: `pl… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - `edge:` — an edge case the brief never named and how you handled it. Example: `edge: emp… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - `open:` — a decision the brief left open and which way you went. Example: `open: retry b… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - `test:` — a failing test's diagnosis (`test: <name> — <code wrong \| assertion wrong \| en… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - `rule:` — a failing stamped `must` house rule, produced only by `worker-rule-selfcheck.s… | script:worker-rule-selfcheck.sh |
| §Step 5.7: Optional — record deviations from plan: An entry without one of these prefixes is read as `other:` by consumers and is **never rej… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: CRITICAL constraints: | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - **`deviations` is THIS run's transient story — the opposite of `memory_candidates`, whic… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - **Never put secrets, credentials, tokens, or PII in `deviations`** — same rule as `memor… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - **REPORT-ONLY** — `deviations` never influences `status`, `outputs_gap`, or any other WO… | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - **Omit the field entirely when there is nothing to report** (the common case). | kept-as-one-line |
| §Step 5.7: Optional — record deviations from plan: - **Also echo any `deviations` into your `.worker-summary.md`** (the summary file you alre… | kept-as-one-line |
| §Step 5.75: Record what you could not verify (honest limits): For every surface your diff affects that you did NOT observe running — a rendered `<route>… | kept-as-one-line |
| §Step 5.75: Record what you could not verify (honest limits): This is CONDITIONALLY MANDATORY, unlike the OPTIONAL `memory_candidates`/`deviations` fiel… | kept-as-one-line |
| §Step 5.75: Record what you could not verify (honest limits): - **Never put secrets, credentials, tokens, or PII in `not_verified`** — same rule as `mem… | kept-as-one-line |
| §Step 5.75: Record what you could not verify (honest limits): - **REPORT-ONLY** — `not_verified` never influences `status`, `outputs_gap`, or any other … | kept-as-one-line |
| §Step 5.75: Record what you could not verify (honest limits): - **Also echo any `not_verified` items into your `.worker-summary.md`** under a dedicated … | kept-as-one-line |
| §WORKER_RESULT: **Status / outputs_gap invariant (v2):** | kept-as-one-line |
| §WORKER_RESULT: - `status: completed` ⇔ `outputs_gap == ""` (all `provides` items verified present) | kept-as-one-line |
| §WORKER_RESULT: - `status: partial` ⇔ `outputs_gap != ""` (one or more `provides` items missing) | kept-as-one-line |
| §WORKER_RESULT: - `status: failed` ⇒ crash / unfixable error; `outputs_verified` and `outputs_gap` should … | kept-as-one-line |
| §WORKER_RESULT: - **Carve-out (brief unreadable / insufficient spec, per Step 1):** a worker that could no… | kept-as-one-line |
| §WORKER_RESULT: - **`out_of_lane` is a SEPARATE, REPORT-ONLY field and is NOT part of this invariant.** It… | kept-as-one-line |
| §WORKER_RESULT: - **`deviations` is ALSO a SEPARATE, REPORT-ONLY field, same independence as `out_of_lane`… | kept-as-one-line |
| §WORKER_RESULT: - **`not_verified` is ALSO a SEPARATE, REPORT-ONLY field, same independence as `out_of_lan… | kept-as-one-line |
| §WORKER_RESULT: **Read-only subtasks (`no_changes`):** when your subtask is read-only or verify-only (coun… | hook:SubagentStop[loomwright:worker] validate-worker-result.py |
| §WORKER_RESULT: **v1 backward compatibility:** Older artifacts emitted `schema_version: 1` and omitted `ou… | kept-as-one-line |
| §Retry Protocol: When spawned with retry context (previous review failed): | kept-as-one-line |
| §Retry Protocol: 1. **Read previous issues** from the retry context | kept-as-one-line |
| §Retry Protocol: 2. **Focus fixes** on the specific issues identified | kept-as-one-line |
| §Retry Protocol: 3. **Don't refactor** unrelated code during retry | kept-as-one-line |
| §Retry Protocol: 4. **Run the same tests** to verify fixes | kept-as-one-line |
| §Retry Protocol: 5. **Note in WORKER_RESULT** that this is a retry | kept-as-one-line |
| §Retry Protocol: **Retry context format (provided by Supervisor):** | kept-as-one-line |
| §Inline Execution Mode: When the Supervisor uses the Single-Agent or Sequential Path (no worktree): | kept-as-one-line |
| §Inline Execution Mode: - The worktree path is the project root | kept-as-one-line |
| §Inline Execution Mode: - Everything else works the same | kept-as-one-line |
| §Inline Execution Mode: - Output the same WORKER_RESULT format | kept-as-one-line |
| §Inline Execution Mode: - Write `.worker-summary.md` at `{worktree_path}/.worker-summary.md` (parallel mode) or `.… | kept-as-one-line |
| §Inline Execution Mode: Workers receive skill references from the Supervisor. Common skills: | kept-as-one-line |
| §Inline Execution Mode: \| Skill \| When Referenced \| | kept-as-one-line |
| §Inline Execution Mode: \|-------\|----------------\| | kept-as-one-line |
| §Inline Execution Mode: \| `skills/quality-checklist/SKILL.md` \| Pre-completion checks \| | kept-as-one-line |
| §Inline Execution Mode: \| `skills/unit-testing/SKILL.md` \| Test writing and structure \| | kept-as-one-line |
| §Inline Execution Mode: \| `skills/error-handling/SKILL.md` \| Error paths and exceptions \| | kept-as-one-line |
| §Inline Execution Mode: \| `skills/{domain}/SKILL.md` \| Framework/stack patterns (e.g., stackpack@atelier NestJS/Ne… | kept-as-one-line |
| §Error Handling: Before outputting WORKER_RESULT: | kept-as-one-line |
| §Error Handling: - [ ] All acceptance criteria addressed | kept-as-one-line |
| §Error Handling: - [ ] `self_review` carries all four parts (Step 5 item 5), unless `status: failed` or `no… | hook:SubagentStop[loomwright:worker] validate-worker-result.py |
| §Error Handling: - [ ] Changes are minimal and focused | kept-as-one-line |
| §Error Handling: - [ ] Existing patterns followed | kept-as-one-line |
| §Error Handling: - [ ] Type safety maintained | kept-as-one-line |
| §Error Handling: - [ ] Tests run (if infrastructure exists) | kept-as-one-line |
| §Error Handling: - [ ] No debug code or console.logs left | kept-as-one-line |
| §Error Handling: - [ ] No secrets or PII in code | kept-as-one-line |
| §Error Handling: - [ ] WORKER_RESULT block is complete and accurate | kept-as-one-line |
| §Error Handling: - [ ] Files only modified within worktree path | kept-as-one-line |

### Planning and implementation steps

~~~~text
1. Determine what files to create/modify
2. Plan changes to meet each acceptance criterion
3. If retry: plan fixes for previously identified issues
4. Keep changes minimal and focused
~~~~

### Why the summary file exists

~~~~text
**Why:** The Execute Manager reads this file (~200 tokens) instead of parsing full TaskOutput (~5,000+ tokens), preventing context pollution in the orchestration layer.

~~~~

### Where memory candidates go

~~~~text
OPTIONALLY populate the additive `memory_candidates` field on WORKER_RESULT with short, one-line strings capturing learnings about *this codebase* that are worth remembering across sessions. Only do so for facts that are **durable, reusable, and decision-changing** — and that are NOT already in `CLAUDE.md` (per the Memory Core Principle in `AGENT_GUIDELINES.md`). Examples: a non-obvious module boundary, a build/test invariant that surprised you, a convention enforced implicitly. Transient details (what you changed this run, ticket-specific notes) are NOT memory-worthy.

CRITICAL constraints:
- **Workers run in isolated git worktrees and MUST NEVER write project memory** (never call `write-project-memory.sh`) — a worktree write would be lost on worktree removal (red-team F1). Workers only PROPOSE candidate strings here; promotion to memory is human-gated and happens at the repo root.
- **Never put secrets, credentials, tokens, or PII in `memory_candidates`** — durable structural facts only.
- **Omit the field entirely when nothing is memory-worthy** (the common case).
- **Also echo any `memory_candidates` into your `.worker-summary.md`** (the summary file you already write) under a dedicated `## memory_candidates` heading, **one `- ` bullet per candidate string, verbatim** — so a later `/dreaming` reflection pass can collect them unambiguously. Omit the heading entirely when you have no candidates. This changes nothing about the WORKER_RESULT schema (stays v2).

> **Where candidates go (current scope):** proposed candidates surface in your `WORKER_RESULT` block for a human — or a future P4 reflection pass — to promote at the repo root via `write-project-memory.sh`. There is **no automatic Supervisor collection/promotion step yet** (deferred to P4); emitting them here is the v1 deliverable, not a dead end.
~~~~

### v1 backward compatibility

~~~~text
**v1 backward compatibility:** Older artifacts emitted `schema_version: 1` and omitted `outputs_verified` + `outputs_gap`. Consumers should accept v1 blocks (treating the two new fields as `[]` and `""` respectively) for legacy logs only — new emissions MUST be v2.
~~~~

### Schema reference

~~~~text
> **Schema reference:** See `docs/RESULT_SCHEMAS.md` for full validation rules.
~~~~

### Inline execution mode

~~~~text
When the Supervisor uses the Single-Agent or Sequential Path (no worktree):

- The worktree path is the project root
- Everything else works the same
- Output the same WORKER_RESULT format
- Write `.worker-summary.md` at `{worktree_path}/.worker-summary.md` (parallel mode) or `.supervisor/worker-summaries/{subtask_id}.md` (inline mode)

---

## Skill References

Workers receive skill references from the Supervisor. Common skills:

| Skill | When Referenced |
|-------|----------------|
| `skills/quality-checklist/SKILL.md` | Pre-completion checks |
| `skills/unit-testing/SKILL.md` | Test writing and structure |
| `skills/error-handling/SKILL.md` | Error paths and exceptions |
| `skills/{domain}/SKILL.md` | Framework/stack patterns (e.g., stackpack@atelier NestJS/Next.js/gateway/database skills when installed) |
~~~~

### Skill references and quality checklist

~~~~text
---

## Quality Checklist

Before outputting WORKER_RESULT:
- [ ] All acceptance criteria addressed
- [ ] `self_review` carries all four parts (Step 5 item 5), unless `status: failed` or `no_changes: true`
- [ ] Changes are minimal and focused
- [ ] Existing patterns followed
- [ ] Type safety maintained
- [ ] Tests run (if infrastructure exists)
- [ ] No debug code or console.logs left
- [ ] No secrets or PII in code
- [ ] WORKER_RESULT block is complete and accurate
- [ ] Files only modified within worktree path
~~~~

### Preload decisions

- No `skills:` entries at base — nothing preloaded, nothing to move. Spawn prompts name the skills a subtask needs and the worker Reads them at Step 1, unchanged.
