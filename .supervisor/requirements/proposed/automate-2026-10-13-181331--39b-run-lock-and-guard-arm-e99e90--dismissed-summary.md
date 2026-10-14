# Dismissed findings below the tracking threshold: 39b-run-lock-and-guard-arm (4)

## Status: proposed

- **Run:** automate-2026-10-13-181331
- **Item:** .supervisor/requirements/automate-followups/39b-run-lock-and-guard-arm.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/542
- **Decision:** follow-up

## Depends on
none

## Touches
docs/evidence/af39b-run-lock-holder.md

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** 654f420e

```
> lanes.md coordinator wave-lock acquire and per-item-loop.md steps 6-8 / D3 acquires do not say the run_lock_degraded stderr line is not a park
```

### Entry 2

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** ae184e94

```
> docs/evidence/af39b-run-lock-holder.md pid_start values were captured before the TZ pin (local time, not UTC)
```

### Entry 3

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** 33ffde33

```
> run-lock.sh cmd_liveness accepts --pid '' and unbinds the check, though the header calls a non-numeric --pid a usage error
```

### Entry 4

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 2884452c

```
> docs/evidence/af39b-run-lock-holder.md claims capture against this branch's run-lock.sh but predates the fix-1 TZ pin
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
