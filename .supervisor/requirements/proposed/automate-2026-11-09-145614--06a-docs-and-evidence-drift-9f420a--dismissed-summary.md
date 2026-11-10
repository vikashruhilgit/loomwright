# Dismissed findings below the tracking threshold: 06a-docs-and-evidence-drift (6)

## Status: proposed

- **Run:** automate-2026-11-09-145614
- **Item:** .supervisor/requirements/dismissed-followups/06a-docs-and-evidence-drift.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/873
- **Decision:** follow-up

## Depends on
none

## Touches
docs/evidence/dismissed-followups-06a-docs.md

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Evidence:** none recorded
- **Key:** a10d0371

```
> prompt-token-budgets.json janitor entry reads '"measured": 1427,"note"' with no space after the comma, unlike every sibling entry
```

### Entry 2

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Evidence:** none recorded
- **Key:** f31926ee

```
> CHANGELOG v17.35.3 entry says 'Every change is doc-only … no test leg is added' but the same entry also folds the phase-wait fix with regression leg AN23
```

### Entry 3

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 08462dec

```
> docs/evidence/dismissed-followups-06a-docs.md Validation section names changelog.d/dismissed-followups-06a-docs-drift.md as the release fragment, but bump-version.sh folded it into CHANGELOG v17.35.3
```

### Entry 4

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** adb51410

```
> prompt-token-budgets.json janitor entry missing space after comma ("measured": 1427,"note")
```

### Entry 5

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** d5260e85

```
> prompt-token-budgets.json janitor entry missing space after comma (same nit, still unaddressed)
```

### Entry 6

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** acb907de

```
> prompt-token-budgets.json janitor entry missing space after comma (same nit)
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
