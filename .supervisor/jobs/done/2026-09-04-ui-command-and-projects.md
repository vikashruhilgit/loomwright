# Supervisor Job: `/ui` — a direct command, and one floor for every project

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — 161 lines, latest-change paragraph describes v15.45.0 archive views)
- **Git:** dirty (1 file: `.supervisor/postmortem/results.jsonl`, an untracked-by-intent advisory ledger append), branch: main @ d81e826
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 2 (see Risk Assessment R1, R6)
- **Source requirement:** .supervisor/requirements/loom-floor-ui/06-ui-command-and-projects.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 / BSD-safe engine (`setup-ui.sh`), framework-free bundle (`floor-ui/{index.html,floor.css,floor.js}`), `python3 -m http.server`. No bundler, no package manager. All present on this machine. |
| 2 | Dependency Availability | CAUTION | The registry is JSON, but `setup-ui.sh`'s own header states **"`jq` is NOT a dependency of this script"** (verified at `setup-ui.sh` header §Portability; jq appears only as a *probe* in `do_check` and a *note* in `do_serve`). Registry parsing must therefore either guard on jq with a named reason (exit 0, per the fail-safe contract) or avoid jq entirely. Naming that decision is an explicit obligation of Subtask 1 — see AC-1e and R1. |
| 3 | Architecture Fit | GO | `~/.claude/loomwright/` already exists with an `observability` sibling, so the registry's stated neighbourhood is real (verified on disk). The `/setup` module pattern and the `(z)` release-surface parity precedent both exist. |
| 4 | Scope vs Supervisor Capability | CAUTION | Exceeds the single-agent default: > 12 files and > 800 changed lines across engine, bundle, a new command and the whole doc surface. Split under the named reason `context-bound` into 3 sequential subtasks. |
| 5 | Hard Blockers | GO | None. No new runtime dependency, no migration, no credential. Both declared corpus-task ids (`doc-currency-green`, `version-consistent`) exist under `scripts/eval-corpus/` (verified). |

**Overall Verdict:** CAUTION (proceed; findings 2 and 4 carried into Risk Assessment as R1 and the split reason)

## Task
**Goal:** Add a direct `/ui` command for the floor's operational verbs and a user-scope project registry, so one server on one port can display any registered project, chosen in the page rather than by which directory a terminal was launched in.

**Problem Statement:**
The owner needs the floor reachable directly and able to show more than one project, because the view is currently reachable only the long way and can only ever look at one project. Currently `/setup ui` — a *configuration* command — is the only entry point for `serve` and `stop`, which are daily *operations*; in practice that pushed the owner back to `bash loomwright/scripts/setup-ui.sh serve` in a terminal, which is the exact friction the module existed to remove. Meanwhile the bundle is global but the data is per-directory: `apply` copies the bundle to one user-scope directory and `serve` regenerates `floor.json` from whatever directory it was launched in into that one shared slot, so two projects collide on the slot and only the port guard (which refuses to move the port rather than serve wrong bytes) saves the user today. Per-project isolation exists only as two flags the user must remember to pass. This causes a view that is either not opened or opened against the wrong project. Success looks like: one command starts the floor, a picker in the page switches projects within one poll interval, every project reports its own freshness, and the page still only reads.

