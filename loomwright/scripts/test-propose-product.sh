#!/usr/bin/env bash
# test-propose-product.sh — self-tests for propose-product.sh, the PROPOSE-ONLY, CONFIRM-GATED
# bootstrap and sole writer of the committed `.agent/product.json` product-context store.
#
# WRITE CONTAINMENT IS THE POINT OF THIS FILE'S SHAPE, not an incidental precaution. Every case —
# INCLUDING the `--confirm` ones — runs inside a `mktemp -d` + `git init` throwaway tree, and the
# suite NEVER runs the writer against this repo. The reason is specific: this repo's root IS a
# primary checkout, so the writer's non-primary-checkout guard (the `.git`-is-a-FILE discriminator)
# does NOT protect it — a `--confirm` run here would happily create a real `.agent/product.json` in
# a TRACKED directory and a developer would find an unexplained file staged under their name.
# `git init` yields a `.git` DIRECTORY, so a throwaway tree passes the guard and the write really
# does happen there, which is what makes the assertions meaningful rather than trivially satisfied.
# Case (c) closes the loop by hashing the developer's REAL `.agent/` before and after the whole run.
# Precedent for the harness: test-add-rule.sh, whose own header records the same mktemp+git-init
# reason for never touching the real repo's `.agent/rules/`.
#
# Static-only: no network, no `gh`, no Docker. Exit 0 = all pass, 1 = any failure (auto-registered
# by ci.yml's `loomwright/scripts/test-*.sh` glob).
#
# Covers, mapped to the job's acceptance criteria:
#   (a) AC5  no store + NO --confirm + NO TTY  → a proposal is PRINTED and the working tree is
#            BYTE-IDENTICAL before and after (hashed, not read off the code), and no `.agent/` is
#            created at all
#   (b) AC7  --confirm inside the throwaway tree → `.agent/product.json` is created there and it is
#            the ONLY new path; every pre-existing file is byte-identical afterwards
#   (c) AC7  the developer's REAL `.agent/` is untouched by the entire suite, and this repo never
#            gains a `.agent/product.json`
#   (d)      the written store's SHAPE: all six required keys present, stance in the two-value enum,
#            and each competitor carries `last_fetched` as a PRESENT key whose value is null
#            (never fetched) — asserted with jq `has()`, because a `//` default would collapse a
#            legitimate null into the missing-key case
#   (e)      `stance_default_action` is EMITTED-BUT-NOT-STORED: it must NOT be a key in the file
#   (f)      --confirm WITHOUT --stance is REFUSED (non-zero) and writes nothing — stance decides a
#            default action and is never guessed
#   (g)      an out-of-enum --stance is REFUSED on every path, including the dry run
#   (h)      NO-CLOBBER: a second --confirm run refuses and leaves the existing store's bytes intact
#   (i)      the non-primary-checkout guard refuses (exit 3) when the top-level `.git` is a FILE,
#            WITH a positive control proving the same directory succeeds once it is a real checkout
#   (j)      MUTATION CONTROL for the containment assertions themselves: a deliberately-planted
#            stray file must make the tree-hash comparison FAIL. Without this, a hash function that
#            silently returned a constant would make every "wrote nothing" assertion above vacuous
#            while printing "ok".
#   (k-p)    THE WHOLE DOMAIN-SCAN CASCADE, branch by branch. new_repo() plants a README, and README
#            is the FIRST branch, so from it every later branch is unreachable BY CONSTRUCTION —
#            which is how they all went untested while the suite reported green. new_repo_bare()
#            plus seed() reach them: (k) the --domain override, asserted against a repo whose README
#            would otherwise win · (l) package.json · (m) composer.json · (n) pyproject.toml
#            `[project]` and `[tool.poetry]` · (o) Cargo.toml `[package]` · (p) the directory-name
#            placeholder. Each asserts the resolved `domain` VALUE **and** the `domain_source`
#            label — the label is what stops a case from passing off another branch's output.
#            Two of these are REGRESSIONS for defects the gap was hiding:
#              (o2) a SINGLE-QUOTED TOML literal string — the strip handled only double quotes, so
#                   `'A B2B invoicing API'` reached the committed field with its delimiters;
#              (n1)/(o1) a `description` under an EARLIER table (`[tool.black]`, `[dependencies.foo]`)
#                   beat the real `[project]`/`[package]` one, committing another package's blurb as
#                   this project's identity.
#            (o3) pins the deliberate consequence of the fix: a description found ONLY under an
#            unrecognised table is DISCARDED, not used as a first-match fallback.
#              (o4)-(o8) are the REGRESSION for the defect the (o2) fix itself introduced: the
#                   closing delimiter was found by scanning BACKWARD from the end of the line, so a
#                   quote inside a trailing `# comment` matched instead of the real one and the
#                   value swallowed the real closing quote plus part of the comment. (o5) is the
#                   quote-free-comment CONTROL that passed throughout — the pair is what shows the
#                   trigger is a quote INSIDE the comment. (o7) pins the unterminated value being
#                   left exactly as written; (o8) pins the honest limit for a string that closes
#                   mid-line.
#   (q)      every --competitor REJECTION path — embedded newline, missing `|`, empty name, empty
#            url — each on the CONFIRM path, with the exit status PINNED (1, confirmed empirically)
#            and a positive control proving a well-formed value gets through the same repo.
#
#   jq is a HARD dependency of the writer (unlike the reader, which skips fail-safe without it), so
#   a host with no jq has no write path to exercise. The suite then reports a DEGRADED RUN and
#   asserts only what remains true: the writer refuses, and the real .agent/ is untouched.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRITER="$HERE/propose-product.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"

