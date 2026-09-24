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
# `gh pr merge` — and `brief-repair`, whose only write is the brief lifecycle
# move performed by `reconcile-jobs.sh --repair` under `.supervisor/jobs/`,
# never a source-repo or git mutation. UNCOUNTED by the doc-currency gate (it is
# a plain script, not an agent/command/skill/hook).
#
# Subcommands:
#   config-suppress  <config_path> <backup_path>      # §7 backup byte-for-byte, set auto_review=false; malformed ⇒ abort
#   config-restore   <config_path> <backup_path>      # §7 overwrite-from-backup OR delete-if-absent; deletes backup
#   config-orig      <config_path> [<backup_path>]     # §7 prints true|false|absent (the ORIGINAL auto_review); pass the backup once suppress has run
#   runfile-write    <runfile_path> < CONTENT          # §3 atomic temp+rename write
#   progress-append  <runfile_path> <line>             # §3 append-only ## Progress (never rewrites prior lines)
#   queue-checkoff   <runfile_path> <item> [reason] [mark]  # §3/§5 flip - [ ] -> - [x] (optional "# <skipped|abandoned>: reason"; mark default skipped)
#   remaining        <runfile_path>                     # §3 count of "- [ ]" lines only
#   ceiling-check    <runfile_path> <max_tokens> [--root <checkout>]  # §6 PICK-time token-ceiling check via read-token-ledger.sh --run-id; prints OK/PARK, always exits 0
#   resolve-folder   <dir>                              # §2 list *.md not done and not proposed|parked
#   resolve-backlog  <backlog.md>                       # §2 dependency-ordered items honoring done/✅ markers (dir-fallback path also skips proposed|parked, per is_not_ready)
#   resume-glob      <automate_dir>                     # §4 list *.md not "## Status: done"
#   reconcile-item   <pr_url> <belief>                  # §4 belief vs gh/git truth -> corrected state
#   gate-eval        <pr_url> <ctx.json>                # §10 MERGE|PARK 6-condition fail-closed gate (cond 6 = classify-risk.sh high_risk, NO override)
#   learning-emit    <ledger_path> <flags...>           # §6 step 3 fail-safe (always exit 0) engine-native ground-truth POSTMORTEM_RESULT line; idempotent on run_id+item+pr_url+source+completeness (a degraded emit never blocks a later complete one)
#   brief-repair     <item> <pr_url>                    # §6 steps 1/5 fail-safe (always exit 0) evidence-positive brief lifecycle repair: `gh pr view` says MERGED (or a non-empty mergedAt) ⇒ sibling reconcile-jobs.sh --repair --evidence <item>=<pr_url>; prints ONE line for ## Progress
#   reconcile-status <requirements_root> [--apply]      # queue-hygiene/01: dry-run-default requirement `## Status:` reconciler — a `pending`/absent-status *.md under <requirements_root> (skips `00-*`, `_*`, `README*`, `operator-run/`) whose PR is MERGED (state via reconcile-item) and whose body cites the file's repo-relative path, OR whose head branch matches the slug on its `.supervisor/jobs/done/` brief, is stamped the §6 shape byte-for-byte; a `.supervisor/automate/*.md` Queue row carrying `# abandoned:` and naming a requirement stamps `done_with_escalation — ABANDONED (<row verbatim>)`; NEVER downgrades an existing `done`/`done_with_escalation`; prints one `plan\t…` row per file it WOULD stamp (or `stamped\t…` under `--apply`) plus one `info\t…` row per `brief-shipped` file (never promoted); writes nothing without `--apply`.
#
# Exit codes: 0 success; 1 generic failure; 2 abort (malformed pre-existing config, §7).
# (learning-emit, brief-repair and reconcile-status are the fail-SAFE exceptions: they ALWAYS exit 0 — never die/abort.)

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

# config-orig <config_path> [<backup_path>]
# Prints the auto_review_original value to record in ## Run Config: true|false|absent.
#
# CALL-ORDER (§7): the contract sequence is backup -> suppress -> record, so this is
# normally called AFTER config_suppress has rewritten the live config to
# auto_review:false — at which point the LIVE file reports "false" for every original
# and only the byte-for-byte backup still holds the truth. So when <backup_path>
# exists we read THE BACKUP; otherwise we fall back to the live config (the
# pre-suppress call order, where the live config IS the original). The answer is
# therefore the same in either call order. Losing the true/false/absent distinction
# by reading the wrong FILE would defeat the same care the value-extraction below
# takes to avoid losing it by using the wrong OPERATOR.
#
# A backup path that is GIVEN but MISSING falls back to the live config; it does NOT
# abort the way a MALFORMED backup does (they are different kinds of event: malformed
# can never be legitimate, missing is the normal state of a correct PRE-suppress 2-arg
# call, and aborting on it would re-introduce call-order dependence in the other
# direction). The residual: if the backup is lost AFTER suppress (stale/reused run_id,
# partial cleanup, a race with a concurrent restore) the fallback reports the SUPPRESSED
# value as the original. The helper cannot distinguish that from the pre-suppress call —
# both are "2 args, no backup on disk" — so only the CALLER can prevent it, by recording
# the original before deleting the backup. Both arms pinned in test §A7f; SKILL.md §7.
config_orig() {
  local cfg="$1" bak="${2:-}" src
  if [ -n "$bak" ] && [ -f "$bak" ]; then
    # The __ABSENT__ marker means there was no pre-existing config at suppress time.
    if [ "$(head -n1 "$bak")" = "__ABSENT__" ]; then echo "absent"; return 0; fi
    src="$bak"
  else
    src="$cfg"
  fi
  if [ ! -f "$src" ]; then echo "absent"; return 0; fi
  if ! "$JQ" -e . "$src" >/dev/null 2>&1; then abort "config to read the original from is not valid JSON: $src"; fi
  # NB: use an explicit null/has() check, NOT `.auto_review // "absent"` — the `//`
  # operator is FALSY-triggered, so a genuine `false` would collapse to "absent",
  # making a recorded false original indistinguishable from no config (the same
  # falsy-coercion hazard documented in gate_eval §10). Emit true|false|absent
  # faithfully so ## Run Config records the real original.
  local v; v="$("$JQ" -r 'if has("auto_review") and (.auto_review != null) then .auto_review else "absent" end' "$src")"
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

# ceiling-check <runfile_path> <max_tokens> [--root <checkout>]
# §6 step 1 PICK-time token ceiling. Sums the run's ledger via
# `read-token-ledger.sh --run-id <runfile>` (§1.5) and compares its TOTAL
# against <max_tokens>. Always prints exactly ONE line and returns 0 (a PARK
# is a normal, expected outcome here — same fail-CLOSED-but-never-crash
# convention gate_eval already uses, never a shell failure the caller has to
# special-case):
#   "OK total=<n> max=<n>"                          — under the ceiling, proceed
#   "PARK: token_ceiling total=<n> max=<n>"          — strictly exceeding the ceiling (total > max; exactly at max is OK)
#   "PARK: ledger_unreadable"                        — reader could not sum anything
# This is the load-bearing seam mutation-control targets (test-automate-helpers.sh
# §"ceiling-check"): a ledger reader that always reports 0 real tokens must
# never let this print "OK" when the true spend is over <max_tokens>.
ceiling_check() {
  local out="$1" max="$2" root=""
  shift 2 2>/dev/null || true
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) root="${2:-.}"; shift 2 2>/dev/null || shift ;;
      *) shift ;;
    esac
  done
  [ -f "$out" ] || die "run file not found: $out"
  case "$max" in
    ''|*[!0-9]*) die "ceiling-check: max_tokens must be a non-negative integer (got '$max')" ;;
  esac
  local reader="$(dirname "$0")/read-token-ledger.sh"
  local args=(--run-id "$out")
  [ -n "$root" ] && args+=(--root "$root")
  local ledger_out=""
  if [ -x "$reader" ] || [ -f "$reader" ]; then
    ledger_out="$(bash "$reader" "${args[@]}" 2>/dev/null || true)"
  fi
  if [ -z "$ledger_out" ] || printf '%s' "$ledger_out" | grep -q 'LEDGER_UNREADABLE=1'; then
    echo "PARK: ledger_unreadable"
    return 0
  fi
  local total
  total="$(printf '%s' "$ledger_out" | grep -oE 'TOTAL=[0-9]+' | head -1 | cut -d= -f2)"
  if [ -z "$total" ]; then
    echo "PARK: ledger_unreadable"
    return 0
  fi
  if [ "$total" -gt "$max" ]; then
    echo "PARK: token_ceiling total=${total} max=${max}"
    return 0
  fi
  echo "OK total=${total} max=${max}"
  return 0
}

