# Supervisor Job: Hardening sweep — Floor GET Host check, bot-author regex, telemetry body, description card, platform pin

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: worktree-automate-hardening-2026-09-22 (== origin/main @ 223cd89)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/red-team-hardening/08-hardening-sweep.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Python (setup-ui.sh's embedded server, send-telemetry-core.sh), jq (classify-bot-review.sh), JSON manifests, GitHub Actions YAML, bash tests — all match the existing plugin's stack. |
| 2 | Dependency Availability | GO | No new dependency; all touched tooling (python3, jq) already required repo-wide. |
| 3 | Architecture Fit | GO | Each of the 5 fixes follows an established pattern already used elsewhere in this run (fail-safe/fail-closed emitters, mutation-controlled new gates, doc-currency assertions). |
| 4 | Scope vs Supervisor Capability | CAUTION | 5 independent problems bundled into one requirement, ~13-15 files across 5 largely-disjoint areas, BUT two files are shared by 2 of the 5 fixes plus the consolidating version-bump step (`loomwright/.claude-plugin/plugin.json` — touched by fix 4's description rewrite AND, conditionally, fix 5's version-pin field IF one exists AND the final version bump; `CHANGELOG.md` — the requirement's own Scope item 6 says "one version bump" consolidating all 5 fixes' narrative into ONE entry). Fixes 1/2/3 (Floor Host check, bot-regex, telemetry body) touch neither shared file directly. This shared-file convergence is still a **file-conflict** condition (SKILL.md's first legal split reason: "two coherent work groups would edit the same file — they must serialize anyway"), not a genuine-parallelism opportunity — splitting into 5 subtasks would require a 6th subtask solely to consolidate the CHANGELOG/version bump, BLOCKED on all 5, which adds coordination overhead without proportional wall-clock savings for a single-worker-per-subtask model. Kept as ONE subtask, consistent with items 06/07 in this same automate run (comparable or larger multi-file scope, both completed correctly as Single-Agent Path, item 06 needing several turn-limit resumes). Recorded as a Risk Assessment row (generous worker turn budget expected). |
| 5 | Hard Blockers | GO | No migration framework, no new credentials, no missing modules. Every line-number citation in the source requirement was independently re-verified during planning — two were found to be off (see Risk Assessment) and are corrected below; the requirement's "14 scripts" claim for undocumented-field dependents was found to be 12 by direct grep and is flagged UNVERIFIED rather than repeated as fact. |

**Overall Verdict:** CAUTION (proceeds silently per Phase 2.5 flow, feeds Risk Assessment — no NO-GO, no human override needed)

## Task
**Goal:** Land five small, independently-verified hardening fixes in one PR: a Floor GET/HEAD Host-header check (closes a DNS-rebinding read hole), a tightened bot-author regex for review classification, a telemetry body that ships structured fields instead of the whole result block, a plugin description under 400 chars with a length gate, and a pinned `claude-code-action` ref plus a new hook-payload-contract test.

**Problem Statement:**
Five real, independently-verified gaps (each verified 2026-09-21 per the source requirement) sit in this plugin today. (1) `setup-ui.sh`'s `FloorHandler` only guards `do_POST` via `_guard()` (token → Origin → Host); `do_GET`/`do_HEAD` are never overridden, so `SimpleHTTPRequestHandler`'s inherited GET handler answers every read request with no Host check at all — a DNS-rebinding page that gets a victim's browser to resolve an attacker-controlled name to 127.0.0.1 can read `index.json` (registered project paths, run state) and `serve.log` through that GET path, even though the four POST-driven action routes are already locked down. (2) `classify-bot-review.sh`'s `bot_author_re` (`^claude(\[bot\])?$|\[bot\]$|^github-actions`) trusts a human login literally named `claude` and any login merely *starting with* `github-actions` — looser than necessary regardless of whether GitHub reserves those exact strings. (3) `send-telemetry-core.sh` ships the entire redacted result block to a GitHub issue behind a 9-regex secret-scanner allowlist; a regex allowlist catches known secret *shapes*, not arbitrary sensitive content (file paths, finding descriptions, subtask names) — the privacy boundary should be field selection, not pattern-matching. (4) `plugin.json`'s `description` is 3,131 characters of accreted release narrative, directly violating CLAUDE.md's own stated "description is a summary, not a changelog" rule, with no gate enforcing it. (5) 12+ scripts read undocumented Claude Code hook-payload fields (`last_assistant_message`, `agent_transcript_path`) with no minimum-CLI-version pin and no regression test — a silent upstream field rename would turn fail-SAFE emitters into silent no-ops, and both GitHub Actions workflows float `anthropics/claude-code-action@v1` (a moving major tag) rather than a pinned SHA/tag. Success looks like: Floor reads require the same Host check as Floor actions; the bot classifier trusts only exact bot logins; telemetry bodies are privacy-by-field-selection with an opt-in escape hatch; the description card is short and gated; and the platform coupling is pinned, documented, and regression-tested.

## Acceptance Criteria
- [ ] Given a running Floor server (`serve --detach`), when a GET request arrives with `Host: evil.example`, then the response is `403` with the existing `host-not-loopback` refusal JSON body; given the same request with `Host: 127.0.0.1:<port>`, then the response is `200`; the four existing POST routes' behavior is unchanged.
- [ ] Given `classify-bot-review.sh`'s `bot_author_re`, when tested against `claude` (a human login, no `[bot]` suffix), `github-actions-fan` (a login merely starting with `github-actions`), `claude[bot]`, `github-actions[bot]`, and `anything[bot]`, then only the three `[bot]`-suffixed logins classify as bot-authored — `claude` and `github-actions-fan` are excluded.
- [ ] Given `send-telemetry-core.sh --dry-run` on a fixture result, when the emitted `raw_data` JSON is inspected, then it contains NO `result_block` key by default, but DOES contain structured fields for `schema`, `score`/`score_bucket`, `status`, `primary_error` (truncated to 200 chars), an `issues` object with a count per severity, and a `tools` field; given the user-scope `include_result_block: true` consent key is set, then `result_block` reappears in the body.
- [ ] Given `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`'s loomwright entry, when their `description` field length is measured, then both are ≤ 400 characters and both describe what the plugin is, the four current counts, and point to CHANGELOG.md for history.
- [ ] Given `scripts/check-doc-currency.sh` run against a fixture with a 601-character description, then it FAILS; given the new ≤400-char card, then it PASSES.
- [ ] Given both `.github/workflows/claude.yml` and `.github/workflows/claude-code-review.yml`, when grepped for `anthropics/claude-code-action`, then both reference a specific tag or commit SHA (never a bare `@v1`), each with a one-line comment naming the date and reason for that pin.
- [ ] Given a new `loomwright/scripts/test-hook-payload-contract.sh`, when run against the current codebase, then it PASSES (every hook-payload field a script reads is present in at least one fixture under `loomwright/scripts/progress-event-fixtures/spawn-probe-2026-09-02/`); given a mutation that adds a read of a field absent from every fixture, then it FAILS (mutation control, proving the assertion is load-bearing).
- [ ] Given the full existing test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh`) plus the new/extended suites above, when run, then all are green with zero regressions.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Hardening sweep (5 independent fixes, bundled per file-conflict on plugin.json + CHANGELOG.md) | all | 13 modify, 1 create | none needed (plain script/JSON/YAML/doc edits) | LAUNCHABLE |

```yaml
# Subtask 1 — Hardening sweep (LAUNCHABLE, sole subtask)
provides:
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "do_GET"}
  - {kind: "symbol", path: "loomwright/scripts/setup-ui.sh", name: "do_HEAD"}
  - {kind: "file", path: "loomwright/scripts/test-hook-payload-contract.sh"}
  - {kind: "symbol", path: "loomwright/scripts/send-telemetry-core.sh", name: "raw_data"}
requires: []
lanes:
  - "loomwright/scripts/setup-ui.sh"
  - "loomwright/scripts/test-setup-ui.sh"
  - "loomwright/scripts/classify-bot-review.sh"
  - "loomwright/scripts/test-classify-bot-review.sh"
  - "loomwright/scripts/send-telemetry-core.sh"
  - "loomwright/scripts/test-send-telemetry-core.sh"
  - "loomwright/docs/TELEMETRY.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "scripts/check-doc-currency.sh"
  - "CLAUDE.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "README.md"
  - "loomwright/scripts/test-hook-payload-contract.sh"
  - ".github/workflows/claude.yml"
  - ".github/workflows/claude-code-review.yml"
  - "CHANGELOG.md"
external_requires: []
```

### File Impact Map (detail behind the contract above — 5 fixes, independently verified line numbers)

**Fix 1 — Floor GET Host check:**
- `loomwright/scripts/setup-ui.sh` — `FloorHandler` (class starts line 1624) currently overrides only `do_POST` (line 1703), which calls `self._guard()` (defined lines 1647-1655: token → Origin → Host, returns `None` or a refusal-name string) before proceeding, else 403 via `REFUSALS[...]` (line 1532 has `"host-not-loopback"`). `do_GET`/`do_HEAD` are NOT overridden anywhere (confirmed via `grep -n "def do_"` — only `do_POST` exists), so `SimpleHTTPRequestHandler`'s inherited GET/HEAD answer every request with zero Host check. Add `do_GET`/`do_HEAD` overrides that call `self._host_ok(self.headers.get("Host"))` (function at lines 1566-1567) FIRST — 403 with the SAME `REFUSALS["host-not-loopback"]` JSON shape on failure, else `super().do_GET()`/`super().do_HEAD()`. **Correction to the source requirement's own citation:** the "bare address still reads everything" sentence it cites at "~line 245" is actually at **line 1037** (inside `check_module()`'s printed status text, not a header comment) — update that sentence there ("a bare address still reads everything" → "a bare *loopback* address reads everything; a rebound name does not"), and check the related phrasing at lines 241-251, 1039, and 1043 for consistency (same security-argument family, may also need the loopback-vs-rebound distinction).
- `loomwright/scripts/test-setup-ui.sh` (7289 lines; harness: `pass=0; fail=0; skip=0` + `ok()`/`no()`/`skipn()`) — add GET/HEAD cases using the existing `n_req()` helper (lines ~4756-4780, a `python3 -c` `http.client`-based requester taking `<port> <method> <path> <token> <origin> <host> <body> <token-header-name>`, returning `"<status>\t<body>"`) alongside group (h)'s existing detached-server POST scaffold (~line 4740+): `Host: evil.example` GET ⇒ 403 `host-not-loopback`; `Host: 127.0.0.1:<port>` GET ⇒ 200; confirm the 4 existing POST-route cases are unaffected.

**Fix 2 — Bot-author regex tightening:**
- `loomwright/scripts/classify-bot-review.sh` — line 181 currently: `bot_author_re: "^claude(\\[bot\\])?$|\\[bot\\]$|^github-actions"`. Change to exact-login form: `^(claude\[bot\]|github-actions\[bot\]|dependabot\[bot\])$` plus any login ending in `[bot]` (i.e. drop the bare `^claude$` alternative and the `^github-actions` bare-prefix alternative). Used inside `author_ok($login)` (lines 192-197) feeding the main jq `select(...)` filter (lines 199-208). Item 01's `--trusted-actors` file, when present, supersedes this regex entirely (no change needed to that interaction).
- `loomwright/scripts/test-classify-bot-review.sh` (373 lines; harness: `pass=0; fail=0` + `ok()`/`no()`, tail `RESULT: $pass passed, $fail failed`) — **already has 17 test cases** (cases 1-12 base classifier, 13-17 the `--trusted-actors` allowlist from item 01) — ADD the 5 new/changed login cases described in Acceptance Criteria (this is additive to the existing 17, not a replacement suite).

**Fix 3 — Telemetry body privacy (field selection, not regex-only):**
- `loomwright/scripts/send-telemetry-core.sh` — `raw_data` dict construction is at **lines 675-688** (source requirement's "~670-684" is close but the field itself is at line 686: `"result_block": redacted_block,`; line 670 is `redacted_block = redact_text(result_block)`, the input). Drop the `result_block` key from the default `raw_data`. **Truncate `primary_error` ONLY at the `raw_data` dict-literal call site** (e.g. `"primary_error": primary_error[:200]`) — do NOT reassign the shared `primary_error` variable in place. That same variable feeds the dedup-hash input at line 740 (`hash_input = "%s::%s::%s" % (task_id, bucket, primary_error)`, the sha256 6-hour dedup gate) and a separate `emit("PRIMARY_ERROR", primary_error)` output at line 752, both AFTER `raw_data` is built and both currently reading the untruncated value; an in-place truncation would silently make two distinct long errors sharing a 200-char prefix dedupe as one AND truncate the PRIMARY_ERROR emit channel — neither is in scope for this fix. The dict currently has NO `issues`-per-severity or `tools` fields at all (they exist only as intermediate computations today: `_count_severity()` at lines 417-440 computes blocking/high/medium/low counts for the markdown body; a `tools_rx` match at lines 643-645) — ADD both as new structured `raw_data` fields (not just "keep" them, since they don't currently exist in this dict). Add a user-scope consent key `include_result_block: true` in the item-02 `egress.json` per-repo entry, set only via `/telemetry enable --include-result-block`, surfaced by `/telemetry status`; when set, `result_block` is restored to the body. `PRIVACY_PATTERNS` (lines 120-130, 9 regexes) stays as-is — it's a secondary defense on whatever text IS included, not being removed.
- `loomwright/scripts/test-send-telemetry-core.sh` (766 lines; **a SECOND, distinct harness convention** from fixes 1/2 above — `PASS_COUNT`/`FAIL_COUNT` + `assert_eq()`/`assert_match()`/`assert_not_match()` helpers per the file's own comment "test-telemetry.sh convention", lines 126-161; tail prints `RESULT  total=... passed=... failed=...`) — add cases: default body has no `result_block` key; with the consent key set, it does; `issues`/`tools` fields present and correctly populated.
- `loomwright/docs/TELEMETRY.md` — the section to rewrite is `## Privacy whitelist (lives in core)` at **line 1499** (documents the 9-regex deny-list table at lines 1519-1529, says "Subtask #2b owns the canonical list in code; this table is the spec") — reframe: the regex list is a secondary tripwire, not the privacy boundary; field selection (what's IN `raw_data` at all) is. **Do NOT touch** `### Privacy posture` at line 1757 — that section documents `send-webhook.sh`'s SUPERVISOR_RESULT payload, an unrelated feature (generic gate-event webhooks, not GitHub Issues telemetry).

**Fix 4 — Description card:**
- `loomwright/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (repo root, loomwright entry) — both currently **3,131 characters** (independently re-measured via `python3 -c 'import json;print(len(json.load(open(...))["description"]))'` — confirmed identical text duplicated in both files, matching the source requirement's cited figure exactly). Rewrite both to ≤400 chars: what the plugin is, the four current counts (14 agents/24 commands/42 skills/39 hooks — re-verify at implementation time, do not hardcode from this brief), "history in CHANGELOG.md".
- `scripts/check-doc-currency.sh` (repo root, 249 lines) — currently has ZERO description-length checking (confirmed via grep — its scope is version/count *prose* claims only, per its own header comment lines 1-41). Add a new assertion: fail when either `plugin.json` or `marketplace.json`'s loomwright `description` exceeds 600 chars OR contains more than one `v\d+\.\d+\.\d+`-shaped token.
- `CLAUDE.md` line 76 — the exact existing paragraph (one bold-lead-in block, "anti-rebloat" is a parenthetical inside the lead-in, not a `##`/`###` heading): `**Plugin \`description\` is a summary, not a changelog (anti-rebloat):** ... never append another version clause to the description.` — append a clause noting length is now gated by `check-doc-currency.sh`.

**Fix 5 — Platform pin + payload contract test:**
- `.github/workflows/claude.yml:35` and `.github/workflows/claude-code-review.yml:42` — both currently `uses: anthropics/claude-code-action@v1` (a floating major tag, confirmed via grep). Pin both to a specific tag or commit SHA with a one-line comment naming the date and reason (resolve the current recommended pin at implementation time — do not invent a SHA).
- `loomwright/.claude-plugin/plugin.json` — no minimum-CLI-version-style manifest field exists today (confirmed: top-level keys are `name`/`version`/`description`/`author`/`license`/`keywords` only). Research via the `claude-code-guide` agent or `claude plugin validate --help` in the implementing session whether the plugin manifest format documents such a field; if yes, add it; if NO such field exists, record the required minimum version in README's Requirements section and in `loomwright/docs/ARCHITECTURE_CONTRACTS.md` instead — do not invent a manifest field that isn't real.
- **New `loomwright/scripts/test-hook-payload-contract.sh`** — for each hook script that reads a hook-payload field, assert the field name appears in the recorded fixtures under `loomwright/scripts/progress-event-fixtures/spawn-probe-2026-09-02/` (6 JSON files confirmed present: `posttooluse-task-{1,2}.json`, `pretooluse-task-{1,2}.json`, `subagentstop-{1,2}.json` — a rich fixture set covering `session_id`, `transcript_path`, `agent_transcript_path`, `last_assistant_message`, `agent_id`, `agent_type`, `stop_hook_active`, etc.). **Correction to the source requirement's own claim:** it says "14 scripts" depend on undocumented hook-payload fields; independent re-verification via `grep -rl "last_assistant_message\|agent_transcript_path"` across `loomwright/scripts/*.sh` found exactly **12** (6 production: `build-floor.sh`, `capture-task-spawn-payload.sh`, `emit-progress-event.sh`, `emit-token-ledger.sh`, `send-telemetry-core.sh`, `send-webhook.sh`; 6 test files: `test-classify-risk.sh`, `test-progress-state.sh`, `test-result-validators.sh`, `test-telemetry.sh`, `test-token-ledger.sh`, `test-webhook.sh`). The worker should re-derive the exact field set and script list at implementation time (possibly other field names beyond these two account for the discrepancy) rather than trusting "14" — the new test's own scan IS the authoritative enumeration, so this discrepancy is self-resolving as long as the test scans for fields programmatically rather than hardcoding a list. A field read by a script but absent from every fixture should FAIL the test (mutation control: temporarily add a read of a fixture-absent field, confirm the test catches it, then revert).

**Shared/consolidating (touched once, at the end, after the 5 fixes above land):**
- `CHANGELOG.md` — one new entry covering all 5 fixes (one paragraph per fix, per the source requirement's own Scope item 6), one version bump.
- `loomwright/.claude-plugin/plugin.json` version field + `.claude-plugin/marketplace.json` mirror — bumped in the SAME commit as the CHANGELOG entry (this is the file-conflict convergence point noted in Feasibility check 4).

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | none needed — plain script/JSON/YAML/doc edits, no framework-specific skill applies |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Scope vs Supervisor Capability CAUTION (Phase 2.5) — 5 independent fixes, ~14 files, converging on shared `plugin.json`+`CHANGELOG.md` | MEDIUM | Kept single-subtask deliberately (file-conflict on the shared version-bump/changelog files makes a clean parallel split unavailable without a blocking 6th consolidation subtask); worker should expect and budget for multiple turn-limit resumes, matching items 06/08's scale in this same automate run. |
| Two coexisting test-harness conventions in this codebase (`pass/fail`+`ok()`/`no()` vs. `PASS_COUNT/FAIL_COUNT`+`assert_eq()`) | LOW | `test-setup-ui.sh`/`test-classify-bot-review.sh` use the first; `test-send-telemetry-core.sh` uses the second (its own comment calls it "test-telemetry.sh convention"). The new `test-hook-payload-contract.sh` should follow the first (simpler, closer match to its fixture-scan shape) — worker should not blindly copy the wrong convention into the wrong file. |
| Source requirement's own line-number citations were imprecise in 2 places | LOW | Independently re-verified during planning: (a) the "bare address" sentence is at `setup-ui.sh:1037`, not "~245" (245 is a different, related paragraph); (b) `send-telemetry-core.sh`'s `raw_data` dict is at lines 675-688, not "670-684" (670 is the input to the field, not the dict itself). Worker should re-grep rather than trust cited line numbers verbatim — same discipline applied throughout this automate run. |
| Source requirement's "14 scripts" claim for undocumented-field dependents could not be reproduced (found 12 via direct 2-field grep) | LOW | Documented as UNVERIFIED in the File Impact Map (Fix 5) rather than repeated as fact; the new `test-hook-payload-contract.sh`'s own programmatic field-scan is the authoritative enumeration going forward — the discrepancy is self-resolving as long as the test derives its script/field list by scanning rather than hardcoding a count. |
| Telemetry `issues`/`tools` fields don't exist yet in `raw_data` (they're currently only intermediate computations for the markdown body) | LOW | File Impact Map explicitly flags this as an ADD, not a "keep" — worker should not assume these fields already exist and merely need `result_block` removed around them. |
| No minimum-CLI-version manifest field may exist in the current plugin-manifest format | LOW | File Impact Map instructs the worker to verify via the `claude-code-guide` agent or `claude plugin validate --help` before assuming such a field exists; falls back to a README/ARCHITECTURE_CONTRACTS.md-documented requirement instead of inventing a manifest field. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-23-hardening-sweep.md
```
