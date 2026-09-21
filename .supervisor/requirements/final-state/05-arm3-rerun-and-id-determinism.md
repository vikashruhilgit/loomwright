# 05 — Arm-3 re-run + Launch Pad id-determinism (Fix 2 remainder, D1, D11)

**OPERATOR-RUN eval — /automate must NOT drive the re-run half** (multi-session, external
`ntfs-tool` repo; same NO-GO class as twin-remediation 07). The id-determinism half IS a normal
code-change item and may be split out and automated.

## Problem
The SDK runner's two blockers are FIXED and MERGED (PR #111: tolerant parser + `materializeWave`).
The CUT verdict in `FABLE_PARITY_EVAL.md` measured the unfinished artifact. Per D1 the runner is
the chosen substrate — fix forward and re-measure. Separately: Launch Pad's id scheme is
non-deterministic across runs (numeric `1–5` vs `1a/1b` from a byte-identical prompt) — a defect
regardless of the runner.

## Goal
An honest second data point for the runner, and deterministic brief ids.

## Scope
1. **Id-determinism (code):** pin Launch Pad's brief format to one id scheme (numeric is what the
   fixtures encode) — emitted, documented in the brief template, and tolerated-but-normalized by
   the parser. Cover with a fixture test.
2. **Arm-3 re-run (operator):** same corpus entry (`ntfs-tool` `03-tree-and-find.md`), same base
   `5df1ded`, `--sdk-runner --multi-voter-heal`. Record as a **second row beside the abort row** —
   the abort row stays (D11: re-runs are second rows; "fix until it passes" must stay visible).
   Headless discipline: `exit 0` is not completion — poll branch/PR; re-invoke with
   `claude -p --resume <id> "Continue"` when Supervisor backgrounds work and yields.
3. If the re-run completes, `--multi-voter-heal` gets its first measurement (record per-layer; it
   is currently UNMEASURED, not cut).

## Non-goals
No new metrics (pre-registration rule; any amendment additive + loud). No corpus expansion here
(that decision is item 06's output).

## Acceptance criteria
- Launch Pad emits deterministic ids; regression test in sdk-spike fixtures or launch-pad surface.
- FABLE_PARITY_EVAL Results gains the arm-3 second row at run time; abort row untouched.
- Per-layer verdict updated (KEEP/CUT/INSUFFICIENT DATA) with cited metrics.

## Outcomes Rubric
- Deterministic id scheme shipped + tested
- Second arm-3 row recorded, abort row preserved
- multi-voter-heal measurement recorded or explicitly still-unmeasured with reason
