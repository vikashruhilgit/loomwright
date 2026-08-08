#!/usr/bin/env bash
# setup-memory.sh — fail-safe engine for the `/setup memory` module: put a repo's Twin memory
# stores under version control IN PLACE via gitignore negation, plus the repo allowlist that
# decides which ledger records belong to this repo.
#
# WHAT: the Twin's accumulated judgment (`.claude/agent-memory/`, `.supervisor/memory/`) plus the
# findings ledger (`.supervisor/postmortem/results.jsonl`) is gitignored in every repo the plugin
# runs in, so a fresh clone, a second machine, CI and every `git worktree` checkout start COLD, and
# a bad curation pass is irreversible (there is no `git checkout` to undo it). This helper
# un-ignores exactly those THREE stores WHERE THEY ALREADY SIT — no move, no symlink, no generated
# copy, no bridge. Nothing moves, so the harness keeps injecting agent memory from its own fixed
# path and there is nothing to prove about injection.
#
# THE THIRD STORE IS GATED, THE FIRST TWO ARE NOT. The findings ledger is structurally CROSS-REPO:
# a `/pr-postmortem` append lands in the CURRENT working `.supervisor/`, never in the analysed
# repo's, so a ledger accumulates records belonging to OTHER repos (this plugin's own ledger held 7
# `vendsy/hub` records before it was filtered). Un-ignoring an unfiltered ledger therefore
# PUBLISHES another repo's churn analysis. So `apply` FAILS CLOSED on it: the ledger negation is
# emitted only while every record's `.repo` sits inside the resolved allowlist. Otherwise the
# negation is WITHHELD, the offending slugs are NAMED, the readiness verdict is the dedicated
# `gated` class — and the exit code is still 0 (see FAIL-SAFE CONTRACT below: the gate fails closed
# in the WRITE dimension, never in the exit-status dimension).
#
# HONEST LIMIT — the gate is evaluated AT APPLY TIME ONLY. A repo whose ledger gains a foreign
# record AFTER a clean apply stays un-ignored until the next `apply` runs, and a routine
# `git add -A` can commit it in between. Run `setup-memory.sh filter-ledger` before committing;
# do not read the gate as complete coverage. A withdrawal also does NOT un-track an ALREADY
# COMMITTED ledger — `.gitignore` only governs UNTRACKED files.
#
# NON-GOAL (a decision, not an oversight): the gate keys on `.repo` ONLY. A record whose `.repo` is
# allowlisted but whose finding TEXT cites a foreign org is NOT caught here; content-level sweeping
# of the ledger is a separate item (test-committed-twin-scrub.sh's EXPLICIT_STORE_ROOTS is
# deliberately NOT widened to `.supervisor/postmortem`).
#
# THE NAIVE NEGATION SILENTLY FAILS. Git cannot re-include a file whose parent directory is
# excluded, so this looks right and does NOTHING:
#     .claude/
#     !.claude/agent-memory/
# The working form excludes the directory's CONTENTS, which leaves the directory traversable:
#     .claude/*
#     !.claude/agent-memory/
# Both forms are asserted in test-setup-memory.sh — the failure is proven, not commented.
#
# WHY the allowlist is a LIST (and never the live remote): the findings ledger
# (`.supervisor/postmortem/results.jsonl`) carries a `repo` field per record, and a repo RENAME
# leaves older records under the old slug. In this plugin's own ledger, 42 records sit under
# `<owner>/ai-agent-manager` (pre-rename) against 39 under the current slug — a filter keyed on
# the live remote would silently drop the larger, older half. (Those two figures are ILLUSTRATIVE
# and drift as the ledger grows; re-derive with jq, never grep — the ledger mixes compact and
# spaced JSON, so `grep -c '"repo":"…"'` under-counts the spaced records silently.) So the
# allowlist is stored as a
# JSON ARRAY, defaults to the CURRENT remote's owner/repo on a fresh install (never a hardcoded
# owner — the plugin ships to other users), and is extended by hand when a repo is renamed.
#
# WHY here: this is the deterministic, mechanizable engine. The INTERACTIVE half — the
# consent-bearing AskUserQuestion offer that must be answered BEFORE anything is written — lives
# in the COMMAND layer (commands/setup.md), not here. This script probes, reports, and performs
# the two contained writes it is told to perform.
#
# CONSENT IS LOAD-BEARING: applying this makes a user's agent memory VERSION-CONTROLLED, and it
# travels wherever the repo travels (a public repo publishes it). Agent memory can hold
# proprietary architecture, internal service names, or client detail. `check` prints the exact
# disclosure the command layer must show before offering to apply; `apply` reprints it.
#
# FAIL-SAFE CONTRACT (mirrors setup-twin.sh / build-bridge.sh / read-bridge.sh): every branch —
# no git repo, absent .gitignore, unparseable .gitignore, missing jq — STILL `exit 0`. The helper
# NEVER blocks a session, NEVER gates, NEVER changes a heal_decision or a review decision.
# Machine-readable status lines (`apply: …` / `remove: …` / `Memory readiness: …`) carry the
# outcome instead of an exit code.
#
# THE LEDGER GATE DOES NOT BREAK THAT CONTRACT. "Fails closed" here means REFUSE-TO-WRITE plus a
# named-slug status line plus `exit 0` — never a non-zero exit. The gate withholds a write; it
# never blocks a caller. Implementing it as a non-zero exit would regress every non-blocking
# caller that treats this helper as advisory.
#
# WRITE-CONTAINMENT INVARIANT: the ONLY things this helper writes are, under the resolved repo
# root, (a) `.gitignore` plus one timestamped `.gitignore.backup.<ts>` sibling (suffixed with the
# pid, then a counter, when that name is already taken — a backup NEVER overwrites another, and if
# every candidate name is taken the write is REFUSED outright rather than clobbering one), and (b)
# `.supervisor/config.json` `.setup_memory.repo_allowlist` (backup-first jq merge that preserves
# every unrelated key). It writes NOTHING under `~/.claude/`, and it NEVER runs `git add`,
# `git rm`, `git commit` or any other history-touching command. `check`, `allowlist` and
# `filter-ledger` write nothing at all.
#
# TRACKED-WRITE RISK (stated here, deliberately NOT fixed here): once `.claude/agent-memory/` is
# tracked, every memory write becomes a working-tree modification — it shows in `git status`, can
# be swept into an unrelated commit by `git add -A`, and MEMORY.md becomes a conflict surface
# under parallel workers. Today that is near-theoretical (hand-written, rare). The mitigation
# belongs to the memory-writer item (agent writes land in a gitignored proposal queue; only
# /dreaming-promoted entries touch the tracked store) — building a proposal queue here is OUT OF
# SCOPE by design.
#
# Usage:
#   setup-memory.sh check                          # report: ignore status per path + allowlist (no writes)
#   setup-memory.sh apply                          # write the negation block + seed the allowlist
#   setup-memory.sh remove                         # undo the negation block (does NOT unpublish history)
#   setup-memory.sh allowlist                      # print the resolved allowlist, one entry per line
#   setup-memory.sh filter-ledger --ledger F       # print ledger records whose .repo is in the allowlist
#   setup-memory.sh filter-ledger --ledger F --allow owner/repo --allow owner/old-name
#   setup-memory.sh --root /path/to/repo check     # point at a fixture repo
#   setup-memory.sh -h | --help
#
# Exit: 0 in every normal path.

set -uo pipefail

# ---- managed-block constants (timestamp-FREE by design: apply/remove compare the proposed
#      content byte-for-byte against the current file to decide "already configured") ---------
MB_BEGIN='# >>> loomwright /setup memory BEGIN — committable Twin stores (managed block) >>>'
MB_END='# <<< loomwright /setup memory END <<<'
DISABLED_MARK='# [loomwright/setup-memory] disabled: a bare directory exclude defeats the negation below'

# ---- arg parsing ------------------------------------------------------------
SUBCMD=""
ROOT_OVERRIDE=""
LEDGER=""
ALLOW_FLAGS=""     # newline-separated (bash-3.2-safe: no arrays needed downstream)

