---
description: Maintain the committed .agent/rules/ house-rules substrate — list / suggest / add / retract / check project conventions an implementer can read on the DO side, not only get caught on the REVIEW side. Advisory enforcement is wired (never-gating) at the worker / Phase 4.5 / SessionStart-nudge seams; `add` (with optional `--supersedes`) and `retract` are both mechanized in add-rule.sh, `check` in rules-check.sh (unattended `check` execution gated via --no-cmd).
---

> **Reads code read-only on `list` / `suggest` / `check`; the write paths are `add` (append-only) and `retract` (curation/anti-rot, remove-only) — both write a single path-contained `*.json` under `.agent/rules/` on explicit confirmation, and both go through the sole-writer `add-rule.sh`.** `.agent/rules/` is the plugin's first **committed-convention** surface — version-controlled, travels with the repo (unlike the gitignored `.supervisor/` / `.claude/agent-memory/`). The protocol authority for every flow is `${CLAUDE_PLUGIN_ROOT}/skills/rules/SKILL.md` — read it at Step 0; when this command and that skill disagree, **the skill wins**.

# Command: /rules

> **The committed house-rules substrate.** `/rules` maintains a single, version-controlled source of truth for project conventions (`.agent/rules/*.json`) so an implementer can read them while doing the work, not only get caught on review. The substrate (store, schema, fail-safe reader `read-rules.sh`, this authoring command) shipped in slice #3b-i; **slice #3b-ii added ADVISORY enforcement** — the reader is consumed (never-gating, subordinate to CLAUDE.md) at the worker / Phase 4.5 self-heal / SessionStart-nudge seams; `/rules add` is mechanized into the sole-writer `add-rule.sh`; and `/rules check` is mechanized into `rules-check.sh` with a default-off `--no-cmd` unattended trust valve. The reader still surfaces each `check` as DATA and **never executes it**. **Curation/anti-rot** added a `supersedes` field (optional flag on `add`) and a `retract` action — both mechanized in `add-rule.sh`; see Subcommands below.

## Purpose

Conventions a team agrees on tend to live in heads, in CLAUDE.md prose, or get re-discovered every review round. `.agent/rules/` makes them **first-class, committed data**: zero-or-more `*.json` files, each a JSON array of rule objects (`id` · `category` · `statement` · `enforcement` (`advisory` | `must`) · `check` · `provenance` · optional `applies_to` · optional `supersedes`). `/rules` is how you read, propose, author, retract, and (human-invoked) verify them. The rules are **subordinate to CLAUDE.md** — on conflict, CLAUDE.md wins.

## Usage

```bash
/rules list                 # show all valid rules (advisory reader output)
/rules suggest              # scan the repo → PROPOSE rules for human review (never auto-writes)
/rules add                  # append one rule to .agent/rules/<category>.json (confirm-only)
/rules add --supersedes X   # append a rule that supersedes (hides) an OLDER rule id X
/rules retract              # remove an existing rule object by id (confirm-only)
/rules check                # human-invoked: run `must` rules' checks after explicit confirmation
```

## Subcommands

The protocol for each is defined in `skills/rules/SKILL.md` (§ numbers below); this restates the load-bearing contracts so the command is self-explanatory.

### `list` (§4, §5 — read-only)

