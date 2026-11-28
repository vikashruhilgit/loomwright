# Dismissed findings below the tracking threshold: 2026-11-26-221024-product-owner-and-orchestrator-publish-what-they-write-to-the-metadata-branch (5)

## Status: proposed

- **Run:** automate-2026-11-27-162041
- **Item:** .supervisor/requirements/2026-11-26-221024-product-owner-and-orchestrator-publish-what-they-write-to-the-metadata-branch.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/999
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 69f711ce

```
> The FAILED retry command prints --paths-from and --root exactly as given, so a relative `--root .` / `--paths-from rel.list` gives a retry that only works from the original cwd. The agent prompts pass mktemp and show-toplevel absolute paths, so they are unaffected.
```

### Entry 2

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 7e2d7f2d

```
> meta_publish does not check that --root is a git checkout. Given a directory that does not exist, or a plain directory, setup-memory.sh mode reads 'off' and the helper prints 'meta-publish: skipped — branch mode off' instead of a FAILED line. Both prompts pass $(git rev-parse --show-toplevel), so this cannot happen from them today.
```

### Entry 3

- **Round:** 2
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** a7072b08

```
> meta_publish scope loop compares raw --paths-from lines; meta-sync.sh normalizes trailing CR and leading ./ first, so such lines are refused by meta-publish but accepted by meta-sync
```

### Entry 4

- **Round:** 2
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** 64d01826

```
> FAILED retry: command omits --message, so a hand retry commits with meta-sync's default message instead of 'chore(supervisor): publish planning file(s) on write'
```

### Entry 5

- **Round:** 2
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** 5310d867

```
> same ./-prefix / CRLF normalization gap in meta_publish's scope loop as r2-1 (low severity, unreachable via the documented call sites)
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
