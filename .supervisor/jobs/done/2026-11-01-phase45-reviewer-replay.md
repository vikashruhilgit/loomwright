# Supervisor Job: Phase 4.5 reviewer replays its own past misses before a reviewer change ships

## Environment
- **Project:** ai-agent-manager-lanes/automate-2026-11-01-195532/L2 (lane clone of `vikashruhilgit/loomwright`)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/2026-11-01-092115-phase-4-5-reviewer-replays-its-own-past-misses.md
- **Base commit:** 26eda742b616a339f971b34b5b7d8740c9654851

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + BSD userland + jq + git, same as `loomwright/evals/coordinator-model/` |
| 2 | Dependency Availability | CAUTION | `claude plugin eval` is installed (`claude plugin eval --help` exits 0). Unverified: that the eval child's Agent tool can spawn the plugin agent `loomwright:loomwright:code-reviewer` (coordinator-model disallows Agent, so no prior evidence) |
| 3 | Architecture Fit | GO | Reuses the coordinator-model pattern: per-case `scaffold.sh` + shared `lib/` stager, deterministic `regex` graders over `.eval/verdict.txt`, model-free `lib/selftest.sh` run as a CI leg |
| 4 | Scope vs Supervisor Capability | CAUTION | About 18 files. Split into 2 dependency-ordered subtasks (`context-bound`) |
| 5 | Hard Blockers | CAUTION | Owner decision at Launch Pad (2026-11-01): corpus cases are confirmed by the owner in a follow-up session. This run ships the machinery, the two controls and a PENDING baseline section, and the PR stays open until the owner confirms ≥5 misses and records the model-backed baseline |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add an on-demand `claude plugin eval` suite, `loomwright/evals/phase45-reviewer/`, that replays recorded Phase 4.5 reviewer misses against the current `loomwright:code-reviewer`, plus a human-gated corpus builder. A PR that changes the reviewer must report its before/after caught count.

