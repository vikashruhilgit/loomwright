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

## History

This server shipped bundled inside the `loomwright` plugin up to and including v15.5.0. It was spun out into this standalone plugin so it can be installed (or skipped) independently.
