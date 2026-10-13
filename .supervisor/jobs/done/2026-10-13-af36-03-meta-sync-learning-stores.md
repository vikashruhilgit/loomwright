# Supervisor Job: meta-sync carries the learning stores (twin pair rule, per-file merge, consent before first publish)

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean (one unrelated untracked file `AI-Radar-All.md` — never stage it), branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (source requirement lives on the metadata branch in branch mode, not on `main` — expected)
- **Source requirement:** .supervisor/requirements/af36-remainder/03-meta-sync-learning-stores.md
- **Base commit:** 508aabc434bbd8d7c9ac6a6513e9321e023cd9a2

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2 + awk + git plumbing + jq, exactly as `meta-sync.sh` / `setup-memory.sh` today |
| 2 | Dependency Availability | GO | no new dependency; sha256 via the same tool `read-system-contract.sh` already uses |
| 3 | Architecture Fit | CAUTION | the managed set is TWO closed lists in `meta-sync.sh` (`is_managed` AND `list_local`'s root loop + `symlink_hazard`'s root list), and the union rule is keyed on ONE path variable (`-v ledger="$LEDGER_PATH"`) — a second union kind needs a predicate, not a second variable |
| 4 | Scope vs Supervisor Capability | GO | 12 modified + 1 created file (+ the release bump), one coherent change — below the Decomposition Threshold |
| 5 | Hard Blockers | CAUTION | owner decisions were needed and were taken 2026-10-13 (see Task) — the requirement's literal text is amended by them in four places |

**Overall Verdict:** CAUTION

## Task
**Goal:** Extend `loomwright/scripts/meta-sync.sh`'s managed set with the learning stores (twin contracts + `.provenance.jsonl`, agent-memory proposals, eval history; dismissed-decisions already managed), with a twin pair rule, per-file merge semantics, a scrub test leg per new file type, and a user-scoped consent record that gates the FIRST publish of those stores — without changing how run history syncs for any existing caller.

**Problem Statement:**
After M1, run history travels on `loomwright-meta` and the memory stores travel on `main`, but several stores the agents read back to decide better travel nowhere: a second machine, a fresh clone or a lost disk starts without them. On-disk inventory at the base commit: 41 twin contracts + 73 chain-intact provenance lines, 2 agent-memory proposals, 2 eval JSONL files, 21 dismissed-decision ledgers; 0 scrub hits across them. `loomwright-meta` can be a PUBLIC branch, so the first publish of these stores must be consented.