**Problem Statement:**
A plugin owner who edits the code-reviewer prompt, the Phase 4.5 protocol (`loomwright/skills/self-heal-advisory/`) or its model routing needs a repeatable way to measure catch rate, because those surfaces change often (PR #634, `cb9e69c`, `4aefe4d`, `8d602e8`) and none of those changes was checked for catch rate.
Currently, misses are recorded (`.supervisor/postmortem/results.jsonl`, `self_heal_misses`, CI-lens rounds) but never replayed. This causes a prompt diet, split or model change to lower catch rate silently.
Success looks like this: one documented command prints `caught / total`, the per-case results and the controls' noise count, and `AGENT_GUIDELINES.md` and the PR template require that count for reviewer-touching PRs.

**Owner decisions recorded at Launch Pad (2026-11-01, LP-CLARIFY):**
- Corpus minimum: **≥5 owner-confirmed miss cases + ≥2 clean controls.**
- Confirmation route: **park for the owner.** This run ships the builder, the suite, the selftest, the CI wiring, the docs and the two controls. It runs the builder in dry-run mode only and records the candidates it prints in the evidence file. It never passes `--confirm` for a miss case. The miss cases and the model-backed baseline are added in a follow-up owner session on the same PR, which stays open until then.

**Design (binding for the worker, so that every case runs the same protocol):**
- **Case layout:** `loomwright/evals/phase45-reviewer/<NN>-<kind>-pr<N>/` holds `case.yaml`, `scaffold.sh` and `case.env`. `case.env` holds ONLY the staging inputs: `PR=`, `BASE_SHA=` and `HEAD_SHA=` (the pre-drain head). The expectations live OUTSIDE the plugin root, in the repo-root corpus table `docs/evidence/phase45-reviewer-corpus.tsv`. It has one row per case: `case_id<TAB>pr<TAB>kind<TAB>expected_file<TAB>severity_floor`, where kind is `miss` or `control`, severity_floor is BLOCKING, HIGH, MEDIUM or LOW, and a control has empty `expected_file`/`severity_floor`. A control has the tag `control`. A miss case has the tag `miss`. The `case.yaml` files differ only in `name`, `description` and `tags`, and every one is byte-identical from `execution:` on: one shared template, `case-template.yaml`, with one prompt and one grader for both kinds. The selftest checks this, the same way coordinator-model's S4 does.
- **No expectation inside the sandbox (prevents leaking the answer to the reviewer):** the reviewer runs in the sandbox cwd and can read anything there, including `.eval/`. So the sandbox gets only what staging needs, `.eval/case-id`, `.eval/base_sha` and `.eval/head_sha`, and NEVER an expected file or floor. The expectations are also not inside the plugin under test (`claude plugin eval ./loomwright`), whose files the rendered prompt sends the reviewer to read. They are in the repo-root `docs/evidence/phase45-reviewer-corpus.tsv`. Grading happens after the run, outside the sandbox. `lib/summarize.sh` reads each kept sandbox's `.eval/reviewer-reply.md` and `.eval/case-id`, and grades it with `lib/grade.sh` against that table's row. Honest limit, stated in README and evidence: the reviewer could still reach the source checkout by absolute path, and the plugin root holds the post-fix versions of replayed loomwright files. The follow-up Baseline steps include checking each kept trace for a read of `phase45-reviewer-corpus.tsv` or `evals/phase45-reviewer/`; a run that read either is reported, not counted. The eval's own `regex` grader only checks that a reply was captured: `^CODE_REVIEW_RESULT:` over `.eval/reviewer-reply.md`, the same for every case. The eval's pass/fail therefore means "reviewer replied", never "caught". README and evidence say so. `.eval/` is also added to the scratch repo's `.git/info/exclude`.
- **Staging (`lib/stage-case.sh`, called by each `scaffold.sh` in the sandbox cwd):** it finds the source repo from `BASH_SOURCE`, as `coordinator-model/lib/stage-golden.sh` does. If `git -C "$REPO" cat-file -e "<sha>^{commit}"` fails for BASE_SHA or HEAD_SHA, it writes `.eval/unstageable` and exits 0, and grading then reports `UNSTAGEABLE`. Otherwise it builds a scratch repo: the `git archive` of BASE_SHA as the root commit, `refs/remotes/origin/main` set to that commit, and the branch `replay` with `git diff --binary BASE_SHA HEAD_SHA` applied and committed. The reviewer's `git diff "origin/$BASE_BRANCH...HEAD"` therefore sees exactly the pre-drain diff. Nothing is written into the source repo.
- **Prompt (`lib/render-prompt.sh`):** renders the Phase 4.5 round-1 spawn prompt from the plugin under test, `<plugin>/skills/self-heal-advisory/SKILL.md`. It reads the `prompt: "…"` argument of the `Task(` whose `subagent_type: "loomwright:code-reviewer",` line it finds. It unescapes `\"` and drops every conditional paragraph whose text says `include this line ONLY when`. All of their inputs are empty in a replay, so the pin-mutation, house-rules, brief-conformance, deviations, prior-churn and module-shape blocks are omitted, as the requirement's round-1 assumption requires. It substitutes `{BASE_BRANCH}`→`main`, `{STACKED}`→`false` and `{feature_branch}`→`replay`. It is never copied into a case. When the anchor is missing, or any `{…}` placeholder remains, it exits non-zero and names the anchor.
- **Run (the `case.yaml` prompt):** if `.eval/unstageable` exists, the eval child replies `UNSTAGEABLE` and stops. Otherwise it spawns ONE `Agent` with `subagent_type: "loomwright:loomwright:code-reviewer"` (the double prefix: project memory a178a7b5 says the single-prefix form errors) and the prompt from `.eval/review-prompt.md`. It writes the agent's reply verbatim to `.eval/reviewer-reply.md` and stops. It does not grade. The case uses round 1 only and never runs a fix task.
- **Grader (`lib/grade.sh <reply file> <case_id> <corpus tsv>`, deterministic, no LLM, run outside the sandbox):** an absent reply file for a staged case prints `RESULT: MISSED (no reply)`. Otherwise: it reads the LAST `CODE_REVIEW_RESULT:` block in the reply and its `issues:` entries (`severity:` and `file:`), and it prints ONE result line plus, for a control, a `NOISE:` line:
  - Miss case (`EXPECTED_FILE` set): `RESULT: CAUGHT` when some issue has severity at or above `SEVERITY_FLOOR` (order BLOCKING > HIGH > MEDIUM > LOW) and `file` equal to `EXPECTED_FILE`. Otherwise `RESULT: MISSED`. With no parseable block: `RESULT: MISSED (unparseable)`.
  - Control (`EXPECTED_FILE` empty): `RESULT: CLEAN` or `RESULT: NOISE`, plus `NOISE: <count of BLOCKING/HIGH issues>`. A control never fails anything on noise alone.
  - `CAUGHT` is reachable only with `EXPECTED_FILE` set. `CLEAN`/`NOISE` are reachable only with it empty.
- **Command (`lib/run.sh`, the one documented command):** it first checks that `claude plugin eval --help` exits 0. If not, it prints `phase45-reviewer: missing tool: claude plugin eval` on stderr, exits non-zero and prints no caught count. Otherwise it runs `claude plugin eval ./loomwright --eval-dir evals/phase45-reviewer --scaffold --allow-tools Bash --ablation none --no-publish --trust-plugin --keep-temp …` into a `mktemp -d` dir, then `lib/summarize.sh`. Subtask 1 checks `claude plugin eval --help` for the multi-value `--tag` syntax and records it in the README. The suite holds only `miss` and `control` cases, so no tag filter is needed by default.
- **Report (`lib/summarize.sh <eval --json> <suite dir>`):** it maps each kept sandbox to its case via `.eval/case-id` and grades it with `lib/grade.sh`. It prints one row per case (`CAUGHT` / `MISSED` / `MISSED (unparseable)` / `MISSED (no reply)` / `UNSTAGEABLE` / `CLEAN` / `NOISE`), then `caught: X/Y`, `unstageable: <n>`, `no_reply: <n>` and `noise: <sum> BLOCKING/HIGH on <m> controls`, plus model, wall clock, turns and cost.
  - **Denominator rule:** Y counts every miss case except UNSTAGEABLE ones. A staged miss case whose reviewer crashed, timed out or never replied stays in Y as `MISSED (no reply)`, so a failed spawn shows as `caught: 0/<n>` with `no_reply: <n>` and never as `0/0`.
  - A case whose kept sandbox is missing (no `--keep-temp` dir) prints `?` in its row and is counted in Y as not caught, never as a guessed number. Like coordinator-model's `summarize.sh`, it opens the sealed kept dir with `chmod u+rwx`.
- **Grader injection seam (for the AC7 mutant leg):** `lib/selftest.sh` and `lib/summarize.sh` call the grader through `PHASE45_GRADE` (default: the suite's own `lib/grade.sh`). The selftest prints its mutation-control assertion's failure as a line starting `FAIL: mutation-control`.
- **Corpus builder (`loomwright/scripts/build-reviewer-replay-case.sh`):** it uses local git, and the ledger is used only for annotation.
  - `--list [--since <date>]` prints candidate miss PRs. A candidate is a first-parent merge of `main` whose second-parent chain has a pre-drain head and a later commit (not `chore(release)…`) that changes a file the pre-drain diff `merge-base..pre-drain` also changes. The pre-drain head is the last `fix: address review feedback (iteration N)` commit, which is Phase 4.5's own fix-commit subject (`skills/self-heal-advisory/SKILL.md`). It also prints clean controls: merged, no commit after the pre-drain head other than release, no revert of the PR on main.
  - `--pr <N> [--floor HIGH] [--control]` prints `base: <sha>`, `pre_drain_head: <sha>` and `expected: {file: <path>, severity_floor: <floor>}` (for a control, `expected: none (control)`), then `dry run — nothing written; re-run with --confirm`, and writes nothing.
  - `--pr <N> … --confirm` writes exactly one case dir (`case.env` + `case.yaml` copied from the suite's shared template + a `scaffold.sh` that calls `lib/stage-case.sh`) and appends exactly one row to `docs/evidence/phase45-reviewer-corpus.tsv`, creating it with a header line if absent.
  - It refuses (non-zero, nothing written) when the PR's merge or either sha is unreachable, and when the case dir already exists. It only considers merges of this repo's own `main` (requirement: cases come only from this public repo's merged PRs).

## Acceptance Criteria

**Happy path**
- [ ] AC1: Given the committed corpus (at merge time of this run: the two controls), when `bash loomwright/evals/phase45-reviewer/lib/run.sh` runs on the current reviewer, then it prints `caught: X/Y`, one result row per case and the controls' `noise:` count.
- [ ] AC2: Given a candidate PR from the ledger or `--list`, when `bash loomwright/scripts/build-reviewer-replay-case.sh --pr <N>` runs without `--confirm`, then it prints the case's base sha, pre-drain head sha and expected `{file, severity floor}`, and the working tree is byte-identical afterwards. With `--confirm` it writes exactly one case dir and one corpus-table row.
- [ ] AC3: Given a PR that edits the code-reviewer prompt, when it is opened, then `AGENT_GUIDELINES.md` names the replay command as required evidence for a PR that edits `loomwright/agents/code-reviewer.md`, `loomwright/skills/self-heal-advisory/` or Phase 4.5 routing (`loomwright/scripts/resolve-routing.sh`, `loomwright/docs/PROVIDER_ROUTING.md`), and `.github/pull_request_template.md` has a line for the before/after caught count.

**Edge cases**
- [ ] AC4: Given a case whose base or head sha is not reachable, when the suite runs, then that case reports `UNSTAGEABLE` and is removed from the denominator, never counted as caught. This is proven model-free in `lib/selftest.sh` by staging a `case.env` with a nonexistent sha.
- [ ] AC5: Given a reviewer reply with no parseable `CODE_REVIEW_RESULT` block, when it is graded, then the case is `MISSED (unparseable)`, never caught.

**Error scenarios**
- [ ] AC6: Given `claude plugin eval` is unavailable (a PATH-stubbed `claude` that exits non-zero), when `lib/run.sh` runs, then it exits non-zero, names the missing tool on stderr and prints no `caught:` line.
- [ ] AC7: Given the graders are edited to always match (a scratch mutant of `lib/grade.sh` that always prints `RESULT: CAUGHT`, passed as `PHASE45_GRADE=<mutant>`), when CI runs, then the selftest's mutation-control case fails. The CI leg in `test-build-reviewer-replay-case.sh` asserts three things in the same leg: the unmutated selftest exits 0; the mutant is non-empty, differs from the original and passes `bash -n`; and the mutated selftest exits non-zero with a `FAIL: mutation-control` line.

**Selftest and evidence**
- [ ] AC8: `bash loomwright/evals/phase45-reviewer/lib/selftest.sh` exits 0 with no model and no network. It feeds canned reviewer replies to `lib/grade.sh` and asserts all of the following, and it is run as a leg of `loomwright/scripts/test-build-reviewer-replay-case.sh`, which CI globs:
  - hit ⇒ `CAUGHT`
  - miss ⇒ `MISSED`
  - wrong-file finding ⇒ `MISSED`
  - below-floor finding ⇒ `MISSED`
  - unparseable ⇒ `MISSED (unparseable)`
  - a control with one HIGH ⇒ `NOISE` and `NOISE: 1`
  - a mutation-control expectation (deliberately wrong `EXPECTED_FILE` against a hit reply) ⇒ not `CAUGHT`
  - `lib/render-prompt.sh` against the live `skills/self-heal-advisory/SKILL.md` yields a prompt containing `EXECUTION DIRECTIVE` and `CODE_REVIEW_RESULT v3`, no `{` placeholder and no `PIN-MUTATION VERDICTS`
  - every `case.yaml` (template included) is byte-identical from `execution:` on
  - a staged miss case with no reply file ⇒ `MISSED (no reply)`
  - `lib/summarize.sh` over a fixture corpus table plus fixture kept-sandbox dirs prints `caught: 1/4`, `unstageable: 1`, `no_reply: 1`, `noise: 1 BLOCKING/HIGH on 1 controls`, and a `?` row for the case with no sandbox. The fixtures, all miss cases unless named:
    - one CAUGHT reply
    - one MISSED reply
    - one `.eval/unstageable`
    - one staged case with no reply
    - one case with no kept sandbox at all
    - one control reply with one HIGH
  - no sandbox staged by `lib/stage-case.sh` contains the corpus table, its expected path or floor, and no file under `loomwright/` (the plugin root) contains an expected-file value from the fixture table
  - the missing-tool assertion runs `lib/run.sh` with a PATH stub that shadows `claude`, and asserts the stub was the binary invoked (the stub writes a marker)
- [ ] AC9: Given this run, then a committed evidence file `docs/evidence/phase45-reviewer-replay.md` contains: the exact run command; the corpus minimum the owner set (≥5 misses + ≥2 controls); the `--list` candidate table the builder printed at the base commit; the two committed controls and why they qualify; a `## Baseline` section marked `PENDING — owner confirmation` that lists the follow-up steps (confirm ≥5 cases with `--confirm`, run `lib/run.sh` on the merge commit, record caught/total, noise, model, wall clock and cost from the eval JSON); and the honest limits: run-to-run variance; the corpus comes from this repo only; the eval's own pass/fail means "reply captured", not "caught"; the expectation never enters the sandbox or the plugin root, but the reviewer could still reach the source checkout (the corpus table, the post-fix versions of replayed files) by absolute path, which is why the Baseline steps include a per-trace read check for `phase45-reviewer-corpus.tsv` / `evals/phase45-reviewer/`. The PR body links to it.
- [ ] AC10: Given the Phase 4.5 reviewer is never run in GitHub CI, then no `.github/workflows/*` file invokes `claude plugin eval` or `lib/run.sh`. No `test-*.sh` invokes them either, except `lib/run.sh` under a PATH stub that shadows `claude` (the AC6 assertion, which proves its stub was the binary invoked).

## House Rules
> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| eval suite (Subtask 1) | — | `loomwright/evals/phase45-reviewer/README.md`, `loomwright/evals/phase45-reviewer/.gitignore` (`results/`, as coordinator-model's), `loomwright/evals/phase45-reviewer/case-template.yaml`, `loomwright/evals/phase45-reviewer/lib/stage-case.sh`, `loomwright/evals/phase45-reviewer/lib/render-prompt.sh`, `loomwright/evals/phase45-reviewer/lib/grade.sh`, `loomwright/evals/phase45-reviewer/lib/summarize.sh`, `loomwright/evals/phase45-reviewer/lib/run.sh`, `loomwright/evals/phase45-reviewer/lib/selftest.sh`, `loomwright/evals/phase45-reviewer/lib/fixtures/` (canned replies) | HIGH |
| builder + wiring + docs (Subtask 2) | `AGENT_GUIDELINES.md` (831), `.github/pull_request_template.md` (19) | `loomwright/scripts/build-reviewer-replay-case.sh`, `loomwright/scripts/test-build-reviewer-replay-case.sh`, two control case dirs `loomwright/evals/phase45-reviewer/<NN>-control-pr<N>/{case.yaml,scaffold.sh,case.env}` (written by the builder with `--control --confirm`), `docs/evidence/phase45-reviewer-replay.md`, `docs/evidence/phase45-reviewer-corpus.tsv` (the expectation table, header + the two control rows, written by the builder), `changelog.d/phase45-reviewer-replay.md` | HIGH (controls' PR numbers MEDIUM — picked from `--list` output) |

**Module layout (`skills/supervisor-readiness/SKILL.md` §"Module layout"):**
- One home per responsibility, each a CREATE under `lib/`: staging → `stage-case.sh`; prompt rendering → `render-prompt.sh`; grading → `grade.sh`; reporting → `summarize.sh`; the command → `run.sh`; the model-free proof → `selftest.sh`. Corpus selection is a separate concern, so it gets `loomwright/scripts/build-reviewer-replay-case.sh` and its test.
- Reuse, do not extract: the sandbox-run, kept-temp and verdict-reading idioms follow `loomwright/evals/coordinator-model/lib/` (`stage-golden.sh`, `summarize.sh`, `selftest.sh`) by pattern. Those helpers are case-format-specific, so nothing is shared code and no extract row is needed.
- `AGENT_GUIDELINES.md` (831, at or past the threshold) gets one short subsection appended. Reason: it is the single home for contributor PR-evidence rules that the requirement names, and the change adds no code responsibility.
- `.github/pull_request_template.md` (19) gets one line.
- Tests count like source. The new test is a CREATE, and `test-automate-next-step.sh` (the coordinator-model leg's home) is NOT touched.

> **Validator-owned surfaces:** `AGENT_GUIDELINES.md` is in `scripts/check-doc-currency.sh`'s `FILES=(` list and in `loomwright/scripts/test-citation-drift.sh`'s scan globs. Files scanned by those validators may need updates. Add no count or version literal, and no bare unpinned `file:N` citation. `test-citation-drift.sh` also scans `scripts/*.sh`-shaped paths, so the new `loomwright/scripts/build-reviewer-replay-case.sh` and its test follow the same no-bare-citation rule in their comments.

## Touched-file invariants

> Grounded at base `26eda742b616a339f971b34b5b7d8740c9654851`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`AGENT_GUIDELINES.md`**
  - keep: no new count/version literal, because the file is scanned by `scripts/check-doc-currency.sh` (its `FILES=(` block lists `  AGENT_GUIDELINES.md`) and the house rule above applies. No bare `path:N` citation (`loomwright/scripts/test-citation-drift.sh` globs `'AGENT_GUIDELINES.md'`).
  - mirror: the new requirement cites `## Review Counter-Pressure Rule` by path and never restates its lens table ("Every surviving pass elsewhere in this repo cites this section by path — it is not restated"). The replay is evidence about a lens, not a new pass.
- **`.github/pull_request_template.md`**
  - keep: the existing `## Test Plan` checklist lines (`- [ ] Tested locally with \`claude\` CLI`). Add one checklist line under `## Test Plan` and do not restructure the template.
- **`loomwright/skills/self-heal-advisory/SKILL.md`** (READ, not modified)
  - mirror: `lib/render-prompt.sh` reads it by anchor, `subagent_type: "loomwright:code-reviewer",`, then `prompt: "` up to the `",` before `model: "sonnet"`. The conditional paragraphs carry `include this line ONLY when`. The selftest pins the rendering against the live file, so a later edit to that prompt that breaks the anchor turns CI red instead of silently replaying a different prompt.
- **`loomwright/evals/coordinator-model/`** (READ, pattern source)
  - mirror: `stage-golden.sh`'s repo-root-from-`BASH_SOURCE` + `.eval/` layout.
  - mirror: the CI-leg shape in `loomwright/scripts/test-automate-next-step.sh` leg E: `if [ -f "$ESELF" ]; then … else no "E: $ESELF missing"; fi`. The new leg also fails closed when `selftest.sh` is missing.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/evals/phase45-reviewer/lib/selftest.sh` — hit ⇒ CAUGHT / wrong-file ⇒ MISSED | in `lib/grade.sh`, make the file comparison always true (drop the `EXPECTED_FILE` equality test). The wrong-file and mutation-control assertions must go red |
| `lib/selftest.sh` — below-floor ⇒ MISSED | in `lib/grade.sh`, treat every severity as meeting the floor. The below-floor assertion must go red |
| `lib/selftest.sh` — unparseable ⇒ MISSED (unparseable) | in `lib/grade.sh`, default an absent block to `RESULT: CAUGHT`. The unparseable assertion must go red |
| `lib/selftest.sh` — plain miss ⇒ MISSED | in `lib/grade.sh`, print `RESULT: CAUGHT` for any parseable block with ≥1 issue. The plain-miss assertion must go red |
| `lib/selftest.sh` — control with one HIGH ⇒ NOISE, `NOISE: 1` | in `lib/grade.sh`, count only BLOCKING as noise. The `NOISE: 1` assertion must go red |
| `lib/selftest.sh` — rendered prompt has no `{` placeholder and no `PIN-MUTATION VERDICTS` | in `lib/render-prompt.sh`, skip the drop of `include this line ONLY when` paragraphs. The assertion must go red |
| `lib/selftest.sh` — every case.yaml byte-identical from `execution:` | give one committed control's `case.yaml` a different grader pattern. The same-protocol assertion must go red |
| `lib/selftest.sh` — UNSTAGEABLE stages | in `lib/stage-case.sh`, delete the `cat-file -e` reachability check. The unstageable assertion must go red |
| `lib/selftest.sh` — summarize `caught: 1/2`, `unstageable: 1` | in `lib/summarize.sh`, count UNSTAGEABLE cases in the denominator. The `caught: 1/2` assertion must go red |
| `lib/selftest.sh` — no expectation in the sandbox | in `lib/stage-case.sh`, copy the corpus table into `.eval/`. The no-expectation assertion must go red |
| `lib/selftest.sh` — summarize `no_reply: 1` / `caught: 1/4` | in `lib/summarize.sh`, drop no-reply cases from the denominator. The `caught: 1/4` assertion must go red |
| `lib/selftest.sh` — missing tool via PATH stub | in `lib/run.sh`, call `claude` by an absolute path instead of via `PATH`. The stub-was-invoked assertion must go red |
| `lib/selftest.sh` — missing tool | in `lib/run.sh`, delete the `claude plugin eval --help` availability check. The PATH-stubbed run must then not print the missing-tool line, and the assertion goes red |
| `loomwright/scripts/test-build-reviewer-replay-case.sh` — dry run writes nothing | in `build-reviewer-replay-case.sh`, write the case dir without checking `--confirm`. The byte-identical-tree assertion must go red |
| `test-build-reviewer-replay-case.sh` — always-match grader leg (AC7) | in `lib/selftest.sh`, delete the mutation-control assertion (the one that prints `FAIL: mutation-control`). The AC7 leg must go red, because the mutated run's output then lacks the `FAIL: mutation-control` line |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Eval suite: stager, prompt renderer, grader, summarize, run command, model-free selftest, README | AC1, AC4, AC5, AC6, AC8 (all except the CI-leg wiring) | 0 modify, 10 create | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` | LAUNCHABLE |
| 2 | Corpus builder + its test (incl. the selftest CI leg and the AC7 mutant leg), two controls, AGENT_GUIDELINES + PR template, evidence file, changelog fragment | AC2, AC3, AC7, AC8 (CI leg), AC9, AC10 | 2 modify, 10 create | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md`, `skills/commit/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "loomwright/evals/phase45-reviewer/README.md"}
  - {kind: "file", path: "loomwright/evals/phase45-reviewer/case-template.yaml"}
  - {kind: "file", path: "loomwright/evals/phase45-reviewer/lib/stage-case.sh"}
  - {kind: "file", path: "loomwright/evals/phase45-reviewer/lib/render-prompt.sh"}
  - {kind: "file", path: "loomwright/evals/phase45-reviewer/lib/grade.sh"}
  - {kind: "file", path: "loomwright/evals/phase45-reviewer/lib/summarize.sh"}
  - {kind: "file", path: "loomwright/evals/phase45-reviewer/lib/run.sh"}
  - {kind: "file", path: "loomwright/evals/phase45-reviewer/lib/selftest.sh"}
  - {kind: "symbol", path: "loomwright/evals/phase45-reviewer/lib/selftest.sh", name: "PHASE45_GRADE"}
  - {kind: "file", path: "loomwright/evals/phase45-reviewer/.gitignore"}
requires: []
lanes:
  - "loomwright/evals/phase45-reviewer/README.md"
  - "loomwright/evals/phase45-reviewer/.gitignore"
  - "loomwright/evals/phase45-reviewer/case-template.yaml"
  - "loomwright/evals/phase45-reviewer/lib/**"
external_requires:
  - "claude plugin eval (Claude Code CLI) — only for the on-demand model-backed run, never in CI"
  - "the eval child's Agent tool can spawn plugin agent loomwright:loomwright:code-reviewer"

# Subtask 2
provides:
  - {kind: "file", path: "loomwright/scripts/build-reviewer-replay-case.sh"}
  - {kind: "file", path: "loomwright/scripts/test-build-reviewer-replay-case.sh"}
  - {kind: "file", path: "docs/evidence/phase45-reviewer-replay.md"}
  - {kind: "symbol", path: "docs/evidence/phase45-reviewer-replay.md", name: "## Baseline"}
  - {kind: "file", path: "docs/evidence/phase45-reviewer-corpus.tsv"}
  - {kind: "file", path: "changelog.d/phase45-reviewer-replay.md"}
requires:
  - {from: "1", kind: "file", path: "loomwright/evals/phase45-reviewer/case-template.yaml"}
  - {from: "1", kind: "file", path: "loomwright/evals/phase45-reviewer/lib/stage-case.sh"}
  - {from: "1", kind: "file", path: "loomwright/evals/phase45-reviewer/lib/selftest.sh"}
  - {from: "1", kind: "symbol", path: "loomwright/evals/phase45-reviewer/lib/selftest.sh", name: "PHASE45_GRADE"}
lanes:
  - "loomwright/scripts/build-reviewer-replay-case.sh"
  - "loomwright/scripts/test-build-reviewer-replay-case.sh"
  - "loomwright/evals/phase45-reviewer/[0-9]*/**"
  - "docs/evidence/phase45-reviewer-replay.md"
  - "docs/evidence/phase45-reviewer-corpus.tsv"
  - "AGENT_GUIDELINES.md"
  - ".github/pull_request_template.md"
  - "changelog.d/phase45-reviewer-replay.md"
external_requires: []
```

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 1 | Subtask 2 | none (Subtask 2 writes case dirs under `loomwright/evals/phase45-reviewer/[0-9]*/`, Subtask 1 owns only `README.md`, `case-template.yaml`, `lib/`) | YES — dependency (`requires`), not overlap |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md`, `skills/ci-cd/SKILL.md`, `skills/commit/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): the eval child may be unable to spawn the plugin agent `loomwright:loomwright:code-reviewer` via Agent | MEDIUM | Subtask 1 records in the README how the case reaches the agent. If the follow-up owner run shows the spawn fails, every staged miss case reads `MISSED (no reply)` and stays in the denominator (`caught: 0/<n>`, `no_reply: <n>`), so the failure is visible and never inflates the score |
| Feasibility (Phase 2.5): corpus confirmation and baseline are deferred to the owner (owner decision) | HIGH | The PR stays open. The evidence file's `## Baseline` says `PENDING — owner confirmation` with exact follow-up steps. A Phase 4.5 PASS or drain READY on this PR does NOT mean Validation 2 is met, and the item must not be stamped done until the owner adds ≥5 confirmed cases and real numbers |
| Feasibility (Phase 2.5): ~18 files | MEDIUM | `context-bound` split into 2 ordered subtasks |
| Pre-drain-head heuristic (last `fix: address review feedback (iteration N)` commit) misidentifies some PRs. A probe at base found 18 raw candidates among 76 merges since 2026-10-14, and some have dozens of later commits from base-merges | MEDIUM | The builder only proposes. The owner confirms each case, and `--list` shows the later-commit count so noisy candidates are visible |
| Reviewer output varies run to run | MEDIUM | Per-case rows. The PR evidence compares the same cases on both reviewers, and a 1-case swing is not a signal on its own (stated in README + evidence) |
| A later edit to the Phase 4.5 prompt breaks `render-prompt.sh`'s anchor | MEDIUM | The selftest renders the live file in CI and fails closed |
| Expectation leak: the reviewer runs in the sandbox cwd and could read the expected file and inflate `caught` (the analogue of coordinator-model README §"Honest limits") | MEDIUM | No expectation enters the sandbox or the plugin root (it lives in repo-root `docs/evidence/phase45-reviewer-corpus.tsv`). Grading runs after the run. The Baseline steps check each kept trace for a read of the table, and the remaining reachability by absolute path is stated as an honest limit. A selftest pin asserts this, and `.eval/` goes into `.git/info/exclude` |
| Model-backed run spends the subscription cap (machine-level weekly-cap lesson) | MEDIUM | On-demand only. AC10 forbids any CI invocation, and the worker never runs `lib/run.sh` against a model in this run |
| Selftest mutants silently invalid (lesson fa32a308) | LOW | The AC7 leg checks its mutant is non-empty, differs from the original and passes `bash -n` before trusting the run |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-01-phase45-reviewer-replay.md
```

## Outcome
- **Status:** completed
- **Completed:** 2026-11-01T18:06:44Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/783
- **Branch:** feature/phase45-reviewer-replay
- **Files changed:** 23
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Shipped the phase45-reviewer replay suite (stager, prompt renderer, deterministic grader, summarize, run command, model-free selftest), the human-gated corpus builder with its CI test (incl. the AC7 always-CAUGHT mutant leg), two controls (#651, #770), the AGENT_GUIDELINES evidence rule, the PR-template line, the evidence file with a PENDING Baseline and a changelog fragment. The pre-push full CI caught two gate failures (an inline origin/main, and grep -q pipes), and a worker fixed both. Phase 4.5 iteration 1 fixed one HIGH: an unterminated last corpus row was dropped from Y. Iteration 2 PASSed with LOW-only follow-ups. Baseline and the ≥5 owner-confirmed miss cases are still PENDING the owner: the PR must stay open, and the requirement is not done.

## Not verified
- **lib/run.sh model-backed claude plugin eval run (Agent spawn of loomwright:loomwright:code-reviewer from the eval child)** — spends the owner's credential; the brief forbids it in this job (subtask 1)
- **real eval --json / --keep-temp sandbox layout consumed by lib/summarize.sh** — inferred from coordinator-model; exercised only by fixtures (subtask 1)
- **lib/selftest.sh on Linux CI (mawk, GNU userland)** — no Linux host available (subtask 1)
- **lib/run.sh model-backed run over the two committed controls** — owner-only, by owner decision (subtask 2)
- **test-build-reviewer-replay-case.sh on Linux CI** — GNU date -d fallback not run (subtask 2)
- **full ci-local pool on the final tree** — rerun shows 3/194 red, none from this diff: test-automate-lanes is lane env leakage (passes 1070/0 with the env scrubbed); test-automate-next-step and test-automate-trail timed out at 900s under load 38-50 (subtask 2 retry)
