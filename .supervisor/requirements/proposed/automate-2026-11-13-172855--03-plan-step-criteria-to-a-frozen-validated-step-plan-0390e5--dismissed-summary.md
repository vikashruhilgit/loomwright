# Dismissed findings below the tracking threshold: 03-plan-step-criteria-to-a-frozen-validated-step-plan (6)

## Status: proposed

- **Run:** automate-2026-11-13-172855
- **Item:** .supervisor/requirements/qa-split/03-plan-step-criteria-to-a-frozen-validated-step-plan.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/924
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** ab74a261

```
> freezeRun rewrites plan.json and freeze.json before the exclusive (wx) plan.sha256 marker, so of two concurrent --freeze runs on one folder the loser overwrites the winner's freeze.json after the folder is frozen, then fails
```

### Entry 2

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 5118e0d2

```
> plan-planner.mjs imports BASE_ENV from the snapshot CLI module (which pulls in the route guard), where shared CLI helpers (isMain, parseCliArgs) now live in env-config.mjs
```

### Entry 3

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** a266324c

```
> Module shape: snapshot.mjs is now 521 lines, past the brief's 500-line threshold; the iteration-2 redaction code is a separate responsibility
```

### Entry 4

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** 20077c8c

```
> cmdPlan's testable.length === 0 branch (all-vague criteria, no planner run) has no test arm in selvedge/tests/
```

### Entry 5

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** 60a43aa5

```
> Re-raise: cmdPlan's all-vague (testable.length === 0) branch still untested
```

### Entry 6

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** a2baca16

```
> README and planner.md say check's `checked` is optional but never state it defaults to true (only snapshot.mjs's step.checked !== false encodes it); the 'redundant first plan.json write' nit is not redundant — the catch path tells the user to fix plan.json in the run folder and re-freeze
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
