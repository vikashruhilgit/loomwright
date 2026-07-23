---
name: rules
description: Protocol authority for the /rules command and the committed .agent/rules/ house-rules substrate — the rule JSON schema + per-object fail-safe-skip validation, the v1 "applicable = all valid rules" read contract, the scan-to-suggest spec, the advisory/must/no-op-when-absent reader contract (read-rules.sh), the /rules add path-contained atomic-append write discipline (mechanized in add-rule.sh, with an optional `--supersedes` flag), the /rules retract remove-only write discipline (also mechanized in add-rule.sh), the /rules check human-invoked+confirmed execution semantics (mechanized in rules-check.sh), the single-hop supersession read contract, and the check-is-arbitrary-shell trust boundary (unattended `check` execution is now GATED via rules-check.sh --no-cmd). Use when running /rules or modifying any part of the rules substrate.
version: "1.2.0"
lastUpdated: "2026-07-23"
---

# Rules Skill

Protocol authority for `/rules` (see `${CLAUDE_PLUGIN_ROOT}/commands/rules.md` for the user-facing flows). The command owns orchestration and UX; this skill owns the schema, the contracts, and the trust boundary. When the two disagree, **this skill wins**.

> This is a **reference contract** skill (markdown prose, NOT executable code), in the same spirit as `skills/setup/SKILL.md` and `skills/automate-loop/SKILL.md`. There is **no `-runner` agent** — `/rules` is inline-only (agents stay 14).

`.agent/rules/` is the plugin's **first committed-convention surface**: a single, version-controlled source of truth for project conventions so an implementer can read them on the DO side, not only get caught on the REVIEW side. Slice #3b-i shipped the **SUBSTRATE** — the store, the schema, the fail-safe reader, and the `/rules` authoring command. **Slice #3b-ii (this skill's current state) adds ADVISORY enforcement:** the reader is now consumed (advisorily, never-gating) at the worker / Phase 4.5-self-heal / SessionStart-nudge seams; the `/rules add` write path is mechanized into the sole-writer `add-rule.sh` (with a real path-traversal-rejection test); and `/rules check` is mechanized into `rules-check.sh` with a default-off `--no-cmd` unattended trust valve. The reader still emits `check` as DATA and **NEVER executes it**. (Company-base ↔ per-project layering and Tier-3 learned conventions remain deferred — §10.)

---

## When to Use

- Executing any `/rules` flow (the command reads this skill at Step 0): `list`, `suggest`, `add`, `check`.
- Implementing or modifying `read-rules.sh` — the reader conforms to the contract below, never the reverse.
- Reviewing changes that touch `.agent/rules/` or the rules reader/command.

## When NOT to Use

- Project memory / lessons — those live in `.claude/agent-memory/` and `.supervisor/` (gitignored, per-user) and are read via `read-project-memory.sh` / `read-lessons.sh`. `.agent/rules/` is **committed** and travels with the repo.
- Enforcement at the worker / Phase 4.5 / nudge seams is now WIRED (advisory, never-gating) in slice #3b-ii — the reader is consumed at those seams, but it is context enrichment, not a gate.
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
| `applies_to` | path-glob / language / category | **no (optional)** | **RESERVED for a later slice's path/scope filtering. STILL inert — NOT consulted by the v1 reader (even after 3b-ii wired advisory enforcement, `applies_to` remains unactivated).** Forward-compat only — present in the schema so a later slice needs no schema change. |
| `supersedes` | string (rule `id`) | **no (optional)** | **Curation/anti-rot.** Names the `id` of an OLDER rule this one replaces. A LIVE rule's `supersedes` HIDES the named rule from `read-rules.sh` output (single-hop, non-transitive — see §5). Stamped only via `/rules add --supersedes <rule-id>`; OMITTED entirely (never an explicit `null`) when not supplied. A malformed / self-referential / dangling value is fail-safe-ignored by the reader (demote-never-crash, §5) — never a crash, never a suppression of the entry that carries it. |

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

