# Dismissed findings below the tracking threshold: 01-version-bump-script (1)

## Status: proposed

- **Run:** automate-2026-10-01-142337
- **Item:** .supervisor/requirements/parallel-automate/01-version-bump-script.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/327
- **Decision:** follow-up

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 0
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 240cbc49

```
> bump-version.sh .bump-version.XXXXXX backup dir under the repo root is not gitignored; left untracked after SIGKILL / kept-on-failed-restore, so git add -A would commit it (reproduced)
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