**Owner decisions (2026-10-13, Launch Pad clarification — binding; they amend the requirement's literal text):**
- **D1 Consent record = user-scoped, keyed by repo.** Consistent with CLAUDE.md's telemetry invariant ("a repo-relative file can at most request, never grant"). The ask lives in `/setup memory` (command layer); `meta-sync.sh` only READS the record; it never asks.
- **D2 Push path = whole-set push only; `status` splits.** The new stores travel on a whole-set `meta-sync.sh push` (no `--paths-from`) — `trail-pr` and lanes keep pushing exact lists and are NOT changed. `meta-sync.sh status`'s existing first line (incl. `local_ahead` — what `lane-remove` checks) counts RUN-HISTORY paths only, so lanes behave exactly as today; the learning stores' state is reported separately, opt-in. Wiring `trail-pr`/lanes to carry them is a follow-up (non-goal here).
- **D3 Twin refusal is scoped to the twin set.** A `.provenance.jsonl` fork (both sides appended since the meta-base) or a pair-rule break refuses the WHOLE TWIN SET (every contract + the provenance file: nothing of it written or deleted on the side being written, every offending path named) while run history and the other stores still sync — so `meta-entry` and lane pulls keep working. "As a whole" in B1/B2 reads as "the twin set as a whole".
- **D4 Worker summaries are DEFERRED.** `.supervisor/worker-summaries/*.md` are named `{subtask_id}.md` (`1.md`, `2.md`, `S1.md`, `ST-1.md` … verified on disk), rewritten per run, so two machines would conflict routinely. They are NOT added to the managed set here; a follow-up first gives them unique names (writer change in `agents/worker.md`).

## Acceptance Criteria
- [ ] **AC1 (Scope 1 + D4)** Given the managed set, then it additionally holds `.supervisor/twin/contracts/*.md` (top level only), `.supervisor/twin/.provenance.jsonl`, `.supervisor/agent-memory-proposals/*.md` (top level only), `.supervisor/eval/results.jsonl` and `.supervisor/eval/brain-baseline.jsonl`; `.supervisor/automate/?*.dismissed-decisions` stays managed; `.supervisor/worker-summaries/` is NOT managed. The same exclusions hold for every new path (nested directories under the new roots, non-canonical paths, symlinks fail closed, newline-in-name refused), and `list-managed` lists the new paths. Both closed lists move together: `is_managed` and the local enumeration roots (`list_local`'s root loop, `symlink_hazard`'s root list).
- [ ] **AC2 (B1, Scope 2, D3)** Given a contract whose chain-valid `add` provenance entry is missing on either side (the branch or local), when `push` or `pull` would leave that side's post-state with a contract lacking it, then the twin set is refused as a whole on that side — no twin path written or deleted, every offending contract named on stderr (`meta_sync: twin_refused <path>: <reason>`) — while the run-history plan still applies and the command exits as it would without the twin set. Pair validity uses the SAME chain rules `read-system-contract.sh` applies (`GENESIS` first `prev_hash`; each later `prev_hash` = sha256 of the previous raw line; a contract is valid only when its sha256 is the `content_hash` of a chain-valid `add`). The leg goes red when the pair check is removed (mutant).
- [ ] **AC3 (B2, Scope 3, D3)** Given both sides appended to `.provenance.jsonl` since the meta-base, when `push` or `pull` runs, then the provenance file is a conflict — reported (`meta_sync: twin_refused .supervisor/twin/.provenance.jsonl: conflict` or the existing `conflict` wording, named), NO line-union, nothing of the twin set written — and run history still syncs. The leg goes red when provenance is routed to a union (mutant).
- [ ] **AC3b (D3 — meta-base after a twin-set refusal)** Given a pull or push that refused the twin set, then the meta-base it records must NOT make any refused twin path look agreed: for every twin path it keeps the previous base entry (absent when it had none), while every other path is recorded as today — so `cmd_pull`'s wholesale `write_base_file "$RT"` and push's `write_base_file "$nb"` become per-path for the twin set. A follow-up whole-set push (or pull) on the same divergence re-refuses the twin set; it never deletes the other side's contracts nor overwrites its provenance chain. Pinned by a two-step leg (refused pull, then whole-set push ⇒ the branch's twin set is byte-unchanged and the push prints `twin_refused` again) and a mutant that records the remote tree for twin paths. The header's rationale `any conflict anywhere aborts, because the meta-base written afterwards must cover every managed path` is rewritten to state the twin-set exception and this per-path base rule.
- [ ] **AC4 (Scope 3 — merge semantics per file, stated in the header and tested)** `.supervisor/eval/results.jsonl` and `.supervisor/eval/brain-baseline.jsonl` line-union exactly like `.supervisor/postmortem/results.jsonl` (the union selection becomes a predicate over the union paths, not a single-path variable; the `.repo` ledger scrub rule stays scoped to the postmortem ledger only). `*.dismissed-decisions` line-unions with an ORDERED merge: every distinct line kept; `summary-member<TAB><h8><TAB><slot>` rows are a set (position-independent — the reader in `automate-dismissed.sh` collects them into `members.setdefault(...)`); decision rows `<draft><TAB><decision><TAB><ts>` are ordered by their ISO-8601 `ts` (stable; ties keep branch-side rows first) so the reader's last-row-wins (`ledger[parts[0]] = parts[1]`) yields the time-latest decision per draft — tested with an OLDER local decision and a NEWER branch decision for the same draft (the newer must win; a plain `union_into` would let the older local row win — the leg must go red on that mutant). Each `.md` store keeps today's per-file 3-way rule. The header's 3-WAY RULE / PULL text states all of this.
- [ ] **AC5 (B4, Scope 4)** Given an injected home path, and separately an injected token, in a new-type `.jsonl` file (`eval/results.jsonl`) and in a `.dismissed-decisions` file, and a home path in a twin contract `.md`, when `push` runs (with consent recorded), then the scrub refuses (exit 2) and nothing is pushed — one test leg per new file type, each proven red with the injected hit (the clean control passes).
- [ ] **AC6 (B5, Scope 5, D1)** Given no recorded consent for this repo, when a whole-set `push` would add any learning-store path, then those paths are skipped and named (`meta_sync: learning_skipped <path> — no consent (run /setup memory)` or one summary line naming them), run history still pushes, and the exit code is the one run history alone would give. Given a recorded `declined`, the same. Given a recorded `granted`, they push. The consent record is user-scoped (under `$HOME/.claude/loomwright/`, one JSON file, keyed by the repo's origin `owner/repo` slug — the existing `remote_slug` helper — falling back to the literal origin URL when no slug parses), written ONLY by a new `setup-memory.sh` subcommand (grant | decline | status), never by `meta-sync.sh`; `/setup memory` asks once (Accept / Decline) after the existing apply, naming the stores and saying they hold internal reasoning the scrub only pattern-checks; it cannot ask ⇒ records nothing (fail toward not publishing). Tests set `HOME` to a scratch dir.
- [ ] **AC7 (D2)** Given a checkout whose only unpushed managed changes are learning-store paths, when `meta-sync.sh status` runs (with or without `--paths`), then its first line is what it would be without those stores — learning-store paths are excluded from the CONFLICT, TAKE_L/UNION and TAKE_R counts alike (a twin-only provenance fork does not print `conflict <n>`, a learning-only remote change does not print `remote_ahead`), so `automate-lanes.sh` lane-remove and every existing caller are unchanged; the learning stores' state is available through an explicit opt-in (e.g. `status --learning`, one line). Pull still takes learning-store paths from the branch (consent governs publishing only).
- [ ] **AC8 (B3)** Given a round trip — a source clone with twin contracts + provenance, proposals, eval files and a dismissed-decisions ledger pushes (consent granted) to a throwaway meta branch in a hermetic bare origin, then a fresh clone pulls — then `read-system-contract.sh` in the fresh clone verifies the same contracts as in the source (`twin_store_status: healthy`, same emitted count) and proposals, dismissed ledgers and eval files are byte-identical.
- [ ] **AC9 (Scope 6 + house rule on restated lists)** Every surface that states the managed set or the ".md + results.jsonl only" rule is updated in the same change: the `meta-sync.sh` header (MANAGED SET, local-enumeration paragraph, 3-WAY RULE, PULL, STATUS) and the inline comment `(meta-base must cover every path)`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md` §"Metadata branch" (managed-set list; enumeration sentence; 3-way table rows incl. the union row and the twin-path exception to the `both changed, any other path` row; the no-meta-base paragraph's `any conflict anywhere aborts, because the \`meta-base\` written afterwards must cover every managed path` rationale; the 'What `meta-base` records' paragraph — per-path for a refused twin set; the 'Exit codes.' paragraph — the status vocabulary gains the opt-in learning line, and ONE sentence says `twin_refused` / `learning_skipped` are stderr-only and leave the exit code unchanged (they do NOT join the exit-1 token list); the 'Stated limits' bullet `The script never picks a side for a non-ledger path` — rewritten for the eval unions and the ordered dismissed-decisions merge), `loomwright/docs/CORE_CONTRACT.md` (NO new §1.1 row — the new stores have none by design and the `is_managed` pointer covers membership; add ONE sentence after the §1.1 table: in branch mode twin contracts + `.provenance.jsonl`, `agent-memory-proposals/*.md` and the two eval JSONL files are meta-branch, published only with the user-scope consent), `loomwright/skills/automate-loop/branch-mode.md` §13 (what travels; that `trail-pr` does NOT carry the learning stores), `setup-memory.sh`'s branch-mode consent disclosure (`print_consent_disclosure_branch_mode`) and its WRITE-CONTAINMENT INVARIANT (the one new user-scope file), `loomwright/commands/setup.md` + `loomwright/skills/setup/SKILL.md` (the new consent question and the record), and the `test-meta-sync.sh` header's coverage notes. The branch-only M1 operator-run file is NOT edited (non-goal); the `changelog.d/af36-03-meta-sync-learning-stores.md` fragment names it as an owner follow-up.
- [ ] **AC9b (Scope 6 — the checks that restate the managed set or the ".md + results.jsonl only" rule)** `meta-sync.sh list-managed` gains a run-history-only selector (e.g. `--run-history`) so callers can tell the two classes apart without a second list. `loomwright/scripts/meta-sync-rehearsal.sh`: `verify-present` and `pull-roundtrip` compare RUN-HISTORY paths (consent may legitimately skip the learning stores); `verify-nothing-extra` still compares the full managed list; `verify-types` accepts exactly the managed file kinds (the `.md`, the two `results.jsonl`, `brain-baseline.jsonl`, `.provenance.jsonl`, `*.dismissed-decisions` — fixing the pre-existing gap for an already-managed dismissed ledger). `loomwright/scripts/migrate-branch-mode.sh`: `ab_check`'s A/B comparison is over run-history paths (A is `list-managed --tracked`; learning stores are untracked in branch mode), and its `nonmd` branch-type check accepts the same managed kinds; its header line `nothing but *.md / results.jsonl on the branch` is updated. `test-meta-sync-rehearsal.sh` gains two legs on a fixture holding a provenanced twin store — no consent (every check PASSes, learning stores absent from the branch) and consent granted under the scratch `HOME` (every check PASSes, learning stores on the branch and round-tripped); `test-migrate-branch-mode.sh` stays green with no assertion weakened.
- [ ] **AC10 (Validation 1–2, release)** Targeted suites green with `<passed>/<total>` reported per suite: `test-meta-sync.sh`, `test-setup-memory.sh`, `test-migrate-branch-mode.sh`, `test-meta-sync-rehearsal.sh`, `test-automate-dismissed.sh`, `scripts/check-doc-currency.sh`, `loomwright/scripts/test-citation-drift.sh` (+ `check-token-budget.sh` and the vendor ratchet AFTER `git add`); every EXISTING `test-meta-sync.sh` assertion passes with no assertion edited (header prose may change); a `changelog.d/af36-03-meta-sync-learning-stores.md` fragment is added and — this is a SEQUENTIAL run, so this PR releases — `bash scripts/bump-version.sh` is run so that `bash scripts/check-version-bump.sh` passes. Do NOT run the full `scripts/ci-local.sh` (owner rule 2026-10-12: GitHub CI runs the suite).

