# Dismissed findings below the tracking threshold: 11a-qa-removal-manifest-and-rollback-tag (4)

## Status: proposed

- **Run:** automate-2026-11-18-170208
- **Item:** .supervisor/requirements/qa-split/11a-qa-removal-manifest-and-rollback-tag.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/944
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Evidence:** none recorded
- **Key:** fa117643

```
> propose-from-verify.sh is in names.txt. Seven files carry a keep row on it, but commands/propose.md, command-parts/agent-help/knowledge.md, fixtures/self-test-weights.tsv, propose-from-verify.sh itself and test-propose-from-verify.sh contain it with no row. The "one row per QA name the file contains" claim in How this list was generated is applied unevenly.
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 72bd86fa

```
> The fragment restates the manifest row count ('434 rows'), a second copy of the checker-verified 'Row count: 434' that no check backs. It already drifted once (433 -> 434 in the round-1 fix), and any later heal round or removal-PR row edit makes it stale again.
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** e88d2b56

```
> The conflict check only compares rows with the same (path, reference). A re-point or keep row on a file under a deleted directory row passes parsing and only shows at --expect 12 as an unfixable 're-point file is missing' MISMATCH. The real manifest has no such pair (verified); this fails safe, toward MISMATCH.
```

### Entry 4

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** a05e6ef4

```
> Four refusal branches have no self-test leg: the tab-in-row refusal, the unclosed-code-fence refusal, and the --manifest= / --root= forms. The first two were run by hand in this review and behave correctly.
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
