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

Telemetry is **opt-in** and disabled by default. The hook (`SubagentStop` -> `send-telemetry.sh`) will only post to GitHub Issues once the user has explicitly run `/telemetry enable` AND a target repo has been resolved (env var `AI_AGENT_MANAGER_TELEMETRY_REPO` OR consent-file `telemetry_repo`).

This slash command is the SOLE first-run consent path. The hook itself never prompts the user — `type: command` hooks cannot drive interactive prompts. See `ai-agent-manager-plugin/docs/TELEMETRY.md` for the full design.

## When to Use

- **`/telemetry status`** — Inspect current consent + target repo + last-sent timestamp + retained pending-notice markers (~24h window) without changing anything.
- **`/telemetry enable`** — First-time setup or change of target repo. Writes `.supervisor/telemetry-consent.json`.
- **`/telemetry disable`** — Stop telemetry without uninstalling the plugin. Writes `{"telemetry":"no"}`.
- **`/telemetry test`** — Verify the core script renders a sane issue body for the most recent (or fixture) payload. NEVER calls `gh`.

---

# Agent Prompt

You are handling the `/telemetry` slash command. The user passed arguments after the command. Parse the FIRST positional argument as the subcommand. Branch as follows.

## Setup (every subcommand)

1. The repo root is the directory containing `.supervisor/` (typically the current working directory). Use the absolute path when invoking scripts. The plugin scripts live under `ai-agent-manager-plugin/scripts/`.
2. Print a 1-line summary at the END of the subcommand output, prefixed `Telemetry:` so the user can scan results.

## If subcommand == `status`

Read each of the following and synthesise a status report:

1. **Consent file:** Read `.supervisor/telemetry-consent.json` if it exists.
   - If present and parses as JSON: extract `telemetry` (one of `always_allow` | `no` | `prompt`) and `telemetry_repo` (string or absent).
   - If absent OR malformed JSON: treat consent state as `unset` (equivalent to `prompt`).
2. **Env var:** Read `AI_AGENT_MANAGER_TELEMETRY_REPO`. Trim whitespace. Treat empty as unset.
3. **Resolved target repo + source** (precedence):
   - If env var is set and matches `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$` -> source is `env var`, target is the env value.
   - Else if consent file has a non-empty `telemetry_repo` matching the same regex -> source is `consent file`, target is that value.
   - Else -> source is `unset (telemetry disabled)`, target is `(none)`.
4. **Pending-notice markers retained ~24h:** Use Bash to count files matching the glob `.supervisor/logs/telemetry-pending-shown-*.flag`. Run:
   ```
   ls -1 .supervisor/logs/telemetry-pending-shown-*.flag 2>/dev/null | wc -l | tr -d ' '
   ```
   The output is the count. If the directory or files do not exist, the count is `0`.
5. **Last sent timestamp:** Run:
   ```
   tail -n 1 .supervisor/logs/telemetry-sent.log 2>/dev/null | awk '{print $1}'
   ```
   The first column of the last line is the ISO timestamp. If the file does not exist or is empty, print `never`.

Print the report in this exact shape (use code fences for clarity):

```
## /telemetry status

- Consent state: <always_allow | no | prompt | unset>
- Resolved target repo: <owner/repo or (none)>
- Source: <env var | consent file | unset (telemetry disabled)>
- Pending-notice session markers retained ~24h: <N>
- Last sent: <ISO timestamp or never>
```

Then a 1-line summary, e.g. `Telemetry: enabled, target=vikashruhilgit/ai-agent-manager (env var), last sent 2026-04-25T19:27:09Z.` or `Telemetry: disabled (consent=unset, no target repo configured).`

## If subcommand == `enable`

1. Use AskUserQuestion to collect the target repo. Suggest `vikashruhilgit/ai-agent-manager` as the canonical maintainer repo for community-shared signal, but accept any `owner/repo` value. Example question:
   - `question`: "Which GitHub repo should receive telemetry issues? (owner/repo format)"
   - `header`: "Target repo"
   - `multiSelect`: false
   - `options`: an array with two entries — the suggested repo `vikashruhilgit/ai-agent-manager` (label: "Maintainer repo (recommended for community signal)") and an `Other` option that lets the user type a custom value (label: "Other repo (I'll specify owner/repo)").
2. If the user chose `Other`, ask a follow-up free-text question to collect the `owner/repo` value.
3. Validate the answer against `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`. If it does not match, print an error explaining the format and stop (do NOT write the file). Example error: `Telemetry: invalid repo format "<value>". Expected owner/repo (e.g. octocat/hello-world). No changes written.`
4. Ensure `.supervisor/` exists (`mkdir -p .supervisor`).
5. Write `.supervisor/telemetry-consent.json` with EXACTLY this content (replace `<answer>` with the validated repo):
   ```json
   {"telemetry":"always_allow","telemetry_repo":"<answer>"}
   ```
   Use the Write tool. If the file already exists, overwrite it (the user is reconfiguring).
