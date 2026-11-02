# Dismissed findings below the tracking threshold: 2026-11-01-092116-feature-scorecard-shows-which-features-earn-their-cost (10)

## Status: proposed

- **Run:** automate-2026-11-01-195532-L3
- **Item:** .supervisor/requirements/2026-11-01-092116-feature-scorecard-shows-which-features-earn-their-cost.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/785
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
- **Key:** 77f01f14

```
> propose-from-verify.sh:13 'identical to the other two bases' is stale now that a fourth basis exists
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** dcc2a447

```
> propose.md --from-scorecard shell-out is a comment, not a runnable line; knowledge.md Parameters list omits --from-scorecard
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 8aca1518

```
> build-insights.sh staleness treats any row naming a second repo as foreign, so a multi-repo measurement reads stale forever (matches AC7 as written)
```

### Entry 4

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 3766440c

```
> build-feature-scorecard.sh markdown table does not escape '|' in cells (build-insights.sh does)
```

### Entry 5

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** bb85fa74

```
> Heal-signal staleness counts any multi-repo row as foreign, so a legitimate multi-repo run always renders stale (AC7 literal; deviation 2)
```

### Entry 6

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** a4ceb75a

```
> Markdown table mode does not escape '|' in cells; an unreadable verdict carrying a file name with '|' breaks the row
```

### Entry 7

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 60202c9d

```
> propose-from-verify.sh header still says 'identical to the other two bases' (line 10 'the third /propose basis')
```

### Entry 8

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 4ac646ef

```
> commands/propose.md --from-scorecard shell-out is a comment rather than an invocation line
```

### Entry 9

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** c9b71d7b

```
> command-parts/agent-help/knowledge.md /propose Parameters list names only --domain; --from-scorecard and --from-verify missing
```

### Entry 10

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** c976aa65

```
> build-feature-scorecard.sh --since validation is shape-only: '--since 2026-19-39' returns status ok and every feature silently becomes insufficient data
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
