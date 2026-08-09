#!/usr/bin/env bash
# test-citation-drift.sh — every in-repo `file.ext:<N>` citation on a LIVE surface is policed.
#
# WHY THIS EXISTS (measured, four times in one change)
#   A worker inserts lines ABOVE an absolute line reference and silently falsifies every pointer
#   below it. Nothing in the repo notices: the citation still parses, the file still exists, the
#   line still exists — it just describes something else now. PR #138 hit this three times:
#     1. An 8-line comment block pushed the no-arg `bash "$reader"` call in session-resume.sh from
#        :311 to :319, falsifying FIVE committed citations. Caught only by a CI review bot.
#     2. add-rule.sh's `--applies-to` comment cited the `category` traversal reject as `(:245+)`;
#        the real guard was at :274. It was wrong the moment it was authored and survived two
#        follow-up commits that were specifically hunting this defect class.
#     3. The source requirement cited session-resume.sh:197 for a seam that lived at :294-329.
#   The fix that landed was `(j4b)` in test-read-rules.sh: re-derive the real line via git grep
#   instead of hard-coding it. But it was scoped to ONE file and ONE keyword — it only policed
#   `session-resume.sh:<N>` citations that also said "no-arg" on the same line. Defect 2 was
#   invisible to it, which is exactly why that one survived. This file is the general form.
#
# WHAT IS MECHANICALLY DECIDABLE, AND WHAT IS NOT
#   "Line N of file F contains the thing the surrounding prose claims" is NOT decidable in
#   general — it needs the semantics of the prose. So this gate deliberately does not pretend to.
#   It enforces three checks of strictly increasing strength, and claims nothing beyond them:
#
#     (A) RESOLVE + LINE-COUNT FLOOR — hard, automatic, every citation.
#         The cited file must resolve and must actually HAVE line N. Catches deletion, file
#         shrink, and grossly-wrong numbers. It is a FLOOR, not a correctness proof: it did not
#         catch a single one of the three defects above, all of which cited a line that existed
#         and merely said something else. Cheap and free of false positives, so it is kept — but
#         a green (A) means "the line exists", never "the citation is right".
#
#     (B) PINNED ANCHORS — hard, OPT-IN, the check that actually has teeth.
#         A citation may carry `[pins: <literal>]` on the same line. That literal must occur
#         within +/-3 lines of N in the cited file. Because the author chooses the literal, this
#         has zero false positives by construction — unlike auto-deriving an anchor from the
#         prose, which was prototyped against this repo's real corpus and measured at 1 hit /
#         11 false alarms / 8 no-signal. It re-derives content the way (j4b) did, for any file.
#
#     (C) BARE-CITATION RATCHET — hard, automatic.
#         Every citation that is NOT pinned must appear in the BARE_ALLOWLIST below. A new bare
#         `file:N` therefore fails the gate: new citations must either carry `[pins: ...]` or use
#         a descriptive anchor ("the `category` guard in section 1 above"), which is the style
#         PR #138 converged on and which cannot rot at all. The allowlist is also checked for
#         STALE entries, so it can only ratchet down.
#
# WHAT IS NOT POLICED, ON PURPOSE
#   CHANGELOG.md and loomwright/docs/SPIKES/ are FROZEN HISTORICAL surfaces. They legitimately
#   cite lines as they were at the time (`session-resume.sh:197`, `:311 -> :319` narratives, eval
#   records pinning agent prompts at a past revision). "Correcting" them would destroy accurate
#   history, and a repo-wide sweep without this exclusion fails immediately on correct text.
#   Unresolvable citations are SKIPPED, not failed: agent prompts carry illustrative output
#   (`path/to/file.ts:67`, `src/auth/token.ts:45`) and some real citations point into gitignored
#   `.supervisor/` artifacts. Neither is drift.
#
# SELF-TEST / MUTATION CONTROL
#   The narrow (j4b) guard was VACUOUS on first write — the citation and its keyword sat on two
#   different lines, so its `git grep` matched nothing and it reported success over an empty set.
#   A guard that cannot fail is worse than no guard. So every check here is run a second time
#   against a synthetic fixture tree with a deliberately corrupted citation, through the SAME
#   scan_surface() code path, and is REQUIRED to report the corruption. If a refactor makes a
#   check vacuous, the mutation control goes red.
#
# Fail-CLOSED: a drifted or unratcheted citation exits 1. This is a correctness gate.
# CI runs it automatically via the existing `loomwright/scripts/test-*.sh` self-test loop, so it
# needs no `.github/workflows/` edit (which would make `claude-code-action` self-skip the PR's
# own review — see CLAUDE.md).
#
# Portability: macOS bash 3.2 + BSD userland is the dev host, GNU/Linux is CI. No `stat -f`/`-c`,
# no `sed -i`, no `mapfile`, no `grep -q` on the read end of a pipe (SIGPIPE 141 under pipefail).
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

