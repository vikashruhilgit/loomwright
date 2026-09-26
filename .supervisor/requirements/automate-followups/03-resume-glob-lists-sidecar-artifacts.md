# 03 — `resume-glob` lists the run's own sidecar artifacts as "incomplete runs"

## Status: pending

> **Origin (2026-09-26).** Surfaced at the close of `/automate` run `automate-2026-09-22-013403`. After the
> run file was stamped `## Status: done`, `automate-helpers.sh resume-glob .supervisor/automate` still printed
> two "incomplete runs":
> - `automate-2026-09-22-013403.review-heal-result.md`
> - `automate-2026-09-22-013403.supervisor-result.md`
>
> These are the transient sidecars §6 steps 2–3 write verbatim, not runs. PR #268 committed them to `main`
> as part of the run trail (`.gitignore` negates `automate/*.md`), so every checkout now carries them.

## Problem
`resume_glob()` iterates `"$dir"/*.md` and prints every file that fails `is_done`. The per-run sidecars
`<run_id>.review-heal-result.md` and `<run_id>.supervisor-result.md` (skill `automate-loop` §6 steps 2 and 3)
share the directory and the `.md` extension, but carry no `## Status:` line, so they are always reported as
incomplete runs.

Effects:
- A bare `/automate` (RESUME first, §4) offers "continue / start new / archive" for files that are not runs.
- Under `--non-interactive-fallback`, more than one "incomplete run" makes the resume **ambiguous** and it
  fails closed (`resume_ambiguous`), so two sidecars alone can block unattended use.

## Goal
`resume-glob` returns only run files. A sidecar never appears, whether it is transient or committed.

## Scope (recommendation, not pre-decided)
- **Option A (smallest):** `resume_glob()` skips any `*.md` that has no `# Automate Run:` title line (the
  run-file template's first line). This covers these sidecars and any future ones, and makes no filename
  assumptions.
- **Option B:** rename the sidecars to a non-`.md` extension (e.g. `.review-heal-result.txt`). Note that
  `.gitignore` then stops tracking them, which may be desired, since they are "transient, overwritten per
  item" per §6.
- Whichever is chosen: update `skills/automate-loop/SKILL.md` §4/§6 wording and
  `scripts/test-automate-helpers.sh` (a fixture dir holding a done run plus both sidecars ⇒ `resume-glob`
  prints nothing).
- Decide separately whether committed sidecars belong in the permanent trail at all.

## Acceptance criteria
- [ ] A fixture dir holding one `## Status: done` run file plus both sidecars ⇒ `resume-glob` prints nothing.
- [ ] A fixture holding one `## Status: paused` run file plus both sidecars ⇒ it prints exactly the run file.
- [ ] Mutation control: removing the new skip makes the first AC print the two sidecars.
- [ ] The full test loop is green.

## Verified premises (read at `main @ e319536`, 2026-09-26)
- `automate-helpers.sh` `resume_glob()`: `for f in "$dir"/*.md; … is_done "$f" && continue; echo "$f"`. There
  is no run-file shape check.
- Live output after run `automate-2026-09-22-013403` was stamped done: exactly the two sidecar paths above.
