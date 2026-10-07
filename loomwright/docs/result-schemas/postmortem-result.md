## POSTMORTEM_RESULT (PR review-churn analyzer)

Appended by the `/pr-postmortem` command (governed by `skills/pr-postmortem/SKILL.md`) — the read-only
on-demand **PR review-churn root-cause analyzer**. After a PR has absorbed multiple rounds of post-PR
review-and-fix, the command gathers the PR's metadata + review threads + diff stats (via
`scripts/pr-postmortem-gather.sh`), buckets each review round into a reproducible root-cause class, and
attributes it to a flow stage. It prints a human-readable root-cause report, then appends **exactly one**
jq-built JSONL line to `.supervisor/postmortem/results.jsonl` under the current working `.supervisor/`
(never the analyzed repo).

It is **advisory / diagnostic only** — it never writes code, never gates, never blocks the PR. The append
is best-effort and fail-safe (a `jq`/IO failure prints one warning and still exits 0; the report is already
printed). There is **no hook validator** (mirroring EVAL_RESULT / GROUND_TRUTH_JSON — the command is the
main agent of its own session). The accumulated trend file is the **seed corpus for a future synthetic eval
harness** (the deferred M2b part-2b headless-`claude` evaluator).

```json
{
  "schema_version": 1,
  "ts": "2026-06-10T12:00:00Z",
  "repo": "owner/repo",
  "number": 43,
  "agent_generated_guess": true,
  "review_rounds": 4,
  "additions": 312,
  "deletions": 27,
  "changed_files": 9,
  "categories": [ {"round": 1, "class": "quality_gap", "self_heal_miss": true, "flow_stage": "self_heal", "evidence": "backend missing the numeric guard the frontend has"}, ... ],
  "self_heal_misses": 3,
  "flow_stages": { "launch_pad": 0, "worker": 1, "self_heal": 3, "unknowable": 0 },
  "summary": "4 rounds; 3 were self-heal misses (validation parity + falsy coercion)",
  "plugin_version": "14.24.0",
  "pr_url": "https://github.com/owner/repo/pull/43",
  "branch": "feature/x",
  "changed_paths": ["src/a.ts", "src/b.ts"],
  "brief_path": null,
  "job_path": null
}
```

**Field contract (schema_version: 1):**
- `schema_version` — integer, required, always `1`.
- `ts` — ISO 8601 UTC timestamp at append time.
- `repo` — `owner/repo` of the analyzed PR (from gather).
- `number` — integer PR number (from gather).
- `agent_generated_guess` — boolean; best-effort agent-PR heuristic (from gather).
- `review_rounds` — integer; total review-and-fix rounds (from gather). The gather derives it as the
  MAX of three signals: review-fix commit headlines, formal churn-review submissions, and
  **bot-authored issue-comment review rounds** (a comment from a review-bot author — login `claude`,
  `github-actions*`, or any `*[bot]` — whose body
  carries a review marker — a word-bounded review stem ("review"/"reviewed"/"reviewer"/"reviewing"/"reviews") or
  "finding(s)" anywhere in the body — followed by at least one later push). The
  third signal covers repos whose review feedback arrives as CI-workflow comments (e.g. `claude[bot]`)
  instead of GitHub review objects, which previously left this field at 0 despite real churn. The
  gather's own output additionally carries a `review_rounds_source` note (`fix_commits` |
  `formal_reviews` | `bot_comments` | `none`); that note stays in the gather output and is NOT part of
  this trend line — the schema is unchanged at `schema_version: 1`.
- `additions` / `deletions` / `changed_files` — integers; PR size (from gather).
- `categories` — array of per-round objects `{round, class, self_heal_miss, flow_stage, evidence}`, one
  per review round, classifying each into a root-cause class and the flow stage that should have caught it.