PASS=0
FAIL=0
ok() { echo "PASS: $1"; PASS=$((PASS + 1)); }
no() { echo "FAIL: $1" >&2; FAIL=$((FAIL + 1)); }

cd "$REPO_ROOT" 2>/dev/null || { echo "FAIL: cannot cd to repo root" >&2; exit 1; }

# How far from the cited line a pinned literal may sit. Deliberately TIGHT: the motivating
# defect was an 8-line insertion, so a window of 8 or more would have waved it through.
WINDOW=3

# A citation shape: an optional path prefix, a basename with a source-file extension, a colon and
# a line number. Ranges (`:124-126`) and lists (`:249,251`) are normalised to their MAXIMUM line,
# which is the number that has to exist for the reference to be readable at all.
CITE_RE='[A-Za-z0-9_./-]*[A-Za-z0-9_-]\.(sh|md|py|json|ts|yml|yaml):[0-9]+'

# ---------------------------------------------------------------------------------------------
# (C) BARE-CITATION RATCHET ALLOWLIST
#
# `<citing path>|<cited target>` for every citation that is deliberately left unpinned. Each
# entry needs a reason. New citations must NOT be added here as a matter of routine — pin them
# with `[pins: ...]` or write a descriptive anchor instead. Entries are verified to still exist,
# so this list can only shrink.
# ---------------------------------------------------------------------------------------------
BARE_ALLOWLIST="$(cat <<'ALLOW'
loomwright/skills/claude-md-validation/SKILL.md|CLAUDE.md:42
ALLOW
)"
# claude-md-validation/SKILL.md:235 — ILLUSTRATIVE, not a citation: it is sample reviewer output
# ("-> Check CLAUDE.md:42 - may be outdated") shown to teach the output format. It happens to
# resolve against this repo's own CLAUDE.md by coincidence of the name, and pinning it would
# assert a fact about line 42 that the example never meant to claim.

# Exact whole-line membership tests. Both deliberately avoid `case "$blob" in *"$needle"*)`,
# which is a SUBSTRING test: with a multi-entry allowlist, `a.md|b.sh:1` is a substring of
# `xa.md|b.sh:12`, so one entry could silently exempt a different, unlisted citation. Harmless at
# one entry, wrong the moment the list grows — and a ratchet that quietly widens is worse than no
# ratchet. Plain shell loops, so there is no regex-metacharacter escaping to get wrong in a path.
allowlist_has() {
  local needle="$1" line
  while IFS= read -r line; do
    [ "$line" = "$needle" ] && return 0
  done <<EOF
$BARE_ALLOWLIST
EOF
  return 1
}

bares_has() {
  local e_src="$1" e_tgt="$2" line
  while IFS= read -r line; do
    [ "$line" = "$(printf 'BARE\t%s\t%s' "$e_src" "$e_tgt")" ] && return 0
  done <<EOF
$BARES
EOF
  return 1
}

