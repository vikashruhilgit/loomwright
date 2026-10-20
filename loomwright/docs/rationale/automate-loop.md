# Rationale — automate-loop

Stories, history, examples and explanations moved out of the runtime prompts of the `automate-loop` group: the `skills/automate-loop/` skill (its index `SKILL.md` and every split file) and the `commands/automate.md` command body. Nothing here is read at runtime and nothing here is a rule: every rule stayed in a runtime prompt, at the step that uses it, or is executed by a script (`scripts/automate-next-step.sh` and the helpers it calls). Each inventory row of kind `story` in `docs/loop-inventory/automate-loop.md` points at the heading below that holds its text.

## Index, invariants and command body

### Purpose and layering

The plugin can drive **one** requirement deep (`/autonomous`), but nothing walked **arbitrary** work from any starting point. `/automate` is the outermost loop, and the layering is strictly nested:

```
/autonomous (one requirement)  ⊂  per-item loop  ⊂  /automate (source → Queue → loop)
```

- **`/autonomous`** runs one requirement end-to-end to a PR (Launch Pad → Supervisor, with Phase 4.5 self-heal + Rubric Grader). Under `--inline-phases` the engine drives it `--single-iteration`; by default the driver runs its two phases itself, Launch Pad and then Supervisor, each as its own fresh headless session, and applies `/autonomous` PLAN's result handling (the skill's Coordinator loop).
- **The per-item loop** wraps a single `/autonomous` run with an owned until-mergeable drain, a trusted-merge-or-park gate, and a `main` re-sync (skill §6).
- **`/automate`** resolves a source into a `## Queue` once, materializes ONE run file, and drives each Queue item through the per-item loop.

The per-item engine is source-agnostic — only the intake differs, and intake is just "convert the source into the run file's Queue, once" (skill §2). Further sources (issues, Beads `bd ready`, Jira) would each just populate the Queue; none needs a framework. For a `--parallel N` wave the engine builds the wave branch (lane merges, local CI, the release bump) and opens the wave PR; the owner merges it.

### The command body's purpose section

`/automate` converts any source — a prompt (via `/product-owner`), a requirements folder, or a backlog/plan doc — into a full Queue with a per-run processing cap inside ONE markdown run file (`.supervisor/automate/<run_id>.md`, which is the contract, the dashboard and the resume state). It then drives each Queue item through the per-item loop: Launch Pad → Supervisor → an owned `/review-pr --until-mergeable` drain, each a fresh session (under `--inline-phases`: `/autonomous --single-iteration` + an inline drain) → trusted-merge-or-park → pull `main` → check the item off and append to `## Progress`. It is smart about resume: on start it globs `.supervisor/automate/*.md` for incomplete runs, reconciles them against ground truth (`gh`/`git`/`## Status: done`), and offers continue / start new / archive.

The command body states this once as a surface summary. Every contract it names — intake, the run-file model, RESUME, the per-item loop, the single drain and its config toggle, the single-open-PR invariant, the two modes and the fail-closed trusted auto-merge gate — is coined in the skill; the command body previously restated "defined ONCE in the skill" three times, and now says it once.

### Why Step 0 re-reads the bodies every run

Step 0 guards against prompt drift: if the loop protocol, `/autonomous` or `/review-pr` evolves between releases, `/automate` picks up the change because it re-reads them every run rather than executing remembered shapes.

### Why the command keeps a short overview

The command body's overview is a map of the steps `scripts/automate-next-step.sh` runs, not the contract. It stays in the command body (shortened to one line per step) because several tests assert that the command body itself mirrors the surface — that it names `trail-gate`, `closeout`, `closeout-classify`, `closeout-others`, `closeout --no-trail`, `trail-pr`, the "never at a park" trail rule, the qualified single-drain claim, and the derived wall-clock cost of a fix-now option. Each step it names is executed by the driver, and the skill's Coordinator loop forbids re-running one by hand.

### Why the flag list lives in the command only

The skill's §12 used to carry its own copy of the `/automate` flag list, line for line beside the command body's Usage block. Two copies of one list drift silently, so the skill now points at the command's Usage block (always read with the skill) and keeps the `/loop` driver rules, which the command does not state.

### Why the run file is driver-owned

The coordinator never writes the run file: `scripts/automate-next-step.sh` runs every step that changes it, through the helpers. The run-file section (§3: template, item lifecycle, `## Status` semantics, the crash-safety contract and the `## Current` transition table) is therefore read only when it is needed — a new run's intake writes the first run file from the template, a run-file helper or a driver call fails, or the owner asks for a check-off by hand — and not on every start.

### Why Current moves only through current-set

`## Current` is the resume state RESUME trusts first, so it is never left to prose. Lane w1-10 (run `automate-2026-10-04-103627`) wrote `## Current` once at creation and never again — every later event was a `progress-append` — so a RESUME mid-drain would have read "nothing in flight" while a PR was open. That incident is why every write of the item line and the `pause_reason` line is one `automate-helpers.sh current-set` call, and why `progress-append` refuses to record a `picked` / `ran /autonomous` / `owned drain started` line over an unset `## Current` (exit 3, `current_not_set`).

### Why runfile-write validates before rename

Temp + rename protects against a crash mid-write, but it installs whatever the temp file holds. The engine builds rewrites as `<generator> "$RF" | automate-helpers.sh runfile-write "$RF"`, and a generator that errors — BSD awk rejecting a newline in a `-v` value, an unescaped delimiter in a `sed`, a failed redirect — prints nothing while the helper cannot see its exit status. Validating the staged payload before the `mv` is what keeps such a failure from replacing the only copy of resume state with an empty or truncated file. A shrinking line count is deliberately not a refusal reason (unlike `/verify`'s `queue-write`), because `## Current` legitimately loses lines, e.g. `pending_decisions:` disappears when the next item is picked.

### Why a clean bot review is not a dismissed finding

A bot review that says "no new findings" carries no finding to decide on, so `dismissed-drafts` never drafts one from it (#617). The skill's Quality Gates line keeps the rule; the PR reference lives here.
