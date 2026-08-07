---
name: jq-optional-chain-type-trap
description: jq `(.path)?` suppresses path-access errors only — non-string values abort at test()/gsub()/capture(); BUT capture() on a NON-MATCHING STRING emits empty (no error) — `tostring | capture(re)` is safe
metadata:
  type: project
---

In the jq-built gather scripts (pr-postmortem-gather.sh family, single-jq-invocation pattern), `((.user.login)? // "")` does NOT make downstream `test()`/`gsub()` safe: the `?` only guards path-access errors (e.g. indexing a string). A field that EXISTS but holds a non-string (number/bool/object) is truthy, passes `// ""`, and `test()` then errors — aborting the ENTIRE single jq invocation, which converts the whole emit to `{"status":"unavailable","reason":"normalize_failed"}`. Verified live on PR #49 iteration 2: `{"user":{"login":123}}` in the comments array killed the gather despite the header's "comments problem must NEVER turn the gather unavailable" invariant.

**IMPORTANT scope correction (verified empirically 2026-06-13, ST4 review):** the abort class is TYPE errors (regex builtins applied to non-string input). `capture(re)` on a string that simply DOESN'T MATCH emits **empty output, no error** — so `tostring | capture(re)` inside a collect `[...]` is fully safe (non-matching values silently drop out). Don't flag that pattern as an abort risk; probed live against build-insights.sh per-version jq with `rubric_score: 5` (number) — table rendered correctly.

**Why:** the `(…)?` form *looks* like full hardening and the in-code comments claimed it covered untrusted elements; the gap only surfaces with adversarial-but-valid JSON, which no happy-path self-test exercises. The capture-non-match correction matters because over-applying the trap produces false-positive review findings.
**How to apply:** any review of a jq program consuming `--argjson` untrusted arrays — probe with non-string field types (`{"login":123}`, numeric body). Verified safe patterns: `(((.field)? | strings) // "")` for test/gsub inputs; `tostring | capture(re)` for parse-or-drop. Related: [[substring-heuristic-traps]].
