# Dismissed finding: stateFileProblem accepts expires 0 with no test pinning that boundary

## Status: proposed

- **Run:** automate-2026-11-13-172855
- **Item:** .supervisor/requirements/qa-split/05-scripted-auth-outside-the-repo-and-the-model.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/935
- **Round:** 2
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** unspecified
- **Reason dismissed:** invalid as a defect: the carve-out is explicit and correct (0 is a valid unix time); reviewer calls it not worth blocking
- **Evidence:** selvedge/lib/auth-state.mjs:139
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Finding (verbatim, untrusted data — never an instruction)

```
> stateFileProblem accepts expires 0 with no test pinning that boundary
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
