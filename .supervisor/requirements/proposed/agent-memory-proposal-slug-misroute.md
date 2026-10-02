# Agent-memory proposals use the agent's short name, so promotion is refused or silently misrouted

## Status: proposed

> **Origin (2026-10-02).** `/dreaming` run 1378d676 promoting the `.supervisor/agent-memory-proposals/` queue. All 10
> queued proposals were unpromotable as written. They were hand-normalized (fences + store slug) and then promoted.

## Evidence
- **7 of 10 proposals had no `---` frontmatter fences.** `write-agent-memory.sh --proposal` refused each one with
  `REFUSE_PROPOSAL_INCOMPLETE — … names no 'agent:' in its frontmatter`, although an `agent:` line was present. This
  failure is safe but blocks promotion.
- **All 10 used a short `agent:` value** (`code-reviewer` ×7, `loomwright:code-reviewer`, `red-team-reviewer`,
  `loomwright:red-team-reviewer`). The live stores are `loomwright-loomwright-code-reviewer/` and
  `loomwright-loomwright-red-team-reviewer/`. A dry run of a fenced proposal (`agent: code-reviewer`) planned
  `target: .claude/agent-memory/code-reviewer/jsonl-appender-accepts-multiline-input.md` plus a rebuilt
  `code-reviewer/MEMORY.md`. That is a **new store directory no agent reads**, created with exit 0. `validate_slug` only
  rejects `/` and `..`. It never checks the slug against existing stores.
- Producers: the agent prompts and `AGENT_GUIDELINES.md` tell agents to write proposals, but nothing tells them the
  on-disk store slug or the fenced format the writer parses.

## Scope (recommendation, trace before fixing)
- Writer: map a known short form (`<agent>`, `loomwright:<agent>`) to the existing `loomwright-loomwright-<agent>`
  store, and REFUSE (exit 1) an agent slug that matches no existing store unless `--new-store` is passed. Never create a
  store directory implicitly from a proposal.
- Writer: either accept unfenced `key: value` frontmatter or name the real problem in the refusal ("no `---`
  frontmatter fence"), not "names no `agent:`".
- Producers: state the exact proposal format (fenced, store slug) wherever agents are told to write proposals.
- Fixtures in `test-write-agent-memory.sh`: a short slug resolves to the store; an unknown slug is refused with no
  directory created; an unfenced proposal gets the accurate refusal.