# ---------------------------------------------------------------------------------------------
# CORE SCANNER — shared by the real run and by the mutation controls.
#
# scan_surface <resolve_root> <file>...
#   Emits one TAB-separated verdict per citation found:
#     OK        <citing>  <resolved>:<n>          line exists (and pin matched, if pinned)
#     OVERRUN   <citing>  <resolved>:<n>  <total> (A) file is shorter than the cited line
#     PINMISS   <citing>  <resolved>:<n>  <lit>   (B) pinned literal absent near the cited line
#     BARE      <citing>  <cited>:<n>             (C) unpinned — caller decides against allowlist
#     SKIP      <citing>  <cited>:<n>             unresolvable (placeholder / gitignored target)
#   Never exits non-zero itself; classification is the caller's job.
# ---------------------------------------------------------------------------------------------
scan_surface() {
  local root="$1"; shift
  local src text next cite cpath cn base resolved hits nhits total pin lo hi win maxn part i n
  local pinsrc

  for src in "$@"; do
    [ -r "$src" ] || continue
    # Slurp into an array rather than streaming, because a pin is allowed to sit on the line
    # AFTER its citation (see below) and that needs one line of lookahead. Reading the file
    # ourselves — rather than shelling out to `git grep` — is what lets a non-git fixture tree
    # run through exactly this code path in the mutation controls.
    local -a L=()
    while IFS= read -r text || [ -n "$text" ]; do L[${#L[@]}]="$text"; done < "$src"

    n=${#L[@]}
    i=0
    while [ "$i" -lt "$n" ]; do
      # `:-` on BOTH reads: under `set -u`, bash 3.2 treats a reference into an array that is
      # empty (a zero-byte source file) as an unbound variable and kills the shell. Because
      # scan_surface runs inside a command substitution, that would silently TRUNCATE the result
      # set rather than fail loudly — the scan would just report fewer citations and pass.
      text="${L[$i]:-}"
      next="${L[$((i + 1))]:-}"
      i=$((i + 1))
      case "$text" in *.sh:[0-9]*|*.md:[0-9]*|*.py:[0-9]*|*.json:[0-9]*|*.ts:[0-9]*|*.yml:[0-9]*|*.yaml:[0-9]*) ;; *) continue ;; esac

      # A pin applies to every citation on its line. It may be written on the citation's own
      # line, OR on the immediately following line — comments wrap at ~100 columns and forcing
      # them onto one line is precisely how the original narrow guard became vacuous (its
      # citation and its keyword ended up on two different lines, so its grep matched nothing
      # and it reported success over an empty set). A next-line pin is only borrowed when that
      # next line carries no citation of its own, so it cannot be stolen from a later reference.
      pinsrc=""
      case "$text" in *'[pins: '*) pinsrc="$text" ;; esac
      if [ -z "$pinsrc" ]; then
        case "$next" in
          *'[pins: '*)
            case "$next" in
              *.sh:[0-9]*|*.md:[0-9]*|*.py:[0-9]*|*.json:[0-9]*|*.ts:[0-9]*|*.yml:[0-9]*|*.yaml:[0-9]*) ;;
              *) pinsrc="$next" ;;
            esac
            ;;
        esac
      fi
      pin=""
      if [ -n "$pinsrc" ]; then
        pin="${pinsrc#*\[pins: }"
        # Backtick-delimited form `[pins: \`foo\`]` is the convention, and it is parsed FIRST and
        # on its own terms: the literal ends at the closing BACKTICK, not at the first `]`. That
        # matters because a pin into JSON or a character class legitimately contains `]`
        # (`[0-9]`, `"tools": [...]`), and ending the literal at the first `]` would silently
        # truncate it — producing a spurious PINMISS, or worse a false OK if the truncated
        # fragment happens to occur inside the +/-3 window. Only the undelimited form falls back
        # to `]`, where there is nothing better to key on.
        case "$pin" in
          '`'*) pin="${pin#\`}"; pin="${pin%%\`*}" ;;
          *)    pin="${pin%%\]*}" ;;
        esac
      fi

      for cite in $(printf '%s\n' "$text" | grep -oE "$CITE_RE"); do
        cpath="${cite%:*}"
        cn="${cite##*:}"
        base="${cpath##*/}"

        # Normalise a range/list (`:124-126`, `:249,251`) to its maximum. The scanner only sees
        # the first number via CITE_RE, so re-read the tail of the citation from the raw line.
        maxn="$cn"
        part="${text#*$cite}"
        case "$part" in
          -[0-9]*|,[0-9]*|,\ :[0-9]*)
            for n in $(printf '%s' "$part" | grep -oE '^[-,][ ]*:?[0-9]+' | grep -oE '[0-9]+'); do
              [ "$n" -gt "$maxn" ] && maxn="$n"
            done
            ;;
        esac

        # Resolve, in order: the path as written, the path under the plugin dir, then a UNIQUE
        # SUFFIX match. The suffix step matters because citations are routinely written as a
        # partial path (`async-orchestration/SKILL.md`, `agents/supervisor.md`) that exists at
        # neither of the first two locations; matching on the basename alone would be useless
        # here, since 41 different skills all have a file called SKILL.md. Ambiguous (>1 hit) and
        # no-hit both fall through to SKIP — a citation we cannot resolve is not evidence of drift.
        resolved=""
        if [ -f "$root/$cpath" ]; then
          resolved="$cpath"
        elif [ -f "$root/loomwright/$cpath" ]; then
          resolved="loomwright/$cpath"
        else
          hits="$(cd "$root" && find . -name "$base" -type f 2>/dev/null \
                    | sed 's|^\./||' | grep -v '^\.git/' | grep -e "/$cpath\$" -e "^$cpath\$")"
          nhits="$(printf '%s' "$hits" | grep -c . )"
          if [ "$nhits" -eq 1 ]; then
            resolved="$hits"
          fi
        fi

        if [ -z "$resolved" ]; then
          printf 'SKIP\t%s\t%s:%s\n' "$src" "$cpath" "$cn"
          continue
        fi

        # (A) line-count floor.
        total="$(grep -c '' "$root/$resolved" 2>/dev/null || echo 0)"
        if [ "$maxn" -gt "$total" ]; then
          printf 'OVERRUN\t%s\t%s:%s\t%s\n' "$src" "$resolved" "$maxn" "$total"
          continue
        fi

        # (B) pinned anchor.
        if [ -n "$pin" ]; then
          lo=$((cn - WINDOW)); [ "$lo" -lt 1 ] && lo=1
          hi=$((maxn + WINDOW))
          win="$(sed -n "${lo},${hi}p" "$root/$resolved")"
          case "$win" in
            *"$pin"*) printf 'OK\t%s\t%s:%s\n' "$src" "$resolved" "$cn" ;;
            *)        printf 'PINMISS\t%s\t%s:%s\t%s\n' "$src" "$resolved" "$cn" "$pin" ;;
          esac
          continue
        fi

        # (C) resolved, in range, but unpinned — the caller ratchets this.
        printf 'BARE\t%s\t%s:%s\n' "$src" "$cpath" "$cn"
      done
    done < "$src"
  done
}