- `self_heal_misses` — integer; count of rounds flagged `self_heal_miss` (i.e. Phase 4.5 should have
  caught the class but didn't).
- `flow_stages` — object tallying rounds per stage `{launch_pad, worker, self_heal, unknowable}`.
- `summary` — short human-readable one-liner.
- `plugin_version` — string, **additive & optional** — plugin version at analysis time, read
  defensively from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` via jq with an `"unknown"`
  fallback. Absent in older trend lines, which remain valid — `schema_version` stays `1`.
- `pr_url` — string \| null, **additive & optional** — the analyzed PR's URL (gather `.url // null`).
  Absent in older trend lines, which remain valid — `schema_version` stays `1`.
- `branch` — string \| null, **additive & optional** — the PR head branch (gather `.headRefName // null`).
  Absent in older trend lines, which remain valid — `schema_version` stays `1`.
- `changed_paths` — array of strings, **additive & optional** — the PR's changed file paths (gather
  `[(.files // [])[].path]`; `[]` when the PR JSON omits `files`). Absent in older trend lines, which
  remain valid — `schema_version` stays `1`.
- `brief_path` — string \| null, **additive & optional** — local `.supervisor/jobs/done/` brief path
  when the analyzed PR maps to one; `null` by default (unknowable for an arbitrary external PR — never
  invented; a future enrichment may populate it). Absent in older trend lines, which remain valid —
  `schema_version` stays `1`.
- `job_path` — string \| null, **additive & optional** — local job-file path when known; `null` by
  default (unknowable for an external PR — never invented). Absent in older trend lines, which remain
  valid — `schema_version` stays `1`.
- `source` — string, **additive & optional** — discriminates HOW the line was produced. Two values
  today: `"github_postmortem"` (the implicit default — a `/pr-postmortem` GitHub-surface analysis;
  absent on legacy lines, read as `"github_postmortem"` by consumers) and `"automate_drain"` (an
  engine-native line emitted by `/automate` at end-of-DRAIN from `REVIEW_HEAL_RESULT` + `SUPERVISOR_RESULT`
  data the engine already holds — see the variant note below). Absent in older trend lines, which remain
  valid — `schema_version` stays `1`.
