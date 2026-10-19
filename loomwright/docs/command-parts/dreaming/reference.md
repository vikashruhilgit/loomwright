## Example Output

```markdown
## /dreaming — Reflection Report

**Sessions analyzed:** 5 (2026-05-03 → 2026-05-09)
**Agents reflecting:** code-reviewer, red-team, qa-executor
**Contract:** read-only until per-item Accept. Memory/LESSONS/agent-memory writes go through the repo-root sole writers; CLAUDE.md stays paste-to-apply.

---

### 1. Recurring Patterns

- **Pattern A — Missing boundary tests** (3/5 sessions: 2026-05-03, 2026-05-06, 2026-05-09)
  Workers shipped CRUD endpoints without negative-case tests; QA Executor flagged the gap each time.
- **Pattern B — `provides:` drift** (4/5 sessions)
  Subtask briefs declared `provides:` symbols that did not match the symbols actually emitted; outputs_gap was non-empty in each case.
- **Pattern C — Code Reviewer re-flagging stale TODOs** (5/5 sessions)
  Same TODO comments flagged review-after-review; nobody is closing them.

### 2. Distilled Insights

- **Insight 1:** When a subtask lacks an explicit boundary-test acceptance criterion, the worker omits boundary tests roughly 60% of the time. (Evidence: Pattern A.)
- **Insight 2:** `provides:` entries authored from memory rather than from the actual code drift within one session. (Evidence: Pattern B.)
- **Insight 3:** TODOs without an owning task ID accumulate indefinitely. (Evidence: Pattern C.)

### 3. Proposed Memory Updates

- **[code-reviewer]** _add_ → `.claude/agent-memory/.../patterns.md`
  Text: "Always check whether subtask `provides:` symbols actually exist in the modified files; flag drift as BLOCKING."
  Linked insight: 2
  Evidence: 3 distinct sessions (2026-05-03, 2026-05-06, 2026-05-09)
  Status: **PENDING USER APPROVAL**

- **[qa-executor]** _add_ → `.claude/agent-memory/.../boundary-tests.md`
  Text: "If a subtask touches a CRUD endpoint and the brief has no boundary-test criterion, generate boundary tests anyway and report the gap."
  Linked insight: 1
  Evidence: 1 session (2026-05-06)
  Status: **PENDING USER APPROVAL**

### 4. Proposed CLAUDE.md Updates

- **Target section:** "## Common Pitfalls"
  Proposed text: "TODO comments without an owning task ID are forbidden. Either link a Beads/issue ID or remove the TODO before merging — Code Reviewer will block PRs that accumulate ownerless TODOs."
  Linked insight: 3
  Evidence: 2 distinct sessions (2026-05-03, 2026-05-09)
  Status: **PENDING USER APPROVAL**

### 5. Collected Memory Candidates

- Candidate: "Worker summaries live in .supervisor/worker-summaries/ and are the cheap result-extraction path, not the full TaskOutput."
  Source: session 2026-05-06, subtask BD-22a
  Evidence: 1 session (2026-05-06)
  Status: **PENDING USER APPROVAL**
  (deduped against existing project memory: not already present)

### 6. Proposed LESSONS

- category: testing — "When a subtask touches a CRUD endpoint with no boundary-test criterion, generate boundary tests anyway."
  Score: 0.72 (recall-frequency 3/5 × outcome 0.8 [QA-flagged gap] × diversity 3 distinct subtasks)
  Linked insight: 1
  Status: **PENDING USER APPROVAL**
- category: contracts — "Author `provides:` symbols from the actual diff, not from memory." (category full → replaces oldest: "Prefer interface-first contracts")
  Score: 0.64
  Linked insight: 2
  Status: **PENDING USER APPROVAL**

---

### Approval

For each item above, choose **Accept**, **Reject**, or **Edit** (per-item — there is no bulk-accept). On **Accept**: PROJECT_MEMORY facts (incl. accepted §5 candidates) are written by `/dreaming` via `write-project-memory.sh`, and §6 LESSONS via `write-lessons.sh` (both repo-root sole writers, run from the repo root, both invoked with `--confirm` — their store is committed). CLAUDE.md (§4) proposals are paste-to-apply by you; agent-memory (§3) proposals are promoted through the sole writer with `write-agent-memory.sh --proposal <file> --confirm` and are never hand-applied. **Reject**/**Edit** never writes. There is no auto-write. Each item is asked with `AskUserQuestion` using the fixed option set for its class — see "Approval Option Contract" above.

Worked recommendation pass over the items above (the rules are in that section's table; the point of printing it is that every marker is checkable against the report):

- §3 `[code-reviewer]` — evidence 3 distinct sessions ⇒ `Accept (Recommended)` first, description citing "3 sessions corroborate".
- §3 `[qa-executor]` — evidence 1 session ⇒ **no recommendation**, neutral order.
- §4 additive — evidence 2 distinct sessions ⇒ `Accept (Recommended)`, header `CLAUDE.md`. Recommended even though it is paste-to-apply: the marker is about the evidence, not about who performs the write.
- §5 candidate — evidence 1 session ⇒ **no recommendation**, neutral order.
- §6 `testing` — highest-scoring proposal in its category and evidence spans 3 subtasks ⇒ `Accept (Recommended)`.
- §6 `contracts` — displaces the oldest lesson in a full category ⇒ **never recommended**, regardless of score.
- Harvested rules — **never recommended** on either gate.
- Memory PR Pre-push confirmation — **never recommended**, either option.

Three of eight recommended is a normal-looking pass; zero is also normal. Abstain is the default, not a degraded outcome.

### Promotion queues (shown only when they are non-empty)

- **PROMOTE PENDING PROPOSAL** — `.supervisor/agent-memory-proposals/2026-05-09-jq-optional-chain.md`
  agent: `loomwright-loomwright-code-reviewer` · name: `jq-optional-chain-type-trap`
  Accept promotes via `write-agent-memory.sh --proposal … --confirm` and deletes the file; Reject deletes it without writing.
- **Harvested `.agent/rules/` batch** — 4 proposed rules (coverage 74/107, dedupe 18.50 findings/rule, scope fidelity 98% of the 55 CHECKABLE findings / 73% over all 74 motivating findings — both figures, never the flattering one alone). One of the four carries a `check_candidate: grep -rnE -- '19' src/a/*; test $? -eq 1` line (≥3 of its findings share that literal) — DATA only, never executed here.
  Each rule takes **two** gates: content (**Accept**, or **Accept rule WITH check** when a candidate was shown), then a separate **Pre-push confirmation** (push). Only rules clearing both are committed to `dreaming/rules-<session_id>` and delivered by `gh pr create` — a rule accepted WITH check is first PROVEN by `prove-rule-check.sh` against a counterexample patch shown beside it, then committed with that exact string as its `check` and **`enforcement: must`** (the only enforcement `rules-check.sh` selects; a candidate that does not prove `PROVEN` is offered as `advisory`, its check kept as data), and it still does not RUN anywhere until a human separately runs `/rules check --confirm` on their own machine (see `skills/rules/SKILL.md` §8.1). Nothing confirmed ⇒ no branch, no PR. `/dreaming` never merges the PR it opens.
- **Memory PR** — offered once, after every Accept above, only if both memory stores were clean before the first write (the harness-memory pointer's file excepted). Changed this run: `.supervisor/memory` (1 lesson, 1 fact), `.claude/agent-memory` (1 promotion). ONE **Pre-push confirmation** (`Do not push` · `Push and open a PR`, never recommended) covers the whole set — not per item, because those Accepts share `LESSONS.md`, `PROJECT_MEMORY.md`, the provenance files and the `MEMORY.md` index. Push ⇒ after the rules delivery, `dreaming/memory-<session_id>` carries only the recorded files those writers changed (never the harness-memory pointer) and `gh pr create` opens it; your branch then reads the pre-run memory content until that PR merges and you pull. Do not push (or an unclear answer) ⇒ no branch; the writes stay in place, uncommitted. `CLAUDE.md` (§4) stays a hand PR. `/dreaming` never merges the PR it opens.
```

## Workflow Positioning

`/dreaming` is a **post-hoc reflection** command. It does not replace any existing pipeline — it complements them.

| Command | Direction | When to use |
|---------|-----------|-------------|
| `/orchestrator` | Forward (plan) | Decompose a goal into tasks before execution |
| `/supervisor` | Forward (execute) | Autonomously execute tasks end-to-end |
| `/code-reviewer` | Lateral (live audit) | Review the current diff or files |
| `/red-team-reviewer` | Lateral (live audit) | Adversarially attack the current state |
| `/qa-executor` | Forward (test) | Generate and run tests against the running app |
| **`/dreaming`** | **Backward (reflect)** | **After several sessions, distill patterns into proposed memory + CLAUDE.md updates** |

Use `/dreaming` periodically — for example, weekly or after every N completed `/supervisor` runs — to harvest durable lessons from session logs and keep agent memory and project documentation aligned with how the team actually works.

## When to Use

- After a streak of completed `/supervisor` sessions, to surface recurring issues
- Before updating `CLAUDE.md` by hand, to discover what *the logs* say should change
- When onboarding a new pattern, to see whether the agents have been quietly learning it
- As a recurring "retrospective" cadence (weekly / per milestone)

## When NOT to Use

- During active execution — `/dreaming` reflects on past sessions, not the current one
- When you need code changes — `/dreaming` never touches code (it persists approved memory/LESSONS/promotions, and its two branch-and-PR paths stage only `.agent/rules/*.json` and its own recorded project-memory and agent-memory writes); use `/supervisor` or `/code-reviewer` for code changes
- For agents not currently supported — six agents have `memory: project` (Launch Pad, Code Reviewer, Red Team Reviewer, Product Owner, QA Strategist, QA Executor), but v12.2.0's `--agent` flag covers only Code Reviewer, Red Team Reviewer, and QA Executor; the other three are out of scope until a follow-up release

## See Also

- `/supervisor` — Autonomous workflow whose logs are the input to `/dreaming`
- `/code-reviewer` — Live (forward) review counterpart
- `/red-team-reviewer` — Live (forward) adversarial counterpart
- `/qa-executor` — Live (forward) QA counterpart
- `/agent-help` — Full command list
- `loomwright/skills/memory-tool/SKILL.md` — Decision aid for what to write to agent memory directories (consulted on demand)
- `.supervisor/logs/{session_id}.jsonl` — Source data consumed by `/dreaming`
