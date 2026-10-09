# Dismissed finding: emit-token-ledger.sh: read_transcript(_apath) is not gated on the same agent-<agent_id>.jsonl basena

## Status: proposed

- **Run:** automate-2026-10-08-121222
- **Item:** .supervisor/requirements/parallel-automate/24-pa05-validation-fixes-b.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/435
- **Round:** 2
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** unspecified
- **Reason dismissed:** same root cause and fix as the owner-decided follow-up draft 2f32897a (gate the transcript read on the subagent basename match); surfaced after the sub-floor termination, put to the owner at the park
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Finding (verbatim, untrusted data — never an instruction)

```
> emit-token-ledger.sh: read_transcript(_apath) is not gated on the same agent-<agent_id>.jsonl basename identity check that gates agent_scope, so an agent_transcript_path pointing at a foreign transcript would attribute that transcript's real tokens to this agent/lane (reviewed at 783b00b)
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
