# Supervisor Job: Curation cadence — one recorded last-run, derived siblings, a counted SessionStart nudge, and readiness-aware output

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — 16939 bytes, mtime 2026-08-09)
- **Git:** clean (0 files), branch: main @ db593ab (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (6 pre-existing `.claude/worktrees/*` from earlier sessions; unrelated to this lane, do not clean them up)
- **Source requirement:** `.supervisor/requirements/twin-loop/02-curation-cadence.md`

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash + jq + markdown command bodies, exactly the existing surface. No new runtime. |
| 2 | Dependency Availability | GO | `jq` present; `gh` authenticated. Both already treated as optional-with-fallback by sibling scripts, and this work must do the same. |
| 3 | Architecture Fit | CAUTION | The nudge has an in-repo precedent (`rules_nudge()`), but the precedent sits **after** a source gate that excludes fresh sessions — see finding 1. Mirroring it naively ships a nudge that never fires. Risk row present. |
| 4 | Scope vs Supervisor Capability | GO | One coherent lane. Below the Decomposition Threshold ⇒ ONE subtask. |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** GO (with the Phase 2.5 CAUTION carried into Risk Assessment)

## Task

**Goal:** Give the plugin one durable, fail-safe record of curation cadence — stored for `/dreaming` alone and *derived* for `/insights` and `/pr-postmortem` — surface it as a counted, debounced SessionStart nudge that actually fires on a fresh session, and make the curation commands readiness-aware, so the "is what we wrote down still true?" half of the plugin stops depending on the user happening to remember.

**Problem Statement:**
The plugin writes continuously (session logs, worker results, PR review churn) but only *checks* what it wrote when a human personally types `/dreaming`, `/insights`, or `/pr-postmortem`. None of the three leaves a last-run trace, so nobody — user or agent — can tell whether running one now is worthwhile. Measured agent-memory write cadence is thin and irregular (2026-08-04, 2026-07-06, 2026-06-26; all to a single store). Running `/dreaming` over 3 new findings is noise; running it over 47 is overdue, and today the two are indistinguishable from outside. Success looks like: one line surfaced at session start carrying a real **count**, each corpus-wide command able to say "too early — wait", and every run explaining what it achieved and what that improves.

### Verified pre-work findings (do NOT re-derive; measured against the running system)

Findings 1, 1b, 2 and 4 **overrule** the literal wording of `02-curation-cadence.md`. This section is authoritative over the source requirement where they conflict. Findings 1b, 1c and 5 were found by Plan Review round 1 and independently re-verified against the real files before acceptance.

1. **The seam is `SessionStart`, not `Stop`.** The requirement calls this a "session-end reminder" and says to verify the seam rather than assume it. Verified: `hooks.json:94-95` `.hooks.Stop` is a **`type: "prompt"`** hook whose contract is to answer `{"ok": true}` / `{"ok": false, …}`; it validates the code-reviewer's result block and its output is consumed by that validator, never shown as text. `hooks.json:188` `.hooks.SessionStart` is a **`type: "command"`** hook running `session-resume.sh`. **Wire the nudge into `session-resume.sh`. Do not touch the `Stop` hook.** Honest consequence to state in the docs: the user sees the cadence line at the *start* of the next session, not the end of this one.

2. **(1b — BLOCKING if missed) `session-resume.sh` exits before any nudge on a fresh session.** `session-resume.sh:59-62` is `case "$SOURCE" in resume|clear|compact) ;; *) exit 0 ;; esac`, and `rules_nudge` is called at `:229`, far below it. So **`source=startup` — a fresh session, exactly when a cadence reminder matters most — never reaches the nudge.** A worker told to "mirror `rules_nudge()` exactly" ships a feature that provably never fires on the case the Problem Statement promises, while every nudge test still passes if the test feeds `{"source":"resume"}`.

   **Decision: add a DEDICATED `startup` branch — do NOT widen the shared gate.** The branch runs the curation nudge, emits its own `hookSpecificOutput` envelope, and **exits before the `## Loomwright — prior-session context` header at `:221`**:

   ```sh
   case "$SOURCE" in
     resume|clear|compact) ;;
     startup) curation_nudge_startup_only; exit 0 ;;
     *) exit 0 ;;
   esac
   ```

   **Three things the branch must do for itself, because it exits above the code that normally does them** (each is pinned by its own AC below — prose alone is not enough):
   - **Its own `.supervisor/` presence check.** The shared bail `if [ ! -d ".supervisor" ]` is at `session-resume.sh:65-67`, *below* the case. A `startup)` arm that exits inside the case structurally bypasses it — and since decision (f) makes `unknown` counts NON-suppressing, the nudge would otherwise fire on **every fresh session in every repo the user opens**, contradicting the very precedent this design cites (`session-resume.sh:34-36`: "never in a truly fresh repo — that's `/setup twin`'s job, so it sits after the `.supervisor/` bail").
   - **Its own output envelope.** `session-resume.sh:313-315` states that a bare top-level `additionalContext` is **NOT recognized** (dropped, or shown as raw JSON); the working emit is the `printf | iconv -c | jq -Rs '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:.}}'` chain at `:320-323`, which sits after the exit point and must therefore be duplicated. A bare `printf` of the line satisfies "the nudge fires" while never reaching the model.
   - **Definition above line 59.** Every existing helper is defined *below* the case (`append` `:74`, `observability_probe` `:100`, `rules_nudge` `:186`), so `curation_nudge_startup_only` and anything it calls must be defined above `:59` or the call is `command not found` (rc 127) — swallowed by the following `exit 0` and hidden by the `|| true` at `hooks.json:188`.

   **Why not simply widen the gate (this was tried in revision 2 and is WRONG — recorded so it is not re-proposed):** everything below `:59-62` becomes reachable on startup, and that set is far larger than "the prior-state sections". Verified against the real file: `observability_probe` is called **unconditionally** at `:226` and runs `curl --connect-timeout 1 --max-time 1` at `:126`, then fires a **desktop notification** via `notify-desktop.sh` at `:153-156` when the stack is down. Widening would therefore add a **network call and a desktop notification to every fresh session start** — contradicting decision (e) and finding 3 of this very brief. Below that sit the unconditional header `:221`, Sections 1–5 (`:231`, `:241`, `:251`, `:264`, `:282`), the **unconditional** Section 6 recovery hints `:299`, and `rules_nudge` `:229`. On this repo `.supervisor/state.md`, `.supervisor/logs/*.jsonl` and `.supervisor/jobs/in-progress/` all exist, so it would fire on the very next session. The dedicated branch avoids all of it structurally rather than by guarding sections one at a time.

   **`rules_nudge` firing surface is explicitly UNCHANGED:** it stays below the gate and does **not** fire on `startup`. That is a deliberate answer, not a side effect — `rules_nudge` is a different shipped feature (v15.1.0 slice #3b-ii) whose own design comment at `:35-36` reasons about where it sits relative to these bails, and this work must not silently move it. Pinned by test.

   **Do NOT add a new `hooks.json` entry** — hook count is a doc-currency-enforced claim (`scripts/check-doc-currency.sh:56` computes `[.hooks[][].hooks[]] | length`, currently 24, mirrored in `README.md`), so a new entry ripples through every count surface for no benefit the dedicated branch does not already give.

3. **(1c) The nudge reaches the *session*, not a rendered UI line — say so honestly.** `session-resume.sh:313-322` emits `hookSpecificOutput.additionalContext`; that is **model-context injection**, which the agent then surfaces — it is not a directly-rendered user notification. The source requirement asks for "one line where the user will see it… proven to reach the user (demonstrated, not assumed)" (`02:58-63`, `02:92-93`). This design satisfies it the same way every other section of this script does, and the docs must describe it accurately rather than claiming a UI guarantee the mechanism does not provide. **Considered and deliberately rejected:** `notify-desktop.sh` (used at `session-resume.sh:150-156` for the observability probe) is the one genuinely user-facing path, but it is reserved there for an *exceptional fault* (stack down). A recurring cadence reminder is not a fault, and a desktop notification per session start would be noise. Recorded as an explicit non-goal so a later reader knows it was weighed, not overlooked.

4. **(2) `max .ts` over the whole ledger is the WRONG derivation for `/pr-postmortem`'s last run.** Since v15.28.0 `.supervisor/postmortem/results.jsonl` is a **unified corpus with two producers**, discriminated by `.source`: `/pr-postmortem` command runs, and engine-native `automate_drain` lines appended by `automate-helpers.sh learning-emit`, which no human ever "ran". Measured on the live 81-record ledger: `source: null` → 45 (legacy command lines predating the field), `automate_drain` → 26, `manual_postmortem` → 10. Plan Review independently falsified the obvious failure mode: `automate_key` appears on exactly the 26 `automate_drain` records (1:1), so there are **no** source-less drain lines the filter could misclassify; and `results.jsonl:65` is a source-less *manual* record dated `2026-07-19`, newer than the `automate_drain` line at `:64` (`2026-07-18`) — concrete proof that drain and command records **interleave chronologically**, so the filter is load-bearing in general. It does NOT mean the naive max returns a wrong answer today — the two newest records are source-less, so filtered and unfiltered max currently coincide; the AC-3 fixture is what makes a naive implementation fail red. **The derivation MUST be `select(.source != "automate_drain")` then `map(.ts)|max`.**

5. **(3) `build-insights.sh` re-measured at 6.29 s, not the requirement's quoted 4.8 s.** Scope 6 explicitly says to re-measure rather than trust the figure. Done on this repo this session (`rc=0`). The requirement's conclusion **survives and strengthens**: 6.3 s is fine for an explicit or async run and far too slow for a blocking `SessionStart`. Quote **6.3 s (re-measured 2026-08-09)** in any doc line, never 4.8 s. *(Two honest caveats: the measurement regenerated `dashboard.md`, so the mtime `/insights` derives its last-run from is now 2026-08-09 — idempotent regeneration, not data loss. And Plan Reviewer is structurally read-only and could not re-run the script, so this is the one load-bearing number no second party has checked.)*

6. **(4) `/pr-postmortem` must NOT get a declining readiness gate.** `commands/pr-postmortem.md:16-17` shows exactly two invocation forms — `<pr-url>` and `OWNER/REPO#N` — both **targeted at one named PR**; there is no batch or no-argument form. A gate answering "only 3 PRs since last run, come back later" would refuse to answer a direct question about a PR the user just named. `/pr-postmortem` still gains readiness **reporting** and still contributes its pending count to the nudge, but it never declines. The declining gate applies to `/dreaming` and `/insights`, the corpus-wide passes.

7. **(5) The house-rule citation is narrower than the argument it was carrying.** `.agent/rules/process.json:5` is scoped to "a **count or version** claim … in exactly ONE authoritative **machine-readable** place". Decision (b) below applies derive-don't-restate to a *last-run timestamp*, which is outside that rule's stated scope. The design is still right — see (b) — but it now stands on its own merits, and `process.json` is cited only as an **analogous precedent**, not as a governing rule. (The source requirement at `02:36-37` makes the same over-broad citation; this brief does not inherit it.)

### Design decisions settled here (the worker must NOT re-invent these)

- **(a) One new uncounted plain script, `loomwright/scripts/curation-status.sh`**, with three subcommands; the command bodies and `session-resume.sh` shell out to it, so the tested code is the executed code. **It ALWAYS exits 0 on every path** — a runtime advisory emitter under CLAUDE.md's bimodal invariant, never a correctness gate.
  - `status [--json]` — per-command `last_run` / `age_days` / `pending` / `threshold` / `ready`.
  - `record dreaming` — the ONLY legal `record` target (see (b)); any other argument is rejected with a message and still exits 0.
  - `nudge` — prints the ONE advisory line, or **nothing at all** when nothing is pending.
- **(b) Store ONE last-run value, derive the other two.** `.supervisor/curation-state.json` holds `/dreaming` only. **Justification on its own merits** (per finding 7): a derived value cannot go stale, and `/dreaming`'s case is genuinely different — it writes only through the memory writers, so `.supervisor/memory/` mtime reports the last run *that accepted something* and is structurally blind to the ran-but-accepted-nothing case (`02:44`), which is exactly what this record exists to capture. `.agent/rules/process.json` is an analogous precedent, not the governing authority. **The source requirement's AC1 ("`curation-state.json` is written by all three commands", `02:90`) is a survival of its pre-revision draft and is superseded by its own Scope 1** — writing all three would rebuild the restatement Scope 1 rejects. Record a retirement condition in the file's header: if `/dreaming` ever gains its own durable artifact, retire this record and derive from that instead.
- **(c) Derivation table (exact — assert each against the real path, do not trust this table blindly):** `/insights` ⇐ mtime of `.supervisor/insights/dashboard.md`; `/pr-postmortem` ⇐ max `.ts` over `results.jsonl` records with `.source != "automate_drain"` (finding 4); `/dreaming` ⇐ `.dreaming.last_run` in `.supervisor/curation-state.json`.
- **(d) mtime reads use `stat -c %Y` FIRST with `stat -f %m` as fallback, and the result is validated numeric before any arithmetic.** This is the repo's recorded `stat`-flavour trap: BSD `stat -f %m` *succeeds with garbage* on GNU/Linux, and an empty value inside `$(( ))` under `set -u` silently empties the probe — it passed macOS dev and failed Linux CI once already. Non-numeric ⇒ `unknown`, never a crash, never a fabricated 0.
- **(e) The nudge is LOCAL-ONLY — never a network call.** `session-resume.sh` runs in a `SessionStart` hook; a `gh` call there is a latency hazard on every session start. The "merged PRs absent from the ledger" count (`02` Scope 2) is computed **only** on an explicit `status` invocation and reported as `unknown` to the nudge. Nudge counts come only from local files.
- **(f) Any unreadable input yields the string `unknown` — never a fabricated `0`.** A fabricated zero would *suppress* the nudge, i.e. fail silent on exactly the input we could not read. `unknown` means "do not suppress, but do not claim a number".
- **(g) Thresholds live in `.supervisor/config.json` under `.curation.thresholds.{dreaming,insights}`**, with in-script defaults `dreaming: 15`, `insights: 10`. **Both are unvalidated starting guesses and must be labelled as such** in the script header, in both command docs, and in the decline message itself. Do not create a new config file. **`config.json` is LIVE on this repo** — it holds `webhook_url`, `setup_memory.repo_allowlist`, and (transiently, while `/automate` is driving this run) `auto_review`, a key the `/automate` single-drain invariant owns. **Read it; never rewrite it.**
- **(h) `.supervisor/curation-state.json` is operational cadence, NOT curated judgment.** It stays gitignored. **Do not add it to `setup-memory.sh`'s `INTENDED_PATHS`**, do not add a `.gitignore` negation, and do not touch the committed-twin surface (`setup-memory.sh`, `test-committed-twin-scrub.sh`, the ledger gate) at all — just re-hardened by #132/#133 and out of this lane.
- **(i) The decline is advisory and exits 0.** `--force` overrides it. Never an error exit, never a hook failure, never blocks a session.
- **(j) Output-surface ownership (settled so the worker does not split authority):** the readiness lines for `/pr-postmortem` are printed by the **command shell before `skills/pr-postmortem/SKILL.md`'s protocol runs**; that skill is the declared single source of truth for the report itself (`SKILL.md:11`, `commands/pr-postmortem.md:38`) and is **deliberately untouched**. Likewise `/insights`' readiness lines are printed by the **command shell**, not by `build-insights.sh` — the dashboard generator is untouched. Neither file is in `lanes`, and that is intentional, not an omission.

## Acceptance Criteria

- [ ] Given a repo with no `.supervisor/curation-state.json`, when `curation-status.sh status` runs, then `/dreaming` reports `last_run: never` and the script exits 0.
- [ ] Given a `curation-state.json` that is truncated, empty, or not valid JSON, when `status` runs, then it reports `last_run: never` (never an error, never a crash) and exits 0.
- [ ] Given a ledger holding both `automate_drain` and command-authored records, when `status` derives `/pr-postmortem`'s last run, then it returns the max `.ts` **excluding** `automate_drain` records — pinned by a fixture whose **newest line is an `automate_drain` record**, so a bare `map(.ts)|max` implementation fails the test red.
- [ ] Given `.supervisor/insights/dashboard.md` exists, when `status` derives `/insights`' last run, then it uses `stat -c %Y` with a `-f %m` fallback and validates the value numeric before arithmetic; a non-numeric result yields `unknown`, not a crash and not `0`.
- [ ] Given each of: an absent ledger, an unreadable ledger, an absent `jq`, and an absent insights dashboard — when `status`, `nudge`, and `record` each run, then every one exits 0 and reports `unknown`/`never` rather than a fabricated count.
- [ ] **(pending-count correctness)** Given a fixture of N session logs and M ledger records with timestamps known relative to a fixed `last_run`, when `status` computes the pending counts, then it reports **exactly the hand-counted values** — restoring `02:91`.
- [ ] **(startup fires)** Given `{"source":"startup"}` on a repo with pending work, when `session-resume.sh` runs, then the curation nudge **DOES** fire. Given `{"source":"resume"}` with pending work, it also fires.
- [ ] **(startup emits NOTHING else — assert absence, not a two-item allow-list)** Given `{"source":"startup"}` on this repo (where `.supervisor/state.md`, `.supervisor/logs/*.jsonl` and `.supervisor/jobs/in-progress/` all exist), the emitted output contains the curation line and **none** of: the string `prior-session context` (the `:221` header), the string `Recovery hints` (the unconditional `:299` section), any `curl` invocation, any `notify-desktop.sh` invocation, and any house-rules nudge output. Asserted as **absence of each**, so guarding only some sections cannot pass.
- [ ] **(startup is silent outside a plugin repo)** Given `{"source":"startup"}` in a directory with **no `.supervisor/`**, the startup branch emits **nothing** and exits 0 — the branch performs its own `[ -d ".supervisor" ]` check, because the shared bail at `session-resume.sh:65-67` sits below the case it exits from. Without this the nudge fires in every repo the user opens.
- [ ] **(the emitted line actually reaches the model)** Given `{"source":"startup"}` with pending work, the emitted stdout **parses as JSON**, and `.hookSpecificOutput.hookEventName == "SessionStart"` and `.hookSpecificOutput.additionalContext` contains the curation line — mirroring the `jq -Rs` / `iconv -c` emit at `session-resume.sh:320-323`, not a bare `printf`. A bare `printf` passes the "nudge fires" AC while being dropped or rendered as raw JSON (`session-resume.sh:313-315`).
- [ ] **(rules_nudge surface unchanged)** Given `{"source":"startup"}` on a repo with zero valid house rules, the house-rules nudge does **not** fire; given `{"source":"resume"}` on the same repo it still does. Both pinned, so this work cannot silently move another feature's firing surface.
- [ ] Given pending work exists, then exactly ONE advisory line is emitted carrying a real **count** (not merely a date), debounced by a 24h mtime-windowed marker, and silenced entirely by `LOOMWRIGHT_CURATION_NUDGE=0|off|false` — mirroring `rules_nudge()`'s conventions.
- [ ] Given nothing is pending, then the curation nudge emits **nothing at all** (no empty header, no blank section).
- [ ] Given the nudge path runs, then it makes **no network call** (no `gh`, no `curl`) — asserted by the test, not by inspection.
- [ ] **(record wiring)** Given a `/dreaming` run completes, then `commands/dreaming.md` invokes `bash "${CLAUDE_PLUGIN_ROOT}/scripts/curation-status.sh" record dreaming`, and a subsequent `status` reports a **non-`never`** `last_run` for `/dreaming`.
- [ ] **(threshold is genuinely configurable)** Given `.supervisor/config.json` sets `.curation.thresholds.dreaming` to `3`, when `/dreaming` readiness is evaluated with 4 pending items, then it does **not** decline — proving the config value overrides the in-script default; an absent or malformed config falls back to the default and still exits 0.
- [ ] Given `/dreaming` or `/insights` is invoked below threshold without `--force`, then it declines with a reason naming the observed count, the threshold, and the fact that the threshold is an unvalidated guess; and exits 0. With `--force`, it proceeds. Both paths tested.
- [ ] Given `/pr-postmortem <pr-url>` is invoked, then it **never declines** (finding 6) but its output states last-run, delta, produced, and expected improvement.
- [ ] Each of the three commands' run output states: when it last ran · what changed since · what it produced this time · what that will improve.
- [ ] `loomwright/scripts/test-curation-status.sh` exists, is Ubuntu-clean (bash 3.2-safe and GNU-safe), and is picked up by the CI glob `loomwright/scripts/test-*.sh` (`.github/workflows/ci.yml:62`); the full glob stays green. `loomwright/scripts/test-rules-seams.sh` stays green (it statically asserts `session-resume.sh` references `read-rules.sh` and never references `rules-check.sh` — preserve both properties).
- [ ] **(no restated count in the edited header)** The `session-resume.sh` header block documents the curation nudge **without restating any hook count**, and the stale line at `session-resume.sh:36` — `Adds NO new hook — hooks stay 21`, wrong against the authoritative 24 computed at `scripts/check-doc-currency.sh:56` — is corrected or de-numbered in the same edit. The worker is editing this exact block, and restating a count there re-commits the very trap `.agent/rules/process.json:5` names.
- [ ] Version bumped to `15.29.0` in lockstep across `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md`, and `CHANGELOG.md`, with no stale `15.28.0` outside CHANGELOG history.
- [ ] `scripts/check-doc-currency.sh` and `scripts/check-command-sync.sh` green; agent/command/skill/**hook** counts UNCHANGED (this work adds only uncounted plain scripts and must not add a hook entry — finding 2).

## Outcomes Rubric

- `loomwright/scripts/curation-status.sh` is a newly added file implementing exactly the subcommands `status`, `record`, `nudge`, and every `exit` in it is `exit 0`.
- The `/pr-postmortem` last-run derivation filters on `.source != "automate_drain"`, and `test-curation-status.sh` contains a fixture whose newest line is an `automate_drain` record.
- `loomwright/scripts/session-resume.sh` gains a dedicated `startup)` branch in the `case "$SOURCE"` at `:59-62` that runs a curation-nudge function reading a `.supervisor/.curation-nudge-shown` 24h marker plus an env opt-out, performs its OWN `[ -d ".supervisor" ]` check, emits its OWN `hookSpecificOutput.hookEventName: "SessionStart"` envelope via `jq -Rs`, and `exit`s before the `## Loomwright — prior-session context` header; the `resume|clear|compact` arm is otherwise unchanged and `rules_nudge` remains below the header.
- `loomwright/hooks/hooks.json` is **unmodified** by this PR, and `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CLAUDE.md` and `CHANGELOG.md` all state version `15.29.0`.
- `loomwright/commands/dreaming.md` contains a `curation-status.sh record dreaming` invocation.
- `loomwright/commands/dreaming.md` and `loomwright/commands/insights.md` each document a `--force` flag in a Parameters table (creating one in `insights.md`, which has none today); `loomwright/commands/pr-postmortem.md` documents no declining gate.
- Both threshold defaults are accompanied by the word "unvalidated" in the script header and in both command docs.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Curation cadence: probe script, SessionStart nudge, readiness-aware commands | ALL | 10 modify, 2 create | `skills/state-management/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### Subtask 1 contract

```yaml
provides:
  - {kind: "file", path: "loomwright/scripts/curation-status.sh"}
  - {kind: "file", path: "loomwright/scripts/test-curation-status.sh"}
  - {kind: "symbol", path: "loomwright/scripts/curation-status.sh", name: "derive_postmortem_last_run"}
  - {kind: "symbol", path: "loomwright/scripts/curation-status.sh", name: "cmd_nudge"}
  - {kind: "symbol", path: "loomwright/scripts/session-resume.sh", name: "curation_nudge_startup_only"}
  - {kind: "symbol", path: "loomwright/scripts/test-curation-status.sh", name: "test_postmortem_excludes_automate_drain"}
  - {kind: "symbol", path: "loomwright/scripts/test-session-resume.sh", name: "test_curation_nudge_fires_on_startup"}
  - {kind: "symbol", path: "loomwright/commands/dreaming.md", name: "record dreaming"}
requires: []
external_requires:
  - "jq (optional — absent ⇒ every probe degrades to unknown/never, still exit 0)"
  - "git (present; used only for repo-root resolution)"
lanes:
  - "loomwright/scripts/curation-status.sh"
  - "loomwright/scripts/test-curation-status.sh"
  - "loomwright/scripts/session-resume.sh"
  - "loomwright/scripts/test-session-resume.sh"
  - "loomwright/commands/dreaming.md"
  - "loomwright/commands/insights.md"
  - "loomwright/commands/pr-postmortem.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CLAUDE.md"
  - "CHANGELOG.md"
```

> **`provides` non-false-passing note:** every symbol above was verified ABSENT from the repo at plan time (`grep -rn` on each returns 0 hits), independently re-confirmed by Plan Review, so none can pass by matching pre-existing content. Note the two deliberate strengthenings over round 1: `--force` was replaced as a `provides` symbol because a bare-substring matcher is satisfied by *any* occurrence including prose like "never use `--force`" — the `--force` obligation is carried by the rubric bullet instead, which names the Parameters table. `record dreaming` and `test_curation_nudge_fires_on_startup` were added so the two round-1 false-completion vectors (unwired `record`, nudge that never fires on startup) are contract-visible, not just prose.
>
> **`agent-help.md` is in lanes deliberately:** `commands/agent-help.md:607-614` mirrors `/dreaming`'s full flag list, and `scripts/check-command-sync.sh:15-17` covers ONLY `commands/code-reviewer.md` while `check-doc-currency.sh` does not scan flags — so adding `--force` without updating it produces exactly this repo's recorded agent↔command mirror-drift class, which passes every gate and only a Phase 4.5 consistency_audit catches.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 (single, independent)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | n/a (single subtask) | n/a |

### Batch Plan
- **Batch 1:** Subtask 1
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/state-management/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Nudge never fires on a fresh session** — `session-resume.sh:59-62` bails on `source=startup`, and every nudge test passes anyway if fed `{"source":"resume"}` (false-completion) | HIGH | Finding 2 + the startup-fires AC + the `test_curation_nudge_fires_on_startup` provides symbol. Carried from Phase 2.5 CAUTION check 3 |
| **The obvious fix is worse than the bug** — widening the `:59-62` gate exposes `observability_probe` (`curl` `:126`, desktop notification `:153-156`), the `:221` header, Sections 1–5, the unconditional `:299` recovery hints, and `rules_nudge` `:229` on every fresh session — contradicting this brief's own decision (e) and finding 3, while a "no new `curl` in the diff" check stays green because the `curl` is pre-existing | HIGH | Finding 2's dedicated-`startup`-branch decision (structural, not section-by-section guarding) + the assert-absence AC + the rules_nudge-unchanged AC. This was revision 2's actual design and is recorded as rejected so it is not re-proposed |
| **`record dreaming` implemented but never wired** — the one stored value the whole design rests on stays `never` forever, with every other AC green | HIGH | The record-wiring AC + the `record dreaming` provides symbol + the rubric bullet naming `dreaming.md` |
| A fabricated `0` on an unreadable input silently SUPPRESSES the nudge — failing silent on exactly the case we could not read | HIGH | Decision (f): unreadable ⇒ `unknown`, never `0`. Pinned by absent-ledger / unreadable-ledger / absent-jq fixtures asserting `unknown` and exit 0 |
| `stat -f %m` succeeds with GARBAGE on Linux ⇒ macOS-green, CI-red (this repo has been bitten already) | HIGH | Decision (d): `-c %Y` first, numeric validation before any `$(( ))`. Test asserts the validation branch |
| A bare `map(.ts)\|max` reads `automate_drain` engine lines as "you ran /pr-postmortem" — plausible, passes a naive test, wrong on any `/automate`-driven repo | HIGH | Finding 4 + a fixture whose newest record is `automate_drain`, so the naive implementation fails red |
| **The unreadable-ledger fixture asserts nothing when run as root** — `chmod 000` does not block reads for uid 0, so under a root/container CI executor the assertion passes for the wrong reason | MEDIUM | Skip that fixture with an explicit message when `EUID` is 0 rather than asserting; the skip must be visible in output, not silent |
| Editing `session-resume.sh` (a live `SessionStart` hook script) can break every session start in this repo, and `test-rules-seams.sh:36-41` statically greps it for `read-rules.sh` presence / `rules-check.sh` absence | MEDIUM | Mirror `rules_nudge()`'s shape; extend `test-session-resume.sh`; preserve both grep properties; the nudge must safe-skip — never fire — on any error path |
| A `gh` call in the nudge adds network latency to every session start | MEDIUM | Decision (e): nudge is local-only; `gh`-based count is `status`-only. Asserted by a no-network test |
| Scope creep into the committed-twin surface just re-hardened by #132/#133 | MEDIUM | Decision (h): out of lane; an edit there is an out-of-lane write |
| Threshold defaults (15/10) harden into doctrine by restatement; or `configurable` is never actually implemented | LOW | Decision (g) + the config-override AC + the "unvalidated" rubric bullet |
| **Four deviations from the source requirement**, not two — AC1 (all-three-write), "each command declines", the hand-counted pending fixture, and configurable thresholds. The last two were dropped silently in round 1 | LOW | All four now disclosed: AC1 in decision (b), declining in finding 6, and the two dropped ACs restored as explicit acceptance criteria above |
| Finding 5's 6.29 s is the one load-bearing number no second party verified (Plan Reviewer is read-only, no Bash) | LOW | Recorded as unverified-by-review so it is not mistaken for a checked claim; the conclusion it supports is directionally safe either way |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-09-curation-cadence.md
```

## Outcome
- heal_loop_ran: true
- heal_decision: PASS
- heal_iterations: 1
- heal_remaining_issues: 0
- rubric_score: 7/7
- pr_url: https://github.com/vikashruhilgit/loomwright/pull/134
- drain_rounds: 2
- until_mergeable_dispatched: false (engine owned ONE inline drain; 0 dispatch markers for pull/134)
- status: completed (PR left OPEN for human approval — safe mode never merges)
