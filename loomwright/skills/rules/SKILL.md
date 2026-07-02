---
name: rules
description: Protocol authority for the /rules command and the committed .agent/rules/ house-rules substrate — the rule JSON schema + per-object fail-safe-skip validation, the v1 "applicable = all valid rules" read contract, the scan-to-suggest spec, the advisory/must/no-op-when-absent reader contract (read-rules.sh), the /rules add path-contained atomic-append write discipline, the /rules check human-invoked+confirmed execution semantics, and the check-is-arbitrary-shell trust boundary (unattended execution DEFERRED to slice 3b-ii). Use when running /rules or modifying any part of the rules substrate.
version: "1.0.0"
lastUpdated: "2026-06-30"
---

# Rules Skill

Protocol authority for `/rules` (see `${CLAUDE_PLUGIN_ROOT}/commands/rules.md` for the user-facing flows). The command owns orchestration and UX; this skill owns the schema, the contracts, and the trust boundary. When the two disagree, **this skill wins**.

> This is a **reference contract** skill (markdown prose, NOT executable code), in the same spirit as `skills/setup/SKILL.md` and `skills/automate-loop/SKILL.md`. There is **no `-runner` agent** — `/rules` is inline-only (agents stay 14).

`.agent/rules/` is the plugin's **first committed-convention surface**: a single, version-controlled source of truth for project conventions so an implementer can read them on the DO side, not only get caught on the REVIEW side. This skill governs **slice #3b-i: the SUBSTRATE only** — the store, the schema, the fail-safe reader, and the `/rules` authoring command. **Enforcement wiring at the three seams (worker / Phase 4.5 / nudge), close-the-loop, and unattended `check` execution are slice #3b-ii** and are explicitly out of scope here.

---

## When to Use

- Executing any `/rules` flow (the command reads this skill at Step 0): `list`, `suggest`, `add`, `check`.
- Implementing or modifying `read-rules.sh` — the reader conforms to the contract below, never the reverse.
- Reviewing changes that touch `.agent/rules/` or the rules reader/command.

## When NOT to Use

- Project memory / lessons — those live in `.claude/agent-memory/` and `.supervisor/` (gitignored, per-user) and are read via `read-project-memory.sh` / `read-lessons.sh`. `.agent/rules/` is **committed** and travels with the repo.
- Enforcement at the worker / Phase 4.5 / nudge seams — **slice #3b-ii**, not this slice.
- Bootstrapping a fresh repo into a Twin-ready state — `/setup twin` *bootstraps*; `/rules` *maintains*. (Division per `docs/SPIKES/NORTH_STAR_DIRECTION.md`.)

---

## §1 — The rule schema

`.agent/rules/` is a **version-controlled** directory (NOT gitignored — unlike `.supervisor/`) holding **zero-or-more `*.json` files, each a JSON ARRAY of rule objects**. Each rule object:

```json
{
  "id": "version-validate-version-script-must-pass",
  "category": "version",
  "statement": "scripts/validate-version.sh must exit 0 before a version bump lands.",
  "enforcement": "must",
  "check": "bash scripts/validate-version.sh",
  "provenance": { "source": "/rules add", "added": "2026-06-30T12:00:00Z" },
  "applies_to": null
}
```

| Field | Type | Required | Rule |
|---|---|---|---|
| `id` | string | **yes** | UNIQUE across the merged set (see §2 merge order). |
| `category` | string | **yes** | The convention's category; also drives the target filename for `/rules add` (slugified — §7). |
| `statement` | string | **yes** | The human-readable rule text. |
| `enforcement` | enum | **yes** | EXACTLY one of `advisory` \| `must`. Any other value ⇒ the object is SKIPPED (§2). |
| `check` | string \| null | **yes** | A runnable shell string OR `null`. **Emitted as DATA only by the reader — NEVER executed by it** (§5, §9). |
| `provenance` | object | **yes** | e.g. `{source, added, ...}`. `source` records who/what added the rule; `added` is a UTC ISO-8601 timestamp. |
| `applies_to` | path-glob / language / category | **no (optional)** | **RESERVED for slice #3b-ii enforcement filtering. NOT consulted by the v1 reader.** Forward-compat only — present in the schema so 3b-ii needs no schema change. |

The `check` value is **arbitrary shell** authored by anyone who clones or PRs the repo. Treat it as untrusted data everywhere except the one human-invoked + confirmed path (§8, §9).

---