# --------------------------------------------------------------------------- #
# §2 — folder / backlog-doc resolvers
# --------------------------------------------------------------------------- #

# is_done <file> — true when the file carries a terminal close-out stamp on its
# `## Status:` HEADING line. Both terminal values count: `done_with_escalation`
# work still SHIPPED, so re-picking it would redo merged work. (The `\b` after a
# bare `done` does NOT match `done_with_escalation` — `_` is a word character —
# which is why the escalated arm is spelled out rather than left to the boundary.)
# Authority for what the completion tail writes here: skills/self-heal-advisory/SKILL.md
# step 2.5, which stamps the value ON this heading for exactly this reason.
is_done() { grep -qE '^## Status:[[:space:]]*done(_with_escalation)?\b' "$1" 2>/dev/null; }

# is_not_ready <file> — true when the file carries a not-ready-to-run stamp on
# its `## Status:` HEADING line (`proposed` or `parked`). This is a SEPARATE
# predicate from `is_done` and MUST NOT be folded into it (decision H2):
# `is_done` is shared with `resume-glob`, whose run files use a DIFFERENT
# status vocabulary (`running|paused|done`, per docs/RESULT_SCHEMAS.md
# §AUTOMATE_RUN) — a run file stamped `## Status: paused` must never be
# treated as not-ready, so `is_not_ready` is called ONLY from `resolve_folder`
# and `resolve_backlog_dir`, never from `resume_glob`.
is_not_ready() { grep -qE '^## Status:[[:space:]]*(proposed|parked)\b' "$1" 2>/dev/null; }

# resolve-folder <dir> — every *.md NOT marked "## Status: done" and not
# "## Status: proposed|parked" (sorted).
resolve_folder() {
  local dir="$1" f
  [ -d "$dir" ] || die "folder not found: $dir"
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_done "$f" && continue
    is_not_ready "$f" && continue
    echo "$f"
  done | LC_ALL=C sort
}