usage() {
  # Print the leading header comment block (line 2 through the last contiguous `#` line),
  # robust to header edits — no hard-coded line range to drift when the header grows/shrinks.
  awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "${BASH_SOURCE[0]}"
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    check|apply|remove|allowlist|filter-ledger)
      [ -z "$SUBCMD" ] && SUBCMD="$1"; shift ;;
    --root)
      # Require a following value. Shift the flag first, then the value ONLY if present — a bare
      # trailing `--root` must NOT `shift 2` (that underflows when $#<2 and would re-process the
      # same arg → spin). A valueless --root is a usage error, never a silent fall-back.
      if [ $# -lt 2 ]; then
        echo "setup-memory: --root requires a path argument" >&2
        exit 0
      fi
      ROOT_OVERRIDE="$2"; shift 2 ;;
    --ledger)
      if [ $# -lt 2 ]; then
        echo "setup-memory: --ledger requires a path argument" >&2
        exit 0
      fi
      LEDGER="$2"; shift 2 ;;
    --allow)
      if [ $# -lt 2 ]; then
        echo "setup-memory: --allow requires an owner/repo argument" >&2
        exit 0
      fi
      ALLOW_FLAGS="${ALLOW_FLAGS}${2}
"
      shift 2 ;;
    -h|--help) usage ;;
    *) echo "setup-memory: unknown arg '$1' (try --help)" >&2; shift ;;
  esac
done

[ -z "$SUBCMD" ] && usage

# ---- repo root resolution ---------------------------------------------------
# When --root is given, use it verbatim and do NOT require it to be a git repo (testability).
if [ -n "$ROOT_OVERRIDE" ]; then
  repo="$ROOT_OVERRIDE"
else
  repo="$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
GI="$repo/.gitignore"
CFG="$repo/.supervisor/config.json"

# ---- probe paths ------------------------------------------------------------
# INTENDED: must be committable after apply. The two `.`-prefixed sidecars are listed separately
# from the `**` cases on purpose — a dotfile inside a re-included directory is its own
# silent-failure class, and losing them strips provenance from a fresh clone (read-lessons.sh's
# read-side provenance gate depends on them).
INTENDED_PATHS='.claude/agent-memory/loomwright:supervisor/MEMORY.md
.claude/agent-memory/loomwright:supervisor/.provenance.jsonl
.supervisor/memory/LESSONS.md
.supervisor/memory/.lessons-provenance.jsonl'

# The THIRD store, held separately from INTENDED_PATHS on purpose: its membership in the probed
# intended set is CONDITIONAL on the ledger gate passing. Folding it into INTENDED_PATHS would make
# a CORRECT refusal report as `not configured`, whose remediation copy tells the user to comment out
# "the surviving exclude" — which for a withheld ledger is this module's OWN `.supervisor/*` line.
# That is exactly the wrong remedy, and commands/setup.md mandates relaying it verbatim. See the
# `gated` verdict class in render_report() / warn_if_not_configured().
LEDGER_INTENDED_PATH='.supervisor/postmortem/results.jsonl'

# UNINTENDED: must stay ignored (worktree checkouts, machine-local settings, session logs).
UNINTENDED_PATHS='.claude/worktrees/busy-darwin/README.md
.claude/settings.local.json
.supervisor/logs/session.jsonl'

# ---- primitive probes (REAL commands only — never assert an unprobed state) --

# ignore_status <repo-relative path> → ignored | committable | unknown
# `git check-ignore` is pattern-based: the path need not exist. Exit 0 = ignored, 1 = not
# ignored, 128 = error (not a git repo / bad usage) → reported as `unknown`, never a crash.
ignore_status() {
  local p="$1" rc
  git -C "$repo" check-ignore -q -- "$p" >/dev/null 2>&1
  rc=$?
  case "$rc" in
    0) echo "ignored" ;;
    1) echo "committable" ;;
    *) echo "unknown" ;;
  esac
}

# tracked_count <repo-relative prefix> → number of files git currently TRACKS under it ("?" when
# the repo can't be queried). Load-bearing for `remove`: un-ignoring is not un-tracking.
tracked_count() {
  local p="$1" n
  n="$(git -C "$repo" ls-files -- "$p" 2>/dev/null | wc -l | tr -d ' ')"
  case "$n" in ''|*[!0-9]*) echo "?" ;; *) echo "$n" ;; esac
}

# gitignore_gate → ok | absent | "unparseable: <reason>"
# Deliberately conservative: anything this rewriter cannot round-trip safely is refused OUTRIGHT
# rather than half-written. A refusal changes nothing and says why.
gitignore_gate() {
  if [ -L "$GI" ]; then
    echo "unparseable: .gitignore is a symlink (refusing to follow it and rewrite someone else's file)"
    return
  fi
  if [ ! -e "$GI" ]; then
    echo "absent"
    return
  fi
  if [ ! -f "$GI" ]; then
    echo "unparseable: .gitignore exists but is not a regular file"
    return
  fi
  if [ ! -r "$GI" ] || [ ! -w "$GI" ]; then
    echo "unparseable: .gitignore is not both readable and writable"
    return
  fi
  # Binary content — a NUL byte means this is not a line-oriented ignore file. Detected by
  # comparing the file against a NUL-stripped copy of itself: bash cannot hold a NUL in a
  # variable, so `grep $'\0'` would silently degrade to an empty pattern that matches EVERY
  # file (it would flag every .gitignore as binary). `tr | cmp -` is portable to BSD and GNU.
  if ! LC_ALL=C tr -d '\000' < "$GI" 2>/dev/null | cmp -s - "$GI" 2>/dev/null; then
    echo "unparseable: .gitignore contains NUL bytes (binary, not a line-oriented ignore file)"
    return
  fi
  # An unresolved merge is a hand-editing state, not a file to rewrite underneath the user.
  if grep -qE '^(<<<<<<< |=======$|>>>>>>> )' "$GI" 2>/dev/null; then
    echo "unparseable: .gitignore contains unresolved git conflict markers"
    return
  fi
  # Sentinel sanity: at most one BEGIN and one END, BEGIN first. A half-deleted or duplicated
  # managed block is exactly the hand-edited case that must NOT be blind-repaired.
  # NOTE: `grep -c` PRINTS 0 and EXITS 1 on no-match, so a `|| echo 0` fallback would append a
  # SECOND line ("0\n0") and break every numeric test below. Swallow the status with `|| true`
  # and only default when the output is genuinely empty.
  # MATCHER INVARIANT: `grep -F` here is SUBSTRING-anywhere-on-the-line, and strip_managed_block()
  # MUST use the same rule (see its header) — a gate that counts a sentinel the stripper cannot
  # remove makes `apply` append a second block and brick the file.
  local nb ne lb le
  nb="$(grep -cF "$MB_BEGIN" "$GI" 2>/dev/null || true)"; [ -n "$nb" ] || nb=0
  ne="$(grep -cF "$MB_END" "$GI" 2>/dev/null || true)"; [ -n "$ne" ] || ne=0
  if [ "$nb" -gt 1 ] || [ "$ne" -gt 1 ]; then
    echo "unparseable: duplicated managed-block sentinels (BEGIN x$nb, END x$ne)"
    return
  fi
  if [ "$nb" -ne "$ne" ]; then
    echo "unparseable: unbalanced managed-block sentinels (BEGIN x$nb, END x$ne)"
    return
  fi
  if [ "$nb" -eq 1 ]; then
    lb="$(grep -nF "$MB_BEGIN" "$GI" | head -n1 | cut -d: -f1)"
    le="$(grep -nF "$MB_END" "$GI" | head -n1 | cut -d: -f1)"
    if [ "$lb" -ge "$le" ]; then
      echo "unparseable: managed-block END sentinel precedes its BEGIN sentinel"
      return
    fi
  fi
  echo "ok"
}

# managed_block_present → yes | no  (assumes the gate already passed)
managed_block_present() {
  if [ -f "$GI" ] && grep -qF "$MB_BEGIN" "$GI" 2>/dev/null; then echo "yes"; else echo "no"; fi
}

# ---- content transforms (pure: stdin → stdout, no writes) -------------------

# Strip an existing managed block (BEGIN..END inclusive).
#
# ONE MATCHER, TWO CALLERS (invariant — do not split these again). The presence gate
# (gitignore_gate / managed_block_present) counts sentinels with `grep -F`, i.e. the sentinel
# ANYWHERE on the line, so this stripper must use the SAME rule — `index() > 0`, never a
# column-1 anchor. When the two disagreed, a merely INDENTED BEGIN sentinel passed the gate as
# "one valid block" but was NOT stripped, so `apply` appended a SECOND block. The file then held
# BEGIN x2 / END x2 and every later `apply` AND `remove` aborted with `unparseable: duplicated
# managed-block sentinels` — a corrupt state the tool created itself and then refused to repair.
# Substring matching is safe here because the sentinels are full, highly distinctive lines: a
# line that contains one verbatim IS that sentinel (indented, or otherwise re-wrapped by hand).
strip_managed_block() {
  awk -v b="$MB_BEGIN" -v e="$MB_END" '
    index($0, b) > 0 { skip = 1 }
    skip == 1 { if (index($0, e) > 0) skip = 0; next }
    { print }
  '
}