Invoke the fail-safe reader and show its advisory output verbatim:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/read-rules.sh"
```

The reader merges `.agent/rules/*.json` in `LC_ALL=C` path-sorted, first-seen-`id`-wins order, fail-safe-skips any invalid object (missing field / unknown `enforcement` / duplicate `id`), and emits an advisory markdown block headed `## Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)` listing each rule's `statement`, `category`, a `must` flag for `must` rules, and its `check` **shown as DATA only — text, never executed by the reader.** It emits NOTHING and exits 0 when no valid rule exists (so machine consumers can gate on non-empty stdout). v1 emits **all valid rules** — there is no path/scope guessing; `applies_to` is still inert (reserved for a later slice — 3b-ii wired advisory enforcement without activating it).

### `suggest` (§6 — scan-to-suggest, propose-only)

Analyze the repo and **PROPOSE** rules — never blank-slate-ask, never auto-write (mirrors `/setup twin`'s offer model):

- **Scanner (degrades gracefully, never blocks):** always grep / glob / read of the repo; **graph-if-present** via `brain-context` (graphify graph when present, staleness-aware, grep fallback — never hard-depends on the external `graphify` CLI); plus `claude-md-validation` convention patterns.
- **Output:** a list of proposed rule objects (suggested `category` / `statement` / `enforcement` / `check`), surfaced for human review.
- **Human-confirmed:** nothing is written without explicit user confirmation. On confirm, each accepted proposal is routed through the `add` write discipline below.
- **Never blocks** and never auto-applies.

### `add` (§7 — append-only write discipline, confirm-only)

`add` is a **thin caller** of the sole-writer helper `${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.sh` — it does **not** re-implement the write in prose. The helper enforces the §7 write discipline **in code** (path containment + value validation + array-only parse-gate + atomic append), so the command just collects the fields and delegates:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.sh" \
  --category "<category>" \
  --statement "<statement>" \
  --enforcement "<advisory|must>" \   # optional, default advisory
  --check "<shell string>" \          # optional, default null (omit for a null check)
  --source "<who/what added it>" \    # optional, default "/rules add"
  --supersedes "<older-rule-id>" \    # optional (curation/anti-rot) — see below
  --confirm                           # write only when passed (see confirm-only)
```

The helper, per `add-rule.sh` (mechanizing SKILL.md §7):

1. **Category containment (in code).** Slugs a **legitimate** `category` to a single `[a-z0-9-]` path segment via benign normalization only, and **REJECTS** (aborts, non-zero, with a diagnostic — never silently sanitizes) any `category` containing `/`, `..`, a leading dot, shell metacharacters, or that is empty / empty-after-slug. The write can **NEVER escape `.agent/rules/`**.
2. **Value validation before writing** (so it never authors a rule `read-rules.sh` would skip): non-empty `statement` + non-empty derived `statement-slug`; `enforcement` exactly `advisory`|`must`; `check` a string or null; `--supersedes` (when given) non-empty, newline-free, and rejected as a self-reference against the about-to-be-created id.
3. **Array-only parse-gate** the target `.agent/rules/<category-slug>.json` with `jq -e 'type=="array"'` — **ABORT, never clobber** a malformed or valid-but-non-array pre-existing file; create as a single-element array if absent.
4. **Deterministic unique `id`** = `<category-slug>-<statement-slug>`, suffixed `-N` (`-2`, `-3`, …) on collision across the **merged set** (matching the reader's global dedup scope).
5. **Stamps** `provenance.source` (from `--source`) + `provenance.added` (UTC ISO-8601), builds the object with `jq -n --arg …` (never string-interpolating untrusted input), writes via **temp-file + atomic `mv`**, then **read-back verifies** the file parses and contains the new id.
6. **Confirm-only:** writes ONLY when `--confirm` is passed (or an interactive TTY confirms). With no `--confirm` and non-interactive, it **prints the planned write and writes nothing**. Append-only — never edits or removes an existing rule via the ADD action (`--retract`, below, is the one sanctioned exception).

The path-containment and validation guarantees are proven by `scripts/test-add-rule.sh` (rejects `../escape`, `a/b`, `.hidden`, `foo;rm -rf`, backtick, and empty categories; asserts no traversal write).

**`--supersedes <rule-id>` (curation/anti-rot, optional flag on `add`).** Stamps a `supersedes` member — naming the id of an OLDER rule this one replaces — onto the *newly-authored* rule object. Purely declarative: the older rule object is left untouched in its file; it is `read-rules.sh` (the reader) that hides it from output at read time (single-hop, non-transitive — "A supersedes B hides B; it does not chase B's own supersedes"). A malformed / self-referential / dangling `supersedes` is fail-safe-ignored by the reader (demote-never-crash) — self-reference against the about-to-be-created id is additionally rejected at write time. There is no separate `supersede` **action** in this file (unlike `write-lessons.sh`'s `supersede` verb, or `add-orientation.sh`'s `--supersedes` action) — here it is only ever an optional flag on the default ADD action, because the newly-added rule itself *is* the replacement content; no `--replacement` flag exists or is needed.

### `retract` (curation/anti-rot — remove an existing rule, confirm-only)

`retract` is a **new action** on the same sole-writer helper, mutually exclusive with every add-only flag, mirroring `curate-postmortem.sh`'s shape (`--target`/`--reason`/`--replacement`/`--confirm`) and its validate-before-write / fail-loud discipline:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.sh" \
  --retract \
  --target "<rule-id>" \    # required — the id of the rule object to remove
  --reason "<text>" \       # required — printed as the one-line provenance record
  --confirm                 # write only when passed (see confirm-only)
```

- `--target` and `--reason` are both **required**; `--replacement` is **ALWAYS REJECTED** on `retract` — a bare removal has no meaningful "replacement" (the inverse of `curate-postmortem.sh`'s own rationale for requiring `--replacement` on its `supersede` verb: "a supersede without a replacement would be an indistinguishable synonym for retract" — here, a replacement on a pure retract is the contradiction).
- The target id is located across every **well-formed** `.agent/rules/*.json` array (`LC_ALL=C` path-sorted, first match); not found ⇒ fail loud, nothing written.
- Confirm-only (identical gate semantics to `add`): writes only on `--confirm` or an interactive TTY confirm; otherwise prints the planned retract and exits without writing.
- Removes the object via temp-file + atomic `mv`; read-back verifies the file still parses as an array and no longer contains the target id.
- **There is no in-store home for the retraction reason** (adding one would violate the curation freeze — see the job brief's Normative encoding contract), so the writer **PRINTS** a one-line provenance record (`retracted rule id=<id> from <file> — reason: <reason>`) to stdout; the commit that lands the removal is the durable record.

### `check` (§8 — HUMAN-invoked only)

`check` is a **thin caller** of the sole-execution helper `${CLAUDE_PLUGIN_ROOT}/scripts/rules-check.sh` — it does **not** re-implement check execution in prose. The helper is the ONLY path in the whole slice that runs a rule's `check`, and it does so only behind an explicit confirmation gate:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/rules-check.sh" \
  --confirm       # execute the checks (equivalently RULES_CHECK_CONFIRM=1, or an interactive TTY confirm)
# bash "${CLAUDE_PLUGIN_ROOT}/scripts/rules-check.sh" --no-cmd   # unattended trust valve: skip ALL execution
```

The helper, per `rules-check.sh` (mechanizing SKILL.md §8):

- **Reads the store DIRECTLY via jq** for the RAW `.check` string — reusing `read-rules.sh`'s per-object validation + `LC_ALL=C` first-seen-`id`-wins dedup. It **never parses the reader's human-facing markdown** (whose `gsub("[\t\n]"; " ")` render is LOSSY); the executed command is **byte-exact** to the authored rule.
- Runs ONLY `must` rules whose `check` is a **non-null string** (advisory rules and null-check rules are skipped — never run).
- Each selected command runs from the **repo root** via `bash -c`, **DISPLAYED before running**, and an **aggregate pass/fail** summary is printed.
- **Confirmation gate:** executes ONLY after explicit confirmation — an interactive TTY prompt, `--confirm`, or `RULES_CHECK_CONFIRM=1`. Under **non-interactive / no-confirm** (CI, stdin-not-tty, no flag) it runs **nothing** and reports `skipped — needs confirmation` for each.
- **Default-off unattended valve `--no-cmd` (or `RULES_CHECK_NO_CMD=1`)** skips all execution, recording `cmd execution disabled` — and **`--no-cmd` WINS over `--confirm`** if both are passed (fail-safe). This mirrors `run-ground-truth.sh --no-cmd`, the trust valve for machine/unattended callers.
- It is **NOT an unattended gate** in this slice — human-invoked only; it never blocks a PR, a worker, or a merge.

## Trust boundary (`check` is arbitrary shell — §9)

A `check` value is **arbitrary shell authored by anyone who cloned or PR'd the repo** — untrusted data everywhere except one explicit, confirmed path:

- **The reader (`read-rules.sh`) emits `check` as DATA and the `check` is never executed by the reader** — there is no code path in it that runs a `check`. Safe for any unattended caller (a hook, a worker, a future enforcement seam) with zero code-execution risk.
- **`/rules check` requires confirmation** — it is HUMAN-invoked only, DISPLAYS each `must`-rule's `check`, and runs it ONLY after explicit confirmation. It never blind-executes a check authored by a cloning teammate.
- **Unattended execution of `check` commands is now MECHANIZED + GATED in `rules-check.sh`** — its default-off `--no-cmd` valve (which WINS over `--confirm`) inherits `run-ground-truth.sh --no-cmd`'s machine-authored trust boundary (the same boundary Plan Reviewer Criterion 14 enforces). The advisory seams (worker / Phase 4.5 / SessionStart-nudge) consume the READER only — which surfaces each `check` as DATA and never executes it.

## See Also
- `skills/rules/SKILL.md` — the protocol authority (schema, validation, merge order, read/write/check contracts, trust boundary).
- `scripts/read-rules.sh` — the fail-safe advisory reader (`set -uo pipefail`, always exits 0, READ-ONLY, never executes a `check`).
- `commands/setup.md` (`/setup twin`) — bootstraps a repo into Twin-readiness; `/rules` maintains the committed conventions. Shares the check/report/offer/apply/verify confirmed-write discipline.
