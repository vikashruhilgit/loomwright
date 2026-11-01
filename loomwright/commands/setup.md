---
description: Umbrella setup command — status dashboard plus guided configuration for every optional plugin capability — observability (local Langfuse + OTel collector), memory in version control, portable house-rule seeding, telemetry, notifications, webhook, Beads, MySQL MCP, opt-in status line, the project's base branch
---

# Command: /setup

## Usage

```
/setup                      # Status dashboard (one row per module) + multi-select "what do you want to configure?"
/setup observability        # Observability module directly: init | status | remove
/setup memory               # Put the Twin memory stores under version control IN PLACE (gitignore negation + repo allowlist): status | apply | remove | migrate
/setup rules                # Seed .agent/rules/ with PORTABLE conventions on a cold-start repo (labelled seeded, not learned): status | (no-arg → seed)
/setup statusline           # Wire the one-line run report into the user-scope settings file: status | apply | remove
/setup base-branch          # View / pin the base (integration) branch in .supervisor/config.json: status | set <branch> | remove
/setup providers            # Route read and write seats to another AI CLI: status | apply | remove
/setup telemetry            # DELEGATES to /telemetry (no consent logic duplicated here)
/setup notifications        # Status + guidance (notification hooks are always-on)
/setup webhook              # Status + guided write of the user-scope webhook URL (LOOMWRIGHT_WEBHOOK_URL still wins when set)
/setup beads                # Status + guidance (bd CLI + .beads/)
/setup mysql-mcp            # Status + guidance (DB_* env for the read-only MySQL MCP — separate mysql-mcp@atelier plugin)
/setup --help               # Every module and its subcommands, from the skill's module registry (also -h, help)
```

## Parameters

- **module** (optional): one of `observability`, `telemetry`, `notifications`, `webhook`, `beads`, `mysql-mcp`, `memory`, `rules`, `statusline`, `base-branch`, `providers` — the `skills/setup/SKILL.md` Pattern 2 registry is the authority (`test-setup-module-registry.sh` checks this list against it).
  - If omitted: run the full status dashboard, then offer configuration via `AskUserQuestion` (multi-select).
  - If `--help`, `-h` or `help`, or unrecognised: see Help and unknown module below — never the dashboard.
- **subcommand** (optional, second positional arg): one from the module's registry Subcommands cell (the help prints them; every `status` is a read-only report). If omitted, the module's check step decides — e.g. observability: unconfigured → offer `init`; configured → offer `status` / `remove` / reconfigure. Why a module requires or lacks `remove`, or never replaces a foreign status line unasked: its registry row and part.

## What This Does

`/setup` is the single entry point for checking and configuring the plugin's optional capabilities. Every module follows the same contract (authority: the `setup` skill, read at Step 0):

> **check → report → offer → apply → verify** — idempotent, and never blind-overwrite.

Settled design facts (do not re-litigate at runtime):

- **The plugin emits NO spans itself.** Claude Code's native OpenTelemetry telemetry (`CLAUDE_CODE_ENABLE_TELEMETRY=1`) is the only emitter. `/setup observability` configures *where those signals go*, nothing more.
- **Langfuse's OTLP endpoint (`/api/public/otel`) ingests TRACES ONLY.** Metrics and logs are not ingested by Langfuse. The bundled collector terminates metrics/logs in a debug exporter so senders never see export errors. This is documented behavior, not worked around.
- **Assets are COPIED at init time** from `${CLAUDE_PLUGIN_ROOT}/scripts/otel/` to `~/.claude/loomwright/observability/`; `docker compose` always runs against the copy (the plugin install dir stays pristine and survives plugin updates).
- **Env changes go in user-scope `~/.claude/settings.json`** under the `env` key via **jq deep-merge** — unrelated keys are never touched, a **timestamped backup is written first**, and the flow **aborts (never half-writes) if the existing file fails to parse**.
- `/telemetry` (GitHub-issues telemetry) is a separate, unchanged command; `/setup telemetry` delegates to it.

---

# Agent Prompt

You are handling the `/setup` slash command inline on the main thread. Parse the FIRST positional argument as the module and the SECOND as the subcommand — one from that module's Subcommands cell in the skill's Pattern 2 registry. For `memory status`, `rules status`, `base-branch status` and `providers status`, run the Check + Report steps ONLY and STOP — they are read-only, so never fall through to that module's Offer/Apply flow.

