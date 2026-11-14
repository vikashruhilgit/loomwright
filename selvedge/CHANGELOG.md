# Changelog

All notable changes to the selvedge plugin. Selvedge releases on its own: each release bumps
`selvedge/.claude-plugin/plugin.json`, its entry in `.claude-plugin/marketplace.json` and this
file together, never through the repository's `changelog.d/` fragments (those fold into
Loomwright's version only).

Format: each release is a heading `## <X.Y.Z> — <YYYY-MM-DD>`; the first such heading is the
current release, and `selvedge/tests/run.sh` checks it equals `plugin.json`'s `version`.

## 0.1.0 — 2026-11-13

- First release: the plugin scaffold. Manifest, the `selvedge` CLI (`--version`, `install-cli`,
  which links the CLI into `~/.local/bin`), and the plugin's own release gate
  (`selvedge/tests/run.sh`, run by CI's `static` job).
- `docs/cli-discovery.md` records whether a plugin's `bin/` reaches `PATH`.