pass=0; fail=0
ok() { echo "  ok: $1"; pass=$((pass+1)); }
no() { echo "  FAIL: $1"; fail=$((fail+1)); }

if [ ! -f "$WRITER" ]; then
  echo "  FAIL: writer not found at $WRITER"
  echo "RESULT: 0 passed, 1 failed"
  exit 1
fi

ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT" 2>/dev/null' EXIT

# ---------------------------------------------------------------------------
# Harness helpers.
# ---------------------------------------------------------------------------

# tree_list <dir> — every regular file path under <dir>, excluding .git, sorted stably.
tree_list() {
  ( cd "$1" 2>/dev/null && find . -path ./.git -prune -o -type f -print 2>/dev/null | LC_ALL=C sort )
}

# tree_hash <dir> — a content-AND-path digest of the whole tree (excluding .git). Two trees compare
# equal only if they hold the same paths with the same bytes. Used for the byte-identical
# before/after assertions; case (j) is the control that proves it actually discriminates.
tree_hash() {
  local d="$1" p
  ( cd "$d" 2>/dev/null || exit 0
    tree_list "." | while IFS= read -r p; do
      printf '%s\t' "$p"
      cksum < "$p" 2>/dev/null
    done
  ) | cksum
}

# new_repo — a throwaway PRIMARY checkout (`git init` ⇒ a `.git` DIRECTORY, so it passes the
# writer's non-primary-checkout guard) carrying a scannable README and one commit for provenance.
new_repo() {
  local r; r="$(mktemp -d "$ROOT/repo.XXXXXX")"
  (
    cd "$r" || exit 1
    git init -q
    git config user.email t@t
    git config user.name t
    printf '# Acme Invoicing\n\nA B2B invoicing API for finance teams.\n' > README.md
    printf 'placeholder\n' > src.txt
    git add -A
    git commit -qm init
  ) >/dev/null 2>&1
  printf '%s' "$r"
}

# new_repo_bare — a throwaway PRIMARY checkout carrying NO scannable description source at all: no
# README.md, no package.json, no *.toml. new_repo() always plants a README, and README is the FIRST
# branch of the domain cascade, so from new_repo() every LATER branch is unreachable by construction
# — which is exactly how those branches went untested. This is the entry point for reaching them.
new_repo_bare() {
  local r; r="$(mktemp -d "$ROOT/repo.XXXXXX")"
  (
    cd "$r" || exit 1
    git init -q
    git config user.email t@t
    git config user.name t
    printf 'placeholder\n' > src.txt
    git add -A
    git commit -qm init
  ) >/dev/null 2>&1
  printf '%s' "$r"
}

# seed <repo> <filename> — write stdin into <repo>/<filename> and commit it.
seed() {
  local r="$1" f="$2"
  cat > "$r/$f"
  ( cd "$r" && git add -A && git commit -qm seed ) >/dev/null 2>&1
}

# run_writer <repo> [args...] → sets OUT (stdout+stderr) and RC. stdin is /dev/null so the writer's
# interactive-TTY branch can never be taken — the no-TTY half of AC5 is part of the invocation.
run_writer() {
  local repo="$1"; shift
  OUT="$( ( cd "$repo" && bash "$WRITER" "$@" ) </dev/null 2>&1 )"; RC=$?
}

# proposed_domain / proposed_source — the RESOLVED values out of the last dry run's PLANNED WRITE.
# These read the writer's own printed proposal (the `object:` JSON and the `domain source:` label),
# so a scan assertion is about the value that would be COMMITTED, not merely about exit 0.
proposed_domain() {
  printf '%s\n' "$OUT" | sed -n '/^  object: /,$p' | sed '1s/^  object: //' | jq -r '.domain' 2>/dev/null
}
proposed_source() {
  printf '%s\n' "$OUT" | sed -n 's/^  domain source: //p'
}

