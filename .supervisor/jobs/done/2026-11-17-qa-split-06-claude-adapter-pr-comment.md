# Supervisor Job: `/selvedge:verify` with a separate Bash+Read verifier, and `selvedge comment` posting ONE text-only, updated-in-place PR comment (qa-split item 06)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** dirty (2 untracked dirs: `reports/`, `research_notes/`, unrelated), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 2 (untracked dirs; 5 linked worktrees on unrelated branches)
- **Source requirement:** .supervisor/requirements/qa-split/06-claude-adapter-and-one-text-only-pr-comment.md
- **Base commit:** 304eb74910e66b52b380c208e443927e0dc397fd

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Selvedge is Node >= 18 standard library + a bash 3.2 dispatcher (`selvedge/bin/selvedge`). The comment command shells out to `gh` exactly as `selvedge criteria from-pr` already does (`execFileSync('gh', ['pr', 'view', n, '--json', 'body']` in `selvedge/lib/criteria.mjs`). The adapter is plain plugin markdown (`commands/`, `agents/`, `skills/` at the plugin root). |
| 2 | Dependency Availability | GO | No new dependency. `gh` 2.102.0 is installed; tests use a PATH `gh` stub (the pattern in `selvedge/tests/test-criteria.sh`: `cat > "$STUB/gh" <<'EOF'`). |
| 3 | Architecture Fit | GO | `verdict.json` already carries every per-criterion field the comment shows (`interpretation`, `unverified_assumptions[].material`, `steps[].type`, `expected`, `matched`, `evidence_class`, `reason`, `read_value`) plus `plan_sha256`, `plan_revision` and `prior_revisions` (`selvedge/schemas/verdict.schema.json`); step locators come from the run folder's `plan.json`, criterion text from its `criteria.json` (`RUN_FILES` in `selvedge/lib/plan-runs.mjs`). `loadConfig({ base })` already reads `<base>:selvedge.json` (`selvedge/lib/env-config.mjs`). |
| 4 | Scope vs Supervisor Capability | CAUTION | 17 files (8 modify, 9 create), above the 12-file single-worker bound: split `context-bound` into 2 sequential subtasks. |
| 5 | Hard Blockers | CAUTION | Not a blocker, but (a) the plan needs files outside the requirement's `## Touches` (`env-config.mjs` for the config key and reasons, `test-env.sh`, `bin/selvedge`, `README.md`, the release surfaces, `selvedge/skills/SKILLS_INDEX.md`, one evidence file) — asked once at Phase 6 (`LP-SCOPE`); (b) the `/selvedge:verify` ≡ hand-run criterion needs a live Claude Code session, which CI cannot run, so its proof is a committed evidence file, not a CI test. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add `selvedge comment <run-dir> --pr <n>` (one PR comment found by `<!-- selvedge:verdict -->`, created once and updated in place, text evidence only, no raw page values unless a private repo opts in through the base branch's `selvedge.json`, revisions shown) and the Claude Code adapter: `/selvedge:verify [criteria source]`, a verifier subagent whose tools are exactly Bash and Read, and `selvedge/skills/verify/SKILL.md` carrying the same workflow for any agent host — released as selvedge 0.6.0.

**Problem Statement:**
The owner (and later the item 10b CI entry) needs a selvedge verdict shown on the PR by an agent that did not write the code, because the implementing agent checks its own mental model (D8), and a public PR comment must show the work without leaking cookies, PII or page values (D13, N8).
Currently, selvedge stops at a local `verdict.json`: there is no command, no subagent, no skill and no way to put the verdict on a PR, so every verdict is invisible unless someone opens `.selvedge/runs/`.
Success looks like: two `selvedge comment` runs on the same PR leave exactly one selvedge comment (updated), its body carries no link, header, request body or page value by default, a revised criterion reads `FAIL on plan 1 → PASS on plan 2`, the verifier's tools are exactly Bash and Read, and a real `/selvedge:verify` session produces the same per-criterion verdicts as the CLI run by hand on the same frozen plan — each proven by a test in `selvedge/tests/`, except the last, which is a committed evidence file.

## Design decisions
- decision: Where the comment code lives (T2 new modules)
  chosen: two new modules — `selvedge/lib/comment-render.mjs` (pure: `renderComment(run)` → body string with the marker, the summary line, one `<details>` block per criterion, the revisions cell, and `redactValue(value, patterns)` with the default patterns; no I/O, no `gh`) and `selvedge/lib/comment.mjs` (the `selvedge comment` command: args, run-folder reads, base-branch config, visibility check, confirmation, `gh` find / create / update)
  rejected: one module — every render case would then need a `gh` shim and a temp repo to test; test cost no
  rejected: render inside `selvedge/lib/verdict.mjs` — it is 355 lines and owns verdict derivation from evidence only ("no model writes it"); output formatting is a separate concern; blast radius partial
  rejected: reuse `redactValues(text, secrets)` (`selvedge/lib/snapshot.mjs`) or `selvedge/lib/runner/trace-redact.mjs` — both blank out KNOWN secret values or headers; the comment needs pattern-based PII redaction of unknown values (emails, digit runs, query strings, tokens), a different job; fits-stack no
  evidence: `grep -n "^export" selvedge/lib/verdict.mjs` → `VERDICTS`, `EVIDENCE_CLASSES`, `countVerdicts`, `VERDICT_FILE` exist and are imported (never copied) by `comment-render.mjs`; `RUN_FILES` (`criteria: 'criteria.json'`, `plan: 'plan.json'`) from `selvedge/lib/plan-runs.mjs`
  revisit when: a second output format (the post-MVP export, P9) needs the same per-criterion rows
  status: confirmed