`applies_to` exists in the schema (§1) but is **still inert** — reserved for a later slice, which will define and test path/scope/language filtering (3b-ii wired advisory enforcement WITHOUT activating `applies_to`). Until then, "applicable" means "valid".

---

## §4 — Reader input contract (no-hang)

`read-rules.sh` mirrors `read-postmortem.sh` / `read-bridge.sh`:

- It accepts **OPTIONAL positional args**. In v1 these are **informational / forward-compat only — they do NOT change the v1 output** (which is always "all valid rules"). They reserve the calling shape a later `applies_to` slice will use for scope filtering.
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
- **Supersession (curation/anti-rot, single-hop, non-transitive):** a LIVE (validation-surviving) rule's `supersedes` field HIDES the rule it names from this reader's output. "A supersedes B hides B; it does not chase B's own `supersedes`" — cycles cannot loop by construction. A `supersedes` value is a hiding edge ONLY when it is a non-null string naming another LIVE rule's `id`; a malformed, self-referential, or dangling `supersedes` is **fail-safe-ignored** (demote-never-crash) — the entry carrying it is still emitted normally, and the reader still exits 0 unconditionally. A supersedes **cycle of ANY length** (a mutual 2-entry `A⇄B`, or an n-hop `A→B→C→A`) is fail-safe-ignored on every side — every member of the cycle stays VISIBLE rather than hidden or looped. A node OUTSIDE a cycle whose `supersedes` points into it keeps its live single-hop edge (so an external `D` naming `A` still hides `A`, while the cycle members `A`/`B`/`C` remain visible among themselves).

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

