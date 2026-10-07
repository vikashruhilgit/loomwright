# Dismissed findings below the tracking threshold: 11-split-shared-hotspot-files (5)

## Status: proposed

- **Run:** automate-2026-10-06-154514
- **Item:** .supervisor/requirements/parallel-automate/11-split-shared-hotspot-files.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/408
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 962d554e

```
> automate-dismissed.sh:348 and propose-from-verify.sh:125 still locate _pw_touches copy 1 in automate-helpers.sh (now automate-helpers.d/plan-waves.sh)
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 0eff86cf

```
> automate-helpers.sh lost its executable bit (100755 -> 100644)
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 80673e7a

```
> _ah_source accepts an empty family file (only -f/-r) while _ah_bundle treats empty as missing
```

### Entry 4

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** a5c14226

```
> SKILLS_INDEX.md Last Updated for qa-gates/ and qa-test-patterns/ moved backwards because their frontmatter lastUpdated is stale
```

### Entry 5

- **Round:** 0
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** pre-existing: identical line-1 rule at base a14db34 (frontmatter_version), not introduced by this PR
- **Key:** 4db4538e

```
> check-skills-index-sync.sh frontmatter_field() requires the frontmatter --- on line 1; a SKILL.md with a leading blank line or BOM falls out of scope silently
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
