# Dismissed findings below the tracking threshold: 16-machine-load-guard (3)

## Status: proposed

- **Run:** automate-2026-10-06-154117
- **Item:** .supervisor/requirements/parallel-automate/16-machine-load-guard.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/402
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
- **Reason dismissed:** nit
- **Key:** ea0584a4

```
> ci-slot.sh header: the default machine dir is $HOME/.local/state/loomwright/machine, so a caller with a different HOME is silently isolated from the machine holders list; the header does not state this HOME dependency.
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 34169a86

```
> ci-slot.sh header layout still says 'a ticket adds a fifth' line but held tickets now carry a sixth (the hold reason); the status usage line does not mention the machine view or the held/machine --json keys.
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** a114b2d6

```
> machine-load.sh header says --json is 'one object with the same keys' but --json also emits busy_at and overloaded_at.
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
