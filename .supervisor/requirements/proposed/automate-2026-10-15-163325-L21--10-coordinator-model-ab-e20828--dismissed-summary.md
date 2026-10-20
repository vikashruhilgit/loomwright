# Dismissed findings below the tracking threshold: 10-coordinator-model-ab (7)

## Status: proposed

- **Run:** automate-2026-10-15-163325-L21
- **Item:** .supervisor/requirements/automate-speed/10-coordinator-model-ab.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/632
- **Decision:** follow-up

## Depends on
none

## Touches
docs/evidence/coordinator-model-ab.md

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** drift
- **Key:** eab4f99e

```
> Four restated exit-2 'nothing written' copies (automate-loop SKILL.md, per-item-loop.md, supervisor-result.md, completion-tail.md) not updated for the coordinator-model ledger exception
```

### Entry 2

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** ae95dc32

```
> ns_reprint re-prints a stale or absent coordinator_model after a config change
```

### Entry 3

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** f0b1a9d0

```
> 'at most one escalated record per ledger' can be broken by a rare stale-lock break race
```

### Entry 4

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** e0cbb093

```
> coordinator_model_invalid stderr message hard-codes an unchecked copy of NS_CM_VALUES
```

### Entry 5

- **Round:** 1
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** a25373c6

```
> In a lane checkout lane-remove discards the coordinator-model ledger
```

### Entry 6

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Key:** 8b16a194

```
> eval verdict.sh SKIPPED counts any later --result call as answering a spawn/ask without checking its rc (calls.log field 3), so a refused answer scores SKIPPED:0; plus ns_checkout_of git/pwd fallback branch has no exercised coverage
```

### Entry 7

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Key:** 8093942c

```
> PR body Test Plan says PASS: 180 while docs/evidence/coordinator-model-ab.md says PASS: 184 for the same command after iteration 1; nit: ns_valve_report hand-rolls ## Current item parsing instead of ns_section/ns_kv
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
