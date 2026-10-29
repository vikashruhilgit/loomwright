# ============================================================================
echo "== (m) the 'gated' verdict class — a CORRECT refusal must NOT report as 'not configured' =="
# render_report sets intended_ok=no for any INTENDED path probing `ignored`, which yields
# `not configured`, whose remediation copy tells the user to comment out "the surviving exclude" —
# which for a withheld ledger is this module's OWN `.supervisor/*` line. Following that advice
# un-ignores the contaminated ledger, and commands/setup.md mandates relaying the copy VERBATIM. So a
# gated repo needs its own verdict AND its own copy; this group pins both.
if [ -z "$JQ" ]; then
  ok "(m) jq unavailable — the gated-verdict group is skipped (pass)"
else
  Mg="$(mkgate)"
  printf '{"repo":"otherhub/otherrepo","number":7}\n' >> "$Mg/$P_LEDGER"
  out_m="$(mem "$Mg" apply 2>&1)"; rc_m=$?
  [ "$rc_m" -eq 0 ] && ok "(m) apply exits 0 on the gated path" || no "(m) apply exited $rc_m on the gated path"
  has '^Memory readiness: gated' "$out_m" && ok "(m) the verdict is the THIRD class 'gated'" || no "(m) the verdict is not 'gated' (got: $(grep '^Memory readiness:' <<< "$out_m" | head -n1))"
  has '^Memory readiness: not configured' "$out_m" && no "(m) a CORRECT refusal reported as 'not configured' — the destructive mis-classification this class exists to prevent" || ok "(m) the refusal is NOT reported as 'not configured'"
  hasi 'comment out the rule named above' "$out_m" && no "(m) THE DESTRUCTIVE UNDER-INCLUSION COPY was printed for a gated repo — it points at this module's own '.supervisor/*' line" || ok "(m) the misleading under-inclusion copy is NOT printed on the gated path"
  hasF 'otherhub/otherrepo' "$out_m" && ok "(m) the gated warning NAMES the offending slug" || no "(m) the gated warning names no slug"
  hasF 'filter-ledger' "$out_m" && ok "(m) the gated warning gives the filter-ledger remedy" || no "(m) the gated warning omits the filter-ledger remedy"
  hasF 'repo_allowlist' "$out_m" && ok "(m) the gated warning also offers the extend-the-allowlist remedy" || no "(m) the gated warning omits the allowlist remedy"
  hasi 'does NOT un-track' "$out_m" && ok "(m) the gated warning states the honest limit: withholding does NOT un-track an already-committed ledger" || no "(m) the gated warning omits the already-committed honest limit"
  assert_committable "$Mg" "$P_MEM"    "(m) the two memory stores ARE applied on the gated path (gated is not 'nothing happened')"
  assert_ignored     "$Mg" "$P_LEDGER" "(m) the ledger stays ignored while gated"
  chk_m="$(mem "$Mg" check 2>&1)"
  has '^Memory readiness: gated' "$chk_m" && ok "(m) 'check' reports the gated verdict too (not just apply)" || no "(m) check did not report the gated verdict"
  # THE NO-OP HEADLINE. proposed_applied_content omits the ledger lines while gated, so current ==
  # proposed and do_apply reaches its no-op branch — which used to print the exact 'already
  # configured' copy the gated class exists to prevent, and setup.md mandates relaying it verbatim.
  out_m2="$(mem "$Mg" apply 2>&1)"
  has '^apply: no-op' "$out_m2" && ok "(m) the second apply on a gated repo is still a byte-compare no-op" || no "(m) the second apply on a gated repo was not a no-op"
  hasF 'apply: no-op — already configured' "$out_m2" && no "(m) the gated repo printed 'apply: no-op — already configured' — setup.md relays that headline VERBATIM, so it would state the opposite of the truth" || ok "(m) the gated no-op headline names the gated state instead of 'already configured'"
  hasF 'GATED' "$out_m2" && ok "(m) the gated no-op headline says the ledger is GATED and stays ignored" || no "(m) the gated no-op headline does not name the gated state"

  # THE WITHDRAWAL TRANSITION: applied cleanly, THEN contaminated. Correct fail-closed behaviour, but
  # it rewrites .gitignore and must be ANNOUNCED — never a bare `apply: applied`.
  Wd="$(mkgate)"
  mem "$Wd" apply >/dev/null 2>&1
  assert_committable "$Wd" "$P_LEDGER" "(m) precondition: the clean apply un-ignored the ledger"
  printf '{"schema_version": 1, "repo": "stranger/elsewhere", "number": 3}\n' >> "$Wd/$P_LEDGER"
  out_w="$(mem "$Wd" apply 2>&1)"; rc_w=$?
  [ "$rc_w" -eq 0 ] && ok "(m) the withdrawal re-apply exits 0" || no "(m) the withdrawal re-apply exited $rc_w"
  hasF 'WITHDRAWN' "$out_w" && ok "(m) the clean→contaminated re-apply ANNOUNCES the withdrawal" || no "(m) the withdrawal was silent"
  hasF 'stranger/elsewhere' "$out_w" && ok "(m) the withdrawal names WHICH slugs appeared since the last apply" || no "(m) the withdrawal does not name the new slugs"
  hasE '^apply: applied — managed block written' "$out_w" && no "(m) the withdrawal was reported under a BARE 'apply: applied' headline" || ok "(m) the headline itself is qualified — never a bare 'apply: applied'"
  hasi 'does not un-track' "$out_w" && ok "(m) the withdrawal states that it does NOT un-track an already-committed ledger" || no "(m) the withdrawal implies the ledger is unpublished — it is not"
  assert_ignored "$Wd" "$P_LEDGER" "(m) after the withdrawal the ledger is IGNORED again"
