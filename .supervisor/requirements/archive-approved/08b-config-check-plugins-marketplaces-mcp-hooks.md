# Unattended runs refuse to start when plugins, marketplaces, MCP servers or settings hooks differ from the owner's approved config (run-start config check, part 2 of 3)

## Status: pending

**As the** owner (Vikash), whose CLI plugin store and settings can gain plugins, marketplaces, MCP servers and hooks without me knowing (example threat: an app upgrade that installs its own plugin and a `SessionStart` hook),
**I want** the run-start config check from 08a to compare what a Claude Code session of this project will load with what I approved: the enabled plugins and their content, the known marketplaces, every configured MCP server, and every hook defined in settings files,
**so that** nothing added behind my back loads into a run I am not watching, and I see exactly what changed before I approve it.

This is part **08b** of item 08 (archive H4). It carries batch E P's plugin, marketplace and MCP pin, G1's MCP allowlist rules (not its in-run install guard) and H4's settings-hook leg. It adds legs to `config-integrity.sh`, the approved-state file and `approve` from 08a. No new call site, status family or `pause_reason`. Read on `main` `8ec200e` (plugin 17.35.1).

## Problem (verified on main 8ec200e and on this Mac)

- Nothing in `loomwright/` reads `installed_plugins.json`, `known_marketplaces.json`, `enabledPlugins`, settings `hooks` or `~/.claude.json` `mcpServers`. Matches in the repo are only in `docs/SPIKES/`.
- `claude plugin list --json` is called only by the `loomwright-lanes` add-on, to find Loomwright.
- **This Mac's CLI store differs from what H4 recorded:**
  - `~/.claude/plugins/installed_plugins.json` now exists (`version: 2`; each entry has `installPath`, `version`, `gitCommitSha`, `scope`).
  - `known_marketplaces.json` has two entries (`atelier`, `claude-plugins-official`), each with `source` and `installLocation`.
  - `~/.claude/settings.json` has `enabledPlugins` (7 plugins), `extraKnownMarketplaces`, `env` and `permissions`.
  - `~/.claude.json` has one user-scope MCP server.
  - `remote-settings.json` and `settings.local.json` exist under `~/.claude/`.
- **What a run loads, and what is out of reach.** Headless lanes and phase sessions load the CLI store plus the shared `~/.claude/settings.json` `enabledPlugins`, and Loomwright through `--plugin-dir` (`automate-lanes.d/launch.sh`). The Claude desktop app keeps its own plugin store (under `~/Library/Application Support/Claude/`) and passes its own `--plugin-dir`. A check run inside a session cannot see the other `--plugin-dir` arguments of its own command line.
- `classify-risk.sh` treats `.mcp.json` and `.claude/` as trusted roots for **committed** changes at the merge gate only. Nothing judges a working-tree, user-scope or plugin change before a run.

## Scope

All legs read config files only. They never run `claude plugin …`, `claude mcp …` (`claude mcp get` health-checks, which starts the server it would judge), `codex`, or any hook. The surface table in the script header cites the Claude Code docs, with the read date, for every source below. A source the docs name that is missing here is added to that one table in the same PR.

