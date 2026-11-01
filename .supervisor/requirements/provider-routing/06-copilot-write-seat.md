# 06 — Copilot CLI as a write-seat provider

## Status: parked — owner has no Copilot CLI access yet (2026-11-01); un-park when `copilot` is installed and logged in on the owner's machine

**As a** maintainer, **I want** GitHub Copilot CLI to be eligible for the `worker` / `heal_fix` / `drain_fix` seats,
**so that** I can pick it for code changes under the same controls 04 built for Grok.

## Why parked
Written ahead of access so the work is not lost. The owner cannot install or log in to Copilot CLI today, so nothing
here can be probed, and a write seat is eligible only on an OBSERVED denial (05), never on help text or docs.

## FIRST STEP — re-check the plugin's current state (mandatory, before any design)
Everything below was read on 2026-11-01 at `main @ 26eda74` (v17.24.x). Re-read it against `main` before promoting:
1. `loomwright/scripts/adapters/providers/write-run.sh` — the write-seat contract (`provider_write_argv`, refusals,
   tamper/restore). It may have moved since 04.
2. `loomwright/scripts/adapters/providers/launch-provider-cli.sh` — isolated HOME, declared login pass-through, the
   `.claude/` copy guard.
3. `loomwright/scripts/adapters/providers/provider-copilot.sh` and `provider-grok.sh` (the one working write provider,
   the reference shape).
4. Re-run `bash loomwright/scripts/setup-providers.sh check` on the owner's machine and record the Copilot line verbatim.
5. Read Copilot CLI's CURRENT official docs (dated) for headless mode, tool allow/deny flags, default permission
   behaviour, and which settings files it reads. Never cite this file's notes as current.
6. Check `.supervisor/requirements/proposed/` for the 04 follow-up drafts (repo-level config merging into the pin,
   `.claude/settings*.json` written mid-launch); fix or account for them first, because they apply to every provider.

## Premises as of 2026-11-01 (re-verify — see FIRST STEP)
- `provider-copilot.sh` defines `provider_build_argv` and `provider_extract_text` only — **no `provider_write_argv`**,
  so `write-run.sh` refuses it today as `write_unpinnable`.
- `PROBE_PERM_PIN_FLAGS="--allow-tool --deny-tool --available-tools"` — candidate pin flags exist on paper.
- `PROVIDER_LOGIN_FILES=()` and `PROVIDER_LOGIN_ENV=()` — **no login is declared to cross the isolated HOME**, so under
  05's launcher even its read-only seats would fail at login. Declaring the real login file or token variable is part
  of this item.
- Owner-machine probe status (04's requirement): `copilot` not installed.
- Prior research note (2026-09-30, unverified on a real run): Copilot CLI reads Claude's plugin/hook formats and
  `.claude/settings.json`; hook timeouts fail OPEN. Reading `.claude/settings.json` is exactly the Grok failure mode
  (a `permissions.defaultMode` there overrode the CLI pin), so the isolated launch is load-bearing here too.

## Intended shape (rewrite after the FIRST STEP)
- Declare Copilot's login file/env in `provider-copilot.sh` so the isolated launch can authenticate.
- Add `provider_write_argv` with an allow-list pin (read/search/edit/write tools only), prompt last, mirroring Grok.
- `setup-providers.sh check` must grade it `usable for write seats` only after an observed denial under the isolated
  launch; add a test fixture for the denial case.
- Probe whether any settings file Copilot reads (user or repo level) can widen the pin, and refuse or neutralise it
  in the launcher the way 04 handles `~/.claude/settings.json`.
- Same consent, worktree, disk-gate and Supervisor-only-push rules as 04 (D1 one provider per run; D2 fix seats default
  to Claude).

## Depends on
04-routing-write-seats.md, 05-provider-launch-parity.md (both merged)

## Touches
unknown — decided after the FIRST STEP