## House Rules

> Advisory house rules — subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)
- A count or version claim lives in exactly ONE authoritative machine-readable place (plugin.json, hooks.json, or the agents/commands/skills directories themselves). Every other surface either derives it at read time or omits the number entirely — prose says 'see hooks.json', never restating a literal count (a literal here would itself become a live claim needing maintenance, which is the trap this rule names). A sync-checking CI gate is the LAST resort, kept only where a consumer genuinely needs a second static copy.
  - id: process-a-count-or-version-claim-lives-in-exactly-one-authoritative-machine-readable-place-plugin-json-hooks-json-or-the-agents-commands-skills-directories-themselves-every-other-surface-either-derives-it-at-read-time-or-omits-the-number-entirely-prose-says-see-hooks-json-never-restating-a-literal-count-a-literal-here-would-itself-become-a-live-claim-needing-maintenance-which-is-the-trap-this-rule-names-a-sync-checking-ci-gate-is-the-last-resort-kept-only-where-a-consumer-genuinely-needs-a-second-static-copy
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)
- When one surface restates a list, table or enumeration owned by another, the restating copy is updated in the SAME change as its authority, or it is replaced by a pointer to that authority — a second copy that drifts silently is the defect, not the drift.
  - id: process-when-one-surface-restates-a-list-table-or-enumeration-owned-by-another-the-restating-copy-is-updated-in-the-same-change-as-its-authority-or-it-is-replaced-by-a-pointer-to-that-authority-a-second-copy-that-drifts-silently-is-the-defect-not-the-drift
  - enforcement: advisory
  - category: process
  - check (data only, NOT executed by this reader): (none)