## §2 — Per-object validation (fail-safe-skip) + deterministic merge order

The reader validates **each rule object independently** and SKIPS — never crashes on — any object that:

- is missing a required field (`id` / `category` / `statement` / `enforcement` / `check` / `provenance`), OR
- carries an unknown `enforcement` value (anything other than `advisory` / `must`), OR
- duplicates an `id` already seen in the merged set.

A skipped object is dropped from output and gets a **one-line diagnostic to `.supervisor/logs/`** (NEVER to stdout). The reader STILL exits 0 and STILL emits every remaining valid rule. A single malformed object never suppresses its valid siblings.

**Deterministic merge order (so "first-seen `id` wins" is reproducible):**

1. Glob `.agent/rules/*.json` and process the files in **`LC_ALL=C` repo-relative-path-sorted** order.
2. Within each file, process the array **by index**.
3. The **FIRST valid occurrence** of an `id` wins; any later object with the same `id` is a duplicate and is SKIPPED.

This makes the merged set a pure function of the committed files — identical across runs and across machines.

**Injection safety (jq-only):** untrusted rule text (statements, checks, ids, paths) enters jq ONLY by jq reading the rule file as a **positional file-path argument** (`jq … "$file"`, the path sourced from `find`, never from rule content); the only flag-passed value is `--argjson fi`, the trusted integer file index. Rule text is NEVER string-interpolated into a shell command or into a jq program, and the jq program text is fixed. (Same injection-safety *property* as `read-bridge.sh`, but the *mechanism differs*: `read-bridge.sh` passes corpus text via `--rawfile`/`--slurpfile`/`--argjson`, whereas this reader reads each rule file positionally. The `/rules add` **write** path is the one place that uses `jq -n --arg` — see §7 — to build a new object from user input without interpolation.)

---

## §3 — v1 "applicable = ALL valid rules" (no guessing)

In v1 there is **NO path/scope filtering**. The reader emits **ALL valid rules** in the merged set — full stop. There is no heuristic that tries to guess which rules apply to a given file or change; doing so without an explicit, tested contract would be guessing, so v1 doesn't.

`applies_to` exists in the schema (§1) but is **inert in v1** — reserved for slice #3b-ii, which will define and test path/scope/language filtering. Until then, "applicable" means "valid".

---

## §4 — Reader input contract (no-hang)

`read-rules.sh` mirrors `read-postmortem.sh` / `read-bridge.sh`:

- It accepts **OPTIONAL positional args**. In v1 these are **informational / forward-compat only — they do NOT change the v1 output** (which is always "all valid rules"). They reserve the calling shape 3b-ii will use for scope filtering.
- It **NEVER blocks on stdin in a non-TTY context.** Args take precedence; **if no args are given AND stdin is not a TTY, the reader does NOT read stdin.** So a future hook / agent caller (whose stdin is an open-but-idle pipe) can never hang it.

---

## §5 — The READ contract (advisory / must / no-op-when-absent)

`read-rules.sh` is the fail-safe reader — same idiom as `read-bridge.sh` / `read-lessons.sh`:

- **Shell discipline:** `set -uo pipefail` — **NO `set -e`** ("a read must never break its caller").
- **ALWAYS exits 0.** Absent `.agent/rules/` dir, empty dir, malformed JSON, and `jq` unavailable ALL → emit nothing, exit 0.
- **READ-ONLY.** Writes nothing except optional diagnostics to stderr / `.supervisor/logs/`.
- **Output when rules apply:** an advisory markdown block headed exactly:

  `## Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)`

  listing each applicable rule with its `statement`, its `category`, **`must` flagged** (advisory rules unflagged), and its `check` shown as **DATA only** (text — never run). Emit rules in a **deterministic order** (e.g. category then id) so output is stable across runs.
- **Empty when nothing applies:** emits NOTHING (no banner) when no valid rule exists — so machine consumers can gate on **non-empty stdout**.
- **The invariant (§9):** the reader emits each `check` as data and **NEVER executes it** — there is no code path in the reader that runs a `check` value. This is what makes the reader safe to call from a future unattended seam with zero code-execution risk.

---

## §6 — The scan-to-suggest spec (`/rules suggest`)

`/rules suggest` analyzes the repo and **PROPOSES** rules; it **never blank-slate-asks, never auto-writes** (mirror `/setup twin`):

