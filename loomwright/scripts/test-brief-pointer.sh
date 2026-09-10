#!/usr/bin/env bash
# test-brief-pointer.sh — self-tests for brief-pointer.sh, the ONE parser for a
# Supervisor brief's `- **Source requirement:**` pointer.
#
# ASSERTED THROUGH THE CALL SITES, NOT THROUGH THE HELPER IN ISOLATION. Every
# behavioural case below runs `reconcile-jobs.sh` or `stamp-requirement-status.sh`
# as a SUBPROCESS. That is deliberate and load-bearing: the helper existing and
# the consumers going through it are different claims, and only the second one is
# the change. A suite that sourced the helper directly would stay green with both
# consumers still carrying their own parse.
#
# `reconcile-jobs.sh` is never SOURCED here, either. Its main body runs at top
# level and ends in `exit 0`, so sourcing it from a test exits the TEST shell
# with status 0 — reporting green having run no assertion and having silently
# truncated every case after it. Subprocess, always.
#
# THE REFUSAL DISCRIMINATOR IS PINNED, because the obvious one collides.
# `reconcile-jobs.sh` emits state `unknown` for BOTH "the pointer was refused"
# and "the pointer resolved but carries no evidence", so a case asserting
# `state == unknown` passes with every containment guard deleted. Cases here
# discriminate on the `--porcelain` EVIDENCE STRING instead:
#     refused                 -> `did not resolve under`
#     resolved, unevidenced   -> `carries no done stamp`
#     resolved, stamped done  -> `stranded_closed` + `is stamped done`
#
# Runs entirely inside mktemp sandboxes; the real `.supervisor/` is never read or
# written. Exit 0 = all pass (auto-registered by ci.yml's
# `loomwright/scripts/test-*.sh` glob).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/brief-pointer.sh"
RECON="$SCRIPT_DIR/reconcile-jobs.sh"
STAMP="$SCRIPT_DIR/stamp-requirement-status.sh"

pass=0; fail=0
ok() { echo "ok   - $1"; pass=$((pass+1)); }
no() { echo "FAIL - $1"; fail=$((fail+1)); }

ROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$ROOT" 2>/dev/null; rm -rf "$ROOT" 2>/dev/null' EXIT
mktmp() { mktemp -d "$ROOT/d.XXXXXX"; }

# ─────────────────────────────────────────────────────────────────────────────
# THE REAL CORPUS'S THREE POINTER SHAPES, committed as in-repo fixtures.
#
# `.supervisor/**` is gitignored, so the corpus itself is absent from a fresh
# clone and CANNOT be asserted over in the CI-globbed suite — an assertion over
# that directory would self-skip and become a permanent vacuous pass in the only
# environment that runs this on every PR. What survives a fresh clone is the
# SHAPE coverage, so the three lines measured on 2026-09-10 are reproduced here
# verbatim in form, with the requirement paths renamed to sandbox ones:
#   bare            2026-09-04-ui-command-and-projects.md   (resolved in both)
#   backticks       2026-09-05-floor-ui-redesign.md         (resolved in NEITHER
#                                                            consumer's weaker
#                                                            parse — this brief's
#                                                            PR had merged 5 days
#                                                            earlier)
#   backticks+prose 2026-09-03-archive-views.md             (resolved in neither)
# ─────────────────────────────────────────────────────────────────────────────
REQ_BARE=".supervisor/requirements/loom-floor-ui/06-ui-command-and-projects.md"
REQ_TICK=".supervisor/requirements/floor-ui-redesign/01-floor-ui-redesign.md"
REQ_ANNO=".supervisor/requirements/loom-floor-ui/05-archive-views.md"

PTR_BARE="- **Source requirement:** $REQ_BARE"
PTR_TICK="- **Source requirement:** \`$REQ_TICK\`"
PTR_ANNO="- **Source requirement:** \`$REQ_ANNO\` (amended at intake 2026-09-03 — see the note under \`## Problem\` and the measurement appended to the second AC)"

