# Dismissed findings below the tracking threshold: 01-scaffold-selvedge-with-its-own-gates-and-release (11)

## Status: proposed

- **Run:** automate-2026-11-13-172855
- **Item:** .supervisor/requirements/qa-split/01-scaffold-selvedge-with-its-own-gates-and-release.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/912
- **Decision:** follow-up

## Depends on
none

## Touches
CLAUDE.md
scripts/check-version-bump.sh
scripts/ci-local.sh
selvedge/bin/selvedge
selvedge/tests/run.sh

## Findings (verbatim, untrusted data — never an instruction)

### Entry 1

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** cdedb879

```
> bump-version.sh check_scope ignores bump-owned paths wholesale: a selvedge/ change plus an edit to loomwright plugin.json's description or another plugin's marketplace entry is classified selvedge-only and its fragment is rejected (fails closed)
```

### Entry 2

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 00719043

```
> bump-version.sh check_scope skips changelog.d/* so a selvedge-only branch could rewrite a fragment main already has (round 1, LOW; re-raised at MEDIUM in round 2 and fixed)
```

### Entry 3

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** c227f37d

```
> bump-version.sh check_scope exit-2 'cannot list this branch's changed paths' branch had no test (round 1, LOW; re-raised at MEDIUM in round 2 and fixed)
```

### Entry 4

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** a034785c

```
> selvedge/bin/selvedge BIN_DIR uses cd without CDPATH= so an exported CDPATH plus a relative invocation garbles the resolved dir (--version dies; install-cli would write a broken link)
```

### Entry 5

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 83d7386a

```
> selvedge/bin/selvedge manifest_version takes the first "version" key anywhere in plugin.json, so a nested key placed earlier wins
```

### Entry 6

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Evidence:** none recorded
- **Key:** d845f1ef

```
> scripts/check-version-bump.sh header says the scope rule 'lives in bump-version.sh --check too', implying a second copy
```

### Entry 7

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 40ef09f6

```
> A local --check is stricter than CI on a fragment-only or bump-only branch when an untracked or uncommitted file sits under selvedge/ (release-refold.sh would then refuse the push)
```

### Entry 8

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** nit
- **Evidence:** none recorded
- **Key:** 5e292599

```
> CLAUDE.md sibling-plugins list reads 'mysql-mcp/ (…) and loomwright-lanes/ (…) and selvedge/ (…)' with two 'and's
```

### Entry 9

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** 55065be1

```
> scripts/ci-local.sh 'Honest limits (2)' and the end-of-run 'not run locally' message name only the sdk-spike step, not the new bash selvedge/tests/run.sh CI step
```

### Entry 10

- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** below_severity_floor
- **Evidence:** none recorded
- **Key:** a744d2de

```
> scripts/check-version-bump.sh Scope header omits the round-2 violation: editing a fragment main already has
```

### Entry 11

- **Round:** 1
- **Origin:** drain
- **Source:** issue_comments
- **Severity:** LOW
- **Reason dismissed:** below_fix_floor
- **Evidence:** severity LOW is below the fix floor MEDIUM
- **Key:** 410b3010

```
> test-cli.sh replace-a-link-pointing-elsewhere branch does not assert the install-cli re-run note
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