- decision: How the one comment is found and updated (T3 external integration: GitHub PR comments through `gh`)
  chosen: list `gh api --paginate repos/{owner}/{repo}/issues/<n>/comments` (gh's own `{owner}/{repo}` substitution), take the FIRST comment whose body contains `<!-- selvedge:verdict -->` and update it with `gh api -X PATCH repos/{owner}/{repo}/issues/comments/<id> -F body=@<tmpfile>`; when none has the marker, create one with `gh pr comment <n> --body-file <tmpfile>`. The body always travels as a file argument via `execFileSync(…, [args])`, never a shell string or hand-built JSON
  rejected: `gh pr comment <n> --edit-last --create-if-none` — it edits "the last comment of the current user" (`gh pr comment --help`), so it would overwrite an unrelated comment by the same account; correctness no
  rejected: a new comment per run with the old one deleted — notifies on every run and loses the in-place history P5 asks for; fits-stack partial
  evidence: `gh pr comment --help` → `--edit-last  Edit the last comment of the current user`; lesson [a7e4fb1c] (security): PR text into a `gh` call is built with argument arrays / files, never shell-templated
  revisit when: item 10b posts from a GitHub Action with `GITHUB_TOKEN`, whose author differs from a local run's
  status: confirmed
- decision: Where `comment.read_values` is read from (T4 cross-cutting: trust boundary of the opt-in)
  chosen: `selvedge comment` loads the config with `loadConfig({ base })`, `base` = `--base <ref>` when given, else `origin/<baseRefName>` from `gh pr view <n> --json baseRefName`; the working tree's `selvedge.json` is never read by `comment`
  rejected: the working tree's `selvedge.json` — a PR branch could opt itself in to publishing page values; correctness no
  evidence: `selvedge/lib/env-config.mjs` header of `loadConfig`: "With `base`, the config is the committed `<base>:selvedge.json` (git show) and the working tree is never read, so a PR branch cannot widen its own allowlist"; reason `base_config_unreadable` already exists for a missing `<ref>:selvedge.json`
  revisit when: item 10b runs in CI, where `origin/<base>` must be fetched first
  status: confirmed
- decision: How the verifier declares its token budget (T5: hand-rolling what the harness provides)
  chosen: the harness's own `maxTurns:` frontmatter key bounds the run, plus a selvedge-owned `token_budget:` frontmatter integer that `selvedge/tests/test-adapter.sh` checks against the prompt's measured size (bytes / 4, the proxy Loomwright's `check-token-budget.sh` uses); `model: inherit`
  rejected: a selvedge copy of Loomwright's `check-token-budget.sh` / `prompt-token-budgets.json` — selvedge imports nothing from Loomwright (D4) and one agent does not justify a budget registry; reversibility no
  evidence: `scripts/check-token-budget.sh` scans only `loomwright/agents` (`AGENTS_DIR="${TOKEN_BUDGET_AGENTS_DIR:-loomwright/agents}"`, `selvedge/docs/evidence/gate-scopes.md`), so no root gate covers a selvedge agent; Loomwright agents use `maxTurns:` (`loomwright/agents/launch-pad.md` frontmatter)
  revisit when: selvedge ships a second agent
  status: confirmed

## Acceptance Criteria
- [ ] AC1 — Given `selvedge.json` with `"comment": {"read_values": true, "redact": ["ORD-[0-9]+"]}`, when any command loads it (`loadConfig`), then it is accepted: `comment` is in `CONFIG_KEYS` and in `selvedge/schemas/selvedge-config.schema.json` (`"additionalProperties": false` inside it; the existing key-set equality test in `selvedge/tests/test-env.sh` still passes), `read_values` defaults to `false` when absent, `redact` defaults to `[]`; an unknown `comment` sub-key, a non-boolean `read_values`, a non-array `redact` or a `redact` entry that is not a string compiling as a JS `RegExp` is refused `config_schema_violation` (exit 2).
- [ ] AC2 — Given a `gh` PATH stub that keeps a PR's comments in a temp JSON file and records every argv, and a fixture run folder (`criteria.json`, frozen `plan.json` + `plan.sha256`, `verdict.json`), when `selvedge comment <run-dir> --pr 42 --yes` runs twice (the second time after the run folder's `verdict.json` changed), then the stub holds exactly ONE comment containing `<!-- selvedge:verdict -->`, its body is the second run's body, the second run issued a PATCH to that comment's id and no second create; and a pre-existing comment by the same account without the marker is unchanged byte for byte.
- [ ] AC3 — Given a run folder whose plan has a `goto` to `http://localhost:<port>/account?token=abc`, a `fill` with value `{{APP_PASS}}` (with `APP_PASS` set to a distinct fixture secret in the environment) and a `fill` with a literal value, when `selvedge comment` renders the body, then the body contains no `http://` or `https://` substring (a `goto` shows only its URL's path, no origin and no query string; the same URL-to-path rewrite applies to every free-text field the body renders — criterion text, interpretation, assumption text and the expected value — so a fixture criterion whose text and expected value contain `https://shop.example.test/cart?id=9` render `/cart`), no `Cookie`, `Set-Cookie` or `Authorization` (case-insensitive), not the `APP_PASS` value, no `fill` / `select` value (those steps show type + locator only), and no evidence file name (`.png`, `trace.zip`, `evidence.jsonl`); and it does contain the one-line summary (`<n> PASS · <n> FAIL · …`, zero counts omitted) and one `<details>` block per criterion with: criterion text, interpretation, unverified assumptions (material ones marked), steps (types + locators), expected value (op + value from the plan), matched yes/no, verdict, `evidence_class`, the reason and its unblock hint for BLOCKED / NOT_VERIFIABLE, and the short plan sha256 (first 12 hex) and revision.
- [ ] AC4 — Given the default config (no `comment` key) and a run folder whose `verdict.json` `read_value`s are a fixture email (`jane.doe` at `example.test`) and a fixture name (`Jane Doe`), when `selvedge comment` posts, then neither string appears anywhere in the posted body.
- [ ] AC5 — Given `"comment": {"read_values": true}` on the base branch's `selvedge.json` and a `gh` stub whose `gh repo view --json visibility` reports `PUBLIC`, when `selvedge comment <run-dir> --pr 42 --yes` runs, then it exits 2 with `read_values_public_repo` on stderr and the stub recorded no create and no PATCH (any visibility other than `PRIVATE` — `PUBLIC`, `INTERNAL`, or an unreadable answer — is refused the same way: fail closed); with `--allow-public-values` added (or the stub reporting `PRIVATE`), it posts and each read value appears only after redaction: the defaults replace an email, a run of 6+ digits, a URL query string and a base64 / hex token of 32+ characters with `[redacted]`, and a configured `redact` pattern (`ORD-[0-9]+`) is applied on top of the defaults; and given the opt-in only in the working tree (not on the base ref), read values stay unpublished.
- [ ] AC6 — **Per-criterion revision history (owner decision, Launch Pad Phase 6, 2026-11-17):** `verdict.json`'s top-level `prior_revisions` lists the earlier revisions with each one's OVERALL run verdict (`priorRevisions()` in `selvedge/lib/verdict.mjs` reads the `event: "run"` line), so the comment never paints that overall verdict onto every criterion. Instead, for each revision `r` in `prior_revisions`, `selvedge comment` finds that revision's own run line in `<repo root>/.selvedge/runs.jsonl` (`event: "run"`, same `criteria_sha256`, `plan_revision: r`, `replay_of: null` — the same match `priorRevisions` uses) and reads the criterion's own verdict from `.selvedge/runs/<run_id>/verdict.json` `criteria[<id>].verdict` (criterion ids are stable for the same `criteria_sha256`). Given a run folder on `plan_revision: 2` with two criteria A and B, both `PASS` now, where plan 1's own run folder has A `FAIL` and B `PASS`, when the body renders, then A's verdict cell reads exactly `FAIL on plan 1 → PASS on plan 2` and B's reads `PASS on plan 1 → PASS on plan 2` (never a bare `PASS` while `prior_revisions` is non-empty); the summary counts A under its own label `1 PASS after revision` and B in the plain `PASS` count (a criterion is "PASS after revision" when it is `PASS` now and its own verdict on some earlier plan was not `PASS`); a revision whose `verdict` is `null` (it never ran) renders `not run on plan <r>`; and when that revision's run folder or its `verdict.json` or the criterion's entry is missing, the cell shows the run-level verdict labelled as such, `FAIL on plan 1 (whole run) → PASS on plan 2`, and the criterion is counted in the plain `PASS` count.
- [ ] AC7 — Given no `--yes`, when `selvedge comment` runs with stdin not a terminal, then it exits 2 with `comment_requires_yes` on stderr and posts nothing; given an interactive confirmation (the confirm function injectable, as `signedInGate` takes `readLine`) answered anything but `y`, it posts nothing and exits 0; given a run folder with no `verdict.json` it exits 2 `verdict_missing`, and with a `plan.json` whose sha256 differs from `verdict.json`'s `plan_sha256` it exits 2 `plan_modified`, posting nothing in both; a failing `gh` exits 1.
- [ ] AC8 — Given `selvedge/agents/verifier.md`, when its frontmatter is parsed by `selvedge/tests/test-adapter.sh`, then `tools` is exactly `Bash, Read` (no other tool), `maxTurns` and `token_budget` are integers and the prompt's measured size (bytes / 4) is within `token_budget`; its body forbids editing `plan.json` after `plan --freeze` and forbids reading `~/.local/state/selvedge/`; the ordered list of `selvedge <command>` invocations it prescribes (`criteria`, `plan --init`, `snapshot` (with `--run-dir <the folder plan --init printed>`), `plan --validate`, `plan --freeze`, `run`, `verdict`) is the same, in the same order, as in `selvedge/skills/verify/SKILL.md`; `selvedge/commands/verify.md` names the verifier by exactly the `subagent_type` string the AC9 evidence file records; and `selvedge/commands/verify.md` resolves a PR number / file / pasted text to `selvedge criteria from-pr | from-md | from-text`, spawns the verifier, reports the verdict table, and posts only through `selvedge comment … --yes` after asking (never on by default).
- [ ] AC9 — Given the item 04 fixture app (`selvedge/tests/fixtures/app-server.mjs`) and a criteria file, when `/selvedge:verify <criteria file>` runs in a real Claude Code session and the same frozen plan is then run by hand with the CLI's own re-run path, `selvedge run --replay <the verifier's run folder>` + `selvedge verdict <the new folder>` (a copied folder is refused `plan_modified` by `assertFreezeLine` in `selvedge/lib/runner/run.mjs`: "replay that folder"), then a committed evidence file `selvedge/docs/evidence/verify-adapter-equivalence.md` contains the commands, the subagent type the session used, both `verdict.json` files' `plan_sha256` (equal), and the empty output of `diff <(jq -S 'del(.criteria[].steps[].duration_ms) | .criteria' <session verdict.json>) <(jq -S 'del(.criteria[].steps[].duration_ms) | .criteria' <hand-run verdict.json>)` — "the same `verdict.json`" means the same `plan_sha256` and the same per-criterion objects with step `duration_ms` excluded (wall-clock time differs run to run) and the run-level `replay_of` differing by construction — and the PR body links to it.
- [ ] AC10 — Given the change, when `bash selvedge/tests/run.sh` and `bash scripts/check-skills-index-sync.sh` run, then both pass: `selvedge/skills/SKILLS_INDEX.md` exists with one row for `verify/` (generated by `check-skills-index-sync.sh --write`); `selvedge/README.md` documents `selvedge comment`, the `comment` config key, `/selvedge:verify`, the verifier and the skill, and its reasons table has `read_values_public_repo`, `comment_requires_yes` and `verdict_missing` rows (its README-sync arm stays green); and selvedge is released as 0.6.0 (`selvedge/.claude-plugin/plugin.json`, its `.claude-plugin/marketplace.json` entry, and a `## 0.6.0 — <date>` heading in `selvedge/CHANGELOG.md`); and a `test-adapter.sh` arm (no root gate checks selvedge's description: `scripts/check-doc-currency.sh` reads only `select(.name == "loomwright")`) asserts that `selvedge/.claude-plugin/plugin.json`'s `description` is ≤ 600 characters, carries no `v<X>.<Y>.<Z>` token, and equals the `selvedge` entry's `description` in `.claude-plugin/marketplace.json` byte for byte (the description is 596 characters at base, so naming the comment command and the adapter means condensing the text, not appending to it).

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

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

## File Impact Map

| Group | Files to Modify (lines at base) | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| config + reasons | `selvedge/lib/env-config.mjs` (391 — `REASONS`, `CONFIG_KEYS`, a `COMMENT_KEYS` set, `comment` checks in `validateSchema` and the frozen normalized config), `selvedge/schemas/selvedge-config.schema.json` (58), `selvedge/tests/test-env.sh` (427 — only the `const want = [` reasons needle extended) | — | HIGH |
| comment command | `selvedge/bin/selvedge` (136 — one `comment` dispatch arm + usage line) | `selvedge/lib/comment-render.mjs`, `selvedge/lib/comment.mjs`, `selvedge/tests/test-comment.sh` | HIGH |
| Claude adapter | — | `selvedge/commands/verify.md`, `selvedge/agents/verifier.md`, `selvedge/skills/verify/SKILL.md`, `selvedge/skills/SKILLS_INDEX.md`, `selvedge/tests/test-adapter.sh`, `selvedge/docs/evidence/verify-adapter-equivalence.md` | HIGH (adapter files) / MEDIUM (`SKILLS_INDEX.md` layout — generated by `--write`) |
| docs + release | `selvedge/README.md` (719 — the single CLI doc; Subtask 1 adds the three reasons-table rows, the `comment` key bullet and the `selvedge comment` section; Subtask 2 the adapter section), `selvedge/CHANGELOG.md` (172), `selvedge/.claude-plugin/plugin.json` (15), `.claude-plugin/marketplace.json` (140) | — | HIGH |

Module layout: each new responsibility has one home — body rendering + redaction → `selvedge/lib/comment-render.mjs`; the command (args, config, visibility, confirmation, `gh`) → `selvedge/lib/comment.mjs`; the config key and reasons → `selvedge/lib/env-config.mjs` (391, under the threshold; the single authority for `REASONS` and config keys); verdict counts / names → reuse `VERDICTS`, `countVerdicts` from `selvedge/lib/verdict.mjs`; run-folder file names → reuse `RUN_FILES` from `selvedge/lib/plan-runs.mjs`; CLI flags → reuse `parseCliArgs`, the y/N read → reuse `readOneLine` (both `env-config.mjs`). `README.md` (719, past the threshold) gains only user docs — it is the single CLI doc, and its reasons table is pinned by `test-env.sh`. New tests go in new files (`test-comment.sh`, `test-adapter.sh`), not in `test-env.sh` (427) or `test-verdict.sh` (467).

New directories: `selvedge/commands/`, `selvedge/agents/` and `selvedge/skills/` do not exist at base; they are the plugin-root component directories Claude Code discovers by default (`selvedge/.claude-plugin/plugin.json` declares no custom paths).

> **Validator-owned surfaces:** acceptance depends on `selvedge/tests/check-release.sh` (version == CHANGELOG top heading), Loomwright's `scripts/validate-version.sh` (plugin.json version == marketplace entry), the new `selvedge/tests/test-adapter.sh` description arm (length, no version token, plugin.json == marketplace description; `scripts/check-doc-currency.sh` checks only Loomwright's description) and `scripts/check-skills-index-sync.sh`, which discovers `selvedge/skills/` through `.claude-plugin/marketplace.json` `.plugins[].source` and fails a `skills/` dir without a `SKILLS_INDEX.md` (`selvedge/docs/evidence/gate-scopes.md` records it skipping selvedge only because `selvedge/skills/` did not exist). All of their scanned files are in the map.

### File Overlap Detection

| Group A | Group B | Overlapping Files | Serialization Required |
|---------|---------|-------------------|----------------------|
| Subtask 1 | Subtask 2 | `selvedge/README.md` (Subtask 1: reasons rows, `comment` key bullet, `selvedge comment` section; Subtask 2: the adapter section — sequential, legal); Subtask 2's command and skill call `selvedge comment`, which Subtask 1 adds | YES — `requires` edges |

## Touched-file invariants

> Grounded at base `304eb74910e66b52b380c208e443927e0dc397fd`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`selvedge/lib/env-config.mjs`** — keep: `REASONS` is the one closed reason list, so `read_values_public_repo`, `comment_requires_yes` and `verdict_missing` are added there (config / usage group, beside `approve_requires_tty: 'approve_requires_tty',`) and `comment.mjs` imports them, never string literals; `validateSchema` refuses unknown keys (`unknown top-level key`) and must refuse an unknown `comment` sub-key the same way (a new frozen `COMMENT_KEYS`, as `AUTH_KEYS` is `export const AUTH_KEYS = Object.freeze(['env', 'signed_in_check']);`); `validateConfig` returns a frozen normalized config (`return Object.freeze({`) — add `comment` to it (frozen, `{ read_values: false, redact: [] }` when absent); mirror: `export const CONFIG_KEYS = Object.freeze([` and the JSON schema's `properties` are "a real second copy, not a tautology"; reuse: `parseCliArgs`, `readOneLine`, `loadConfig({ cwd, base })`, `EnvError`, `UsageError`; pinned by: `selvedge/tests/test-env.sh` `eq(Object.keys(s.properties), E.CONFIG_KEYS)`, `const want = [` and the README-sync arm (`README sync: every REASONS key has exactly one row`), so the three README rows land in the SAME subtask (Subtask 1) as the `REASONS` entries.
- **`selvedge/schemas/selvedge-config.schema.json`** — keep: `"additionalProperties": false` at the top level and inside the new `comment` object; mirror: `CONFIG_KEYS` in `selvedge/lib/env-config.mjs`; pinned by: `selvedge/tests/test-env.sh` `eq(Object.keys(s.properties), E.CONFIG_KEYS)`.
- **`selvedge/tests/test-env.sh`** — keep: hermetic temp HOME; only the `const want = [` list gains the three reasons (in `REASONS` order); its README-sync arm is unchanged and stays green because Subtask 1 adds the README rows with the reasons.
- **`selvedge/bin/selvedge`** — keep: bash 3.2, `set -uo pipefail`, "no jq, no `readlink -f`"; reuse: `cmd_node` (add `comment) shift; cmd_node comment "$@" ;;`, module `lib/comment.mjs`), and list `comment` in the header comment's Node-command list; keep the exit-code contract ("0 ok, 1 an operation failed, 2 usage error or BLOCKED"); keep the `*) printf 'selvedge: unknown command` arm last; pinned by: `selvedge/tests/test-cli.sh` (`unknown command exits 2`, `--version`, the no-argument help naming `install-cli`).
- **`selvedge/README.md`** — keep: the reasons table's row form `` | `<reason>` | <kind> | <meaning> | `` (the README-sync arm greps it); the `## \`selvedge.json\`` key list ends "No other key is accepted." — add a `comment` bullet before it; the `## Releasing` steps unchanged; pinned by: `selvedge/tests/test-env.sh` README-sync arm.
- **`selvedge/CHANGELOG.md`, `selvedge/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`** — keep: "Selvedge releases on its own", never through `changelog.d/`; the first `## <X.Y.Z> — <YYYY-MM-DD>` heading equals `plugin.json`'s `version`; the plugin and marketplace `description` stay identical, ≤ 600 characters, with no `vX.Y.Z` token (596 characters at base: condense, never append); only the `selvedge` entry of `marketplace.json` changes; pinned by: `selvedge/tests/check-release.sh` (`changelog_version_mismatch`; it checks the version only) and `scripts/validate-version.sh` (plugin.json version == the marketplace entry). No existing gate checks selvedge's description (`scripts/check-doc-currency.sh` reads only `select(.name == "loomwright")`), so the new `test-adapter.sh` description arm (AC10) is its pin.

## Closed enumerations touched

> Sibling grep at base `304eb74`: `git grep -n "approve_requires_tty" -- . ':!.supervisor'` → 6 hits in 4 files.

- **`read_values_public_repo`, `comment_requires_yes`, `verdict_missing`** (sibling: `approve_requires_tty`) — must be named in:
  - `selvedge/lib/env-config.mjs` — `REASONS` (`approve_requires_tty: 'approve_requires_tty',`) — extend (config / usage group).
  - `selvedge/tests/test-env.sh` — the `const want = [` exact reasons list — extend.
  - `selvedge/README.md` — the `## BLOCKED and config reasons` table (`| \`approve_requires_tty\` | usage |`) — extend, in Subtask 1 (pinned by the README-sync arm).
  - `selvedge/README.md` line in `## \`env\` commands` (`**\`approve\`** needs an interactive terminal`) and `selvedge/lib/env.mjs` (`failReason(REASONS.approve_requires_tty`) and `selvedge/tests/test-env.sh` (`grep -qF 'approve_requires_tty'`) — uses of the sibling itself — no change: not lists of reasons.
- **`comment`** (sibling config key: `allow_remote_mutation`; `git grep -n "allow_remote_mutation" -- selvedge`) — must be named in:
  - `selvedge/lib/env-config.mjs` — `CONFIG_KEYS` — extend.
  - `selvedge/schemas/selvedge-config.schema.json` — top-level `properties` — extend.
  - `selvedge/README.md` — the `## \`selvedge.json\`` key list ("No other key is accepted") — extend, in Subtask 1.
  - `selvedge/lib/env.mjs` (`env check` prints `allow_remote_mutation: …`; `env init` writes a starter config) — no change: `comment` is optional and off by default, `env check` prints only target-safety keys, and `init` writes no optional key it does not need.
  - `selvedge/lib/runner/proxy.mjs`, `selvedge/lib/runner/route-guard.mjs`, `selvedge/CHANGELOG.md` — uses of `allow_remote_mutation` itself — no change.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `selvedge/tests/test-env.sh` — reasons `want` list | delete `  comment_requires_yes: 'comment_requires_yes',` in `selvedge/lib/env-config.mjs` |
| `selvedge/tests/test-env.sh` — schema key set equals `CONFIG_KEYS` | flip `'hooks', 'auth', 'comment'])` → `'hooks', 'auth'])` in `selvedge/lib/env-config.mjs` |
| `selvedge/tests/test-comment.sh` — AC1 unknown `comment` sub-key refused | in `selvedge/lib/env-config.mjs`, delete the line that fails a `comment` key outside `COMMENT_KEYS` |
| `selvedge/tests/test-comment.sh` — AC2 second run updates, no second comment | in `selvedge/lib/comment.mjs`, delete the line that returns the id of the comment whose body contains the marker (every run then creates) |
| `selvedge/tests/test-comment.sh` — AC3 no `http(s)://` in the body | in `selvedge/lib/comment-render.mjs`, render a `goto` step's full `url` instead of its URL's `pathname` |
| `selvedge/tests/test-comment.sh` — AC3 no `fill` value | in `selvedge/lib/comment-render.mjs`, append the step's `value` to the rendered `fill` step |
| `selvedge/tests/test-comment.sh` — AC4 no read value by default | in `selvedge/lib/comment-render.mjs`, delete the line that omits `read_value` when `read_values` is false |
| `selvedge/tests/test-comment.sh` — AC5 public repo refused | in `selvedge/lib/comment.mjs`, delete the line that throws `REASONS.read_values_public_repo` |
| `selvedge/tests/test-comment.sh` — AC5 email redacted | in `selvedge/lib/comment-render.mjs`, delete the email pattern from the default redaction patterns |
| `selvedge/tests/test-comment.sh` — AC5 opt-in read from the base ref only | in `selvedge/lib/comment.mjs`, call `loadConfig({ cwd })` without `base` |
| `selvedge/tests/test-comment.sh` — AC1 non-boolean `read_values` refused | in `selvedge/lib/env-config.mjs`, delete the line that fails a `comment.read_values` that is not a boolean |
| `selvedge/tests/test-comment.sh` — AC1 non-array `redact` refused | in `selvedge/lib/env-config.mjs`, delete the line that fails a `comment.redact` that is not an array |
| `selvedge/tests/test-comment.sh` — AC1 non-compiling `redact` regex refused | in `selvedge/lib/env-config.mjs`, delete the line that fails a `comment.redact` entry whose `new RegExp(…)` throws |
| `selvedge/tests/test-comment.sh` — AC1 defaults `read_values: false`, `redact: []` | in `selvedge/lib/env-config.mjs`, flip the normalized default `read_values: false` → `read_values: true` |
| `selvedge/tests/test-comment.sh` — AC2 unmarked comment by the same account unchanged | in `selvedge/lib/comment.mjs`, select the last comment in the list (the `--edit-last` semantics) instead of the first whose body contains the marker |
| `selvedge/tests/test-comment.sh` — AC3 `APP_PASS` value absent | in `selvedge/lib/comment-render.mjs`, render a step locator with its `{{NAME}}` placeholders resolved from `process.env` |
| `selvedge/tests/test-comment.sh` — AC3 URL in criterion / interpretation / expected text shown path-only | in `selvedge/lib/comment-render.mjs`, delete the line that passes free text through the URL-to-path rewrite |
| `selvedge/tests/test-comment.sh` — AC5 digit run of 6+ redacted | in `selvedge/lib/comment-render.mjs`, delete the digit-run pattern from the default redaction patterns |
| `selvedge/tests/test-comment.sh` — AC5 URL query string redacted | in `selvedge/lib/comment-render.mjs`, delete the query-string pattern from the default redaction patterns |
| `selvedge/tests/test-comment.sh` — AC5 32+ char base64 / hex token redacted | in `selvedge/lib/comment-render.mjs`, delete the token pattern from the default redaction patterns |
| `selvedge/tests/test-comment.sh` — AC5 `INTERNAL` refused like `PUBLIC` | in `selvedge/lib/comment.mjs`, flip the refused-visibility check from "not `PRIVATE`" to "equals `PUBLIC`" |
| `selvedge/tests/test-comment.sh` — AC5 `PRIVATE` repo posts with redacted values | in `selvedge/lib/comment.mjs`, delete the line that passes `read_values: true` to `renderComment` when the repo is `PRIVATE` |
| `selvedge/tests/test-comment.sh` — AC5 configured `redact` pattern applied on top of the defaults | in `selvedge/lib/comment-render.mjs`, delete the line that appends the config's `redact` patterns to the default patterns |
| `selvedge/tests/test-comment.sh` — AC3 no `Cookie` / `Authorization` text | in `selvedge/lib/comment-render.mjs`, render each step's full JSON (`JSON.stringify(step)`) instead of type + locator, with a fixture step whose locator text is `Authorization` |
| `selvedge/tests/test-comment.sh` — AC3 no evidence file name | in `selvedge/lib/comment-render.mjs`, append the criterion's screenshot path from `evidence.jsonl` to its `<details>` block |
| `selvedge/tests/test-comment.sh` — AC6 per-criterion cell (B stays PASS → PASS, not FAIL → PASS) | in `selvedge/lib/comment-render.mjs`, use the `prior_revisions` entry's run-level `verdict` instead of the looked-up `criteria[<id>].verdict` |
| `selvedge/tests/test-comment.sh` — AC6 `PASS after revision` counted separately | in `selvedge/lib/comment-render.mjs`, delete the line that counts a criterion under `PASS after revision` |
| `selvedge/tests/test-comment.sh` — AC6 `not run on plan <r>` | flip `not run on plan` → `FAIL on plan` in `selvedge/lib/comment-render.mjs` |
| `selvedge/tests/test-comment.sh` — AC6 missing earlier folder falls back labelled `(whole run)` | flip `(whole run)` → `(criterion)` in `selvedge/lib/comment-render.mjs` |
| `selvedge/tests/test-comment.sh` — AC7 no TTY without `--yes` refused | in `selvedge/lib/comment.mjs`, delete the line that throws `REASONS.comment_requires_yes` |
| `selvedge/tests/test-comment.sh` — AC7 declined confirmation posts nothing | in `selvedge/lib/comment.mjs`, delete the line that returns early when the confirmation answer is not `y` |
| `selvedge/tests/test-comment.sh` — AC7 missing `verdict.json` | in `selvedge/lib/comment.mjs`, delete the line that throws `REASONS.verdict_missing` |
| `selvedge/tests/test-comment.sh` — AC7 changed plan refused | in `selvedge/lib/comment.mjs`, delete the line that throws `REASONS.plan_modified` when `plan.json`'s sha256 differs from `verdict.json`'s `plan_sha256` |
| `selvedge/tests/test-comment.sh` — AC7 failing `gh` exits 1 | in `selvedge/lib/comment.mjs`, return exit 0 from the `gh` failure branch instead of 1 |
| `selvedge/tests/test-comment.sh` — single quote / backslash / newline body round-trip (Risk row) | in `selvedge/lib/comment.mjs`, pass the body to `gh` as `-f body=<body>` instead of `--body-file` / `-F body=@<file>`, with the round-trip assertion comparing the stub's received body byte for byte |
| `selvedge/tests/test-adapter.sh` — AC8 tools exactly Bash and Read | flip `tools: Bash, Read` → `tools: Bash, Read, Write` in `selvedge/agents/verifier.md` |
| `selvedge/tests/test-adapter.sh` — AC8 same command order in agent and skill | in `selvedge/skills/verify/SKILL.md`, move the `selvedge plan --freeze` step after `selvedge run` |
| `selvedge/tests/test-adapter.sh` — AC8 `plan --init` before `snapshot` | in `selvedge/agents/verifier.md`, delete the `selvedge plan --init` step |
| `selvedge/tests/test-adapter.sh` — AC8 no edit of `plan.json` after freeze | in `selvedge/agents/verifier.md`, delete the line forbidding edits to `plan.json` after `plan --freeze` |
| `selvedge/tests/test-adapter.sh` — AC8 no reading `~/.local/state/selvedge/` | in `selvedge/agents/verifier.md`, delete the line forbidding reads of `~/.local/state/selvedge/` |
| `selvedge/tests/test-adapter.sh` — AC8 prompt within `token_budget` | in `selvedge/agents/verifier.md`, flip the `token_budget:` value to `1` |
| `selvedge/tests/test-adapter.sh` — AC8 posting only through `selvedge comment … --yes` after asking | in `selvedge/commands/verify.md`, delete the line that asks before running `selvedge comment` |
| `selvedge/tests/test-adapter.sh` — AC8 command names the recorded `subagent_type` | in `selvedge/commands/verify.md`, flip the recorded `subagent_type` string to `selvedge:verifier-x` |
| `selvedge/tests/test-adapter.sh` — AC8 `maxTurns` integer present | in `selvedge/agents/verifier.md`, delete the `maxTurns:` frontmatter line |
| `selvedge/tests/test-adapter.sh` — AC8 PR number / file / text → `from-pr` / `from-md` / `from-text` | in `selvedge/commands/verify.md`, flip `selvedge criteria from-md` → `selvedge criteria from-text` |
| `selvedge/tests/test-adapter.sh` — AC10 no `v<X>.<Y>.<Z>` token in the description | in `selvedge/.claude-plugin/plugin.json` and the `selvedge` entry of `.claude-plugin/marketplace.json`, append ` (v0.6.0)` to the `description` |
| `selvedge/tests/test-adapter.sh` — AC10 description ≤ 600 and equal in both manifests | in `.claude-plugin/marketplace.json`, append ` Extra.` to the `selvedge` entry's `description` |

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Config `comment` key, three reasons, `selvedge comment` (render, redaction, base-ref opt-in, public-repo refusal, find-and-update via `gh`, confirmation) | AC1, AC2, AC3, AC4, AC5, AC6, AC7 (+ the README reasons rows, `comment` key bullet and `selvedge comment` section) | 5 modify, 3 create | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` | LAUNCHABLE |
| 2 | `/selvedge:verify`, the Bash+Read verifier, the verify skill + `SKILLS_INDEX.md`, adapter test, equivalence evidence; README adapter section + 0.6.0 release | AC8, AC9, AC10 | 4 modify, 6 create | `skills/unit-testing/SKILL.md` | BLOCKED (by #1) |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "selvedge/lib/comment-render.mjs"}
  - {kind: "symbol", path: "selvedge/lib/comment-render.mjs", name: "renderComment"}
  - {kind: "symbol", path: "selvedge/lib/comment-render.mjs", name: "redactValue"}
  - {kind: "symbol", path: "selvedge/lib/comment-render.mjs", name: "<!-- selvedge:verdict -->"}
  - {kind: "file", path: "selvedge/lib/comment.mjs"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "read_values_public_repo"}
  - {kind: "symbol", path: "selvedge/lib/env-config.mjs", name: "COMMENT_KEYS"}
  - {kind: "symbol", path: "selvedge/schemas/selvedge-config.schema.json", name: "read_values"}
  - {kind: "symbol", path: "selvedge/bin/selvedge", name: "cmd_node comment"}
  - {kind: "file", path: "selvedge/tests/test-comment.sh"}
  - {kind: "symbol", path: "selvedge/README.md", name: "comment_requires_yes"}
requires: []
lanes:
  - "selvedge/lib/env-config.mjs"
  - "selvedge/schemas/selvedge-config.schema.json"
  - "selvedge/tests/test-env.sh"
  - "selvedge/bin/selvedge"
  - "selvedge/lib/comment-render.mjs"
  - "selvedge/lib/comment.mjs"
  - "selvedge/tests/test-comment.sh"
  - "selvedge/README.md"  # the three reasons rows, the comment key bullet and the `selvedge comment` section; Subtask 2 (which reaches Subtask 1 via requires) adds the adapter section
external_requires:
  - "gh >= 2.x on PATH at run time (tests use a PATH stub, no network)"

# Subtask 2
provides:
  - {kind: "file", path: "selvedge/commands/verify.md"}
  - {kind: "file", path: "selvedge/agents/verifier.md"}
  - {kind: "symbol", path: "selvedge/agents/verifier.md", name: "tools: Bash, Read"}
  - {kind: "file", path: "selvedge/skills/verify/SKILL.md"}
  - {kind: "file", path: "selvedge/skills/SKILLS_INDEX.md"}
  - {kind: "file", path: "selvedge/tests/test-adapter.sh"}
  - {kind: "file", path: "selvedge/docs/evidence/verify-adapter-equivalence.md"}
  - {kind: "symbol", path: "selvedge/README.md", name: "/selvedge:verify"}
  - {kind: "symbol", path: "selvedge/CHANGELOG.md", name: "## 0.6.0"}
  - {kind: "symbol", path: "selvedge/.claude-plugin/plugin.json", name: "\"version\": \"0.6.0\""}
requires:
  - {from: "1", kind: "file", path: "selvedge/lib/comment.mjs"}
  - {from: "1", kind: "symbol", path: "selvedge/bin/selvedge", name: "cmd_node comment"}
  - {from: "1", kind: "symbol", path: "selvedge/README.md", name: "comment_requires_yes"}
lanes:
  - "selvedge/commands/verify.md"
  - "selvedge/agents/verifier.md"
  - "selvedge/skills/verify/SKILL.md"
  - "selvedge/skills/SKILLS_INDEX.md"
  - "selvedge/tests/test-adapter.sh"
  - "selvedge/docs/evidence/verify-adapter-equivalence.md"
  - "selvedge/README.md"
  - "selvedge/CHANGELOG.md"
  - "selvedge/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
external_requires:
  - "A live Claude Code session with the selvedge plugin loaded from this checkout (claude --plugin-dir) and Playwright Chromium from selvedge/tests/lib/playwright-cache.sh, for the AC9 evidence run only"
```

**Notes for the workers:**
- Subtask 1: `selvedge comment <run-dir> --pr <n> [--yes] [--base <ref>] [--allow-public-values]` order: parse args (`parseCliArgs`) → read the run folder (`verdict.json` absent → `verdict_missing`; `plan.json` sha256 ≠ `verdict.json` `plan_sha256` → `plan_modified`; `criteria.json`) → resolve base (`--base`, else `gh pr view <n> --json baseRefName` → `origin/<name>`) → `loadConfig({ base })` → when `comment.read_values` is true, `gh repo view --json visibility`; `PUBLIC` without `--allow-public-values` → `read_values_public_repo` → render the body (`renderComment`) → confirm (`--yes`; else a TTY y/N via `readOneLine`; else `comment_requires_yes`) → find / update / create (Design decisions). Print the comment URL `gh` returns, never the body. The `gh` stub in `test-comment.sh` follows `selvedge/tests/test-criteria.sh`'s pattern (records argv to a log, serves `pr view`, `repo view`, `api` list / PATCH and `pr comment` from files in `$TMP`), and the test is hermetic (temp HOME, temp git repo with a commit carrying the base-branch `selvedge.json`, no network, no browser — fixture run folders are written by the test). Pass an unblock hint per reason from one map in `comment-render.mjs` keyed by `REASONS` values (e.g. `needs_auth` → `run selvedge auth setup`). The per-criterion revision lookup (AC6) lives in `comment.mjs` (it reads files: `readRunsLog` from `selvedge/lib/plan-runs.mjs`, the earlier folders' `verdict.json`) and hands `renderComment` a plain `{ <criterion id>: [{ revision, verdict, scope: "criterion" | "run" }] }` map, so the renderer stays pure; the AC6 fixture writes `runs.jsonl` run lines and both revisions' run folders by hand.
- Subtask 2: the verifier's prompt tells it to work only through the CLI (Bash) and to read run-folder files (Read); it writes `plan.json` with a Bash heredoc into the run folder before `plan --validate` (Write is not in its tools), and never touches `plan.json` after `plan --freeze`. `selvedge/commands/verify.md` is the main-thread entry: resolve criteria, spawn the verifier, show the table from `verdict.json`, and only when the source was a PR number ask (once) before `selvedge comment <run-dir> --pr <n> --yes`. Generate `selvedge/skills/SKILLS_INDEX.md` with `bash scripts/check-skills-index-sync.sh --write` (give `SKILL.md` `name`, `description`, `version`, `lastUpdated` frontmatter first). For AC9, load the plugin from the checkout (`claude --plugin-dir selvedge`), record which `subagent_type` spawned the verifier, re-run its frozen plan with `selvedge run --replay <its run folder>` + `selvedge verdict <the new folder>`, and write the evidence file with the commands and outputs, comparing with the `jq -S 'del(.criteria[].steps[].duration_ms) | .criteria'` projection AC9 names. The verifier's workflow runs `selvedge plan --init <criteria.json>` (it creates the run folder and prints its path) before any `snapshot --run-dir <that folder>`. Condense the selvedge `description` (596 characters at base) rather than appending to it.

