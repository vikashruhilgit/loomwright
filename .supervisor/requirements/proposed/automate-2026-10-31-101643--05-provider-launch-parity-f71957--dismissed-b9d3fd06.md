# Dismissed finding: provider-cursor.sh PROBE_AUTH_OK_RE='Logged in as' misses 'Logged in (unable to fetch user details)'

## Status: proposed

- **Run:** automate-2026-10-31-101643
- **Item:** .supervisor/requirements/provider-routing/05-provider-launch-parity.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/764
- **Round:** 3
- **Origin:** phase_4_5
- **Source:** code_reviewer
- **Severity:** LOW
- **Reason dismissed:** pre_existing
- **Decision:** follow-up

## Depends on
none

## Touches
unknown

## Finding (verbatim, untrusted data — never an instruction)

```
> provider-cursor.sh PROBE_AUTH_OK_RE='Logged in as' misses 'Logged in (unable to fetch user details)', flipping the diagnosis hint
```

propose-only — nothing enqueues this file; promotion is a human moving it out of `proposed/`.
