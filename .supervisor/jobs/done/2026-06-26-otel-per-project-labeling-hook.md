# Supervisor Job: Auto-maintain per-project OTEL_RESOURCE_ATTRIBUTES (telemetry-gated SessionStart hook)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh, v14.46.0)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Worktrees:** 1 (main only)
- **Blockers:** 0 | **Warnings:** 1 (opinionated cross-repo write — gated + fail-safe; see Risk Assessment row 1)

## Task
**Goal:** Ship a plugin feature that, **only when telemetry is enabled**, automatically keeps each project's OpenTelemetry `service.name` (the repo name) and `service.version` (the plugin version) current in that project's `.claude/settings.local.json` — so Claude Code's native OTel traces are labeled per-project in Langfuse/Grafana **without the user hand-editing a file per repo**. This automates the manual per-repo `service.name` snippet that `/setup observability` currently only *offers* (`commands/setup.md` lines 174-178).

**Mechanism:** a new fail-safe `SessionStart` hook script that derives the values and idempotently merges `OTEL_RESOURCE_ATTRIBUTES` into the project's `.claude/settings.local.json`. The same script is also invoked at the end of a successful `/setup observability` init so the **current** repo is labeled the moment telemetry is enabled (honoring "also when telemetry is enabled").

**Why `settings.local.json`:** it is the project-scoped, gitignored-by-convention, highest-precedence settings file (Local > Project > User), so it cleanly overrides the global `service.version=<X>` that `/setup observability` writes to `~/.claude/settings.json`, and carries no commit risk in repos that ignore it.

## Acceptance Criteria
- [ ] Given telemetry is enabled (user `~/.claude/settings.json` `.env.CLAUDE_CODE_ENABLE_TELEMETRY=="1"`, OR the runtime env var is `1`), when a session starts in a git repo, then `<repo>/.claude/settings.local.json` is created/updated so `.env.OTEL_RESOURCE_ATTRIBUTES == "service.name=<repo-basename>,service.version=<plugin version>"`, preserving every other key already in that file.
- [ ] Given telemetry is **NOT** enabled, when a session starts, then the script is a **silent no-op** (writes nothing, exits 0) — no `.claude/settings.local.json` is created in any repo.
- [ ] Given the value is already current, when the script runs again, then it makes **no write** (idempotent — file mtime unchanged).
- [ ] Given `.claude/settings.local.json` exists but is **not valid JSON**, when the script runs, then it does **not** clobber the file and exits 0 (fail-safe).
- [ ] Given the cwd is not a git repo, when the script runs (telemetry on), then `service.name` falls back to the cwd basename (still labeled, never errors).
- [ ] Given a `service.name` derived from a repo whose basename contains `,`/`=`/space/newline, when written, then those characters are sanitized (→ `_`) so the `OTEL_RESOURCE_ATTRIBUTES` list parses as exactly the intended pairs (no corrupted/extra attributes).
- [ ] Given an existing `OTEL_RESOURCE_ATTRIBUTES` with unrelated attrs (e.g. `deployment.environment=dev`), when the script runs, then `service.name`/`service.version` are updated AND the unrelated attrs are preserved (not erased).
- [ ] Given telemetry enabled in **console mode or env-only** (no `OTEL_EXPORTER_OTLP_ENDPOINT`), when a session starts, then labeling still happens (the gate keys only on `CLAUDE_CODE_ENABLE_TELEMETRY`).
- [ ] `/setup observability` owns the per-project label across its full lifecycle: **init** (any backend) labels the current repo immediately and reports the resulting `service.name`/`service.version`; **status** reports the current repo's `OTEL_RESOURCE_ATTRIBUTES` (or "not set"); **remove** best-effort strips the current repo's project-level `OTEL_RESOURCE_ATTRIBUTES`.
- [ ] Given the change, when the self-test + `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` run, then all green; hook count claims advance 20 → 21 everywhere they appear (including the unscanned `OBSERVABILITY.md` stale "19").