# expect_scan <label> <repo> <expected domain> <expected source> [extra writer args...]
# A DRY RUN (no --confirm) — nothing is written anywhere — asserting BOTH the resolved `domain`
# value and the `domain_source` label. Asserting the label as well as the value is what stops a
# case from passing because some OTHER branch of the cascade happened to produce the same string.
expect_scan() {
  local label="$1" repo="$2" want_dom="$3" want_src="$4"; shift 4
  run_writer "$repo" "$@"
  local got_dom got_src
  got_dom="$(proposed_domain)"
  got_src="$(proposed_source)"
  [ "$RC" -eq 0 ] && ok "$label: the dry run exits 0" \
                  || no "$label: the dry run exited $RC — output: $OUT"
  [ "$got_dom" = "$want_dom" ] && ok "$label: domain = [$want_dom]" \
                               || no "$label: domain was [$got_dom], expected [$want_dom]"
  [ "$got_src" = "$want_src" ] && ok "$label: domain_source = [$want_src]" \
                               || no "$label: domain_source was [$got_src], expected [$want_src]"
}

# expect_competitor_reject <label> <repo> <message needle> <--competitor value>
# Runs the CONFIRM path — the one that could actually write — and pins the exit status, the reason,
# and that the tree is untouched.
expect_competitor_reject() {
  local label="$1" repo="$2" needle="$3" comp="$4"
  local before after
  before="$(tree_hash "$repo")"
  run_writer "$repo" --confirm --stance tool --competitor "$comp"
  after="$(tree_hash "$repo")"
  # Exit 1 is PINNED, not merely "non-zero", and was confirmed empirically against this writer
  # rather than assumed: these are ARGUMENT rejections and belong to the header's documented
  # `1 refused`, NOT to the `2 shape validation failed` class that (f)/(g) pin. A regression that
  # renumbered one of them would sail past a `-ne 0` check.
  [ "$RC" -eq 1 ] && ok "$label: refused with the documented status 1 (refused)" \
                  || no "$label: expected exit 1 (refused), got $RC — output: $OUT"
  case "$OUT" in
    *"$needle"*) ok "$label: the refusal names the reason" ;;
    *) no "$label: the refusal does not say [$needle] — output: $OUT" ;;
  esac
  [ "$before" = "$after" ] && ok "$label: the tree is byte-identical — nothing was written" \
                           || no "$label: the refused run modified the tree"
  [ ! -e "$repo/.agent/product.json" ] && ok "$label: no store was created" \
                                       || no "$label: a store was created despite the refusal"
}

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

# ---------------------------------------------------------------------------
# (c) PRE-flight half — snapshot the developer's REAL .agent/ before anything runs.
# ---------------------------------------------------------------------------
REAL_AGENT="$REPO_ROOT/.agent"
REAL_AGENT_BEFORE="$(tree_hash "$REAL_AGENT")"
REAL_STORE_ABSENT_BEFORE=0
[ ! -e "$REAL_AGENT/product.json" ] && REAL_STORE_ABSENT_BEFORE=1

# ---------------------------------------------------------------------------
# jq is a HARD dependency of this writer, unlike the READER, which skips fail-safe without it. So
# when jq is absent there is no write path to test at all: the suite degrades to the one assertion
# that is still meaningful — the writer must REFUSE rather than write bytes it could not validate —
# plus the real-.agent containment checks. It is reported as a DEGRADED RUN rather than silently
# reporting a smaller green tally as if it were the full suite.
# ---------------------------------------------------------------------------
if [ "$HAVE_JQ" -eq 0 ]; then
  echo "== DEGRADED RUN: jq is absent on this host =="
  echo "   propose-product.sh requires jq, so every write-path case is unreachable here."
  echo "   Running the refusal case and the real-.agent containment checks only."
  r_nojq="$(new_repo)"
  before_nojq="$(tree_hash "$r_nojq")"
  run_writer "$r_nojq" --confirm --stance tool
  after_nojq="$(tree_hash "$r_nojq")"
  [ "$RC" -ne 0 ] && ok "[no jq] the writer REFUSES rather than writing unvalidated bytes (rc=$RC)" \
                  || no "[no jq] the writer did not refuse without jq"
  [ "$before_nojq" = "$after_nojq" ] && ok "[no jq] nothing was written" \
                                     || no "[no jq] the refused run modified the tree"
  REAL_AGENT_AFTER="$(tree_hash "$REAL_AGENT")"
  [ "$REAL_AGENT_BEFORE" = "$REAL_AGENT_AFTER" ] \
    && ok "(c) the real repo's .agent/ is byte-identical before and after the suite" \
    || no "(c) THIS SUITE MODIFIED the real repo's .agent/"
  [ ! -e "$REAL_AGENT/product.json" ] \
    && ok "(c) the real repo still carries no .agent/product.json" \
    || no "(c) the suite CREATED .agent/product.json in this repo"
  echo
  echo "RESULT: $pass passed, $fail failed (DEGRADED — jq absent)"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
fi

