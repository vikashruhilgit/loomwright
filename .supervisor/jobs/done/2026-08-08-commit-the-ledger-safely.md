# Supervisor Job: Make the findings ledger committable, safely (fail-closed on foreign records)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — last committed 2026-08-08)
- **Git:** clean (0 files), branch: main @ 0276ad6 (== origin/main)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit; scopes gist, read:org, repo, workflow)
- **Blockers:** 0 | **Warnings:** 1 (6 orphaned `.claude/worktrees/*` from prior sessions — unrelated to this lane, do not clean up here)
- **Source requirement:** .supervisor/requirements/twin-loop/01c-commit-the-ledger.md

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | POSIX sh + jq + git, exactly the existing `setup-memory.sh` idiom. No new dependency. |
| 2 | Dependency Availability | GO | `jq` already required and already guarded (`seed_allowlist` / `filter_ledger_by_allowlist` both skip-with-message when absent). |
| 3 | Architecture Fit | GO | The change is a new managed-path + a fail-closed gate inside an existing, well-factored helper with an 807-line test suite already covering the negation classes. |
| 4 | Scope vs Supervisor Capability | GO | Single coherent capability in one script + its test + doc mirrors → Single-Agent Path (Decomposition Threshold default 1). |
| 5 | Hard Blockers | GO | No credentials, no migration, no missing module. `.supervisor/postmortem/results.jsonl` exists (88 records). |

**Overall Verdict:** GO

## Task
**Goal:** Make `.supervisor/postmortem/results.jsonl` committable via `/setup memory apply`, gated so that `apply` **fails closed** (refuses to un-ignore the ledger, naming the offending slugs) whenever the ledger holds a record whose `.repo` is outside the resolved allowlist — then apply it to this repo and commit the filtered ledger.

**Problem Statement:**
The Twin's learning loop needs the findings ledger in version control, but three verified findings block a naive addition. Currently the ledger is gitignored, so the churn corpus does not travel with the repo and every fresh clone starts blind. Success looks like: `apply` either un-ignores a provably-clean ledger or refuses with a named reason; the negation survives repeated `apply` runs; `check` can no longer report a false `configured`; and every consent surface tells the truth about the third store.

### Verified grounding (all anchors re-checked against HEAD 0276ad6 — cite these, not the requirement's numbers)

The requirement file's line references drifted by ~1 in places. **These are the verified ones:**

