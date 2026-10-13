# Supervisor Job: The repo allowlist travels as a tracked request file; only same-repo entries are granted

## Environment
- **Project:** ~/Documents/work/AI/ai-agent-manager-lanes/automate-2026-10-12-181635/L2 (lane L2 clone of ai-agent-manager)
- **CLAUDE.md:** ✓ Found (fresh)
- **Git:** clean, branch: main
- **GitHub CLI:** ✓ Authenticated
- **Blockers:** 0 | **Warnings:** 1 (source requirement is a lane-local copy pulled from the metadata branch, not on `main` — expected in branch mode)
- **Source requirement:** .supervisor/requirements/af36-remainder/02-meta-allowlist-grant.md
- **Base commit:** 3e354b5adf831a4c1f49e3bad47edec6e624cc90

## Feasibility

| # | Check | Verdict | Detail |
|---|-------|---------|--------|
| 1 | Tech Stack Compatibility | GO | bash 3.2-safe shell + jq, as today; `gh` is used elsewhere in the plugin (automate helpers, review-heal) but NOT by `setup-memory.sh` / `meta-sync.sh` today |
| 2 | Dependency Availability | CAUTION | `gh api repos/<slug> --jq .id` follows GitHub's rename redirect, but it makes `gh` a NEW optional runtime dependency of the resolver — and so of `meta-sync.sh`'s push scrub, `apply`'s seeding/gate and `validate-entry.sh`'s cross-repo check; a missing or failing `gh` must fail closed (A3) |
| 3 | Architecture Fit | GO | adds one layer inside the ONE resolver (`load_allowlist`); every consumer (`meta-sync.sh` scrub, `validate-entry.sh`, `filter-ledger`, `check`, `apply` seeding) already delegates to it |
| 4 | Scope vs Supervisor Capability | GO | 7 modified + 2 created files, single coherent change — below the Decomposition Threshold |
| 5 | Hard Blockers | CAUTION | CI has no network and no `gh`: every new test stubs `gh` on PATH; the A1 fixture needs a GitHub-shaped origin that is still fetchable locally (see Risk Assessment) |

**Overall Verdict:** CAUTION

## Task
**Goal:** Add a tracked request file `.agent/meta-allowlist.txt` that `setup-memory.sh allowlist` reads as a new precedence layer (below `--allow` / env / `config.json`, above the current-remote default), granting an entry ONLY when `gh api repos/<slug> --jq .id` equals the id of `origin`'s slug; seed it with this repo's two slugs and correct the docs that say the allowlist "does not travel".

**Problem Statement:**
Branch mode needs a correct repo allowlist on every machine, because `meta-sync.sh push` scrubs every pushed file against it (ledger `.repo` and forge `owner/repo` slugs). Currently the allowlist lives only in the gitignored `.supervisor/config.json`, so a second machine or a scratch clone falls back to the live remote alone (precedence layer 4). 42 of 126 ledger records carry the pre-rename slug `vikashruhilgit/ai-agent-manager` and 51 files on `loomwright-meta` cite it in a forge context — the 2026-10-03 M1 rehearsal reported 218 scrub hits in a clone without `config.json`, so every trail push that adds a ledger line or edits an old-slug file is refused there. A plain committed allowlist would fix that but is a security hole: the ledger collects records about OTHER repos analysed from this checkout, so a clone owner who controls the committed list could list private repos and publish their records to a public metadata branch. Success looks like: a fresh clone with no `config.json` resolves both slugs (the old one because GitHub redirects it to the same repository id), while any slug that resolves to a different repository — or any entry at all when `gh` cannot answer — is never granted and is named in a status line.

