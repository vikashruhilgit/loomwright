#!/usr/bin/env bash
# automate-helpers.sh — pure, deterministic, testable helpers for the `/automate`
# generic automation engine. The PROTOCOL AUTHORITY is
# `skills/automate-loop/SKILL.md` — every contract implemented here conforms to a
# named section there (§ refs in each subcommand's comment). The run-file layout
# matches `docs/RESULT_SCHEMAS.md §AUTOMATE_RUN` and the brief's "The run file
# (the contract)" template.
#
# This script is a library of SUBCOMMANDS the inline `/automate` loop shells out
# to (wired in `skills/automate-loop/SKILL.md` §1.5 + the inline "execute via
# automate-helpers.sh" pointers at §3/§4/§7/§10, and referenced from
# `commands/automate.md`) for the few pieces of logic that benefit from being
# scriptable + self-tested (config suppress/restore, atomic run-file writes,
# append-only Progress, resume reconcile, the trusted auto-merge gate) — so the
# TESTED code is the EXECUTED code (one implementation, not a prose re-spec). It
# is READ-ONLY toward the work it
# drives — it never edits source repos, never runs git mutations of its own, and
# (outside the explicitly-stubbed `gate-eval` MERGE branch) never calls
# `gh pr merge`. UNCOUNTED by the doc-currency gate (it is a plain script, not an
# agent/command/skill/hook).
#
# Subcommands:
#   config-suppress  <config_path> <backup_path>      # §7 backup byte-for-byte, set auto_review=false; malformed ⇒ abort
#   config-restore   <config_path> <backup_path>      # §7 overwrite-from-backup OR delete-if-absent; deletes backup
#   config-orig      <config_path>                     # §7 prints true|false|absent (the recorded auto_review_original)
#   runfile-write    <runfile_path> < CONTENT          # §3 atomic temp+rename write
#   progress-append  <runfile_path> <line>             # §3 append-only ## Progress (never rewrites prior lines)
#   queue-checkoff   <runfile_path> <item> [reason] [mark]  # §3/§5 flip - [ ] -> - [x] (optional "# <skipped|abandoned>: reason"; mark default skipped)
#   remaining        <runfile_path>                     # §3 count of "- [ ]" lines only
#   resolve-folder   <dir>                              # §2 list *.md not "## Status: done"
#   resolve-backlog  <backlog.md>                       # §2 dependency-ordered items honoring done/✅ markers
#   resume-glob      <automate_dir>                     # §4 list *.md not "## Status: done"
#   reconcile-item   <pr_url> <belief>                  # §4 belief vs gh/git truth -> corrected state
#   gate-eval        <pr_url> <ctx.json>                # §10 MERGE|PARK 5-condition fail-closed gate
#   learning-emit    <ledger_path> <flags...>           # §6 step 3 fail-safe (always exit 0) engine-native ground-truth POSTMORTEM_RESULT line; idempotent on run_id+item+pr_url+source
#
# Exit codes: 0 success; 1 generic failure; 2 abort (malformed pre-existing config, §7).
# (learning-emit is the fail-SAFE exception: it ALWAYS exits 0 — never die/abort.)

set -euo pipefail

JQ="${LOOMWRIGHT_JQ_BIN:-jq}"
GH="${LOOMWRIGHT_GH_BIN:-gh}"

die()   { echo "automate-helpers: $*" >&2; exit 1; }
abort() { echo "automate-helpers: ABORT: $*" >&2; exit 2; }

# --------------------------------------------------------------------------- #
# §7 — config suppress / restore (byte-for-byte; absent-delete; malformed-abort)
# --------------------------------------------------------------------------- #

# config-suppress <config_path> <backup_path>
# Backs up an existing config byte-for-byte to <backup_path>, then writes a config
# with .auto_review=false. If the config is ABSENT, no backup is made (absence is
# recorded by config-restore's marker semantics) and a minimal {"auto_review":false}
# is written. A MALFORMED pre-existing config ⇒ ABORT (exit 2) — never clobber a
# hand-edited config (SKILL §7 "malformed-abort"; Anti-Pattern).
config_suppress() {
  local cfg="$1" bak="$2"
  if [ -f "$cfg" ]; then
    # Validate JSON before touching anything.
    if ! "$JQ" -e . "$cfg" >/dev/null 2>&1; then
      abort "pre-existing config is not valid JSON: $cfg"
    fi
    # Byte-for-byte backup (cp preserves exact bytes).
    cp "$cfg" "$bak"
    # Merge auto_review=false into the existing object (atomic temp+rename).
    local tmp; tmp="$(mktemp "${cfg}.XXXXXX")"
    "$JQ" '.auto_review = false' "$cfg" > "$tmp"
    mv -f "$tmp" "$cfg"
  else
    # Originally absent: write a marker backup so restore knows to DELETE on restore.
    printf '__ABSENT__\n' > "$bak"
    printf '{"auto_review":false}\n' > "$cfg"
  fi
}

