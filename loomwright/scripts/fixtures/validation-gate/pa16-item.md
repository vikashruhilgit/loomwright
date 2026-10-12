# parallel-automate/16 — machine load guard (fixture: the ## Validation section below is copied verbatim from the requirement)

## Validation (must pass before merge)
- `bash scripts/ci-local.sh` green.
- **Running system:** in a scratch area, start three `ci-local` runs from three clones (two GitHub-origin, one
  local-bare-origin) at once on the owner's machine. Record peak load1 with the guard and the S3 baseline of 119 (no
  rerun of the baseline: that froze the machine). Pass: peak load1 stays below the `overloaded` threshold plus one
  re-check interval of overshoot, and the machine stays responsive (a `date` in a terminal returns within 1 s
  throughout).

## Verified premises (re-check before starting)
