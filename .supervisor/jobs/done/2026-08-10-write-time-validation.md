# Supervisor Job: Validate before you write — five shared checks across six sole writers, a real agent-memory write path, and a proposal queue

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main @ c6bfda6 (origin/main; carries PR #138 v15.31.0 applies_to routing AND PR #139 v15.32.0 citation-drift guard)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (7 git worktrees present — pre-existing, unrelated to this item)
- **Source requirement:** .supervisor/requirements/twin-loop/04-write-time-validation.md

## Feasibility (Phase 2.5)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + jq, matching all five existing sole writers. No new runtime. |
| 2 | Dependency Availability | GO | `jq` already a soft dependency of every writer; the allowlist reader (`setup-memory.sh allowlist`) already exists and is the single consumer this item shares. |
| 3 | Architecture Fit | GO | The proposal-queue half is a **verbatim mirror** of a shipped, proven pattern (`.supervisor/orientation-proposals/` → `/dreaming` per-item Accept → `add-orientation.sh --confirm`), verified live at `add-orientation.sh:8`, `commands/dreaming.md:5`, `:157`, `:325`, and `skills/self-heal-advisory/SKILL.md:939`. No new trust model. |
| 4 | Scope vs Supervisor Capability | CAUTION | This is the **largest item in the twin-loop queue** — 6 writers + 1 new script + 6 agent prompts + the shared agent contract + release surface + tests. **27 files expected to change** (5 create + 22 modify — the sum of the Est. Files column), across **32 declared lane paths** — the 5 extra are subtask 2's collateral suites (AC10d), declared so a fixture broken by a *correct* refusal is fixable in-lane rather than out-of-lane, and expected to stay untouched. Either figure is **over** the `context-bound` bound (`> 12 files changed OR > 800 changed lines`), so the brief **SPLITS into 4 sequentially-ordered subtasks** (`Split reason: context-bound`). Plan Review round 1 correctly rejected an earlier single-subtask form whose rationale conflated *splitting* with *parallelising*; `file-conflict` is itself a legal split reason, and ordering here comes from `requires` edges over four fully disjoint lane sets. |
| 5 | Hard Blockers | GO | No migration framework, no credentials, no missing module. `write-agent-memory.sh` confirmed ABSENT (`ls` — it is a create, not a modify). |

**Overall Verdict:** CAUTION (proceed; the size risk is recorded in Risk Assessment R1)

## Task
**Goal:** Make every write to a curated store pass five deterministic validations first, give agent memory a real validated write path that owns its own `MEMORY.md` index, and mirror the proven orientation-proposal queue for agent-authored proposals — without introducing autonomous agent writes, autonomous deletion, or any new gate.

**Problem Statement:**
The plugin's curated stores need a write-time guard because curation currently happens only when a human types a command. Today the five sole writers append without looking around first, so a store only ever grows and quietly accumulates entries that are no longer true. This causes contaminated, contradicting, and dead-referencing entries to persist — and, on the agent-memory side, there is no sanctioned write path at all, so the only writes are hand-pasted, which is how one index rotted badly enough to make 17 files invisible to the agents that own them.
Success looks like: a seeded violation of each of the five checks is refused with a named reason by every sole writer, an agent-memory entry can round-trip proposal → validated write → indexed store, and the index can no longer rot because the writer owns it.

## PRE-FLIGHT CORRECTIONS TO THE SOURCE REQUIREMENT (verified at plan time — do NOT re-derive, do NOT re-litigate)

These were measured against the running system during Phase 3. Each **overrules** the requirement's own wording where they conflict.

1. **The `1-of-18` index rot is ALREADY REPAIRED — do not go hunting it.** Item 01b fixed it. Live measurement today: `.claude/agent-memory/loomwright-loomwright-code-reviewer/` = 19 files / 18 index pointers; `…-qa-executor/` = 6 / 5; `…-red-team-reviewer/` = 6 / 5. Every store is `N` files / `N-1` pointers because `MEMORY.md` does not index itself. **Consequence, and it is load-bearing:** the AC "a seeded unindexed file is corrected" MUST be proven against a **seeded fixture store in a temp dir**, never against the live store — a test that merely observes an already-healthy live store passes identically against a `write-agent-memory.sh` that does nothing, which is the vacuous-test class this repo keeps catching. **Owner decision (2026-08-10): record the correction, keep the AC, fixture-only.** Widening to a standing live-store parity gate was offered and NOT chosen — do not add one.

2. **`code-reviewer`'s `Write` is blocked by `disallowedTools`, NOT by omission from `tools:`.** `agents/code-reviewer.md:4` lists `Write` in `tools:`; `:13` is `disallowedTools: Write, Edit, NotebookEdit, Task, TaskOutput, WebSearch, WebFetch`, and `:9-11` explains that `permissionMode` is silently ignored for plugin-distributed agents so `disallowedTools` is the enforcement that survives distribution. A worker who "fixes" the `tools:` line would break the documented mechanism. `:95` further records that Bash is NOT restricted by the harness and read-only is a prompt-level contract there — so a Bash-based memory write is reachable for every one of the six agents regardless of `disallowedTools`, which is exactly why scope 6's answer has to be stated in the prompts and not assumed from the tool list.

3. **The requirement's line counts in the independence caveat are STALE; the conclusion is NOT.** Re-measured: `write-lessons.sh` 541 (req. says 460), `write-project-memory.sh` 300 (says 123), `add-rule.sh` 551 (says 435), `add-orientation.sh` 476 ✓, `write-system-contract.sh` 169 ✓. Items 01c/02/03 grew them. **Independently re-verified the claim that actually matters:** all five have **zero** `source`/`.` lines — the standalone shape is real, not incidental. Use the re-measured facts; do not quote the requirement's numbers.

4. **`agents/rubric-grader.md:49` is CORRECT as cited** (`- **No memory writes.** This agent does not have \`memory: project\` and must not write to \`.claude/agent-memory/\`.`). `agents/code-reviewer.md:293` also resolves and supports what the requirement uses it for (the memory-consult step is read-only) — note the `**Consult memory (advisory, read-only)**` **heading** is at `:292`; `:293` is its first bullet. Both were checked because base `c6bfda6` now carries **PR #139's citation-drift guard** (`loomwright/scripts/test-citation-drift.sh`, fail-closed). **This is a NEW gate that did not exist when this requirement was written, and it is a RATCHET, not merely a resolver:** its bare-citation check fails a **NEW** bare `file:N` *even when the line resolves*, unless the citation carries a `[pins: <literal>]` marker or is added to the script's `BARE_ALLOWLIST` (which a companion check then polices for staleness). So "make it resolve" is NOT sufficient. Prefer **descriptive anchors** over line numbers in all new prose — the discipline item 03's drain converged on after inflicting `:311→:319` drift on itself.

5. **THE ALLOWLIST RUNS THE OPPOSITE WAY FROM WHAT THE REQUIREMENT ASSUMES — this correction is the single most load-bearing item in this brief.** The source requirement (scope 1) says to "derive org and short names from the allowlist's **known foreign slugs**", which presumes the allowlist is a DENY list of other people's repos. **It is not.** Verified in `loomwright/scripts/setup-memory.sh`: the allowlist is **this repo's own permitted slugs** — it defaults to the current git remote when unset, and `filter-ledger` **KEEPS** records whose `.repo` **is in** it (its usage line reads "print ledger records whose `.repo` is in the allowlist"). The gate's stated purpose is that a foreign slug like `otherhub` is **NOT** in the allowlist: "the ledger negation is emitted only while every record's `.repo` sits inside the resolved allowlist. Otherwise the negation is WITHHELD, the offending slugs are NAMED". Live value here is `["vikashruhilgit/ai-agent-manager", "vikashruhilgit/loomwright"]` — this repo and its pre-rename name.

   **Therefore the cross-repo check reads: REFUSE an entry whose prose cites a repo-shaped token that is NOT in the allowlist; PASS a token that IS in it.** Implementing the requirement's literal wording would invert it — refusing citations of *this* repo and passing genuinely foreign ones — and would go **fully green on every AC while behaving backwards**, which is worse than a no-op.

   **Two consequences the worker must not undo:**
   - **NEVER add a foreign slug to the allowlist, in a fixture or anywhere else.** Doing so makes `setup-memory.sh apply` judge foreign ledger records clean and **emit** the negation that un-ignores `.supervisor/postmortem/results.jsonl` — publishing another repo's churn analysis from this **PUBLIC** repo, defeating a shipped fail-closed publication gate. Any fixture that needs a different allowlist must use a **temp fixture repo** (`setup-memory.sh --root <fixture>`), never the live `.supervisor/config.json`.
   - **The blind spot is restated accordingly.** The documented limit is NOT "a repo missing from the list is invisible" — it is that the scanner only catches tokens it can **recognise as repo references** (an `owner/repo` slug, or a known short name like `otherhub #146` matched case-insensitively as a whole word). Free prose naming a repo in a shape the scanner does not recognise is invisible. State that limit; do not describe the check as complete coverage.

6. **THE ALLOWLIST IS GITIGNORED AND MACHINE-LOCAL — never read the live resolver in a test.** Verified: `.supervisor/config.json` is excluded by `.gitignore`'s `.supervisor/*`, and the managed block re-includes the memory stores and the ledger but **never the config**. So on a fresh clone and **in CI**, `load_allowlist` falls through to the **git remote alone — one entry** (`vikashruhilgit/loomwright`), and this repo's pre-rename slug `vikashruhilgit/ai-agent-manager` is judged FOREIGN. This is not hypothetical: `test-committed-twin-scrub.sh` records in committed prose that "this exact census passed on the author's machine (2-entry config) and failed in CI (1-entry remote default) on the very commit that introduced it", and states the rule — **"a gate asserting a property of COMMITTED data must take its expectation from COMMITTED source, or it asserts a property of whoever happens to run it."**

   **Three binding consequences:**
   - **Follow the twin-scrub precedent:** any test expectation about which slugs are "ours" is **declared in committed test source** or pinned via `LOOMWRIGHT_MEMORY_REPO_ALLOWLIST`. Never call `setup-memory.sh allowlist` to derive an expectation.
   - **AC4's positive token must be one that resolves in CI** — use `loomwright` (the live remote), never `ai-agent-manager`, which is absent from the CI-resolved list and would go green locally and RED in CI, re-committing the documented incident.
   - **The empty-allowlist case must be specified, not discovered.** With no git remote and no config, `load_allowlist` yields an empty list, under which a naive membership test refuses **every** repo-shaped token. Decision (b) governs: an allowlist that could not be resolved is *could-not-examine*, so the writer REFUSES with a reason naming the unresolved allowlist — it must not silently pass everything, and must not silently refuse everything as if it had examined them.

7. **Version target: bump `15.32.0 → 15.33.0`** (NOT the `15.29.0`/`15.30.0` any older brief text implies — #137 and #139 already shipped past those). Counts re-verified off the directories at plan time: **14 agents / 21 commands / 41 skills**. Do **not** hand-count hooks — re-derive every count with `scripts/check-doc-currency.sh`, which is the authoritative gate.

## Owner decisions settled at plan time (the worker MUST NOT re-open these)

- **(a) Validator shape = SHARED HELPER, SOURCED DEFENSIVELY.** One new `scripts/validate-entry.sh` holding all five checks. Each sole writer sources it **if present and parseable**; if it is **missing, unparseable, or only PARTIALLY loaded, the writer REFUSES the write** with a named, machine-greppable reason — it must NOT crash, and it must NOT fall through and append unvalidated. Rationale to state in the PR: a refusal is already this item's documented failure mode (scope 2 — "a validation failure is a refusal to write plus an explanation, never a silent mutation"), so a broken helper degrades into the behaviour the design already sanctions rather than into either a crash or a silent unvalidated append. The five-independent-copies and hard-dependency alternatives were both offered and **rejected** — copies make the "one allowlist, two consumers" and "a test moves the list once and both behaviours move" ACs drift-prone by construction; a hard dependency inverts the writers' fail-safe convention. Record BOTH rejected alternatives in the PR body so neither is re-proposed.

  **Allowlist resolution is DELEGATED, never re-implemented.** `validate-entry.sh` obtains the allowlist by invoking `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-memory.sh" allowlist` and **MUST NOT parse `LOOMWRIGHT_MEMORY_REPO_ALLOWLIST` (or any other layer) itself.** This is load-bearing: that env var is only **layer 2 of four** in `load_allowlist`'s precedence (`--allow` → env → `.supervisor/config.json` array → git-remote default). A second parser inside `validate-entry.sh` would pass AC5 fully green while diverging from the ledger filter on layers 1, 3 and 4 — reproducing the very config-vs-remote divergence PRE-FLIGHT CORRECTION 6 documents, and reintroducing the duplication decision (a) rejected five copies to avoid. One resolver, two consumers.

  **The load guard is specified, not left to the worker — a half-loaded helper is the examined-vs-could-not-examine trap applied to the LOADER.** Sourcing a file with a syntax error returns non-zero *without* killing the caller, but bash defines every function **above** the error before aborting the parse — so a truncated helper leaves the writer with SOME validators defined. A guard keying on `command -v <one function>` would then report "examined and clean" over a partially-loaded validator. The guard is therefore: **(i)** the `source` must exit 0, **AND (ii)** all five validator functions must be present (`command -v` each), **AND (iii)** a version/sentinel variable exported by the helper must match what the writer expects. Any shortfall is the named refusal. **`|| true` is FORBIDDEN on the source line** — this repo's pervasive `|| true` convention applied there yields exactly the silent-unvalidated-append this decision forbids; a mutation control must prove that replacing the guard with `|| true` turns the AC2 test RED.

- **(f) PROVENANCE IS STRICT, AND ITS CALLER IS FIXED HERE (owner decision, 2026-08-10, mid-execution).** Surfaced by subtask 1's author as the largest blast radius in AC10d: `write-lessons.sh` defaults `SOURCE="unknown"`, and `/dreaming`'s shipped Accept path calls it with `--source "dreaming"` — a command name, not a motivating reference. The requirement defines provenance as "an entry must cite what motivated it (a finding, a PR, a session)", so **a bare command name is REFUSED**: `--source` (or the entry text) must carry a real reference — a PR/issue number, a session id, or a commit sha. Three alternatives were offered and rejected: deferring the caller fix to item 05 (knowingly breaks a shipped human-gated workflow in the interim), accepting any non-placeholder string (makes provenance near-vacuous — it would assert only that a caller passed *some* string), and shipping lenient with a follow-up item (lets the store accumulate unprovenanced entries meanwhile).

  **Consequence — this PARTIALLY REVERSES decision (e):** `loomwright/commands/dreaming.md` joins **subtask 2's** lanes for the single purpose of passing a real reference (`--source "dreaming:<session_id>"` — the session id is already in hand, since item 02 made the `record dreaming <session_id>` call mandatory). **Only the provenance argument changes.** The `/dreaming` **triage** wiring for the agent-memory queue remains item 05's and must NOT be touched.

- **(e) `/dreaming` triage wiring is OUT OF SCOPE — deferred to item 05.** The source requirement's own diagram puts the triage step under item 05 (`↓ /dreaming triages → item 05`). This item builds the **queue and the writer**; item 05 wires the promotion. Consequence stated honestly rather than hidden: `commands/dreaming.md` says, across **9 sites** (verified — item 05 inherits all of them), `.claude/agent-memory/` proposals "remain paste-to-apply", which will be a **live contradiction** against a queue that exists but nothing triages until 05 lands. `commands/dreaming.md` is deliberately **NOT** in any lane — do not edit it here.
- **(b) Fail-safe direction is REFUSE, not fail-open.** Every one of the five checks, on an input it **cannot examine** (unreadable file, absent jq, unparseable JSON), must REFUSE the write and name why — it must never report "examined and clean". This is the exact `examined-vs-could-not-examine` class that v15.28.0 was built to close and that item 02's drain hit three more times; treat any `[ -r X ]`-style guard that conflates *absent* with *unreadable* as a defect, and mirror the shape `derive_postmortem_last_run` already uses (`[ -e ] || never`, then `[ -r ] || unknown`).
- **(c) Agent write permission = NO.** `memory: project` agents may **not** write their own store directly; they write **proposals** only, and every store write goes through the sole writer. State this in the shared agent contract and make all six prompts say so. This is the requirement's own recommendation (scope 6) and is now settled.
- **(d) Proposal trigger = SURPRISE-ONLY** (scope 5), stated explicitly in every one of the six prompts. Queue volume is to be **recorded**, not acted on — widening to every-run is a later decision made on data, and this item must not make it.

## Acceptance Criteria

- [ ] AC1 — Given `scripts/validate-entry.sh` exists carrying all five checks, when **each of the six sole writers** is handed an entry seeded to violate **each of the five checks** (30 cases — the coverage is per-writer, not per-check-once), then that writer REFUSES the write with a reason naming the failing check, and the store file is **byte-unchanged** after the refusal. **Per-writer mutation control is mandatory:** deleting the validator CALL from one writer must turn that writer's fixtures RED while the others stay green — a writer that *sources* the helper but never *invokes* it on the write path is otherwise invisible.
- [ ] AC2 — Given the shared helper is **absent**, **unparseable**, or **truncated mid-file so only some validators are defined**, when a sole writer runs, then **three separately-asserted things hold**: (i) it exits with its refusal status, (ii) a **named, greppable reason** appears on stderr, and (iii) the store is byte-unchanged. All three are needed because the writers commit via temp-file + atomic `mv`, so byte-unchanged alone is *also* true of a plain crash and does not discriminate. Each of the six writers exposes a `REFUSE_VALIDATOR_UNAVAILABLE` token on disk so the self-reported `outputs_verified` gate can see the guard exists. A mutation control replaces the guard with `|| true` and proves this AC goes RED.
- [ ] AC3 — Given the allowlist holds **only this repo's own slugs** (never a foreign one — PRE-FLIGHT CORRECTION 5), when an entry citing `otherhub #146` is written, then the cross-repo check **REFUSES** it: `hub` is a repo-shaped token that is **not** in the allowlist, matched case-insensitively as a **whole word**. This is the known instance.
- [ ] AC4 — Given the token **`loomwright`**, which IS in the allowlist under **every** resolution path including CI's remote-only default (PRE-FLIGHT CORRECTION 6 — do NOT use `ai-agent-manager` here), when an entry cites it, then it **PASSES** — an entry may freely reference its own repo. Separately, a test pins the **documented blind spot**: prose naming a repo in a shape the scanner cannot recognise as a repo reference passes undetected. The refusal message and every doc surface must state that bound and must not describe the check as complete coverage.
- [ ] AC4b — **Mutation controls, mandatory — AC3 and AC4 do not discriminate on their own.** (i) Inverting the membership test (`in` ↔ `not in`) must turn **AC4 RED**. (ii) A fixture allowlist that **adds** `otherhub` must turn **AC3 GREEN** — proving the check reads the list rather than pattern-matching a hardcoded token. Both run with the allowlist supplied via `LOOMWRIGHT_MEMORY_REPO_ALLOWLIST` in the test's own environment; **the live `.supervisor/config.json` is never modified** (R0).
- [ ] AC4c — Given an allowlist that **cannot be resolved** (no config, no env var, no git remote ⇒ empty list), when an entry with any repo-shaped token is written, then the writer REFUSES with a reason naming the **unresolved allowlist** — not a silent pass-everything, and not a silent refuse-everything dressed as a real verdict. This is decision (b) applied to the allowlist itself.
- [ ] AC5 — Given the cross-repo check and item 01's ledger filter resolve the **same** allowlist, when one test sets that single list **once** via the process-global `LOOMWRIGHT_MEMORY_REPO_ALLOWLIST` (`setup-memory.sh` precedence layer 2 — it reaches both consumers with **no** root-override capability required of `validate-entry.sh`, and touches no file), then **both** behaviours move together in that one test. **Second assertion, mandatory — the env var alone does not discriminate:** the same test also moves the list via a `--root` fixture repo's `.supervisor/config.json` (precedence **layer 3**, the layer the live value in CORRECTION 5 actually comes from) and asserts both behaviours move again. Passing on layer 2 only is satisfiable by a duplicate parser; passing on layers 2 **and** 3 is not. **Negative control, mandatory:** the same test asserts that with a foreign record present, `setup-memory.sh apply` in a `--root` fixture repo still **WITHHOLDS** the ledger negation — proving this work did not weaken the shipped publication gate.
- [ ] AC6 — Given an entry whose cited file path no longer resolves, when it is written, then the dead-reference check REFUSES it; and on a **nullable-but-required** field the check asserts key **presence** via `jq has()` — a test proves a **missing key** does not pass as valid, distinct from an explicit `null`.
- [ ] AC7 — Given `scripts/write-agent-memory.sh` (new), when it writes an entry to a **seeded fixture store**, then it rebuilds `MEMORY.md` so a seeded unindexed file becomes indexed, and the resulting store satisfies the `N` files / `N-1` pointers rule from PRE-FLIGHT CORRECTION 1. Fixture-only — the live store is not touched or asserted on.
- [ ] AC8 — Given a proposal file under `.supervisor/agent-memory-proposals/`, when it is promoted via `write-agent-memory.sh` (validations run, entry written, index rebuilt), then the entry is in the store and `MEMORY.md` names it — proven on a **seeded fixture store**. **No gitignore work is claimed:** `.gitignore` already carries `.supervisor/*` inside a `/setup memory`-MANAGED sentinel block whose header states hand-edits are overwritten on the next apply, so the directory is gitignored with zero work and `.gitignore` is deliberately **NOT** in any lane. Per decision (e), the `/dreaming` triage leg is item 05's — AC8 proves proposal → validated write → indexed entry, not proposal → `/dreaming` → store.
- [ ] AC9 — Given decision (c), when the shared agent contract at **`AGENT_GUIDELINES.md` (repo ROOT — there is no `loomwright/AGENT_GUIDELINES.md`, and creating one would fork the contract into a file no gate scans)** and all six `memory: project` prompts (`code-reviewer`, `launch-pad`, `product-owner`, `qa-executor`, `qa-strategist`, `red-team-reviewer`) are read, then each states that the agent may NOT write its own store and must propose instead, and each states the surprise-only trigger from decision (d). **The test asserts CONTENT, not a heading** — a heading grep is satisfiable by adding seven empty headings, which is exactly the vacuous-guard class this item exists to close. It must match, under the `### Agent memory write permission` heading in each of the seven files, both the refusal sentence and the surprise-only trigger wording; and a **mutation control** deletes the refusal sentence from one prompt and proves the test goes RED naming only that file. The heading form is `### Agent memory write permission` in **all seven** files.
- [ ] AC10 — **The "existing sole-writer worktree invariant" is only 3-of-5 — verified, and the requirement's wording is wrong.** `write-lessons.sh`, `write-project-memory.sh` and `write-system-contract.sh` each carry a guard; `add-rule.sh` and `add-orientation.sh` carry **none** (zero `worktree` mentions) and resolve their store with a bare `git rev-parse --show-toplevel`, which in a **linked worktree returns the worktree's own toplevel** — so both write happily from a worktree today. Split accordingly:
  - **AC10a** — the three writers that have the guard: re-verify by test that each still refuses a worktree CWD.
  - **AC10b** — `add-rule.sh` and `add-orientation.sh` **gain** the guard, modelled on `write-lessons.sh`'s — **and the AC pins exactly which parts transfer, because that guard is two behaviours, not one**: (i) a worktree CWD refuses with **exit 3**; (ii) the existing **non-git-repo fallback stays UNCHANGED** — both scripts deliberately fall back to `pwd`, and `write-lessons.sh`'s hard `exit 2` in that case must NOT be copied across; (iii) for `add-orientation.sh`, whose `--root` / `ORIENTATION_REPO_DIR` override has no `write-lessons.sh` analogue, the guard evaluates the **RESOLVED store root**, so an explicit `--root` pointing at a worktree is refused too — a cwd-only guard would miss it. Each pinned by test. This is a deliberate, named scope addition (subtask 2), not a silent expansion — the alternative was to weaken the AC to match the code, which is this item's own false-completion class.
  - **AC10c** — `write-agent-memory.sh` carries the guard from birth (subtask 3), pinned by test.
- [ ] AC10d — Given the five validations are wired into writers that 25 other files call (71 call sites, incl. `curate-postmortem.sh`, `build-insights.sh`, `build-vault.sh`, `read-rules.sh` and eleven `test-*.sh` suites), when subtask 2 begins, then it **first RE-DERIVES these figures itself** (`wc -l` on the five writers, `grep -c` for caller sites, and the `commands/dreaming.md` paste-to-apply site count) and reports any divergence from this brief rather than trusting them — three of the brief's counts were not independently confirmed at Plan Review. It then **enumerates every caller and REPORTS** which existing fixtures the new validations would newly refuse. A caller broken by a *correct* refusal is fixed in its own suite (those suites are in subtask 2's lanes); a caller broken because a validation is **wrong** is reported, never worked around by loosening the validator.
- [ ] AC15 — Given decision (f), when `write-lessons.sh` is called with a bare `--source "dreaming"` (or the `unknown` default), then provenance **REFUSES**; and when called with `--source "dreaming:<session_id>"`, a PR/issue number, or a commit sha, it **PASSES**. `loomwright/commands/dreaming.md`'s LESSONS invocation is updated to pass the real session id it already holds. A test pins both directions. Only the provenance argument changes in `dreaming.md` — its triage wiring stays item 05's.
- [ ] AC16 — **CORPUS REGRESSION (owner decision, 2026-08-10, mid-execution — the gating criterion).** Subtask 2 replayed all 21 live curated entries from `LESSONS.md` + `PROJECT_MEMORY.md` and **12 of 21 (57%) were refused, every one a false positive** — independently reproduced by the coordinator. Given the real corpus, when every live curated entry is replayed through `validate_entry_all`, then **ZERO are refused**. Specifically: `check-doc-currency.sh` resolves (it lives under `loomwright/scripts/`, not the repo root); `test-*.sh` is a glob and `~/.claude/settings.json` is tilde-shaped — both are *unresolvable-by-shape* and must SKIP, not refuse; and English prose pairs (`yaml/json`, `dev/ci`, `budget/zone`, `user/pr-text`, `shell/wget`, `worker_result/code_review_result`) must not be read as `owner/repo` slugs. **A false refusal is worse than a miss here** — it blocks a legitimate write, and the check's whole value is that a human trusts it. The corpus replay ships as a permanent test so this cannot regress.
- [ ] AC17 — **Provenance strictness lives in `validate_provenance`, not in a writer.** Decision (f) is currently implemented writer-side in one writer, which is the five-copies drift decision (a) rejected. All six writers must inherit it from the shared helper: a source qualifies only if it carries a real reference (digit, or a `:`/`/`/`#`/`@` id separator); a bare command name like `dreaming` does not.
- [ ] AC18 — **The writer's own idempotent dedup runs BEFORE the validator.** `write-project-memory.sh` had a benign "already stored" no-op (exit 0); the validator now fires first and turns it into a hard exit 1. Ordering fixed, pinned by test.
- [ ] AC11 — Given a validation refusal, when it fires anywhere, then it blocks **only that write**: no PR, no run, no `heal_decision`, and no gate changes. No new gate is added anywhere.
- [ ] AC12 — Given the release surface, when `scripts/check-doc-currency.sh` and `scripts/check-command-sync.sh` run, then both are green at **v15.33.0** with counts re-derived off the directories, and no stale `15.32.0` remains outside `CHANGELOG.md`.
- [ ] AC13 — Given base `c6bfda6` carries the citation-drift guard, when `scripts/test-citation-drift.sh` runs, then it is green — every `file:N` this item adds or moves resolves, and new prose prefers descriptive anchors over line numbers.
- [ ] AC14 — Given the full suite, when every `loomwright/scripts/test-*.sh` runs, then all are green on macOS bash 3.2, and any new script honours the always-exit-0 convention where its siblings do.

## Outcomes Rubric
- `scripts/validate-entry.sh` exists and is demonstrably **INVOKED on the write path of** all six sole writers, each guarded so a missing, unparseable, or partially-loaded helper produces a named refusal rather than a crash or an unvalidated append
- Each of the five checks has a fixture that makes it RED on a seeded violation **for every one of the six writers**, and a per-writer mutation control proves the call site, not just the source line
- The cross-repo check REFUSES a repo-shaped token **not in** the allowlist and PASSES one that **is**, with the blind spot pinned by test; no fixture ever adds a foreign slug to the live allowlist
- The cross-repo check and the ledger filter resolve the same allowlist, with one fixture-repo test that changes the list once, asserts both, and asserts the ledger negation is still WITHHELD on a foreign record
- `scripts/write-agent-memory.sh` exists, rebuilds `MEMORY.md` on every write, and is proven on a seeded fixture store rather than the live store
- All six `memory: project` agent prompts and the root `AGENT_GUIDELINES.md` state the no-direct-write rule and the surprise-only trigger
- No refusal path changes a `heal_decision`, blocks a PR, or adds a gate; every writer still refuses a worktree CWD

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | The shared validator: five checks + its own suite | AC3, AC4, AC4b, AC4c, AC6 (check semantics), AC14 | 0 modify, 2 create | quality-checklist, unit-testing | LAUNCHABLE |
| 2 | Wire the five existing sole writers to the validator + the strict-provenance caller fix | AC1, AC2, AC6, AC10a, AC10b, AC10d, AC11, AC15 | 11 modify, 0 create (+5 collateral lanes, expected untouched) | quality-checklist, unit-testing | BLOCKED (by #1) |
| 3 | `write-agent-memory.sh` — sixth sole writer, index owner, proposal queue | AC1, AC2, AC5, AC7, AC8, AC10c | 1 modify, 2 create | quality-checklist, unit-testing, context-setup | BLOCKED (by #1) |
| 4 | Capability statement across six prompts + the release surface | AC9, AC12, AC13 | 11 modify, 1 create | context-setup, quality-checklist | BLOCKED (by #2, #3) |

**Ordering note (reachability, not wave index).** #2 and #3 are mutually unreachable and share **no** lane path, so their concurrency is safe. All four lane sets are **pairwise fully disjoint** — there is no lane sharing anywhere in this brief; the ordering rests solely on the `requires` edges. #4 is last because the version bump and count re-derivation must observe the finished file set.

### Subtask 1 contract

```yaml
provides:
  - {kind: "file", path: "loomwright/scripts/validate-entry.sh"}
  - {kind: "file", path: "loomwright/scripts/test-validate-entry.sh"}
  - {kind: "symbol", path: "loomwright/scripts/validate-entry.sh", name: "validate_cross_repo_reference"}
  - {kind: "symbol", path: "loomwright/scripts/validate-entry.sh", name: "validate_dead_reference"}
  - {kind: "symbol", path: "loomwright/scripts/validate-entry.sh", name: "VALIDATE_ENTRY_CONTRACT"}
requires: []
external_requires:
  - "jq (already a soft dependency of every existing sole writer)"
  - "bash 3.2 (macOS stock) — no bashisms above 3.2"
lanes:
  - "loomwright/scripts/validate-entry.sh"
  - "loomwright/scripts/test-validate-entry.sh"
```

`VALIDATE_ENTRY_CONTRACT` is the sentinel from decision (a) clause (iii) — the version marker each writer's load guard must match.

### Subtask 2 contract

```yaml
provides:
  - {kind: "symbol", path: "loomwright/scripts/write-lessons.sh", name: "REFUSE_VALIDATOR_UNAVAILABLE"}
  - {kind: "symbol", path: "loomwright/scripts/write-project-memory.sh", name: "REFUSE_VALIDATOR_UNAVAILABLE"}
  - {kind: "symbol", path: "loomwright/scripts/add-rule.sh", name: "REFUSE_VALIDATOR_UNAVAILABLE"}
  - {kind: "symbol", path: "loomwright/scripts/add-orientation.sh", name: "REFUSE_VALIDATOR_UNAVAILABLE"}
  - {kind: "symbol", path: "loomwright/scripts/write-system-contract.sh", name: "REFUSE_VALIDATOR_UNAVAILABLE"}
requires:
  - {from: 1, kind: "symbol", path: "loomwright/scripts/validate-entry.sh", name: "VALIDATE_ENTRY_CONTRACT"}
external_requires: []
lanes:
  - "loomwright/scripts/write-lessons.sh"
  - "loomwright/scripts/write-project-memory.sh"
  - "loomwright/scripts/add-rule.sh"
  - "loomwright/scripts/add-orientation.sh"
  - "loomwright/scripts/write-system-contract.sh"
  - "loomwright/scripts/test-lessons.sh"
  - "loomwright/scripts/test-project-memory.sh"
  - "loomwright/scripts/test-add-rule.sh"
  - "loomwright/scripts/test-add-orientation.sh"
  - "loomwright/scripts/test-system-contract.sh"
  - "loomwright/scripts/test-rules-docs.sh"
  - "loomwright/scripts/test-read-rules.sh"
  - "loomwright/scripts/test-read-lessons.sh"
  - "loomwright/scripts/test-read-orientation.sh"
  - "loomwright/scripts/test-suite-helpers-defined.sh"
  - "loomwright/commands/dreaming.md"
  - "loomwright/scripts/test-twin-graph.sh"
```

**Lane added mid-execution (2026-08-10).** `test-twin-graph.sh` was found RED as out-of-lane collateral by subtask 3, which proved causation by stashing only subtask 2's modified files (rc=0 pristine, rc=1 with them applied) rather than inferring it — the suite references `write-system-contract.sh`. Declaring it here is what makes AC10d's "fix a correct refusal in its own suite" legal instead of an out-of-lane write.

**Collateral lanes (AC10d).** The last five paths are declared because 25 files call the five writers across 71 sites; a fixture that a *correct* new refusal breaks must be fixable in-lane. They are lanes, not a mandate to edit — an untouched collateral lane is the expected outcome.

### Subtask 3 contract

```yaml
provides:
  - {kind: "file", path: "loomwright/scripts/write-agent-memory.sh"}
  - {kind: "file", path: "loomwright/scripts/test-write-agent-memory.sh"}
  - {kind: "symbol", path: "loomwright/scripts/write-agent-memory.sh", name: "rebuild_memory_index"}
  - {kind: "symbol", path: "loomwright/scripts/write-agent-memory.sh", name: "REFUSE_VALIDATOR_UNAVAILABLE"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-memory.sh", name: "one_allowlist_two_consumers"}
requires:
  - {from: 1, kind: "symbol", path: "loomwright/scripts/validate-entry.sh", name: "VALIDATE_ENTRY_CONTRACT"}
external_requires: []
lanes:
  - "loomwright/scripts/write-agent-memory.sh"
  - "loomwright/scripts/test-write-agent-memory.sh"
  - "loomwright/scripts/test-setup-memory.sh"
```

`one_allowlist_two_consumers` is AC5's shared-list test; it lands in `test-setup-memory.sh` because that suite already owns the fixture-repo (`--root`) harness. **`loomwright/scripts/setup-memory.sh` itself is deliberately NOT in any lane — this item consumes the allowlist, it does not change it.**

### Subtask 4 contract

```yaml
provides:
  - {kind: "file", path: "loomwright/scripts/test-agent-memory-permission.sh"}
  - {kind: "symbol", path: "AGENT_GUIDELINES.md", name: "### Agent memory write permission"}
  - {kind: "symbol", path: "loomwright/agents/code-reviewer.md", name: "### Agent memory write permission"}
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "### Agent memory write permission"}
  - {kind: "symbol", path: "loomwright/agents/product-owner.md", name: "### Agent memory write permission"}
  - {kind: "symbol", path: "loomwright/agents/qa-executor.md", name: "### Agent memory write permission"}
  - {kind: "symbol", path: "loomwright/agents/qa-strategist.md", name: "### Agent memory write permission"}
  - {kind: "symbol", path: "loomwright/agents/red-team-reviewer.md", name: "### Agent memory write permission"}
requires:
  - {from: 2, kind: "symbol", path: "loomwright/scripts/add-rule.sh", name: "REFUSE_VALIDATOR_UNAVAILABLE"}
  - {from: 3, kind: "file", path: "loomwright/scripts/write-agent-memory.sh"}
external_requires:
  - "gh (release-surface verification only; not required to complete the edits)"
lanes:
  - "loomwright/scripts/test-agent-memory-permission.sh"
  - "AGENT_GUIDELINES.md"
  - "loomwright/agents/code-reviewer.md"
  - "loomwright/agents/launch-pad.md"
  - "loomwright/agents/product-owner.md"
  - "loomwright/agents/qa-executor.md"
  - "loomwright/agents/qa-strategist.md"
  - "loomwright/agents/red-team-reviewer.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CLAUDE.md"
  - "CHANGELOG.md"
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
```

**Two lanes added at integration (2026-08-10, coordinator).** Adding the shared `### Agent memory write permission` block to all six `memory: project` prompts breached `scripts/check-token-budget.sh` on `red-team-reviewer` (the smallest budget) by 155 proxy tokens. Subtask 4 fixed it in-lane by compressing the block, but that left **5 proxy tokens of headroom** — a trap where the next one-sentence edit to that prompt reddens CI for an unrelated reason. The sanctioned remedy per CLAUDE.md is to re-declare the budget at the measured weight plus ~10%, which lives in these two files (the JSON and its mechanically-synced mirror row). Re-declared 6065 → 6666 (measured 5513 → 6060); headroom is now 606, consistent with every other agent.

**The shared agent contract is `AGENT_GUIDELINES.md` at the REPO ROOT.** Verified: `loomwright/AGENT_GUIDELINES.md` does **not** exist, and the citation-drift guard's own surface list scans the root file. Creating a `loomwright/` copy would satisfy the self-reported `outputs_verified` gate while writing decision (c) into a document nothing reads — a concrete false-completion path, so the path is pinned here.

**`provides` names are non-false-passing — verified at plan time.** Every symbol above returned **0 grep hits** across the repo when this brief was written, so no contract can be satisfied by pre-existing code. Re-check with `grep -rn "<name>" loomwright/ AGENT_GUIDELINES.md` before starting; if any already resolves, the contract is stale and must be reported, not worked around.

## Parallelism Analysis

4 subtasks, 3 waves. #1 runs alone; #2 and #3 may run concurrently (mutually unreachable, zero lane overlap); #4 runs last.

- Recommended workers: 2

## Skill References

| Skill | Subtasks | Why |
|---|---|---|
| `skills/quality-checklist/SKILL.md` | 1, 2, 3, 4 | Pre/post-task gates. Load-bearing here because several ACs are only meaningful under mutation testing, which this skill's post-task gate is the natural home for. |
| `skills/unit-testing/SKILL.md` | 1, 2, 3 | Every AC in this item is discharged by a `test-*.sh` fixture; the suites are the deliverable as much as the scripts are. |
| `skills/context-setup/SKILL.md` | 3, 4 | #3 must resolve the agent-memory store layout and #4 must edit six agent prompts plus the shared contract — both need the project-context load rather than guessing conventions. |

## Configuration
- **Base Branch:** main
- **Split reason:** context-bound — 27 files expected to change (5 create + 22 modify) across 32 declared lanes, over the `> 12 files changed OR > 800 changed lines` bound. The split is **sequential**, not parallel: #1 produces the helper and #2/#3 consume it under a `requires` edge, over four pairwise-disjoint lane sets. This directly mitigates R1 (turn-limit exhaustion), which has fired on every prior item in this queue.
- **Version bump:** 15.32.0 → 15.33.0
- **Mode:** parallel (max 2 workers — the only concurrent pair is #2 and #3, which are lane-disjoint)
- **Cost profile:** default (`inherit`) — this run has never used `--cheap` and the profile stays consistent mid-queue.

## Risk Assessment

| # | Risk | Severity | Source | Mitigation |
|---|------|----------|--------|------------|
| R0 | **Implementing the cross-repo check in the requirement's literal direction inverts it** — refusing own-repo citations, passing foreign ones, while every AC goes green | BLOCKING-class | PRE-FLIGHT CORRECTION 5 (verified in `setup-memory.sh`) | AC3/AC4/AC5 are written in the corrected direction. AC5's negative control asserts the ledger negation is still WITHHELD on a foreign record. **No fixture may add a foreign slug to the live allowlist** — use `setup-memory.sh --root <fixture>`. Plan Review round 1 caught this; it is the reason this brief exists in its current form. |
| R1 | Worker turn-limit exhaustion — this is the largest item in the queue (27 files) | HIGH | Feasibility check 4 | **RESUME the worker via SendMessage from its transcript; do NOT respawn.** A respawn redoes the validator from scratch and pays twice. This has happened on every prior item in this queue (01c, 02, 03 — 03 resumed twice). Also: the deterministic `outputs_verified` gate is worker-SELF-REPORTED, so a worker that dies before emitting `WORKER_RESULT` leaves it with no input and nothing flags it — verify the `provides` symbols **on disk**, not from the result block. |
| R2 | A shared helper becomes a single point of failure across every curated store | MEDIUM | Requirement scope 1 (independence caveat) | Decision (a): defensive sourcing — a missing/unparseable helper degrades to a REFUSAL, the design's own sanctioned failure mode. Pinned by AC2 with a byte-unchanged assertion. |
| R3 | A check silently conflates "could not examine" with "examined and clean" | HIGH | v15.28.0 fail-open incident; item 02 drain (3 sightings) | Decision (b). Every check must distinguish absent / unreadable / clean, mirroring `derive_postmortem_last_run`. **Mutation-test each check before trusting it** — this repo has repeatedly shipped guards that were vacuous until mutated. |
| R4 | A test that merely observes the already-healthy live store passes against a no-op writer | HIGH | PRE-FLIGHT CORRECTION 1 | AC7 is fixture-only. Prove the fixture makes the assertion RED under mutation (writer's index rebuild removed) before accepting it. |
| R5 | New `file:N` citations break the brand-new citation-drift guard from PR #139 | MEDIUM | PRE-FLIGHT CORRECTION 4 | AC13. Prefer descriptive anchors; run `test-citation-drift.sh` before commit, not only in CI. |
| R6 | Cross-repo check overstated as complete coverage in prose | MEDIUM | Requirement scope 1 | AC4 pins the blind spot **by test**. The refusal text and every doc surface must state the allowlist bound explicitly — overstating it is the same false-clean class that motivated the check. |
| R7 | The six agent prompts drift from the shared agent contract | MEDIUM | Documented `agent↔command mirror drift` lesson | AC9 greps all six in one test. Note `check-command-sync.sh` does NOT cover prose, so a green gate is necessary, not sufficient. |
| R8 | Publication gate — this is a PUBLIC repo and the cross-repo fixtures deliberately contain foreign slugs (`otherhub`, `hub`) | MEDIUM | Item 01b/01c precedent | Fixtures may use those slugs (they are already public in this repo's own merged history via the v15.28.0 ledger work), but run the derived-terms sweep on the staged diff before commit and do a **positive-inclusion** review that every path is in the declared lanes. |

## Handoff
/supervisor job: .supervisor/jobs/pending/2026-08-10-write-time-validation.md

---

> **DELIVERED — verified 2026-08-23, retired from `in-progress/` to `done/`.**
>
> Shipped as **v15.33.0 via PR #144** (merged 2026-08-13), not by the run this brief was authored for; PR #140, the first attempt at the same scope, was closed superseded. Follow-up **PR #146** fixed a writer that stamped its own citation and so vouched for every memo it wrote. Both merge commits verified present on current `main` with `git merge-base --is-ancestor` (`70710a1`, `97e721d`) — they predate the 2026-08-20 force-push and survived it.
>
> Verified on disk rather than from the changelog: all seven scripts exist, all six sole writers reference the validator on their write path, the `### Agent memory write permission` heading carries real content in all six `memory: project` prompts plus the root `AGENT_GUIDELINES.md`, and the proposal queue is wired in both `write-agent-memory.sh` and `commands/dreaming.md`. Suites re-run green on this checkout: validate-entry 298, write-agent-memory 170, lessons 168, project-memory 156, add-rule 113, add-orientation 90, system-contract 74, agent-memory-permission 12 — **1081 assertions, 0 failures**. Release gates green: doc-currency, command-sync, citation-drift 26/0.
>
> **One AC deviation, recorded rather than glossed:** AC1/AC3/AC4 as written require `dead-reference` and `cross-repo` to REFUSE. Both are now **ADVISORY** — they report on stderr and always return 0. This was an owner decision taken on measurement after six consecutive review rounds found false refusals, every one of them in those two checks, ending with a fix that made the verdict machine-dependent. The reasoning is recorded in `CHANGELOG.md` and in `validate-entry.sh`'s own header. `duplicate`, `contradiction` and `provenance` still refuse, and the contract sentinel moved to `validate-entry/2` so a writer built against `/1` refuses rather than writing under a contract it does not implement.
>
> The brief's own Feasibility check 5 ("`write-agent-memory.sh` confirmed ABSENT") is therefore **stale** — that file has existed since v15.33.0. Do not resume this brief.
