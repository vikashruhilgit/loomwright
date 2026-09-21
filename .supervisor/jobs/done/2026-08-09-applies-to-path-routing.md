# Supervisor Job: Implement `applies_to` path routing in the house-rules reader

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh — updated 2026-08-09, describes v15.29.0)
- **Git:** branch `main` @ 585d314; working tree carries ONE intentional uncommitted line
  (`.supervisor/postmortem/results.jsonl`, the engine-native learning line for PR #134 — owner
  decision: carry it into this branch's PR, do not stash)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Worktrees:** 6 sibling worktrees present (`.claude/worktrees/*`) — none on the branch this job
  will create; Single-Agent Path creates no new worktree
- **Blockers:** 0 | **Warnings:** 1 (pre-existing uncommitted ledger line, deliberate)

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure bash 3.2 + `jq`, identical to the existing reader/writer pair. No new dependency. |
| 2 | Dependency Availability | GO | `jq` already a hard requirement of `read-rules.sh` (it exits 0 and emits nothing when absent). |
| 3 | Architecture Fit | GO | The advisory-reader contract (always exit 0, EMPTY on nothing-to-say, `--arg`-only into jq, `check` is DATA) is unchanged; routing is a filter placed inside it. |
| 4 | Scope vs Supervisor Capability | GO | One coherent feature across ~11 files, no genuine parallelism, no file conflict → Single-Agent Path (Decomposition Threshold default 1). |
| 5 | Hard Blockers | CAUTION | Two — see Risk Assessment R1 (the requirement's seam evidence is partly WRONG) and R2 (`case`-glob semantics ≠ `.gitignore` semantics, which the requirement itself flags). |

## Task

**Problem Statement:** `read-rules.sh` emits **every** rule to **every** agent on **every** task. `applies_to`
exists in the schema but is inert — the reader accepts touched paths as positional args and discards them. A
rule that fires everywhere is indistinguishable from a rule that fires nowhere.

**Goal:** Make `applies_to` a real path filter in `.agent/rules/`, honoured by `read-rules.sh`, writable by
`add-rule.sh --applies-to`, failing **OPEN** on every ambiguity, and prove that a **non-match actually
SUPPRESSES** a rule (a test that only asserts emission cannot distinguish working routing from today's no-op).

**Source requirement:** `.supervisor/requirements/twin-loop/03-applies-to-routing.md` (queue item 03 of the
twin-loop backlog; declared **BLOCKER** for items 04 and 05 — do not reorder).

**Why now:** the store holds exactly ONE rule, so "every rule to every agent" is currently invisible. Item 05
harvests ~104 own-repo `convention_mismatch` findings into rules; fifty unrouted rules injected at three seams
produce token bloat *and* the advisory-prose-gets-ignored effect this queue exists to fix.

### Verified ground truth (read from the files, 2026-08-09 — supersedes the requirement where they disagree)

| Claim in `03-…md` | Verified? | Correction |
|---|---|---|
| `read-rules.sh:18` + `:53` describe `applies_to` as INERT/reserved | ✓ exact | — |
| `add-rule.sh:376` hardcodes `applies_to: null` | ✓ exact | it sits inside the `jq -n` object builder at `:371-380` |
| `read-rules.sh:303` uses a `case "$line" in` idiom | ✓ exact | but that `case` partitions the jq output stream (`SKIP\t`/`RULE\t`), it is **not** a path matcher — it is a *precedent* for the idiom, not a call site to extend |
| Worker DO-side seam `agents/supervisor.md:735` passes touched paths as args | ✓ | prose seam; says "args, never stdin" |
| Worker DO-side seam `agents/execute-manager.md:190` | ✓ | prose seam |
| Phase 4.5 seam `skills/self-heal-advisory/SKILL.md:534` (+ call shape at `:216-226`) | ✓ | prose seam; passes the integrated-diff scope as args |
| SessionStart seam `scripts/session-resume.sh:197` | ✗ **WRONG** | the real seam is `rules_nudge()` at **`scripts/session-resume.sh:294-329`**, and the reader call at **`:311`** is `bash "$reader"` — **NO ARGUMENTS AT ALL**. `:197` is an unrelated observability-probe comment. |
| "All three seams already pass the touched-file set. No seam changes are required." | ✗ **FALSE for the third seam** | two of three pass paths; the SessionStart nudge passes none. See R1. |
| The `applies_to`/INERT prose lives in 3 places | ✗ **undercount** | **11** stale-prose sites — enumerated below. |

### The authoritative sweep set for AC10 (11 sites, enumerated — grep-verified 2026-08-09)

| # | Site | What it currently claims |
|---|------|--------------------------|
| 1 | `loomwright/scripts/read-rules.sh:18` | "RESERVED for slice 3b-ii enforcement filtering — INERT in v1" |
| 2 | `loomwright/scripts/read-rules.sh:53` | "informational / forward-compat ONLY … `applies_to` is inert in v1" |
| 3 | `loomwright/commands/rules.md:38` | "`applies_to` is still inert (reserved for a later slice…)" |
| 4 | `loomwright/skills/self-heal-advisory/SKILL.md:221-222` | "emits ALL valid rules regardless of the touched paths (the `applies_to` field is INERT / reserved…)" |
| 5 | `loomwright/skills/self-heal-advisory/SKILL.md:534` | Phase 4.5 seam prose carrying the same inert/reserved claim |
| 6 | `loomwright/skills/rules/SKILL.md:56` | schema table: "RESERVED for a later slice's path/scope filtering" |
| 7 | `loomwright/skills/rules/SKILL.md:89` | "exists in the schema (§1) but is **still inert**" |
| 8 | `loomwright/skills/rules/SKILL.md:97` | "positional args … **do NOT change the v1 output**" — now false |
| 9 | `loomwright/skills/rules/SKILL.md:205` | Anti-pattern: "Applicable = all valid rules; `applies_to` is still inert" |
| 10 | `loomwright/skills/rules/SKILL.md:225` | Quality-gate checkbox asserting the OPPOSITE of the new behaviour — must be rewritten, not deleted |
| 11 | `.agent/rules/README.md:25` | "RESERVED for a future slice (3b-ii) enforcement filtering — NOT consulted" |

**Deliberately NOT in the sweep set** (do not "fix" these): `loomwright/skills/rules/SKILL.md:44` and
`.agent/rules/process.json:12` are `"applies_to": null` **data/JSON examples** that stay valid under AC2;
`loomwright/scripts/add-rule.sh:376` is the writer default, owned by **AC5** not AC10; `CHANGELOG.md` is a
historical record and is never retro-edited.

## Acceptance Criteria

- [ ] **AC1 — match/non-match.** Given a rule with `applies_to: ["loomwright/scripts/**"]`, when `read-rules.sh`
      is called with a script path, then the rule IS emitted; when called with only an unrelated doc path, then
      the rule is **ABSENT from stdout** — non-match asserted by absence, not by a weaker signal.
- [ ] **AC2 — `null` is repo-wide.** Given `applies_to: null` (or the key absent), when the reader is called with
      any path set, then the rule is emitted — no regression for the one existing rule (`.agent/rules/process.json`).
- [ ] **AC3 — fail OPEN on ambiguity.** Given a malformed `applies_to` (non-array, array containing a non-string,
      empty array) **or an empty touched-path set**, when the reader runs, then the rule is **emitted anyway**, exit
      status is 0, and nothing is written to stdout on the fail-open path (diagnostics go to stderr + `memory.log`).
- [ ] **AC4 — the no-arg call must stay repo-wide (load-bearing, see R1).** Given `bash read-rules.sh` with **zero
      positional args** — the exact shape `session-resume.sh:311` uses — when routing is live, then **every** valid
      rule is emitted exactly as today. `rules_nudge`'s firing surface is CLAUDE.md-**pinned**; a nudge that starts
      firing on a repo that HAS rules is a regression, and it would fire the moment a no-arg call returned EMPTY.
- [ ] **AC5 — writer support.** `add-rule.sh --applies-to <glob>` is accepted, **repeatable** (N flags ⇒ N-element
      array), defaults to `null` when omitted, and **REJECTS traversal-style patterns** (`../`, absolute `/…`)
      with a non-zero exit, mirroring the existing hostile-category rejection at `add-rule.sh:242+`.
- [ ] **AC6 — reader invariants preserved.** `read-rules.sh` still: always exits 0; emits EMPTY (no banner, no
      sentinel) when no rule qualifies; passes untrusted text into `jq` only via file-path positional args /
      `--arg`/`--argjson`; and **never** runs, evals, sources, or `bash -c`s a `check`.
- [ ] **AC7 — supersession still composes.** A rule hidden by a live `supersedes` edge stays hidden regardless of
      routing, and a rule filtered out by routing does **not** thereby resurrect a rule it supersedes. Order of
      operations between the two filters is chosen deliberately and asserted by a test.
- [ ] **AC8 — pattern syntax documented.** The supported syntax is stated explicitly where a rule author will read
      it (`skills/rules/SKILL.md` §1 and `.agent/rules/README.md`), **including** the `case`-glob caveat that `*`
      does NOT stop at `/` — an explicit contrast with `.gitignore` semantics.
- [ ] **AC9 — the seams' invocation shapes traced dynamically, with the limit stated.** The three prose seams
      reduce to **exactly two distinct executable shapes**. Both MUST be executed against a fixture rules store
      with assertions on real stdout: **(i)** `bash read-rules.sh <paths…>` — the shape used by BOTH the worker
      DO-side (`agents/execute-manager.md:190`, `agents/supervisor.md:735`) and Phase 4.5
      (`skills/self-heal-advisory/SKILL.md:534`, call at `:226`); they differ only in the *path set* passed, not
      in the shape. **(ii)** `bash read-rules.sh` with no args — the SessionStart shape at
      `scripts/session-resume.sh:311` (this is AC4). **Explicit limit:** a dynamic trace CANNOT prove the two
      *prose* seams still hand the reader the right paths — they are agent/skill markdown, not executable code.
      That wiring stays covered by the existing **static** grep assertions in `scripts/test-rules-seams.sh:17-23`,
      which must remain green. Do not claim end-to-end proof the traces cannot deliver.
- [ ] **AC10 — stale prose swept.** No surface still claims `applies_to` is inert/reserved/not-consulted — **all
      11 enumerated sites** in the sweep table above, PLUS a repo-wide backstop grep for `applies_to` cross-checked
      against `inert`/`reserved`/`forward-compat`/`later slice`/`do NOT change` (the enumeration is a floor, not a
      ceiling — if the grep finds a 12th, fix it). `skills/rules/SKILL.md:225`'s Quality-Gates checkbox must be
      **rewritten** to assert the new behaviour, never merely deleted. The four excluded sites listed under the
      sweep table must be left alone.
- [ ] **AC11 — no count drift; version + docs current.** Agents/commands/skills/hooks stay **14 / 21 / 41 / 24**
      (no new file of any counted kind). `plugin.json` + `.claude-plugin/marketplace.json` version bumped in place
      (v15.29.0 → v15.30.0) with the description kept short, `CHANGELOG.md` gains the release narrative,
      CLAUDE.md's one-paragraph banner is replaced (not appended to), and `scripts/check-doc-currency.sh` passes.
- [ ] **AC12 — full suite green.** Every `loomwright/scripts/test-*.sh` passes, in particular `test-read-rules.sh`,
      `test-add-rule.sh`, `test-rules-seams.sh`, `test-session-resume.sh`, `test-rules-check.sh`, and
      `test-rules-docs.sh`.
- [ ] **AC13 — `rules-check.sh` stays repo-wide (DECIDED — do not re-litigate).** The checker does **NOT** follow
      routing. Grounds, verified in the file: `rules-check.sh:49` declares `Usage: rules-check.sh [--confirm]
      [--no-cmd]` and its arg loop at `:70-83` **warns-and-ignores any unrecognized argument** — it accepts **no
      path scope at all**, so routing has no input to act on there. Adding one would be new surface the source
      requirement's Non-goals explicitly forecloses. The parity that `rules-check.sh:16,131,159` promises is over
      **per-object validation + `LC_ALL=C` first-seen-id dedup** — *which objects are well-formed* — and routing
      does not touch that; routing is an **emission filter for advisory injection**, a strictly separate axis.
      `/rules check` therefore remains a **repo-wide audit** ("are all our conventions upheld?"), which is the
      behaviour a user expects from it. **Required of the worker:** state this distinction in one short paragraph
      in `rules-check.sh`'s header near the parity comment at `:16`, note it in the CHANGELOG entry, and add/keep
      a `test-rules-check.sh` assertion that a routed-out rule is STILL selected by the checker. Do not add path
      arguments to `rules-check.sh`.

## Outcomes Rubric
- Routing implemented; non-match suppression proven, not just match emission
- Fail-open on malformed/empty, exit 0 preserved
- All three seams traced dynamically end-to-end
- Writer support with traversal rejection
- Stale INERT prose swept repo-wide

> **Grading note for bullet 3 (added post-PASS; the five bullets above are byte-identical to
> `.supervisor/requirements/twin-loop/03-applies-to-routing.md:86-91` and MUST NOT be edited).**
> "All three seams traced dynamically end-to-end" is satisfied by tracing the **two distinct executable
> invocation shapes** the three seams reduce to — `bash read-rules.sh <paths…>` (worker DO-side AND Phase 4.5;
> they differ only in the path set) and `bash read-rules.sh` with no args (SessionStart) — per **AC9**. The two
> prose seams are agent/skill markdown and cannot themselves be executed; their wiring is held statically.
> Score bullet 3 against AC9, not against a literal reading that AC9 documents as impossible.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `applies_to` path routing: reader filter, writer flag, dynamic seam traces, doc sweep | AC1–AC13 | 17 modify, 0 create | `skills/rules/SKILL.md`, `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |

> **Why 17 files is still ONE subtask (Decomposition Threshold, explicit).** `supervisor-readiness/SKILL.md:393`
> puts the `context-bound` split trigger at **> 12 changed files**, and this brief crosses it on raw count — so
> the default is justified here rather than assumed. Of the 17 paths, **6 are release-lockstep boilerplate**
> (`plugin.json`, `marketplace.json`, `CLAUDE.md` banner, `CHANGELOG.md`, and the two doc-currency-adjacent test
> files) — one-line-each edits the repo already performs on every version bump, carrying no independent
> reasoning. The genuine reasoning surface is **5 scripts + 4 doc surfaces around a single filter**. Splitting
> would be actively worse: any partition puts `read-rules.sh`, `test-read-rules.sh`, and `skills/rules/SKILL.md`
> on **both** sides of the cut (the filter, its tests, and its contract are one artefact), which is the
> `file-conflict` condition the threshold exists to *avoid*, and would serialize into a dependency chain with no
> parallelism won. **Decision: single subtask, Single-Agent Path, no `Split reason`.**

```yaml
# Subtask 1 — the whole feature (Single-Agent Path; below the Decomposition Threshold)
provides:
  # The filter itself. `rule_applies` is named deliberately: it is the shell function that performs the
  # `case`-glob match, so it CANNOT exist without the routing being implemented. (A comment-banner symbol
  # would be a vacuous gate — writing the banner alone would pass.)
  - {kind: "file",   path: "loomwright/scripts/read-rules.sh"}
  - {kind: "symbol", path: "loomwright/scripts/read-rules.sh", name: "rule_applies"}
  # Writer flag. Name has NO leading `--`: agents/worker.md:157 runs the gate as
  # `grep -nE '<name>' <path>`, and a leading `--` is eaten by getopt as an unknown long option on both
  # GNU and BSD grep, erroring the check into a spurious `missing`. `applies-to` matches the `--applies-to)`
  # case label.
  - {kind: "file",   path: "loomwright/scripts/add-rule.sh"}
  - {kind: "symbol", path: "loomwright/scripts/add-rule.sh", name: "applies-to"}
  - {kind: "file",   path: "loomwright/scripts/test-read-rules.sh"}
  - {kind: "file",   path: "loomwright/scripts/test-add-rule.sh"}
  - {kind: "file",   path: "loomwright/scripts/test-rules-seams.sh"}
  - {kind: "file",   path: "loomwright/scripts/test-rules-check.sh"}
  - {kind: "file",   path: "loomwright/scripts/rules-check.sh"}
  - {kind: "file",   path: "loomwright/skills/rules/SKILL.md"}
  - {kind: "file",   path: "loomwright/skills/self-heal-advisory/SKILL.md"}   # AC10 sites 4 + 5
  - {kind: "file",   path: "loomwright/commands/rules.md"}                    # AC10 site 3 + --applies-to param row
  - {kind: "file",   path: ".agent/rules/README.md"}                          # AC10 site 11 + AC8 syntax doc
  # Release lockstep — these carry AC11 and were previously verified by nothing.
  - {kind: "file",   path: "loomwright/.claude-plugin/plugin.json"}
  - {kind: "symbol", path: "loomwright/.claude-plugin/plugin.json", name: "15.30.0"}
  - {kind: "file",   path: ".claude-plugin/marketplace.json"}
  - {kind: "file",   path: "CLAUDE.md"}
  - {kind: "file",   path: "CHANGELOG.md"}
requires: []
lanes:
  - "loomwright/scripts/read-rules.sh"
  - "loomwright/scripts/add-rule.sh"
  - "loomwright/scripts/rules-check.sh"
  - "loomwright/scripts/test-read-rules.sh"
  - "loomwright/scripts/test-add-rule.sh"
  - "loomwright/scripts/test-rules-seams.sh"
  - "loomwright/scripts/test-rules-check.sh"
  - "loomwright/scripts/test-rules-docs.sh"
  - "loomwright/scripts/test-session-resume.sh"
  - "loomwright/skills/rules/SKILL.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/commands/rules.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - ".agent/rules/README.md"
  - "CHANGELOG.md"
  - "CLAUDE.md"
external_requires:
  - "jq (already a hard dependency of read-rules.sh)"
  - "bash 3.2 / BSD userland (macOS dev host) — CI runs GNU/Linux"
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1  (no dependencies)
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | — | n/a (single subtask) | n/a |

### Batch Plan
- Batch 1: Subtask 1
- **Estimated batches:** 1 | **Recommended workers:** 1 (Single-Agent Path — no worktree)

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/rules/SKILL.md` (schema + reader contract authority), `skills/quality-checklist/SKILL.md`, `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **R1 — the SessionStart seam passes NO paths.** `session-resume.sh:311` calls `bash "$reader"` with zero args and nudges when stdout is EMPTY. If "no touched paths" were treated as "nothing matches", every repo that HAS rules would start getting the "no house rules found" nudge — a silent, user-visible regression in a firing surface CLAUDE.md calls **pinned**. (Source: Feasibility Phase 2.5; corrects the requirement's own evidence.) | **HIGH** | AC3 + AC4 make empty-path-set fail **OPEN** and require an explicit no-arg regression test; `test-session-resume.sh` must stay green unchanged. |
| **R2 — `case` globs do not treat `/` specially.** `"loomwright/scripts/*"` will match `loomwright/scripts/a/b/c.sh`, unlike `.gitignore`. A rule author will assume otherwise. (Requirement flags this; Feasibility confirms it.) | MEDIUM | AC8 — document the exact semantics of `*` and `**` at a path boundary, with an explicit `.gitignore` contrast, in both author-facing surfaces. Do not emulate gitignore semantics; do not implement matching in `jq`. |
| **R3 — a vacuous test.** A test asserting only "rule is emitted" passes identically against today's no-op reader. | **HIGH** | AC1 requires the non-match case to assert **absence**; add a mutation control — with the filter deleted, the non-match test MUST fail. |
| **R4 — routing × supersession interaction is unspecified.** Both filters remove rules from the output; order matters and neither the requirement nor the current code says which runs first. | MEDIUM | AC7 — pick an order deliberately, state the rationale in the reader's header docstring, and pin it with a test. |
| **R5 — `rules-check.sh` divergence. RESOLVED at plan time; the worker implements, it does not decide.** The checker mirrors the reader's validation + dedup (`rules-check.sh:16,131,159`). Verified: it accepts NO path scope (`:49` usage, `:70-83` warns-and-ignores unknown args), so routing has no input there, and the promised parity is over *object validity*, not *applicability*. | MEDIUM (was: open decision) | **AC13** — checker stays repo-wide; document the emission-filter-vs-audit distinction in `rules-check.sh`'s header near `:16` + the CHANGELOG, and assert a routed-out rule is still selected. **Do not add path args to `rules-check.sh`.** |
| **R6 — doc-currency is necessary but not sufficient.** A green `check-doc-currency.sh` does not catch prose that still says `applies_to` is inert. | MEDIUM | AC10's 9-site table + a grep for bare `inert`/`reserved` near `applies_to`; CLAUDE.md banner **replaced**, plugin description **not** appended to. |
| **R7 — macOS-green ≠ CI-green.** bash 3.2 + BSD userland here; GNU on CI. Historic bites: `stat -f %m`, `${var//…}` O(n²), `grep -q` + `pipefail` SIGPIPE. | MEDIUM | Keep matching to native `case` (portable by construction, no `shopt`); avoid `stat`/`sed -i`/`date` flavour-dependent calls in new code and tests. |
| **R8 — uncommitted ledger line rides along.** `.supervisor/postmortem/results.jsonl` (+1 line, PR #134's engine-native learning record) is in the tree by owner decision. | LOW | Commit it in this branch with an explicit note in the commit body; it is data, not behaviour, and must not be reverted or re-generated. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-08-09-applies-to-path-routing.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/138 (branch `feature/applies-to-path-routing`, base `main`)
- **Commits:** cfb866b (implementation) + 6751db1 (Phase 4.5 heal iteration 1)
- **heal_loop_ran:** true | **heal_decision:** PASS | **heal_iterations:** 1 | **heal_remaining_issues:** 2 (both LOW, advisory)
- **rubric_score:** 5/5
- **Until-mergeable dispatched:** false — resolved from the ON-DISK MARKER, not from control flow: no `.supervisor/review-dispatch/` marker matches this PR URL and no `review-pr-runner` is live. This is truthful-false by DESIGN, not a missed step: `/automate` deliberately suppressed `auto_review` around the RUN phase so the engine could own exactly ONE inline drain (automate-loop §7).
- **Deterministic gate:** re-run by the Supervisor rather than trusted from `WORKER_RESULT` — 55/55 `loomwright/scripts/test-*.sh` suites + 7/7 root gates, both before and after the heal.

### Deviations from this brief, and why
1. **AC11's version target was stale on arrival.** The brief targeted `v15.29.0 → v15.30.0`; PR #137 shipped v15.30.0 while this brief sat in `pending/`. Phase 1.5 caught it and the worker bumped **v15.30.0 → v15.31.0** instead. Counts unchanged at 14/21/41/24.
2. **R8 was moot.** The uncommitted `.supervisor/postmortem/results.jsonl` line the brief planned to carry had already been swept into PR #136 by a concurrent session and was on `main`. The worker was told not to re-add it.
3. **Launch Pad was not re-run.** This brief was authored and Plan-Review-PASSED on the prior tick, which halted at Phase 1.5 on a concurrent writer before any implementation. On owner decision, the RUN step reused this brief via inline `/supervisor` rather than re-running `/autonomous --single-iteration`, which would have re-authored it from scratch and discarded two review rounds plus two source-corrections.

### Two findings the Supervisor raised into review rather than accepting
- **`read-rules.sh ""`** (ONE empty-string arg, not zero) suppressed scoped rules — found by an independent probe during the deterministic gate, not by the suite. Adjudicated MEDIUM (no executable seam produces the shape, but it falsified a promise stated at `skills/self-heal-advisory/SKILL.md:226`). **Fixed** in 6751db1, pinned by `test-read-rules.sh` (j7).
- **`session-resume.sh` (+8, comment-only) was out-of-lane** while `WORKER_RESULT` reported `out_of_lane: []`. Content correct and kept; the mislabel is recorded as a LOW signal-integrity issue. The brief's own `lanes:` is arguably at fault — it lists `test-session-resume.sh` but not `session-resume.sh`.

### The reviewer's own catch (not raised by the Supervisor)
**`--applies-to` newline rejection could not fire.** Newline is the accumulator's OWN delimiter (`add-rule.sh:136-137`), so an embedded newline was consumed before the validation loop at `:344-357` ever saw it — `--applies-to $'src/*\ndocs/*'` silently wrote TWO patterns while three doc surfaces claimed it was rejected. Fail-open in direction, each segment still independently validated, so MEDIUM. **Fixed** in 6751db1 by rejecting at parse time, pinned by `test-add-rule.sh` (M3c). This is the repo's recurring "rule contradicted by its own surrounding text" class.

### Carried forward (2 LOW, deliberately not fixed here)
- `read-rules.sh:448` — `log_note` writes one line per routed-out rule per call to `.supervisor/logs/memory.log`, which nothing trims. Invisible at one rule; item 05 harvests ~104, at three seams per task. Growth is pre-existing; this change multiplies the rate.
- The out-of-lane lane-list gap above.
