# Dismissed findings below the tracking threshold: 02-classifier-unknowable-attribution (2)

## Status: proposed

- **Run:** automate-2026-10-11-182243-L1
- **Item:** .supervisor/requirements/churn-ledger/02-classifier-unknowable-attribution.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/477
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
- **Key:** bc20a581

```
> Header (and SKILL Step 2 / schema doc) justify the first-commit exclusion as 'no review can precede the commit that opened the PR', but the code excludes commits[0] = oldest commit on the current head; after a force-push/squash that commit can postdate reviews (bounded: review_rounds is a MAX)
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** drift
- **Key:** 8cadbe1d

```
> Summary blurbs (commands/agent-help.md, skills/pr-postmortem/SKILL.md and commands/pr-postmortem.md frontmatter descriptions) still say each review round is categorized; under the omit rule only rounds with concrete evidence are
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