# new_recon_repo <pointer-line> [requirement-body] -> sandbox path
# A repo skeleton with one in-progress brief. An empty pointer line stamps none
# at all. The requirement file is created (stamped `## Status: done` by default,
# so a RESOLVED pointer classifies stranded_closed and a REFUSED one cannot).
new_recon_repo() {
  local ptr="${1:-}" body="${2:-$(printf '# req\n\n## Status: done\n')}" r req
  r="$(mktmp)"
  mkdir -p "$r/.supervisor/jobs/in-progress" "$r/.supervisor/jobs/done" \
           "$r/.supervisor/automate" "$r/.supervisor/requirements"
  {
    echo "# Supervisor Job: thing"
    echo
    echo "## Environment"
    [ -n "$ptr" ] && echo "$ptr"
  } > "$r/.supervisor/jobs/in-progress/brief.md"
  for req in "$REQ_BARE" "$REQ_TICK" "$REQ_ANNO"; do
    mkdir -p "$r/$(dirname "$req")"
    printf '%s\n' "$body" > "$r/$req"
  done
  printf '%s' "$r"
}

# new_stamp_repo <pointer-line> -> sandbox path (a brief already in done/)
new_stamp_repo() {
  local ptr="${1:-}" r req
  r="$(mktmp)"
  mkdir -p "$r/.supervisor/jobs/done" "$r/.supervisor/requirements"
  {
    echo "# Supervisor Job: thing"
    echo
    echo "## Environment"
    [ -n "$ptr" ] && echo "$ptr"
  } > "$r/.supervisor/jobs/done/brief.md"
  for req in "$REQ_BARE" "$REQ_TICK" "$REQ_ANNO"; do
    mkdir -p "$r/$(dirname "$req")"
    printf '# Requirement\n\n- something\n' > "$r/$req"
  done
  printf '%s' "$r"
}

recon()  { (cd "$1" && bash "${2:-$RECON}" --porcelain 2>/dev/null) || true; }

# ═══ AC-1 — bare path still resolves through BOTH call sites (regression) ═════
r="$(new_recon_repo "$PTR_BARE")"
out="$(recon "$r")"
case "$out" in
  stranded_closed*"source requirement $REQ_BARE is stamped done"*)
    ok "AC-1 reconcile-jobs: bare pointer resolves to the path (regression)" ;;
  *) no "AC-1 reconcile-jobs: bare pointer regressed — $out" ;;
esac

s="$(new_stamp_repo "$PTR_BARE")"
bash "$STAMP" --project-root "$s" >/dev/null 2>&1
grep -qE '^## Status: brief-shipped' "$s/$REQ_BARE" \
  && ok "AC-1 stamp-requirement-status: bare pointer resolves (regression)" \
  || no "AC-1 stamp-requirement-status: bare pointer regressed"

# ═══ AC-2 — backticks resolve through reconcile-jobs.sh (broken before) ══════
r="$(new_recon_repo "$PTR_TICK")"
out="$(recon "$r")"
case "$out" in
  stranded_closed*"source requirement $REQ_TICK is stamped done"*)
    ok "AC-2 backticked pointer yields the same path as the unstyled one" ;;
  *) no "AC-2 backticked pointer did not resolve — $out" ;;
esac
case "$out" in
  *'`'*) no "AC-2 (control) a markdown delimiter survived into the resolved path" ;;
  *)     ok "AC-2 (control) no markdown delimiter survives into the resolved path" ;;
esac

# ═══ AC-3 — backticks + trailing annotation, through BOTH call sites ═════════
r="$(new_recon_repo "$PTR_ANNO")"
out="$(recon "$r")"
case "$out" in
  stranded_closed*"source requirement $REQ_ANNO is stamped done"*)
    ok "AC-3 reconcile-jobs: annotated pointer yields the path alone" ;;
  *) no "AC-3 reconcile-jobs: annotated pointer did not resolve — $out" ;;
