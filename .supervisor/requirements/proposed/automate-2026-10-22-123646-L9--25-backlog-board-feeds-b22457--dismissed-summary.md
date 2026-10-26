# Dismissed findings below the tracking threshold: 25-backlog-board-feeds (5)

## Status: proposed

- **Run:** automate-2026-10-22-123646-L9
- **Item:** .supervisor/requirements/parallel-automate/25-backlog-board-feeds.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/709
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
- **Key:** 8a9f6ebe

```
> build-floor.sh backlog_basis says a merged-PR-only item 'reads unknown'; backlog.sh header and floor-projection.md say 'unknown, or its open-path state'
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 1950c248

```
> session-resume.sh empty-SR_STATE skip (host mode, no valid state dir) has no test
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** 630f38c0

```
> test-session-resume.sh (bn2) byte-identical check compares against origin/main and self-skips once this PR merges
```

### Entry 4

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** drift
- **Key:** 1e2fc5de

```
> status-read.sh _lanes_render_terse comment still calls itself lane-status's default view without the trailing backlog pointer line status.sh appends
```

### Entry 5

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** bc39abb9

```
> session-resume.sh / HOOKS.md say 'up to LOOMWRIGHT_SR_BACKLOG_TIMEOUT seconds'; SECONDS granularity makes the worst case about timeout + 1 s
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