## Executable Acceptance
- corpus-task: doc-currency-green
- corpus-task: version-consistent

## File Impact Map

| Group | Files to Modify | Files to Create | Confidence |
|-------|----------------|-----------------|------------|
| engine | `loomwright/scripts/meta-sync.sh` (`is_managed`, `list_local` roots, `symlink_hazard` roots, `compute_plan` union selection, a new ordered union for dismissed-decisions, the twin-set pair/conflict gate, the consent read on push, `cmd_status` split + opt-in learning line, header) | — | HIGH |
| checks | `loomwright/scripts/meta-sync-rehearsal.sh` (verify-present / pull-roundtrip / verify-types scoping), `loomwright/scripts/test-meta-sync-rehearsal.sh` (two learning-store legs), `loomwright/scripts/migrate-branch-mode.sh` (`ab_check` A/B scope + `nonmd` kinds + header) | — | HIGH |
| consent | `loomwright/scripts/setup-memory.sh` (new consent subcommand writing the one user-scope file; WRITE-CONTAINMENT INVARIANT; `print_consent_disclosure_branch_mode`; usage) | — | HIGH |
| tests | `loomwright/scripts/test-meta-sync.sh` (new legs AC1–AC8 + mutants; existing assertions untouched), `loomwright/scripts/test-setup-memory.sh` (consent subcommand legs, containment) | — | HIGH |
| docs | `loomwright/commands/setup.md`, `loomwright/skills/setup/SKILL.md`, `loomwright/skills/automate-loop/branch-mode.md`, `loomwright/docs/ARCHITECTURE_CONTRACTS.md`, `loomwright/docs/CORE_CONTRACT.md` | `changelog.d/af36-03-meta-sync-learning-stores.md` | HIGH |
| release | `loomwright/.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `CHANGELOG.md`, `loomwright/capabilities.json` — written ONLY by `bash scripts/bump-version.sh`, never by hand | — | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` scans `loomwright/commands/` and `loomwright/skills/` (no count changes expected); `test-citation-drift.sh` fails a new bare `file:N` citation — write anchors descriptively. `loomwright/docs/CORE_CONTRACT.md` is outside the requirement's `## Touches` but restates the meta-branch rows (house rule: update with its authority).

