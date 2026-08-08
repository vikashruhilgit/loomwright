---
name: test-telemetry-cwd-sensitivity
description: test-telemetry.sh MUST run from repo root — run from scripts/ it phantom-fails ~27-30 cases (would_exit=3 everywhere); consent file is $REPO_ROOT-based but core reads $PWD
metadata:
  type: project
---

`test-telemetry.sh` writes the consent fixture to `$REPO_ROOT/.supervisor/telemetry-consent.json` (REPO_ROOT = script-dir/../..) but `send-telemetry-core.sh` resolves `CONSENT_FILE="${PWD}/.supervisor/..."`. The harness never cd's — so invoking the test from `loomwright/scripts/` makes every allow-state fixture resolve to no_consent (`WOULD_EXIT=3`), producing ~27-30 phantom failures (same on main). CI runs from repo root and passes.

**Why:** burned 2026-06-13 (v14.24.0 review): initial suite run from scripts/ showed 30 telemetry failures incl. the 3 NEW plugin_version tests; a main-branch worktree comparison plus a repo-root re-run (117/117 pass) proved all were invocation artifacts, not regressions.

**How to apply:** always run `bash loomwright/scripts/test-*.sh` from the repo root. If telemetry failures all show `actual=3`, suspect cwd before suspecting the diff; cross-check against origin/main in a throwaway worktree before counting failures as new.
