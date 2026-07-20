# Pointer Audit — "Pointers, not payloads"

> Audit of every Task-spawn prompt / inter-agent handoff in the plugin sources
> (`agents/*.md`, `skills/*/SKILL.md`, `commands/*.md`) that instructed pasting
> >~1k chars of file-backed content into a spawn prompt. Each true paste site was
> either **converted** to `path + ≤200-char bounded summary + "Read only the sections
> you need"` or kept as a **justified exception** documented below. Verified from the
> files, not memory. Line numbers are as of the audit date (2026-07-20) and will
> drift — the section anchors are the durable reference.
>
> **Transport-only guarantee:** every conversion changes how content travels, never
> which gates, schemas, decisions, or spawn cardinality apply. No agent's behavior
> contract changed.

## The rule

When a spawn input is **file-backed** (job brief, plan file, corpus), pass:

1. the file **path** (repo-relative, or absolute where required — see worktree reality),
2. a **bounded ≤200-char summary**, and
3. the explicit instruction **"Read only the sections you need."**

Keep a paste ONLY where the consumer provably needs the full content every time —
each such exception is enumerated in the table with its justification.

**Worktree reality (hard constraint):** gitignored `.supervisor/` artifacts do **not**
exist inside linked git worktrees. A pointer handed to a worktree-resident consumer
(parallel-path workers) must **pin the main-checkout absolute path and say so in the
prompt text**. Consumers running at the project root (Orchestrator, Execute Manager,
fast-path Worker/Reviewer, Phase 4.5 spawns) can use the repo-relative path directly.
The normative statement of this rule lives in `skills/async-orchestration/SKILL.md`
Part 2 §"Subagent Spawn Contracts" ("Pointers, not payloads" paragraph).

## Audit table