- `automate_key` — string, **additive & optional** — a deterministic idempotency key
  (`run_id` + item + `pr_url` + `source` + completeness, joined on U+001F) present **only on
  `source: "automate_drain"` lines**. The `/automate` `learning-emit` helper scans the ledger for a
  line with the same key and skips the append if found, so a crash/`--resume` re-entry yields exactly
  one line per processed PR. The trailing **completeness** component is `"complete"` when
  `changed_paths` is a non-empty array and `"degraded"` otherwise, because a `changed_paths: []` line
  is permanently invisible to `read-postmortem.sh` (its overlap filter can never match an empty
  array); without the discriminator a degraded first emit poisoned the key and blocked every later
  emit that DID carry the fetch data. `complete` requires at least one **non-empty** path: an empty
  string is not a usable path (`read-postmortem.sh` drops empty query paths before matching), so a
  `changed_paths: [""]` line is exactly as invisible as `[]` and must stay correctable. Consequently
  at most TWO lines can share a run/item/pr/source prefix — one `degraded` and one `complete`. The
  `degraded` line is invisible to `read-postmortem.sh` but is **NOT** quarantined downstream: `repo`
  and `number` are derived from `pr_url` independently of the fetch that degrades, so a
  contract-compliant caller emits it with the REAL `number` (a `number: 0` means `--number` was
  omitted entirely, not that the fetch failed). Both lines therefore share the `repo`#`number` key
  that `build-loop-evidence.sh` and `measure-heal-signal.py` join on — **both pick floor-raising**
  (max `review_rounds`, tie-break latest `ts`), so the richer line wins and the pair cannot report a
  stale low count. **Legacy keys** written before the discriminator carry only the four components;
  the helper recognises them by prefix, so a legacy *complete* line stays idempotent and a legacy
  *degraded* line is correctable. Treat `automate_key` as an opaque string — match it by EXACT
  equality (as `curate-postmortem.sh`'s `target_key` does), never by parsing its components. Absent on
  `github_postmortem` lines and older trend lines, which remain valid — `schema_version` stays `1`.

**`source: "automate_drain"` variant (engine-native ground-truth line).** When `/automate` processes a
PR-producing item (merged OR parked), it emits ONE full valid `schema_version: 1` POSTMORTEM_RESULT at
end-of-DRAIN — built jq-only by `scripts/automate-helpers.sh learning-emit` from the owned drain's
`REVIEW_HEAL_RESULT` (`fix_cycles`, `repeat_check_failure`, `unresolved_bot_feedback`, `decision`) +
the inner `SUPERVISOR_RESULT` (`repo`, `number`, `pr_url`, `branch`) plus a single
`gh pr view --json files,additions,deletions,changedFiles` for `changed_paths` and the integer size
fields. It deliberately does NOT run a `/pr-postmortem` gather (which reads a false `review_rounds: 0`
on the inline-drain + CI-check + squash flow `/automate` produces). Field-mapping specifics for this
variant:
- `review_rounds` is the **`effective_review_rounds`** = the ground-truth drain `fix_cycles` (the real
  fix→push count), OR `1` for a zero-cycle escalation (`fix_cycles == 0 AND decision == "ESCALATED"`) —
  it is NOT a GitHub-measured review count. It stays **drain-only** even when `self_heal_rounds` (next
  bullet) is present — `build-loop-evidence.sh` / `measure-heal-signal.py` join on `review_rounds`
  floor-raising, so folding self-heal churn into it would silently change historical comparisons.
  `flow_stages.self_heal` carries the same drain-only value; the other flow stages are `0` (the engine
  cannot attribute drain churn to launch_pad/worker).
- `self_heal_rounds` — integer, **additive & optional**, `automate_drain` lines only — the Phase 4.5
  self-heal fix iterations the PR absorbed BEFORE it reached the drain (a PR healed in self-heal and
  then drained with 0 fix cycles otherwise reads as `review_rounds: 0` / `categories: []` — a false
  clean). Its source is the **OBSERVED** `SUPERVISOR_RESULT.heal_iterations`, passed as
  `learning-emit --self-heal-rounds <n>` — **never** the configured `/supervisor --heal-iterations`
  MAXIMUM bound (which is why the flag does not reuse that name: the bound would record fake churn).
  **Presence rule:** emitted ONLY when `--self-heal-rounds` was passed (any value), placed right after
  `review_rounds`; with the flag omitted the line is byte-identical to a pre-field line (the engine
  omits the flag when its `SUPERVISOR_RESULT` artifact has no `heal_iterations:` line — never a
  fabricated count). **Normalization:** surrounding whitespace is trimmed first; a non-negative
  integer then passes through; anything else (non-numeric, negative, fractional, empty, internal
  whitespace) ⇒ `0` — never a non-zero exit (fail-SAFE). NOT part of
  `automate_key`. Absent on `github_postmortem` lines and older trend lines — `schema_version` stays `1`.
- `categories[]` carries **at most one drain entry plus at most one `self_heal_churn` entry**, coarser
  than `/pr-postmortem`'s per-round classification but honestly labeled by `class`. The **zero-rule**
  (load-bearing because `read-postmortem.sh` counts each `categories[]` element as one prior-churn round
  and groups by `.class`): `categories: []` **iff** `effective_review_rounds == 0` (i.e.
  `fix_cycles == 0 AND decision != "ESCALATED"`) **AND** `self_heal_rounds == 0` (absent counts as `0`)
  — NEVER a synthetic entry for absent churn (it would report fake churn; self-heal churn is real).
  Entries, in chronological order (self-heal precedes the drain):
  - `self_heal_rounds > 0` → FIRST, one `{round: self_heal_rounds, class: "self_heal_churn",
    self_heal_miss: false, flow_stage: "self_heal", evidence: "Phase 4.5 self-heal, heal_iterations=<n>"}`
    (`self_heal_miss: false` — a finding healed in self-heal is a catch, not a miss);
  - `fix_cycles > 0` → one `{round: fix_cycles, class: "drain_churn", flow_stage: "self_heal", ...}`;
    a zero-cycle escalation → one `{round: 1, class: "drain_escalation", flow_stage: "self_heal", ...}`.
- **`flow_stages.self_heal` is drain-only (the counter-vs-categories split):** self-heal churn appears
  ONLY in `self_heal_rounds` and its `categories[]` entry, never in the `flow_stages` counter. This
  widens the known counter-vs-`categories[]` disagreement that `build-floor.sh` reports as
  `flow_stage_counter_disagreements` (see the `postmortem` caveat in FLOOR_PROJECTION) — still confined
  to `automate_drain` lines.
- **`/propose` will see `self_heal_churn` as a recurring pair.** `scripts/propose-work.sh` groups
  `categories[]` by `(class, flow_stage)` and writes a candidate once a pair reaches its threshold
  (`PROPOSE_THRESHOLD`, default 10). Every self-healed PR adds one `self_heal_churn`/`self_heal` entry,
  so that pair WILL cross the threshold and yield candidates whose evidence is entirely catches
  (`self_heal_miss: false`) — the same shape as the owner-dismissed `drain_churn` pair. Advisory only
  (a candidate still needs a human to promote it); dismiss it the same durable way `drain_churn` was.
- The default `summary` (no caller `--summary`) appends `; self-heal: <n> round(s)` when
  `self_heal_rounds > 0`; otherwise it is unchanged. A caller-supplied `--summary` is emitted verbatim.
- `self_heal_misses` ← `1` if `repeat_check_failure OR unresolved_bot_feedback`, else `0` (the drain
  `categories[]` entry's `self_heal_miss` mirrors `self_heal_misses > 0`; the `self_heal_churn` entry's
  is always `false`).
- `changed_paths` **and** `repo` are **both required for `read-postmortem.sh` visibility** — the advisory
  reader keeps a corpus line only when its `changed_paths` overlaps the query paths **AND** (when the
  current repo is determinable) its `repo` matches the reader's repo case-insensitively
  (`read-postmortem.sh:159` [pins: `changed_paths overlap the query set`]). So `repo` is co-load-bearing with `changed_paths`: an `automate_drain`
  line with `repo: ""` (the helper's default when `--repo` is omitted — emitted as `""`, NOT `null`) is
  filtered out whenever the reader's repo resolves. The `/automate` wiring therefore derives `repo`
  (`owner/repo`) from `pr_url` and always passes `--repo`. On a failed `gh pr view` fetch `changed_paths`
  degrades to `[]` and the integer size fields to `0` (NEVER `null`) — the line is still written
  (fail-safe), just invisible to the reader. That invisibility is **recoverable, not permanent**: the
  `automate_key` completeness discriminator (above) lets a later `learning-emit` for the same
  run/item/PR append the corrective `complete` line once the fetch data is in hand, leaving the inert
  degraded line untouched (append-only; `curate-postmortem.sh` stays the sole curator writer).

**`source: "curation"` variant (curation record — retract / supersede).** The ledger may also contain
**curation records** — jq-built JSONL lines appended ONLY by `scripts/curate-postmortem.sh` (the
human-gated **sole curator writer**, mirroring the `add-rule.sh` writer precedent) so the advisory reader
can hide retracted / superseded entries. A curation record is NOT a churn data line — it names one:

```json
{"schema_version":1,"source":"curation","curation_action":"retract","target_key":"<automate_key or pr_url>","replacement":null,"reason":"root-cause classification was wrong — re-analyzed","ts":"2026-07-07T12:00:00Z"}
```

Field contract for this variant (ADDITIVE — `schema_version` stays `1`; an OLD reader fail-safe-skips a
curation record because it carries no `changed_paths`, so the overlap filter can never match it):
- `curation_action` — `"retract"` (the target entry is wrong/noise) \| `"supersede"` (a later PR replaced
  the analysis). **Both actions hide the target identically today** — `replacement` is provenance for the
  human trail, not a reader input.
- `target_key` — required non-empty string; matches a data line's `automate_key` **OR** `pr_url` by
  **EXACT string equality** (`read-postmortem.sh` then excludes every matched entry from churn hits).
  Newlines/CRs and whitespace-only values are rejected at write time (they could never match a real
  JSONL line's key and would only produce a dead record).
- `replacement` — REQUIRED `pr_url` string on `supersede` (the writer REJECTS a replacement-less
  supersede, exit 2 — it would be an indistinguishable synonym for retract); `null` on `retract`
  (the writer likewise REJECTS `--replacement` on a retract, exit 2).
- `reason` — required non-empty free text (jq-escaped; embedded newlines become `\n` inside the JSON
  string so the record stays a single line).
- `ts` — ISO 8601 UTC at append time.

**Human gate + write discipline** (enforced in code by `curate-postmortem.sh`, never as prose): WITHOUT
`--confirm` the writer prints the exact would-append JSON line + a dry-run notice and **exits 1 — it
never writes unattended**; with `--confirm` it appends exactly ONE line (append-only — an existing
ledger line is NEVER rewritten, edited, or removed; correcting a bad curation record means appending a
new one) and read-back-verifies the ledger tail. All JSON is jq-built (`jq -n --arg`) — user input is
never string-interpolated. As a WRITER it fails LOUD (exit 2 validation / write error; exit 3 refused —
jq unavailable OR run from a git worktree: like `write-lessons.sh`'s red-team-F1 guard, curation writes
only from the repo main checkout, since a worktree's gitignored `.supervisor/` is silently lost on
`git worktree remove`), unlike the fail-safe readers (bimodal failure philosophy).

**Reader behavior** (`read-postmortem.sh`): (a) a curation record is **NEVER counted as a churn hit
itself**; (b) the curated `target_key` set is built over the WHOLE corpus first — independent of repo
scoping and of where in the file the record sits — and any data entry whose `automate_key` OR `pr_url`
is in that set is excluded from the aggregation. **Presence discipline:** a curation record whose
`target_key` is missing, `null`, non-string, or empty is malformed and contributes NO target — the
entries it meant to curate stay LIVE (skip the record, never guess). The reader's EMPTY⇒silent and
always-exit-0 contracts are unchanged.

**Staleness (`CHURN_STALE_DAYS`):** independently of curation, the reader now EXCLUDES any data entry
whose `ts` parses as ISO 8601 and is older than `CHURN_STALE_DAYS` days (env override; default `180`; a
non-numeric override falls back to 180) vs now. A **missing or unparseable `ts` is treated as FRESH**
(fail-open — an old-format line must never vanish silently); parsing uses jq's `fromdateiso8601?` so a
bad `ts` can never crash the query. The `/insights` `## Corpus health` section reports the same counts
advisorily (entries / curated / stale) using the same record shapes.

**Backward compatibility:** these provenance + discriminator fields (`pr_url`, `branch`, `changed_paths`,
`brief_path`, `job_path`, `source`, `automate_key`) are purely additive — a pre-Phase-4 corpus line that
omits all of them is still a valid `schema_version: 1` POSTMORTEM_RESULT line and parses cleanly for any
consumer (a line with no `source` is read as `"github_postmortem"`; `automate_key` is present only on
`automate_drain` lines; so is `self_heal_rounds`, which additionally appears only when
`learning-emit --self-heal-rounds` was passed). The `source: "curation"` record variant is likewise additive: `schema_version`
stays `1`, and a pre-curation reader fail-safe-skips it via the `changed_paths` overlap filter.

**Append-only / write-only:** the file is the seed corpus for the deferred synthetic eval harness; it is
never read back **by this skill** (a separate advisory reader, `scripts/read-postmortem.sh`, now consults it — see Phase 4) and lives under the current working `.supervisor/`, never the analyzed repo.
The ledger has exactly three sanctioned appenders — `/pr-postmortem` (data lines), `/automate`
`learning-emit` (`automate_drain` data lines), and `curate-postmortem.sh` (`curation` records) — and
NONE of them ever rewrites an existing line.
See `skills/pr-postmortem/SKILL.md` (the analysis protocol + miss-class taxonomy) and
`scripts/pr-postmortem-gather.sh` (the read-only gather).

---

