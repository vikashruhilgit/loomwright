---
name: setup
description: Module protocol authority for the /setup umbrella command — the check/report/offer/apply/verify contract, the module registry, the jq deep-merge rules for ~/.claude/settings.json (backup-first, abort-on-parse-failure, idempotent), the .gitignore managed-block rules for the memory module, the statusline module's user-scope write class, the ui module's local-serve write class, the seeded-vs-learned provenance contract for the rules module, and the OTLP smoke-test recipe. Use when running /setup or modifying any setup module.
version: "1.4.0"
lastUpdated: "2026-09-03"
---

# Setup Skill

Protocol authority for `/setup` (see `${CLAUDE_PLUGIN_ROOT}/commands/setup.md` for the user-facing flows). The command owns orchestration and UX; this skill owns the contract and the canonical recipes. When the two disagree, this skill wins.

## When to Use

- Executing any `/setup` module flow (the command reads this skill at Step 0).
- Adding a new module to `/setup` — implement the contract below and add a registry row.
- Reviewing changes that touch user-scope `~/.claude/settings.json` — the merge rules here are the only sanctioned write path.

## When NOT to Use

- Telemetry consent — `/telemetry` owns `.supervisor/telemetry-consent.json`; `/setup telemetry` only delegates. See `telemetry/`.
- Per-run observability *analysis* — `/insights` reads logs; this skill only wires up emission backends.
- Anything that emits spans from the plugin itself. **The plugin emits NO spans** — Claude Code's native OTel telemetry is the only emitter; this skill configures destinations.

## Core Patterns

### Pattern 1 — The module contract

Every module implements five phases, in order, every invocation:

| Phase | Rule |
|---|---|
| **check** | Derive state from REAL commands (file tests, `jq -e`, `docker inspect`, `command -v`). Never assert state you didn't probe. |
| **report** | Print what check found. `status` subcommands stop here. |
| **offer** | `AskUserQuestion` with the applicable actions. Already-configured modules offer status/reconfigure/remove — never silently re-apply. **`AskUserQuestion` caps at 4 options** — the no-arg dashboard must NOT emit one option per module (10 modules > 4); it uses the fixed ≤4-option set in `commands/setup.md`: "Claude Code surfaces" (observability · statusline · ui, via ONE nested ≤4-option question) · "Repo knowledge stores" (memory · rules, via ONE nested ≤4-option question) · "Other integrations" (telemetry · webhook · Beads · MySQL MCP) · "Nothing". **The set is FIXED at four and is never grown when a module is added** — a new module folds into an existing bucket or into a nested question, as `memory`, `rules`, `statusline` and `ui` did. Every module stays reachable as a direct `/setup <module>` jump regardless of the dashboard set. Where an apply PUBLISHES user content (the `memory` module), the offer is consent-bearing: state exactly what becomes version-controlled BEFORE applying, and default to not applying. |
| **apply** | Make the change. Backup before any mutation of a pre-existing file. Stop at the first failed step — never continue past a failure to "finish" the flow. |
| **verify** | Re-run check (+ smoke test where defined) and show before/after. Success is claimed ONLY after verify passes. |

**Idempotency invariant:** running a module twice in a row must be safe — the second run reports "already configured" and changes nothing without an explicit user choice. Concretely: never regenerate an existing `.env` (it holds keys), never duplicate env-block keys (the merge is keyed), never `cp` over user-modified configs without saying so.

### Pattern 2 — Module registry