# config-restore <config_path> <backup_path>
# Restores config from the backup, OR DELETES config if it was originally absent
# (backup holds the __ABSENT__ marker). Deletes the transient backup on success.
# Never leaves a partial config.json (SKILL §7 "absent-delete").
config_restore() {
  local cfg="$1" bak="$2"
  [ -f "$bak" ] || die "no backup to restore: $bak"
  if [ "$(head -n1 "$bak")" = "__ABSENT__" ]; then
    rm -f "$cfg"
  else
    # Atomic restore (temp+rename) so a crash mid-restore can't half-write.
    local tmp; tmp="$(mktemp "${cfg}.XXXXXX")"
    cp "$bak" "$tmp"
    mv -f "$tmp" "$cfg"
  fi
  rm -f "$bak"
}

# config-orig <config_path>
# Prints the auto_review_original value to record in ## Run Config: true|false|absent.
config_orig() {
  local cfg="$1"
  if [ ! -f "$cfg" ]; then echo "absent"; return 0; fi
  if ! "$JQ" -e . "$cfg" >/dev/null 2>&1; then abort "pre-existing config is not valid JSON: $cfg"; fi
  # NB: use an explicit null/has() check, NOT `.auto_review // "absent"` — the `//`
  # operator is FALSY-triggered, so a genuine `false` would collapse to "absent",
  # making a recorded false original indistinguishable from no config (the same
  # falsy-coercion hazard documented in gate_eval §10). Emit true|false|absent
  # faithfully so ## Run Config records the real original.
  local v; v="$("$JQ" -r 'if has("auto_review") and (.auto_review != null) then .auto_review else "absent" end' "$cfg")"
  echo "$v"
}

# --------------------------------------------------------------------------- #
# §3 — run-file atomic write + append-only Progress + queue check-off
# --------------------------------------------------------------------------- #

# runfile-write <runfile_path>   (content on stdin)
# Atomic write: stage to a temp file in the same dir, then rename into place.
runfile_write() {
  local out="$1" dir tmp
  dir="$(dirname "$out")"
  mkdir -p "$dir"
  tmp="$(mktemp "${out}.XXXXXX")"
  cat > "$tmp"
  mv -f "$tmp" "$out"
}

# progress-append <runfile_path> <line>
# Appends ONE line under "## Progress" WITHOUT rewriting any existing line. We
# rebuild the file via atomic write but the prior Progress lines are copied
# verbatim and the new line is inserted at the END of the Progress block — the
# invariant tested is "no prior Progress line is ever altered or dropped".
progress_append() {
  local out="$1" line="$2"
  [ -f "$out" ] || die "run file not found: $out"
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  # Pass the new line via the ENVIRONMENT (not awk -v): awk's -v assignment
  # interprets backslash escapes in the value, which would mangle a path/line
  # containing a literal backslash. ENVIRON[...] is read verbatim.
  AH_NEWLINE="- $line" awk '
    BEGIN { in_prog=0; appended=0; seen_prog=0; newline=ENVIRON["AH_NEWLINE"] }
    /^## Progress/ { print; in_prog=1; seen_prog=1; next }
    /^## / {
      if (in_prog && !appended) { print newline; appended=1; in_prog=0 }
      print; next
    }
    { print }
    # Fallback: if the run file had NO "## Progress" section, create one rather
    # than silently dropping the event (defensive — the template always includes
    # the section, but a malformed file must not lose progress lines).
    END {
      if (!appended) {
        if (!seen_prog) print "## Progress"
        print newline
      }
    }
  ' "$out" > "$tmp"
  mv -f "$tmp" "$out"
}

