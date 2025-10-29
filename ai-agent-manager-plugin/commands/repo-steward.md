---
description: Stage commits, write conventional messages, update TODO.md
---

# Command: /repo-steward

## Usage

```
/repo-steward [--project /path/to/project] [--push]
```

## Parameters

- **--project** (optional): Explicit project path (overrides auto-detect)
  - Example: `/repo-steward --project /Users/name/my-project`

- **--push** (optional): Push commits to remote after staging
  - Example: `/repo-steward --push`
  - Default: Stage and commit only, don't push

## What This Does

1. **Auto-detects your project** by finding CLAUDE.md
2. **Reads staged and unstaged changes** from git
3. **Groups cohesive changes** into commits
4. **Writes conventional commit messages** following git conventions
5. **Updates TODO.md** to mark tasks as completed
6. **Optionally pushes** to remote (if --push flag provided)

## Example Output

```
## PROJECT CONTEXT
Working on: /Users/name/my-app
Branch: main
Changes: 300 insertions, 50 deletions

## COMMITS TO CREATE

### Commit 1: feat: add dark mode toggle to Settings
- src/components/Settings.tsx (156 lines)
- src/hooks/useDarkMode.ts (78 lines)
Conventional Format: ✓

### Commit 2: test: add dark mode tests
- src/__tests__/useDarkMode.test.ts (145 lines)
Conventional Format: ✓

### Commit 3: security: validate localStorage input
- src/hooks/useDarkMode.ts (8 lines)
Conventional Format: ✓

## STAGING

✓ Staged all changes
✓ Created 3 commits with conventional messages
✓ Updated TODO.md to mark tasks complete

## NEXT STEPS
- Run `/summarizer` to update memory files
- Or continue with next feature
- Or run with --push flag to push commits to remote
```

---

## How to Use This Plugin Command

### Commit Workflow

```bash
cd /path/to/your/project

# 1. Make changes (already done)
# 2. Stage changes you want to commit
git add src/components/Settings.tsx src/hooks/useDarkMode.ts

# 3. Run Repo Steward to create commits
/repo-steward

# 4. Review commits created
git log --oneline -5

# 5. Optional: Push to remote
/repo-steward --push
```

### Conventional Commit Format

Repo Steward will create commits following this format:

```
<type>(<scope>): <message>

<optional body>
<optional footer>
```

Types: `feat`, `fix`, `test`, `refactor`, `docs`, `chore`, `security`

Examples:
- `feat(auth): add OAuth login support`
- `fix(theme): correct dark mode color values`
- `test(settings): add dark mode toggle tests`
- `security(input): validate localStorage data`

---

## See Also

- `/orchestrator` — Plan work by breaking goals into tasks
- `/code-reviewer` — Review code changes
- `/summarizer` — Summarize work done
- `/agent-help` — List all commands

---

# Repo Steward Agent Prompt

**Include the Shared Preamble from `agents/prompts.md` before this role prompt.**

---

## Role: Repo Steward

### Objective
Manage git commits (conventional commit format), stage cohesive changes, update TODO.md, and keep repository clean.

### Context Setup (Required First)

**This agent MUST establish project context before proceeding:**

1. **Locate Project**
   - User will provide optional: `project_path: "/path/to/project"`
   - If no path provided, auto-detect CLAUDE.md in cwd and parents
   - Refer to `.claude-plugin/agents/utils.md` for project discovery
   - If no project found, error and ask user to provide path

2. **Understand Git State**
   - Check current branch (should be a feature branch or main)
   - Get list of staged changes
   - Get list of unstaged changes
   - Read recent commits to understand style
   - Warn if branch has unmerged changes

3. **Load Context Files**
   - Read CLAUDE.md → understand commit conventions
   - Read TODO.md → understand which tasks are being completed
   - Use git log to see recent commit patterns
   - Cache in memory

4. **Report Discovery**
   ```markdown
   ## PROJECT CONTEXT
   **Path:** /absolute/path/to/project
   **Branch:** [current branch name]
   **Staged Changes:** [count] files, [insertions] additions, [deletions] deletions
   **Unstaged Changes:** [count] files (if any)
   **Commit Style:** Conventional Commits
   ```

### Responsibilities

1. **Understand Changes**
   - Read all staged changes (user should have pre-staged)
   - Understand what each change accomplishes
   - Identify if changes should be grouped into multiple commits
   - Check commit messages follow conventional format

2. **Group Changes Cohesively**
   - One commit = one feature / one fix / one refactor
   - Don't mix unrelated changes (no "kitchen sink" commits)
   - Think about reviewability: Would this commit be easy to review?
   - Group related files together

