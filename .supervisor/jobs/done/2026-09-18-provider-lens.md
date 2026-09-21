# Supervisor Job: Provider-pluggable review lens (`lens-run.sh` adapter + `--voter-provider`)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main (v15.81.0)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 1 (non-main worktrees from other concurrent plugin activity — acknowledged, non-blocking)
- **Source requirement:** .supervisor/requirements/orca-derived/07-provider-lens.md (includes a 2026-09-18 "Probe result" section — read it first, it changes what this item can honestly claim)

## Task
**Goal:** A new, isolated adapter (`loomwright/scripts/adapters/providers/lens-run.sh`) turns any installed agent CLI into a second-opinion review lens that returns the same findings shape the existing multi-voter merge rule already consumes; the multi-voter verification voter becomes provider-selectable via a new `--voter-provider` flag/config key; the gate shape, merge rule, and never-merge invariant are untouched. **This PR must NOT be merged by the executing agent or by any automation — leave it open, reviewed, CI-green, for the repo owner (Vikash) to merge himself.** This is an explicit standing instruction for this item only (items 01–06 in this same automate run WERE auto-merged per standing order; item 07 is the deliberate exception, per Vikash's own words: "Do NOT merge").

**Problem Statement:**
D4 fixes two review lenses and requires every additional pass to state what the earlier one could not see. Today both lenses are Claude (Phase 4.5 + the `claude-review` CI bot). A second MODEL FAMILY is the cleanest form of genuinely different information — different training, different blind spots. The multi-voter verification mechanism (`--multi-voter-heal`, opt-in, default OFF, fully specified in `loomwright/skills/self-heal-advisory/SKILL.md` §"Multi-voter verification" — but **confirmed to have NEVER executed in this repo, 0 `multi_voter` lines in any live session log as of 2026-09-12**) already has the right shape: an independent second reviewer votes on the same diff, a refute check decides which of its findings actually get fixed, and `heal_decision` (the gate) derives ONLY from the primary `code-reviewer` — the voter can delay finalization within the existing `--heal-iterations` bound, never flip PASS↔FAIL. Today that second voter can only be a Claude subagent (`loomwright:red-team-reviewer`), because Claude Code subagents cannot run a non-Anthropic model. The only route to a genuinely different model family is shelling out to a vendor CLI in print mode — the exact pattern `loomwright/scripts/dispatch-pr-review.sh` already uses for `claude -p`.

**What changed since the source requirement was written (2026-09-11/12) — read before implementing:**
- `cursor-agent` (the only non-Claude CLI installed on this machine) is confirmed present but **NOT authenticated** (`cursor-agent status` → `Not logged in`), and the repo owner declined an interactive login during this automated run (2026-09-18). The requirement's own §"probe this first" (`-f`/deny-by-default behavior) **cannot be executed** — it is recorded as a named, dated follow-up in the source requirement file's new "Probe result" section, not fabricated or silently skipped. **This changes the honest posture of Scope 2 ("read-only by verification"): treat the throwaway-worktree-plus-mutation-check as the ONLY confirmed lever, not a backstop to a confirmed deny-by-default** — the doc comments/adapter header must say so.
- `codex exec` and `gemini -p` remain NOT installed on this machine (re-verify with `command -v codex`/`command -v gemini` before writing any provider-specific code — do not assume either has appeared).
- Because no non-Claude CLI is authenticated, **every acceptance criterion below that needs a live external CLI is satisfied via a STUB on PATH**, exactly as item 06 (`loomwright/scripts/adapters/orca/`) did for `orca`. This is the sanctioned approach for this repo (see that item's own precedent), not a shortcut — the requirement's own AC wording for `cursor-agent` already anticipates "absent → `provider_unavailable`" as a first-class, tested path.

## Acceptance Criteria
- [ ] **AC-0 — baseline row (execution-mechanism criterion, not a code diff):** THIS brief itself must be executed via a real `/supervisor ... --multi-voter-heal` Phase 4.5 run (default Claude voter — `--voter-provider` is NOT passed, since the code this PR adds doesn't exist yet at the start of the run and the default path needs none of it). This is the **first-ever real execution** of the multi-voter mechanism in this repo. After the run finishes (whatever `heal_decision` it reaches), the operator records one baseline row in `loomwright/docs/SPIKES/FABLE_PARITY_EVAL.md` (or creates a minimal "multi-voter-only baseline (no --sdk-runner)" entry if no existing table row fits — do NOT call it "arm 3", that name is already the pre-registered `--sdk-runner` + `--multi-voter-heal` combined arm in that doc) with: iteration count, `findings_raised`/`findings_refuted`/`findings_fixed` (from the `SUPERVISOR_RESULT` summary's `multi_voter: ...` line per `self-heal-advisory/SKILL.md` line ~797), and an honest wall-clock/turn-cost note. **This row is added as a follow-up commit AFTER the run completes** (the numbers don't exist beforehand) — do not fabricate placeholder numbers in the initial diff.
- [ ] Given `loomwright/scripts/adapters/providers/` does not exist today, when this item lands, then `lens-run.sh --provider <p>[:<model>] --role review --diff <file> --prompt <file> --out <json>` exists, with a provider table covering `claude`, `cursor`, `codex`, `gemini` — one small file per provider (command template + output parser), so adding a fifth provider later touches one new file, not `lens-run.sh` itself.
- [ ] Given a provider's CLI is absent from PATH (true today for ALL FOUR — even `claude` should be probed via `command -v`, never assumed), when `lens-run.sh` is invoked for that provider, then it exits 0, writes a `provider_unavailable` result to `--out`, and does NOT attempt any subprocess.
- [ ] Given a provider's CLI is present (a **stub** for `cursor`/`codex`/`gemini`, since none is authenticated/installed for real; `claude` itself may be probed for real since it IS installed, but the test must not depend on live Claude output — use a stub for `claude` too, for determinism), when `lens-run.sh` runs it inside a throwaway **detached `git worktree`** at the diff's target commit, then: (a) the CLI is invoked with a scrubbed environment (no `GH_TOKEN`, `HOME` redirected to a temp dir unless a specific CLI's auth is proven to require the real `HOME` — verify per-provider, don't assume), (b) `--workspace <worktree>` (or that provider's equivalent flag) is passed, (c) `git remote remove origin` has been run in the throwaway worktree before the CLI executes, (d) after the run, `git status --porcelain` in the worktree is checked — non-empty → the result is DISCARDED with a `lens_mutated_tree` marker and the worktree is removed either way.
- [ ] Given a stub provider produces well-formed output, when `lens-run.sh` normalizes it, then `--out` contains the CODE_REVIEW_RESULT `issues[]` fields exactly as `loomwright/docs/RESULT_SCHEMAS.md` defines them (`severity`, `category`, `file`, `line`, `description`, `suggestion` — NOT `summary`/`evidence`, which are red-team-reviewer's free-form prose fields, not this schema's) — read the actual schema first, match it exactly, do not invent a parallel shape.
- [ ] Given a stub provider produces garbage/unparseable output, when `lens-run.sh` normalizes it, then `--out` contains a `lens_unparseable` marker (exit 0, not an error) — this and `lens_mutated_tree`/`provider_unavailable` all degrade the SAME way once wired: the calling multi-voter loop treats them identically to "voter errored/timed out" (the existing fail-safe degradation already specified in `self-heal-advisory/SKILL.md` line ~795 — reuse it, do not invent a second degradation path).
- [ ] Given `.supervisor/config.json` has no `.voter_provider` key today (verify — this is a NEW key, confirm it's absent before claiming so), when this item lands, then: a new `--voter-provider <provider>[:<model>]` CLI flag and `.voter_provider` config key are resolved in `loomwright/skills/supervisor-config/SKILL.md` (mirror the exact flag-vs-config precedence pattern step 2.9 already uses for `--multi-voter-heal` — flag wins over config, absent-both keeps default), and `loomwright/skills/self-heal-advisory/SKILL.md`'s "Multi-voter verification" §1 (the two-reviewer spawn step) is amended so that when `VOTER_PROVIDER` resolves to a non-default value, the verification-voter half of the vote is produced by invoking `lens-run.sh` directly (via Bash, not a Task spawn) instead of spawning the `loomwright:red-team-reviewer` Task — everything downstream (the refute check, the merge rule, `heal_decision` derivation, the delay-vs-decide invariant) is **completely unchanged**, because `lens-run.sh`'s normalized output slots into the exact same findings shape the Task-spawned voter already produces.
- [ ] Given `--voter-provider` is absent (the default, and the state of every run before this item), when the multi-voter loop runs, then behavior is byte-for-byte identical to today — existing multi-voter-related tests (if any exist; if none exist today, note that explicitly rather than assuming) still pass, and this is proven by AC-0's own baseline run using no `--voter-provider` flag at all.
- [ ] Given the full test suite runs (`bash loomwright/scripts/test-*.sh` from repo root, plus root `scripts/test-*.sh`, `check-vendor-coupling.sh`, `check-doc-currency.sh` — the full loop, not a scoped subset), when `lens-run.sh` and its provider-table files are tested, then stub-backed tests cover: provider-absent → `provider_unavailable`; mutation → `lens_mutated_tree` + worktree removed; garbage output → `lens_unparseable`; well-formed output → correct normalized findings JSON; scrubbed-env assertion (stub records its own env, test asserts `GH_TOKEN` absent).
- [ ] `grep -rl "cursor-agent\|codex exec\|gemini -p" loomwright/ --exclude-dir=adapters` returns documentation files only — no core (`agents/`, `skills/` outside the adapter's own doc references, `commands/`) file names a specific vendor CLI.
- [ ] `loomwright/docs/ARCHITECTURE_CONTRACTS.md`'s existing `## Portability` section (created by item 06) gets a short addition noting the `adapters/providers/` directory and its purpose — do not duplicate the whole section, extend it.
- [ ] The source requirement file's `## Status: pending` line is updated to reflect what actually shipped vs. what's deferred (mirror the pattern in `06-orca-adapter.md`'s `## Status: done (PR #237...)` line, but since this item's PR is deliberately left unmerged, phrase it as `## Status: PR open, awaiting owner merge (PR #<n>) — live cursor-agent probe deferred, see Probe result section`).

## Outcomes Rubric
- Provider table + parser per provider; absent CLI is a named no-op, never a crash
- Read-only posture is honestly scoped: in-tree mutation is detected and discarded (proven by test); out-of-tree risk and the deferred `-f` probe are both stated plainly, never called "enforced" or "verified safe"
- Voter is provider-selectable; merge rule, refute check, and `heal_decision` derivation are provably unchanged (AC-0's own default-voter baseline run is the proof)
- Cost recorded honestly — `unknown` when a CLI's usage isn't reported, never `0`
- Core (`agents/`, `commands/`, non-adapter `skills/`) stays free of hardcoded vendor CLI names (grep-verified)
- No code path in this diff invokes `gh pr merge` (merge withholding is an operator/process instruction, tracked in Configuration + Risk Assessment, not a diff-checkable rubric fact)

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | `lens-run.sh` adapter + provider table + stub tests + `--voter-provider` wiring into `supervisor-config/SKILL.md` + `self-heal-advisory/SKILL.md` + Portability doc addition + requirement-file status update | all | ~4 modify, ~7 create (lens-run.sh + 4 provider files + test + doc) | none preloaded | LAUNCHABLE |

**Split reason:** none — single subtask (Decomposition Threshold default). The SKILL.md wiring (what would otherwise be a second subtask) prose must reference `lens-run.sh`'s exact flag names and output-JSON shape (`--provider`, `--role`, `--diff`, `--prompt`, `--out`, and the `provider_unavailable`/`lens_mutated_tree`/`lens_unparseable` markers) — a genuine dependency on the adapter's own contract, not just a shared-file concern. None of the three legal split predicates (`file-conflict`, `context-bound` >12 files/>800 lines, `genuine-parallelism` ≥3 files per side) is met by this item's ~11 total files, and a real cross-piece dependency is exactly the case a single worker handles most reliably — it writes `lens-run.sh` first, then threads the wiring against what it actually built, instead of a second worker guessing at a contract pinned only in this document.

### Provides / Requires Schema

```yaml
# Subtask 1 — lens-run.sh adapter + --voter-provider wiring (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/adapters/providers/lens-run.sh"}
  - {kind: "file", path: "loomwright/scripts/adapters/providers/test-lens-run.sh"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "Portability"}
  - {kind: "symbol", path: "loomwright/skills/supervisor-config/SKILL.md", name: "voter_provider resolution (step 2.9 extension)"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "Multi-voter verification (provider-substitution branch)"}
requires: []
lanes:
  - "loomwright/scripts/adapters/providers/"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/skills/supervisor-config/SKILL.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - ".supervisor/requirements/orca-derived/07-provider-lens.md"
external_requires:
  - "cursor-agent / codex / gemini CLIs (all optional, runtime-detected — not a build/test dependency; all tests use stubs, none authenticated on this machine as of 2026-09-18)"
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1
- **Estimated batches:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | (none preloaded — new isolated adapter plus a direct SKILL.md prose edit) |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| **This item's PR must NOT be merged**, breaking the pattern every prior item in this automate run followed (auto-merge on green) | HIGH if the standing merge habit is applied by mistake | This brief states it in three places (Task goal, Acceptance Criteria checklist item, Outcomes Rubric); the executing agent/operator must skip the `gh pr merge` step entirely for this item — Supervisor's own Phase 4.5 already never merges (CLAUDE.md invariant), so this only requires the OPERATOR (not Supervisor) to withhold the manual merge step used for items 01–06 |
| AC-0 requires a REAL `--multi-voter-heal` Supervisor run (not the operator's manual worker/reviewer loop used for items 01–06) — this is the only item in the queue that must be executed via the actual `/supervisor` mechanism to exercise the never-before-run multi-voter path | HIGH — using the manual loop instead would silently fail AC-0 while looking like a normal completed item | Handoff below specifies `--multi-voter-heal` explicitly; the operator must confirm the run's own `SUPERVISOR_RESULT` summary contains a `multi_voter: findings_raised=... findings_refuted=... findings_fixed=...` line before claiming AC-0 satisfied — its ABSENCE means the flag didn't take effect (e.g. wrong config precedence) and must be investigated, not treated as "zero findings" |
| The live `cursor-agent -f`/deny-by-default probe cannot be executed (auth unavailable) — the requirement's own Mechanism section conditions the read-only safety claim on this probe's result | HIGH if silently ignored, LOW if honestly scoped | Already documented as a dated, named follow-up in the source requirement file (`## Probe result — 2026-09-18, DEFERRED`); this brief requires every doc/comment describing Scope 2's read-only posture to say "in-tree mutation detected, out-of-tree unmitigated, deny-by-default UNVERIFIED" — never "enforced" or "safe" |
| `codex`/`gemini` CLIs are absent — their provider-table entries can only be written against documented CLI flag conventions, not verified against real `--help` output | MEDIUM | Mirror the existing memory lesson `verify-invocation-shapes-from-the-file`: since neither CLI can be inspected on this machine, the worker must write each provider file's command template defensively (documented assumption, not asserted fact) and make `provider_unavailable` the exercised, tested path for both — this is honest given the constraint, not a shortcut |
| A CLI-invocation adapter is a plausible injection-risk surface (diff/prompt file paths, model names passed as argv) | HIGH if mishandled | `jq`/array-based argv construction throughout, exactly as item 06's `orca-mirror.sh` precedent; never string-interpolate untrusted fields into a shell command |
| Feasibility (Phase 2.5) — Scope vs Supervisor Capability | MEDIUM | Single subtask, well within Single-Agent Path capacity; the genuinely novel risk is procedural (execution mechanism + merge withholding), not implementation complexity |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1
- **Base Branch:** main
- **Multi-voter:** `--multi-voter-heal` REQUIRED at Handoff (see below) — this is the AC-0 execution mechanism, not optional
- **Merge:** DO NOT auto-merge; DO NOT manually merge after CI/review completes. Leave PR open.

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-18-provider-lens.md --multi-voter-heal
```
**Do not pass `--auto-merge`** (this repo's automate-loop convention already avoids it — merge commits are executed manually by the operator per standing order, and for THIS item specifically, no merge step runs at all). **Do not pass `--voter-provider`** — the point of this run is to exercise the DEFAULT (Claude) voter path for the first time, since the provider-selectable code doesn't exist until this run finishes building it.