esac
case "$out" in
  *"amended at intake"*) no "AC-3 (control) the trailing annotation leaked into the evidence path" ;;
  *)                     ok "AC-3 (control) the trailing annotation is not part of the path" ;;
esac

s="$(new_stamp_repo "$PTR_ANNO")"
bash "$STAMP" --project-root "$s" >/dev/null 2>&1
grep -qE '^## Status: brief-shipped' "$s/$REQ_ANNO" \
  && ok "AC-3 stamp-requirement-status: annotated pointer yields the path alone" \
  || no "AC-3 stamp-requirement-status: annotated pointer did not resolve"

# ═══ AC-4 — label variants all resolve identically ═══════════════════════════
# Capitalisation, leading whitespace, and presence/absence of the leading `- `.
ac4_fail=0
while IFS= read -r variant; do
  [ -n "$variant" ] || continue
  r="$(new_recon_repo "$variant")"
  out="$(recon "$r")"
  case "$out" in
    stranded_closed*"source requirement $REQ_BARE is stamped done"*) : ;;
    *) ac4_fail=$((ac4_fail+1)); echo "     variant failed: [$variant] -> $out" ;;
  esac
done <<VARIANTS
- **Source requirement:** $REQ_BARE
-  **source requirement:**  $REQ_BARE
  **SOURCE REQUIREMENT:** $REQ_BARE
**Source Requirement:**	$REQ_BARE
VARIANTS
[ "$ac4_fail" -eq 0 ] \
  && ok "AC-4 label case / leading whitespace / bullet-prefix variants all resolve identically" \
  || no "AC-4 $ac4_fail label variant(s) resolved differently"

# ═══ AC-5 — absent pointer is a silent no-op at both call sites ══════════════
r="$(new_recon_repo "")"
out="$(recon "$r")"
case "$out" in
  unknown*"no source requirement pointer on brief"*)
    ok "AC-5 reconcile-jobs: no pointer ⇒ silent no-op verdict, no error" ;;
  *) no "AC-5 reconcile-jobs: expected the no-pointer arm, got — $out" ;;
esac
(cd "$r" && bash "$RECON" --repair >/dev/null 2>&1); rc=$?
if [ "$rc" -eq 0 ] && [ -f "$r/.supervisor/jobs/in-progress/brief.md" ]; then
  ok "AC-5 reconcile-jobs: no pointer ⇒ exit 0 and the brief is left alone"
else
  no "AC-5 reconcile-jobs: no-pointer brief was touched or exit was $rc"
fi

s="$(new_stamp_repo "")"
bash "$STAMP" --project-root "$s" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && ! grep -qE '^## Status' "$s/$REQ_BARE" 2>/dev/null; then
  ok "AC-5 stamp-requirement-status: no pointer ⇒ nothing stamped, exit 0"
else
  no "AC-5 stamp-requirement-status: no-pointer brief stamped something or exit was $rc"
fi

# ═══ AC-6 — five containment guards, asserted through EACH call site ═════════
# One case per guard × two call sites = ten assertions, every one executed
# through the script as a subprocess.
#
# The two symlink victims deliberately carry `## Status: done`. With the guard
# removed the reconciler would classify the brief `stranded_closed` and `--repair`
# WOULD move it, so "the brief stayed in in-progress/" is a real discriminator
# rather than a no-op. (Proven by the containment mutation control below.)

plant_symlinks() {   # plant_symlinks <sandbox>
  mkdir -p "$1/outside" "$1/outside/reqdir"
  printf '# victim\n\n## Status: done\n' > "$1/outside/victim.md"
  printf '# victim\n\n## Status: done\n' > "$1/outside/reqdir/x.md"
  ln -s "$1/outside/victim.md" "$1/.supervisor/requirements/link.md"
  ln -s "$1/outside/reqdir"    "$1/.supervisor/requirements/sub"
}

