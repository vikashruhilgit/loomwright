# Supervisor Job: Pin the mysql-mcp package, drop --refresh, state the read-only honest limit

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: feature/red-team-07-mysql-mcp-pin (== origin/main @ 74da8ae)
- **GitHub CLI:** ✓ Authenticated (vikashruhilgit)
- **Blockers:** 0 | **Warnings:** 0
- **Source requirement:** .supervisor/requirements/red-team-hardening/07-mysql-mcp-pin.md

## Feasibility (optional — Launch Pad v10.3+)

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Pure JSON/markdown edits + one `uvx`/PyPI read already performed during planning; no code changes to the loomwright plugin itself. |
| 2 | Dependency Availability | GO | `uvx`/`uv 0.10.7` confirmed present and working in this environment; `jq` already required repo-wide. |
| 3 | Architecture Fit | GO | `mysql-mcp/` is a standalone sibling plugin (confirmed: only `.mcp.json`, `README.md`, `.claude-plugin/plugin.json` — no source, per requirement's own "Verified premises"); pinning its launch args is a self-contained, in-repo change. |
| 4 | Scope vs Supervisor Capability | GO | 6 files, all small edits (JSON args, two README sections, two version bumps, one setup.md status-cell tweak, one check-doc-currency.sh assertion) — well under the Decomposition Threshold's context-bound guideline. Single subtask, no split needed. |
| 5 | Hard Blockers | GO | No migration framework, no new credentials, no missing modules. Current published PyPI version independently verified during planning (see below) — not guessed. |

**Overall Verdict:** GO

## Task
**Goal:** Pin `mysql-mcp/.mcp.json`'s `uvx` invocation to an exact, reviewed PyPI version (drop `--refresh`), and make the README honestly state where read-only enforcement lives and that this repo does not verify it.

**Problem Statement:**
Operators installing the `mysql-mcp@atelier` plugin need the server version that launches on every Claude Code session start to be a specific, reviewed release — not whatever PyPI happens to resolve at that moment. Currently `mysql-mcp/.mcp.json:4` reads `"args": ["--from", "vikashruhil-mysql-mcp", "--refresh", "mysql-mcp"]`: no version pin, and `--refresh` forces `uvx` to re-resolve the latest release on every start. The process receives `DB_HOST`/`DB_USER`/`DB_PASS`/`DB_NAME` from the environment — a compromised publisher account or a bad release ships straight into a credentialed process on every launch, and nothing in this repo can verify the server's own "read-only" claim (the implementation lives on PyPI, outside this repo). Success looks like: the plugin launches a specific version by default, upgrading it is a visible, reviewed diff in this repo (not a silent runtime re-resolve), and the README says plainly that read-only enforcement is the PyPI package's own responsibility, unverified here.

**Independently verified during planning (not guessed, per the source requirement's explicit instruction):**
- `curl -s https://pypi.org/pypi/vikashruhil-mysql-mcp/json | python3 -c "...d['info']['version']..."` → current published version is **`1.0.1`**. Full release list: `1.0.0`, `1.0.1`.
- `uvx --help` confirms `-c`/`--constraint <CONSTRAINTS>` exists but takes a **requirements file path**, constraining transitive dependency resolution — not a single inline hash pin for the `--from` package itself. There is no `uvx --from pkg==X.Y.Z --hash <sha256>` inline flag. An exact-version `==` pin (already the strongest inline mechanism `uvx --from` supports) is the correct scope; a full hash-verified install would require restructuring this as a `uv`-managed project with a lockfile, which conflicts with the lightweight single-command MCP launcher design this plugin intentionally uses — document this as the "why not" honest limit per Scope item 1's explicit instruction, do not silently omit it.
- `mysql-mcp/.claude-plugin/plugin.json` current version: `1.0.0`. `.claude-plugin/marketplace.json` (repo root) mysql-mcp entry: also `1.0.0` — the two are currently in lockstep and must stay that way.
- `scripts/check-doc-currency.sh` (repo root): its `FILES`/authoritative-version scan is scoped to the **loomwright** plugin only (`grep -n "mysql-mcp" scripts/check-doc-currency.sh` → 0 hits) — it does NOT scan mysql-mcp's or stackpack's own version claims. Per Scope item 4's explicit either/or instruction, this means the NEW one-line assertion (that `.mcp.json` carries `==`, no floating dependency) must be added — it is not already covered.
- `loomwright/commands/setup.md` line 85 (module 6, mysql-mcp) currently only reports which `DB_*` env vars are unset; line 106 is the dashboard row with a `<derived>` placeholder. Neither currently reads or prints the pinned version.

## Acceptance Criteria
- [ ] Given `mysql-mcp/.mcp.json`, when read with `jq -r '.mcpServers.mysql.args[]'`, then the output contains an element with a `==` pin (e.g. `vikashruhil-mysql-mcp==1.0.1`) and no `--refresh` string appears anywhere in the args array.
- [ ] Given `mysql-mcp/README.md`, when read, then it contains a "Supply chain" section (the pin, how to bump it — edit `.mcp.json`, bump `mysql-mcp/.claude-plugin/plugin.json`, add a CHANGELOG-equivalent line) and an "Honest limits" section (read-only behavior is enforced inside the PyPI package, this repo neither vendors nor tests it; the `DB_USER` grant should itself be read-only at the database level; and the uvx-constraint-vs-hash-pin honest limit from the Problem Statement's verified premises).
- [ ] Given `mysql-mcp/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`'s mysql-mcp entry, when compared, then both report the SAME version (matching whatever `.mcp.json`'s pin resolves to at implementation time, e.g. `1.0.1`) and the plugin.json `description` field includes the literal substring `pinned to` followed by the version.
- [ ] Given `scripts/check-doc-currency.sh`, when run, then it exits 0 (green) AND contains a NEW assertion (grep-visible) that `mysql-mcp/.mcp.json`'s args carry a `==` pin — never a floating/unpinned `--from vikashruhil-mysql-mcp` alone.
- [ ] Given `loomwright/commands/setup.md`'s mysql-mcp module (module 6, ~line 85) and its dashboard row (~line 106), when the status cell is derived, then it additionally reports the pinned version read from `.mcp.json` via `jq` (e.g. `configured (pinned v1.0.1)` / `missing: DB_HOST (pinned v1.0.1)`).
- [ ] Given the full existing test loop (`loomwright/scripts/test-*.sh` + root `scripts/test-*.sh` + `scripts/check-vendor-coupling.sh`), when run, then all suites are green with zero regressions.

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Pin mysql-mcp, drop --refresh, document honest limits | all | 7 modify, 0 create | none needed (plain JSON/markdown edits) | LAUNCHABLE |

```yaml
# Subtask 1 — Pin mysql-mcp (LAUNCHABLE, sole subtask)
provides:
  - {kind: "file", path: "mysql-mcp/.mcp.json"}
  - {kind: "file", path: "mysql-mcp/README.md"}
  - {kind: "symbol", path: "mysql-mcp/README.md", name: "Supply chain"}
  - {kind: "symbol", path: "mysql-mcp/README.md", name: "Honest limits"}
  - {kind: "file", path: "mysql-mcp/.claude-plugin/plugin.json"}
requires: []
lanes:
  - "mysql-mcp/.mcp.json"
  - "mysql-mcp/README.md"
  - "mysql-mcp/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "loomwright/commands/setup.md"
  - "scripts/check-doc-currency.sh"
  - "CLAUDE.md"
external_requires: []
```

### File Impact Map

**Modify:**
- `mysql-mcp/.mcp.json` — change `"args": ["--from", "vikashruhil-mysql-mcp", "--refresh", "mysql-mcp"]` to `"args": ["--from", "vikashruhil-mysql-mcp==1.0.1", "mysql-mcp"]` (drop `--refresh` entirely; re-verify the current PyPI version at implementation time with `curl -s https://pypi.org/pypi/vikashruhil-mysql-mcp/json | python3 -c "import json,sys;print(json.load(sys.stdin)['info']['version'])"` in case it moved since planning — do not blindly trust the `1.0.1` cited here without one fresh check).
- `mysql-mcp/README.md` — add a "Supply chain" section (pin location, bump procedure: edit `.mcp.json`, bump `plugin.json` + `marketplace.json` version, add a changelog-equivalent line since this sibling plugin has no `CHANGELOG.md` of its own — confirm via `ls mysql-mcp/` whether one exists before assuming) and an "Honest limits" section (read-only enforcement lives in the PyPI package, unverified by this repo; `DB_USER` should be a read-only DB grant; `uvx`'s `--constraint` mechanism constrains transitive deps via a requirements file, not a single-package hash pin — an exact `==` version pin is the practical mechanism here).
- `mysql-mcp/.claude-plugin/plugin.json` — version `1.0.0` → `1.0.1`; append `"— pinned to \`==1.0.1\`"` (or similar) to the `description` field so the literal substring `pinned to` is present.
- `.claude-plugin/marketplace.json` (repo root) — mirror the mysql-mcp plugin entry's version `1.0.0` → `1.0.1` in the SAME commit (lockstep, per the project's own release-surfaces convention).
- `loomwright/commands/setup.md` — module 6 (mysql-mcp, ~line 85): after computing the `configured`/`missing: <names>` status, read the pinned version from `mysql-mcp/.mcp.json` via jq (e.g. `jq -r '.mcpServers.mysql.args[] | select(contains("=="))' mysql-mcp/.mcp.json` then strip to the version) and append `(pinned vX.Y.Z)` to the status cell; update the dashboard row template (~line 106) and the worked status-cell examples in the surrounding prose consistently.
- `scripts/check-doc-currency.sh` (repo root) — add one new assertion (independent of the existing loomwright-scoped `FILES` scan) that `mysql-mcp/.mcp.json`'s `mcpServers.mysql.args` contains an element matching `==` (a `jq`/grep check) — fail the gate if the args array has `--from vikashruhil-mysql-mcp` with no `==` suffix or if `--refresh` reappears.
- `CLAUDE.md` (line ~32, the sibling-plugins bullet under "Plugin Layout") — currently hand-restates `mysql-mcp/` (read-only MySQL MCP server `vikashruhil-mysql-mcp`, v1.0.0)`; bump the restated version number to match the new pin so this line doesn't go stale on merge (no existing `check-doc-currency.sh` regex catches this specific phrasing — confirmed at Plan Review).

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | none needed — plain JSON/markdown edits, no framework-specific skill applies |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| PyPI version may have moved between planning and implementation | LOW | Worker re-verifies via the PyPI JSON API (or `uvx --from vikashruhil-mysql-mcp mysql-mcp --version`) at implementation time rather than trusting the `1.0.1` cited in this brief verbatim — instructed explicitly in the File Impact Map. |
| `check-doc-currency.sh` new assertion could be too loose (misses a re-introduced `--refresh` or a non-`==` pin) or too strict (breaks on a legitimate future syntax like `@` version specifiers) | LOW | Worker should test the new assertion against BOTH the current pinned state (must pass) and a deliberately-reverted `--refresh`/unpinned mutant (must fail) before finalizing — same mutation-control discipline used elsewhere in this run's items. |
| mysql-mcp has no `CHANGELOG.md` of its own (unconfirmed at planning time) | LOW | Worker verifies with `ls mysql-mcp/` before writing bump instructions in the README's "Supply chain" section — phrase the bump procedure to match whatever actually exists (plugin.json + marketplace.json version bump, and a changelog line only if a changelog file exists). |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-09-22-mysql-mcp-pin.md
```

---

## Outcome
- **Status:** completed
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/255
- **Reconciled:** lifecycle move completed by reconcile-jobs.sh, not by the completion tail
- **Evidence:** automate engine supplied merge evidence for .supervisor/requirements/red-team-hardening/07-mysql-mcp-pin.md (https://github.com/vikashruhilgit/loomwright/pull/255) — the engine verified the PR merged against the forge; this reconciler stayed offline
- **Caveat:** fields the completion tail would have recorded (files changed, heal decision and iterations, red-team advisory) are NOT recoverable after the fact and are deliberately omitted rather than invented.
