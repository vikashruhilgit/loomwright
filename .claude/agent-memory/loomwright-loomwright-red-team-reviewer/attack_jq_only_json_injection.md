---
name: attack-jq-only-json-injection
description: Every user/PR-text → JSON path in a firing path MUST be jq --arg built (never echo/shell-templated); gate with a quote/backslash/newline round-trip test
metadata:
  type: project
---

Every user/PR-text → JSON path in a firing path MUST be built with `jq --arg`, never `echo '{…}'`/shell-templated JSON.

**Why:** v14 webhook + pr-postmortem gatherer + settings deep-merge all adopted this; the v14 webhook pins a single-quote/backslash/newline round-trip sub-test as a hard merge gate.

**How to apply:** When auditing webhook (`send-webhook.sh`), telemetry (`send-telemetry-core.sh`), pr-postmortem (`pr-postmortem-gather.sh`), or any `gh`/curl call that embeds user/PR text — grep the firing path for `echo '{` or string-interpolated braces. Any shell-templated JSON in a firing path is FATAL by this project's own standard. Test it with input containing `' " \ \n`. (Distinct from jq PARSE-time type traps — see the code-reviewer `jq-optional-chain-type-trap` memory.)