# ---------------------------------------------------------------------------------------------
# LIVE SURFACES
# ---------------------------------------------------------------------------------------------
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "SKIP: not a git repository — citation-drift gate is repo-local"
  exit 0
fi

# Tracked files only, so an untracked scratch file cannot fail the build. CHANGELOG.md and
# docs/SPIKES/ are the frozen historical surfaces (see header); this file's own fixture strings
# live under a temp dir and are never in the tracked set.
SURFACES="$(git ls-files -- \
    'loomwright/scripts/*.sh' 'loomwright/scripts/*.py' \
    'loomwright/skills/*.md' 'loomwright/commands/*.md' 'loomwright/agents/*.md' \
    'loomwright/docs/*.md' 'scripts/*.sh' 'CLAUDE.md' 'AGENT_GUIDELINES.md' 'README.md' 2>/dev/null \
  | grep -v '^loomwright/docs/SPIKES/' \
  | grep -v '^CHANGELOG.md$' \
  | grep -v '^loomwright/scripts/test-citation-drift.sh$')"

if [ -z "$SURFACES" ]; then
  no "no live surfaces matched — the scan glob is broken (anti-drift: this must never be empty)"
else
  # shellcheck disable=SC2086
  RESULTS="$(scan_surface "$REPO_ROOT" $SURFACES)"

  n_total="$(printf '%s\n' "$RESULTS" | grep -c .)"
  n_ok="$(printf '%s\n' "$RESULTS" | grep -c '^OK	' || true)"
  n_skip="$(printf '%s\n' "$RESULTS" | grep -c '^SKIP	' || true)"

  # Anti-vacuity: the scan must actually find citations. If a regex or glob change silences it,
  # every check below would pass over an empty set — exactly the (j4b) failure mode.
  #
  # The floor is set from a MEASURED baseline (~30 citations at the time of writing), not from a
  # round number: the `set -u` truncation bug this check exists to catch dropped the scanned set
  # to 14, which a loose floor of 10 would have waved straight through. It is set below the real
  # count so that ordinary curation — converting a citation to a descriptive anchor, which this
  # gate actively encourages — does not trip it, and it should be lowered deliberately (with the
  # new baseline stated) rather than raised to chase the corpus.
  CITE_FLOOR=20
  if [ "$n_total" -lt "$CITE_FLOOR" ]; then
    no "citation scan found only $n_total citations across the live surfaces — expected >=$CITE_FLOOR; the scanner has gone vacuous"
  else
    ok "citation scan is non-vacuous: $n_total citations found ($n_ok pinned-and-verified, $n_skip unresolvable/skipped)"
  fi

  # ---- (A) line-count floor -------------------------------------------------------------------
  OVERRUNS="$(printf '%s\n' "$RESULTS" | grep '^OVERRUN	' || true)"
  if [ -z "$OVERRUNS" ]; then
    ok "(A) every resolvable citation points at a line the cited file actually has"
  else
    printf '%s\n' "$OVERRUNS" | while IFS="$(printf '\t')" read -r _ src tgt total; do
      echo "    $src cites $tgt but that file has only $total lines" >&2
    done
    no "(A) $(printf '%s\n' "$OVERRUNS" | grep -c .) citation(s) point past the end of the cited file"
  fi

  # ---- (B) pinned anchors ---------------------------------------------------------------------
  PINMISS="$(printf '%s\n' "$RESULTS" | grep '^PINMISS	' || true)"
  n_pinned=$((n_ok + $(printf '%s\n' "$PINMISS" | grep -c . || true)))
  if [ "$n_pinned" -eq 0 ]; then
    no "(B) no citation carries a [pins: ...] anchor — the only check with teeth is switched off"
  elif [ -z "$PINMISS" ]; then
    ok "(B) all $n_pinned pinned citation(s) still resolve to their anchored content (+/-$WINDOW lines)"
  else
    printf '%s\n' "$PINMISS" | while IFS="$(printf '\t')" read -r _ src tgt lit; do
      echo "    $src cites $tgt but '$lit' is not within +/-$WINDOW lines of it" >&2
    done
    no "(B) $(printf '%s\n' "$PINMISS" | grep -c .) pinned citation(s) have DRIFTED off their anchor"
  fi

  # ---- (C) bare-citation ratchet --------------------------------------------------------------
  BARES="$(printf '%s\n' "$RESULTS" | grep '^BARE	' || true)"
  unratcheted=0
  if [ -n "$BARES" ]; then
    while IFS="$(printf '\t')" read -r _ src tgt; do
      [ -z "$src" ] && continue
      # EXACT per-line comparison, not a substring test against the whole blob: `a.md|b.sh:1` is
      # a substring of `xa.md|b.sh:12`, so a substring match would let one allowlist entry
      # silently exempt a DIFFERENT, unlisted citation as the list grows.
      if allowlist_has "$src|$tgt"; then :; else
        echo "    $src cites $tgt with no [pins: ...] anchor and no allowlist entry" >&2
        unratcheted=$((unratcheted + 1))
      fi
    done <<EOF