# ============================================================================
echo "== (a) AC5 — no --confirm, no TTY: a proposal is printed and NOTHING is written =="
r_a="$(new_repo)"
before_a="$(tree_hash "$r_a")"
list_before_a="$(tree_list "$r_a")"
run_writer "$r_a"
after_a="$(tree_hash "$r_a")"
list_after_a="$(tree_list "$r_a")"

[ "$RC" -eq 0 ] && ok "(a) the dry run exits 0" \
                || no "(a) the dry run exited $RC (expected 0) — output: $OUT"
case "$OUT" in
  *"PLANNED WRITE (not written"*) ok "(a) it PRINTS a proposal (PLANNED WRITE banner)" ;;
  *) no "(a) no PLANNED WRITE proposal was printed — output: $OUT" ;;
esac
case "$OUT" in
  *"product.json"*) ok "(a) the proposal names the target store" ;;
  *) no "(a) the proposal does not name the target store" ;;
esac
case "$OUT" in
  *"--stance"*) ok "(a) the proposal says --stance is what stands between it and a write" ;;
  *) no "(a) the proposal does not mention the required --stance" ;;
esac
[ "$before_a" = "$after_a" ] && ok "(a) the working tree is BYTE-IDENTICAL before and after (hashed)" \
                             || no "(a) the dry run MODIFIED the working tree"
[ "$list_before_a" = "$list_after_a" ] && ok "(a) no path was added or removed" \
                                       || no "(a) the dry run changed the file list"
[ ! -e "$r_a/.agent" ] && ok "(a) no .agent/ directory was created at all" \
                       || no "(a) the dry run created $r_a/.agent"

# ============================================================================
echo "== (b) AC7 — --confirm writes EXACTLY .agent/product.json, and nothing else =="
r_b="$(new_repo)"
before_b="$(tree_hash "$r_b")"
list_before_b="$(tree_list "$r_b")"
run_writer "$r_b" --confirm --stance tool \
  --audience "finance teams — ASSUMED" \
  --competitor "Stripe Billing|https://stripe.com/billing" \
  --competitor "Chargebee|https://chargebee.com"
list_after_b="$(tree_list "$r_b")"
STORE_B="$r_b/.agent/product.json"

[ "$RC" -eq 0 ] && ok "(b) the confirmed run exits 0" \
                || no "(b) the confirmed run exited $RC — output: $OUT"
[ -f "$STORE_B" ] && ok "(b) .agent/product.json was created in the THROWAWAY tree" \
                  || no "(b) .agent/product.json was NOT created — output: $OUT"

# The ONLY new path must be ./.agent/product.json — asserted as a set difference over the file
# lists, so an extra log, backup or leftover temp file anywhere in the tree is caught.
added_b="$(comm -13 <(printf '%s\n' "$list_before_b") <(printf '%s\n' "$list_after_b"))"
removed_b="$(comm -23 <(printf '%s\n' "$list_before_b") <(printf '%s\n' "$list_after_b"))"
[ "$added_b" = "./.agent/product.json" ] \
  && ok "(b) the ONLY added path is ./.agent/product.json" \
  || no "(b) unexpected added paths: [$added_b]"
[ -z "$removed_b" ] && ok "(b) no pre-existing path was removed" \
                    || no "(b) paths were removed: [$removed_b]"

# Every pre-existing file must still hold its original bytes: hash the tree with the new store
# excluded and compare against the before-hash.
if [ -f "$STORE_B" ]; then
  cp -R "$r_b" "$ROOT/b-copy"
  rm -f "$ROOT/b-copy/.agent/product.json"
  rmdir "$ROOT/b-copy/.agent" 2>/dev/null
  after_b_excl="$(tree_hash "$ROOT/b-copy")"
  [ "$before_b" = "$after_b_excl" ] \
    && ok "(b) every pre-existing file is byte-identical (only the store was added)" \
    || no "(b) the confirmed run also changed pre-existing files"
fi

