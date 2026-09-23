# mysql-mcp

A read-only MySQL MCP server for Claude Code, packaged as a standalone plugin. It runs [`vikashruhil-mysql-mcp`](https://pypi.org/project/vikashruhil-mysql-mcp/) via `uvx` — no agents, commands, skills, or hooks, just the MCP server.

## Install

```
/plugin install mysql-mcp@atelier
```

Requires `uvx` (from [uv](https://docs.astral.sh/uv/)) on your PATH.

## Configuration

The server resolves its connection settings from environment variables (names only — never commit values):

| Variable | Required |
|---|---|
| `DB_HOST` | yes |
| `DB_USER` | yes |
| `DB_PASS` | yes |
| `DB_NAME` | yes |
| `DB_PORT` | optional |

Set them in your shell profile or per-project environment. `/setup mysql-mcp` (from the loomwright plugin) reports which are unset.

## Supply chain

`mysql-mcp/.mcp.json` pins the exact `uvx`-launched release: `--from vikashruhil-mysql-mcp==1.0.1` (no `--refresh`). This is deliberate — `uvx` re-resolves `--from` on every launch, and without a version pin a compromised publisher account or a bad release would ship straight into a process that already holds `DB_HOST`/`DB_USER`/`DB_PASS`/`DB_NAME` from the environment. Pinning makes every upgrade a visible, reviewed diff in this repo instead of a silent runtime re-resolve.

To bump the pinned version:
1. Verify the new release on PyPI first: `curl -s https://pypi.org/pypi/vikashruhil-mysql-mcp/json | python3 -c "import json,sys;print(json.load(sys.stdin)['info']['version'])"` — never pin a version you have not looked up.
2. Edit `mysql-mcp/.mcp.json`'s `args` to the new `==<version>`.
3. Bump the version in `mysql-mcp/.claude-plugin/plugin.json` and the mirrored `mysql-mcp` entry in the repo root's `.claude-plugin/marketplace.json` (the two must stay in lockstep) — including the `pinned to` clause in `plugin.json`'s `description`.
4. Also update the two loomwright-side restatements that name this pin — `CLAUDE.md`'s sibling-plugins bullet (`... mysql-mcp/ (... vX.Y.Z, pinned to \`==X.Y.Z\`)`) and `loomwright/docs/CAPABILITY_BASELINE.json`'s `deps.vikashruhil-mysql-mcp.pin` field — neither is covered by `check-doc-currency.sh`'s automated checks, so they only stay accurate if bumped by hand alongside the steps above.
5. This plugin has no `CHANGELOG.md` of its own; the diff in `.mcp.json` + the two version bumps above IS the changelog-equivalent record — there is no additional file to update.

## Honest limits

- **Read-only enforcement lives inside the PyPI package, not this repo.** `vikashruhil-mysql-mcp`'s implementation is outside this repo's source tree; this repo does not vendor it, does not test it, and cannot verify at build time that it actually restricts itself to read-only queries. Treat the "read-only" label as the package's own claim.
- **The database grant should itself be read-only, defense in depth.** The `DB_USER` supplied via environment variables should be provisioned with a read-only (`SELECT`-only) grant at the database level — don't rely on the MCP server's own claimed behavior as the only safeguard.
- **An exact-version pin, not a hash pin.** `uvx --help` documents a `-c`/`--constraint <CONSTRAINTS>` flag, but it takes a requirements-file path that constrains *transitive* dependency resolution — there is no `uvx --from pkg==X.Y.Z --hash <sha256>` inline flag for pinning the `--from` package itself by content hash. An exact `==` version pin (what `.mcp.json` uses) is the strongest inline mechanism `uvx --from` supports; a full hash-verified install would require restructuring this plugin as a `uv`-managed project with a lockfile, which conflicts with the lightweight single-command MCP launcher design this plugin intentionally uses.

## History

This server shipped bundled inside the `loomwright` plugin up to and including v15.5.0. It was spun out into this standalone plugin so it can be installed (or skipped) independently.
