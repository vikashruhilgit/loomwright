# Dismissed findings below the tracking threshold: 09-loomwright-verify-kind-and-unknown-prefix-root-fix (2)

## Status: proposed

- **Run:** automate-2026-11-27-162041
- **Item:** .supervisor/requirements/qa-split/09-loomwright-verify-kind-and-unknown-prefix-root-fix.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/995
- **Decision:** follow-up

## Depends on
none

## Touches
docs/evidence/qa-split-09-verify-kind.md
loomwright/scripts/ground-truth-verify.sh

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** a37ad86e

```
> loomwright/scripts/ground-truth-verify.sh: criterion id/text read via jq @tsv escapes a backslash, so a folded criterion whose text contains a backslash never matches and is reported verify_verdict_unreadable (fails safe, never a pass, but a valid verdict is lost)
```

### Entry 2

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** f69c5dc9

```
> docs/evidence/qa-split-09-verify-kind.md: the recorded SELVEDGE_BIN=<checkout>/... "$SELVEDGE_BIN" --version line cannot run as written (the shell expands $SELVEDGE_BIN before the prefix assignment)
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