# ============================================================================
echo "== (d) the written store's SHAPE =="
if [ -f "$STORE_B" ]; then
  jq -e 'type == "object"' "$STORE_B" >/dev/null 2>&1 \
    && ok "(d) the store root is a JSON object" || no "(d) the store root is not a JSON object"

  missing=""
  for k in domain stance audience competitors written_at head_sha; do
    jq -e --arg k "$k" 'has($k)' "$STORE_B" >/dev/null 2>&1 || missing="$missing $k"
  done
  [ -z "$missing" ] && ok "(d) all six required keys are present" \
                    || no "(d) required keys missing:$missing"

  jq -e '.stance == "tool"' "$STORE_B" >/dev/null 2>&1 \
    && ok "(d) stance is the value that was supplied, in the two-value enum" \
    || no "(d) stance is not the supplied enum value"

  jq -e '.competitors | length == 2' "$STORE_B" >/dev/null 2>&1 \
    && ok "(d) both --competitor entries were recorded" \
    || no "(d) the competitors array does not hold the two supplied entries"

  # NULLABLE-REQUIRED: the KEY must be present (has()) AND, since nothing was fetched, its value
  # must be exactly null. A date here would be an invention — this writer performs no network call.
  jq -e '.competitors | all(has("last_fetched"))' "$STORE_B" >/dev/null 2>&1 \
    && ok "(d) every competitor carries last_fetched as a PRESENT key (jq has())" \
    || no "(d) a competitor is missing the required last_fetched key"
  jq -e '.competitors | all(.last_fetched == null)' "$STORE_B" >/dev/null 2>&1 \
    && ok "(d) every last_fetched is exactly null (never fetched — no date was invented)" \
    || no "(d) a last_fetched carries a value, but nothing was ever fetched"

  jq -e '(.domain | type == "string") and (.domain | length > 0)' "$STORE_B" >/dev/null 2>&1 \
    && ok "(d) domain is a non-empty string (scanned from the throwaway README)" \
    || no "(d) domain is empty or not a string"
  jq -e '.domain | test("Acme Invoicing")' "$STORE_B" >/dev/null 2>&1 \
    && ok "(d) domain was actually SCANNED from the project (README H1 is present in it)" \
    || no "(d) domain does not reflect the scanned README — the scan is not doing anything"

  # ==========================================================================
  echo "== (e) stance_default_action is EMITTED-BUT-NOT-STORED =="
  jq -e 'has("stance_default_action") | not' "$STORE_B" >/dev/null 2>&1 \
    && ok "(e) the written store carries NO stance_default_action key" \
    || no "(e) the writer stored stance_default_action — it is a reader output only"
fi

# ============================================================================
echo "== (f) --confirm WITHOUT --stance is refused, and writes nothing =="
r_f="$(new_repo)"
before_f="$(tree_hash "$r_f")"
run_writer "$r_f" --confirm
after_f="$(tree_hash "$r_f")"
# Exit 2 is PINNED, not merely "non-zero": propose-product.sh's header documents a distinct
# `2 shape validation failed` (V1–V5), and a regression collapsing it into the generic `1 refused`
# would sail past a `-ne 0` check. This path is V3 on the WRITE side.
[ "$RC" -eq 2 ] && ok "(f) refused with the documented shape-validation status 2" \
                || no "(f) expected exit 2 (shape validation failed), got $RC"
case "$OUT" in
  *"never guessed"*) ok "(f) the refusal says stance is never guessed" ;;
  *) no "(f) the refusal does not explain why stance cannot be defaulted — output: $OUT" ;;
esac
[ "$before_f" = "$after_f" ] && ok "(f) the tree is byte-identical — nothing was written" \
                             || no "(f) the refused run still modified the tree"
[ ! -e "$r_f/.agent/product.json" ] && ok "(f) no store was created" \
                                    || no "(f) a store was created despite the refusal"

# ============================================================================
echo "== (g) an out-of-enum --stance is refused on EVERY path, including the dry run =="
r_g="$(new_repo)"
before_g="$(tree_hash "$r_g")"
run_writer "$r_g" --stance banana
[ "$RC" -eq 2 ] && ok "(g) the DRY RUN refuses an out-of-enum stance with the documented status 2" \
                || no "(g) expected exit 2 (shape validation failed) from the dry run, got $RC"
run_writer "$r_g" --confirm --stance banana
after_g="$(tree_hash "$r_g")"
[ "$RC" -eq 2 ] && ok "(g) the CONFIRMED run refuses an out-of-enum stance with the documented status 2" \
                || no "(g) expected exit 2 (shape validation failed) from the confirmed run, got $RC"
[ "$before_g" = "$after_g" ] && ok "(g) neither refused run wrote anything" \
                             || no "(g) a refused out-of-enum run modified the tree"

# ============================================================================
echo "== (h) NO-CLOBBER — a second --confirm run refuses and leaves the store intact =="
if true; then
  r_h="$(new_repo)"
  run_writer "$r_h" --confirm --stance product
  first_rc="$RC"
  store_h="$r_h/.agent/product.json"
  if [ "$first_rc" -eq 0 ] && [ -f "$store_h" ]; then
    ok "(h) the first confirmed run wrote the store"
    bytes_before="$(cksum < "$store_h")"
    run_writer "$r_h" --confirm --stance tool
    bytes_after="$(cksum < "$store_h")"
    [ "$RC" -ne 0 ] && ok "(h) the second confirmed run REFUSES (non-zero: $RC)" \
                    || no "(h) the second confirmed run did not refuse — a bootstrap must not clobber a curated store"
    [ "$bytes_before" = "$bytes_after" ] \
      && ok "(h) the existing store's bytes are unchanged (stance stayed 'product')" \
      || no "(h) the existing store was overwritten"
  else
    no "(h) could not establish a store for the no-clobber case (rc=$first_rc)"
  fi
