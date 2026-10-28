## No-arg flow — status dashboard

Run ONE real check per module (never guess; every cell of the dashboard is derived from a command you actually ran):

1. **observability** —
   - Env block: `[ -f "$SETTINGS" ] && jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY == "1"' "$SETTINGS" >/dev/null 2>&1`
   - Mode: if env block present, read `.env.OTEL_TRACES_EXPORTER` (value `console` → console-debug mode) and `.env.OTEL_EXPORTER_OTLP_ENDPOINT`. Classify as **local stack** when the endpoint host is `localhost`/`127.0.0.1` (ANY port — do NOT key off the literal `:4318`; the port is parameterized as `$OTEL_COLLECTOR_PORT` and a customized value must still classify as local) AND the copied stack exists (`[ -f "$OBS_DIR/docker-compose.yml" ]`); otherwise **external endpoint**.
   - Local stack health (only when local): copied stack present (`[ -f "$OBS_DIR/docker-compose.yml" ] && [ -f "$OBS_DIR/.env" ]`) and per-container health via the wait-healthy probe from the skill (single pass, no loop):
     ```bash
     docker compose -p loomwright-observability -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" ps -q \
       | xargs docker inspect -f '{{.Name}} {{.State.Health.Status}}' 2>/dev/null
     ```
     Bucket the reported states before choosing the cell: if any container reports `starting`, the stack is **booting** (first boot can take ~10 min — image pulls + ClickHouse migrations), NOT down — surface that distinctly so a just-launched `init` in another pane doesn't read as a failure. **Collector caveat (liveness-only):** `otel-collector`'s healthcheck is `--version` (the contrib image is distroless — no in-container HTTP probe), so a `healthy` collector cell proves the process is *up*, not that it bound `:4318` or is actually ingesting. True readiness is confirmed only by the `init` smoke test (Pattern 6); the dashboard MUST NOT upgrade "N/7 healthy" to "ingesting."
   - Status cell: `configured — local stack N/7 healthy (collector liveness-only)` | `configured — local stack booting (M/7 healthy, K starting)` | `configured — external endpoint` | `configured — console debug` | `partial — env block present, stack down/missing` | `not configured`.
2. **telemetry** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-egress-config.sh"` and read its `TELEMETRY=`/`TELEMETRY_REPO=` lines (v15.87.0, red-team-hardening item 02 — the SAME user-scoped resolution `send-telemetry-core.sh` itself uses; a repo-relative `.supervisor/telemetry-consent.json`, if present, is an inert informational request only, never the source of this status). `TELEMETRY=always_allow` + non-empty `TELEMETRY_REPO` → `enabled (target=<owner/repo>)`; `TELEMETRY=no` → `disabled`; empty/unset (no user-scope entry for this repo's slug) → `unset`.
3. **notifications** — always-on via plugin hooks (desktop banners at human-decision gates); status cell is `active (built-in hooks)`. No check command needed — note that the webhook variant additionally requires the webhook module below.
4. **webhook** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-egress-config.sh"` and read its `WEBHOOK_URL=` line (this is the SAME resolution `send-webhook.sh` uses — env var, else the user-scope `~/.claude/loomwright/egress.json` entry for this repo's slug; v15.87.0, red-team-hardening item 02). Status: `set (host: <hostname-only>, source: env var|user-scope config)` / `not set`. NEVER print the URL value itself (it may embed a token) — print only the hostname and which source resolved it.
5. **beads** — `command -v bd >/dev/null 2>&1` and `[ -d .beads ]`. Status: `ready` / `bd installed, repo not initialised` / `not installed`. Note: only Orchestrator/Product Owner use Beads — optional.
6. **mysql-mcp** — check `DB_HOST`, `DB_USER`, `DB_PASS`, `DB_NAME` env vars are non-empty (`DB_PORT` optional). Also try to read the pinned server version this repo's copy of `mysql-mcp/.mcp.json` launches: `jq -r '.mcpServers.mysql.args[] | select(contains("=="))' mysql-mcp/.mcp.json 2>/dev/null | sed 's/.*==//'` (repo-relative — only resolvable from a dev checkout of this marketplace, not from a project where only the standalone `mysql-mcp@atelier` plugin is installed; if unreachable or empty, omit the suffix rather than guessing). Status: `configured (pinned vX.Y.Z)` / `missing: <names of unset vars> (pinned vX.Y.Z)` when the version resolves, else plain `configured` / `missing: <names of unset vars>`. NEVER print values — names only.
7. **memory** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh" check` and read the `Memory readiness:` verdict plus the per-path `intended` / `unintended` ignore-status cells and the `allowlist:` line. `check` is fail-safe (exits 0) and READ-ONLY — it writes nothing. Derive a compact status cell: `configured` → `stores committable`; `gated (...)` → `memory stores committable, findings ledger WITHHELD` plus the offending slugs from the helper's own parenthetical (a **third** outcome — never collapse it into `configured` or `not configured`); `not configured` → `stores ignored (not in version control)`; `partial (...)` and `unknown (...)` → surface the helper's own parenthetical verbatim (`unknown` means the ignore status could not be probed at all — never restate it as a configured/partial claim); if the `.gitignore:` cell reads `absent` or `unparseable: …`, say so instead (e.g. `.gitignore unparseable — apply would abort`). Never guess — every cell comes from that one probe.

