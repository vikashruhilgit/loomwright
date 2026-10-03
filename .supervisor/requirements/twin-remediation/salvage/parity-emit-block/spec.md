# Task: parity-emit-block

## What this task asks

Every hook-required result-block field must appear **inside the agent's
actual emit-block template**, not merely anywhere in the prompt file.

This closes the documented blind spot in `check-contract-parity.sh`
("name-presence anywhere in the file, not emit-block membership — it
catches a field deleted entirely … but not one mentioned in prose yet
dropped from the emit format"). A field discussed in prose but missing
from the fenced template the agent copies from will pass the parity gate
and then be rejected by the hook at runtime.

## How it's checked

`check.sh` parses the `MANIFEST` table out of the repo-root
`scripts/check-contract-parity.sh` (deliberately reusing that single
source of field truth rather than adding a fourth parallel table). For
each row it:

1. Extracts every fenced code block in the agent file that contains the
   block name (e.g. `SUPERVISOR_RESULT`) — the emit template region.
2. Verifies each required field name appears inside that region.

Fail if any agent has no fenced block naming its result block, or if a
required field is absent from the emit region while present elsewhere in
the file. Deterministic and read-only.
