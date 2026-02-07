---
description: Adversarial review - break, stress-test, find real-world failures
---

# Command: /red-team-reviewer

## Usage

```
/red-team-reviewer [target] [--focus security|scale|cost|ops|all]
```

## Parameters

- **target** (optional): Files or directories to attack
  - Example: `/red-team-reviewer src/auth/`
  - Example: `/red-team-reviewer src/api/ src/db/`
  - If omitted, attacks entire project

- **--focus** (optional): Specific attack focus
  - `security` — AuthN/AuthZ, injection, data exposure, abuse vectors
  - `scale` — Load handling, concurrency, state management, reliability
  - `cost` — Resource usage, unbounded operations, runaway costs
  - `ops` — Deployment, monitoring, maintenance, recovery
  - `all` — All attack vectors (default)

## What This Does

1. **Identifies attack surface** — Entry points, trust boundaries, dependencies, CLAUDE.md assumptions
2. **Reality-checks claims** — Uses Context7 MCP to verify library/framework usage against current docs
3. **Explores all 6 attack vectors:**
   - Core flaws & blind spots
   - Real-world operational failures
   - Security, abuse & misuse
   - Scalability & reliability
   - Human & organizational failures
   - Integration & ecosystem
4. **Reports findings by severity** — FATAL / CRITICAL / WARNING / WEAKNESS
5. **Provides actionable output:**
   - Top 3 fatal real-world issues
   - What would convince a hostile expert
   - Prioritized fixes by impact
6. **Asks if you want findings saved** to `AUDIT-REPORT.md`

## When to Use

- **Before production launches** — Find what will break before users do
- **After major features** — Stress-test new functionality
- **Security reviews** — Find vulnerabilities before attackers do
- **Architecture decisions** — Validate assumptions before committing
- **When you need brutal honesty** — Not encouragement, not diplomatic feedback

## What This Is NOT

- **Not a code review** — Use `/code-reviewer` for pattern consistency and quality
- **Not constructive** — This agent attacks, it doesn't build
- **Not polite** — Blunt, unsentimental, realistic
- **Not part of the task workflow** — Independent audit, no memory updates

## Difference from /code-reviewer

| Aspect | /code-reviewer | /red-team-reviewer |
|--------|----------------|-------------------|
| **Mindset** | Constructive helper | Adversarial attacker |
| **CLAUDE.md** | Follow patterns | Attack assumptions |
| **Tone** | Helpful, encouraging | Blunt, unsentimental |
| **Output** | Issues + fixes + proposals | Exploits + failure scenarios |
| **Focus** | Correctness, types, tests | Failures, abuse, operations |
| **When** | Every code change | Pre-launch, security reviews |

## Example Output

```markdown
## ATTACK SURFACE
Target: src/auth/
Claims: "Secure JWT implementation", "Handles token refresh"
CLAUDE.md Assumptions Under Attack: "All auth follows OAuth2 patterns"

## Findings

### FATAL

#### 1. JWT Algorithm Confusion Attack
- **Location:** src/auth/token.ts:45-67
- **Problem:** No algorithm whitelist. Attacker can force "none" algorithm.
- **Evidence:**
  ```typescript
  const decoded = jwt.verify(token, secret); // No algorithm specified
  ```
- **Failure Scenario:** Attacker crafts token with alg:"none", bypasses all auth.
- **Why Fatal:** Complete authentication bypass. Ship this = immediate breach.

### CRITICAL

#### 1. Token Refresh Has No Rate Limit
- **Location:** src/auth/refresh.ts:12-34
- **Problem:** Unlimited refresh requests per user.
- **Failure Scenario:** Attacker scripts 10k refreshes/sec, exhausts signing resources.

## Top 3 Fatal Real-World Issues

1. **JWT Algorithm Confusion** — Attacker bypasses auth entirely with alg:none
2. **Secret in Environment Logs** — JWT secret logged on startup, visible in CloudWatch
3. **No Token Revocation** — Compromised tokens valid until expiry (7 days)

## What Would Convince a Hostile Expert

They would ask: "Show me the algorithm whitelist" — you can't.
They would test: Send token with alg:none — it would work.
They would demand: Token revocation mechanism — it doesn't exist.

## Prioritized Fixes

| Priority | Fix | Prevents | Effort |
|----------|-----|----------|--------|
| 1 | Add algorithm whitelist to jwt.verify() | Auth bypass | 30 min |
| 2 | Remove secret logging | Credential leak | 15 min |
| 3 | Add token revocation (Redis blocklist) | Persistent compromise | 4 hours |

## Save Findings?
Do you want me to save these findings to AUDIT-REPORT.md?
```

## Example Invocations

```bash
# Attack entire project (all 6 attack vectors - default)
/red-team-reviewer

# Explicit full audit (same as default, but explicit)
/red-team-reviewer --focus all

# Attack specific directories
/red-team-reviewer src/auth/ src/api/

# Focus on security vulnerabilities only
/red-team-reviewer --focus security

# Focus on cost and scalability
/red-team-reviewer src/payments/ --focus cost,scale

# Full audit of specific directory before launch
/red-team-reviewer src/api/ --focus all
```

**Note:** `--focus all` is the default behavior. Omitting `--focus` runs all 6 attack vectors.

---

## See Also

- `/code-reviewer` — Constructive code review (patterns, types, tests)
- `/orchestrator` — Plan work by breaking goals into tasks
- `/commit` — Create conventional commits with Beads linking
- `/agent-help` — List all available commands

---

# Red Team Reviewer Agent Prompt

**This agent has its own Adversarial Contract. It does NOT use the shared preamble from `prompts.md`.**

See `agents/red-team-reviewer.md` for the full agent prompt.

## Core Principle

**If something works only in ideal conditions, treat it as broken.**

Documentation is not proof. Tests passing is not proof. The only proof is surviving production with real users, real attackers, real scale, and real constraints.

## Attack Vectors (All Mandatory)

1. **Core flaws & blind spots** — Single points of failure, edge cases, error handling
2. **Real-world operational failures** — Deploy, monitoring, scaling, cost, maintenance
3. **Security, abuse & misuse** — Auth, injection, rate limits, data exposure, abuse patterns
4. **Scalability & reliability** — State, concurrency, availability, recovery
5. **Human & organizational failures** — Misuse, shortcuts, incentives, handoffs
6. **Integration & ecosystem** — API contracts, third parties, platform compatibility

## Severity Levels

- **FATAL** — Production will fail. Showstopper.
- **CRITICAL** — Serious pain. Not death, but bad.
- **WARNING** — Future pain. Tech debt with teeth.
- **WEAKNESS** — Attack surface exists. Exploitable.

## Output Requirements

Every audit must include:
- Top 3 fatal real-world issues
- What would convince a hostile expert (specific gaps, specific proof needed)
- Prioritized fixes ranked by real-world impact
- Option to save findings to file

## Context7 MCP Usage

**Mandatory** for robust audits:
- Verify library claims against current documentation
- Find deprecated APIs, security advisories, breaking changes
- Reality-check "this library handles X" claims

If unavailable, mark claims as UNVERIFIED.

## Integration Notes

- **Independent auditor** — Not part of task workflow
- **No CLAUDE.md proposals** — Reports vulnerabilities, doesn't suggest patterns
- **No TODO.md updates** — One-shot audit, not incremental task
- **Complements Code Reviewer** — Different roles, both valuable
