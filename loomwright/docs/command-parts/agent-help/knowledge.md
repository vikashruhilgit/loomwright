### 💤 /dreaming — Reflect on Past Sessions (Read-Only Until You Accept)

**Purpose:** Run target agents in reflection mode over recent session logs to **propose** memory and `CLAUDE.md` updates, and to **harvest recorded `convention_mismatch` findings into proposed `.agent/rules/` entries**. Read-only on code, agent memory and `CLAUDE.md` while it gathers and proposes; every write is per-item human-gated. **It is not read-only on the *remote*:** an accepted rule proposal can reach a branch, a push and a `gh pr create` — but only through a **second, separate** per-item **Pre-push confirmation** — and the memory writes its Accepts made in place can reach ONE memory PR, but only through one per-run **Pre-push confirmation**. `/dreaming` never merges.

**Usage:**
```
/dreaming                                      # All agents, last 5 sessions
/dreaming --agent code-reviewer                # Reflect with Code Reviewer only
/dreaming --agent red-team --sessions 10       # Red Team, last 10 sessions
/dreaming --agent qa-executor --sessions 3     # QA Executor, last 3 sessions
/dreaming --agent all --sessions 20            # All agents, deeper history
/dreaming --full-model                         # Reflection spawns inherit the session model (skip sonnet default)
/dreaming --force                              # Skip the curation-readiness check and reflect anyway
```

**Parameters:**
- `--agent all|code-reviewer|red-team|qa-executor` (default `all`)
- `--sessions N` (default `5`)
- `--full-model` (default off — reflection spawns default to `model: "sonnet"` per `docs/ARCHITECTURE_CONTRACTS.md` §Cost Profiles → "Async analysis surfaces"; flag restores `inherit`)
- `--force` (default off — skips the curation-readiness check from `scripts/curation-status.sh`; without it `/dreaming` declines, advisory and exit 0, below an **unvalidated** threshold guess of `15` **unreflected** session logs — logs never fed to reflection that carry reflection signal, tracked as a consumed set rather than a timestamp so a windowed run never retires the backlog it did not read — overridable at `.curation.thresholds.dreaming` in `.supervisor/config.json`). `/insights` has the same flag; `/pr-postmortem` deliberately has none — it targets one named PR and never declines.

**What it does:**
- Reads the N most recent `.supervisor/logs/{session_id}.jsonl` files (read-only)
- Spawns target agent(s) in reflection mode with read-only access to their own `.claude/agent-memory/{agent-id}/`
- Aggregates per-agent output into a single reflection report with six mandatory sections, in this order:
  - Recurring Patterns
  - Distilled Insights
  - Proposed Memory Updates
  - Proposed CLAUDE.md Updates (may also be prune / merge / supersede curation candidates — see `dreaming.md` §4)
  - Collected Memory Candidates
  - Proposed LESSONS