fi

# ============================================================================
echo "== (n) EMIT vs WITHDRAW are ASYMMETRIC — 'could not examine' must never withdraw a good negation =="
# THE ROOT CAUSE THIS GROUP PINS. The emission decision (`pass`) also governed whether an EXISTING
# negation survived the regenerated block, so "we could not determine the ledger's state" was treated
# identically to "we determined the ledger is contaminated". On a FRESH repo that is correct
# fail-closed behaviour (groups l4/l8/l9 pin it). On an ALREADY-APPLIED repo it silently WITHDREW a
# good negation and blamed foreign slugs that do not exist.
#
# Emitting a NEW negation still requires an affirmative examined `pass`. WITHDRAWING an existing one
# now requires an affirmative `refuse` backed by REAL, EXAMINED foreign slugs.
if [ -z "$JQ" ]; then
  ok "(n) jq unavailable — the emit/withdraw asymmetry group is skipped (pass)"
else
  # (n1) ALREADY APPLIED + jq ABSENT ⇒ the negation is PRESERVED. Same PATH-with-no-jq fixture shape
  # as (l4), but against a repo that ALREADY carries the negation — that is the whole difference.
  N1="$(mkgate)"
  mem "$N1" apply >/dev/null 2>&1
  assert_committable "$N1" "$P_LEDGER" "(n1) precondition: the clean apply un-ignored the ledger"
  out_n1="$(PATH="$L4BIN" bash "$MEM" --root "$N1" apply 2>&1)"; rc_n1=$?
  [ "$rc_n1" -eq 0 ] && ok "(n1) the jq-absent re-apply exits 0" || no "(n1) the jq-absent re-apply exited $rc_n1"
  assert_committable "$N1" "$P_LEDGER" "(n1) THE FIX: with jq ABSENT on an ALREADY-APPLIED repo the negation is PRESERVED — the ledger stays committable"
  hasF 'WITHDRAWN' "$out_n1" && no "(n1) a missing jq WITHDREW the negation — an unrequested state change on a diagnosis never made" || ok "(n1) the jq-absent re-apply does not announce a withdrawal"
  hasF 'records outside the allowlist' "$out_n1" && no "(n1) the jq-absent re-apply claimed FOREIGN RECORDS it never observed" || ok "(n1) no false contamination message when jq is absent"
  has '^Memory readiness: gated' "$out_n1" && no "(n1) a missing jq failed toward 'gated' on an applied repo" || ok "(n1) the verdict is not 'gated' when jq is merely absent"
  hasF 'PRESERVED' "$out_n1" && ok "(n1) the output says HONESTLY that the negation was PRESERVED, not re-verified" || no "(n1) the preservation is silent — the user cannot tell the gate did not run"

  # (n2) ALREADY APPLIED + jq PRESENT BUT BROKEN. `command -v jq` tests PRESENCE, NOT FUNCTION: a jq
  # that exits non-zero makes the whole-file pass AND every per-line probe fail, so a perfectly CLEAN
  # ledger was counted entirely unparseable and the gate REFUSED. Strictly worse than (n1) — it did
  # not merely withdraw, it printed "(unparseable record at ledger line 1)" as if it were a slug.
  N2="$(mkgate)"
  mem "$N2" apply >/dev/null 2>&1
  assert_committable "$N2" "$P_LEDGER" "(n2) precondition: the clean apply un-ignored the ledger"
  N2BIN="$N2/brokenbin"; mkdir -p "$N2BIN"
  for _c in bash sh git awk grep sed cut head tail tr cmp date cp mv rm mkdir rmdir dirname basename wc cat ls sort uniq find id chmod touch expr sleep env; do
    _p="$(command -v "$_c" 2>/dev/null)" && ln -sf "$_p" "$N2BIN/$_c"
  done
  printf '#!/bin/sh\nexit 127\n' > "$N2BIN/jq"; chmod +x "$N2BIN/jq"
  # META-CHECK, in a FRESH bash (this shell has jq hashed): the stub must be FOUND and must FAIL —
  # otherwise the branch below is not the one being driven.
  if PATH="$N2BIN" bash -c 'command -v jq' >/dev/null 2>&1 && ! PATH="$N2BIN" bash -c 'printf "{}" | jq -e . >/dev/null 2>&1'; then
    ok "(n2) the broken-jq fixture is genuinely PRESENT on PATH and genuinely NON-FUNCTIONAL (the branch is really driven)"
  else
    no "(n2) the broken-jq fixture is not present-and-broken — the assertions below would be vacuous"
  fi
  out_n2="$(PATH="$N2BIN" bash "$MEM" --root "$N2" apply 2>&1)"; rc_n2=$?
  [ "$rc_n2" -eq 0 ] && ok "(n2) the broken-jq re-apply exits 0" || no "(n2) the broken-jq re-apply exited $rc_n2"
  assert_committable "$N2" "$P_LEDGER" "(n2) THE FIX: a BROKEN jq on an ALREADY-APPLIED repo PRESERVES the negation — the ledger stays committable"
  hasF 'WITHDRAWN' "$out_n2" && no "(n2) a broken jq WITHDREW the negation on a perfectly CLEAN ledger" || ok "(n2) the broken-jq re-apply does not announce a withdrawal"
  hasF 'unparseable record' "$out_n2" && no "(n2) a broken jq reported '(unparseable record ...)' against a CLEAN ledger — contamination it never observed" || ok "(n2) no false 'unparseable record' claim when jq itself is what is broken"
  hasF 'records outside the allowlist' "$out_n2" && no "(n2) the broken-jq re-apply claimed FOREIGN RECORDS it never observed" || ok "(n2) no false contamination message when jq is broken"
  has '^Memory readiness: gated' "$out_n2" && no "(n2) a broken jq failed toward 'gated' on an applied repo with a clean ledger" || ok "(n2) the verdict is not 'gated' when jq itself is broken"

  # (n3) REGRESSION CONTROL — the asymmetry must not disarm the gate. A REAL foreign record on an
  # already-applied repo must STILL withdraw the negation and name the real slug.
  N3="$(mkgate)"
  mem "$N3" apply >/dev/null 2>&1
  assert_committable "$N3" "$P_LEDGER" "(n3) precondition: the clean apply un-ignored the ledger"
  printf '{"repo": "stranger/elsewhere", "number": 9}\n' >> "$N3/$P_LEDGER"
  out_n3="$(mem "$N3" apply 2>&1)"; rc_n3=$?
  [ "$rc_n3" -eq 0 ] && ok "(n3) the contaminated re-apply exits 0" || no "(n3) the contaminated re-apply exited $rc_n3"
  assert_ignored "$N3" "$P_LEDGER" "(n3) REGRESSION CONTROL: a REAL foreign record STILL WITHDRAWS the negation — the ledger is ignored again"
  hasF 'WITHDRAWN' "$out_n3" && ok "(n3) the real-contamination path still ANNOUNCES the withdrawal" || no "(n3) the real withdrawal went silent — the asymmetry disarmed the gate"
  hasF 'stranger/elsewhere' "$out_n3" && ok "(n3) the withdrawal names the REAL observed slug" || no "(n3) the withdrawal does not name the real slug"