- **Scanner (degrades gracefully, never blocks):**
  - **Always:** grep / glob / read of the repo (conventions visible in code, config, existing docs).
  - **Graph-if-present:** `brain-context` (graphify graph when present, **staleness-aware** — degrades to grep when the graph is absent or stale; never hard-depends on the external `graphify` CLI).
  - `claude-md-validation` patterns (the conventions a well-formed CLAUDE.md already encodes).
- **Output:** a list of PROPOSED rule objects (with suggested `category` / `statement` / `enforcement` / `check`), surfaced for human review.
- **Human-confirmed:** nothing is written without explicit user confirmation. On confirm, each accepted proposal goes through the `/rules add` write discipline (§7).
- **Never blocks** and never auto-applies.

---

## §7 — `/rules add` write discipline (exact)

Append-only authoring. The discipline mirrors the setup settings-merge (parse-gate → atomic write → verify). **Writes ONLY on explicit user confirmation — never blind-write.** Never edits or removes an existing rule in this slice (append-only).

1. **Target filename = slugified category (path containment).** The target file is `.agent/rules/<category-slug>.json` where `<category-slug>` is the `category` lowercased and reduced to `[a-z0-9-]` only. **REJECT / sanitize** any `category` that contains `/`, `..`, a leading dot, shell metacharacters, or is empty after slugging — so the write can **NEVER escape `.agent/rules/`** (it is always a single path segment under that dir). An invalid category aborts the add (never falls through to a default path).
2. **Parse-gate the existing target.** If `.agent/rules/<category-slug>.json` exists, gate it with `jq -e 'type=="array"'`. **ABORT — never clobber —** on malformed JSON OR valid-but-non-array JSON (rule files MUST be arrays). If absent, the file is created as a **single-element array**.
3. **Deterministic unique `id`.** `id = "<category-slug>-<statement-slug>"`. On collision (the id already exists in the **merged set**, not just the target file), append a numeric `-N` suffix (`-2`, `-3`, …) until unique.
4. **Stamp provenance.** Set `provenance.source = "/rules add"` (or the user-provided source) and `provenance.added = <UTC ISO-8601>`.
5. **Append via jq, atomically.** Build the new object with `jq -n --arg …` (never string-interpolate untrusted input), append to the array, write to a **temp file**, then **atomic `mv`** over the target.
6. **Verify.** Read the appended rule back (e.g. via `read-rules.sh` or a `jq` re-parse) to confirm it landed and parses.

---

## §8 — `/rules check` execution semantics

`/rules check` is the ONLY path in this slice that runs a rule's `check`, and it is **HUMAN-invoked only**:

- Runs ONLY `must` rules whose `check` is **non-null** (advisory rules and null-check rules are skipped).
- Each command runs from the **repo root** via `bash -c`.
- **Every command is DISPLAYED before running and executes ONLY after explicit confirmation.**
- Under **non-interactive / no-confirm** (CI, stdin-not-tty, or `--no-confirm`), it does **NOT run any check** — it reports `skipped — needs confirmation` for each.
- Reports an **aggregate pass/fail** summary at the end.
- It is **NOT an unattended gate** in this slice — human-invoked only. It never blocks a PR, a worker, or a merge.

---

## §9 — Trust boundary (`check` is arbitrary shell)

The `check` field is **arbitrary shell authored by anyone who cloned or PR'd the repo** — so it is treated as untrusted data everywhere except one explicit, confirmed path:

- **The reader (`read-rules.sh`) emits `check` as DATA and NEVER runs it** — safe for any unattended caller (a hook, a worker, a future enforcement seam) with zero code-execution risk.
- **`/rules check` is HUMAN-invoked only** — the trust anchor is the user running it. It DISPLAYS each `must`-rule's `check` and runs it ONLY after explicit confirmation (it never blind-executes a check authored by a cloning teammate).
- **Unattended execution of `check` commands (the worker / Phase 4.5 enforcement seams) is explicitly DEFERRED to slice #3b-ii and MUST be gated there.** The gating model to inherit is `run-ground-truth.sh --no-cmd`'s machine-authored trust valve (the same boundary Plan Reviewer Criterion 14 enforces for `cmd:` Executable-Acceptance bullets): a machine / unattended caller must NOT execute author-supplied shell without an explicit trust gate. **This requirement is flagged here so 3b-ii inherits it.**

### §9.1 — `/rules add` write path is PROSE-only in v1 — mechanize + test it in 3b-ii (inherited requirement)

