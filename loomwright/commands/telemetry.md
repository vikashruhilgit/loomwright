---
description: Manage opt-in GitHub Issues telemetry — status, enable, disable, test
---

# Command: /telemetry

## Usage

```
/telemetry status              # Report current consent + target repo + last-sent + retained pending markers
/telemetry enable              # Interactively configure target repo and write always_allow consent
/telemetry disable             # Write {"telemetry":"no"} consent (silently disables future sends)
/telemetry test                # Dry-run the core script against latest payload or bundled fixture
```

## Parameters

- **subcommand** (required): one of `status`, `enable`, `disable`, `test`.
  - If omitted or unrecognised, print this usage block and exit.

## What This Does

Telemetry is **opt-in** and disabled by default. The hook (`SubagentStop` -> `send-telemetry.sh`) will only post to GitHub Issues once the user has explicitly run `/telemetry enable` AND a target repo has been resolved (env var `LOOMWRIGHT_TELEMETRY_REPO` OR the user-scope `~/.claude/loomwright/egress.json` entry for this repo's slug).

This slash command is the SOLE first-run consent path. The hook itself never prompts the user — `type: command` hooks cannot drive interactive prompts. See `${CLAUDE_PLUGIN_ROOT}/docs/TELEMETRY.md` for the full design.

**v15.87.0 — consent is USER-SCOPED, keyed by repo (red-team-hardening item 02).** Consent and the target repo now live in `~/.claude/loomwright/egress.json`, keyed by this repo's slug (`git remote get-url origin` normalized to `owner/repo`, else `local:<toplevel-basename>`) — never in the repo-relative `.supervisor/telemetry-consent.json`. A repo-relative consent file can still exist (some old installs have one), but it is read ONLY as an informational *request*, never a grant: a cloned/attacker-controlled repo that ships its own `.supervisor/telemetry-consent.json` can no longer choose its own consent or its own destination repo. Resolution happens in `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-egress-config.sh`, shared by both the telemetry core and the webhook wrapper.

## When to Use

- **`/telemetry status`** — Inspect current consent + target repo + last-sent timestamp + retained pending-notice markers (~24h window) without changing anything.
- **`/telemetry enable`** — First-time setup or change of target repo. Writes `.supervisor/telemetry-consent.json`.
- **`/telemetry disable`** — Stop telemetry without uninstalling the plugin. Writes `{"telemetry":"no"}`.
- **`/telemetry test`** — Verify the core script renders a sane issue body for the most recent (or fixture) payload. NEVER calls `gh`.

---

# Agent Prompt

You are handling the `/telemetry` slash command. The user passed arguments after the command. Parse the FIRST positional argument as the subcommand. Branch as follows.

## Setup (every subcommand)

1. The user-project root is the directory containing `.supervisor/` (typically the current working directory) — that is where the repo-relative *request* file and logs live. The AUTHORITATIVE consent + target-repo store is `~/.claude/loomwright/egress.json` (user scope, keyed by repo slug — see the resolver below). The plugin scripts and bundled fixtures live INSIDE the plugin install, NOT under the user project. Always reference plugin assets via the `${CLAUDE_PLUGIN_ROOT}` environment variable (set by Claude Code for plugin-distributed commands), e.g. `${CLAUDE_PLUGIN_ROOT}/scripts/send-telemetry-core.sh`, `${CLAUDE_PLUGIN_ROOT}/scripts/resolve-egress-config.sh`, and `${CLAUDE_PLUGIN_ROOT}/scripts/telemetry-fixtures/<name>.json`. NEVER hard-code `loomwright/...` paths under the user project — those only resolve in the maintainer's dev checkout.
2. Resolve this repo's slug via Bash once, for every subcommand: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-egress-config.sh"` and read its `REPO_SLUG=` line. This is the exact key used in `~/.claude/loomwright/egress.json`'s `.repos` map — use it, never recompute the slug logic yourself.
3. Print a 1-line summary at the END of the subcommand output, prefixed `Telemetry:` so the user can scan results.

## If subcommand == `status`

1. **Run the resolver** (Bash): `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-egress-config.sh"`. Parse its `KEY=VALUE` output — this is the single source of truth for the resolved consent + target repo (`TELEMETRY=`, `TELEMETRY_REPO=`, `REPO_SLUG=`, `REPO_REQUESTED_TELEMETRY_REPO=`).
2. **Env var:** `LOOMWRIGHT_TELEMETRY_REPO` — report whether it is set (never print the raw resolver env precedence logic to the user, just the outcome).
3. **Honoured flag:** compare `REPO_REQUESTED_TELEMETRY_REPO` (if non-empty) to `TELEMETRY_REPO` — `honoured: yes` when they are byte-identical, `honoured: no` when they differ or the repo-relative request is present but there is no user-scope entry at all.
4. **Migration offer (one-time, human-confirmed):** if a repo-relative `.supervisor/telemetry-consent.json` exists (i.e. `REPO_REQUESTED_TELEMETRY_REPO` is non-empty, or the file parses with a `telemetry` key) AND `TELEMETRY=` from the resolver is empty (no user-scope entry for this repo's slug yet), offer to import it: use `AskUserQuestion` — `question`: "Found a repo-relative telemetry-consent.json requesting `<value>`, but no user-scope consent is set for this repo yet. Import it into your user-scope config now?", `header`: "Import request", `multiSelect`: false, `options`: `Yes, import` / `No, leave unset`. **This import ONLY happens here, human-confirmed inside `/telemetry status` — hooks and every other code path NEVER auto-import** (this is the exact vulnerability class this feature closes; auto-importing would silently recreate it). If the user picks "Yes, import", run the SAME write procedure as `enable` below using the repo-relative file's `telemetry_repo` value (still validated against the `owner/repo` regex), then re-run the resolver and continue the status report with the fresh values.
5. **Pending-notice markers retained ~24h:** Use Bash to count files matching the glob `.supervisor/logs/telemetry-pending-shown-*.flag`. Run:
   ```
   ls -1 .supervisor/logs/telemetry-pending-shown-*.flag 2>/dev/null | wc -l | tr -d ' '
   ```
   The output is the count. If the directory or files do not exist, the count is `0`.
6. **Last sent timestamp:** Run:
   ```
   tail -n 1 .supervisor/logs/telemetry-sent.log 2>/dev/null | awk '{print $1}'
   ```
   The first column of the last line is the ISO timestamp. If the file does not exist or is empty, print `never`.

Print the report in this exact shape (use code fences for clarity):

```
## /telemetry status

- Repo slug: <owner/repo or local:name>
- Consent state (user scope): <always_allow | no | unset>
- Resolved target repo: <owner/repo or (none)>
- Source: <env var | user-scope config | unset (telemetry disabled)>
- Repo-relative request: <owner/repo or (none)> — honoured: <yes | no | n/a>
- Pending-notice session markers retained ~24h: <N>
- Last sent: <ISO timestamp or never>
```

Then a 1-line summary, e.g. `Telemetry: enabled, target=vikashruhilgit/loomwright (user-scope config), last sent 2026-04-25T19:27:09Z.` or `Telemetry: disabled (consent=unset, no target repo configured).`

## If subcommand == `enable`

1. Use AskUserQuestion to collect the target repo. Suggest `vikashruhilgit/loomwright` as the canonical maintainer repo for community-shared signal, but accept any `owner/repo` value. Example question:
   - `question`: "Which GitHub repo should receive telemetry issues? (owner/repo format)"
   - `header`: "Target repo"
   - `multiSelect`: false
   - `options`: an array with two entries — the suggested repo `vikashruhilgit/loomwright` (label: "Maintainer repo (recommended for community signal)") and an `Other` option that lets the user type a custom value (label: "Other repo (I'll specify owner/repo)").
2. If the user chose `Other`, ask a follow-up free-text question to collect the `owner/repo` value.
3. Validate the answer against `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`. If it does not match, print an error explaining the format and stop (do NOT write the file). Example error: `Telemetry: invalid repo format "<value>". Expected owner/repo (e.g. octocat/hello-world). No changes written.`
4. **Resolve `REPO_SLUG`** via the resolver (Setup step 2 above) — this is the key you write under.
5. **Write the user-scope entry, backup-first, jq-deep-merge, abort-on-parse-failure (never a partial write):**
   ```bash
   EGRESS="$HOME/.claude/loomwright/egress.json"
   mkdir -p "$(dirname "$EGRESS")"
   if [ -f "$EGRESS" ]; then
     if ! jq -e . "$EGRESS" >/dev/null 2>&1; then
       echo "ABORT: existing $EGRESS does not parse as JSON — refusing to touch it unbacked-up. No changes written."
       exit 1
     fi
     cp "$EGRESS" "${EGRESS}.backup.$(date -u +%Y%m%dT%H%M%SZ)"
   fi
   TMP="$(mktemp)"
   BASE='{"schema_version":1,"repos":{}}'
   [ -f "$EGRESS" ] && BASE="$(cat "$EGRESS")"
   printf '%s' "$BASE" | jq --arg slug "$REPO_SLUG" --arg repo "<answer>" \
     '.schema_version = 1 | .repos[$slug].telemetry = "always_allow" | .repos[$slug].telemetry_repo = $repo' \
     > "$TMP" && mv "$TMP" "$EGRESS"
   ```
   Run this via Bash with `<answer>` and `$REPO_SLUG` substituted for real values (never shell-interpolate the repo string directly into the jq filter — pass it as a `--arg`, exactly as shown, so a hostile repo name can never break out of the JSON). If the `jq -e .` parse check fails, STOP — print the abort message verbatim and do NOT write anything, not even a backup-less partial file. This is the same discipline `setup-memory.sh` and the `/setup` modules already use for their own `.supervisor/config.json`/`~/.claude/settings.json` writes (backup-first, parse-gated, abort-without-partial-write).
6. **Do NOT** write `.supervisor/telemetry-consent.json` anymore — that file is now read-only input (a repo-relative *request*), never this command's output target. If a stale repo-relative consent file exists from before this change, leave it alone (it is now inert on its own).
7. Print confirmation:
   ```
   ## /telemetry enable

   Telemetry consent: always_allow
   Target repo: <answer>
   Repo slug: <REPO_SLUG>
   User-scope config: ~/.claude/loomwright/egress.json (backup written)
   ```
   Followed by 1-line summary: `Telemetry: enabled, target=<answer> (user-scope config). Future qualifying agent runs will post issues.`

## If subcommand == `disable`

1. **Resolve `REPO_SLUG`** via the resolver (Setup step 2 above).
2. **Write the user-scope entry** using the SAME backup-first, jq-deep-merge, abort-on-parse-failure procedure as `enable` step 5, except the jq filter sets `.repos[$slug].telemetry = "no"` and does NOT touch `.repos[$slug].telemetry_repo` (leave whatever target repo was previously configured — disabling is reversible without re-asking for the repo).
3. Print confirmation:
   ```
   ## /telemetry disable

   Telemetry consent: no
   Repo slug: <REPO_SLUG>
   User-scope config: ~/.claude/loomwright/egress.json (backup written)
   ```
   Followed by 1-line summary: `Telemetry: disabled. The hook will skip silently for the rest of this and future sessions.`

## If subcommand == `test`

1. Locate a payload to dry-run against. Try in order:
   - **(a)** Latest payload from `.supervisor/logs/telemetry.log` (under the user-project root). If the file exists and is non-empty, attempt to extract the most recent JSON-payload line. The wrapper does NOT log raw payloads, only structured event lines, so payload extraction may fail — that is expected. Treat any of these as "no payload available": missing file, empty file, no JSON object on the last 50 lines.
   - **(b)** Fallback: bundled fixture at `${CLAUDE_PLUGIN_ROOT}/scripts/telemetry-fixtures/supervisor-escalated.json` (resolve `${CLAUDE_PLUGIN_ROOT}` via Bash before reading — it is the canonical Claude Code variable for plugin-bundled assets and works regardless of which user project the plugin is installed into). Read the file with the Read tool once the absolute path is known.
2. Pipe the chosen payload to the core script in dry-run mode (Bash):
   ```
   cat <payload-file-or-stdin-source> | bash "${CLAUDE_PLUGIN_ROOT}/scripts/send-telemetry-core.sh" --dry-run
   ```
   Capture stdout. The script always exits 0 in dry-run mode regardless of `WOULD_EXIT`, so do not branch on exit status — branch on the `WOULD_EXIT=<n>` line in stdout.
3. Parse stdout for these fields and print them:
   - `TARGET_REPO=<value>` — print `Target repo: <value>` or `Target repo: unset` if missing/empty.
   - `BODY_BEGIN`...`BODY_END` block — print the body verbatim under a `## Issue body (dry-run)` heading using a markdown code fence.
   - `WOULD_EXIT=<n>` — print `WOULD_EXIT: <n>`.
4. **Do NOT** call `gh issue create`. **Do NOT** modify `~/.claude/loomwright/egress.json` or any repo-relative file. Dry-run is read-only.
5. Print final 1-line summary:
   - If `WOULD_EXIT=0`: `Telemetry: dry-run would create an issue at <target-repo>.`
   - Else: `Telemetry: dry-run would skip (WOULD_EXIT=<n>); see body above for early-exit reason.`

## If subcommand is missing or unrecognised

Print the Usage block at the top of this file and exit. 1-line summary: `Telemetry: unknown subcommand "<arg>". Run /telemetry status to inspect current state.`

---

## Constraints (apply to every subcommand)

- ONLY modify `~/.claude/loomwright/egress.json` (user scope), and only via the backup-first, jq-deep-merge, abort-on-parse-failure procedure in `enable`/`disable` (and `status`'s human-confirmed one-time import, which reuses that same procedure). Never touch any other file.
- NEVER write `.supervisor/telemetry-consent.json` — it is a read-only, repo-relative *request* surface now, never this command's output target.
- For `enable`, use AskUserQuestion (not a hook-driven prompt) to collect the target repo.
- NEVER call `gh issue create` from this command — that is the hook's job.
- **NEVER auto-import** a repo-relative request into user scope. The ONLY import path is `status`'s human-confirmed `AskUserQuestion` offer — this is a standing invariant, not a convenience shortcut to relax later (auto-importing would recreate the exact vulnerability red-team-hardening item 02 closes).
- `test` is fully read-only.
- Always print the 1-line `Telemetry: ...` summary at the end so the user can scan results.

## Examples

### Example: status (telemetry not configured)
```
$ /telemetry status

## /telemetry status

- Repo slug: vikashruhilgit/loomwright
- Consent state (user scope): unset
- Resolved target repo: (none)
- Source: unset (telemetry disabled)
- Repo-relative request: (none) — honoured: n/a
- Pending-notice session markers retained ~24h: 0
- Last sent: never

Telemetry: disabled (consent=unset, no target repo configured).
```

### Example: status (repo-relative request present, no user-scope entry — offers import)
```
$ /telemetry status

Found a repo-relative telemetry-consent.json requesting `some/repo`, but no
user-scope consent is set for this repo yet.

[AskUserQuestion: "Import it into your user-scope config now?"]
> Yes, import

## /telemetry status

- Repo slug: vikashruhilgit/loomwright
- Consent state (user scope): always_allow
- Resolved target repo: some/repo
- Source: user-scope config
- Repo-relative request: some/repo — honoured: yes
- Pending-notice session markers retained ~24h: 0
- Last sent: never

Telemetry: enabled, target=some/repo (user-scope config, imported from repo-relative request).
```

### Example: enable (interactive)
```
$ /telemetry enable

[AskUserQuestion: "Which GitHub repo should receive telemetry issues?"]
> vikashruhilgit/loomwright

## /telemetry enable

Telemetry consent: always_allow
Target repo: vikashruhilgit/loomwright
Repo slug: vikashruhilgit/loomwright
User-scope config: ~/.claude/loomwright/egress.json (backup written)

Telemetry: enabled, target=vikashruhilgit/loomwright (user-scope config). Future qualifying agent runs will post issues.
```

### Example: disable
```
$ /telemetry disable

## /telemetry disable

Telemetry consent: no
Repo slug: vikashruhilgit/loomwright
User-scope config: ~/.claude/loomwright/egress.json (backup written)

Telemetry: disabled. The hook will skip silently for the rest of this and future sessions.
```

### Example: test (dry-run with fixture)
```
$ /telemetry test

## Issue body (dry-run)

[... formatted markdown body printed by core script ...]

Target repo: vikashruhilgit/loomwright
WOULD_EXIT: 0

Telemetry: dry-run would create an issue at vikashruhilgit/loomwright.
```