# resolve-backlog <backlog.md> — emit items in DOCUMENTED build order, honoring
# done/✅ markers. We parse "- [ ] <path>" / "- [x] <path>" checklist lines (the
# documented order = file order) and emit only the not-done ones. A line carrying
# "## Status: done" inline, a "✅" marker, or a checked "[x]" box is treated as
# ground-truth done and excluded. _BACKLOG.md-absent ⇒ fall back to dir scan.
# SCOPE BOUNDARY (deliberate, not an oversight): a checklist line here names a
# path directly, which is a human's explicit inclusion decision for that line —
# distinct from the file's own internal stamp. This parser does NOT check the
# pointed-to file's own `## Status:` stamp; that stamp is honoured ONLY on the
# dir-fallback path below (`resolve_backlog_dir`, via `is_not_ready`), never
# when a checklist line directly names an existing file.
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
# excluding ## Status: done files and ## Status: proposed|parked files.
resolve_backlog_dir() {
  local dir="$1" f
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    is_done "$f" && continue
    is_not_ready "$f" && continue
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
# §10 — trusted auto-merge gate (6 conditions, fail CLOSED, SELF-RESOLVING)
# --------------------------------------------------------------------------- #

# _ge_result_field <file> <field> — bounded grep/awk extraction of one scalar
# field's value from the LAST `REVIEW_HEAL_RESULT` block in <file> (markdown
# `## REVIEW_HEAL_RESULT` / `- field: value` bullet form, OR YAML
# `REVIEW_HEAL_RESULT:` / `  field: value` form — "last block wins", mirroring
# result_block_parser.py's own convention). result_block_parser.py exposes NO
# CLI (it is a library; its `__main__` guard prints a usage notice and exits 0
# — checked before writing this), so this is the bounded grep/awk fallback the
# brief sanctions. Prints the trimmed scalar (surrounding double-quotes
# stripped), or nothing when the field/file/block is absent.
_ge_result_field() {
  local file="$1" field="$2"
  [ -f "$file" ] || return 0
  awk -v field="$field" '
    BEGIN { in_block = 0; val = "" }
    /^##[ \t]*REVIEW_HEAL_RESULT[ \t]*$/ { in_block = 1; val = ""; next }
    /^REVIEW_HEAL_RESULT:[ \t]*$/        { in_block = 1; val = ""; next }
    in_block && /^##[ \t]/                        { in_block = 0 }
    in_block && /^[A-Za-z_][A-Za-z0-9_]*:[ \t]*$/  { in_block = 0 }
    in_block {
      line = $0
      sub(/^[ \t]*-[ \t]*/, "", line)
      sub(/^[ \t]+/, "", line)
      if (line ~ ("^" field "[ \t]*:")) {
        sub(("^" field "[ \t]*:[ \t]*"), "", line)
        sub(/[ \t]+#.*$/, "", line)
        gsub(/^"/, "", line)
        gsub(/"$/, "", line)
        val = line
      }
    }
    END { print val }
  ' "$file"
}

# _ge_pr_parts <pr_url> — "owner\trepo\tnumber" parsed from a
# https://github.com/<owner>/<repo>/pull/<n> URL, or three empty fields when
# the URL does not match (the caller's subsequent gh/api calls then target a
# malformed path and fail closed on their own — no separate error path needed).
_ge_pr_parts() {
  local url="$1" rest ownerrepo number owner repo
  case "$url" in
    *github.com/*/*/pull/*)
      rest="${url#*github.com/}"
      ownerrepo="${rest%%/pull/*}"
      number="${rest#*/pull/}"
      number="${number%%[!0-9]*}"
      owner="${ownerrepo%%/*}"
      repo="${ownerrepo#*/}"
      printf '%s\t%s\t%s\n' "$owner" "$repo" "$number"
      ;;
    *)
      printf '\t\t\n'
      ;;
  esac
}

# gate-eval <pr_url> <ctx.json> [--root <checkout>]
# SELF-RESOLVING decision over the six conditions (red-team-hardening item 03):
# the gate re-derives every condition it can from LIVE ground truth (`gh`,
# GraphQL, `classify-risk.sh`, and two artifact-file reads) instead of trusting
# a model-authored value — a caller can no longer hand the gate a fabricated
# verdict for any of conditions 2 through 6. Prints "MERGE" and EXECUTES
# `gh pr merge --squash <url>` ONLY when ALL 6 hold; otherwise prints
# "PARK: <reason>" and returns 0 (a PARK is a normal, expected outcome — fail
# CLOSED, never crash).
#
# ctx.json shape — SHRUNK to exactly what only the drain/caller can know (every
# other former key is now GATE-OWNED and REFUSED if present — see below):
#   {
#     "drain_result": "READY|ESCALATED",           # cond 1 — the owned drain's terminal decision
#     "termination_reason": "converged|bound_hit|sub_floor_converged",  # cond 1b
#        # A "sub_floor_converged" drain skipped its final all-channel re-scan, so it is NOT
#        # merge-eligible. Read with an explicit has()/!= null check: missing/null ⇒ PARK.
#     "ready_sha": "<sha>",                         # cond 2 — the drain's claim, cross-checked
#        # against the LIVE `gh pr view --json headRefOid` (never trusted alone).
#     "trust_unprotected": true|false,              # cond 4 override — a legitimate operator flag,
#        # NOT a fact the gate can observe, so it stays a ctx input.
#     "review_heal_result_path": "<path>",          # cond 1/1b cross-check — a file containing the
#        # verbatim REVIEW_HEAL_RESULT block the owned drain emitted; drain_result/termination_reason
#        # above MUST match the block's own decision/termination_reason, or the gate PARKs — the
#        # drain's self-report is corroborated against the artifact it actually wrote, never trusted blind.
#     "supervisor_result_path": "<path>"            # cond 5 rubric — a file containing a
#        # `rubric_score: N/M` line (the Supervisor Phase 4.5 SUPERVISOR_RESULT record). The gate
#        # parses it itself; N==M ⇒ satisfied, no such line ⇒ "na" (not a blocker), unreadable file ⇒ PARK.
#   }
#
# GATE-OWNED KEYS — REFUSED, NEVER TRUSTED. The ctx keys below now name
# conditions the gate computes itself. If ANY of them is present in ctx.json --
# REGARDLESS of the value it carries — the gate PARKs with
# `ctx_carries_gate_owned_key` BEFORE evaluating anything else: `high_risk`,
# `risk_reasons`, `head_sha`, `base`, `review_decision`,
# `unresolved_human_thread`, `protection_enforceable`, `checks_green`,
# `rubric_satisfied`. A caller attempting to hand the gate a pre-computed
# verdict for a gate-owned condition is refused, never silently accepted.
#
# Self-resolution per condition (all fail CLOSED — any read failure ⇒ PARK):
#   cond 2  `gh pr view <url> --json headRefOid,baseRefName,statusCheckRollup` (this combined
#           call also feeds cond 5's checks — mirrors review-heal/SKILL.md §U1(a)'s own combined
#           read). Live `headRefOid` must equal ctx's `ready_sha`; live `baseRefName` must be `main`.
#   cond 3  a SEPARATE `gh pr view <url> --json reviewDecision` call (kept apart from cond 2's read
#           so a reviewDecision-specific failure parks on its OWN named reason,
#           `review_decision_unreadable`, rather than being masked by cond 2's `head_sha_moved`
#           firing first on a combined-call failure) — null ⇒ "none", unreadable ⇒ "unreadable" —
#           PLUS the review-threads GraphQL query — adapted from review-heal/SKILL.md §U1(b) (same
#           query minus the unused `body` field) — to compute the unresolved-human-thread blocker: any unresolved thread
#           whose first-comment actor is NOT in the trusted-actor set
#           (`${HOME}/.claude/loomwright/trusted-actors.json`, red-team-hardening item 01 — same
#           fail-CLOSED "absent file ⇒ nobody trusted" resolution as `wrap-external-text.sh`, no
#           `bot_author_re` fallback here) blocks; `hasNextPage` (truncated >100 threads) blocks;
#           any GraphQL read error blocks.
#   cond 4  `gh api repos/<owner>/<repo>/branches/main/protection` — a 404 ⇒ unprotected (false);
#           ANY OTHER error ⇒ `protection_unreadable` (PARK). `trust_unprotected` stays a ctx input
#           (an operator flag, not an observable fact).
#   cond 5  required-check greenness from the SAME protection payload's required-context list
#           (review-heal/SKILL.md §U2's discovery recipe) cross-referenced against the combined
#           call's `statusCheckRollup`. Rubric satisfaction is now a FILE READ: ctx's
#           `supervisor_result_path` is parsed for a `rubric_score: N/M` line by THIS gate (never
#           asserted by a caller) — N==M ⇒ satisfied, absent line ⇒ "na" (not a blocker), unreadable
#           file ⇒ PARK.
#   cond 6  the gate ITSELF invokes `"$(dirname "$0")/classify-risk.sh" main <live head_sha>
#           --root <root>` and reads `.high_risk`/`.reasons` from its own output — no ctx input of
#           any kind feeds this condition any more. NO override of any kind (owner decision R5):
#           not `--trust-unprotected` (cond 4 only), not a config key, not an exclude list.
#
# Every PARK reason from the pre-self-resolving gate is preserved verbatim:
# ctx_unreadable, drain_not_ready, sub_floor_not_merge_eligible, head_sha_moved,
# base_not_main, review_decision_blocking, review_decision_unreadable,
# unresolved_human_thread, unprotected_branch, checks_not_green,
# rubric_unsatisfied, high_risk_diff, merge_command_failed. New reasons added by
# self-resolution: ctx_carries_gate_owned_key, review_heal_result_unreadable,
# drain_result_mismatch, protection_unreadable, supervisor_result_unreadable.
gate_eval() {
  local url="$1" ctx="$2"
  shift 2 2>/dev/null || true
  local root="."
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root) root="${2:-.}"; shift 2 2>/dev/null || shift ;;
      *)      shift ;;
    esac
  done

  [ -f "$ctx" ] || die "ctx not found: $ctx"
  if ! "$JQ" -e . "$ctx" >/dev/null 2>&1; then
    echo "PARK: ctx_unreadable"; return 0
  fi

  # GATE-OWNED KEY REFUSAL — checked FIRST, before any other read. A ctx that
  # still tries to hand the gate a pre-computed verdict for a now-gate-owned
  # condition is refused outright, regardless of the value it carries.
  local _ge_k
  for _ge_k in high_risk risk_reasons head_sha base review_decision \
               unresolved_human_thread protection_enforceable checks_green rubric_satisfied; do
    if "$JQ" -e --arg k "$_ge_k" 'has($k)' "$ctx" >/dev/null 2>&1; then
      echo "PARK: ctx_carries_gate_owned_key"; return 0
    fi
  done

  # NB: a bash function definition is always global — there is no `local` function
  # scoping — so J() lives until gate_eval returns and the next call redefines it;
  # no `local J` (which would only declare an unused local var of that name).
  J() { "$JQ" -r "$1 // \"__MISSING__\"" "$ctx"; }

  # Condition 1 — owned drain == READY.
  local drain_result; drain_result="$(J '.drain_result')"
  if [ "$drain_result" != "READY" ]; then
    echo "PARK: drain_not_ready"; return 0
  fi

  # Condition 1b — a `sub_floor_converged` READY is NOT auto-merge-eligible (AC9,
  # drain-bounding-earned-checks). Read WITHOUT the falsy-coercing `//` — an
  # explicit has()/!=null check so a legitimate string value is never coerced away.
  local tr
  tr="$("$JQ" -r 'if has("termination_reason") and (.termination_reason != null) then .termination_reason else "__MISSING__" end' "$ctx")"
  if [ "$tr" = "__MISSING__" ] || [ "$tr" = "sub_floor_converged" ]; then
    echo "PARK: sub_floor_not_merge_eligible"; return 0
  fi

  # Condition 1 cross-check — the drain's OWN self-report (drain_result /
  # termination_reason above) must match the REVIEW_HEAL_RESULT artifact it
  # actually wrote, never be trusted as a bare assertion.
  local rhrp; rhrp="$(J '.review_heal_result_path')"
  if [ "$rhrp" = "__MISSING__" ] || [ ! -f "$rhrp" ]; then
    echo "PARK: review_heal_result_unreadable"; return 0
  fi
  local art_decision art_tr
  art_decision="$(_ge_result_field "$rhrp" "decision")"
  art_tr="$(_ge_result_field "$rhrp" "termination_reason")"
  if [ -z "$art_decision" ] || [ "$art_decision" != "$drain_result" ] \
     || [ -z "$art_tr" ] || [ "$art_tr" != "$tr" ]; then
    echo "PARK: drain_result_mismatch"; return 0
  fi

  # ---- `gh pr view` read #1 feeds conditions 2 (headRefOid/baseRefName) and
  # 5 (statusCheckRollup) — a combined multi-field read (mirrors review-heal/
  # SKILL.md §U1(a)'s own combined read). A total read failure fails EVERY
  # dependent field closed (empty/unreadable defaults below), never partially
  # trusted. `cmd || rc=$?` (not `x="$(cmd)"; rc=$?`) — under `set -e` a plain
  # (non-`local`) assignment whose RHS command substitution fails ABORTS THE
  # SCRIPT before the next statement ever runs (the exit-status-lost-across-
  # subshells trap, but in the OPPOSITE direction: here the failure is very
  # much seen, just fatally). Folding the failure into an `||` list keeps it a
  # normal, inspectable value.
  local pv pv_rc=0
  pv="$("$GH" pr view "$url" --json headRefOid,baseRefName,statusCheckRollup 2>/dev/null)" || pv_rc=$?
  local pv_ok=0
  printf '%s' "$pv" | "$JQ" -e . >/dev/null 2>&1 && [ "$pv_rc" -eq 0 ] && pv_ok=1
  local live_head="" live_base="" rollup_json="[]"
  if [ "$pv_ok" -eq 1 ]; then
    live_head="$(printf '%s' "$pv" | "$JQ" -r '.headRefOid // empty')"
    live_base="$(printf '%s' "$pv" | "$JQ" -r '.baseRefName // empty')"
    rollup_json="$(printf '%s' "$pv" | "$JQ" -c '.statusCheckRollup // []')"
  fi

  # ---- `gh pr view` read #2 feeds condition 3's reviewDecision — kept as its
  # OWN call (not folded into read #1) so a reviewDecision-specific read
  # failure PARKs on its own named reason (`review_decision_unreadable`)
  # rather than being masked by cond 2's `head_sha_moved`, which would fire
  # first on a combined-call failure and make this reason unreachable.
  local pv2 pv2_rc=0 rd="unreadable"
  pv2="$("$GH" pr view "$url" --json reviewDecision 2>/dev/null)" || pv2_rc=$?
  if [ "$pv2_rc" -eq 0 ] && printf '%s' "$pv2" | "$JQ" -e . >/dev/null 2>&1; then
    rd="$(printf '%s' "$pv2" | "$JQ" -r 'if has("reviewDecision") and (.reviewDecision != null) then .reviewDecision else "none" end')"
  fi

  # Condition 2 — live head SHA matches the drain's `ready_sha` claim, AND base == main.
  local ready_sha; ready_sha="$(J '.ready_sha')"
  if [ "$ready_sha" = "__MISSING__" ] || [ -z "$live_head" ] || [ "$ready_sha" != "$live_head" ]; then
    echo "PARK: head_sha_moved"; return 0
  fi
  if [ "$live_base" != "main" ]; then
    echo "PARK: base_not_main"; return 0
  fi

  # Condition 3 — reviewDecision not blocking AND no unresolved human/untrusted thread.
  case "$rd" in
    CHANGES_REQUESTED|REVIEW_REQUIRED)   echo "PARK: review_decision_blocking"; return 0 ;;
    APPROVED|none)                       : ;;   # acceptable -- defer protection judgment to cond 4
    *)                                    echo "PARK: review_decision_unreadable"; return 0 ;;
  esac

  # Review-threads GraphQL query — adapted from review-heal/SKILL.md §U1(b) (same
  # query minus the unused `body` field this gate never reads). `hasNextPage`
  # (truncated >100 threads) or any read error ⇒ fail CLOSED (treated as an
  # unresolved blocking thread).
  local parts owner repo number
  parts="$(_ge_pr_parts "$url")"
  IFS=$'\t' read -r owner repo number <<GEPARTS
