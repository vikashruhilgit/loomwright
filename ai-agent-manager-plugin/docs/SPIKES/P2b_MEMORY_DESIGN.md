# P2b — Agent-Writable Project Memory (DESIGN, for review)

> Status: **IMPLEMENTED in v14.3.0 (PR #18)** — retained as the design / rationale record.
> P2b is the red-team's *single most
> dangerous idea* (memory the system writes and later trusts), so this nails the
> safety-critical decisions before implementation. Builds on the v14.2.x Memory
> Core Principle (now in `AGENT_GUIDELINES.md`) and the doc-currency gate (P2a).

---

## 1. Goal & threat model

**Goal:** give the plugin a small, durable, cross-session **project memory** so it stops
re-discovering the codebase every run (OpenHands' documented failure) — *without* letting
the system trust unvetted self-writes.

**Threat model (what we defend against):**
- **Worktree data-loss / repo pollution** (red-team F1, FATAL) — parallel workers in git
  worktrees writing divergent memory copies that vanish on `git worktree remove`, or memory
  files getting committed into the user's app repo.
- **Memory poisoning** (MINJA/MemoryGraft) — a malicious requirement, dependency README, or
  tricked agent appending a poisoned "fact" that later agents read as ground truth.
- **Slow drift** — low-value/incorrect entries accumulating until memory misleads.

**Non-goals for P2b (deferred):** `LESSONS.md` reflection (P4), reusable playbooks (P4/P5),
vector/semantic recall (deferred unless file+grep fails at scale), `/dreaming` extension (P4).

---

## 2. Data layout (all under the already-gitignored `.supervisor/`)

```
.supervisor/memory/
├── PROJECT_MEMORY.md      # advisory index, ≤200 lines / 25KB, one fact per line, provenance-tagged
├── topics/<topic>.md      # on-demand detail, ≤400 lines each (e.g. auth-flow.md, deploy.md)
└── .provenance.jsonl      # hash-chained provenance, one entry per PROJECT_MEMORY line
```

- `.supervisor/` is gitignored (`.gitignore:34`) → memory never pollutes the user repo. P2b adds
  an idempotent "ensure `.supervisor/` ignored" guard before first write (mirrors `state-management`).
- **Entry format** in `PROJECT_MEMORY.md` (one line): `` - [<id>] <fact text> `` where `<id>`
  links to the provenance record. Topic files are free-form markdown the index points to.

---

## 3. Single-writer rule (kills the worktree-divergence FATAL)

**Workers NEVER write memory.** Workers run in worktrees with a CWD that is *not* the repo root;
any relative `.supervisor/memory/` write would diverge and be destroyed on worktree removal.

- Workers may *propose* learnings via a new **optional** `WORKER_RESULT.memory_candidates[]` field
  (array of short strings; absent by default — additive, no schema_version bump for the optional add,
  per the existing WORKER_RESULT v2 pattern).
- **The sole writer is Context-Keeper** (already the sole writer of `.supervisor/`), invoked by the
  main thread / Execute Manager with the **repo-root CWD resolved once at session start** (never a
  worktree path). It writes via `scripts/write-project-memory.sh`.
- This reuses the proven Context-Keeper sole-writer contract instead of inventing a new one.

---

## 4. Write path — `scripts/write-project-memory.sh` (sole sanctioned writer)

Contract: `write-project-memory.sh --fact "<text>" --source "<session_id|code-reviewer|...>"`
1. Resolve memory dir against the **repo root** (refuse to run if CWD looks like a worktree —
   `git rev-parse --show-toplevel` vs a `../<project>-<subtask>` sibling pattern → abort).
2. Compute `content_hash = sha256(fact)`, `id = short hash`, `prev_hash = sha256(last provenance line)`
   (genesis = a fixed constant for the first entry).
3. Append `` - [<id>] <fact> `` to `PROJECT_MEMORY.md` and the provenance entry (§6) to
   `.provenance.jsonl` — **atomically** (write temp, `mv`).
4. **Write-time eviction** (Memory Core Principle hard cap): if `PROJECT_MEMORY.md` > 200 lines,
   evict the lowest-value entry (v1: oldest by provenance `written_at`; v2 could use a recall
   counter) — remove its line AND append an `evicted` provenance record (never silently drop).
5. Always exit 0 on best-effort failures that don't corrupt state; exit non-zero only on a
   would-corrupt condition (so a bad call can't half-write).

**What triggers a write (human-gated promotion — conservative for v1):** memory is NOT
auto-written from raw agent output. Candidates surface as **proposals** (Code Reviewer's existing
"Proposed CLAUDE.md Update" pattern, or `WORKER_RESULT.memory_candidates[]`), and a human (or, in
P4, `/dreaming` with per-item approval) approves before Context-Keeper calls the writer. P2b ships
the *mechanism*; promotion stays human-gated. This is the primary poisoning defense.

---

## 5. Read path — `scripts/read-project-memory.sh` (sole sanctioned reader; the read-side gate)

The red-team's key point: **write-side provenance is theater unless something reads it before
trusting an entry.** So reads go through a gate, not raw `cat`.

Contract: `read-project-memory.sh` →
1. Validate the hash chain in `.provenance.jsonl` from genesis. On the first broken link, mark that
   entry **and all after it** untrusted.
2. Emit only `PROJECT_MEMORY.md` lines whose `content_hash` matches a *chain-valid* provenance entry.
   Lines with no valid provenance (e.g. an out-of-band poisoned append) are **dropped + reported to
   stderr** (`.supervisor/logs/memory.log`).
3. Prefix output with an advisory banner: *"Advisory project memory — subordinate to CLAUDE.md; on
   conflict, CLAUDE.md wins."*

**Who reads:** Launch Pad (during discovery) and Supervisor (ACQUIRE) call this helper on demand —
**not** a SessionStart injection (see §7). Other commands don't read memory. This is "just-in-time
retrieval" per the Memory Core Principle (filesystem + a gated helper, no RAG).

---

## 6. Provenance scheme (tamper-**evident**, honestly scoped)

`.provenance.jsonl`, one JSON object per line:
```json
{"id":"a1b2c3","prev_hash":"<sha256 of prior line, or GENESIS>","content_hash":"<sha256(fact)>",
 "source":"<session_id|agent|user>","action":"add|evict","written_at":"<ISO8601>"}
```
- **Hash chain** → any out-of-band edit/insert/delete breaks `prev_hash` continuity, so the reader
  detects tampering and distrusts from the break onward.
- **Honest limitation:** in a file-based system the chain lives in the same writable dir, so this is
  tamper-**evidence**, not tamper-**proofing** (an attacker who rewrites the whole chain consistently
  isn't detected). That's acceptable because (a) the *real* defense is human-gated promotion (§4) +
  memory-is-advisory-never-enforcement (§8), and (b) the chain catches the realistic case: a
  poisoned line appended without rewriting history. Per the red-team's instruction: we ship a real
  read-side check, and we do **not** overclaim it as a security boundary.

---

## 7. SessionStart injection — considered & REJECTED for v1

The original plan floated scoped/lazy `SessionStart` injection of the memory index. Rejected:
- **Per-session tax** (red-team C3): SessionStart fires on *every* session incl. cheap utility
  commands; injecting memory there taxes runs that don't need it.
- **Soft scoping:** the hook can't reliably tell which agent/command is running, so "only planning
  agents" can't be enforced at the hook.
- **On-demand read is strictly better:** Launch Pad/Supervisor explicitly call
  `read-project-memory.sh` when they need it — natural scoping, mechanical provenance gate, zero tax
  elsewhere. (`session-resume.sh`'s SessionStart role — crash/compact recovery — is unchanged.)

---

## 8. Subordination & safety invariants

- Memory is **advisory**; on any conflict with the human-authored `CLAUDE.md`, CLAUDE.md wins
  (stated in the read banner + agent prompts). Memory is **never an enforcement boundary** — hard
  gates stay in hooks (Anthropic guidance; existing plugin stance).
- Workers can't write it; only Context-Keeper (repo-root CWD) can.
- Every write is provenance-chained; every read is provenance-gated.
- Bounded (≤200/≤400 lines) with write-time eviction.

---

## 9. Tests (the worktree one is a MERGE BLOCKER)

1. **Worktree-concurrency (blocker):** create 2 sibling worktrees; assert (a) the writer aborts if
   invoked with a worktree CWD, (b) parallel "worker" sims write nothing under `.supervisor/memory/`,
   (c) the repo-root `PROJECT_MEMORY.md` remains the single source. Proves F1 is closed.
2. **Provenance tamper-detection:** valid chain → all lines emitted; flip one byte in a mid-chain
   `content_hash` → that line + all after are dropped (reader exits clean, logs the break).
3. **Poison drop:** append a line to `PROJECT_MEMORY.md` with no provenance entry → reader drops it.
4. **Eviction:** write 201 facts → file capped at 200, oldest evicted, `evict` provenance recorded.
5. **Gitignore:** `.supervisor/memory/` is `git check-ignore`-d.
All wired into a `scripts/test-project-memory.sh` self-test (mirrors `test-webhook.sh`).

---

## 10. Version / hook / count impact (interacts with the P2a gate)

- **New runtime → plugin version bump to v14.3.0.**
- New files: `scripts/write-project-memory.sh`, `scripts/read-project-memory.sh`,
  `scripts/test-project-memory.sh`. (Repo `scripts/` for the test; plugin `scripts/` for the
  read/write helpers since agents call them at runtime via `${CLAUDE_PLUGIN_ROOT}`.)
- **Possible new hook:** a `WORKER_RESULT` validation tweak to accept `memory_candidates[]` (extends
  the existing worker SubagentStop prompt — no new hook entry, so hook count stays 19). If we add a
  memory-write audit hook, that's +1 → 20, and **the P2a doc-currency gate will force** updating
  every "19 hooks" claim in the same PR (dogfooding the gate).
- Agent prompt changes: Launch Pad + Supervisor (read memory on demand), Context-Keeper (write +
  evict), Worker (emit `memory_candidates[]`). `RESULT_SCHEMAS.md` gains the optional field + a
  `PROJECT_MEMORY` provenance note.

---

## 11. Open questions for you (decide before I code)

1. **Promotion trigger for v1** — keep it strictly human-gated (proposals → you approve → write), or
   allow Context-Keeper to auto-write a *narrow* class (e.g. Code Reviewer pattern proposals the
   human already approved in the CLAUDE.md-update workflow)? *Recommendation: strictly human-gated
   for v1; auto-write is P4 via `/dreaming`.*
2. **Helper location** — read/write helpers in the **plugin** `scripts/` (runtime, `${CLAUDE_PLUGIN_ROOT}`)
   vs repo `scripts/`. *Recommendation: plugin scripts/ (agents call them at runtime).*
3. **Scope of first wire-up** — both Launch Pad *and* Supervisor read memory in v1, or just Launch
   Pad (smaller blast radius)? *Recommendation: Launch Pad only in v1; add Supervisor in a follow-up.*
4. **`sha256` dependency** — `shasum -a 256` (macOS) / `sha256sum` (Linux); the helper detects which.
   OK, or prefer a pure-shell fallback? *Recommendation: detect shasum/sha256sum; abort-with-warn if
   neither (provenance disabled → memory read-only-empty, fail-safe).*
