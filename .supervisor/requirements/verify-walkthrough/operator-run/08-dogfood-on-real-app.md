# 08 — Dogfood `/verify` on a real app and record what lied (OPERATOR-RUN — not an /automate item)

## Status: pending (operator-run — lives in `operator-run/` so `resolve-folder` never enqueues it)

## Why this exists
The QA ladder's one real-repo run is the only reason we know its roll-up lied and its output had no consumer
(memory `qa-l1-validated-on-sports-management`). Items 01–07 are built on those lessons; nothing but a real
run proves they took. D11: eval honesty — abort rows stay, re-runs are second rows.

## Procedure (after 01–05 have merged; 06/07 optional)
1. Target: `~/Documents/work/personal/sports-management` (Next.js 16, 97 routes / 175 APIs, known-open
   `BUG-NC-001` in `POST /api/chats`). Run `propose-verify.sh` there; record what it guessed right/wrong and
   what `--non-prod` you had to supply.
2. Pick 3 tickets: one shipped feature with a requirement file, one brief from `.supervisor/jobs/done/`, and
   one hand-written requirement whose AC is the `BUG-NC-001` behaviour (it MUST come out `FAIL`).
3. Run `/verify` on each. Record per ticket: per-AC verdicts, `NOT_VERIFIABLE` count and whether each was
   honest, `needs_auth` handling, tool-call budget consumed, wall time, cost (`token_ledger`).
4. Falsify: hand-edit `summary.md` and confirm it is overwritten; delete the FAIL line and confirm the draft
   writer produces nothing on re-run; move the branch head and confirm the stale path (if 07 shipped).
5. Write the findings into THIS file under `## Findings <date>`, and amend the affected item(s) — never a new
   item — with the evidence. If the summary or drafts lied anywhere, that is the first fix.

## Findings
(none yet)
