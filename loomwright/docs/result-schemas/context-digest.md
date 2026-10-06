## CONTEXT_DIGEST

A per-job **file artifact** — not an agent result block — built by `${CLAUDE_PLUGIN_ROOT}/scripts/build-context-digest.sh` from the assembled Supervisor-Ready Brief text and pointer-handed to every worker spawned on the job, on both the Task-spawn carrier and the SDK-runner carrier (`skills/async-orchestration/SKILL.md` §"Context digest pointer"; `sdk-spike/src/runner.ts`'s `contextDigestPointer`). It carries **no `schema_version` field** and is **not validated by any `SubagentStop` hook** — correctness enforcement lives in `scripts/test-context-digest.sh` instead (see below). Introduced in v15.20.0 (D6 — worker shared-context digest + explicit file lanes): spawned workers cold-start with an empty context and each re-derives the same codebase understanding Launch Pad already computed at Phase 3 (the File Impact Map) and Phase 4 (subtask contracts); the digest hands that analysis over once per job instead of once per worker.

**Producer:** Launch Pad, Phase 5 PACKAGE, immediately after the brief is assembled (`agents/launch-pad.md` §"Phase 5: PACKAGE" step 9 — "MATERIALIZE — scratch file + context digest"). The write is **NOT gated on Phase 5.5 Plan Review** — the digest is a derived analysis artifact (File Impact Map, subtask contracts, lanes), not the brief itself, so it exists as soon as Phase 5 PACKAGE completes even if the brief later fails review or is discarded. This is a deliberate divergence from the brief's own gated save (`docs/POINTER_AUDIT.md` row 7, "the brief is not file-backed at review time") — a stray digest file left behind by a discarded/failed-review brief is harmless: it is bounded, gitignored, and has no downstream consumer without a matching saved brief to point at it.

**Path convention:** `.supervisor/jobs/context-digests/{basename(brief_path)}` — the same basename as the brief file, in a sibling directory under `.supervisor/jobs/`, mirroring the existing `{pending,in-progress,done,failed}/{basename}` lifecycle-directory convention (the `{basename(current_brief_path)}` anchor pattern already used by `skills/autonomous-loop/SKILL.md`). Callers pass this path explicitly via `build-context-digest.sh --out`; the script's own built-in default (`.supervisor/jobs/context-digests/context-digest.md`) is a single-file fallback for ad-hoc/manual invocations only, not the documented per-job path.

**Lifecycle — write-once, never pruned (deliberate, bounded):** unlike the brief itself, a digest does NOT move as its job flows `pending → in-progress → done/failed`; it is written once at Launch Pad Phase 5 MATERIALIZE and left in place. Nothing garbage-collects `context-digests/`, so it accumulates one file per job. That is accepted rather than overlooked: each entry is capped at 6000 bytes (so 1000 jobs ≈ 6 MB worst case), the whole tree is gitignored, and a digest deliberately outlives its job — it stays readable for post-hoc inspection of what a worker was actually handed, which a prune-on-completion rule would destroy exactly when a postmortem needs it. Operators wanting the space back can delete the directory at any time: every consumer treats a missing digest as advisory-absent (`contextDigestPointer` returns `undefined`; every spawn contract says "proceed without it").

**Bound + truncation marker (AC2 — the digest is NEVER unbounded):** hard cap of 6000 bytes by default (`CONTEXT_DIGEST_MAX_CHARS` env override; `--max-chars` flag; the flag keeps `build-repo-map.sh`'s `chars` spelling but the cap and every
budget derived from it are measured in **bytes**), mirroring `build-repo-map.sh`'s `--max-chars` cap contract exactly. When the assembled digest exceeds the cap, it is truncated so the TOTAL file (content + marker) fits within the cap, with a final line:

```
[context-digest truncated at N chars]
```

> **Sizing contract (v15.20.0).** The digest is bounded (default 6000 bytes) and the bound is
> honored by **per-section budgeting**, not by truncating the tail. Every heading is emitted
> UNCONDITIONALLY, and a section that was clipped says so with its own marker — so a consumer can
> always distinguish "the brief declared none" (`_(none found)_`) from "the cap clipped it"
> (`_(truncated …)_`). Budget is granted in priority order — contracts, interfaces, sibling
> summary, conventions, then File Impact Map last — because tail-first truncation previously
> deleted the Cross-lane contracts section outright on 8 of 72 archived briefs, i.e. on the
> largest and most parallel jobs, which is exactly where lane ownership matters most.
>
> **Per-section floor.** Priority order governs the *surplus*, not the whole pool: each of the
> five sections may first reserve up to 10% of the pool (capped at what it actually needs, so an
> absent or short section returns the remainder immediately), and only then is the rest granted
> in priority order. Without that floor the highest-priority section can consume the entire pool
> and every later section renders as a bare `_(truncated)_` with ZERO content — measured on 15 of
> 72 archived briefs, worst case 4 of 5 sections. A floor too small to hold one whole line
> (<80 bytes, i.e. only at a very tight cap) is skipped in favour of pure priority order, since
> `clip` cuts on line boundaries and a sub-line floor would yield nothing but the marker.
>
> **Budgets are measured in BYTES**, matching the unit the cap is enforced in (`wc -c`), via
> `blen()` rather than `${#var}` — the latter is a *character* count under a UTF-8 locale and a
> byte count under `C`/`POSIX`, so identical input produced different budgets depending on the
> caller's environment (measured: `a — b` is 5 under `en_US.UTF-8`, 7 under `C`). That is a
> latent, locale-dependent defect, **not** the cause of the one observed cap overshoot: that
> overshoot reproduced *identically* under both locales and was the fixed-overhead constant
> (`260`) underestimating the real header/heading overhead. Both are addressed — budgets are now
> locale-invariant, and the per-section floor leaves enough slack that the constant no longer
> binds. The whole-file backstop remains a last-resort invariant guard, and
> `scripts/test-context-digest.sh` asserts across the archived corpus, **under a pinned UTF-8
> locale**, that it never fires.
>
> **Cap floor.** The digest has a fixed overhead of its own (~900 bytes: title, headings, the
> cross-lane explainer, and the per-section marker reserve), so a cap must fund that *plus* a
> content floor. A cap below the full-fidelity overhead first triggers a **shrink** — short
> truncation markers, explainer dropped — spending the budget on the brief's data rather than
> the builder's prose. A cap that cannot fund even the shrunk form writes **nothing**, reports
> why on stderr, and still exits 0: an absent digest is honest and every consumer already
> handles absence, whereas a digest of headings and empty markers claims to carry analysis it
> does not have. (Before v15.20.0's cap-floor fix, any `--max-chars` below ~1200 produced
> exactly that contentless output and reported success.)

**Sections (in order):**
1. `## File Impact Map` — the brief's `## File Impact Map` table verbatim **when present**, which is the RARE case: measured 2026-07-31, only 10 of 73 archived briefs carry that heading. Otherwise derived from `## Subtask Structure` + `### File Overlap Matrix` (72/73 and 28/73) — the common path — with a note recording which source was used. This section is allocated budget LAST (see the size note below), so it is the one that absorbs a cap squeeze.
2. `## Interfaces touched` — deduplicated bullet list of every `{kind: symbol|type, path, name}` entry across all subtasks' `provides`/`requires` YAML, rendered `path :: name (kind)`.
3. `## Conventions` — the brief's `## Environment` block plus `## Skill References` (71/73 and 54/73). **Not** `**Tech Stack:**` / `**Architecture:**` bold lines: that was the original implementation and it was measured (2026-07-31) to match **0 of 73** real briefs — dead code, removed in v15.20.0.
4. `## Sibling-subtask summary` — verbatim copy of the brief's Subtask Structure table (title / criteria subset / files / skills / status per subtask).
5. `## Cross-lane producer/consumer contracts` — the brief's contract YAML block(s) verbatim, resolved through a layout ladder because real briefs use at least six shapes: the umbrella headings `Subtask contracts` / `Provides / Requires Contracts` / `Provides / Requires Schema` / `Subtask Detail`, then per-subtask `### Subtask N` / `### ST N` headings with no umbrella, then a STRUCTURAL fallback collecting any fenced block carrying a contract key. Measured after v15.20.0: 54/54 contract-bearing briefs populate this section (a single-heading lookup left 54 of 72 empty), i.e. every subtask's `provides` / `requires` / `lanes` / `external_requires` together — this IS the producer/consumer + lane-ownership data; the digest does not re-derive lane-collision logic (that rule lives in `skills/supervisor-readiness/SKILL.md` §"Lane Declaration Schema" and the worker-side `out_of_lane` gate — see the `WORKER_RESULT` schema above).

A section with no matching content in the source brief is rendered `_(none found)_` rather than a hard failure — the builder is **fail-safe** (always exits 0, mirroring the sibling `build-*.sh` advisory-artifact convention: `build-repo-map.sh`, `build-handoff.sh`). Correctness enforcement (bound honored, truncation marker present, worktree-absolute pointer form, same-wave lane overlap flagged vs sequentially-ordered sharing not flagged) is `scripts/test-context-digest.sh`'s job, which — per that same sibling convention — is allowed to fail loudly on a genuine assertion failure; the builder itself never is.

**Consumption:** pointer-handed as `path + ≤200-char summary + "Read only the sections you need"` (`docs/POINTER_AUDIT.md` §"The rule" and §"Context digest"). Parallel-path (worktree-resident) workers receive the **main-checkout absolute path** — gitignored `.supervisor/` artifacts do not exist inside linked git worktrees (`docs/POINTER_AUDIT.md` §"Worktree reality") — while Single-Agent-/Sequential-path workers and Execute Manager (all project-root-resident) may use the repo-relative path directly. The exact spawn-prompt wording lives in `skills/async-orchestration/SKILL.md` §"Context digest pointer" (Task-spawn carrier) and `sdk-spike/src/runner.ts`'s `contextDigestPointer` (SDK-runner carrier) — this section documents the artifact contract only, not the spawn-prompt text.

---

