# Task: doc-currency-green

## What this task asks

Plugin doc/count claims (agent/command/skill/hook counts, version
annotations) must stay consistent with the authoritative sources; the
doc-currency gate must be green.

The authoritative sources are `plugin.json`, `hooks.json`, and the
`agents/`/`commands/`/`skills/` directories. Any doc surface asserting a
stale plugin version or a stale agent/command/skill/hook count is drift
and must be fixed in the same change that moved the source of truth.

## How it's checked

`check.sh` resolves the repo root (via `git rev-parse --show-toplevel`)
and runs the repo-root doc-currency gate:

```
bash scripts/check-doc-currency.sh
```

It exits with that gate's status — exit 0 (clean) = pass, non-zero
(drift detected) = fail. The check is deterministic: the same repo state
always yields the same result, and it is read-only (modifies no files).
