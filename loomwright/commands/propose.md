---
description: Turn the recorded churn ledger — or, with --domain, what competent apps in this project's domain do — into candidate work items; a propose-only pass that writes evidence-carrying requirement drafts to .supervisor/requirements/proposed/ for a human to promote or delete
---

> **Read-only on your work; writes only derived drafts.** `/propose` reads a basis the plugin already has (`.supervisor/floor/floor.json` by default, or the committed product store `.agent/product.json` with `--domain`) and writes candidate requirement files to `.supervisor/requirements/proposed/` (gitignored). It touches no code, no agent, no state, no existing surface. It **never queues, dispatches, ranks, scores, or merges** — `proposed/` is deliberately **not** an `/automate --folder` target. Bare `/propose` sends nothing anywhere and makes **zero** external calls; only `--domain` fetches, and only through the one named, overridable seam described below.

# Command: /propose

## Purpose

The learning loop **records and never proposes.** Findings accumulate automatically — postmortem records, classified categories, per-entry flow stages — but nothing converts a trend into a piece of work. Every item this system has ever executed was typed by a human: `/automate`'s three intake sources (a prompt via `/product-owner`, `--folder`, `--backlog`) are all human-seeded.

Measured on this repo when the proposer was written: **109 `convention_mismatch` entries had produced 3 rules.** The recording was never the gap.

`/propose` is the invocation seam for that missing half. It is the *intake* side of a mill that invents its own work — and it stops at intake by design. **It proposes; the human decides at dequeue.**

## The two bases

`/propose` has two bases, and **they never run in one invocation.**

| Basis | Flag | Reads | Looks | Evidence class |
|-------|------|-------|-------|----------------|
| **Ledger** (default) | *(none)* | `.supervisor/floor/floor.json` | **inward** — our own recorded mistakes | derived, from counted ledger entries |
| **Domain** | `--domain` | `.agent/product.json` via `read-product.sh`, plus fetched competitor sources | **outward** — what the domain expects that this app does not do | derived (the local inventory) **plus** external/judgment (the fetched half) |

**Why they are never mixed.** The default basis is local `jq` over a local file: it costs nothing, reaches nothing, and its output is derived from entries this system recorded itself. The domain basis spends **fetch budget** and emits **judgment-class** output built partly from competitor and vendor text. Someone running bare `/propose` must therefore never trigger a network call — so the outward basis is behind an explicit flag and is never implicit. The precedent is `/capability-check`, whose adoption and `--strategy` modes are likewise two never-mixed modes behind one command.

Both bases emit the same kind of artifact into the same folder under the same propose-only contract. The domain basis names its files **`domain--<slug>.md`**, so the two bases cannot collide on a filename in `proposed/` — and only the default basis authors `proposed/README.md` (a second author of that one file would collide on exactly the file the namespacing exists to protect).

## Usage

```bash
/propose                                    # ledger basis: read floor.json, write candidates to .supervisor/requirements/proposed/
/propose --domain                           # domain basis: what the domain expects that this project does not do
```

The command shells out to the tested implementations — **one basis per invocation**:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/propose-work.sh"      # default, no flag
bash "${CLAUDE_PLUGIN_ROOT}/scripts/propose-domain.sh"    # --domain
```

## Parameters

| Flag | Default | Description |
|------|---------|-------------|
| `--domain` | off | Run the **domain** basis *instead of* the ledger basis (never both, never implicit). Requires the committed product store `.agent/product.json`; with no store it prints the named "no product context" message plus the `propose-product.sh` bootstrap offer, writes nothing, fetches nothing, and exits 0. |

Each basis is tuned by environment variables, all optional.

### Ledger basis — read by `propose-work.sh`

| Variable | Default | Description |
|----------|---------|-------------|
| `PROPOSE_FLOOR_JSON` | `.supervisor/floor/floor.json` | The basis to read. The **only** ledger surface consulted — it is not a second parser. |
| `PROPOSE_OUT_DIR` | `.supervisor/requirements/proposed` | Where candidates are written. The only place any file is written. |
| `PROPOSE_REQUIREMENTS_DIR` | `.supervisor/requirements` | Root scanned for `## Status: done` files that supersede a candidate. |
| `PROPOSE_THRESHOLD` | `10` | Entries a `(class, flow_stage)` pair needs before it is emitted. A non-numeric value is ignored with a named reason. |
| `PROPOSE_MAX_AGE_SECONDS` | `86400` (24h) | Staleness limit on the basis. Older ⇒ propose nothing, name the age, exit 0. |
| `PROPOSE_SOURCE_DATE_EPOCH` | *(now)* | Pin the staleness "now" for reproducible runs. |

