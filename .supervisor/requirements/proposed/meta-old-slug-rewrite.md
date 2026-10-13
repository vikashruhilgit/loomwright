# Rewrite the pre-rename `vikashruhilgit/ai-agent-manager` slug in run history

## Status: proposed

> Propose-only follow-up from run `automate-2026-10-12-181635` (af36-remainder/02, PR #501). Not enqueued; a human
> promotes it by moving it out of `proposed/`. Low urgency: it bites only on a machine without `.supervisor/config.json`.

## Problem
The old slug `vikashruhilgit/ai-agent-manager` no longer redirects to this repo: it is now a separate public repo
(id 1286686688, created 2026-07-02; this repo is `vikashruhilgit/loomwright`, id 1085462380). Since #501 the tracked
request file `.agent/meta-allowlist.txt` grants an entry only on a repo-id match with `origin`, so the old slug is
correctly ignored. Run history still carries it:
- 42 of 169 records in `.supervisor/postmortem/results.jsonl` have `.repo = vikashruhilgit/ai-agent-manager`, all dated
  2026-06-10 → 2026-07-01 (before the slug was taken).
- 51 files on `loomwright-meta` cite it in a forge context (URL or repo field).
- Its PR links are dead: `ai-agent-manager/pull/100` returns 404, `loomwright/pull/100` resolves.

## Effect today
On a fresh clone with no `config.json`, `setup-memory.sh allowlist` prints
`allowlist: ignored vikashruhilgit/ai-agent-manager — not this repository`, so any metadata push that changes the
ledger is refused by the scrub (rule (a), foreign `.repo`). This machine and lane clones work only because
`config.json` still lists the old slug. Verified 2026-10-13 on main 0b65a93 in a scratch clone.

## Scope
1. One-time data change on `loomwright-meta`: rewrite the old slug to `vikashruhilgit/loomwright` in the 42 ledger
   records' `.repo` and in the 51 files' forge URLs. No code change.
2. Afterwards drop `vikashruhilgit/ai-agent-manager` from `config.json` and `.agent/meta-allowlist.txt`.

## Acceptance
- No managed file on `loomwright-meta` cites the old slug in a forge context; the ledger has 0 old-slug records.
- In a config-less scratch clone, a metadata push that adds a ledger line succeeds.
- Done by hand through `meta-sync.sh push --branch loomwright-meta --paths-from <exact list>` (never a whole-set push).