8. **rules** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/seed-rules.sh" check` and read its per-seed `seed: ABSENT` / `seed: ALREADY SEEDED` lines plus the `seeds: N total · N already seeded · N absent` summary. `check` is READ-ONLY — it invokes no writer and creates nothing (not even the store directory). Derive a compact status cell from that summary alone: `0 absent` → `seeded (N/N portable rules)`; `N absent` with some present → `partially seeded (N of M)`; all absent → `not seeded (M portable rules available)`. If the helper exits non-zero it could not run (missing `jq` — exit 2); report `unknown (seed-rules.sh could not run)` and never a seeded/not-seeded claim. Never guess — every cell comes from that one probe.

9. **statusline** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" check` and read its `statusLine:` cell plus the `Statusline readiness:` verdict. `check` is READ-ONLY — it writes nothing. Derive a compact status cell from that verdict alone: `configured` → `active (one-line run report)`; `not configured` → `not wired`; `foreign (...)` → `another status line is configured — preserved` (a **third** outcome: it is neither configured nor unconfigured, and must never be collapsed into either, because collapsing it to `not configured` is what would invite a silent overwrite); `unknown (...)` → surface the helper's own parenthetical verbatim (missing `jq`, or a settings document that does not parse — report UNVERIFIED, never a configured/not-configured claim). Never guess — every cell comes from that one probe.

10. **base-branch** — run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-base-branch.sh" status` and read its `base-branch:` headline. It writes no config. Status cell: the headline's value verbatim — `<branch> (source: <step>)`, or `unresolved (<status>)` (report that as UNRESOLVED, never as a branch). Never guess — every cell comes from that one probe.


Print the dashboard:

```
## /setup — module status

| Module        | Status                                  | Configure with        |
|---------------|-----------------------------------------|-----------------------|
| observability | <derived>                               | /setup observability  |
| telemetry     | <derived>                               | /setup telemetry      |
| notifications | active (built-in hooks)                 | /setup notifications  |
| webhook       | <derived>                               | /setup webhook        |
| beads         | <derived>                               | /setup beads          |
| mysql-mcp     | <derived, incl. pinned version>         | /setup mysql-mcp      |
| memory        | <derived>                               | /setup memory         |
| rules         | <derived>                               | /setup rules          |
| statusline    | <derived>                               | /setup statusline     |
| base-branch   | <derived>                               | /setup base-branch    |
```