## Acceptance Criteria
- [ ] AC-1a Given a fresh install, when `/ui check` runs, then it reports module state and registry state in one report and writes nothing — including when the registry file does not exist, which reports as `no projects registered`, never as an error.
- [ ] AC-1b Given `/ui add` run with no argument inside a project, when it completes, then that project is registered with its absolute path and a slug derived from it; a second run in the same project reports `already registered` and writes nothing. Given `add <path>` where the path does not exist, nothing is written and the reason names the path.
- [ ] AC-1c Given a registry containing three projects, when `/ui list` runs, then each is printed with path, slug and last-regenerated age, any whose path is currently missing marked `unavailable`; `list` never mutates the registry, including when an entry is unavailable.
- [ ] AC-1d Given `/ui forget <slug>`, when it completes, then that entry is removed from the registry and **the project directory itself is untouched** — asserted by hashing the project tree before and after. Given an unregistered slug, nothing is written and the reason says so.
- [ ] AC-1e Given a registry file that is not valid JSON, when any subcommand runs, then it refuses to write, names the reason, preserves the file **byte-for-byte** (asserted by hash), and exits 0 — the engine's existing refuse-to-write-plus-named-reason convention, never a non-zero exit. **The jq decision is explicit:** whichever way Subtask 1 resolves Feasibility finding 2, the chosen posture is stated in `setup-ui.sh`'s header alongside the existing portability paragraph, and the jq-absent path for every registry subcommand is asserted by a test that makes jq unfindable rather than by inspection.
- [ ] AC-1h **Registry tests never touch the developer's real config tree.** `test-setup-ui.sh`'s header states isolation is "LOAD-BEARING AND IS ASSERTED, NOT ASSUMED" and names `--ui-dir` into a `mktemp -d` as the mechanism — but the registry is deliberately a **sibling** of the ui directory (AC-1g's whole rationale) and `setup-ui.sh`'s arg loop sets **only** `UI_DIR`, so `--ui-dir` provably cannot redirect it. Therefore: every registry-touching case MUST run under a fixture `HOME` (the suite's existing precedent — `HOME=<fixture> bash "$ENGINE" …`. **Do not trust a count here:** the brief originally said "3 call sites", the implementing worker reported 6, and a direct measurement against `origin/main` finds **4** such invocations using **3** distinct fixture-HOME variables (`$FHUI`, `$HOMEUI`, `$FAKE_HOME`), out of 7 `HOME=` assignments of any shape. The mechanism is what matters and it is real; find the sites rather than relying on any of these numbers) **or** the engine MUST gain an explicit registry-path override, and `registry_path` MUST honour whichever is chosen. Asserted **two ways, because the hash alone is not sufficient**: (i) a **static** assertion that every registry-touching engine invocation in `test-setup-ui.sh` carries the fixture `HOME` (or the explicit override), grep-asserted, **with a mutation control that strips `HOME=` from one call site and requires the gate to redden** — this is what actually enforces the MUST; and (ii) as a backstop, hashing the real `$HOME/.claude/loomwright` tree before and after the whole suite. **(ii) alone is insufficient and must not be the only assertion:** an add-then-forget sequence — the natural shape of AC-1b plus AC-1d — writes and then restores, so on a machine with no pre-existing `projects.json` the two hashes match and the tree was still touched. The hash **must also be DEFINED for an absent tree** (CI has no `$HOME/.claude/loomwright`), never skipped-when-absent, or it is vacuous exactly where it is cheapest to be. Without this the naive implementation satisfies AC-1a…AC-1g by writing the user's real `projects.json`, and the header's isolation claim becomes false with nothing detecting it.
- [ ] AC-1f Given `/ui scan <dir>`, when it runs, then candidates are listed as a **proposal** and the registry is unchanged until an explicit confirmation; the scan is bounded by a stated maximum depth; a scan finding nothing says so rather than printing an empty success. Asserted with a fixture tree, including that the unconfirmed path writes nothing (hash-asserted).
- [ ] AC-1g Given a module `remove`, when it completes, then the registry is intact — asserted directly, because the registry living outside the ui directory is the whole reason it survives.
- [ ] AC-2a Given two registered projects and `/ui serve`, when the page loads, then one server on one port serves a page whose picker lists both; selecting the second switches the rendered floor to that project's data within one poll interval, and the branch and HEAD shown change with it. Browser-verified against committed fixtures, DOM read, console read for errors.
- [ ] AC-2b Given five registered projects, when `serve` runs, then the selected project regenerates on the configured interval while the others regenerate on the slower cadence, and **the loop never falls behind its own interval** — asserted by measuring elapsed time across a fixed number of ticks against a **stub projector with a known cost**, not by inspection. The requirement's own measured basis is 1.05–1.07 s per real projector run at 13,641 log lines (2026-09-03, after item 05); at ~1.06 s a naive regenerate-everything-every-tick starves a 2 s loop at **two** projects.
- [ ] AC-2c Given a registered project whose directory is deleted while `serve` is running, when the next poll occurs, then that project renders `unavailable` with the reason, the other projects keep rendering, and the server does not exit.
- [ ] AC-2d Given three registered projects of which one path is missing, when the page loads, then it displays each project's label, path, slug and last-regenerated age, marks the missing one `unavailable` with the reason, and shows the module's own state (bundle present, registry readable) — **without issuing any request the static server cannot serve.** Asserted by a browser load against committed fixtures **plus** a static check that the bundle contains no `POST`, no `PUT`, no `DELETE` and no `fetch` with a `method` option.
- [ ] AC-2e Given a registry that is absent or unparseable, when the page loads, then it says **which of the two** it is and still renders the rest of the floor — never a blank page, never a console error.
- [ ] AC-2f Given the page and server as changed, when exercised, then the page still issues zero requests to any origin but its own and the server still binds loopback only — asserted the way item 04 asserts them (a real network log, and a refused connection from a non-loopback address).
- [ ] AC-3a Given `/setup ui`, `/ui` and the engine, when their subcommand sets are compared, then: (i) every verb documented in `commands/setup.md`'s `## Module: ui` flow exists in the engine's real subcommand set, (ii) every verb documented in `commands/ui.md` exists in that same set, and (iii) the **union** of the two documented sets **equals** the engine's real set — so a verb the engine supports but neither file documents FAILS. The engine's set is **parsed out of `setup-ui.sh`'s own dispatch `case`**, never restated in the test. Asserted mechanically with **two mutation controls**, because the obvious one provably does NOT redden: `commands/setup.md:497` already documents all five module verbs (`check`/`apply`/`serve`/`stop`/`remove`), so deleting any of those from `commands/ui.md` leaves the union unchanged and the gate stays green. The controls are therefore: **(c1)** delete a verb documented ONLY in `commands/ui.md` — one of the registry verbs `add`/`list`/`forget`/`scan` — and require red; **(c2)** append a verb to a scratch copy of `setup-ui.sh`'s dispatch `case`, document it nowhere, and require clause (iii) to redden — the engine-side drift, which otherwise has no control at all. **Pin what is parsed:** the dispatch is the `case "$SUBCMD" in` statement (anchor on that literal, NOT on a line number — it was at 493 when this brief was written and subtasks 1 and 2 pushed it to 1190; pin by anchor per CLAUDE.md's citation rule); the file contains 8 `case` statements and parsing the wrong one silently yields a nonsense verb set. Note its `*)` arm restates the verb list in its error text — a second in-file enumeration that can itself drift, so parse the arm labels, not that string. Note the three sets are deliberately NOT equal pairwise — `/setup ui` keeps `apply`/`remove` while `/ui` adds the operational and registry verbs; it is the UNION that must equal the engine. `forget` is deliberately not named `remove`.
- [ ] AC-3b Given the release-surface lockstep, when the change lands, then commands go **21 → 22** with both manifests' version and `description` counts updated **in place**, plus `README.md`, `CLAUDE.md`'s latest-change paragraph, `commands/agent-help.md`, `docs/FLOOR_UI.md`, `skills/setup/SKILL.md` and `CHANGELOG.md` — and `scripts/check-doc-currency.sh` exits 0. **Two distinct test obligations, both required:** the existing `(z)` release-surface parity group is **EXTENDED** (continuing its `(z1)`…`(z9)` numbering) with the `/ui` registration rows — registry row, module flow, bundled-status recipe, and zero stale `21 commands` residue — which are **four separate assertions occupying `(z10)`…`(z13)`**, not one, so a single added row cannot satisfy the gate while dropping three; their count is reported in AC-4's before/after tally — AND the entry-point parity of AC-3a gets its **own new group**, because they gate different things. Extending `(z)` is the requirement's own instruction; do not satisfy one obligation and silently drop the other.
- [ ] AC-3c Given the vendor-coupling ratchet, when measured, then the delta is reported whatever it is — obtained by running `bash scripts/check-vendor-coupling.sh --print-allowances` **after `git add` of every new file**, and the measured values declared. **Never hand-typed.** (`setup-ui.sh` currently declares 3 and `docs/FLOOR_UI.md` 4; both will move.)
- [ ] AC-3d Given `docs/FLOOR_UI.md`'s `## What it writes — the whole list` section, when the change lands, then it names the **served-index write** introduced by Subtask 2 — so that section stays the exhaustive list it claims to be. **Made checkable rather than prose-only:** fold a grep into the `(z)` extension asserting that section (`docs/FLOOR_UI.md:103`) names the served-index filename Subtask 2 introduces, so the obligation has a mechanical subject — R6 records that `check-doc-currency.sh` structurally cannot see a claim that should have been made. (This is also what makes Subtask 3's `requires` edge on Subtask 2's `write_served_index` **earned rather than inferred**: without it, Subtasks 2 and 3 would be mutually unreachable and their shared `test-setup-ui.sh` lane would become a genuine same-wave collision.)
- [ ] AC-4 Given the whole change, when the suites run, then every `loomwright/scripts/test-*.sh` exits 0 and all **seven** `scripts/check-*.sh` gates exit 0, with before/after assertion counts stated for each suite touched.

## Outcomes Rubric
- The floor is reachable in one command, and switching projects never means restarting a server or remembering a port.
- A project appears on the page only because a human added it.
- Every project shows its own freshness; a slow or missing project reads as exactly that, never as an empty or wrong floor.
- The loop's cost is bounded and measured, not assumed.
- Everything the command can report, the page can show — while remaining a page that only reads.
- Loopback only, no egress, no write path into any registered project.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Registry substrate + engine registry subcommands | AC-1a…AC-1h | 2 modify, 0 create | `skills/quality-checklist`, `skills/unit-testing` | LAUNCHABLE |
| 2 | Multi-project serve scheduling + the page | AC-2a…AC-2f | 5 modify, 0 create | `skills/frontend-ui`, `skills/quality-checklist` | BLOCKED (by #1) |
| 3 | `/ui` command, parity gate, release surface | AC-3a…AC-3d, AC-4 | 11 modify, 1 create | `skills/quality-checklist`, `skills/claude-md-validation` | BLOCKED (by #2) |

### Subtask Contracts

```yaml
# Subtask 1 — Registry substrate + engine registry subcommands (LAUNCHABLE)
provides:
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "do_add"}
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "do_list"}
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "do_forget"}
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "do_scan"}
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "registry_path"}   # MUST honour the AC-1h isolation override (fixture HOME or explicit flag)
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "registry_read"}
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "project_slug"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-ui.sh", name: "(k) AC-registry"}
requires: []
lanes:
  - "loomwright/scripts/setup-ui.sh"
  - "loomwright/scripts/test-setup-ui.sh"
external_requires:
  - "python3 >= 3.7 (already required by `serve` only)"

# Subtask 2 — Multi-project serve scheduling + the page (BLOCKED by #1)
provides:
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "regen_project"}
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "write_served_index"}
  - {kind: "symbol", path: "loomwright/scripts/floor-ui/floor.js", name: "renderProjectPicker"}
  - {kind: "symbol", path: "loomwright/scripts/floor-ui/floor.js", name: "projectStateLabel"}
  - {kind: "symbol", path: "loomwright/scripts/floor-ui/index.html", name: "project-picker"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-ui.sh", name: "(l) AC-multiproject"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "registry_read"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "project_slug"}
lanes:
  - "loomwright/scripts/setup-ui.sh"
  - "loomwright/scripts/floor-ui/index.html"
  - "loomwright/scripts/floor-ui/floor.css"
  - "loomwright/scripts/floor-ui/floor.js"
  - "loomwright/scripts/test-setup-ui.sh"
external_requires: []

# Subtask 3 — /ui command, parity gate, release surface (BLOCKED by #2)
provides:
  - {kind: "file", path: "loomwright/commands/ui.md"}
  - {kind: "symbol", path: "loomwright/commands/ui.md", name: "# Command: /ui"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-ui.sh", name: "(m) AC-entrypoint-parity"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-ui.sh", name: "(z10)"}
  - {kind: "symbol", path: "loomwright/docs/FLOOR_UI.md", name: "## Projects"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "v15.46.0"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "do_add"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "write_served_index"}
lanes:
  - "loomwright/commands/ui.md"
  - "loomwright/commands/setup.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/docs/FLOOR_UI.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "README.md"
  - "CLAUDE.md"
  - "CHANGELOG.md"
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
| Subtask 1 | Subtask 2 | `loomwright/scripts/setup-ui.sh`, `loomwright/scripts/test-setup-ui.sh` | YES — and **legal**: 2 is reachable from 1 in the `requires` DAG, so the pair is ordered, not a same-wave collision |
| Subtask 2 | Subtask 3 | `loomwright/scripts/test-setup-ui.sh` | YES — 3 is reachable from 2; ordered, not a collision |
| Subtask 1 | Subtask 3 | `loomwright/scripts/test-setup-ui.sh` | YES — 3 is transitively reachable from 1 (1 → 2 → 3); ordered, not a collision |

> **Sequential sharing grants VISIBILITY, not PRESERVATION.** The deterministic `outputs_verified` gate checks a producer's own `provides` at producer time ONLY — nothing re-verifies that a later consumer preserved them. Scoped to what each subtask actually shares:
> - **Subtask 2** edits `setup-ui.sh`, which carries Subtask 1's `provides` symbols, and MUST re-verify that `registry_read` / `project_slug` / `do_add` / `do_list` / `do_forget` / `do_scan` still resolve after its own edits.
> - **Subtask 3 does NOT edit `setup-ui.sh`** — it only PARSES it (AC-3a) and moves its ratchet allowance, which lives in `docs/vendor-coupling-manifest.json`, not in the script. `setup-ui.sh` is deliberately absent from Subtask 3's lanes; do not edit it there. Subtask 3 shares only `test-setup-ui.sh`, and MUST re-verify that Subtask 1's `(k) AC-registry` and Subtask 2's `(l) AC-multiproject` groups still exist and still pass after its own append.
>
> This is authoring discipline, not an automated gate.

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after 1)
- **Batch 3:** Subtask 3 (after 2)
- **Recommended workers:** 1
- **Estimated batches:** 3

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/frontend-ui/SKILL.md`, `skills/quality-checklist/SKILL.md` |
| 3 | `skills/quality-checklist/SKILL.md`, `skills/claude-md-validation/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| R1 — **jq-vs-portability conflict** (Feasibility 2). The registry is JSON but `setup-ui.sh` explicitly declares jq is not its dependency. A naive `jq` call silently makes every registry verb fail on a jq-less machine. | HIGH | AC-1e forces the decision to be named in the script header and asserted by a test that makes jq **unfindable**, not by inspection. Guarding registry verbs on jq (named reason, exit 0) preserves the existing property for `check`/`apply`/`serve`/`stop`/`remove`. |
| R2 — **Scheduling starves the loop.** At the measured ~1.06 s/projector-run, regenerating every project every tick falls behind a 2 s interval at **two** projects and renders everything permanently stale. | HIGH | AC-2b asserts elapsed time across a fixed tick count against a **stub projector with known cost** — a measurement, not inspection. Item 05's 4.1x regression passed 338 assertions and 7 gates silently, which is why a timing assertion is mandatory here. |
| R3 — **The page gains a write path.** Item 07 (not this item) adds guarded writes; adding one here would invalidate item 04's stated reason for having no auth layer ("nothing to authenticate against on loopback"). | HIGH | AC-2d's static check asserts no `POST`/`PUT`/`DELETE`/`fetch`-with-`method` in the bundle; AC-2f re-asserts loopback-only and zero egress with a real network log. |
| R4 — **`remove` destroys the registry.** The registry's survival depends entirely on living outside the ui directory. | HIGH | AC-1g asserts it directly rather than reasoning from the path. |
| R5 — **`forget` mistaken for `remove`.** One word meaning both "tear down the module" and "drop a project" is a data-loss shape. | MEDIUM | Distinct verb names are an AC (AC-3a), and AC-1d hashes the project tree before/after to prove `forget` touches nothing on disk. |
| R6 — **Release-surface drift.** `check-doc-currency.sh` verifies claims that ARE made; it structurally cannot see a claim that should have been made (the gap item 05's `(j36)` region-parity gate closed for FLOOR_UI.md). | MEDIUM | AC-3b extends the `(z)` parity group rather than trusting prose; AC-3c forbids hand-typed ratchet values. |
| R7 — **Test-suite ratchet / vacuous assertions.** Item 05 recorded assertions written after the implementation, and a `$HERE`-undefined false green that printed "0 failed" while ~30 assertions never ran. | MEDIUM | AC-4 requires before/after assertion counts per suite, so a silent drop in total is visible; new gates must be proven RED before green (mutation control), per the repo's established discipline. |
| R8 — **Working tree carries an unstaged `.supervisor/postmortem/results.jsonl`.** | LOW | It is an advisory ledger append, deliberately left unstaged by the prior run. Leave it unstaged; do not include it in any commit. |

## Configuration
- **Workers:** 1
- **Mode:** sequential (single-agent per subtask)
- **Estimated batches:** 3
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-04-ui-command-and-projects.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/181
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** vcs merge commit c5f4e46 on origin/main — subject [Merge pull request #181 from vikashruhilgit/feature/ui-command-and-projects] — attributed by branch-slug match, committed on/after the brief date; git refs on disk only, no fetch, no forge call (https://github.com/vikashruhilgit/loomwright/pull/181)
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