| # | Site | file:line (at audit) | ~pasted chars | Converted / exception | Rationale |
|---|------|----------------------|---------------|-----------------------|-----------|
| 1 | Supervisor → Orchestrator spawn (`Acceptance criteria: {criteria}`) | `skills/async-orchestration/SKILL.md` §Subagent Spawn Contracts, ~L681 | 0.5–2k (brief acceptance-criteria section) | **CONVERTED** | Brief is file-backed; Orchestrator runs at the project root so the gitignored `.supervisor/jobs/in-progress/` path resolves. Now: brief pointer + ≤200-char summary + read-only-needed-sections. Beads `task: BD-XX` mode (no brief file) points at `bd show {task_id}` or passes criteria inline — the only non-file-backed input on this seam. |
| 2 | Supervisor → Execute Manager spawn (`Subtask list: [{ids, titles, criteria, files, skills, deps}]`) | `skills/async-orchestration/SKILL.md` §Subagent Spawn Contracts, ~L691; mirror in `agents/supervisor.md` §Parallel Path, ~L258 | 1–6k (full per-subtask criteria/file/skill lists) | **CONVERTED** (both mirror sites, kept in sync) | Now: brief pointer (main-checkout path — resolves for the EM, which runs at the project root, NOT inside worker worktrees) + compact index (ids/titles/deps only). EM reads criteria/files/skills/`provides:` from the brief itself (`agents/execute-manager.md` Inputs + Step 1 updated to match). **No-brief (`/supervisor task:`) mode:** no brief file exists — the contract falls back to `.supervisor/requirements/{slug}-plan.md` (Beads-absent) or `bd show {id}` (Beads), or inline criteria as a documented exception (same text at all mirror sites). |
| 3 | Supervisor → fast-path Worker spawn (`Acceptance criteria: {criteria}`) | `skills/async-orchestration/SKILL.md` §Subagent Spawn Contracts, ~L706 | 0.5–2k | **CONVERTED** | Now: brief pointer + ≤200-char summary. Safe because the fast-path worker's worktree path IS the project root, so the gitignored brief resolves (stated in the contract text). **No-brief (`/supervisor task:`) mode:** falls back to `.supervisor/requirements/{slug}-plan.md` (Beads-absent) or `bd show {id}` (Beads), or inline criteria as a documented exception. |
| 4 | Supervisor → fast-path Code Reviewer spawn (`Task context: {subtask_title} — {criteria}`) | `skills/async-orchestration/SKILL.md` §Subagent Spawn Contracts, ~L732 | 0.5–2k | **CONVERTED** | Same brief-backed criteria; reviewer runs blocking at the project root, path resolves. Now: title + ≤200-char summary + brief pointer. **No-brief (`/supervisor task:`) mode:** falls back to `.supervisor/requirements/{slug}-plan.md` (Beads-absent) or `bd show {id}` (Beads), or inline criteria as a documented exception. |
| 5 | Execute Manager → Worker spawn ("subtask details … criteria") | `agents/execute-manager.md` Step 3, ~L175 | 0.3–1.5k (can exceed 1k on rich criteria) | **CONVERTED** | Now: bounded ≤200-char criteria summary + the **pinned MAIN-CHECKOUT ABSOLUTE brief path** with "Read only your subtask's section" — pinned explicitly because these workers sit in worktrees where the gitignored brief is **absent** (the worktree-reality case). `provides:` stays verbatim (row 6). **No-brief (`/supervisor task:`) mode:** falls back to `.supervisor/requirements/{slug}-plan.md` (Beads-absent) or `bd show {id}` (Beads), or inline criteria as a documented exception — with the same worktree pin (the gitignored plan file is also absent inside worker worktrees, so its main-checkout absolute path is pinned). |
| 6 | Worker `provides:` YAML paste (`Provides (verbatim from the brief's Subtask Contracts)`) | `skills/async-orchestration/SKILL.md` §Worker contract ~L715; `agents/execute-manager.md` Step 3 ~L175; referenced by `agents/supervisor.md` ~L635 | typically <1k (a few YAML lines per subtask) | **EXCEPTION (kept, annotated inline)** | The worker's Step 5.5 outputs-verification re-reads `provides:` **from the spawn prompt** — it is the v12 outputs gate's required input; a pointer would make a correctness gate depend on a file read the worker may skip, and on the parallel path the gitignored brief is absent in the worktree. Small by construction. |
| 7 | Launch Pad → Plan Reviewer full-brief paste (`--- BRIEF START --- {complete brief text} --- BRIEF END ---`) | `agents/launch-pad.md` §Spawn contract, ~L528–542 | 4–8k | **EXCEPTION (kept)** | The brief is **not file-backed at review time**: it exists only in Launch Pad's Phase 5 context — the save to `.supervisor/jobs/pending/` is gated ON the Plan Review outcome (PASS saves; FAIL never saves). Pre-saving a file just to point at it would invert the gate. The reviewer must also check all 15 criteria against the full text every time — partial reads defeat the review. |
| 8 | Phase 4.5 fix-task findings list (`{numbered list: file:line + description + suggestion}`) | `skills/self-heal-advisory/SKILL.md` Part 2 review-and-fix loop, ~L657 | 0.3–3k | **EXCEPTION (kept, annotated inline)** | **Not file-backed** — `CODE_REVIEW_RESULT` exists only in the reviewer Task's transcript, no durable on-disk artifact, so a pointer has nothing durable to point at. Already bounded by construction (`category=new` + severity ≥ HIGH only), and the fix worker provably needs each finding's full file:line + description + suggestion every time — they ARE the work items. Writing findings to a scratch file just to point at it would add a write path to a review seam that has none. |
| 9 | review-heal fix workers (`{fixable}` findings) | `skills/review-heal/SKILL.md` Step 2 ~L146 and §Validate-Then-Fix ~L404; described in `agents/review-pr.md` | 0.3–3k | **EXCEPTION (kept)** | Same rationale as row 8: transcript-backed review findings (plus validated bot findings resolved in-context from the GitHub API, also not file-backed), bounded, and the fixer needs the full finding text every time. |
| 10 | Phase 4.5 reviewer enrichment lines (`{prior_churn summary}` / `{area_knowledge summary}` / `{house_rules summary}`) | `skills/self-heal-advisory/SKILL.md` Part 2, ~L617–621 | bounded reader outputs | **ALREADY COMPLIANT (no change)** | These are the *summary half* of the pointer pattern by design: `read-postmortem.sh` / `read-bridge.sh` / `read-rules.sh` emit bounded digests of file-backed corpora. Pointing the reviewer at the raw corpora instead would UNBOUND the content and break two invariants: the readers' fail-safe self-gating (empty output ⇒ omit the line) and the "corpus is fed to the REVIEW lens only, never to workers/fixers" seam. |
| 11 | Rubric grader (`{numbered list of rubric_bullets}`) | `skills/self-heal-advisory/SKILL.md` Part 2, ~L757 | 0.2–0.7k (3–7 one-line bullets by authoring rule) | **BELOW THRESHOLD (no change)** | Under 1k by construction, and the grader must score EVERY item — a partial read is a wrong grade. |
| 12 | System Twin contract-builder (`{incident_map}`) | `skills/self-heal-advisory/SKILL.md` Part 1, ~L403 | small (touched subsystems only) | **BELOW THRESHOLD (no change)** | This-run derived in-context data, not file-backed; bounded to the run's touched subsystems. |
| 13 | `/dreaming` reflection-mode prompts | `commands/dreaming.md` INPUTS block, ~L102–110 | n/a | **ALREADY POINTER-NATIVE (no change)** | Inputs are numbered lists of **absolute paths** to session logs, worker summaries, and briefs; the reflection agent reads the files itself. This is the pattern's reference implementation. |
| 14 | QA Executor → QA Strategist spawns | `agents/qa-executor.md` ~L521, ~L603 | n/a | **ALREADY POINTER-NATIVE (no change)** | `Discovery data at: discovery/`, `Generated tests at: {testDir}/` — path pointers. |
| 15 | `/autonomous` review-heal Task step | `skills/autonomous-loop/SKILL.md` ~L440 | n/a | **ALREADY POINTER-NATIVE (no change)** | Passes `pr_url` + skill reference; the Task resolves the branch and diff itself. |
| 16 | Phase 4.5 red-team advisory lens spawn | `skills/self-heal-advisory/SKILL.md` Part 2, ~L822 | n/a | **ALREADY POINTER-NATIVE (no change)** | Passes branch, PR URL, and a diff *expression* (`git diff $BASE_BRANCH...HEAD`) — the reviewer computes the diff itself. |
| 17 | `/autonomous` refined-requirement templates (`<original requirement body … verbatim>`) | `skills/autonomous-loop/SKILL.md` ~L512/L578/L671 | n/a | **OUT OF SCOPE (no change)** | These are file-**authoring** templates: they produce the next iteration's requirement file — the durable artifact that later handoffs point AT. The copy is artifact creation (with the rubric-freeze invariant attached), not a spawn-prompt paste. |
| 18 | Part 1 "Worker Prompt Template" teaching sketch (`**Acceptance criteria:** {criteria}`) | `skills/async-orchestration/SKILL.md` Part 1 §Background Worker Dispatch, ~L181 | 0.5–2k | **CONVERTED** | Teaching template for background-dispatch mechanics, now showing the same pointer shape as the normative contracts: bounded ≤200-char criteria summary + pinned MAIN-CHECKOUT ABSOLUTE brief path + "read only your subtask's section" (worktree-resident consumer — the worktree-reality case). `provides:` / house-rules / the no-brief (`/supervisor task:`) fallback are deliberately deferred to Part 2 §Subagent Spawn Contracts + `agents/execute-manager.md` Step 3 (the authorities), stated in a note beneath the template. |