$BARES
EOF
  fi
  if [ "$unratcheted" -eq 0 ]; then
    ok "(C) no new bare file:N citation — every unpinned citation is a known allowlist entry"
  else
    no "(C) $unratcheted new bare file:N citation(s): pin them with [pins: <literal>] or use a descriptive anchor"
  fi

  # ---- (C2) the allowlist may only ratchet DOWN -----------------------------------------------
  stale=0
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    e_src="${entry%%|*}"; e_tgt="${entry#*|}"
    if bares_has "$e_src" "$e_tgt"; then :; else
      echo "    allowlist entry no longer present as a bare citation: $entry" >&2
      stale=$((stale + 1))
    fi
  done <<EOF
$BARE_ALLOWLIST
EOF
  if [ "$stale" -eq 0 ]; then
    ok "(C2) every BARE_ALLOWLIST entry is still a real bare citation — no stale exemptions"
  else
    no "(C2) $stale stale BARE_ALLOWLIST entr(ies) — delete them so the ratchet cannot drift upward"
  fi
fi

# ---------------------------------------------------------------------------------------------
# MUTATION CONTROLS — prove each check CAN fail. See header: (j4b) shipped vacuous.
# ---------------------------------------------------------------------------------------------
FIX="$(mktemp -d "${TMPDIR:-/tmp}/citation-drift-fixture.XXXXXX")" || FIX=""
if [ -z "$FIX" ] || [ ! -d "$FIX" ]; then
  no "(M) could not create a fixture dir — mutation controls did not run, so the checks above are UNPROVEN"
