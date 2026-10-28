# Supervisor Job: Per-step provider routing for read-only seats — routing config, user-scoped provider grant, role-aware lens, `/setup providers`

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (0 files), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (11 linked worktrees from other sessions — not orphaned by this run; none on this item's branch)
- **Source requirement:** .supervisor/requirements/provider-routing/03-routing-config-readonly-seats.md
- **Base commit:** b0109dd49f498aa719d06a04a778e18cd53d9337

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe scripts + jq + markdown prompts, the plugin's existing stack; no new dependency |
| 2 | Dependency Availability | GO | `lens-run.sh`, the six `provider-*.sh` table entries, `setup-providers.sh check`, `resolve-egress-config.sh` and every validator's `--raw` mode (`result_block_parser.extract_payload`) already exist on main |
| 3 | Architecture Fit | GO | Consent stays user-scoped (red-team-hardening item 02 pattern); the conductor is not routable; the seat list gets one home (a script), every other surface points at it |
| 4 | Scope vs Supervisor Capability | CAUTION | ~40 files across scripts, a `/setup` module and 17 seat call sites — far past one worker (`context-bound`); split into 7 subtasks, the largest batch 3 wide |
| 5 | Hard Blockers | GO | Items 01 (#724) and 02 (#723) are merged; the only usable non-Claude provider on the owner's machine is `cursor` (read-only seats), which is enough to exercise the routed path in tests via PATH stubs |

**Overall Verdict:** CAUTION

## Task
**Goal:** Let the maintainer route each read-only pipeline seat to a chosen AI CLI through a `.supervisor/config.json` `routing` block, with Claude the default everywhere, a per-repo per-provider grant held only in user scope, a role-aware `lens-run.sh`, and a `/setup providers` module — while a repo with no `routing` block behaves exactly as today.

**Problem Statement:**
The maintainer needs to run review and analysis seats on other models because cross-family second opinions catch different defects, without changing the conductor or letting any repo send code to a vendor the user never approved.
Currently, only the Phase 4.5 multi-voter's second vote can leave Claude (`--voter-provider` / `.voter_provider`), `lens-run.sh` only produces review-shaped `issues[]`, it starts any provider CLI with no consent check, and no `/setup` screen exists for providers. This leaves every other read-only seat Claude-only and the one routed seat unconsented.
Success looks like: every seat listed by `resolve-routing.sh seats` resolves through one resolver, a non-Claude provider runs only with a user-scope grant, a degraded or ungranted route falls back to the Claude path with a named reason, and `/setup providers` renders the probe's verdicts and writes the routing block plus the grant only after an explicit ask.

## Acceptance Criteria

**A. Resolver and config (`routing` block)**
- [ ] AC1 — Given no `routing` key in `.supervisor/config.json` and no per-run flag, when `bash loomwright/scripts/resolve-routing.sh seat <seat>` runs for every id `resolve-routing.sh seats` prints, then each prints `PROVIDER=claude`, `MODEL=` (empty), `SOURCE=default`, `REASON=` (empty) as `KEY=VALUE` lines and exits 0 — the "no `routing` block ⇒ today's behaviour exactly" default.
- [ ] AC2 — Given `routing: {"default": "claude", "on_unavailable": …, "seats": {"<seat>": "<provider>[:<model>]" | ["<provider>[:<model>]", …]}}`, when a seat is resolved, then the value splits on its first `:` into `PROVIDER`/`MODEL`; an array is an ordered preference list (the first entry that is granted AND whose provider CLI is on PATH wins); `on_unavailable` absent reads `fallback_to_default` (owner decision 2026-10-28).
- [ ] AC3 — Given a malformed input, when resolved, then the resolver prints `PROVIDER=claude` with a named `REASON` and never a non-Claude provider: `config_unparseable` (config not exactly one JSON object), `unknown_seat` (a seat key or `seat <id>` argument absent from the `seats` list), `invalid_provider` (a provider name failing `[A-Za-z0-9_-]+` or with no `provider-<name>.sh` file), `routing_default_not_claude` (a `routing.default` other than `claude` — the default stays Claude in this item). Always exit 0 for a known subcommand; a usage error exits 2.
- [ ] AC4 — Given precedence inputs, when seat `heal_voter` is resolved, then the order is `--voter-provider` flag > `--route heal_voter=<p>` > `routing.seats.heal_voter` > `.voter_provider` > default (the back-compatible alias), and for every other seat `--route <seat>=<p>` > `routing.seats.<seat>` > default; `SOURCE` names the winning step (`flag`, `route_flag`, `config`, `voter_provider_alias`, `default`). Each step has its own test leg.
- [ ] AC5 — Given seat `heal_voter` with every input absent, when Supervisor Phase 4.5 runs the multi-voter step, then it spawns the `loomwright:red-team-reviewer` Task exactly as before: `skills/self-heal-advisory/multi-voter.md`'s bullet beginning `` `VOTER_PROVIDER == ""` (the DEFAULT `` is kept verbatim, and `skills/supervisor-config/SKILL.md` step 2.9a records `VOTER_PROVIDER` from `resolve-routing.sh seat heal_voter` (empty when `PROVIDER=claude`).

**B. Consent (user scope only)**
- [ ] AC6 — Given `~/.claude/loomwright/egress.json` with `repos.<slug>.providers: ["cursor"]`, when `resolve-egress-config.sh` runs in that repo, then it prints a new always-present `PROVIDER_GRANTS=cursor` line (comma-joined, each name filtered to `[A-Za-z0-9_-]+`, newline-bearing values blanked by the existing `strip_if_newline`); unreadable / malformed file ⇒ `PROVIDER_GRANTS=` empty; every existing output key is unchanged and the script still always exits 0.
- [ ] AC7 — Given a repo whose `.supervisor/config.json` routes a seat to `cursor` but no user-scope grant, when the seat resolves, then `PROVIDER=claude`, `REASON=provider_not_granted` regardless of `on_unavailable` (a missing grant never sends), and `resolve-egress-config.sh` reports the repo's routed providers only as an informational `REPO_REQUESTED_PROVIDERS=` line that nothing grants from. `claude` never needs a grant.
- [ ] AC8 — Given `lens-run.sh --provider cursor …` with no grant for the repo, when it runs, then it writes `lens_status: "provider_not_granted"` with `issues: []`, creates no sandbox and starts no provider CLI (a PATH-stub sentinel file is never written), and exits 0; with a grant, the existing behavior holds. `--provider claude` skips the grant check.

**C. Unavailable provider**
- [ ] AC9 — Given a granted provider whose CLI is not on PATH, when the seat resolves with `on_unavailable` `fallback_to_default`, then `PROVIDER=claude`, `REASON=provider_unavailable`; with `strict`, then `PROVIDER=` (empty), `REASON=provider_unavailable_strict`, and `docs/PROVIDER_ROUTING.md` states that an empty `PROVIDER` makes the seat take its existing degraded / errored path (never a silent Claude run).

**D. Role-aware lens**
- [ ] AC10 — Given `lens-run.sh --role review`, when it runs, then its output JSON keeps the existing shape (`lens_status`, `provider`, `model`, `issues[]`, `cost: "unknown"`, optional `notes`), and every existing leg of `test-lens-run.sh` keeps its assertions unchanged. The harness, not the script, changes: every leg runs under a scratch `HOME` whose `~/.claude/loomwright/egress.json` grants the stub provider for the test repo's slug, and that slug is pinned hermetically (a scratch repo with a fixed `origin` URL — the mechanism `test-resolve-egress-config.sh` uses). Leg E's scrubbed-child-`HOME` assertion still holds. The grant check runs AFTER the provider-table lookup and the `command -v` availability check, so leg A's `provider_unavailable` stays deterministic, and BEFORE any sandbox work. `lens-run.sh` gets no env-var or flag bypass of the grant: that would be a consent bypass.
- [ ] AC11 — Given `--role <seat>` for any other seat, when it runs, then the role must be registered in `lens-roles.sh` (unregistered ⇒ `lens_unparseable`, notes `unknown role`, no CLI started); a registered role's composed prompt carries that role's output-contract preamble from `lens-roles.sh`, and the output JSON adds `result_text` (the provider's final text, size-bounded) with `lens_status: "ok"` only when `result_text` contains the role's registered marker (else `lens_unparseable`). `cost` is always `"unknown"`, never `0` (D11).

**E. Seats wired**
- [ ] AC12 — Given each seat id that `resolve-routing.sh seats` prints, when its home file is read, then it carries one "Seat routing" paragraph that (a) runs `resolve-routing.sh seat <id>`, (b) on `PROVIDER=claude` runs today's Task / inline path unchanged, (c) on another provider runs `lens-run.sh --role <id>` per `docs/PROVIDER_ROUTING.md` §"Routed seat protocol", validates `result_text` with the same validator the Claude path uses where one exists (`validate-plan-review-result.py --raw`, `validate-code-review-result.py --raw`) or the role marker otherwise, and (d) on any non-`ok` `lens_status` or a failed validation runs the Claude path and logs one `seat_routing <id> provider=<p> reason=<r>` line. The seat ids and their homes: `plan_reviewer` (`agents/launch-pad.md` Phase 5.5), `orchestrator` (`skills/async-orchestration/SKILL.md`), `phase45_reviewer` (`skills/self-heal-advisory/SKILL.md`), `rubric_grader` (`skills/self-heal-advisory/completion-tail.md`), `heal_voter` and `refute` (`skills/self-heal-advisory/multi-voter.md`), `drain_reviewer` (`skills/review-heal/SKILL.md`), `fallback_reviewer` (`skills/review-heal/fallback-review.md`), `evaluate_reviewer` (`skills/autonomous-loop/multi-iteration.md`), `postmortem_classifier` (`skills/pr-postmortem/SKILL.md`), `dreaming_analysis` (`commands/dreaming.md`), `capability_check` (`commands/capability-check.md`), `red_team` (`commands/red-team-reviewer.md`), `code_reviewer` (`commands/code-reviewer.md`), `product_owner` (`commands/product-owner.md`), `qa_strategist` (`commands/qa-strategist.md`).
- [ ] AC13 — Given an inline-command seat (`product_owner`, `qa_strategist`, `red_team`, `code_reviewer`, `dreaming_analysis`, `capability_check`, `postmortem_classifier`), when it is routed, then only the analysis step goes to the provider: every file write, every `AskUserQuestion` gate and every sole-writer call stays on the Claude main thread exactly as today.
- [ ] AC14 — Given the conductor roles (main session, supervisor-runner, execute-manager, context-keeper, worker, the `/autonomous` and `/automate` loops, the detached drain runner, the `TaskCompleted` prompt hook), when `resolve-routing.sh seats` runs, then none of them is listed and `resolve-routing.sh seat worker` prints `REASON=unknown_seat` with `PROVIDER=claude` (write seats are item 04).
- [ ] AC15 — Given `/supervisor --route <seat>=<provider>[:<model>]` (repeatable), when Phase 0 INIT parses it, then it is forwarded to every `resolve-routing.sh seat` call of that run as `--route`; `commands/supervisor.md` documents the flag beside `--voter-provider`. Other commands read config only.

**F. `/setup providers`**
- [ ] AC16 — Given `/setup providers status`, when it runs, then it renders `setup-providers.sh check`'s table and verdicts verbatim (never a hard-coded provider list), plus the resolved per-seat routing from `resolve-routing.sh` and the repo's `PROVIDER_GRANTS`; it writes nothing.
- [ ] AC17 — Given `/setup providers apply`, when it runs interactively, then it offers only providers `check` marked `usable for read-only seats` or `usable for write seats` (a write-seat-usable provider is also usable read-only; `setup-routing.sh` has a test leg for each verdict and refuses any other), writes `.supervisor/config.json`'s `routing` key via `setup-routing.sh` (jq merge, backup-first, parse-gated, atomic, byte-compare idempotent — the `setup-base-branch.sh` write class), and writes the user-scope grant `repos.<slug>.providers` only after an `AskUserQuestion` that names the provider and states what is sent to it (the reviewed diff and the seat's prompt); a declined ask writes no grant. Can't ask ⇒ report and stop, nothing written.
- [ ] AC18 — Given `/setup providers remove`, when it runs, then it deletes the `routing` key and this repo's `providers` grant only (every other key at every level preserved), each backup-first; a second run reports `no-op`.
- [ ] AC19 — Given the `/setup` registry, when `test-setup-module-registry.sh` runs, then `providers` has a Pattern 2 row in `skills/setup/SKILL.md`, a flow part at `docs/command-parts/setup/providers.md`, a `## Parameters` and Usage entry in `commands/setup.md`, a dashboard table row, and is folded into the existing **Other integrations** bucket as status + a pointer to `/setup providers apply` (the dashboard keeps exactly four top-level options; no consent ask runs from the bundle).

**G. Docs and release**
- [ ] AC20 — Given `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, when `git grep -nF 'gemini' -- loomwright/docs/ARCHITECTURE_CONTRACTS.md` runs, then it finds no restated provider list: §"Portability" "Second example" points at the `provider-*.sh` files in `loomwright/scripts/adapters/providers/` instead (handed over from item 02).
- [ ] AC21 — Given the changed prompts, when `scripts/check-token-budget.sh`, `scripts/check-vendor-coupling.sh`, `loomwright/scripts/test-loop-inventory.sh`, `scripts/check-doc-currency.sh` and `scripts/check-version-bump.sh` run, then each passes: every grown file's budget entry and its `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row are raised in the same change, every new install-root reference has a manifest allowance with a reason, every new branch in a loop-inventory source has a row, and a `changelog.d/` fragment describes the change.

**Evidence rule:** every criterion above is checked against the diff and the named tests; none relies on the PR body.

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

**How this brief honors them:** the seat list's one home is `resolve-routing.sh` (its `seats` subcommand prints id, home file, role marker and validator). `docs/PROVIDER_ROUTING.md` and every seat paragraph point at it and never restate the full list or a seat count; the AC12 table above is the brief's checklist, not a committed surface. The provider list stays the `provider-*.sh` files (AC20).

## Design decisions (Launch Pad, from the requirement's "Intended shape" — owner may amend at save)
- **D-a Seat ids** are snake_case and closed in `resolve-routing.sh` (AC12 list). `heal_voter` is the existing voter; `refute` is the multi-voter second-opinion refute check.
- **D-b Array seat values** are an ordered preference list (first granted + installed entry wins), not several parallel lenses.
- **D-c `routing.default`** must be `claude` in this item (AC3); a non-Claude default is item 04 territory.
- **D-d Per-run override** is `/supervisor --route <seat>=<p>` only (AC15); the existing `--voter-provider` stays.
- **D-e Grant key** is `repos.<slug>.providers` (array of provider names) in `~/.claude/loomwright/egress.json`; resolver key `PROVIDER_GRANTS`.
- **D-f Non-review roles** return `result_text` + a registered marker (AC11); the caller validates it with the Claude path's validator (`--raw`) where one exists.
- **D-g Writer split:** `setup-providers.sh` stays check-only (item 02's contract); the new writer is `setup-routing.sh`.
- **D-h Split rule (owner, 2026-10-28):** postmortem, dreaming and propose stay in this item. If, with their seat paragraphs in place, `check-token-budget.sh` cannot pass with a ≤10% headroom raise on those three files, the subtask-6 worker reports it under `deviations` and leaves those three paragraphs out; the owner moves them to a follow-up item.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Touched-file invariants

> Grounded at base `b0109dd49f498aa719d06a04a778e18cd53d9337`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/resolve-egress-config.sh`** — keep: always exit 0 via `trap 'exit 0' EXIT`; fail CLOSED to empty values on an unreadable or malformed user-scope file; the SECURITY CONTRACT that repo-relative values print only under `REPO_REQUESTED_*` keys (`MUST NOT feed REPO_REQUESTED_* into anything that grants consent`); every printed value goes through `strip_if_newline` before printing (newline-forgery defense). reuse: the existing `jq -r --arg s "$REPO_SLUG"` read pattern for the new `providers` key; `case`, never `${var//…}` (bash 3.2 O(n²) trap). mirror: the consumers parse `KEY=VALUE` lines with a naive `while IFS='=' read -r` loop (`send-telemetry-core.sh`, `send-webhook.sh`) — a new key must not change any existing line. pinned by: `loomwright/scripts/test-resolve-egress-config.sh` (`HOME="$H1" bash "$RESOLVER"` hermetic legs).
- **`loomwright/scripts/test-resolve-egress-config.sh`** — keep: every leg runs with a scratch `HOME=` so the real operator's egress.json is never read or written (`harness never reads/writes the real operator's egress.json`); hermetic per `scripts/check-test-hermetic.sh`.
- **`loomwright/scripts/adapters/providers/lens-run.sh`** — keep: every degradation exits 0 through `emit_result` (`# DEGRADATION (four outcomes, ALL exit 0` — becomes five with `provider_not_granted`); the cheapest gate runs first and starts no subprocess (`provider_unavailable` path); the child env is `env -i PATH="$PATH" HOME="$SCRUB_HOME"`; `cost` is `"unknown"`, never `0`; usage errors exit 64 (`exit 64`); provider argv built as an array (`PROVIDER_ARGV`), never `eval`; the SAFETY POSTURE honesty (never call the sandbox "enforced"). reuse: `emit_result` for the new status; source the new `lens-roles.sh` the way the script sources `provider-<name>.sh` (allowlisted name before splicing into a path). mirror: `lens-compare.sh` treats any `lens_status != "ok"` as degraded (`if ($A.lens_status == "ok") and ($B.lens_status == "ok") then "ok"`) — no change needed there; `skills/self-heal-advisory/multi-voter.md` lists the non-ok statuses `(`provider_unavailable`, `lens_mutated_tree`, `lens_unparseable`)` — extend it. pinned by: `loomwright/scripts/adapters/providers/test-lens-run.sh` (`A lens_status=provider_unavailable`).
- **`loomwright/scripts/adapters/providers/test-lens-run.sh`** — keep: every existing leg's assertions unchanged (`A lens_status=provider_unavailable` and the rest); PATH-stub providers (`PROVIDER_NAME="teststub$RUN_TAG"`), no network, hermetic. Change only the harness, per AC10: a scratch `HOME` with an egress.json granting the stub for a pinned scratch-repo slug, so the grant check passes for the legs that expect the CLI to start (D, B, G, C, H, K, F). Add one new leg for `provider_not_granted` (no grant ⇒ the stub's sentinel file is never written).
- **`loomwright/scripts/test-setup-module-registry.sh`** — keep the R/P/U/H/N/S/C/D checks and every mutation control (`D: the dashboard keeps exactly four top-level options`) unchanged; a new mutation control may only be added, never weakened.
- **`loomwright/skills/self-heal-advisory/multi-voter.md`** — keep verbatim the default bullet `` `VOTER_PROVIDER == ""` (the DEFAULT — absent flag AND absent config) — spawn a `loomwright:red-team-reviewer` Task exactly as before ``; keep the refute wording `test-execution-directive-seam.sh` pins (`(c) multi-voter refute: only the code-reviewer-lens refute carries the directive`). pinned by: `loomwright/scripts/test-execution-directive-seam.sh`, `loomwright/scripts/test-loop-inventory.sh` (row SV-516/SV-517 anchors `q: \`VOTER_PROVIDER == ""\``).
- **`loomwright/skills/supervisor-config/SKILL.md`** — keep step 2.9a's precedence prose `flag wins over config` and the empty default `VOTER_PROVIDER = ""`; the base-branch step 2.9b text is untouched.
- **Loop-inventory sources** (`agents/launch-pad.md`, `skills/self-heal-advisory/{SKILL,completion-tail,multi-voter}.md`, `skills/async-orchestration/SKILL.md`, `commands/supervisor.md`, `skills/review-heal/{SKILL,fallback-review}.md`, `skills/autonomous-loop/multi-iteration.md`) — keep every existing `q:`/`h:` anchor line intact (LIVE ANCHORS); a new `###`/`####` heading needs an `h:` row (HEADING COVERAGE) — prefer a bold paragraph label over a new heading. pinned by: `loomwright/scripts/test-loop-inventory.sh` (`FAIL <id>: anchor not found in <file>`).
- **`loomwright/docs/command-parts/setup/dashboard.md`** — keep `The set below is FIXED at four and must NOT be grown when a module is added`; a module from the **Other integrations** bundle prints status + guidance only (the telemetry precedent: `do NOT auto-launch the interactive enable`). pinned by: `loomwright/scripts/test-setup-module-registry.sh` (`D: the dashboard keeps exactly four top-level options`).
- **`loomwright/skills/setup/SKILL.md` / `loomwright/commands/setup.md`** — keep `New modules append a row here AND a flow section in \`commands/setup.md\``; the Subcommands cell is what `/setup --help` prints. pinned by: `test-setup-module-registry.sh` checks P/U/S/C (parity, usage, restating surfaces incl. `README.md` and `docs/command-parts/agent-help/more.md`, count-free).
- **`loomwright/docs/prompt-token-budgets.json` / `loomwright/docs/vendor-coupling-manifest.json`** — keep: budgets = measured + ~10% with the `ARCHITECTURE_CONTRACTS.md` §"Prompt Token Budgets" mirror row changed in the same edit; a manifest allowance raise carries its one-line `allowance_reasons` entry (`To add a reference to a ratcheted path, raise its allowance in the SAME PR`). pinned by: `scripts/check-token-budget.sh`, `scripts/check-vendor-coupling.sh`.

## Closed enumerations touched

> Sibling grep at base `b0109dd`: `grep -rnF 'provider_unavailable' --exclude=CHANGELOG.md loomwright` → 19 hits in 7 files.

- **`provider_not_granted`** (sibling: `provider_unavailable`) — must be named in:
  - `loomwright/scripts/adapters/providers/lens-run.sh` — the OUTPUT SHAPE enum `"lens_status": "ok" | "provider_unavailable" | "lens_mutated_tree" | "lens_unparseable"` and the DEGRADATION list — extend.
  - `loomwright/skills/self-heal-advisory/multi-voter.md` — the non-ok list `(`provider_unavailable`, `lens_mutated_tree`, `lens_unparseable`)` — extend.
  - `loomwright/scripts/adapters/providers/test-lens-run.sh` — legs A/I/J assert the sibling — extend with a new leg for the new value.
  - `loomwright/scripts/adapters/providers/provider-{codex,gemini,cursor}.sh` — header prose naming the sibling as the tested path — no change: not a closed list.
  - `loomwright/scripts/adapters/providers/test-lens-compare.sh` — asserts the sibling on a degraded `provider_b` (`lens-compare.sh` itself branches on `!= "ok"`) — no change: degraded generically.
  - `loomwright/docs/loop-inventory/supervisor.md` — row SV-517 says "any other status ⇒ degrade" (generic, the sibling is not named) — no change for the enum; subtask 4 still updates the row for the new seat-routing branch.
- **`providers`** `/setup` module (sibling: `base-branch`; `grep -rlF '/setup base-branch' --exclude=CHANGELOG.md loomwright README.md` → 11 files):
  - `loomwright/skills/setup/SKILL.md` Pattern 2 registry — extend.
  - `loomwright/commands/setup.md` `## Parameters` + Usage + flow section — extend.
  - `loomwright/docs/command-parts/setup/dashboard.md` status table + bundle option 3 label — extend.
  - `loomwright/docs/command-parts/agent-help/more.md` `/setup` entry — extend.
  - `README.md` "Optional integrations" sentence + Setup row — extend.
  - `loomwright/docs/vendor-coupling-manifest.json` — per-file allowance for the new part — extend.
  - `loomwright/docs/command-parts/setup/base-branch.md`, `scripts/setup-base-branch.sh`, `scripts/test-setup-base-branch.sh`, `scripts/resolve-base-branch.sh`, `scripts/reconcile-jobs.sh`, `skills/supervisor-config/SKILL.md` — the sibling module's own files — no change: not a module list.
- **Seat ids** — a new closed list whose ONE home is `resolve-routing.sh`'s `seats` case arm; no prior sibling.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `loomwright/scripts/test-resolve-routing.sh` — no-grant leg asserts `REASON=provider_not_granted` | delete `provider_not_granted` in `loomwright/scripts/resolve-routing.sh` |
| `loomwright/scripts/test-resolve-routing.sh` — no-routing leg asserts `PROVIDER=claude` / `SOURCE=default` for every seat | flip `SOURCE=default` → `SOURCE=config` in `loomwright/scripts/resolve-routing.sh` |
| `loomwright/scripts/test-resolve-routing.sh` — `heal_voter` alias leg asserts `SOURCE=voter_provider_alias` | delete `voter_provider_alias` in `loomwright/scripts/resolve-routing.sh` |
| `loomwright/scripts/test-resolve-egress-config.sh` — grant leg asserts `PROVIDER_GRANTS=cursor` | delete `PROVIDER_GRANTS=%s` in `loomwright/scripts/resolve-egress-config.sh` |
| `loomwright/scripts/adapters/providers/test-lens-run.sh` — no-grant leg asserts `provider_not_granted` and no stub sentinel | delete `provider_not_granted` in `loomwright/scripts/adapters/providers/lens-run.sh` |
| `loomwright/scripts/adapters/providers/test-lens-roles.sh` — unregistered role leg asserts `unknown role` | delete `unknown role` in `loomwright/scripts/adapters/providers/lens-run.sh` |
| `loomwright/scripts/test-setup-routing.sh` — remove leg asserts every other config key preserved | flip `del(.routing)` → `del(.)` in `loomwright/scripts/setup-routing.sh` |

(The literals named in the Mutation column are required in the code: each subtask's worker writes them as-is so the rows stay machine-applicable.)

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Routing resolver + user-scope provider grant + routing protocol doc | AC1–AC4, AC6, AC7, AC9, AC14 | 2 modify, 3 create | `skills/error-handling/SKILL.md` | LAUNCHABLE |
| 2 | Role-aware `lens-run.sh` + grant check | AC8, AC10, AC11 | 3 modify, 2 create | `skills/error-handling/SKILL.md` | BLOCKED (by #1) |
| 3 | `/setup providers` module + `setup-routing.sh` writer | AC16–AC19 | 6 modify, 3 create | — | BLOCKED (by #1) |
| 4 | Wire Supervisor-family seats (`orchestrator`, `phase45_reviewer`, `rubric_grader`, `heal_voter`, `refute`) + `--route` | AC5, AC12, AC15 (its seats) | 7 modify, 0 create | — | BLOCKED (by #1, #2) |
| 5 | Wire Launch Pad / review-heal / autonomous seats (`plan_reviewer`, `drain_reviewer`, `fallback_reviewer`, `evaluate_reviewer`) | AC12 (its seats) | 6 modify, 0 create | — | BLOCKED (by #1, #2) |
| 6 | Wire inline-command seats (`postmortem_classifier`, `dreaming_analysis`, `capability_check`, `red_team`, `code_reviewer`, `product_owner`, `qa_strategist`) | AC12, AC13 (its seats) | 8 modify, 0 create | — | BLOCKED (by #1, #2) |
| 7 | Budgets, vendor manifest, ARCHITECTURE_CONTRACTS pointer, changelog fragment | AC20, AC21 | 3 modify, 1 create | — | BLOCKED (by #3, #4, #5, #6, #8) |
| 8 | Remediation (owner adjudication B, 2026-10-28): drop the `propose` seat — `/propose` has no LLM-judgment step | AC12, AC14 (seat list) | 5 modify, 0 create | — | BLOCKED (by #1, #2) |

### File Impact Map (lines at base)

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|------------------|-----------------|------------|
| 1 resolver | `loomwright/scripts/resolve-egress-config.sh` (242), `loomwright/scripts/test-resolve-egress-config.sh` (352) | `loomwright/scripts/resolve-routing.sh`, `loomwright/scripts/test-resolve-routing.sh`, `loomwright/docs/PROVIDER_ROUTING.md` | HIGH |
| 2 lens | `loomwright/scripts/adapters/providers/lens-run.sh` (580 — grant check + `result_text` plumbing only; role registry lives in the new module), `loomwright/scripts/adapters/providers/test-lens-run.sh` (626 — only the new `provider_not_granted` leg; role legs go to the new test) | `loomwright/scripts/adapters/providers/lens-roles.sh`, `loomwright/scripts/adapters/providers/test-lens-roles.sh` | HIGH |
| 3 setup | `loomwright/skills/setup/SKILL.md` (294), `loomwright/commands/setup.md` (310), `loomwright/docs/command-parts/setup/dashboard.md` (82), `loomwright/docs/command-parts/agent-help/more.md` (48), `README.md` (770 — one word in the existing "Optional integrations" sentence and Setup row, the surfaces `test-setup-module-registry.sh` S already checks), `loomwright/scripts/test-setup-module-registry.sh` (220 — only if a mutation control needs the new module) | `loomwright/docs/command-parts/setup/providers.md`, `loomwright/scripts/setup-routing.sh`, `loomwright/scripts/test-setup-routing.sh` | HIGH |
| 4 supervisor seats | `loomwright/skills/self-heal-advisory/multi-voter.md` (31), `loomwright/skills/self-heal-advisory/SKILL.md` (415), `loomwright/skills/self-heal-advisory/completion-tail.md` (518 — one paragraph; the routing procedure itself lives in `docs/PROVIDER_ROUTING.md`), `loomwright/skills/async-orchestration/SKILL.md` (422), `loomwright/skills/supervisor-config/SKILL.md` (92), `loomwright/commands/supervisor.md` (235), `loomwright/docs/loop-inventory/supervisor.md` (1294 — the inventory's own single table) | — | MEDIUM |
| 5 LP/review-heal seats | `loomwright/agents/launch-pad.md` (882 — one paragraph at Phase 5.5; procedure in `docs/PROVIDER_ROUTING.md`), `loomwright/skills/review-heal/SKILL.md` (572 — one paragraph; same), `loomwright/skills/review-heal/fallback-review.md` (22), `loomwright/skills/autonomous-loop/multi-iteration.md` (368), `loomwright/docs/loop-inventory/review-heal.md` (414), `loomwright/docs/loop-inventory/launch-pad-autonomous.md` (995 — the inventory's own single table) | — | MEDIUM |
| 6 command seats | `loomwright/skills/pr-postmortem/SKILL.md` (214), `loomwright/commands/dreaming.md` (201), `loomwright/commands/propose.md` (131), `loomwright/commands/capability-check.md` (195), `loomwright/commands/red-team-reviewer.md` (208), `loomwright/commands/code-reviewer.md` (251), `loomwright/commands/product-owner.md` (690 — one paragraph; procedure in `docs/PROVIDER_ROUTING.md`), `loomwright/commands/qa-strategist.md` (445) | — | MEDIUM |
| 7 docs/release | `loomwright/docs/prompt-token-budgets.json` (93), `loomwright/docs/ARCHITECTURE_CONTRACTS.md` (1051 — the §"Portability" pointer + budget mirror rows, both already homed here), `loomwright/docs/vendor-coupling-manifest.json` (790 — the gate's single policy file; allowance entries only) | `changelog.d/provider-routing-readonly-seats.md` | HIGH |

**Module layout:** every new responsibility has one CREATE home — seat resolution `resolve-routing.sh`, the routed-seat procedure `docs/PROVIDER_ROUTING.md`, role contracts `lens-roles.sh` (so `lens-run.sh`, already past 500 lines, gains only the grant check and the `result_text` field), the routing/grant writer `setup-routing.sh` (so `setup-providers.sh`, 447, stays check-only), new test legs in new test files. Large prompt files (`agents/launch-pad.md`, `review-heal/SKILL.md`, `completion-tail.md`, `product-owner.md`) gain one pointer paragraph each, the procedure living once in `docs/PROVIDER_ROUTING.md`. No helper is copied by 2+ siblings: the backup-first jq-merge write is reused by reading `setup-base-branch.sh`'s idiom, the egress write by `commands/telemetry.md` §"If subcommand == `enable`" step 5's recipe.

> **Validator-owned surfaces:** `scripts/check-token-budget.sh` (every grown agent/command/skill file → `prompt-token-budgets.json` + mirror row), `scripts/check-vendor-coupling.sh` (every new `${CLAUDE_PLUGIN_ROOT}` / ask-user reference → `vendor-coupling-manifest.json`), `loomwright/scripts/test-loop-inventory.sh` (the three inventories), `loomwright/scripts/test-setup-module-registry.sh` (the `/setup` restating surfaces), `scripts/check-doc-currency.sh` (no count changes expected — no agent/command/skill is added), `scripts/check-test-hermetic.sh` (every new `test-*.sh` incl. `adapters/*/test-*.sh`). All folded into the map above.

### Subtask Contracts

```yaml
# Subtask 1 — routing resolver + grant + protocol doc (LAUNCHABLE)
provides:
  - {kind: "file", path: "loomwright/scripts/resolve-routing.sh"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-routing.sh", name: "provider_not_granted"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-routing.sh", name: "voter_provider_alias"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-routing.sh", name: "seats)"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-egress-config.sh", name: "PROVIDER_GRANTS"}
  - {kind: "symbol", path: "loomwright/scripts/resolve-egress-config.sh", name: "REPO_REQUESTED_PROVIDERS"}
  - {kind: "file", path: "loomwright/scripts/test-resolve-routing.sh"}
  - {kind: "file", path: "loomwright/docs/PROVIDER_ROUTING.md"}
  - {kind: "symbol", path: "loomwright/docs/PROVIDER_ROUTING.md", name: "## Routed seat protocol"}
requires: []
lanes:
  - "loomwright/scripts/resolve-routing.sh"
  - "loomwright/scripts/test-resolve-routing.sh"
  - "loomwright/scripts/resolve-egress-config.sh"
  - "loomwright/scripts/test-resolve-egress-config.sh"
  - "loomwright/docs/PROVIDER_ROUTING.md"
external_requires:
  - "jq (already a plugin dependency; command -v guarded)"

# Subtask 2 — role-aware lens-run + grant check (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/scripts/adapters/providers/lens-roles.sh"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/lens-run.sh", name: "provider_not_granted"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/lens-run.sh", name: "result_text"}
  - {kind: "symbol", path: "loomwright/scripts/adapters/providers/lens-run.sh", name: "unknown role"}
  - {kind: "file", path: "loomwright/scripts/adapters/providers/test-lens-roles.sh"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/resolve-egress-config.sh", name: "PROVIDER_GRANTS"}
  - {from: "1", kind: "symbol", path: "loomwright/scripts/resolve-routing.sh", name: "seats)"}
lanes:
  - "loomwright/scripts/adapters/providers/lens-run.sh"
  - "loomwright/scripts/adapters/providers/lens-roles.sh"
  - "loomwright/scripts/adapters/providers/test-lens-run.sh"
  - "loomwright/scripts/adapters/providers/test-lens-roles.sh"
external_requires: []

# Subtask 3 — /setup providers + setup-routing.sh (BLOCKED by #1)
provides:
  - {kind: "file", path: "loomwright/scripts/setup-routing.sh"}
  - {kind: "symbol", path: "loomwright/scripts/setup-routing.sh", name: "del(.routing)"}
  - {kind: "file", path: "loomwright/scripts/test-setup-routing.sh"}
  - {kind: "file", path: "loomwright/docs/command-parts/setup/providers.md"}
  - {kind: "symbol", path: "loomwright/docs/command-parts/setup/providers.md", name: "## Module: providers"}
  - {kind: "symbol", path: "loomwright/skills/setup/SKILL.md", name: "`providers`"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/scripts/resolve-egress-config.sh", name: "PROVIDER_GRANTS"}
  - {from: "1", kind: "file", path: "loomwright/scripts/resolve-routing.sh"}
lanes:
  - "loomwright/scripts/setup-routing.sh"
  - "loomwright/scripts/test-setup-routing.sh"
  - "loomwright/docs/command-parts/setup/providers.md"
  - "loomwright/docs/command-parts/setup/dashboard.md"
  - "loomwright/docs/command-parts/agent-help/more.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/commands/setup.md"
  - "loomwright/scripts/test-setup-module-registry.sh"
  - "README.md"
external_requires: []

# Subtask 4 — Supervisor-family seats + --route (BLOCKED by #1, #2)
provides:
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/multi-voter.md", name: "provider_not_granted"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/multi-voter.md", name: "resolve-routing.sh seat heal_voter"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/SKILL.md", name: "resolve-routing.sh seat phase45_reviewer"}
  - {kind: "symbol", path: "loomwright/skills/self-heal-advisory/completion-tail.md", name: "resolve-routing.sh seat rubric_grader"}
  - {kind: "symbol", path: "loomwright/skills/async-orchestration/SKILL.md", name: "resolve-routing.sh seat orchestrator"}
  - {kind: "symbol", path: "loomwright/commands/supervisor.md", name: "--route"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/docs/PROVIDER_ROUTING.md", name: "## Routed seat protocol"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/adapters/providers/lens-run.sh", name: "result_text"}
lanes:
  - "loomwright/skills/self-heal-advisory/multi-voter.md"
  - "loomwright/skills/self-heal-advisory/SKILL.md"
  - "loomwright/skills/self-heal-advisory/completion-tail.md"
  - "loomwright/skills/async-orchestration/SKILL.md"
  - "loomwright/skills/supervisor-config/SKILL.md"
  - "loomwright/commands/supervisor.md"
  - "loomwright/docs/loop-inventory/supervisor.md"
external_requires: []

# Subtask 5 — Launch Pad / review-heal / autonomous seats (BLOCKED by #1, #2)
provides:
  - {kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "resolve-routing.sh seat plan_reviewer"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/SKILL.md", name: "resolve-routing.sh seat drain_reviewer"}
  - {kind: "symbol", path: "loomwright/skills/review-heal/fallback-review.md", name: "resolve-routing.sh seat fallback_reviewer"}
  - {kind: "symbol", path: "loomwright/skills/autonomous-loop/multi-iteration.md", name: "evaluate_reviewer"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/docs/PROVIDER_ROUTING.md", name: "## Routed seat protocol"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/adapters/providers/lens-run.sh", name: "result_text"}
lanes:
  - "loomwright/agents/launch-pad.md"
  - "loomwright/skills/review-heal/SKILL.md"
  - "loomwright/skills/review-heal/fallback-review.md"
  - "loomwright/skills/autonomous-loop/multi-iteration.md"
  - "loomwright/docs/loop-inventory/review-heal.md"
  - "loomwright/docs/loop-inventory/launch-pad-autonomous.md"
external_requires: []

# Subtask 6 — inline-command seats (BLOCKED by #1, #2)
provides:
  - {kind: "symbol", path: "loomwright/skills/pr-postmortem/SKILL.md", name: "resolve-routing.sh seat postmortem_classifier"}
  - {kind: "symbol", path: "loomwright/commands/dreaming.md", name: "resolve-routing.sh seat dreaming_analysis"}
  - {kind: "symbol", path: "loomwright/commands/capability-check.md", name: "resolve-routing.sh seat capability_check"}
  - {kind: "symbol", path: "loomwright/commands/red-team-reviewer.md", name: "resolve-routing.sh seat red_team"}
  - {kind: "symbol", path: "loomwright/commands/code-reviewer.md", name: "resolve-routing.sh seat code_reviewer"}
  - {kind: "symbol", path: "loomwright/commands/product-owner.md", name: "resolve-routing.sh seat product_owner"}
  - {kind: "symbol", path: "loomwright/commands/qa-strategist.md", name: "resolve-routing.sh seat qa_strategist"}
requires:
  - {from: "1", kind: "symbol", path: "loomwright/docs/PROVIDER_ROUTING.md", name: "## Routed seat protocol"}
  - {from: "2", kind: "symbol", path: "loomwright/scripts/adapters/providers/lens-run.sh", name: "result_text"}
lanes:
  - "loomwright/skills/pr-postmortem/SKILL.md"
  - "loomwright/commands/dreaming.md"
  - "loomwright/commands/capability-check.md"
  - "loomwright/commands/red-team-reviewer.md"
  - "loomwright/commands/code-reviewer.md"
  - "loomwright/commands/product-owner.md"
  - "loomwright/commands/qa-strategist.md"
external_requires: []

# Subtask 7 — budgets, vendor manifest, ARCHITECTURE_CONTRACTS pointer, changelog (BLOCKED by #3, #4, #5, #6)
provides:
  - {kind: "file", path: "changelog.d/provider-routing-readonly-seats.md"}
  - {kind: "symbol", path: "loomwright/docs/ARCHITECTURE_CONTRACTS.md", name: "provider-*.sh"}
requires:
  - {from: "3", kind: "file", path: "loomwright/docs/command-parts/setup/providers.md"}
  - {from: "4", kind: "symbol", path: "loomwright/commands/supervisor.md", name: "--route"}
  - {from: "5", kind: "symbol", path: "loomwright/agents/launch-pad.md", name: "resolve-routing.sh seat plan_reviewer"}
  - {from: "6", kind: "symbol", path: "loomwright/commands/product-owner.md", name: "resolve-routing.sh seat product_owner"}
  - {from: "8", kind: "file", path: "loomwright/scripts/resolve-routing.sh"}
lanes:
  - "loomwright/docs/prompt-token-budgets.json"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/vendor-coupling-manifest.json"
  - "loomwright/docs/prompt-history-refs-baseline.json"
  - "loomwright/docs/command-parts/setup/other.md"
  - "changelog.d/provider-routing-readonly-seats.md"
external_requires: []

# Subtask 8 — remediation (owner adjudication requires_gap B, 2026-10-28): drop the `propose` seat (BLOCKED by #1)
# /propose is deterministic scripts end to end (propose-domain.sh classifies), so there is no analysis step to route.
# Remove `propose` from resolve-routing.sh's `seats)` arm, from every test-resolve-routing.sh expectation, and from any
# docs/PROVIDER_ROUTING.md mention; `resolve-routing.sh seat propose` must then print REASON=unknown_seat PROVIDER=claude.
# Also remove any `propose` role from lens-roles.sh / test-lens-roles.sh if subtask 2 registered one.
provides:
  - {kind: "file", path: "loomwright/scripts/resolve-routing.sh"}
requires:
  - {from: "1", kind: "file", path: "loomwright/scripts/resolve-routing.sh"}
  - {from: "2", kind: "file", path: "loomwright/scripts/adapters/providers/lens-roles.sh"}
lanes:
  - "loomwright/scripts/resolve-routing.sh"
  - "loomwright/scripts/test-resolve-routing.sh"
  - "loomwright/docs/PROVIDER_ROUTING.md"
  - "loomwright/scripts/adapters/providers/lens-roles.sh"
  - "loomwright/scripts/adapters/providers/test-lens-roles.sh"
external_requires: []
```

### Per-subtask notes
- **#1** `resolve-routing.sh` subcommands: `seats` (one line per seat: `<id> <home-file> <role-marker> <validator|->`), `seat <id> [--route <seat>=<p>]… [--voter-provider <p>] [--repo <dir>]` (`KEY=VALUE`: `SEAT`, `PROVIDER`, `MODEL`, `SOURCE`, `REASON`, `ON_UNAVAILABLE`). Reads `.supervisor/config.json` (`jq`, `has()`-guarded per the jq-safety lesson), the grant via `resolve-egress-config.sh`'s `PROVIDER_GRANTS`, installed-ness via the provider table's `PROVIDER_CLI_NAME` + `command -v`. Read-only, always exit 0 (usage error 2), bash 3.2 safe. `docs/PROVIDER_ROUTING.md` holds: config shape, precedence, consent rule, the §"Routed seat protocol" (prompt file + empty diff file for non-diff seats, `lens-run.sh --role <id>`, validator `--raw`, fallback + `seat_routing` log line, `strict` ⇒ the seat's degraded path), the "not routable" conductor list, cost honesty — and points at `resolve-routing.sh seats` for the seat list.
- **#2** `lens-roles.sh` maps each seat id to its output-contract preamble and required marker (read each role's own output contract from its `agents/*.md` / command file and quote the marker; `review`, `heal_voter`, `refute` keep the `issues[]` envelope). The grant check runs after the provider-table lookup and before any sandbox work.
- **#3** `setup-routing.sh status|apply --seat <id>=<p>[:<m>]…|--grant <p>…|remove [--repo <dir>]` with `setup-base-branch.sh`'s headline vocabulary (`applied` / `no-op` / `REFUSED (<reason>)` / `ABORTED (<reason>)`, exit 0 on every refusal). It refuses a provider `setup-providers.sh check` did not mark `usable for read-only seats` or `usable for write seats`. The grant write reuses the telemetry enable recipe (backup-first, jq deep-merge, abort on parse failure). Tests use a scratch `HOME`.
- **#4–#6** each seat paragraph is a pointer to `docs/PROVIDER_ROUTING.md` §"Routed seat protocol" (no restated procedure, no seat list, no count). Under Supervisor, a fallback is also recorded with `record_decision`.
- **#7** measure each grown file with `check-token-budget.sh`'s own proxy, set measured + ~10%; mirror rows in the same edit.

## Parallelism Analysis

### Dependency Graph
```
Subtask 1 ──→ Subtask 2 ──→ Subtask 4 ──→ Subtask 7
   │              ├────────→ Subtask 5 ──→ Subtask 7
   │              └────────→ Subtask 6 ──→ Subtask 7
   └─────────→ Subtask 3 ─────────────────→ Subtask 7
```

### File Overlap Matrix

| Group A | Group B | Overlapping Files | Serialize? |
|---------|---------|-------------------|------------|
| Subtask 2 | Subtask 3 | none | NO |
| Subtask 4 | Subtask 5 | none (separate loop-inventory files) | NO |
| Subtask 4 | Subtask 6 | none | NO |
| Subtask 5 | Subtask 6 | none | NO |
| Subtask 3 | Subtask 4/5/6 | none | NO |
| Subtask 7 | 3–6 | none (7 alone owns the budget/manifest/ARCHITECTURE_CONTRACTS files) | ordered by `requires` |

### Batch Plan
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2, Subtask 3 (parallel)
- **Batch 3:** Subtask 4, Subtask 5, Subtask 6 (parallel; 3 may still be running)
- **Batch 4:** Subtask 7
- **Recommended workers:** 3
- **Estimated batches:** 4

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md` |
| 2 | `skills/error-handling/SKILL.md` |
| 3 | `skills/setup/SKILL.md` (Patterns 1–2: check → offer → apply → verify; the registry) |
| 4 | `skills/self-heal-advisory/SKILL.md` (read only the seats' spawn sites) |
| 5 | `skills/review-heal/SKILL.md` |
| 6 | — |
| 7 | — |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): ~40 files and 17 call sites in one PR — reviewer load and Phase 4.5 heal rounds grow with diff size | HIGH | `context-bound` split into 7 subtasks; each seat paragraph is a one-paragraph pointer to one protocol doc, so the review surface is the 4 new scripts + 1 doc |
| An existing `--voter-provider cursor` user without a grant now gets `provider_not_granted` (voter degraded to single-voter) where it used to run | MEDIUM | Intended (requirement: `lens-run.sh` checks the grant before any non-default CLI). Call it out in the changelog fragment with the `/setup providers apply` fix |
| Routed `result_text` from a non-Claude CLI is prompt-injectable via the reviewed diff (lens-run SAFETY POSTURE) and could carry a forged result block | MEDIUM | Same validator as the Claude path (`--raw`); a routed seat is advisory-equivalent to its Claude seat — it never gains a write, merge or ask path (AC13); SAFETY POSTURE stays honest |
| Loop-inventory, token-budget and vendor-coupling gates fail on prompt growth | MEDIUM | Subtask 7 owns budgets/manifest; subtasks 4–5 own their inventory rows; workers run `test-loop-inventory.sh` for their files |
| Seat ids for inline commands do not map cleanly to one "analysis step" (propose is mostly script-driven) | LOW | Seat = the LLM-judgment step only (propose: the `--domain` basis ideation); a command with no such step reports it under `deviations` rather than inventing one |
| Concurrent writers on this checkout (project memory: a concurrent agent runs `git checkout -- <file>`) | LOW | Workers run in worktrees (Supervisor default) |
| Split rule (D-h) fires for postmortem/dreaming/propose | LOW | Worker leaves those paragraphs out and reports `deviations`; owner moves them to a follow-up |

## Configuration
- **Workers:** 3
- **Mode:** parallel
- **Estimated batches:** 4
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-28-provider-routing-readonly-seats.md
```

## Plan Review: PASS (attempt 2/3)

| # | Severity | Section | Description | Resolution |
|---|----------|---------|-------------|------------|
| 1 | MEDIUM | Touched-file invariants | The dashboard.md entry quotes `do NOT auto-launch the interactive enable`, which lives in `docs/command-parts/setup/other.md`, not dashboard.md | deferred |
| 2 | MEDIUM | Subtask Contracts / D-h | If D-h fires, subtask 6's three postmortem/dreaming/propose provides read `missing` at outputs_verified; treat that as the expected deviation, reported to the owner | deferred |
| 3 | LOW | Touched-file invariants | The test-lens-run.sh leg list omits E and D2; AC10's scratch-HOME grant covers every leg except the new provider_not_granted leg | deferred |

## Outcome
- **Status:** completed
- **Completed:** 2026-10-28T13:21:27Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/746
- **Branch:** feature/provider-routing-readonly-seats
- **Files changed:** 44
- **Heal loop ran:** true
- **Heal decision:** PASS
- **Heal iterations:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** 8 subtasks (7 planned + remediation subtask 8 from owner adjudication B dropping the `propose` seat) merged; Phase 4.5 iteration 1 FAIL (2 HIGH: strict heal_voter silent-Claude vote, understated consent text; plus red CI locale-prefix) fixed in 257fddb; iteration 2 PASS at fix floor HIGH. 10 findings dismissed below the floor (posted as the dismissed marker comment). Ground truth 2/2 pass; rules_check none; rules_audit clean; risk_classification high_risk=true (advisory).

## Not verified
- **real cursor-agent end-to-end routed seat** — tests use PATH stubs only (subtask 1)
- **real provider CLIs** — PATH-stub providers only (subtask 2)
- **real provider CLIs** — setup-providers check verdicts stubbed in tests (subtask 3)
- **interactive AskUserQuestion flow** — /setup providers apply grant ask not exercised live (subtask 3)
