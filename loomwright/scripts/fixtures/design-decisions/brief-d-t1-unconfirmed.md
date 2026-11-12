<!-- Fixture brief, paired with the repo/ directory beside it. Pinned by scripts/test-design-decisions.sh. Not a real job. -->
# Supervisor Job: Rate-limit the upload route

## Environment
- **Project:** fixture-notes-api (Node.js 20, Express 4, CommonJS; the `repo/` directory beside this brief)
- **Base commit:** 0000000000000000000000000000000000000000

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | Express middleware on an Express 4 router, the stack `package.json` declares. |
| 2 | Dependency Availability | CAUTION | New dependency `express-rate-limit` is not in `package.json`; it must be added. |
| 3 | Architecture Fit | GO | One middleware on one existing route. |
| 4 | Scope vs Supervisor Capability | GO | 2 modify, 1 create. |
| 5 | Hard Blockers | GO | None. |

**Overall Verdict:** CAUTION

## Task
**Goal:** Limit `POST /api/upload` to 10 requests per minute per client IP in `src/routes/upload.js`, answering HTTP 429 beyond that.

**Problem Statement:**
One client can flood the upload route today. Success looks like a per-IP limit with no change for other clients.

## Design decisions
- decision: how to limit the request rate on the upload route
  chosen: `express-rate-limit`, mounted on the upload router
  rejected: a hand-written in-memory counter in `src/routes/upload.js` — test cost: no, the window and reset logic need their own tests
  rejected: a reverse-proxy limit (nginx `limit_req`) — fits the CLAUDE.md stack: no, the repo ships no proxy config
  evidence: `grep -n rate package.json` → no match, so every candidate is new; `express-rate-limit` is Express middleware (Context7)
  revisit when: the API runs on more than one instance and needs a shared counter store
  status: unconfirmed

## Acceptance Criteria
- [ ] **AC1:** the 11th upload from one IP within a minute gets HTTP 429.
- [ ] **AC2:** uploads from a second IP in the same minute still get HTTP 201.
- [ ] **AC3:** `test/upload-rate-limit.test.js` covers AC1–AC2 and passes under `node --test`.

## Touched-file invariants

- **`src/routes/upload.js`** — keep: `module.exports = router;` and the `store.single('file')` middleware; pinned by: `test/upload-rate-limit.test.js`, which this change creates.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Per-IP upload rate limit | AC1–AC3 | 2 modify, 1 create | unit-testing | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: "test/upload-rate-limit.test.js"}
requires: []
lanes:
  - "src/routes/upload.js"
  - "package.json"
  - "test/upload-rate-limit.test.js"
external_requires: []
```

### File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| upload | `src/routes/upload.js`, `package.json` | `test/upload-rate-limit.test.js` | HIGH |

## Parallelism Analysis
- **Batch 1:** Subtask 1
- **Recommended workers:** 1

## Skill References
- `skills/unit-testing/SKILL.md`

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| New dependency `express-rate-limit` (Feasibility (Phase 2.5)) | MEDIUM | Pinned to one major version in `package.json`. |

## Configuration
- **Mode:** sequential
- **Recommended workers:** 1

## Handoff
/supervisor job: .supervisor/jobs/pending/fixture-upload-rate-limit.md
