---
name: infra-self-test-contract
description: This repo's "QA surface" is shell self-tests + gate scripts, not Playwright; every script needs a co-located static-only test-*.sh
metadata:
  type: project
---
This is a Claude Code plugin (meta-repo), not a web app — there is no UI/API to crawl.
The QA surface is: shell self-tests (`test-*.sh`), golden fixtures, and gate scripts
(check-doc-currency, validate-version, check-command-sync, check-contract-parity).

Fact: CI runs EVERY `ai-agent-manager-plugin/scripts/test-*.sh`, and CI has no Docker
daemon, no network, no `gh`. **Why:** these are external deps unavailable in CI.
**How to apply:** when reflecting on or proposing test coverage here, a new `*.sh`
deliverable is incomplete without a sibling `test-*.sh`, and that test MUST be
static-only (parse YAML/JSON, stub PATH for curl/docker/gh, assert state machines,
never hit the network). See [[golden-fixture-regen]] and [[fail-safe-exit-0]].
