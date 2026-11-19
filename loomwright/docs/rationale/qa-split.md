# Rationale — the QA split

Why Loomwright's own QA system (the `qa-strategist` and `qa-executor` agents, the `/qa-strategist`,
`/qa-executor` and `/verify` commands, their skills, hooks and agent memory) was removed, and where its
useful part went. History by design: this doc records a decision and is not read at runtime.

## Why

- **It had zero runs where it mattered.** Nothing in Loomwright's delivery loop (Supervisor, Execute
  Manager, Worker, Launch Pad, `/autonomous`, `/automate`) ever spawned a QA agent or ran `/verify`.
  `/verify` had zero runs anywhere; the QA agents had two manual runs ever, both on one project. The
  plan's §2 "Facts" table records how each fact was checked.
- **Every release still paid for it.** The QA files were carried through every count, token-budget,
  history-reference, vendor-coupling and doc-currency gate, and through review rounds on any change near
  them. That drift cost was paid on each release whether or not anyone used QA.
- **Decision D1 (owner): remove all QA from Loomwright.** No QA agent, command, skill, schema, hook, CI
  cache or agent-memory dir stays. Decision D2 keeps only the evidenced part: one PASS / FAIL / BLOCKED /
  NOT_VERIFIABLE verdict per acceptance criterion. That part is rebuilt as the separate Selvedge plugin
  (`selvedge/`), which deliberately does not carry over the Strategist's risk-strategy role, the
  Executor's test generation and exploration, or the debate and audit gates.

## What replaces what

| Removed | Replacement |
|---|---|
| `/qa-executor`, `/verify` | `/selvedge:verify` and the `selvedge` CLI |
| `/qa-strategist` | none — its risk-strategy role is not carried over (D2) |

Install Selvedge with `/plugin install selvedge@atelier`, then put its CLI on `PATH` with
`selvedge install-cli` (before that first run, call the installed copy's own `bin/selvedge install-cli`;
the Selvedge README's "Install" section has the exact path).

## How the removal is done

- **Plan:** `.supervisor/requirements/qa-split/00-plan.md` (decisions D1 and D2, the order of the PRs).
- **Manifest:** `loomwright/docs/qa-removal-manifest.md` lists every QA path and named reference, each
  marked `delete`, `re-point` or `keep` with the PR that acts on it, and
  `loomwright/scripts/check-qa-removal-manifest.sh` checks each removal PR against it row by row.
- **Three PRs:** 11b1 removes the agents, commands, skills, hooks and agent memory; 11b2 removes the
  scripts, schema docs, blueprint and CI Playwright steps left without a caller; 12 points the remaining
  surfaces at Selvedge.

## Rollback

The tag `pre-qa-removal` marks the last commit before any QA file was removed. Restore one file with
`git checkout pre-qa-removal -- <path>`, or look at the whole old system with
`git worktree add <dir> pre-qa-removal`. The tag's sha and how it was recorded are in
`docs/evidence/qa-split-11b1-removal.md`.
