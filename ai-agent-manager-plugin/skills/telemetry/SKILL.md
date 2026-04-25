---
name: telemetry
description: Opt-in GitHub Issues telemetry for ai-agent-manager. Enables longitudinal analysis of agent quality by emitting structured, scored, redacted issues from `SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`, and `QA_RESULT` blocks. Use when a project wants to feed run outcomes back into the maintainer repo (or its own analytics repo) without standing up a backend.
version: "1.0.0"
lastUpdated: "2026-04"
---

# Telemetry

Opt-in feedback channel that turns finished agent runs into structured
GitHub issues. The issue is the database; labels are the index.

Full design: `ai-agent-manager-plugin/docs/TELEMETRY.md`.

---

## When to Use

- A project has installed the ai-agent-manager plugin and wants to
  contribute anonymised run signal to a chosen repo (the maintainer
  repo, or a private analytics repo).
- A maintainer wants to identify weak agents (`agent:qa-weak`,
  `agent:planner-weak`) across many runs.
- A team wants to track score trends per `task:{agent-type}` after
  prompt or skill changes.

## When NOT to Use

- The project has not opted in. Telemetry is disabled by default and
  must never be silently enabled. If `.supervisor/telemetry-consent.json`
  is absent or set to `prompt`, the hook does nothing except drop a
  rate-limited `telemetry pending` notice.
- The user wants to send arbitrary data. Only the three result blocks
  (`SUPERVISOR_RESULT`, `CODE_REVIEW_RESULT`, `QA_RESULT`) are
  recognised; everything else is `unknown_payload_skipped` (exit 5).
- The host project is the user's own application repo and no explicit
  target has been chosen. There is **no `origin` fallback** — see
  "Target repo" below.

---

## Quick start (project opting in)

1. Run `/telemetry enable`. The slash command asks which repo should
   receive issues (suggesting `vikashruhilgit/ai-agent-manager`, but
   accepting any `owner/repo`).
2. The command writes:
   ```json
   { "telemetry": "always_allow", "telemetry_repo": "<chosen>" }
   ```
   to `.supervisor/telemetry-consent.json` (gitignored via the existing
   `.supervisor/` rule).
3. From the next qualifying agent run, the `SubagentStop` hook invokes
   `ai-agent-manager-plugin/scripts/send-telemetry.sh` with the result
   payload on stdin. The wrapper always exits 0; the core script may
   exit 0..5 (see exit-code table in `docs/TELEMETRY.md`).

To stop sending: `/telemetry disable`. To inspect state:
`/telemetry status`. To preview without sending: `/telemetry test`.

## What gets sent

- A title of the form
  `[Telemetry] {agent_type} | Score: {N} | Failed: {true|false}`.
- A body with sections: Task Summary, Agent Scores, Issues Detected,
  AI Suggestions, Tools Used, Raw Data (JSON of the redacted payload).
- Labels: `telemetry`, `score:{low|medium|high}`,
  `task:{agent-type}`, and `agent:{name}-weak` for any sub-score `< 5`.

## What does NOT get sent

- Anything matching the privacy whitelist: API keys (`sk-...`,
  `ghp_...`), `Bearer` tokens, `api_key` / `password` patterns,
  `/Users/<name>/` and `/home/<name>/` paths, email addresses, or raw
  `.env`-style assignments. A single match -> core exits `2`
  (`privacy_blocked`), structured log entry names which pattern hit
  (never the matched content). Stderr is redacted by the same list
  before being appended to the log.
- Healthy runs. Interest filter: skip if score `>= 5` AND status is in
  the success set (`completed`/`PASS`/all-tests-passed). Send if score
  `< 5` OR status in `{failed, FAIL, completed_with_escalation,
  ESCALATED, NEEDS_HUMAN}`.
- Duplicate signal. 6-hour dedup window keyed on
  `{task_id, score_bucket, primary_error}` via
  `.supervisor/logs/telemetry-sent.log`.