## Acceptance Criteria
- [ ] **A1** Given a fresh clone with no `.supervisor/config.json` and the seeded request file, when `meta-sync.sh pull` then a `push` that adds a ledger line and edits a file citing the old slug runs, then the push succeeds, because the old slug resolves to this repo's id.
- [ ] **A2** Given a request file listing a slug that resolves to a DIFFERENT repository, when the allowlist is resolved, then that slug is not granted, it is named in the status line (`allowlist: ignored <slug> — not this repository`), and a ledger record under it is refused by the scrub. The test fails when the id comparison is removed (mutant).
- [ ] **A3** Given `gh` is unavailable (absent, or failing), when the allowlist is resolved, then tracked-file entries are not granted, `config.json` entries still are, and the status line says why.
- [ ] **A4** Given the tracked file's layer, when `setup-memory.sh allowlist` runs, then the precedence is `--allow` → `$LOOMWRIGHT_MEMORY_REPO_ALLOWLIST` → `config.json` array → tracked request file (granted entries) + current-remote default — first non-empty layer wins exactly as today for layers 1–3, so a present `config.json` (or `--allow`, or the env var) means the request file is not read and no `gh` call is made.
- [ ] **A5** Given the current remote's own slug, it is always granted with no `gh` call (also when it is listed in the request file, compared case-insensitively); a request-file entry that is not `owner/repo`-shaped (`[A-Za-z0-9._-]+/[A-Za-z0-9._-]+`) is never passed to `gh` and is named as ignored; `#` comments and blank lines are skipped; an origin with no parseable `owner/repo` (filesystem-path remote) grants no request-file entry and makes no `gh` call.
- [ ] **A6** Given every status line (granted / ignored / why), it goes to STDERR, never stdout — `setup-memory.sh allowlist` stdout stays one entry per line, because `meta-sync.sh`'s `load_allowlist` and `validate-entry.sh` read stdout as the list; the `# source:` stderr line names the request-file layer when it contributed.
- [ ] **A7** `.agent/meta-allowlist.txt` is created and seeded with `vikashruhilgit/loomwright` and `vikashruhilgit/ai-agent-manager` (plus a `#` comment header naming the request/grant rule); `/setup memory`'s disclosure and the allowlist docs in `loomwright/commands/setup.md` describe the request/grant split and the new optional `gh` dependency (missing `gh` ⇒ request entries not granted); the `skills/setup/SKILL.md` line saying the allowlist "does not travel" is corrected WITHOUT losing its lesson — `config.json` does not travel; the request file does but can only request; with no `gh` (CI) it grants nothing and layer 4 still yields the remote alone, so a committed-data gate still declares its expected values in committed code (`test-committed-twin-scrub.sh`'s `OWNED_SLUGS` stays); `validate-entry.sh`'s restated precedence — its comment AND its `ADVISORY_CROSS_REPO_ALLOWLIST_UNRESOLVED` message text — names the new layer; a `changelog.d/af36-02-meta-allowlist-grant.md` fragment is added (NO `bump-version.sh` — this is a `--parallel` lane; `wave-build` bumps).
- [ ] **A9** Given no request file, or one holding only the current remote's own slug, comments and blank lines, when the allowlist is resolved at layer 4, then ZERO `gh` calls are made (origin's id is looked up lazily, only when a non-own, well-formed entry needs comparing) — pinned with a `gh` stub that records every invocation; the existing GitHub-shaped fixtures (`newgit https://<forge>/<owner>/<repo>.git`) therefore stay hermetic.
- [ ] **A8** Tests stub `gh` on PATH (no network): a same-id slug (granted), a different-id slug (ignored + named + scrub-refused), a failing `gh` and an absent `gh` (A3); the A2 mutant (id comparison removed ⇒ grant every entry) turns the A2 leg red, gated on the mutant being non-empty, different from the original and `bash -n`-clean. Targeted suites green: `test-setup-memory.sh`, `test-meta-sync.sh`, `test-validate-entry.sh`, `scripts/check-doc-currency.sh`, `loomwright/scripts/test-citation-drift.sh`.

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
| resolver | `loomwright/scripts/setup-memory.sh` (`load_allowlist`, header precedence comment, usage, consent disclosure) | — | HIGH |
| tests | `loomwright/scripts/test-setup-memory.sh` (A2–A6 + mutant), `loomwright/scripts/test-meta-sync.sh` (A1) | — | HIGH |
| data | — | `.agent/meta-allowlist.txt` | HIGH |
| docs | `loomwright/scripts/test-committed-twin-scrub.sh` (one comment clause), `loomwright/commands/setup.md`, `loomwright/skills/setup/SKILL.md`, `loomwright/scripts/validate-entry.sh` (comment + `ADVISORY_CROSS_REPO_ALLOWLIST_UNRESOLVED` message text — its restated precedence list; code and exit behaviour unchanged) | `changelog.d/af36-02-meta-allowlist-grant.md` | HIGH |

> **Validator-owned surfaces:** `scripts/check-doc-currency.sh` scans `loomwright/commands/` and `loomwright/skills/`; no count or version claim changes, so no other doc surface should need an edit. `test-citation-drift.sh` fails a new bare `file:N` citation — write anchors descriptively.

