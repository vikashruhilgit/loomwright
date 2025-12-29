# Red Team Audit Report: ai-agent-manager

**Date:** 2025-12-18
**Auditor:** Red Team Reviewer Agent
**Target:** ai-agent-manager plugin system (v1.1.0)
**Scope:** Full adversarial audit — follow-up to previous audit from 2025-12-17
**Rating:** 4.5/10

---

## Executive Summary

| Severity | Previous (12/17) | Current (12/18) | Delta |
|----------|------------------|-----------------|-------|
| FATAL | 6 | 4 | -2 (partial fixes) |
| CRITICAL | 4 | 5 | +1 (new findings) |
| WARNING | 3 | 4 | +1 (new findings) |
| WEAKNESS | 2 | 3 | +1 (new findings) |

**Verdict:** Progress made but still **NOT production-ready**. Some mitigations documented, but core issues remain unenforced.

**Rating Breakdown:**

| Category | Score | Reasoning |
|----------|-------|-----------|
| Architecture & Design | 7/10 | Well-thought-out multi-agent system, clear separation of concerns |
| Documentation | 8/10 | Excellent documentation, clear instructions, comprehensive |
| Implementation | 2/10 | Documentation without enforcement. Policies in Markdown, not code |
| Testing | 0/10 | Zero tests. Unacceptable for "Quality First" claim |
| Security | 3/10 | Good awareness but no actual enforcement |
| Reliability | 4/10 | Non-atomic writes, no guaranteed pruning |
| Production Readiness | 2/10 | Would not trust without major fixes |

---

## Attack Surface

**Entry Points:**
- `/orchestrator`, `/code-reviewer`, `/repo-steward`, `/summarizer`, `/red-team-reviewer` slash commands
- User-maintained CLAUDE.md, TODO.md, memory/context.md files
- Git repository (agents execute git commands based on user state)
- File system (agents read project files, no sandboxing)
- External MCP tools (Context7) with no authentication/authorization
- User input via `goal:` parameter (documented limits, unenforced)

**Trust Boundaries:**
- No validation that CLAUDE.md content is safe or accurate
- Agents trust TODO.md status markers implicitly
- Git operations assume clean state but no verification
- File paths assumed valid; no canonicalization or sandbox checks

**External Dependencies:**
- Claude Code plugin system (undocumented failure modes)
- Git (must be installed, configured, working)
- Context7 MCP (optional, fallback behavior vague)
- File system (assumes readable, writable, with correct permissions)

**Context7 Reality Check:**

| Claim | Context7 Docs Say | Verdict |
|-------|-------------------|---------|
| "Hooks system" integration | Claude Code hooks use JSON config with `PreToolUse`, `PostToolUse` | PARTIAL — agents don't use hooks API |
| "Plugin marketplace" | Plugins use `/plugin install`, `marketplace.json`, `plugin.json` | CORRECT — structure matches |
| "MCP servers" integration | OAuth, command-based config | UNVERIFIED — no MCP server in plugin |
| "Sandbox mode" | Claude Code has `sandbox.allowUnsandboxedCommands` setting | NOT USED — agents don't configure sandbox |

---

## FATAL Findings (Production Will Fail)

### FATAL-1: Still No Tests — Zero Validation

**Location:** Entire repository
**Problem:** Previous audit flagged 0% test coverage. Still 0%.

**Evidence:**
```bash
$ find . -name "*.test.*" -o -name "*.spec.*"
# NOTHING FOUND
```

**Real-World Impact:**
- Agent behavior changes ship without validation
- Regressions invisible until users report broken workflows
- Memory corruption undetected

**Why Fatal:** System claims "Quality First" with ">=80% coverage" requirement but has **0%** coverage itself. Fundamental integrity failure.

**Status:** UNFIXED from previous audit

---

### FATAL-2: Memory Writes Still Non-Atomic

**Location:** `utils.md:196-262`, `summarizer.md:91-111`
**Problem:** Backup-before-write protocol added but has critical flaw.

**Documented Protocol:**
1. Read current state
2. Validate structure
3. Create backup
4. Write new content
5. Verify write
6. Delete backup

**Attack Scenario:**
1. Summarizer creates `context.md.backup`
2. Summarizer writes new `context.md` (partial write — disk full)
3. Verification fails
4. Recovery says "Restore from backup"
5. **But backup might also be corrupted** if disk was full during backup creation
6. **Git checkout fallback assumes clean git state** — what if uncommitted changes?

**Why Fatal:** Recovery procedure has no recursive failure handling. No transactional guarantees.

**Status:** PARTIALLY MITIGATED (backup added) but still vulnerable

---

### FATAL-3: Pruning Policy Exists But Unenforced