| Module | Depth (v1) | check probes | apply writes |
|---|---|---|---|
| `observability` | FULL init / status / remove | `~/.claude/settings.json` env block; `~/.claude/loomwright/observability/` copy; `docker inspect` health; current-repo `<project>/.claude/settings.local.json` label | asset copy + `.env` + `docker compose` + settings merge + per-project label (init-tail + remove `del`, see Pattern 7) |
| `telemetry` | delegate | `.supervisor/telemetry-consent.json` | nothing — `/telemetry` owns it |
| `notifications` | status + guidance | none (always-on hooks) | nothing |
| `webhook` | status + guidance | `LOOMWRIGHT_WEBHOOK_URL` set? | nothing (guidance only) |
| `beads` | status + guidance | `command -v bd`; `.beads/` dir | nothing (guidance only) |
| `mysql-mcp` | status + guidance | `DB_HOST`/`DB_USER`/`DB_PASS`/`DB_NAME` set? | nothing (guidance only) |
| `memory` | FULL status / apply / **remove** (remove is REQUIRED here — un-committing is a real user need) | `setup-memory.sh check`: per-path `git check-ignore` for the intended stores + the must-stay-ignored set; the findings-ledger gate (every record's `.repo` vs the allowlist, jq); `.gitignore` parse gate; managed-block presence; `git ls-files` tracked counts; resolved repo allowlist + its source | `<project>/.gitignore` sentinel-managed block (backup-first, atomic, byte-compare idempotent, ABORTS on an unparseable file) + `<project>/.supervisor/config.json .setup_memory.repo_allowlist` (jq merge, array-shaped). The block un-ignores THREE stores — the two memory stores unconditionally, and `.supervisor/postmortem/results.jsonl` only while the gate passes. NEVER `git add`/`rm`/`commit`; nothing under `~/.claude/` |
| `rules` | status / seed (no remove — a committed, human-curated store; retracting a rule is `/rules` territory via `add-rule.sh --retract`, not a module teardown) | `seed-rules.sh check`: per-seed presence across every well-formed `.agent/rules/*.json` array, keyed on the SEEDED STAMP rather than on the statement text — two branches: an EXACT `.statement` match (any provenance, so a hand-authored identical rule still counts), **OR** a rule carrying `provenance.source=setup:rules-seed` that belongs to this seed's category, matched on `.category` or on the frozen `<category>-` id prefix (statement text is not consulted at all on this branch). The second branch is the point: an EDITED seed reads as CURATED (`ALREADY SEEDED`, match `curated`), not missing. Exact-only made the skip STRICTLY NARROWER than the writer's near-identical duplicate refusal, so one edited word in a seed the docs invite you to edit put the module in a permanent failure state (ABSENT → writer REFUSES → exit 1 forever). Category is a faithful per-seed key only while the table has one row per category — asserted at startup, a duplicate category is a loud exit 2, never a silently-masked seed. **RETRACT IS NOT COVERED:** `add-rule.sh --retract` deletes the object outright, so nothing is left carrying the stamp and a later run re-offers and rewrites that seed at exit 0 — the same known limit `commands/setup.md`'s rules Idempotency note states (editing is durable curation; retracting is not). Read-only — invokes no writer, creates nothing | `<project>/.agent/rules/<category>.json` via `seed-rules.sh seed --confirm` ONLY, which authors every rule through the sole writer `add-rule.sh` (never a hand-built object, no new member, no sidecar). Seeds are PORTABLE-only, stamped `provenance.source=setup:rules-seed` (that stamp IS the seeded-vs-learned distinction), repo-wide (`applies_to: null` — a path glob would assume a layout), `check: null` (rules are DATA, never executed — NO new gate). Both non-`--confirm` paths write nothing, and EVERY writer invocation is stdin-detached so the module can never prompt |
| `statusline` | FULL status / apply / **remove** (remove is REQUIRED here — the module changes a visible, always-on surface, so backing it out and restoring the previous status line is a real user need) | `setup-statusline.sh check`: the user-scope settings document's parse gate (`jq empty`); whether `.statusLine` is absent, installed by this plugin (its `.command` names `status-line.sh`) or FOREIGN; the `.loomwrightStatusLinePrior` restore record; and whether the renderer script exists. Read-only — writes nothing | the USER-SCOPE settings document ONLY (backup-first, parse-gated, atomic, byte-compare idempotent), and within it exactly TWO keys: `statusLine` and the namespaced restore record `loomwrightStatusLinePrior`. Every other key at every level is preserved. NOTHING else under the user's config directory — no sidecar state file — and no project write, no `.gitignore` write, no `git add`/`rm`/`commit`. A FOREIGN `.statusLine` is PRESERVED and reported; replacing it needs the explicit `--replace` flag, and the replaced value is recorded so `remove` restores it verbatim |
| `ui` | FULL check / apply / **serve** / **stop** / **remove**, plus the registry verbs **add** / **list** / **forget** / **scan**. **TWO ENTRY POINTS, ONE ENGINE, and the split is deliberate:** this module (`/setup ui`) owns the CONFIGURATION verbs `apply` and `remove` — the two that materialise and delete a directory of files outside the repo — while the direct `/ui` command owns the operational and registry half (`check` / `serve` / `stop` / `add` / `list` / `forget` / `scan`). Starting the view and choosing which projects it may show are daily operations, and routing them through a configuration dashboard is friction that sends people back to the shell. Every verb the engine has is documented exactly once as one of the two files' responsibility, and `test-setup-ui.sh` group `(m)` asserts that UNION against the engine's own dispatch table. (remove is REQUIRED here — apply materialises a directory of files outside the repo, so taking it back is a real user need; `serve`/`stop` are extra because this is the only module that runs a long-lived local process) | `setup-ui.sh check`: the ui dir and whether it carries the `.loomwright-ui-module` ownership marker; per-file bundle drift (byte hash of each installed file vs the plugin's `floor-ui/` copy); the availability of `python3`, `jq` and `build-floor.sh`; and a `UI readiness:` verdict (`configured` / `not configured` / `stale (run apply)` / `WITHHELD (…)`). Read-only — writes nothing | TWO places and no others: (a) the UI DIRECTORY, default `~/.claude/loomwright/ui` and overridable with `--ui-dir` (which is how every self-test runs inside a `mktemp -d`) — into it go exactly the three bundle files copied from the plugin's `floor-ui/`, the marker, an optional `serve.pid` and a COPY of `floor.json`; and (b) `<project>/.supervisor/floor/floor.json`, and ONLY by running `build-floor.sh` — never by writing that path itself, and `serve --no-regen` makes even that write impossible. **The marker is the ownership proof and `remove` needs it:** a directory carrying no marker is REPORTED and PRESERVED, because `--ui-dir` is user-supplied and a typo pointing at a real directory must not cost the user that directory; `remove` additionally refuses `/`, `$HOME`, and anything at or under the plugin install directory. NO user-scope settings write (that is `statusline`'s one domain), no `.gitignore` write, no `git add`/`rm`/`commit`. `serve` always passes `--bind 127.0.0.1` — there is no flag to change it and no code path that omits it |

New modules append a row here AND a flow section in `commands/setup.md` in the same change.

### Pattern 8 — `.gitignore` managed block (the `memory` module's write class)

> Placed here, out of numeric order, on purpose: it reads as the write-class footnote to the `memory` row in Pattern 2 directly above. Numbers are stable identifiers for cross-references (Patterns 3–7 are cited from `commands/setup.md` and from the checklist below) — they are not a reading order, so a new pattern appends its number and sits where it belongs.

The `memory` module is the only one that rewrites a **committed, user-authored** file, so it carries its own rules — the settings-merge rules in Pattern 3 do not transfer (there is no JSON to parse-gate, and the file is tracked):

- **Negate CONTENTS, never the directory.** `.claude/` + `!.claude/agent-memory/` silently does NOTHING — git cannot re-include a file whose parent directory is excluded. The working form is `.claude/*` + `!.claude/agent-memory/`. Any pre-existing **directory-shaped** `.claude/` / `.supervisor/` exclude must be **neutralised** (commented out, restorable verbatim), not merely out-ordered — one survivor kills the whole block. That includes the recursive family (`.claude/**`, `**/.claude/`, `**/.claude/**`, and the leading-slash forms), because git applies the LAST matching rule and `.claude/**` still beats a later directory-only `!.claude/agent-memory/`. `X/*` is deliberately NOT neutralised — that is the working form itself. Both the failing and the working form are fixture-asserted in `test-setup-memory.sh`; a comment is not a test.
- **Sentinel-delimited, timestamp-free block.** The block content is a **pure function of (the pre-existing `.gitignore` contents, the ledger-gate outcome)**, and it must be byte-stable across runs **for a fixed gate outcome** — which is exactly what the byte-compare idempotency contract requires. Equal ⇒ report "already configured" and write nothing. The gate outcome IS an input, so a repo that applied cleanly and later gains a foreign ledger record will legitimately rewrite `.gitignore` to WITHDRAW the ledger negation; that transition must be ANNOUNCED with the offending slugs, never emitted under a bare `apply: applied`, and the message must state that withdrawal does **not** un-track an already-committed file. Emitting the conditional lines unconditionally (and gating only the verdict) is the tempting simplification and is WRONG — it un-ignores an unfiltered cross-repo ledger, which is the exact failure the gate exists to prevent.
- **A CONDITIONAL store needs its own VERDICT class, not a shared one.** When a store is deliberately withheld, it must NOT be counted as a blocked intended path: that yields the under-inclusion verdict, whose remedy ("comment out the surviving exclude") points at the module's OWN exclude and would publish exactly what was withheld — and the command layer relays that copy verbatim. Under-inclusion, over-inclusion and deliberate-withholding are three distinct modes with three opposite remedies and **must not share copy**. The `memory` module's third class is `gated`; its warning names the offending repo slugs and the filter/extend remedy, and the command layer's verdict enumerations, success criterion and headline list all admit it.
- **A committed-data gate must read its expectation from COMMITTED source.** The repo allowlist lives in a gitignored config, so it does not travel: a fresh clone resolves it to the live remote alone, and a legitimately pre-rename record then reads as foreign. Declare the expected values in committed code and demote the machine-local resolution to an advisory cross-check — otherwise the gate asserts a property of whoever runs it, and passes locally while failing in CI.
- **Fail CLOSED in the WRITE dimension, never in the exit status.** For a fail-safe helper, "fails closed" means REFUSE-TO-WRITE plus a machine-readable named-reason status line plus `exit 0`. A non-zero exit would regress every non-blocking caller. Degenerate inputs are decided explicitly, not left to chance: an ABSENT input passes (nothing to withhold — this is every fresh repo), and an ABSENT dependency (`jq`) leaves the gate UNEVALUATED with the conditional lines NOT emitted — it must fail neither toward the refusal class (which would permanently mis-report for every user without the dependency) nor toward emitting (which would publish something unchecked). And an UNREADABLE input REFUSES — "could not examine" is never "examined and clean", which is the distinction a per-line fallback silently loses when it reads "produced no output" as "found nothing wrong".
- **EMITTING and WITHDRAWING are ASYMMETRIC — one gate outcome must not govern both.** Emitting a NEW conditional negation requires an affirmative *examined-and-clean* verdict; WITHDRAWING one that is ALREADY in the block requires an affirmative *examined-and-contaminated* verdict backed by REAL, OBSERVED offenders. A "could not examine" outcome (dependency absent **or broken**, input unreadable, every record unparseable) must PRESERVE what is already there and say so. Reason: a withdrawal is an **unrequested state change justified by a diagnosis that was never made** — preserving publishes nothing new (the file is already un-ignored and possibly already committed, and `.gitignore` does not untrack tracked files), whereas withdrawing silently re-ignores what the user deliberately un-ignored **and** prints a contamination message naming offenders that do not exist. Keep the two channels separate in code (observed offenders vs. could-not-examine reasons) so they cannot share copy — they take **opposite** remedies: `filter-ledger > tmp && mv tmp ledger` is right for a real foreign record and **destructive** for an unreadable one (it prints nothing and truncates the file to zero bytes); the could-not-examine remedy is "make it examinable".
- **Probe that a dependency WORKS, not that it EXISTS.** `command -v jq` tests PRESENCE, not FUNCTION. A `jq` on `PATH` that exits non-zero (wrong arch, broken install, a shim) makes every probe "fail", so a perfectly CLEAN input reads as entirely unparseable and the gate refuses while reporting contamination it never observed. Probe functionally (`printf '{}' | jq -e . >/dev/null 2>&1`) and treat broken exactly like absent.
- **Assert ledger/JSONL content with `jq`, never `grep`.** A JSONL store mixes compact (`"k":"v"`) and spaced (`"k": "v"`) records, so a compact-form grep silently under-counts AND a hostile record written in the spaced form evades it entirely — a grep-based gate is a guard that cannot fire. Pin the spaced form as a NAMED fixture case and prove the evasion (grep=0, jq=1) inside the fixture, so the assertion can never decay into a jq-vs-jq tautology.
- **ONE sentinel matcher for the gate AND the stripper.** The presence gate and the block stripper must agree on what counts as a sentinel line (both substring, or both column-1-anchored). When they disagreed, an INDENTED `BEGIN` passed the gate as one valid block but was not stripped, so apply appended a second one — and every later apply *and* remove then aborted on "duplicated managed-block sentinels", a corrupt state the tool created itself and refused to repair.
- **Abort, never half-write, never blind-repair.** Absent / non-regular / symlinked / NUL-containing / conflict-marked / sentinel-unbalanced `.gitignore` ⇒ report the reason, write nothing, and do NOT create a backup (nothing was staged). A hand-edited file is the user's; refuse it rather than rewriting underneath them.
- **Backup-first + atomic**: timestamped `.gitignore.backup.<ts>` sibling, then tmp-file + `mv`. The name must be **collision-proof** — a second-granular timestamp alone means two writes in the same second resolve to one path and the second `cp` destroys the user's pristine original, which is the only thing the backup exists to protect. Assert the backup **positively** (it exists, and its content equals the pre-write file); a count comparison across an idempotent no-op passes as `0 = 0` while no backup is written at all.
- **Never report unqualified success on an unverified negation.** After the write, re-probe and qualify the headline: if readiness is not `configured`, name the intended paths still ignored and the rule that actually wins for each, taken from a real `git check-ignore -v` probe. A deeper exclude the rewriter does not recognise otherwise leaves a silently dead block under `apply: applied`.
- **Consent before publishing.** Applying makes user content version-controlled and it travels wherever the repo travels. State exactly what becomes committed BEFORE applying, and make `remove` state plainly that git history retains anything already pushed — removal stops future tracking, it does not unpublish.
- **Un-ignoring is not committing, and un-ignoring is not un-tracking.** The helper never runs `git add` / `git rm` / `git commit`; already-tracked files stay tracked until the user runs `git rm --cached` themselves.
- **Repo allowlist is a LIST, never a string, and never the live remote at read time.** A repo RENAME is the reason: pre-rename records carry the old slug, so a live-remote-keyed filter silently drops the older half of a ledger. Default to the current remote on fresh install (never a hardcoded owner), store as a JSON array, and treat an empty allowlist as retaining NOTHING (fail-closed) — which also means an empty allowlist REFUSES the ledger gate.
- **State the residual risk; do not present the gate as complete coverage.** The ledger gate is evaluated at APPLY TIME ONLY, so a store that gains foreign content after a clean apply stays un-ignored until the next apply and a routine `git add -A` can commit it in between. It also keys on a structured field (`.repo`) ONLY and does not read free text. Both limits belong in the consent disclosure and in the command-layer docs, as decisions — not omissions.

### Pattern 3 — Settings merge (jq deep-merge into `~/.claude/settings.json`)

The ONLY sanctioned way to write user-scope settings. Rules: (a) timestamped backup BEFORE any write; (b) abort — never half-write — if the existing file fails to parse; (c) merge only under the `env` key, preserving every unrelated key at both levels; (d) atomic replace via tmp-file + `mv`.

```bash
SETTINGS="$HOME/.claude/settings.json"
# $ENV_JSON = a JSON object of the keys to merge, built with jq -n (never string-interpolated):
ENV_JSON=$(jq -n --arg endpoint "$ENDPOINT" --arg headers "$HEADERS" --arg ver "$PLUGIN_VERSION" '{
  CLAUDE_CODE_ENABLE_TELEMETRY: "1",
  OTEL_METRICS_EXPORTER: "otlp",
  OTEL_LOGS_EXPORTER: "otlp",
  OTEL_TRACES_EXPORTER: "otlp",
  OTEL_EXPORTER_OTLP_PROTOCOL: "http/protobuf",
  OTEL_EXPORTER_OTLP_ENDPOINT: $endpoint,
  OTEL_EXPORTER_OTLP_HEADERS: $headers,
  OTEL_RESOURCE_ATTRIBUTES: ("service.version=" + $ver)
}')

if [ -f "$SETTINGS" ]; then
  jq empty "$SETTINGS" 2>/dev/null \
    || { echo "ABORT: $SETTINGS exists but is not valid JSON — fix it by hand; nothing was written."; exit 1; }
  cp "$SETTINGS" "$SETTINGS.backup.$(date +%Y%m%d-%H%M%S)"
  jq --argjson new "$ENV_JSON" '.env = ((.env // {}) + $new)' "$SETTINGS" > "$SETTINGS.tmp" \
    && mv "$SETTINGS.tmp" "$SETTINGS"
else
  mkdir -p "$HOME/.claude"
  jq -n --argjson new "$ENV_JSON" '{env: $new}' > "$SETTINGS"
fi
```

Removal is the mirror image: same parse-check + backup, then `del(.env.KEY1, .env.KEY2, …)` of EXACTLY the keys this skill added — never `del(.env)` wholesale (the user may keep unrelated env there).

**The `statusline` module writes the same document under the same rules, with two additions that do not generalise to the `env` merge — stated here so the difference is a decision rather than an inconsistency:**

- **A key the user may ALREADY OWN needs consent, not a merge.** The `env` merge adds keys nobody else writes; `statusLine` is a single key a user may have configured themselves, so deep-merging it is DESTRUCTION wearing the costume of a merge. The rule: when the existing value was not written by this plugin, PRESERVE it, REPORT it, and require an explicit flag to replace — and record the replaced value so `remove` gives it back. An AC that protects only the keys *unrelated* to the one you are writing protects nothing about the one you are writing.
- **A restore record belongs INSIDE the document it restores.** `remove` must put back what was there before, which needs the prior value persisted somewhere. It goes in the same document under a namespaced top-level key (`loomwrightStatusLinePrior`), NOT in a sidecar file — that keeps the module's write domain one path, and a sidecar would drift from the document it describes.
- **Capture the prior value in the SHELL, never inside the jq pipeline.** `.statusLine = $sl | .[$k] = (.statusLine // null)` reads correct and is WRONG: jq evaluates a pipeline left to right, so the first assignment has already overwritten `.statusLine` by the time the second one reads it, and the "record" ends up being the value you just wrote. The user's status line is then unrecoverable and `remove` hands back a copy of what it was supposed to undo. Read the prior value first and pass it in with `--argjson`. This was a real defect caught by its own self-test, not a hypothetical.
- **Idempotency must not eat the record.** A second apply finds its own value in `.statusLine`; if it recaptures that as "the prior one", the original is lost on the second run rather than the first. When the current value is already ours, carry the existing record through untouched.

**Why these 8 keys:** this is the settled env-block contract — `CLAUDE_CODE_ENABLE_TELEMETRY=1`, the three `OTEL_*_EXPORTER=otlp` keys, `OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf`, endpoint, headers, and `OTEL_RESOURCE_ATTRIBUTES=service.version=<plugin version>`. Console mode is the one sanctioned variant (exporters=`console`, OTLP keys omitted/removed).

### Pattern 4 — `.env` generation (observability local backend)

Generated once into `~/.claude/loomwright/observability/.env`; NEVER regenerated if the file exists. Every variable below is consumed by the copied `docker-compose.yml` (`${CLAUDE_PLUGIN_ROOT}/scripts/otel/docker-compose.yml`) — except `COMPOSE_PROJECT_NAME`, which is consumed by the compose CLI itself (see the project-name convention below):

```bash
PK="pk-lf-$(openssl rand -hex 16)"
SK="sk-lf-$(openssl rand -hex 16)"
ADMIN_PW="$(openssl rand -hex 12)"
cat > "$OBS_DIR/.env" <<EOF
# Generated by /setup observability — local-only secrets, never commit.
# Project-name convention (belt-and-braces): every recipe/printed command
# carries -p loomwright-observability explicitly (correct on any
# compose version, from any cwd), AND this key makes a bare
# `docker compose -f <this dir>/docker-compose.yml ...` join the SAME
# project — compose v2 loads .env from the first -f file's directory, so
# without it the project name would derive from the dir basename
# ("observability") and create a second parallel stack with empty volumes.
COMPOSE_PROJECT_NAME=loomwright-observability
POSTGRES_USER=langfuse
POSTGRES_PASSWORD=$(openssl rand -hex 16)
POSTGRES_DB=langfuse
CLICKHOUSE_USER=clickhouse
CLICKHOUSE_PASSWORD=$(openssl rand -hex 16)
REDIS_AUTH=$(openssl rand -hex 16)
MINIO_ROOT_USER=minio
MINIO_ROOT_PASSWORD=$(openssl rand -hex 16)
LANGFUSE_S3_BUCKET=langfuse
LANGFUSE_SALT=$(openssl rand -hex 16)
LANGFUSE_ENCRYPTION_KEY=$(openssl rand -hex 32)
NEXTAUTH_SECRET=$(openssl rand -hex 32)
NEXTAUTH_URL=http://localhost:3000
LANGFUSE_PORT=3000
LANGFUSE_INIT_ORG_ID=loomwright
LANGFUSE_INIT_ORG_NAME=Loomwright
LANGFUSE_INIT_PROJECT_ID=claude-code
LANGFUSE_INIT_PROJECT_NAME=Claude Code
LANGFUSE_INIT_PROJECT_PUBLIC_KEY=$PK
LANGFUSE_INIT_PROJECT_SECRET_KEY=$SK
LANGFUSE_INIT_USER_EMAIL=admin@local.test
LANGFUSE_INIT_USER_NAME=Admin
LANGFUSE_INIT_USER_PASSWORD=$ADMIN_PW
LANGFUSE_BASIC_AUTH=$(printf '%s:%s' "$PK" "$SK" | base64 | tr -d '\n')
OTEL_COLLECTOR_PORT=4318
EOF
chmod 600 "$OBS_DIR/.env"
```

Key facts: `LANGFUSE_ENCRYPTION_KEY` must be 64 hex chars (`-hex 32`); `LANGFUSE_BASIC_AUTH` is `base64("<public_key>:<secret_key>")` consumed by the collector's `Authorization: Basic` header toward Langfuse; the `LANGFUSE_INIT_*` block headlessly provisions org/project/user/keypair on first boot so init never clicks through the UI.

**Project-name convention (settled — do not vary):** the compose project is ALWAYS `loomwright-observability`, pinned two ways: (a) every compose command in the recipes AND every user-facing printed command (restart hints, the chown pre-seed, teardown) carries `-p loomwright-observability` explicitly; (b) `COMPOSE_PROJECT_NAME=loomwright-observability` is written into the generated `.env` so a hand-typed bare `docker compose -f "$OBS_DIR/docker-compose.yml" …` still resolves to the same project (compose v2 loads `.env` from the first `-f` file's directory; verified empirically). Named volumes are therefore always `loomwright-observability_*`. A command that omits BOTH would derive project `observability` from the directory basename and spin up a second parallel stack on fresh empty volumes — never print such a command.

### Pattern 5 — Wait-healthy loop

```bash
P="loomwright-observability"
for i in $(seq 1 60); do  # 60 × 10s = 10 min ceiling (first boot pulls images + runs ClickHouse migrations)
  total=$(docker compose -p "$P" -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" ps -q | wc -l | tr -d ' ')
  healthy=$(docker compose -p "$P" -f "$OBS_DIR/docker-compose.yml" --env-file "$OBS_DIR/.env" ps -q \
            | xargs docker inspect -f '{{.State.Health.Status}}' 2>/dev/null | grep -c '^healthy$')
  [ "$total" -gt 0 ] && [ "$healthy" -eq "$total" ] && break
  sleep 10
done
# Final assertion requires a NON-ZERO total: zero containers (stack never
# started / wrong project name) must abort, never false-pass as 0 == 0.
[ "${total:-0}" -gt 0 ] && [ "$healthy" -eq "$total" ] || { echo "TIMEOUT: ${healthy:-0}/${total:-0} healthy"; exit 1; }
```

`docker inspect` is used (not `compose ps` text parsing) because output is stable across compose versions, and the collector's health port (13133) is intentionally not published to the host.

### Pattern 6 — Smoke-test recipe (emit span → poll Langfuse)

Success is claimed ONLY after a real span round-trips. Emit via OTLP/HTTP JSON to the collector, then poll the Langfuse public API with the generated keypair:

```bash
# Source the keypair + ports from the stack's generated .env FIRST — on the
# reuse/reconfigure path the keys were generated in a prior session, so
# in-memory $PK/$SK from the generation recipe may be absent/stale (a 401
# on the poll otherwise).
PK=$(sed -n 's/^LANGFUSE_INIT_PROJECT_PUBLIC_KEY=//p' "$OBS_DIR/.env")
SK=$(sed -n 's/^LANGFUSE_INIT_PROJECT_SECRET_KEY=//p' "$OBS_DIR/.env")
LANGFUSE_PORT=$(sed -n 's/^LANGFUSE_PORT=//p' "$OBS_DIR/.env")
OTEL_COLLECTOR_PORT=$(sed -n 's/^OTEL_COLLECTOR_PORT=//p' "$OBS_DIR/.env")

TRACE_ID=$(openssl rand -hex 16); SPAN_ID=$(openssl rand -hex 8)
NOW_NS=$(($(date +%s) * 1000000000))
curl -sf -X POST "http://localhost:${OTEL_COLLECTOR_PORT:-4318}/v1/traces" \
  -H 'Content-Type: application/json' -d '{
  "resourceSpans": [{
    "resource": {"attributes": [{"key": "service.name", "value": {"stringValue": "loomwright-smoke-test"}}]},
    "scopeSpans": [{
      "scope": {"name": "setup-smoke-test"},
      "spans": [{"traceId": "'"$TRACE_ID"'", "spanId": "'"$SPAN_ID"'", "name": "setup-smoke-test",
                 "kind": 1, "startTimeUnixNano": "'"$NOW_NS"'", "endTimeUnixNano": "'"$((NOW_NS + 1000000))"'"}]
    }]
  }]
}'
# Poll: ingestion is async (collector batch 5s → Langfuse worker → ClickHouse). Up to ~3 min.
for i in $(seq 1 36); do
  curl -sf -u "$PK:$SK" "http://localhost:${LANGFUSE_PORT:-3000}/api/public/traces?name=setup-smoke-test&limit=1" \
    | jq -e '.data | length > 0' >/dev/null && { echo "SMOKE OK ($TRACE_ID)"; break; }
  sleep 5
done
```

For an external/existing endpoint, only the emit half runs (verify 2xx) — arbitrary backends can't be polled. **Traces only:** Langfuse's `/api/public/otel` ingests traces, not metrics/logs; the local collector terminates those in a debug exporter by design. Document this, never work around it.

### Pattern 7 — Per-project auto-label (`set-otel-resource-attrs.sh`)

Per-project OTel labeling is auto-maintained by `${CLAUDE_PLUGIN_ROOT}/scripts/set-otel-resource-attrs.sh`, fired two ways:

- **SessionStart hook** (`hooks.json`) — runs on every session start, including `startup` (unlike `session-resume.sh`, which skips `startup`), so it gets its own sibling `SessionStart` entry.
- **`/setup observability` init-tail** — invoked once at the END of a successful init (any telemetry-enabling backend: local / external / console) so the CURRENT repo is labeled immediately instead of waiting for the next session.

Contract (do not vary):

- **Telemetry gate:** runs only when `CLAUDE_CODE_ENABLE_TELEMETRY == "1"` (from `~/.claude/settings.json` OR env) — gated on the enable flag ONLY, NOT on the endpoint/exporter. Silent no-op when telemetry is off or `jq` is missing.
- **Fail-safe:** ALWAYS exits 0 (it is a SessionStart hook helper — must never block a session or fail loud).
- **Target:** `<project>/.claude/settings.local.json`, key `.env.OTEL_RESOURCE_ATTRIBUTES`.
- **Value-level merge:** writes `service.name=<repo-basename>,service.version=<plugin version>`, preserving any OTHER attributes already in the value (it restates only service.name/service.version).
- **Version source:** `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` (or a BASH_SOURCE-relative fallback).

The `remove` subflow best-effort strips the CURRENT repo's label (`jq 'del(.env.OTEL_RESOURCE_ATTRIBUTES)'`, same backup-first/parse-gate/atomic discipline); other repos' auto-written labels are left in place but are INERT while telemetry is off.

## Anti-Patterns

- **String-interpolating user input into the settings JSON.** Always build `$ENV_JSON` with `jq -n --arg` — injection-safe by construction.
- **Overwriting `~/.claude/settings.json` wholesale** (or writing it with a non-jq tool). Unrelated keys (model, hooks, permissions) must survive every merge.
- **Proceeding after a parse failure** ("I'll just recreate the file"). The file may hold config you can't reconstruct — abort with the path and let the human fix it.
- **Regenerating `.env` on re-init.** The keypair in it authenticates the collector to Langfuse and the smoke-test poll; regenerating orphans the provisioned project.
- **Claiming success without the smoke test.** "Containers are up" is not "traces land".
- **Repo-relative plugin paths at runtime.** Only `${CLAUDE_PLUGIN_ROOT}/scripts/otel/...` resolves for installed users.
- **Running compose against the plugin install dir.** Always copy to `~/.claude/loomwright/observability/` first — the install dir is replaced on plugin update and must never accumulate state (`.env`, volumes).

## Example Implementation

`/setup observability` on a clean machine: check finds no env block and no copy → report "not configured" → offer backends → user picks local → Docker check (warn about start-at-login) → copy assets → generate `.env` (Pattern 4) → `compose up -d` → wait-healthy (Pattern 5) → settings merge (Pattern 3) → smoke test (Pattern 6) → report dashboard URL + login + "restart Claude Code sessions" + optional per-repo `service.name` snippet. A second `/setup observability` run finds everything healthy and offers status/reconfigure/remove instead of re-applying.

## Testing Approach

- Merge recipe: run against a fixture settings.json with unrelated keys (`model`, `hooks`) + a pre-existing `env` → assert all preserved, 8 keys added, backup file exists; run against malformed JSON → assert abort + no write + no backup-restore needed.
- Idempotency: run apply twice → assert second run is a no-op offer, `.env` mtime unchanged.
- Smoke test: assert failure path stops the flow (kill `langfuse-worker`, expect poll timeout → no success claim).
- Removal: assert exactly the 8 keys are deleted and everything else survives.
- Healthcheck fragility (functional, not static): the `minio` probe (`mc ready local`) is the most image-version-fragile of the compose healthchecks — it depends on the `local` alias the upstream entrypoint sets up, which the entrypoint override could skip. It is NOT covered by the static self-test; on any minio image bump, functionally verify the container reaches `healthy` before trusting wait-healthy.

## Related Skills

- `telemetry/` — the OTHER telemetry (GitHub-issues run summaries); `/setup telemetry` delegates there. Disjoint write paths: this skill never touches `.supervisor/telemetry-consent.json`.
- `docker/` — container patterns behind the compose stack (healthchecks, pinned images).
- `error-handling/` — the fail-closed abort pattern used by the merge recipe.
- `quality-checklist/` — gates for reviewing changes to this skill or the command.

## Quality Gates

- [ ] Sanctioned write domain (setup's OWN logic): `~/.claude/loomwright/observability/*`, user-scope `~/.claude/settings.json`, and project-scope `<project>/.claude/settings.local.json` (the per-project label — written via the init-tail `set-otel-resource-attrs.sh` invocation and stripped by the `remove` `del`). setup's OWN settings(.local).json writes (the user-scope merge and the `remove` `del`) are backup-first + `jq empty` parse gate + tmp+`mv` atomic replace; the delegated init-tail `set-otel-resource-attrs.sh` write is parse-gate + atomic + idempotent-skip but NOT backup-first (single-key idempotent merge — nothing destructive to roll back).
- [ ] Sanctioned write domain (`statusline` module): the helper (`setup-statusline.sh`) writes the USER-SCOPE settings document ONLY (+ one timestamped backup), and within it exactly the `statusLine` and `loomwrightStatusLinePrior` keys — see Pattern 3's statusline addendum. Backup-first + `jq empty` parse gate + tmp+`mv` atomic + byte-compare idempotent; an unparseable document ABORTS with no write AND no backup. NO sidecar state file, no other path under the user's config directory, no project write, no `.gitignore` write, no history-touching git command. `check` writes nothing at all. A FOREIGN `statusLine` is preserved and reported — replacing it requires the explicit `--replace` flag, and `remove` restores the recorded prior value verbatim and refuses to touch a status line this plugin did not write.
- [ ] Sanctioned write domain (`ui` module): the helper (`setup-ui.sh`) writes the UI DIRECTORY ONLY (default `~/.claude/loomwright/ui`, overridable with `--ui-dir`) — the three bundle files, the `.loomwright-ui-module` marker, an optional `serve.pid` and a copy of `floor.json` — plus `<project>/.supervisor/floor/floor.json` and ONLY by running `build-floor.sh`. `check` writes nothing. `apply` is byte-compare idempotent (`no-op — already configured`); `apply` and `remove` both WITHHOLD on a directory carrying no marker, and `remove` additionally refuses `/`, `$HOME` and the plugin install dir. NO user-scope settings write, no `.gitignore` write, no history-touching git command. `serve` binds 127.0.0.1 only.
- [ ] Sanctioned write domain (`rules` module): the helper (`seed-rules.sh`) writes `<project>/.agent/rules/*.json` ONLY, and ONLY on `seed --confirm`, and ONLY through `add-rule.sh` — no hand-built rule object, no sidecar, no new member on the frozen schema, no `--check` (rules stay DATA), no `--applies-to` (a portable rule cannot assume a layout). `check` and a bare `seed` write nothing at all. NO `~/.claude/` write, no `.gitignore` write, no history-touching git command. The module adds NO gate.
- [ ] Sanctioned write domain (`memory` module): the helper (`setup-memory.sh`) writes `<project>/.gitignore` (+ one timestamped backup) and `<project>/.supervisor/config.json .setup_memory.repo_allowlist` ONLY — see Pattern 8. NO `~/.claude/` write of any kind, and NO history-touching git command (`git add`/`rm`/`commit`) on any path. `check` / `allowlist` / `filter-ledger` write nothing at all.
- [ ] Env block is exactly the 8 settled keys (or the documented console variant) — no extras, no renames.
- [ ] `.env` variable names match what `${CLAUDE_PLUGIN_ROOT}/scripts/otel/docker-compose.yml` consumes (sole exception: `COMPOSE_PROJECT_NAME`, consumed by the compose CLI) — verify against the compose file on any change to either.
- [ ] Every compose command (recipe or printed) carries `-p loomwright-observability` — the project-name convention in Pattern 4.
- [ ] No repo-relative plugin path (the dev-checkout-only form) in any runtime instruction — `${CLAUDE_PLUGIN_ROOT}/...` only.
- [ ] Smoke test gates the success claim (local backend) — never report success on `compose up` alone.
- [ ] Idempotency invariant holds for every module (re-run = report + offer, not re-apply).
- [ ] No secret values printed except the local-only Langfuse dashboard login.

## Token Cost

- Invocation: ~1,600 tokens (skill body)
- Storage: inline (markdown only)
- Context7: not required