# --- 6a. through reconcile-jobs.sh -------------------------------------------
guard_names="absolute .. outside-prefix symlink-final symlink-parent"
i=0
for evil in "/etc/passwd" \
            ".supervisor/requirements/../../etc/passwd" \
            "README.md" \
            ".supervisor/requirements/link.md" \
            ".supervisor/requirements/sub/x.md"; do
  i=$((i+1)); name="$(echo "$guard_names" | cut -d' ' -f$i)"
  r="$(new_recon_repo "- **Source requirement:** $evil")"
  plant_symlinks "$r"
  printf 'untouched\n' > "$r/README.md"
  out="$(recon "$r")"
  case "$out" in
    *"did not resolve under"*) ok "AC-6 reconcile-jobs refuses [$name] — '$evil'" ;;
    *) no "AC-6 reconcile-jobs did NOT refuse [$name] '$evil' — $out" ;;
  esac
  # The symlink cases additionally assert no lifecycle move happened under --repair.
  case "$name" in
    symlink-*)
      (cd "$r" && bash "$RECON" --repair >/dev/null 2>&1)
      if [ -f "$r/.supervisor/jobs/in-progress/brief.md" ] && [ ! -e "$r/.supervisor/jobs/done/brief.md" ]; then
        ok "AC-6 reconcile-jobs --repair did not move the brief for [$name]"
      else
        no "AC-6 reconcile-jobs --repair MOVED the brief for [$name]"
      fi ;;
  esac
done

# --- 6b. through stamp-requirement-status.sh ---------------------------------
# This is the sole WRITER to a requirement file, so the byte-unmodified clause
# binds here: the two symlink cases assert the target file is untouched, not
# merely that the run returned.
i=0
for evil in "/etc/passwd" \
            ".supervisor/requirements/../../etc/passwd" \
            "README.md" \
            ".supervisor/requirements/link.md" \
            ".supervisor/requirements/sub/x.md"; do
  i=$((i+1)); name="$(echo "$guard_names" | cut -d' ' -f$i)"
  s="$(new_stamp_repo "- **Source requirement:** $evil")"
  plant_symlinks "$s"
  printf 'untouched\n' > "$s/README.md"
  before_v="$(cat "$s/outside/victim.md")"
  before_x="$(cat "$s/outside/reqdir/x.md")"
  bash "$STAMP" --project-root "$s" >/dev/null 2>&1
  bad=0
  grep -qE '^## Status' "$s/README.md" 2>/dev/null && bad=1
  [ "$(cat "$s/outside/victim.md")"    = "$before_v" ] || bad=1
  [ "$(cat "$s/outside/reqdir/x.md")"  = "$before_x" ] || bad=1
  [ "$bad" -eq 0 ] \
    && ok "AC-6 stamp-requirement-status refuses [$name] and leaves the target byte-unmodified" \
    || no "AC-6 stamp-requirement-status wrote outside the containment root for [$name] '$evil'"
done

# ═══ AC-6b — no surviving weak guard set in reconcile-jobs.sh ════════════════
# `provides` can assert presence but never absence, so the deletion obligation is
# pinned here. BOTH the definition and every call site: the weak function was
# invoked twice (classify() and the repair status lookup), so asserting only "no
# definition" would leave a dangling call.
# Deliberately stricter than the criterion: this is a WHOLE-FILE match, so even a
# comment naming the deleted function fails. A dead name reappearing in a comment
# is the tell that the deletion is being reconsidered, and this file has nothing
# left to say about it — the rationale lives in brief-pointer.sh's header.
n_weak="$(grep -cF 'safe_requirement_path' "$RECON" 2>/dev/null || true)"
[ "${n_weak:-0}" -eq 0 ] \
  && ok "AC-6b reconcile-jobs.sh carries no safe_requirement_path definition or call site" \
  || no "AC-6b reconcile-jobs.sh still mentions safe_requirement_path ($n_weak line(s))"