> `loomwright/scripts/validate-entry.sh` is outside the requirement's declared `## Touches`. It is a comment + advisory-message-text edit (the restated precedence list; the pins in `test-validate-entry.sh` match only the code `ADVISORY_CROSS_REPO_ALLOWLIST_UNRESOLVED`), and no other item of this wave (af36-remainder/01, /04) touches it; af36-remainder/03 (next wave) does not list it either.

## Touched-file invariants

> Grounded at base `3e354b5adf831a4c1f49e3bad47edec6e624cc90`. Every worker re-checks the entries for the files in its lanes before hand-back.

- **`loomwright/scripts/setup-memory.sh`** — keep: the FAIL-SAFE CONTRACT (every branch still exits 0; `allowlist` writes nothing — `` `check`, `allowlist`, `` in the WRITE-CONTAINMENT INVARIANT); `load_allowlist` stays an in-shell function setting `$ALLOWLIST` / `$ALLOWLIST_SOURCE` (`It must run in the CURRENT shell`); the `# source:` line stays on stderr (`echo "# source: $ALLOWLIST_SOURCE" >&2`); `remote_slug` never guesses an owner (`Echoes nothing when it cannot decide — NEVER guesses an owner`); bash 3.2, no arrays (`bash-3.2-safe expansion of the newline-separated list`); the final trim/dedupe pass (`Trim, drop blanks, de-duplicate while preserving order`). reuse: `remote_slug` for origin's slug; the existing `$repo` root variable for the request-file path. mirror: `meta-sync.sh`'s `load_allowlist` reads stdout only (`awk 'NF && $0 !~ /^#/'`, lowercased) — any new status text must go to stderr or it becomes an allowlist entry; `validate-entry.sh` delegates (`ALLOWLIST RESOLUTION IS DELEGATED, NEVER RE-IMPLEMENTED`). pinned by: `test-setup-memory.sh` and `test-validate-entry.sh` (`bash "$SM" allowlist`).
- **`loomwright/scripts/test-setup-memory.sh`** — keep: `ok()` / `no()` counters and the `mkfix` fixture helper (optional remote argument: `git remote add origin "$remote"`); ledger assertions use jq only (header note); every new leg scrubs `LOOMWRIGHT_MEMORY_REPO_ALLOWLIST` with `env -u` (the file already does: `env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$MEM" --root "$d" allowlist`).
- **`loomwright/scripts/test-meta-sync.sh`** — keep: the file-level `export LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="owner/repo,owner/repo-old"` (other legs rely on it) — the A1 leg runs its children under `env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST`; reuse the `mkshim` helper / `PATH="$W/…:$PATH"` shim pattern for the `gh` (and, if needed, `git remote get-url`) stubs.
- **`loomwright/scripts/validate-entry.sh`** — keep: it never parses the allowlist itself (`test-validate-entry.sh` greps that it never expands `$LOOMWRIGHT_MEMORY_REPO_ALLOWLIST`); only the comment's restated precedence list (`` (`--allow` -> env -> .supervisor/config.json array -> git-remote default) ``), its "layer 2 of four" count, and the `ADVISORY_CROSS_REPO_ALLOWLIST_UNRESOLVED` message's list of layers change — the advisory code itself and its exit behaviour stay byte-identical.

- **`loomwright/scripts/test-committed-twin-scrub.sh`** — keep: the committed `OWNED_SLUGS` expectation and every assertion byte-identical (`THE EXPECTED SLUGS ARE DECLARED HERE, IN COMMITTED CODE`); only the census comment's first clause (`So the allowlist DOES NOT TRAVEL with the repo`) is reworded.

## Pin mutations

| Pin | Mutation (one line, applied to the code the pin protects) |
|-----|-------------------------------------------------------------|
| `test-setup-memory.sh` — A2 different-id slug not granted + named | replace the request-file id comparison in `setup-memory.sh` with an unconditional grant (e.g. flip the `[ "$id" = "$origin_id" ]` test to `true`) |
| `test-setup-memory.sh` — A3 failing/absent `gh` grants nothing | make the `gh`-failure branch fall through to granting the entry |
| `test-setup-memory.sh` — A6 status lines on stderr | drop the `>&2` from the `allowlist: ignored …` echo |
| `test-meta-sync.sh` — A1 push succeeds with old-slug ledger line | delete the request-file layer call from `load_allowlist` |
| `test-setup-memory.sh` — A4 config present ⇒ request file not read, no `gh` call | move the request-file layer above the `config.json` layer in `load_allowlist` |
| `test-setup-memory.sh` — A5 malformed entry never passed to `gh` | drop the `owner/repo` shape check before the `gh api` call |
| `test-setup-memory.sh` — A9 zero `gh` calls with no request file / own slug only | look up origin's id eagerly (unconditionally) at the top of the request-file layer |

