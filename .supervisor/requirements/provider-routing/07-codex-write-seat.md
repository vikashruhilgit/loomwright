# 07 — Codex CLI as a write-seat provider (or a documented "read-only only")

## Status: parked — owner has no Codex access yet (2026-11-01); un-park when `codex` is installed and logged in on the owner's machine

**As a** maintainer, **I want** to know whether OpenAI Codex CLI can safely take the `worker` / `heal_fix` /
`drain_fix` seats, and to have it eligible if it can, **so that** I can use it for code changes under 04's controls,
or know for certain why I cannot.

## Why parked
Written ahead of access so the work is not lost. Nothing can be probed without a logged-in `codex`, and a write seat
is eligible only on an OBSERVED denial (05).

## FIRST STEP — re-check the plugin's current state (mandatory, before any design)
Everything below was read on 2026-11-01 at `main @ 26eda74`. Re-read it against `main` before promoting:
1. `loomwright/scripts/adapters/providers/write-run.sh` and `launch-provider-cli.sh` — the write-seat contract and the
   isolated launch (they may have moved since 04).
2. `loomwright/scripts/adapters/providers/provider-codex.sh` and `provider-grok.sh` (reference shape).
3. Re-run `bash loomwright/scripts/setup-providers.sh check` and record the Codex line verbatim.
4. Read Codex CLI's CURRENT official docs (dated): headless/exec mode, sandbox and approval modes, whether any mode
   denies writes outside an allow-list by default, and which config files (user `~/.codex/`, repo-level) it reads.
5. Check `.supervisor/requirements/proposed/` for the 04 follow-up drafts that apply to every provider.

## The gating question (answer before building anything)
**Does Codex have a headless mode that refuses a write unless explicitly allowed?** 04 rests on an observed
default-deny under the isolated launch. If Codex has no such mode, the answer is a documented outcome, not a
workaround: `provider-codex.sh` stays read-only, `check` keeps grading it so, and this item closes with the evidence.
A deny-list is not an acceptable pin (fail-OPEN on any tool it omits — 04's requirement, premise 2).

## Premises as of 2026-11-01 (re-verify — see FIRST STEP)
- `provider-codex.sh` defines `provider_build_argv` and `provider_extract_text` only — **no `provider_write_argv`**
  (`write-run.sh` refuses it as `write_unpinnable`).
- `PROBE_PERM_PIN_FLAGS=""` — **no permission-pin flags are declared at all**.
- `PROVIDER_LOGIN_FILES=()`, `PROVIDER_LOGIN_ENV=()` — no login crosses the isolated HOME, so its read-only seats would
  also fail at login under 05's launcher.
- Owner-machine probe status (04's requirement): `codex` not installed.
- Prior research note (2026-09-30, unverified on a real run): Codex hooks use Claude's field names and
  `{"decision":"block"}`, alias `CLAUDE_PLUGIN_ROOT`, and accept `.claude-plugin/marketplace.json` as a fallback — so it
  may also load this user's Claude plugin hooks; the isolated launch must prevent that, as for Grok.

## Intended shape (only if the gating question is answered yes; rewrite after the FIRST STEP)
- Declare Codex's login file/env so the isolated launch authenticates.
- Declare its real pin flags in `PROBE_PERM_PIN_FLAGS`; add `provider_write_argv` with an allow-list pin, prompt last.
- `check` grades `usable for write seats` only after an observed denial; add the denial fixture.
- Neutralise any user/repo config that can widen the pin, in the launcher.
- Same consent, worktree, disk-gate and Supervisor-only-push rules as 04 (D1, D2).

## Depends on
04-routing-write-seats.md, 05-provider-launch-parity.md (both merged)

## Touches
unknown — decided after the FIRST STEP
