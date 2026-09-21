# 04b — Rate-limit proximity probe (operator-run planning item — NOT for `/automate`)

Split out of 04 §3 on 2026-09-12: `/automate` processes a file as one item and cannot skip a section, and
this section's only AC ("record the finding in this file") cannot be satisfied by an autonomous worker.

## Question
Does ANY local or authenticated source expose rate-limit proximity for this account, so a pre-item check
(">80% → park early") could exist? Orca claims to read one; unverified for Claude (00 §facts).

## Known-NOT sources (verified 2026-09-11)
- `~/.claude/stats-cache.json` — usage history, last written 2026-04-30. Not a window.
- `~/.claude/policy-limits.json` — policy, not consumption.

## Candidates to probe (record command + date + result below, one line each)
1. What Claude Code's `/usage` display calls — observe the request (`CLAUDE_DEBUG`/proxy), never scrape UI.
2. The OAuth usage endpoint the desktop app uses, if reachable with the CLI's stored token
   (read-only GET; if it needs a token from `~/.claude/.credentials.json` that is the USER's action, not a script's).
3. Orca's own source (MIT, `stablyai/orca`): find how it derives proximity for Claude; if it is a private
   endpoint or scraping, record that as the answer.

## Outcome
- **Source exists** → open `04c-rate-limit-early-park.md`: a pre-item read in `automate-loop`, fail-SAFE
  (unreadable source ⇒ no check, logged), threshold in config, never a retry.
- **No source** → record it here, close this file; 04's post-hoc park is the whole mechanism.

## Findings
_(none yet — add `YYYY-MM-DD · <command> · <result>` lines here)_

## Status: operator-run
