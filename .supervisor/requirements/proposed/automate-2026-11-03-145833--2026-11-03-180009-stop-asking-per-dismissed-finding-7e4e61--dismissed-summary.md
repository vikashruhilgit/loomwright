# Dismissed findings below the tracking threshold: 2026-11-03-180009-stop-asking-per-dismissed-finding (3)

## Status: proposed

- **Run:** automate-2026-11-03-145833
- **Item:** .supervisor/requirements/2026-11-03-180009-stop-asking-per-dismissed-finding.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/820
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 0
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** drift
- **Key:** a0d36c03

```
> automate-loop SKILL.md's 'each drafted finding gets an owner decision where section 6 says' is stale; most drafts are now followed up automatically
```

### Entry 2

- **Round:** 0
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** a731d94a

```
> Golden case pick-pending-decisions-ask now asks nothing; its name is stale
```

### Entry 3

- **Round:** 2
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Key:** f326fd37

```
> meta-sync.sh header and meta-sync.d/plan.sh ordered_merge comment describe .dismissed-decisions rows as 3 columns, omitting the trailing auto column now common on --auto rows (comment-only; merge code is generic)
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