Then use `AskUserQuestion`. **`AskUserQuestion` accepts at most 4 options**, so do NOT emit one option per unconfigured module (the registry holds more modules than the 4-option limit → an invalid call). The set below is FIXED at four and must NOT be grown when a module is added — a new module folds into an existing bucket or gets its own nested question, exactly as `memory`, `rules`, `statusline` and `base-branch` do here:
- `question`: "Which would you like to configure now?"
- `header`: "Configure"
- `multiSelect`: true
- `options` (exactly these, in order; append each module's current status to its description):
  1. **Claude Code surfaces (observability · status line)** — the modules that write under your Claude Code config directory; selecting it asks ONE nested question (below) to pick which.
  2. **Repo stores & settings (memory in version control · portable rule seeds · base branch)** — the per-repo apply flows; selecting it asks ONE nested question (below) to pick which.
  3. **Other integrations (telemetry · webhook · Beads · MySQL MCP)** — print status + setup guidance / delegation for these (telemetry delegates to `/telemetry`; webhook offers a guided write of the user-scope URL, see its own module below; Beads · MySQL MCP are guidance-only; `notifications` is always-on and needs no action).
  4. **Nothing — just checking** — stop with the summary line.

**How to render the status on a BUNDLED option** (options 1, 2 and 3 each fold several modules behind one label, so "the module's status" is ambiguous): append the per-module statuses joined by ` · `, each prefixed with its module name — `observability: <status> · statusline: <status>` for option 1, `memory: <status> · rules: <status> · base-branch: <status>` for option 2, and `telemetry: <status> · webhook: <status> · beads: <status> · mysql-mcp: <status>` for option 3. Never collapse them into one aggregate word, and never pick one module's status to stand for the bundle. Option 4 is no-module and takes none. Truncate from the right if the description exceeds the option-description limit — drop whole `name: status` pairs, never a status string mid-word.

**Nested question — only when option 1 was selected** (also ≤4 options; never inline these into the set above):
- `question`: "Which Claude Code surface?"
- `header`: "Surfaces"
- `multiSelect`: true
- `options` (exactly these, in order; append each module's current status to its description):
  1. **observability** — full local-Langfuse / existing-endpoint / console init flow.
  2. **statusline** — wire the one-line run report (phase · branch · N/M subtasks · age of the last event) into the user-scope settings file. Backup-first and parse-gated. **If a status line you did not install is already configured it is PRESERVED and merely reported** — replacing it is a separate, explicit choice, and the previous value is recorded so `remove` restores it.
  3. **None — go back** — skip both and continue with the remaining selections.

**Nested question — only when option 2 was selected** (also ≤4 options; never inline these into the set above):
- `question`: "Which repo store or setting?"
- `header`: "Repo"
- `multiSelect`: true
- `options` (exactly these, in order; append each module's current status to its description):
  1. **memory** — put `.claude/agent-memory/` + `.supervisor/memory/` + the judgement trail (`.supervisor/requirements/`, `.supervisor/jobs/done/` + `failed/`, `.supervisor/automate/*.md` — v15.84.0) + the findings ledger `.supervisor/postmortem/results.jsonl` under version control IN PLACE (gitignore negation + repo allowlist). The ledger is GATED: it is un-ignored only while every record's `.repo` is inside the repo allowlist. Consent-bearing — the memory module's own Offer step states what becomes version-controlled before anything is written.
  2. **rules** — seed `.agent/rules/` with a small set of PORTABLE conventions (true of any repo) so a cold-start repo is not empty. They are labelled SEEDED, not learned: every one carries `provenance.source=setup:rules-seed`. Advisory only, no gate.
  3. **base-branch** — view or pin the base (integration) branch every stage branches from, targets and diffs against, in `.supervisor/config.json` (`.base_branch`). Backup-first; nothing is written without a choice.
  4. **None — go back** — skip all three and continue with the remaining selections.

Run the corresponding module flow (below) for each selection, in the order listed. For option 3, run the `telemetry` delegation block plus the `webhook`, `beads`, and `mysql-mcp` status/guidance blocks in turn. If "Nothing", stop with the summary line.

**Every module stays reachable as a direct jump regardless of this set** — `/setup memory` and `/setup rules` (and every other module name) go straight to that module's flow without touching the dashboard question. The ≤4-option set is a convenience for the no-arg dashboard, never the only route to a module.