# Comment out directory-shaped excludes that would defeat the negation. A bare `.claude/` excludes
# the DIRECTORY, so git never descends into it and no later `!` line can re-include anything
# below it — the line must be neutralized, not merely out-ordered. Commenting (rather than
# deleting) keeps the user's original text and makes `remove` exactly reversible.
#
# The `**` FAMILY COUNTS TOO. `.claude/**` matches every path below the directory, and since git
# applies the LAST matching rule, it still wins over a later `!.claude/agent-memory/` (which is
# directory-only and never matches the files inside). `**/.claude/` is just a bare directory
# exclude spelled for any depth. Leaving any of these live produced a silently dead negation
# under an unqualified `apply: applied` headline, so they are neutralized alongside the bare form.
#
# `X/*` is DELIBERATELY ABSENT from the set — but NOT because commenting it could neutralise this
# module's own fix. It cannot: proposed_applied_content() pipes ONLY the stripped pre-existing file
# through this filter and appends managed_block() AFTERWARDS, so the block's own `.claude/*` never
# passes through here and self-neutralisation is structurally impossible. The real reason is that
# `X/*` is not an obstacle at all: it excludes the directory's CONTENTS while leaving the directory
# traversable, which is exactly the shape the `!` lines need, so a user who already wrote it is
# already correct. Commenting it out would be pointless churn on a line doing no harm (and `remove`
# would then have to restore it). Pinned by test — see test-setup-memory.sh group (b3), which seeds
# a pre-existing `.claude/*` and asserts it SURVIVES apply UNCOMMENTED.
#
# THE MATCH IS TRAILING-WHITESPACE-TOLERANT AND NOTHING MORE, ON PURPOSE — it mirrors GIT'S OWN
# lexer, which is the only correct reference. Git strips TRAILING whitespace from a pattern (so
# `.claude/   ` really does exclude `.claude/` — hence the `sub(/[ \t\r]+$/,"")` below), but it does
# NOT strip leading whitespace and it has NO inline-comment syntax: only a line whose FIRST
# character is `#` is a comment. Therefore:
#   `   .claude/`          → git treats it as a pattern for a directory literally named `   .claude`
#   `.claude/   # my note` → git treats it as a pattern containing ` # my note`
# NEITHER ignores anything under `.claude/` (verified with `git check-ignore` on git 2.50 — both
# forms leave `.claude/agent-memory/**` AND `.claude/settings.local.json` committable). So these are
# NOT obstacles to the negation, and commenting them out would be a behaviour change that alters a
# user's file for no benefit. Leaving them live is the CORRECT outcome, not an escape hatch — and it
# is asserted, not assumed, by test-setup-memory.sh group (b5).
# Corollary: if a user MEANT `.claude/` and typed one of these, their exclude was already dead before
# this module ran; the post-write verdict still reports the real, probed status either way.
comment_bare_excludes() {
  awk -v mark="$DISABLED_MARK" '
    BEGIN {
      nn = split(".claude .supervisor", names, " ")
      nf = split("@ @/ /@ /@/ @/** /@/** **/@ **/@/ **/@/**", forms, " ")
      for (i = 1; i <= nn; i++) {
        for (j = 1; j <= nf; j++) {
          p = forms[j]
          gsub(/@/, names[i], p)
          blocking[p] = 1
        }
      }
    }
    {
      t = $0
      sub(/[ \t\r]+$/, "", t)
      if (t in blocking) {
        print "# " $0 "   " mark
      } else {
        print
      }
    }
  '
}

# Inverse of comment_bare_excludes.
uncomment_bare_excludes() {
  awk -v mark="$DISABLED_MARK" '
    {
      line = $0
      p = index(line, "   " mark)
      if (p > 0 && substr(line, 1, 2) == "# ") {
        print substr(line, 3, p - 3)
        next
      }
      print line
    }
  '
}

# The canonical managed block.
#
# BYTE-STABILITY, RESTATED HONESTLY (it is NOT broken — it is a function of one more input). The
# block is a PURE FUNCTION OF (the pre-existing .gitignore contents, the ledger gate outcome). For a
# FIXED gate outcome it is byte-identical across runs, which is exactly what the byte-compare
# idempotency contract requires. But the gate outcome IS an input now, so a repo that applied
# cleanly and LATER gains a foreign record will legitimately rewrite .gitignore on the next apply,
# WITHDRAWING the ledger negation. That transition is correct fail-closed behaviour and do_apply
# ANNOUNCES it — it is never a silent `apply: applied`.
#
# The alternative (emit the ledger lines unconditionally and gate only the verdict) was considered
# and REJECTED: it would have `apply` un-ignore an unfiltered cross-repo ledger, which is precisely
# the failure this gate exists to prevent.
managed_block() {
  printf '%s\n' "$MB_BEGIN"
  cat <<'BLOCK'
# Negate CONTENTS, not the directory. Git cannot re-include a file whose parent directory is
# excluded, so the naive form
#     .claude/
#     !.claude/agent-memory/
# looks correct and silently does NOTHING. The `/*` form below excludes the directory's contents
# and leaves the directory itself traversable, so the `!` lines can re-include.
#
# Committed on purpose: the Twin's accumulated judgment (agent memory + distilled lessons),
# including their dot-prefixed provenance sidecars, and — when the repo-allowlist gate passes — the
# findings ledger `.supervisor/postmortem/results.jsonl`. Everything else under these three
# directories stays ignored: worktree checkouts, machine-local settings, session logs, job briefs,
# automate run-files, and every other file under `.supervisor/postmortem/`.
#
# Managed by `/setup memory`. Edit via that command (`/setup memory remove` reverts it);
# hand-edits inside these sentinels are overwritten on the next apply.
.claude/*
!.claude/agent-memory/
.supervisor/*
!.supervisor/memory/
BLOCK
  if ledger_gate_permits_negation; then
    cat <<'LEDGERBLOCK'
# The findings ledger, un-ignored only because every record's `.repo` is inside this repo's
# allowlist (`setup-memory.sh allowlist`). THREE lines, in THIS ORDER, and AFTER `.supervisor/*`:
# the first re-includes the DIRECTORY so git will descend into it, the second re-excludes its
# CONTENTS so nothing else there leaks, the third re-includes the one file. A single naive
# `!.supervisor/postmortem/results.jsonl` does NOTHING (its parent directory is excluded), and the
# same three lines placed BEFORE `.supervisor/*` do nothing either — both are pinned as negative
# controls in test-setup-memory.sh.
!.supervisor/postmortem/
.supervisor/postmortem/*
!.supervisor/postmortem/results.jsonl
LEDGERBLOCK
  fi
  printf '%s\n' "$MB_END"
}

# The exact content apply WOULD write (deterministic → byte-comparable for idempotency).
proposed_applied_content() {
  strip_managed_block < "$GI" | comment_bare_excludes
  managed_block
}

# The exact content remove WOULD write.
proposed_removed_content() {
  strip_managed_block < "$GI" | uncomment_bare_excludes
}

# unique_backup_path <file> → a `<file>.backup.<ts>` sibling that does NOT already exist, or
# NOTHING (empty stdout, status 1) when every candidate name is taken.
#
# The timestamp is second-granular, so two writes inside the SAME second resolve to the same name
# and the second `cp` would OVERWRITE the first backup — destroying the user's PRISTINE original,
# which is the single file the whole backup-first contract exists to protect (the later backup
# only holds this tool's own output). The plain `<file>.backup.<ts>` form is kept for the common
# case because it is the documented name; a collision falls back to a pid-qualified name, then to
# a counter bounded at $BACKUP_MAX_TRIES.
#
# EXHAUSTION FAILS CLOSED. The bounded counter cannot promise "a free name always exists", so when
# it runs out this returns EMPTY rather than a path it never verified — an earlier version fell out
# of the loop at the bound and returned `$base.$$.<bound>` WITH that file still present, which the
# caller's `cp` would then have overwritten. Callers MUST treat empty as "no backup is possible"
# and abort without writing (write_gitignore / seed_allowlist both do). Asserted in
# test-setup-memory.sh group (e), which seeds every candidate name and asserts the write is refused
# and the pre-existing backup is left byte-identical.
BACKUP_MAX_TRIES=1000
unique_backup_path() {
  local f="$1" ts base n
  ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo unknown)"
  base="$f.backup.$ts"
  if [ ! -e "$base" ]; then printf '%s' "$base"; return 0; fi
  if [ ! -e "$base.$$" ]; then printf '%s' "$base.$$"; return 0; fi
  n=1
  while [ "$n" -le "$BACKUP_MAX_TRIES" ]; do
    if [ ! -e "$base.$$.$n" ]; then printf '%s' "$base.$$.$n"; return 0; fi
    n=$((n + 1))
  done
  return 1
}

# Backup-first + atomic replace. Echoes the backup path on success.
write_gitignore() {
  local content="$1" backup tmp
  backup="$(unique_backup_path "$GI")"
  if [ -z "$backup" ]; then
    echo "setup-memory: every backup name for $GI is already taken (${BACKUP_MAX_TRIES}+ collisions); refusing to overwrite an existing backup — nothing changed." >&2
    return 1
  fi
  cp "$GI" "$backup" 2>/dev/null || { echo "setup-memory: could not write backup $backup — nothing changed." >&2; return 1; }
  tmp="$GI.tmp.$$"
  printf '%s\n' "$content" > "$tmp" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; echo "setup-memory: could not stage the rewrite — nothing changed." >&2; return 1; }
  mv "$tmp" "$GI" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; echo "setup-memory: could not replace .gitignore — nothing changed." >&2; return 1; }
  printf '%s' "$backup"
}

# ---- allowlist --------------------------------------------------------------

ALLOWLIST=""
ALLOWLIST_SOURCE="none"

# Parse `owner/repo` out of a git remote URL. Handles https, ssh scp-style, and ssh:// forms;
# strips a trailing `.git`. Echoes nothing when it cannot decide — NEVER guesses an owner.
remote_slug() {
  local url slug head
  url="$(git -C "$repo" remote get-url origin 2>/dev/null || true)"
  [ -n "$url" ] || return 0
  # A FILESYSTEM-PATH remote carries no owner at all. `origin = /Users/x/myrepo` has the same
  # shape as `host/owner/repo` once you only look at the last two segments, so the naive tail
  # split would return `x/myrepo` — an owner invented from a parent directory name, which is
  # exactly what this function promises never to do. Decide it is a path and return nothing.
  case "$url" in
    # NOTE the QUOTED tilde: bash tilde-expands `case` PATTERNS, so a bare `~*` would silently
    # become the developer's own home path and stop matching a literal `~/...` remote.
    /*|./*|../*|'~'*|file://*) return 0 ;;
  esac
  slug="$url"
  slug="${slug%.git}"
  slug="${slug%/}"
  case "$slug" in
    *://*|*:*) : ;;                 # a scheme or an scp-style `host:` — a real remote URL
    *)
      # No scheme and no colon: only a HOST-LIKE leading segment can be followed by an owner.
      # `subdir/myrepo` or a bare `myrepo` is a relative path, not `owner/repo`.
      head="${slug%%/*}"
      case "$head" in
        *.*|localhost) : ;;
        *) return 0 ;;
      esac ;;
  esac
  case "$slug" in
    *:*/*)  slug="${slug##*:}" ;;   # git@host:owner/repo  → owner/repo
  esac
  # For URL forms the tail is still host/owner/repo — keep the LAST two segments.
  local repo_part owner_part rest
  repo_part="${slug##*/}"
  rest="${slug%/*}"
  owner_part="${rest##*/}"
  [ -n "$repo_part" ] && [ -n "$owner_part" ] || return 0
  case "$owner_part" in *:*) return 0 ;; esac   # no owner segment at all
  printf '%s/%s\n' "$owner_part" "$repo_part"
}