# queue-checkoff <runfile_path> <item> [reason] [mark]
# Flips "- [ ] <item>" to "- [x] <item>". With a reason, writes the excluded form
# "- [x] <item>  # <mark>: <reason>" where <mark> is "skipped" (default) or
# "abandoned" (§5 — both are checked-off so the item is never re-picked and does not
# block ## Status: done). Atomic write. Idempotent on already-checked items
# (leaves them untouched).
queue_checkoff() {
  local out="$1" item="$2" reason="${3:-}" mark="${4:-skipped}"
  case "$mark" in skipped|abandoned) ;; *) die "queue-checkoff: mark must be skipped|abandoned (got '$mark')" ;; esac
  [ -f "$out" ] || die "run file not found: $out"
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  # Pass item/reason via the ENVIRONMENT (not awk -v): -v interprets backslash
  # escapes in the value, which would mangle a path/reason containing a literal
  # backslash. ENVIRON[...] is read verbatim.
  AH_ITEM="$item" AH_REASON="$reason" AH_MARK="$mark" awk '
    BEGIN { item=ENVIRON["AH_ITEM"]; reason=ENVIRON["AH_REASON"]; mark=ENVIRON["AH_MARK"] }
    {
      line=$0
      # Match an unchecked queue line whose payload (after "- [ ] ") equals item.
      if (line ~ /^- \[ \] /) {
        payload=substr(line, 7)
        if (payload == item) {
          if (reason != "")
            print "- [x] " item "  # " mark ": " reason
          else
            print "- [x] " item
          next
        }
      }
      print line
    }
  ' "$out" > "$tmp"
  mv -f "$tmp" "$out"
}

# remaining <runfile_path>
# Counts ONLY unchecked "- [ ]" lines (skipped/checked items excluded), so a
# skipped item never blocks ## Status: done (§3/§5).
remaining() {
  local out="$1"
  [ -f "$out" ] || die "run file not found: $out"
  grep -c '^- \[ \] ' "$out" || true
}

# --------------------------------------------------------------------------- #
# §2 — folder / backlog-doc resolvers
# --------------------------------------------------------------------------- #

# is_done <file> — true if the file is stamped "## Status: done".
is_done() { grep -qE '^## Status:[[:space:]]*done\b' "$1" 2>/dev/null; }

# resolve-folder <dir> — every *.md NOT marked "## Status: done" (sorted).
resolve_folder() {
  local dir="$1" f
  [ -d "$dir" ] || die "folder not found: $dir"
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_done "$f" && continue
    echo "$f"
  done | LC_ALL=C sort
}

# resolve-backlog <backlog.md> — emit items in DOCUMENTED build order, honoring
# done/✅ markers. We parse "- [ ] <path>" / "- [x] <path>" checklist lines (the
# documented order = file order) and emit only the not-done ones. A line carrying
# "## Status: done" inline, a "✅" marker, or a checked "[x]" box is treated as
# ground-truth done and excluded. _BACKLOG.md-absent ⇒ fall back to dir scan.
resolve_backlog() {
  local doc="$1"
  if [ ! -f "$doc" ]; then
    # Fallback: scan the directory the path points into by ## Status: stamp.
    local d; d="$(dirname "$doc")"
    [ -d "$d" ] && resolve_backlog_dir "$d"
    return 0
  fi
  # Preserve documented order; emit not-done checklist items.
  while IFS= read -r line; do
    case "$line" in
      "- [x] "*|"- [X] "*) continue ;;          # checked ⇒ done
      "- [ ] "*)
        # NOTE: '[' and ']' are glob metachars in parameter-expansion patterns,
        # so strip the fixed 6-char "- [ ] " prefix by offset, not by '#- [ ] '.
        local payload="${line:6}"
        case "$payload" in
          *"✅"*) continue ;;                    # explicit done marker
          *"# Status: done"*|*"## Status: done"*) continue ;;
        esac
        # strip any trailing inline comment / marker, keep the item token
        payload="${payload%%  #*}"
        echo "$payload"
        ;;
    esac
  done < "$doc"
}

# resolve_backlog_dir <dir> — fallback ordering by directory order over *.md,
# excluding ## Status: done files.
resolve_backlog_dir() {
  local dir="$1" f
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_done "$f" && continue
    echo "$f"
  done | LC_ALL=C sort
}

# --------------------------------------------------------------------------- #
# §4 — resume: glob + reconcile (run-file is BELIEF; git/gh is TRUTH)
# --------------------------------------------------------------------------- #

# resume-glob <automate_dir> — list run files NOT marked "## Status: done".
resume_glob() {
  local dir="$1" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_done "$f" && continue
    echo "$f"
  done | LC_ALL=C sort
}