### Plugins (`kind: plugin`)
- **Loaded set** = plugins enabled in `enabledPlugins` (user `~/.claude/settings.json`, project `.claude/settings.json`, project-local `.claude/settings.local.json`, plus any managed settings file the docs name) that are present in `installed_plugins.json`, **plus** the effective `${CLAUDE_PLUGIN_ROOT}` (Loomwright's own root, however it was loaded).
- Each item records `{name, version, source, install_path, content_hash}`. `content_hash` is SHA-256 over the sorted `<sha256>  <relpath>` lines of every regular file under the root, with `.git/` excluded and symlinks recorded by their target string (not followed). The basis is pinned in the schema doc with a fixture tree.
- A plugin's own `hooks/hooks.json`, scripts, agents and skills are covered by this hash, so any change is `changed` and a new plugin is `unlisted`.

### Marketplaces (`kind: marketplace`)
- Every entry in `known_marketplaces.json` and in `extraKnownMarketplaces` (each settings scope): `{name, source, manifest_sha256}`, where the hash is of `.claude-plugin/marketplace.json` at its `installLocation`.

### MCP servers (`kind: mcp_server`, G1's allowlist rules)
- **Configured set:** the project `.mcp.json`, each loaded plugin root's `.mcp.json` (and inline `mcpServers` in its `plugin.json` if the docs say plugins can declare them there), `~/.claude.json` top-level `mcpServers` and its `projects[<root>].mcpServers`, plus any managed MCP file the docs name.
- **Identity:** the exact `command` and `args` for stdio servers, or the exact `url` for http/sse. A local-path `command` also records the file's SHA-256 (a symlink is resolved, then hashed). `env` values are never recorded or printed; only key names are.
- **Pinned-launcher rule:** `approve` refuses to record a server whose `command` is a package runner (`npx`, `uvx`, `pipx run`, `bunx`, `pnpm dlx`, `yarn dlx`, `uv tool run`) without an exact package version (`pkg==1.0.1`, `pkg@1.2.3`). It reports `mcp_entry_unpinned`, so such a server stays `unlisted` and an unattended run refuses while it is configured.
- A configured server whose identity matches no approved entry is `unlisted`. The same name with different args (a version change) is `changed`.

### Settings hooks (`kind: hook`)
- Every hook in user, project, project-local and managed settings files: `{source, event, matcher, command_sha256, script: {path, sha256} | null}`. `script` is filled when the command names a resolvable file (`${CLAUDE_PLUGIN_ROOT}/…`, an absolute path, or `bash|sh|python3 <path>`). The hook's timeout is not part of its identity.
- Output carries the script basename and hashes, never the full command text.

### How the legs report
- New `drift` item reasons: `unlisted` (loaded but not approved; this is the app-upgrade case), `changed` (same identity, different hash or version), and `missing` (approved but no longer loaded). `missing` refuses only for Loomwright's own plugin root; for everything else it is recorded and advisory.
- `approve` covers these kinds in the same file, with global entries plus `repos.<repo-key>` entries for project-scoped items (the project `.mcp.json`, project settings hooks and plugins enabled only at project scope).
- A `repos.<A>` entry matches in repo A only.
- **Codex:** when `~/.codex/` exists or `codex` is on `PATH`, the check records `hosts.codex: not_covered` and prints one advisory line. It does not parse Codex config and never refuses for it.
- Any unreadable source (a malformed `installed_plugins.json`, `known_marketplaces.json`, settings file, `.mcp.json` or `~/.claude.json`, an unreadable file under a plugin root, a missing `installLocation`) ⇒ `unreadable`, never `match` or `absent`.

### Docs
- `docs/result-schemas/config-integrity.md`: the new item kinds, the hash basis and the `drift` reasons.
- The script header's surface table, including an **out of reach** list: the desktop app's plugin store, other `--plugin-dir` arguments on a session's command line, servers added at runtime that are in no config file, and Codex.

## Acceptance Criteria

All tests run under `hermetic-test-env.sh` with no network. Fixtures in `loomwright/scripts/fixtures/config-integrity/`:
- a temp `HOME` with `installed_plugins.json` (v2 shape, as on this Mac), `known_marketplaces.json`, `settings.json` (with and without `hooks.SessionStart`, `enabledPlugins`, `extraKnownMarketplaces`) and `~/.claude.json` (with user and per-project `mcpServers`);
- a fixture plugin root (`.claude-plugin/plugin.json`, a nested file, a symlink, a `.git/` dir, `hooks/hooks.json` calling `${CLAUDE_PLUGIN_ROOT}/scripts/h.sh`, `.mcp.json` shaped like `mysql-mcp/.mcp.json`);
- a fixture marketplace manifest;
- a fixture repo with a project `.mcp.json` and `.claude/settings.json`;
- stub `claude` and `codex` on `PATH` that log every argv.

Legs are added to `loomwright/scripts/test-config-integrity.sh`.

**Happy path**
- [ ] Given the fixtures and an owner-terminal `approve --confirm`, then the approved file holds one `plugin` item per loaded root with a `content_hash` equal to the schema doc's recomputation, the marketplaces, each MCP server (args containing `==1.0.1` verbatim, no `env` values) and each settings hook with its `command_sha256` and `script.sha256`. When `check` runs next, then `match`, exit 0, and the stub `claude` logged only `--version`. *(test-config-integrity.sh)*
- [ ] **(App-upgrade case)** Given that approval, when a new plugin is added to `installed_plugins.json` and `enabledPlugins` **and** a `SessionStart` hook `{"type":"command","command":"/opt/vendor/bin/agent-hook --x"}` is added to `~/.claude/settings.json`, then `drift` naming the plugin `unlisted` and the hook `unlisted` (`source: claude_user_settings`), exit 1. The JSON and the log carry the basename `agent-hook` and the hash, never `--x`. *(test-config-integrity.sh)*
- [ ] Given one byte changed in a nested plugin file, then `drift` `changed` for that plugin with both hashes. Given the plugin's `.git/` changed, then `match`. Given a symlink retargeted, then `drift`. *(test-config-integrity.sh)*
- [ ] Given `==1.0.1` changed to `==1.0.2` in the plugin `.mcp.json`, then `drift` `changed` for that server. Given a new server `evil` in the project `.mcp.json` or in `~/.claude.json` `projects[<root>].mcpServers`, then `unlisted`. *(test-config-integrity.sh)*
- [ ] Given a new entry in `known_marketplaces.json` or `extraKnownMarketplaces`, then `drift` `unlisted` for that marketplace. *(test-config-integrity.sh)*
- [ ] Given one byte changed in `scripts/h.sh` with the hook command unchanged, then `drift` for that plugin (content hash) and, for a settings hook pointing at a changed absolute-path script, `drift` `changed` for that hook. *(test-config-integrity.sh)*
- [ ] Given Supervisor INIT `--non-interactive` on the app-upgrade fixture, then a park with `config_integrity_drift` before the step-6 move. Given `/automate`, then PICK parks `config_integrity_refused` with a Progress line naming the first item. *(test-supervisor-next-step.sh, test-automate-next-step.d/)*

**Edge cases**
- [ ] Given `approve` with a configured server `{"command":"npx","args":["-y","some-mcp"]}`, then it reports `mcp_entry_unpinned` and does not record it, and the next `check` reports it `unlisted`. Given `["-y","some-mcp@1.2.3"]`, then it is recorded. *(test-config-integrity.sh)*
- [ ] Given an approved non-Loomwright plugin removed, then `missing` and exit 0. Given Loomwright's own root absent from the loaded set, then `drift` exit 1. *(test-config-integrity.sh)*
- [ ] Given a `repos.<A>` MCP entry, then that server is `match` in repo A and `unlisted` in repo B. Given a repo file that "allows" a server or hook, then it shows only as `REPO_REQUESTED_*`. *(test-config-integrity.sh)*
- [ ] Given `~/.codex/` present, then `hosts.codex: not_covered`, one advisory line, no refusal, and the stub `codex` logged no call. *(test-config-integrity.sh)*
- [ ] Given a hook command or a plugin file path with spaces, quotes or a backtick, then the hashes are stable across two runs and the JSON stays valid. *(test-config-integrity.sh)*
- [ ] Given an `env` block holding a secret-looking value, then no stdout, stderr, JSON or log line contains it. *(test-config-integrity.sh)*

**Error scenarios**
- [ ] Given a malformed `installed_plugins.json`, `known_marketplaces.json`, `settings.json`, `.mcp.json` or `~/.claude.json`, an unreadable plugin file, or a marketplace `installLocation` that does not exist, then `unreadable`, exit 1. Never `match` or `absent`. *(test-config-integrity.sh)*
- [ ] Given each mutation, then at least one case fails: (a) the check calls `claude plugin`, `claude mcp` or `codex`; (b) symlinks are followed; (c) an unpinned runner is recorded by `approve`; (d) a repo file grants; (e) a full hook command or an `env` value is printed; (f) an unreadable source is treated as `absent`. *(test-config-integrity.sh)*

## Non-goals
- **G1's in-run install guard** (`PreToolUse` Bash/Write parsing of `claude mcp add`, `npx`/`uvx`, writes to `.mcp.json` or settings MCP keys). Rejected by the owner. An install made during a run is caught at the next run start.
- **The Claude desktop app's own plugin store**, other `--plugin-dir` arguments, and MCP servers added at runtime outside any config file. These are out of reach and named in the script header.
- **Codex legs** (Codex plugins, marketplaces, hooks, trusted-hook records). Deferred; see Owner decisions.
- G1's MCP known-bad package list, and registry (PyPI/npm) package hashes.
- Claude workspace-trust records (`~/.claude.json` `hasTrustDialogAccepted`).
- Passing `--strict-mcp-config` to lanes or phase sessions.
- Live plugin installs in tests.
- New call sites, new statuses beyond `drift` item reasons, a new `pause_reason`, or a new hook leaf.

## Owner decisions
- 2026-11-09 (Vikash, in chat): APPROVED from the archive review; refreshed against main 8ec200e / v17.35.1.
- 2026-11-09 (Vikash, in chat): one user-scope approved-state file and one owner-terminal `approve` cover batch E P's plugins, marketplaces and MCP servers and G1's MCP allowlist (not three files, not two approvals). G1's Bash-parsing install guard is rejected. Cover the CLI store and the shared `~/.claude/settings.json` `enabledPlugins` that headless lanes load, and say plainly what is out of reach. Repo-relative files can only request, never grant.
- PO default, pending owner review: the legs read config files instead of running `claude plugin list --json`. This avoids any CLI side effect and fails closed (`unreadable`) when an undocumented file format changes.
- PO default, pending owner review: Codex legs are deferred. `codex` is not on `PATH` here, and Loomwright runs Codex only as a provider (`provider-codex.sh`), so no Codex config loads into a Claude-hosted run. `~/.codex/` is reported as `not_covered`.
- PO default, pending owner review: `missing` refuses only for Loomwright's own plugin root (H4's OQ-H53).
- PO default, pending owner review: plugin-bundled hooks are judged through the plugin content hash. Only settings-defined hooks get their own `hook` items.