**Location:** `summarizer.md:72-90`
**Problem:** Retention policy documented but **no actual code executes it**.

**Documented Policy (summarizer.md:72-90):**
```markdown
1. **Count session files:** `ls memory/session/ | wc -l`
2. **If > 30 files:**
   - Move oldest to archive
```

**Reality:** This is Markdown instructions to an LLM. Summarizer is a prompt, not code. Claude may or may not follow these instructions consistently.

**Test:** Create 50 session files. Run `/summarizer`. Watch it not prune anything.

**Why Fatal:** Unbounded growth is guaranteed. "Policy exists" != "Policy enforced."

---

### FATAL-4: Input Validation Is Just Instructions

**Location:** `prompts.md:52-79`
**Problem:** "Input validation required" section exists but is unenforceable.

**Documented Requirements (prompts.md:52-79):**
```markdown
**Goal/Task Input:**
- Length: Max 1000 characters (reject longer with clear error message)
- Content: No executable code blocks unless explicitly requested
```

**Reality:** No code that:
1. Counts characters before processing
2. Rejects invalid input with error
3. Prevents path traversal
4. Validates memory file structure

**Attack:** Send goal with 100,000 characters. Agent tries to process, hits token limit, crashes mid-output.

**Why Fatal:** "Instructions" != "Validation." LLMs don't reliably enforce character limits.

---

## CRITICAL Findings (Serious Pain)

### CRITICAL-1: Git Safety Rails Are Just Instructions

**Location:** `repo-steward.md:46-87`
**Problem:** Detailed safety protocol documented but unenforced.

**Documented Check:**
```markdown
if [[ "$current_branch" == "main" || "$current_branch" == "master" ]]; then
  # REFUSE unless --allow-main flag is provided
```

**Reality:** This is a bash snippet inside a Markdown prompt. Claude **might** run this check, or might skip directly to `git commit`. LLMs don't reliably execute conditional logic.

**Attack:** User on `main` branch runs `/repo-steward`. Claude might commit directly to main.

---

### CRITICAL-2: File Verification Is Aspirational

**Location:** `prompts.md:81-94`
**Problem:** "Verify files exist before referencing" — but LLMs hallucinate.

**Documented Requirement:**
```markdown
Before referencing ANY file in output:
1. **Verify existence:** Run `ls -la [path]` to confirm file exists
```

**Reality:** LLMs frequently skip this step. They generate plans referencing files that don't exist.

**Attack:** Ask orchestrator to plan feature involving `src/config/redis.ts`. Watch it generate detailed plan for non-existent file.

---

### CRITICAL-3: Context7 Dependency Fallback Is Vague

**Location:** `utils.md:395-411`
**Problem:** Fallback behavior when Context7 unavailable is vague.

**Documented Fallback:**
```markdown
1. Don't block the agent run
2. Use CLAUDE.md patterns
3. Flag uncertainty in output
```

**Reality:** "Flag uncertainty" is vague. Useless audit if everything is "UNVERIFIED."

---

### CRITICAL-4: Token Overhead Is 5,000-10,000 Per Invocation

**Location:** All agent prompts (2,390 lines total)
**Problem:** Each invocation loads massive prompt overhead.

**Breakdown:**
- Shared preamble: ~284 lines
- Agent-specific: ~400-600 lines
- Utils: ~448 lines
- Plus: CLAUDE.md + TODO.md + context.md from user project

**Cost Impact:**
- At $15/MTok (Opus): 10,000 tokens = $0.15 per invocation
- 20 invocations/day = $3/day = ~$90/month just for overhead

---

### CRITICAL-5: Proposal Conflict Detection Is LLM-Dependent

**Location:** `code-reviewer.md:159-192`
**Problem:** Conflict detection relies on LLM to implement.

**Documented Process:**
```markdown
- Scan existing proposals in context.md before proposing
- If same pattern name exists, flag in "Conflicts With"
```

**Reality:** No guarantee LLM actually scans and compares. Could miss conflicts entirely.

---

## WARNING Findings (Future Pain)

### WARNING-1: Red Team Has No Follow-Up Mechanism

**Location:** `red-team-reviewer.md:375-381`
**Problem:** Independent auditor with no way to track if findings were addressed.

**Impact:** User gets audit, fixes some things, forgets others. No tracking.

---

### WARNING-2: Session File Naming Is Ambiguous

**Location:** `summarizer.md:26-59`
**Problem:** Template says `[task-name]-completed.md` but no standardization.

**Possible Variations:**
- `jwt-auth-completed.md`
- `JWT Auth - Completed.md`
- `task_jwt_completed_2025-12-18.md`

