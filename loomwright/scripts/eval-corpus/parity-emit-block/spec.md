# Task: parity-emit-block

## What this task asks

Every hook-required result-block field must appear **inside the agent's
actual emit-block template**, not merely anywhere in the prompt file.

This closes the documented blind spot in `check-contract-parity.sh`
Check 1 ("name-presence anywhere in the file, not emit-block membership —
it catches a field deleted entirely … but not one mentioned in prose yet
dropped from the emit format"). A field discussed in prose but missing
from the template the agent copies from will pass the parity gate and
then be rejected by the SubagentStop hook at runtime.

## How it's checked

`check.sh` parses the `MANIFEST` table out of the repo-root
`scripts/check-contract-parity.sh` (deliberately reusing that single
source of field truth rather than adding a fourth parallel table). For
each `matcher|agent|block|fields` row it:

1. Extracts every emit-template region for the block from the agent
   file, in either authoring style: a YAML anchor line (`BLOCK:` plus
   its indented body, captured until dedent or a fence line) or a
   markdown heading (`## BLOCK` plus its `- field:` bullet lines).
   Fence toggling is deliberately **not** used — agent files contain
   unbalanced fences. Multiple template occurrences are unioned.
2. Verifies each required field name appears **as a key line**
   (`field:` or `- field:`) inside that region — a prose mention or a
   word inside another field's comment does not count.

Fail if any agent has no template anchored on its block name, or if a
required field is absent from the emit region while present elsewhere in
the file. Deterministic and read-only.

The eval-mode entry point takes no arguments (repo root resolved via
`git rev-parse --show-toplevel`, which works from the runner's
`cd <task-dir>` convention). `--root <dir>` points the check at a
fixture tree — used by the mutation self-test (delete `heal_decision:`
from a copied supervisor.md template; the check must FAIL).

This is a **maintainer-side** task (like `doc-currency-green`): it
depends on this repo's `scripts/check-contract-parity.sh` and
`loomwright/agents/` and would not pass under an arbitrary user project.
