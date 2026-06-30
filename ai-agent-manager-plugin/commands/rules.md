---
description: Maintain the committed .agent/rules/ house-rules substrate — list / suggest / add / check project conventions an implementer can read on the DO side, not only get caught on the REVIEW side. Substrate only; enforcement deferred to slice 3b-ii.
---

> **Reads code read-only on `list` / `suggest` / `check`; the only write path is `add`, which append-only writes a single path-contained `*.json` under `.agent/rules/` on explicit confirmation.** `.agent/rules/` is the plugin's first **committed-convention** surface — version-controlled, travels with the repo (unlike the gitignored `.supervisor/` / `.claude/agent-memory/`). The protocol authority for every flow is `${CLAUDE_PLUGIN_ROOT}/skills/rules/SKILL.md` — read it at Step 0; when this command and that skill disagree, **the skill wins**.

# Command: /rules

> **The committed house-rules substrate.** `/rules` maintains a single, version-controlled source of truth for project conventions (`.agent/rules/*.json`) so an implementer can read them while doing the work, not only get caught on review. This slice ships the **SUBSTRATE only** — the store, the schema, the fail-safe reader (`read-rules.sh`), and this authoring command. **Enforcement wiring at the worker / Phase 4.5 / nudge seams, close-the-loop, and unattended `check` execution are slice #3b-ii and explicitly out of scope here.**

## Purpose

Conventions a team agrees on tend to live in heads, in CLAUDE.md prose, or get re-discovered every review round. `.agent/rules/` makes them **first-class, committed data**: zero-or-more `*.json` files, each a JSON array of rule objects (`id` · `category` · `statement` · `enforcement` (`advisory` | `must`) · `check` · `provenance` · optional `applies_to`). `/rules` is how you read, propose, author, and (human-invoked) verify them. The rules are **subordinate to CLAUDE.md** — on conflict, CLAUDE.md wins.

## Usage

```bash
/rules list                 # show all valid rules (advisory reader output)
/rules suggest              # scan the repo → PROPOSE rules for human review (never auto-writes)
/rules add                  # append one rule to .agent/rules/<category>.json (confirm-only)
/rules check                # human-invoked: run `must` rules' checks after explicit confirmation
```

## Subcommands

The protocol for each is defined in `skills/rules/SKILL.md` (§ numbers below); this restates the load-bearing contracts so the command is self-explanatory.

### `list` (§4, §5 — read-only)

Invoke the fail-safe reader and show its advisory output verbatim:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh"
```

The reader merges `.agent/rules/*.json` in `LC_ALL=C` path-sorted, first-seen-`id`-wins order, fail-safe-skips any invalid object (missing field / unknown `enforcement` / duplicate `id`), and emits an advisory markdown block headed `## Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)` listing each rule's `statement`, `category`, a `must` flag for `must` rules, and its `check` **shown as DATA only — text, never executed by the reader.** It emits NOTHING and exits 0 when no valid rule exists (so machine consumers can gate on non-empty stdout). v1 emits **all valid rules** — there is no path/scope guessing; `applies_to` is inert (reserved for 3b-ii).

### `suggest` (§6 — scan-to-suggest, propose-only)

Analyze the repo and **PROPOSE** rules — never blank-slate-ask, never auto-write (mirrors `/setup twin`'s offer model):

- **Scanner (degrades gracefully, never blocks):** always grep / glob / read of the repo; **graph-if-present** via `brain-context` (graphify graph when present, staleness-aware, grep fallback — never hard-depends on the external `graphify` CLI); plus `claude-md-validation` convention patterns.
- **Output:** a list of proposed rule objects (suggested `category` / `statement` / `enforcement` / `check`), surfaced for human review.
- **Human-confirmed:** nothing is written without explicit user confirmation. On confirm, each accepted proposal is routed through the `add` write discipline below.
- **Never blocks** and never auto-applies.

### `add` (§7 — append-only write discipline, confirm-only)

Writes ONLY on explicit user confirmation; append-only (never edits or removes an existing rule in this slice). The discipline mirrors the setup settings-merge (parse-gate → atomic write → verify):

1. **Target filename = slugified category (path containment).** The target is `.agent/rules/<category-slug>.json`, where `<category-slug>` is the `category` lowercased and reduced to `[a-z0-9-]` only. **REJECT / sanitize** any `category` containing `/`, `..`, a leading dot, shell metacharacters, or empty-after-slugging — so the write can **NEVER escape `.agent/rules/`** (always a single path segment under that dir). An invalid category aborts the add (never falls through to a default path).
2. **Array-only parse-gate the existing target.** If the file exists, gate it with `jq -e 'type=="array"'`. **ABORT — never clobber —** on malformed JSON OR valid-but-non-array JSON (rule files MUST be arrays). If absent, create it as a single-element array.
3. **Deterministic unique `id`.** `id = "<category-slug>-<statement-slug>"`. On collision against the **merged set** (not just the target file), append a numeric `-N` suffix (`-2`, `-3`, …) until unique.
4. **Stamp provenance.** Set `provenance.source = "/rules add"` (or a user-provided source) and `provenance.added = <UTC ISO-8601>`.
5. **Append via jq, atomically.** Build the object with `jq -n --arg …` (never string-interpolate untrusted input), append to the array, write to a **temp file**, then **atomic `mv`** over the target.
6. **Verify.** Read the appended rule back (via `read-rules.sh` or a `jq` re-parse) to confirm it landed and parses.

### `check` (§8 — HUMAN-invoked only)

The ONLY path in this slice that runs a rule's `check`:

- Runs ONLY `must` rules whose `check` is **non-null** (advisory and null-check rules skipped).
- Each command runs from the **repo root** via `bash -c`.
- **Every command is DISPLAYED before running and executes ONLY after explicit confirmation.**
- Under **non-interactive / no-confirm** (CI, stdin-not-tty, `--no-confirm`), it does **NOT run any check** — it reports `skipped — needs confirmation` for each.
- Reports an **aggregate pass/fail** summary.
- It is **NOT an unattended gate** in this slice — human-invoked only; it never blocks a PR, a worker, or a merge.

## Trust boundary (`check` is arbitrary shell — §9)

A `check` value is **arbitrary shell authored by anyone who cloned or PR'd the repo** — untrusted data everywhere except one explicit, confirmed path:

- **The reader (`read-rules.sh`) emits `check` as DATA and the `check` is never executed by the reader** — there is no code path in it that runs a `check`. Safe for any unattended caller (a hook, a worker, a future enforcement seam) with zero code-execution risk.
- **`/rules check` requires confirmation** — it is HUMAN-invoked only, DISPLAYS each `must`-rule's `check`, and runs it ONLY after explicit confirmation. It never blind-executes a check authored by a cloning teammate.
- **Unattended execution of `check` commands (the worker / Phase 4.5 enforcement seams) is explicitly DEFERRED to slice #3b-ii and MUST be gated there** — inheriting `run-ground-truth.sh --no-cmd`'s machine-authored trust valve (the same boundary Plan Reviewer Criterion 14 enforces). Flagged here so 3b-ii inherits it.

## See Also
- `skills/rules/SKILL.md` — the protocol authority (schema, validation, merge order, read/write/check contracts, trust boundary).
- `scripts/read-rules.sh` — the fail-safe advisory reader (`set -uo pipefail`, always exits 0, READ-ONLY, never executes a `check`).
- `commands/setup.md` (`/setup twin`) — bootstraps a repo into Twin-readiness; `/rules` maintains the committed conventions. Shares the check/report/offer/apply/verify confirmed-write discipline.
