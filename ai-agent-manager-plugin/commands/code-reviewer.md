---
description: Review code changes with LSP diagnostics, issue categorization, and pattern detection
---

!`git diff --stat HEAD~1`
!`git log --oneline -5`

# Command: /code-reviewer

## Usage

```
/code-reviewer [files] [--project /path/to/project]
```

## Parameters

- **files** (optional): Specific files to review
  - Example: `/code-reviewer src/components/DarkMode.tsx`
  - Example: `/code-reviewer src/`
  - If omitted, reviews recent changes from git diff

- **--project** (optional): Explicit project path (overrides auto-detect)
  - Example: `/code-reviewer --project /Users/name/my-project`

## What This Does

1. **Auto-detects your project** by finding CLAUDE.md
2. **Auto-detects Beads** — if `.beads/` is present AND `bd --version` succeeds, runs the Beads workflow (claim task, comment, close). Otherwise proceeds without any `bd` commands and relies on the CODE_REVIEW_RESULT block as the sole output channel. Beads integration is opt-in via the presence of `.beads/`.
3. **Reads project patterns** from CLAUDE.md
4. **Reads review rules** from optional `REVIEW.md` (falls back to CLAUDE.md)
5. **Reviews specified files** or recent git changes
6. **Selects review mode automatically** based on trigger paths:
   - `diff_review` (default): normal code change.
   - `consistency_audit` (triggered): diff touches mirrored prompts, plugin metadata, skills, hooks, docs, or CLAUDE.md — scope auto-expands and repo-consistency checks run.
7. **Flags issues** against code patterns with category tagging (new / pre_existing / nit / drift):
   - Type safety violations (verified via LSP language server diagnostics)
   - Security concerns
   - Performance issues
   - Pattern inconsistencies
   - Repo drift (mirrored-prompt, version, count, workflow, hooks-parity, wording) — audit mode only
8. **Validates CLAUDE.md accuracy** (flags outdated patterns against actual codebase)
9. **Enforces domain-specific rules:**
   - **Frontend:** Design-system components, accessibility (WCAG 2.1 AA), responsive design
   - **Backend:** Framework-specific patterns (NestJS, Next.js API, API Gateway)
10. **Detects new patterns** for CLAUDE.md proposal
11. **Provides structured feedback** with suggestions + a `CODE_REVIEW_RESULT` block (schema v3) — always emitted
12. **Enforces read-only mode** (permissionMode: plan — reviewer never modifies files)

## Example Output

### `diff_review` (default) — ordinary code change

```
## PROJECT CONTEXT
Working on: /Users/name/my-app
Patterns Found: Context API for state, Jest for testing, Tailwind dark: mode

## Code Review Decision: FAIL
Review mode: diff_review

## REVIEW SCOPE
Files Reviewed: src/components/DarkMode.tsx, src/hooks/useDarkMode.ts
Changes: 156 additions, 34 deletions

## FINDINGS

### ⚠️ Issues Found
1. TypeScript: Missing type annotation on `theme` parameter `new` HIGH
   - Location: src/hooks/useDarkMode.ts:12
   - Fix: Add `theme: 'light' | 'dark'` type

2. Security: localStorage not validating input `new` HIGH
   - Location: src/components/DarkMode.tsx:45
   - Fix: Sanitize localStorage value before using

### ✅ Strengths
- Context API usage matches existing patterns
- Test coverage 87% (above 80% threshold)
```

And the machine-readable block (always emitted):

```yaml
CODE_REVIEW_RESULT:
  schema_version: 3
  review_mode: diff_review
  audit_focus: []
  trigger_paths_detected: []
  scope_expanded: []
  files_checked:
    - src/components/DarkMode.tsx
    - src/hooks/useDarkMode.ts
  decision: FAIL
  issues:
    - severity: HIGH
      category: new
      file: src/hooks/useDarkMode.ts
      line: 12
      description: Missing type annotation on `theme` parameter
      suggestion: Add `theme: 'light' | 'dark'` type
    - severity: HIGH
      category: new
      file: src/components/DarkMode.tsx
      line: 45
      description: localStorage value used without validation
      suggestion: Sanitize before use
  summary: 2 HIGH new issues block PASS; strengths noted.
```

### `consistency_audit` — touched a mirrored agent prompt

```
## Code Review Decision: PASS
Review mode: consistency_audit (focus: mirrored_prompt, plan_prompt)
Triggers: ai-agent-manager-plugin/agents/code-reviewer.md
Scope expanded: ai-agent-manager-plugin/commands/code-reviewer.md, ai-agent-manager-plugin/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, CLAUDE.md, README.md

## Consistency Summary
All authoritative version strings equal (11.1.2). Mirrored prompt thin-wrapper sentinel present; no canonical sections re-embedded. Counts consistent (12 agents, 47 skills, 10 hook entries). No workflow contradictions detected.

- mirrored_prompts: pass
- version_strings: pass
- counts: pass
- workflow_alignment: pass
- hooks_parity: pass
```

