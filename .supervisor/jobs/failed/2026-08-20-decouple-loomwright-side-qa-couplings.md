# Supervisor Job: Decouple the four loomwright-side QA couplings before the move

## Environment

- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ found
- **Git:** `main` @ `c2b53bc` (brief authored at `e44cfa8`; PR #154 merged since — all seven Measured facts re-verified unchanged at the new base, see the engine note in Risks), clean except two known-unrelated artifacts (`.supervisor/postmortem/results.jsonl` modified, `loomwright/docs/SPIKES/IMPECCABLE_TEARDOWN.md` untracked) — **do not commit either**
- **GitHub CLI:** ✓ authenticated
- **Blockers:** 0 | **Warnings:** 0 (PR #154 has since MERGED; **no open PRs remain**, so the single-open-PR invariant is clear and the path-intersection warning is retired)

## Task

**Goal:** land all four loomwright-side QA coupling decisions — implemented, with reasoning and rejected
alternatives recorded **in the repo** — while every QA file is still in place. Slice 04 is the atomic
relocation; everything decidable *before* the move is pulled forward here so 04 reduces to `git mv`
plus mechanical pin updates.

**Counts do not change.** Nothing moves in this slice.

### Owner decisions already taken (do NOT re-litigate)

The source requirement was written 2026-08-18. Its own dependency — the slice-01 spike at
`loomwright/docs/SPIKES/CROSS_PLUGIN_RESOLUTION.md` — landed 2026-08-20 and **supersedes two of the
requirement's four recommendations**. The requirement says "per 01's unknown B"; the spike says "slice 03
makes the behavioural call". Each defers to the other, so both forks were put to the owner with their
measured consequences. The answers:

- **(a) `/dreaming --agent qa-executor` → OPTION 1, cross-plugin spawn.** Unknown C resolved YES. The
  capability is preserved; `--agent qa-executor` is NOT retired.
- **(b) QA telemetry fan-out → the SPIKE's option (d), keep the fan-out.** Loomwright keeps a
  `SubagentStop` matcher for the selvedge QA agent carrying the telemetry + token-ledger fan-out.
  **QA telemetry is PRESERVED. Rubric C stays LIVE and MUST NOT be banner-marked dormant.**
  This overrides the source requirement's recommendation to drop it, and it **corrects the
  requirement's stated slice-04 hook figure from 24→22 to 24→23** (only `validate-qa-result.py` moves).
- **(c) `qa-executor:` reserved kind → OPTION 1**, keep the reserved name and re-point all four surfaces.
- **(d)** decided in the source requirement: fix the comments, do not churn the regex. See fact 5 — the
  requirement's framing of (d) is measurably wrong in two ways and the corrected form is below.

## Subtask Structure

| # | Title | Est. Files | Status |
|---|-------|-----------|--------|
| 1 | Decouple all four QA couplings (a)+(b)+(c)+(d), record every decision in-repo | ~7 modify, 0 create | LAUNCHABLE |

Single subtask **on purpose.** The four couplings are independent in *subject* but not in *record*: (a)
and (c) must agree on the same namespace rule (fact 7), and (b)'s decision record must state a hook
figure that (a)/(c) do not change. Splitting them into parallel worktrees would give each worker a
partial view of one shared decision record and reproduce the cross-file review false-positive this repo
has already recorded. Decomposition Threshold default (1) applies; no fan-out.

## Configuration

- **Mode:** single-agent (no fan-out), Single-Agent Path
- **Recommended workers:** 1
- **Base branch:** `main`
- **Base commit:** `e44cfa8`
- **Cost profile:** default (`inherit`) — `--cheap` was not passed to this run

## Parallelism Analysis

single-agent (no fan-out) — Recommended workers: 1

## Measured facts (read off disk at `e44cfa8`; re-verify before editing)

Every fact below was measured, not inherited from the source requirement. Facts 3, 5 and 6 are
**corrections to the requirement's own claims** — treat the requirement as a stale map where it disagrees.

1. **Hook shape.** `loomwright/hooks/hooks.json` has exactly ONE QA matcher: `SubagentStop` /
   `loomwright:qa-executor`, carrying **2 leaf hooks** — `validate-qa-result.py`, and the shared fan-out
   (`send-telemetry.sh` + `emit-token-ledger.sh` in one command string). Total hooks:
   `jq '[.hooks[][].hooks[]] | length'` = **24**.
2. **Counts at base:** agents **14**, commands **21**, skills **41**, hooks **24**. All must be unchanged.
3. **CORRECTION — there is no spawn string to re-point.** `loomwright/commands/dreaming.md` contains
   **no literal `subagent_type` value anywhere**, and `grep -rn 'loomwright:loomwright:' loomwright/commands
   loomwright/agents` returns **nothing**. `dreaming.md` names its spawn targets in prose only
   (``loomwright/commands/dreaming.md:494 [pins: `Task(subagent_type: ...)`]`` is a *prose mention*, not a
   value). Both the source requirement and the spike assume a literal exists to edit. **Option (a)1 therefore
   ADDS a new pinned literal** — more surface than either document implies. Plan for an addition, not an edit.
4. **The (a) sweep surface.** QA Executor is named in `dreaming.md` at: the usage example
   (``:23 [pins: `/dreaming --agent qa-executor`]``), the `--agent` row **which also carries the
   six-agents-with-`memory: project` enumeration** (``:35 [pins: `Six agents have `memory: project``]``),
   the forward-work spawn note (`:191`), the per-agent role hint (`:266`), the tool-permission note
   (`:494`), the sample output's reflecting line (`:511`) and its `[qa-executor]` proposal line (`:538`),
   **two** `/qa-executor` counterpart rows (`:593` and `:616`), and a **second** six-agent enumeration at
   `:609`. That is **eleven** sites across **two** duplicated enumerations — the source requirement's list
   omits `:609` and counts only one counterpart row.
5. **CORRECTION — (d) is not symmetric, and the comment is wrong twice.**
   `loomwright/scripts/notify-desktop.sh` has an enumerating comment
   (``:100 [pins: `the 12 plugin slash commands`]``) that is wrong on **both** axes: post-split two of the
   listed commands belong to another plugin, **and the count is wrong today** — its own alternation at
   ``:102 [pins: `grep -qE 'loomwright:|/launch-pad`]`` carries **11** command branches, not 12.
   `loomwright/scripts/send-webhook.sh` runs the **identical** alternation at
   ``:296 [pins: `grep -qE 'loomwright:|/launch-pad`]`` but has **no enumerating comment at all** — its only
   nearby comment says it "mirrors notify-desktop.sh", which **stays true** after the split. So (d) is
   **one** comment fix plus a recorded finding, not two edits.
6. **The (c) surfaces, all five sites across four files.** `run-ground-truth.sh` (`:54`–`:55` header,
   `:75`, `:98`, the classifier ``:274 [pins: `qa-executor:*)`]``, and the deferred emitter `:336`–`:337`);
   `agents/plan-reviewer.md` `:266`–`:267`; `skills/supervisor-readiness/SKILL.md` `:193`;
   `skills/self-heal-advisory/SKILL.md` **twice** — `:286` (the `unverified` fail-safe path) and `:287`
   (the deferred-kind + trust-boundary note).
7. **Two namespaces, and mixing them fails SILENTLY.** Per the spike: a `Task(subagent_type:)` spawn takes
   the **DOUBLED** `<plugin>:<frontmatter-name>` form → **`selvedge:selvedge:qa-executor`**. A `hooks.json`
   **matcher** slot takes the **SINGLE**-prefix frontmatter name → **`selvedge:qa-executor`**. Every existing
   matcher in `hooks.json` is single-prefix. Writing a spawn string into a matcher slot yields a matcher that
   never fires, and under the `|| true` hook convention that loses the telemetry fan-out **with no error**.
   A wrong *spawn* string, by contrast, fails **loudly** (the spike measured a `not found` naming every valid
   alternative). Get (a) and (c) — both spawns — doubled; get (b)'s recorded matcher single.

## Acceptance Criteria

- [ ] **(a)** `/dreaming` keeps `--agent qa-executor` and spawns the selvedge agent. The literal
      `selvedge:selvedge:qa-executor` is written into `dreaming.md` **with an explicit note that it is NOT
      derivable from the agent file and depends on the installed plugin name** (fact 7 + fact 3).
- [ ] **(a)** All **eleven** sites in fact 4 are swept, **including both** six-agent `memory: project`
      enumerations (`:35` and `:609`) and **both** `/qa-executor` counterpart rows (`:593`, `:616`).
      **Attach the grep proving zero stragglers**, and derive the search terms from the file's own
      vocabulary rather than guessing a form.
- [ ] **(b)** The telemetry decision is recorded in `loomwright/docs/TELEMETRY.md` with **reason, date
      (2026-08-20), and the rejected alternatives** (the spike's options (a)/(b)/(c) *and* the source
      requirement's drop-the-fan-out and retire-Rubric-C options — four rejections, not two).
- [ ] **(b)** **Rubric C is NOT banner-marked dormant** and no fixture or ledger assertion is deleted.
      QA telemetry is preserved. A change that marks it unexercised is a FAILED criterion, not a variant.
- [ ] **(b)** The slice-04 hook figure is **re-derived from the file** with
      `jq '[.hooks[][].hooks[]] | length'`, stated as **24 → 23** in the decision record with the
      derivation shown, and explicitly noted as **correcting the source requirement's 24 → 22**.
- [ ] **(b)** The decision record states the fact-7 matcher-vs-spawn distinction and that the future
      matcher is the **single**-prefix `selvedge:qa-executor`, with the silent-failure consequence named.
- [ ] **(c)** All five sites in fact 6 are amended consistently to name `selvedge:selvedge:qa-executor`
      as the eventual dispatch target **when selvedge is installed**. `bash loomwright/scripts/test-run-ground-truth.sh`
      still passes and its coverage of the deferred path is preserved.
- [ ] **(d)** `notify-desktop.sh`'s comment is corrected on **both** axes — the count (**11**, not 12) and
      the post-split ownership. **Regex behaviour is unchanged** (assert the alternation is byte-identical
      before/after). The finding that `send-webhook.sh` needs **no** comment change is recorded rather than
      silently skipped.
- [ ] Every decision is recorded **with its reasoning and rejected alternatives, in the repo** — reachable
      from a clone, not only from a PR description.
- [ ] Counts provably unchanged (14/21/41/24), captured **before** any edit and diffed after.
- [ ] Full CI green, including the whole `test-*.sh` hard-gate loop and `test-citation-drift.sh`.

## Executable Acceptance

Machine-run by `run-ground-truth.sh`, which parses **leading-`-` bullets from this section only**
(``loomwright/scripts/run-ground-truth.sh:195 [pins: `## Executable Acceptance`]``); the next `## ` heading
closes the section, so §"Verification commands (worker-facing)" is not parsed.

**`corpus-task:` bullets only — deliberately.** A machine-authored brief MUST NOT emit `cmd:` bullets
(``loomwright/skills/supervisor-readiness/SKILL.md:198 [pins: `MUST NOT emit `cmd:``]``), and Supervisor
passes `--no-cmd` on this unattended dispatch path, which would record every `cmd:` bullet `unverified`.
**`parity-emit-block` is now INCLUDED — the exclusion's premise expired.** The brief originally excluded it
because it failed on pristine `main` while PR #154 (its fix) was still open. **#154 merged on 2026-08-20**
(`main` is now `c2b53bc`), and the engine re-ran the check at that base: `bash
loomwright/scripts/eval-corpus/parity-emit-block/check.sh` exits **0** — *"all hook-required fields present
inside their emit-block templates."* The exclusion was conditional on a failure that no longer exists, so
keeping it would ship a deliberately weakened ground-truth signal on a stale premise. Re-verify it still
passes at your own base before relying on it; if it fails for a reason **outside this slice's ~7 files**,
report that rather than fixing it here.

- corpus-task: version-consistent
- corpus-task: doc-currency-green
- corpus-task: eval-selftest-green
- corpus-task: parity-emit-block

## Verification commands (worker-facing)

> **PATH CORRECTION (engine, 2026-08-20) — this block shipped a FAIL-OPEN.** Two of these gates were
> originally written as `loomwright/scripts/check-doc-currency.sh` and
> `loomwright/scripts/check-plugin-selftests.sh`. **Both live at repo-root `scripts/`.** As written they
> returned **`rc=127`**, and "No such file or directory" reads as noise — so a worker could report the
> gate "run" when it never executed. The worker caught this and ran the real paths; the paths are fixed
> above. Note which gates live where: `check-*.sh` (doc-currency, plugin-selftests, token-budget,
> shared-prefix, contract-parity) are **repo-root** `scripts/`; `test-citation-drift.sh`,
> `run-ground-truth.sh` and `test-run-ground-truth.sh` are under **`loomwright/scripts/`**. Verified
> repo-wide: the wrong form appeared **only** in this brief, nowhere else in the repo.

```bash
# --- Counts unchanged. Capture BEFORE any edit, diff AFTER.
# Field separator is TWO spaces. Do NOT pipe to `head -1`: DRIFT lines print AFTER
# the "Authoritative →" line, so a head-1 pipeline reports an identical first line
# on a FAILING run and its exit status is head's, not the gate's.
bash scripts/check-doc-currency.sh > /tmp/dc.after 2>&1; echo "rc=$?"   # REPO-ROOT scripts/, NOT loomwright/scripts/
jq '[.hooks[][].hooks[]] | length' loomwright/hooks/hooks.json   # must print 24

# --- AC(a): zero stragglers. Derive terms from the file's vocabulary; check BOTH enumerations.
grep -n 'qa-executor\|qa-strategist\|QA Executor\|QA Strategist' loomwright/commands/dreaming.md
grep -c 'memory: project' loomwright/commands/dreaming.md        # two enumerations exist (:35, :609)

# --- AC(d): regex behaviour unchanged. Compare the ALTERNATION ITSELF, not the file.
grep -o "grep -qE '[^']*'" loomwright/scripts/notify-desktop.sh loomwright/scripts/send-webhook.sh

# --- AC(c): deferred-path coverage preserved.
bash loomwright/scripts/test-run-ground-truth.sh

# --- Full hard-gate loop, exactly as ci.yml runs it. bash, NOT the agent's zsh Bash tool.
bash scripts/check-plugin-selftests.sh          # REPO-ROOT scripts/, NOT loomwright/scripts/
bash loomwright/scripts/test-citation-drift.sh  # this one IS under loomwright/scripts/

# --- Commit hygiene: assert over the WHOLE BRANCH (three-dot vs merge base), never HEAD~1..HEAD —
# with no HEAD~1 git writes `fatal:` to stderr with EMPTY stdout, so a `test -z` check fails OPEN.
git diff --name-only origin/main...HEAD    # must NOT list results.jsonl or IMPECCABLE_TEARDOWN.md
```

## Implementation Guidance

- **Prompts are programs — state-trace, don't proofread.** `dreaming.md`, `plan-reviewer.md` and the two
  skills are executable logic. Trace: what does `--agent all` spawn now? What does `--agent qa-executor`
  do when selvedge is **absent**? The owner chose option 1, **not** option 3 — so a graceful-degrade path
  is **out of scope**, but the absent-plugin behaviour must still be *stated* (per the spike, a wrong spawn
  string fails loudly with a `not found`, which is the acceptable failure here and should be said so).
- **Record the decisions where the behaviour lives.** (b) → `docs/TELEMETRY.md`. (a) → `dreaming.md` itself.
  (c) → alongside each of the five amended sites, or one anchor cited from the other four. A decision that
  exists only in the PR body is not reachable from a clone and does not satisfy the criterion.
- **`hooks.json` is JSON and cannot hold a comment** — do not try to record (b)'s reasoning there. The
  record belongs in `docs/TELEMETRY.md` (and, if a hook-side pointer helps, `docs/HOOKS.md`).
- **Citation convention.** Any `file:line` added to committed prose must be **pinned**
  (`` file.sh:128 [pins: `anchor text`] ``) or `test-citation-drift.sh` fails the new bare citation. Prefer
  a descriptive anchor where a number adds nothing. **Re-run `test-citation-drift.sh` after your last edit** —
  inserting lines above your own pins invalidates them, which is a trap this repo has hit twice.
- **`check-doc-currency.sh` does not cover agent/command enumeration prose.** A half-swept enumeration
  passes every gate. Fact 4's eleven sites are the whole surface; grep with flexible separators.

## Risks

| Risk | Mitigation |
|---|---|
| Writing the **doubled** spawn string into a future matcher slot (or the single-prefix into a spawn) | Fact 7. The matcher failure is **silent** under `|| true`; state the rule in the (b) decision record so slice 04 cannot get it wrong. |
| Half-swept enumeration in `dreaming.md` — no gate covers it | Fact 4 lists all eleven sites incl. the two the source requirement missed; AC requires an attached grep. |
| Marking Rubric C dormant out of habit, following the stale source requirement | The owner reversed this. An unexercised-banner is a FAILED criterion. |
| Editing the (d) regex instead of the comment | AC asserts the alternation is byte-identical; compare the alternation, not the file. |
| Sweeping the two known-unrelated working-tree artifacts into a commit | Commit-hygiene check over `origin/main...HEAD`, three-dot, whole branch. |
| ~~PR #154 open on `execute-manager.md`~~ — RETIRED | #154 **merged** 2026-08-20; `gh pr list --state open` returns empty. Its one path (`loomwright/agents/execute-manager.md`) never intersected this brief. Phase 1.5 should classify CLEAR; if it does not, read the intersecting paths before proceeding. |
| `parity-emit-block` was excluded on a premise that has since expired | PR #154 merged; the check now exits **0** at `c2b53bc` (re-measured, not assumed). It is INCLUDED in Executable Acceptance. If it fails at your base for a cause outside this slice's ~7 files, report it — do not fix it here. |

## Outcomes Rubric

- All four couplings are **decided and implemented** while every QA file is still in place — slice 04 shrinks to `git mv` plus pin updates
- `/dreaming`'s live spawn is handled as a real capability decision, with the non-derivable spawn literal pinned and its origin explained
- QA telemetry is **preserved**, and the record says so with its reasoning and all four rejected alternatives
- The slice-04 hook figure is **re-derived from `hooks.json`** and explicitly corrects the source requirement's number
- The matcher-vs-spawn namespace rule is recorded with its **silent**-failure consequence named
- Enumeration sweeps are complete and **grep-proven**, covering both duplicated six-agent enumerations
- (d) is corrected on both axes, and the asymmetry with `send-webhook.sh` is recorded rather than silently skipped
- Counts unchanged and CI green, both proven by pasted output rather than asserted

## Handoff

/supervisor job: .supervisor/jobs/pending/2026-08-20-decouple-loomwright-side-qa-couplings.md

---

> **ABANDONED 2026-08-22 by owner decision** — the selvedge QA-extraction track is not being pursued. Retired here from the active queue so no `/automate` or `/supervisor` tick re-picks it. `main` was force-pushed back past this track on 2026-08-20T15:31:01Z; the work survives only on `origin/feature/relocate-qa-to-selvedge`. Requirements remain at `.supervisor/requirements/selvedge-extraction/` if the decision is ever reversed.