## Hook contract (always-exits-0)

The hook is fire-and-forget. The wrapper never blocks the agent run:

| Layer    | Exit codes                                                 | Why                                                           |
|----------|------------------------------------------------------------|---------------------------------------------------------------|
| Wrapper  | always `0`                                                 | Hook contract — must never fail the agent run.                |
| Core     | `0` sent / `1` generic / `2` privacy / `3` no-consent / `4` no-repo / `5` filtered | Privacy and config violations must fail closed for audit. |

The wrapper captures the core's exit code and redacted stderr,
appends both to `.supervisor/logs/telemetry.log`, and returns `0`.

## Target repo

Resolution precedence (first non-empty wins):

1. `AI_AGENT_MANAGER_TELEMETRY_REPO` env var (shape `owner/repo`).
2. `.supervisor/telemetry-consent.json` -> `telemetry_repo` field.
3. Unset -> core exits `4`; wrapper logs `telemetry_repo_unset` once
   per session.

There is no automatic fallback to `git remote get-url origin`. The
plugin runs in arbitrary user projects whose `origin` is the user's
own app — silently posting telemetry there would be a privacy and
support disaster.

## Determinism

Same input -> same score. The score function does not use timestamps
or randomness. The scoring rubric is expressed as **three separate
per-result-block tables** in `docs/TELEMETRY.md` (a unified mapping
cannot disambiguate the three different status enums). Subtask #2b
implements those tables verbatim.

## Anti-patterns

- Reading `gh remote get-url origin` to pick the target repo. Never.
  Telemetry must be opt-in to a chosen repo, never silently to the
  host project.
- Prompting the user from inside the hook. `type: command` hooks
  cannot drive interactive prompts. The slash command
  `/telemetry enable` is the SOLE first-run consent path.
- Running the privacy whitelist in the wrapper. The wrapper must
  always exit 0; whitelist matches must exit non-zero. Splitting the
  responsibility into wrapper (always 0) + core (structured 0..5) is
  load-bearing — do not collapse it back into one script.
- Adding randomness or timestamps to the score function. The dedup
  hash and `/telemetry status` reporting both depend on
  same-input-same-output.
- Including verbatim error stderr in the log without running it
  through the privacy whitelist. Errors can echo secrets.

## Related skills

- `error-handling/` — fail-closed patterns and structured exit codes
  used by the wrapper/core split. The wrapper's "always exit 0, log
  the failure" pattern is the same shape as the
  `WorktreeCreate`/`StopFailure` blocks already in `hooks.json`.
- `quality-checklist/` — gates the work in Subtasks #1-#5: privacy
  whitelist completeness, exit-code coverage, deterministic score
  function, hook non-blocking property, redacted stderr.

## Quality gates (when emitting or modifying telemetry)

- [ ] Wrapper script invariant: every code path ends in `exit 0`.
- [ ] Core exit codes match the canonical table (0..5) in
      `docs/TELEMETRY.md`.
- [ ] Privacy whitelist: any change to the regex set updates both
      `docs/TELEMETRY.md` AND the script in the same commit
      (consistency audit will flag drift).
- [ ] Score function is deterministic — no `date`, no `$RANDOM`, no
      filesystem-order dependence.
- [ ] Dedup hash uses only `{task_id, score_bucket, primary_error}`
      and is computed identically on every host.
- [ ] No silent `origin` fallback for the target repo.
- [ ] Stderr is run through the privacy whitelist before being
      appended to `telemetry.log`.

## Token Cost

- Invocation: ~700 tokens (skill body)
- Storage: inline (markdown only)
- Context7: not required

## See also

- `ai-agent-manager-plugin/docs/TELEMETRY.md` — full design,
  authoritative scoring rubric tables, exit-code contract, privacy
  whitelist, consent flow, dedup, log files, future work.
- `temp/self-learning.md` — original brief (issue body shape, label
  taxonomy, smart enhancements list).
