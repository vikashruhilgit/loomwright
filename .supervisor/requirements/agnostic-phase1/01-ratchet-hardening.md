# 01 — Vendor-coupling ratchet hardening (count the coupling that actually locks us in)

## Problem
`scripts/check-vendor-coupling.sh` passes (806 refs, 0 breaches) while the plugin's Claude coupling keeps growing:
the allowance sum went 574 (release commit `bfa5716`, 2026-08-31) → 806 at HEAD (71 → 114 entries), because every
new reference arrives with a same-PR allowance raise and nothing asks why. Worse, the gate counts only 4 literal
tokens (`CLAUDE_PLUGIN_ROOT`, `CLAUDE_CODE_`, `claude -p`, `.claude/`) and classifies `loomwright/agents/*`,
`loomwright/commands/*` and `loomwright/hooks/*` as ADAPTER — whole files, bodies included, uncounted. So the four
mechanisms that actually lock the plugin to Claude Code are invisible to it:
- subagent orchestration (`subagent_type`, `TaskOutput`, `SendMessage`, `run_in_background`),
- ask-user (`AskUserQuestion`),
- hook events and payload fields (`SubagentStop`, `agent_transcript_path`, `last_assistant_message`,
  `stop_hook_active`, `hookSpecificOutput`),
- runtime identity (`CLAUDE_PID`, `CLAUDECODE`), the SDK binding (`@anthropic-ai`), and Claude model names.

## Goal
The ratchet measures the real coupling classes, agent/command BODIES are counted (only their frontmatter is the
adapter surface), and an allowance raise cannot land without a stated reason. Growth becomes visible and argued,
not automatic.

## Scope
1. **Token classes in the manifest.** Replace the flat `vendor_tokens` list with named classes the gate sums per
   class and reports per class (keep a flat total too). Minimum classes:
   - `install_root`: the existing four tokens.
   - `orchestration`: `subagent_type`, `TaskOutput`, `SendMessage`, `run_in_background`.
   - `ask_user`: `AskUserQuestion`.
   - `hook_protocol`: `SubagentStop`, `hookSpecificOutput`, `agent_transcript_path`, `last_assistant_message`,
     `stop_hook_active`.
   - `runtime_identity`: `CLAUDE_PID`, `CLAUDECODE`, `CLAUDE_CODE_SESSION_ID` (note: overlaps `CLAUDE_CODE_` — the
     gate must not double-count one occurrence; resolve by longest-match-wins or by excluding it from
     `install_root`, and test the choice).
   - `sdk_binding`: `@anthropic-ai`.
   - `model_names`: fixed strings for Claude model aliases as they appear in code/frontmatter (e.g. `model: haiku`,
     `model: sonnet`, `model: opus`, `"sonnet"`, `"haiku"`) — measure false positives in prose before choosing the
     exact strings; document the choice in the manifest `note`.
   The gate must still hard-code no token (tokens live only in the manifest).
2. **Frontmatter-only adapter exemption for agents and commands.** `loomwright/agents/*.md` and
   `loomwright/commands/*.md` become counted files whose YAML frontmatter block (first `---` … `---`) is excluded
   from the count; everything after it is counted. `loomwright/hooks/*` stays ADAPTER (hooks.json IS the Claude
   adapter). Implement as a manifest-declared mode (e.g. class `adapter_frontmatter`), not a hard-coded path.
3. **Re-baseline in the same PR** with `--print-allowances`; the PR body carries the before/after total per class
   and the command used. This is a measurement, not a policy change — no reference is removed in this item.
4. **Reason required for a raise.** When run in a git checkout where `origin/main` (or `$VENDOR_COUPLING_BASE`) is
   resolvable, the gate compares each allowance with the base manifest; any raised or newly-added allowance must
   have a matching entry in a new manifest map `allowance_reasons` (`"<path>": "<one-line reason>"`), else BREACH.
   When the base is unresolvable (shallow clone, no remote), print `raise_check: skipped (no base)` and do NOT fail
   — but CI must fetch enough history for the check to run (verify `.github/workflows/ci.yml`'s checkout depth; if
   it needs `fetch-depth: 0`, note that editing a workflow file makes `claude-code-action` self-skip the PR's own
   review — say so in the PR body and verify review on the next non-workflow PR).
5. **Tests** in `scripts/test-check-vendor-coupling.sh`: per-class counting; no double count on overlapping tokens;
   frontmatter excluded but body counted; raise-without-reason ⇒ exit 1; raise-with-reason ⇒ exit 0; no base ⇒
   skipped line, exit 0. **Mutation control:** a fixture where a new `AskUserQuestion` appears in an agent BODY with
   no allowance raise must fail the gate.
6. **Docs:** the script header's "WHAT IT CANNOT SEE" section, the manifest `_comment`/notes, CLAUDE.md is NOT
   edited for counts (counts live in the manifest only), CHANGELOG entry, version bump.

## Non-goals
Removing any existing reference (that is Phase 2). Changing `unclassified_default`. Detecting runtime-assembled
names (keep the stated limit). Touching `sdk-spike/` code.

## Acceptance criteria
- `bash scripts/check-vendor-coupling.sh` prints a per-class table and a total; exit 0 at the new baseline.
- Adding `AskUserQuestion` to the body of any `loomwright/agents/*.md` without an allowance change ⇒ exit 1; adding
  it inside that file's frontmatter ⇒ unchanged count.
- Raising any allowance without an `allowance_reasons` entry ⇒ exit 1 (when base resolvable).
- `loomwright/sdk-spike/package.json` now counts ≥1 under `sdk_binding`.
- Full test loop + root checks green.

## Verified premises (re-check before starting)
- `scripts/check-vendor-coupling.sh` header §"HOW IT COUNTS" (literal `grep -oF`, per file, summed over tokens) and
  §"TO RAISE AN ALLOWANCE" (same-PR raise, no reason required).
- `loomwright/docs/vendor-coupling-manifest.json`: `vendor_tokens` = 4 entries; `classes.adapter` includes
  `loomwright/commands/*`, `loomwright/agents/*`, `loomwright/hooks/*`; allowance sum 806 / 114 entries at
  `a262d00` (`jq '[.allowances[]]|add'`); 574 / 71 at `bfa5716`.
- `loomwright/sdk-spike/src/runner.ts:1117-1120` imports `@anthropic-ai/claude-agent-sdk` via a string-constant
  variable; it scores 0 only because `@anthropic-ai` is not a token.

bump = write a `changelog.d/` fragment and run `scripts/bump-version.sh`

## Status: pending

## Depends on
none

## Touches
scripts/check-vendor-coupling.sh
scripts/test-check-vendor-coupling.sh
loomwright/docs/vendor-coupling-manifest.json
.github/workflows/ci.yml
changelog.d/agnostic-phase1-01-ratchet-hardening.md

<!-- loomwright:requirement-closeout -->
## Status: done
- **Completed:** 2026-10-05T02:43:10Z
- **Brief:** .supervisor/jobs/done/2026-10-05-agnostic-phase1-01-ratchet-hardening.md
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/385