Sites 1–5 and 18 were converted in this change; sites 6–9 are the justified exceptions;
sites 10–17 were audited and found already compliant, below threshold, or out of scope.

## HONEST CACHE EXPECTATION (do not overclaim)

**Cross-agent prompt-cache reuse is structurally ZERO.** Prompt caching is a prefix
match over the WHOLE rendered request, and the harness renders each agent's `tools:` /
`disallowedTools:` frontmatter BEFORE the system prompt. Every agent type carries a
different tool set, so two different agent types diverge at position 0 no matter how
byte-identical their `.md` openings are. A shared leading block across agent prompts
**cannot** produce cross-agent cache reads — its value is **consistency, dedup, and a
smaller prompt inventory**, and it must be framed as exactly that.

**Where the cache win is real: SAME-ROLE respawns.** N workers in one Phase 3 wave,
and repeated reviewer / fix-worker spawns in the heal loop, already share identical
agent files — there, stable-prefix-first ordering within each spawn contract plus
volatile-last discipline (task id, paths, criteria summaries at the END of the prompt)
is what pays. The pointer conversions in this audit *help* that: a path + bounded
summary is a much smaller volatile tail than a pasted body, so more of each same-role
prompt is byte-stable across respawns.

**Measurement plan:** the token ledger (`emit-token-ledger.sh`, per-session JSONL
`token_ledger` lines) attributes the change — measure the cache-read share delta on
same-role respawn sequences (Phase 3 waves, heal-loop reviewer spawns) before/after.
Do NOT claim cross-agent cache reuse without ledger evidence (expected ≈ zero per the
above).

## Roadmap: Batch API (documented follow-up only — no code)

Anthropic's Message Batches API offers discounted, async processing that would suit
the plugin's non-interactive analysis surfaces (postmortem categorization, insights
corpus passes, dreaming distillation, eval runs). It is **out of scope for
implementation**: the plugin runs on the Claude Code subscription runtime — there is
no API-key path from hooks/agents to route requests through the Batch API. Recorded
here as a follow-up to revisit if/when an API-key execution path exists (e.g. the
quarantined SDK-runner spike graduating with its own credential model). No code, no
flags, no behavior change ships with this note.
