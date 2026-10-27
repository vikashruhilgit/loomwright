# 02 — Provider probe: test every AI CLI headless (check + report script only) + Grok and Copilot table entries

## Status: pending

**As a** maintainer who wants to choose which AI runs which pipeline step,
**I want** one read-only script to tell me, from commands it actually ran, which AI CLIs on this machine are installed,
logged in, usable headless with parseable output, and permission-pinnable,
**so that** routing (items 03–04) is designed against what works on a real machine — not against vendor docs — and I
know exactly what to install or log in to.

## Verified premises (origin/main @ bd4be26, 2026-10-27 — re-verify before dispatch)

- Provider table: `loomwright/scripts/adapters/providers/provider-{claude,codex,cursor,gemini}.sh`, sourced by
  `lens-run.sh`; adding a provider = one new `provider-<name>.sh` (its header). **No Grok, no Copilot.** The codex and
  gemini entries are written from docs and have never run (their own headers say so).
- Only seat using it: Phase 4.5 multi-voter voter (`--voter-provider` / `.voter_provider`, `skills/supervisor-config/SKILL.md`
  step 2.9a; call site `skills/self-heal-advisory/multi-voter.md`). `lens-run.sh`'s sandbox is detection, not
  enforcement; no egress denial; prompt injection via reviewed content unmitigated (its SAFETY POSTURE header).
- On the owner's machine (checked 2026-10-27): `claude` installed; `cursor-agent` installed but not logged in;
  `codex`, `gemini`, `grok`, `copilot` not installed.
- Grok Build headless (docs.x.ai "Headless & Scripting", updated 2026-06-10): `grok -p "<prompt>"`, `-m <model>`,
  `--cwd <path>`, `--output-format plain|json|streaming-json`, `--always-approve`, `--no-auto-update` for scripts,
  ACP via `grok agent stdio`. Permissions are its own TOML rules / `--allow` / `--deny`, not `.claude/settings.json`
  (memory note, verified from the grok-build source 2026-09-29).
- Gemini CLI was sunset for individual users on 2026-06-18 (memory note) — the probe reports it as-is, no special case.
- `scripts/dispatch-pr-review.sh` already refuses to run headless when `claude --help` does not advertise an
  allowlist-honouring permission mode (`PERMISSION_REGIME_UNPINNABLE`) — the precedent for the permission column.
- Owner decision D2′ (`docs/SPIKES/FINAL_STATE_GOAL.md`): the provider-table runner is built only after a real
  second-harness probe, Grok Build first. This item is that probe; it routes nothing.

## Scope

### Part 1 — probe contract in the provider table
Each `provider-<name>.sh` gains probe entries (data, not new logic in `lens-run.sh`): binary name, version command,
auth-check command, a headless smoke invocation that must return a fixed JSON reply, the flag set that pins tool
permissions (or `none`), and whether it can drive a browser (`unknown` until shown). New `provider-grok.sh` and
`provider-copilot.sh` entries; their invocation shapes come from the vendors' current docs, read at build time and cited
with dates in the file header (never from memory).

### Part 2 — `scripts/setup-providers.sh check`
Read-only, fail-safe (always exit 0), portable bash 3.2. For each provider: `installed` (+ version), `auth`
(ok / not_logged_in / unknown), `headless` (pass / fail:<reason> — runs the smoke with a timeout from a throwaway
directory, never in the repo), `permissions` (pinnable / unpinnable / unknown), `browser` (yes / no / unknown). Never
installs anything, never reads, prints or stores an API key or token, never sends repo content (the smoke prompt is a
fixed string). Prints the exact install / login command to run when a column fails.

### Part 3 — verdict line (no `/setup` screen in this item)
`setup-providers.sh check` ends each provider row with a one-line verdict: `usable for read-only seats` (installed +
auth + headless pass), `usable for write seats` (all of that + permissions pinnable), or `not usable: <first failing
column>`. The `/setup providers` screen that renders this table is item 03's, so this item touches no `/setup` file,
no prompt text and no token budget — which is what lets it run in parallel with item 01.

### Part 4 — evidence for 03/04
The PR body (and a short committed note under `loomwright/docs/evidence/`) records the real report from at least
`claude` and `grok` on a real machine, plus every other provider the owner has installed by then — the input that
item 03's premises are rewritten from.

## Acceptance criteria

**Happy path**
- [ ] With `claude` installed and logged in, `bash loomwright/scripts/setup-providers.sh check` shows `claude: installed <ver> · auth ok · headless pass ·
  permissions pinnable` and verdict `usable for write seats`.
- [ ] With `grok` installed and logged in, the row shows real values for every column (no `unknown` in installed / auth /
  headless).
- [ ] `bash loomwright/scripts/setup-providers.sh check` writes nothing anywhere (asserted by the test: repo tree and
  `~/.claude` unchanged before vs after, using a temp HOME).

**Edge cases / errors**
- [ ] A provider binary that is absent → `installed: no`, the install hint, verdict `not usable: installed`; exit 0.
- [ ] Installed but not logged in (e.g. `cursor-agent` today) → `auth: not_logged_in`, the login hint, headless not run.
- [ ] A smoke call that hangs past the timeout → `headless: fail:timeout`, process group killed, exit 0.
- [ ] A smoke call returning unparseable output → `headless: fail:unparseable`.
- [ ] A CLI whose only non-interactive mode auto-approves every tool (e.g. a lone `--always-approve`) →
  `permissions: unpinnable`, so the verdict can never reach `usable for write seats`.
- [ ] Stub-backed test (`test-setup-providers.sh`) covers every column state with fake binaries on `PATH`, like
  `test-lens-run.sh` does.

**Gates**
- [ ] Nothing under `agents/`, `skills/` or `commands/` names a third-party CLI (portability rule in
  `docs/ARCHITECTURE_CONTRACTS.md` §"Portability"); the vendor-coupling ratchet passes.
- [ ] `check-doc-currency.sh` passes; no file under `agents/`, `commands/`, `skills/` or `docs/command-parts/` changes.
- [ ] `bash scripts/check-version-bump.sh` passes.

## Priority: MVP
**Rationale:** D2′ makes this probe the gate for all routing work; it is also immediately useful on its own.

## Assumptions
- Each CLI has an auth check that needs no network-visible side effects beyond its own login check.
- The owner installs and logs in to `grok` (at least) before this item's evidence step; the item does not do it.

## Risks
- Vendor CLIs change fast (Cursor and Codex moved a lot in one month during 2026); the probe reports what is true at run
  time, and the table entries cite their doc dates.
- `PROVIDER_HOME_SCRUB=1` breaks `cursor-agent` login (FINAL_STATE_GOAL); the probe must run with the real HOME for the
  auth column and say so.

## Depends on
none

## Touches
loomwright/scripts/adapters/providers/provider-claude.sh
loomwright/scripts/adapters/providers/provider-codex.sh
loomwright/scripts/adapters/providers/provider-cursor.sh
loomwright/scripts/adapters/providers/provider-gemini.sh
loomwright/scripts/adapters/providers/provider-grok.sh
loomwright/scripts/adapters/providers/provider-copilot.sh
loomwright/scripts/setup-providers.sh
loomwright/scripts/test-setup-providers.sh
loomwright/docs/evidence
loomwright/docs/vendor-coupling-manifest.json
