---
name: invisible-control-char-delimiter
description: jq join("\x1F") delimiter renders as join("") in diff/sed/cat — verify delimiter bytes with od -c before flagging idempotency-key collision
metadata:
  type: project
---
`automate-helpers.sh learning_emit` builds its idempotency `automate_key` with `[$a,$b,$c,$d] | join("…")` where the `…` is a literal ASCII Unit Separator (`0x1F`, octal `037`) embedded in the source. `git diff`, `sed -n`, and `cat` render the control byte as nothing, so the line LOOKS like `join("")` (empty delimiter ⇒ field-boundary collision). It is NOT empty — `od -c` shows `j o i n ( " 037 " )`.

**Why:** I nearly filed a HIGH idempotency-collision finding (`run-1`+`bc` vs `ab`+`c` both → `abc`) based on the misrendered `join("")`. The actual `0x1F` delimiter cannot appear in field values, so there is no collision. The in-repo helper that does this is the `learning-emit` subcommand (`scripts/automate-helpers.sh`, the `key=` line ~514).

**How to apply:** when a string-concatenation / join / delimiter looks suspiciously empty or single-char in a diff, dump the exact bytes with `od -c` (or `cat -v`) BEFORE asserting a collision/injection finding. A "NUL-free delimiter" comment next to a seemingly-empty join is a tell that an invisible control byte is intended. Also: a generated runtime sample (`` in jq output) is ground truth over the rendered source. See [[verify-invocation-shapes-from-the-file]].
