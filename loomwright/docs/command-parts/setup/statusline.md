## Module: statusline

Wires Loomwright's one-line run report into the host's status-line surface, so a long run stops being opaque without the user opening `.supervisor/state.md` by hand. **Opt-in, and it is the only module that writes the USER-SCOPE settings document.**

The line is assembled from facts that already exist and nothing else:

```
Loomwright · EXECUTE · feature/status-line · 3/4 · 2m ago
```

phase · branch · COMPLETED-over-total subtasks · how long ago the newest session-log record was written. **Every field is omitted rather than guessed** when its source is absent, and with no state file at all the line reads `Loomwright · no run state`.

> **There is deliberately NO "currently running agent" field, and that absence is the honest answer rather than a gap.** Inferring it would mean reading the recency of some other record and calling that liveness — a log line proves something was written, never that anything is running now. The emitter that would have made such a field truthful was investigated and closed NO-GO, so no spawn event exists in any log to read. `test-status-line.sh` asserts the absence mechanically, in the rendered output AND as a source grep, so this paragraph cannot rot into a claim the code does not back.

> **Time is read from the record, never from the filesystem.** The age comes from the log line's own `ts` field, parsed try-BSD-then-GNU and validated numeric before any arithmetic; the field is omitted when neither flavour parses it. `stat` is never invoked — `stat -f %m` is BSD and *succeeds with garbage* on GNU/Linux, which would put a plausible wrong number on screen rather than failing visibly.

The deterministic engine is `${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh` (subcommands `check` / `apply` / `remove`). It is fail-safe (always exits 0 — "fails closed" here means refuse-to-write plus a named-reason status line, never a non-zero exit), write-contained to the user-scope settings document (+ one timestamped backup), and it never touches a project file. The renderer itself is `${CLAUDE_PLUGIN_ROOT}/scripts/status-line.sh` — read-only, dependency-free, and it always exits 0. This command owns the INTERACTIVE half.

### Check

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" check` and report its cells: the settings path, whether the renderer exists, the `settings parse:` gate (`ok` / `absent` / `UNPARSEABLE`), the `statusLine:` cell (absent / installed by this plugin / **NOT installed by this plugin**, with the existing value shown), the `restore record:`, and the `Statusline readiness:` verdict (`configured` / `not configured` / `foreign (…)` / `unknown (…)`). Read-only — `check` writes nothing. `unknown` means nothing could be probed (missing `jq`, or a settings document that does not parse): report it as UNVERIFIED, never as clean.

### Report

Print what check found. For the `status` subcommand, STOP after the report — read-only, no writes, no offer.

### Offer — CONSENT-BEARING when something already exists

**If `not configured`** — use `AskUserQuestion` (cap 4 options):
- `question`: "Wire Loomwright's status line into your settings?"
- `header`: "Statusline"
- `multiSelect`: false
- `options`:
  1. `Apply` — "Set statusLine to Loomwright's one-line run report. Your settings file is backed up first, and every unrelated key is preserved."
  2. `Status only` — "Re-print the report and stop (no writes)."
  3. `Cancel` — "Do nothing."

**If `foreign`** — this is the case that matters, and it is neither configured nor unconfigured. **Do NOT offer a plain "Apply".** Report the existing value verbatim, state plainly that applying would REPLACE the user's own status line, and offer:
  1. `Replace it` — "Install Loomwright's status line. Your current one is recorded under `.loomwrightStatusLinePrior` and `/setup statusline remove` restores it verbatim." Runs the engine **with `--replace`**.
  2. `Leave mine alone` — "Change nothing." (the default; treat any ambiguous answer as this)
  3. `Status only` — "Re-print the report and stop."

Default to NOT applying in both cases. **Never pass `--replace` on the strength of a generic "yes"** — it is earned only by the user choosing `Replace it` against a report that named their existing value.

### Apply

1. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" apply` (adding `--replace` ONLY per the offer above) after an explicit confirm.
2. Read its **headline status line** and report it verbatim. Exactly ONE of these is printed:
   - `apply: applied` — the status line was installed; a timestamped backup path is printed on the following line.
   - `apply: applied (REPLACED a pre-existing statusLine …)` — followed by the `replaced:` value. Relay BOTH; never present this as a plain `applied`, and tell the user how to get their line back.
   - `apply: applied (created …)` — there was no settings document; one was created holding just the status line.
   - `apply: no-op — already configured` — nothing was written (idempotent second run), and no second backup was made.
   - `apply: WITHHELD — a statusLine this plugin did not write is already configured` — followed by the existing value. **Nothing was written and no backup was made.** This is the fail-closed path, not a failure: relay it and go back to the Offer step. Never re-run with `--replace` to "get past" it.
   - `apply: ABORTED — <reason>` — nothing was written, no partial write, no backup. Reasons: the settings document exists but is not valid JSON; `jq` unavailable or non-functional; the renderer script is missing; no free backup name. Surface the reason and STOP. **Never "repair" the settings document to get past an abort** — a hand-edited file is the user's.
3. Tell the user the status line appears on the next session (the host reads `statusLine` at startup).

### Verify

Re-run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" check` and show the before/after: the verdict now `configured`, the command pointing at `status-line.sh`, and the backup path. Success is claimed ONLY after that re-check. As a live smoke test, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/status-line.sh"` in the project and show the actual line — it exits 0 even with no run in flight.

### Subflow: `/setup statusline remove`

1. Confirm via `AskUserQuestion` first.
2. Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-statusline.sh" remove`. It restores the status line that was there BEFORE this module applied (recorded at apply time under `.loomwrightStatusLinePrior`), or deletes ours outright when there was none, then drops the record. Backup-first, like apply.
3. **`remove` REFUSES a status line this plugin did not write** — it prints `remove: REFUSED` and changes nothing. That is correct: a foreign status line is not this module's to remove, and the user should edit it themselves.

### Idempotency note

A second `/setup statusline` on an already-configured setup reports `no-op — already configured`, writes nothing and makes no second backup — apply computes the document it would write and byte-compares it against the one on disk before touching anything. **The restore record survives re-application unchanged:** a second apply must never recapture the current (ours) value as "the prior one", or `remove` would hand the user back a copy of the very thing it was undoing instead of their own status line.

---

