# 03 — Per-step provider routing (`/setup providers` + config + user-scoped consent + read-only seats) — STUB

## Status: pending

**As a** maintainer, **I want** to pick which AI CLI runs each read-only pipeline step, with Claude as the default
everywhere, **so that** I can use other models for review and analysis without changing the conductor or giving any repo
the power to send my code to a vendor I did not approve.

## Verified premises (2026-10-28, from `setup-providers.sh check` on main @ b0109dd and a read of the cited files)

- **Probe report (item 02, PR #723).** `bash loomwright/scripts/setup-providers.sh check` (read-only, ~38s, exit 0)
  verdicts on the owner's machine:
  - `claude` 2.1.312 — auth ok · headless pass · permissions pinnable ⇒ **usable for write seats**
  - `cursor` (`cursor-agent` 2026.10.22) — auth ok · headless pass · permissions **unpinnable** ⇒ **usable for read-only seats**
  - `codex`, `copilot`, `gemini`, `grok` — **not installed** ⇒ not usable (each line prints its install command)

  So on this machine the only non-default provider `/setup providers apply` may offer today is `cursor`, for
  read-only seats. Grok, the provider the owner said to always include, has a table entry
  (`provider-grok.sh`) but is not installed, so it is still **unprobed**. The module must render whatever `check`
  reports at run time and never hard-code this list.
- **Provider table.** `loomwright/scripts/adapters/providers/` holds `provider-{claude,codex,copilot,cursor,gemini,grok}.sh`
  plus `lens-run.sh` and `lens-compare.sh`. `setup-providers.sh` (usage: `setup-providers.sh check`, nothing else) lives
  in `loomwright/scripts/`.
- **`lens-run.sh` today.** Takes `--provider <name>[:<model>] --role <role> --diff --prompt --out [--commit]`. `--role`
  is "free-form … Not branched on here", so the role-aware prompt and output contract this item needs is new work.
  Output is review-shaped only (`lens_status`, `issues[]` in the CODE_REVIEW_RESULT `issues[]` field shape,
  `cost: "unknown"`). Four exit-0 degradations: `provider_unavailable`, `lens_mutated_tree`, `lens_unparseable`, `ok`.
  It makes **no consent/egress check** (its only "egress" mention is the SAFETY POSTURE note that there is no
  network-egress denial), so the grant check is new. Non-review seats (orchestrator, rubric-grader, postmortem
  classification, …) need output shapes other than `issues[]`.
- **Consent store.** `resolve-egress-config.sh` reads `~/.claude/loomwright/egress.json`
  (`schema_version: 1`, `repos.<slug>.{telemetry, telemetry_repo, webhook_url, webhook_url_sha256}`). It always exits 0
  and fails closed (all values empty) on an unreadable or malformed file. It has **no provider-grant key**. A
  `repos.<slug>.providers` grant (or similar) and a new output key are new. Repo-relative values must stay `REPO_REQUESTED_*`
  only, per its SECURITY CONTRACT.
- **Voter alias.** `--voter-provider` / `.supervisor/config.json` `.voter_provider` are parsed in
  `skills/supervisor-config/SKILL.md` step 2.9a (flag wins over config; both absent ⇒ `""` ⇒ byte-identical
  red-team-reviewer Task). It is consumed only by `skills/self-heal-advisory/multi-voter.md` §"Multi-voter verification" under
  `--multi-voter-heal`. Mapping it onto the `heal_voter` seat must keep that empty-default path byte-identical.
- **No `routing` key exists** anywhere under `loomwright/` today (`git grep` for `"routing"` / `.routing` is empty),
  so the "no `routing` block ⇒ today's behaviour exactly" default is unconstrained by existing code.
- **`/setup` registry.** `skills/setup/SKILL.md` has rows for `webhook`, `memory`, `base-branch` (item 01's, PR #724)
  among others. Flow parts live in `docs/command-parts/setup/` (`base-branch.md`, `dashboard.md`, `ex.md`,
  `memory.md`, `obs.md`, `other.md`, `rules.md`, `statusline.md`; no `providers.md` yet). The dashboard's
  `AskUserQuestion` is capped at 4 options (`dashboard.md`, the "accepts at most 4 options" rule), so `providers` must
  fold into an existing bucket. Item 01 has merged, so the "lands after item 01" ordering constraint is already met.
- **Portability hand-over is still open.** `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Portability" ("Second
  example: the provider-lens adapter") still restates `` `claude`, `cursor`, `codex`, `gemini` as of this writing ``,
  which is stale (it omits `copilot` and `grok`). The acceptance criterion below stands as written.

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
- **Handed over from item 02 (owner override, Launch Pad Phase 6, 2026-10-27):** item 02 adds `provider-grok.sh` and
  `provider-copilot.sh` but leaves `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Portability" ("Second example") listing
  `` `claude`, `cursor`, `codex`, `gemini` as of this writing ``, to stay file-disjoint from item 01. This item replaces that
  restated list with a pointer to the `provider-*.sh` files in `loomwright/scripts/adapters/providers/`. Acceptance
  criterion: after this item, `git grep -nF 'gemini' -- loomwright/docs/ARCHITECTURE_CONTRACTS.md` finds no restated provider list.

## Owner decisions (2026-10-28, answered before promoting)
- **Seat value:** `<provider>[:<model>]`, with the model suffix optional (e.g. `grok:grok-4.7`). This is the same shape
  `lens-run.sh --provider` and `--voter-provider` already accept.
- **`on_unavailable` default:** `fallback_to_default`. The seat runs on the default provider and the reason is logged.
  `strict` stays an opt-in value.
- **Split rule:** keep postmortem, dreaming and propose in this item. Move them to their own item only if the touched
  skills breach their token budgets (`check-token-budget.sh`).

## Depends on
01-base-branch-configurable.md
02-providers-probe.md

## Touches
unknown (beyond this, at least: loomwright/docs/ARCHITECTURE_CONTRACTS.md — the provider-list pointer handed over from item 02)

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-28T15:25:17Z
- **Brief:** .supervisor/jobs/done/2026-10-28-provider-routing-readonly-seats.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/746
