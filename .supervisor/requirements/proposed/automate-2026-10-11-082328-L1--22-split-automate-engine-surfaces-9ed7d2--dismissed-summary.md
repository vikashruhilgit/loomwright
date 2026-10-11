# Dismissed findings below the tracking threshold: 22-split-automate-engine-surfaces (2)

## Status: proposed

- **Run:** automate-2026-10-11-082328-L1
- **Item:** .supervisor/requirements/parallel-automate/22-split-automate-engine-surfaces.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/470
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
- **Key:** 89ab864c

```
> automate-helpers.sh _ah_usage merges two #:@ groups with the same name silently instead of failing closed
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** 60122e64

```
> PR #470 body AC10 section: the af/34 comparison plan-waves run shows no command or input order, so it is not reproducible from the body alone
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
