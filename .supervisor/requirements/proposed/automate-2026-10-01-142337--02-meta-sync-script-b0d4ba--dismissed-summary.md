# Dismissed findings below the tracking threshold: 02-meta-sync-script (6)

## Status: proposed

- **Run:** automate-2026-10-01-142337
- **Item:** .supervisor/requirements/parallel-automate/02-meta-sync-script.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/334
- **Decision:** follow-up

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** a77b2486

```
> Plain-refspec push re-creates the branch if it was deleted between fetch and push, contradicting 'init is the ONLY command that may create the branch'
```

### Entry 2

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 8e84fe5a

```
> Reserved first segments (orgs/users/sponsors) and an all-dot repo segment leak an owner name past the slug scrub
```

### Entry 3

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** b3a919ec

```
> A dead reclaim-marker chain deeper than 4 is never reclaimed; the locked message names a dead pid with no recovery hint
```

### Entry 4

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 4c5dd42b

```
> After a failed pid write, rm -rf LOCK_DIR could remove another process's lock (static only)
```

### Entry 5

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** 10c717e5

```
> ARCHITECTURE_CONTRACTS says git rev-parse --git-dir; the script uses --absolute-git-dir
```

### Entry 6

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** invalid: CI's run-self-tests.sh globs loomwright/scripts/test-*.sh automatically, so the test already runs in CI
- **Key:** a2d70be4

```
> CHANGELOG entry lacks the 'CI wiring lands as a follow-up PR' caveat; test-meta-sync.sh is not referenced from any workflow yet
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