**Anchor by DESCRIPTION, not by line number** (this repo's recorded `absolute line-ref drift` class — and Plan Review round 1 caught two inverted "corrections" in an earlier draft of this very table). Line numbers below are a convenience as of `0276ad6`; the descriptive anchor is authoritative.

| Claim | Verified anchor | Status |
|---|---|---|
| Block re-emitted at EOF on every apply | `proposed_applied_content()` in `setup-memory.sh` = `strip_managed_block \| comment_bare_excludes` **then** `managed_block` (~`:369-372`) | ✓ confirmed |
| The `.supervisor/*` line lives inside `managed_block()`, with `!.supervisor/memory/` next | the `.supervisor/*` / `!.supervisor/memory/` pair in the `managed_block()` heredoc (~`:362-363`) | ✓ confirmed |
| `strip_managed_block` removes BEGIN..END inclusive | `strip_managed_block()` awk (~`:260-266`) | ✓ confirmed |
| `INTENDED_PATHS` omits the ledger | the `INTENDED_PATHS=` assignment — **4** entries, ending `.supervisor/memory/.lessons-provenance.jsonl` (`:145-148`; the requirement's range was right, an earlier draft of this brief wrongly "corrected" it) | ✓ confirmed |
| `apply` NEVER filters the ledger | `filter_ledger_by_allowlist()` is called ONLY from `do_filter_ledger()` (the `filter-ledger` subcommand). `do_apply` calls `seed_allowlist` / `print_consent_disclosure` / `render_report` / `warn_if_not_configured` — never the filter. | ✓ confirmed |
| `load_allowlist` layer-4 default = current git remote alone | the `if [ -z "$out" ]; then out="$(remote_slug)"` fallback in `load_allowlist()` (~`:513-520`) | ✓ confirmed |
| `seed_allowlist` never overwrites a non-empty array | the `existing_kind = array && existing_len > 0` early return printing `"already configured … left untouched"` (`:550-553`; the requirement's range was right, an earlier draft wrongly "corrected" it) | ✓ confirmed |
| Rename warning | the `"(a repo RENAME needs the OLD slug added by hand …)"` echo at the tail of `seed_allowlist` (~`:583`) | ✓ confirmed |
| Consent disclosure enumerates exactly two stores | `print_consent_disclosure()`; the now-false line is **`What stays IGNORED (unchanged): … and everything else under those two directories.`** | ✓ confirmed |
| `commands/setup.md` mirror sites | `:119`, `:299`, `:326`, `:344`, `:361` — all five real, all naming exactly the two store paths | ✓ all five real |
| Verbatim-disclosure mandate | `commands/setup.md:319` (*"Show it verbatim — do not paraphrase, summarise or shorten it"*) | ✓ confirmed |
| **Helper is exit-0 on EVERY branch** | the `FAIL-SAFE CONTRACT` header block (~`:40-44`) + `# Exit: 0 in every normal path` (~`:73`): *"Machine-readable status lines … carry the outcome instead of an exit code"* | ✓ confirmed |
| **Two more two-store surfaces exist beyond the five** | `commands/agent-help.md` `/setup` entry (~`:787`) enumerates `.claude/agent-memory/` + `.supervisor/memory/`; `skills/setup/SKILL.md` §Pattern 8 (~`:55-69`) is the module-protocol authority carrying the abort-class and allowlist bullets | ✓ both in scope |
| **`setup-memory.sh` header restates a stale count** | the WHY-the-allowlist-is-a-LIST comment (~`:25`) says *"42 records … against **35** under the current slug"* — the true current figure is **39** | ✓ in scope, must refresh |

### CORRECTION — the requirement's record counts are STALE (do not hard-code 79)

The requirement says 42 `ai-agent-manager` + 37 `loomwright` = 79 retained. **Re-measured at HEAD with jq:**

```
42  vikashruhilgit/ai-agent-manager
39  vikashruhilgit/loomwright     <-- was 37; the ledger grew (01b's own drain emitted lines)
 7  otherhub                    <-- the foreign records to filter out
88  total
```

Retained is **42 + 39 = 81**, not 79. The requirement's *instruction* ("Retained counts verified, not assumed") is exactly right and is what caught this — **re-derive the counts at implementation time; do not copy 81 either, it may drift again before the worker runs.**

The grep-vs-jq evasion is real and current: `grep -c '"repo":"vikashruhilgit/loomwright"'` returns **38**, `jq` returns **39** — line **83** is the spaced-form record (`"repo": "…"`). Same mechanism the requirement describes, different absolute numbers.

### Also verified: `.setup_memory.repo_allowlist` is ALREADY two entries

`.supervisor/config.json` currently holds `["vikashruhilgit/ai-agent-manager","vikashruhilgit/loomwright"]`, so the requirement's Scope §5 one-entry-array hazard is **not live** right now. The AC still stands unchanged — **assert two entries via `setup-memory.sh allowlist` before filtering**, because a re-seed is a silent no-op and the state could differ by the time the worker runs.

> **Live-config caution:** `.supervisor/config.json` is in active use by the running `/automate` engine (it carries `webhook_url` and a transient `auto_review` key). Read it, and write ONLY `.setup_memory.repo_allowlist` if a write is needed — never rewrite the whole file, never drop unrelated keys.

### DESIGN DECISION (settled here so the worker does not have to invent it)

**Two coupled decisions, both forced by Plan Review round 1:**

**(a) "Fail closed" here means REFUSE-TO-WRITE + a named-slug status line + `exit 0`.** It does NOT mean a non-zero exit. `setup-memory.sh` carries an explicit `FAIL-SAFE CONTRACT` — every branch exits 0 and *"machine-readable status lines carry the outcome instead of an exit code"*. CLAUDE.md §"Failure-Mode Invariants" classes this helper as a **runtime emitter** (fail SAFE / always exit 0), and the *gate* it now carries fails closed **in the write dimension** — it refuses to un-ignore. Breaking exit-0 would regress the helper's contract and every caller that treats it as non-blocking.

**(b) The ledger's `INTENDED_PATHS` membership must be CONDITIONAL, and a THIRD verdict class `gated` is added.** Verified mechanism: `render_report` sets `intended_ok=no` for any INTENDED path probing `ignored`; that yields verdict `not configured`; `warn_if_not_configured`'s `not configured` branch prints **UNDER-inclusion** copy telling the user to comment out "the surviving exclude" — which for a gated ledger is the module's OWN `.supervisor/*` line, i.e. exactly the wrong remedy, and `commands/setup.md:342` mandates relaying it verbatim and NOT presenting the apply as success. So an unconditional add makes a **correct refusal permanently self-report as failure with destructive guidance.**

The fix follows the script's own recorded design rule, stated in the comment above `warn_if_not_configured`: *"THE TWO FAILURE MODES ARE OPPOSITES AND MUST NOT SHARE COPY."* A gated ledger is a **third** mode (deliberately withheld, repo is contaminated) and likewise must not share copy with either. Therefore:
- the ledger joins the probed intended set **only when the gate passes**;
- when the gate refuses, the verdict is the new `gated` class with its own dedicated `warn_if_not_configured` branch naming the **offending slugs** and the remedy (`filter-ledger`, or extend the allowlist) — never the "comment out the surviving exclude" copy. Implementation note: `warn_if_not_configured` is a `case` on `$REPORT_VERDICT` whose under-inclusion text is a **fall-through default**, so a `gated*)` arm must be inserted **ahead of** that fall-through; the verdict `elif` chain takes a new branch cleanly;
- `configured` still requires the two original stores; a `gated` repo is NOT `configured` and NOT `not configured`.

**(c) The managed block IS genuinely conditional — and the byte-compare idempotency contract is RESTATED, not broken.** The alternative (emit the ledger lines unconditionally and gate only the verdict) was considered and **REJECTED**: it would have `apply` un-ignore an unfiltered cross-repo ledger, which is precisely the AC1 this whole item exists to satisfy. So the block content genuinely varies with the gate outcome, and two documented statements need one clause each:
- `commands/setup.md:365` (*"A second `/setup memory` on an already-applied repo reports 'already configured' and writes nothing"*)
- `skills/setup/SKILL.md` §Pattern 8 (*"The block content must be byte-stable across runs"*)

The honest restatement: **the block is a pure function of (`.gitignore` contents, gate outcome).** Byte-stability holds for a fixed gate outcome — which is what idempotency actually requires — but the gate outcome is now an input, so a repo that applied cleanly and LATER gains a foreign record WILL legitimately rewrite `.gitignore` on the next apply, withdrawing the ledger negation. That transition is **correct fail-closed behaviour, but it must be ANNOUNCED, not silent**: it must print a distinct "ledger negation WITHDRAWN — <slugs> appeared since the last apply" line, never a bare `apply: applied`.

> **Honest limit that MUST appear in that message and in the docs:** re-ignoring does **NOT** un-track an already-committed ledger — `.gitignore` only affects untracked files. A repo that already committed the ledger and then gained a foreign record must be told to run `git rm -r --cached` / filter and re-commit; the withdrawal alone does not unpublish anything. Never imply otherwise.

**(d) Gate semantics on the two degenerate inputs (stated so the worker does not guess):**
- **Ledger ABSENT** ⇒ the gate **PASSES** (no records ⇒ no foreign records ⇒ nothing to withhold). This is the state of every fresh user repo and every test fixture. It is also load-bearing for an existing consumer: `loomwright/scripts/test-committed-twin-scrub.sh` asserts `"Memory readiness: configured"` on a `--root` fixture that has both memory stores and NO ledger — "absent ⇒ refuse" would turn that assertion red.
- **`jq` ABSENT** ⇒ the gate is **NOT EVALUATED**: the ledger is simply not probed and today's verdict is preserved unchanged. It must NOT fail toward `gated` (that would permanently mis-report for every jq-less user) and must NOT fail toward emitting the negation. This mirrors the existing `seed_allowlist` / `filter_ledger_by_allowlist` skip-with-message guards and preserves the FAIL-SAFE CONTRACT.

## Acceptance Criteria
- [ ] Given a repo whose ledger holds a record with a non-allowlisted `.repo`, when `setup-memory.sh apply` runs, then it does NOT emit the ledger negation, prints a status line naming the offending slug(s), **and still exits 0**.
- [ ] Given the gate is satisfied, when `apply` runs TWICE, then the ledger is committable after both runs — pinned as a regression test that FAILS against the pre-fix (hand-added-line-outside-the-block) form.
- [ ] Given the three negation lines are emitted BEFORE `.supervisor/*`, when ignore status is probed, then the ledger is still ignored — pinned as a negative control, alongside the naive one-line form.
- [ ] Given the gate PASSES, when `setup-memory.sh check` runs, then the ledger appears under `intended (must be committable)` and is probed.
- [ ] Given the gate REFUSES, when the report renders, then the verdict is the new `gated` class — NOT `not configured` — and the emitted warning names the offending slugs and the `filter-ledger`/extend-allowlist remedy, and does NOT tell the user to comment out a surviving exclude.
- [ ] Given any ledger assertion in the test suite, when it counts or matches records, then it uses **jq**, never grep — and a spaced-form record is a **named fixture case**.
- [ ] Given a simulated foreign-repo record appended **in the spaced form**, when the gate runs, then it REFUSES; when the record is removed, then it PASSES.
- [ ] Given `print_consent_disclosure()`, the script header WHAT block, the managed block's inline comment, `do_remove()`'s copy, all five `commands/setup.md` mirror sites, `commands/agent-help.md`'s `/setup` entry, and `skills/setup/SKILL.md` §Pattern 8, when each is read, then it names the third store and the cross-repo caveat; no surface still enumerates only two stores.
- [ ] Given `plugin.json`, `.claude-plugin/marketplace.json` and the CLAUDE.md banner, when read, then each carries the NEW version literal; and `CHANGELOG.md` has a new heading for that version. (The old-version sweep is scoped to NON-changelog surfaces — `CHANGELOG.md` retains old versions by design.)
- [ ] Given `commands/setup.md`'s verdict enumerations (`:82` dashboard cell, `:311` Check section), its "already configured" branch (`:332`), its Verify success criterion (`:354`), its **closed three-headline `apply` enumeration (`:337`, `:339`)** and its **WARNING prose (`:342`, which today defines the warning as under-inclusion only)**, when each is read, then `gated` is admitted as a distinct third outcome with its own rendering (the two memory stores ARE applied, the ledger is withheld), the headline enumeration admits the **gated** and **withdrawn** headlines, and Verify no longer requires the verdict to read `configured` to claim success.
- [ ] Given a repo already applied while GATED, when `apply` runs again and the byte-compare finds no change, then the headline does NOT read `apply: no-op — already configured` — it names the gated state instead. (Trace: `proposed_applied_content()` omits the ledger lines while gated, so `current == proposed` and `do_apply` reaches its no-op branch, printing the exact "already configured" copy the `gated` class exists to prevent — and `commands/setup.md:337` mandates relaying that headline **verbatim**.)
- [ ] Given a repo that applied cleanly and THEN gained a foreign-slug record, when `apply` runs again, then the ledger negation is withdrawn, a distinct "withdrawn + which slugs" line is printed (never a bare `apply: applied`), and the message states that withdrawal does NOT un-track an already-committed ledger.
- [ ] Given a repo with NO ledger file, when `apply` runs, then the gate PASSES and the verdict still reaches `configured` — asserted, and `test-committed-twin-scrub.sh`'s group (F) fixture assertion stays green.
- [ ] Given `loomwright/scripts/test-committed-twin-scrub.sh`, when it is updated, then its **real-repo** ledger assertion has moved from the `assert_ignored` heredoc into the `assert_committable` heredoc, the deferral comment above it is rewritten to record that THIS item is the "later item" it was waiting for, and the suite passes.
- [ ] Given `jq` is unavailable, when `apply`/`check` run, then the gate is not evaluated, the ledger is not probed, the pre-existing verdict is unchanged, and the exit code is still 0.
- [ ] Given the test suite runs, when it completes, then it made ZERO writes under the real repo root (`mktemp -d` + `git init` + `--root`, with `trap … EXIT`).
- [ ] Given `setup-memory.sh allowlist` runs BEFORE any filtering, when its output is read, then it prints **two** entries — asserted, not assumed.
- [ ] Given this repo's committed ledger, when every record's `.repo` is checked with jq, then ZERO records fall outside the allowlist — re-asserted after a simulated foreign append.
- [ ] Given the `setup-memory.sh` header's illustrative record counts, when read after the change, then they match the re-derived live figures (or are explicitly marked frozen) — the current text's `35` is stale.

## Outcomes Rubric
- A shell function named `ledger_gate_blocks_foreign_records` exists in `loomwright/scripts/setup-memory.sh` and is called on the `apply` path before the managed block is written.
- The ledger negation is emitted inside `managed_block()` **after** the `.supervisor/*` line, and `loomwright/scripts/test-setup-memory.sh` contains both `test_negation_wrong_position_still_ignored` and a naive-one-line negative control.
- `loomwright/scripts/test-setup-memory.sh` contains `test_gate_blocks_foreign_spaced_form`, and every ledger assertion in that file uses `jq` (no `grep` against `"repo"`).
- `setup-memory.sh` defines a `gated` verdict class with its own `warn_if_not_configured` branch that names the offending slugs and does NOT emit the surviving-exclude remedy, and `commands/setup.md` admits `gated` in its verdict enumerations, its Verify success criterion, and its `apply` headline enumeration (which also admits the withdrawn headline).
- `commands/setup.md`, `commands/agent-help.md` and `skills/setup/SKILL.md` each name the findings ledger as a third managed store with its cross-repo caveat, and `print_consent_disclosure()` in `setup-memory.sh` no longer claims only two directories are affected.
- `.supervisor/postmortem/results.jsonl` appears in the diff as a newly tracked file containing ZERO records whose `.repo` is outside the allowlist — in particular zero `otherhub` records (7 present at `0276ad6`).
- `15.28.0` appears in `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, the `CLAUDE.md` banner and a new `CHANGELOG.md` heading.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Gate + emit the ledger as a third managed store, add the `gated` verdict class, update every consent surface, apply to this repo | all 17 | 12 modify, 0 create | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

### File Impact Map

| Path | Action | Confidence | Why |
|---|---|---|---|
| `loomwright/scripts/setup-memory.sh` | modify | HIGH | the gate, the `managed_block()` emission, conditional `INTENDED_PATHS`, the `gated` verdict + warning branch, header WHAT block + stale-count refresh, `do_remove()` copy — **and `do_apply`'s no-op headline (~`:857`), which must not read `already configured` when the verdict is `gated`** |
| `loomwright/scripts/test-setup-memory.sh` | modify | HIGH | new gate/negative-control/spaced-form fixture groups |
| `loomwright/commands/setup.md` | modify | HIGH | five mirror sites + the verbatim disclosure + the `gated` status cell |
| `loomwright/commands/agent-help.md` | modify | HIGH | `/setup` entry's two-store enumeration |
| `loomwright/skills/setup/SKILL.md` | modify | MEDIUM | §Pattern 8 abort-class + allowlist bullets gain the ledger gate; the byte-stability bullet gains the "pure function of (contents, gate outcome)" restatement per design decision (c) |
| `loomwright/scripts/test-committed-twin-scrub.sh` | **modify (REQUIRED — this is a CI-breaking edit, not an optional one)** | HIGH | Its group (D) `assert_ignored` heredoc lists `.supervisor/postmortem/results.jsonl`, probed against the **REAL repo root** (`ignore_is` → `ignore_is_in "$REPO_ROOT"`), and the suite is fail-CLOSED (`exit 1`) and hard-globbed by CI (`loomwright/scripts/test-*.sh`). The moment this item applies the change to this repo, that assertion flips to `committable` and **CI goes red**. Move that one path into the `assert_committable` heredoc and rewrite the deferral comment above it (which says the ledger *"must STAY ignored until a later item filters it behind an explicit consent surface"* — this item IS that later item). Leave the group (F) fixture-`configured` assertion as-is; it holds under decision (d). |
| `loomwright/.claude-plugin/plugin.json` | modify | HIGH | version bump |
| `.claude-plugin/marketplace.json` | modify | HIGH | version bump |
| `CLAUDE.md` | modify | HIGH | version banner |
| `CHANGELOG.md` | modify | HIGH | new release entry |
| `.gitignore` | modify | HIGH | the regenerated managed block (written BY the helper, not by hand) |
| `.supervisor/postmortem/results.jsonl` | modify | HIGH | filtered to allowlisted records, then committed |
| `.supervisor/config.json` | conditional modify | MEDIUM | ONLY if `allowlist` does not already print two entries; `jq`-set `.setup_memory.repo_allowlist` alone |

### Subtask 1 contract

```yaml
provides:
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "ledger_gate_blocks_foreign_records"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "LEDGER_INTENDED_PATH"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "REPORT_GATED"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-memory.sh", name: "test_gate_blocks_foreign_spaced_form"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-memory.sh", name: "test_negation_wrong_position_still_ignored"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.28.0"}
  - {kind: "symbol", path: ".claude-plugin/marketplace.json", name: "15.28.0"}
  - {kind: "symbol", path: "CHANGELOG.md", name: "15.28.0"}
  - {kind: "symbol", path: "CLAUDE.md", name: "15.28.0"}
requires: []
external_requires:
  - jq
  - git
lanes:
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/test-setup-memory.sh"
  - "loomwright/commands/setup.md"
  - "loomwright/commands/agent-help.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "CLAUDE.md"
  - ".gitignore"
  - "loomwright/scripts/test-committed-twin-scrub.sh"
  - ".supervisor/postmortem/results.jsonl"
  - ".supervisor/config.json"
```

> **`provides` SUFFICIENCY note (the second form of the `outputs_verified` no-op class — false-COMPLETING rather than false-passing).** The headline deliverable — the *filtered, committed* ledger — is deliberately **absent from `provides`**, because `kind: file` cannot express "tracked AND filtered" and would false-pass on a file that exists today with 88 records. It is instead anchored in **rubric bullet 7** (the untracked→tracked flip IS visible in the PR diff, and the zero-foreign-record assertion is diff-checkable) and in AC12. **A worker that satisfies all 9 `provides` and never filters or commits the ledger has NOT done this job** — the rubric and the ACs are where that is caught, not the deterministic gate.

> **`provides` naming note (LOAD-BEARING — this is the repo's `outputs_verified is a silent no-op` class).** Every name above was verified **absent repo-wide at `0276ad6`**, so each is a real discriminator that cannot pass before the work is done. They are **required literal identifiers**, not paraphrases:
> - `ledger_gate_blocks_foreign_records` — the gate function.
> - `LEDGER_INTENDED_PATH` — the ledger's own path constant. **Do NOT satisfy this by editing `INTENDED_PATHS`**: that identifier already exists in the file today and would false-pass.
> - `REPORT_GATED` — the third verdict class's state variable.
> - the two `test_*` names — the gate + wrong-position fixtures.
>
> **Deliberately NOT declared as `provides`:** `.supervisor/postmortem/results.jsonl` (it exists today with 88 records, and `kind: file` cannot express "tracked AND filtered"), and `loomwright/scripts/test-setup-memory.sh` as a bare file. Their real assertions live in the Acceptance Criteria and the test suite. Note also that the literal string `.supervisor/postmortem/results.jsonl` already appears in `setup-memory.sh`'s header comment, so a symbol-provide on that string would false-pass too.

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
| 1 | `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Emitting the negation in the wrong position inside `managed_block()` silently re-ignores the ledger — and `render_report` would still print `configured` | **HIGH** | Both defects are closed together: the three lines go AFTER `.supervisor/*`, AND the ledger joins `INTENDED_PATHS` so the probe can see it. Pin BOTH wrong forms (naive one-line, correct-lines-wrong-position) as negative controls. |
| `apply` un-ignoring an UNFILTERED cross-repo ledger in every user's repo — generalizing the exact contamination this queue remediates | **HIGH** | The fail-closed gate is the primary mitigation: `apply` refuses while any record's `.repo` is outside the resolved allowlist (fail-closed over the opt-in flag, per CLAUDE.md §"Failure-Mode Invariants"). **Residual, stated honestly and NOT fully mitigated:** the gate is evaluated **at apply time only**, so a repo whose ledger gains foreign records AFTER a clean apply stays un-ignored until the next apply — and this repo's own recorded `git add -A` sweep class makes "contaminated ledger committed with no apply in between" a mechanised path, not a theoretical one. The consent disclosure MUST say so and direct the user to run `filter-ledger` before committing. Do not present the gate as complete coverage. |
| The ledger becomes a third COMMITTED store but escapes the foreign-TERM sweep — the gate keys on `.repo` only, while a record whose `.repo` is allowlisted may still cite a foreign org in its finding TEXT (the recorded "otherhub #146" incident class) | MEDIUM | **Decision, not oversight:** this item gates on `.repo` only; content-level sweeping of the ledger is explicitly DEFERRED and recorded as a non-goal below. `test-committed-twin-scrub.sh`'s `EXPLICIT_STORE_ROOTS` covers only the two memory stores and is deliberately NOT widened here — widening it is its own item. State this as a non-goal in the change so the omission is auditable. |
| A grep-based ledger assertion silently under-counts (spaced vs compact JSON) and a foreign record in spaced form evades the guard entirely | **HIGH** | Every ledger assertion is jq-based; the spaced-form record (currently line 83) is a NAMED fixture case; the simulated foreign append is done in the SPACED form specifically. |
| Consent disclosure becomes materially false ("everything else under those two directories") while `commands/setup.md:319` mandates showing it verbatim | **HIGH** | Update `print_consent_disclosure()` + the script header WHAT block + the managed block's inline comment + `do_remove()`'s copy + all five `setup.md` mirror sites **+ `commands/agent-help.md`'s `/setup` entry + `skills/setup/SKILL.md` §Pattern 8** in the SAME change. Also audit `setup.md:305`/`:307`, which name the stores outside the five cited sites. `check-command-sync.sh` does NOT cover prose, so nothing mechanical catches this drift — the closing sweep is a repo-wide grep for two-store enumerations, not a five-site checklist. |
| A correct gate refusal reports as `not configured` and emits the UNDER-inclusion remedy ("comment out the surviving exclude" = the module's own `.supervisor/*`), relayed verbatim per `setup.md:342` | **HIGH** | The settled design decision (b) above: conditional `INTENDED_PATHS` membership + a third `gated` verdict class with its own warning branch. Pin the `gated` verdict AND its warning copy as tests; assert the surviving-exclude copy is NOT emitted on that path. |
| Implementing "fail closed" as a non-zero exit would break the helper's `FAIL-SAFE CONTRACT` and every non-blocking caller | MEDIUM | Settled design decision (a): refuse-to-write + named-slug status line + `exit 0`. Pin `exit 0` as an explicit assertion on the refusal path. |
| Fixing `gated` only in the script leaves the COMMAND layer reproducing the same defect — `setup.md:354` claims success only on verdict `configured`, so a correctly-gated repo reports as non-success one layer up | **HIGH** | Design decision (b) explicitly extends to the command layer: `:82`, `:311`, `:332`, `:354` all admit `gated`. Covered by its own AC and rubric bullet 4. `check-command-sync.sh` does NOT cover prose, so this is the recorded agent↔command mirror-drift class — the closing sweep must be a repo-wide grep for verdict enumerations, not a named-site checklist. |
| A conditional managed block silently rewrites `.gitignore` and withdraws the ledger negation when contamination arrives later, while two docs promise byte-stability | MEDIUM | Design decision (c): the conditional block is KEPT (the alternative defeats AC1), the two doc statements are amended to "pure function of (contents, gate outcome)", the withdrawal is ANNOUNCED with the offending slugs, and the message states withdrawal does NOT un-track an already-committed ledger. AC covers the gate-passed→contaminated→re-apply transition. |
| Undefined gate behaviour on an absent ledger or absent `jq` — "absent ⇒ refuse" would redden `test-committed-twin-scrub.sh` and permanently mis-report for jq-less users | MEDIUM | Design decision (d): absent ledger ⇒ PASS; absent `jq` ⇒ gate not evaluated, verdict unchanged, still exit 0. Both pinned as ACs; `test-committed-twin-scrub.sh` added to the lane so the worker re-runs it. |
| Hard-coding the requirement's stale record counts (79) would make the guard assert a false number | MEDIUM | Counts are **re-derived at implementation time** with jq. Verified today: 42 + 39 = 81 retained, 7 foreign, 88 total. Do not copy either number blind. |
| Rewriting the live `.supervisor/config.json` would clobber the running engine's `webhook_url` / transient `auto_review` | MEDIUM | Read it; if a write is needed, `jq`-set ONLY `.setup_memory.repo_allowlist` and rename atomically. Never rewrite the whole file. |
| Tests writing under the real repo root would pollute the working tree mid-`/automate` run | MEDIUM | `mktemp -d` + `git init` + `--root` with `trap … EXIT`, per the existing `test-no-junk-tracked-files.sh:62-71` convention. |
| Committing the ledger publishes 81 records of churn analysis to a PUBLIC repo | MEDIUM | This is the deliberate, owner-approved intent of queue item 01c; the gate exists precisely so only allowlisted records ship. The 7 `otherhub` records are filtered out BEFORE the commit. |

## Non-goals (explicit — so omissions are decisions, not oversights)
- **No content-level sweep of the ledger.** The gate keys on `.repo` only. A record with an allowlisted `.repo` whose finding TEXT cites a foreign org is NOT caught here; widening `test-committed-twin-scrub.sh`'s `EXPLICIT_STORE_ROOTS` to `.supervisor/postmortem` is a separate item.
- **No changes to the two existing memory stores** (that was item 01b).
- **No new agent / command / skill / hook** — those four counts stay unchanged. The plugin version DOES bump, because capability code changes.

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-08-commit-the-ledger-safely.md
```