## Touched-file invariants

> Grounded at base `508aabc434bbd8d7c9ac6a6513e9321e023cd9a2`. The worker re-checks every entry before hand-back.

- **`loomwright/scripts/meta-sync.sh`** — keep: the one declared list (`# MANAGED SET — the ONE declared list (is_managed below)`) and its header restating every member; the non-canonical-path arm (`/*|./*|../*|*/./*|*/../*|*//*|*/.|*/..|*/) return 1 ;;`) evaluated BEFORE any new glob, and a `*/*` exclusion arm per new root (a case `*` matches `/`, as the existing `.supervisor/jobs/done/*/*|.supervisor/jobs/failed/*/*|.supervisor/automate/*/*) return 1 ;;` arm shows); the enumeration is parents-first over a fixed root list (`for d in .supervisor .supervisor/requirements .supervisor/jobs .supervisor/jobs/done`) — a new root's parent (`.supervisor/twin` for `.supervisor/twin/contracts`) must be in the list before it; `symlink_hazard`'s root list (`.supervisor|.supervisor/requirements|.supervisor/jobs|`) names the new roots; every git read fails closed (`never treated as an empty tree, an absent file or an empty side of a union`); the exit table (`# EXIT: 0 ok / no_changes; 1 conflict,`) — scrub stays exit 2; `report_conflicts` still aborts with exit 1 for any NON-twin conflict; `status` prints exactly one first line (`# STATUS prints exactly one line and always exits 0`) — the learning line is opt-in, never appended to the default output; the scrub runs `scan_file` over every candidate regardless of extension (only the `.repo` rule is path-gated: `if [ "$p" = "$LEDGER_PATH" ]`) — keep that gate on the postmortem ledger. reuse: `union_into` for the eval files; the `compute_plan` awk outcomes `SAME TAKE_R TAKE_L UNION CONFLICT`. mirror: `automate-lanes.sh` lane-remove parses `status --branch <b> --root <dir> --paths` (`ms="$(bash "$META_SYNC" status --branch "$mb" --root "$LN_DIR" --paths 2>/dev/null)"`) — its first line must not change for learning-store-only differences; `automate-lanes.sh` and `migrate-branch-mode.sh` treat any non-zero `pull`/`push` exit as failure (`|| { _abort "meta-sync pull --branch $mb failed"; return 1; }`) — a twin-set refusal must therefore not change the exit code run history alone would give (D3). pinned by: `test-meta-sync.sh`, `test-meta-sync-rehearsal.sh`, `test-migrate-branch-mode.sh`, `test-automate-lanes.sh` (lane-remove legs).
- **`loomwright/scripts/meta-sync-rehearsal.sh`** — keep: it never touches the real remote (`test-meta-sync-rehearsal.sh`: `fixture refs, remotes and its origin are unchanged`); one PASS/FAIL line per named check (the test pins the count, `one PASS/FAIL line per check (18)` — adding a check changes that pin deliberately and must be stated); the copy step (`bash "$MS" list-managed --root "$ROOT" > "$S/src.list"`) plus the twin copy (`cp -R -p "$ROOT/.supervisor/twin"`). The rehearsal runs under the caller's real `HOME`, so consent there decides what its whole-set push carries.
- **`loomwright/scripts/migrate-branch-mode.sh`** — keep: `ab_check` fails closed on any A/B name or blob mismatch (`A != B — path lists differ`, `blob mismatch`); `tracked_managed() { bash "$MS" list-managed --tracked --root "$ROOT"; }` stays the A source; `seed_check=equal | subset` semantics unchanged for run history.
- **`loomwright/scripts/setup-memory.sh`** — keep: FAIL-SAFE CONTRACT (every branch exits 0 unless documented); the WRITE-CONTAINMENT INVARIANT (`It writes NOTHING under \`~/.claude/\``) is AMENDED to name exactly one exception — the user-scope consent file, written only by the new subcommand — and `check`, `allowlist`, `filter-ledger`, `valid-branch`, `mode` still write nothing; `remote_slug` never guesses an owner (`NEVER guesses an owner`); bash 3.2, no arrays; status/diagnostic lines to stderr where stdout is a machine list. reuse: `remote_slug` for the consent key. mirror: the consent shape `meta-sync.sh` reads must be exactly what the subcommand writes (one helper owns the path + key derivation, or both sides are pinned by one test). pinned by: `test-setup-memory.sh` groups `(h)` (disclosure printed BEFORE anything is written) and `(fn-1)` (branch-mode disclosure wording).
- **`loomwright/scripts/test-meta-sync.sh`** — keep: every existing assertion byte-identical (Validation 2); the helpers (`mkworld`, `clone`, `ms`, `put`/`get`, `br_tip`/`br_show`/`br_has`/`br_names`, `base_of`, `synced_pair`, `roundtrip_world`, `mkshim`, `build_mutant`); `assert_ignored_clean` (`br_names | grep -vE '\.md$|(^|/)results\.jsonl$'`) — new legs that put `.provenance.jsonl` / `.dismissed-decisions` / `brain-baseline.jsonl` on the branch must not run inside a fixture that later calls it, or must use their own world; every mutant is gated non-empty + differs-from-original + `bash -n` (lesson fa32a308); the branch name is `BR="loomwright-meta"` only inside the hermetic bare origin — never push the real branch.
- **`loomwright/scripts/test-setup-memory.sh`** — keep: `ok()`/`no()` counters, `mkfix`, `setup_fail` (exit 2 = fixture broken); every new leg sets `HOME` to a scratch dir and scrubs `LOOMWRIGHT_MEMORY_REPO_ALLOWLIST` with `env -u` as the file's legs already do.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-meta-sync.sh` — AC2 pair rule refuses the twin set | make the pair check return success unconditionally |
| `test-meta-sync.sh` — AC3 provenance fork is a conflict, no union | add `.supervisor/twin/.provenance.jsonl` to the union-path predicate |
| `test-meta-sync.sh` — AC4 dismissed-decisions newer decision wins | route `*.dismissed-decisions` through plain `union_into` instead of the ordered merge |
| `test-meta-sync.sh` — AC4 eval jsonl line-union | drop the eval paths from the union-path predicate (both-changed ⇒ CONFLICT) |
| `test-meta-sync.sh` — AC5 scrub leg per new type | skip `scan_file` for candidates outside the old `.md`/ledger set |
| `test-meta-sync.sh` — AC6 no consent ⇒ learning paths skipped | make the consent read return `granted` unconditionally |
| `test-meta-sync.sh` — AC7 status first line ignores learning-only changes | count learning-store paths in `cmd_status`'s TAKE_L/UNION total |
| `test-meta-sync.sh` — AC1 worker-summaries not managed | add `.supervisor/worker-summaries/*.md) return 0 ;;` to `is_managed` |
| `test-meta-sync.sh` — AC3b refused twin set keeps its previous meta-base entries | record the remote tree (`write_base_file "$RT"`) for twin paths after a refusal |
| `test-meta-sync-rehearsal.sh` — no-consent leg all PASS | make `verify-present` compare the full `list-managed` instead of the run-history list |
| `test-meta-sync-rehearsal.sh` — consent leg all PASS | drop `.provenance.jsonl` from `verify-types`' accepted kinds |
| `test-setup-memory.sh` — consent subcommand writes only the one user-scope file | write the record under the repo root instead of `$HOME/.claude/loomwright/` |

