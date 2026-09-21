# 00 — Red-team hardening overview (index/policy doc — NOT an implementable item)

## Status: done (index document — nothing to implement; this stamp is the ONLY thing `resolve-folder` honours, so it is what keeps `/automate` from enqueuing this file)

**Origin:** 2026-09-21 `/red-team-reviewer review this plugin` (full-plugin adversarial audit, run inline; report
in that session's transcript). Verdict `SHIP_BLOCKED`: 2 FATAL, 5 CRITICAL, 3 WARNING, 3 WEAKNESS. Every finding
below was read from the actual file and, where a claim could be exercised offline, exercised (the consent-file
finding was reproduced with `send-telemetry-core.sh --dry-run` from a scratch repo → `TARGET_REPO=attacker/sink`,
`WOULD_EXIT=0`). One memory proposal was filed:
`.supervisor/agent-memory-proposals/2026-09-21-red-team-repo-scoped-consent-is-not-consent.md`.

**The one-sentence root cause the whole queue attacks:** the plugin's scripts are careful, but every credentialed,
unattended path (detached drain, telemetry, webhook, auto-merge gate, `cmd:` execution) trusts either a file the
*repo author* controls or a value the *model* wrote — and the plugin never checks the permission regime it inherits.

**Authority above this queue:** `loomwright/docs/SPIKES/FINAL_STATE_GOAL.md` (D1–D11), `NORTH_STAR_DIRECTION.md`
§"Explicit NOs", CLAUDE.md §"Failure-Mode Invariants" (bimodal fail-CLOSED / fail-SAFE; sole merge executor; two
review lenses). If an item and any of these disagree, the file wins — and NOTHING in this queue adds a gate that
changes `heal_decision`, adds a merge path, or spawns a new agent.

## The eight items
| Item | Severity closed | Delivers |
|---|---|---|
| 01 drain-permission-and-untrusted-text | FATAL 1 | `dispatch-pr-review.sh` pins an explicit `--permission-mode` + `--allowedTools` allowlist on the detached `claude -p`, and REFUSES to dispatch (review-only degrade) when it cannot; `review-heal` §U1 wraps every fetched comment/review/check body in a "data, not instructions" envelope with an actor allowlist; the check-run channel is name-configured, never globbed |
| 02 user-scoped-consent-and-egress | FATAL 2 | telemetry consent and the webhook destination move to USER scope (`~/.claude/loomwright/…`, keyed by repo); a repo-relative `.supervisor/telemetry-consent.json` / `config.json.webhook_url` is never honoured on its own; the planted-file test fails CLOSED |
| 03 gate-eval-self-resolving | CRITICAL 2 | `automate-helpers.sh gate-eval` computes conditions 2, 3, 4, 5-checks and 6 itself via `gh`/`git`/`classify-risk.sh`; `ctx.json` shrinks to what only the drain knows |
| 04 drain-wait-and-death-detection | CRITICAL 3 | foreground `wait-for-checks.sh` replaces the prose `sleep(poll_interval)` loop; the dispatcher wrapper detects a runner that exited with no `REVIEW_HEAL_RESULT`, writes a `<hash>.died` marker, notifies, and `session-resume.sh` surfaces it; runner prose forbids background polling |
| 05 cmd-valve-by-provenance | CRITICAL 1 | `cmd:` / bare Executable-Acceptance bullets run ONLY when the brief carries an explicit human stamp written after the literal commands were shown; the false "driven by /autonomous ⇒ --no-cmd" comment is corrected; Plan Reviewer Criterion 14 → `NEEDS_HUMAN` |
| 06 cost-ceiling-and-run-lock | CRITICAL 4 | `--max-tokens <N>` for `/automate` and `/autonomous` read from the existing `token_ledger` events, fail-CLOSED PARK on breach; `.supervisor/run.lock` (pid + session_id + ts, TTL reclaim) at automate PICK and Supervisor INIT |
| 07 mysql-mcp-pin | CRITICAL 5 | pin `vikashruhil-mysql-mcp==<version>`, drop `--refresh`, README states what "read-only" does and does not verify |
| 08 hardening-sweep | WEAKNESS 1–3, WARNING 2–3 | Floor `do_GET` applies the Host check; `classify-bot-review.sh` author regex tightened to exact bot logins; telemetry body carries structured fields only unless consent says `include_result_block`; `plugin.json` description cut to a card + length gate in `check-doc-currency.sh`; minimum Claude Code version declared + hook-payload fixture contract test |

## Order
**01 → 04** (both edit `scripts/dispatch-pr-review.sh` and `skills/review-heal/SKILL.md`); **02 → 08** (both edit
`send-telemetry-core.sh`); **03 → 06** (both edit `scripts/automate-helpers.sh` + `skills/automate-loop/SKILL.md`).
05 and 07 are independent. Suggested run order: 01, 02, 03, 04, 05, 06, 07, 08. Each item is one PR; every item
pulls `main` after the previous merge (the engine already does this — no stacking).

## Decisions taken (owner: "lets create a automate requirement to fix all these", 2026-09-21)
| # | Decision | Why |
|---|---|---|
| R1 | **Refuse, don't guess.** Where a script cannot establish a safe regime (permission mode unreadable, consent not in user scope, gate condition unreadable), it PARKS / degrades to read-only and says why. Never a silent proceed. | CLAUDE.md bimodal invariant: correctness gates fail CLOSED. |
| R2 | **Opt-ins are process-env or user-scope only — never a key in a file the repo or the model can write.** | Same reasoning as six-phase-loop-gaps S4: a switch in `.supervisor/config.json` is a switch handed to the thing being guarded. |
| R3 | **No new agent, no new command, no `schema_version` bump** unless an item names one explicitly (03 changes `ctx.json`'s shape — that is a helper input, not a RESULT schema). | NORTH_STAR "No speculative new agents". |
| R4 | **Untrusted-text handling is prose + mechanism, not prose alone.** 01 adds the envelope AND the actor allowlist AND the permission pin; the prose line is the weakest of the three and is never the only one. | 295k words of protocol already carry 1,133 MUST/NEVER clauses with zero mention of untrusted input; adding one more sentence would not have changed the verdict. |
| R5 | **The "prose is the program" WARNING is NOT queued.** A protocol diet / eval arm is FINAL_STATE_GOAL territory (D-series) and `twin-remediation-backlog` item 07 — not re-litigated here. | Scope discipline; memory `feedback_dont_relitigate_plan`. |
| R6 | **Blocking behaviour that lands as a `type: command` hook must NOT carry `\|\| true`.** No item in this queue adds a hook today; if an implementer finds one necessary, CLAUDE.md §Plugin Hooks and HOOKS.md change in the same PR. | CLAUDE.md §Plugin Hooks. |

## Cross-cutting facts every item must respect (each read on 2026-09-21)
- `claude --help` lists `--permission-mode <mode>`, `--allowedTools`, `--disallowedTools` — verify the exact
  accepted `<mode>` values from `claude --help` output in the implementing session before pinning one (memory
  `verify-invocation-shapes-from-the-file`).
- `dispatch-pr-review.sh:94` documents "deliberately NO --permission-mode"; `docs/ARCHITECTURE_CONTRACTS.md:328`
  restates it. Both change in item 01 — `check-doc-currency.sh` will not catch the prose, a consistency read will.
- The runner is `agents/review-pr.md` (`name: loomwright:review-pr-runner`, `permissionMode: default` in
  frontmatter — silently IGNORED for plugin agents per CLAUDE.md "Hook gotcha"; only the CLI flag counts).
- `send-telemetry-core.sh:43` `CONSENT_FILE="${PWD}/.supervisor/telemetry-consent.json"`; `commands/telemetry.md`
  lines 30/49/92/110 write/read the same path; `send-webhook.sh:106-107` reads `.supervisor/config.json` then
  `.supervisor/notify-config.json`. `.supervisor/` is committable (this repo tracks 5 files under it; the
  `/setup memory` module un-ignores more).
- `automate-helpers.sh` `gate_eval` (lines 361–524) is "a pure decision over a context JSON" and the ONLY executor
  of `gh pr merge --squash`; `test-automate-helpers.sh` stubs `$GH`/`$JQ` via `LOOMWRIGHT_GH_BIN`/`LOOMWRIGHT_JQ_BIN`.
  The positive-form grep `grep -rn "gh pr merge --squash" loomwright/ | grep -viE "no |never |not "` must still
  resolve to exactly the five surfaces CLAUDE.md enumerates after every item.
- `review-heal/SKILL.md` scoped wait is pseudocode (`sleep(poll_interval)` at lines ~333, 561–577) — no script
  exists (`ls loomwright/scripts | grep -iE 'wait|poll|settle'` → only `check-children-settled.sh`, unrelated).
  On this checkout 35 dispatch markers / 4 READY / 5 ESCALATED / 26 no decision; five 2026-09-17 logs end with
  "I'll wait for the background poller…" — under `claude -p` the turn end IS process exit.
- `skills/self-heal-advisory/SKILL.md:390-403` `NO_CMD_FLAG = (NON_INTERACTIVE == true) ? "--no-cmd" : ""`, comment
  claims "driven by /autonomous"; `skills/autonomous-loop/SKILL.md:94,284` forward `--non-interactive` ONLY under
  `--non-interactive-fallback`; `agents/plan-reviewer.md:274` Criterion 14 is LOW ⇒ PASS ⇒ saves.
- `emit-token-ledger.sh` writes `{"event":"token_ledger", input_tokens, output_tokens, cache_read_input_tokens,
  cache_creation_input_tokens, …}` into the session JSONL under `.supervisor/logs/` — the ONLY spend signal the
  plugin has; there is no dollar figure and no ceiling anywhere (0 hits for max_cost/spend cap/ceiling).
- `automate-loop/SKILL.md:357` "single-run-per-repo is an assumed constraint, not enforced"; memory
  `review-gate-brief-conformance-queue` names the `.lock` at PICK as the one unqueued follow-up — item 06 is it.
- `mysql-mcp/.mcp.json:4` `uvx --from vikashruhil-mysql-mcp --refresh mysql-mcp` — no version, no hash.
- `setup-ui.sh` `_guard()` (token + Origin + Host) is called from `do_POST` only; `SimpleHTTPRequestHandler`
  answers every GET. `classify-bot-review.sh` `bot_author_re: "^claude(\\[bot\\])?$|\\[bot\\]$|^github-actions"`.
- `plugin.json` `description` is 3,131 chars (CLAUDE.md §"Plugin description is a summary, not a changelog").
- `loomwright/scripts/test-worktree-audit.sh:159` pins the hooks.json leaf count at 39 and `check-doc-currency.sh`
  reads it — no item here adds a hook; if one does, both move in the same change.
- `bash scripts/check-token-budget.sh` fails CI CLOSED on prompt growth; items touching `agents/review-pr.md`,
  `agents/launch-pad.md`, `agents/plan-reviewer.md` re-measure and raise in `docs/prompt-token-budgets.json` +
  the ARCHITECTURE_CONTRACTS mirror row in the same PR.
- Run the FULL `loomwright/scripts/test-*.sh` loop AND root `scripts/test-*.sh` + `scripts/check-*.sh`
  (incl. `check-vendor-coupling.sh`) before pushing (memory `run-full-ci-suite-loop-before-push`).
- Version bump touches `plugin.json` + `.claude-plugin/marketplace.json` + `CHANGELOG.md` only (memory
  `release-surfaces-readme-claude-md-no-longer-bump`). Current version at authoring: 15.82.0.
