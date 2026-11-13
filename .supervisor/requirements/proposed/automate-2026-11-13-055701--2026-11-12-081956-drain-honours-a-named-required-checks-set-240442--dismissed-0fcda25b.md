# Dismissed finding: test-review-heal-next-step.sh does not parse under /bin/bash 3.2 (CHEAP_PINS heredoc inside $(...));

## Status: proposed

- **Run:** automate-2026-11-13-055701
- **Item:** .supervisor/requirements/drain-named-required-checks/2026-11-12-081956-drain-honours-a-named-required-checks-set.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/905
- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** pre_existing
- **Evidence:** none recorded
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Finding (verbatim, untrusted data — never an instruction)

```
> test-review-heal-next-step.sh does not parse under /bin/bash 3.2 (CHEAP_PINS heredoc inside $(...)); origin/main's copy fails the same way
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