# (control) the shared helper must not EXPORT that name either — reusing it would
# let a surviving local definition silently restore the weak containment via
# bash's last-definition-wins while every parsing case above stayed green.
# CODE only here, not whole-file: the helper's header is the one place that has to
# spell the forbidden name out in order to explain why it is forbidden, and a
# comment cannot shadow a function.
n_export="$(grep -vE '^[[:space:]]*#' "$HELPER" 2>/dev/null | grep -cF 'safe_requirement_path' || true)"
[ "${n_export:-0}" -eq 0 ] \
  && ok "AC-6b (control) the shared helper does not export safe_requirement_path" \
  || no "AC-6b (control) the shared helper exports the shadowable name safe_requirement_path"

# ═══ AC-7 — exactly one parsing rule, with the PREDICATE mutation-controlled ══
#
# The predicate is a FIXED-STRING search for `equirement:\*\*` — the label as it
# appears REGEX-ESCAPED inside a `sed`/`grep` argument. It matches structure that
# only a parse implementation has: prose and comments spell the field unescaped
# (`- **Source requirement:**`) and are correctly invisible to it. Two earlier
# proposals were silently vacuous — a literal `Source requirement` grep matches
# its own fixture strings, and an ERE `\*\*[Ss]ource [Rr]equirement:\*\*` matches
# NONE of the three real lines (their asterisks are backslash-escaped in source,
# and one spells the word with a `[Rr]` bracket class whose literal fourth
# character is `]`).
#
# Exclusions are by PATH, never by content: brief-pointer.sh is the one
# sanctioned implementation and `test-*.sh` files carry fixture strings. A
# content-based exclusion could hide a real second parser.
detect() {
  grep -rnF 'equirement:\*\*' "$1" 2>/dev/null \
    | grep -vE '/brief-pointer\.sh:' \
    | grep -vE '/test-[^/]*\.sh:' \
    || true
}

# --- arm (a) BASELINE: the predicate demonstrably detects what it exists to
#     detect. The three pre-change parse lines are embedded HERE, inside a
#     `test-*.sh` file the post-change arm already excludes by path — putting
#     them under loomwright/scripts/fixtures/ would place them back inside arm
#     (b)'s scan root and make the two arms mutually unsatisfiable.
pre="$(mktmp)"
cat > "$pre/a-reconcile-jobs.sh" <<'PRE_RECON'
brief_source_requirement() {
  sed -n 's/^- \*\*Source requirement:\*\*[[:space:]]*//p' "$1" 2>/dev/null | head -1
}
PRE_RECON
cat > "$pre/b-stamp-requirement-status.sh" <<'PRE_STAMP'
  raw="$(grep -m1 -iE '^[[:space:]]*-?[[:space:]]*\*\*Source requirement:\*\*' "$brief" 2>/dev/null)"
  req="$(printf '%s' "$raw" | sed -E 's/.*\*\*[Ss]ource [Rr]equirement:\*\*[[:space:]]*//')"
PRE_STAMP
n_pre="$(detect "$pre" | grep -c . || true)"
if [ "${n_pre:-0}" -ge 3 ]; then
  ok "AC-7 (a) baseline: the predicate finds all $n_pre pre-change parse lines"
else
  no "AC-7 (a) baseline: predicate found ${n_pre:-0} of the 3 known parse lines — arm (b) would be vacuous"
fi

# --- arm (b) POST-CHANGE: zero independent implementations remain.
n_now="$(detect "$SCRIPT_DIR" | grep -c . || true)"
if [ "${n_now:-0}" -eq 0 ]; then
  ok "AC-7 (b) no second label-parsing implementation remains under loomwright/scripts/"
else
  echo "$(detect "$SCRIPT_DIR")"
  no "AC-7 (b) ${n_now} independent label-parsing line(s) still present"
fi

