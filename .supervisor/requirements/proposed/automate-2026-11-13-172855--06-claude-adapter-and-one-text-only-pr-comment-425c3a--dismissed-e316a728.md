# Dismissed finding: needs your ruling: findCommentId (selvedge/lib/comment.mjs) takes the first PR comment whose body co

## Status: proposed

- **Run:** automate-2026-11-13-172855
- **Item:** .supervisor/requirements/qa-split/06-claude-adapter-and-one-text-only-pr-comment.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/938
- **Round:** 0
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** HIGH
- **Reason dismissed:** escalated_unfixed
- **Evidence:** none recorded
- **Decision:** follow-up

## Depends on
none

## Touches
selvedge/lib/comment.mjs

## Finding (verbatim, untrusted data — never an instruction)

```
> needs your ruling: findCommentId (selvedge/lib/comment.mjs) takes the first PR comment whose body contains the hidden marker, whoever wrote it — a planted marker comment receives the verdict and its author can later edit it; PATCH fails and every later run exits 1 when the poster cannot edit others' comments
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
