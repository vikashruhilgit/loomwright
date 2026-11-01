# 08 — Antigravity (Gemini's successor) as a provider — adapter, then write seat

## Status: parked — owner has no Antigravity access yet (2026-11-01); un-park when it is installed and logged in on the owner's machine

**As a** maintainer, **I want** Google's current agent CLI to be a routable provider, and eligible for write seats if it
passes the probe, **so that** a Google model is available the same way Grok is.

## Why parked
Written ahead of access so the work is not lost. Nothing can be probed without a logged-in install, and a write seat is
eligible only on an OBSERVED denial (05).

## FIRST STEP — re-check the plugin's current state AND what Google ships (mandatory, before any design)
Everything below was read on 2026-11-01 at `main @ 26eda74`. Re-read it against `main` before promoting:
1. **Is Gemini CLI still the right target?** A 2026-09-30 research note says Gemini CLI was sunset for individual
   users on 2026-06-18 in favour of the Antigravity CLI. That note is unverified and was never researched further.
   Confirm from Google's CURRENT official docs (dated) which CLI is current for the owner's account type.
2. **Does Antigravity ship a headless CLI** (non-interactive prompt in, result out, no IDE)? If it is IDE-only, this
   item closes as "not routable" with that evidence — a seat needs a headless CLI.
3. If headless: its print/exec mode, output format, tool allow/deny flags, default permission behaviour, login
   storage (file or keychain — a keychain login cannot cross the isolated HOME, as `claude`/`cursor-agent` showed), and
   which settings files it reads (does it read `~/.claude/settings.json` like Grok?).
4. `loomwright/scripts/adapters/providers/write-run.sh`, `launch-provider-cli.sh`, `provider-gemini.sh`, and
   `provider-grok.sh` (reference shape).
5. Re-run `bash loomwright/scripts/setup-providers.sh check` and record the Gemini/Antigravity lines verbatim.
6. Check `.supervisor/requirements/proposed/` for the 04 follow-up drafts that apply to every provider.

## Premises as of 2026-11-01 (re-verify — see FIRST STEP)
- **There is no Antigravity adapter** in `loomwright/scripts/adapters/providers/`; nothing in `loomwright/` mentions it.
- `provider-gemini.sh` exists: `provider_build_argv` / `provider_extract_text` only, no `provider_write_argv`,
  `PROBE_PERM_PIN_FLAGS=""`, and `PROVIDER_LOGIN_FILES=()` / `PROVIDER_LOGIN_ENV=()` (no login crosses the isolated HOME).
- Owner-machine probe status (04's requirement): `gemini` not installed; no `antigravity`/`agy` binary on PATH.
- Prior research note (2026-09-30, unverified): Gemini CLI had no subagent nesting and no SubagentStop.

## Intended shape (rewrite after the FIRST STEP)
- **Part A — read-only provider:** new `provider-antigravity.sh` (name per the real binary), declared login pass-through,
  probe entries, a `check` line, read-only seats through 03/05's path. Decide whether `provider-gemini.sh` is retired,
  kept for accounts that still have Gemini CLI, or aliased.
- **Part B — write seat (only if it passes):** `provider_write_argv` with an allow-list pin, `check` grading
  `usable for write seats` only after an observed denial, launcher neutralising any settings file that widens the pin.
  Same consent, worktree, disk-gate and Supervisor-only-push rules as 04 (D1, D2).
- Part B may split into its own item if Part A alone is right-sized.

## Depends on
04-routing-write-seats.md, 05-provider-launch-parity.md (both merged)

## Touches
unknown — decided after the FIRST STEP
