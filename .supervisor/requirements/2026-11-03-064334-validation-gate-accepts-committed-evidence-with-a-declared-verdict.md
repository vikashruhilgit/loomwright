# Validation gate accepts committed evidence with a declared verdict

## Status: pending

**Story: Validation gate accepts committed evidence with a declared verdict** (type: story)

**As a** plugin owner whose `/automate` item has a "Running system" Validation step,
**I want** the validation gate to accept a committed evidence file that declares which step it proves and the result,
**so that** a step that was run and recorded parks READY without my waiver, and a waiver again means the step was not run.

### Problem
Two rules disagree about where evidence lives.

- **Evidence goes in a committed file.** That is the rule from #511: `skills/supervisor-readiness/SKILL.md`
  (Evidence rule), Plan Reviewer Criterion 20, and `skills/user-story-writing/SKILL.md` ("Evidence lives in a
  committed file, never the PR body"). The reason is that nothing can edit the PR body after FINALIZE. So
  FINALIZE's `## Evidence` section only links `docs/evidence/*.md` files.
- **The validation gate reads only the PR body.** `validation-gate` and `lane-readiness` share one reader in
  `loomwright/scripts/automate-lanes.d/readiness.sh`. A step passes only when the PR body has a passage for it
  with fenced output, and the gate's remedy (`skills/automate-loop/modes-and-merge-gate.md`, the
  `validation_unrun` bullet) tells the owner to paste output into the PR body.