fi

# ============================================================================
echo "== (o) remove is LEDGER-AWARE — the third store is counted, re-ignored and named =="
# `remove` gained a THIRD tracked-count and a three-path `git rm -r --cached` hint when the ledger
# became a managed store. Groups (l)/(m)/(n) only ever drive `apply`/`check`, and group (g) predates
# the ledger — so without this group the ledger half of do_remove() is unpinned: dropping
# $LEDGER_INTENDED_PATH from either the count or the hint would leave every other assertion green.
# The count is asserted against a ledger that is REALLY `git add`ed, because a count of 0 passes
# whether or not the code looks at the ledger at all.
if [ -z "$JQ" ]; then
  ok "(o) jq unavailable — the ledger-aware remove group is skipped (pass)"
else
  Oo="$(mkgate)"
  mem "$Oo" apply >/dev/null 2>&1
  assert_committable "$Oo" "$P_LEDGER" "(o) precondition: the clean apply un-ignored the ledger"
  # REALLY track it — this is what makes the count assertion non-vacuous.
  git -C "$Oo" add -- "$P_LEDGER" >/dev/null 2>&1
  n_tracked_o="$(git -C "$Oo" ls-files -- "$P_LEDGER" | wc -l | tr -d ' ')"
  [ "${n_tracked_o:-0}" -eq 1 ] && ok "(o) fixture precondition: the ledger is genuinely TRACKED (git ls-files = 1), so a 0 count cannot pass trivially" || no "(o) the ledger is not tracked in the fixture (got $n_tracked_o) — the count assertion below would be vacuous"
  out_o="$(mem "$Oo" remove 2>&1)"; rc_o=$?
  [ "$rc_o" -eq 0 ] && ok "(o) remove exits 0 on a ledger-applied repo" || no "(o) remove exited $rc_o on a ledger-applied repo"
  # EVERY TEXT ASSERTION BELOW IS SCOPED TO THE PRE-`== verify ==` HALF. do_remove() ends by calling
  # render_report, which prints its OWN "tracked today:" line naming all three stores — matching the
  # whole output would therefore stay green even with the ledger deleted from remove's own warning.
  # (Proven: mutating out only remove's ledger count left the unscoped form 294/0.)
  pre_o="${out_o%%== verify ==*}"
  [ "$pre_o" != "$out_o" ] && ok "(o) the remove-specific half of the output was isolated from the trailing verify report" || no "(o) could not split remove's own output from its '== verify ==' report — the text assertions below would not be remove-specific"
  # (o1) the THIRD tracked count is reported by REMOVE ITSELF, for the ledger path, non-zero.
  hasF "$P_LEDGER → 1 file(s)" "$pre_o" && ok "(o1) remove's own already-tracked warning reports the ledger count ($P_LEDGER → 1 file(s))" || no "(o1) remove's own warning does not report a tracked count for $P_LEDGER — the third store is invisible to the already-tracked warning"
  # (o2) the bare exclude is restored — asserted with a REAL git probe, never a .gitignore grep.
  # `--no-index` is REQUIRED here and is not a weakening: plain `git check-ignore` consults the index
  # and reports a TRACKED path as not-ignored regardless of the rules, which is exactly the
  # "already-tracked files stay tracked" fact this very output warns about. Without it the probe would
  # measure the fixture's `git add`, not the restored exclude. The untracked control below is probed
  # with the ordinary helper, so both forms are exercised.
  if git -C "$Oo" check-ignore -q --no-index -- "$P_LEDGER" >/dev/null 2>&1; then
    ok "(o2) after remove the ledger is IGNORED again by the rules (the negation is gone, future tracking stopped)"
  else
    no "(o2) after remove the ledger is still committable by the rules — the bare exclude was not restored"
  fi
  assert_ignored "$Oo" "$P_MEM"    "(o2) after remove the memory store is ignored again too"
  # (o3) the remediation copy names ALL THREE stores, not just the two memory ones.
  hasF "git rm -r --cached .claude/agent-memory .supervisor/memory $P_LEDGER" "$pre_o" && ok "(o3) the 'git rm -r --cached' hint names all THREE stores including the ledger" || no "(o3) the git rm hint omits the ledger — the user would leave the third store tracked"
  hasi 'All THREE stores are covered' "$pre_o" && ok "(o3) remove states that all THREE stores are covered by the managed block" || no "(o3) remove does not state that the third store is covered"