## Step 0 — Load the protocol authority (every invocation)

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/setup/SKILL.md`. It is the authority for the module contract, the module registry, the settings-merge rules, and the smoke-test recipe. Execute its recipes verbatim where this prompt references them.
2. Resolve shared paths once via Bash:
   ```bash
   SETTINGS="$HOME/.claude/settings.json"
   OBS_DIR="$HOME/.claude/loomwright/observability"
   PLUGIN_VERSION=$(jq -r .version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")
   ```
3. NEVER hard-code plugin-repo-relative paths — `${CLAUDE_PLUGIN_ROOT}` is the only valid way to reference plugin assets at runtime.
4. End every invocation with a 1-line summary prefixed `Setup:`.

<!-- index-only:begin -->
5. **Read only this invocation's part.** A section below with a `See` line lives verbatim in a part: `Read` the parsed module's part in full — one Read call per file — and NO other part:
   - bare `/setup` → `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/setup/dashboard.md`, then each selected module's part below
   - `observability` → `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/setup/obs.md`
   - `memory` → `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/setup/memory.md`
   - `rules` → `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/setup/rules.md`
   - `statusline` → `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/setup/statusline.md`
   - `base-branch` → `base-branch.md` (same directory)
   - `providers` → `providers.md` (same directory)
   - `telemetry`, `notifications`, `webhook`, `beads`, `mysql-mcp` → `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/setup/other.md`
   - `--help` / `-h` / `help`, or an unrecognised module → no part (Help and unknown module, below)
   - examples, only if the user asks → `${CLAUDE_PLUGIN_ROOT}/docs/command-parts/setup/ex.md`

   In a part, "below"/"above" means the original single-file order.
<!-- index-only:end -->
### Help and unknown module (before any module flow)

- **Help dispatch:** `--help`, `-h` or `help` as the first argument prints the help and STOPS — no check, no part, no question, no write.
- **Unknown module:** any other first argument that is not a registry module prints `Setup: unknown module '<arg>'`, then the help, and STOPS.
- **Help = the registry, never a copy:** `/setup  (no argument: status dashboard)`, then one `/setup <module>  <Subcommands cell>` line per Pattern 2 row in registry order (the skill read at item 1), then `/setup --help | -h | help`.

<!-- split:begin ../docs/command-parts/setup/dashboard.md -->
## No-arg flow — status dashboard

See [../docs/command-parts/setup/dashboard.md](../docs/command-parts/setup/dashboard.md).
<!-- split:end ../docs/command-parts/setup/dashboard.md -->
## `/setup <module>` — jump straight to that module's flow.

---

<!-- split:begin ../docs/command-parts/setup/obs.md -->
## Module: observability

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).

### Check

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).

### Report

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).

### Offer

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).

### Apply — backend 1: local Langfuse stack (FULL init flow)

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).

### Apply — backend 2: existing OTLP endpoint (env-merge only, no Docker)

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).

### Apply — backend 3: console (debug only)

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).

### Verify (all backends)

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).

### Subflow: `/setup observability status`

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).

### Subflow: `/setup observability remove`

See [../docs/command-parts/setup/obs.md](../docs/command-parts/setup/obs.md).
<!-- split:end ../docs/command-parts/setup/obs.md -->
<!-- split:begin ../docs/command-parts/setup/memory.md -->
## Module: memory

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Check

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Report

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Offer — CONSENT-BEARING (never a silent default)

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Apply

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Verify

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Subflow: `/setup memory remove`

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Branch mode (opt-in, default OFF)

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Learning-store consent (branch mode)

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Subflow: `/setup memory migrate`

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).

### Idempotency note

See [../docs/command-parts/setup/memory.md](../docs/command-parts/setup/memory.md).
<!-- split:end ../docs/command-parts/setup/memory.md -->
<!-- split:begin ../docs/command-parts/setup/rules.md -->
## Module: rules

See [../docs/command-parts/setup/rules.md](../docs/command-parts/setup/rules.md).

### Check

See [../docs/command-parts/setup/rules.md](../docs/command-parts/setup/rules.md).

### Report

See [../docs/command-parts/setup/rules.md](../docs/command-parts/setup/rules.md).

### Offer

See [../docs/command-parts/setup/rules.md](../docs/command-parts/setup/rules.md).

### Apply

See [../docs/command-parts/setup/rules.md](../docs/command-parts/setup/rules.md).

### Verify

See [../docs/command-parts/setup/rules.md](../docs/command-parts/setup/rules.md).

### Idempotency note

See [../docs/command-parts/setup/rules.md](../docs/command-parts/setup/rules.md).
<!-- split:end ../docs/command-parts/setup/rules.md -->
<!-- split:begin ../docs/command-parts/setup/statusline.md -->
## Module: statusline

See [../docs/command-parts/setup/statusline.md](../docs/command-parts/setup/statusline.md).

### Check

See [../docs/command-parts/setup/statusline.md](../docs/command-parts/setup/statusline.md).

### Report

See [../docs/command-parts/setup/statusline.md](../docs/command-parts/setup/statusline.md).

### Offer — CONSENT-BEARING when something already exists

See [../docs/command-parts/setup/statusline.md](../docs/command-parts/setup/statusline.md).

### Apply

See [../docs/command-parts/setup/statusline.md](../docs/command-parts/setup/statusline.md).

### Verify

See [../docs/command-parts/setup/statusline.md](../docs/command-parts/setup/statusline.md).

### Subflow: `/setup statusline remove`

See [../docs/command-parts/setup/statusline.md](../docs/command-parts/setup/statusline.md).

### Idempotency note

See [../docs/command-parts/setup/statusline.md](../docs/command-parts/setup/statusline.md).
<!-- split:end ../docs/command-parts/setup/statusline.md -->
<!-- split:begin ../docs/command-parts/setup/base-branch.md -->
## Module: base-branch

See [../docs/command-parts/setup/base-branch.md](../docs/command-parts/setup/base-branch.md).
<!-- split:end ../docs/command-parts/setup/base-branch.md -->
<!-- split:begin ../docs/command-parts/setup/providers.md -->
## Module: providers

See [../docs/command-parts/setup/providers.md](../docs/command-parts/setup/providers.md).
<!-- split:end ../docs/command-parts/setup/providers.md -->
<!-- split:begin ../docs/command-parts/setup/other.md -->
## Module: telemetry

See [../docs/command-parts/setup/other.md](../docs/command-parts/setup/other.md).

## Module: notifications

See [../docs/command-parts/setup/other.md](../docs/command-parts/setup/other.md).

## Module: webhook

See [../docs/command-parts/setup/other.md](../docs/command-parts/setup/other.md).

### Check

See [../docs/command-parts/setup/other.md](../docs/command-parts/setup/other.md).

### Report

See [../docs/command-parts/setup/other.md](../docs/command-parts/setup/other.md).

### Offer

See [../docs/command-parts/setup/other.md](../docs/command-parts/setup/other.md).

### Apply

See [../docs/command-parts/setup/other.md](../docs/command-parts/setup/other.md).

## Module: beads

See [../docs/command-parts/setup/other.md](../docs/command-parts/setup/other.md).

## Module: mysql-mcp

See [../docs/command-parts/setup/other.md](../docs/command-parts/setup/other.md).
<!-- split:end ../docs/command-parts/setup/other.md -->
## Constraints (every module)

- The ONLY files this command's OWN logic may write:
  - `$OBS_DIR/*` (the copied stack + generated `.env`),
  - `$HOME/.claude/settings.json` — user-scope env, via the merge recipe, backup-first,
  - **webhook** (`/setup webhook`) — `$HOME/.claude/loomwright/egress.json`, via the SAME backup-first / jq-deep-merge / abort-on-parse-failure procedure `/telemetry enable` uses (v15.87.0), touching only that slug's `webhook_url`/`webhook_url_sha256` keys — never the sibling `telemetry`/`telemetry_repo` keys a prior `/telemetry enable` wrote for the same slug. May additionally mirror into `<project>/.supervisor/config.json`'s `.webhook_url` — documented as inert on its own for `send-webhook.sh`'s resolution, which reads that path only as an informational request,
  - `<project>/.claude/settings.local.json` — project-scope, gitignored-by-convention; sanctioned for the `remove` subflow's `jq 'del(.env.OTEL_RESOURCE_ATTRIBUTES)'` (backup-first, like the user-scope merge) and — via the invoked `set-otel-resource-attrs.sh` script — the init-tail per-project label. The script write uses parse-gate (`jq empty`, no clobber on unparseable) + atomic tmp-file-`mv` + idempotent skip-if-unchanged; it does NOT back up (the merge is single-key and idempotent, so there is nothing destructive to roll back), and
  - **memory** (`/setup memory`) — **a `.gitignore` write class no other module has, so it gets its own line:** (a) `<project>/.gitignore`, rewritten ONLY via `setup-memory.sh apply` / `remove`, and ONLY after an explicit consent-bearing confirm. The write is backup-first (a timestamped `<project>/.gitignore.backup.<ts>` sibling, pid-suffixed on a same-second collision so one backup can never overwrite another), atomic (tmp-file + `mv`), confined to a sentinel-delimited managed block plus the commenting-out of pre-existing directory-shaped `.claude/` / `.supervisor/` excludes — including the recursive `**` family (`.claude/**`, `**/.claude/`, `**/.claude/**`), but never the `X/*` working form — and **idempotent by byte-comparison** — apply computes the file it would write and does nothing when it already matches. It **ABORTS without any write and without a backup** on an absent, non-regular, symlinked, NUL-containing, conflict-marked, or sentinel-unbalanced `.gitignore` — never a partial write, never a blind repair; and (b) `<project>/.supervisor/config.json` key `.setup_memory.repo_allowlist` — a jq merge that is parse-gated (`jq empty`), backup-first, atomic, preserves every unrelated key, stores a JSON **array**, and never overwrites an existing non-empty one. The memory module touches NO `~/.claude/settings.json` and nothing under `~/.claude/` except ONE file — the user-scope learning-store consent record (named in the engine paragraph above), written only by `setup-memory.sh consent grant` / `decline` after an explicit Accept / Decline (other repos' entries preserved, atomic, never over a malformed file) — and it **NEVER runs `git add`, `git rm`, `git commit` or any other history-touching git command** — un-ignoring is not committing, and un-committing is the user's own `git rm --cached`.

  - **statusline** (`/setup statusline`) — **the only module whose write domain is the USER-SCOPE settings document, so it gets its own line:** the user-scope settings JSON ONLY (the same path Pattern 3 governs), written ONLY via `setup-statusline.sh apply` / `remove`, and ONLY after an explicit confirm. The write is backup-first (a timestamped `.backup.<ts>` sibling, pid- then counter-suffixed on a same-second collision so one backup can never overwrite another, and an apply that cannot obtain a free backup name ABORTS rather than write unbacked-up), parse-gated (`jq empty` — an unparseable document ABORTS with **no write and no backup**), atomic (tmp-file + `mv`), and **idempotent by byte-comparison** — apply computes the document it would write and does nothing when it already matches. It touches exactly TWO keys, `statusLine` and the namespaced restore record `loomwrightStatusLinePrior`; every other key at every level is preserved, which `test-setup-statusline.sh` asserts by DIFFING the two documents with those two keys removed rather than by spot-checking. **NOTHING ELSE under the user's `~/.claude/` directory** — no sidecar state file, no project write, no `.gitignore` write, and no history-touching git command. A pre-existing `statusLine` this plugin did not write is PRESERVED and reported; replacing it requires the explicit `--replace` flag, and the replaced value is recorded so `remove` restores it verbatim.

  - **base-branch** (`/setup base-branch`): `<project>/.supervisor/config.json` key `.base_branch` ONLY, via `setup-base-branch.sh set` / `remove` (write rules: its part).

  - **providers** (`/setup providers`): `.routing` in `<project>/.supervisor/config.json` and this repo's grant in the user-scope `egress.json`, ONLY, via `setup-routing.sh` (write rules: its part).

  - **rules** (`/setup rules`): `<project>/.agent/rules/<category>.json` ONLY, written ONLY via `seed-rules.sh seed --confirm` (which authors every rule through the sole writer `add-rule.sh`), and ONLY after an explicit confirm. `check` and a bare `seed` write NOTHING — every writer invocation is stdin-detached, so this module NEVER prompts and an unconfirmed run cannot write. No `~/.claude/` write of any kind, no `.gitignore` write, no `git add`/`rm`/`commit`, and no rule object built by hand.

  Everything else is read-only or delegated. One delegation carve-out: when the telemetry module executes telemetry.md's enable recipe (see "Module: telemetry"), that recipe writes `~/.claude/loomwright/egress.json`'s `telemetry`/`telemetry_repo` keys (the SAME backup-first / jq-deep-merge / abort-on-parse-failure procedure the webhook module above uses for its own keys) under telemetry.md's authority — setup.md's own logic still never touches that file directly, and never touches the now-inert repo-relative `.supervisor/telemetry-consent.json` at all.
- Idempotent: re-running any flow against an already-configured module reports "already configured" and offers status/reconfigure/remove — it never blind-overwrites, and never regenerates an existing `.env`.
- Abort (never half-write) if `~/.claude/settings.json` exists but fails to parse — tell the user the path and the backup convention, and stop.
- Never print secret VALUES (webhook URL, DB_PASS, header values, generated keys) except the local-only Langfuse dashboard login at the end of a successful local init.
- All plugin asset references via `${CLAUDE_PLUGIN_ROOT}` — no repo-relative paths.
- Always end with the 1-line `Setup:` summary.

<!-- split:begin ../docs/command-parts/setup/ex.md -->
## Examples

See [../docs/command-parts/setup/ex.md](../docs/command-parts/setup/ex.md).
<!-- split:end ../docs/command-parts/setup/ex.md -->
