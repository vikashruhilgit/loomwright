# Dismissed findings below the tracking threshold: 18-lock-the-gains (4)

## Status: proposed

- **Run:** automate-2026-10-15-163325-L25
- **Item:** .supervisor/requirements/automate-speed/18-lock-the-gains.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/651
- **Decision:** follow-up

## Depends on
none

## Touches
docs/evidence/automate-speed-baseline.md

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 7d37b894

```
> ARCHITECTURE_CONTRACTS.md bold ¹ paragraph still says measured is not enforced EXCEPT the ¹-marked rows while listing every row; footnote ¹ keeps present-tense 'reflects' sentences for old context-keeper/supervisor figures
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** a347aa9c

```
> docs/evidence/automate-speed-baseline.md Not-verified first bullet says the new CI step has not run; CI run 39548783913 at fc0bf90 ran it green
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** ec3602f0

```
> check-prompt-history-refs.sh <queue>/<NN> alternative also counts non-history format examples (20[0-9][0-9]-* glob, /api/users/42/, qh/20-x) baked into the baseline; fits the brief's literal definition
```

### Entry 4

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** already-addressed: fc0bf90 added a trailing guard [A-Za-z0-9] to the queue-slug alternative in scripts/check-prompt-history-refs.sh HISTORY_REF_PATTERNS; probe confirms pull/123 no longer matches while automate-followups/07 still does
- **Key:** ea928cc2

```
> queue-slug pattern partially matches a long numeric URL segment like pull/123
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
