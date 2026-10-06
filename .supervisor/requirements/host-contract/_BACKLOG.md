# Host contract backlog: let a host (Loomwright Studio) read Loomwright's capabilities and keep its hooks out of the host's repos

**Why now (2026-10-06).** Loomwright Studio (the owner's `loomwright-studio` repo) is a desktop host that runs Claude Agent SDK sessions with Loomwright loaded. Its decision **D32** asks Loomwright to publish a versioned capability contract that Studio reads, instead of Studio parsing Loomwright's files. Loomwright changes fast (22 cached versions, 15.61.0 → 15.123.x), so parsing its internals would break on every release. Studio's probe p9, on 15.123.0, found that Loomwright's hooks write into the repo a session works in: `.claude/settings.local.json` (`env.OTEL_RESOURCE_ATTRIBUTES`), `.supervisor/logs/<session>.jsonl` and a heartbeat file. The owner's own later sessions in that repo read that settings file.

Run with:

```
/automate --backlog .supervisor/requirements/host-contract/_BACKLOG.md
```

Safe mode (no `--auto-merge`): `main` requires an approving review.

**Order (amended 2026-10-06, owner decision "split"):** 01 (the contract) and 02 (host mode in the hooks) are independent and run as two parallel S3 wave-3 lanes. 03 declares host mode in the contract and runs after both merge — done directly, not in this backlog. (An `/automate` run parks after each item's PR until it merges, so a single run of this backlog would stop after 01 and wait for that merge before starting 02.)

**Rules:** follow this repo's `CLAUDE.md`, especially its "Failure-Mode Invariants". Both items are additive. With no host switch set, behaviour is byte-for-byte unchanged. Each item ships a `changelog.d` fragment. **Amended 2026-10-06 (owner decision):** these run as an S3 wave-3 lane, so no item bumps the version; the wave branch carries the one bump (P7). Run alone outside a wave, a release bump follows separately.

- [ ] .supervisor/requirements/host-contract/01-published-capability-contract.md
- [ ] .supervisor/requirements/host-contract/02-host-mode-no-repo-writes.md