## Priority: P1
**Rationale:** an app or plugin upgrade can add a plugin, an MCP server or a `SessionStart` hook that runs in every later unattended session, and today no check names it.

## Assumptions
- The loaded plugin set is `enabledPlugins` (all settings scopes) ∩ `installed_plugins.json`, plus `--plugin-dir` roots. The implementer cites the plugin docs for scope precedence and captures the v2 `installed_plugins.json` shape from this Mac as the fixture (field names only, no personal values).
- Whether `~/.claude/settings.local.json` and `~/.claude/remote-settings.json` can carry hooks or `enabledPlugins` is not verified. The implementer cites the settings docs and adds each loaded source to the surface table.
- Hashing every loaded plugin tree takes a few seconds at most. It is measured in the PR on this Mac's 7 enabled plugins. The SessionStart `--report` keeps its 3 s budget from 08a.
- **Honest limit:** the check reads what the files say a session will load. It cannot see an in-memory change, a binary change, or a desktop-only plugin.

## Dependencies
- Depends on: 08a (the script, file, `approve`, statuses and call sites).
- Blocks: 08c (serialised on `config-integrity.sh` and its suite).

## Risks
- **Re-approval fatigue:** every plugin update parks unattended runs until `approve`. Mitigation: one `approve` for all kinds, plus the SessionStart advisory that warns before a run.
- **Undocumented store formats** (`installed_plugins.json` changed from H4's observations to v2 since 2026-11-06). Mitigation: a format change is `unreadable`, never `match`, and the surface table names the row to fix.
- **Dogfooding:** running from this repo's own checkout as `--plugin-dir` makes every local edit Loomwright-root drift. Mitigation: re-approve, or run from a copied root as PO runs do.

## Validation (must pass before merge)
1. **Static — affected suites:** `bash scripts/ci-local.sh --affected` passes, including the new legs in `loomwright/scripts/test-config-integrity.sh`, `test-supervisor-next-step.sh` and `test-automate-next-step.d/`, plus `check-doc-currency.sh`, `test-citation-drift.sh` and `check-test-hermetic.sh`.
2. **Static — release:** one `changelog.d/` fragment, version files never hand-edited, and `bash scripts/check-version-bump.sh` passes.
3. **Running system — a planted settings hook parks an unattended run:** with a scratch `HOME` holding an approved file, a `SessionStart` hook added to its `~/.claude/settings.json` makes a new live session show the advisory line, and a live `/loomwright:automate --backlog <one-item fixture> --non-interactive-fallback` park `config_integrity_refused` before anything is picked. The transcript holds the hook's basename and hash, never its full command. Excerpts go in `docs/evidence/config-integrity.md` with `Verdict: PASS for Validation 3 (08b)`.

## Depends on
08a-config-check-core-cli-floor-hooks-loaded.md

## Touches
loomwright/scripts/config-integrity.sh
loomwright/scripts/test-config-integrity.sh
loomwright/scripts/fixtures/config-integrity
loomwright/scripts/test-supervisor-next-step.sh
loomwright/scripts/test-automate-next-step.d/16-config-integrity.sh
loomwright/docs/result-schemas/config-integrity.md
docs/evidence/config-integrity.md
changelog.d/config-check-plugins-marketplaces-mcp-hooks.md

## Changes since the sources were written
- Nothing from P, G1 or H4 shipped on main `8ec200e`.
- **False premises in H4 and P:** this Mac now has `installed_plugins.json` (v2), `enabledPlugins` and `extraKnownMarketplaces` in `~/.claude/settings.json`, two known marketplaces, and a user-scope MCP server. H4 recorded none of these. `~/.codex/` now exists with `[plugins.*]`, `[marketplaces.*]`, `[mcp_servers.*]` and `[projects.*]` tables (headers read only), though `codex` is still not on `PATH`.
- P's separate `plugin-pins.json` and G1's `mcp-allowlist.json` become sections of the one approved-state file. P's `claude plugin list --json` enumeration is replaced by file reads.
- G1's `plugin-pin.sh write` refusal (Part E) is not needed, since one `approve` applies the pinned-launcher rule itself.
- The lane-launch and pre-gate call sites from P and G1 are dropped. Lanes are covered by their own PICK and INIT.