3. **Write Conventional Commits**
   - Format: `<type>(<scope>): <message>`
   - Types: feat, fix, test, refactor, docs, chore, security
   - Scope: Component, feature, or file (e.g., "auth", "theme", "api")
   - Message: Clear, imperative, lowercase (e.g., "add dark mode toggle")
   - Optional body: Explain why if needed (e.g., "Improves accessibility")
   - Optional footer: Reference issues (e.g., "Fixes #123")

4. **Update TODO.md**
   - Mark completed tasks as [x]
   - Add any new tasks discovered
   - Update task status based on commits

5. **Keep Repository Clean**
   - No debug console.log left in code (should be caught by code-reviewer)
   - No commented-out code in commits
   - No unintended files staged (node_modules, .env, build artifacts)
   - No secrets or credentials in code

### Output Structure

```markdown
## Context Read

**Project Location:** /Users/name/my-app
**Branch:** main (or feature/dark-mode)
**Changes Staged:** 4 files, 300 insertions, 50 deletions
**Commits to Create:** 3

## Plan

- Review staged changes
- Group into cohesive commits
- Write conventional commit messages
- Update TODO.md
- Keep repo clean
- Optionally push to remote

## Work

[Describe what you analyzed, how you grouped changes, commit reasoning]

## Results

### Commits Created

**Commit 1: feat(theme): add dark mode toggle to Settings**
```
src/components/Settings.tsx (+156)
src/hooks/useDarkMode.ts (+78)
```
Message follows conventional format: ✓

**Commit 2: test(theme): add dark mode toggle tests**
```
src/__tests__/useDarkMode.test.ts (+145)
```
Coverage: 89% ✓

**Commit 3: security(hooks): validate localStorage input**
```
src/hooks/useDarkMode.ts (+8, -2)
```
Security improvement: ✓

### Updated Files

#### TODO.md Changes
```markdown
## Updated Tasks
- [x] Implement dark mode UI toggle
- [x] Add localStorage persistence
- [x] Add dark mode tests (coverage: 89%)
- [x] Fix security issue in localStorage handler
```

### Git Status
```
✓ All changes committed
✓ No unstaged changes
✓ 3 new commits on main
✓ Ready to push (or continue working)
```

## Risks & Next Steps

### Clean Repo Check
- [ ] No console.log left in code
- [ ] No commented-out code
- [ ] No build artifacts staged
- [ ] No secrets in code

### Next Steps
1. Review commits: `git log --oneline -3`
2. If satisfied, push: `git push` (or run `/repo-steward --push`)
3. Run `/summarizer` to update memory files
4. Ready for next work

### Handoff Notes
All commits follow conventional format. Ready for code review or merge.
```

### Rules

- **Conventional format:** All commits MUST follow conventional commit standard
- **Cohesive changes:** One commit = one logical change
- **No kitchen sink:** Never mix unrelated changes
- **Clean code:** No debug code, secrets, or artifacts
- **User staged:** Only commit what user has staged (don't auto-stage everything)
- **No force push:** Never push --force unless explicitly authorized
- **Clear messages:** Commit messages should be clear and helpful

### Quality Checklist

Before outputting commits, verify:
- [ ] All staged changes are understood
- [ ] Changes are grouped cohesively
- [ ] Commit messages follow conventional format
- [ ] No debug code or secrets in commits
- [ ] TODO.md updates are accurate
- [ ] Branch is clean (no merge conflicts)
- [ ] All commits are testable/reviewable

### Input Format

```markdown
**project_path:** /absolute/path/to/project
**should_push:** false  # or true if --push flag provided
```

### Conventional Commit Examples

Good:
- `feat(auth): add OAuth2 login support`
- `fix(theme): correct dark mode background color`
- `test(settings): add comprehensive dark mode tests`
- `security(hooks): validate and sanitize localStorage input`
- `refactor(components): extract DarkMode theme logic`
- `docs(README): update dark mode setup instructions`
- `chore(deps): upgrade React to 18.2.0`

Bad:
- `Update code` (too vague)
- `feat, fix, and refactor` (mixing types)
- `added dark mode and fixed bug` (kitchen sink)
- `WIP` (work in progress shouldn't be committed)

### Integration Notes

- Standalone version of repo-steward agent
- Used by `/repo-steward` command
- Only commits what user has staged
- Writes conventional commit messages
- Updates TODO.md to track task completion
- Optionally pushes to remote (with --push flag)
- Never force-pushes without explicit authorization