### Dependency Graph

```
Subtask 1 ──→ Subtask 2
```

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Batch 2:** Subtask 2 (after Subtask 1 — its `requires` point at Subtask 1)
- **Recommended workers:** 1
- **Estimated batches:** 2

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/error-handling/SKILL.md`, `skills/unit-testing/SKILL.md` |
| 2 | `skills/unit-testing/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Feasibility (Phase 2.5): the plan needs files outside the requirement's `## Touches` (`env-config.mjs`, `test-env.sh`, `bin/selvedge`, `README.md`, the release surfaces, `selvedge/skills/SKILLS_INDEX.md`, the evidence file) | MEDIUM | Each is a one-purpose edit named in the File Impact Map; the owner is asked once at Launch Pad Phase 6 (`LP-SCOPE`), and an accepted widening is recorded in a `## Scope widening` section written then. |
| Feasibility (Phase 2.5): `/selvedge:verify` ≡ hand-run (AC9) needs a live Claude session, which CI cannot run | MEDIUM | Proven once by a committed evidence file (AC9); the deterministic parts (tools, command order, prohibitions) are pinned by `test-adapter.sh` (AC8). |
| Feasibility (Phase 2.5): 17 files, above one worker's bound | MEDIUM | `context-bound` split into 2 sequential subtasks with disjoint lanes except the README (sequential, legal). |
| Plugin agent `subagent_type` naming: this account's runtime registers plugin agents with a doubled prefix (`loomwright:loomwright:<role>`, project memory), so a command naming `selvedge:verifier` may fail with "Agent type not found" | MEDIUM | The AC9 session records the name that worked and `commands/verify.md` names exactly that; `test-adapter.sh` asserts the command names the agent by the same string the evidence file records. |
| Redaction cannot catch every PII shape (names, addresses), even with the opt-in | MEDIUM | Default is unpublished (AC4); the opt-in is base-branch-only and refused on public repos without `--allow-public-values` (AC5); the README states the limit in plain words. |
| PR text / page values reaching `gh` through a shell string or hand-built JSON (lesson [a7e4fb1c]) | MEDIUM | The body always travels as a temp file via `execFileSync` argument arrays (`--body-file`, `-F body=@file`); `test-comment.sh` includes a body with a single quote, backslash and newline and checks the stub received it byte for byte. |
| Per-criterion revision history depends on earlier run folders under the gitignored `.selvedge/runs/` still being present (a fresh clone, a CI runner or a cleaned folder lacks them) | MEDIUM | AC6's fallback shows the run-level verdict explicitly labelled `(whole run)` and never counts it as `PASS after revision`, so a missing folder can understate history but never misattribute it; the README says so. |
| The marker search reads every comment page; a PR with many comments makes several `gh api` calls | LOW | `--paginate`; first marker match wins; the extra cost is per run, not per criterion. |
| `selvedge/skills/` makes the root `check-skills-index-sync.sh` scan selvedge (until now skipped) | LOW | `SKILLS_INDEX.md` generated by `--write` in Subtask 2 and the gate run in AC10. |

