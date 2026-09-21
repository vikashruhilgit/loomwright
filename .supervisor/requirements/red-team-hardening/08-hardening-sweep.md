# 08 — Hardening sweep: Floor GET Host check, bot-author regex, telemetry body, description card, platform pin

## Status: pending

> Five small, independent fixes bundled because each is under an hour and none changes a contract. Sequenced
> after 02 (shares `send-telemetry-core.sh`). If the Supervisor's overlap check wants them split, split by
> file, not by finding.

## Problems (each verified 2026-09-21)
1. **Floor GET has no Host check.** `scripts/setup-ui.sh` `_guard()` (token + Origin + Host) runs only in
   `do_POST`; `SimpleHTTPRequestHandler` answers every GET, so a DNS-rebinding page can read `index.json`
   (registered project paths, run state), `serve.log`, and the served UI. The header (line ~245) accepts
   "a bare address still reads everything" — that is the leak.
2. **Bot-author regex is loose.** `classify-bot-review.sh` `bot_author_re: "^claude(\\[bot\\])?$|\\[bot\\]$|
   ^github-actions"` trusts a human login literally `claude` and any login *starting with* `github-actions`.
   (Whether GitHub reserves those is UNVERIFIED — tighten regardless.)
3. **Telemetry posts the whole result block.** `send-telemetry-core.sh` `raw_data.result_block =
   redacted_block` (lines ~670–684) ships file paths, finding descriptions and subtask names to a GitHub
   issue behind nine regexes. A regex allowlist is a secret scanner, not a privacy boundary.
4. **`plugin.json` description is 3,131 chars** of accreted release narrative; CLAUDE.md §"Plugin
   `description` is a summary, not a changelog" forbids exactly this and no gate checks it.
5. **Unpinned platform coupling.** 14 scripts depend on undocumented hook-payload fields
   (`last_assistant_message`, `agent_transcript_path`, `session_id` placement); no minimum Claude Code
   version is declared; `claude-code-action@v1` floats a major. A silent upstream change turns fail-SAFE
   emitters into green no-ops.

## Scope
1. **Floor:** override `do_GET`/`do_HEAD` in `FloorHandler` to call `_host_ok(self.headers.get("Host"))`
   first and answer `403` with the existing `host-not-loopback` refusal JSON otherwise; `audit()` one line.
   `test-setup-ui.sh`: a GET with `Host: evil.example` ⇒ 403; with `Host: 127.0.0.1:<port>` ⇒ 200; the four
   POST routes unchanged. Header comment paragraph updated (the "bare address reads everything" sentence
   becomes "a bare *loopback* address reads everything; a rebound name does not").
2. **Classifier:** `bot_author_re` becomes exact-login: `^(claude\[bot\]|github-actions\[bot\]|
   dependabot\[bot\])$` plus any login ending in `[bot]` — i.e. drop the bare `^claude$` and the
   `^github-actions` prefix. `test-classify-bot-review.sh`: `claude` (human) ⇒ excluded;
   `github-actions-fan` ⇒ excluded; `claude[bot]`, `github-actions[bot]`, `anything[bot]` ⇒ included.
   (Item 01's `--trusted-actors` file, when present, supersedes this regex entirely.)
3. **Telemetry body:** `raw_data` drops `result_block`; keeps the already-structured fields (`schema`,
   `score*`, `status`, `primary_error` truncated to 200 chars, `issues` count per severity, `tools`).
   A user-scope consent key `include_result_block: true` (in the item-02 `egress.json` entry, set only via
   `/telemetry enable --include-result-block`, printed by `status`) restores the old body. `docs/TELEMETRY.md`
   §Privacy rewritten: the regex list is a secret tripwire; the body's privacy comes from field selection.
   `test-send-telemetry-core.sh`: default body has no `result_block` key; with the consent key it does.
4. **Description card:** rewrite `plugin.json` and `marketplace.json` `description` to ≤ 400 chars (what it
   is, the four counts, "history in CHANGELOG.md"). `scripts/check-doc-currency.sh`: fail when either
   description exceeds 600 chars or contains more than one `v\d+\.\d+\.\d+` token; CLAUDE.md §anti-rebloat
   paragraph gains "(length gated by `check-doc-currency.sh`)".
5. **Platform pin + payload contract test:** `plugin.json` gains the manifest field Claude Code documents for
   a minimum CLI version IF one exists (read the plugin-manifest docs via the `claude-code-guide` agent or
   `claude plugin validate --help` in the implementing session; if none exists, record the required version
   in README §Requirements and in `docs/ARCHITECTURE_CONTRACTS.md`). New `scripts/test-hook-payload-contract.sh`:
   for each hook script that reads a payload field, assert the field name appears in the recorded fixtures
   under `scripts/progress-event-fixtures/` (the 2026-09-02 spawn probe) — a field read by a script but
   absent from every fixture fails, so a rename upstream is caught by re-recording fixtures, not by a silent
   no-op. Pin `anthropics/claude-code-action` to a full tag or SHA in both workflows with a one-line
   comment naming the date and why.
6. CHANGELOG paragraph per fix; one version bump.

## Non-goals
No change to Floor POST guards, to the interest filter, to the classifier's `[]` fail-safe contract, or to
the hooks leaf count.

## Acceptance criteria
- `test-setup-ui.sh` GET/Host cases pass; `test-classify-bot-review.sh` five login cases pass;
  `test-send-telemetry-core.sh` body cases pass; `check-doc-currency.sh` fails on a 601-char description
  fixture and passes on the new card; `test-hook-payload-contract.sh` passes and fails when a script is
  edited to read a field no fixture carries (mutation control).
- `python3 -c 'import json;print(len(json.load(open("loomwright/.claude-plugin/plugin.json"))["description"]))'`
  ≤ 400.
- Both workflows reference `anthropics/claude-code-action@<tag-or-sha>`, not `@v1`.
- Full test loop + root checks green (`check-vendor-coupling.sh` included — the payload-contract test must not
  add a literal `${CLAUDE_PLUGIN_ROOT}` to a core comment).

## Verified premises
- `setup-ui.sh` `FloorHandler` (`do_POST` only calls `_guard`; `_host_ok` exists; `REFUSALS["host-not-loopback"]`).
- `classify-bot-review.sh` jq block; `test-classify-bot-review.sh` exists.
- `send-telemetry-core.sh` `raw_data` dict; `PRIVACY_PATTERNS` (9 regexes); `--dry-run` path.
- `plugin.json` description length 3,131; `check-doc-currency.sh` scans version/count claims only.
- `scripts/progress-event-fixtures/spawn-probe-2026-09-02/` exists (memory `subagentstop-payload-shape`).