# load_allowlist — resolve the allowlist INTO THE GLOBALS $ALLOWLIST (newline-separated entries)
# and $ALLOWLIST_SOURCE (a human-readable provenance label). It must run in the CURRENT shell:
# a command substitution would evaluate it in a SUBSHELL and the source label would never reach
# the caller (the entries would look right while the reported provenance stayed stale).
#
# Precedence (first non-empty wins):
#   1. --allow flags (repeatable)
#   2. $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST (newline-, comma- or colon-separated)
#   3. .supervisor/config.json  .setup_memory.repo_allowlist[]   (a JSON ARRAY — the stored shape)
#   4. default: the CURRENT git remote's owner/repo (fresh-install default; never a hardcoded owner)
#
# It is a LIST at every layer. A repo RENAME is the documented reason: records written before the
# rename carry the old slug, and a live-remote-keyed filter would silently drop them. This is also
# why layer 4 is only a DEFAULT — `apply` snapshots it into config, and every later read comes from
# config, so renaming the remote afterwards does not retroactively change what the filter retains.
load_allowlist() {
  local out=""
  ALLOWLIST_SOURCE="none"
  if [ -n "$ALLOW_FLAGS" ]; then
    out="$ALLOW_FLAGS"
    ALLOWLIST_SOURCE="--allow flags"
  fi
  if [ -z "$out" ] && [ -n "${LOOMWRIGHT_MEMORY_REPO_ALLOWLIST:-}" ]; then
    out="$(printf '%s' "$LOOMWRIGHT_MEMORY_REPO_ALLOWLIST" | tr ',:' '\n\n')"
    ALLOWLIST_SOURCE="env LOOMWRIGHT_MEMORY_REPO_ALLOWLIST"
  fi
  if [ -z "$out" ] && command -v jq >/dev/null 2>&1 && [ -f "$CFG" ]; then
    local kind
    kind="$(jq -r '.setup_memory.repo_allowlist | type' "$CFG" 2>/dev/null || true)"
    if [ "$kind" = "array" ]; then
      out="$(jq -r '(.setup_memory.repo_allowlist // [])[] | select(type == "string")' "$CFG" 2>/dev/null || true)"
      ALLOWLIST_SOURCE="config .setup_memory.repo_allowlist"
    elif [ "$kind" = "string" ]; then
      # Tolerated on READ so a hand-edit is not silently dropped, but it IS a misconfiguration:
      # the stored shape is an ARRAY precisely so a renamed repo can list both slugs.
      echo "setup-memory: WARNING — .setup_memory.repo_allowlist is a STRING in $CFG; it MUST be a JSON array (a renamed repo needs both slugs). Coercing to a single-entry list." >&2
      out="$(jq -r '.setup_memory.repo_allowlist' "$CFG" 2>/dev/null || true)"
      ALLOWLIST_SOURCE="config .setup_memory.repo_allowlist (string — coerced, fix it)"
    fi
  fi
  if [ -z "$out" ]; then
    out="$(remote_slug)"
    if [ -n "$out" ]; then
      ALLOWLIST_SOURCE="default (current git remote)"
    else
      ALLOWLIST_SOURCE="unset (no git remote to default from)"
    fi
  fi
  # Trim, drop blanks, de-duplicate while preserving order.
  ALLOWLIST="$(printf '%s\n' "$out" | awk 'NF { sub(/^[ \t]+/,""); sub(/[ \t\r]+$/,""); if ($0 != "" && !seen[$0]++) print }')"
}

# resolve_allowlist — print the resolved repo allowlist, ONE ENTRY PER LINE (empty output when
# nothing resolves). This is the reusable predicate half of the pair: safe to call from a command
# substitution. Use load_allowlist directly when you also need $ALLOWLIST_SOURCE.
resolve_allowlist() {
  load_allowlist
  [ -n "$ALLOWLIST" ] && printf '%s\n' "$ALLOWLIST"
  return 0
}

