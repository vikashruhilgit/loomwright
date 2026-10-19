### Final step — record this run (mandatory, even when nothing was accepted)

After Phase 4 APPROVE completes — **including a run where every item was Rejected, or where there was nothing to propose at all** — `/dreaming` stamps its own last-run value **and names the session logs it actually read in Phase 1 GATHER**:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/curation-status.sh" record dreaming <session_id> [<session_id> ...]
```

Each `<session_id>` is a log's basename minus `.jsonl` — exactly the `--sessions N` files selected in step 1 of GATHER. Pass **every** one that was fed to reflection, and **only** those.

**Naming them is the whole point of this call, not a detail.** The stored record is a *consumed set*, so `pending` falls by precisely the logs this run read and the unread remainder stays counted for the next one. A bare `record dreaming` with no ids still stamps `last_run` — a run that genuinely read nothing is a real run, and capturing it is why this record exists — but the probe will WARN that `pending` will not fall, because a run that read logs and forgot to name them looks exactly like a stuck probe.

> **Why a set and not a timestamp.** `/dreaming` reads the *most recent* N logs, so what it leaves behind is *older* than any stamp it could write. v15.29.0 stored wall-clock `now` and computed `pending` as "logs newer than that", which meant one run retired the entire unread backlog — on this repo, 56 logs — with no way to target them later. No single timestamp can express "the newest 5 are done, the older 57 are not"; only set membership can.

`dreaming` is the **only** legal `record` target; any other argument is rejected with a message and still exits 0. An id naming a log that is not on disk is reported and not stored. Skipping this call entirely leaves the stored value at `never` forever, which silently keeps the SessionStart curation nudge firing and makes every readiness answer wrong — it is not an optional flourish.