## Hard Constraints (invariants — do not break)
- **Fail-safe (ALWAYS exit 0):** the SessionStart script NEVER blocks or slows session start; any failure (no jq, unparseable settings, unwritable dir, missing plugin.json) is a silent no-op exit 0. Mirror `session-resume.sh`'s `set -u` (NO `set -e`/pipefail), jq-gated, always-exit-0 contract. This is a runtime side-effect emitter → fails **SAFE**, never CLOSED (the bimodal rule in CLAUDE.md §"Failure-Mode Invariants").
- **Telemetry-gated — gate ONLY on `CLAUDE_CODE_ENABLE_TELEMETRY`:** the script does NOTHING unless telemetry is enabled. Enabled IFF `~/.claude/settings.json` `.env.CLAUDE_CODE_ENABLE_TELEMETRY=="1"` **OR** the runtime env var `CLAUDE_CODE_ENABLE_TELEMETRY=="1"`. **Do NOT require `OTEL_EXPORTER_OTLP_ENDPOINT`** (that is `session-resume.sh`'s *probe* gate, which is intentionally stricter) — gating on the endpoint would wrongly skip **console-debug mode** and **env-only** telemetry, both of which should still get labeled. This is a narrower, simpler gate than session-resume's probe; do not copy session-resume's full probe condition. A plugin must not write into a user's repos when they haven't opted into telemetry.
- **Idempotent + non-destructive (covers the attribute VALUE too):** jq deep-merge ONLY `.env.OTEL_RESOURCE_ATTRIBUTES`; preserve all other keys at both the top level and under `.env` (atomic tmp-file + `mv`; no write when unchanged; never `del`). **AND within `OTEL_RESOURCE_ATTRIBUTES` itself, preserve unrelated attributes** — parse any existing value as a comma-separated `key=value` list, drop only the existing `service.name`/`service.version` pairs, set the new ones, and re-join keeping every other attribute (e.g. a user-local `deployment.environment=dev` must survive). Overwriting the whole value would silently erase user attrs. Idempotency compares the full re-joined string.
- **OTel attribute-format safety (NOT just JSON-safety):** `jq --arg` makes the JSON write injection-safe, but it does **not** make the value safe inside the OTel `OTEL_RESOURCE_ATTRIBUTES` grammar (a comma + `=` delimited list). **Sanitize `service.name`** so it cannot break that grammar: replace every character outside `[A-Za-z0-9._-]` with `_` (this neutralizes commas, `=`, spaces, and newlines). Apply BEFORE composing the value. (`service.version` from plugin.json is already in that safe set, but sanitize it the same way defensively.) The repo name and version still cross into the jq program ONLY via `--arg`.
- **No new agent / command / skill.** This adds exactly ONE hook (count 20 → 21) and one script + one self-test. No `schema_version` changes. The two review lenses / advisory contracts elsewhere are untouched.
- **Plugin-path discipline:** all runtime references use `${CLAUDE_PLUGIN_ROOT}/...` (never a repo-relative dev path). The script resolves the plugin version from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` when the env var is set, else from a `BASH_SOURCE`-relative `../.claude-plugin/plugin.json` (so it also works when invoked by `/setup`).

## Feasibility (Phase 2.5)
**Verdict: GO** (1 CAUTION).
1. **Tech-stack compatibility — GO.** bash + jq + a hooks.json entry + markdown doc edits; identical stack to `session-resume.sh` / the `setup` module.
2. **Dependency availability — GO.** `jq`, `git`, bash already required. `${CLAUDE_PLUGIN_ROOT}` is provided to plugin hooks (proven by the existing `session-resume.sh` entry). No new dependency.
3. **Architecture fit — GO.** Sits squarely in the existing observability/`setup` story; reuses the settings.json telemetry-config READ mechanism and the fail-safe-emitter convention from `session-resume.sh` — but with a deliberately NARROWER gate (only `CLAUDE_CODE_ENABLE_TELEMETRY`, not session-resume's stricter BOTH-flag probe; see Hard Constraints).
4. **Scope vs Supervisor — GO.** 4 subtasks of 30–60 min each.
5. **Hard blockers — none. CAUTION:** a plugin auto-writing into *every* repo's `.claude/settings.local.json` is opinionated. Mitigated three ways: (a) **telemetry-gated** (only fires for users who opted in via `/setup observability`); (b) writes the **gitignored-by-convention** `settings.local.json`, not the committed `settings.json`; (c) idempotent + fail-safe. Residual: a repo that does NOT gitignore `settings.local.json` would gain an untracked file (cosmetic; the file is personal). Carried to Risk Assessment row 1.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Hook script `set-otel-resource-attrs.sh` | 1 create | LAUNCHABLE |
| 2 | Fixture-driven self-test | 1 create | BLOCKED (by #1) |
| 3 | Wire the SessionStart hook + `/setup` invocation + docs | 3-4 modify | BLOCKED (by #1) |
| 4 | Housekeeping — version + hook-count 20→21 + CHANGELOG/CLAUDE.md + doc-currency | 5-6 modify | BLOCKED (by #1-#3) |

### Subtask 1 — `ai-agent-manager-plugin/scripts/set-otel-resource-attrs.sh` (LAUNCHABLE)
Mirror `session-resume.sh`'s fail-safe shape (`set -u`; NO `set -e`/pipefail; jq-gated; ALWAYS exit 0; `chmod +x`). The script:
1. **Telemetry gate (first):** enabled IFF `command -v jq` AND (`jq -e '.env.CLAUDE_CODE_ENABLE_TELEMETRY=="1"' "$HOME/.claude/settings.json"` succeeds OR `[ "${CLAUDE_CODE_ENABLE_TELEMETRY:-}" = "1" ]`). **Gate ONLY on this flag — do NOT also require `OTEL_EXPORTER_OTLP_ENDPOINT`** (console-mode and env-only telemetry must still label). Not enabled / no jq ⇒ **exit 0 silently** (no file touched).
2. **Resolve `service.name`:** `ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"`; `APP="$(basename "$ROOT")"`. Empty ⇒ exit 0.
3. **Resolve `service.version`:** prefer `"${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json"` when `CLAUDE_PLUGIN_ROOT` is set; else a `BASH_SOURCE`-relative `"$(dirname "$BASH_SOURCE")/../.claude-plugin/plugin.json"`. `jq -r '.version'`. Unresolvable ⇒ use `unknown` (still label `service.name`; never error).
4. **Sanitize for the OTel attribute grammar:** `APP="$(printf '%s' "$APP" | tr -c 'A-Za-z0-9._-' '_')"` (and the same for `VER` defensively) — neutralizes commas / `=` / spaces / newlines that would corrupt the comma-`=`-delimited `OTEL_RESOURCE_ATTRIBUTES` list. Do this BEFORE composing.
5. **Compose the NEW pairs:** `service.name=${APP}` and `service.version=${VER}`. **Merge-preserve any existing value:** read the current `.env.OTEL_RESOURCE_ATTRIBUTES` from `SL` (if present), split on `,`, DROP any existing `service.name=…`/`service.version=…` pairs, KEEP every other attribute (e.g. `deployment.environment=dev`), then build `ATTR` = the two new pairs followed by the preserved others, comma-joined. (A fresh value when none existed is just the two pairs.)
6. **Current-session best-effort (UNVERIFIED bonus — correctness must NOT depend on it):** if `CLAUDE_ENV_FILE` is set (SessionStart provides it), append `export OTEL_RESOURCE_ATTRIBUTES=<value>` (`printf %q`-quoted) so the CURRENT session *may* pick it up. **Caveat:** OTel commonly reads env at process start, before this hook runs, so this may not take effect — it is a best-effort add-on only; the durable path is the file write below + next-session pickup. Skip silently if `CLAUDE_ENV_FILE` is absent. The self-test does NOT assert cross-session env propagation (timing-dependent, not mechanically testable).
7. **Durable per-project write:** `SL="$ROOT/.claude/settings.local.json"`; `mkdir -p "$ROOT/.claude"`.
   - If `SL` exists: `jq empty "$SL"` (parse-gate — **unparseable ⇒ exit 0, no clobber**); **if current `.env.OTEL_RESOURCE_ATTRIBUTES` already equals the freshly-computed `ATTR` ⇒ exit 0 (idempotent, no write)**; else `jq --arg a "$ATTR" '.env = ((.env // {}) + {OTEL_RESOURCE_ATTRIBUTES:$a})'` to a tmp file then `mv` (atomic). On any jq failure ⇒ remove tmp, exit 0.
   - If `SL` absent: `jq -n --arg a "$ATTR" '{env:{OTEL_RESOURCE_ATTRIBUTES:$a}}' > "$SL"`; `chmod 600 "$SL"` (it can hold user-local config; created-file perms should be owner-only, matching the `.env` precedent in the setup skill).
8. `exit 0` on every path.
9. **`--help`/`-h`** prints the header (a one-paragraph contract) and exits 0. Argument is otherwise ignored (the hook passes none; `/setup` calls it bare).
- **Injection-safety:** `APP`/`VER`/`ATTR` cross into jq via `--arg` ONLY. Never interpolate into the jq program.
- **Read-only toward everything except `<project>/.claude/settings.local.json` and (best-effort) `$CLAUDE_ENV_FILE`.** Never touches `~/.claude/settings.json` (that is `/setup`'s sole-write domain).

### Subtask 2 — `ai-agent-manager-plugin/scripts/test-set-otel-resource-attrs.sh` (BLOCKED by #1)
Fixture-driven (temp `HOME` + temp git repo via `mktemp -d`, `trap` cleanup; never touch the real `~/.claude` or any real repo — set `HOME` to the temp dir for the gate-read, and `cd` into the temp git repo). Auto-registers via the `ci.yml` `test-*.sh` glob (verify the glob, no CI edit). `set -uo pipefail`; PASS/FAIL tally; non-zero exit ONLY on a genuine failure (CI-gate semantics, distinct from the runtime script's always-exit-0). Cover:
- **Telemetry OFF ⇒ no-op:** temp `~/.claude/settings.json` with no telemetry (or absent) and unset env var ⇒ script writes NO `settings.local.json`, exits 0.
- **Telemetry ON (via settings.json) ⇒ writes** `service.name=<temp-repo-basename>,service.version=<plugin version>` into `<repo>/.claude/settings.local.json`.
- **Telemetry ON (via env var only) ⇒ writes** (proves the OR branch — and proves the gate does NOT require `OTEL_EXPORTER_OTLP_ENDPOINT`: set the env flag with NO endpoint anywhere and assert it still labels, covering console/env-only mode).
- **Preserves existing JSON keys:** seed `settings.local.json` with an unrelated `.env.FOO` and a top-level key ⇒ both survive, `OTEL_RESOURCE_ATTRIBUTES` added.
- **Preserves existing OTel attributes (value-level merge):** seed `.env.OTEL_RESOURCE_ATTRIBUTES="deployment.environment=dev,service.name=old"` ⇒ after run, `service.name`/`service.version` are the new computed values AND `deployment.environment=dev` is still present; the stale `service.name=old` is replaced (not duplicated).
- **Special-character repo name ⇒ sanitized:** drive a temp repo dir whose basename contains a comma / `=` / space (e.g. `my,repo=x`) ⇒ assert the written `service.name` has those replaced with `_` and the `OTEL_RESOURCE_ATTRIBUTES` value parses as exactly the intended pairs (no extra/broken attributes). Also confirm no shell/jq breakage (always exit 0).
- **Idempotent:** run once, capture content + mtime; **`sleep 1`** (avoid same-second mtime flakiness); run again with the value already current ⇒ file content byte-identical AND mtime unchanged (proves no second write).
- **Unparseable settings.local.json ⇒ no clobber, exit 0** (assert byte-identical before/after).
- **Non-git cwd ⇒ cwd-basename fallback** (still writes a labeled value, exit 0).
- **Created-file perms:** when the script CREATES `settings.local.json`, assert it is `600` (owner-only).
- **Version source:** assert the written `service.version` equals `jq -r .version` of the fixture/`${CLAUDE_PLUGIN_ROOT}` plugin.json (drive `CLAUDE_PLUGIN_ROOT` at a fixture manifest).
- **Always exit 0** on the runtime script across every above path (the harness itself may fail loud).

### Subtask 3 — Wire the hook + `/setup` invocation + docs (BLOCKED by #1)
- **`ai-agent-manager-plugin/hooks/hooks.json`** — add a SECOND `SessionStart` entry (a new array element with its own `{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}/scripts/set-otel-resource-attrs.sh\""}]}`), a sibling to the existing `session-resume.sh` entry. **Do NOT** merge it into session-resume's entry — they have different source-filtering (session-resume skips `startup`; this one must fire on `startup` too) and different concerns. This is the **+1 hook leaf** (count 20 → 21 via `[.hooks[][].hooks[]] | length`).
- **`ai-agent-manager-plugin/commands/setup.md`** — `/setup observability` must OWN the per-project label across its full lifecycle (init labels → status reports → remove strips). FOUR edits:
  - **Manual→auto note:** at the local-backend Report step 8 and backend-2/3 Report steps, replace/augment the **manual** "Optional per-repo `service.name` snippet" (lines ~174-178, ~185) with a note that per-project labeling is now **auto-maintained by the `set-otel-resource-attrs.sh` SessionStart hook when telemetry is enabled** (keep a one-line manual-fallback mention). Keep the "project-level `OTEL_RESOURCE_ATTRIBUTES` replaces the user value wholesale" note (the script's value-level merge already restates `service.name`/`service.version` and preserves other attrs).
  - **init (all backends):** add a step at the END of a successful init (every backend that enables telemetry — local / external / console) that invokes `bash "${CLAUDE_PLUGIN_ROOT}/scripts/set-otel-resource-attrs.sh"` once so the current repo is labeled IMMEDIATELY (don't wait for the next session). Report the resulting `service.name`/`service.version` in the success summary. This is the **primary `/setup observability` integration** — the SessionStart hook is the ongoing-maintenance backstop; `/setup` is where it first lands.
  - **status (§"Subflow: `/setup observability status`"):** read and report the CURRENT repo's `.claude/settings.local.json` `.env.OTEL_RESOURCE_ATTRIBUTES` (names/values are non-secret) — e.g. `per-project label: service.name=<repo>,service.version=<X>` or `per-project label: not set` — so the user can verify labeling from `/setup`. Read-only.
  - **remove (§"Subflow: `/setup observability remove`"):** after stripping the user-level env block, ALSO best-effort strip the **current repo's** project-level label — `jq 'del(.env.OTEL_RESOURCE_ATTRIBUTES)'` on `<project>/.claude/settings.local.json` (same backup-first / parse-gate / atomic discipline; fail-safe no-op if absent/unparseable). Document that **other repos'** auto-written labels are left in place and are **inert while telemetry is off** (nothing is exported), and can be cleaned manually — `remove` only knows the current repo. This closes the reviewer's remove-path gap.
  - **Write-domain allow-list (REQUIRED — keeps the brief self-consistent):** the `## Constraints (every module)` block in `commands/setup.md` (~line 234) enumerates the ONLY files `/setup`'s own logic may write as `$OBS_DIR/*` and `$HOME/.claude/settings.json`. The new **remove** `del` writes the project `<project>/.claude/settings.local.json`, which is OUTSIDE that set — so EXTEND the allow-list to add `<project>/.claude/settings.local.json` (project-scope, gitignored-by-convention; sanctioned for the remove `del` and — via the invoked script — the init label), keeping `~/.claude/settings.json` as the existing user-scope entry. (Plan-review MEDIUM finding — without this the consistency audit will flag the write-domain mismatch.)
- **`ai-agent-manager-plugin/skills/setup/SKILL.md`** — add a short note under the observability module (and/or Anti-Patterns/registry) documenting the auto-label hook + its telemetry gate + fail-safe contract, so the skill (the protocol authority) stays in sync with the command. **Also update the skill's Constraints/registry if it mirrors the setup.md write-domain allow-list**, so the protocol authority and the command agree on the new `settings.local.json` write target.
- **`ai-agent-manager-plugin/docs/OBSERVABILITY.md`** — document the auto-labeling behavior (trigger = SessionStart + `/setup` init; gate = telemetry enabled; target = `settings.local.json`; the one-session-lag note + the `CLAUDE_ENV_FILE` best-effort).

### Subtask 4 — Housekeeping (BLOCKED by #1-#3)
- **Hook count 20 → 21** across EVERY doc-currency-scanned hook claim AND the authoritative hook table. The doc-currency gate (`scripts/check-doc-currency.sh`) enforces `[0-9]+ quality gate hooks` and `[0-9]+ hooks centralized`. Update: the CLAUDE.md "**20 hooks centralized**" narrative line (~152) with a new `v14.47.0 added 1 entry — a SessionStart → set-otel-resource-attrs.sh` clause (mirroring the v14.34.0 clause), the CLAUDE.md **hook table** (add a row), `plugin.json` + `marketplace.json` descriptions ("20 quality gate hooks" → 21), `.claude-plugin/README.md`, and `commands/agent-help.md` if it carries a hook count.
- **Sweep UNSCANNED files too (doc-currency does NOT cover every doc).** Run `grep -rn "19 hooks\|20 hooks\|hook count\|hooks centralized\|quality gate hooks" ai-agent-manager-plugin/docs/ ai-agent-manager-plugin/skills/ README.md AGENT_GUIDELINES.md` and update genuine **current-claims**. **Known stale hit:** `ai-agent-manager-plugin/docs/OBSERVABILITY.md:65` says "hook count unchanged at **19**" — already wrong (it's 20 today), and this file is NOT scanned by the gate. Fix it (to 21, or reword so it doesn't assert a stale absolute count). **Leave historical/changelog mentions** ("vX.Y.Z added N → count became M") and SPIKE-doc planning notes UNTOUCHED (the doc-currency philosophy — don't chase historical/example values; cf. CLAUDE.md §"Doc currency"). **Belt-and-suspenders:** after editing, `grep -rn "20 hooks\|20 quality gate"` repo-wide finds no surviving current-claim.
- **Version bump 14.46.0 → 14.47.0** across the 5 doc-currency version surfaces (plugin.json `version`+description, marketplace.json `version`+description, CLAUDE.md `plugin.json (vX.Y.Z)`, `.claude-plugin/README.md` "Plugin manifest (vX.Y.Z)", `commands/agent-help.md` "Plugin metadata (vX.Y.Z)"). Agent/command/skill counts stay 14/19/56. **Verify the base version at execution** — if a prior PR already advanced `plugin.json` past 14.46.0, bump from the actual current value.
- **`CHANGELOG.md`** new v14.47.0 entry; **`CLAUDE.md`** new v14.47.0 banner (rotate the oldest of the two banners into CHANGELOG per the two-most-recent rule). Update the CLAUDE.md `scripts/` description line to mention the new script.
- Run `scripts/check-doc-currency.sh` + `scripts/validate-version.sh` → both green before finishing.

## File Impact Map

| Path | Action | Confidence | Subtask |
|------|--------|-----------|---------|
| `ai-agent-manager-plugin/scripts/set-otel-resource-attrs.sh` | CREATE | HIGH | 1 |
| `ai-agent-manager-plugin/scripts/test-set-otel-resource-attrs.sh` | CREATE | HIGH | 2 |
| `ai-agent-manager-plugin/hooks/hooks.json` | MODIFY | HIGH | 3 |
| `ai-agent-manager-plugin/commands/setup.md` | MODIFY | HIGH | 3 |
| `ai-agent-manager-plugin/skills/setup/SKILL.md` | MODIFY | MEDIUM | 3 |
| `ai-agent-manager-plugin/docs/OBSERVABILITY.md` | MODIFY | MEDIUM | 3 |
| `ai-agent-manager-plugin/.claude-plugin/plugin.json` | MODIFY | HIGH | 4 |
| `.claude-plugin/marketplace.json` | MODIFY | HIGH | 4 |
| `.claude-plugin/README.md` | MODIFY | HIGH | 4 |
| `ai-agent-manager-plugin/commands/agent-help.md` | MODIFY | MEDIUM | 4 |
| `CLAUDE.md` | MODIFY | HIGH | 4 |
| `CHANGELOG.md` | MODIFY | HIGH | 4 |

**Reference (read-only, do NOT modify):** `ai-agent-manager-plugin/scripts/session-resume.sh` (fail-safe SessionStart pattern + telemetry-config detection), `ai-agent-manager-plugin/skills/setup/SKILL.md` Pattern 3 (jq deep-merge discipline), `ai-agent-manager-plugin/scripts/test-build-bridge.sh` (fixture-driven self-test pattern), `ai-agent-manager-plugin/hooks/hooks.json` (current SessionStart entry).

## Subtask Contracts (provides / requires)
- **Subtask 1** — `provides:` `set-otel-resource-attrs.sh` (telemetry-gated, fail-safe, idempotent, injection-safe; writes ONLY `<project>/.claude/settings.local.json` + best-effort `$CLAUDE_ENV_FILE`; resolves version from `${CLAUDE_PLUGIN_ROOT}`/BASH_SOURCE; always exit 0). `requires:` (none — leaf).
- **Subtask 2** — `requires:` the script contract from #1. `provides:` `test-set-otel-resource-attrs.sh` registered via the CI glob (fixture-driven; asserts the gate, idempotency, key-preservation, no-clobber, fallback, version source, always-exit-0).
- **Subtask 3** — `requires:` the script from #1. `provides:` the SessionStart hook entry (count +1), the `/setup` init-tail invocation, and the setup.md / setup SKILL / OBSERVABILITY doc updates.
- **Subtask 4** — `requires:` #1-#3. `provides:` version 14.47.0 + hook-count 21 across all scanned surfaces, CHANGELOG/CLAUDE.md banners, both CI gates green.

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 + Subtask 3 (parallel — 2 touches `scripts/test-*`, 3 touches `hooks.json`+`commands/`+`skills/`+`docs/`; no file overlap)
- **Batch 3:** Subtask 4 (after all)
- **Recommended workers:** 2

## Risk Assessment

| Risk | Impact | Likelihood | Mitigation | Source |
|------|--------|-----------|-----------|--------|
| Plugin auto-writes `.claude/settings.local.json` into every repo the user opens — surprising / untracked-file in repos that don't gitignore `settings.local.json` | MEDIUM | MEDIUM | Telemetry-gated (only opt-in users), idempotent, fail-safe, writes the gitignored-by-convention personal file; document the behavior in OBSERVABILITY.md. Residual leak is cosmetic (one personal file). | Feasibility (Phase 2.5) |
| One-session lag — `settings.local.json` is read at session start BEFORE the hook writes it, so a brand-new repo session emits with the prior/absent value | LOW | MEDIUM | Best-effort `$CLAUDE_ENV_FILE` write covers the current session where OTel init timing allows; the `/setup` init-tail invocation labels the repo where you enable telemetry; steady-state repos are already correct. Document the lag. | This analysis (verified vs Claude Code settings model) |
| Hook slows or breaks session start | HIGH | LOW | `set -u` (no `-e`), jq-gated, ALWAYS exit 0, no network, single cheap jq merge; mirrors `session-resume.sh`. Self-test asserts exit 0 on every path. | Hard constraint (fail-safe emitter) |
| Clobbering a user's hand-edited `settings.local.json` | HIGH | LOW | Parse-gate (`jq empty`) before any write, merge-only of the single key, atomic tmp+mv, idempotent skip-if-unchanged. Self-test asserts key-preservation + no-clobber-on-unparseable. | Setup skill Pattern 3 |
| Hook-count drift in docs (20→21 missed somewhere) | LOW | MEDIUM | doc-currency gate enforces the two count phrasings; belt-and-suspenders `grep -rn "20 hooks\|20 quality gate"` after edit; update the authoritative CLAUDE.md hook table (not gate-scanned). | Lessons (sweep-grep-gate-variants) |
| Injection via a hostile repo name into the jq program | MEDIUM | LOW | `--arg` only; never interpolate `APP`/`VER` into the jq program. Self-test can include a repo dir with shell-special chars. | Setup skill anti-patterns |
| **OTel attribute-grammar corruption** — a repo basename with `,`/`=`/space/newline breaks the comma-`=`-delimited `OTEL_RESOURCE_ATTRIBUTES` list (jq `--arg` makes the JSON safe but NOT the OTel grammar) | HIGH | LOW | Sanitize `service.name` to `[A-Za-z0-9._-]` (→ `_`) BEFORE composing; special-char fixture asserts a clean parse. | External review (brief revision) |
| **Clobbering user-local OTel attrs** — overwriting the whole `OTEL_RESOURCE_ATTRIBUTES` would erase e.g. `deployment.environment=dev` | MEDIUM | MEDIUM | Value-level merge: drop only existing `service.name`/`service.version`, preserve all other attrs; fixture asserts preservation. | External review (brief revision) |
| **Stale per-project labels after `/setup observability remove`** — disabling telemetry leaves inert `OTEL_RESOURCE_ATTRIBUTES` in repos | LOW | MEDIUM | `remove` strips the current repo's value; other repos' labels are inert while telemetry is off (nothing exported) and documented as manually cleanable. | External review (brief revision) |

## Outcomes Rubric
- [ ] `scripts/set-otel-resource-attrs.sh` exists, is executable, telemetry-gated **on `CLAUDE_CODE_ENABLE_TELEMETRY` only** (no-op when telemetry off; labels in console/env-only mode), idempotent, fail-safe (ALWAYS exit 0; no-clobber on unparseable settings), injection-safe (`--arg` only) **and OTel-grammar-safe** (`service.name` sanitized to `[A-Za-z0-9._-]`), and writes ONLY `<project>/.claude/settings.local.json` (+ best-effort `$CLAUDE_ENV_FILE`).
- [ ] On a session start with telemetry ON in a git repo, `<repo>/.claude/settings.local.json` `.env.OTEL_RESOURCE_ATTRIBUTES` carries the new `service.name=<repo>` + `service.version=<plugin version>`, **preserving both other JSON keys AND other OTel attributes** (value-level merge), with `service.name` sanitized.
- [ ] `scripts/test-set-otel-resource-attrs.sh` exists, is fixture-driven (temp HOME + temp repo, no real `~/.claude` touched), registered via the CI glob, and covers: telemetry-off no-op, on-via-settings, on-via-env (console/no-endpoint), JSON-key-preservation, **OTel-attr-preservation**, **special-char sanitization**, idempotency (with `sleep 1` mtime guard), no-clobber-on-unparseable, non-git fallback, **created-file 600 perms**, version-source, always-exit-0.
- [ ] `hooks.json` gains exactly ONE new `SessionStart` entry (a sibling to `session-resume.sh`, NOT merged into it); `[.hooks[][].hooks[]] | length == 21`.
- [ ] `/setup observability` owns the full label lifecycle — **init** invokes the script + reports the label, **status** reports the current repo's label, **remove** strips it; `commands/setup.md` + `skills/setup/SKILL.md` + `docs/OBSERVABILITY.md` describe the auto-label hook and its telemetry gate.
- [ ] Hook count advances 20 → 21 across plugin.json/marketplace descriptions, CLAUDE.md narrative + hook table, README, agent-help; version bumped one minor; CHANGELOG + CLAUDE.md banner updated.
- [ ] `scripts/check-doc-currency.sh` and `scripts/validate-version.sh` both exit 0; no new agent/command/skill (counts stay 14/19/56); no `schema_version` change.

## Executable Acceptance
- cmd: `bash ai-agent-manager-plugin/scripts/test-set-otel-resource-attrs.sh`
- cmd: `bash scripts/check-doc-currency.sh`
- cmd: `bash scripts/validate-version.sh`
- cmd: `bash ai-agent-manager-plugin/scripts/set-otel-resource-attrs.sh --help >/dev/null && echo SET_OTEL_HELP_OK`
- cmd: `HOME=$(mktemp -d) bash ai-agent-manager-plugin/scripts/set-otel-resource-attrs.sh; echo "telemetry-off exit=$?"`  # must be 0, writes nothing (no telemetry in the temp HOME)
- cmd: `jq -e '([.hooks[][].hooks[]] | length) == 21' ai-agent-manager-plugin/hooks/hooks.json && echo HOOK_COUNT_21_OK`

## Configuration
- **Beads:** absent (Beads-optional — this brief is the handoff artifact)
- **Cost profile:** default (inherit). `--cheap` viable (mechanical bash + doc edits).
- **Self-heal:** default ON. The diff touches `hooks/`, `commands/`, `skills/`, `docs/`, plugin metadata → Code Reviewer auto-expands to a consistency audit (expected — the hook-count/version sync is exactly what it should catch).
- **Non-interactive:** N/A (interactive `/supervisor` run expected).

## Notes for the Supervisor run (execution callouts)
1. **NEW hook ⇒ count changes (unlike the v14.46 bridge work).** This is the FIRST count-changing release in a while; do not copy the bridge brief's "counts unchanged" boilerplate. `[.hooks[][].hooks[]] | length` must read 21, and EVERY "20 hooks"/"20 quality gate hooks" current-claim must advance. Grep the OLD number repo-wide as the backstop.
2. **Separate hook entry, not merged into `session-resume.sh`.** session-resume.sh deliberately skips `startup` (it only injects recovery context on resume/clear/compact); this feature MUST fire on `startup` too, so it needs its own entry/script. Merging would either break session-resume's startup-silence or miss fresh-session labeling.
3. **The script's sole user-settings interaction is READ-ONLY** (the telemetry gate reads `~/.claude/settings.json`). It must NEVER write `~/.claude/settings.json` — that is `/setup`'s exclusive write domain. It writes only the PROJECT `settings.local.json`.
4. **Fail-safe is the load-bearing invariant** — this is a SessionStart hook, so a non-zero exit or a hang degrades every session launch. Always exit 0; no network; bounded jq. The self-test's always-exit-0 assertions are mandatory.
5. **Verify the base version at FINALIZE** — bump from the actual current `plugin.json` value (14.46.0 today, but confirm a prior PR didn't advance it).
6. **`OTEL_RESOURCE_ATTRIBUTES` is an OTel grammar, not just a JSON string** (external-review finding). `jq --arg` only protects the JSON write; the VALUE is a comma-`=`-delimited attribute list. TWO separate safeties are required and easy to conflate: (a) **sanitize `service.name`** so special chars can't break the list; (b) **value-level merge** so updating `service.name`/`service.version` never erases a user's other attrs (`deployment.environment=…`). The self-test must cover BOTH with dedicated fixtures.
7. **Gate ONLY on `CLAUDE_CODE_ENABLE_TELEMETRY`** (external-review finding) — do NOT replicate `session-resume.sh`'s probe gate (which also requires `OTEL_EXPORTER_OTLP_ENDPOINT` and the resume/clear/compact source filter). Copying it would skip console-mode and env-only telemetry. This hook's gate is deliberately narrower than the probe's.
8. **Doc-currency does NOT scan every doc** (external-review finding). `OBSERVABILITY.md:65` already carries a stale "hook count unchanged at 19"; sweep the unscanned doc/skill set by grep and fix genuine current-claims, but leave historical/changelog/SPIKE mentions frozen.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-06-26-otel-per-project-labeling-hook.md
```

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/ai-agent-manager/pull/80
- **Branch:** feature/otel-per-project-labeling-hook (commit c827958)
- **heal_loop_ran:** true
- **heal_decision:** PASS
- **heal_iterations:** 0 (no fixable BLOCKING/HIGH new issues — review clean on first pass)
- **heal_remaining_issues:** 0
- **rubric_score:** 7/7
- **consistency_audit:** PASS (version_strings / counts / hooks_parity / workflow_alignment all pass)
- **Gates:** check-doc-currency.sh ✓ · validate-version.sh ✓ · self-test 32/32 ✓
- **Until-mergeable dispatched:** true
- **Until-mergeable log:** .supervisor/logs/review-pr-dispatch-20260626T135303Z-80da0ec5660ba6baa371495a155eb877f619c132.log
- **Version:** 14.46.0 → 14.47.0 · **Hooks:** 20 → 21
