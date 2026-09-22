# _BACKLOG — hardening sequence (2026-09-22): ONE `/automate` run across five folders, in dependency order

Run it as ONE backlog-doc source so the engine owns the order and pulls `main` between items:

```
/automate --backlog .supervisor/requirements/_BACKLOG-hardening-sequence-2026-09-22.md --limit 20
```

**Why one run, not three `--folder` runs.** No single-run-per-repo lock exists yet (`grep -n "\.lock\|flock"
loomwright/scripts/automate-helpers.sh` → nothing; `red-team-hardening/06` is what adds it). Three concurrent
runs share one checkout and race — the incident in memory `concurrent-heal-loop-sweeps-uncommitted-edits`.
Until 06 lands, start NO second `/automate` (or `/autonomous`, `/supervisor`) in this repo while this one runs.

**How the resolver reads this file (verified `automate-helpers.sh resolve_backlog`, 2026-09-22 at `8e54942`):**
- Only `- [ ] <path>` lines are enqueued, in file order; `- [x]`, a `✅`, or an inline `## Status: done` marker
  excludes the line. Text after two spaces + `#` is stripped from the payload.
- Paths MUST be repo-root-relative exactly as written here (`.supervisor/requirements/...`) — a `./…` or absolute
  spelling never matches Launch Pad's `Source requirement` pointer and `brief-repair` lands on a `skipped` line
  (`automate-loop/SKILL.md` §6).
- The resolver does NOT read each item file's own `## Status:` stamp (that is `resolve-folder`'s rule). The
  engine stamps the ITEM file `done` at check-off (§6); whether it also ticks THIS doc was not verified — assume
  it does not. **Before any re-intake of this doc, tick every merged item here by hand** (`queue-hygiene/01`
  reconciles item stamps from merged PRs, not this doc).
- `--limit` caps PROCESSED items (default 5); 20 items ⇒ `--limit 20`, or `--resume` after each pause.

**Dependency reasoning (file-touch matrix built 2026-09-22 over all 17 previously queued items + the 3 new):**
- `red-team-hardening/01` rewrites the `dispatch-pr-review.sh` launch line that `six-phase-loop-gaps/02`
  pre-arms ⇒ red/01 before six/02.
- `six-phase-loop-gaps/01`, `/02` and `harness-port/01` all add `agents/worker.md` prose, a WORKER_RESULT
  optional list, a `validate-worker-result.py` rule and a worker budget raise (all three measured the same
  `29 headroom` at `05823bf`) ⇒ serial, each re-measures; cross-queue amendments are in each file.
- `twin-loop/08` reuses the stamp semantics of `red-team-hardening/05` and the user-scope location of `/02`.
- `token-economy/07` shares `/verify` evidence + summary surfaces with `harness-port/04` ⇒ after it.
- In-folder orders are preserved verbatim (red: 01→04, 02→08, 03→06; harness-port: 01→04→06, 02 early, 05→07).
- `queue-hygiene/01` goes first: it makes every `## Status:` stamp after it trustworthy and touches nothing the
  others edit.

## Queue

- [ ] .supervisor/requirements/queue-hygiene/01-reconcile-status-from-merged-prs.md  # stamps become trustworthy
- [ ] .supervisor/requirements/red-team-hardening/01-drain-permission-and-untrusted-text.md  # FATAL 1; rewrites drain launch line
- [ ] .supervisor/requirements/red-team-hardening/02-user-scoped-consent-and-egress.md  # FATAL 2; user-scope location (twin-loop/08 depends)
- [ ] .supervisor/requirements/red-team-hardening/03-gate-eval-self-resolving.md
- [ ] .supervisor/requirements/red-team-hardening/04-drain-wait-and-death-detection.md  # after 01
- [ ] .supervisor/requirements/red-team-hardening/05-cmd-valve-by-provenance.md  # stamp semantics (twin-loop/08 depends)
- [ ] .supervisor/requirements/red-team-hardening/06-cost-ceiling-and-run-lock.md  # after 03; adds the run lock
- [ ] .supervisor/requirements/red-team-hardening/07-mysql-mcp-pin.md
- [ ] .supervisor/requirements/red-team-hardening/08-hardening-sweep.md  # after 02
- [ ] .supervisor/requirements/six-phase-loop-gaps/01-worker-deviations.md  # worker.md raise #1
- [ ] .supervisor/requirements/six-phase-loop-gaps/02-test-integrity-guard.md  # first fail-CLOSED PreToolUse; after red/01; worker.md raise #2
- [ ] .supervisor/requirements/harness-port/01-worker-rules.md  # worker.md raise #3
- [ ] .supervisor/requirements/harness-port/02-not-ready-stamp.md
- [ ] .supervisor/requirements/harness-port/03-cited-line-premise.md
- [ ] .supervisor/requirements/harness-port/04-not-verified-transport.md  # after 01; /verify surfaces (token-economy/07 depends)
- [ ] .supervisor/requirements/harness-port/05-dismissed-findings.md
- [ ] .supervisor/requirements/harness-port/06-shared-local-services.md  # after 01
- [ ] .supervisor/requirements/harness-port/07-ci-trust-probe.md  # after 05
- [ ] .supervisor/requirements/twin-loop/08-executable-rule-candidates.md  # after red/02 + red/05
- [ ] .supervisor/requirements/token-economy/07-verify-spec-replay.md  # after harness-port/04

## Progress
(the engine's run file `.supervisor/automate/<run_id>.md` is the dashboard; tick items above by hand only for a
re-intake)
