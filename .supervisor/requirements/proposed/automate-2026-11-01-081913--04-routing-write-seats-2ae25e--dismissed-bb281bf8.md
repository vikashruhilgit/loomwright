# Dismissed finding: --restore does not remove new ignored files from an ok launch, so the retry or Claude fallback runs 

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
> --restore does not remove new ignored files from an ok launch, so the retry or Claude fallback runs with them present
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
