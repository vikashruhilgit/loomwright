# 07 — Pin the `mysql-mcp` package; drop `--refresh`; state what "read-only" does and does not verify


## Problem
`mysql-mcp/.mcp.json:4`: `"args": ["--from", "vikashruhil-mysql-mcp", "--refresh", "mysql-mcp"]` — no version,
no hash, and `--refresh` forces `uvx` to re-resolve the latest PyPI release on every server start. The process
receives `DB_HOST/DB_USER/DB_PASS/DB_NAME` from the environment. A compromised publisher account or a bad
release ships straight into a credentialed process on every launch, and nothing in this repo can verify the
"read-only" claim (the code lives on PyPI; the red-team marked it UNVERIFIED).

## Goal
The plugin launches a specific, reviewed version; upgrades are a visible diff in this repo; the README says
honestly where read-only enforcement lives and that this repo does not verify it.

## Scope
1. `mysql-mcp/.mcp.json`: `--from vikashruhil-mysql-mcp==<current published version>` (read it with
   `uvx --from vikashruhil-mysql-mcp mysql-mcp --version` or `pip index versions vikashruhil-mysql-mcp` in
   the implementing session — do not guess), remove `--refresh`. If `uvx` supports a `--constraint`/hash
   mechanism in the installed version, add it; otherwise record why not in the README.
2. `mysql-mcp/README.md`: a "Supply chain" section — the pin, how to bump it (edit `.mcp.json`, bump
   `mysql-mcp/.claude-plugin/plugin.json` version, CHANGELOG line), and an "Honest limits" line: read-only
   behaviour is enforced inside the PyPI package, this repo neither vendors nor tests it; the DB user
   supplied via `DB_USER` should itself be a read-only grant.
3. `mysql-mcp/.claude-plugin/plugin.json` version bump (1.0.0 → 1.0.1) and description sentence "pinned to
   `==<v>`". `.claude-plugin/marketplace.json` mirror. `commands/setup.md` `mysql-mcp` module: print the
   pinned version in its status cell (read from `.mcp.json` with jq).
4. `scripts/check-doc-currency.sh`: if it scans marketplace/plugin versions for the sibling plugins, keep it
   green; if it does not, add a one-line assertion that `.mcp.json` carries `==` (no floating dependency).

## Non-goals
No vendoring, no fork of the server, no change to the loomwright plugin's counts.

## Acceptance criteria
- `jq -r '.mcpServers.mysql.args[]' mysql-mcp/.mcp.json` contains a `==` pin and no `--refresh`.
- README "Supply chain" + "Honest limits" sections exist.
- Versions consistent across `mysql-mcp/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`;
  `check-doc-currency.sh` green.
- Full test loop + root checks green.

## Verified premises
- `mysql-mcp/` contains only `.mcp.json`, `README.md`, `.claude-plugin/plugin.json` (no source).
- `commands/setup.md` has a `mysql-mcp` module that reports unset env vars.

## Status: done (PR #255, merge 223cd89)
- **Completed:** 2026-09-26T02:14:45Z
- **Brief:** .supervisor/jobs/done/2026-09-22-mysql-mcp-pin.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/255
