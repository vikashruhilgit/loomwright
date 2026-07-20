# Spike: Owning code-structure intelligence (build vs. third-party graph product)

**Status:** Investigated → built → **VALIDATED → reposcan PARKED.** The Tier-1 repo-map was built and measured
(4 repos / 4 languages), then its ranking **failed** independent validation. Decision: use **LSP + graphify
as-is** (enough); keep the **validation harness**; resume reposcan only if needed. Full story in **Outcome** below.
**Updated:** 2026-06-27.
**Date:** 2026-06-25
**Scratch (gitignored):** `.supervisor/scratch/code-graph-spike/` (`reposcan.py` + run artifacts)
**Test bed:** BetterBlocks — Unity/C#, 219 source files, ~43k LOC, ~550k source tokens.

---

## Outcome (TL;DR — read this first)

1. **Built** a deterministic Tier-1 repo-map (`reposcan`, tree-sitter + PageRank). Measured great *compression*
   (289×–1273×) across 4 repos / 4 languages (C#/TS/Dart/Py). The journey is recorded below.
2. **Validated it** against an independent ground truth (the real import graph) — and it **FAILED**: ranking
   scored **0/10** on the most-imported files, **32% edge precision**. The "type-only edges" fix solved
   *test-file noise* but introduced *value-hub blindness* — it ranks symbol-RICH files, not the most-DEPENDED-ON
   ones. Earlier "ranking looks right" was confirmation bias.
3. **An import-edge fix scored 7/10** (the validated resume path) — but needs per-language resolution (TS/Py/Dart
   imports resolve to files; C#/Java namespace-imports + monorepos need symbol resolution / LSP).
4. **graphify, judged fairly** (it is a Q&A/navigation tool, NOT a ranker), is **good at feature/concept
   navigation, weak at precise code-dependency** — complementary to LSP, not a competitor. My earlier "graphify
   0/10" was an unfair cross-task test; **retracted**.
5. **Decision: reposcan PARKED.** LSP (precise structure, always fresh, already in code-reviewer) + graphify
   (concept navigation, advisory, already integrated) are **enough** for the code half. The kept deliverable is
   the reusable **validation harness** (`validate.py` / `validate_gen.py`) — any future graph must pass it.
   See `NORTH_STAR_DIRECTION.md` Bet 1 (now de-scoped to LSP wiring).

> The sections below are the **full journey** — research, the build, the *later-disproven* claims (kept, with
> ⚠️ corrections), the validation, the graphify investigation, and the distilled lessons.

---

## Question

Instead of depending on a vendor *product* (graphify-as-a-service, GitNexus, CodeGraph) for code
intelligence, can we **own** a deterministic "where to look / what's connected" capability built only on
**open primitives** (tree-sitter, LSP, SCIP/stack-graphs)? What are the challenges, and can we beat them?

Reframe that motivated the spike: tree-sitter / LSP / SCIP / stack-graphs are open *infrastructure*, not
products — building on them is ownership, like depending on `git` or a compiler. The only thing we author is
the thin glue (extraction orchestration + ranking + cache + the advisory read seam).

## The three ownable tiers

| Tier | What we build | Primitive | Solves |
|---|---|---|---|
| **0 — LSP on-demand** | *nothing* (code-reviewer already has `LSP`) | LSP | Exhaustive callers / impact, deterministic, **always fresh, zero cache** |
| **1 — repo-map** | tree-sitter + personalized PageRank, token-budgeted, SHA-cached | tree-sitter | Cheap ranking / "where to look", huge token compression |
| **2 — owned graph** | tree-sitter + stack-graphs, file-incremental, confidence-tagged | stack-graphs (SCIP) | A persistent graph we own; staleness structurally impossible |

This spike built **Tier-1** (the uncertain, high-value artifact) and validated the Tier-0 premise by design.

---

## Tier-1 results (measured on BetterBlocks)

`reposcan.py` — ~210 LOC, zero vendor deps (`tree-sitter` + `tree-sitter-c-sharp` via `uv run`).

| Metric | Value |
|---|---|
| Files parsed | 219 |
| Parse time (full, cold) | **0.3 s** |
| Full source tokens (est) | ~550,485 |
| Repo-map tokens (est) | ~1,906 |
| **Compression** | **~289×** |
| Incremental cache (warm re-run) | **219/219 unchanged detected** (SHA manifest) |

**Ranking quality (after fixing challenge #2):** top-ranked files are the genuine architectural hubs —
`GameConfig.cs`, `Theme.cs`, `ShopCatalog.cs`, `IInventory.cs`, `IWallet.cs`, `NavigationService.cs`,
`IScreen.cs`. These are exactly the files an agent should see first, and the most expensive to discover cold.

---

## Challenges found — and how we beat them (the spike's real payload)

1. **No type resolution → noisy edges (challenge #2, observed empirically).**
   *First run ranked test files (`ShopScreenTests`) above core classes.* Cause: common **method** names
   (`Reset`/`Push`/`SetUp`) are defined in many files and referenced everywhere, injecting spurious edges.
   **Mitigation (worked):** build edges from **type** names only (classes/interfaces/enums) + IDF —
   split a name's weight across its definers and drop names defined in >8 files. Edges 10,550 → 1,085;
   ranking flipped to correct hubs. *Method names stay in the skeleton, just not in the graph.*
   **⚠️ Later DISPROVEN as a *ranking* solution (see "Validation" below):** type-only edges fixed test-file
   noise but make the graph blind to function/component/value hubs — which are often the MOST-imported files.
   The validated fix is **import-based edges**.

2. **Staleness / cache invalidation (the user's central worry).**
   **Beaten structurally**, not with hooks: cache is keyed by **git-blob/content SHA** per file, so a warm
   re-run re-parses only what changed (219/219 unchanged detected here). A commit/PostToolUse hook becomes a
   mere *trigger*, never the correctness guarantee. This is the same file-incremental principle stack-graphs
   uses at GitHub scale.

3. **Completeness is high but NOT exhaustive.** Probe: graph in-edges to `GameConfig` vs `grep` ground truth
   → grep 101 / graph 94 (**8 missed, 1 spurious**). The lightweight approach is ~90%+ recall but imperfect
   precision *because* it lacks full type resolution. **Conclusion: Tier-1 is correct for ADVISORY ranking,
   wrong for ground-truth impact analysis** — for "trust this is ALL the callers" use Tier-0 LSP or Tier-2
   stack-graphs.

4. **Multi-language.** tree-sitter grammar per language; LSP server per language. Degrade gracefully (full
   where a grammar/server exists, skeleton elsewhere) — never hard-fail.

---

## Cross-repo validation (multi-language generalization)

`reposcan_multi.py` adds TypeScript / TSX / Python behind one per-language config (same algorithm,
type-only edges + IDF). Run on three real, unrelated codebases — **the ranking *appeared* to generalize cleanly
(⚠️ later disproven by validation — see below)**:

| Repo | Stack | Files | Parse | Full→map tokens | Compression | Top hubs surfaced |
|---|---|---|---|---|---|---|
| BetterBlocks | Unity / C# | 219 | 0.3 s | 550k → 1.9k | **289×** | `GameConfig`, `Theme`, `ShopCatalog`, `IInventory` |
| sports-management | Next.js / TS | 1,126 | 1.3 s | 2.58M → 2.5k | **1042×** | `lib/api-types.ts`, `lib/templates/types.ts`, schema/reducer modules |
| HUB (Tray) | NestJS+Next monorepo / TS | 2,358 | 1.5 s | 2.76M → 2.2k | **1273×** | `IPaginated`/`paginated.interface.ts`, `user.entity.ts`, `role.entity.ts`, correlation/DTO services |
| tray-pos-flutter | Flutter / Dart | 1,460 | 2.4 s | 2.25M → 2.0k | **1099×** | `app_typography`, `failures`, domain models (`menu_item`, `modifier_group`, `order`, `order_item`), `payment_provider` |

Four languages (C#, TS/TSX, Dart, Python) now share one extractor with no per-repo algorithm tuning.

**⚠️ Validation (below) later showed these RANKINGS are wrong** — the "top hubs" shown are symbol-rich files,
not the most-depended-on ones. The **compression and parse-time numbers stand**; the *ranking-quality* claim
("generalizes cleanly") does **not**. Read the Validation section before trusting any row's "top hubs" column.

Findings:
- **Generalizes with no per-repo tuning.** The type-only-edge heuristic that fixed C# noise works identically
  for TS (`type_identifier` refs → type defs) and Python (classes only). Top-ranked files are the genuine
  cross-cutting hubs in every repo (shared type modules, entities, interfaces).
- **Compression scales with repo size** (289× → 1273×) — confirming the payoff is on large codebases, exactly
  where cold-LLM exploration is most expensive.
- **Monorepo ranks are flatter** (HUB max rank 0.012 vs sports 0.096) — correct: a monorepo has many
  independent subsystems, no single god-object, so importance is distributed.
- **Vendored-dir exclusion works:** HUB's 499 "Python files" were 502 under `services/dw-service/.venv`
  (a virtualenv) — correctly skipped; only 5 are first-party. The SKIP heuristic filtered third-party noise
  as intended.
- Sub-3-second parse on 1,460–2,358-file repos (pure Python, single thread) — fast enough to run on a hook.

**Real-world hygiene findings (surfaced by dogfooding the Flutter repo):** a naive walker over-counts badly.
The Flutter run first ranked junk until two exclusions were added — both generic, both important for any builder:
- **Duplicate working copies:** `.claude/worktrees/` held full agent-worktree clones, so every hub file
  appeared 2–3× with identical rank. *Insight:* the SHA cache already hashes every file — identical-content
  files across paths can be **auto-deduped** (collapse same-SHA files), turning this from a config problem into
  a structural one.
- **Vendored multi-version SDKs:** `temp/Payments/` checked in `AlohaPaymentsCOM` at 4 versions
  (951 C# files) — third-party, duplicated per version, dominated the ranks. Excluded like `.venv`/`node_modules`.
- After exclusions the map is pure first-party code (1,460 Dart files) with architecturally correct hubs.
  Lesson: the exclusion list (`node_modules`, `.venv`, `.dart_tool`, `ios/Pods`, generated `*.g.dart`/`*.d.ts`,
  vendored/`temp`/worktree dirs) is load-bearing and must ship with the builder, not be discovered per repo.

## Decision (revised after validation — reposcan PARKED)

The spike's *compression* and *speed* numbers are real, but validation overturned the original "clears the bar"
conclusion: the **ranking measured the wrong thing**. Revised tier decision:

- **Precise code structure (callers / blast-radius / "which files central")** → **LSP (Tier-0)** — exhaustive,
  deterministic, always fresh, zero cache, already in code-reviewer. The workhorse. *Wired into
  worker / QA / launch-pad (advisory) in v15.5.0.*
- **Feature/concept navigation + "surprising connections"** → **graphify** (already integrated, advisory,
  validated good for this). Complementary to LSP.
- **Tier-1 reposcan repo-map** → **PARKED.** Ranking failed validation; the import-edge fix (7/10) is the resume
  path *if* LSP+graphify ever prove insufficient, and only back through the validation harness.
- **Tier-2 stack-graphs** → unbuilt; only if a persistent owned graph is ever justified.

Net: **no code graph needs to be built.** LSP + graphify cover the code half; the *decision* half is curation
(`NORTH_STAR_DIRECTION.md` Bet 2, handoff digest). The kept deliverable from this whole spike is the
**validation harness** — the discipline that no graph is trusted until it passes ground-truth on the real repo.

## Next steps (status)

- **DEFERRED** (reposcan parked): ~~Langfuse A/B~~, ~~generalize reposcan~~, ~~wire repo-map through brain-context~~.
- **Shipped (v15.5.0):** `LSP` wired from code-reviewer into worker / qa-executor / launch-pad (advisory, never-gating) — the last Bet-1 item is closed (agents' `tools:` frontmatter + the `ARCHITECTURE_CONTRACTS.md` capability matrix).
- **Kept:** the validation harness (`validate.py` / `validate_gen.py`) as the gate for any future graph.
- **Productized (v15.12.0):** the parked repo-map tier shipped as `loomwright/scripts/build-repo-map.sh` — the flat Tier B floor (directory skeleton + exported-symbol scan, best-effort tree-sitter Tier A); the PageRank ranker is still NOT ported (it failed validation and stays parked).

## Validation (the turning point — 2026-06-27)

**Method.** Score the repo-map against an INDEPENDENT ground truth — the real TypeScript import graph
(`import … from '…'`), extracted by a *different* method than reposcan's type-identifier matching, so agreement
is real validation, not circular. Resolved **99%** of local imports on sports-management (`@/`→root + relative).
Two axes: **edge precision** (reposcan edges backed by a real import) and **ranking** (top files by PageRank vs
the most-imported files). Harness: `.supervisor/scratch/code-graph-spike/validate.py` (+ `validate_gen.py`).

**Result — reposcan FAILED:**

| Metric | reposcan (type-edges) | graphify (symbol-count) | **import-edge fix** |
|---|---|---|---|
| Top-10 overlap w/ most-imported | **0/10** | **0/10** | **7/10** |
| Top-20 overlap | 2/20 | — | 16/20 |
| Edge precision (backed by a real import) | **32%** | — | 100% (by construction) |

reposcan ranked `api-types.ts` (45 imports) #1 — a real hub — but **missed the actual top hubs entirely**:
`auth-helpers.ts` (imported **320×**), `supabase-server.ts` (198×), `utils.ts` (137×), the UI primitives.

**Diagnosis — the deep lesson.** Type-only edges (and graphify's symbol-count) measure *"how much is DEFINED
here"* (symbol richness). But **importance is "how much DEPENDS on you"** (import in-degree). `api-types.ts`
defines 97 types so it *looks* central; `auth-helpers.ts` defines little but is imported everywhere — and is far
more central. The build-phase "type-only edges" fix over-corrected: killing method-name collisions also blinded
the graph to function/component/value modules, which are the most-imported files (especially in function-heavy
TS). "It found api-types, looks right" was confirmation bias.

**The validated fix — import-based edges.** Build edges from the real import graph (deterministic, 99%
resolvable on clean TS, 100% precise) instead of identifier matching. Ranking jumped **0/10 → 7/10**; the fixed
top-10 is the genuine spine (`utils`, `auth-helpers`, `supabase-server`, `session`, `rate-limit`, `button`).

**Generalization (`validate_gen.py`) — the defect is systematic and language-dependent:**

| Repo / lang | type-edge ranking | import resolution | note |
|---|---|---|---|
| sports-management / TS | **0/10** | 99% | function-heavy → type-edges fail hardest |
| HUB / TS monorepo | **1/10** | 71% | cross-package imports drop resolution |
| tray-pos-flutter / Dart | **5/10** | 73% | class-heavy → type-edges partially work |

The defect is **not a sports-management fluke**, and severity is **language-dependent** — worst in function-heavy
TS, milder in class-heavy Dart. **Corollary: the earlier C# (BetterBlocks) "looked right" result is now
suspect** — C# is class-heavy like Dart, so it was likely ~half-right and was never validated. The import-edge
fix needs **per-language resolution**: TS/JS/Py/Dart resolve to files; C#/Java `using`/`import` target a
*namespace*, needing symbol resolution (→ LSP) — exactly where Tier-0 LSP earns its place.

## graphify — investigated fairly (earlier comparison retracted)

The build phase framed this as "reposcan vs graphify, ours is cleaner." That was a **category error**, corrected
through three layers:

1. **Structural findings (real, but not the whole story):** the two graphify copies (personal-brain vs
   sports-management) are byte-identical; the graph is **57 files / 36 commits STALE** vs HEAD; and its top
   "code files" were polluted — `package.json` ranked **#1**, plus `.md` docs, `.supervisor/` generated
   artifacts, a duplicate `user-journeys copy.md`, and a **cross-machine path** (`C:/Users/mason/…`) leaked from
   another contributor's checkout. As a *clean code ranking* it is noisy and stale.
2. **But ranking is the WRONG test for graphify.** Per its own `SKILL.md`, graphify is a **GraphRAG
   question-answering / navigation tool** (`query` / `path` / `explain`, community detection, multi-modal:
   code+docs+papers+images+video) — NOT a file-importance ranker. Its edges are *semantic by design* (a superset
   of imports). So both "graphify 0/10 ranking" and "edge precision vs imports" tested it on tasks it does not
   perform — **both retracted.**
3. **Fair eval — ran real `graphify query`:** **good at feature/concept navigation** — "how does coach booking
   work?" returned the right neighborhood (`coach-booking-reducer`, `coaches-list`, `coach-card`, `lessons/page`,
   `server-fetch`). **Weak at precise code-dependency** — "what calls supabase-server?" / "what does api-types
   define?" keyword-matched and were fooled by token collisions (`types` in tsconfig, `supabase` in package.json),
   blending in doc nodes as noise.

**Conclusion: graphify and LSP are COMPLEMENTARY, not competitors.**
- **graphify** → "how does feature X work / cross-cutting concepts / what's the neighborhood" (semantic, multi-modal).
- **LSP** → "what calls Y / where is Z / blast radius" (precise, deterministic, fresh).

This *strengthens* the "two eyes / index code-not-docs" framing: graphify's doc-blending is exactly why its
precise-code answers got noisy — and exactly why the layers stay separate.

## Cross-cutting lessons (the reasoning, distilled)

- **Importance = how many DEPEND on you, not how much you DEFINE.** Both reposcan (type-edges) and graphify
  (symbol-count) fell for definition-richness. Import in-degree is the honest importance signal.
- **A persistent graph is a CACHE → it brings staleness** (graphify was 57 files behind). On-demand tools (LSP,
  a fresh import scan) are never stale. Prefer the cache only when re-scan is genuinely too expensive.
- **Ask "does this even need a graph?" first.** Most code-structure questions are answered by grep + LSP +
  on-demand import scan; decisions by prose curation. A graph's *only* unique value is community/surprising-
  connections (graphify) — a bonus, not a requirement.
- **Validate against an independent ground truth before trusting any graph.** "Looks right" is confirmation bias
  (api-types fooled us). The harness is non-negotiable.
- **Benchmark a tool against its ACTUAL use, not an assumed one.** graphify got scored with ranking metrics
  twice before its docs were read. Check the real consumer/use model first.
- **Fixes have side effects — re-validate every time.** The type-only-edge fix solved test-file noise and
  silently created value-hub blindness. Every fix must re-run the gate.

## Doc-map probe (the architecture/documentation layer)

`docscan.py` — the markdown counterpart: extracts H1/headings (doc skeleton), doc→doc links, and
doc→code references, building a doc-hub ranking + a doc→code join (mirrors read-bridge). Run on
sports-management (90 md, 4 ADRs, 58-file `agent-docs/`):

| Metric | Value |
|---|---|
| Docs / headings | 90 / 2,639 |
| Scan time | **0.02 s** (no parser — far cheaper than code) |
| Full md → TOC skeleton | 231k → 16k tokens = **14.4×** |
| doc→code edges / distinct files | 563 / 327 |

- **Works for RETRIEVAL:** top doc-hubs are exactly the ADRs (`0001-multi-tenant-rls`,
  `0002-stripe-platform-account`, `0003-tournament-algorithms`) + security-audit + GUIDELINES — the real
  "why" docs surfaced correctly.
- **Doc skeletons compress ~14×, not ~1000×.** Prose isn't structure; headings are a large fraction. Docs are
  fundamentally less compressible than code — index them for *findability*, not token savings.
- **Same collision challenge, worse:** doc→code join is precise for distinctly-named files
  (`auth-helpers.ts`, `supabase-server.ts`, a migration `.sql`) but useless for convention names
  (`route.ts` "in 24 docs", `page.tsx`) — hundreds of those exist. Plus a false positive (`Next.js` matched the
  `.js` code-ref regex). **Verdict: doc-map is good for "which doc covers this area," NOT for precise code linkage.**

Cross-repo doc-map (scan times all <0.1 s; compression a flat ~13–26× regardless of repo — docs don't compress like code):

| Repo | Docs (human) | Top doc-hubs | doc→code agrees with code-graph? |
|---|---|---|---|
| sports-management | 90 | ADRs (RLS, Stripe, tournaments) + security-audit | partial (convention-name noise) |
| HUB | 150 | infra/deploy/config docs (`environments`, `aws-setup`, `secrets-management`) | yes — `app.module.ts`, `*-orchestrator.provider.ts` |
| BetterBlocks | **~30 human** (was 210) | design docs (`DESIGN_SYSTEM`, `UX_AUDIT`, `STRATEGY`) | **yes — `GameConfig`/`Theme`/`HudView` = same hubs the call-graph ranked top** |

**Live confirmation of the decision rule (BetterBlocks):** the first run swept in `.supervisor/jobs/`,
`requirements/`, and `worker-summaries/` — **the plugin's OWN generated artifacts were ~80% of the "doc"
token mass**. Including them *inflated* the join (`GameConfig` "31 docs" → really 6) and *polluted* retrieval
(a `Shop` probe returned only generated job-briefs, zero human docs). Excluding `.supervisor/`/`graphify-out/`
restored a clean human-doc picture. This is the decision rule proven empirically: **indexing your own
generated artifacts as docs swamps the real signal and distorts every join — don't do it.**

Independent cross-validation bonus: where docs *are* human-authored, the most-doc-referenced code files match
the call-graph's top-ranked hubs (`GameConfig`/`Theme`/`HudView`; `app.module.ts`/provider files) — two
independent methods agreeing the same files are central.

### Decision rule — what to index vs. what NOT to (incl. the plugin's own generated docs)

The plugin generates a lot of artifacts. Most must **NOT** be doc/graph-indexed:

| Artifact class | Examples | Index it? |
|---|---|---|
| Structured + has a typed reader | `.supervisor/logs/*.jsonl`, postmortem `results.jsonl`, `bridge.json`, churn ledger, `*_RESULT` blocks, `LESSONS.md` | **NO** — use the existing reader (read-bridge / read-postmortem / measure-heal-signal). Re-indexing typed JSONL as fuzzy doc-text is a **lossy regression**. |
| Generated projection of indexed data | `/insights` dashboard, `/obsidian` vault, `/dreaming` output | **NO** — projection of already-indexed data; double redundancy. |
| Already in context every session | `CLAUDE.md` | **NO** — already loaded. |
| Human prose, long-tail, retrieved by "which doc covers X" | `docs/*.md`, ADRs, `AGENT_GUIDELINES.md`, architecture docs | **MAYBE** — a doc-map helps *findability* only; advisory, provenance-stamped, never trusted. |

**Principle:** index for RETRIEVAL when the corpus is too big to hold *and* you don't know which item you need.
Do NOT index what already has a typed query or is already in context. Architecture/decision docs (ADRs) are the
one genuine doc-index candidate — and they go stale faster than code, so the doc layer must be **even more**
strictly advisory than the code layer.

**Important clarification (do not misread "don't index" as "discard"):** "don't index the `.supervisor/`
generated artifacts" is scoped to the *centrality/doc-retrieval* lens only. Those artifacts (job briefs with
rationale, worker-summaries with findings, `state.md`, `memory/`) are the **highest-value continuity asset in
the repo** — the *why*, the *findings*, the *handoff state* so a second person doesn't diverge. They are not
removed; they already have *purpose-built continuity consumers* (`/supervisor --continue`, brief lifecycle,
`/dreaming`, `/obsidian`, agent memory). The reason not to build a *new fuzzy index* over them is that they are
already served better by those typed/continuity readers — NOT that they lack value. See `NORTH_STAR_DIRECTION.md`
Bet 2 (handoff digest). Caveat: decisions go stale too — capture the *basis* ("decided X because Y"), so the next
person can check whether Y still holds before trusting X (the v13→v14 stale-branch trap).

## Invariants to preserve

Advisory / non-gating / fail-safe throughout. A wrong or stale edge must never change a review `decision`,
a `heal_decision`, or a GO/NO-GO gate — it only biases *where* attention goes. Mirrors the existing bridge.
