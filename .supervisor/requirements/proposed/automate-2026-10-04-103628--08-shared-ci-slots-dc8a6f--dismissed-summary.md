# Dismissed findings below the tracking threshold: 08-shared-ci-slots (3)

## Status: proposed

- **Run:** automate-2026-10-04-103628
- **Item:** .supervisor/requirements/parallel-automate/08-shared-ci-slots.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/375
- **Decision:** follow-up

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 94ffa44f

```
> Honest limit (3) understates a double stale-mutex takeover: two processes inside the mutex can issue the same counter value, the losing waiter's ticket is overwritten and it stalls until --wait expires
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** d08914b7

```
> POLL validation accepts '.' or '1.2.3'; sleep then fails at once and the wait loop busy-spins against the mutex (test knob only)
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** c2680f29

```
> The background poll sleep is not killed when TERM interrupts the waiter, so it outlives the helper by up to one poll period
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
