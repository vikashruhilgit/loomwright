# 05 — `cmd:` Executable-Acceptance bullets run only behind an explicit, command-visible human stamp


## Problem
`skills/self-heal-advisory/SKILL.md:390-403`: `NO_CMD_FLAG = (NON_INTERACTIVE == true) ? "--no-cmd" : ""`, with
the comment "when NON_INTERACTIVE == true — i.e. this run was driven by /autonomous". That is false:
`skills/autonomous-loop/SKILL.md:94,284` forward `--non-interactive` to Supervisor ONLY under
`--non-interactive-fallback`. A default interactive `/autonomous "goal"` therefore runs a MACHINE-AUTHORED
brief with `NON_INTERACTIVE=false`, and any `cmd:` or bare bullet under `## Executable Acceptance` executes via
`bash -c` in Phase 4.5 (`run-ground-truth.sh`). The only guards are prose: Launch Pad is told "NEVER emit
`cmd:`" (`agents/launch-pad.md:482`) while reading a repo whose README may say "acceptance: run …"; Plan
Reviewer Criterion 14 (`agents/plan-reviewer.md:274`) rates a present `cmd:` bullet LOW ⇒ PASS ⇒ the brief
saves; Launch Pad's Phase 6 "save/refine/discard?" prompt shows the verdict, not the commands. Memory
`acceptance-check-vs-adversarial-review` names exactly this class: a stated invariant ("can NEVER run with no
human in the loop") that nothing falsified.

## Goal
A `cmd:`/bare bullet executes only when a human has seen the literal command text and stamped the brief;
the stamp is keyed to the bullets' content so a later edit invalidates it; the safety-valve comment tells the
truth; machine-authored briefs never carry the stamp by construction.

## Scope
1. **Brief stamp.** `## Configuration` gains an optional line
   `- **Executable Acceptance Approved:** sha256:<hash of the normalized cmd:/bare bullet list>` (documented in
   `skills/supervisor-readiness/SKILL.md` §"`## Executable Acceptance`" and `docs/RESULT_SCHEMAS.md`). New
   helper `scripts/exec-acceptance-hash.sh <brief>` prints the hash (bullets classified with the SAME rule as
   `run-ground-truth.sh`: `cmd:` prefix or bare; `corpus-task:`/`qa-executor:` excluded; whitespace-normalized;
   empty list ⇒ prints `none`).
2. **`run-ground-truth.sh`:** when `--brief` is given and `--no-cmd` is NOT, execute `cmd`-kind checks ONLY
   if the brief's stamp equals `exec-acceptance-hash.sh <brief>`; otherwise record them
   `unverified` with reason `cmd_unapproved` (new reason string beside `cmd_disabled`). `--check <cmd>` and
   `--checks-file` (explicit human invocation) are unaffected. `test-run-ground-truth.sh` (read the tree for
   its name) covers: stamp matches ⇒ runs; stamp absent ⇒ `cmd_unapproved`; stamp stale (bullet edited) ⇒
   `cmd_unapproved`; `--no-cmd` wins over a valid stamp. **Mutation control:** delete the hash comparison ⇒
   the stale-stamp case must fail.
3. **Plan Reviewer Criterion 14** (`agents/plan-reviewer.md` ~261–278): severity becomes **NEEDS_HUMAN** when
   ≥1 `cmd:`/bare bullet is present and no valid stamp exists; the issue `description` lists every bullet
   verbatim (already required) — this is the text the human must see. A valid stamp ⇒ LOW (visibility only,
   as today). The "M3 graduation" forward note is retired (it is now the behaviour).
4. **Launch Pad Phase 6** (`agents/launch-pad.md`): when the Plan Reviewer returns NEEDS_HUMAN with an
   `executable_acceptance` issue, the AskUserQuestion MUST quote the flagged bullets in the question text and
   offer `approve-and-stamp | strip-cmd-bullets | discard`; `approve-and-stamp` writes the stamp line via
   `exec-acceptance-hash.sh`; `strip-cmd-bullets` removes them (leaving `corpus-task:` bullets) and re-runs
   Plan Review. Under `--non-interactive` / fallback mode there is no question: strip + record
   `cmd_bullets_stripped_non_interactive` in `LAUNCH_PAD_RESULT` (additive field, no bump — read
   `validate-launch-pad-result.py` for the additive-field precedent).
5. **`skills/self-heal-advisory/SKILL.md` §safety valve:** correct the comment — `--no-cmd` is passed when
   `NON_INTERACTIVE == true`; on every other path execution is governed by the stamp inside
   `run-ground-truth.sh`; the sentence "so a `cmd:` bullet can NEVER run arbitrary shell with no human in the
   loop" is now backed by §2 and says so with the script name. `agents/supervisor.md` Phase 4.5 pointer
   updated if it restates the valve (grep `no-cmd`).
6. **Docs:** `supervisor-readiness/SKILL.md`, `RESULT_SCHEMAS.md` §"`## Executable Acceptance`", PITFALLS.md,
   CHANGELOG, bump. Re-measure token budgets for `launch-pad`, `plan-reviewer`.

## Non-goals
No change to `corpus-task:` execution (sandboxed to `eval-corpus/`), to `rules-check.sh` (already gated), or to
the advisory nature of `ground_truth` (still never changes `heal_decision`). No attempt to sandbox the command
once approved.

## Acceptance criteria
- A brief with a `cmd:` bullet and no stamp, run through `run-ground-truth.sh --brief` without `--no-cmd`,
  records the check `unverified` / `cmd_unapproved` and executes nothing (test asserts via a bullet that
  would create a sentinel file).
- The same brief with a valid stamp executes it; after editing the bullet, the stamp is stale and it does not.
- `agents/plan-reviewer.md` Criterion 14 says NEEDS_HUMAN for unstamped bullets and lists them verbatim.
- `agents/launch-pad.md` Phase 6 quotes the bullets in the question and names the three options.
- `grep -n 'driven by /autonomous' skills/self-heal-advisory/SKILL.md` → 0 (the false claim is gone).
- Full test loop + root checks green.

## Verified premises
- `run-ground-truth.sh` flags (`--check`, `--brief`, `--checks-file`, `--no-cmd`, `--project`) and its
  bullet-kind classification comment (lines ~41–60).
- `agents/plan-reviewer.md` Criterion 14 text (~261–278) and the Decision Matrix (lone LOW ⇒ PASS).
- `agents/launch-pad.md:482` "NEVER emit `cmd:`"; Phase 5.5 / Phase 6 gates (`autonomous-loop/SKILL.md:197-199`).
- `skills/self-heal-advisory/SKILL.md:390-403`.

## Status: done (PR #252, merge ed2dbcd)
- **Completed:** 2026-09-26T02:14:40Z
- **Brief:** .supervisor/jobs/done/2026-09-22-cmd-valve-by-provenance.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/252