## Closed enumerations touched

> Sibling grep at base `3e354b5adf831a4c1f49e3bad47edec6e624cc90`: `grep -rnF 'default (current git remote)' --exclude=CHANGELOG.md .` → hits in `loomwright/scripts/setup-memory.sh` and `loomwright/scripts/test-setup-memory.sh`.

- **new `$ALLOWLIST_SOURCE` label for the request-file layer** (sibling: `default (current git remote)`) — must be named in:
  - `loomwright/scripts/setup-memory.sh` — `load_allowlist`'s label assignments — extend (the combined label MUST keep the substring `default (current git remote)` when the remote default contributed).
  - `loomwright/scripts/test-setup-memory.sh` — leg (d1) `hasF 'default (current git remote)' "$src_d1"` — no change: substring match still holds by the rule above.
- **`meta-sync-rehearsal.sh --no-config` configuration pair** (sibling: `.agent/meta-sync-deny.txt`) — `loomwright/scripts/meta-sync-rehearsal.sh` removal loop `for p in .supervisor/config.json .agent/meta-sync-deny.txt; do` — no change: `.agent/meta-allowlist.txt` is a TRACKED request file that travels with every clone, so `--no-config` (which simulates a fresh clone) keeps it, exactly as a fresh clone would. `loomwright/commands/setup.md` Rehearsal sentence (`"configuration" there means`) — extend with one sentence: the request file is not "configuration" (it travels), and a rehearsal against a local bare origin cannot show its grant (A5: a filesystem-path origin grants nothing), so the old-slug hits a `--no-config` rehearsal reports are expected there and A1's test leg is the proof of the fix.
- **new precedence layer** (restated four-layer list) — `loomwright/scripts/validate-entry.sh` comment `` (`--allow` -> env -> .supervisor/config.json array -> git-remote default) `` and its `ADVISORY_CROSS_REPO_ALLOWLIST_UNRESOLVED` message — extend; `loomwright/commands/setup.md` allowlist paragraph — extend. `test-committed-twin-scrub.sh`'s "DOES NOT TRAVEL" census comment — extend its first clause to say the resolver reads gitignored `.supervisor/config.json` and, without `gh`, grants nothing from the tracked request file (one-line comment edit; no other wave-1 lane touches that file). Deliberate follow-ups (not edited here, named in the PR body): `harvest-conventions.sh` header/echo and `docs/HARVEST_DRYRUN_SAMPLE.md` ("reads gitignored machine-local config").

## Subtask Structure

| # | Title | Acceptance Criteria Subset | Est. Files (modify/create) | Skills | Status |
|---|-------|---------------------------|---------------------------|--------|--------|
| 1 | Tracked allowlist request file with same-repo grant | all | 7 modify, 2 create | `skills/unit-testing/SKILL.md`, `skills/error-handling/SKILL.md` | LAUNCHABLE |

### Subtask Contracts