fi

# ============================================================================
echo "== (i) non-primary-checkout guard — a top-level .git FILE is refused (exit 3) =="
# A linked worktree's (and a submodule's) top-level carries a `.git` FILE rather than a directory;
# that is the whole discriminator, so a `.git` file is a faithful simulation of the condition.
r_i="$(mktemp -d "$ROOT/wt.XXXXXX")"
printf '# Fake\n\nA simulated non-primary checkout.\n' > "$r_i/README.md"
printf 'gitdir: /nonexistent/worktrees/fake\n' > "$r_i/.git"
[ -f "$r_i/.git" ] && ok "(i) the simulation is effective: the top-level .git is a FILE" \
                   || no "(i) the simulation is INVALID — .git is not a file"
before_i="$(tree_hash "$r_i")"
run_writer "$r_i" --confirm --stance tool
after_i="$(tree_hash "$r_i")"
[ "$RC" -eq 3 ] && ok "(i) refused with the dedicated exit status 3" \
                || no "(i) expected exit 3 from the non-primary-checkout guard, got $RC — output: $OUT"
case "$OUT" in
  *"worktree"*submodule*|*submodule*worktree*) ok "(i) the refusal names BOTH the worktree and the submodule case" ;;
  *) no "(i) the refusal does not name both causes of a .git FILE — output: $OUT" ;;
esac
[ "$before_i" = "$after_i" ] && ok "(i) nothing was written in the refused checkout" \
                             || no "(i) the refused non-primary checkout was modified"
# POSITIVE CONTROL — the same directory, once it is a genuine primary checkout, must get past the
# guard. Without this, exit 3 could be coming from anything at all in that directory.
rm -f "$r_i/.git"
( cd "$r_i" && git init -q && git config user.email t@t && git config user.name t \
    && git add -A && git commit -qm init ) >/dev/null 2>&1
run_writer "$r_i"
[ "$RC" -eq 0 ] && ok "(i) CONTROL: the same directory, as a real checkout, gets past the guard" \
                || no "(i) CONTROL FAILED: the guard is not what refused the .git-file case (rc=$RC)"

# ============================================================================
echo "== (k) the --domain explicit override BEATS a live scan candidate =="
# Deliberately run against a repo whose README WOULD produce a candidate: an override that only
# worked when nothing else was found would be indistinguishable from the fallback.
r_k="$(new_repo)"
expect_scan "(k)" "$r_k" "a domain nothing in this repo could have produced" "--domain (explicit)" \
  --domain "a domain nothing in this repo could have produced"

# ============================================================================
echo "== (l) scan_json_description — package.json .description =="
r_l="$(new_repo_bare)"
seed "$r_l" package.json <<'JSON'
{ "name": "acme", "description": "A B2B invoicing API for finance teams" }
JSON
expect_scan "(l)" "$r_l" "A B2B invoicing API for finance teams" "package.json .description"

# ============================================================================
echo "== (m) scan_json_description — composer.json .description (the LAST cascade branch) =="
r_m="$(new_repo_bare)"
seed "$r_m" composer.json <<'JSON'
{ "name": "acme/billing", "description": "A PHP billing engine" }
JSON
expect_scan "(m)" "$r_m" "A PHP billing engine" "composer.json .description"

# ============================================================================
echo "== (n) scan_toml_description — pyproject.toml, table-scoped =="
# REGRESSION FOR DEFECT 2: a `description` under an EARLIER, unrelated table must not win. A
# first-match-anywhere scan returns the tool's blurb here.
r_n1="$(new_repo_bare)"
seed "$r_n1" pyproject.toml <<'TOML'
[tool.black]
description = "WRONG - a formatter's own blurb"

[project]
name = "acme"
description = "A PEP 621 packaged service"
TOML
expect_scan "(n1)" "$r_n1" "A PEP 621 packaged service" "pyproject.toml description"

# `[tool.poetry]` is still common and is the documented second choice for pyproject.toml.
r_n2="$(new_repo_bare)"
seed "$r_n2" pyproject.toml <<'TOML'
[tool.poetry]
name = "acme"
description = "A poetry-packaged service"
TOML
expect_scan "(n2)" "$r_n2" "A poetry-packaged service" "pyproject.toml description"

# ============================================================================
echo "== (o) scan_toml_description — Cargo.toml, table-scoped and quote-correct =="
# REGRESSION FOR DEFECT 2, Cargo flavour: `[dependencies.foo]` sits ABOVE `[package]`.
r_o1="$(new_repo_bare)"
seed "$r_o1" Cargo.toml <<'TOML'
[dependencies.foo]
version = "1.0"
description = "WRONG - a dependency blurb"

[package]
name = "acme"
description = "RIGHT - the real project"
TOML
expect_scan "(o1)" "$r_o1" "RIGHT - the real project" "Cargo.toml description"

