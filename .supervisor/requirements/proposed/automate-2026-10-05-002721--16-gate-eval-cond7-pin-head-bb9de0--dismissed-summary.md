# Dismissed findings below the tracking threshold: 16-gate-eval-cond7-pin-head (6)

## Status: proposed

- **Run:** automate-2026-10-05-002721
- **Item:** .supervisor/requirements/automate-followups/16-gate-eval-cond7-pin-head.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/384
- **Decision:** follow-up

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** e9b52db9

```
> read-failure branches of the three new ls-files reads not tested on their own
```

### Entry 2

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Key:** d03561a3

```
> SKILL §10 cites review-heal Step 1 heading without the (isolation-aware) suffix
```

### Entry 3

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** bcc46ebd

```
> repo-local core.worktree redirects the pin's reads to another tree while the helper reads --root (dirty root MERGEd)
```

### Entry 4

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** dc4a3b49

```
> with HOME unset git config --global exits 128 and every clean at-head checkout parks rules_gate_dirty_tree
```

### Entry 5

- **Round:** 2
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Key:** 6e17cfe1

```
> test gate() relocates HOME but not XDG_CONFIG_HOME / system git config; R11h not hermetic
```

### Entry 6

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** invalid: gate_eval already nests J() and _ge_rules_ids() with a documented scope comment — follows the function's own convention
- **Key:** 0d332c3d

```
> _ge_git() nested inside gate_eval() unlike top-level _ge_* helpers (review of 8dce99b)
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
