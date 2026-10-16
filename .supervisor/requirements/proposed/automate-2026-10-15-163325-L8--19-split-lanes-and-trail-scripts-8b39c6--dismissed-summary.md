# Dismissed findings below the tracking threshold: 19-split-lanes-and-trail-scripts (3)

## Status: proposed

- **Run:** automate-2026-10-15-163325-L8
- **Item:** .supervisor/requirements/automate-speed/19-split-lanes-and-trail-scripts.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/577
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
- **Key:** b1ef1752

```
> guard-lane-wait-armed.sh:26,35 comments place _LANES_WAIT_LIVE / _lanes_quick_state in automate-lanes.sh; they now live in automate-lanes.d/status.sh
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 224689ba

```
> docs/evidence §3 still cites git show 051553e for the AC3 legs (now e232771); the line-7 pre-merge list disagrees with §9
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 2185be82

```
> docs/evidence §6 says AC11 was not re-run on the merged tree; the merged-tree re-run is recorded only in the PR body
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