## Closed enumerations touched

> Sibling grep at base `508aabc434bbd8d7c9ac6a6513e9321e023cd9a2`: `grep -rnE 'dismissed-decisions|postmortem/results\.jsonl' loomwright/scripts/*.sh` (non-test) → `meta-sync.sh` (`is_managed`, `LEDGER_PATH`, header), `automate-lanes.sh` (`_lanes_meta_extras` exact push list, `_lanes_noclaim_files`), `automate-trail.sh` (`TRAIL_LEDGER` / trail candidates), `automate-dismissed.sh` (the writer).

- **managed-set member** (sibling: `.supervisor/postmortem/results.jsonl`) — must be named in: `meta-sync.sh` `is_managed` — extend; `meta-sync.sh` `list_local` root loop and `symlink_hazard` root list — extend; `meta-sync.sh` header MANAGED SET — extend; `ARCHITECTURE_CONTRACTS.md` §"Metadata branch" managed-set list — extend; `CORE_CONTRACT.md` meta-branch rows — extend; `branch-mode.md` §13 — extend. `automate-lanes.sh` `_lanes_meta_extras` / `_lanes_noclaim_files` and `automate-trail.sh` trail candidates — NO change (D2: they never carry the learning stores; follow-up).
- **union-merge path** (sibling: `LEDGER_PATH=".supervisor/postmortem/results.jsonl"` / `-v ledger=`) — `compute_plan`'s two `p == ledger` arms — replace with a predicate covering the postmortem ledger + the two eval files; the `.repo` scrub gate (`if [ "$p" = "$LEDGER_PATH" ]`) — no change (stays postmortem-only); `ARCHITECTURE_CONTRACTS.md` 3-way table row `both changed, path is .supervisor/postmortem/results.jsonl | line-union` — extend.
- **branch file-type filter ".md + results.jsonl only"** (sibling regex `\.md$|(^|/)results\.jsonl$`; `grep -rnF 'results\.jsonl$' loomwright/scripts/*.sh`) — `meta-sync-rehearsal.sh` `verify-types` awk — extend to the managed kinds; `migrate-branch-mode.sh` `nonmd` grep + its header line — extend; `test-meta-sync.sh` `assert_ignored_clean` — no change (its fixtures hold no learning stores; new legs use their own world).
- **`meta_sync:` refusal tokens** (siblings `newline_in_path`, `not_a_file`, `tree_guard`) — `twin_refused` and `learning_skipped` change no exit code, so they do NOT join the exit-1 token list in `docs/ARCHITECTURE_CONTRACTS.md` §"Metadata branch" 'Exit codes.' or the `meta-sync.sh` header's EXIT table; each of those two surfaces gains ONE sentence naming them as stderr-only.
- **question gate** — the `/setup memory` consent ask extends the existing `/setup` offer (Question-gate inventory row `/setup` offers: "MI only … writes nothing without an Accept"); confirm with `grep -rn AskUserQuestion loomwright/commands/setup.md loomwright/skills/setup/SKILL.md` that the new ask is covered by that row (or add it to the row's list) — no new catalog code.

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Learning stores on the metadata branch (pair rule, merges, scrub legs, consent) | all | 12 modify (+4 via bump-version.sh), 1 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: ".supervisor/twin/.provenance.jsonl"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: ".supervisor/agent-memory-proposals"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "brain-baseline.jsonl"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "twin_refused"}
  - {kind: "symbol", path: "loomwright/scripts/meta-sync.sh", name: "learning_skipped"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: ".claude/loomwright/"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "twin_refused"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "learning_skipped"}
  - {kind: "file", path: "changelog.d/af36-03-meta-sync-learning-stores.md"}
