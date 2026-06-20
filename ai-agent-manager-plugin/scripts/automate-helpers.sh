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
#   queue-checkoff   <runfile_path> <item> [reason]    # §3/§5 flip - [ ] -> - [x] (with optional "# skipped: reason")
#   remaining        <runfile_path>                     # §3 count of "- [ ]" lines only
#   resolve-folder   <dir>                              # §2 list *.md not "## Status: done"
#   resolve-backlog  <backlog.md>                       # §2 dependency-ordered items honoring done/✅ markers
#   resume-glob      <automate_dir>                     # §4 list *.md not "## Status: done"
#   reconcile-item   <pr_url> <belief>                  # §4 belief vs gh/git truth -> corrected state
#   gate-eval        <pr_url> <ctx.json>                # §10 MERGE|PARK 5-condition fail-closed gate
#
# Exit codes: 0 success; 1 generic failure; 2 abort (malformed pre-existing config, §7).

set -euo pipefail

JQ="${AI_AGENT_MANAGER_JQ_BIN:-jq}"
GH="${AI_AGENT_MANAGER_GH_BIN:-gh}"

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
  local v; v="$("$JQ" -r '.auto_review // "absent"' "$cfg")"
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

# queue-checkoff <runfile_path> <item> [reason]
# Flips "- [ ] <item>" to "- [x] <item>". With a reason, writes the skipped form
# "- [x] <item>  # skipped: <reason>" (§5). Atomic write. Idempotent on already-
# checked items (leaves them untouched).
queue_checkoff() {
  local out="$1" item="$2" reason="${3:-}"
  [ -f "$out" ] || die "run file not found: $out"
  local tmp; tmp="$(mktemp "${out}.XXXXXX")"
  # Pass item/reason via the ENVIRONMENT (not awk -v): -v interprets backslash
  # escapes in the value, which would mangle a path/reason containing a literal
  # backslash. ENVIRON[...] is read verbatim.
  AH_ITEM="$item" AH_REASON="$reason" awk '
    BEGIN { item=ENVIRON["AH_ITEM"]; reason=ENVIRON["AH_REASON"] }
    {
      line=$0
      # Match an unchecked queue line whose payload (after "- [ ] ") equals item.
      if (line ~ /^- \[ \] /) {
        payload=substr(line, 7)
        if (payload == item) {
          if (reason != "")
            print "- [x] " item "  # skipped: " reason
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
# checkbox without reconciling). `gh` is stubbable via the AI_AGENT_MANAGER_GH_BIN
# env override.
#
# SCOPE: this helper resolves the gh-PR-STATE half of reconcile only (merged /
# open / closed-unmerged). The complementary git-branch-LANDED corroboration that
# SKILL §4 lists ("Branch landed? `git branch --contains <sha>`") is performed by
# the loop itself, not here — wiring git into this helper would need stub fixtures
# out of scope for the pure-logic library. So this returning `merged`/`gone` is
# the gh half; it is NOT incomplete.
reconcile_item() {
  local url="$1" belief="${2:-}"
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
#     "review_decision": "APPROVED|CHANGES_REQUESTED|REVIEW_REQUIRED|null",  # cond 3
#     "unresolved_human_thread": true|false,        # cond 3
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
  local J; J() { "$JQ" -r "$1 // \"__MISSING__\"" "$ctx"; }

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

  # Condition 3 — reviewDecision clean (not CHANGES_REQUESTED/REVIEW_REQUIRED,
  # not null/unreadable) AND no unresolved human-authored review thread.
  local rd; rd="$(J '.review_decision')"
  case "$rd" in
    CHANGES_REQUESTED|REVIEW_REQUIRED)            echo "PARK: review_decision_blocking"; return 0 ;;
    __MISSING__|null|"")                          echo "PARK: review_decision_null"; return 0 ;;
  esac
  if [ "$(J '.unresolved_human_thread')" = "true" ]; then
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
    ""|-h|--help)
      grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
