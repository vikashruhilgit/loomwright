# 00 — QA split: remove QA from Loomwright, build a criteria-verdict plugin (plan + decision record)

## Status: done (plan + decision record — owner approved rev 2 on 2026-11-12, rev 3 critique fixes applied 2026-11-12/13 (§14); nothing to implement in this file. Phase 1 items are `01`–`06c` in this folder)

- **Drafted:** 2026-11-12 (rev 1). **Revised:** 2026-11-12 (rev 2), after `/loomwright:red-team-reviewer` returned **SHIP_BLOCKED** on rev 1 (4 FATAL, 7 CRITICAL, 9 WARNING, 5 WEAKNESS). §13 maps every FATAL, CRITICAL and WARNING to where this revision answers it.
- **Evidence this plan rests on:**
  - `reports/AI QA tools plugin research.md` (round 1: tool landscape, benchmarks, the Claude Code ecosystem)
  - `reports/AI QA competitors and lessons.md` (round 2: ~30 tools, what failed and why, build/borrow/avoid)
  - `reports/AI QA mobile and desktop.md` (round 3: the owner's native targets. **Rev 1 did not use it.** It now shapes D17 and the post-MVP order)
  - The notes behind all three, under `research_notes/`
  - Repo facts verified on 2026-11-12 (§2, each with how it was checked)
- **Purpose of this file:** a later reader should be able to see *what* we decided, *why*, and *what we rejected and why*. Every decision row in §4 and every "not doing" row in §7 carries its reason. If a reason stops being true, the decision is open again. Say so in a new owner line; don't silently drift.

---

## 1. The problem, in one paragraph

Loomwright carries a QA subsystem that nobody runs and that costs upkeep everywhere:
- two agents (QA Strategist, QA Executor);
- three commands (`/qa-strategist`, `/qa-executor`, `/verify`);
- six skills (`qa-strategy`, `qa-gates`, `qa-orchestration`, `qa-test-patterns`, `playwright-e2e`, `verify-walkthrough`);
- about a dozen scripts, two SubagentStop hooks, a result-schema family, token budgets, a CI Playwright cache, and nine tracked agent-memory files.

Outside its own files it is referenced from **at least 124 files** (§2). Nothing in Loomwright's delivery loop ever calls any of it.

The valuable part is `/verify`'s per-criterion verdict contract. Close shapes exist (Kane CLI, QA.tech, Revyl, AskUI), but none of them publishes how often its PASS is wrong. Test generation, self-healing and exploratory debate are now done free by Playwright and the agent hosts.

So: rebuild the valuable part as its own plugin, shaped by what the research says works and safe enough to run unattended. Delete the rest.

**The goal is a product, not a refactor.** Success means people, starting with the owner, actually run it, trust its verdicts, and fix things because of them, in any repo, with or without Loomwright. §5a lists what makes or breaks that. §8 says how we find out, in numbers.

## 2. Facts this plan depends on (verified 2026-11-12)

| Fact | How it was checked |
|---|---|
| Only two QA runs ever, both manual, both on `personal/sports-management`: `.qa-summary.md` dated 2026-04-06, `.qa-session/` 2026-07-21 | `find ~/Documents/work -maxdepth 6` for `.qa-session`, `.qa-summary.md`, `.supervisor/verify` |
| Zero `/verify` runs anywhere (no `.supervisor/verify/` dir under `~/Documents/work`) | same `find` |
| Nothing in Supervisor / Orchestrator / Execute Manager / Worker / Launch Pad / `/autonomous` / `/automate` spawns a QA agent or runs `/verify` | grep of `agents/`, `skills/automate-loop/`, `skills/autonomous-loop/`; the only "verify" hits are `verify-provides.sh`, the unrelated `outputs_verified` gate |
| `qa-executor:` Executable Acceptance bullets are recognised but **deferred**: they record `unverified` (`qa_executor_dispatch_deferred_m2b_1b`) and spawn nothing | `run-ground-truth.sh` header (the `qa-executor:` row); `exec-acceptance-lib.sh` `classify_kind` |
| **Any unknown `word:` prefix falls through to `cmd`**: `classify_kind`'s last arm is `*) printf 'cmd\n'`. A `verify:` bullet would today be hashed and treated as a shell command | `exec-acceptance-lib.sh` `classify_kind` |
| Plan Review passes `corpus-task:` / `qa-executor:` / `rule:` bullets **silently**; it flags only `cmd:`/bare ones | `agents/plan-reviewer.md`, the Executable Acceptance criterion's "How" list |
| Ground truth reads **`pass` when ≥1 check passed and zero failed, with deferred/unverified checks allowed alongside**. "1 PASS + 1 can't-tell" renders as a plain pass | `run-ground-truth.sh` header, the `status "pass"` row |
| Ground truth is a **HARD ADVISORY CONTRACT**: it never changes `heal_decision` and **never triggers a fix iteration** | `skills/self-heal-advisory/completion-tail.md`, the ground-truth section |
| **There is no production-host denylist.** `.agent/verify.json` has only `non_prod_assert`: an **unanchored** ERE matched against the `base_url` in the same file, or a `cmd` whose exit 0 passes. Nothing checks the hosts the browser actually reaches (redirects, OAuth, an API on another host). Rev 1 claimed a fail-closed denylist; **that claim was false** | `verify-env.sh` `assert_non_prod` (`grep -Eq -- "$re" <<<"$C_BASE_URL"`); no allow/deny list in `verify-*.sh`, `read-verify.sh` or the skill |
| `bump-version.sh` versions **only** the loomwright plugin. `loomwright-lanes` carries its own hand-set version (0.4.0), but its PRs still add a `changelog.d/` fragment, which folds into **Loomwright's** release | `scripts/bump-version.sh` "HONEST LIMITS"; `git show --stat b685d9f` |
| Removal touches more than the 124 grep hits: `loomwright/capabilities.json`; `.claude-plugin/marketplace.json` (description counts + `qa-strategist`/`qa-executor`/`playwright` keywords); `.github/workflows/ci.yml` (the Playwright pin + cache steps for `test-verify-walkthrough.sh`); and **9 tracked files** under `.claude/agent-memory/loomwright-loomwright-qa-executor/` | grep of each file; `git ls-files .claude/agent-memory` |
| **The owner's apps are mostly not web.** Loomwright Studio (Electron), Flutter mobile apps, Tray POS (Flutter macOS), Block Paradise (Unity Android). The web one is `sports-management` (Next.js + Supabase, with a Playwright config). It lives in `karch4162`'s GitHub account, **whose Actions are billing-blocked** | round-3 report; `ls` + `package.json` of `personal/sports-management`; `git remote -v`; global CLAUDE.md billing note |
| **This repo (atelier) has no UI.** A verdict engine has nothing to walk here | repo layout |
| **We tried a QA extraction once before, and it was rolled back** (§3) | `gh pr list --search selvedge`; `git merge-base --is-ancestor` per merge; PR #158 body |
| Stale competing records still exist: `qa-evolution/` has **10 `## Status: pending`** items (so `/automate` could pick them up); `selvedge-extraction/` says "companion"; branch `feature/relocate-qa-to-selvedge` exists locally and on origin | `grep '^## Status'`; `git branch -a --list '*selvedge*'` |

## 3. The earlier attempt (selvedge), and what it teaches

**What happened:**
- **2026-08-18:** the owner asked to "extract the QA flow into a separate plugin". A 7-slice plan was written: `.supervisor/requirements/selvedge-extraction/`.
- **2026-08-20:** slices 01–03 merged to main:
  - PR #153, a spike on cross-plugin name resolution;
  - PR #155, the `selvedge/` scaffold plus making the CI gates plugin-aware;
  - PR #156, decoupling four Loomwright-side QA couplings.
- **Later on 2026-08-20:** `main` was force-pushed back to its 2026-08-17 state, discarding #153–#156. PR #158 (2026-08-23) re-landed #154 only. The selvedge slices were never re-landed.
- **2026-08-22:** slice 04, PR #157 (the actual relocation, 42 files), was closed unmerged.
- **The goal was different (owner, 2026-11-12).** Selvedge was a *context-reduction refactor*. The rollback is therefore not evidence against this plan.

**Lessons (each shapes a decision in §4):**
1. **Moving code verbatim is the expensive path.** Slice 04 had to land atomically because every CI gate checks the same bytes. → **D3: delete and rebuild.**
2. **A companion that imports Loomwright's assets keeps the coupling.** → **D4: no imports; one CLI + one JSON file.**
3. **It moved a subsystem nobody used.** → **D2: only the evidenced part survives.**
4. **Requirement files went stale.** → **§11: this plan marks what it supersedes, and the stale branch.**

## 4. Decisions — what we do, why, and what we rejected

Rows marked **(rev 2)** changed after the red team. This file is gitignored, so rev 1's wording is not kept anywhere; the reason for each change is in the row itself or in §13.

| # | Decision | Why | Rejected alternatives, and why not |
|---|---|---|---|
| **D1** | **Remove all QA from Loomwright.** No QA agent, command, skill, schema, hook, CI cache or agent-memory dir stays. | Zero `/verify` runs, two manual QA runs ever, no caller (§2). Yet 124+ files carry them through every count/budget/doc gate. | *Wire them into the loop (qa-evolution stories):* wires the half that doesn't work (D2). *Leave them dormant:* the drift cost continues. |
| **D2 (rev 2)** | **The plugin is a criteria-verdict engine: one evidenced PASS / FAIL / BLOCKED / NOT_VERIFIABLE per acceptance criterion.** The Strategist, the Executor's exploration/generation modes, the debate and the 13 audit gates are not carried over. | (a) Of ~30 tools reviewed, none publishes how often its PASS is wrong. Kane CLI, QA.tech, Revyl and AskUI ship close verdict shapes, so the gap is **measured** verdicts, not verdicts as such. (b) WebTestBench (arXiv 2603.25226): unguided exploration stays under 30% F1, and a gold checklist roughly doubles it. **The doubled score is still only ~49%, and a PR description is not a gold checklist.** Criteria help; they don't make the agent reliable. That is why D6/D7 move the verdict off the model (below). (c) The dominant failure is "default-correctness bias": passing because no failure was seen. | *Port the Strategist/Executor pair:* exploratory LLM QA is the least reliable oracle. *Test-suite generator:* crowded; Octomind shut down in 2026. *Exploration swarms:* same oracle problem, at multiples of the cost. |
| **D3** | **Delete in Loomwright, build fresh in the plugin.** Copy ideas and the bits worth keeping (verdict taxonomy, the sign-in pause and its can't-ask branch, evidence-append as sole writer, the Playwright pin reader); no `git mv`. | Selvedge lesson 1. Git history keeps every deleted file. | *`git mv` then rewrite:* pays the atomic-relocation cost. *Frozen copy in Loomwright:* the drift we're removing. |
| **D4 (rev 2)** | **No dependency from the plugin on Loomwright; an optional one the other way.** Loomwright finds the CLI via `SELVEDGE_BIN`, then `command -v selvedge`. If neither resolves it records `unverified` / `verify_plugin_absent`. The plugin ships `selvedge install-cli`, which symlinks the CLI into `~/.local/bin`. | Selvedge lesson 2; same pattern as `loomwright-lanes`. Plugin install paths differ between the desktop app and the CLI (project memory), so neither side may guess a cache path. Whether Claude Code puts a plugin's `bin/` on `PATH` is **unverified**; item 01 spikes it, and if it does, `install-cli` becomes optional. | *Companion model:* shared drift. *Loomwright spawns the plugin's agent via `Task`:* doubled-prefix namespace trap, fails at runtime. *Resolve via `~/.claude/plugins/cache/…`:* wrong on the desktop install. |
| **D5 (rev 2)** | **Playwright is the driver, run by selvedge's own runner from a step plan (D6).** No browser MCP of our own; no free-form LLM-written Node at run time. | CATJudge (arXiv 2609.00081): locator-based programmatic checks beat pixel driving on recall and precision. A step plan keeps that (locators, value reads) while making the run deterministic and safe to run unattended (D15). Playwright runs headless in CI; Claude in Chrome does not. | *Our own browser MCP:* saturated and gets absorbed. *Claude in Chrome / desktop auto-verify:* no CI path. *Computer use / screenshots:* lowest precision; reserved for the `model-judged` evidence class (D9). *Model writes and runs arbitrary `.spec.ts` (rev 1):* that is arbitrary code from a model that read PR-controlled pages, run with the user's privileges (red team F1). Allowed only as an interactive, human-approved escape hatch (D15). *Adopt Playwright Test Agents (planner / generator / healer) as the engine:* they produce tests, not verdicts: no PASS/FAIL/BLOCKED/NOT_VERIFIABLE, no frozen plan the model can't edit, no model-free run, no origin allowlist, no measured false-PASS rate, and their healer re-runs and patches a failing test until it passes (or skips it), which is the self-greening a judge must not do. What we give up: a live-exploring planner (answered by `snapshot --steps`, item 03), free upgrades to their prompts, and a familiar output format (answered by the post-MVP export, P9). They complement selvedge rather than replace it: library upgrades (auto-wait, locators, `ariaSnapshot`, `routeWebSocket`) reach our runner anyway. |
| **D6 (rev 2)** | **Plan and run are separate steps, and only the plan step uses a model.** `selvedge plan` (model) turns criteria into `plan.json`: per criterion, a list of typed steps (`goto`, `click`, `fill`, `select`, `wait_for`, `read`, `expect`) with locators and the expected value. It reads the page only through `selvedge snapshot`, which returns an accessibility snapshot of an allowed host (D12). The plan is written to disk with its **sha256**. `selvedge run` takes the plan, **refuses if its hash differs from the one `plan` recorded**, and executes it with no model in the loop. Evidence is written by the runner process, never by the model. **Revisions (rev 3):** `plan --freeze` is one-shot per run folder and `run` refuses a folder that already ran. A new plan for the same criteria is a numbered revision. Every revision's plan and verdict are kept, and the verdict on record shows the first frozen plan's result next to later ones (`FAIL on plan 1 → PASS on plan 2`), never a bare later PASS. Re-planning after a FAIL is allowed (it can fix a misread criterion); hiding the FAIL is not. The hash catches edits, not re-planning: the revision record is an audit trail, not immutability. **Replay (rev 3):** `selvedge run --replay <frozen-run-dir>` runs a frozen plan again in a new run folder, with no model and zero tokens; this is the regression path. Drift shows as `BLOCKED step_failed` (fixed by re-planning, a new revision) or FAIL, never as a quiet repair. | Rev 1 froze the plan with a PreToolUse hook. That only worked inside the Claude adapter, and the model still wrote both the check and the evidence (red team C4). Moving integrity into the CLI makes it hold everywhere: in a session, in CI, from Loomwright. Devin, Kane CLI, Anthropic's harness post and EvilGenie (arXiv 2511.21654) all say the same thing: write the expectation first, and never let the actor edit it. | *Agent decides checks as it goes:* self-greening. *Hook-only freeze (rev 1):* bypassable, Claude-only, and a user-wide fail-closed hook (W6). *Healing adjusts assertions:* hides real bugs. |
| **D7 (rev 2)** | **PASS needs a value read after the last action, matched to the plan.** `selvedge plan --validate` rejects any criterion whose steps don't end in `read` + `expect` on a property other than existence or visibility (item 03). No read value → NOT_VERIFIABLE. **Negative criteria** ("must not …") must prove the prohibited side effect is absent, not that a UI element is: a baseline read, the action, then a read of the side effect. If the side effect can't be observed → NOT_VERIFIABLE. **Assumptions:** each criterion's plan carries `interpretation` and `unverified_assumptions`; any assumption marked material → NOT_VERIFIABLE, never PASS (the planner decides materiality, so the held-out false-PASS number stays the real check). **FAIL only after a stable-page wait.** Setup, auth and env problems → **BLOCKED**, never FAIL. **Exit-code precedence:** any FAIL → 1; else any BLOCKED → 2; else any NOT_VERIFIABLE → 3; else 0. | WebTestBench's two dominant errors: passing on absence of failure, and failing during async loading. Kane CLI separates test failure from setup failure. A static lint turns the PASS rule into something checked before anything runs. | *Existence-only checks:* already an anti-pattern. *A screenshot judge decides PASS:* triage-grade (85–94% agreement), not oracle-grade; see D9. |
| **D8** | **The verifier runs in its own context, separate from the agent that wrote the code.** | DevAssure, Kane, and Anthropic's own harness post. Same reason Phase 4.5 doesn't trust the worker's report. | *The implementing worker verifies itself:* it checks its own mental model. |
| **D9 (rev 2)** | **Every verdict carries an `evidence_class`: `structured-read` (DOM or semantics value), `in-process-assert`, or `model-judged` (screenshot judgment).** A `model-judged` PASS needs two judgments to agree; disagreement → NOT_VERIFIABLE. `model-judged` is **off by default** and counted separately in every accuracy number. **Two judgments from the same model are a consistency check, not independent judges**, and the README says so. A second model is optional config, never required. | Round 3: some criteria (visual, Unity gameplay) have no other oracle, so the class must exist from the first schema, or adding it later breaks consumers. Bug0's fail-on-disagreement is the only shipped false-PASS guard of its kind. Rev 1 cited Bug0's cross-vendor consensus while forbidding a second key (N1): that contradiction is now stated as a limit instead of hidden (W2). | *Arbiter breaks ties:* hides disagreement. *Require a second vendor key:* onboarding wall (N1). |
| **D10** | **Replay only steps a later assertion confirmed. Never cache assertions. Report every AI fallback during replay as a finding.** | e2e (Apache-2.0) caches only assert-confirmed steps; Midscene and Arbigent never cache assertions; Shortest passes on replay without re-checking. With D6 the run is already model-free; this governs re-planning after a locator breaks. | *Runtime self-healing:* self-greening. *LLM on every step:* slow, costly, non-repeatable. |
| **D11 (rev 2)** | **Auth is scripted and run by the CLI, not the model.** `selvedge auth setup` runs the repo's declared login step, reading credentials from env vars, and writes `storageState` to `~/.local/state/selvedge/<repo-id>/auth/` (mode 0600, outside the repo). Plans refer to secrets only as `{{NAME}}`, resolved by the runner at run time. A human sign-in: interactive → pause and ask; non-interactive → BLOCKED `needs_auth`, never loop. **Honest limit:** a model with a shell can read any file the user can. We keep secrets out of the plan, the evidence, the PR comment and the model's prompt by default. We cannot keep them out of reach of an agent with shell access, and the README says so. | Devin: a scripted login "decreased flakiness dramatically". HN reports agents looping at login walls. Rev 1's "the model never sees a secret" overclaimed (red team C5). Loomwright invariant: every question gate has a named can't-ask branch. | *Agent types credentials:* leaks into traces. *Vendor login for the tool:* onboarding wall. *Claim full secret isolation:* not true with shell access; we state the limit instead. |
| **D12 (rev 2)** | **Target safety is an anchored host allowlist, enforced on every request.** `selvedge.json` lists exact `scheme://host[:port]` origins. Nothing is implied: an empty list allows nothing, and `selvedge env init` writes only a local origin (`localhost`, `127.0.0.1` or `[::1]` with its port). **Enforcement (rev 3) is a local proxy run by the runner**, through which Chromium sends every connection: each HTTP request, each HTTPS `CONNECT` tunnel, each redirect hop and each `ws`/`wss` connection. The proxy checks the **origin (scheme, host, port) of every connection**; for HTTPS/WSS it sees host and port only, never the path or messages, and the docs say so. A connection to an unlisted origin is refused → BLOCKED `host_not_allowed`, naming the host. Local origins match by exact host **and port** (a page on `localhost:3000` cannot reach `localhost:5432`). For a remote origin the proxy resolves DNS itself and refuses a name that resolves to a loopback, private or link-local address, IPv4 or IPv6 (DNS rebinding). The proxy string is built by the runner with no `direct://` fallback and no `bypass` list, and the runner refuses to start when `PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK` is set (Playwright otherwise forces loopback through the proxy). `context.route('**/*')` stays as a second layer. Why a proxy: Playwright calls a route handler only for the first URL of a redirect chain and the browser follows the rest unrouted, and WebSockets need a separate API; route alone cannot keep the browser off production. **Scope: the browser only.** The verifier's shell is not contained (D11's honest limit); no OS firewall in the MVP. A non-local origin needs `"allow_remote": true` plus its exact origin. **Mutating requests** (POST/PUT/PATCH/DELETE) to a non-local origin are refused unless `"allow_remote_mutation": true`. Env hooks (`seed`, `reset`) run only when every listed origin is local. **MVP is web only**; native targets follow round 3's order (§6, after Phase 5). | Rev 1 claimed a "fail-closed production-host denylist" that does not exist (§2). The real `non_prod_assert` is an unanchored regex on a self-declared URL, which `https://shop.example.com/?next=localhost` passes, and it never sees where the browser actually goes (red team F2). Enforcing at the request layer, with an allowlist, is what actually keeps the browser off production. | *Keep `non_prod_assert`:* unanchored and checks a declaration, not traffic. *A denylist of prod hosts:* enumerating badness misses new hosts. *Trust the URL the user gave:* redirects and cross-origin APIs escape it. |
| **D13 (rev 2)** | **Output: one `verdict.json` plus one PR comment carrying text evidence only** (criterion, interpretation and assumptions, steps taken, expected value and whether the read value matched, verdict, plan revision, `evidence_class`, plan hash). **The raw value read from the page is not published by default** (names, addresses and arbitrary text can't be reliably masked); it stays in local evidence, with a per-repo opt-in for private repos that applies configurable redaction patterns. Screenshots and traces stay **local**, in gitignored `.selvedge/evidence/`. Traces are off by default. When on, the runner strips `Cookie`, `Set-Cookie` and `Authorization` headers and `{{NAME}}` values before writing. Nothing is uploaded as a CI artifact by default. | Playwright traces record full headers and bodies, including session cookies, and this repo is public. Rev 1 linked that evidence from the PR comment (red team F3). Text evidence is enough to show the work (P4). QA.tech's single updated comment is still the shape. | *Link traces or screenshots from the PR:* leaks cookies and PII. *Dashboards:* the SaaS game. *A comment per criterion:* noise. |
| **D14 (rev 2)** | **Advisory to Loomwright's merge, always, including through branch protection.** The verdict is never a `gate-eval` condition. In CI the selvedge check concludes **`neutral` on FAIL** by default, so it cannot block even if someone marks it required. A repo owner may opt into `--fail-check` in their own repo, and the docs say this makes it a merge gate there. Loomwright's own repos never set it. **Verdict → ground truth mapping:** all PASS → `pass`; any FAIL → `fail`; anything else → `unverified`, with the BLOCKED/NOT_VERIFIABLE reason carried per check. The ground-truth line **must print the counts** (e.g. `verify 3 PASS · 1 NOT_VERIFIABLE`). Item 09 pins with a test that "1 PASS + 1 can't-tell" never renders as a bare `pass`. | Loomwright invariant: QA is advisory; `gate-eval` has seven conditions and one executor. Rev 1 left a back door: a required check *is* a merge gate (red team W9). The current fold also shows "can't tell" as green (red team C3). | *QA gate in Phase 3.5:* conflicts with the review-lane contract. *Change the global ground-truth fold for all kinds:* bigger blast radius than needed; we fix the rendering for `verify:` checks and leave other kinds alone. |
| **D15 (rev 2)** | **Loomwright calls the plugin from one seam, the Executable Acceptance `verify:` kind, under an explicit trust rule.** What can run, and who approves it: **(a)** the step plan has no shell and only reaches allowlisted origins (D6, D12), so it runs unattended, including under `--no-cmd` / non-interactive `/automate`. **(b)** `selvedge.json` is read from the **base branch** (`git show origin/$BASE:selvedge.json`), never from the PR head, so a PR cannot widen its own allowlist. **(c)** Its shell hooks (`seed`, `reset`, `auth setup`) run only if their sha256 matches a **user-scoped approval** in `~/.claude/selvedge/approvals.json`, keyed by repo. No approval → those hooks don't run → BLOCKED `env_hooks_unapproved`. A repo can request approval, never grant it, the same as Loomwright's telemetry egress consent. **(d)** The free-code escape hatch (D5) never runs unattended. **(e)** `verify:` bullets enter the Executable Acceptance stamp hash. Plan Review lists them at LOW with what they will touch, instead of passing them silently. | **Nothing called the tools, which is why there were zero runs** (§2). A seam gated behind `--no-cmd` would reproduce that zero under `/automate`. A seam that runs PR-controlled shell and model-written code unattended is a remote-code path (red team F1). Splitting "bounded browser steps" from "arbitrary shell" lets the useful part run unattended and keeps the dangerous part behind a human. | *No caller:* the current zero. *Gate the whole seam behind the `cmd:` stamp + `--no-cmd`:* zero usage under `/automate` again. *Read `selvedge.json` from the PR head:* the PR picks its own targets and shell. *Repo-scoped approval file:* a cloned repo would approve itself. |
| **D16 (rev 2)** | **Accuracy is measured on a held-out, third-party known-answer set, by our own harness, and published with its interval.** Definitions, N, the abstention ceiling and the gate are in §6 Phase 2. `claude plugin eval` is optional, for a with/without-plugin comparison only. | Rev 1's "≤5% on a seeded fixture" had no denominator, no N, no ceiling on NOT_VERIFIABLE (answering "can't tell" to everything scored 0%), was self-seeded, and relied on `claude plugin eval`. The red team reports that tool has no custom-code graders and a sandbox that can't read the browser cache under `~` (red team F4; item 07 re-verifies those limits before relying on either way). | *Vendor-style claims:* what we criticise. *Real usage only:* too slow to catch a bad oracle. *Rev 1's seeded set, self-authored:* circular. |
| **D17 (new)** | **The core is target-agnostic from day one: a per-target adapter contract.** Each adapter declares five things: act, read structured state, capture a screenshot, collect logs/crashes, and a preflight that returns ready or a named BLOCKED reason. MVP ships only the web adapter. Schemas carry `target` and `evidence_class` from v1. | Round 3: each native target needs a different **oracle**, not a different driver. Four of the owner's five apps are native. If the first schema is web-shaped, every later target is a breaking change, and the product never reaches the apps the owner actually builds. | *Web-shaped v1, generalise later:* a schema break per target. *Build native adapters now:* breadth before trust (N5). |
| **D18 (new)** | **Root fix in Loomwright: an unknown `word:` prefix in Executable Acceptance becomes `unverified` / `unknown_kind`, never `cmd`.** | Today any typo or rename (`verify:` before its arm exists, `verfy:`) silently becomes a shell command that gets hashed and maybe run (§2, red team C7). Phase 4 and Phase 3 ordering then can't produce that hazard. | *Order the PRs carefully:* prevents only this instance, not the next rename. |
| **D19 (new)** | **Selvedge releases on its own.** It has its own `version` in its `plugin.json` and its own `selvedge/CHANGELOG.md`. A selvedge-only PR carries no `changelog.d/` fragment and never moves Loomwright's version. Item 01 makes `check-version-bump.sh` scope fragments to the loomwright plugin and pins that with a test. | `bump-version.sh` versions only Loomwright, and today a lanes-only PR's fragment folds into Loomwright's release (§2, red team W3). Rev 1's "Loomwright untouched in Phase 1" was false; the honest statement is "the loomwright plugin is untouched; repo release tooling gets one scoped change". | *Ride Loomwright's changelog like lanes:* every selvedge fix bumps Loomwright. |

## 5. The new plugin — target shape

- **Name: `selvedge`** (owner, 2026-11-12). Known clashes:
  - The unscoped npm name is taken, so any published CLI uses a scoped name (`@atelier/selvedge`).
  - `masondelan/selvedge` is an active MIT MCP project in the same audience.
  - The command is `/selvedge:verify`, because a bare `/verify` clashes with other plugins.
  - This is a naming read, not a trademark check.
- **Location: sibling `selvedge/` in the atelier repo** (owner). It has its own small gates and its own release (D19), and it joins none of Loomwright's count/budget gates.
- **Core CLI** (bash + Node/Playwright), the same on every entry path:
  - `selvedge env check`: reads `selvedge.json` (from the base branch when `--base` is given; D15b) and validates the allowlist and approvals. Exit 2 with a named reason when anything is wrong.
  - `selvedge snapshot <url> [--steps <prefix.json>]`: an accessibility snapshot of an allowed origin, optionally after a validated prefix of steps (item 03). The only way the planner sees the page.
  - `selvedge plan`: criteria → `plan.json` + sha256, plus the testability pre-check (vague criteria flagged with a suggested rewrite). Uses a model through `SELVEDGE_PLANNER`. The default is `claude -p` with a fixed prompt and a token budget. In a Claude session, the verifier subagent writes the plan and calls `plan --validate`.
  - `selvedge plan --validate`: static lint (D7: every criterion ends in `read` + `expect`; only typed steps; every origin is allowed).
  - `selvedge run [--replay <frozen-run-dir>]`: hash check, then a deterministic run with no model (`--replay` re-runs a frozen plan in a new folder: the regression path); request routing (D12), stable waits, evidence, redaction.
  - `selvedge verdict`: derives `verdict.json` from the runner's evidence, never from a model summary; exit precedence 1 > 2 > 3 > 0 (D7).
  - `selvedge auth setup` (D11) · `selvedge install-cli` (D4).
  - Every run appends one line to gitignored `.selvedge/runs.jsonl`: time, entry path (`session` / `ci` / `loomwright`), counts per verdict, tokens, duration, plan hash. That is the §8 data source.
- **Schemas** (versioned, `schema_version`): `criteria.json` in; `plan.json`; `verdict.json` out (per criterion: `verdict`, `evidence_class`, `target`, the value read, the expected value, a reason for BLOCKED/NOT_VERIFIABLE, plan hash, Playwright version).
- **Config:** `selvedge.json` at the repo root, committed and owned by selvedge alone. Rev 1 reused `.agent/verify.json`, which would have left a contract shared between two plugins (red team W4). That file has no users (zero `/verify` runs) and is not read.
- **SKILL.md:** how any agent uses the CLI. It is portable to other hosts.
- **Claude Code adapter:** `/selvedge:verify` and a verifier subagent (D8). **No hooks in the MVP.** Plan integrity lives in the CLI (D6). Rev 1's user-wide fail-closed PreToolUse guard would have blocked every Write/Edit in every repo whenever it crashed (red team W6).
- **Borrowed patterns** (only from MIT/Apache sources):
  - e2e's assert-confirmed caching;
  - Midscene and Arbigent's never-cache-assertions rule;
  - Arbigent's stuck-screen detection (→ BLOCKED after N identical snapshots);
  - agent-browser's "fail a click on a hidden or covered target".
- **Ideas only, no code,** from AGPL/FSL projects: Skyvern, Hercules, workflow-use, qodo-cover, Bug0 `@bug0/ai`.

## 5a. Making it a product people use — do / don't

### Do

| # | Do this | Why |
|---|---|---|
| P1 | **First verdict in ≤ 15 minutes on a fresh machine, with no selvedge account or vendor sign-up beyond the user's existing Claude login** (timed in item 06c) | Onboarding friction is the top drop reason. DevAssure (OAuth), Bug0 (two keys + Redis) and Propolis (auth) each put a wall up front |
| P2 | **Take criteria from where they live:** PR description, a markdown list, pasted ticket text | Criteria help (D2), though a PR description is not a gold checklist; P3 exists because of that |
| P3 | **Check the criteria before the app:** flag vague ones and suggest a testable rewrite | Bad criteria produce confident nonsense (Atlassian Rovo grades testability first) |
| P4 | **Show the work:** steps, the value read, the expected value, and for BLOCKED/NOT_VERIFIABLE the reason and what would unblock it | "Can't tell what it checked" is a recurring trust complaint |
| P5 | **One PR comment, updated in place;** summary on top, detail folded | Noisy comments drive people away (Canary) |
| P6 | **Three ways in, one engine:** a session (command + skill), CI (CLI + Action, same-repo PRs only; item 10b), Loomwright (the `verify:` seam) | Meet developers where they are; the desktop app's auto-verify has no CI path |
| P7 | **Scope each run to the change's criteria** | Full exploration costs 0.87M–7.43M tokens per app |
| P8 | **Show cost per run and enforce a budget** → BLOCKED `budget_exceeded` | Token blowups are a repeated complaint. `run` itself spends zero model tokens (D6) |
| P9 | **Regression: replay frozen plans (MVP, item 04); export a passed plan as a plain Playwright `.spec.ts` (opt-in, post-MVP)** | Replay keeps regression a judgement at zero tokens. The export is for teams who want Playwright Test in CI without selvedge (Ranger's stickiest feature; no lock-in), and lets Test Agents' healer maintain it. **Once the healer edits an exported spec it is no longer a selvedge verdict**, and a healer-skipped test is a FAIL signal, never a PASS |
| P10 | **Publish measured accuracy, with its interval and abstention rate** (D16) | The one claim nobody else makes |
| P11 | **Dogfood on a real web app before announcing** (Phase 5: sports-management) | Shipped-but-never-dogfooded is how `/verify` got zero runs |

### Don't

| # | Don't | Why |
|---|---|---|
| N1 | Require Loomwright, a vendor account, Redis or a second model key | Onboarding walls |
| N2 | Run on every PR by default | Noise gets a tool uninstalled; triggering is opt-in |
| N3 | File tickets automatically | A FAIL can *propose* one; a human files it |
| N4 | Ask users to learn a test language | `plan.json` is internal. Users write plain criteria; anything kept is plain Playwright |
| N5 | Expand targets before web verdicts are trusted | Breadth before trust left the old L2–L5 ladder unbuilt. The probe sprint (2b) is research, not adapters |
| N6 | Claim numbers we haven't measured | What we criticise vendors for |
| N7 | Hide BLOCKED and NOT_VERIFIABLE, **or abstain to look accurate** | Honest "can't tell" makes PASS believable, but abstention is capped and counted (Phase 2), so it can't be used to game the score |
| N8 | Put traces, screenshots or request bodies in PR comments or CI artifacts by default | They carry cookies and PII; public repos expose them (D13) |

## 6. Work items (proposed order)

Each item becomes its own requirement file in this folder once the owner approves the plan. **A phase starts only when the previous phase's "done when" holds.** The exceptions are named: Phase 2b runs alongside Phase 2, and Phase 4 may start after Phase 1.

### Phase 0 — owner decisions (no code)
Done 2026-11-12: Q6 (a), Q7 point estimate, rev 2 approved (§12). §11 stamps applied; stale branch deleted.

### Phase 1 — plugin MVP (the loomwright plugin is untouched; repo tooling gets item 01's one change)

| Item | Done when |
|---|---|
| 01 Scaffold `selvedge/` + its own gates + its own release (D19) + CLI discovery (D4) | It installs from the marketplace. Its gates run in CI. A test shows a selvedge-only PR needs no `changelog.d/` fragment and leaves Loomwright's version alone. The spike records whether a plugin `bin/` reaches `PATH` |
| 02 `selvedge.json` + `env check` + the host allowlist (D12) + user-scoped hook approvals (D15c) + base-branch read (D15b) | Tests: a request to an unlisted origin (direct, via redirect, via a cross-origin `fetch`) → BLOCKED `host_not_allowed`. A non-local POST without `allow_remote_mutation` is refused. A PR-head edit to `selvedge.json` has no effect with `--base`. Unapproved hooks → BLOCKED `env_hooks_unapproved` |
| 03 `snapshot` + `plan` + `plan --validate` + testability pre-check + criteria inputs (PR text, markdown, pasted ticket) | A criterion without a final `read` + `expect` is rejected. A vague criterion comes back flagged with a rewrite. The three inputs give the same plan for the same criteria |
| 04 `run` + `verdict` + run log | Tests: an edited plan (hash mismatch) is refused. No read value → never PASS. The exit precedence holds over mixed verdicts. Traces with `Cookie`/`Authorization` come out stripped. `run` makes zero model calls |
| 05 Auth (D11) | A non-interactive run behind a login wall exits 2 `needs_auth` and never loops. `storageState` is written outside the repo with mode 0600 |
| 06 Claude adapter (command + verifier subagent) + PR comment (text-only, updated in place) | Re-running updates the same comment. The comment has no links to traces or screenshots |
| 06c Quick start, timed | A fresh machine reaches a first verdict on the sample app in ≤ 15 minutes with no sign-up beyond the user's Claude login, and the time is recorded |

### Phase 2 — measurement (time-boxed: 3 weeks; at most two engine revisions)

| Item | Done when |
|---|---|
| 07 **Known-answer set.** Sources: (a) defects written by a **separate session with no access to selvedge's source or prompts**, into a fixture web app; (b) **real bugs from `sports-management`'s history**: check out the parent of each bug-fix commit and take the criterion from that PR. At least **100 defect criteria** (known answer FAIL) and **100 non-defect criteria** (known answer PASS). Split **tuning 40% / held-out 60% by underlying defect, not by criterion** (every criterion from one bug lands on the same side; criteria from one bug are correlated); the held-out answers are never shown to the engine's builder. Also re-verify the reported `claude plugin eval` limits | Both sets exist with an answers file; the split is recorded; the author session is named |
| 08 **Harness + gate** (`selvedge/eval/`, our own script comparing `verdict.json` to the answers). Reported on the **held-out** set, once per engine version: **false-PASS rate** = PASS verdicts on known-FAIL criteria ÷ all known-FAIL criteria; **false-FAIL rate** the mirror image; **abstention rate** = BLOCKED + NOT_VERIFIABLE ÷ all criteria; each with its **Clopper-Pearson 95% interval**. `model-judged` verdicts reported separately; results also grouped per defect and per app. **Repeatability, two numbers reported apart:** planner variance (3 fresh plans of the held-out set) and runner variance (3 `--replay`s of one frozen plan set); flips are reported on their own and the runs are not extra samples | **Gate to Phase 3:** false-PASS ≤ 5% (point estimate, Q5) **and** abstention ≤ 20%, with the interval published in the README. **Missing the gate never means "abstain more"** (rev 1's remedy, removed). After two revisions without meeting it, stop and run the §8 review early |

Why these numbers: with 20 known-FAIL criteria and one miss, the 95% interval runs from 0.1% to 24.9%, which is useless. With ~60 held-out known-FAIL criteria, 3 misses (5%) gives an upper bound of 13.9%. To *prove* ≤ 5% at 95% confidence takes 0 misses in 72, or ≤ 2 in ~135 (Q7).

### Phase 2b — native probe sprint (alongside Phase 2; research only, no selvedge adapter code)
Run round 3's probes: Tray POS AX tree, Unity accessibility nodes, Electron fuse/version, Flutter semantics coverage, TCC preflight, mobile-mcp privacy, vision false-PASS. **Done when:** each probe has a recorded result and the post-MVP target order (below) is confirmed or changed by an owner line. Why now: four of the owner's five apps are native, so the probes decide whether the product reaches them. They are cheap, and three of them decide whole branches of the architecture.

### Phase 3 — the Loomwright seam

| Item | Done when |
|---|---|
| 09 Loomwright: **D18** (unknown prefix → `unverified`/`unknown_kind`); a `verify:` arm calling the CLI (D4 discovery, D15 trust rule); `qa-executor:` kept as an **alias of `verify:`** so no existing bullet changes meaning; `verify:` bullets in the stamp hash; Plan Review lists them at LOW; ground-truth line prints the counts (D14) | Tests: `frobnicate: x` → `unknown_kind`, never run. Plugin absent → `verify_plugin_absent`. 1 PASS + 1 NOT_VERIFIABLE never renders as bare `pass`. `gate-eval` is untouched (still seven conditions) |
| 10 Launch Pad writes `verify:` bullets for UI-facing criteria; the PR body shows the verdict counts | A brief with a UI criterion gets a `verify:` bullet; a FAIL shows as an advisory Phase 4.5 finding |
| 10b CI entry: a GitHub Action on **`pull_request` only** (never `pull_request_target`), same-repo PRs only (fork PRs skipped with a note); the check concludes `neutral` on FAIL unless `--fail-check` (D14); no artifacts uploaded (D13). **Hook approval in CI:** `~/.claude/selvedge/approvals.json` does not exist on a hosted runner, so CI hooks read an admin-set repository variable holding the hooks' sha256. That is an approval signal only inside a workflow the repo trusts: `pull_request` runs the workflow from the PR's merge commit, so a same-repo PR author can edit the workflow and skip or fake the check. Same trust as merging code; the docs state the limit and never call it protection | A sample same-repo PR shows the check and one comment. A fork PR runs nothing with secrets |

### Phase 4 — remove QA from Loomwright (may start after Phase 1, per Q4)

| Item | Done when |
|---|---|
| 11a **Removal manifest:** an explicit, committed list of every path and every named reference to remove or re-point, generated once and reviewed. It includes `capabilities.json`, `marketplace.json` (counts + keywords), `ci.yml` (the Playwright pin/cache steps), and the 9 tracked agent-memory files. The list replaces "grep returns nothing" as the done-check. Before 11b, tag `main` as `pre-qa-removal` and write a short rollback note (which tag to restore from, what to re-add) | Each later item is checked against the manifest, entry by entry |
| 11b Delete: 2 agents, 3 commands, 6 skills, the QA/verify scripts and tests, the two SubagentStop matchers, the schema docs, token-budget entries, `QA_SYSTEM_BLUEPRINT.md`, the CI Playwright cache steps, the agent-memory dir. **Keep `classify_kind`'s `qa-executor` arm** until item 09 lands (or D18 has landed) | Every manifest "delete" entry is gone. `ci-local.sh --affected` green, CI green. `check-doc-currency.sh` counts match |
| 12 Re-point the coupled files per the manifest: agent-help, dreaming (`--agent qa-executor` removed), the notify/webhook/telemetry/routing/token-ledger name maps, `classify-risk.sh` trusted paths (swap `.agent/verify.json` → `selvedge.json`), `/propose --from-verify` (reads selvedge's `verdict.json`), setup, handoff, rules, docs | Each re-pointed surface has a test that fails if the old name comes back |
| 13 Migration note via `changelog.d/` + a rationale doc in `loomwright/docs/rationale/` pointing here | A `/qa-executor` user reading the changelog knows what replaced it and why |

This is a multi-PR change touching well over 124 files (the red team counted ~184; item 11a produces the real number), not "one small release" as rev 1 implied (red team C7). Items 11b and 12 may be split per surface, each green on its own. `verify-provides.sh`, the `outputs_verified` gate, `unit-testing` and `quality-checklist` are not QA and stay.

### Phase 5 — dogfood and the keep/kill review (60 days after item 09 ships)

| Item | Done when |
|---|---|
| 14 Use it on **sports-management** (web; local Next.js + a local Supabase, so every origin is localhost). Run from a session and through `/automate` on that repo. **Not CI there:** `karch4162`'s Actions are billing-blocked. **Not this repo:** atelier has no UI | `.selvedge/runs.jsonl` holds the 60 days of runs |
| 15 Keep/kill review against §8 | Owner line recorded: keep, reshape, or remove |

### After Phase 5 (only if the review says keep), in round 3's order, adjusted by the Phase 2b probes
1. Export a passed frozen plan as a plain Playwright `.spec.ts` (P9): emits role/label/text/test-id locators and `expect`s from the plan, `{{NAME}}` as `process.env`, and a header naming the plan sha256. Healer edits make it no longer a selvedge verdict; a healer skip is a FAIL signal.
2. **Electron** (Loomwright Studio) via Playwright `_electron`, behind a fuse/version preflight.
3. **Flutter mobile** via Maestro on an Android emulator (Maestro's AI commands not used), then iOS simulators.
4. **Tray POS** (Flutter macOS) via generated `flutter test integration_test -d macos`; AX driving only if its probe passed.
5. **Block Paradise** (Unity) via an owner-added dev-build state readout; `model-judged` only for inherently visual criteria.

Each step ships with its fixtures and its false-PASS number before the next starts.

## 7. What we are NOT doing — and why (read this before proposing any of it)

| Not doing | Why not |
|---|---|
| A browser, mobile or desktop driver or MCP server | Free, saturated, absorbed (maestro-mcp archived) |
| Test-suite generation as the product | Playwright's agents do it free; Octomind shut down. A suite is a by-product: replay of frozen plans (MVP) and a `.spec.ts` export (post-MVP, P9) |
| Runtime self-healing | Self-greening hides real bugs |
| A model in the run loop | Non-repeatable and costly, and it lets page content steer the verdict. The model plans; the runner runs (D6) |
| **Running model-written code or PR-controlled shell unattended** | A remote-code path through the PR (red team F1). Bounded step plans run unattended; shell hooks need user-scoped approval; free code only with a human (D15) |
| **Reading `selvedge.json` from the PR head** | The PR would choose its own targets and shell (D15b) |
| **`pull_request_target`, or uploading traces/screenshots** | Secret exposure on fork PRs; cookies in public artifacts (D13, item 10b) |
| A regex or denylist as the production guard | Unanchored and checks a declaration, not traffic (D12) |
| Exploratory agents or swarms as the verdict source | Least reliable oracle (< 30% F1) |
| Porting Strategist + Executor, the debate loop, the 13 gates | Unused, and the generation/exploration half is now free or unreliable |
| A screenshot judge as a default PASS oracle | Triage-grade. Allowed only as labelled `model-judged`, off by default, two agreeing judgments, counted separately (D9) |
| Our own user-facing test format | Lock-in. `plan.json` is internal; anything kept is plain Playwright |
| Cloud runner, dashboards, hosted reports | That's SaaS's game |
| Redis, a required second key, a vendor login | Onboarding walls |
| A user-wide fail-closed hook | One crash blocks every edit in every repo (D6, red team W6) |
| Native targets in the MVP | Different oracles; probes first (Phase 2b), adapters after Phase 5 |
| Any Loomwright merge block, including via a required check | Invariant; the check is `neutral` on FAIL by default (D14) |
| A companion that imports Loomwright assets, or a shared config file | The coupling that made selvedge expensive (§3, D4, §5 config) |
| Code from AGPL or FSL projects | Licence |
| The qa-evolution stories as written | They evolve the lane this plan removes (§11) |
| "Prefer NOT_VERIFIABLE" as an accuracy fix | Abstaining games the false-PASS number; abstention is capped (Phase 2) |

## 8. How we'll know it earns its keep (and when to kill it)

Measured at the Phase 5 review. Data source: `.selvedge/runs.jsonl` on sports-management, the PRs' git history, and the Phase 2 harness.

| Measure | Keep if | Kill or reshape if |
|---|---|---|
| Verdict runs on sports-management in 60 days | ≥ 10 | < 3: it isn't being used; find out why before anything else |
| FAILs acted on: a fix commit, or a corrected criterion, on the same PR after the FAIL | ≥ 2 | 0: it finds nothing that matters (or Q6 needs the other answer) |
| Held-out false-PASS (Phase 2 harness, latest engine version) | ≤ 5% point, interval published | > 5% on two consecutive versions |
| Abstention (BLOCKED + NOT_VERIFIABLE) on real runs | ≤ 30% by day 60 | > 50%: setup or criteria quality is the real problem (P2/P3/D11) |
| Model tokens per criterion (planning; `run` spends 0) | Median reported and ≤ the per-run budget | Median grows release over release |
| Fresh-machine time to first verdict | ≤ 15 min, no sign-up beyond the Claude login | > 30 min: fix onboarding first |
| Runs started outside Loomwright | ≥ 30% of runs | < 10%: it's a Loomwright feature, not a product; judge it as one |
| Independent outside use | ≥ 1 developer outside this repo installs it themselves, runs it on their own project on ≥ 2 separate days, and says whether they'd keep using it | None by day 60: judge it as a personal tool, not a product |

## 9. Risks

- **Web-only MVP reaches one of the owner's five apps.** This is the biggest adoption risk, because it repeats the "built but never used" pattern (red team C2). Mitigations: D17 keeps the core target-agnostic; Phase 2b settles the native path early; §8's usage floor is measured on the one web app that exists, not on this UI-less repo.
- **Playwright adds a verdict mode.** Test Agents evolving toward more autonomy (a healer that fixes more) is the direction a judge avoids, so it doesn't make selvedge obsolete; a mode that issues verdicts against acceptance criteria would. Watch-listed, re-checked at Phase 5.
- **Plan-time exploration changes app state.** `snapshot --steps` (item 03) really clicks; an approved `reset` hook runs before `run`, otherwise the count of plan-time mutating steps is logged with the run. It also widens what the planner reads (prompt injection, below).
- **Anthropic absorbs the niche.** The desktop app already auto-verifies. Our value is the contract: frozen plan, model-free run, allowlist, measured accuracy, CI path. Re-checked at Phase 5.
- **Hallucinated PASS.** D6, D7, D9, D10 and the held-out measurement. **Honest limit:** the model still writes the plan, so it can plan a check that asserts the wrong thing. That is exactly what the held-out false-PASS number measures.
- **Prompt injection at plan time.** The planner reads page text through `snapshot`. Bounded by: no shell in plans, the allowlist, `--validate`, and the plan being shown in the PR comment. Not eliminated.
- **The network boundary covers the browser only.** The D12 proxy keeps Chromium on allowed origins; it does not contain the verifier's shell, which can reach anything the user can (D11). No OS firewall or network namespace in the MVP; considered for CI only.
- **Re-planning after a FAIL.** Allowed, and recorded as a revision (D6); the first frozen plan's verdict stays on record and shows in the comment.
- **Secrets.** D11's honest limit: an agent with a shell can read the user's files. We keep secrets out of plans, evidence, comments and prompts.
- **Measurement cost.** 200 known-answer criteria is real work for one owner. The time-box and the real-bug source (sports-management history) keep it bounded.
- **Repeating selvedge.** D3/D4/D19: nothing moves, nothing is shared, and the removal follows a manifest.

## 10. Open questions for the owner

- **Q1–Q5:** answered 2026-11-12 (§12): selvedge was a different idea; name `selvedge`; sibling in atelier; remove after Phase 1; false-PASS ≤ 5%.
- **Q6 — answered 2026-11-12: (a), advisory in Phase 3; (b) revisited at Phase 5 with data.** What happens to a FAIL inside Loomwright? Ground truth never triggers a fix iteration (§2), so in Phase 4.5 a FAIL can't lead to a fix by itself (red team C1).
  - **(a) Recommended for Phase 3:** keep it advisory. The FAIL appears as a Phase 4.5 finding, in the PR comment, and is offered to `/propose --from-verify`. §8 measures whether humans act on it.
  - **(b)** Let `structured-read` FAILs enter the review-and-fix loop as fixable, non-blocking findings. That changes a HARD ADVISORY CONTRACT, so it would be its own decision with its own tests, revisited at Phase 5 with data.
- **Q7 — answered 2026-11-12: point estimate ≤ 5% on ≥ 60 held-out known-FAIL criteria, interval published.** What does "≤ 5%" mean?
  - **Recommended:** a point estimate ≤ 5% on ≥ 60 held-out known-FAIL criteria, with the interval published. That is achievable, and honest because the interval is shown.
  - **Alternative:** a 95% upper bound ≤ 5%. That needs 0 misses in 72, or ≤ 2 in ~135. It is stronger, and roughly doubles the measurement work.

## 11. What this plan supersedes (actions on approval)

- `.supervisor/requirements/selvedge-extraction/`: **done 2026-11-12.** Stamped `## Status: done_with_escalation — SUPERSEDED by qa-split/00-plan.md (…)`. A bare `superseded` is not a status `/automate` recognises (`status-stamp.sh` treats only `done`/`done_with_escalation` as terminal), so it would have left the items queueable. 01–03 also note that their PRs were discarded by the force-push; 04–07 were already ABANDONED.
- `.supervisor/requirements/qa-evolution/` (9 items were `pending`): **done 2026-11-12**, same stamp; all 18 files in both sets read terminal through `status_is_done`. Ideas kept: a consumer for FAILs (02 → `/propose --from-verify`), measured worth (03 → §8), verify in the loop (04 → D15), preview targets (05 → D12's `allow_remote`), Electron/mobile (09a/09b → after Phase 5).
- Branch `feature/relocate-qa-to-selvedge`: **deleted 2026-11-12 with the owner's OK**, locally and on origin (was `8adefd3`). Its commits stay reachable through `refs/pull/157/head`.
- `loomwright/docs/QA_SYSTEM_BLUEPRINT.md`: deleted in item 11b.
- `REQUIREMENTS-SITE-V2.md` "QA spin-off (Selvedge) — queued": point it here.

## 12. Owner decisions

- 2026-11-12 (Vikash): direction set: "get rid of all QA stuff from LW and set up a new plugin by doing proper research". Research done. Plan drafted.
- 2026-11-12 (Vikash): **selvedge was a different idea** (context reduction). **The goal now is a working, usable product based on the 2026 findings.**
- 2026-11-12 (Vikash): **name is `selvedge`**, reused on purpose.
- 2026-11-12 (Vikash): **location is a sibling `selvedge/` in the atelier repo**, with its own gates.
- 2026-11-12 (Vikash): **remove QA from Loomwright after Phase 1.**
- 2026-11-12 (Vikash): **false-PASS ceiling ≤ 5%**; it gates Phase 3. (Rev 2 defines what it is measured on; Q7 asks point vs bound.)
- 2026-11-12 (Vikash): ran the red-team review on rev 1 → SHIP_BLOCKED; asked for the plan to be revised. Rev 2 drafted.
- 2026-11-12 (Vikash): **approved rev 2 as recommended**: Q6 (a) FAILs stay advisory in Phase 3, the fix-loop route is revisited at Phase 5; Q7 the gate is a point estimate ≤ 5% on ≥ 60 held-out known-FAIL criteria with the 95% interval published. Phase 1 requirement files written. Branch `feature/relocate-qa-to-selvedge` deleted on the owner's OK. Still open: updating the tracked `REQUIREMENTS-SITE-V2.md` (left for a PR, since this checkout carries a live `/automate` run).
- 2026-11-12 (Vikash): two outside critiques of rev 2 reviewed; **"Yes, apply them"**: the agreed fixes go in as rev 3 (§14). Phase 4 order and scope unchanged; D20–D25 not added.
- 2026-11-13 (Vikash): Test Agents comparison and regression question reviewed; **"Yes, apply them"**: `snapshot --steps`, `run --replay`, two-number repeatability, Test Agents as a rejected alternative under D5, P9 export rules, Playwright verdict mode on the §9 watch list (§14).

## 13. Red-team disposition (rev 1 → rev 2)

Every FATAL, CRITICAL and WARNING is listed. The five WEAKNESS items were not dispositioned one by one; none of them changed a decision.

| Finding | What rev 1 got wrong | Where rev 2 answers it |
|---|---|---|
| **F1** unattended seam runs PR-controlled shell + model-written code | D15 had no trust rule | D5 (no free code unattended), D6 (model-free run), D15 (a)–(e), §7 |
| **F2** no production guard exists | D12 claimed a denylist that isn't there | §2 fact row; D12 request-level allowlist + mutation rule; item 02 tests |
| **F3** secrets in CI and evidence | 06b used fork-capable triggers; evidence linked traces | D13 text-only comment + local redacted evidence; item 10b `pull_request` same-repo only; N8 |
| **F4** circular, ungameable-proof accuracy gate | No denominator, no N, no abstention cap, self-seeded, eval-tool limits | D16; Phase 2 items 07–08 (definitions, N, held-out third-party set, 20% abstention cap, intervals); Q7 |
| **C1** kill criteria undecidable; no UI here; FAIL can't cause a fix | Vague thresholds; dogfood on this repo | §8 numeric + data source; Phase 5 on sports-management; Q6 |
| **C2** repeats the never-used failure | Web-only with native-heavy owner apps, round 3 unused | §2 fact; D17; Phase 2b; post-MVP order; §9 first risk |
| **C3** NOT_VERIFIABLE/BLOCKED fold into green | No mapping | D14 mapping + count rendering; item 09 test |
| **C4** frozen plan bypassable; model controls check and evidence | Hook-only freeze | D6 hash check in the CLI, runner-written evidence; §9 honest limit |
| **C5** model can see secrets | Overclaimed isolation | D11 rewritten with the stated limit |
| **C6** CLI needs an LLM; discovery unspecified | Silent | D4 discovery; §5 `SELVEDGE_PLANNER`; only `plan` uses a model |
| **C7** removal isn't small; `verify:` falls through to `cmd` | "124 files, one release" | §2 surfaces; item 11a manifest; D18; `qa-executor` arm kept until 09 |
| **W1** evidence overreach | Gold-checklist, cross-vendor, AskUI-Electron, "nobody builds verdicts" | D2 and D9 wording; Electron now sourced from round 3 |
| **W2** D9 contradicts N1 | Cross-vendor consensus without a second key | D9 states same-model = consistency check |
| **W3** release tooling | "Loomwright untouched" was false | D19; item 01 |
| **W4** `.agent/verify.json` shared across plugins | Shared contract | §5 config: selvedge owns `selvedge.json`; item 12 swaps the trusted path |
| **W5** stale stamps and branch | Not actioned | §11 actions on approval |
| **W6** user-wide crashing guard | Fail-closed PreToolUse hook | No hooks in MVP; integrity in the CLI (D6) |
| **W7** done-when checks that can't be verified | "Most", "some", "grep returns nothing" | Item tables now name a test or a recorded artifact; 11a manifest |
| **W8** evidence location | Unspecified | D13: gitignored `.selvedge/evidence/`, auth state outside the repo |
| **W9** required-check back door | D14 allowed it | D14: `neutral` on FAIL by default; opt-in `--fail-check` documented as gating |

## 14. Rev 3: outside-critique fixes (2026-11-12)

Two outside critiques of rev 2, checked against the item files, Playwright's docs (`network.md`: a route handler runs only for the first URL of a redirect chain) and Playwright's Chromium launch code (`shouldProxyLoopback` forces `<-loopback>` unless `bypass` names a loopback host or the env override is set).

| Finding | Change |
|---|---|
| Redirect hops after the first escape `context.route` (found while checking the first critique; neither critique had it) | D12: runner-owned proxy checks every connection; item 02 tests |
| WebSockets aren't covered by `route` | Same proxy; `ws`/`wss` tests in item 02 |
| "Reject loopback/private IPs" would block every localhost target | Narrowed: local origins match exact host + port; the private-range refusal applies to remote names only (DNS rebinding) |
| Boundary scope unstated | D12 + §9: browser only; the shell is D11's limit |
| Hash doesn't stop re-planning | D6 revisions: one-shot freeze, every revision kept, first verdict stays on record (items 03, 04, 06) |
| Raw page values in a public PR comment | D13: not published by default; per-repo opt-in with redaction (item 06) |
| Wrong-thing-verified, negative criteria | D7: interpretation + assumptions, material ⇒ NOT_VERIFIABLE, negative criteria need a baseline + side-effect read (items 03, 04) |
| D7 "non-existence" wording | Reworded to match item 03 |
| Correlated criteria in the eval | Item 07 split by defect; item 08 per-defect grouping + 3-run repeatability |
| CI hook approval | Item 10b: repository variable, limit stated |
| "No account" vs `claude -p` | P1, 06c, §8 reworded |
| Rollback before removal | Item 11a: `pre-qa-removal` tag + rollback note |
| Demand measured only on the owner | §8: independent outside use |
| **Not adopted:** move Phase 4 after Phase 2; add D20–D25; make interviews a prerequisite | Old QA has zero runs and no caller (D1, Q4); the plan is a dogfood experiment with §8 kill lines. Both critiques agreed in the end |

**Added 2026-11-13 (Test Agents comparison, regression):**

| Finding | Change |
|---|---|
| Planner sees one page per URL; modals, drawers and later form steps are invisible | Item 03: `snapshot --steps <prefix.json>`, validated and proxied like a plan; §9 risk on plan-time state |
| No regression path; rev 3's `already_run` blocked re-running a frozen plan | D6 + item 04: `run --replay` (new folder, no model, zero tokens); P9 |
| Repeatability mixed planner and runner variance | Item 08: two numbers |
| Test Agents not listed as an alternative | D5 rejected alternatives |
| Healer maintenance of an exported spec | P9 + after-Phase-5 item 1: healer edits end the verdict; a skip is a FAIL signal |
| Playwright could add a verdict mode | §9 watch list |
