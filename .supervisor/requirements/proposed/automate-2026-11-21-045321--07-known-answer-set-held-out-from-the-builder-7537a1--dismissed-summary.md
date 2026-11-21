# Dismissed findings below the tracking threshold: 07-known-answer-set-held-out-from-the-builder (4)

## Status: proposed

- **Run:** automate-2026-11-21-045321
- **Item:** .supervisor/requirements/qa-split/07-known-answer-set-held-out-from-the-builder.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/968
- **Decision:** follow-up

## Depends on
none

## Touches
selvedge/CHANGELOG.md
selvedge/README.md
selvedge/eval/eval-set.mjs

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** a38e1b29

```
> jsonValues misses a pretty-printed JSON file that starts with a UTF-8 BOM, so check-leak passes it (selvedge/eval/eval-set.mjs).
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Evidence:** none recorded
- **Key:** 3643d713

```
> Round-1 rewording left an over-long line in the CHANGELOG 0.8.0 entry and an orphaned short line in selvedge/README.md's known-answer-set paragraph.
```

### Entry 3

- **Round:** 2
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** f45cbfa3

```
> selvedge/CHANGELOG.md line 22 runs 149 chars, breaking the ~99-char wrap used by the rest of the file (cosmetic nit; reviewer also notes a dormant, not-currently-triggered check-leak fragility)
```

### Entry 4

- **Round:** 2
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** 34d68104

```
> selvedge/CHANGELOG.md line 22 runs 149 chars, breaking the ~99-char wrap used by the rest of the file (cosmetic nit)
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