## Configuration
- **Workers:** 1
- **Mode:** sequential
- **Estimated batches:** 2
- **Base Branch:** main
- **Split reason:** context-bound

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-11-17-qa-split-06-claude-adapter-pr-comment.md
```


## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-11-18T02:45:00Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/938
- **Branch:** feature/qa-split-06-claude-adapter-pr-comment
- **Files changed:** 17
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 0
- **Heal reason:** needs_human
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Test guard:** armed
- **Summary:** Two sequential subtasks shipped. `selvedge comment` (c0e7038) posts ONE text-only PR comment, found by its marker and updated in place, with base-ref-only, private-repo-only, redacted read values and per-criterion revisions. `/selvedge:verify` + the Bash,Read `selvedge:verifier` + the verify skill + live-session equivalence evidence ship with selvedge 0.6.0 (813c89c). The Phase 4.5 review returned NEEDS_HUMAN on one HIGH finding. The marker comment is taken whoever wrote it, so a planted marker comment receives the verdict (reproduced). This follows the brief's confirmed design decision, so the owner rules on it. Three LOW findings were below the MEDIUM fix floor and are recorded as dismissed. No fix round ran. Ground truth 2/2 pass, rules gate none, rules audit clean, required CI pending at review.

## Not verified
- **real gh against GitHub (tests use a PATH gh stub)** — no network or real PR used (subtask 1)
- **rendered comment on github.com** — nothing posted to a real PR (subtask 1)
- **/selvedge:verify PR-number source ask-then-post path** — claude -p cannot ask; pinned statically by test-adapter.sh (subtask 2)
- **AC9 PR body links the evidence file** — no PR opened by the worker; the Supervisor's PR body links it (subtask 2)