requires: []
lanes:
  - "loomwright/scripts/meta-sync.sh"
  - "loomwright/scripts/test-meta-sync.sh"
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/meta-sync-rehearsal.sh"
  - "loomwright/scripts/test-meta-sync-rehearsal.sh"
  - "loomwright/scripts/migrate-branch-mode.sh"
  - "loomwright/scripts/test-setup-memory.sh"
  - "loomwright/commands/setup.md"
  - "loomwright/skills/setup/SKILL.md"
  - "loomwright/skills/automate-loop/branch-mode.md"
  - "loomwright/docs/ARCHITECTURE_CONTRACTS.md"
  - "loomwright/docs/CORE_CONTRACT.md"
  - "changelog.d/af36-03-meta-sync-learning-stores.md"
  - "loomwright/.claude-plugin/plugin.json"
  - ".claude-plugin/marketplace.json"
  - "CHANGELOG.md"
  - "loomwright/capabilities.json"
external_requires: []
```

## Parallelism Analysis

single-agent (no fan-out)

### Batch Plan
- **Recommended workers:** 1

## Skill References

| Subtask | Skills |
|---------|--------|
| 1 | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Security: `loomwright-meta` can be PUBLIC; twin contracts / proposals hold internal reasoning the scrub only pattern-checks | HIGH | D1 consent, user-scoped, fail toward NOT publishing (absent / declined / unreadable record ⇒ skip + name); scrub leg per new type proven red (AC5); human merge only. |
| Feasibility (Phase 2.5): the managed set is two closed lists + a single-path union variable — editing one list alone silently does nothing locally (enumeration never finds the file) or unions the wrong path | HIGH | AC1 requires both lists; AC4 replaces the variable with a predicate; mutants per pin. |
| D3 continuing past a twin-set refusal breaks the reason `any conflict anywhere aborts` existed (the meta-base must cover every managed path): recording the remote tree would let the next push delete the other machine's contracts and overwrite its chain | HIGH | AC3b per-path meta-base for the twin set + two-step leg + mutant (Plan Review attempt 1). |
| Rehearsal / migration checks restate the managed set and the ".md + results.jsonl only" rule and verify against `list-managed`; consent-skipped learning stores would turn `verify-present` / `pull-roundtrip` / `ab_check` red | HIGH | AC9b scopes them to run history and widens the type filter; two rehearsal legs (no consent / consent). |
| A twin-set refusal that changes the exit code would break `meta-entry`, lane pulls and `migrate-branch-mode.sh` (all treat non-zero as failure) | HIGH | D3: twin refusal is loud on stderr but leaves the exit code to run history; pinned by AC2/AC3 asserting run history synced AND the exit code. |
| `lane-remove` refuses forever on `local_ahead` if learning-store paths count there (lanes write twin entries; their exact push list never carries them — happened twice before for other files) | HIGH | D2/AC7: `status`'s first line counts run-history only; `test-automate-lanes.sh` must stay green. |
| Dismissed-decisions plain union lets an OLDER local decision override a newer branch one (reader is last-row-wins) | MEDIUM | AC4 ordered merge + red mutant. |
| Pull writes files with `FILE_MODE` (umask-derived); `.supervisor/twin/.provenance.jsonl` is mode 600 on disk | LOW | Decided: `write-system-contract.sh` sets no mode (no chmod/umask — Plan Review attempt 2), so 0600 is incidental; pull writes `.provenance.jsonl` with `FILE_MODE` like every managed file, and the `meta-sync.sh` header PULL text says so. |
| Consent key: hermetic tests use filesystem-path origins where `remote_slug` yields nothing | MEDIUM | AC6: key falls back to the literal origin URL; tests set `HOME` to a scratch dir and grant for that key. |
| The provenance remedy text: `reprovenance-twin-contracts.sh` is documented as "the SANCTIONED recovery path for System Twin contracts whose bodies were changed outside write-system-contract.sh" — not for chain forks | MEDIUM | The header's manual resolution: keep ONE side's chain (pull after discarding the local twin set, or push after re-pulling), then `reprovenance-twin-contracts.sh --confirm` only to re-bless contract bodies left without a chain entry — cite it only in that role. |
| Verified lesson 1b4bf009: the twin read path fails DARK (dropped contracts while the store looks populated) | MEDIUM | AC8 evidence is `read-system-contract.sh`'s `twin_store_status: … (emitted N, dropped 0 …)` on both sides, never a file count. |
| Verified lessons 34e7c865 / ef916b74: tests must be hermetic (no network, no gh) and scrub inherited env | LOW | Bare local origin only; `HOME` and `LOOMWRIGHT_MEMORY_REPO_ALLOWLIST` scrubbed per leg. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Non-goals (follow-ups, drafted separately)
- `trail-pr` / lane carriage of the learning stores (D2).
- Worker summaries on the branch — first give them unique names (D4).
- Editing the branch-only M1 operator-run file (owner, via `meta-sync.sh push`).

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-13-af36-03-meta-sync-learning-stores.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-13T12:00:22Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/528
- **Branch:** feature/af36-03-meta-sync-learning-stores
- **Files changed:** 25
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 0
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** meta-sync manages the learning stores (twin contracts + provenance, agent-memory proposals, eval JSONL; dismissed-decisions already managed) with a twin pair rule / fork refusal and per-path meta-base, per-file merges (eval line-union, timestamp-ordered dismissed-decisions), a scrub leg per new type, user-scope consent before publishing, a run-history-only status first line, and rehearsal/migrate checks scoped accordingly. Phase 4.5: iter 1 FAIL (2 MEDIUM, fixed 683f0af), iter 2 FAIL (HIGH tracked_managed + MEDIUM rollback test; merged #529, re-folded to v17.0.0; fixed c8ac37c), iter 3 FAIL (HIGH tracked learning store had two owners) ⇒ ESCALATED and posted. OWNER OVERRIDE: decision (a) git owns a tracked learning store + one extra fix pass (153b47b, 8f14864; also the CI check-locale-prefix fix) + one re-review ⇒ PASS with 1 MEDIUM + 1 LOW; owner-approved tiny fix ce89ce3 (inherited GIT_INDEX_FILE fail-open + header wording), verified by suites, no further LLM review. Open issues at the end of the loop: 0 at the fix floor. Released as v17.0.0 (major, from #529's fragment).

## Not verified
- **Real loomwright-meta push/pull on this repo** — exercised only against a throwaway branch on a local bare origin (real-store round trip: 41/41 contracts healthy both sides, 0 bytes differing) (subtask 1)
- **/setup memory learning-store consent ask** — command-layer prose needing an interactive session; not executed (subtask 1)
- **Branch-only M1 operator-run file** — still states the old managed set; owner follow-up on the metadata branch (subtask 1)
- **list-managed --tracked GIT_INDEX_FILE fix** — fixed in ce89ce3 and probed directly, but no dedicated test leg (fix-ce89ce3)