So every Running system step written the way the evidence rule says parks `validation_unrun`. Run
`automate-2026-11-02-173506` (PR #802) parked on V3 and V4. Both had committed, passing evidence, and the owner
waived both.

Pointing the existing passage reader at the evidence files does not fix this. I measured it (2026-11-03) by
running the reader with each #802 evidence file as the body:

- **V3** reads "mentioned … without pasted output". The `Validation 3` anchor is in the file's title heading,
  and the next heading ends the match before any output.
- **V4** is not matched. The file says `(V4)`, not `Validation 4`.
- **V3's file** also holds 11 lines of expected `decision: FAIL` output (a fixture that should fail). The reader
  reads any `FAIL` word in pasted output as a failed step.

A whole document about one step is not a PR-body passage, so the gate needs to be told what the file proves.

### Non-goals
- Pasting evidence into the PR body. This would reverse #511.
- Changing the waiver. It stays for steps that truly were not run.
- Judging whether the evidence is correct. The gate checks that it is declared and present, as today.
- Changing the PR-body path. Output pasted in the body keeps passing exactly as today.
- Making PR #802's existing evidence files pass. They predate the declared line.

### Owner decisions (2026-11-03)
- **The gate reads an evidence file only through a line the file declares,** naming the step and its result
  (for example `Verdict: PASS for Validation 3`). It never infers either from headings or from words inside the
  output. So expected `FAIL` output in a fixture never fails the step.
- **New files only.** PR #802's two files are not edited. This story's own proof uses a newly written evidence file.

### Acceptance Criteria

**Happy Path:**
- [ ] Given a Running system step, when a `docs/evidence/` file the PR adds or changes declares a passing verdict
      for that step and holds fenced output, then `validation-gate` reads the step as evidenced and names the file.
- [ ] Given that file's fenced output contains the word `FAIL` (expected output of a failing fixture), when its
      declared verdict is a pass, then the step still reads as evidenced.
- [ ] Given a step already evidenced by output pasted in the PR body, when the gate runs, then the result is
      unchanged from today.
- [ ] Given `lane-readiness`, when it reports the validation check for the same PR, then each step's result and
      evidence source match `validation-gate`'s.

**Edge Cases:**
- [ ] Given an evidence file that declares a passing verdict but that the PR does not add or change, when the
      gate runs, then the file is not used.
- [ ] Given an evidence file with no declared verdict line (such as PR #802's), when the gate runs, then the file
      does not evidence any step, and the gate's line says the file has no declared verdict.
- [ ] Given a file declaring a verdict for one step, when the item has two Running system steps, then only the
      declared step is evidenced.
- [ ] Given a declared verdict that is not a pass (a fail, or not run), when the gate runs, then the step reads
      as failed or not run, naming the file.
- [ ] Given a declared passing verdict in a file with no fenced output, when the gate runs, then the step reads
      as not run ("declared but no output").

**Error Scenarios:**
- [ ] Given the PR's changed-file list or an evidence file cannot be read, when the gate runs, then the step reads
      as not run with the reason. The gate fails closed: unreadable never counts as evidence. It still prints one
      line and exits 0.
- [ ] Given a step is not evidenced after both the body and the files are read, when the gate prints `unrun`,
      then its remedy text tells the owner to add the declared verdict line and output to the step's evidence
      file. It never tells them to paste into the PR body.

### Priority
- [x] MVP - Core functionality, must ship

**Rationale:** every future item with a Running system step hits this park. Waiving evidence that exists trains
the owner to waive, which empties the gate.

### Assumptions
- Authors and agents can write one declared verdict line per evidence file when the authoring surfaces ask for
  it. The Evidence rule in `skills/supervisor-readiness/SKILL.md` and `skills/user-story-writing/SKILL.md` teach
  the line in the same change.
- Reading a changed file's contents at the PR head is possible through the gate's existing `gh` seam. Today it
  calls `pr view --json body` and `pr diff --name-only`; reading contents is a new call shape. Launch Pad
  confirms the call and how the test stub supports it.
- The declared line's exact syntax is Launch Pad's choice. It must name the step by its `Validation <n>` number
  and a result word, and one file may declare more than one step.

### Dependencies
- Depends on: none
- Blocks: none
- Shares files with pending items, so it cannot run in the same `--parallel` wave as them:
  `dismissed-followups/03-lanes-and-meta-sync-defects.md` (`readiness.sh`) and
  `dismissed-followups/12-bundle-04ab-drivers-and-gate-tooling.md` (automate-loop docs).
- Supersedes a hand-written draft (deleted 2026-11-03, never shared) that proposed reusing the passage reader;
  the measurement above shows that would not work.

### Risks
- `readiness.sh` is 506 lines. Check it against `skills/supervisor-readiness/SKILL.md` §"Module layout" before
  adding the file reader; a new module may be the better home.
- `test-pr-body-evidence-seam.sh` pins the Evidence rule's text. Teaching the verdict line moves those pins in
  the same change.
- Evidence written before this change keeps parking until it carries the line. This is intended (owner decision).

### Success Metrics
- The next `/automate` item with a Running system step and a declared evidence file parks READY with no waiver.
- `validation_unrun` waivers whose note says "the evidence exists in a file" stop appearing in run files.

### Handoff
Ready for: `/launch-pad goal: ".supervisor/requirements/2026-11-03-064334-validation-gate-accepts-committed-evidence-with-a-declared-verdict.md"`

## Validation (must pass before merge)
1. **Static — gate tests:** `bash loomwright/scripts/test-automate-lanes.sh` covers every acceptance criterion
   above with a stubbed `gh`. Each criterion has a mutation control: the test fails when the file read is
   removed, when the "PR changes the file" filter is removed, and when the FAIL-in-output exemption is removed.
2. **Static — authoring and seam tests:** `bash loomwright/scripts/test-pr-body-evidence-seam.sh` and
   `bash loomwright/scripts/test-requirement-shape.sh` pass, with the verdict line taught in the Evidence rule and
   the story template.
3. **Static — release and suite:** `bash scripts/check-version-bump.sh` passes and
   `bash scripts/ci-local.sh --affected` is green.
4. **Running system — a real READY park with no waiver:** this item's own `/automate` run commits its Validation 4
   output to `docs/evidence/validation-gate-declared-verdict.md`, with a declared verdict line. The gate on this
   item's PR prints `validation-gate: ok`, naming that file, with no `--waive` in the run file's `## Progress`.

## Depends on
none

## Touches
loomwright/scripts/automate-lanes.d/readiness.sh
loomwright/scripts/test-automate-lanes.sh
loomwright/skills/automate-loop/modes-and-merge-gate.md
loomwright/skills/supervisor-readiness/SKILL.md
loomwright/skills/user-story-writing/SKILL.md
loomwright/scripts/test-pr-body-evidence-seam.sh
loomwright/scripts/test-requirement-shape.sh
docs/evidence/validation-gate-declared-verdict.md
changelog.d/validation-gate-declared-verdict.md