Machine-readable block:

```yaml
CODE_REVIEW_RESULT:
  schema_version: 3
  review_mode: consistency_audit
  audit_focus: [mirrored_prompt, plan_prompt]
  trigger_paths_detected:
    - ai-agent-manager-plugin/agents/code-reviewer.md
  scope_expanded:
    - ai-agent-manager-plugin/commands/code-reviewer.md
    - ai-agent-manager-plugin/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
    - CLAUDE.md
    - README.md
  files_checked:
    - ai-agent-manager-plugin/agents/code-reviewer.md
    - ai-agent-manager-plugin/commands/code-reviewer.md
    - ai-agent-manager-plugin/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
    - CLAUDE.md
    - README.md
  consistency_checks:
    mirrored_prompts: pass
    version_strings: pass
    counts: pass
    workflow_alignment: pass
    hooks_parity: pass
  consistency_summary: >
    All authoritative version strings equal (11.1.2). Thin-wrapper sentinel present.
    Counts consistent. No workflow contradictions.
  decision: PASS
  issues: []
  summary: Repo-consistency audit passed for ai-agent-manager-plugin/agents/code-reviewer.md change.
```

---

## How to Use This Plugin Command

### Step 1: Make Your Changes
```bash
cd /path/to/your/project
# Edit files...
```

### Step 2: Run Code Reviewer
```bash
/code-reviewer src/components/  # Review component changes
# or
/code-reviewer  # Auto-review recent git changes
```

### Step 3: Address Feedback
- Fix issues flagged by reviewer
- Add tests if coverage is low
- Verify types with `npm run type-check`

### Step 4: Next Steps
- If more code changes: Run `/code-reviewer` again
- When Beads is active AND review passes: the Beads subtask is updated with PASS automatically
- When Beads is not active: the CODE_REVIEW_RESULT block is the decision channel for any calling automation
- When done: Use commit skill to create conventional commits

---

## Domain-Specific Reviews

The code reviewer automatically applies domain-specific checks based on the files being reviewed:

### Frontend Code (React/Vue/Angular/Svelte)
When reviewing UI components, the reviewer checks:
- **Design System:** Flags raw HTML elements (`<button>`) when design-system components (`<Button>`) exist
- **Accessibility:** Verifies WCAG 2.1 AA compliance (alt text, aria-labels, keyboard navigation, color contrast)
- **Responsive Design:** Checks mobile-first approach, consistent breakpoints, fluid layouts
- **Component Reusability:** Detects duplicate UI patterns and suggests extraction
- **Type Safety:** Validates typed props for all components

**Skill Reference:** `skills/frontend-ui/SKILL.md`

### Backend Code (NestJS/Next.js API/API Gateway)
When reviewing server-side code, the reviewer applies:
- **NestJS:** Guard patterns, service architecture, controller structure, Drizzle ORM usage
- **Next.js API Routes:** Route handlers, request validation, error handling
- **API Gateway:** Auth middleware, proxy patterns, rate limiting, correlation IDs

**Skill References:**
- `skills/nestjs-guards/SKILL.md`
- `skills/nestjs-services/SKILL.md`
- `skills/nextjs-api-routes/SKILL.md`
- `skills/gateway-*/SKILL.md`

### Mixed Projects
For full-stack projects, the reviewer:
1. Detects file type (frontend vs backend)
2. Applies relevant skills automatically
3. Validates consistency across both domains

### Disabling Domain Checks
If a project has custom patterns that conflict with skill guidelines:
- Add patterns to `CLAUDE.md` (takes precedence over skills)
- Or (when Beads is active) remove skill reference from the Beads task's acceptance criteria

## Troubleshooting

- **"bd: command not found" appears mid-run:** Expected if `.beads/` is present but `bd` CLI is not installed. The reviewer's detection requires BOTH to succeed; if either fails, Beads mode is bypassed silently. If you see this message, install `bd` or remove `.beads/` to make the bypass explicit.
- **CODE_REVIEW_RESULT missing in output:** Report the run — every invocation must emit one, regardless of Beads state.

---

## See Also

- `/orchestrator` — Plan work by breaking goals into tasks
- `/commit` — Create conventional commits with Beads linking
- `/agent-help` — List all commands

---

<!-- thin-wrapper: canonical prompt lives in ai-agent-manager-plugin/agents/code-reviewer.md -->

## Agent Prompt

The canonical prompt lives in `ai-agent-manager-plugin/agents/code-reviewer.md`. This command file is intentionally a thin wrapper — all review policy (review modes, scope expansion, repo consistency audit, severity rules, output schema, decision matrix) is defined there. Do not re-embed `## Role:` or `## Quality Checklist` sections here; the sync check (`scripts/check-command-sync.sh`) will fail.