# Seed the allowlist into .supervisor/config.json as a JSON ARRAY. Backup-first, parse-gated,
# atomic, and idempotent: an existing non-empty array is NEVER overwritten (a renamed repo's
# hand-added second slug must survive re-apply).
seed_allowlist() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "  allowlist: SKIPPED — jq not available (config unchanged)."
    return 0
  fi
  local existing_kind existing_len entries json
  if [ -f "$CFG" ]; then
    if ! jq empty "$CFG" >/dev/null 2>&1; then
      echo "  allowlist: SKIPPED — $CFG exists but is not valid JSON; fix it by hand (nothing was written)."
      return 0
    fi
    existing_kind="$(jq -r '.setup_memory.repo_allowlist | type' "$CFG" 2>/dev/null || echo null)"
    existing_len="$(jq -r '(.setup_memory.repo_allowlist // []) | if type == "array" then length else 0 end' "$CFG" 2>/dev/null || echo 0)"
    if [ "$existing_kind" = "array" ] && [ "${existing_len:-0}" -gt 0 ]; then
      echo "  allowlist: already configured ($existing_len entr$([ "$existing_len" = "1" ] && echo y || echo ies)) — left untouched."
      return 0
    fi
  fi
  entries="$(resolve_allowlist)"
  if [ -z "$entries" ]; then
    echo "  allowlist: SKIPPED — no git remote to default from and nothing configured; seed it by hand:"
    echo "             jq '.setup_memory.repo_allowlist = [\"owner/repo\"]' $CFG"
    return 0
  fi
  json="$(printf '%s\n' "$entries" | jq -R . | jq -s .)" || return 0
  mkdir -p "$(dirname "$CFG")" 2>/dev/null
  local tmp="$CFG.tmp.$$"
  if [ -f "$CFG" ]; then
    # Backup-first here too, and fail CLOSED when no free backup name exists — an unbacked-up
    # rewrite of a user's config is exactly what the backup-first contract forbids.
    local cfg_backup
    cfg_backup="$(unique_backup_path "$CFG")"
    if [ -z "$cfg_backup" ] || ! cp "$CFG" "$cfg_backup" 2>/dev/null; then
      rm -f "$tmp" 2>/dev/null
      echo "  allowlist: SKIPPED — could not write a backup of $CFG; refusing to rewrite it unbacked-up (unchanged)."
      return 0
    fi
    jq --argjson a "$json" '.setup_memory = ((.setup_memory // {}) | .repo_allowlist = $a)' "$CFG" > "$tmp" 2>/dev/null \
      && mv "$tmp" "$CFG" 2>/dev/null \
      || { rm -f "$tmp" 2>/dev/null; echo "  allowlist: SKIPPED — could not merge into $CFG (unchanged)."; return 0; }
  else
    jq -n --argjson a "$json" '{setup_memory: {repo_allowlist: $a}}' > "$tmp" 2>/dev/null \
      && mv "$tmp" "$CFG" 2>/dev/null \
      || { rm -f "$tmp" 2>/dev/null; echo "  allowlist: SKIPPED — could not create $CFG (unchanged)."; return 0; }
  fi
  echo "  allowlist: seeded as a JSON array → $(printf '%s' "$entries" | tr '\n' ' ')"
  echo "             (a repo RENAME needs the OLD slug added by hand — the list shape exists for exactly that.)"
}

# filter_ledger_by_allowlist <ledger-path> [allow-entry ...]
#
# Prints, one per line, the JSONL records whose `.repo` is in the allowlist. Records with a
# missing/null/empty `.repo` are EXCLUDED — an unattributable record cannot be shown to belong to
# this repo, and the cost of wrongly publishing another repo's record is higher than dropping one.
# An EMPTY allowlist retains NOTHING (never "everything") for the same reason.
# Unparseable lines are skipped with a stderr note; a corrupt line never aborts the filter.
filter_ledger_by_allowlist() {
  local ledger="$1"; shift
  if ! command -v jq >/dev/null 2>&1; then
    echo "setup-memory: jq required for filter-ledger — skipping (nothing printed)." >&2
    return 0
  fi
  if [ ! -f "$ledger" ]; then
    echo "setup-memory: ledger not found at $ledger — skipping (nothing printed)." >&2
    return 0
  fi
  local allow_json
  if [ "$#" -eq 0 ]; then
    allow_json='[]'
    echo "setup-memory: WARNING — empty allowlist; NO records are retained (fail-closed by design)." >&2
  else
    allow_json="$(printf '%s\n' "$@" | jq -R . | jq -s .)" || return 0
  fi
  # Whole-file pass first (fast). If any line is malformed, jq aborts → fall back to a per-line
  # pass that skips only the bad lines.
  #
  # The status is captured from the ASSIGNMENT, not from an `if jq …; then` — after a failed
  # `if cmd; then …; fi` bash reports the exit status of the IF STATEMENT (0), not of `cmd`, so
  # reading `$?` there would always look successful and the fallback would be dead code.
  # No `-e`: without it jq exits 0 on a clean run that simply retained nothing.
  local out rc
  out="$(jq -c --argjson allow "$allow_json" \
          'select(((.repo // "") | tostring) as $r | ($allow | index($r)) != null)' \
          "$ledger" 2>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ]; then
    [ -n "$out" ] && printf '%s\n' "$out"
    return 0
  fi
  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    [ -n "$line" ] || continue
    printf '%s' "$line" | jq -c --argjson allow "$allow_json" \
      'select(((.repo // "") | tostring) as $r | ($allow | index($r)) != null)' 2>/dev/null \
      || echo "setup-memory: skipping unparseable ledger line $n" >&2
  done < "$ledger"
}

# ---- the findings-ledger gate (fails closed in the WRITE dimension, never in the exit status) --
#
# LEDGER_GATE_STATE ∈ { "" (unevaluated), pass, refuse, not-evaluated }
#   pass          — every record's `.repo` is inside the resolved allowlist (or there is no ledger)
#   refuse        — at least one record is outside it; $LEDGER_FOREIGN_SLUGS names the offenders
#   not-evaluated — jq is unavailable, so NOTHING was probed and no claim may be made either way
LEDGER_GATE_STATE=""
LEDGER_FOREIGN_SLUGS=""

# ONE jq PROGRAM, TWO CALLERS (the whole-file pass and the per-line fallback) so they cannot drift.
# It prints ONE LINE PER OFFENDING RECORD — the record's `.repo`, or a placeholder for an
# unattributable one. A record whose `.repo` IS allowlisted prints nothing.
#
# jq, NEVER grep. This ledger mixes compact (`"repo":"x"`) and spaced (`"repo": "x"`) JSON, so a
# compact-form grep under-counts silently AND a foreign record appended in the spaced form evades
# it entirely — which would make this gate a guard that cannot fire. Pinned by
# test-setup-memory.sh's test_gate_blocks_foreign_spaced_form.
LEDGER_GATE_JQ='((.repo // "") | tostring) as $r
  | select(($allow | index($r)) == null)
  | (if $r == "" then "(record with no .repo field)" else $r end)'

_evaluate_ledger_gate() {
  local ledger="$repo/$LEDGER_INTENDED_PATH"
  LEDGER_FOREIGN_SLUGS=""

  # jq ABSENT ⇒ the gate is NOT EVALUATED. It must NOT fail toward `refuse` (that would permanently
  # mis-report for every jq-less user) and must NOT fail toward emitting the negation (that would
  # publish an unchecked ledger). Nothing is probed and the pre-existing verdict is preserved —
  # mirroring the seed_allowlist / filter_ledger_by_allowlist skip-with-message guards.
  if ! command -v jq >/dev/null 2>&1; then
    LEDGER_GATE_STATE="not-evaluated"
    return 0
  fi
  # Ledger ABSENT ⇒ PASS. No records ⇒ no foreign records ⇒ nothing to withhold. This is the state
  # of every fresh user repo and of every fixture in the test suites.
  if [ ! -f "$ledger" ]; then
    LEDGER_GATE_STATE="pass"
    return 0
  fi

  local entries allow_json out rc line one orc n=0
  entries="$(resolve_allowlist)"
  if [ -n "$entries" ]; then
    allow_json="$(printf '%s\n' "$entries" | jq -R . | jq -s .)" || allow_json='[]'
  else
    # An EMPTY allowlist retains NOTHING (filter_ledger_by_allowlist's rule), so EVERY record is
    # outside it and the gate refuses. Fail-closed, never "nothing configured ⇒ everything is fine".
    allow_json='[]'
  fi

  out="$(jq -r --argjson allow "$allow_json" "$LEDGER_GATE_JQ" "$ledger" 2>/dev/null)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    # A malformed line aborts the whole-file pass. Fall back per line and count an UNPARSEABLE
    # record as FOREIGN: a record that cannot be parsed cannot be SHOWN to belong to this repo, and
    # the cost of publishing another repo's record is higher than the cost of withholding one.
    out=""
    while IFS= read -r line; do
      n=$((n + 1))
      [ -n "$line" ] || continue
      one="$(printf '%s' "$line" | jq -r --argjson allow "$allow_json" "$LEDGER_GATE_JQ" 2>/dev/null)"
      orc=$?
      if [ "$orc" -ne 0 ]; then
        out="${out}(unparseable record at ledger line $n)
"
      elif [ -n "$one" ]; then
        out="${out}${one}
"
      fi
    done < "$ledger"
  fi

  LEDGER_FOREIGN_SLUGS="$(printf '%s\n' "$out" | awk 'NF && !seen[$0]++')"
  if [ -n "$LEDGER_FOREIGN_SLUGS" ]; then
    LEDGER_GATE_STATE="refuse"
  else
    LEDGER_GATE_STATE="pass"
  fi
}