# REGRESSION FOR DEFECT 1: TOML permits single-quoted LITERAL strings. Stripping only double quotes
# left the delimiters in the committed `domain`.
r_o2="$(new_repo_bare)"
seed "$r_o2" Cargo.toml <<'TOML'
[package]
name = "acme"
description = 'A B2B invoicing API'
TOML
expect_scan "(o2)" "$r_o2" "A B2B invoicing API" "Cargo.toml description"

# The deliberate NO-FIRST-MATCH-FALLBACK decision, pinned: when the ONLY description in the file
# belongs to an unrecognised table, the scan yields NOTHING and the cascade falls through to the
# honest placeholder — rather than committing another package's blurb as this project's identity.
r_o3="$(new_repo_bare)"
seed "$r_o3" Cargo.toml <<'TOML'
[dependencies.foo]
description = "WRONG - a dependency blurb"
TOML
run_writer "$r_o3"
dom_o3="$(proposed_domain)"
case "$dom_o3" in
  *"WRONG - a dependency blurb"*) no "(o3) a dependency's blurb was adopted as this project's domain: [$dom_o3]" ;;
  *"SCAN FOUND NO DESCRIPTION"*)  ok "(o3) an unrecognised table's description is DISCARDED — the scan falls through to the placeholder" ;;
  *) no "(o3) unexpected domain for an unrecognised-table-only manifest: [$dom_o3]" ;;
esac

# REGRESSION FOR DEFECT 3 — introduced by the fix for DEFECT 1 and caught in review. The closing
# delimiter was located by scanning BACKWARD from the end of the line for the same quote character.
# A trailing `# comment` containing a quote therefore matched instead of the real delimiter, and the
# value absorbed the real closing quote plus part of the comment. The fix scans FORWARD from just
# after the opening delimiter, so the FIRST subsequent matching quote closes the string and only
# what genuinely follows it is dropped. Each case below asserts the resolved `domain` VALUE and the
# `domain_source` LABEL — not exit 0, which the defect never disturbed.
r_o4="$(new_repo_bare)"
seed "$r_o4" Cargo.toml <<'TOML'
[package]
name = "acme"
description = "A B2B invoicing API" # uses "REST" style
TOML
expect_scan "(o4) trailing comment CONTAINING a quote" "$r_o4" \
  "A B2B invoicing API" "Cargo.toml description"

# The CONTROL for (o4): the same shape with a quote-free comment. It passed even with the backward
# scan, which is precisely why the defect shipped — without this pairing, (o4) alone cannot show
# that the trigger is a quote INSIDE the comment rather than the presence of a comment at all.
r_o5="$(new_repo_bare)"
seed "$r_o5" Cargo.toml <<'TOML'
[package]
name = "acme"
description = "A plain API" # no quotes in this comment
TOML
expect_scan "(o5) CONTROL — trailing comment with NO quote" "$r_o5" \
  "A plain API" "Cargo.toml description"

# The single-quoted flavour of the same defect: an apostrophe in the comment is a literal-string
# delimiter, so `it's` was matched as the close.
r_o6="$(new_repo_bare)"
seed "$r_o6" Cargo.toml <<'TOML'
[package]
description = 'A plain API' # it's fine
TOML
expect_scan "(o6) single-quoted, apostrophe in the comment" "$r_o6" \
  "A plain API" "Cargo.toml description"

# UNTERMINATED VALUE — no closing delimiter anywhere on the line. The header promises this is left
# EXACTLY AS WRITTEN, opening delimiter included, rather than reshaped into something that looks
# valid. The backward scan honoured that only when the line held no second quote of any kind.
r_o7="$(new_repo_bare)"
seed "$r_o7" Cargo.toml <<'TOML'
[package]
description = "oops # a lone opening quote
TOML
expect_scan "(o7) unterminated — left exactly as written" "$r_o7" \
  '"oops # a lone opening quote' "Cargo.toml description"

# The HONEST LIMIT, pinned so it is a decision rather than a surprise: a line whose string closes
# MID-LINE and is followed by more text is not an unterminated value — TOML ends the string at that
# second quote. So the scan yields the content up to it (trailing space and all) and drops the rest.
# The backward scan returned `oops # a "quoted` here, which is neither reading.
r_o8="$(new_repo_bare)"
seed "$r_o8" Cargo.toml <<'TOML'
[package]
description = "oops # a "quoted" word
TOML
expect_scan "(o8) closes mid-line — content up to the first close" "$r_o8" \
  'oops # a ' "Cargo.toml description"

# ============================================================================
echo "== (p) the directory-name PLACEHOLDER fallback — nothing scannable at all =="
r_p="$(new_repo_bare)"
expect_scan "(p)" "$r_p" \
  "$(basename "$r_p") — SCAN FOUND NO DESCRIPTION; replace this with what this project is, in the terms its own market uses" \
  "repo directory name (nothing else found — this is a placeholder, not a finding)"
