# 03 — Per-step provider routing (`/setup providers` + config + user-scoped consent + read-only seats) — STUB

## Status: proposed (stub — premises depend on item 02's probe report; rewrite the Verified premises from that report, then promote to `pending`)

**As a** maintainer, **I want** to pick which AI CLI runs each read-only pipeline step, with Claude as the default
everywhere, **so that** I can use other models for review and analysis without changing the conductor or giving any repo
the power to send my code to a vendor I did not approve.

## Intended shape (to be re-verified, not built from this text)

- **Config:** `.supervisor/config.json` `routing` = `{ "default": "claude", "on_unavailable": "fallback_to_default" |
  "strict", "seats": { "<seat>": "<provider>[:<model>]" | [ ... ] } }`. No `routing` block ⇒ today's behaviour exactly.
  `.voter_provider` / `--voter-provider` become the `heal_voter` seat (back-compatible alias). Per-run flag overrides.
- **Consent (user scope, never repo scope):** a per-repo, per-provider grant in `~/.claude/loomwright/egress.json`,
  read by `resolve-egress-config.sh`. A seat routed to a provider without a grant falls back to the default and logs
  `provider_not_granted` — it never sends. `lens-run.sh` checks the grant before starting any non-default CLI.
- **`/setup providers` module** (moved here from the probe item so the probe could run in wave 1): `status` renders
  `setup-providers.sh check`'s table and verdicts; `apply` offers only providers item 02 marked usable and writes the
  routing block (backup-first) and, after an explicit ask that names what will be sent, the user-scope grant; `remove`
  deletes both. Registry row in `skills/setup/SKILL.md`, flow part under `docs/command-parts/setup/`, folded into an
  existing dashboard bucket (four-option cap not grown). Lands after item 01, which also edits these files.
- **Read-only seats** via a generalized `lens-run.sh` (role-aware prompt + output contract per role): plan-reviewer,
  orchestrator, Phase 4.5 integrated reviewer, rubric-grader, voter, refute, drain reviewer, Earned Fallback Review,
  `/autonomous` EVALUATE reviewer, pr-postmortem classification, dreaming analysis, propose, capability-check, and the
  standalone red-team / code-reviewer / product-owner / qa-strategist commands. Each seat's output still goes through the
  same result-block validation as the Claude path.
- **Not routable:** the conductor (see 00-overview).
- **Cost honesty (D11):** non-Claude usage is `cost: unknown`, never `0`; no "cheaper" claim without measured cost.

## Open questions for the owner (answer before promoting)
- Per-seat model suffixes (`grok:grok-4.7`) or provider only?
- `on_unavailable` default: `fallback_to_default` (recommended) or `strict`?
- Split postmortem/dreaming/propose into their own item if the token budgets of the touched skills breach?

## Depends on
01-base-branch-configurable.md
02-providers-probe.md

## Touches
unknown
