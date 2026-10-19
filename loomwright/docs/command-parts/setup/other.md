## Module: telemetry

DELEGATES — print `Telemetry is managed by /telemetry (consent logic lives there and is not duplicated).`, show the consent state from the dashboard check, and tell the user to run `/telemetry enable | disable | status | test`.

**When to auto-run the enable flow (and when NOT to):** only when telemetry was the EXPLICIT target — i.e. invoked directly as `/setup telemetry`. On that explicit path you may execute the `/telemetry enable` flow by following `${CLAUDE_PLUGIN_ROOT}/commands/telemetry.md` directly (the user-scope write to `~/.claude/loomwright/egress.json` is performed by telemetry.md's own enable recipe, permitted under telemetry.md's authority — v15.87.0, red-team-hardening item 02). When telemetry is reached via the no-arg dashboard's bundled **Other integrations (telemetry · webhook · Beads · MySQL MCP)** option, print the delegation message + consent state ONLY and point the user to `/telemetry enable` — do NOT auto-launch the interactive enable / repo-selection flow from the bundle (a user who picked the bundle for webhook/Beads/MySQL must not get a surprise telemetry consent prompt).

What is forbidden on every path is `/setup`'s OWN logic touching `~/.claude/loomwright/egress.json`'s `telemetry`/`telemetry_repo` keys — never read-modify-write them, duplicate the consent prompt, or write them outside of executing telemetry.md's recipe verbatim. `/setup`'s own logic also never reads or writes the repo-relative `.supervisor/telemetry-consent.json` — that file is now inert (an informational request only, resolved — never granted — via `resolve-egress-config.sh`).

## Module: notifications

Status + guidance only. Report: desktop notifications fire via always-on plugin hooks (`PreToolUse[AskUserQuestion]` + `Notification` → `notify-desktop.sh`) — nothing to configure. The webhook-POST variant of gate notifications additionally needs `LOOMWRIGHT_WEBHOOK_URL` → point to the webhook module.

## Module: webhook

**v15.87.0 (red-team-hardening item 02) — the webhook destination is now USER-scoped**, resolved by `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-egress-config.sh` from `LOOMWRIGHT_WEBHOOK_URL` (env, highest precedence, still the right choice for a one-off/CI shell) or `~/.claude/loomwright/egress.json` (persists across shells without needing an export). This module writes the LATTER.

### Check
Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-egress-config.sh"` and read its `WEBHOOK_URL=` line — this is the SAME resolution `send-webhook.sh` itself performs, never guess or recompute it. Never print the URL value (it may embed a token) — print only whether it is `set (host: <hostname-only>, source: env var|user-scope config)` or `not set`.

### Report
If `LOOMWRIGHT_WEBHOOK_URL` is set, note that the env var is currently winning and any user-scope value written here will not take effect until it is unset. If a repo-relative `.supervisor/config.json`/`.supervisor/notify-config.json` carries a `webhook_url` that does not match the resolved value, note it is present but NOT honoured (informational request only, per resolve-egress-config.sh) — never imply it is in effect.

### Offer
If not configured (or the user wants to change it), ask via `AskUserQuestion` whether to write a webhook URL now: `question`: "Set a webhook URL for this repo? (Slack/Discord/ntfy/custom — paste the full URL)", `header`: "Webhook URL", `multiSelect`: false, free-text entry (no suggested options — this is credential-shaped input, never guess a default). Validate the answer starts with `https://` or `http://`; on any other shape, print an error and write nothing.

### Apply
Resolve `REPO_SLUG` via the SAME resolver output as Check, then write `~/.claude/loomwright/egress.json` with the identical backup-first, jq-deep-merge, abort-on-parse-failure procedure `/telemetry enable` uses (see `${CLAUDE_PLUGIN_ROOT}/commands/telemetry.md` §"If subcommand == `enable`" step 5 for the exact recipe — reuse it verbatim, substituting the jq filter's target fields):
```bash
jq --arg slug "$REPO_SLUG" --arg url "<answer>" --arg sha "$(printf '%s' "<answer>" | shasum -a 256 | awk '{print $1}')" \
  '.schema_version = 1 | .repos[$slug].webhook_url = $url | .repos[$slug].webhook_url_sha256 = $sha'
```
This is a SEPARATE write from `/telemetry enable`'s (different keys, same file, same procedure) — never overwrite the sibling `telemetry`/`telemetry_repo` keys already present for this slug; the jq filter above touches only `webhook_url`/`webhook_url_sha256`.

**May still mirror into `<project>/.supervisor/config.json`'s `.webhook_url`** — this mirror is now INERT on its own for `send-webhook.sh`'s own resolution (it is read back only as an informational *request*, per `resolve-egress-config.sh`); document that explicitly in the confirmation message so a user does not assume editing `.supervisor/config.json` by hand changes where the webhook fires.

This command does NOT edit shell profiles — the env var path is unchanged (`export LOOMWRIGHT_WEBHOOK_URL=...` by hand, still highest precedence).

## Module: beads

Status + guidance only. Report `bd` availability and `.beads/` presence. Guidance: Beads is optional and used only by Orchestrator / Product Owner; install per the Beads project docs, then `bd init` in the repo. This command does NOT install software.

## Module: mysql-mcp

Status + guidance only. Report which of `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` (+ optional `DB_PORT`) are unset — names only, never values — and append the pinned server version, resolved the same way as the dashboard check (`jq` against this repo's `mysql-mcp/.mcp.json`; omit the suffix when that file isn't reachable). Guidance: the read-only MySQL MCP server is provided by the separate `mysql-mcp@atelier` plugin (`/plugin install mysql-mcp@atelier`) and resolves these from the environment; set them in the shell profile or project `.mcp.json` env. This command does NOT write credentials anywhere and does NOT install the plugin.

---

