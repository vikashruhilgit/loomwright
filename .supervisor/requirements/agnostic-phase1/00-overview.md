# 00 — Agent-agnostic Phase 1 overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp is what keeps `/automate` from enqueuing this file)

## Where this queue comes from
A flow-level audit of every Claude Code dependency in the plugin (2026-09-30), then a validation pass of every claim
against `main` at `d927996`, Claude Code's current docs (installed CLI v2.1.284) and the official docs/source of
Cursor, Codex, Copilot CLI, OpenCode, Gemini CLI and xAI Grok Build. Phase 1 fixes what is broken or misleading
**on Claude Code today** and stops the coupling from growing, before any harness-porting work (Phase 2) starts.
Phase 2 is NOT in this folder; it waits on the owner's FINAL_STATE_GOAL D1/D2 decision.

## The five items
| # | Item | Why it is first-class |
|---|---|---|
| 01 | Vendor-coupling ratchet hardening | The ratchet grew 574 → 806 in a month and cannot see the real coupling classes. Lands FIRST so 02–05 and all of Phase 2 are measured. |
| 02 | Completion-evidence integrity | FINALIZE passes with zero evidence (`no_identity_rows`); one worker spawn shape is never validated, recorded, or guarded. |
| 03 | Silent script failures | `run-lock.sh` records a dead pid outside Claude Code; the guard's hook arm path fails silently. |
| 04 | Non-interactive question gates | Product Owner's pre-persist gate has no non-interactive branch and `/automate` calls it; Claude Code strips `AskUserQuestion` from every subagent. |
| 05 | Docs & hygiene sweep | Stale "subagents cannot nest" premise, stale platform claims, one code-level memory-path bug, frontmatter defects. |

## Order
01 → 02 → 03 → 04 → 05 (`/automate --folder .supervisor/requirements/agnostic-phase1`). 01 must land first. 02–05
touch disjoint files except CHANGELOG / plugin.json version bumps; run sequentially, never in parallel.

## Cross-cutting facts every item must respect (verified 2026-09-30 at `a262d00`)
- Claude Code v2.1.284 facts (code.claude.com/docs, read 2026-09-30): subagents MAY spawn subagents up to three
  layers below the main conversation (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`); `AskUserQuestion` is removed from
  EVERY subagent's tool set regardless of its `tools:` list; a per-invocation `model` parameter is honoured FIRST in
  model resolution and persists on resume; plugin agents ignore only `hooks`, `mcpServers`, `permissionMode`
  frontmatter; Claude Code reads `AGENTS.md` natively (v2.1.277+) when no CLAUDE.md is on the path.
- Bimodal failure philosophy (CLAUDE.md §"Failure-Mode Invariants"): correctness gates fail CLOSED under
  non-interactive/CI/non-TTY; runtime side-effect emitters and every `|| true` hook ALWAYS exit 0. Nothing in this
  queue may make a `|| true` hook exit non-zero, and nothing may make a gate silently proceed.
- Command-hook block shape: `{"decision":"block","reason":…}` / `exit 2`; `{"ok":false}` blocks nothing.
- Run the FULL test loop before pushing: every `loomwright/scripts/test-*.sh` AND root `scripts/test-*.sh` +
  `scripts/check-vendor-coupling.sh` + `scripts/check-token-budget.sh` + `scripts/check-doc-currency.sh`.
- Any agent-prompt growth needs a budget raise in `loomwright/docs/prompt-token-budgets.json` + the mirror row in
  `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets", measured live (worker headroom has historically been ~29).

## Evidence
Audit + validation files were session scratch (not committed). Every item below carries its own "Verified premises"
block with the exact lines to re-read — re-read them, `main` moves.