else
  trap 'rm -rf "$FIX"' EXIT

  mkdir -p "$FIX/loomwright/scripts"
  # Cited file: the anchor literal sits on line 5.
  cat > "$FIX/loomwright/scripts/target.sh" <<'TGT'
#!/usr/bin/env bash
# line 2
# line 3
# line 4
running|checkpoint) ;;
# line 6
# line 7
TGT

  # 1. A pin that MATCHES (control for the control: the checker must not fail everything).
  printf '# see target.sh:5 [pins: `running|checkpoint)`]\n' > "$FIX/loomwright/scripts/good.sh"
  # 2. A pin that has DRIFTED — cites :1, anchor is 4 lines away (outside +/-3).
  printf '# see target.sh:1 [pins: `running|checkpoint)`]\n' > "$FIX/loomwright/scripts/drifted.sh"
  # 3. A citation past the end of the file.
  printf '# see target.sh:99\n' > "$FIX/loomwright/scripts/overrun.sh"
  # 4. A bare, unpinned citation.
  printf '# see target.sh:5\n' > "$FIX/loomwright/scripts/bare.sh"
  # 5. A pin on the line AFTER the citation (comment wrapping) — must still be honoured, and
  #    must still CATCH drift rather than being waved through as "unpinned".
  printf '# see target.sh:5\n#   [pins: `running|checkpoint)`]\n' > "$FIX/loomwright/scripts/wrapgood.sh"
  printf '# see target.sh:1\n#   [pins: `running|checkpoint)`]\n' > "$FIX/loomwright/scripts/wrapdrift.sh"
  # 6. A next-line pin must NOT be stolen by a citation on the preceding line when that next
  #    line carries a citation of its own — otherwise one pin could silently vouch for two
  #    different references.
  printf '# see target.sh:1\n# see target.sh:5 [pins: `running|checkpoint)`]\n' > "$FIX/loomwright/scripts/nosteal.sh"
  # 7. A partial-path citation resolved by unique SUFFIX match, not by basename.
  mkdir -p "$FIX/loomwright/skills/demo-skill"
  printf 'a\nb\nc\nd\nSIGNAL LINE HERE\n' > "$FIX/loomwright/skills/demo-skill/SKILL.md"
  printf '# see demo-skill/SKILL.md:5 [pins: `SIGNAL LINE HERE`]\n' > "$FIX/loomwright/scripts/suffix.sh"
  # 8. SKIP must fire ONLY for genuinely unresolvable citations. Untested, a regression in the
  #    resolution chain (path -> loomwright/path -> unique suffix) would route a REAL, DRIFTED
  #    citation into SKIP and silently exempt it from (A), (B) and (C) — a vacuous guard by the
  #    back door, which is exactly the failure this file exists to prevent. Two fixtures: a file
  #    that does not exist at all, and an AMBIGUOUS basename (2 candidates, no unique suffix).
  printf '# see nonexistent-file.sh:5\n' > "$FIX/loomwright/scripts/unresolvable.sh"
  mkdir -p "$FIX/loomwright/skills/dup-a" "$FIX/loomwright/skills/dup-b"
  printf 'x\ny\nz\n' > "$FIX/loomwright/skills/dup-a/DUP.md"
  printf 'x\ny\nz\n' > "$FIX/loomwright/skills/dup-b/DUP.md"
  printf '# see DUP.md:2\n' > "$FIX/loomwright/scripts/ambiguous.sh"
  # 9. A pin literal containing `]` must survive parsing intact (JSON / character-class pins).
  printf 'p\nq\nmatch [0-9] here\nr\n' > "$FIX/loomwright/scripts/brackety.sh"
  printf '# see brackety.sh:3 [pins: `match [0-9] here`]\n' > "$FIX/loomwright/scripts/bracketcite.sh"

  M_GOOD="$(scan_surface "$FIX" "$FIX/loomwright/scripts/good.sh")"
  M_DRIFT="$(scan_surface "$FIX" "$FIX/loomwright/scripts/drifted.sh")"
  M_OVER="$(scan_surface "$FIX" "$FIX/loomwright/scripts/overrun.sh")"
  M_BARE="$(scan_surface "$FIX" "$FIX/loomwright/scripts/bare.sh")"

  case "$M_GOOD" in
    OK*) ok "(M1) control: a correctly pinned citation is accepted (the checker is not failing everything)" ;;
    *)   no "(M1) control FAILED: a correct pin was rejected — verdict was '$M_GOOD'" ;;
  esac

  case "$M_DRIFT" in
    PINMISS*) ok "(M2) mutation: a pinned citation moved off its anchor IS caught — check (B) can fail" ;;
    *)        no "(M2) VACUOUS GUARD: a deliberately drifted pin was NOT caught — verdict was '$M_DRIFT'" ;;
  esac

  case "$M_OVER" in
    OVERRUN*) ok "(M3) mutation: a citation past end-of-file IS caught — check (A) can fail" ;;
    *)        no "(M3) VACUOUS GUARD: a past-EOF citation was NOT caught — verdict was '$M_OVER'" ;;
  esac

  case "$M_BARE" in
    BARE*) ok "(M4) mutation: an unpinned citation IS reported as bare — check (C) can fail" ;;
    *)     no "(M4) VACUOUS GUARD: a bare citation was NOT reported — verdict was '$M_BARE'" ;;
  esac

  M_WGOOD="$(scan_surface "$FIX" "$FIX/loomwright/scripts/wrapgood.sh")"
  M_WDRIFT="$(scan_surface "$FIX" "$FIX/loomwright/scripts/wrapdrift.sh")"
  M_NOSTEAL="$(scan_surface "$FIX" "$FIX/loomwright/scripts/nosteal.sh")"
  M_SUFFIX="$(scan_surface "$FIX" "$FIX/loomwright/scripts/suffix.sh")"

  case "$M_WGOOD" in
    OK*) ok "(M5) control: a pin on the line AFTER its citation is honoured (comments wrap at ~100 cols)" ;;
    *)   no "(M5) a wrapped pin was not honoured — authors would be forced onto one line: '$M_WGOOD'" ;;
  esac

  case "$M_WDRIFT" in
    PINMISS*) ok "(M6) mutation: a WRAPPED pin still catches drift — the lookahead did not weaken check (B)" ;;
    *)        no "(M6) VACUOUS GUARD: a wrapped pin failed to catch drift — verdict was '$M_WDRIFT'" ;;
  esac

  # The first citation must stay BARE (its next line has its own citation, so the pin there is
  # off limits); the second must be OK. Both verdicts are asserted, not just the count.
  case "$M_NOSTEAL" in
    *"BARE"*) case "$M_NOSTEAL" in
                *"OK"*) ok "(M7) a next-line pin is NOT borrowed across a line that has its own citation" ;;
                *)      no "(M7) the pinned second citation was not accepted: '$M_NOSTEAL'" ;;
              esac ;;
    *) no "(M7) a pin was STOLEN by the preceding citation — one pin vouched for two references: '$M_NOSTEAL'" ;;
  esac

  case "$M_SUFFIX" in
    OK*) ok "(M8) a partial-path citation resolves by unique suffix (41 files share the name SKILL.md)" ;;
    *)   no "(M8) suffix resolution failed — every partial-path citation would silently SKIP: '$M_SUFFIX'" ;;
  esac

  M_UNRES="$(scan_surface "$FIX" "$FIX/loomwright/scripts/unresolvable.sh")"
  M_AMBIG="$(scan_surface "$FIX" "$FIX/loomwright/scripts/ambiguous.sh")"
  M_BRACK="$(scan_surface "$FIX" "$FIX/loomwright/scripts/bracketcite.sh")"

  case "$M_UNRES" in
    SKIP*) ok "(M9) a citation to a nonexistent file SKIPs (illustrative prompts / gitignored targets)" ;;
    *)     no "(M9) an unresolvable citation did not SKIP — verdict was '$M_UNRES'" ;;
  esac

  # The SKIP verdicts above are only meaningful alongside M1/M8, which prove that a RESOLVABLE
  # citation does not skip. Together they pin the resolution chain from both sides.
  case "$M_AMBIG" in
    SKIP*) ok "(M10) an AMBIGUOUS basename SKIPs rather than guessing a target" ;;
    *)     no "(M10) an ambiguous citation was resolved to a guess — verdict was '$M_AMBIG'" ;;
  esac

  case "$M_BRACK" in
    OK*) ok "(M11) a pin literal containing \`]\` survives parsing (JSON / character-class pins)" ;;
    *)   no "(M11) a pin containing \`]\` was truncated at the bracket — verdict was '$M_BRACK'" ;;
  esac

  # (M12) The ratchet's membership test must be EXACT. Run against a two-entry allowlist in which
  # one entry is a strict substring of the other — the shape that makes a substring test silently
  # exempt an unlisted citation. Asserted in a subshell so the real BARE_ALLOWLIST is untouched.
  m12="$(
    BARE_ALLOWLIST="$(printf 'xa.md|b.sh:12\nother.md|c.sh:3')"
    allowlist_has "a.md|b.sh:1"    && echo "SUBSTRING-MATCHED"
    allowlist_has "xa.md|b.sh:12"  && echo "EXACT-MATCHED"
    :
  )"
  case "$m12" in
    "EXACT-MATCHED") ok "(M12) the ratchet allowlist matches whole entries only — no substring exemptions" ;;
    *SUBSTRING-MATCHED*) no "(M12) allowlist matched a SUBSTRING — one entry silently exempts a different citation" ;;
    *) no "(M12) allowlist failed to match its own exact entry — the ratchet would fire on listed citations: '$m12'" ;;
  esac
fi

echo
echo "citation-drift: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
