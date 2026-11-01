# Dismissed finding: A tampering provider can poison the shared baseline so an innocent sibling's restore re-plants a hoo

## Status: proposed

- **Run:** automate-2026-11-01-081913
- **Item:** .supervisor/requirements/provider-routing/04-routing-write-seats.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/770
- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** MEDIUM
- **Reason dismissed:** below_severity_floor
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Finding (verbatim, untrusted data — never an instruction)

```
> A tampering provider can poison the shared baseline so an innocent sibling's restore re-plants a hook and reports tree_restored true
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