### Domain basis — read by `propose-domain.sh` (`--domain` only)

| Variable | Default | Description |
|----------|---------|-------------|
| `PROPOSE_DOMAIN_STORE` | `<repo root>/.agent/product.json` | The product store — domain, stance, audience, `competitors[]`. Read by shelling out to `read-product.sh`, never re-parsed here, so `stance_default_action` keeps exactly one home. Absent or unreadable ⇒ name it, offer the bootstrap, write nothing, exit 0. |
| `PROPOSE_DOMAIN_OUT_DIR` | `.supervisor/requirements/proposed` | Where candidates are written. The only place any file is written, through a single write-path guard. |
| `PROPOSE_DOMAIN_REQUIREMENTS_DIR` | `.supervisor/requirements` | Root scanned for `## Status: done` files that supersede a candidate. |
| `PROPOSE_DOMAIN_FETCH_CMD` | *(unset ⇒ no fetcher)* | **The only external transport in the run.** Invoked as `<cmd> <url>` with the source text read from its stdout; it must be one executable command with no arguments (wrap it in a script otherwise) and it owns its own timeout. Unset, empty, or not executable ⇒ **nothing is fetched at all**: there is no implicit `curl`, no `wget` and no shell default, ever. |
| `PROPOSE_DOMAIN_MAX_FETCHES` | `5` | Hard cap on external calls for the **whole run** (mirrors `/capability-check --max-fetches`). Local reads — the store, the code/doc inventory, `.agent/orientation/` — are not external calls and never draw on it. A non-numeric value is named and ignored. |
| `PROPOSE_DOMAIN_MAX_SOURCE_AGE_SECONDS` | `7776000` (90d) | A source whose store-recorded `last_fetched` is older than this is named **STALE** in the output rather than cited silently. A date that cannot be parsed degrades to *staleness unknown* — unknown is not old, and never-fetched is not stale. |
| `PROPOSE_DOMAIN_SURFACE_FILE_CAP` | `4000` | Per-surface file cap on the capability inventory. When a surface is truncated at this cap the run reports the cap as **REACHED** with its matched-vs-searched counts, and every unmatched capability is `unverified` rather than `missing` — the evidence may simply lie past the cap. Overridable so that behaviour is reachable in a test; a non-numeric or sub-1 value is named and ignored. |
| `PROPOSE_DOMAIN_SOURCE_DATE_EPOCH` | *(now)* | Pin the staleness "now" for reproducible runs. The wall clock is read exactly once and only for staleness; no run timestamp reaches an emitted byte. |

## What the ledger basis does

1. **Refuses to propose from a stale or unreadable basis.** A missing `jq`, a missing / unparseable `floor.json`, an unreadable clock, or a basis older than the staleness threshold each **skip with a named reason and exit 0**. Skipping is the correct behaviour for an advisory reader; proposing from a stale basis is the exact failure this system keeps writing rules about.
2. **Threshold, never ranking.** A candidate is emitted when a `(class, flow_stage)` pair crosses the stated count. There is **no score, no rank, no priority, no top-N, no ordering field** — a view that ranks becomes a view that decides, and deciding is the human's half of this loop.
3. **Cites its evidence or stays silent.** Every candidate carries a mandatory `## Evidence` section naming each ledger entry it rests on (`class`, `flow_stage`, `round`, source `line`, `self_heal_miss`) plus the `generated_at_epoch` it read. **A candidate that cannot cite at least 3 distinct entries is not written.** Absent evidence is omitted, never defaulted — a fabricated count inside a proposal is precisely what this reduces.
4. **Suppresses what is already covered**, reporting each suppression with its basis so a silent suppression is never mistaken for "nothing to propose".
5. **Writes a directory contract.** `proposed/README.md` states that the directory is not an `/automate --folder` target and that promotion is a human moving a file out of it.

## What the domain basis does (`--domain`)