fi

# ============================================================================
# (p) ONE ALLOWLIST, TWO CONSUMERS.
#
# `setup-memory.sh`'s allowlist now has a SECOND consumer: validate-entry.sh's cross-repo write-time
# check, which asks this script for the list rather than parsing any layer itself. This group is the
# drift alarm for that arrangement — it moves the list ONCE and asserts BOTH behaviours move.
#
# WHY TWO PRECEDENCE LAYERS AND NOT ONE. Moving the list via $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST alone
# is satisfiable by a DUPLICATE PARSER inside validate-entry.sh: that env var is layer 2 of four, and
# a second parser reading it would agree here and diverge everywhere else. The live value in this
# repo comes from layer 3 (`.supervisor/config.json`), the layer a duplicate env parser cannot see at
# all — so the group asserts both, and layer 3 is asserted through a `--root` FIXTURE REPO whose
# config disagrees with its own git remote, which additionally proves the `--root` really reaches the
# resolver instead of the checked-out repo's own state.
#
# R0 — THE LIVE ALLOWLIST IS NEVER TOUCHED, AND NO FOREIGN SLUG EVER ENTERS IT. Adding a foreign slug
# to this repo's own allowlist would make `apply` judge foreign ledger records clean and EMIT the
# negation that un-ignores .supervisor/postmortem/results.jsonl — publishing another repo's churn
# analysis from this PUBLIC repo. Every fixture below is either a per-invocation env var or a
# `--root` temp repo, and the tail of the group re-checks the live config byte-for-byte.
# ============================================================================
echo "== (p) AC5 — ONE allowlist, TWO consumers: the cross-repo check and the ledger filter =="
# $TEST_SETUP_MEMORY_VALIDATE_ENTRY exists so this group's MUTATION CONTROL is reproducible by hand
# rather than asserted in prose. Point it at a mutated copy of validate-entry.sh and re-run:
#   · a copy whose allowlist loader DROPS the `--root` forwarding, or
#   · a copy that parses $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST itself instead of delegating
# both leave every (p/L2) assertion GREEN and turn the (p/L3) ones RED — which is the entire reason
# this group asserts two precedence layers instead of the one the env var reaches.
VE="${TEST_SETUP_MEMORY_VALIDATE_ENTRY:-$HERE/validate-entry.sh}"
CFG_LIVE="$PLUGIN_REPO/.supervisor/config.json"
CFG_LIVE_SUM_BEFORE="$(sum "$CFG_LIVE")"
CFG_LIVE_EXISTED=0; [ -f "$CFG_LIVE" ] && CFG_LIVE_EXISTED=1