**`--supersedes <rule-id>` (curation/anti-rot, optional).** An optional flag on the ADD action — NOT a separate verb. Stamps a `supersedes` member on the newly-authored object naming the id of an OLDER rule it replaces; OMITTED entirely (never an explicit `null`) when not supplied. Purely declarative: the named older rule is left untouched in its file — `read-rules.sh` is what hides it at read time (§5). Validated non-empty and newline-free at write time; a self-reference against the about-to-be-created id is rejected (exit non-zero); a dangling/unresolvable target is **not** rejected at write time (rejecting it would be a stricter, divergent policy from the reader's own fail-safe tolerance of a dangling `supersedes`). No `--replacement` flag exists here — the newly-added rule itself *is* the replacement content, unlike `retract` (§7.5) where a bare removal has no replacement to name.

---

## §7.5 — `/rules retract` write discipline (exact)

**Curation/anti-rot** added a second write action, `retract`, mirroring `curate-postmortem.sh`'s shape (`--target`/`--reason`/`--replacement`/`--confirm`) and its validate-before-write / fail-loud discipline — mechanized in the same sole-writer, `add-rule.sh`.

1. **Mutually exclusive.** `--retract` cannot be combined with any add-only flag (`--category`/`--statement`/`--check`/`--supersedes`) — combining them is rejected outright (non-zero), never silently ignored.
2. **`--target <rule-id>` required** — non-empty, newline/CR-free.
3. **`--reason <text>` required** — non-empty; this is the text printed in the provenance record (there is no in-store home for it — see below).
4. **`--replacement` is ALWAYS REJECTED** on `retract` (non-zero) — the inverse of `curate-postmortem.sh`'s own rationale for requiring `--replacement` on its `supersede` verb ("a supersede without a replacement would be an indistinguishable synonym for retract"): here, a replacement on a pure retract is the contradiction.
5. **Locate the target** across every **well-formed** (`jq -e 'type=="array"'`) `.agent/rules/*.json` array, `LC_ALL=C` path-sorted, first match. Not found (including "found only inside a malformed sibling file") ⇒ fail loud, nothing written.
6. **Confirm-only** — identical gate semantics to `add`: writes only on `--confirm` or an interactive TTY confirm; otherwise prints the planned retract and exits 0 without writing.
7. **Remove via temp-file + atomic `mv`** (never a partial/in-place edit); **read-back verify** the file still parses as an array AND no longer contains the target id.
8. **No in-store home for the reason.** `.agent/rules/` keeps `provenance` as a field INSIDE each rule object — deleting the object deletes its provenance, and adding a sidecar file for a post-deletion reason would violate the curation freeze (no new stores). The writer instead **PRINTS** a single provenance line to stdout naming the id, source file, and reason — this **IS** the durable record; the commit that lands the removal is the audit trail. There is **no in-place `retracted: true` marker** anywhere in this store — retraction REMOVES the object, matching the same "removes, not marks" semantics `write-lessons.sh retract` already ships for the lessons store.

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
- **Unattended execution of `check` commands is now MECHANIZED + GATED in `rules-check.sh`.** The checker carries a default-off `--no-cmd` unattended trust valve (mirroring `run-ground-truth.sh --no-cmd`, the same boundary Plan Reviewer Criterion 14 enforces for `cmd:` Executable-Acceptance bullets): a machine / unattended caller must NOT execute author-supplied shell without an explicit trust gate. **`--no-cmd` WINS over `--confirm`** if both are passed (fail-safe). No advisory seam ever calls `rules-check.sh` with execution enabled — the worker / Phase 4.5 / SessionStart-nudge seams consume `read-rules.sh` (which surfaces each `check` as DATA) and **the reader still never executes a check**.

### §9.1 — `/rules add` write path is MECHANIZED as the sole-writer `add-rule.sh` (with a real traversal-rejection test)

The security-sensitive `/rules add` write discipline (§7) — the slug-to-single-`[a-z0-9-]`-segment containment, the `/`/`..`/leading-dot/metachar/empty rejection, the array-only parse-gate, the atomic temp+`mv`, the read-back verify — is now **mechanized in code** as the sole-writer helper `${CLAUDE_PLUGIN_ROOT}/scripts/add-rule.sh`. `/rules add` is a thin caller that delegates to it. A dedicated test, `${CLAUDE_PLUGIN_ROOT}/scripts/test-add-rule.sh`, proves the containment holds — it asserts that `../escape`, `a/b`, `.hidden`, shell-metachar (`foo;rm -rf`, backtick), and empty categories are REJECTED (non-zero, diagnostic, no traversal write), that a clean category writes exactly `.agent/rules/<slug>.json`, and that the array-only parse-gate aborts rather than clobbers a non-array target. The write path — where a malicious/typo `category` could otherwise escape `.agent/rules/` — now has the same code+test rigor the reader already had.

---

## §10 — Company-base ↔ per-project layering (DEFERRED)

A layered model — a company-base rule set composed with per-project overrides — is **out of scope for this slice**. v1 reads only the repo-local `.agent/rules/*.json`. Layering (precedence, override semantics, where a company-base set lives) is **deferred** to a later slice and is noted here only so the substrate doesn't accidentally bake in assumptions that would block it.

---

## Anti-Patterns

- **Executing a `check` in the reader (or any unattended path).** The reader emits `check` as data, period. Unattended execution is now gated in `rules-check.sh --no-cmd` (default-off valve; `--no-cmd` wins over `--confirm`) — and no advisory seam ever enables it.
- **String-interpolating untrusted rule text into a shell command or a jq program.** Keep rule text inside jq's data model: the reader reads each file as a positional jq file-path argument (§2); the `/rules add` write path builds objects via `jq -n --arg` (§7). Never splice rule text into the program string or a shell command.
- **`set -e` in the reader, or a non-zero exit on a normal failure path.** A read must never break its caller — ALWAYS exit 0.
- **Letting `/rules add` write outside `.agent/rules/`.** The category is slugged to a single `[a-z0-9-]` segment and traversal/metachars/empty are rejected.
- **Clobbering an existing rule file on malformed/non-array JSON.** Parse-gate with `jq -e 'type=="array"'` and abort — never overwrite.
- **Blind-writing on `add` or `suggest`.** Both write ONLY on explicit user confirmation.
- **Guessing which rules "apply" in v1.** Applicable = all valid rules; `applies_to` is still inert (a later slice will define path/scope filtering — 3b-ii wired advisory enforcement without activating it).
- **Adding `.agent/` to `.gitignore`.** Rules are committed and must travel with the repo.
- **Chasing a `supersedes` chain transitively, or looping on a cycle.** Supersession is single-hop only (§5) — a mutual or n-hop cycle is fail-safe-ignored on every side, never chased and never a hang.
- **Adding a `--replacement` flag to `retract`, or a `--replacement`-less `supersede` verb.** `retract` has no replacement (§7.5); `--supersedes` (§7) is a flag on `add`, not a separate verb — this file has no `supersede` action.
- **Adding an in-store tombstone / `retracted: true` marker, or a provenance sidecar for retraction reasons.** Retraction REMOVES the object outright; the writer prints the reason to stdout and the commit is the durable record (§7.5) — a sidecar would violate the curation freeze (no new stores).

## Related Skills

- `setup/` — `/setup twin` bootstraps a repo into Twin-readiness; `/rules` maintains the committed conventions. Shares the check/report/offer/apply/verify confirmed-write discipline.
- `brain-context/` — the graph-if-present scanner the `suggest` flow degrades from (staleness-aware, grep fallback).
- `claude-md-validation/` — the convention patterns `suggest` mines.
- `error-handling/` / `monitoring-observability/` — the fail-safe reader idiom (`set -uo pipefail`, always-exit-0, diagnostics to `.supervisor/logs/`).
- `quality-checklist/` — gates for reviewing changes to this skill, the command, or the reader.

## Quality Gates

- [ ] `.agent/rules/` is NOT in `.gitignore` (rules are committed).
- [ ] The reader NEVER executes a `check` value (emits as data only); `/rules check` runs checks ONLY human-invoked + confirmed (via `rules-check.sh`); unattended execution is GATED via `rules-check.sh --no-cmd` (default-off valve, `--no-cmd` wins over `--confirm`) and no advisory seam enables it.
- [ ] Reader is `set -uo pipefail` (no `-e`), ALWAYS exits 0, READ-ONLY, emits the subordinate-to-CLAUDE.md banner only when a rule applies (EMPTY otherwise).
- [ ] Per-object validation is fail-safe-skip (missing field / unknown `enforcement` / duplicate `id` → skip + diagnostic to `.supervisor/logs/`, never crash); merge order is `LC_ALL=C` path-sorted, first-seen-id-wins.
- [ ] `applies_to` is documented as reserved for a later slice (still inert) and NOT consulted by the v1 reader.
- [ ] `/rules add` slugs the category to a single `[a-z0-9-]` segment (rejects `/`, `..`, leading dot, metachars, empty), parse-gates with `jq -e 'type=="array"'`, assigns a deterministic unique id, stamps `provenance.source`/`provenance.added`, writes via temp-file + atomic `mv`, verifies read-back, and writes ONLY on confirmation (append-only).
- [ ] `/rules add --supersedes <id>` is an optional flag (not a separate verb), OMITS the member entirely when unsupplied, and rejects only a self-reference at write time (a dangling target is the reader's fail-safe-ignore concern, not the writer's).
- [ ] `/rules retract` is mutually exclusive with add-only flags, requires `--target`+`--reason`, ALWAYS rejects `--replacement`, removes via temp-file + atomic `mv`, read-back verifies the id is gone, and PRINTS (never stores) the provenance reason.
- [ ] `read-rules.sh` hides a rule named by a LIVE rule's `supersedes` — single-hop, non-transitive — and fail-safe-ignores (never crashes on, never over-hides for) a malformed/self-referential/dangling/cyclic `supersedes`.
- [ ] No secret values written into a rule object.

## Token Cost

- Invocation: ~1,300 tokens (skill body)
- Storage: inline (markdown only)
- Context7: not required
