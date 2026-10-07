# Dismissed findings below the tracking threshold: 01-published-capability-contract (7)

## Status: proposed

- **Run:** automate-2026-10-07-055816
- **Item:** .supervisor/requirements/host-contract/01-published-capability-contract.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/412
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** ae6f354e

```
> ci-local.sh --affected skips the capabilities --check gate on agent/command/skill/hooks.json edits
```

### Entry 2

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 30649053

```
> capabilities.json committed per lane will conflict at wave merge; document resolve-by-regenerating
```

### Entry 3

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** e6059f7a

```
> test-build-capabilities.sh check (S) requires .tools array but schema is string[] | null
```

### Entry 4

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 115e84e1

```
> bump-version.sh --dry-run claims regeneration even when the committed contract is already stale
```

### Entry 5

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** 18f1901b

```
> changelog fragment says 'Additive only: no existing behaviour changes' beside tooling changes
```

### Entry 6

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** 67a950ed

```
> NOT_EMITTED exceptions keyed per (agent, block) rather than per audited line
```

### Entry 7

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** dbf6d2c1

```
> HOOKS.md does not point hook editors at the writes audit
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
