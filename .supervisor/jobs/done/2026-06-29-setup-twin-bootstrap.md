# Supervisor Job: Add the `/setup twin` cold-start bootstrap module (north-star slice #3a)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean working tree, branch: main @ v14.49.0 (handoff digest merged as PR #82; direction spikes tracked). Supervisor branches a fresh feature branch off `origin/main`.
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0

## Feasibility (Launch Pad)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Bash + jq module helper + a markdown command flow — identical idiom to the existing `/setup observability` module. |
| 2 | Dependency Availability | GO | No new deps. Reuses plugin-owned `build-bridge.sh` + the `claude-md-validation` skill. graphify is an EXTERNAL user-global CLI (`~/.claude/skills/graphify`, not a plugin command) → module must DETECT/GUIDE, never hard-depend. Corpus ids `doc-currency-green` + `version-consistent` confirmed. |
| 3 | Architecture Fit | GO | A 7th `/setup` module following the established 5-phase contract (check/report/offer/apply/verify, authority `skills/setup/SKILL.md`). Advisory / fail-safe / idempotent per the umbrella's invariants. No new top-level command (so command count stays 20). |
| 4 | Scope vs Supervisor Capability | GO | 4 subtasks: module helper + test + umbrella wiring + version/doc. Bounded; the `/rules` authoring + `.agent/rules/` enforcement + SessionStart nudge are explicitly DEFERRED to slice #3b. |
| 5 | Hard Blockers | GO | None. Adds NO hook (nudge deferred), so the hook count is untouched. |

**Overall Verdict:** GO

## Task
**Goal:** Add a `twin` module to the `/setup` umbrella that gives a one-place **Twin-readiness status** for the current repo and a **guided cold-start bootstrap** — detect/refresh the graphify graph (guide if the CLI is absent, run if present), rebuild the plugin-owned bridge, and validate (or offer to scaffold) CLAUDE.md — so a fresh repo's Twin actually populates instead of silently staying empty.

**Problem Statement:**
A developer on a fresh clone (or a new repo) needs a discoverable way to populate this plugin's "Twin" (the graph + bridge + CLAUDE.md patterns that `brain-context` reads), because today `brain-context` is **read-path-only and opportunistic** (`skills/brain-context/SKILL.md`) — it detects an existing `graphify-out/graph.json` + brain root, else silently falls back to grep forever.
Currently there is **no bootstrap path**: the graph only exists if the user already knew to run the external `graphify` CLI, and there is no consolidated view of whether the Twin is ready. This causes the loop's advisory context to add nothing on any repo nobody manually bootstrapped.
Success looks like: `/setup twin` reports Twin readiness (graph present/fresh · bridge built · CLAUDE.md present/fresh) and, on `/setup twin` (no sub-arg) or via the dashboard, guides the user through bootstrapping — closing the "fresh repo's Twin never populates" frontier from the north-star doc.

This is north-star **slice #3a** (the foundational half of Bet 6 / the cold-start frontier). See `ai-agent-manager-plugin/docs/SPIKES/NORTH_STAR_DIRECTION.md` §"Open frontier → Cold-start / bootstrapping". Follows Bet 3 (PR #81) and Bet 2 (PR #82). **Per-repo, committed-knowledge bootstrap** — distinct from the per-user/machine modules (observability/telemetry/notifications).