# ═══ AC-8 — mutation control, with the MUTANT ITSELF GATED ═══════════════════
#
# A fixture corpus of only unstyled pointers would pass every case above with the
# delimiter handling deleted, so the mechanism is reverted and AC-2/AC-3 must turn
# red. The mutant is gated BEFORE the run is trusted (verified lesson fa32a308:
# `perl -0pi -e` interpolates `$VAR` inside the pattern even under \Q…\E so the
# mutation no-ops, and a `sed` delimiter colliding with the target line yields an
# EMPTY mutant — both pass every fail-open assertion).
#
# `awk` is used rather than `sed`/`perl` precisely to sidestep both traps: it
# matches with `index()` on a fixed string, so no delimiter and no variable
# interpolation is involved at all.
mutant_bin() {   # mutant_bin <marker-substring> -> a bin dir whose helper has that block cut
  local marker="$1" bin
  bin="$(mktmp)"
  cp "$RECON" "$STAMP" "$bin/" || return 1
  awk -v m=">>> $marker" -v e="<<< $marker" \
      'index($0,m){s=1} !s{print} index($0,e){s=0}' "$HELPER" > "$bin/brief-pointer.sh"
  printf '%s' "$bin"
}
gate_mutant() {  # gate_mutant <bin> <label> -> 0 when the mutant is trustworthy
  local bin="$1" label="$2" g=0
  [ -s "$bin/brief-pointer.sh" ] || { no "$label mutant is EMPTY — the cut collapsed the file"; g=1; }
  cmp -s "$bin/brief-pointer.sh" "$HELPER" && { no "$label mutant is byte-identical — the cut no-opped"; g=1; }
  bash -n "$bin/brief-pointer.sh" 2>/dev/null || { no "$label mutant does not parse — reads as broken, not as failing"; g=1; }
  [ "$g" -eq 0 ] && ok "$label mutant gated: non-empty, byte-differs, parses"
  return "$g"
}

bin="$(mutant_bin 'delimiter-strip')"
if gate_mutant "$bin" "AC-8"; then
  # (validity control) the mutant must still resolve the BARE pointer. Without
  # this, a mutant that merely broke the helper would satisfy the two red
  # assertions below for entirely the wrong reason.
  r="$(new_recon_repo "$PTR_BARE")"
  case "$(recon "$r" "$bin/reconcile-jobs.sh")" in
    stranded_closed*"$REQ_BARE"*) ok "AC-8 (validity control) the mutant still resolves a bare pointer" ;;
    *) no "AC-8 (validity control) the mutant broke the bare-pointer path too — the reds below prove nothing" ;;
  esac
  r="$(new_recon_repo "$PTR_TICK")"
  case "$(recon "$r" "$bin/reconcile-jobs.sh")" in
    *"did not resolve under"*) ok "AC-8 AC-2 turns RED with the delimiter strip reverted" ;;
    *) no "AC-8 AC-2 still passes with the delimiter strip reverted — the case is vacuous" ;;
  esac
  r="$(new_recon_repo "$PTR_ANNO")"
  case "$(recon "$r" "$bin/reconcile-jobs.sh")" in
    *"did not resolve under"*) ok "AC-8 AC-3 turns RED with the delimiter strip reverted" ;;
    *) no "AC-8 AC-3 still passes with the delimiter strip reverted — the case is vacuous" ;;
  esac
fi

# ═══ AC-6 mutation control — the containment cases are not vacuous either ════
# The five guards are asserted above through both call sites; this proves those
# assertions can FAIL. With the symlink block cut, the reconciler must resolve
# the planted link and `--repair` must move the brief — which is exactly the
# outcome the guard prevents.
bin="$(mutant_bin 'symlink-guard')"
if gate_mutant "$bin" "AC-6 (containment)"; then
  r="$(new_recon_repo "- **Source requirement:** .supervisor/requirements/link.md")"
  plant_symlinks "$r"
  case "$(recon "$r" "$bin/reconcile-jobs.sh")" in
    stranded_closed*) ok "AC-6 (containment control) the symlink case turns RED with the guard cut" ;;
    *) no "AC-6 (containment control) the symlink case passes with the guard cut — it is vacuous" ;;
  esac
fi

echo "---------------------------------------------------------------------------"
echo "test-brief-pointer: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
