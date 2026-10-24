# Supervisor Job: Native overlap map (2b/2d evidenced entries, 2c/2e KEEP verdicts) and a capability-scan reminder on every minor/major bump

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-22-123646/L4
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1
- **Source requirement:** .supervisor/requirements/twin-remediation/09b-overlap-map-and-scan-cadence.md
- **Base commit:** 7b7cb08392ce372c66c0694db7ced666fd0cbba9

> **Warning (1):** this checkout is lane `L4` of the `--parallel` wave `automate-2026-10-22-123646`. Sibling lanes run at the same time in their own clones: L1 (`parallel-automate/18b`, `loomwright/scripts/automate-helpers*`, `propose-common.sh`, …), L2 (`automate-followups/39e`, `proc-registry.sh`, dispatch scripts, `test-automate-lanes.d/`, …), L3 (`parallel-automate/07`, `CLAUDE.md`, `README.md`, `loomwright/docs/PITFALLS.md`, its evidence file and fragment). None intersects this item's File Impact Map. Stay inside this brief's `lanes:`. This PR carries a `changelog.d/` fragment and NO version bump (lane PRs never bump; the bump is the wave branch's last commit).

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Markdown doc, one JSON `_comment`/entry edit, a bash 3.2 function + hermetic bash test cases — all existing idioms |
| 2 | Dependency Availability | GO | `jq` is already required by `bump-version.sh` (`command -v jq >/dev/null 2>&1 \|\| die "jq is required"`) |
| 3 | Architecture Fit | CAUTION | The requirement maps 2b to `CORE_CONTRACT.md` §3.3, but §3.3 is *isolate-a-workspace*; the poll loop is §3.2 *run-in-background*. Brief corrects it (2b → §3.2, 2d → §3.3) |
| 4 | Scope vs Supervisor Capability | GO | 8 files, single worker, no split reason fires |
| 5 | Hard Blockers | CAUTION | New doc lands under `loomwright/docs/*` (vendor-coupling class `coupled`, no allowance ⇒ 0); it must carry zero manifest tokens or the ratchet breaches |

**Overall Verdict:** CAUTION

## Task
**Goal:** Commit `loomwright/docs/NATIVE_OVERLAP.md` (evidenced 2b and 2d entries with verdicts, one KEEP line each for 2c and 2e), point the agent-teams skill at it in place of its stale graduation line, and make `scripts/bump-version.sh` print a one-line `/capability-check` reminder on every minor or major bump.

**Problem Statement:**
The plugin maintainer needs the native-vs-ours overlap decisions recorded and a recurring prompt to re-scan the platform, because `/capability-check` last scanned at plugin 15.132.0 and the plugin is now two major versions later with nothing that triggers a scan (the per-release ritual that owned the cadence was abandoned).
Currently the two overlaps with real value — the Execute Manager's hand-rolled poll loop vs native background completion notifications, and Supervisor's own worker worktrees vs native `isolation: worktree` — are undocumented, and the agent-teams skill still carries a 2026-05-10 graduation snapshot. This causes repeated re-analysis and silent staleness.
Success looks like a short committed overlap doc whose every platform claim cites `CAPABILITY_BASELINE.json` or says "unverified", and a reminder line that `bump-version.sh` prints on minor/major bumps (and in `--dry-run`), read live from the baseline.

## Acceptance Criteria

- [ ] **AC1 (overlap doc — 2b).** Given the PR branch, when `loomwright/docs/NATIVE_OVERLAP.md` is read, then it has a `2b` entry for the Execute Manager poll loop ↔ native background execution with completion notification that (a) describes what ours does, citing `agents/execute-manager.md` §"Step 4: Poll Loop" by quoted anchor (e.g. `poll_interval = 2000`) and noting `scripts/supervisor-next-step.sh` leaves that loop alone (its header: `The Execute Manager's own poll loop is its own`); (b) describes the native side ONLY from the `CAPABILITY_BASELINE.json` `known_not_adopted` entry whose `feature` starts `Nested subagents (spawn depth default 3` (quote the feature name); every property the baseline does not state — including whether a completion notification reaches a subagent such as Execute Manager — is marked **unverified**; (c) carries exactly one verdict from `KEEP OURS | ADOPT NATIVE | HYBRID | BLOCKED` with a one-paragraph reason; (d) names the port it maps to as `CORE_CONTRACT.md` §3.2 *run-in-background* (native primitives belong in the Claude adapter, never the core). Expected verdict on the current evidence is KEEP OURS (the baseline records the capability's name only); if the worker's verdict is ADOPT NATIVE or HYBRID, it also writes a follow-up requirement draft under `.supervisor/requirements/proposed/` (gitignored, local only) and the doc names that draft's path. No orchestration behaviour changes.
- [ ] **AC2 (overlap doc — 2d).** Given the same file, then it has a `2d` entry for worker worktrees ↔ `isolation: worktree` with verdict **BLOCKED**, citing (a) the baseline `known_not_adopted` entry `isolation: worktree frontmatter` — quoting its branch-base finding (the native worktree branches from the default branch, not the parent session's HEAD) and the removal of the old blocking hook; (b) `CORE_CONTRACT.md` §3.3 *isolate-a-workspace* (the core creates worktrees itself with `git` and binds none of the harness's isolation features). It names the owner-run, manual empirical re-probe (a session with the plugin reinstalled) as the trigger to revisit.
- [ ] **AC3 (overlap doc — 2c, 2e, cadence).** Given the same file, then it has exactly one KEEP OURS line each for **2c** (Workflow tool / nested spawning) and **2e** (Agent Teams), each with a one-clause reason; it states that the baseline's other 2026-10-12 CANDIDATE entries are untouched and that the Nested-subagents entry is answered by 2b/2c here while staying byte-unchanged in the baseline (no count of the CANDIDATE entries and no quote of their status wording — the baseline owns that list); and it records the scan cadence: `bash scripts/bump-version.sh` prints a reminder on every minor or major bump, read from the baseline's `plugin_version_at_last_scan`, with one honest-limit sentence: the reminder reaches whoever runs the script directly, while a `--parallel` wave's release step (`loomwright/scripts/automate-wave.sh`) captures bump output to a log shown only on failure, so on that path it is not seen (changing `automate-wave.sh` is out of scope; a follow-up if wanted). Every platform claim in the doc cites a baseline entry or says "unverified"; an entry is cited by its `feature` name or, where that name carries a vendor-coupling token, by a distinctive token-free prefix (2e cites "the baseline's Agent Teams entry", never its full parenthesised feature name); the doc restates none of the baseline's lists (pointer, not copy). The doc contains none of the vendor-coupling manifest's `token_classes` tokens (e.g. no `TaskOutput`, `run_in_background`, `SendMessage`, `subagent_type`, `CLAUDE_CODE_`, `CLAUDE_PLUGIN_ROOT`, `.claude/`, `AskUserQuestion`, `SubagentStop`) — reword (e.g. "the background-output poll call") instead; and no bare unpinned `file.ext:<N>` citation.
- [ ] **AC4 (agent-teams skill).** Given the PR branch, when `loomwright/skills/agent-teams/SKILL.md` is read, then the sentence `As of 2026-05-10, **3 of 6** are met.` is gone, replaced by the 2e KEEP OURS verdict and a pointer to `docs/NATIVE_OVERLAP.md`; the replacement text carries no date, no `vX.Y.Z`, no `#NNN`, and no `<slug>/<NN>` reference (`check-prompt-history-refs.sh` patterns); the skill's frontmatter (`version`, `lastUpdated`) is unchanged so `SKILLS_INDEX.md` needs no edit; `bash scripts/check-token-budget.sh` stays OK for `agent-teams` (budget 3231); its vendor-coupling count stays ≤ its allowance (4). `loomwright/docs/prompt-history-refs-baseline.json`'s `loomwright/skills/agent-teams/SKILL.md` entry is lowered to the live count the gate prints (`lower the baseline: … 3 -> 2`), and no other entry changes.
- [ ] **AC5 (baseline record).** Given the PR branch, when `loomwright/docs/CAPABILITY_BASELINE.json` is read, then it is valid JSON; its `_comment` gains one sentence recording the cadence (`scripts/bump-version.sh` prints a `/capability-check` reminder on every minor or major bump, reading `plugin_version_at_last_scan`) and pointing at `docs/NATIVE_OVERLAP.md`; the `Agent Teams (CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS)` entry's `why` no longer restates the removed skill snapshot (`dated 2026-05-10, 3 of 6 met`) and instead points at `docs/NATIVE_OVERLAP.md` §2e; `baseline_date`, `plugin_version_at_last_scan`, `schema_version`, every other `known_not_adopted` entry (the seven CANDIDATEs included) and `product_directions` are byte-unchanged; its vendor-coupling count stays ≤ 10. `loomwright/commands/capability-check.md` is not edited.
- [ ] **AC6 (reminder — minor/major).** Given a `test-bump-version.sh` fixture carrying `loomwright/docs/CAPABILITY_BASELINE.json` with `"plugin_version_at_last_scan": "1.0.0"`, when `bash scripts/bump-version.sh minor` (and separately `major`) runs, then it exits 0, the bump is applied, and its output contains exactly one line containing `capability baseline last scanned at 1.0.0; run /capability-check`.
- [ ] **AC7 (reminder — patch and dry-run).** Given the same fixture, when a patch bump runs (no level, no directive), then the output contains no `capability baseline last scanned` line; when `bash scripts/bump-version.sh minor --dry-run` runs, then it exits 0, writes nothing, and prints the reminder line.
- [ ] **AC8 (reminder — fail-SAFE).** Given each of three fixtures — (i) NO baseline file, (ii) a baseline that is invalid JSON, (iii) a baseline that is valid JSON without an X.Y.Z `plugin_version_at_last_scan` (key absent or non-semver) — when a minor bump runs, then it exits 0, the version files are bumped, and the output contains no `capability baseline` line and no `jq:` error text. All three fixtures are required (each shape is pinned by a different mutation below). `--check` and `--refold` no-op paths never print the reminder.
- [ ] **AC9 (fragment, no bump).** Given the PR diff, then `changelog.d/tr09b-overlap-map-and-scan-cadence.md` exists in the `changelog.d/README.md` format, and `bash scripts/check-version-bump.sh` passes (state "not bumped … fragment(s) pending — legal"); no version file (`loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `loomwright/capabilities.json`) is touched.
- [ ] **AC10 (running-system evidence).** Given the PR branch, when `bash scripts/bump-version.sh --dry-run` and `bash scripts/bump-version.sh minor --dry-run` are run at the repo root, then a committed evidence file `docs/evidence/tr09b-overlap-map-and-scan-cadence.md` contains both commands and their verbatim output — the reminder line with the live baseline's version (`15.132.0`), or, for the default-level run, the reason it did not print (the fragment requests patch) — plus the outputs (summary lines) of `bash scripts/test-bump-version.sh`, `bash scripts/check-doc-currency.sh`, `bash loomwright/scripts/test-citation-drift.sh`, `bash scripts/check-token-budget.sh`, `bash scripts/check-vendor-coupling.sh` and `bash scripts/check-prompt-history-refs.sh`; and the PR body links to it. The evidence file itself carries no vendor-coupling token and no absolute home path.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

> How this brief honors them: the reminder reads `plugin_version_at_last_scan` from the baseline at run time (no second copy of the version); `NATIVE_OVERLAP.md` points at baseline entries by `feature` name instead of restating their lists; AC5 replaces the baseline's restatement of the removed skill snapshot with a pointer in the same change.

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| overlap-doc | `loomwright/docs/CAPABILITY_BASELINE.json`, `loomwright/skills/agent-teams/SKILL.md`, `loomwright/docs/prompt-history-refs-baseline.json` | `loomwright/docs/NATIVE_OVERLAP.md` | HIGH |
| scan-cadence | `scripts/bump-version.sh`, `scripts/test-bump-version.sh` | — | HIGH |
| release + evidence | — | `changelog.d/tr09b-overlap-map-and-scan-cadence.md`, `docs/evidence/tr09b-overlap-map-and-scan-cadence.md` | HIGH |

> **Validator-owned surfaces:** `scripts/check-vendor-coupling.sh` (manifest `loomwright/docs/vendor-coupling-manifest.json`: `loomwright/docs/*` and `loomwright/skills/*` are `coupled`, root `scripts/` falls to `unclassified_default: core`; root `docs/evidence/` is outside the manifest's `scan_roots` (`loomwright`, `scripts`, `.claude-plugin`) and unscanned, so AC10's no-token rule there is a voluntary extra; a scanned path with no allowance may carry 0 tokens — no manifest edit is planned, AC3/AC4/AC5 keep every touched file at or under its allowance); `scripts/check-prompt-history-refs.sh` (scans `loomwright/skills/**`, hence the baseline entry in the map); `scripts/check-token-budget.sh` (`agent-teams` budget); `loomwright/scripts/test-citation-drift.sh` (scans `docs/*.md`); `scripts/check-doc-currency.sh` (none of the touched files is in its `FILES` list; run it anyway). The vendor-coupling gate enumerates `git ls-files` — `git add` the new files before a local run.

## Touched-file invariants

> Grounded at base `7b7cb08392ce372c66c0694db7ced666fd0cbba9`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`scripts/bump-version.sh`** — keep: no `-e` (`set -uo pipefail`), so the reminder must never change an exit status — every failure inside it is `|| return 0` and it is called only after the dry-run output and after the success line `bump-version: bumped $old_ver -> $new_ver`; the exit-code contract in the header (`Exit: 0 bumped / re-folded / nothing to re-fold / check consistent (or dry run printed),`); `--check` stays read-only and prints nothing new (`[ "$mode" = "check" ] && run_check` runs before any reminder site); portability (`Portability: bash 3.2 + BSD userland (macOS) and GNU (CI): no sed -i, no mapfile, temp file + mv.`). reuse: the script's own `level_rank()` (`level_rank() { case "$1" in patch) echo 1 ;; minor) echo 2 ;; major) echo 3 ;; *) echo 0 ;; esac; }`) to test minor-or-major, `semver_ok()` to validate the read version, `jq -r '… // empty' … 2>/dev/null` (the read idiom of `read_wt`), and the `bump-version: ` line prefix every other output line carries; declare the baseline path as a constant beside `CAPS_JSON="loomwright/capabilities.json"`. mirror: `loomwright/scripts/release-refold.sh` extracts the machine line with `sed -n 's/^bump-version: refold-touched: //p'` and otherwise prints `tail -n 1` of the log — the reminder must not begin with `bump-version: refold-touched:` and must not be printed on the `--refold` no-op paths (`--refold: nothing to re-fold`); in a real re-fold the child bump run prints it, before the parent's `refold-touched:` line. `loomwright/scripts/automate-wave.sh` reads the last log line on failure (`grep . "$tmp/bump.log" 2>/dev/null | tail -1`) and, on success, may parse the new version from the log with `sed -n 's/^bump-version: bumped [^ ]* -> \([^ ]*\) .*/\1/p' "$tmp/bump.log" | tail -1` — the reminder must never begin with `bump-version: bumped ` (nor `bump-version: refold-touched:`). The `usage()` sed range (`/^# usage:/,/CI passes a dedicated fetched ref/`) must still delimit the usage block if the header gains a sentence. pinned by: `scripts/test-bump-version.sh` — its `mutate()` inserts before `/^# ---- 2\.\.6/`, and its `mutant` programs match `/^chk\(\) \{/`, `[ "$ignore_pending" -eq 0 ]`, `[ "$W_CAPS" != "$W_VER" ]` and `if [ "$old_ver" != "$BASE_VER" ]; then` — all five literals must survive unchanged; the dry-run pin greps `'1.2.3 -> 1.3.0'`, the caps pin greps `'CHANGELOG.md, capabilities.json, removed fragments'`.
- **`scripts/test-bump-version.sh`** — keep: hermetic (`. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../loomwright/scripts/hermetic-test-env.sh"`, every case in a throwaway repo under `$TMP`); the `RESULT: $pass passed, $fail failed, $skip skipped` summary and exit-1-on-any-fail; bash 3.2 (`Portability: bash 3.2 (macOS /bin/bash) and GNU bash; no sed -i, no mapfile.`). reuse: `make_fixture`, `frag`, `run_bump`, `ver_of`, `check` — add a small helper that writes the fixture baseline (and commits it) rather than editing `make_fixture` (the existing cases must keep running without a baseline, which is itself the missing-baseline shape). fired by: `.github/workflows/ci.yml` names it explicitly (`bash scripts/test-bump-version.sh`) — root `scripts/` tests run only when ci.yml names them; no ci.yml edit is needed.
- **`loomwright/docs/CAPABILITY_BASELINE.json`** — keep: valid JSON with `"schema_version": 1`; the scan pair `"baseline_date": "2026-10-12"` / `"plugin_version_at_last_scan": "15.132.0"` is written only by `/capability-check --update-baseline` (its `_comment`: `Both are bumped together only by a real \`--update-baseline\` adoption scan`); every CANDIDATE entry byte-unchanged. mirror: its consumer `loomwright/commands/capability-check.md` (not edited) and, after this change, `scripts/bump-version.sh`'s reader of `plugin_version_at_last_scan` — the key name must not change. pinned by: `loomwright/docs/vendor-coupling-manifest.json` allowance `"loomwright/docs/CAPABILITY_BASELINE.json": 10`.
- **`loomwright/skills/agent-teams/SKILL.md`** — keep: frontmatter `version: "1.1.0"` / `lastUpdated: "2026-05-10"` unchanged (mirrored by the `SKILLS_INDEX.md` row `| Agent Teams | \`agent-teams/\` | — (reference) | ~800 | 1.1.0 | 2026-05-10 |`, which `scripts/check-skills-index-sync.sh` verifies); the `## Graduation Criteria (Experimental → Stable)` heading and its Met/Unmet lists stay (only the dated status sentence goes; the `**Current status:** 3 of 6 criteria met.` line may be reworded to defer to the verdict). pinned by: `loomwright/docs/prompt-token-budgets.json` `"agent-teams": {"budget": 3231, …}`, `loomwright/docs/prompt-history-refs-baseline.json` `"loomwright/skills/agent-teams/SKILL.md": 3`, vendor-coupling allowance `"loomwright/skills/agent-teams/SKILL.md"` = 4.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `scripts/test-bump-version.sh` — minor (and major) bump prints `capability baseline last scanned at 1.0.0; run /capability-check` | flip `-ge 2 ] \|\| return 0` → `-ge 4 ] \|\| return 0` in `scripts/bump-version.sh` |
| `scripts/test-bump-version.sh` — patch bump prints no `capability baseline last scanned` line | flip `-ge 2 ] \|\| return 0` → `-ge 1 ] \|\| return 0` in `scripts/bump-version.sh` |
| `scripts/test-bump-version.sh` — AC8 (iii) valid JSON without an X.Y.Z key: no `capability baseline` line | flip `semver_ok "$v" \|\| return 0` → `: \|\| return 0` in `scripts/bump-version.sh` |
| `scripts/test-bump-version.sh` — AC8 (i) missing file and (ii) invalid JSON: no `jq:` error text in the output | flip `"$CAP_BASELINE" 2>/dev/null)` → `"$CAP_BASELINE")` in `scripts/bump-version.sh` |
| `scripts/test-bump-version.sh` — AC8 (i) missing baseline: minor bump still exits 0 and bumps | flip `2>/dev/null)" \|\| return 0` → `2>/dev/null)" \|\| exit 1` in `scripts/bump-version.sh` |
| `scripts/test-bump-version.sh` — `minor --dry-run` prints the reminder | delete the `scan_reminder` call in the `--dry-run` block of `scripts/bump-version.sh` (the line after `printf '%s\n' "$entry"`) |

> Implementation shape these rows assume (the worker may restyle, but must keep each mutated literal unique in the file so the row applies to exactly one line): a function `scan_reminder <level>` whose body is `[ "$(level_rank "$1")" -ge 2 ] || return 0`, then `v="$(jq -r '.plugin_version_at_last_scan // empty' "$CAP_BASELINE" 2>/dev/null)" || return 0`, then `semver_ok "$v" || return 0`, then `echo "bump-version: capability baseline last scanned at $v; run /capability-check"`; called once after `printf '%s\n' "$entry"` in the dry-run block and once after the `bumped $old_ver -> $new_ver` line. If the final literals differ, the worker updates this table's literals in the evidence file. Why the fail-SAFE shapes need different mutations: for a missing file or invalid JSON, jq exits non-zero (2 / 5, measured) so the jq-line guard returns first, and `semver_ok` would also reject the empty value — the two guards back each other up, so neither guard's single-line removal can make those shapes print the reminder. What those pins can see is the stderr suppression (removing `2>/dev/null` leaks `jq: error: Could not open file …` / `jq: parse error: …` into the captured output) and the exit status; the `semver_ok` guard alone is observable only through shape (iii), where jq exits 0 with an empty value.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Overlap doc, skill pointer, baseline record, bump reminder + tests, fragment, evidence | all | 5 modify, 3 create | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/docs/NATIVE_OVERLAP.md"}
  - {kind: "symbol", path: "loomwright/docs/NATIVE_OVERLAP.md", name: "2b"}
  - {kind: "symbol", path: "loomwright/docs/NATIVE_OVERLAP.md", name: "2d"}
  - {kind: "symbol", path: "loomwright/skills/agent-teams/SKILL.md", name: "NATIVE_OVERLAP.md"}
  - {kind: "symbol", path: "loomwright/docs/CAPABILITY_BASELINE.json", name: "NATIVE_OVERLAP.md"}
  - {kind: "symbol", path: "scripts/bump-version.sh", name: "scan_reminder"}
  - {kind: "symbol", path: "scripts/test-bump-version.sh", name: "capability baseline last scanned at"}
  - {kind: "file", path: "changelog.d/tr09b-overlap-map-and-scan-cadence.md"}
  - {kind: "file", path: "docs/evidence/tr09b-overlap-map-and-scan-cadence.md"}
requires: []
lanes:
  - "loomwright/docs/NATIVE_OVERLAP.md"
  - "loomwright/docs/CAPABILITY_BASELINE.json"
  - "loomwright/docs/prompt-history-refs-baseline.json"
  - "loomwright/skills/agent-teams/SKILL.md"
  - "scripts/bump-version.sh"
  - "scripts/test-bump-version.sh"
  - "changelog.d/tr09b-overlap-map-and-scan-cadence.md"
  - "docs/evidence/tr09b-overlap-map-and-scan-cadence.md"
external_requires:
  - "jq (already required by scripts/bump-version.sh)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` (AAA-style cases, mutation controls as in the existing suite) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Requirement maps 2b to `CORE_CONTRACT.md` §3.3, which is *isolate-a-workspace* (source: "Feasibility (Phase 2.5)") | MEDIUM | 2b cites §3.2 *run-in-background* (its consuming seams name "Execute Manager Step 3–4 (background workers + poll loop)"); 2d cites §3.3. Say so in one line in the doc so the reader is not surprised |
| New `loomwright/docs/NATIVE_OVERLAP.md` has no vendor-coupling allowance, so any manifest token breaches CI (source: "Feasibility (Phase 2.5)") | MEDIUM | Reword (AC3 lists the tokens); `git add` the file, then run `bash scripts/check-vendor-coupling.sh`. Do not raise an allowance — a reworded doc is the planned path |
| A platform claim written from recollection (read-before-write rule) | MEDIUM | Every native-side sentence cites a baseline `feature` name or says "unverified"; the reviewer checks each against `CAPABILITY_BASELINE.json` |
| The reminder breaking a bump consumer (`release-refold.sh` machine line, `automate-wave.sh` failure tail) | LOW | Prefix `bump-version: capability baseline …`, never `refold-touched:`; printed only on success / dry-run; `--refold` no-op and `--check` paths untouched |
| The reminder is invisible on the `--parallel` wave release path: `automate-wave.sh` runs `(cd "$wt" && bash scripts/bump-version.sh) > "$tmp/bump.log" 2>&1` and surfaces that log only on failure, so a successful minor/major wave bump prints the reminder where nobody reads it | MEDIUM | Out of scope for this lane (no `automate-wave.sh` change); AC3 records it as an honest limit in `NATIVE_OVERLAP.md`'s cadence section; the reminder still reaches a maintainer who runs the script directly or with `--dry-run`. A follow-up can surface it in the wave report |
| The default `--dry-run` on this branch prints no reminder (the fragment requests patch) | LOW | Expected; AC10 records the reason and also runs `minor --dry-run` against the live baseline to show the line |
| History-ref ratchet: replacement text in the skill adds a date or `<slug>/<NN>` ref | LOW | AC4 forbids them; lower the skill's baseline entry to the printed live count |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-22-tr09b-overlap-map-and-scan-cadence.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/683
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** automate engine supplied merge evidence for .supervisor/requirements/twin-remediation/09b-overlap-map-and-scan-cadence.md (https://github.com/vikashruhilgit/loomwright/pull/683) — the engine verified the PR merged against the forge; this reconciler stayed offline
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