## Acceptance Criteria
- [ ] Given `/setup twin status` (or the no-arg dashboard row), when run, then it reports a derived Twin-readiness cell from REAL probes: graph (`graphify-out/graph.json` present? + stale via the SAME prefix-tolerant comparison `read-bridge.sh:135-149` uses — `built_at_commit` may be an ABBREVIATED SHA, so treat FRESH when `built_at_commit` is a prefix of the full `git rev-parse HEAD`, OR HEAD's 12-char prefix is a prefix of `built_at_commit`; otherwise stale ⇒ hint. NEVER an exact `!=` against the full HEAD), bridge (`.supervisor/bridge/bridge.json` present?), CLAUDE.md (present? + fresh per `claude-md-validation`), and the optional `AI_AGENT_MANAGER_BRAIN_ROOT` wiki — never asserting a state it did not probe.
- [ ] Given `/setup twin` (no sub-arg) on a repo with no graph, then the `commands/setup.md` layer **offers** (via `AskUserQuestion`) to bootstrap; the helper only REPORTS whether `graphify` is available. On confirm, if `graphify` is present the command layer runs `graphify .` (or drives the helper to); otherwise it prints the exact install/run guidance (NEVER hard-fails on the absent external CLI). The shell helper never prompts.
- [ ] Given bootstrap runs, then after any graph-producing step completes IN THE SAME INVOCATION (including a just-accepted `graphify .`), the module RE-PROBES `graphify-out/graph.json` and runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-bridge.sh" --root "$repo" --out "$repo/.supervisor/bridge"` (the explicit `--out` is MANDATORY — see the scoped-write invariant; never the bare call, which a repo-local `.build_bridge.out` config could redirect) before the verify step — so a first run that builds the graph ALSO builds the bridge in that same run, never deferring the bridge to a second invocation. Because `build-bridge.sh` is fail-safe (exits 0 / no-ops when no graph exists), the bootstrap path MAY call it (with that same explicit `--out`) unconditionally at the end; then it re-reports readiness.
- [ ] Given CLAUDE.md is present, when bootstrap runs, then it validates freshness/patterns via the `claude-md-validation` skill (advisory, non-blocking); given CLAUDE.md is ABSENT, then it OFFERS to scaffold a minimal starter CLAUDE.md (tech stack / structure / key patterns skeleton) — **human-confirmed, never auto-written, never overwrites an existing file**.
- [ ] Given the module follows the umbrella contract, when implemented, then it obeys the 5-phase check/report/offer/apply/verify shape, is **idempotent** (a second run reports "already bootstrapped" and changes nothing without an explicit choice), and the `offer` step caps at 4 `AskUserQuestion` options.
- [ ] **Invariant (advisory / fail-safe / scoped writes):** the helper `scripts/setup-twin.sh` itself writes ONLY `.supervisor/bridge/` — and to GUARANTEE that containment it MUST invoke the bridge builder with an explicit out dir: `build-bridge.sh --root "$repo" --out "$repo/.supervisor/bridge"`. (Rationale: `build-bridge.sh:79-82` honors a `.supervisor/config.json` `.build_bridge.out` override ONLY when `--out` is empty; passing `--out` explicitly short-circuits that branch — `build-bridge.sh:54` — so a repo-local config can NOT redirect the helper's write outside `.supervisor/bridge/`.) The external `graphify` CLI (only when the user opts to run it) writes `graphify-out/`. The helper NEVER writes `CLAUDE.md` — when CLAUDE.md is absent it PRINTS a proposed starter skeleton to **stdout only**, and the `commands/setup.md` layer performs the actual `CLAUDE.md` write afterward, ONLY on explicit user confirm and ONLY if the file is still absent (never overwrite). Neither layer touches any `~/.claude/settings.json` key. It NEVER blocks a session, NEVER changes a heal/review/GO decision, and the helper's check path ALWAYS exits 0 (mirrors `build-insights.sh`/`read-bridge.sh`). The SessionStart "no-twin" nudge is OUT OF SCOPE (slice #3b).
- [ ] Given the new module, when registered, then `skills/setup/SKILL.md`'s module registry gains a `twin` row, `commands/setup.md` gains a `twin` flow section + usage line + dashboard row + arg parsing, and the module enumerations stay consistent across both files (the `/setup` description's 6-module list → 7).
- [ ] Given the `twin` module's subcommand surface, when defined, then it mirrors the observability `init|status|remove` second-positional-arg convention (`commands/setup.md:24`) as: `status` = read-only readiness report (no writes); no-subarg = check decides (unbootstrapped → offer bootstrap; bootstrapped → offer status / re-bootstrap); and `remove` is **explicitly N/A for v1** (Twin artifacts — graph/bridge/CLAUDE.md — are committed knowledge, not per-user config, so teardown is out of scope) — documented as a deliberate omission, NOT left ambiguous. The `Parameters` section's `module` enumeration (`commands/setup.md:21`: "one of observability, telemetry, …") gains `twin`, and a twin subcommand note parallels the observability one (`:24`).
- [ ] Given the no-arg dashboard runs ONE real check per module as a numbered list (`commands/setup.md:60-76`), when `twin` is added, then a `twin` check step is appended to that list (deriving the readiness cell per AC1's probes) AND a `twin` row is added to the dashboard status table (`commands/setup.md:~90`) with "Configure with `/setup twin`" — so the dashboard cell shows a real derived value, not an empty row.
- [ ] Given the no-arg `/setup` dashboard's **fixed ≤4-option `AskUserQuestion` offer set** (`commands/setup.md:93-101`), when `twin` is added, then that set is REVISED so `twin` is surfaced as an actionable option (not just a status row) while preserving the hard 4-option cap — e.g. fold `telemetry` (which only delegates to `/telemetry`) into the "Other integrations" group so the two real-apply modules (`observability` + `twin`) keep individual slots: `1. observability · 2. twin · 3. Other integrations (telemetry · webhook · Beads · MySQL MCP) · 4. Nothing`. Without this, `/setup` no-arg would show a twin row with no bootstrap path.
- [ ] Given the change, when counts are inspected, then agents/commands/skills/hooks are **UNCHANGED** (no new top-level command, skill, agent, or hook); `plugin.json` + `marketplace.json` bump to **14.50.0** (equal), `CLAUDE.md` gets a new banner + version line, `CHANGELOG.md` a new entry.
- [ ] Given the change, when `scripts/validate-version.sh`, `scripts/check-doc-currency.sh`, and `scripts/check-command-sync.sh` run, then all exit 0; and `bash ai-agent-manager-plugin/scripts/test-setup-twin.sh` passes (auto-registered by the `ci.yml` `test-*.sh` glob).

## Outcomes Rubric
- `ai-agent-manager-plugin/scripts/setup-twin.sh` (executable) and `ai-agent-manager-plugin/scripts/test-setup-twin.sh` both exist.
- `setup-twin.sh` contains `set -uo pipefail` + an `exit 0` fail-safe path, detects the graph via `graphify-out/graph.json`, and invokes `build-bridge.sh` with an explicit `--out` argument whose value ends in `.supervisor/bridge` (write-containment — does NOT rely on the config-default out dir).
- `setup-twin.sh` emits any CLAUDE.md skeleton to stdout and contains NO write to `CLAUDE.md` or `~/.claude/settings.json`.
- `ai-agent-manager-plugin/skills/setup/SKILL.md` has a `twin` module-registry row, its Pattern 1 `offer` text lists `twin` among the no-arg options (≤4 total — no longer the old observability/telemetry/Other/Nothing set), AND its §Quality Gates sanctioned-write-domain bullet names `twin`'s write domains.
- `ai-agent-manager-plugin/commands/setup.md` has a `twin` flow section + `/setup twin` usage line, a `twin` row in the no-arg dashboard status table, `twin` in the Parameters `module` enumeration, its no-arg `AskUserQuestion` option list includes `twin` with ≤4 options, and its `## Constraints` section names the sanctioned `twin` write domains (`.supervisor/bridge/` + confirmed `CLAUDE.md`).
- `ai-agent-manager-plugin/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` version are both "14.50.0" and `CHANGELOG.md` has a new top entry beginning "v14.50.0".
- No new file under `ai-agent-manager-plugin/agents/`, `ai-agent-manager-plugin/commands/`, or `ai-agent-manager-plugin/skills/` (counts stay 14/20/56), and `hooks/hooks.json` is unchanged.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Design notes (verified facts — embedded so workers don't re-derive)

- **Mirror the `/setup observability` module precedent** (the richest existing module). The 5-phase contract authority is `skills/setup/SKILL.md` (check → report → offer → apply → verify; idempotent; backup-first/abort-on-parse-failure jq merges; 4-option offer cap). New modules MUST "append a row [to the registry table] AND a flow section in `commands/setup.md` in the same change" (`skills/setup/SKILL.md`). The mechanizable parts live in a helper script (`scripts/setup-twin.sh`, mirroring how observability uses `set-otel-resource-attrs.sh` + recipes); the interactive offer/apply flow lives in `commands/setup.md`.
- **graphify is EXTERNAL** — a user-global skill/CLI (`~/.claude/skills/graphify`, triggered by `/graphify`), NOT a plugin command or skill. The module CANNOT invoke `/graphify`. The helper REPORTS availability via `command -v graphify`; the `commands/setup.md` layer owns the offer/confirm and (on confirm) runs `graphify .`; otherwise guidance is printed. Detection signal for an existing graph = `test -e graphify-out/graph.json` (the exact signal `brain-context` uses). Staleness = the PREFIX-TOLERANT comparison from `read-bridge.sh:135-149` (built_at_commit is often abbreviated; fresh when built_at is a prefix of full HEAD OR HEAD's 12-char prefix is a prefix of built_at; else stale ⇒ hint). NEVER an exact `!=` against the full 40-char HEAD (that false-stales every abbreviated graph). Never a hard fail.
- **bridge is plugin-owned** — `scripts/build-bridge.sh` (v14.46.0) rebuilds `.supervisor/bridge/bridge.json` from the current graph + findings corpus; READ-ONLY toward inputs, exits 0 on missing graph/python. This is the one bootstrap step the module runs directly.
- **CLAUDE.md** — `skills/claude-md-validation/SKILL.md` is **validation-only** (freshness > 30 days warn; samples 2-3 documented patterns vs grep; non-blocking). There is NO existing scaffolder — the "offer to scaffold a starter CLAUDE.md when absent" is net-new, must be a simple skeleton, human-confirmed, and must never overwrite an existing CLAUDE.md.
- **brain-context** (`skills/brain-context/SKILL.md`) is read-path-only / opportunistic / NOT preloaded, with NO bootstrap path today — this module closes exactly that gap. The module changes none of brain-context's read behavior.
- **Hook count untouched:** the SessionStart "run /setup twin" nudge is DEFERRED to 3b, so `hooks/hooks.json` is NOT edited and the hook-count claim stays valid (do NOT restate the number in any edit — let `check-doc-currency.sh` confirm).
- **Doc-currency:** counts are unchanged (a `/setup` sub-module is not a new command/skill/agent/hook). The only restated-list that changes is the `/setup` module enumeration (6 → 7 modules) in `commands/setup.md` (frontmatter `description:` + usage) and `skills/setup/SKILL.md` (registry); keep those two consistent. Per the anti-rebloat rule, do NOT append a new clause to `plugin.json`/`marketplace.json` `description` — only bump the `vX.Y.Z` token (adding "Twin" to the existing `/setup` capability enumeration in the description is acceptable but optional; do not lengthen the sentence).

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `setup-twin.sh` module helper (check + bootstrap engine) | readiness probes (prefix-tolerant staleness) · no-graph guide · same-invocation bridge build · CLAUDE.md validate/stdout-skeleton · 5-phase+idempotent · scoped-write/fail-safe invariant | 0 modify, 1 create | monitoring-observability, error-handling | LAUNCHABLE |
| 2 | `test-setup-twin.sh` static fixture self-test | the self-test + CI-gate criterion (final AC) | 0 modify, 1 create | unit-testing | BLOCKED (by #1) |
| 3 | Wire the `twin` module into the `/setup` umbrella (setup.md flow + SKILL registry + dashboard + arg parse) | module-registration criterion (registry row + flow section + 6→7 enumeration) AND the no-arg ≤4-option offer-set revision criterion | 2 modify, 0 create | — | BLOCKED (by #1) |
| 4 | Version bump 14.50.0 + doc surfaces (CLAUDE.md banner, README/agent-help twin mention, CHANGELOG) + run gate scripts | counts-unchanged/version-bump criterion + the gate-scripts-green/self-test criterion | ~5 modify, 0 create | commit | BLOCKED (by #1, #3) |

### Subtask Detail

**Subtask 1 — `ai-agent-manager-plugin/scripts/setup-twin.sh`.** Plugin-owned helper with subcommands: `check` (emit derived readiness — graph present/stale [prefix-tolerant per AC1], bridge present, CLAUDE.md present/fresh, brain-root set — to stdout, ALWAYS exit 0, never probes-by-assertion) and `bootstrap` (if graph absent: the helper REPORTS graphify availability via `command -v graphify` and prints the `graphify .` guidance — it does NOT prompt; the `commands/setup.md` layer owns the `AskUserQuestion` offer/confirm and, only on confirm, either runs `graphify .` itself or invokes the helper to run it. The helper executes the external CLI ONLY when the command layer drives it post-confirm. Then RE-PROBE the graph and ALWAYS run `build-bridge.sh --root "$repo" --out "$repo/.supervisor/bridge"` at the end (explicit `--out` is REQUIRED — it short-circuits the `.supervisor/config.json .build_bridge.out` redirect at `build-bridge.sh:79-82`, guaranteeing write containment) — fail-safe, no-ops if still no graph, so the bridge is built in the same run per AC3; validate CLAUDE.md, or when absent PRINT a starter skeleton to **stdout only** — the helper NEVER writes CLAUDE.md). `set -uo pipefail`; fail-safe exit 0 on every no-data/missing-dep branch; the helper's own writes are limited to `.supervisor/bridge/` (via build-bridge); it touches NO settings.json and NEVER writes/overwrites CLAUDE.md (that is the command layer's confirmed-only job). `chmod +x`. Use `${CLAUDE_PLUGIN_ROOT}` for sibling-script calls.

**Subtask 2 — `ai-agent-manager-plugin/scripts/test-setup-twin.sh`.** Static (no graphify CLI, no network, no Docker), fixture-driven — mirror `test-setup-observability.sh` style. Cover: (a) `check` output on a fixture with graph+bridge+CLAUDE.md vs an empty fixture; (b) staleness — an ABBREVIATED `built_at_commit` that IS a prefix of HEAD reports FRESH (guards against the exact-`!=` regression), while a genuinely divergent SHA reports stale-hint; (c) graphify-absent path guides without failing (exit 0); (d) scoped-writes invariant — assert the helper writes NO `~/.claude/settings.json`, and writes/overwrites NO `CLAUDE.md` at all (skeleton goes to stdout); (d2) write-containment — with a fixture `.supervisor/config.json` that sets `.build_bridge.out` to a redirect path, assert the helper's bridge write still lands in `.supervisor/bridge/` (i.e. it passed explicit `--out`, ignoring the config redirect) and NOTHING is written to the redirect path; (e) idempotency — second `check`/`bootstrap` changes nothing. Non-zero exit on any failure.

**Subtask 3 — umbrella wiring.** In `commands/setup.md`: add a `## Module: twin` flow section (check/report/offer/apply/verify subflows mirroring the observability section but calling `setup-twin.sh`); a `/setup twin` line in the **Usage block** (`:9-17`); `twin` to the **Parameters `module` enumeration** (`:21`) + a twin subcommand note parallel to the observability one (`:24`, surface = `status` / no-subarg-bootstrap, `remove` N/A — see AC); a numbered **`twin` check step appended to the no-arg dashboard check list** (`:60-76`) AND a **`twin` row in the dashboard status table** (`:~90`); and `twin` in the FIRST-positional-arg parser + the frontmatter `description:` enumeration (6→7 modules). **Revise the no-arg fixed ≤4-option offer set at `commands/setup.md:93-101`** to surface `twin` as actionable while keeping the 4-option cap (fold `telemetry` into "Other integrations"; keep observability + twin as the two individual real-apply slots — see the AC). In `skills/setup/SKILL.md` (the **authority** — "when the two disagree, this skill wins", `SKILL.md:10`): add a `twin` row to the module registry table; update the **Pattern 1 `offer` row (`SKILL.md:34`)** whose text currently hard-codes the old fixed set ("observability, telemetry, 'Other integrations'…, 'Nothing'") so it matches the revised `observability · twin · Other integrations (telemetry·webhook·Beads·MySQL MCP) · Nothing` set — otherwise the stale authority overrides the command's offer; AND update the **§Quality Gates sanctioned-write-domain checklist (`SKILL.md:241`)** — a SECOND write-domain list distinct from `commands/setup.md`'s Constraints — to include `twin`'s domains (helper writes `.supervisor/bridge/` only via explicit `build-bridge.sh --out`; command layer may create `CLAUDE.md` only when absent + confirmed; NO `~/.claude/settings.json` write for `twin`). Both the SKILL Constraints/Quality-Gates list AND the command Constraints list must sanction twin (the authority list is the load-bearing one). Also update `commands/setup.md`'s **`## Constraints (every module)` section (`setup.md:243-250`)** — which today enumerates the ONLY files setup's own logic may write (`$OBS_DIR`, `~/.claude/settings.json`, `<project>/.claude/settings.local.json`) — to additionally sanction the `twin` write domains: the helper's `.supervisor/bridge/` write (via `build-bridge.sh --out`) and the command-layer confirmed `CLAUDE.md` create-when-absent. Keep all module enumerations + the offer set consistent across both files (restated-list discipline).

**Subtask 4 — version + doc.** Bump `plugin.json` 14.49.0 → **14.50.0** (+ its description `vX.Y.Z`; optionally add "Twin" to the `/setup` capability phrase, do not lengthen the sentence). Same for `marketplace.json` (must equal — `validate-version.sh`). `CLAUDE.md`: new v14.50.0 banner (keep only the two most recent — drop the older banner, already in CHANGELOG), `plugin.json (vX.Y.Z)` line, and add the twin module to any `/setup` mention. Add a brief twin mention where `/setup` is described in `README.md` + `commands/agent-help.md`. Add a `CHANGELOG.md` top entry. **Counts stay 14/20/56/21 — do not change any count claim.** RUN `bash scripts/validate-version.sh && bash scripts/check-doc-currency.sh && bash scripts/check-command-sync.sh` and fix any drift before done. (doc-currency FILES = CLAUDE.md, README.md, AGENT_GUIDELINES.md, .claude-plugin/README.md, .claude-plugin/marketplace.json, plugin.json, commands/agent-help.md, docs/ARCHITECTURE.md, docs/ARCHITECTURE_CONTRACTS.md — grep each, but since NO count changes, expect no count-claim edits.)

### Provides / Requires Schema

```yaml
# Subtask 1 — module helper (LAUNCHABLE)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/setup-twin.sh"}
requires: []
external_requires:
  - "graphify CLI (optional, external, user-global — module guides when absent, never hard-depends)"
```

```yaml
# Subtask 2 — self-test (BLOCKED by #1)
provides:
  - {kind: "file", path: "ai-agent-manager-plugin/scripts/test-setup-twin.sh"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/setup-twin.sh"}
external_requires: []
```

```yaml
# Subtask 3 — umbrella wiring (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/commands/setup.md", name: "Module: twin"}
  - {kind: "symbol", path: "ai-agent-manager-plugin/skills/setup/SKILL.md", name: "twin"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/setup-twin.sh"}
external_requires: []
```

```yaml
# Subtask 4 — version + doc (BLOCKED by #1, #3)
provides:
  - {kind: "symbol", path: "ai-agent-manager-plugin/.claude-plugin/plugin.json", name: "version"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "version"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "v14.50.0"}
requires:
  - {from: "1", kind: "file", path: "ai-agent-manager-plugin/scripts/setup-twin.sh"}
  - {from: "3", kind: "symbol", path: "ai-agent-manager-plugin/commands/setup.md", name: "Module: twin"}
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──┬──→ Subtask 2
            └──→ Subtask 3 ──→ Subtask 4
                 (Subtask 4 also requires Subtask 1)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| ST1 (setup-twin.sh) | ST2 (test-setup-twin.sh) | none | content dep only — ST2 tests ST1 |
| ST2 (test) | ST3 (setup.md, setup/SKILL.md) | none | No — run in parallel after ST1 |
| ST3 (setup wiring) | ST4 (plugin.json, marketplace.json, CLAUDE.md, README.md, agent-help.md, CHANGELOG.md) | none | Yes — ST4 banner describes the landed module |

- **Batches:** B1 = {ST1}; B2 = {ST2, ST3} (parallel); B3 = {ST4}. Three batches.
- **Recommended workers:** 2.

## Skill References
- `monitoring-observability`, `error-handling` — fail-safe shell helper discipline (ST1)
- `unit-testing` — static fixture self-test (ST2)
- `commit` — conventional commit + version-bump discipline (ST4)
- (consumed at runtime by the module, not by workers: `claude-md-validation`, `build-bridge.sh`, `brain-context`)

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Module hard-depends on the external `graphify` CLI and breaks when absent | HIGH | AC2 + ST1 + ST2 test (c) mandate detect-and-guide; the module NEVER fails on absent graphify — it prints the command. graphify is `external_requires`, never a `from` target. |
| `build-bridge.sh`'s `.supervisor/config.json .build_bridge.out` override redirects the helper's write outside `.supervisor/bridge/`, breaking the scoped-write invariant | HIGH | AC6 + ST1 require calling `build-bridge.sh --root "$repo" --out "$repo/.supervisor/bridge"`; explicit `--out` short-circuits the config branch (`build-bridge.sh:79-82` gates on `[ -z "$OUT" ]`); ST2 test (d2) asserts a redirecting config is ignored. |
| Scaffolding CLAUDE.md overwrites a real one (data loss) | HIGH | AC4 + invariant: scaffold ONLY when absent, ONLY on explicit confirm, never overwrite; ST2 test (d) asserts no overwrite of an existing CLAUDE.md. |
| Module mutates `~/.claude/settings.json` like observability does (wrong — twin is per-repo committed knowledge, not per-user config) | MEDIUM | AC6 + ST2 test (d): twin touches NO settings.json keys; it writes only `.supervisor/bridge/` (via build-bridge), `graphify-out/` (via external graphify), and CLAUDE.md (confirmed). |
| Module-enumeration drift (6→7) between `setup.md` and `setup/SKILL.md` | MEDIUM | AC7 + ST3 keeps both consistent; Phase 4.5 consistency_audit catches restated-list drift (this repo's own surfaces). |
| `twin` reachable via `/setup twin` but invisible/inactionable in the no-arg `/setup` dashboard offer (the fixed ≤4-option `AskUserQuestion` set) | MEDIUM | AC + ST3 require revising the offer set (fold `telemetry` into "Other integrations"; observability + twin keep individual real-apply slots) — preserves the 4-option cap while giving twin a bootstrap path from the no-arg flow. |
| Staleness check conflates the graph's `built_at_commit` with mtime or mis-resolves HEAD | LOW | Mirror `brain-context`/`read-bridge.sh` exactly: SHA-vs-HEAD, stale ⇒ hint, never hard fail (the freshness lesson from the handoff brief). |
| Scope creep into 3b (rules suggestion / `/rules` / `.agent/rules/` / SessionStart nudge) | LOW | Explicitly OUT OF SCOPE here; this slice is graph+bridge+CLAUDE.md bootstrap + status only. |
| Hook-count claim churn | LOW | No hook added; `hooks/hooks.json` untouched; brief does not restate the hook number — `check-doc-currency.sh` confirms. |

## Configuration
- **Workers:** 2
- **Mode:** parallel
- **Estimated batches:** 3
- **Base Branch:** main
- **Self-heal:** default ON (Phase 4.5) — new script + setup-module surface; consistency_audit + corpus-task ground-truth are the right gates.
- **Heal iterations:** default (3)
- **Cost profile:** default (inherit)
- **Beads:** not required (Supervisor/Launch Pad path)

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-06-29-setup-twin-bootstrap.md

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/83
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 0 (review clean on first pass — no fixes needed)
- **Heal remaining issues:** 0 (one LOW pre-existing cosmetic note, no action)
- **Rubric score:** 7/7
- **Ground-truth (corpus-tasks):** doc-currency-green PASS · version-consistent PASS (validate-version + check-doc-currency + check-command-sync all exit 0)
- **Self-test:** test-setup-twin.sh 29/29; observability + build-bridge regressions green
- **Until-mergeable dispatched:** true
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20260629T130516Z-d61e6e749245f0422fd613b77af65a77fce8c772.log
- **Version:** 14.49.0 → 14.50.0 (counts unchanged 14/20/56/21)