# ledger_gate_blocks_foreign_records → status 0 when the gate REFUSES (the ledger holds at least one
# record outside the allowlist, so the negation must be WITHHELD), 1 otherwise.
#
# Memoized per process. `managed_block()` is reached through TWO nested command substitutions on the
# apply path, so globals set inside them are discarded and the evaluation simply repeats there. That
# is safe ONLY because the evaluation is deterministic and side-effect-free — the result may never
# depend on call ORDER, and this function must never write anything.
ledger_gate_blocks_foreign_records() {
  [ -n "$LEDGER_GATE_STATE" ] || _evaluate_ledger_gate
  [ "$LEDGER_GATE_STATE" = "refuse" ]
}

# ledger_gate_permits_negation → status 0 when the ledger negation may be EMITTED and PROBED.
# ONLY `pass` permits it: `refuse` withholds it, and `not-evaluated` withholds it too (nothing was
# checked, so emitting would publish an unverified ledger).
ledger_gate_permits_negation() {
  [ -n "$LEDGER_GATE_STATE" ] || _evaluate_ledger_gate
  [ "$LEDGER_GATE_STATE" = "pass" ]
}

# ---- consent disclosure (the exact copy the command layer must show BEFORE applying) --------
print_consent_disclosure() {
  cat <<'DISCLOSURE'
What becomes VERSION-CONTROLLED if you apply this:
  · .claude/agent-memory/**   — every agent's persistent store (MEMORY.md + entry files +
                                 .provenance.jsonl sidecars)
  · .supervisor/memory/**     — distilled LESSONS.md / PROJECT_MEMORY.md + their
                                 .lessons-provenance.jsonl sidecars
  · .supervisor/postmortem/results.jsonl — the findings ledger (PR-churn analysis), and ONLY this
                                 one file; everything else under .supervisor/postmortem/ stays
                                 ignored. GATED: it is un-ignored only while every record's
                                 `.repo` is inside this repo's allowlist. If any record is not,
                                 the negation is WITHHELD, the offending slugs are named, and
                                 readiness reports `gated`.
These are COMMITTED IN PLACE — nothing is moved, symlinked or copied, so every agent keeps
reading its store from the same path it uses today.

Read this before saying yes:
  · Committing publishes. Agent memory can contain proprietary architecture, internal service
    names, client detail, or anything an agent inferred while working. It travels wherever the
    repo travels — a PUBLIC repo publishes it to everyone, and so does any fork or clone.
  · Removal does NOT unpublish. `/setup memory remove` stops FUTURE tracking; anything already
    committed and pushed stays in git history and on every remote that has it.
  · Writes become working-tree changes. Once tracked, memory writes show in `git status` and can
    be swept into an unrelated commit by `git add -A`; MEMORY.md becomes a merge-conflict surface
    when parallel workers write it.
  · THE LEDGER IS CROSS-REPO BY CONSTRUCTION. A `/pr-postmortem` append lands in the CURRENT
    working `.supervisor/`, never in the analysed repo's, so a ledger accumulates records
    belonging to OTHER repos. The allowlist gate refuses to un-ignore a ledger holding any such
    record — but it is evaluated AT APPLY TIME ONLY. A ledger that gains a foreign record AFTER a
    clean apply stays un-ignored until the next apply, and a routine `git add -A` can commit it in
    between. Run `setup-memory.sh filter-ledger --ledger .supervisor/postmortem/results.jsonl`
    before you commit. The gate is not complete coverage, and it does not look at finding TEXT —
    only at each record's `.repo` field.
What stays IGNORED (unchanged): .claude/worktrees/, .claude/settings.local.json,
.supervisor/logs/, every file under .supervisor/postmortem/ OTHER than results.jsonl, and
everything else under those three directories.
DISCLOSURE
}

# ---- report render (shared by check + apply/remove verify) ------------------
#
# render_report also PUBLISHES its conclusion into three globals so a caller can react to it without
# re-deriving (or re-guessing) the verdict:
#   $REPORT_VERDICT             — the readiness verdict string
#   $REPORT_BLOCKED_INTENDED    — newline-separated INTENDED paths that came back `ignored`
#                                 (UNDER-inclusion: a surviving exclude beats the negation)
#   $REPORT_LEAKED_UNINTENDED   — newline-separated UNINTENDED paths that came back `committable`
#                                 (OVER-inclusion: an over-broad `!` re-include; the `partial` case)
#   $REPORT_GATED / $REPORT_GATED_SLUGS
#                               — yes/no plus the offending repo slugs when the findings-ledger gate
#                                 REFUSED (the `gated` case: deliberately withheld, repo contaminated)
#
# THREE FAILURE MODES NOW, AND NONE OF THEM MAY SHARE COPY. `not configured` is UNDER-inclusion,
# `partial` is OVER-inclusion, and `gated` is a DELIBERATE withholding — a correct outcome, not a
# defect in the ignore rules. Handing a gated repo the under-inclusion remedy ("comment out the
# surviving exclude") would tell the user to delete this module's OWN `.supervisor/*` line, which is
# precisely the wrong fix. Hence the dedicated verdict class and the dedicated warning branch.
# The two lists are DISJOINT failure modes with opposite remedies, which is exactly why they are
# published separately — warn_if_not_configured() must never hand out under-inclusion guidance
# ("comment out the surviving exclude") for an over-inclusion failure, where there is no surviving
# exclude to name and commenting one out would make it worse.
# This must run in the CURRENT shell — every existing call site already does.
REPORT_VERDICT=""
REPORT_BLOCKED_INTENDED=""
REPORT_LEAKED_UNINTENDED=""
REPORT_GATED=""
REPORT_GATED_SLUGS=""

render_report() {
  local gate mb p st intended_ok=yes unintended_ok=yes probed=0 unknowns=0

  REPORT_VERDICT=""
  REPORT_BLOCKED_INTENDED=""
  REPORT_LEAKED_UNINTENDED=""
  REPORT_GATED="no"
  REPORT_GATED_SLUGS=""

  gate="$(gitignore_gate)"
  mb="$(managed_block_present)"

  echo "Memory store report for: $repo"
  echo "  .gitignore:        $gate"
  echo "  managed block:     $([ "$mb" = "yes" ] && echo present || echo absent)"

  echo "  intended (must be committable):"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    st="$(ignore_status "$p")"
    printf '    %-56s %s\n' "$p" "$st"
    probed=$((probed + 1))
    [ "$st" = "unknown" ] && unknowns=$((unknowns + 1))
    [ "$st" = "committable" ] || intended_ok=no
    if [ "$st" = "ignored" ]; then
      REPORT_BLOCKED_INTENDED="${REPORT_BLOCKED_INTENDED}${p}
"
    fi
  done <<EOF
$INTENDED_PATHS
EOF

  # THE THIRD STORE — probed ONLY when the ledger gate PASSES. When it refuses, the ledger is
  # deliberately withheld and must NOT be counted as a blocked intended path (that would make a
  # CORRECT refusal report as `not configured` and emit the destructive under-inclusion remedy).
  # When jq is absent nothing was evaluated, so nothing is claimed either way.
  if ledger_gate_permits_negation; then
    st="$(ignore_status "$LEDGER_INTENDED_PATH")"
    printf '    %-56s %s\n' "$LEDGER_INTENDED_PATH" "$st"
    probed=$((probed + 1))
    [ "$st" = "unknown" ] && unknowns=$((unknowns + 1))
    [ "$st" = "committable" ] || intended_ok=no
    if [ "$st" = "ignored" ]; then
      REPORT_BLOCKED_INTENDED="${REPORT_BLOCKED_INTENDED}${LEDGER_INTENDED_PATH}
"
    fi
  elif ledger_gate_blocks_foreign_records; then
    REPORT_GATED="yes"
    REPORT_GATED_SLUGS="$LEDGER_FOREIGN_SLUGS"
    printf '    %-56s %s\n' "$LEDGER_INTENDED_PATH" "GATED — withheld (records outside the allowlist)"
  else
    printf '    %-56s %s\n' "$LEDGER_INTENDED_PATH" "not probed (jq unavailable — gate not evaluated)"
  fi

  echo "  unintended (must stay ignored):"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    st="$(ignore_status "$p")"
    printf '    %-56s %s\n' "$p" "$st"
    probed=$((probed + 1))
    [ "$st" = "unknown" ] && unknowns=$((unknowns + 1))
    [ "$st" = "ignored" ] || unintended_ok=no
    if [ "$st" = "committable" ]; then
      REPORT_LEAKED_UNINTENDED="${REPORT_LEAKED_UNINTENDED}${p}
"
    fi
  done <<EOF
$UNINTENDED_PATHS
EOF

  echo "  tracked today:     .claude/agent-memory/ → $(tracked_count '.claude/agent-memory') file(s), .supervisor/memory/ → $(tracked_count '.supervisor/memory') file(s), $LEDGER_INTENDED_PATH → $(tracked_count "$LEDGER_INTENDED_PATH") file(s)"

  load_allowlist   # in-shell (not a subshell) so $ALLOWLIST_SOURCE is real, not stale
  if [ -n "$ALLOWLIST" ]; then
    echo "  allowlist:         $(printf '%s' "$ALLOWLIST" | tr '\n' ' ') [source: $ALLOWLIST_SOURCE]"
  else
    echo "  allowlist:         (empty) [source: $ALLOWLIST_SOURCE]"
  fi

  # UNKNOWN DOMINATES. Off a git repo every `git check-ignore` returns 128 → every cell is
  # `unknown`, which makes intended_ok=no AND unintended_ok=no and would fall through to
  # `partial (an unintended path is committable …)` — a claim about a state that was never
  # probed. Nothing here may assert an unprobed status, so say so instead.
  local verdict
  if [ "$probed" -gt 0 ] && [ "$unknowns" -eq "$probed" ]; then
    verdict="unknown (not a git repo — ignore status could not be probed)"
    REPORT_BLOCKED_INTENDED=""
    REPORT_LEAKED_UNINTENDED=""
  elif [ "$REPORT_GATED" = "yes" ]; then
    # THE THIRD CLASS. NOT `configured` (the ledger is deliberately withheld) and NOT
    # `not configured` (nothing about the ignore rules is wrong — the repo's LEDGER is contaminated).
    verdict="gated (the findings ledger is WITHHELD — records outside the allowlist: $(printf '%s' "$REPORT_GATED_SLUGS" | tr '\n' ' '))"
  elif [ "$intended_ok" = "yes" ] && [ "$unintended_ok" = "yes" ]; then
    verdict="configured"
  elif [ "$intended_ok" = "no" ] && [ "$unintended_ok" = "yes" ]; then
    verdict="not configured"
  else
    verdict="partial (an unintended path is committable — review the ignore rules by hand)"
  fi
  REPORT_VERDICT="$verdict"
  echo "Memory readiness: $verdict"
}

# After a write (or a no-op re-apply) the `apply: applied` headline on its own reads as
# unqualified success — but a pre-existing pattern this rewriter does not neutralise (a
# `.claude/agent-memory/**`, a rule in a PARENT .gitignore, or the global excludesfile) can still
# win for the intended paths, leaving a silently dead negation. Qualify the headline, and name the
# rule that actually wins from a REAL probe (`git check-ignore -v`) rather than guessing at it.
#
# THE TWO FAILURE MODES ARE OPPOSITES AND MUST NOT SHARE COPY. `not configured` is UNDER-inclusion
# (an intended path is still ignored → a surviving exclude wins) and its remedy is to comment out or
# re-order that exclude. `partial` is OVER-inclusion (an UNINTENDED path became committable → an
# over-broad `!` re-include wins) and its remedy is to NARROW the re-include; there is no surviving
# exclude to name, so the under-inclusion copy would print a bullet list of nothing and then tell the
# user to comment out a rule that does not exist and whose removal would leak MORE. Hence the
# dedicated branch below, pinned by test-setup-memory.sh group (b4).
#
# print_path_rules <newline-separated paths> — one path per bullet with the pattern that ACTUALLY
# wins for it, from a REAL `git check-ignore -v -n` probe, never a guess. `-n` is required for the
# over-inclusion list: without it check-ignore prints nothing for a path it does not ignore. A path
# that matches NO pattern at all comes back as a bare `::` record, which is reported as such.
print_path_rules() {
  local paths="$1" p src
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    src="$(git -C "$repo" check-ignore -v -n -- "$p" 2>/dev/null | head -n1)"
    case "$src" in
      ''|'::'*) src="(no pattern matches it at all — nothing is ignoring it)" ;;
    esac
    echo "         $p"
    echo "             <- $src"
  done <<EOF
$paths
EOF
}

warn_if_not_configured() {
  local _slug=""
  case "$REPORT_VERDICT" in
    configured) return 0 ;;
    unknown*)
      echo
      echo "apply: WARNING — readiness is '$REPORT_VERDICT'."
      echo "       The ignore status was never probed here, so nothing above confirms the negation took effect."
      return 0 ;;
    partial*)
      echo
      echo "apply: WARNING — readiness is '$REPORT_VERDICT', not 'configured'; a path that must stay"
      echo "       IGNORED is now COMMITTABLE. This is OVER-inclusion — the opposite of a surviving"
      echo "       exclude — so something is re-including MORE than the managed block asks for."
      echo "       These unintended paths are now COMMITTABLE, each with the rule that actually wins for it:"
      print_path_rules "$REPORT_LEAKED_UNINTENDED"
      if [ -n "$REPORT_BLOCKED_INTENDED" ]; then
        echo "       (Separately, these intended paths are STILL IGNORED — an under-inclusion failure on top:)"
        print_path_rules "$REPORT_BLOCKED_INTENDED"
      fi
      echo "       An over-broad '!' re-include is the cause: a '!.claude/**'-shaped line, or a '!' rule"
      echo "       in a NESTED .gitignore (e.g. .claude/.gitignore), which takes PRECEDENCE over the root"
      echo "       file and so survives this block. NARROW or delete the re-include named above — do NOT"
      echo "       comment out an exclude here; an exclude is not what is failing, and removing one would"
      echo "       leak more. Nothing else about the write is in doubt: the managed block IS in place and"
      echo "       a backup of the previous file sits beside it."
      return 0 ;;
    gated*)
      # MUST sit AHEAD of the fall-through below, which is the UNDER-inclusion copy. A gated repo is
      # not under-including anything: the two memory stores ARE applied and the ledger is withheld
      # ON PURPOSE. Telling the user to "comment out the surviving exclude" would point them at this
      # module's own `.supervisor/*` line and un-ignore the contaminated ledger — the exact outcome
      # the gate exists to prevent. Pinned by test-setup-memory.sh group (m).
      echo
      echo "apply: WITHHELD — the two memory stores are applied, but the findings ledger"
      echo "       ($LEDGER_INTENDED_PATH) is NOT un-ignored. This is the gate"
      echo "       working, not a failure of the ignore rules — do NOT comment out any exclude."
      echo "       These repo slugs appear in the ledger but are NOT in this repo's allowlist:"
      while IFS= read -r _slug; do
        [ -n "$_slug" ] || continue
        echo "         · $_slug"
      done <<EOF
$REPORT_GATED_SLUGS
EOF
      echo "       Remedy — either drop the foreign records, or widen the allowlist if they really"
      echo "       are this repo's:"
      echo "         bash setup-memory.sh filter-ledger --ledger $LEDGER_INTENDED_PATH > /tmp/ledger.filtered"
      echo "         mv /tmp/ledger.filtered $LEDGER_INTENDED_PATH   # review it first"
      echo "         # …or: jq '.setup_memory.repo_allowlist += [\"owner/repo\"]' .supervisor/config.json"
      echo "       then re-run apply. The two memory stores stay applied throughout."
      echo "       NOTE: withholding does NOT un-track a ledger that is ALREADY COMMITTED —"
      echo "       .gitignore only governs UNTRACKED files. If it is already tracked, filter it and"
      echo "       run 'git rm -r --cached $LEDGER_INTENDED_PATH' yourself, then re-commit."
      if [ -n "$REPORT_LEAKED_UNINTENDED" ]; then
        echo "       Separately — and independently of the gate — these paths that must stay IGNORED"
        echo "       are COMMITTABLE (OVER-inclusion; NARROW the '!' rule named for each):"
        print_path_rules "$REPORT_LEAKED_UNINTENDED"
      fi
      if [ -n "$REPORT_BLOCKED_INTENDED" ]; then
        echo "       Separately — and independently of the gate — these MEMORY-STORE paths are still"
        echo "       IGNORED (UNDER-inclusion; neutralise or re-order the rule named for each):"
        print_path_rules "$REPORT_BLOCKED_INTENDED"
      fi
      return 0 ;;
  esac
  echo
  echo "apply: WARNING — readiness is '$REPORT_VERDICT', not 'configured'; the negation did NOT fully take effect."
  if [ -n "$REPORT_BLOCKED_INTENDED" ]; then
    echo "       These intended paths are STILL IGNORED, each with the rule that actually wins for it:"
    print_path_rules "$REPORT_BLOCKED_INTENDED"
  fi
  echo "       A surviving recursive or deeper exclude is the usual cause — this helper only"
  echo "       neutralises the directory-shaped excludes it recognises (.claude, .supervisor and"
  echo "       their /**, **/ and / forms). Comment out the rule named above, or move it ABOVE the"
  echo "       managed block, then re-run. Nothing else about the write is in doubt: the managed"
  echo "       block IS in place and a backup of the previous file sits beside it."
}