# reconcile-item <pr_url> <belief> — reconcile a single in-flight item's BELIEF
# (the checkbox/Current status the run file remembers) against GROUND TRUTH via
# gh/git. Prints the CORRECTED state, one of:
#   merged          — PR is MERGED (gh state==MERGED or mergedAt non-null);
#                     item should be "- [x]" regardless of what the file believed.
#   awaiting_merge  — PR is OPEN/unmerged; item stays awaiting_merge even if the
#                     file believed it checked (a premature check-off).
#   gone            — PR is CLOSED-unmerged (neither merged nor open).
# Reconcile ALWAYS prefers ground truth (SKILL §4 / Anti-Pattern: never trust a
# checkbox without reconciling). `gh` is stubbable via the LOOMWRIGHT_GH_BIN
# env override.
#
# SCOPE: this helper resolves the gh-PR-STATE half of reconcile only (merged /
# open / closed-unmerged). The complementary git-branch-LANDED corroboration that
# SKILL §4 lists ("Branch landed? `git branch --contains <sha>`") is performed by
# the loop itself, not here — wiring git into this helper would need stub fixtures
# out of scope for the pure-logic library. So this returning `merged`/`gone` is
# the gh half; it is NOT incomplete.
reconcile_item() {
  # <belief> is accepted for call-site symmetry with the run file's remembered
  # status (SKILL §1.5 signature) but is INTENTIONALLY IGNORED — ground truth
  # (gh/git) always wins (SKILL §4), so it never influences the result.
  local url="$1" belief="${2:-}"
  : "${belief:-}"   # referenced only to mark it deliberately unused
  local view state merged
  if ! view="$("$GH" pr view "$url" --json state,mergedAt 2>/dev/null)"; then
    # Unreadable ⇒ fail closed to the safe non-merged belief.
    echo "awaiting_merge"; return 0
  fi
  state="$(printf '%s' "$view" | "$JQ" -r '.state // empty' 2>/dev/null || true)"
  merged="$(printf '%s' "$view" | "$JQ" -r '.mergedAt // empty' 2>/dev/null || true)"
  if [ "$state" = "MERGED" ] || [ -n "$merged" ]; then
    echo "merged"; return 0
  fi
  if [ "$state" = "OPEN" ]; then
    echo "awaiting_merge"; return 0
  fi
  # CLOSED-unmerged or unknown.
  echo "gone"
}

# --------------------------------------------------------------------------- #
# §10 — trusted auto-merge gate (5 conditions, fail CLOSED)
# --------------------------------------------------------------------------- #

