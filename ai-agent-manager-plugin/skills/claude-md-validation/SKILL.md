---
name: claude-md-validation
description: Validate CLAUDE.md freshness and pattern accuracy. Use when establishing project context to ensure documented patterns are current.
allowed-tools: Read, Bash, Grep
---

# CLAUDE.md Validation Skill

Proactive validation to detect stale patterns and outdated documentation.

## Quick Rules

- Check git last-modified date (warn if > 30 days)
- Parse optional frontmatter timestamp
- Sample 2-3 documented patterns (verify they exist in code)
- Non-blocking warnings (informational only)

---

## Validation Steps

### 1. Check Freshness (Git-Based)

```bash
# Get last modification date
LAST_MOD=$(git log -1 --format=%cd --date=short CLAUDE.md 2>/dev/null)

if [ -z "$LAST_MOD" ]; then
  echo "⚠️ CLAUDE.md not tracked in git (cannot determine age)"
else
  # Calculate days since last update
  LAST_MOD_EPOCH=$(date -j -f "%Y-%m-%d" "$LAST_MOD" +%s 2>/dev/null || date -d "$LAST_MOD" +%s 2>/dev/null)
  NOW_EPOCH=$(date +%s)
  DAYS_OLD=$(( ($NOW_EPOCH - $LAST_MOD_EPOCH) / 86400 ))

  if [ $DAYS_OLD -gt 30 ]; then
    echo "⚠️ CLAUDE.md is $DAYS_OLD days old (last modified: $LAST_MOD)"
    echo "→ Consider reviewing and updating project patterns"
  else
    echo "✓ CLAUDE.md is fresh (modified $DAYS_OLD days ago)"
  fi
fi
```

### 2. Parse Frontmatter (Optional)

Projects can add YAML frontmatter to track update schedule:

```yaml
---
last-updated: 2026-01-04
review-interval: 30
---
# CLAUDE.md
...
```

**Check for frontmatter:**
```bash
# Check if CLAUDE.md has frontmatter
if grep -q "^---$" CLAUDE.md; then
  FRONTMATTER_DATE=$(sed -n '/^---$/,/^---$/p' CLAUDE.md | grep "last-updated:" | cut -d: -f2- | tr -d ' ')

  if [ -n "$FRONTMATTER_DATE" ]; then
    echo "✓ Frontmatter found: last-updated = $FRONTMATTER_DATE"

    # Compare with current date
    FRONT_EPOCH=$(date -j -f "%Y-%m-%d" "$FRONTMATTER_DATE" +%s 2>/dev/null || date -d "$FRONTMATTER_DATE" +%s 2>/dev/null)
    NOW_EPOCH=$(date +%s)
    FRONT_DAYS=$(( ($NOW_EPOCH - $FRONT_EPOCH) / 86400 ))

    if [ $FRONT_DAYS -gt 30 ]; then
      echo "⚠️ Frontmatter date is $FRONT_DAYS days old"
    fi
  fi
fi
```

### 3. Sample Patterns (Verify Against Codebase)

Extract 2-3 key patterns from CLAUDE.md and check if they exist in code.

**Example: Check for documented pattern**
```bash
# Extract pattern names from CLAUDE.md (example)
PATTERNS=$(grep -i "pattern:\|use.*pattern\|## pattern" CLAUDE.md | head -3)

# For each pattern, verify in codebase
# Example: CLAUDE.md says "use Drizzle ORM"
if grep -qi "drizzle" CLAUDE.md; then
  # Check if actually used
  if grep -rq "drizzle" --include="*.ts" --include="*.js" src/ 2>/dev/null; then
    echo "✓ Pattern 'Drizzle ORM' found in codebase"
  else
    echo "⚠️ Pattern 'Drizzle ORM' documented but not found in src/"
    echo "→ May be outdated or incorrectly named"
  fi
fi

# Example: CLAUDE.md says "test coverage ≥ 85%"
if grep -qi "coverage.*85" CLAUDE.md; then
  echo "ℹ️  Pattern: Test coverage ≥ 85% (validate during review)"
fi
```

---

## Warning Templates

### Fresh File (< 30 days)

```markdown
✓ CLAUDE.md is fresh (modified 12 days ago)
```

### Stale File (> 30 days)

