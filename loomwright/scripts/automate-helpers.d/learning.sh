# --------------------------------------------------------------------------- #
# §6 step 3 — engine-native ground-truth learning line (fail-SAFE, jq-only,
#             idempotent). Emits ONE full valid schema_version:1 POSTMORTEM_RESULT
#             per processed PR (merged OR parked) from data the engine already
#             holds (REVIEW_HEAL_RESULT fix_cycles/repeat_check_failure/
#             unresolved_bot_feedback/drain_result + SUPERVISOR_RESULT
#             repo/number/pr_url/branch) plus a single `gh pr view` for
#             changed_paths + integer size fields. NO /pr-postmortem gather, so no
#             GitHub-blind false-0. Additive `source:"automate_drain"` +
#             `automate_key` discriminate it from a github_postmortem line.
# --------------------------------------------------------------------------- #

# learning-emit <ledger_path> --repo <r> --number <n> --pr-url <url> --run-id <id>
#   --item <item> --fix-cycles <n> --drain-result <READY|ESCALATED>
#   --repeat-check-failure <true|false> --unresolved-bot-feedback <true|false>
#   --changed-paths-json <json-array> --additions <n> --deletions <n>
#   --changed-files <n> --summary <text> [--plugin-version <v>] [--ts <iso>]
#   [--branch <b>] [--source <s>] [--self-heal-rounds <n>]
#
# --self-heal-rounds <n> — the Phase 4.5 self-heal churn that happened BEFORE the
# PR reached the drain. <n> is the OBSERVED count, `SUPERVISOR_RESULT.heal_iterations`,
# never the configured `/supervisor --heal-iterations` MAXIMUM bound (default 3) —
# which is exactly why the flag is not named `--heal-iterations`: passing the bound
# would record fake churn. Contract (decisions 1–8 of the
# 2026-09-26-learning-emit-self-heal-rounds brief; authority for the field mapping
# is docs/RESULT_SCHEMAS.md POSTMORTEM_RESULT §"`source: \"automate_drain\"` variant"):
#   1. `review_rounds` keeps its DRAIN-ONLY meaning (effective_review_rounds, below).
#      build-loop-evidence.sh / measure-heal-signal.py join on it floor-raising, so
#      folding self-heal into it would silently change historical comparisons.
#   2. Additive integer `self_heal_rounds`, emitted ONLY when the flag was passed
#      (any value). Omit the flag ⇒ the line is byte-identical to the pre-flag one.
#      Normalization: a non-negative integer passes through; anything else
#      (non-numeric, negative, fractional, empty) ⇒ 0 — never a non-zero exit.
#      Surrounding whitespace is trimmed FIRST (`" 2"`/`"2\n"` from a grep/awk
#      extraction ⇒ 2), so a padded value is never silently recorded as 0.
#   3. `self_heal_rounds > 0` adds ONE `categories[]` entry
#      {round: n, class: "self_heal_churn", self_heal_miss: false,
#       flow_stage: "self_heal", evidence: "Phase 4.5 self-heal, heal_iterations=<n>"},
#      placed BEFORE any drain entry (self-heal precedes the drain). A healed finding
#      is a catch, not a miss ⇒ self_heal_miss:false. read-postmortem.sh counts each
#      element as one round and groups by .class, so it needs no change.
#   4. Zero-rule restated: `categories: []` iff effective_review_rounds == 0 AND
#      self_heal_rounds == 0 (absent counts as 0) — at most ONE drain entry plus at
#      most ONE self_heal_churn entry. Still no fake churn: self-heal churn is real.
#   5. Default summary unchanged when self_heal_rounds is absent/0; when > 0 it
#      appends "; self-heal: <n> round(s)". A caller --summary is emitted verbatim.
#   6. The idempotency key (run_id|item|pr_url|source|completeness) is UNCHANGED —
#      self_heal_rounds is not part of it.
#   7. (flag name — see the first paragraph above.)
#   8. `flow_stages.self_heal` keeps counting DRAIN rounds only; self-heal churn
#      appears only in `self_heal_rounds` and `categories[]` (this widens the known
#      counter-vs-categories disagreement build-floor.sh reports as
#      flow_stage_counter_disagreements, confined to automate_drain lines).
#
# FAIL-SAFE: this is one of the two subcommands (with brief-repair) that must
# NEVER die/abort — it runs inside the per-item loop as an advisory side-effect
# and a failure must NEVER gate the engine. We `set +e` at the top (this lib is `set -euo pipefail`) so any failing
# command (jq absent, unwritable ledger, bad JSON, missing arg) degrades to a
# no-op / degraded line and returns 0 — same posture as dispatch-pr-postmortem.sh /
# send-webhook.sh.
learning_emit() {
  set +e   # FAIL-SAFE: always exit 0; never die/abort inside the per-item loop.

  local ledger="${1:-}"; shift || true
  [ -n "$ledger" ] || return 0

  # Defaults.
  local repo="" number="0" pr_url="" run_id="" item=""
  local fix_cycles="0" drain_result="" repeat_check_failure="false" unresolved_bot_feedback="false"
  local changed_paths_json="[]" additions="0" deletions="0" changed_files="0"
  local summary="" plugin_version="" ts="" branch="" source="automate_drain"
  local shr_given="0" shr_raw=""

  # Parse named flags defensively — an unknown/short flag is ignored, never fatal.
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)                    repo="${2:-}"; shift 2 || shift ;;
      --number)                  number="${2:-0}"; shift 2 || shift ;;
      --pr-url)                  pr_url="${2:-}"; shift 2 || shift ;;
      --run-id)                  run_id="${2:-}"; shift 2 || shift ;;
      --item)                    item="${2:-}"; shift 2 || shift ;;
      --fix-cycles)              fix_cycles="${2:-0}"; shift 2 || shift ;;
      --drain-result)            drain_result="${2:-}"; shift 2 || shift ;;
      --repeat-check-failure)    repeat_check_failure="${2:-false}"; shift 2 || shift ;;
      --unresolved-bot-feedback) unresolved_bot_feedback="${2:-false}"; shift 2 || shift ;;
      --changed-paths-json)      changed_paths_json="${2:-[]}"; shift 2 || shift ;;
      --additions)               additions="${2:-0}"; shift 2 || shift ;;
      --deletions)               deletions="${2:-0}"; shift 2 || shift ;;
      --changed-files)           changed_files="${2:-0}"; shift 2 || shift ;;
      --summary)                 summary="${2:-}"; shift 2 || shift ;;
      --plugin-version)          plugin_version="${2:-}"; shift 2 || shift ;;
      --ts)                      ts="${2:-}"; shift 2 || shift ;;
      --branch)                  branch="${2:-}"; shift 2 || shift ;;
      --source)                  source="${2:-automate_drain}"; shift 2 || shift ;;
      --self-heal-rounds)        shr_given="1"; shr_raw="${2:-}"; shift 2 || shift ;;
      *)                         shift ;;   # unknown flag: ignore, never fatal
    esac
  done

  # jq-absent guard: degrade to no-op (NO write) if jq isn't runnable.
  command -v "$JQ" >/dev/null 2>&1 || return 0

  [ -n "$source" ] || source="automate_drain"
  [ -n "$ts" ] || ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  [ -n "$changed_paths_json" ] || changed_paths_json="[]"

  # Normalize changed_paths ONCE (the same shape the record below embeds) so the
  # completeness discriminator and the emitted field can never disagree.
  local cp_clean
  cp_clean="$( printf '%s' "$changed_paths_json" \
    | "$JQ" -c 'if type=="array" then map(select(type=="string")) else [] end' 2>/dev/null )"
  [ -n "$cp_clean" ] || cp_clean="[]"

  # self_heal_rounds (decision 2): JSON `null` ⇒ the flag was NOT passed ⇒ the field
  # is omitted and the line stays byte-identical to the pre-flag shape. When passed,
  # ONLY a string of ASCII digits survives; everything else (empty, `-1`, `1.5`,
  # `abc`) normalizes to 0. An explicit digit check, NOT a bare `tonumber? // 0`
  # (which would accept `-1` and `1.5`). Surrounding whitespace is trimmed first —
  # prefix/suffix parameter expansion only (bash 3.2-safe; never the O(n²)
  # `${var//[[:space:]]/}` global substitution), and INTERNAL whitespace (`"1 2"`)
  # still normalizes to 0.
  local shr_json="null"
  if [ "$shr_given" = "1" ]; then
    shr_raw="${shr_raw#"${shr_raw%%[![:space:]]*}"}"
    shr_raw="${shr_raw%"${shr_raw##*[![:space:]]}"}"
    case "$shr_raw" in
      ''|*[!0-9]*) shr_json="0" ;;
      *) shr_json="$( printf '%s' "$shr_raw" | "$JQ" -R 'tonumber? // 0' 2>/dev/null )"
         [ -n "$shr_json" ] || shr_json="0" ;;
    esac
  fi

  # DEGRADED-EMIT DESIGN — option (b): the idempotency key is degradation-aware.
  #
  # A line with `changed_paths: []` is PERMANENTLY INVISIBLE to read-postmortem.sh
  # (its overlap filter can never match an empty array). Before this, a FIRST emit
  # that degraded — the single `gh pr view --json files,...` fetch failed, or the
  # caller omitted the fetch args — poisoned the key and silently skipped every
  # later emit that DID carry the data. Silent invisibility is the exact failure
  # this feature exists to prevent.
  #
  # Fix: the key carries a `complete`|`degraded` discriminator, so a degraded line
  # does not block a later complete one. Exactly-once still holds per (key, state),
  # and at most ONE complete line is ever written per run/item/pr/source.
  #
  # Why not the alternatives:
  #   (a) supersede the degraded line via curate-postmortem.sh — unusable here. Its
  #       `target_key` matches a data line's `automate_key` OR `pr_url`, so a record
  #       aimed at the degraded line would ALSO hide the corrective line (same
  #       pr_url); and it is human-gated on --confirm, so it can never run inside
  #       the per-item loop. It stays the manual, human-driven curation path.
  #   (c) refuse to emit a degraded line at all — throws away the honest
  #       `review_rounds` / `self_heal_misses` churn signal on every fetch failure
  #       and breaks the documented always-emit fail-safe contract.
  #
  # The degraded line is left in place. It stays invisible to read-postmortem.sh
  # (empty changed_paths), but do NOT assume it is quarantined downstream: `repo` and
  # `number` are derived from pr_url INDEPENDENTLY of the fetch that degrades
  # (skills/automate-loop/SKILL.md §6), so a contract-compliant caller emits the
  # degraded line with the REAL number — `number: 0` only happens when --number is
  # omitted altogether. The degraded and corrective lines therefore SHARE the
  # repo#number key that build-loop-evidence.sh and measure-heal-signal.py join on.
  # Both pick floor-raising (max review_rounds, tie-break latest ts), so the richer
  # line wins and the pair cannot report a stale low count. Ledger stays append-only;
  # no new writer.
  # COMPLETE requires at least one NON-EMPTY path. An empty string is not a usable
  # path — read-postmortem.sh drops empty query paths before matching, so a
  # `changed_paths: [""]` line is just as invisible as `[]`. Classing it complete
  # would re-open this very defect: an unusable line blocking its own correction.
  local completeness="degraded"
  if printf '%s' "$cp_clean" | "$JQ" -e 'any(.[]; . != "")' >/dev/null 2>&1; then
    completeness="complete"
  fi

  # Deterministic idempotency key: run_id|item|pr_url|source|completeness joined on
  # the ASCII Unit Separator (U+001F, written as the \u001f jq escape — NOT an empty
  # join; a raw 0x1F byte renders invisibly in diffs/cat and reads as join("")). The
  # separator closes the boundary-ambiguity collision class (e.g. run_id="a",
  # item="bc" vs "ab","c" would collide under an empty join). Built jq-only so a
  # field containing spaces/quotes can't break the scan; U+001F never appears in a
  # repo slug / URL / run-id, so the join is exact.
  local base key
  base="$("$JQ" -rn --arg a "$run_id" --arg b "$item" --arg c "$pr_url" --arg d "$source" \
    '[$a,$b,$c,$d] | join("\u001f")' 2>/dev/null)"
  [ -n "$base" ] || return 0
  key="$("$JQ" -rn --arg b "$base" --arg s "$completeness" '[$b,$s] | join("\u001f")' 2>/dev/null)"
  [ -n "$key" ] || return 0

  # Idempotency skip. A "match" is an existing line whose automate_key is this base
  # (a LEGACY pre-discriminator line) or this base plus a discriminator suffix. Skip when:
  #   - an exact-key line already exists (plain re-entry). NOT redundant with the two
  #     arms below: they judge completeness from the line's OWN changed_paths, so a line
  #     whose key suffix and payload disagree (hand-edited, or a truncated write) would
  #     otherwise slip past and be appended twice. This arm keys on identity alone, OR
  #   - this emit is DEGRADED and any match exists  (never regress an existing good
  #     line, and never write a second invisible line), OR
  #   - this emit is COMPLETE and a complete match exists      (at most one good line;
  #     this arm also keeps a LEGACY complete line idempotent under the new key shape).
  # The one newly-permitted append is COMPLETE-after-DEGRADED — the correction.
  if [ -f "$ledger" ]; then
    if "$JQ" -R 'fromjson? // empty' "$ledger" 2>/dev/null \
         | "$JQ" -e -s --arg k "$key" --arg base "$base" --arg state "$completeness" '
             [ .[]
               | select(type == "object")
               | ((.automate_key // "") | if type == "string" then . else "" end) as $ak
               | select($ak == $base or ($ak | startswith($base + "\u001f")))
               # `complete` MUST use the same rule as the discriminator above (at least
               # one NON-EMPTY path), not merely `length > 0`. A `[""]` line is degraded
               # by the discriminator, so if this arm judged it complete it would block
               # the very correction the discriminator just permitted.
               | { ak: $ak,
                   complete: ((((.changed_paths // []) | type) == "array")
                              and ((.changed_paths // []) | any(.[]?; . != ""))) }
             ] as $m
             | ($m | any(.ak == $k))
               or (($state == "degraded") and (($m | length) > 0))
               or (($state == "complete") and ($m | any(.complete)))
           ' >/dev/null 2>&1; then
      return 0   # already recorded for this run/item/pr/source/state — exactly-once.
    fi
  fi

  # Build the record jq-only (--arg / --argjson ONLY — no string interpolation of
  # any PR-supplied text; injection-safe, same contract as pr-postmortem-gather.sh).
  # All churn logic (effective_review_rounds, the categories[] zero-rule,
  # self_heal_misses, flow_stages) is computed INSIDE jq so it is a single source
  # of truth and the zero-rule holds exactly.
  local line
  line="$("$JQ" -cn \
    --arg ts "$ts" \
    --arg repo "$repo" \
    --argjson number "$( printf '%s' "$number"      | "$JQ" -R 'tonumber? // 0' )" \
    --argjson fix_cycles "$( printf '%s' "$fix_cycles" | "$JQ" -R 'tonumber? // 0' )" \
    --arg drain_result "$drain_result" \
    --arg repeat_check_failure "$repeat_check_failure" \
    --arg unresolved_bot_feedback "$unresolved_bot_feedback" \
    --argjson additions "$( printf '%s' "$additions"      | "$JQ" -R 'tonumber? // 0' )" \
    --argjson deletions "$( printf '%s' "$deletions"      | "$JQ" -R 'tonumber? // 0' )" \
    --argjson changed_files "$( printf '%s' "$changed_files" | "$JQ" -R 'tonumber? // 0' )" \
    --arg summary "$summary" \
    --arg plugin_version "$plugin_version" \
    --arg pr_url "$pr_url" \
    --arg branch "$branch" \
    --arg source "$source" \
    --arg automate_key "$key" \
    --argjson cp_raw "$cp_clean" \
    --argjson shr "$shr_json" \
    '
    # changed_paths: keep only an array of strings, else [].
    ( if ($cp_raw | type) == "array" then ($cp_raw | map(select(type=="string"))) else [] end ) as $changed_paths
    # self_heal_misses ← 1 if repeat_check_failure OR unresolved_bot_feedback.
    | ( if ($repeat_check_failure == "true") or ($unresolved_bot_feedback == "true") then 1 else 0 end ) as $shm
    # effective_review_rounds — mirror the categories[] branch order exactly so the
    # two never disagree (and an unreachable negative fix_cycles clamps to 0/1, never
    # a negative review_rounds): fix_cycles>0 -> fix_cycles; else ESCALATED -> 1; else 0.
    | ( if $fix_cycles > 0 then $fix_cycles elif $drain_result == "ESCALATED" then 1 else 0 end ) as $err
    # categories[] zero-rule (read-postmortem counts each element as one round):
    #   fix_cycles>0           -> one drain_churn entry {round: fix_cycles}
    #   fix_cycles==0 ESCALATED -> one drain_escalation entry {round: 1}
    #   fix_cycles==0 non-esc  -> no drain entry (NEVER a synthetic one — no fake churn)
    # plus, BEFORE any drain entry, one self_heal_churn entry iff self_heal_rounds > 0.
    # So `categories: []` iff effective_review_rounds == 0 AND self_heal_rounds == 0
    # ($shr null = flag absent = 0).
    | ( if $shr == null then 0 else $shr end ) as $shrn
    | ( if $shrn > 0 then
          [ { round: $shrn, class: "self_heal_churn", self_heal_miss: false,
              flow_stage: "self_heal",
              evidence: ("Phase 4.5 self-heal, heal_iterations=" + ($shrn|tostring)) } ]
        else
          []
        end ) as $self_heal_categories
    | ( if $fix_cycles > 0 then
          [ { round: $fix_cycles, class: "drain_churn", self_heal_miss: ($shm > 0),
              flow_stage: "self_heal",
              evidence: ("until-mergeable drain, decision=" + (if $drain_result=="" then "READY" else $drain_result end) + ", fix_cycles=" + ($fix_cycles|tostring)) } ]
        elif $drain_result == "ESCALATED" then
          [ { round: 1, class: "drain_escalation", self_heal_miss: ($shm > 0),
              flow_stage: "self_heal",
              evidence: "until-mergeable drain escalated before any fix cycle" } ]
        else
          []
        end ) as $drain_categories
    | ($self_heal_categories + $drain_categories) as $categories
    # self_heal_rounds sits right after review_rounds, and ONLY when the flag was
    # passed — built by object concatenation so the flag-absent line keeps the exact
    # pre-flag key order (byte-identical, decision 2).
    | {
        schema_version: 1,
        ts: $ts,
        repo: $repo,
        number: $number,
        agent_generated_guess: true,
        review_rounds: $err
      }
      + (if $shr == null then {} else { self_heal_rounds: $shr } end)
      + {
        additions: $additions,
        deletions: $deletions,
        changed_files: $changed_files,
        categories: $categories,
        self_heal_misses: $shm,
        # flow_stages.self_heal counts DRAIN rounds only (decision 8).
        flow_stages: { launch_pad: 0, worker: 0, self_heal: $err, unknowable: 0 },
        summary: (if $summary == "" then
                    ("automate drain: " + (if $err==0 then "no churn" else (($err|tostring) + " round(s)") end)
                     + (if $shrn > 0 then ("; self-heal: " + ($shrn|tostring) + " round(s)") else "" end))
                  else $summary end),
        plugin_version: (if $plugin_version == "" then "unknown" else $plugin_version end),
        pr_url: (if $pr_url == "" then null else $pr_url end),
        branch: (if $branch == "" then null else $branch end),
        changed_paths: $changed_paths,
        brief_path: null,
        job_path: null,
        source: $source,
        automate_key: $automate_key
      }
    ' 2>/dev/null)"

  # If the record didn't build (jq error), degrade to a no-op rather than write junk.
  [ -n "$line" ] || return 0

  # Append atomically (append-only — never rewrite the ledger). Create dir best-effort.
  mkdir -p "$(dirname "$ledger")" 2>/dev/null
  printf '%s\n' "$line" >> "$ledger" 2>/dev/null

  return 0
}

# --------------------------------------------------------------------------- #
# §6 steps 1 & 5 — brief-repair (fail-SAFE, evidence-positive, ONE mover)
# --------------------------------------------------------------------------- #

# brief-repair <item> <pr_url>
#
# The engine-side seam for repairing a stranded brief on the strongest evidence
# there is: the engine itself watched the PR merge (its --auto-merge gate merged
# it at §6 step 5 SYNC, or RESUME reconcile found an item parked awaiting_merge
# now merged at §6 step 1). It re-reads merge state from the forge (evidence-
# POSITIVE: only `state == MERGED` or a non-empty `mergedAt` proceeds; every
# failure to read is a skip, never a repair) and then hands the evidence to the
# SIBLING `reconcile-jobs.sh --repair --porcelain --evidence <item>=<pr_url>`,
# which stays the ONE mover — this helper moves nothing itself. The reconciler
# scopes the repair to that key and refuses an ambiguous match (two in-progress
# briefs with the same pointer), so this helper cannot attribute a PR to a
# stranded earlier attempt.
#
# Prints EXACTLY one stdout line for the loop to `progress-append` verbatim:
#   brief-repair: repaired <brief_path> → <done_path> (<pr_url>)
#   brief-repair: skipped — <reason>
# Each gate has its own reason so the Progress line says WHICH gate stopped it.
#
# FAIL-SAFE (same posture as learning-emit): `set +e` first; ALWAYS returns 0;
# never die/abort; `set -u` stays on so every expansion carries a default.
# Never reads or writes the run file, never touches ## Queue / ## Current, and
# never calls `gh pr merge` (the sole executor stays gate-eval, §11).
# The reconciler is found by the plain `dirname "$0"` sibling lookup the scripts
# already use (this file is held at allowance 0 by check-vendor-coupling.sh).
brief_repair() {
  set +e   # FAIL-SAFE: always exit 0; never die/abort inside the per-item loop.

  local item="${1:-}" pr_url="${2:-}"
  if [ -z "$item" ] || [ -z "$pr_url" ]; then
    echo "brief-repair: skipped — missing argument"; return 0
  fi

  # (a′) lexical gate — belt-and-braces: the reconciler would ignore a junk
  # value anyway, but this keeps the forge call from ever being made for junk.
  local malformed=0
  case "$item" in
    /*|*..*)                     malformed=1 ;;
    .supervisor/requirements/?*) ;;
    *)                           malformed=1 ;;
  esac
  # Built-in ERE match, not `printf | grep -q`: under pipefail a `grep -q` can
  # fail via SIGPIPE even on a match (recorded trap).
  [[ "$pr_url" =~ ^https?://[^[:space:]]+/pull/[0-9]+$ ]] || malformed=1
  if [ "$malformed" -eq 1 ]; then
    echo "brief-repair: skipped — malformed item or pr_url"; return 0
  fi

  # (b)–(e) evidence-positive forge read.
  if ! command -v "$GH" >/dev/null 2>&1; then
    echo "brief-repair: skipped — gh unavailable"; return 0
  fi
  local view state merged
  view="$("$GH" pr view "$pr_url" --json state,mergedAt 2>/dev/null)"
  if [ $? -ne 0 ]; then
    echo "brief-repair: skipped — gh pr view failed"; return 0
  fi
  if ! printf '%s' "$view" | "$JQ" -e '.state' >/dev/null 2>&1; then
    echo "brief-repair: skipped — gh output unparseable"; return 0
  fi
  state="$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null)"
  merged="$(printf '%s' "$view" | "$JQ" -r '.mergedAt // empty' 2>/dev/null)"
  if [ "$state" != "MERGED" ] && [ -z "$merged" ]; then
    echo "brief-repair: skipped — PR not merged (state=${state:-unknown})"; return 0
  fi

  # (f) the sibling reconciler — the ONE mover.
  local recon
  recon="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/reconcile-jobs.sh"
  if [ ! -r "$recon" ]; then
    echo "brief-repair: skipped — reconciler unavailable"; return 0
  fi

  # (g) run it; stderr (refusal reasons) is discarded — the rows are the trace.
  local rows
  rows="$(bash "$recon" --repair --porcelain --evidence "${item}=${pr_url}" 2>/dev/null)"

  # (h) scan the rows in precedence order. Capture-then-test throughout: no
  # `producer | grep -q` (SIGPIPE under pipefail can fail it even on a match).
  local st path ev brief_hit="" amb_n="" refused=0
  while IFS=$'\t' read -r st path ev; do
    [ -n "${st:-}" ] || continue
    case "$st" in
      repaired)
        case "${ev:-}" in *"$pr_url"*) [ -n "$brief_hit" ] || brief_hit="$path" ;; esac ;;
      unknown)
        case "${ev:-}" in
          "ambiguous: "*" point at ${item} "*|"ambiguous: "*" point at ${item}")
            [ -n "$amb_n" ] || amb_n="$(printf '%s' "$ev" | sed -n 's/^ambiguous: \([0-9][0-9]*\) .*/\1/p')" ;;
        esac ;;
      stranded_merged)
        case "${ev:-}" in "automate engine supplied "*"$pr_url"*) refused=1 ;; esac ;;
    esac
  done <<EOF
$rows
EOF

  if [ -n "$brief_hit" ]; then
    echo "brief-repair: repaired ${brief_hit} → .supervisor/jobs/done/$(basename "$brief_hit") (${pr_url})"
  elif [ -n "$amb_n" ]; then
    echo "brief-repair: skipped — ambiguous match (${amb_n} briefs point at ${item})"
  elif [ "$refused" -eq 1 ]; then
    echo "brief-repair: skipped — reconciler refused the move (destination exists, ## Outcome present, or write failure — re-run reconcile-jobs.sh --repair --evidence <item>=<pr_url> by hand for the reason)"
  else
    echo "brief-repair: skipped — no in-progress brief matches ${item}"
  fi
  return 0
}