```yaml
# Subtask 1
provides:
  - {kind: "file", path: ".agent/meta-allowlist.txt"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "meta-allowlist.txt"}
  - {kind: "symbol", path: "loomwright/scripts/setup-memory.sh", name: "not this repository"}
  - {kind: "symbol", path: "loomwright/scripts/test-setup-memory.sh", name: "meta-allowlist.txt"}
  - {kind: "symbol", path: "loomwright/scripts/test-meta-sync.sh", name: "meta-allowlist.txt"}
  - {kind: "file", path: "changelog.d/af36-02-meta-allowlist-grant.md"}
requires: []
lanes:
  - "loomwright/scripts/setup-memory.sh"
  - "loomwright/scripts/test-setup-memory.sh"
  - "loomwright/scripts/test-meta-sync.sh"
  - "loomwright/scripts/validate-entry.sh"
  - "loomwright/scripts/test-committed-twin-scrub.sh"
  - ".agent/meta-allowlist.txt"
  - "loomwright/commands/setup.md"
  - "loomwright/skills/setup/SKILL.md"
  - "changelog.d/af36-02-meta-allowlist-grant.md"
external_requires:
  - "gh CLI (`gh api repos/<owner>/<repo> --jq .id`) — stubbed on PATH in every test; live only in the running-system check"
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
| Security: a committed list that GRANTS would let a clone owner publish other repos' ledger records to a public metadata branch | HIGH | Grant only on an id match against `origin`; never grant on `gh` failure (fail CLOSED); the A2 mutant proves the comparison is load-bearing. Security-sensitive — human merge only. |
| Status lines leaking into stdout become allowlist entries for `meta-sync.sh` (it filters only blank and `#` lines) and `validate-entry.sh` | HIGH | Every status line to stderr (A6, pinned with a mutant). |
| A1 fixture: `git remote get-url` expands `url.<x>.insteadOf` (probed 2026-10-12: a `https://<forge>/<owner>/<repo>.git` origin rewritten to a local bare repo reports the LOCAL path), so `remote_slug` returns nothing and no grant can happen | MEDIUM | Do not change `remote_slug`. In the A1 leg, shim `git` (or only `git remote get-url origin`) on PATH for the `setup-memory.sh` child, or otherwise give the clone a GitHub-shaped origin while fetching from the local bare repo; prove the leg turns red when the request-file layer is removed. |
| Hermeticity: CI has no network and no `gh`; a developer machine has an authenticated `gh`. Existing `test-setup-memory.sh` fixtures use GitHub-shaped origins (`newgit https://<forge>/<owner>/<repo>.git`, an scp-style `<user>@<forge>:` leg), so an eager origin-id lookup would make a live call in every layer-4 leg | MEDIUM | Lazy lookup + A9's zero-call pin; every new leg stubs `gh` on PATH (lesson 34e7c865). Named exposure: `test-committed-twin-scrub.sh`'s advisory cross-check runs `allowlist` against the REAL repo (which will hold the seeded file), so on a dev machine with no `config.json` it may call `gh` live — and in CI too (`ubuntu-latest` ships `gh`; unauthenticated it fails, so it grants nothing — fail closed) — advisory output only, never a gate; `test-meta-sync-rehearsal.sh` exports its own allowlist and is unaffected. |
| New runtime dependency: `gh` now sits on the resolver path used by `meta-sync.sh`'s fail-CLOSED scrub, `apply` seeding/gate and `validate-entry.sh` | MEDIUM | Only reached when layers 1–3 are empty AND the request file holds a non-own entry; missing/failing `gh` ⇒ that entry not granted + stderr reason (A3) — identical to today's result; documented in `/setup memory`. |
| `apply`'s `seed_allowlist` on a machine with no `config.json` now seeds granted request-file entries into config too | LOW | Intended (the snapshot then carries both slugs); mention it in the `/setup memory` docs; no test change needed beyond the existing seeding legs staying green. |
| Each `allowlist` call without `config.json` costs 1 + N `gh` API calls (meta-sync calls it per push/scrub) | LOW | Skip `gh` for the remote's own slug; resolve `origin`'s id lazily and at most once per call (A9); N is 2 here. |

## Configuration
- **Workers:** 1
- **Mode:** single-agent
- **Estimated batches:** 1

## Handoff
```
/supervisor job: .supervisor/jobs/pending/2026-10-12-af36-02-meta-allowlist-grant.md
```

## Outcome
- **Status:** completed_with_escalation
- **Completed:** 2026-10-12T18:06:59Z
- **PR:** https://github.com/vikashruhilgit/loomwright/pull/501
- **Branch:** feature/af36-02-meta-allowlist-grant
- **Files changed:** 10
- **Heal loop ran:** true
- **Heal decision:** ESCALATED
- **Heal iterations:** 3
- **Heal reason:** max_iterations_reached
- **Heal remaining issues:** 1
- **Red team advisory:** disabled
- **Until-mergeable dispatched:** false
- **Summary:** Tracked .agent/meta-allowlist.txt request layer in setup-memory.sh allowlist; grant only on a github.com repo-id match with origin, bounded and capped gh calls, fail closed. 6 review findings fixed over 3 heal iterations; the iteration-3 fix (gh process-group bound) was not re-reviewed but was independently verified. Acceptance A1 not met for this repo: the old slug vikashruhilgit/ai-agent-manager is a separate repository (owner-accepted).

## Not verified
- **real-system A1 — fresh clone resolving both seeded slugs** — vikashruhilgit/ai-agent-manager is a separate repo (id 1286686688); only vikashruhilgit/loomwright is granted live; needs an owner decision (subtask 1)
- **gh latency or hang on the meta-sync.sh push path with a real gh** — bounded by gh_id_bounded (stubbed tests only; a setsid-escaping descendant is not bounded) (subtask 1)
