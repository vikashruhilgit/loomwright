# Supervisor Job: `/propose --domain` — a domain-derived second basis for candidate work

## Environment
- **Project:** /private/tmp/claude-501/-Users-vikashruhil-Documents-work-AI-loomwright-stateloop/3d4bc285-2db6-4763-9ee2-6b3c83ea634b/scratchpad/domain-mode
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: detached @ origin/main d5de845
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (run executes in an isolated worktree; a concurrent Claude session holds the shared checkout)
- **Source requirement:** .supervisor/requirements/invention/02b-propose-domain-mode.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash + `jq` + markdown, identical to `propose-work.sh` / `read-product.sh`. No new runtime. |
| 2 | Dependency Availability | GO | `jq` present. The store **reader** `loomwright/scripts/read-product.sh` and the **bootstrap** `loomwright/scripts/propose-product.sh` shipped with 02a (PR #204, merged at `2b1325f`) — that is the hard dependency, and it is satisfied. The store itself is **per-project and is absent in this worktree** (`read-product.sh` states it is created by the bootstrap, never by the reader); that is the specified AC2 path, and the tests run against committed fixture stores. |
| 3 | Architecture Fit | GO | Joins the advisory-reader family (`read-product.sh`, `read-rules.sh`, `read-postmortem.sh`, `propose-work.sh`): `set -uo pipefail` with no `set -e`, a `jq` skip-not-fail guard, `exit 0` always, writes only under one guarded output directory. |
| 4 | Scope vs Supervisor Capability | CAUTION | ~1100 changed lines across 13 distinct files — over **both** halves of the `context-bound` bound (`> 12 files` OR `> 800 changed lines`). Split into 2 sequential subtasks (producer, then verifier + surfaces). |
| 5 | Hard Blockers | GO | No migrations, no credentials, no missing modules. `.agent/orientation/` currently holds only `README.md` — no memos — which is itself an input to the *unverified* path and is handled, not blocked. |

**Overall Verdict:** CAUTION (proceeding; the scope finding is addressed by the decomposition)

## Task
**Goal:** Add a `--domain` flag to `/propose` that derives candidate work items from what competent apps in this project's domain do and this app does not — emitting the same evidence-carrying artifact, into the same `proposed/` folder, under the same propose-only contract as the existing ledger basis.

**Problem Statement:**
A maintainer needs the system to surface capability gaps it has never been told about, because a project's most valuable missing work is rarely in its own churn ledger — it is the thing the domain expects and the app lacks (multi-currency, rate limits, SSO).
Currently, `/propose` reads only `.supervisor/floor/floor.json` — the inward half, derived entirely from recorded mistakes. `/capability-check --strategy` is the only outward-looking surface and it is maintainer-only and plugin-scoped; `/product-owner --brainstorm` only researches a problem a human has already named. This causes discovery to remain a purely human act: every item this system has executed was typed by a person.
Success looks like one command with two bases — ledger and domain — emitting into one triage folder, where every domain gap names its classification, its evidence class, the surfaces searched, and each source's URL and fetch date, and where an unconfirmable capability is reported *unverified* rather than *missing*.

## Acceptance Criteria
- [ ] Given a repo with a fetcher available, when bare `/propose` (no `--domain`) runs, then **zero** external calls are attempted — asserted by running it with a counting fetcher stub installed and observing an empty call log, not by reading the code.
- [ ] Given no product store at `.agent/product.json`, when `--domain` runs, then it prints the named "no product context" message plus the `propose-product.sh` bootstrap offer, writes **no** file, and exits 0.
- [ ] Given a committed fixture store and a stubbed domain source, when `--domain` runs, then at least one gap file is emitted, and every emitted gap carries its classification, its evidence class (`derived` vs `judgment`), the surfaces searched with the terms used, and each cited source's URL and fetch date — asserted by parsing the emitted file, never by reading the script.
- [ ] Given a fixture built so a capability cannot be confirmed either way, when `--domain` runs, then that capability is emitted as **unverified** and never as missing — with a mutation control proving the assertion can fail.
- [ ] Given the same fixture under `stance: product` and under `stance: tool`, when `--domain` runs twice, then the two outputs carry the **same classifications** and **different default actions** — asserted by diffing the two emitted files.
- [ ] Given a `NOT-FOR-US` gap already recorded, when `--domain` runs a second time, then that gap is not re-emitted and the suppression is reported naming the basis that suppressed it — with a mutation control that deletes the suppression check and asserts this case then fails.
- [ ] Given the fetch cap set to 1, when `--domain` runs against a store with two or more competitors, then exactly one external call is made and the output reports **partial coverage** naming what was not reached.
- [ ] Given a source whose fetch date is older than the stated staleness threshold, when `--domain` runs, then that source is named as **stale** in the output rather than cited silently.
- [ ] Given both bases run against the same repo, when the directory is listed, then a `--domain` run's filenames are namespaced (`domain--<slug>.md`) so neither basis can overwrite the other's file in `proposed/`.
- [ ] Given a run of either basis, when the filesystem tree is hashed before and after, then no file outside `.supervisor/requirements/proposed/` is created or modified — with a guard-deleted mutation control that plants a real stray write.
- [ ] Given any emitted gap file, when it is grepped for score / rank / priority / ordering fields, then none is present — on a run that emitted ≥1 file, with a positive control proving the grep can fire.
- [ ] Given the repo after the change, when `bash loomwright/scripts/test-propose-domain.sh` runs, then it exits 0; and `bash loomwright/scripts/test-propose-work.sh` still exits 0 (the existing basis is unchanged).

## Outcomes Rubric
- The system can say what the domain expects that this app does not do, with sources and dates.
- Derived and judgment are visibly different classes; a gap never claims more than it verified.
- "We don't have it" is backed by where it looked, and unverified is never reported as absent.
- Stance decides the default action, so one lane serves a product and a tool honestly.
- One command, two bases, one triage folder, no new surface.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Design constraints (binding on both subtasks)

1. **One flag, one command, one folder.** No new command, agent, hook, or skill. `/propose` keeps its current no-flag behaviour byte-for-byte; `--domain` is its first flag. The two bases NEVER run in one invocation, and `--domain` is never implicit.
2. **The fetch seam is named and overridable, and it is the ONLY external call path.** `propose-domain.sh` performs every external fetch through a single fetcher command resolved from `PROPOSE_DOMAIN_FETCH_CMD` (invoked as `<cmd> <url>`, printing the source text on stdout). Unset ⇒ no fetcher ⇒ the run fetches nothing, reports it, and every domain expectation degrades to *unverified* with partial coverage. This is what makes the "zero network calls" and "cap=1 ⇒ exactly one call" criteria mechanically assertable rather than code-read.
3. **`PROPOSE_DOMAIN_MAX_FETCHES` defaults to 5**, mirroring `/capability-check --max-fetches`. Local file reads (the store, the code/doc inventory, `.agent/orientation/`) are NOT external calls and never draw on the budget.
4. **Unverified is not absent.** A capability the inventory could not confirm either way is emitted as `unverified`. Absent evidence is omitted, never defaulted — `build-floor.sh`'s rule, applied to the input this lane is most likely to fabricate.
5. **No code graph.** The inventory is direct reads (grep/glob over the project's own code and docs) plus `.agent/orientation/` memos read through the existing reader path. Do NOT build, read, or resurrect `graphify-out/`, `read-bridge.sh`, or `brain_context`.
6. **Classification, never a score.** Every gap is exactly one of `TABLE-STAKES` / `DIFFERENTIATOR` / `NOT-FOR-US`. The default action is read from the store's stance via `read-product.sh`'s emitted `stance_default_action` — it is NEVER re-derived here (that mapping has exactly one home, `read-product.sh`'s `def STANCE_ACTIONS`).
7. **Dedup by a stable token, same discipline as the ledger basis.** Each gap carries a token line and is suppressed when that token already appears in `proposed/` or in a `## Status: done` requirement file under `.supervisor/requirements/`; every suppression is reported with the file that caused it.
8. **Fail-safe.** `set -uo pipefail`, no `set -e`, a `command -v jq` guard that skips rather than fails, `exit 0` always, and every write through a `guarded_write`-shaped path guard.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `propose-domain.sh` — the domain-basis producer, plus its committed fixtures | AC2–AC11 (implementation side) | 0 modify, 6 create | `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | `test-propose-domain.sh` + the `/propose --domain` command surface and release bump | AC1–AC12 (assertion side) + doc mirrors | 6 modify, 1 create | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1 — the producer (LAUNCHABLE)
provides:
  - {kind: "file",   path: "loomwright/scripts/propose-domain.sh"}
  - {kind: "symbol", path: "loomwright/scripts/propose-domain.sh", name: "guarded_write"}
  - {kind: "symbol", path: "loomwright/scripts/propose-domain.sh", name: "superseded_by"}
  - {kind: "symbol", path: "loomwright/scripts/propose-domain.sh", name: "fetch_source"}
  - {kind: "symbol", path: "loomwright/scripts/propose-domain.sh", name: "classify_gap"}
  - {kind: "file",   path: "loomwright/scripts/fixtures/propose-domain/product.json"}
  - {kind: "file",   path: "loomwright/scripts/fixtures/propose-domain/product-tool.json"}
  - {kind: "file",   path: "loomwright/scripts/fixtures/propose-domain/README.md"}
requires: []
lanes:
  - "loomwright/scripts/propose-domain.sh"
  - "loomwright/scripts/fixtures/propose-domain/README.md"
  - "loomwright/scripts/fixtures/propose-domain/*"
external_requires:
  - "jq >= 1.6 (already a hard dependency of propose-work.sh and read-product.sh)"

# Subtask 2 — the verifier and the command/doc surface (BLOCKED by #1)
provides:
  - {kind: "file",   path: "loomwright/scripts/test-propose-domain.sh"}
  - {kind: "symbol", path: "loomwright/commands/propose.md", name: "## The two bases"}
  - {kind: "symbol", path: "loomwright/commands/agent-help.md", name: "### 🌱 /propose — Candidate Work Items from the Churn Ledger and the Domain (Read-Only, Propose-Only)"}
  - {kind: "symbol", path: "README.md", name: "two bases"}   # zero current hits in README.md; the rewritten /propose table row must contain this phrase, so outputs_verified can confirm the one edit no CI gate covers
requires:
  - {from: "1", kind: "file",   path: "loomwright/scripts/propose-domain.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/propose-domain.sh", name: "fetch_source"}
  - {from: "1", kind: "file",   path: "loomwright/scripts/fixtures/propose-domain/product.json"}
  - {from: "1", kind: "file",   path: "loomwright/scripts/fixtures/propose-domain/product-tool.json"}
lanes:
  - "loomwright/scripts/test-propose-domain.sh"
  - "loomwright/commands/propose.md"
  - "loomwright/commands/agent-help.md"
  - "README.md"
  - "CHANGELOG.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires: []
```

**Subtask 1 — what to build**

`loomwright/scripts/propose-domain.sh`, an advisory reader/producer in the family style of `propose-work.sh`:

- **Inputs, each carrying its own evidence class.** (a) the product store, read by shelling out to `read-product.sh` (never by re-parsing `.agent/product.json` — one parser, and `stance_default_action` comes from there); (b) the capability inventory — grep/glob over the project's own code and docs plus any `.agent/orientation/` memos, class **derived**; (c) the domain expectation set — fetched from the store's `competitors[]` through `fetch_source`, class **external**, and stated as the weakest input.
- **Absent store** ⇒ print the named "no product context" message and the `propose-product.sh` bootstrap offer to stderr, write nothing, `exit 0`. Never a silent skip.
- **Every gap states where it looked** — the surfaces searched and the exact terms used — and a capability the inventory cannot confirm either way is `unverified`, never missing.
- **`fetch_source`** is the sole external-call site, bounded by `PROPOSE_DOMAIN_MAX_FETCHES` (default 5, shared across the run). Exhausting it reports **partial coverage** naming what was not reached. Every cited source carries its URL and fetch date; a source older than `PROPOSE_DOMAIN_MAX_SOURCE_AGE_SECONDS` is named **stale** rather than cited silently.
- **Emitted shape mirrors `propose-work.sh`** — title, dedup token line, basis lines, `## Problem` / `## Goal` / `## Scope` / `## Acceptance criteria` / `## Evidence`, plus a per-source citation list. Filenames are `domain--<slug>.md`.
- **Env knobs** (all optional, mirroring the existing table): `PROPOSE_DOMAIN_OUT_DIR`, `PROPOSE_DOMAIN_REQUIREMENTS_DIR`, `PROPOSE_DOMAIN_STORE`, `PROPOSE_DOMAIN_FETCH_CMD`, `PROPOSE_DOMAIN_MAX_FETCHES`, `PROPOSE_DOMAIN_MAX_SOURCE_AGE_SECONDS`, `PROPOSE_DOMAIN_SOURCE_DATE_EPOCH`.
- **Committed fixtures** under `loomwright/scripts/fixtures/propose-domain/`: a `product.json` (`stance: product`), a `product-tool.json` identical but for `stance: tool`, and a `README.md` stating why these are committed (`.supervisor/*` is gitignored, so a test driven off the real tree would go silently green in CI). Any fixture that stands in for fetched source text must NOT use a `.log` extension — the bare `*.log` under root `.gitignore`'s `# Logs` section makes `git add` skip it silently. If that reasoning is carried into a committed comment, use that descriptive anchor rather than a bare line number (`test-citation-drift.sh` fails new unpinned citations).

**Subtask 2 — what to build**

- `loomwright/scripts/test-propose-domain.sh` — hermetic self-tests, one case per acceptance criterion, in the exact style of `test-propose-work.sh`: committed fixtures only, every temp tree via `mktemp -d` **outside the repo root**, assertions parsed **out of the emitted files** rather than read off the script, and a **mutation control** for each guard whose deletion must make its case fail (unverified-not-missing, `NOT-FOR-US` suppression, the write-path guard, the no-score grep's positive control). Auto-registered by `.github/workflows/ci.yml`'s `loomwright/scripts/test-*.sh` glob — no CI file edit needed.
- `loomwright/commands/propose.md` — add `--domain` to Usage **using the runtime plugin-root form, mirroring the existing line**: the new invocation must be written `bash "${CLAUDE_PLUGIN_ROOT}/scripts/propose-domain.sh"` and never a repo-relative `loomwright/scripts/...` path, which resolves only for the plugin maintainer; add a Parameters row (the file currently states "`/propose` takes no flags"; that sentence must go), add the `## The two bases` section stating that the bases never run in one invocation and why (the default basis is local `jq` over a local file and costs nothing; `--domain` spends fetch budget and emits judgment-class output, so bare `/propose` must never trigger a network call), and add the `--domain` env table.
- `loomwright/commands/agent-help.md` — update the whole `/propose` section so the agent↔command mirror does not drift. **Three distinct edits, all required:** (a) the heading `### 🌱 /propose — Candidate Work Items from the Churn Ledger …` gains "and the Domain" before the parenthetical — keep the `### ` level, the emoji, and the em dash, since `check-doc-currency.sh` asserts an `^### .*/propose ` section exists; (b) the **`**Parameters:** none.`** line is a *second, independent* no-flags claim (distinct from the one in `commands/propose.md`) and must be rewritten to document `--domain` plus the new env vars; (c) the usage block below it (`/propose  # read floor.json, …`) must gain the `--domain` form. This section is why the repo's recorded `agent-command-mirror-drift-on-fixes` defect keeps recurring: nothing mechanical couples Parameters-table prose.
- `README.md` — the `/propose` row in the root command table currently describes the ledger basis alone ("Turn the churn ledger into evidence-carrying candidate work items…"). Update it to name **both** bases. This is the third doc mirror and **no CI gate covers it**: root `scripts/check-command-sync.sh` targets only `loomwright/commands/code-reviewer.md`, and `check-doc-currency.sh` verifies counts and versions, not prose. It is in this subtask's lane precisely because nothing mechanical will catch it.
- `CHANGELOG.md` — a new top entry; `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` — bump `15.61.0` → `15.62.0` and update the `vX.Y.Z` string **in place** in both `description` fields without appending a new version clause. **Counts are unchanged** (no new command, agent, skill, or hook) — do not touch them.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none | YES (dependency, not overlap) |

Subtask 2 is BLOCKED because its `requires` list is non-empty: the test file asserts on the producer's exact emitted bytes and its fixture paths, so it must be authored against the finished script rather than against a guess. There is zero lane overlap between the two.

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/quality-checklist/SKILL.md`, `skills/error-handling/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md`, `skills/quality-checklist/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| macOS bash 3.2 + BSD userland vs GNU CI: `stat -f %m` succeeds with *garbage* on Linux, `date -d` is GNU-only, `sed -i` differs. A macOS-green run is not CI-green. | HIGH | Try `stat -c %Y` first and fall back to `-f %m`; validate a mtime is numeric before any `$(( ))` under `set -u`; never use `date -d`. This exact defect shipped once already (PR #101 fail-open). |
| A test assertion goes silently vacuous — `producer \| grep -q` returns 141 under `pipefail` even on a match; `local x="$(...)"` discards the status; `... \|\| echo 0` appends a second line. | HIGH | Run `grep -q` only directly against a FILE, never as the right side of a pipe; keep assignment and status-check as separate statements; take counts from an `awk END`. Mirror `test-propose-work.sh`'s header, which enumerates all three. |
| Fixtures live under `.supervisor/`, which is gitignored ⇒ CI exercises only the fail-safe skip path and goes silently green. | HIGH | Every fixture is committed under `loomwright/scripts/fixtures/propose-domain/` and restamped at test time; the real-tree run, if any, is a local-only corroboration whose skips are reported separately and never counted as passes. |
| Root `.gitignore`'s bare `*.log` makes `git add` silently skip any `.log` fixture — present on disk, absent from a fresh clone. | MEDIUM | No committed fixture uses a `.log` extension. Verify with `git check-ignore -v` and `git ls-files` before completing, never with `git add -f`. |
| The doc mirrors drift: `/propose` is described in **three** places — `commands/propose.md`, `commands/agent-help.md`, and the root `README.md` command table — and nothing mechanical couples them. `check-command-sync.sh` covers only `code-reviewer.md`; `check-doc-currency.sh` checks counts and versions, not prose. A green CI run is necessary but not sufficient here. | MEDIUM | Subtask 2 owns all three files in one lane and edits them in the same change. Before completing, sweep `grep -rn '/propose' README.md loomwright/commands/ loomwright/docs/` and confirm no surviving surface still says the ledger is the only basis or that the command takes no flags. |
| A guard written to catch a claim ends up vacuous itself — a `NOT-FOR-US` suppression or an unverified path that passes with the mechanism deleted. | MEDIUM | Each such case carries an explicit mutation control that deletes the guard and asserts the case then FAILS. This is required, not optional. |
| `stance_default_action` gets re-derived locally instead of read from `read-product.sh`, giving the mapping a second home that can drift. | MEDIUM | Design constraint 6 forbids it; `propose-domain.sh` shells out to `read-product.sh` and consumes its emitted value. |
| Scope (~1100 changed lines across 13 files) exceeds one worker's context budget — Feasibility (Phase 2.5) row 4. | MEDIUM | Split into 2 sequential subtasks; Subtask 2 is authored against the finished producer rather than against a guess, so neither worker carries both halves. |
| `PROPOSE_DOMAIN_FETCH_CMD` resolves an arbitrary command invoked as `<cmd> <url>` — an execution seam. | LOW | It is the standard overridable-fetcher test pattern and runs at the same trust level as the invoking shell. Binding requirement: an **unset** value must degrade to *no fetch at all* (report it, mark coverage partial, every expectation `unverified`) and must NEVER fall back to a shell default or an implicit `curl`. |
| The 02a store is absent in most real repos, so `--domain` is a no-op there. | LOW | That is the specified behaviour (AC2): name the absence, offer the bootstrap, write nothing, exit 0. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-09-propose-domain-mode.md
```