- Presents each proposed update for **per-item user approval** (Accept / Reject / Edit)
- Appends up to three **promotion queues** after the six sections, shown only when non-empty: pending **orientation** memos, pending **agent-memory** proposals (labeled **PROMOTE PENDING PROPOSAL** — surfaced automatically; you no longer list `.supervisor/agent-memory-proposals/` by hand), and the harvested **`.agent/rules/` PR delivery queue** (each rule with its `applies_to`, the finding ids that motivated it, and the batch's coverage / dedupe-rate / scope-fidelity numbers — fidelity always as BOTH figures, checkable and all-motivating-findings). A batch the harvester marked **DISTILLATION FAILURE** is **not offered at all**: the verdict is surfaced, the queue stops there, and no gate is asked
- After every Accept, may offer ONE **memory PR** for the project-memory and agent-memory writes it made in place (see the contract below)

**Read-only-until-Accept contract:**
- `/dreaming` modifies nothing — not code, agent memory, `CLAUDE.md`, or any store — while it gathers and proposes; the convention harvest is a **dry run with no write mode at all**
- Every proposed update is labeled **PENDING USER APPROVAL**
- Persistence happens **only after** the user explicitly approves each item: on per-item Accept, `/dreaming` writes project-memory facts + LESSONS via the repo-root sole writers, promotes orientation proposals via `add-orientation.sh --confirm` and agent-memory proposals via `write-agent-memory.sh --proposal <file> --confirm` (each that store's sole writer, literal argv); **CLAUDE.md proposals stay paste-to-apply** — including curation (prune/merge/supersede) candidates — because there is no CLAUDE.md writer
- **Two remote-affecting actions, each behind two gates.** A harvested rule needs the per-item **Accept** (authorising its *content*) **and** a separate per-item **Pre-push confirmation** (authorising the *push*); neither implies the other. Only rules clearing both are authored through `add-rule.sh --confirm`, committed to a `dreaming/rules-<session_id>` branch (staged by path — never `git add -A` — and committed pathspec-limited to `.agent/rules`, so an unrelated entry you had already staged stays out; the commit's file list is verified to be rules-only before the push) and delivered by `gh pr create`. Nothing confirmed ⇒ no branch, no commit, no PR. Delivery also **aborts before branching** unless HEAD is already contained in `origin/<base>` (base resolved from the repo, never assumed `main`) — a PR is the branch-versus-base diff, not the commit, so a rules-only commit cut from an unrelated feature branch would still open a PR full of that branch's changes. **`/dreaming` never merges the PR it opens.**
- **The memory PR — a second branch, one per-run push gate.** Accepted project-memory facts, LESSONS and agent-memory promotions are written in place. After every Accept, `/dreaming` may offer ONE PR on its own `dreaming/memory-<session_id>` branch (separate from `dreaming/rules-<session_id>`, so either can merge without the other), behind **one** per-run **Pre-push confirmation** — not per item, because those Accepts share files such as `LESSONS.md`. It records each successful writer call's files at Accept time, stages only the changed files of that record (in the project-memory and agent-memory stores, never the harness-memory pointer) by explicit pathspec, commits them pathspec-limited, verifies the commit's file list equals that set (no stray, no missing path) before pushing, runs the same HEAD-in-base pre-flight, and runs after the rules delivery when both apply. It is not offered when those stores held uncommitted changes before the first write (checked with `--untracked-files=all`, so it does not depend on your `status.showUntrackedFiles`; the harness-memory pointer's file excepted), when that check itself could not run, when a recorded file is gitignored or unstageable, or when the harness-memory pointer's target is a recorded file. Declined ⇒ no branch; the writes stay in place, uncommitted. After delivery your branch reads the pre-run memory content until the PR merges and you pull. `CLAUDE.md` stays a hand PR. **`/dreaming` never merges the PR it opens.**

**When to Use:**
- After a streak of completed `/supervisor` sessions, to surface recurring issues
- Before updating `CLAUDE.md` by hand, to discover what the logs say should change
- As a recurring retrospective cadence (weekly / per milestone)

**When NOT to Use:**
- During active execution → `/dreaming` reflects on *past* sessions
- When you need code changes → `/dreaming` never touches code (its two PRs stage only `.agent/rules/*.json` and its own recorded project-memory and agent-memory writes); use `/supervisor` or `/code-reviewer`
- For agents without persistent memory → only Code Reviewer, Red Team Reviewer, and QA Executor are valid targets

**Learn More:** see `loomwright/commands/dreaming.md` for the full parameter table, the reflection-mode task prompt template, the read-only-until-Accept contract (incl. the two remote-affecting actions and their gates), the rules PR and memory PR delivery queues, and example output

---

### 🔭 /capability-check — Scan for New Platform Capabilities (Read-Only)

**Purpose:** On-demand, bounded (≤5 fetches) scan that diffs the live Claude Code changelog/docs plus dependency info against the tracked `loomwright/docs/CAPABILITY_BASELINE.json` and reports **CANDIDATE** adoptions — new platform capabilities the plugin could adopt. Never self-applies; suppresses output when nothing new is found. `--update-baseline` is an explicit maintainer action that refreshes the tracked baseline. With **`--strategy`** it instead runs a grounded product-evolution pass that proposes scored, deduped, differentiated **product directions** (distinct from adoption candidates, reusing the brainstorming skill) — same propose-only / bounded / human-gated discipline.

**Learn More:** see `loomwright/commands/capability-check.md` for the scan protocol, fetch budget, the `--strategy` product-direction mode, and the maintainer `--update-baseline` flow

---

### 📊 /insights — Local Insights Dashboard (Read-Only, Obsidian-friendly)

**Purpose:** Generate a local markdown insights dashboard (`.supervisor/insights/dashboard.md` + per-run notes with Dataview-compatible frontmatter) from `.supervisor/logs/*.jsonl`, covering work / quality / session-performance (completion rate, self-heal outcomes, rubric scores, subtask counts, files touched). Deterministic `jq` aggregation via `scripts/build-insights.sh`. **Cost (tokens/$) is intentionally NOT captured** — it lives in Claude Code's own transcripts; the dashboard points to `npx ccusage`.

**Parameters:**
- `--force` (default off — skips the curation-readiness check from `scripts/curation-status.sh`; without it `/insights --force` is what you need when it declines, advisory and exit 0, below an **unvalidated** threshold guess of `10` new session logs — counting only those carrying a `session_end`, the sole event a rebuild consumes — since the dashboard's mtime, overridable at `.curation.thresholds.insights` in `.supervisor/config.json`; set that key to `0` to keep the reporting but never decline). `/dreaming` has the same flag; `/pr-postmortem` deliberately has none — it targets one named PR and never declines.

```
/insights                                      # Build the dashboard (declines below the readiness threshold)
/insights --force                              # Skip the curation-readiness check and build anyway
```

**Learn More:** see `loomwright/commands/insights.md` for the dashboard layout, the Dataview frontmatter schema, the `--force` / readiness contract, and the `ccusage` cost note

---

### 🔮 /obsidian — Local Obsidian Vault Projection (Read-Only, Linked)

**Purpose:** Project this repo's accumulated knowledge — session logs, System Twin contracts (with `[[dependency]]` wikilinks so the graph view = blast radius), and Lessons / Project Memory — into a fully-**linked** external Obsidian vault you configure. Read-only one-way projection (no source-of-truth file touched, no agent reads it back, no data leaves your machine) via `scripts/build-vault.sh`. **Opt-in:** destination via `LOOMWRIGHT_OBSIDIAN_VAULT` env or `.supervisor/obsidian-config.json`; **no-op (exits 0, prints how to opt in) when unset.** Content-hash idempotent and sparse-tolerant.

**Learn More:** see `loomwright/commands/obsidian.md` for the configuration (env var / config file / slug), the vault layout, and the idempotency / sparse-tolerance guarantees

---

### 🤝 /handoff — Catch-Up / Hand-Off Digest (Read-Only)

**Purpose:** Assemble ONE recency-focused, per-work-item catch-up digest so a second person can pick up where you left off in ~2 minutes. Interleaves work items across Supervisor jobs, autonomous runs, and automate runs into a single newest-first list, surfacing the five facets where derivable — decision · why · tried/rejected · current state · provenance — plus an honest freshness/basis line (mtime vs recorded commit-SHA, never conflated). Reuses the sanctioned `read-project-memory.sh` / `read-lessons.sh` readers, silently skips absent surfaces, and writes a derived digest to `.supervisor/handoff/digest.md` (gitignored) via `scripts/build-handoff.sh`. Read-only on your work; always exits 0. Distinct from `/insights` (run trends/aggregates) and `/obsidian` (external vault projection).

**Usage:** `/handoff` · `/handoff --publish` (ALSO writes a shareable, point-in-time snapshot)

**Learn More:** see `loomwright/commands/handoff.md` for the facet-derivation rules, the freshness-basis contract, the surfaces it reads, and the opt-in `--publish` snapshot written to `.supervisor/handoff/snapshot.md` (the default digest path is byte-identical with or without the flag)

---

### 🌱 /propose — Candidate Work Items from the Churn Ledger, a /verify Run, the Feature Scorecard, and the Domain (Read-Only, Propose-Only)

**Purpose:** Turn the recorded churn ledger — or, with `--from-verify`, a `/verify` run's evidence, with `--from-scorecard`, the feature scorecard, or with `--domain`, this project's own domain — into candidate work. The learning loop records and never proposes — findings accumulate, but nothing converts a trend into a piece of work, so every item this system executes was human-typed. By default `/propose` reads the pre-aggregated `.supervisor/floor/floor.json` and writes evidence-carrying candidate requirement files to `.supervisor/requirements/proposed/` (gitignored) via `scripts/propose-work.sh`. **It proposes; it never queues** — `proposed/` is deliberately NOT an `/automate --folder` target, and promotion is a human moving a file out of it. Threshold, never ranking: a `(class, flow_stage)` pair emits at ≥10 entries, with no score, rank, priority or top-N. A candidate that cannot cite ≥3 distinct ledger entries is not written; a basis older than 24h proposes nothing and names the age. Advisory and fail-safe — `set -uo pipefail` with no `set -e`, a `jq` guard that skips, `exit 0` always. **Several bases, never more than one in one invocation:** the default reads inward (our own recorded mistakes, local `jq` over a local file, **zero** external calls); `--from-verify <run_id>` reads a single `/verify` run's `evidence.jsonl` and drafts one file per `FAIL` `ac` line classified `REAL_BUG` plus every `issue` line (`DISCOVERY_GAP`/`ENVIRONMENT_ISSUE`/`BLOCKED`/`NOT_VERIFIABLE` never draft), via `scripts/propose-from-verify.sh`, sharing its blast-radius guard with the other bases through `scripts/propose-common.sh`; `--from-scorecard` reads `scripts/build-feature-scorecard.sh --json` and drafts one `scorecard--<feature-slug>.md` per non-critical `review:` feature — numbers, record paths, an enhance and a retire option — via `scripts/propose-scorecard.sh`, and never changes a feature; while `--domain` reads outward via `scripts/propose-domain.sh` — the committed product store `.agent/product.json` (through `read-product.sh`, never re-parsed) plus competitor sources fetched through one named seam — and asks what competent apps in this domain do that this one does not. `--domain` is never implicit precisely because it spends fetch budget and emits judgment-class output. Its files are namespaced `domain--<slug>.md` so no two bases can collide in `proposed/`; it emits nothing an actually-fetched source does not corroborate (its expectation catalogue is a list of things to look for, not evidence); a capability the inventory cannot confirm either way is reported **unverified**, never missing; every gap is classified `TABLE-STAKES` / `DIFFERENTIATOR` / `NOT-FOR-US` with the default action read verbatim from `read-product.sh`'s `stance_default_action`; and with no product store it names the absence, offers the `propose-product.sh` bootstrap, writes nothing and exits 0.

**Parameters:**
- `--from-verify <run_id>` (default off — run the **verify** basis *instead of* the ledger basis, via `propose-from-verify.sh` on `.supervisor/verify/<run_id>`)
- `--from-scorecard` (default off — run the **scorecard** basis *instead of* the ledger basis, via `propose-scorecard.sh`)
- `--domain` (default off — run the **domain** basis *instead of* the ledger basis, via `propose-domain.sh`; never implicit)
- Bases never combine — at most one basis flag per invocation

Each basis is tuned by env vars read by its own script, all optional. Ledger basis (`propose-work.sh`): `PROPOSE_FLOOR_JSON`, `PROPOSE_OUT_DIR`, `PROPOSE_REQUIREMENTS_DIR`, `PROPOSE_THRESHOLD` (10), `PROPOSE_MAX_AGE_SECONDS` (86400), `PROPOSE_SOURCE_DATE_EPOCH`. Verify basis (`propose-from-verify.sh`): `PROPOSE_FROM_VERIFY_OUT_DIR` (`.supervisor/requirements/proposed`). Scorecard basis (`propose-scorecard.sh`): `PROPOSE_SCORECARD_OUT_DIR` (`.supervisor/requirements/proposed`). Domain basis (`propose-domain.sh`): `PROPOSE_DOMAIN_STORE` (`.agent/product.json`), `PROPOSE_DOMAIN_OUT_DIR` (`.supervisor/requirements/proposed`), `PROPOSE_DOMAIN_REQUIREMENTS_DIR` (`.supervisor/requirements`), `PROPOSE_DOMAIN_FETCH_CMD` (**unset ⇒ no fetcher and nothing fetched at all** — it is the only external transport, invoked as `<cmd> <url>`, and there is no implicit `curl` fallback), `PROPOSE_DOMAIN_MAX_FETCHES` (5, for the whole run; local reads never draw on it), `PROPOSE_DOMAIN_MAX_SOURCE_AGE_SECONDS` (7776000 = 90d, past which a source is named STALE rather than cited silently), `PROPOSE_DOMAIN_SURFACE_FILE_CAP` (4000), `PROPOSE_DOMAIN_SOURCE_DATE_EPOCH`.

```
/propose                                       # read floor.json, write candidates to .supervisor/requirements/proposed/
/propose --from-verify <run_id>                # verify basis: read a /verify run's evidence.jsonl, write verify-<run_id>-*.md candidates
/propose --from-scorecard                      # scorecard basis: read the feature scorecard, write scorecard--<feature-slug>.md candidates
/propose --domain                              # domain basis: read .agent/product.json + fetched sources, write domain--<slug>.md candidates
```

**Note — deleting a proposal is NOT a durable dismissal.** The cited coordinates are the earliest entries for a pair, so the `evidence-set:` token is stable and the candidate returns on the next run; a domain candidate's `domain-gap: <slug>@<classification>` token is stable for the same reason. To dismiss permanently, paste that token into a requirement file stamped `## Status: done` anywhere under `.supervisor/requirements/`, and the next run names the file that suppressed it.

**Learn More:** see `loomwright/commands/propose.md` for the bases contract, each basis's env table, the promote/dismiss contract, and the emission + staleness thresholds

---

