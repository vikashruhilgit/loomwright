# Backlog — af/36 remainder (split 2026-10-12)

## Status: parked (operator-run backlog doc: run it with `/loomwright:automate --backlog .supervisor/requirements/af36-remainder/_BACKLOG.md --parallel 3`)

Split of `automate-followups/36-s3-engine-fixes.md`'s remaining work (Part B item A + Part C) into four PRs, per
that file's 2026-10-12 Re-scope. Parts A and B-B shipped in v15.133.0 (#492); B-C shipped in #438.

Expected waves (plan-waves decides): wave 1 = 01, 02, 04; wave 2 = 03 (depends on 02, shares meta-sync /
setup-memory files). 02 and 03 are security-sensitive — human merge only.

- [ ] .supervisor/requirements/af36-remainder/01-validation-unrun-gate.md
- [ ] .supervisor/requirements/af36-remainder/02-meta-allowlist-grant.md
- [ ] .supervisor/requirements/af36-remainder/04-dreaming-memory-pr.md
- [ ] .supervisor/requirements/af36-remainder/03-meta-sync-learning-stores.md