# gate-eval <pr_url> <ctx.json>
# Pure decision over a context JSON describing the 5 conditions. Prints "MERGE"
# and EXECUTES `gh pr merge --squash <url>` ONLY when ALL 5 hold; otherwise prints
# "PARK: <reason>" and returns 0 (a PARK is a normal, expected outcome — fail
# CLOSED, never crash). The `gh` calls behind each condition are pre-resolved into
# ctx.json by the caller (the loop), which is exactly what the test stubs.
#
# ctx.json shape (all fields read defensively; any missing/null ⇒ that condition
# fails closed):
#   {
#     "drain_result": "READY|ESCALATED",          # cond 1
#     "ready_sha": "<sha>", "head_sha": "<sha>",   # cond 2
#     "base": "main",                               # cond 2
#     "review_decision": "APPROVED|CHANGES_REQUESTED|REVIEW_REQUIRED|none|unreadable",  # cond 3
#        # "none" = reviews-not-required (the loop maps a successfully-read null here);
#        # "unreadable" = the gh reviewDecision read failed. Bare null/absent ⇒ fail-closed PARK.
#     "unresolved_human_thread": true|false,        # cond 3 — loop passes `false` ONLY on a
#        # SUCCESSFULLY-read no-unresolved-human-thread result; an unresolved human thread OR an
#        # unreadable/errored thread read ⇒ pass `true` (or omit) ⇒ fail-closed PARK (`!= "false"`).
#     "protection_enforceable": true|false,         # cond 4
#     "trust_unprotected": true|false,              # cond 4 override
#     "checks_green": true|false,                   # cond 5
#     "rubric_satisfied": true|"na"|false           # cond 5 (na = no rubric ⇒ not a blocker)
#   }
gate_eval() {
  local url="$1" ctx="$2"
  [ -f "$ctx" ] || die "ctx not found: $ctx"
  if ! "$JQ" -e . "$ctx" >/dev/null 2>&1; then
    echo "PARK: ctx_unreadable"; return 0
  fi
  # FAIL-CLOSED CONVENTION (do not break): every condition below tests `!= "true"`
  # (or an affirmative-string match), so this jq `// "__MISSING__"` default is safe
  # EVEN THOUGH it coerces a JSON `false` to "__MISSING__" — a coerced value is
  # never == "true", so it parks. NEVER add a condition written as `= "false"`:
  # the falsy-coercion would make it silently never fire (fail OPEN). Keep all new
  # conditions in the affirmative `!= "true"` ⇒ PARK form.
  # NB: a bash function definition is always global — there is no `local` function
  # scoping — so J() lives until gate_eval returns and the next call redefines it;
  # no `local J` (which would only declare an unused local var of that name).
  J() { "$JQ" -r "$1 // \"__MISSING__\"" "$ctx"; }

  # Condition 1 — owned drain == READY.
  if [ "$(J '.drain_result')" != "READY" ]; then
    echo "PARK: drain_not_ready"; return 0
  fi

  # Condition 2 — head SHA unchanged AND base == main.
  local ready_sha head_sha base
  ready_sha="$(J '.ready_sha')"; head_sha="$(J '.head_sha')"; base="$(J '.base')"
  if [ "$ready_sha" = "__MISSING__" ] || [ "$head_sha" = "__MISSING__" ] || [ "$ready_sha" != "$head_sha" ]; then
    echo "PARK: head_sha_moved"; return 0
  fi
  if [ "$base" != "main" ]; then
    echo "PARK: base_not_main"; return 0
  fi

  # Condition 3 — reviewDecision not blocking AND no unresolved human thread.
  #   CHANGES_REQUESTED / REVIEW_REQUIRED        → PARK (a review is required or negative).
  #   APPROVED, or "none" (reviews-not-required, i.e. a SUCCESSFULLY-read null
  #     reviewDecision — the branch does not require approving reviews)
  #                                              → NOT a cond-3 blocker. Whether an
  #     unprotected / checks-only branch may actually merge is cond 4's call
  #     (protection_enforceable OR --trust-unprotected). This is the fix that makes
  #     --trust-unprotected and the checks-only-protection arm of cond 4 REACHABLE —
  #     previously a null reviewDecision parked here before cond 4 ever ran.
  #   anything else (unreadable / __MISSING__ / null / "" / unrecognized)
  #                                              → PARK (fail-CLOSED; reviewDecision is unknown).
  # LOAD-BEARING LOOP CONTRACT (mirrors the rubric "na" rule, §10 cond 5): the loop MUST
  # map a successfully-read null reviewDecision to the literal string "none" (NEVER bare
  # JSON null/absent, which J() coerces to __MISSING__ → fail-closed PARK), and pass
  # "unreadable" only when the `gh pr view --json reviewDecision` read actually failed.
  # So "reviews-not-required" merges (subject to cond 4) while a genuinely-unknown
  # reviewDecision still fails closed.
  local rd; rd="$(J '.review_decision')"
  case "$rd" in
    CHANGES_REQUESTED|REVIEW_REQUIRED)   echo "PARK: review_decision_blocking"; return 0 ;;
    APPROVED|none)                       : ;;   # acceptable — defer protection judgment to cond 4
    *)                                   echo "PARK: review_decision_unreadable"; return 0 ;;
  esac
  # FAIL-CLOSED — PARK unless the loop EXPLICITLY passed a readable, non-null `false`.
  # Read WITHOUT the falsy-coercing `//` (J() would map a legitimate `false` to
  # __MISSING__ — the same trap config_orig avoids), using an explicit has()/null
  # check so we can distinguish a real `false` (proceed) from missing/null (PARK).
  # Missing / null / unreadable / `true` ⇒ PARK: an unresolved human thread OR an
  # unreadable GraphQL thread read must NEVER merge (SKILL §10 cond 3, "Unreadable ⇒
  # do-not-merge"; CLAUDE.md bimodal fail-closed invariant). The prior `= "true"`
  # form was a fail-OPEN polarity bug (a missing value merged).
  local uht
  uht="$("$JQ" -r 'if has("unresolved_human_thread") and (.unresolved_human_thread != null) then (.unresolved_human_thread|tostring) else "__MISSING__" end' "$ctx")"
  if [ "$uht" != "false" ]; then
    echo "PARK: unresolved_human_thread"; return 0
  fi

  # Condition 4 — enforceable branch protection OR --trust-unprotected.
  local prot trust
  prot="$(J '.protection_enforceable')"; trust="$(J '.trust_unprotected')"
  if [ "$prot" != "true" ] && [ "$trust" != "true" ]; then
    echo "PARK: unprotected_branch"; return 0
  fi

  # Condition 5 — required checks green AND rubric satisfied (na = not a blocker).
  if [ "$(J '.checks_green')" != "true" ]; then
    echo "PARK: checks_not_green"; return 0
  fi
  local rub; rub="$(J '.rubric_satisfied')"
  if [ "$rub" != "true" ] && [ "$rub" != "na" ]; then
    echo "PARK: rubric_unsatisfied"; return 0
  fi

  # ALL 5 hold — the ONLY sanctioned `gh pr merge --squash` in the plugin (§11).
  if "$GH" pr merge --squash "$url" >/dev/null 2>&1; then
    echo "MERGE"; return 0
  fi
  echo "PARK: merge_command_failed"; return 0
}

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
#   [--branch <b>] [--source <s>]
#
# FAIL-SAFE: this is the ONE subcommand that must NEVER die/abort — it runs inside
# the per-item loop as an advisory side-effect and a failure must NEVER gate the
# engine. We `set +e` at the top (this lib is `set -euo pipefail`) so any failing
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
      *)                         shift ;;   # unknown flag: ignore, never fatal
    esac
  done

  # jq-absent guard: degrade to no-op (NO write) if jq isn't runnable.
  command -v "$JQ" >/dev/null 2>&1 || return 0

  [ -n "$source" ] || source="automate_drain"
  [ -n "$ts" ] || ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  [ -n "$changed_paths_json" ] || changed_paths_json="[]"

  # Deterministic idempotency key: run_id|item|pr_url|source joined on the ASCII
  # Unit Separator (U+001F, written as the \u001f jq escape — NOT an empty join;
  # a raw 0x1F byte renders invisibly in diffs/cat and reads as join("")). The
  # separator closes the boundary-ambiguity collision class (e.g. run_id="a",
  # item="bc" vs "ab","c" would collide under an empty join). Built jq-only so a
  # field containing spaces/quotes can't break the scan; U+001F never appears in a
  # repo slug / URL / run-id, so the join is exact.
  local key
  key="$("$JQ" -rn --arg a "$run_id" --arg b "$item" --arg c "$pr_url" --arg d "$source" \
    '[$a,$b,$c,$d] | join("\u001f")' 2>/dev/null)"
  [ -n "$key" ] || return 0

  # Idempotency skip: if any existing ledger line already carries this key, no-op.
  if [ -f "$ledger" ]; then
    if "$JQ" -R 'fromjson? // empty' "$ledger" 2>/dev/null \
         | "$JQ" -e -s --arg k "$key" 'any(.[]; .automate_key == $k)' >/dev/null 2>&1; then
      return 0   # already recorded for this run/item/pr/source — exactly-once.
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
    --argjson cp_raw "$( printf '%s' "$changed_paths_json" | "$JQ" -c 'if type=="array" then . else [] end' 2>/dev/null || echo '[]' )" \
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
    #   fix_cycles==0 non-esc  -> [] (NEVER a synthetic entry — no fake churn)
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
        end ) as $categories
    | {
        schema_version: 1,
        ts: $ts,
        repo: $repo,
        number: $number,
        agent_generated_guess: true,
        review_rounds: $err,
        additions: $additions,
        deletions: $deletions,
        changed_files: $changed_files,
        categories: $categories,
        self_heal_misses: $shm,
        flow_stages: { launch_pad: 0, worker: 0, self_heal: $err, unknowable: 0 },
        summary: (if $summary == "" then ("automate drain: " + (if $err==0 then "no churn" else (($err|tostring) + " round(s)") end)) else $summary end),
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
# dispatch
# --------------------------------------------------------------------------- #

main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    config-suppress) config_suppress "$@" ;;
    config-restore)  config_restore "$@" ;;
    config-orig)     config_orig "$@" ;;
    runfile-write)   runfile_write "$@" ;;
    progress-append) progress_append "$@" ;;
    queue-checkoff)  queue_checkoff "$@" ;;
    remaining)       remaining "$@" ;;
    resolve-folder)  resolve_folder "$@" ;;
    resolve-backlog) resolve_backlog "$@" ;;
    resume-glob)     resume_glob "$@" ;;
    reconcile-item)  reconcile_item "$@" ;;
    gate-eval)       gate_eval "$@" ;;
    learning-emit)   learning_emit "$@" ;;
    ""|-h|--help)
      grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
