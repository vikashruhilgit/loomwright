# Migration Guide

This document describes breaking changes between versions and how to migrate.

---

## Version Compatibility

| Plugin Version | Memory Format | Claude Code | Breaking Changes |
|----------------|---------------|-------------|------------------|
| 1.1.0 | v2 (proposals with IDs) | Any | Proposal format changed |
| 1.0.0 | v1 (original) | Any | Initial release |

---

## Migrating from 1.0.0 to 1.1.0

### Breaking Changes

1. **Proposal Format** — CLAUDE.md proposals now require IDs, timestamps, and expiration dates

2. **Session File Pruning** — Summarizer now enforces retention policy (max 30 session files)

3. **Git Safety Rails** — Repo Steward now refuses commits on main/master without `--allow-main` flag

### Migration Steps

#### 1. Update Proposal Format in context.md

**Old format (1.0.0):**
```markdown
### Pattern: [Pattern Name]
- **File:** src/file.ts (lines X-Y)
- **Severity:** GOOD_TO_USE
- **Status:** ⏳ AWAITING USER APPROVAL
```

**New format (1.1.0):**
```markdown
### CLAUDE.md Proposal

| Field | Value |
|-------|-------|
| **ID** | PROP-YYYYMMDD-001 |
| **Created** | 2025-12-17T10:00:00Z |
| **Expires** | 2025-12-24T10:00:00Z |
| **Conflicts With** | None |
| **Pattern** | [Pattern Name] |
| **Severity** | GOOD_TO_USE |
| **Status** | AWAITING_APPROVAL |

**Location:** src/file.ts:X-Y
```

**Migration:** Manually update existing proposals or approve/reject them before upgrading.

#### 2. Archive Old Session Files (Optional)

If you have more than 30 session files, the Summarizer will automatically archive older ones to `memory/archive/`. To do this proactively:

```bash
# Create archive directory
mkdir -p memory/archive

# Move oldest files (keep 30 most recent)
ls -t memory/session/ | tail -n +31 | xargs -I {} mv memory/session/{} memory/archive/
```

#### 3. Update Git Workflow

Repo Steward now requires explicit flags for main/master:

```bash
# Old (1.0.0): Would commit on any branch
/repo-steward

# New (1.1.0): Refuses on main/master
/repo-steward
# ERROR: You are on main branch. Use --allow-main to override.

# New (1.1.0): Explicit override
/repo-steward --allow-main
```

---

## Future Versions

### Planned for 1.2.0

- **Automated test harness** for agent prompts
- **Token optimization** with selective context loading
- **Security scanner integration** (Semgrep, Bandit)

### Breaking Changes Policy

- **Major versions (2.0, 3.0):** May include breaking changes to memory format
- **Minor versions (1.1, 1.2):** May change agent behavior, always backward-compatible memory
- **Patch versions (1.1.1):** Bug fixes only, no behavioral changes

---

## Troubleshooting

### "Validation Error" on context.md

Your context.md may be using the old proposal format. Either:
1. Approve/reject existing proposals (clears them)
2. Manually update to new format
3. Delete proposals section and let agents recreate

### "Refusing to commit on main branch"

New safety feature. Either:
1. Create a feature branch: `git checkout -b feature/your-feature`
2. Use override flag: `/repo-steward --allow-main`

### Session files being archived unexpectedly

Retention policy is now enforced. Files older than 30 are moved to `memory/archive/`. This is expected behavior.

---

## Support

If you encounter issues migrating:
1. Check AUDIT-REPORT.md for known limitations
2. Review agent prompts in `ai-agent-manager-plugin/agents/`
3. Open an issue with reproduction steps