# ---- subcommand: check ------------------------------------------------------
do_check() {
  render_report
  echo
  print_consent_disclosure
  exit 0
}

# ---- subcommand: apply ------------------------------------------------------
do_apply() {
  local gate
  gate="$(gitignore_gate)"

  if [ "$gate" = "absent" ]; then
    echo "apply: ABORTED — no .gitignore at $GI, so nothing is ignoring these stores; there is nothing to negate."
    echo "       Nothing was written. If a parent .gitignore or a global excludesfile is ignoring them, edit that file."
    exit 0
  fi
  case "$gate" in
    unparseable:*)
      echo "apply: ABORTED — $gate"
      echo "       Nothing was written (no partial write, no backup). Fix .gitignore by hand, then re-run."
      exit 0 ;;
  esac

  # Evaluate the ledger gate ONCE, in THIS shell, BEFORE the headline is chosen. proposed_applied_content
  # runs managed_block inside a command substitution, so the gate it evaluates there cannot reach us —
  # and the no-op headline must NOT read "already configured" for a repo whose ledger is withheld
  # (commands/setup.md mandates relaying that headline verbatim, which would state the opposite of the
  # truth the `gated` class exists to tell).
  ledger_gate_blocks_foreign_records || true

  local current proposed neg_line ledger_withdrawn=no
  current="$(cat "$GI")"
  proposed="$(proposed_applied_content)"
  neg_line="!$LEDGER_INTENDED_PATH"

  # WITHDRAWAL: the file on disk carries the ledger negation and the file we are about to write does
  # NOT. That is the gate-passed → contaminated → re-apply transition. It is correct behaviour, but it
  # must be ANNOUNCED — never a bare `apply: applied`.
  case "$current" in
    *"$neg_line"*)
      case "$proposed" in
        *"$neg_line"*) : ;;
        *) ledger_withdrawn=yes ;;
      esac ;;
  esac

  if [ "$current" = "$proposed" ]; then
    if [ "$LEDGER_GATE_STATE" = "refuse" ]; then
      echo "apply: no-op — the two memory stores are already configured, but the findings ledger is GATED and stays IGNORED (records outside the allowlist: $(printf '%s' "$LEDGER_FOREIGN_SLUGS" | tr '\n' ' ')). Nothing was written."
    else
      echo "apply: no-op — already configured (the managed block and the disabled bare excludes are exactly as apply would write them). Nothing was written."
    fi
    seed_allowlist
    echo
    echo "== verify =="
    render_report
    warn_if_not_configured
    exit 0
  fi

  echo "== what you are about to version-control =="
  print_consent_disclosure
  echo

  local backup
  backup="$(write_gitignore "$proposed")" || { echo "apply: ABORTED — the rewrite could not be staged; .gitignore is unchanged."; exit 0; }
  if [ "$ledger_withdrawn" = "yes" ]; then
    echo "apply: applied (ledger negation WITHDRAWN) — managed block written to $GI"
  else
    echo "apply: applied — managed block written to $GI"
  fi
  echo "  backup:  $backup   (delete it once you are happy; it is untracked)"
  if [ "$ledger_withdrawn" = "yes" ]; then
    echo "apply: ledger negation WITHDRAWN — these repo slugs appeared in $LEDGER_INTENDED_PATH"
    echo "       since the last apply and are NOT in this repo's allowlist: $(printf '%s' "$LEDGER_FOREIGN_SLUGS" | tr '\n' ' ')"
    echo "       The ledger is IGNORED again from now on. THIS DOES NOT UN-TRACK AN ALREADY-COMMITTED"
    echo "       LEDGER — .gitignore only governs UNTRACKED files, so if you already committed it the"
    echo "       foreign records are still published. Filter it and stop tracking it yourself:"
    echo "         bash setup-memory.sh filter-ledger --ledger $LEDGER_INTENDED_PATH > /tmp/ledger.filtered"
    echo "         mv /tmp/ledger.filtered $LEDGER_INTENDED_PATH && git rm -r --cached $LEDGER_INTENDED_PATH"
    echo "       then commit. The withdrawal alone unpublishes nothing."
  fi
  seed_allowlist
  echo
  echo "== verify =="
  render_report
  warn_if_not_configured
  echo
  echo "Next: the stores are only UN-IGNORED — nothing is committed yet. Review with"
  echo "  git status --short .claude/agent-memory .supervisor/memory"
  echo "and commit deliberately. This helper never runs git add / git rm / git commit."
  exit 0
}