case "$(proposed_domain)" in
  *"SCAN FOUND NO DESCRIPTION"*) ok "(p) the placeholder SAYS it is a placeholder rather than posing as a finding" ;;
  *) no "(p) the fallback value does not announce itself as unscanned" ;;
esac

# CONTAINMENT for the whole scan block: every case above is a dry run, so not one of them may have
# created a store. Asserted once, over all of them, rather than trusting each case's exit code.
scan_leak=""
for d in "$r_k" "$r_l" "$r_m" "$r_n1" "$r_n2" "$r_o1" "$r_o2" "$r_o3" "$r_o4" "$r_o5" "$r_o6" "$r_o7" "$r_o8" "$r_p"; do
  [ -e "$d/.agent" ] && scan_leak="$scan_leak $d"
done
[ -z "$scan_leak" ] && ok "(k-p) every scan case stayed a DRY RUN — no .agent/ anywhere" \
                    || no "(k-p) a scan case created .agent/:$scan_leak"

# ============================================================================
echo "== (q) every --competitor rejection path refuses, and writes nothing =="
r_q="$(new_repo)"
# An embedded newline is rejected at PARSE time, before the value is appended: the accumulator is
# newline-terminated, so one flag would silently become two competitors.
expect_competitor_reject "(q1) embedded newline" "$r_q" \
  "may not contain newline characters" "$(printf 'Acme\nBad|https://acme.example')"
expect_competitor_reject "(q2) missing | separator" "$r_q" \
  'must be of the form' "AcmeNoSeparator"
expect_competitor_reject "(q3) empty name" "$r_q" \
  "has an empty name" "|https://acme.example"
expect_competitor_reject "(q4) empty url" "$r_q" \
  "has an empty url" "Acme|"
# CONTROL: the same repo, with a WELL-FORMED competitor, must get all the way through — otherwise
# the four refusals above could be coming from anything in that directory rather than from the
# competitor validation.
run_writer "$r_q" --confirm --stance tool --competitor "Stripe Billing|https://stripe.com/billing"
[ "$RC" -eq 0 ] && [ -f "$r_q/.agent/product.json" ] \
  && ok "(q) CONTROL: the same repo accepts a well-formed --competitor and writes the store" \
  || no "(q) CONTROL FAILED: the competitor validation is not what refused q1-q4 (rc=$RC)"
if [ -f "$r_q/.agent/product.json" ]; then
  jq -e '.competitors == [{name: "Stripe Billing", url: "https://stripe.com/billing", last_fetched: null}]' \
    "$r_q/.agent/product.json" >/dev/null 2>&1 \
    && ok "(q) CONTROL: exactly the one accepted competitor was recorded — no rejected value leaked in" \
    || no "(q) CONTROL: the competitors array is not exactly the one accepted entry"
fi

# ============================================================================
echo "== (j) MUTATION CONTROL — the containment assertions must actually discriminate =="
# Every "nothing was written" assertion above rests on tree_hash(). If that function could not see a
# change, all of them would pass for free. Plant one stray file and require the comparison to fail.
r_j="$(new_repo)"
h1_j="$(tree_hash "$r_j")"
printf 'a file the writer never created\n' > "$r_j/stray.txt"
h2_j="$(tree_hash "$r_j")"
[ "$h1_j" != "$h2_j" ] \
  && ok "(j) a planted stray file CHANGES the tree hash — the containment checks discriminate" \
  || no "(j) tree_hash did not notice a new file; every containment assertion above is VACUOUS"
# And a content-only edit, with no new path, must be caught too.
printf 'edited\n' > "$r_j/src.txt"
h3_j="$(tree_hash "$r_j")"
[ "$h2_j" != "$h3_j" ] \
  && ok "(j) an in-place content edit also changes the tree hash" \
  || no "(j) tree_hash ignores content changes; the byte-identical assertions are VACUOUS"

# ============================================================================
echo "== (c) the developer's REAL .agent/ is untouched by this entire suite =="
REAL_AGENT_AFTER="$(tree_hash "$REAL_AGENT")"
[ "$REAL_AGENT_BEFORE" = "$REAL_AGENT_AFTER" ] \
  && ok "(c) the real repo's .agent/ is byte-identical before and after the suite" \
  || no "(c) THIS SUITE MODIFIED the real repo's .agent/ — write containment is broken"
[ "$REAL_STORE_ABSENT_BEFORE" -eq 1 ] \
  && ok "(c) precondition: the real repo carried no .agent/product.json before the run" \
  || no "(c) precondition FAILED: this repo already carries .agent/product.json (it must not — the store is created per project at runtime)"
[ ! -e "$REAL_AGENT/product.json" ] \
  && ok "(c) the real repo still carries no .agent/product.json" \
  || no "(c) the suite CREATED .agent/product.json in this repo"

echo
echo "RESULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