# consumer A — the cross-repo write-time check. Echoes its VERDICT ON THE SLUG: 1 = this entry cites
# a repository outside the resolved allowlist, 0 = it does not.
#
# THAT VERDICT IS READ OFF THE REPORT, NOT OFF THE EXIT STATUS, and the difference is the point of
# this helper rather than an implementation detail. cross-repo is now an ADVISORY check: it reports
# on stderr and returns 0 on every path (validate-entry.sh's header records the six measured rounds
# of false refusals that bought that). Its exit status therefore no longer distinguishes anything,
# and a status-based helper here would have returned 0 for every entry and silently turned this
# whole group — the AC5 "one list, two consumers" parity proof — into assertions that can only pass.
# What the group actually needs is unchanged and still observable: whether the ONE resolved list
# moved BOTH consumers. So consumer A's answer is now "did it name this slug as foreign", which is
# the same question the exit status used to answer, asked of the surface that still answers it.
# VALIDATE_ENTRY_SETUP_MEMORY pins the ONE resolver to the script under test, so a stray
# CLAUDE_PLUGIN_ROOT in the developer's environment cannot point this at a different setup-memory.sh.
xrepo() {   # <entry-text> [--root <dir>]
  local e="$1"; shift
  local err; err="$(VALIDATE_ENTRY_SETUP_MEMORY="$MEM" bash "$VE" cross-repo --entry "$e" "$@" 2>&1 >/dev/null)"
  case "$err" in *"ADVISORY_CROSS_REPO"*) echo 1 ;; *) echo 0 ;; esac
}

# xrepo_noenv — the same, with $LOOMWRIGHT_MEMORY_REPO_ALLOWLIST SCRUBBED from the child environment
# so precedence layer 3 is genuinely reached. The scrub lives INSIDE the helper on purpose: `env` can
# only exec an external command, so an `env -u … xrepo …` call site would fail to find the shell
# FUNCTION, yield an EMPTY verdict, and every `[ "$v" = "0" ]` written against it would compare
# against "" — a whole group of assertions that can never pass and never say why.
xrepo_noenv() {   # <entry-text> [--root <dir>]
  local e="$1"; shift
  local err; err="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST VALIDATE_ENTRY_SETUP_MEMORY="$MEM" \
    bash "$VE" cross-repo --entry "$e" "$@" 2>&1 >/dev/null)"
  case "$err" in *"ADVISORY_CROSS_REPO"*) echo 1 ;; *) echo 0 ;; esac
}

