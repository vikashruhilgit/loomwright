# Shared Agent Prefix (Canonical Source)

> **Byte-identity contract:** the block between the `SHARED-AGENT-PREFIX v1 BEGIN/END` markers below is the SINGLE canonical source of the shared leading block that every `loomwright/agents/*.md` prompt opens with (immediately after its YAML frontmatter, before any role-specific content). Each agent file must contain the block — marker lines included — **byte-identically and exactly once**. `scripts/check-shared-prefix.sh` enforces this in CI and fails CLOSED (non-zero exit, no `|| true`) on any drift, missing block, duplicate block, or a missing/malformed canonical file. To change the block: edit it HERE, re-apply it byte-identically to every `loomwright/agents/*.md` file in the same PR, and let the gate prove identity.
>
> **HONEST CACHE EXPECTATION (do not overclaim):** this shared block does **NOT** buy cross-agent prompt-cache hits. Prompt caching is a prefix match over the whole rendered request, and `tools` render before the system prompt — each agent type carries a different `tools:`/`disallowedTools:` frontmatter set, so two different agent types diverge at position 0 no matter how byte-identical their `.md` openings are. The value of this block is **consistency, dedup, and a smaller prompt inventory**. The real cache win is SAME-ROLE respawns (Phase 3 worker waves, heal-loop reviewer/fix-worker spawns), which already share identical agent files — served by volatile-last ordering (see `docs/POINTER_AUDIT.md`), not by this block.

**Placement rule (per agent file):** frontmatter → shared block → role-specific content → preloaded-skills-dependent content → volatile content. The shared block applies to `loomwright/agents/*.md` ONLY — inline command surfaces (`commands/launch-pad.md`, `commands/supervisor.md`) never load it, so any bullet deduplicated out of an agent's Critical Rules must be RETAINED in the mirrored `commands/*.md` lists.

**Why this file lives under `docs/`:** an `agents/`-resident `.md` would be counted as an extra agent by `scripts/check-token-budget.sh` (fail-CLOSED on a missing budget) and `scripts/check-doc-currency.sh` (agent count). The CI check reads the canonical block from this one path.

**Token-budget interplay:** the block adds spawn-time prompt-inventory weight to every agent; budget raises driven by it are recorded in `loomwright/docs/prompt-token-budgets.json` (+ the `ARCHITECTURE_CONTRACTS.md` mirror) with a one-line justification referencing this block, per the gate's raise rule.

---

<!-- SHARED-AGENT-PREFIX v1 BEGIN -->
## Shared Agent Contract

Baseline contract for every Loomwright agent (full standard: `AGENT_GUIDELINES.md`). Role-specific contracts below extend or specialize this baseline.

- **Mission:** deliver the smallest correct thing that advances the objective — surgical changes, existing patterns, no scope creep.
- **Safety:** no destructive actions without explicit approval; never invent files, APIs, or paths — verify against the codebase or ask when unsure; no secrets or PII in code, logs, or output.
- **Escalation:** merge conflicts always escalate — never force-resolve.
- **Output:** default result structure is Context Read → Plan → Work → Results → Risks; where the role defines its own output contract (structured result block or response template), that role contract is authoritative.
<!-- SHARED-AGENT-PREFIX v1 END -->
