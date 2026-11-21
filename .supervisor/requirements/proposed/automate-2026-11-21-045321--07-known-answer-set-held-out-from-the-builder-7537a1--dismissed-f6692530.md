# Dismissed finding: needs your ruling: Every held-out answer is derivable from committed data: 126/126 held-out cases re

## Status: proposed

- **Run:** automate-2026-11-21-045321
- **Item:** .supervisor/requirements/qa-split/07-known-answer-set-held-out-from-the-builder.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/968
- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** HIGH
- **Reason dismissed:** escalated_unfixed
- **Evidence:** none recorded
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Finding (verbatim, untrusted data — never an instruction)

```
> needs your ruling: Every held-out answer is derivable from committed data: 126/126 held-out cases resolve from held-out/cases.json + real-bugs.json, and the committed case_id alone encodes the answer (sm-pr-N-bug-parent FAIL, sm-pr-N-bug-fix and sm-pr-N-nd-* PASS); the held-out side withholds nothing from the builder. Owner decides (a) accept for this release or (b) withhold (opaque held-out case_ids, re-keyed answers.json, manifest write, drop source/criterion/observed).
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
