---
name: jsonl-appender-accepts-multiline-input
title: jsonl-appender-accepts-multiline-input
description: A JSONL store whose gate validates with json.loads (--line) accepts pretty-printed input; the appender then writes N physical lines and the store fails its own file-mode validator — jq's DEFAULT output is pretty-printed, so the natural producer call triggers it
metadata:
  type: project
source: PR #222 review (verify-helpers.sh evidence-append + validate-verify-evidence.py --line), verified live 2026-09-14
written_at: 2026-10-02T07:21:30Z
head_sha: c594e83
---

When reviewing any "validate-then-`>>`" JSONL appender, pipe `jq -n '{…}'` (no `-c`) into it and check `wc -l` on the store and the file-mode validator afterwards. `json.loads`/`jq .` tolerate inter-token newlines, so line-mode validation passes while the one-fact-per-line invariant, the physical line count and file-mode re-validation all break. Fix is one `tr -d '\r\n'` after validation (raw newlines in valid JSON are always inter-token) or a newline reject in the line-mode gate.