$parts
GEPARTS
  local gql gql_rc=0
  gql="$("$GH" api graphql -f query='
  query($owner:String!,$repo:String!,$number:Int!){
    repository(owner:$owner,name:$repo){
      pullRequest(number:$number){
        reviewThreads(first:100){
          pageInfo{ hasNextPage }
          nodes{ isResolved comments(first:1){ nodes{ author{ login __typename } } } }
        }
      }
    }
  }' -F owner="$owner" -F repo="$repo" -F number="$number" 2>/dev/null)" || gql_rc=$?

  local uht="true"
  if [ "$gql_rc" -eq 0 ] && printf '%s' "$gql" | "$JQ" -e '.data.repository.pullRequest.reviewThreads' >/dev/null 2>&1; then
    # Explicit == false check (NOT the falsy-coercing `//`, which would map a
    # genuine `false` to the "true" default and silently defeat the truncation
    # guard — the same trap `config_orig`/`unresolved_human_thread` avoid).
    local hasNext; hasNext="$(printf '%s' "$gql" | "$JQ" -r 'if .data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage == false then "false" else "true" end')"
    if [ "$hasNext" = "false" ]; then
      # Trusted-actor set (red-team-hardening item 01) — same fail-CLOSED resolution
      # as wrap-external-text.sh: absent/unreadable/malformed file ⇒ EMPTY set =>
      # every actor is "not in the trusted set" ⇒ blocking. No bot_author_re fallback here.
      local trusted_file trusted_json='[]'
      trusted_file="${HOME:-}/.claude/loomwright/trusted-actors.json"
      if [ -n "$trusted_file" ] && [ -r "$trusted_file" ]; then
        local _t; _t="$("$JQ" -c '.' "$trusted_file" 2>/dev/null || true)"
        if [ -n "$_t" ] && printf '%s' "$_t" | "$JQ" -e 'type=="array"' >/dev/null 2>&1; then
          trusted_json="$_t"
        fi
      fi
      local blocking
      blocking="$(printf '%s' "$gql" | "$JQ" -r --argjson trusted "$trusted_json" '
        [ .data.repository.pullRequest.reviewThreads.nodes[]?
          | select(.isResolved == false)
          | (.comments.nodes[0].author.login // "") as $login
          | select( ($trusted | index($login)) == null )
        ] | length > 0
      ' 2>/dev/null)"
      [ "$blocking" = "false" ] && uht="false"
    fi
  fi
  if [ "$uht" != "false" ]; then
    echo "PARK: unresolved_human_thread"; return 0
  fi

  # Condition 4 — enforceable branch protection OR --trust-unprotected. A 404
  # means genuinely unprotected (false); ANY OTHER error is unreadable ⇒ PARK
  # (never silently treated as either protected or unprotected).
  local prot_raw prot_rc=0 protection_enforceable="false" required_contexts_json="[]"
  prot_raw="$("$GH" api "repos/$owner/$repo/branches/main/protection" 2>&1)" || prot_rc=$?
  if [ "$prot_rc" -ne 0 ]; then
    case "$prot_raw" in
      *"404"*|*"Not Found"*) protection_enforceable="false" ;;
      *)                     echo "PARK: protection_unreadable"; return 0 ;;
    esac
  else
    if printf '%s' "$prot_raw" | "$JQ" -e . >/dev/null 2>&1; then
      protection_enforceable="$(printf '%s' "$prot_raw" | "$JQ" -r '
        ( ((.required_pull_request_reviews.required_approving_review_count // 0) >= 1)
          or (((.required_status_checks.contexts // []) | length) > 0)
          or (((.required_status_checks.checks // []) | length) > 0) )
      ' 2>/dev/null)"
      required_contexts_json="$(printf '%s' "$prot_raw" | "$JQ" -c '
        ( (.required_status_checks.contexts // []) + ((.required_status_checks.checks // []) | map(.context)) ) | unique
      ' 2>/dev/null)"
      [ -n "$required_contexts_json" ] || required_contexts_json="[]"
    else
      echo "PARK: protection_unreadable"; return 0
    fi
  fi
  local trust; trust="$(J '.trust_unprotected')"
  if [ "$protection_enforceable" != "true" ] && [ "$trust" != "true" ]; then
    echo "PARK: unprotected_branch"; return 0
  fi

  # Condition 5 — required checks green (discovery recipe: review-heal/SKILL.md §U2,
  # here sourced from the SAME branch-protection payload cond 4 already fetched)
  # AND rubric satisfied (na = not a blocker, now a FILE read — never caller-asserted).
  local checks_green
  checks_green="$(printf '%s' "$rollup_json" | "$JQ" -r --argjson req "$required_contexts_json" '
    . as $rollup
    | ( ($req | length) == 0 ) or
      ( all($req[]; . as $name
          | ( $rollup | map(select((.name // .context // "") == $name))
              | any( ( ((.conclusion // "") | ascii_downcase) as $c
                       | ((.state // "") | ascii_downcase) as $s
                       | ($c == "success" or $c == "neutral" or $s == "success") ) ) )
        ) )
  ' 2>/dev/null)"
  if [ "$checks_green" != "true" ]; then
    echo "PARK: checks_not_green"; return 0
  fi

  local srp; srp="$(J '.supervisor_result_path')"
  if [ "$srp" = "__MISSING__" ] || [ ! -f "$srp" ]; then
    echo "PARK: supervisor_result_unreadable"; return 0
  fi
  local rubric_line rub
  rubric_line="$(grep -m1 -E 'rubric_score:[[:space:]]*[0-9]+/[0-9]+' "$srp" 2>/dev/null || true)"
  if [ -z "$rubric_line" ]; then
    rub="na"
  else
    local rub_n rub_m
    rub_n="$(printf '%s' "$rubric_line" | sed -E 's/.*rubric_score:[[:space:]]*([0-9]+)\/([0-9]+).*/\1/')"
    rub_m="$(printf '%s' "$rubric_line" | sed -E 's/.*rubric_score:[[:space:]]*([0-9]+)\/([0-9]+).*/\2/')"
    if [ -n "$rub_n" ] && [ "$rub_n" = "$rub_m" ]; then rub="true"; else rub="false"; fi
  fi
  if [ "$rub" != "true" ] && [ "$rub" != "na" ]; then
    echo "PARK: rubric_unsatisfied"; return 0
  fi

  # Condition 6 — NOT a high-risk diff (owner decision R5: NO override, of ANY kind).
  # The gate ITSELF invokes classify-risk.sh on the live head SHA it just confirmed
  # in cond 2 — no ctx input feeds this condition any more. Read in EXACTLY the
  # cond-3 `unresolved_human_thread` shape: an explicit has() + `type == "boolean"`
  # check, PARK unless the value is the JSON boolean `false`.
  local risk_bin; risk_bin="$(dirname "$0")/classify-risk.sh"
  local risk_json=""
  if [ -r "$risk_bin" ]; then
    risk_json="$(bash "$risk_bin" main "$live_head" --root "$root" 2>/dev/null)"
  fi
  local hr rr
  if [ -n "$risk_json" ] && printf '%s' "$risk_json" | "$JQ" -e . >/dev/null 2>&1; then
    hr="$(printf '%s' "$risk_json" | "$JQ" -r 'if has("high_risk") and ((.high_risk|type) == "boolean") then (.high_risk|tostring) else "__MISSING__" end')"
    rr="$(printf '%s' "$risk_json" | "$JQ" -r 'if has("reasons") and ((.reasons|type) == "array") then (.reasons | map(tostring) | .[:3] | join("; ")) else "" end')"
  else
    hr="__MISSING__"; rr=""
  fi
  if [ "$hr" != "false" ]; then
    [ -z "$rr" ] && rr="no risk_reasons recorded"
    echo "PARK: high_risk_diff ($rr)"; return 0
  fi

  # ALL 6 hold — the ONLY sanctioned `gh pr merge --squash` in the plugin (§11).
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

  # Normalize changed_paths ONCE (the same shape the record below embeds) so the
  # completeness discriminator and the emitted field can never disagree.
  local cp_clean
  cp_clean="$( printf '%s' "$changed_paths_json" \
    | "$JQ" -c 'if type=="array" then map(select(type=="string")) else [] end' 2>/dev/null )"
  [ -n "$cp_clean" ] || cp_clean="[]"

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

# --------------------------------------------------------------------------- #
# queue-hygiene/01 — reconcile-status: requirement `## Status:` from ground
# truth (a merged PR, an owner `# abandoned:` decision), dry-run by default.
# --------------------------------------------------------------------------- #
#
# WHY THIS EXISTS. `/automate`'s per-item loop is the ONLY writer of a
# requirement's `## Status: done` line (SKILL.md §6). Every other way a PR
# reaches main — a hand `gh pr merge`, the GitHub UI, a bare `/supervisor`, an
# owner-merged `/review-pr` heal — leaves the requirement untouched, so
# `is_done()` still treats it as pending and `resolve-folder`/`resolve-backlog`
# re-offer already-shipped work. This closes that gap the same way
# `reconcile-jobs.sh --repair-merged` closes the sibling brief-lifecycle gap:
# read ground truth back, never infer it.
#
# EVIDENCE, for a *.md this script does NOT already consider `is_done()`:
#   (a) PR-BODY CITATION — a `gh pr list --state merged --search <rel-path>`
#       hit whose body (fetched with ONE more `gh pr view`) contains the
#       file's own repo-relative path, literally.
#   (b) BRANCH-SLUG — when this requirement has an associated
#       `.supervisor/jobs/done/<brief>.md` (found by the SAME reverse
#       `## Source requirement:` pointer scan `stamp-requirement-status.sh`
#       runs, via the shared `brief-pointer.sh`), that brief's own `- **PR:**`
#       Outcome line is tried as a candidate FIRST, and a merged candidate's
#       `headRefName` ending in the brief's date-stripped filename slug is
#       accepted as a match when the body citation is absent.
# PR STATE is resolved EXCLUSIVELY through `reconcile_item` (merged|open|gone)
# — this is not a second gh-state parser; the extra `gh pr view` call here
# reads ADDITIONAL fields (body, mergeCommit, headRefName) on a candidate
# `reconcile_item` has ALREADY confirmed merged.
#
# NEVER DOWNGRADES: `is_done()` gates every file before ANY evidence is
# gathered, so a `done`/`done_with_escalation` file is never even read past
# that check — this function does not distinguish "no evidence" from "already
# done" in its write path because the caller-side gate makes the second case
# structurally unreachable here.
#
# DRY RUN BY DEFAULT. Without --apply, nothing under <requirements_root> (or
# the matched `.supervisor/automate/*.md` / `.supervisor/jobs/done/*.md`) is
# ever opened for writing — only `--apply` calls the two stamp-writers.
#
# OUTPUT (tab-separated, one row per line, mirrors reconcile-jobs.sh
# --porcelain's convention):
#   plan\t<repo-relative file>\t<status line the file would get>\t<evidence>
#   stamped\t<repo-relative file>\t<status line just written>\t<evidence>
#   info\t<repo-relative file>\tbrief-shipped\t<job path> (<PR url or "no PR recorded">)
#
# FAIL-SAFE (`set +e` below): a network hiccup, an unreadable brief, or a
# malformed run-file row degrades that ONE candidate to "no evidence" — it
# never aborts the whole pass. This is a read-mostly reconciliation pass, not
# a correctness gate (CLAUDE.md bimodal invariant).

# _rs_project_root <requirements_root_abs> — the directory holding
# `.supervisor/` that <requirements_root_abs> sits under (normally its
# grandparent: `<proj>/.supervisor/requirements` -> `<proj>`). Falls back to a
# walk-up so a differently-nested fixture still resolves; falls back to the
# root itself when no `.supervisor/` ancestor exists (jobs/done + automate
# scans then simply find nothing, which is the safe degrade).
_rs_project_root() {
  local abs="$1" parent
  parent="$(dirname "$abs")"
  if [ "$(basename "$parent")" = ".supervisor" ]; then
    dirname "$parent"; return 0
  fi
  local cur="$abs"
  while [ -n "$cur" ] && [ "$cur" != "/" ]; do
    if [ -d "$cur/.supervisor" ]; then printf '%s' "$cur"; return 0; fi
    cur="$(dirname "$cur")"
  done
  printf '%s' "$abs"
}

# _rs_skip_path <abs_file> — the Scope §1 exclusion list: an index file, a
# leading-underscore file, a README, or anything under an `operator-run/`
# subfolder (the `/automate` engine's own worked-by-hand pile, never
# reconciled mechanically).
_rs_skip_path() {
  local f="$1" base; base="$(basename "$f")"
  case "$base" in 00-*|_*|README*) return 0 ;; esac
  case "$f" in */operator-run/*) return 0 ;; esac
  return 1
}

# _rs_load_brief_pointer — source the sibling brief-pointer.sh (THE one
# Source-requirement parser; see its header) if not already loaded; absent
# helper degrades to "no reverse pointer ever resolves", never an abort —
# same fail-safe posture stamp-requirement-status.sh and reconcile-jobs.sh
# both already carry for this exact sibling.
_rs_load_brief_pointer() {
  command -v brief_requirement_pointer >/dev/null 2>&1 && return 0
  local d; d="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)"
  [ -r "$d/brief-pointer.sh" ] && . "$d/brief-pointer.sh"
  if ! command -v brief_requirement_pointer >/dev/null 2>&1; then
    brief_requirement_pointer() { return 1; }
  fi
}

# _rs_outcome_pr <brief> — the `- **PR:**` line's URL from a done/ brief's
# `## Outcome` block, or empty.
_rs_outcome_pr() {
  grep -m1 -E '^- \*\*PR:\*\*[[:space:]]*' "$1" 2>/dev/null \
    | sed -E 's/^-[[:space:]]*\*\*PR:\*\*[[:space:]]*//'
}

# _rs_brief_slug <brief_path> — the brief's own filename with a leading
# `YYYY-MM-DD-` date stripped and `.md` removed (mirrors
# reconcile-jobs.sh's vcs_merge_for_brief slug convention).
_rs_brief_slug() {
  local base; base="$(basename "$1" .md)"
  case "$base" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-?*) printf '%s' "${base:11}" ;;
    *) printf '%s' "$base" ;;
  esac
}

# _rs_strip_trailing_status <file> <tmp> — copy every line of <file> to <tmp>
# EXCEPT a bare `## Status: pending` heading (the stale line a stamp replaces;
# SKILL §1.5/queue-hygiene AC-2 "stale trailing pending line is removed").
_rs_strip_trailing_status() {
  grep -vE '^## Status:[[:space:]]*pending[[:space:]]*$' "$1" > "$2" 2>/dev/null
}

# _rs_find_done_brief <rel_path> <jobs_done_dir> — echo the ONE
# `.supervisor/jobs/done/*.md` brief whose `## Source requirement:` pointer is
# EXACTLY <rel_path> (first match wins — mirrors stamp-requirement-status.sh's
# own "only the FIRST matching line" rule at the field level, applied here at
# the file level). Prints nothing when none matches.
_rs_find_done_brief() {
  local rel="$1" dir="$2" b ptr
  [ -d "$dir" ] || return 0
  for b in "$dir"/*.md; do
    [ -f "$b" ] || continue
    ptr="$(brief_requirement_pointer "$b" 2>/dev/null)"
    if [ "$ptr" = "$rel" ]; then printf '%s' "$b"; return 0; fi
  done
  return 0
}

# _rs_evidence_for <abs_file> <rel_path> <done_brief|""> — echo
# "<pr_url>\t<pr_number>\t<sha7>\t<justification>" for the first candidate PR
# that is MERGED (via reconcile_item) AND either cites <rel_path> in its body
# or (when <done_brief> is non-empty) has a headRefName ending in that
# brief's slug. Echoes nothing when no candidate matches.
_rs_evidence_for() {
  local rel="$1" done_brief="$2" candidates="" c seen=$'\x1f'
  [ -n "${3:-}" ] && candidates="$3"$'\n'
  local search_json
  search_json="$("$GH" pr list --state merged --search "$rel" --json url --limit 5 2>/dev/null)"
  if [ -n "$search_json" ]; then
    local urls; urls="$(printf '%s' "$search_json" | "$JQ" -r '.[]?.url // empty' 2>/dev/null)"
    [ -n "$urls" ] && candidates="${candidates}${urls}"$'\n'
  fi
  [ -n "$candidates" ] || return 0

  local slug=""
  [ -n "$done_brief" ] && slug="$(_rs_brief_slug "$done_brief")"

  while IFS= read -r c; do
    [ -n "$c" ] || continue
    case "$seen" in *$'\x1f'"$c"$'\x1f'*) continue ;; esac
    seen="${seen}${c}"$'\x1f'
    local state; state="$(reconcile_item "$c" "" 2>/dev/null)"
    [ "$state" = "merged" ] || continue
    local view num body oid headref
    view="$("$GH" pr view "$c" --json number,body,mergeCommit,headRefName 2>/dev/null)"
    [ -n "$view" ] || continue
    num="$(printf '%s' "$view" | "$JQ" -r '.number // empty' 2>/dev/null)"
    body="$(printf '%s' "$view" | "$JQ" -r '.body // empty' 2>/dev/null)"
    oid="$(printf '%s' "$view" | "$JQ" -r '.mergeCommit.oid // empty' 2>/dev/null)"
    headref="$(printf '%s' "$view" | "$JQ" -r '.headRefName // empty' 2>/dev/null)"
    local justification=""
    case "$body" in *"$rel"*) justification="PR body cites $rel" ;; esac
    if [ -z "$justification" ] && [ -n "$slug" ]; then
      case "$headref" in *"$slug") justification="head branch '$headref' matches brief slug '$slug'" ;; esac
    fi
    [ -n "$justification" ] || continue
    [ -n "$oid" ] || oid="unknown"
    printf '%s\t%s\t%s\t%s' "$c" "${num:-0}" "${oid:0:7}" "$justification"
    return 0
  done <<RS_CANDIDATES
$candidates
RS_CANDIDATES
  return 0
}

# _rs_process_file <abs_file> <proj_root> <jobs_done_dir> <apply>
_rs_process_file() {
  local f="$1" proj_root="$2" jobs_done="$3" apply="$4" rel status_hdr
  rel="${f#"$proj_root"/}"
  status_hdr="$(grep -m1 -E '^## Status:' "$f" 2>/dev/null)"

  # brief-shipped: LISTED, never promoted (Scope §4 / Non-goals).
  case "$status_hdr" in
    *brief-shipped*)
      local db pr
      db="$(_rs_find_done_brief "$rel" "$jobs_done")"
      pr=""
      [ -n "$db" ] && pr="$(_rs_outcome_pr "$db")"
      printf 'info\t%s\tbrief-shipped\t%s\n' "$rel" "${pr:-no PR recorded}"
      return 0
      ;;
  esac

  local done_brief; done_brief="$(_rs_find_done_brief "$rel" "$jobs_done")"
  local seed=""
  [ -n "$done_brief" ] && seed="$(_rs_outcome_pr "$done_brief")"
  local evidence; evidence="$(_rs_evidence_for "$rel" "$done_brief" "$seed")"
  [ -n "$evidence" ] || return 0

  local url num sha just status_line
  IFS=$'\t' read -r url num sha just <<RS_EV
$evidence
RS_EV
  status_line="done (PR #${num}, merge ${sha})"

  if [ "$apply" -eq 1 ]; then
    local tmp; tmp="$(mktemp "${f}.XXXXXX")"
    _rs_strip_trailing_status "$f" "$tmp"
    {
      printf '\n## Status: %s\n' "$status_line"
      printf -- '- **Completed:** %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
      printf -- '- **Brief:** %s\n' "${done_brief:-unknown}"
      printf -- '- **PR:** %s\n' "$url"
    } >> "$tmp"
    mv -f "$tmp" "$f"
    printf 'stamped\t%s\t%s\t%s\n' "$rel" "$status_line" "$just"
  else
    printf 'plan\t%s\t%s\t%s\n' "$rel" "$status_line" "$just"
  fi
  return 0
}

# _rs_process_abandoned <requirements_root_abs> <proj_root> <automate_dir> <apply>
# One Queue row `- [x] <req-path>  # abandoned: <reason>` per requirement is
# ground truth for an owner decision (SKILL.md §5). Every row is scanned;
# only a row whose path resolves to a real, not-yet-done, in-scope requirement
# file stamps anything — a row naming a requirement outside
# <requirements_root_abs> (a different queue-hygiene run over a subfolder) is
# left alone.
_rs_process_abandoned() {
  local root_abs="$1" proj_root="$2" automate_dir="$3" apply="$4"
  [ -d "$automate_dir" ] || return 0
  local af line
  for af in "$automate_dir"/*.md; do
    [ -f "$af" ] || continue
    while IFS= read -r line; do
      case "$line" in
        "- [x] "*"  # abandoned: "*)
          local payload reqpath fabs
          payload="${line:6}"
          reqpath="${payload%%  #*}"
          case "$reqpath" in
            .supervisor/requirements/*) ;;
            *) continue ;;
          esac
          fabs="$proj_root/$reqpath"
          [ -f "$fabs" ] || continue
          case "$fabs" in "$root_abs"/*|"$root_abs") ;; *) continue ;; esac
          _rs_skip_path "$fabs" && continue
          is_done "$fabs" && continue
          if [ "$apply" -eq 1 ]; then
            local tmp; tmp="$(mktemp "${fabs}.XXXXXX")"
            _rs_strip_trailing_status "$fabs" "$tmp"
            printf '\n## Status: done_with_escalation \xe2\x80\x94 ABANDONED (%s)\n' "$line" >> "$tmp"
            mv -f "$tmp" "$fabs"
            printf 'stamped\t%s\tdone_with_escalation \xe2\x80\x94 ABANDONED\t%s\n' "$reqpath" "$af"
          else
            printf 'plan\t%s\tdone_with_escalation \xe2\x80\x94 ABANDONED\t%s\n' "$reqpath" "$af"
          fi
          ;;
      esac
    done < "$af"
  done
  return 0
}

# reconcile-status <requirements_root> [--apply]
reconcile_status() {
  set +e   # FAIL-SAFE: one candidate's gh hiccup degrades to "no evidence", never an abort.
  local root="${1:-}" apply=0
  [ -n "$root" ] || { echo "automate-helpers: reconcile-status: requirements root required" >&2; return 1; }
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in --apply) apply=1 ;; esac
    shift
  done
  [ -d "$root" ] || { echo "automate-helpers: reconcile-status: root not found: $root" >&2; return 1; }

  _rs_load_brief_pointer

  local root_abs proj_root jobs_done automate_dir
  root_abs="$(cd "$root" 2>/dev/null && pwd -P)"; [ -n "$root_abs" ] || root_abs="$root"
  proj_root="$(_rs_project_root "$root_abs")"
  jobs_done="$proj_root/.supervisor/jobs/done"
  automate_dir="$proj_root/.supervisor/automate"

  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    _rs_skip_path "$f" && continue
    is_done "$f" && continue
    _rs_process_file "$f" "$proj_root" "$jobs_done" "$apply"
  done < <(find "$root_abs" -type f -name '*.md' 2>/dev/null | LC_ALL=C sort)

  _rs_process_abandoned "$root_abs" "$proj_root" "$automate_dir" "$apply"
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
    ceiling-check)   ceiling_check "$@" ;;
    resolve-folder)  resolve_folder "$@" ;;
    resolve-backlog) resolve_backlog "$@" ;;
    resume-glob)     resume_glob "$@" ;;
    reconcile-item)  reconcile_item "$@" ;;
    gate-eval)       gate_eval "$@" ;;
    learning-emit)   learning_emit "$@" ;;
    brief-repair)    brief_repair "$@" ;;
    reconcile-status) reconcile_status "$@" ;;
    ""|-h|--help)
      grep -E '^#   [a-z]' "$0" | sed 's/^#   /  /'
      ;;
    *) die "unknown subcommand: $cmd (try --help)" ;;
  esac
}

main "$@"