# ---- subcommand: remove -----------------------------------------------------
do_remove() {
  local gate
  gate="$(gitignore_gate)"

  if [ "$gate" = "absent" ]; then
    echo "remove: no-op — no .gitignore at $GI; there is no managed block to remove. Nothing was written."
    exit 0
  fi
  case "$gate" in
    unparseable:*)
      echo "remove: ABORTED — $gate"
      echo "        Nothing was written (no partial write). Fix .gitignore by hand, then re-run."
      exit 0 ;;
  esac

  local current proposed
  current="$(cat "$GI")"
  proposed="$(proposed_removed_content)"

  if [ "$current" = "$proposed" ]; then
    echo "remove: no-op — no managed block and no disabled excludes to restore. Nothing was written."
  else
    local backup
    backup="$(write_gitignore "$proposed")" || { echo "remove: ABORTED — the rewrite could not be staged; .gitignore is unchanged."; exit 0; }
    echo "remove: removed — managed block deleted and the original bare excludes restored in $GI"
    echo "  backup:  $backup"
  fi

  local tam tsm tlg
  tam="$(tracked_count '.claude/agent-memory')"
  tsm="$(tracked_count '.supervisor/memory')"
  tlg="$(tracked_count "$LEDGER_INTENDED_PATH")"
  cat <<EOF

READ THIS — removal stops FUTURE tracking. It does NOT unpublish anything:
  · Git HISTORY RETAINS everything already committed. Every commit that ever contained these
    files still contains them, on this clone and on every remote, fork and clone that has them.
    If it was pushed, it is published — removing the ignore rule cannot take it back.
  · To actually purge published content you must REWRITE HISTORY (e.g. git filter-repo) and
    force-push every affected ref, then ask collaborators to re-clone — and rotate anything
    secret that was exposed, because it must be assumed compromised.
  · Files that are ALREADY TRACKED stay tracked. .gitignore only affects UNTRACKED files.
    Currently tracked: .claude/agent-memory/ → $tam file(s), .supervisor/memory/ → $tsm file(s),
    $LEDGER_INTENDED_PATH → $tlg file(s).
    All THREE stores are covered — the findings ledger is un-ignored by the same managed block
    (behind the repo-allowlist gate), so removing the block re-ignores it too, and that likewise
    unpublishes nothing that was already committed.
    To stop tracking them going forward (keeping the working copies), run yourself:
      git rm -r --cached .claude/agent-memory .supervisor/memory $LEDGER_INTENDED_PATH
    then commit. This helper NEVER runs git rm / git add / git commit.
EOF
  echo
  echo "== verify =="
  render_report
  exit 0
}

# ---- subcommand: allowlist --------------------------------------------------
do_allowlist() {
  load_allowlist
  [ -n "$ALLOWLIST" ] && printf '%s\n' "$ALLOWLIST"
  echo "# source: $ALLOWLIST_SOURCE" >&2
  exit 0
}

# ---- subcommand: filter-ledger ----------------------------------------------
do_filter_ledger() {
  if [ -z "$LEDGER" ]; then
    echo "setup-memory: filter-ledger requires --ledger <path>" >&2
    exit 0
  fi
  local entries
  entries="$(resolve_allowlist)"
  if [ -z "$entries" ]; then
    filter_ledger_by_allowlist "$LEDGER"
  else
    # bash-3.2-safe expansion of the newline-separated list into positional args.
    local oldIFS="$IFS"
    IFS='
'
    # shellcheck disable=SC2086
    set -- $entries
    IFS="$oldIFS"
    filter_ledger_by_allowlist "$LEDGER" "$@"
  fi
  exit 0
}

case "$SUBCMD" in
  check)         do_check ;;
  apply)         do_apply ;;
  remove)        do_remove ;;
  allowlist)     do_allowlist ;;
  filter-ledger) do_filter_ledger ;;
  *)             usage ;;
esac
