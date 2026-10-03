# Supervisor Job: The Floor — a local, read-only, event-driven view of the run

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — modified 2026-09-03; the "Latest change" paragraph describes the v15.43.0 projector this brief extends)
- **Git:** clean (0 files), branch: main @ 7827614 == origin/main
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 — `git worktree list` shows 6 entries under `.claude/worktrees/` (Claude Code's own isolation worktrees, three detached, none a Supervisor worktree; they do not block a `--sequential` run, which creates no worktrees)
- **Source requirement:** .supervisor/requirements/loom-floor-ui/04-the-floor-ui.md (amended 2026-09-03 at intake — see its `## Depends on` Amendment; the numbers below are copied from it, not re-derived)

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + jq + python3 are already hard dependencies (8 `python3` hook entries in `hooks.json`); the bundle is hand-authored HTML/CSS/JS with no framework, bundler or Node. |
| 2 | Dependency Availability | GO | `python3` 3.9.6 on this machine; `python3 -m http.server --bind 127.0.0.1 --directory <dir>` (both flags since 3.7). `jq` present. `build-floor.sh` takes 0.53 s wall-clock on this repo's 13,145 log lines, so a 2 s regeneration interval is affordable. |
| 3 | Architecture Fit | CAUTION | First non-shell surface in the plugin. `loomwright/scripts/*` is CORE-classified by `loomwright/docs/vendor-coupling-manifest.json` and `.claude/` is a vendor token, so every file that must name `~/.claude/loomwright/ui` moves the ratchet — expected movers: `loomwright/scripts/setup-ui.sh` (new, CORE), `loomwright/skills/setup/SKILL.md` (COUPLED, allowance 38 today) and `loomwright/docs/FLOOR_UI.md` (new, COUPLED); `commands/setup.md` is ADAPTER and uncounted. Allowances are measured with `--print-allowances` after staging and declared in the same PR (the `setup-statusline.sh` precedent from PR #172). The bundle and the tests name no token. |
| 4 | Scope vs Supervisor Capability | CAUTION | 27 unique files touched (7 + 9 + 12, minus `test-setup-ui.sh` counted in both 2 and 3; > 12) ⇒ `context-bound` split into 3 strictly sequential subtasks. The v15.42.0 status-line worker hit its 40-turn limit on an 18-lane single subtask; splitting is the mitigation, plus SendMessage-resume rather than respawn. |
| 5 | Hard Blockers | CAUTION | Identity data is PARTIAL by measurement (requirement Amendment 2026-09-03): no spawn event exists; `agent_type` is present on 8 of 2,831 events since 2026-09-01 (4 of 20 `agent_id`s in the newest session). Not a blocker because the design degrades honestly (typed lanes coloured, untyped lanes drawn identity-unknown, liveness never inferred), and the requirement's first AC was rewritten at intake to be satisfiable. |

**Overall Verdict:** CAUTION (three findings carried into Risk Assessment)

## Task
**Goal:** Ship `/setup ui`: a `python3 -m http.server`-served, loopback-only static bundle that renders `.supervisor/floor/floor.json` as five pipeline stages above one lane per agent in the newest session, where motion is driven only by recorded events and a lane that stops receiving events visibly stalls — plus the additive projector keys the bundle needs and the release surfaces that make the module real.

**Problem Statement:**
The plugin's operator needs to see what is happening in a run right now, because today a stall is discovered only when a human notices that nothing has happened for a while. Items 01–03 made the truth available (`floor.json` is the single contract) but nothing renders it; `/insights`, `/handoff` and `/obsidian` report history well and the present not at all. Success looks like: `/setup ui` copies a bundle to `~/.claude/loomwright/ui/`, `setup-ui.sh serve` regenerates `floor.json` on an interval and serves it on 127.0.0.1, and the page shows every agent in the newest session with its event count and last-event age, colours the ones whose type is on record, marks a lane stalled when its last event is older than the threshold, and says plainly when there is no run, no file, or a stale file.

## Acceptance Criteria

**Projector (subtask 1)**
- [ ] **AC-roster:** Given the fixture agents directory (3 committed files: one whose `disallowedTools` covers both `Write` and `Edit`, one with no `color:`, one with `model: haiku`), when `build-floor.sh` runs with `FLOOR_AGENTS_DIR` pointed at it, then `surfaces.agents` reports `status: counted`, `count: 3`, and a `detail.roster` array (sorted by name) whose `name` (frontmatter `name:` minus the `loomwright:` prefix), `color`, `model`, `max_turns` and `read_only` equal values the test computes independently from the fixture files — and a field absent from frontmatter is OMITTED from that agent's row, never defaulted. In real runs the directory is `<script dir>/../agents` (resolved from `$0`; no `CLAUDE_PLUGIN_ROOT`, no vendor token); when it is absent the surface is `absent` with a named reason and no `count`. Because that source is a plugin-install path rather than a repo-relative one, the schema block documents `agents.source` as the one exception to "repo-relative".
- [ ] **AC-current-session:** Given the fixture log where the newest `ts` belongs to session S, and S has 3 `agent_id`s of which one carries `agent_type` on an OLDER line than its newest line, when `build-floor.sh` runs, then `surfaces.sessions.detail.current` carries `cc_session_id: S`, `last_event_ts` (the max `ts`), and an `agents` array (sorted by `agent_id`) with `events`, `first_ts`, `last_ts`, `agent_type` (present for exactly that one agent, taken from any of its lines), and `branch` (present only when a line carried it). Lines from other sessions never contribute. When no line carries a `ts`, `current` is omitted with a note — never guessed from file order. Case (n) seeds `floor-sessions-current.jsonl` into its OWN `new_repo`, never into `seed_tree` (the (c2) precedent, comment at `test-build-floor.sh` §"A SEPARATE seeded fixture"): adding it to the shared fixture would re-key `EXP_LOGS`, `EXP_LOG_DIR_ENTRIES`, `EXP_SESSIONS`, `EXP_SESS_LINES` and the "3 jsonl + 5 plain .log" basis assertion at once, and would edit the very file whose drift guard exists to notice that change.
- [ ] **AC-subtask-rows:** Given the existing `state.md` fixture rows, `surfaces.state.detail.subtasks` is an array of `{id, title, status}` objects in table order; a row with no Status column omits `status` (the PR #173 omit-not-guess rule), and the existing `count` is unchanged.
- [ ] **AC-suite-hermetic:** `test-build-floor.sh`'s `seed_tree` copies the three committed fixture agent files into `<fixture>/agents/`, and `run_build` exports `FLOOR_AGENTS_DIR="$1/agents"` for every run, so the EMPTY fixture (`new_repo`, no `agents/`) still yields an `absent` `agents` surface and the ANTI-VACUITY control ("no section on the empty fixture reaches status counted") stays green; `agents` joins `ALL_KEYS` with `EXP_AGENTS=3`; the three `13` literals (the "all N sections" assertions and the anti-vacuity offender count) become 14; and every assertion that inspects the `agents` surface goes through `run_build` — the twelve direct `bash "$BUILD"` call sites (the c2/f2/f3/g/i/k/l/l2 groups) resolve the real-dir default and assert nothing about `agents`. Case (m), the local-only real-tree corroboration, is the one place the default is asserted on: it symlinks the real `loomwright/agents` into `$MIR/agents` so `run_build`'s export still resolves, and adds `cmp_real agents "$(real_n "$HERE"/../agents/*.md)"`. Every existing assertion still passes; the fixed surface list and its count literal extend to the 14th surface. `RESULT_SCHEMAS.md`'s surface-key list and its "two surfaces of the thirteen" wording extend to fourteen.
- [ ] **AC-schema-additive:** The `## FLOOR_PROJECTION` block in `loomwright/docs/RESULT_SCHEMAS.md` documents the new surface key `agents` and the optional `detail` sub-keys `roster:`, `current:`, `subtasks:` as annotated YAML lines marked optional; `schema_version` stays 1; `test-build-floor.sh` case (h) still parses the required-key set out of that block and still rejects each required key by name; the `agents.source` exception line names no vendor token, so `RESULT_SCHEMAS.md`'s allowance does not move; determinism (i), the single wall-clock read (j) and containment (k) pass with the new surface present.
- [ ] **AC-add_surface-defensive:** Given a `detail` argument that is not valid JSON, `add_surface` no longer returns silently: the surface is still emitted (without `detail`) and a note names the key and the reason. Pinned by a test case with a mutation control that reverts the guard and shows the surface vanishing.

**Bundle + engine (subtask 2)**
- [ ] **AC-lanes:** Given the committed fixture `floor-live.json` whose `current.agents` has 3 rows — two typed (`loomwright:loomwright:worker`, `loomwright:loomwright:code-reviewer`) and one untyped — when the page is served and loaded, then it renders exactly 3 lanes: the typed lanes show the roster name and colour for that type (the type is matched after stripping every `loomwright:` prefix), the untyped lane is drawn with the neutral dashed treatment and the visible text "identity unknown", and each lane's event count and last-event age match the fixture. **Static half (CI):** `test-setup-ui.sh` asserts `floor.js` contains the literal strings `identity unknown` and `events`, the prefix-stripping expression, and `cache: 'no-store'`, and that `floor-live.json` has exactly 3 `current.agents` rows of which exactly 2 carry `agent_type`. **Browser half (Phase 4.5):** the Supervisor loads the served fixture in a browser, reads the DOM (not a screenshot), and records each value in a `## Browser verification` block in the PR body, one line per browser-verified AC with the DOM values read. On a non-interactive run these browser halves are recorded as UNVERIFIED, never as passed.
- [ ] **AC-stall:** Given `floor-stalled.json`, where one agent's `last_ts` is older than the stall threshold (default 300 s, overridable with `?stall=<seconds>`) relative to `generated_at_epoch`, when the page loads, then that lane carries the `stalled` class, its pulse is absent, and its label reads "no event for <age>"; the other lanes do not. Between two polls in which a lane's `events` count rose, its shuttle advances; a lane whose count did not change does not move. Nothing on the page animates on a timer alone, with ONE stated exemption: the `.pulse` keyframe on a non-stalled lane, which is gated by stall state (its absence is the stall signal, per the requirement's Scope §5) and is therefore state-driven even though a keyframe drives its frames. The static occurrence-count check and the browser half both apply that exemption and no other. **Static half:** `test-setup-ui.sh` asserts `floor.js` contains the class token `stalled`, the literal `no event for`, the `stall` query-parameter read, and NO `setInterval`/`requestAnimationFrame` call other than the single poll timer (asserted by counting occurrences); and that `floor-stalled.json` has exactly one agent whose `last_ts` is more than 300 s before `generated_at_epoch`. **Browser half:** as in AC-lanes.
- [ ] **AC-three-states:** Given (a) no `floor.json` (HTTP 404), (b) `floor-empty.json` — `agents` counted (it comes from frontmatter on every real run) but `state` absent AND `sessions.detail.current` omitted, which is the definition of "no run in flight" — and (c) `floor-stale.json`, whose `generated_at_epoch` is older than the freshness threshold (default 3× the poll interval), when the page loads, then each renders a distinct, prominent state text — "no floor.json at this origin", "no run in flight", and "floor.json is stale (<age>)" respectively — never a blank page, a spinner, or a console error. **Static half:** the three strings are asserted in `floor.js`, and `floor-empty.json` is asserted to have `agents.status == counted` with `state.status == absent` and no `sessions.detail.current`. **Browser half:** the three renders, with the console read for errors.
- [ ] **AC-fixtures-conform:** every `loomwright/scripts/fixtures/floor-ui/*.json` validates against the same schema-derived rules `test-build-floor.sh` case (h) applies — required top-level keys parsed out of the `## FLOOR_PROJECTION` block, `schema_version == 1`, every surface carrying `source`/`basis`/`status`, and `count` present ⇔ `status == counted` — so a fixture cannot drift from the contract silently.
- [ ] **AC-no-egress:** `index.html` carries `<meta http-equiv="Content-Security-Policy" content="default-src 'self'; img-src 'self' data:; connect-src 'self'; style-src 'self'; script-src 'self'; font-src 'self'">` and `floor.js` fetches only the relative path `floor.json`. `test-setup-ui.sh` scans the three bundle files and fails on any `http://`, `https://`, protocol-relative `//` inside a `src`/`href`/`url(`, `@import`, `<link rel="preconnect"`, or `url(` that is not `data:`. At Phase 4.5 the browser's network log of a real page load shows requests to the served origin only. No web font: system font stacks only.
- [ ] **AC-loopback:** `setup-ui.sh serve` always passes `--bind 127.0.0.1`. `test-setup-ui.sh` starts `serve --no-regen --port <free port> --ui-dir <fixture dir>` in the background, asserts `curl -s http://127.0.0.1:<port>/floor.json` returns the fixture bytes, then attempts a TCP connect to the host's first non-loopback IPv4 on the same port (python3 socket, 2 s timeout) and asserts it is refused; when no non-loopback address exists the test prints `SKIPPED — no non-loopback address` and reports it separately from passes. The server is stopped by pidfile in a trap.
- [ ] **AC-motion-a11y-theme:** `floor.css` has a `@media (prefers-reduced-motion: reduce)` block that removes every `animation` and `transition` while leaving state classes rendered; the light palette is defined on bare `:root`, dark on `@media (prefers-color-scheme: dark) { :root:not([data-theme="light"]) }` and again on `:root[data-theme="dark"]`; `body` has an explicit token background. Every state is distinguishable without colour: stalled = dashed lane border + text; read-only agent = hollow dot + the text "read-only"; identity-unknown = dashed chip + text; stale/absent/empty = text banners. Static greps in `test-setup-ui.sh`; both themes and reduced-motion rendering browser-verified at Phase 4.5.
- [ ] **AC-engine-contract:** `setup-ui.sh` implements `check` / `apply` / `serve` / `stop` / `remove`, always exits 0 ("fails closed" = refuse-to-write + a named-reason headline, the `setup-statusline.sh` convention), and accepts `--ui-dir <dir>` (default `$HOME/.claude/loomwright/ui`) so every test runs in `mktemp -d`. `apply` copies the three bundle files from `<script dir>/floor-ui/` and writes the marker `.loomwright-ui-module`; a second `apply` reports `apply: no-op — already configured` when bytes match and `apply: updated` (with the changed file names) when the plugin bundle changed. `serve` (foreground; `--detach` writes `<ui dir>/serve.pid`) runs `build-floor.sh` every `--interval` seconds (default 2, minimum 1) from the current project root unless `--no-regen`, copies `.supervisor/floor/floor.json` into the ui dir, and runs `python3 -m http.server --bind 127.0.0.1 --directory <ui dir> <port>`; `--port` defaults to 7734 and a busy port is reported, never silently changed. `stop` kills only a pid whose command line names `http.server` or `setup-ui.sh`. `remove` deletes the ui dir ONLY when the marker is present (a directory without it is reported and preserved) and never touches the plugin install dir. The engine never writes under `.supervisor/` except through `build-floor.sh`, never writes `~/.claude/settings.json`, and never runs a history-touching git command.
- [ ] **AC-remove-residue:** The sequence `apply`, `serve --detach`, `stop`, `remove` is run with `--ui-dir` inside a fixture parent AND with the working directory set to a fixture git repo (`new_repo`-style, so the one out-of-ui-dir write the engine makes — `build-floor.sh`'s `.supervisor/floor/floor.json` — lands in the fixture repo, not the checkout). Afterwards the fixture parent contains nothing that was not there before, the fixture repo's tree differs from before ONLY by `.supervisor/floor/floor.json` (both hashed with `find`, before and after — the assertion's scope is those two trees, stated explicitly), and `sha256` of every file under `loomwright/scripts/floor-ui/` is identical before and after the whole sequence.
- [ ] **AC-engine-fail-safe:** With `python3` absent from `PATH` (PATH stub), `serve` prints `serve: ABORTED — python3 not found` and exits 0; with `jq` absent, `apply` still copies (the bundle needs no jq) but `serve` reports that `build-floor.sh` will skip; with `build-floor.sh` missing, `serve` prints a named reason and exits 0.

**Release surface (subtask 3)**
- [ ] **AC-module-registered:** `loomwright/skills/setup/SKILL.md` gains a `ui` row in the Pattern 2 registry (check probes: ui dir + marker + bundle hash vs plugin bundle; apply writes: the ui dir only), bumps `version` 1.3.0 → 1.4.0 and `lastUpdated`, and its Pattern 1 offer-row bucket restatement "(observability · statusline, via ONE nested…)" adds `ui`; `loomwright/skills/SKILLS_INDEX.md`'s Setup row carries 1.4.0. `commands/setup.md` gains a `## Module: ui` flow (Check / Report / Offer / Apply / Verify / Subflow remove, mirroring the statusline flow's headline-status relay), adds `ui` to the module list and to the "Claude Code surfaces" nested question (still ≤ 4 options — the dashboard set stays FIXED at four) with these four bucket edits enumerated: option 1's description is reworded from "the two modules that write the user-scope settings file" to "the modules that write under your Claude Code config directory"; the bundled-status render recipe gains `ui: <status>`; the "a tenth module folds into…" sentence becomes "an eleventh"; and a `ui` line is added to `## Constraints`. The "9 modules" phrasing in that skill, `commands/setup.md` and `commands/agent-help.md` becomes 10. **Gate:** because `check-command-sync.sh` guards only `commands/code-reviewer.md` and `check-doc-currency.sh` derives no module count, subtask 3 appends a release-surface parity group to `test-setup-ui.sh` asserting: a `` `ui` `` row in the Pattern 2 table, a `## Module: ui` heading in `commands/setup.md`, `ui:` in the bundled-status recipe, and zero `9 modules` residue across the three files. `scripts/check-command-sync.sh`, `scripts/check-skills-index-sync.sh` and `scripts/check-doc-currency.sh` all exit 0.
- [ ] **AC-doc:** `loomwright/docs/FLOOR_UI.md` (the `OBSERVABILITY.md` companion pattern) documents the bundle, the serve loop, the identity limits copied from the requirement Amendment (partial `agent_type`, no liveness, event counts not turns), the loopback-only posture, the local-only contents of `floor.json` (branch names, session ids, agent ids), and the remove path. README's `/setup` mentions (the "Optional integrations" paragraph and the Setup command row) name `ui`; the README banner gains the dated "NEW in" entry.
- [ ] **AC-version-lockstep:** `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` go 15.43.0 → 15.44.0 with the `vX.Y.Z` in each `description` updated IN PLACE (no appended clause); `CHANGELOG.md` gains the top entry; `CLAUDE.md`'s "Latest change" paragraph is replaced with a version-free, count-free summary of this release (the previous paragraph is not kept — the changelog holds history). Counts stay 14 agents / 21 commands / 41 skills / 24 hooks and no token-budget entry is added (no new agent).
- [ ] **AC-ratchet-measured:** `bash scripts/check-vendor-coupling.sh --print-allowances` is run after `git add` of every new file, the delta versus the current manifest is recorded in the CHANGELOG entry whatever it is, and `loomwright/docs/vendor-coupling-manifest.json` declares the measured allowance for every path that moved (expected: `loomwright/scripts/setup-ui.sh`, `loomwright/skills/setup/SKILL.md`, `loomwright/docs/FLOOR_UI.md`) — never hand-typed, never adapter-exempted; the manifest's `allowances_note` addition DESCRIBES the token rather than quoting it (the self-raise trap that note already records). `bash scripts/check-vendor-coupling.sh` exits 0.
- [ ] **AC-suite-green:** every `loomwright/scripts/test-*.sh` exits 0 locally (the CI hard-gate loop), and `scripts/check-contract-parity.sh` exits 0 (`test-citation-drift.sh` lives under `loomwright/scripts/` and is already covered by the suite loop).

## Outcomes Rubric

- A run's live state is visible at a glance, and a stall is visible **without** being
  looked for.
- Motion encodes progress; nothing animates that is not backed by an event.
- Absent, stale and empty are all rendered honestly and distinctly.
- Zero new runtime dependencies; loopback only; nothing leaves the machine.
- The plugin's release surfaces and the coupling ratchet are left consistent and measured.

*Grader guidance — the Supervisor passes these readings to the Rubric Grader ALONGSIDE the extracted `rubric_bullets`, since the grader receives the bullets as a numbered list and prose in this section would otherwise never reach it. (Prose, not rubric items — the five bullets above are the requirement's own yardstick, copied verbatim as the loop directs, and these are the diff-observable readings of each):* bullet 1 = `floor.js` adds the `stalled` class when `generated_at_epoch - last_ts` exceeds the threshold and `floor.css` renders `.stalled` with a dashed border and the "no event for" text, with the lanes rendered on the page's first screen; bullet 2 = `floor.js` has exactly one timer (the poll) and moves a shuttle only when a lane's `events` count changed between renders, and `floor.css` animates nothing outside `.pulse` on non-stalled lanes; bullet 3 = the three literal state strings exist in `floor.js`, are asserted by `test-setup-ui.sh`, and `floor-empty.json`/`floor-stale.json` are committed; bullet 4 = the CSP meta line, `--bind 127.0.0.1`, no `http`/`https`/`//`/`@import` in the bundle, and no new package/CDN reference anywhere in the diff; bullet 5 = the version, counts and the "9 modules" → 10 phrasing agree across every touched surface, and the manifest diff contains only measured numbers with the delta stated in the CHANGELOG. The rubric score is advisory and never gates.)*

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Projector: additive `agents` roster, newest-session agent rows, subtask rows, hermetic suite extension, `add_surface` guard | AC-roster, AC-current-session, AC-subtask-rows, AC-suite-hermetic, AC-schema-additive, AC-add_surface-defensive | 3 modify, 4 create | `skills/quality-checklist/SKILL.md`, `skills/state-management/SKILL.md` | LAUNCHABLE |
| 2 | The floor bundle + `setup-ui.sh` engine + static tests + fixtures | AC-lanes, AC-stall, AC-three-states, AC-fixtures-conform, AC-no-egress, AC-loopback, AC-motion-a11y-theme, AC-engine-contract, AC-remove-residue, AC-engine-fail-safe | 0 modify, 9 create | `skills/quality-checklist/SKILL.md`, `skills/setup/SKILL.md`, `skills/frontend-ui/SKILL.md` (accessibility rules ONLY — see Skill References) | BLOCKED (by #1) |
| 3 | Release surface: `/setup ui` registration, docs, version lockstep, measured ratchet, parity test group | AC-module-registered, AC-doc, AC-version-lockstep, AC-ratchet-measured, AC-suite-green | 11 modify, 1 create | `skills/setup/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #2) |

### Subtask 1 — Projector extension (LAUNCHABLE)

Files (all verified to exist unless marked create):
- modify `loomwright/scripts/build-floor.sh` — add: an `agents` surface (`FLOOR_AGENTS_DIR` env override, default `"$(cd "$(dirname "$0")/.." && pwd)/agents"`; frontmatter parsed with awk between the first two `---` lines: `name:`, `color:`, `model:`, `maxTurns:`, `disallowedTools:`; `read_only` = true iff that list contains both `Write` and `Edit` as whole tokens; every field omitted when absent); `sessions.detail.current` (newest `ts` across all classified lines picks the session; per-`agent_id` aggregation via ONE jq pass over the already-collected lines — no second `cat`); `state.detail.subtasks` rows from the same awk that counts them; the `add_surface` guard. Keep `set -uo pipefail`, no `set -e`, exit 0 always, the single `date` read, `LC_ALL=C` sorting, `jq -S` output, and every `${arr[@]+"${arr[@]}"}` form (bash 3.2 empty-array trap).
- modify `loomwright/scripts/test-build-floor.sh` — `seed_tree` copies the committed fixture agents into `<fixture>/agents/`; `run_build` exports `FLOOR_AGENTS_DIR="$1/agents"`; `agents` joins `ALL_KEYS`, `EXP_AGENTS=3`, the three `13` literals become 14; new cases (m) roster, (n) current session, (o) subtask rows, (p) `add_surface` guard + mutation control; every existing assertion keeps passing.
- modify `loomwright/docs/RESULT_SCHEMAS.md` — `## FLOOR_PROJECTION` block: add `agents` to the surface-key list, document the optional `roster:` / `current:` / `subtasks:` detail lines, document the `agents.source` plugin-path exception (worded to DESCRIBE the plugin install directory, never quoting a vendor token — `RESULT_SCHEMAS.md` is COUPLED with allowance 3 and is not among the three pre-named ratchet movers), and change "two surfaces of the thirteen" to fourteen. Also de-stale the two "nine surfaces / nine parsers" phrasings that a fourteenth input falsifies: `RESULT_SCHEMAS.md`'s `## FLOOR_PROJECTION` lead paragraph, and `build-floor.sh`'s own header comment (its `WHY:` paragraph). The v15.43.0 CHANGELOG-history entry in the same file is a dated historical snapshot and is NOT touched. Keep every existing required marker so case (h) keeps parsing.
- create `loomwright/scripts/fixtures/floor-agents/alpha.md`, `.../beta.md`, `.../gamma.md` (3 synthetic agent files — NOT copies of real agents) and `loomwright/scripts/fixtures/floor-sessions-current.jsonl` (2 sessions, 3 agents in the newest, one typed on a non-newest line, one line without `ts`).

```yaml
# Subtask 1 — projector extension (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "agents_basis"}
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "sess_current"}
  - {kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "subtasks_rows"}
  - {kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "roster:"}
  - {kind: "symbol", path: "loomwright/scripts/test-build-floor.sh", name: "EXP_AGENTS"}
  - {kind: "file", path: "loomwright/scripts/fixtures/floor-agents/alpha.md"}
  - {kind: "file", path: "loomwright/scripts/fixtures/floor-sessions-current.jsonl"}
requires: []
lanes:
  - "loomwright/scripts/build-floor.sh"
  - "loomwright/scripts/test-build-floor.sh"
  - "loomwright/docs/RESULT_SCHEMAS.md"
  - "loomwright/scripts/fixtures/floor-agents/*"
  - "loomwright/scripts/fixtures/floor-sessions-current.jsonl"
external_requires: []
```

### Subtask 2 — Bundle + engine (BLOCKED by #1)

Files (all create):
- `loomwright/scripts/floor-ui/index.html`, `loomwright/scripts/floor-ui/floor.css`, `loomwright/scripts/floor-ui/floor.js` — the bundle. Layout per the design reference (five stages Queue · Plan · Execute · Review · Shipped above one lane per agent, a roster strip, a notes strip that prints `floor.json`'s `notes[]` verbatim). Stage cells: Queue = `jobs_pending.count`, Plan/Execute/Review = highlighted by `state.detail.phase` (PLAN|ACQUIRE|INIT → Plan; EXECUTE → Execute; FINALIZE|SELF_HEAL → Review), Shipped = `jobs_done.count`; a surface without `count` renders "—" with its `reason` as the cell's `title`, never 0. Poll `floor.json` every 2 s with `cache: 'no-store'`; re-render only on a changed `generated_at_epoch`; compute ages from the record timestamps against `generated_at_epoch`, and page staleness from `generated_at_epoch` against `Date.now()`. No timer-driven motion anywhere: the ONLY animated element is a lane's shuttle transition when its `events` count changed since the previous render, and the pulse is present only on non-stalled lanes. Lane order: `last_ts` descending. Lane label: `<agent name or "identity unknown"> · <events> events · last <age>`; stalled lanes: `no event for <age>`. The roster strip lists every `agents.detail.roster` row with colour swatch, `model`, `maxTurns` as "budget", and "read-only" text + hollow swatch when `read_only`. A permanent one-line note under the lanes: "liveness unavailable — a lane shows recorded events, never a running process".
- `loomwright/scripts/setup-ui.sh` — the engine (contract in AC-engine-contract; header comment in the `setup-statusline.sh` style stating exactly what it writes: the ui dir and, through `build-floor.sh`, `.supervisor/floor/floor.json`). Its `remove` deletes with `rm -r --` after asserting the marker and that the path equals the resolved ui dir.
- `loomwright/scripts/test-setup-ui.sh` — static cases: bundle scan (AC-no-egress), CSS/JS greps (AC-motion-a11y-theme, AC-three-states strings, AC-lanes and AC-stall static halves), fixture conformance (AC-fixtures-conform, reusing the `## FLOOR_PROJECTION` required-key parse the way `test-build-floor.sh` (h) does), engine check/apply/updated/no-op/remove/refuse-foreign/fail-safe, loopback (AC-loopback, with the SKIPPED path), residue (AC-remove-residue, two hashed trees). Exit 0/1/2 convention, no `producer | grep -q` pipelines, `LC_ALL=C`. Leaves an explicit `# (z) release-surface parity — appended by subtask 3` anchor comment at the end.
- `loomwright/scripts/fixtures/floor-ui/floor-live.json`, `floor-stalled.json`, `floor-empty.json`, `floor-stale.json` — hand-authored against the extended schema (3 agents: two typed, one untyped; `floor-empty.json` keeps `agents` counted).

```yaml
# Subtask 2 — bundle + engine (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/scripts/floor-ui/index.html"}
  - {kind: "file", path: "loomwright/scripts/floor-ui/floor.css"}
  - {kind: "file", path: "loomwright/scripts/floor-ui/floor.js"}
  - {kind: "file", path: "loomwright/scripts/setup-ui.sh"}
  - {kind: "file", path: "loomwright/scripts/test-setup-ui.sh"}
  - {kind: "file", path: "loomwright/scripts/fixtures/floor-ui/floor-live.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/floor-ui/floor-stalled.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/floor-ui/floor-empty.json"}
  - {kind: "file", path: "loomwright/scripts/fixtures/floor-ui/floor-stale.json"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/docs/RESULT_SCHEMAS.md", name: "roster:"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/build-floor.sh", name: "sess_current"}
lanes:
  - "loomwright/scripts/floor-ui/*"
  - "loomwright/scripts/setup-ui.sh"
  - "loomwright/scripts/test-setup-ui.sh"
  - "loomwright/scripts/fixtures/floor-ui/*"
external_requires:
  - "python3 >= 3.7 (http.server --bind/--directory) at runtime; absent in tests via PATH stub"
```

### Subtask 3 — Release surface (BLOCKED by #2)

Files:
- modify `loomwright/skills/setup/SKILL.md` (registry row, Pattern 1 bucket restatement, version 1.4.0, "9 modules" → 10), `loomwright/skills/SKILLS_INDEX.md` (Setup row 1.4.0 + date), `loomwright/commands/setup.md` (module list, nested question + the four enumerated bucket edits, `## Module: ui` flow, Constraints line, "9 modules" → 10), `loomwright/commands/agent-help.md` (`/setup` purpose paragraph: 9 → 10 modules, one `ui` clause), `README.md` (banner entry + two `/setup` mentions), `CLAUDE.md` (Latest-change paragraph, version-free), `CHANGELOG.md` (top entry incl. the measured ratchet delta), `loomwright/.claude-plugin/plugin.json` + `.claude-plugin/marketplace.json` (15.44.0, description in place), `loomwright/docs/vendor-coupling-manifest.json` (measured allowances), `loomwright/scripts/test-setup-ui.sh` (append the `(z)` release-surface parity group at the anchor subtask 2 left — a legal sequential share: 3 requires 2, and after editing, subtask 3 re-runs the whole file to confirm subtask 2's groups still pass).
- create `loomwright/docs/FLOOR_UI.md`.

```yaml
# Subtask 3 — release surface (BLOCKED by #2)
provides:
  - {kind: "file", path: "loomwright/docs/FLOOR_UI.md"}
  - {kind: "symbol", path: "loomwright/skills/setup/SKILL.md", name: "setup-ui.sh"}
  - {kind: "symbol", path: "loomwright/commands/setup.md", name: "setup-ui.sh"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.44.0"}
  - {kind: "symbol", path: "loomwright/docs/vendor-coupling-manifest.json", name: "setup-ui.sh"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-ui.sh", name: "release-surface parity"}
requires:
  - {from: "2", kind: "file", path: "loomwright/scripts/setup-ui.sh"}
  - {from: "2", kind: "file", path: "loomwright/scripts/floor-ui/index.html"}
  - {from: "2", kind: "file", path: "loomwright/scripts/test-setup-ui.sh"}
lanes:
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/skills/SKILLS_INDEX.md"
  - "loomwright/commands/setup.md"
  - "loomwright/commands/agent-help.md"
  - "README.md"
  - "CLAUDE.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/FLOOR_UI.md"
  - "loomwright/scripts/test-setup-ui.sh"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 3
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (2 only READS the keys 1 emits) | YES (requires) |
| Subtask 2 | Subtask 3 | `loomwright/scripts/test-setup-ui.sh` (3 appends one group; legal — 3 is reachable from 2 in the requires DAG) | YES (requires) |
| Subtask 1 | Subtask 3 | none | YES (transitive) |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after 1)
- **Batch 3:** Subtask 3 (after 2)
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/state-management/SKILL.md` |
| 2 | `skills/quality-checklist/SKILL.md`, `skills/setup/SKILL.md`; `skills/frontend-ui/SKILL.md` for its **accessibility rules only** (WCAG contrast, keyboard reachability, non-colour state cues) — its "design-system components over raw HTML" and typed-props rules do NOT apply: this bundle is framework-free by requirement and must add no dependency |
| 3 | `skills/setup/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Identity is partial: `agent_type` on 8 of 2,831 recent events, no spawn event (source: requirement Amendment 2026-09-03; Feasibility (Phase 2.5) check 5) | HIGH | The bundle NEVER infers identity or liveness: untyped lanes are identity-unknown by design (AC-lanes), the permanent "liveness unavailable" note is rendered, and the roster is complete because it comes from frontmatter. The requirement's first AC was rewritten at intake so the brief does not promise "active agents". |
| The `agents` surface breaks the hermetic suite: `run_build` executes the real script from a fixture cwd, so a real-dir default would count the real 14 agents on the EMPTY fixture and turn the anti-vacuity control red (found at Plan Review) | HIGH | AC-suite-hermetic: `seed_tree` seeds `<fixture>/agents/`, `run_build` exports `FLOOR_AGENTS_DIR="$1/agents"` on every run, case (m) symlinks the real agents dir into its mirror, and the twelve direct `bash "$BUILD"` call sites assert nothing about `agents`. |
| The vendor-coupling ratchet moves — every file naming `~/.claude/loomwright/ui` counts, and three are expected to move: `setup-ui.sh` (new CORE), `skills/setup/SKILL.md` (COUPLED, 38 today), `docs/FLOOR_UI.md` (new COUPLED) (Feasibility (Phase 2.5) check 3) | MEDIUM | Subtask 3 stages every new file, runs `--print-allowances`, declares the MEASURED allowance for each mover (AC-ratchet-measured), describes rather than quotes the token in the manifest note, and records the delta in the CHANGELOG. The bundle and the tests use no token (tests pass `--ui-dir`). |
| Worker turn limit (40) on subtask 2, the largest (Feasibility (Phase 2.5) check 4) | MEDIUM | Three sequential subtasks; if a worker stalls at its limit, RESUME it via SendMessage rather than respawning (project memory: subagents hit turn limit). |
| The worker's `SubagentStop` destructive-command tripwire rejects run output containing `rm -rf` | MEDIUM | `remove` deletes with `rm -r --` after asserting the marker file and that the path equals the resolved ui dir; workers must not print the literal `rm -rf` in their result summary. |
| Module-registry ↔ flow ↔ count phrasing has no CI gate (`check-command-sync.sh` guards one file; `check-doc-currency.sh` derives no module count) | MEDIUM | AC-module-registered enumerates every mandated edit and subtask 3 appends the `(z)` parity group to `test-setup-ui.sh`, which the CI suite loop runs. |
| `python3 -m http.server` serves the whole ui dir | LOW | The ui dir holds only the three bundle files, the marker, an optional pidfile and the `floor.json` copy; it is bound to 127.0.0.1 only (AC-loopback). `floor.json` carries branch names, session ids and agent ids — local-only by construction, stated in `FLOOR_UI.md`. |
| Browser caches `floor.json` and the page never refreshes | LOW | `fetch('floor.json', {cache: 'no-store'})`; re-render keyed on `generated_at_epoch`. |
| `state.md` has read `status: running` since 2026-07-29, so "phase" may be stale on a real machine | LOW | The page shows the state surface's `mtime_epoch` age beside the phase and never labels a run "live"; staleness of the file itself is the AC-three-states stale banner. |
| Regeneration loop cost (0.53 s per run on 13k log lines) | LOW | Minimum interval 1 s, default 2 s; the loop runs `build-floor.sh` synchronously so overlapping runs cannot occur; documented in `FLOOR_UI.md`. |
| Browser-verified ACs cannot run in CI | LOW | Each such AC now has a static half CI runs and a browser half with a stated record shape (`## Browser verification` in the PR body); the fixtures are committed and schema-validated so the browser pass is repeatable; on a non-interactive run the browser halves are recorded UNVERIFIED, never passed. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-03-the-floor-ui.md
```

---

## Outcome

- **Status:** completed (PR open, awaiting the owner's merge — safe mode never merges)
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/176 (head `d9d71e9`, base `main`, 11 commits)
- **Heal loop ran:** true | **heal_decision:** PASS | **heal_iterations:** 2 (Phase 4.5) + 3 further CI drain rounds
- **Rubric:** 5/5
- **Suites at park:** `test-setup-ui.sh` 119/0/0, `test-build-floor.sh` 265/0/0; all six repo gates rc=0; 69-script CI loop green
- **Until-mergeable dispatched:** false (the engine owned ONE inline drain; an exact-URL grep finds no `.supervisor/review-dispatch/` marker for this PR, and `auto_review` was restored byte-faithfully to absent with the backup sidecar deleted)
- **Required checks:** `ci` PASS. `claude-review` is not required and is red because its own "assert a review was posted" guard fires when the reviewer posts nothing (30/36 denials, then 8 turns/0 denials, then 11 turns/7 denials). It posted three real reviews in between, all addressed.

### What the review rounds actually caught

Two findings of the same class, in two different places, both of which the feature exists to prevent:

1. **Phase 4.5, HIGH** — the page rendered the flat claim `no run in flight` whenever it drew zero lanes, including when the projector had explicitly refused to identify a session and recorded why. Reproduced in a browser against the real projector's output shape before the fix.
2. **CI round 3** — `PHASE_STAGE` mapped six of the seven legal `phase` values, so a run in `LOOP` rendered three em dashes: a *recorded* phase displayed identically to no phase at all. Fixed without inventing a stage mapping, since that would be the guess this page refuses.

One measured number (the vendor-coupling allowance for `setup-ui.sh`) was corrected on **four** surfaces — the manifest, its own note, the PR body, and the CHANGELOG — each time by a reviewer rather than by a sweep, because no gate covers a PR body or a changelog entry.

### Deliberately not done

- The `SKILLS_INDEX.md` token-estimate column was left stale. It has no defined basis, no gate reads it, and existing values are not a function of size, so typing a plausible number in would be the exact failure this run spent four commits correcting. Giving that column a definition and a generator is its own change across all 41 rows.
- `claude-review`'s guard conflates "reviewed, nothing to add" with "never reviewed". Fixing it means editing a workflow file, which makes the action skip itself — so it belongs in a separate, non-workflow-adjacent PR.
