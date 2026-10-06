## SYSTEM_CONTRACT

Per-subsystem artifact in the **System Twin** contract store. One file per subsystem at
`.supervisor/twin/contracts/<subsystem-id>.md` (the `<subsystem-id>` is the sanitized filename;
the logical `subsystem` name is preserved verbatim in the artifact body). Written **exclusively**
by `scripts/write-system-contract.sh`, read via `scripts/read-system-contract.sh` (the read-side
provenance gate). This is the **authoritative definition** of the contract body.

`.supervisor/twin/` is an ADVISORY artifact store like `.supervisor/memory/` — **subordinate to
the human-authored CLAUDE.md** and NEVER an enforcement boundary. Contracts are propose-only;
any conformance check against them (`SUPERVISOR_RESULT.contract_conformance`) is advisory and
NEVER blocks a PR or changes a heal decision. See `docs/ARCHITECTURE_CONTRACTS.md` §"System Twin
homing contract" for the sole-writer / pinned-CWD / worktree-guard enforcement model.

```yaml
SYSTEM_CONTRACT:
  schema_version: 1
  subsystem: string            # logical name or path, e.g. "scripts/build-insights.sh" or "supervisor-phase45"
  invariants: [string]         # properties that must hold
  dependencies: [string]       # DIRECTIONAL "depends-on" edges: subsystems/files THIS subsystem depends on.
                               # These are the forward blast-radius edges (Pillar 1 reads these). The REVERSE
                               # direction ("depended-on-by" / derived dependents) is NOT stored — it is
                               # computed on demand by scripts/twin-graph.sh, which scans every verified
                               # contract's dependencies to find who points back at this subsystem.
  behavioral_specs: [string]   # observable behaviors
  incident_history: [ {date, kind, summary, source} ]
                               # OPTIONAL/ADDITIVE advisory blast-radius history; bounded (the Phase 4.5
                               # builder keeps the most recent 5, chronological oldest-first) + deduped. Each entry:
                               #   date    — ISO 8601 timestamp of the incident
                               #   kind    — one of: conformance_violation | self_heal_fix | other
                               #   summary — short string describing the incident
                               #   source  — the builder session id that recorded it
                               # Append-only by the Phase 4.5 contract builder, and only for THIS run's incidents.
  provenance:
    derived_from: string       # commit SHA or "git diff origin/main...HEAD"
    written_at: string         # ISO 8601
    source: string             # builder session id / agent
    content_hash: string       # OPTIONAL/informational only. The AUTHORITATIVE content_hash lives in
                               # the .provenance.jsonl ledger (sha256 of the contract-file bytes), NOT
                               # in the body — a file cannot contain its own hash. See note below.
```

**Store / provenance notes:**
- The artifact body above is held verbatim in the contract file. A separate hash-chained
  provenance ledger at `.supervisor/twin/.provenance.jsonl` carries, per write, a
  `{subsystem, prev_hash, content_hash, source, action, written_at}` entry (mirroring
  `.supervisor/memory/.provenance.jsonl`). The **authoritative `content_hash` lives in the ledger,
  not in the artifact body** — `write-system-contract.sh` computes it as `sha256(contract-file-bytes)`
  at write time and records it only in the ledger entry. The read-side gate (`read-system-contract.sh`)
  **recomputes `sha256(contract-file-bytes)` and matches it against the ledger's `content_hash`** to
  decide whether a contract is verified. (A file cannot contain its own hash, so the body's
  `provenance.content_hash` field is at most an informational copy and is never what the gate checks.)
  Un-provenanced or post-chain-break contracts are dropped (and logged to `.supervisor/logs/twin.log`),
  never emitted.
- **Subsystem ID convention (writer ⇄ reader MUST agree).** The `subsystem` id is the lookup key,
  so the builder (writer) and Launch Pad (reader) must derive the *same* id for the same subsystem —
  otherwise a read silently misses (graceful fallback emits nothing). Convention: use the
  **repo-root-relative path** for a file-backed subsystem (e.g. `scripts/build-insights.sh`) and a
  stable **logical name** for a cross-file concern (e.g. `supervisor-phase45`). The store *filename*
  is a sanitized form of this id (`/` → `-`, etc.); the logical id is preserved verbatim in the body
  and in the provenance `subsystem` field. Do not abbreviate (`build-insights` ≠ `scripts/build-insights.sh`).
- `schema_version` stays `1`. The artifact is propose-only and advisory; downstream subtasks
  (ST2 read-path, ST3 prove/hard-signal, ST4 measure-path) treat this schema as source of truth.
- **`incident_history` is additive (a contract written WITHOUT it stays valid).** Following the
  same additive precedent as the foundation slice, `schema_version` **stays `1`** — adding this
  field does NOT bump the version, and any reader/conformance check MUST treat a missing
  `incident_history` as the empty list. Entries are **advisory / propose-only**, **bounded + deduped**,
  and are only ever **appended by the Phase 4.5 contract builder for THIS run's incidents**
  (a conformance violation it observed, or a self-heal fix it applied) — never backfilled, never
  authoritative, and never a gate. `dependencies[]` remains directional "depends-on" edges; the
  reverse ("depended-on-by") is derived live by `scripts/twin-graph.sh` and is intentionally NOT
  persisted in the contract.

---

