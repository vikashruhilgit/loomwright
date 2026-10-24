# Dismissed findings below the tracking threshold: 39g-leak-gate-and-attention-lines (2)

## Status: proposed

- **Run:** automate-2026-10-22-123646-L7
- **Item:** .supervisor/requirements/automate-followups/39g-leak-gate-and-attention-lines.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/692
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
- **Key:** b91813fd

```
> Leak gate's three lsof calls carry no -b flag and no time bound; a stale network mount could hang ci-local after the suite
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 2a4c58e1

```
> Lane sampler registered as kind lane with the 24h cap; reap --apply TERM after 24h leaves <run_id>.memory-pressure, refusing further lanes in that wave
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