one_allowlist_two_consumers() {
  if [ -z "$JQ" ]; then
    ok "(p) jq unavailable — the one-allowlist/two-consumers group is skipped (pass)"
    return 0
  fi
  if [ ! -f "$VE" ]; then
    no "(p) validate-entry.sh is missing at $VE — the second consumer does not exist, so AC5 cannot be discharged"
    return 0
  fi

  local d led v_alpha v_beta v_remote out n
  local E_ALPHA="the fixture-org/alpha rollout is recorded in this entry"
  local E_BETA="the fixture-org/beta rollout is recorded in this entry"
  local E_REMOTE="the acme/widget repo rollout is recorded in this entry"

  d="$(newgit https://github.com/acme/widget.git)"
  led="$d/ledger.jsonl"
  cat > "$led" <<'LEDGER'
{"repo":"fixture-org/alpha","number":1,"review_rounds":2}
{"repo":"fixture-org/beta","number":2,"review_rounds":5}
LEDGER

  # ---------------------------------------------------------------------------
  # LAYER 2 — the process-global env var. It reaches both consumers with NO root override, and
  # touches no file, so both calls below are deliberately made WITHOUT --root.
  # ---------------------------------------------------------------------------
  v_alpha="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/alpha" xrepo "$E_ALPHA")"
  v_beta="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/alpha" xrepo "$E_BETA")"
  [ "$v_alpha" = "0" ] && ok "(p/L2) consumer A: an entry citing the ALLOWLISTED slug PASSES (verdict 0)" || no "(p/L2) consumer A reported an allowlisted slug as foreign (verdict $v_alpha)"
  [ "$v_beta" = "1" ] && ok "(p/L2) consumer A: an entry citing a slug OUTSIDE the list is REPORTED as foreign (verdict 1)" || no "(p/L2) consumer A verdict on a foreign slug was $v_beta, expected 1"
  out="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/alpha" bash "$MEM" filter-ledger --ledger "$led" 2>/dev/null)"
  n="$(ledger_count "$out")"
  [ "$n" = "1" ] && ok "(p/L2) consumer B: the ledger filter retains 1 of 2 records under the same list" || no "(p/L2) consumer B retained $n records, expected 1"
  ledger_has_repo "$out" "fixture-org/alpha" && ok "(p/L2) consumer B kept the allowlisted record" || no "(p/L2) consumer B dropped the allowlisted record"
  ledger_has_repo "$out" "fixture-org/beta" && no "(p/L2) consumer B leaked the non-allowlisted record" || ok "(p/L2) consumer B excluded the non-allowlisted record"

  # MOVE THE LIST ONCE — both behaviours must move together.
  v_alpha="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/beta" xrepo "$E_ALPHA")"
  v_beta="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/beta" xrepo "$E_BETA")"
  [ "$v_beta" = "0" ] && ok "(p/L2) THE LIST MOVED: consumer A now passes the slug it reported a moment ago" || no "(p/L2) consumer A did not follow the moved list (verdict $v_beta on the newly-allowed slug)"
  [ "$v_alpha" = "1" ] && ok "(p/L2) THE LIST MOVED: consumer A now REPORTS the slug it passed a moment ago" || no "(p/L2) consumer A still passed the now-foreign slug (verdict $v_alpha)"
  out="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/beta" bash "$MEM" filter-ledger --ledger "$led" 2>/dev/null)"
  ledger_has_repo "$out" "fixture-org/beta" && ok "(p/L2) THE LIST MOVED: consumer B now retains the record it dropped a moment ago" || no "(p/L2) consumer B did not follow the moved list"
  ledger_has_repo "$out" "fixture-org/alpha" && no "(p/L2) consumer B still retains the now-foreign record — the two consumers have diverged" || ok "(p/L2) THE LIST MOVED: consumer B now drops the record it kept a moment ago — ONE list, BOTH consumers"

  # ---------------------------------------------------------------------------
  # LAYER 3 — .supervisor/config.json inside a --root FIXTURE REPO. This is the layer the live value
  # actually comes from, and the one an env-var-only parser is blind to. `env -u` is load-bearing:
  # layer 2 outranks layer 3, so a developer with the variable exported would otherwise never reach
  # the config at all and this half would silently re-test layer 2.
  # ---------------------------------------------------------------------------
  mkdir -p "$d/.supervisor" || setup_fail "(p) could not create the fixture .supervisor dir"
  printf '{"setup_memory":{"repo_allowlist":["fixture-org/alpha"]}}\n' > "$d/.supervisor/config.json"
  # PRECONDITION: the config must genuinely BEAT the fixture's own git remote, or the assertions
  # below would be satisfied by layer 4 and would prove nothing about layer 3.
  out="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$MEM" --root "$d" allowlist 2>/dev/null)"
  if [ "$out" = "fixture-org/alpha" ]; then
    ok "(p/L3) PRECONDITION: the fixture's config allowlist BEATS its own git remote (acme/widget) — layer 3 is genuinely what resolves"
  else
    no "(p/L3) the fixture did not resolve to its config value (got: $out) — the layer-3 assertions below would be testing layer 4"
  fi
  v_alpha="$(xrepo_noenv "$E_ALPHA" --root "$d")"
  v_beta="$(xrepo_noenv "$E_BETA" --root "$d")"
  v_remote="$(xrepo_noenv "$E_REMOTE" --root "$d")"
  [ "$v_alpha" = "0" ] && ok "(p/L3) consumer A reads the FIXTURE REPO's config through --root: the config-listed slug PASSES" || no "(p/L3) consumer A did not see the fixture config (verdict $v_alpha on the config-listed slug) — --root is not reaching the resolver"
  [ "$v_beta" = "1" ] && ok "(p/L3) consumer A REPORTS a slug absent from the fixture config" || no "(p/L3) consumer A verdict $v_beta on a slug outside the fixture config, expected 1"
  # The sharpest --root assertion: the fixture's OWN REMOTE is refused, so consumer A is reading the
  # config layer and not falling back to a remote (its own, or this checkout's).
  [ "$v_remote" = "1" ] && ok "(p/L3) consumer A REPORTS the fixture's own git-remote slug — proof it read the config layer, not the remote default" || no "(p/L3) consumer A passed the fixture's remote slug (verdict $v_remote) — it is resolving layer 4, not the config"
  out="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$MEM" --root "$d" filter-ledger --ledger "$led" 2>/dev/null)"
  ledger_has_repo "$out" "fixture-org/alpha" && ok "(p/L3) consumer B reads the same config layer and keeps the config-listed record" || no "(p/L3) consumer B did not follow the config layer"
  ledger_has_repo "$out" "fixture-org/beta" && no "(p/L3) consumer B leaked a record outside the config allowlist" || ok "(p/L3) consumer B excludes the record outside the config allowlist"

  # MOVE THE CONFIG LIST ONCE — both behaviours must move together at layer 3 too.
  printf '{"setup_memory":{"repo_allowlist":["fixture-org/beta"]}}\n' > "$d/.supervisor/config.json"
  v_alpha="$(xrepo_noenv "$E_ALPHA" --root "$d")"
  v_beta="$(xrepo_noenv "$E_BETA" --root "$d")"
  [ "$v_beta" = "0" ] && ok "(p/L3) THE CONFIG LIST MOVED: consumer A now passes the slug it reported" || no "(p/L3) consumer A did not follow the moved config list (verdict $v_beta)"
  [ "$v_alpha" = "1" ] && ok "(p/L3) THE CONFIG LIST MOVED: consumer A now REPORTS the slug it passed" || no "(p/L3) consumer A still passed the now-foreign slug (verdict $v_alpha)"
  out="$(env -u LOOMWRIGHT_MEMORY_REPO_ALLOWLIST bash "$MEM" --root "$d" filter-ledger --ledger "$led" 2>/dev/null)"
  ledger_has_repo "$out" "fixture-org/beta" && ok "(p/L3) THE CONFIG LIST MOVED: consumer B now retains the record it dropped" || no "(p/L3) consumer B did not follow the moved config list"
  ledger_has_repo "$out" "fixture-org/alpha" && no "(p/L3) consumer B still retains the now-foreign record at layer 3 — the two consumers have diverged on the layer an env-var parser cannot see" || ok "(p/L3) THE CONFIG LIST MOVED: consumer B drops it too — ONE list, BOTH consumers, on the layer a duplicate env parser is blind to"

  # THE SCRUB ITSELF, PINNED. Every layer-3 assertion above is only about layer 3 if the env var
  # really was removed from the child. Prove it directly: EXPORT a contradicting layer-2 value and
  # show the fixture's config (now `fixture-org/beta`) still decides the verdict.
  local v_scrub
  v_scrub="$(LOOMWRIGHT_MEMORY_REPO_ALLOWLIST="fixture-org/alpha" xrepo_noenv "$E_ALPHA" --root "$d")"
  [ "$v_scrub" = "1" ] && ok "(p/L3) the env-var scrub is real: an EXPORTED layer-2 value does not reach the child, so the fixture's config still decides — the layer-3 assertions above are about layer 3" || no "(p/L3) an exported layer-2 value leaked into the child (verdict $v_scrub) — the layer-3 assertions above were silently re-testing layer 2"

  # ---------------------------------------------------------------------------
  # NEGATIVE CONTROL — the shipped PUBLICATION GATE is not weakened by any of the above. With a
  # FOREIGN record in the ledger, `apply` in a --root fixture repo must still WITHHOLD the ledger
  # negation and NAME the offending slug. This is the property R0 exists to protect.
  # ---------------------------------------------------------------------------
  local g out_g
  g="$(mkgate)"
  mem "$g" apply >/dev/null 2>&1
  assert_committable "$g" "$P_LEDGER" "(p/neg) precondition: the fixture's ledger is committable while clean, so the withholding below is a real state change"
  printf '{"schema_version": 1, "repo": "otherhub/otherrepo", "number": 124}\n' >> "$g/$P_LEDGER"
  out_g="$(mem "$g" apply 2>&1)"
  assert_ignored "$g" "$P_LEDGER" "(p/neg) with a FOREIGN record present, apply still WITHHOLDS the ledger negation — the publication gate is intact"
  hasF 'otherhub/otherrepo' "$out_g" && ok "(p/neg) the withholding NAMES the offending slug" || no "(p/neg) the refusal does not name the offending slug"
  assert_committable "$g" "$P_MEM" "(p/neg) and only the ledger is withheld — the memory stores stay applied"
}
one_allowlist_two_consumers