**Impact:** HISTORY.md links break. Resuming tasks fails.

---

### WARNING-3: No Versioning Strategy Documented

**Location:** `plugin.json`, `marketplace.json`
**Problem:** Both now say 1.1.0 (fixed) but no semver policy.

**Impact:** Breaking changes might ship as patch versions.

---

### WARNING-4: Context7 Token Guidance May Be Outdated

**Location:** `utils.md:367-377`
**Problem:** Recommends "Never exceed 5000" but Context7 default is 10000.

---

## WEAKNESS Findings (Attack Surface)

### WEAKNESS-1: No Rate Limiting On Agent Invocations

**Problem:** User can spam commands with no cooldown.

**Attack:** Script invoking `/code-reviewer` 100 times/minute -> token exhaustion.

---

### WEAKNESS-2: Memory Files Accept Any Markdown Structure

**Location:** `templates/project-template/memory/context.md`
**Problem:** No schema validation.

**Attack:** User accidentally deletes `## Current Task` header. Next agent fails to parse.

---

### WEAKNESS-3: No Audit Trail For Agent Actions

**Problem:** No logging of what agents did.

**Impact:** "Who committed that?" "Which agent broke memory?" — unanswerable.

---

## Top 3 Fatal Real-World Issues

1. **Zero Test Coverage** — Agent behavior changes ship without any validation. Regressions are invisible until users report broken workflows.

2. **Pruning Policy Unenforced** — Session files will grow indefinitely. After 500 tasks, `memory/session/` has 500 files. Performance degrades.

3. **Input Validation Is Wishful Thinking** — "Max 1000 characters" is an instruction, not enforcement. Users will hit token limits.

---

## What Would Convince a Hostile Expert

A skeptical auditor would reject this because:

1. **"Show me one test"** — Can't. Zero tests exist.
2. **"Demonstrate pruning works"** — Can't. It's just Markdown instructions.
3. **"Prove input validation rejects bad input"** — Can't. No code enforces limits.
4. **"Show me git safety actually prevents main commits"** — Can't. LLM might skip the check.

**To satisfy them, you need:**
- At least 5 integration tests proving agent output format is consistent
- Actual code (not Markdown) that prunes session files
- Actual code (not Markdown) that validates input length
- Actual Claude Code hooks that enforce git branch checks

---

## Prioritized Fixes

| Priority | Fix | Prevents | Effort | Impact |
|----------|-----|----------|--------|--------|
| 1 | Add integration test suite | Regressions, silent failures | 3-5 days | FATAL->Safe |
| 2 | Create actual pruning script | Unbounded growth | 1 day | FATAL->Safe |
| 3 | Use Claude Code hooks for git safety | Accidental main commits | 1-2 days | CRITICAL->Safe |
| 4 | Create PreToolUse hook for input validation | Token crashes | 1 day | FATAL->Safe |
| 5 | Add schema validation for memory files | Corruption | 1-2 days | WEAKNESS->Safe |
| 6 | Implement audit logging | No forensics | 2-3 days | WEAKNESS->Safe |
| 7 | Define semver policy | Breaking changes | 30 min | WARNING->Safe |
| 8 | Create follow-up mechanism for audit findings | Lost fixes | 1 day | WARNING->Safe |

---

## What I Could Not Verify

- Actual LLM behavior consistency (prompts != deterministic execution)
- Context7 reliability at scale
- Claude Code plugin API edge cases
- Memory performance at 500+ sessions
- Security scanning accuracy of Code Reviewer

---

## Progress Since Last Audit (2025-12-17)

**Fixed:**
- Version mismatch (plugin.json and marketplace.json now 1.1.0)
- Backup-before-write protocol documented
- Pruning policy documented
- Input validation requirements documented
- Git safety rails documented
- Red Team Reviewer agent added

**Still Broken:**
- Zero tests (was 0, still 0)
- Pruning policy unenforced (documented != implemented)
- Input validation unenforced (documented != implemented)
- Git safety unenforced (documented != implemented)
- No audit logging
- No rate limiting

---

## Conclusion

**Core Problem:** This system documents what SHOULD happen but has no code to ENFORCE it. Markdown instructions to an LLM are not guarantees. The gap between "documented policy" and "enforced behavior" is the attack surface.

**Rating: 4.5/10**

Great ideas, poor execution. Extensive documentation creates false confidence. Would require significant work to be production-ready.

**What would raise it to 8/10:**
1. Add 20+ integration tests (+2 points)
2. Implement actual hooks for git safety and input validation (+1 point)
3. Create real pruning script (+0.5 points)
4. Add audit logging (+0.5 points)

---

*Generated by Red Team Reviewer Agent*