1. **Three inputs, each carrying its own evidence class into the output.** (a) the **product store**, read through `read-product.sh`; (b) the **capability inventory** — direct grep/glob reads over this project's own code and docs plus any `.agent/orientation/` memos, class **derived** (no code graph is built or read); (c) the **domain expectation set**, fetched from the store's `competitors[]`, class **external/judgment** and stated in every emitted file as **the weakest input** — competitor marketing overstates, and no user has been observed asking for any of it.
2. **A fixed catalogue of expectations, which is not itself evidence.** The run knows how to look for a bounded list of domain expectations (rate limiting, audit log, SSO, 2FA, RBAC, multi-currency, card-data vaulting, webhooks, bulk export, usage analytics). That catalogue is a list of things to **look for**; it is never by itself evidence that this domain expects them. **Nothing is emitted unless at least one fetched source corroborates the expectation** — so with no fetcher there is no corroboration, nothing is written at all, the run says so, and every expectation is reported *unverified* with **partial coverage**.
3. **Unverified is never reported as missing.** A capability the inventory cannot confirm either way — named in the docs but unconfirmed in code, carrying no inventory terms, or searched against an empty surface — is emitted as `unverified` with the reason. Only a search that actually ran against a non-empty code surface and found nothing may say `missing`. Every gap states **where it looked**: the surfaces, their file counts, the per-surface cap, and the exact terms used (matched case-insensitively on word boundaries, never as bare substrings).
4. **Classification, never a score.** Every gap is exactly one of `TABLE-STAKES` / `DIFFERENTIATOR` / `NOT-FOR-US`, decided from the store's own domain and audience text. The **default action** on a gap is read verbatim from `read-product.sh`'s `stance_default_action` and is never re-derived here — which is why the same store under `stance: product` and `stance: tool` yields the **same** classifications and **different** default actions. There is no score, rank, priority or ordering field.
5. **Every citation carries its url and fetch date, and coverage is reported honestly.** Fetch dates are the store's recorded `last_fetched` — this basis never writes the store, so a fetch it performs restamps nothing. Sources beyond the cap are reported as **not reached, by name**; a source older than the staleness threshold is named STALE.
6. **Suppresses what is already recorded.** Each gap carries a `domain-gap: <slug>@<classification>` token; a token already present in `proposed/` or in a `## Status: done` requirement file suppresses the candidate, and the suppression names the file that caused it. That is how a `NOT-FOR-US` gap you have already dismissed stays dismissed.

## Promoting or dismissing a candidate

- **Promote:** move the file out of `proposed/` into a real queue folder, then run it (`/automate --folder <dir>`, `/autonomous --requirement <path>`, or `/launch-pad`). Nothing is enqueued until you do. A domain candidate deliberately stops short of user stories and acceptance criteria for the work itself — hand the decided gap to `/product-owner`.
- **Dismiss durably — deleting a file here is not a durable dismissal.** Deleting a proposal only silences it **until the next run**, which recomputes the same token and writes the same file again. To dismiss permanently, paste the candidate's token line — `evidence-set:` for the ledger basis, `domain-gap:` for the domain basis — into a requirement file stamped `## Status: done` anywhere under `.supervisor/requirements/`. The next run finds that token and suppresses the candidate, naming the file it found it in.

## Notes

- **Determinism.** Two runs of either basis against an unchanged basis produce byte-identical proposal content — no run timestamps, no `$RANDOM`, no hash-order iteration.
- **Fail-safe.** `set -uo pipefail` with no `set -e`, a `jq` guard that skips rather than fails, and `exit 0` always, in both scripts. An advisory reader must never break its caller.
- **Refresh the basis first** if the ledger has gone stale: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/build-floor.sh"`. `/propose` deliberately does **not** regenerate the projection itself. The domain basis's equivalent is the store: create it once with `bash "${CLAUDE_PLUGIN_ROOT}/scripts/propose-product.sh"`, which is itself propose-only and writes nothing without `--confirm`.

## See Also

- `loomwright/scripts/propose-work.sh` — the ledger basis, guarded by `loomwright/scripts/test-propose-work.sh`.
- `loomwright/scripts/propose-domain.sh` — the domain basis, guarded by `loomwright/scripts/test-propose-domain.sh`.
- `loomwright/scripts/read-product.sh` / `propose-product.sh` — the product store's reader and its propose-only bootstrap.
- `/insights` — the run scoreboard over the same session logs.
- `/automate` — the engine that walks a *human-promoted* queue to reviewed PRs.