In this slice the security-sensitive `/rules add` write discipline (§7) — the slug-to-single-`[a-z0-9-]`-segment containment, the `/`/`..`/leading-dot/metachar/empty rejection, the array-only parse-gate, the atomic temp+`mv`, the read-back verify — is **specified as command/skill PROSE the agent follows at runtime**, with **no dedicated `add-rule.sh` and no test** proving (e.g.) that a `../escape` category is actually rejected. This is intentional and consistent with "substrate only" (the read path, which cannot write, is the mechanized + heavily-tested surface). **3b-ii MUST mechanize the write discipline into a sole-writer helper with a path-traversal-rejection test before any unattended/enforcement seam leans on it** — the write path is where a malicious/typo `category` could escape `.agent/rules/`, so it needs the same code+test rigor the reader already has. Flagged here so 3b-ii inherits it.

---

## §10 — Company-base ↔ per-project layering (DEFERRED)

A layered model — a company-base rule set composed with per-project overrides — is **out of scope for this slice**. v1 reads only the repo-local `.agent/rules/*.json`. Layering (precedence, override semantics, where a company-base set lives) is **deferred** to a later slice and is noted here only so the substrate doesn't accidentally bake in assumptions that would block it.

---

## Anti-Patterns

- **Executing a `check` in the reader (or any unattended path).** The reader emits `check` as data, period. Unattended execution is 3b-ii's gated problem.
- **String-interpolating untrusted rule text into a shell command or a jq program.** Keep rule text inside jq's data model: the reader reads each file as a positional jq file-path argument (§2); the `/rules add` write path builds objects via `jq -n --arg` (§7). Never splice rule text into the program string or a shell command.
- **`set -e` in the reader, or a non-zero exit on a normal failure path.** A read must never break its caller — ALWAYS exit 0.
- **Letting `/rules add` write outside `.agent/rules/`.** The category is slugged to a single `[a-z0-9-]` segment and traversal/metachars/empty are rejected.
- **Clobbering an existing rule file on malformed/non-array JSON.** Parse-gate with `jq -e 'type=="array"'` and abort — never overwrite.
- **Blind-writing on `add` or `suggest`.** Both write ONLY on explicit user confirmation.
- **Guessing which rules "apply" in v1.** Applicable = all valid rules; `applies_to` is inert until 3b-ii.
- **Adding `.agent/` to `.gitignore`.** Rules are committed and must travel with the repo.

## Related Skills

- `setup/` — `/setup twin` bootstraps a repo into Twin-readiness; `/rules` maintains the committed conventions. Shares the check/report/offer/apply/verify confirmed-write discipline.
- `brain-context/` — the graph-if-present scanner the `suggest` flow degrades from (staleness-aware, grep fallback).
- `claude-md-validation/` — the convention patterns `suggest` mines.
- `error-handling/` / `monitoring-observability/` — the fail-safe reader idiom (`set -uo pipefail`, always-exit-0, diagnostics to `.supervisor/logs/`).
- `quality-checklist/` — gates for reviewing changes to this skill, the command, or the reader.

## Quality Gates

- [ ] `.agent/rules/` is NOT in `.gitignore` (rules are committed).
- [ ] The reader NEVER executes a `check` value (emits as data only); `/rules check` runs checks ONLY human-invoked + confirmed; unattended execution is DEFERRED to 3b-ii (flagged).
- [ ] Reader is `set -uo pipefail` (no `-e`), ALWAYS exits 0, READ-ONLY, emits the subordinate-to-CLAUDE.md banner only when a rule applies (EMPTY otherwise).
- [ ] Per-object validation is fail-safe-skip (missing field / unknown `enforcement` / duplicate `id` → skip + diagnostic to `.supervisor/logs/`, never crash); merge order is `LC_ALL=C` path-sorted, first-seen-id-wins.
- [ ] `applies_to` is documented as reserved for 3b-ii and NOT consulted by the v1 reader.
- [ ] `/rules add` slugs the category to a single `[a-z0-9-]` segment (rejects `/`, `..`, leading dot, metachars, empty), parse-gates with `jq -e 'type=="array"'`, assigns a deterministic unique id, stamps `provenance.source`/`provenance.added`, writes via temp-file + atomic `mv`, verifies read-back, and writes ONLY on confirmation (append-only).
- [ ] No secret values written into a rule object.

## Token Cost

- Invocation: ~1,300 tokens (skill body)
- Storage: inline (markdown only)
- Context7: not required