```markdown
⚠️ CLAUDE.md is 45 days old (last modified: 2025-11-20)
→ Consider reviewing and updating project patterns
→ Check if tech stack, patterns, or conventions have changed
```

### Pattern Mismatch

```markdown
⚠️ Pattern 'Redux state management' documented but not found in codebase
→ May be outdated or renamed
→ Check: CLAUDE.md line 85
→ Action: Verify pattern still applies or update documentation
```

### Frontmatter Warning

```markdown
⚠️ Frontmatter last-updated is 60 days old
→ Consider updating frontmatter date after reviewing patterns
```

### No Git Tracking

```markdown
⚠️ CLAUDE.md not tracked in git (cannot determine age)
→ Add to git for automatic freshness tracking
```

---

## Validation Output

**Always include in agent output:**

```markdown
## CLAUDE.md Validation

**Freshness:** ✓ Fresh (12 days old) | ⚠️ Stale (45 days old)
**Frontmatter:** ✓ Found (2026-01-04) | ℹ️ None
**Patterns Sampled:** 2/2 found in codebase
**Issues:** None | ⚠️ 1 warning (see below)

### Warnings
- ⚠️ CLAUDE.md is 45 days old - consider review
```

---

## Integration with Agents

### When to Validate

**All agents should validate CLAUDE.md during context setup:**

```markdown
1. Read CLAUDE.md → understand patterns
2. **Validate CLAUDE.md freshness** (see skills/claude-md-validation/SKILL.md)
3. Continue with agent-specific work
```

### How to Use in Agent Prompts

```markdown
**After reading CLAUDE.md:**
- Validate `CLAUDE.md` freshness (see `skills/claude-md-validation/SKILL.md`)
- Report validation status in output
- If stale or warnings: note in Risks section
```

---

## Examples

### Example 1: Fresh CLAUDE.md

```bash
# Run validation
LAST_MOD=$(git log -1 --format=%cd --date=short CLAUDE.md)
# Output: 2026-01-02

# Calculate age
# Output: 2 days old

# Agent output:
## CLAUDE.md Validation
**Freshness:** ✓ Fresh (2 days old)
**Patterns:** All sampled patterns found
```

### Example 2: Stale CLAUDE.md with Pattern Mismatch

```bash
# Run validation
LAST_MOD=$(git log -1 --format=%cd --date=short CLAUDE.md)
# Output: 2025-10-15

# Calculate age
# Output: 81 days old

# Check pattern
grep -qi "redux" CLAUDE.md
# Found

grep -rq "redux" --include="*.ts" src/
# Not found

# Agent output:
## CLAUDE.md Validation
**Freshness:** ⚠️ Stale (81 days old - last modified: 2025-10-15)
**Patterns:** 1/2 found - see warnings

### Warnings
- ⚠️ CLAUDE.md is 81 days old - consider review
- ⚠️ Pattern 'Redux' documented but not found in src/
  → Check CLAUDE.md:42 - may be outdated

### Recommendation
Update CLAUDE.md to reflect current state management approach
```

### Example 3: With Frontmatter

```markdown
---
last-updated: 2025-12-01
review-interval: 30
---
# CLAUDE.md
```

```bash
# Validation output:
## CLAUDE.md Validation
**Freshness:** ✓ Git: 10 days old
**Frontmatter:** ⚠️ last-updated: 2025-12-01 (34 days ago - exceeds review-interval)
**Action:** Review patterns and update frontmatter date
```

---

## Best Practices

1. **Non-blocking:** Validation warnings are informational - agents continue regardless
2. **Quick sampling:** Only check 2-3 key patterns (avoid expensive full scans)
3. **Report clearly:** Include validation status in Context Read section
4. **Actionable:** Provide specific file:line references for issues
5. **Optional frontmatter:** Projects can add it, but git-based checking works without it

---

## Quality Checklist

- [ ] Git last-modified date checked
- [ ] Frontmatter parsed (if exists)
- [ ] 2-3 patterns sampled and verified
- [ ] Warnings non-blocking (don't fail agent)
- [ ] Output includes validation status
- [ ] File:line references for pattern issues

---

## See Also

- `skills/pattern-detector/SKILL.md` - Propose new patterns for CLAUDE.md
- `skills/context-setup/SKILL.md` - Standard context establishment (includes this validation)
