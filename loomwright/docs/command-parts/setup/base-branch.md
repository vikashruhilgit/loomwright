## Module: base-branch

Views and sets the project's **base (integration) branch** — the branch every stage branches from, targets and diffs against. The answer comes from ONE resolver, `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-base-branch.sh` (its header holds the precedence; `skills/supervisor-config/SKILL.md` documents the `.base_branch` key). This module writes only that key, so a repo whose integration branch is not the GitHub default (for example `development`) can pin it once.

The deterministic engine is `${CLAUDE_PLUGIN_ROOT}/scripts/setup-base-branch.sh` (`status` / `set <branch>` / `remove`). It writes `<project>/.supervisor/config.json` key `.base_branch` ONLY — a jq merge, backup-first, parse-gated, atomic, byte-compare idempotent — and every refusal or abort writes nothing and exits 0 with a named headline. `.supervisor/config.json` is gitignored by convention, so the setting is per clone: a teammate's clone resolves on its own until they run `set` too.

**Check.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-base-branch.sh" status` and read its cells: `config:` (the path), `config .base_branch:` (the raw value, `absent`, or `UNPARSEABLE …`) and the headline `base-branch: <branch> (source: <step>)` — the resolver's own `--explain` answer, where `<step>` is `flag`, `brief`, `config`, `origin-head` or `gh` — or `base-branch: unresolved (<status>)` (`base_branch_unresolved`, or `base_branch_invalid:config` for a bad config value). The config is not written; the resolver's origin-head step may run `git remote set-head origin -a`.

**Report.** Print the headline verbatim. For `status`, STOP after the report — no offer, no writes.

**Offer.** Explicit subcommands run directly: `set <branch>` names its value and `remove` names its action, so neither asks again. Bare `/setup base-branch` (or the dashboard's nested pick) uses `AskUserQuestion` (cap 4 options):
- `question`: "Pin this repo's base branch in .supervisor/config.json?"
- `header`: "Base branch"
- `multiSelect`: false
- `options`:
  1. `Pin <resolved>` — offered only when the headline resolved from `origin-head` or `gh`: write that branch to config.
  2. `Remove` — offered only when `config .base_branch` holds a value: delete the key so the resolver falls back to origin/HEAD.
  3. `Status only` — "Re-print the report and stop (no writes)." (the default)

A different branch is set with `/setup base-branch set <branch>` (or the question's free-text answer, used as `<branch>`). Can't ask (non-interactive, or inside a subagent): report and stop with `Setup: base-branch — not changed (cannot ask)`; nothing is written.

**Apply.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-base-branch.sh" set <branch>` (or `remove`) and relay its headline verbatim. Exactly one is printed:
- `set: applied` (+ `backup: <path>`) / `set: applied (created <config>)` — written; a `verify:` status follows.
- `set: no-op — already configured …` — nothing written, no backup.
- `set: REFUSED (invalid_branch_name)` — not a valid branch name; `set: REFUSED (no_such_remote_branch)` — `origin/<branch>` is not a remote-tracking ref (suggest `git fetch origin <branch>`). Nothing written.
- `remove: removed` (+ `backup: <path>`) — only `.base_branch` deleted; `remove: no-op — …` — nothing to delete.
- `<set|remove>: ABORTED (<reason>)` — `config_unparseable` (not exactly one JSON object), `config_symlink`, `jq_unavailable`, `no_backup_name`, `backup_failed`, `write_failed`. Nothing written; **never repair the config to get past it**.

**Verify.** Success is claimed ONLY from the `verify:` block's headline: after `set <branch>` it must read `base-branch: <branch> (source: config)`; after `remove` it shows the next step's answer (`origin-head`, `gh`, or `unresolved`).

**Idempotency note.** A second identical `set` reports `no-op — already configured`, leaves the file byte-identical and makes no second backup — the engine compares the document it would write with the one on disk before touching anything. A flag or a brief `Base Branch:` line still outranks the config for that run.

---