6. Print confirmation:
   ```
   ## /telemetry enable

   Telemetry consent: always_allow
   Target repo: <answer>
   Consent file: .supervisor/telemetry-consent.json
   ```
   Followed by 1-line summary: `Telemetry: enabled, target=<answer> (consent file). Future qualifying agent runs will post issues.`

## If subcommand == `disable`

1. Ensure `.supervisor/` exists (`mkdir -p .supervisor`).
2. Write `.supervisor/telemetry-consent.json` with EXACTLY this content:
   ```json
   {"telemetry":"no"}
   ```
   Use the Write tool. Overwrite if it exists.
3. Print confirmation:
   ```
   ## /telemetry disable

   Telemetry consent: no
   Consent file: .supervisor/telemetry-consent.json
   ```
   Followed by 1-line summary: `Telemetry: disabled. The hook will skip silently for the rest of this and future sessions.`

## If subcommand == `test`

1. Locate a payload to dry-run against. Try in order:
   - **(a)** Latest payload from `.supervisor/logs/telemetry.log`. If the file exists and is non-empty, attempt to extract the most recent JSON-payload line. The wrapper does NOT log raw payloads, only structured event lines, so payload extraction may fail — that is expected. Treat any of these as "no payload available": missing file, empty file, no JSON object on the last 50 lines.
   - **(b)** Fallback: bundled fixture `ai-agent-manager-plugin/scripts/telemetry-fixtures/supervisor-escalated.json` (read this file directly with the Read tool — it is committed to the repo).
2. Pipe the chosen payload to the core script in dry-run mode:
   ```
   cat <payload-file-or-stdin-source> | bash ai-agent-manager-plugin/scripts/send-telemetry-core.sh --dry-run
   ```
   Capture stdout. The script always exits 0 in dry-run mode regardless of `WOULD_EXIT`, so do not branch on exit status — branch on the `WOULD_EXIT=<n>` line in stdout.
3. Parse stdout for these fields and print them:
   - `TARGET_REPO=<value>` — print `Target repo: <value>` or `Target repo: unset` if missing/empty.
   - `BODY_BEGIN`...`BODY_END` block — print the body verbatim under a `## Issue body (dry-run)` heading using a markdown code fence.
   - `WOULD_EXIT=<n>` — print `WOULD_EXIT: <n>`.
4. **Do NOT** call `gh issue create`. **Do NOT** modify `.supervisor/telemetry-consent.json`. Dry-run is read-only.
5. Print final 1-line summary:
   - If `WOULD_EXIT=0`: `Telemetry: dry-run would create an issue at <target-repo>.`
   - Else: `Telemetry: dry-run would skip (WOULD_EXIT=<n>); see body above for early-exit reason.`

## If subcommand is missing or unrecognised

Print the Usage block at the top of this file and exit. 1-line summary: `Telemetry: unknown subcommand "<arg>". Run /telemetry status to inspect current state.`

---

## Constraints (apply to every subcommand)

- ONLY modify `.supervisor/telemetry-consent.json`. Never touch any other file.
- For `enable`, use AskUserQuestion (not a hook-driven prompt) to collect the target repo.
- NEVER call `gh issue create` from this command — that is the hook's job.
- NEVER read or modify `.supervisor/telemetry-consent.json` outside of the `enable` and `disable` paths beyond the read in `status`.
- `test` is fully read-only.
- Always print the 1-line `Telemetry: ...` summary at the end so the user can scan results.

## Examples

### Example: status (telemetry not configured)
```
$ /telemetry status

## /telemetry status

- Consent state: unset
- Resolved target repo: (none)
- Source: unset (telemetry disabled)
- Pending-notice session markers retained ~24h: 0
- Last sent: never

Telemetry: disabled (consent=unset, no target repo configured).
```

### Example: enable (interactive)
```
$ /telemetry enable

[AskUserQuestion: "Which GitHub repo should receive telemetry issues?"]
> vikashruhilgit/ai-agent-manager

## /telemetry enable

Telemetry consent: always_allow
Target repo: vikashruhilgit/ai-agent-manager
Consent file: .supervisor/telemetry-consent.json

Telemetry: enabled, target=vikashruhilgit/ai-agent-manager (consent file). Future qualifying agent runs will post issues.
```

### Example: disable
```
$ /telemetry disable

## /telemetry disable

Telemetry consent: no
Consent file: .supervisor/telemetry-consent.json

Telemetry: disabled. The hook will skip silently for the rest of this and future sessions.
```

### Example: test (dry-run with fixture)
```
$ /telemetry test

## Issue body (dry-run)

[... formatted markdown body printed by core script ...]

Target repo: vikashruhilgit/ai-agent-manager
WOULD_EXIT: 0

Telemetry: dry-run would create an issue at vikashruhilgit/ai-agent-manager.
```
