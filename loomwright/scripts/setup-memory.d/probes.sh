# ---- probe paths ------------------------------------------------------------
# INTENDED: must be committable after apply. The two `.`-prefixed sidecars are listed separately
# from the `**` cases on purpose — a dotfile inside a re-included directory is its own
# silent-failure class, and losing them strips provenance from a fresh clone (read-lessons.sh's
# read-side provenance gate depends on them).
#
# The agent-memory probe path is DERIVED, never typed. The rule is read off the stores the host
# actually creates (the ones this repo tracks are `.claude/agent-memory/loomwright-loomwright-<role>/`):
# a plugin agent's runtime type is the doubled `<plugin>:<plugin>:<role>`, and its store directory is
# that type with every `:` made `-`. The platform docs give only `<name-of-agent>`, so the rule is
# observed, not documented. A colon form (`loomwright:<role>`) names a directory that never exists.
# The probe needs one concrete role; every store shares the parent the gitignore rules govern.
# test-setup-memory.sh group (am) checks the probe against the repo's tracked stores.
agent_memory_store_dir() { printf '.claude/agent-memory/%s' "$(printf '%s' "$1" | tr ':' '-')"; }
AGENT_MEMORY_PROBE_DIR="$(agent_memory_store_dir 'loomwright:loomwright:code-reviewer')"
INTENDED_PATHS="$AGENT_MEMORY_PROBE_DIR/MEMORY.md
$AGENT_MEMORY_PROBE_DIR/.provenance.jsonl
.supervisor/memory/LESSONS.md
.supervisor/memory/.lessons-provenance.jsonl
.supervisor/requirements/queue/01-item.md
.supervisor/jobs/done/2026-01-01-brief.md
.supervisor/jobs/failed/2026-01-01-brief.md
.supervisor/automate/automate-2026-01-01-000000.md"

# The THIRD store, held separately from INTENDED_PATHS on purpose: its membership in the probed
# intended set is CONDITIONAL on the ledger gate passing. Folding it into INTENDED_PATHS would make
# a CORRECT refusal report as `not configured`, whose remediation copy tells the user to comment out
# "the surviving exclude" — which for a withheld ledger is this module's OWN `.supervisor/*` line.
# That is exactly the wrong remedy, and commands/setup.md mandates relaying it verbatim. See the
# `gated` verdict class in render_report() / warn_if_not_configured().
LEDGER_INTENDED_PATH='.supervisor/postmortem/results.jsonl'

# UNINTENDED: must stay ignored (worktree checkouts, machine-local settings, session logs,
# in-flight briefs, automate sidecars, and the nested `.supervisor/` a hook leaves inside a
# requirements folder or any other subfolder — the trail re-includes are siblings of every one of these).
UNINTENDED_PATHS='.claude/worktrees/busy-darwin/README.md
.claude/settings.local.json
.supervisor/logs/session.jsonl
.supervisor/jobs/in-progress/2026-01-01-brief.md
.supervisor/jobs/pending/2026-01-01-brief.md
.supervisor/automate/automate-2026-01-01-000000.config-backup.json
.supervisor/requirements/queue/.supervisor/logs/telemetry.log
probes/.supervisor/.rules-nudge-shown'

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

# gitignore_gate [read] → ok | absent | "unparseable: <reason>"
# Deliberately conservative: anything this rewriter cannot round-trip safely is refused OUTRIGHT
# rather than half-written. A refusal changes nothing and says why.
# `read` (read_mode only) drops the WRITABILITY requirement and nothing else: a reader never
# rewrites the file, so a read-only .gitignore is not ambiguous to it. Every other check — the
# structural ones that make the block's content ambiguous — still applies.
gitignore_gate() {
  local purpose="${1:-write}"
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
  if [ ! -r "$GI" ] || { [ "$purpose" != "read" ] && [ ! -w "$GI" ]; }; then
    echo "unparseable: .gitignore is not both readable and writable"
    return
  fi
  # Binary content — a NUL byte means this is not a line-oriented ignore file. Detected by
  # comparing the file against a NUL-stripped copy of itself: bash cannot hold a NUL in a
  # variable, so `grep $'\0'` would silently degrade to an empty pattern that matches EVERY
  # file (it would flag every .gitignore as binary). `tr | cmp -` is portable to BSD and GNU.
  if ! env LC_ALL=C tr -d '\000' < "$GI" 2>/dev/null | cmp -s - "$GI" 2>/dev/null; then
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