# R0, re-checked mechanically rather than asserted in prose.
if [ "$CFG_LIVE_EXISTED" -eq 1 ]; then
  [ "$(sum "$CFG_LIVE")" = "$CFG_LIVE_SUM_BEFORE" ] && ok "(p) R0: the plugin repo's own .supervisor/config.json is BYTE-IDENTICAL after the group" || no "(p) R0 VIOLATED: THE SUITE MUTATED THE LIVE .supervisor/config.json"
else
  [ ! -f "$CFG_LIVE" ] && ok "(p) R0: the plugin repo had no .supervisor/config.json before the group and still has none" || no "(p) R0 VIOLATED: the suite CREATED a live .supervisor/config.json"
fi
if [ -f "$CFG_LIVE" ] && grep -qE 'otherhub|fixture-org' "$CFG_LIVE" 2>/dev/null; then
  no "(p) R0 VIOLATED: a FOREIGN fixture slug reached the live allowlist — apply would now publish another repo's churn analysis"
else
  ok "(p) R0: no foreign fixture slug (otherhub / fixture-org) is present in the live allowlist"
fi

# ============================================================================
echo "== (t) the judgement TRAIL (v15.84.0): requirements + jobs/done|failed + automate/*.md are committable; in-flight, sidecars and nested .supervisor/ stay ignored =="
# WHY: 2026-09-21 — 144 requirement files, 116 done briefs and every /automate run file existed on
# exactly one laptop, while the repo's stated thesis is a Twin that ACCUMULATES judgement. The
# block gains the trail; this group pins each path both ways and proves the `!` lines are dead
# without the `.supervisor/*` line above them (the same silent-failure class as group (a)).
P_REQ=".supervisor/requirements/queue/01-item.md"
P_REQ_NESTED=".supervisor/requirements/queue/.supervisor/logs/telemetry.log"
P_SUB_NESTED="probes/.supervisor/.rules-nudge-shown"
P_DONE=".supervisor/jobs/done/2026-01-01-brief.md"
P_FAILED=".supervisor/jobs/failed/2026-01-01-brief.md"
P_INPROG=".supervisor/jobs/in-progress/2026-01-01-brief.md"
P_PENDING=".supervisor/jobs/pending/2026-01-01-brief.md"
P_RUN=".supervisor/automate/automate-2026-01-01-000000.md"
P_RUN_SIDECAR=".supervisor/automate/automate-2026-01-01-000000.config-backup.json"
Tt="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Tt"
printf '.supervisor/\n' > "$Tt/.gitignore"
out_t="$(mem "$Tt" apply 2>&1)"; rc_t=$?
[ "$rc_t" -eq 0 ] && ok "(t) apply exits 0" || no "(t) apply non-zero ($rc_t): $out_t"
# INTENDED — one assertion per path.
assert_committable "$Tt" "$P_REQ"    "(t) after apply $P_REQ is committable"
assert_committable "$Tt" ".supervisor/requirements/queue/operator-run/08-item.md" "(t) a requirement in a nested subfolder is committable (directory re-include is recursive)"
assert_committable "$Tt" "$P_DONE"   "(t) after apply $P_DONE is committable"
assert_committable "$Tt" "$P_FAILED" "(t) after apply $P_FAILED is committable"
assert_committable "$Tt" "$P_RUN"    "(t) after apply $P_RUN is committable"
# UNINTENDED — one assertion per path, never a bulk claim.
assert_ignored "$Tt" "$P_INPROG"      "(t) $P_INPROG stays ignored (in-flight state)"
assert_ignored "$Tt" "$P_PENDING"     "(t) $P_PENDING stays ignored (in-flight state)"
assert_ignored "$Tt" "$P_RUN_SIDECAR" "(t) $P_RUN_SIDECAR stays ignored (transient sidecar)"
assert_ignored "$Tt" "$P_REQ_NESTED"  "(t) $P_REQ_NESTED stays ignored (hook junk nested in a requirements folder)"
assert_ignored "$Tt" "$P_SUB_NESTED"  "(t) $P_SUB_NESTED stays ignored (hook junk nested in an arbitrary project subfolder)"
assert_ignored "$Tt" "a/b/.supervisor/logs/x.jsonl" "(t) a .supervisor/ nested two levels below an ordinary folder stays ignored"
# The nested rule must not reach the ROOT store: it stays committable (the reason `*/**/` and not `**/`).
assert_committable "$Tt" ".supervisor/memory/LESSONS.md" "(t) the ROOT store .supervisor/memory/LESSONS.md stays committable under the nested rule"
assert_ignored "$Tt" ".supervisor/state.md" "(t) .supervisor/state.md stays ignored (live run state)"
assert_ignored "$Tt" "$P_LOGS"        "(t) $P_LOGS stays ignored"
# The probes in the script itself must agree with these assertions, or `check` would report a
# configured repo as partial/not-configured.
chk_t="$(mem "$Tt" check 2>/dev/null)"
has '^Memory readiness: configured' "$chk_t" && ok "(t) check verdict = configured with the trail lines in place" || no "(t) check verdict after trail apply: $(grep '^Memory readiness' <<< "$chk_t")"
# Negative control 1: the `!` lines are DEAD without `.supervisor/*` above them.
Tn="$(newgit)"; seed_stores "$Tn"
printf '.supervisor/\n!.supervisor/requirements/\n!.supervisor/jobs/\n.supervisor/jobs/*\n!.supervisor/jobs/done/\n' > "$Tn/.gitignore"
assert_ignored "$Tn" "$P_REQ"  "(t-neg1) bare '.supervisor/' + '!.supervisor/requirements/' STILL ignores $P_REQ — the negation is dead, as the block comment claims"
assert_ignored "$Tn" "$P_DONE" "(t-neg1) same for $P_DONE"
# Negative control 2 (mutant): drop the nested-.supervisor exclude from the block ⇒ the junk
# becomes committable — proving (t)'s nested assertion holds the line, not the seed layout.
Tm="$(mkfix)"; sed '/^\*\/\*\*\/\.supervisor\/$/d' "$MEMB" > "$Tm/setup-memory.sh"
cp "$HERE/contained-path-lib.sh" "$Tm/" || setup_fail "(t-mut) could not place contained-path-lib.sh beside the mutant (apply loads it from the entry's dir)"
if cmp -s "$MEMB" "$Tm/setup-memory.sh"; then no "(t-mut) mutant sed changed nothing"; else
  Tx="$(newgit https://github.com/acme/widget.git)"; seed_stores "$Tx"; printf '.supervisor/\n' > "$Tx/.gitignore"
  bash "$Tm/setup-memory.sh" --root "$Tx" apply >/dev/null 2>&1
  if ignored "$Tx" "$P_REQ_NESTED"; then no "(t-mut) mutant without the nested exclude still ignores $P_REQ_NESTED — the assertion is vacuous"; else ok "(t-mut) without the nested exclude line the hook junk WOULD be committed — the line is load-bearing"; fi
  if ignored "$Tx" "$P_SUB_NESTED"; then no "(t-mut) mutant without the nested exclude still ignores $P_SUB_NESTED — the assertion is vacuous"; else ok "(t-mut) without the nested exclude line $P_SUB_NESTED WOULD be committed (the studio exposure)"; fi
fi

