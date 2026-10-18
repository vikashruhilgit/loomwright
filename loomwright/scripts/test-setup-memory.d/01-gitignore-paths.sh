# ============================================================================
echo "== 0. script under test exists =="
[ -f "$MEM" ] && ok "setup-memory.sh present" || no "setup-memory.sh missing at $MEM"
if [ ! -f "$MEM" ]; then echo; echo "RESULT: $pass passed, $fail failed"; exit 1; fi

# ============================================================================
echo "== (a) the NAIVE negation is proven to FAIL; the /* form is proven to WORK =="
# This is the whole reason the module exists: `.claude/` excludes the DIRECTORY, so git never
# descends into it and NO later `!` line can re-include anything below it. The failure is
# asserted here, not described in a comment.
Na="$(newgit)"
seed_stores "$Na"
printf '.claude/\n!.claude/agent-memory/\n.supervisor/\n!.supervisor/memory/\n' > "$Na/.gitignore"
assert_ignored "$Na" "$P_MEM"     "(a1) NAIVE '.claude/' + '!.claude/agent-memory/' STILL ignores $P_MEM — the negation silently fails, as claimed"
assert_ignored "$Na" "$P_LES"     "(a1) NAIVE '.supervisor/' + '!.supervisor/memory/' STILL ignores $P_LES — same silent failure"
assert_ignored "$Na" "$P_MEM_DOT" "(a1) NAIVE form also still ignores the dotfile sidecar $P_MEM_DOT"

# Same fixture, rewritten to the working form → committable.
printf '.claude/*\n!.claude/agent-memory/\n.supervisor/*\n!.supervisor/memory/\n' > "$Na/.gitignore"
assert_committable "$Na" "$P_MEM" "(a2) WORKING '.claude/*' + '!.claude/agent-memory/' makes $P_MEM committable"
assert_committable "$Na" "$P_LES" "(a2) WORKING '.supervisor/*' + '!.supervisor/memory/' makes $P_LES committable"
assert_ignored "$Na" "$P_WT"    "(a3) WORKING form leaves $P_WT ignored"
assert_ignored "$Na" "$P_LOCAL" "(a3) WORKING form leaves $P_LOCAL ignored"
assert_ignored "$Na" "$P_LOGS"  "(a3) WORKING form leaves $P_LOGS ignored"

# ============================================================================
echo "== (b) apply on a repo carrying the naive bare excludes → per-path ignore status flips correctly =="
Ab="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Ab"
# The realistic starting point: the plugin's own historical form — bare directory excludes.
printf '# editor\n*.swp\n\n# runtime\n.claude/\n.supervisor/\nlogs/\n' > "$Ab/.gitignore"
assert_ignored "$Ab" "$P_MEM" "(b) precondition: $P_MEM ignored before apply"
out_b="$(mem "$Ab" apply 2>&1)"; rc_b=$?
[ "$rc_b" -eq 0 ] && ok "(b) apply exits 0" || no "(b) apply non-zero ($rc_b)"
has '^apply: applied' "$out_b" && ok "(b) apply reports 'applied'" || no "(b) apply did not report 'applied'"
# INTENDED — one assertion per path.
assert_committable "$Ab" "$P_MEM" "(b) after apply $P_MEM is committable"
assert_committable "$Ab" "$P_LES" "(b) after apply $P_LES is committable"
# A deeper nested file must also survive (the re-included directory is traversable all the way down).
assert_committable "$Ab" ".claude/agent-memory/loomwright-loomwright-worker/notes/deep.md" "(b) after apply a DEEPLY nested agent-memory file is committable"
# UNINTENDED — one assertion per path, never a bulk claim.
assert_ignored "$Ab" "$P_WT"    "(b) after apply $P_WT stays ignored"
assert_ignored "$Ab" "$P_LOCAL" "(b) after apply $P_LOCAL stays ignored"
assert_ignored "$Ab" "$P_LOGS"  "(b) after apply $P_LOGS stays ignored"
# The bare excludes must be NEUTRALISED, not merely out-ordered (a surviving `.claude/` line
# anywhere defeats the whole block).
gi_b="$(cat "$Ab/.gitignore")"
hasE '^[[:space:]]*\.claude/[[:space:]]*$' "$gi_b" && no "(b) a live bare '.claude/' line survived apply — the negation would be dead" || ok "(b) no live bare '.claude/' line survives apply"
hasE '^[[:space:]]*\.supervisor/[[:space:]]*$' "$gi_b" && no "(b) a live bare '.supervisor/' line survived apply" || ok "(b) no live bare '.supervisor/' line survives apply"
hasE '^\*\.swp$' "$gi_b" && ok "(b) unrelated user rule '*.swp' preserved verbatim" || no "(b) apply dropped an unrelated user rule"
chk_b="$(mem "$Ab" check 2>/dev/null)"
has '^Memory readiness: configured' "$chk_b" && ok "(b) check verdict = configured after apply" || no "(b) check verdict not 'configured' after apply"

# ============================================================================
echo "== (b2) the RECURSIVE '.claude/**' family is neutralised too, and a survivor is not sold as success =="
# `.claude/**` matches every path BELOW the directory and git applies the LAST matching rule, so
# it still beats the block's `!.claude/agent-memory/` (which is directory-only and never matches
# the files inside). A survivor left the negation silently dead under an `apply: applied` headline.
Bx="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Bx"
printf '# editor\n*.swp\n.claude/**\n.supervisor/**\n**/.claude/\n' > "$Bx/.gitignore"
assert_ignored "$Bx" "$P_MEM" "(b2) precondition: '.claude/**' ignores $P_MEM before apply"
out_bx="$(mem "$Bx" apply 2>&1)"; rc_bx=$?
[ "$rc_bx" -eq 0 ] && ok "(b2) apply exits 0 on a '**'-family .gitignore" || no "(b2) apply non-zero ($rc_bx)"
assert_committable "$Bx" "$P_MEM"     "(b2) a pre-existing '.claude/**' no longer defeats the negation"
assert_committable "$Bx" "$P_LES"     "(b2) a pre-existing '.supervisor/**' no longer defeats the negation"
assert_committable "$Bx" "$P_MEM_DOT" "(b2) the dotfile sidecar survives the '**' family too"
assert_ignored "$Bx" "$P_WT"    "(b2) $P_WT still ignored"
assert_ignored "$Bx" "$P_LOGS"  "(b2) $P_LOGS still ignored"
gi_bx="$(cat "$Bx/.gitignore")"
hasE '^[[:space:]]*\.claude/\*\*[[:space:]]*$'     "$gi_bx" && no "(b2) a live '.claude/**' survived apply"     || ok "(b2) '.claude/**' was neutralised"
hasE '^[[:space:]]*\.supervisor/\*\*[[:space:]]*$' "$gi_bx" && no "(b2) a live '.supervisor/**' survived apply" || ok "(b2) '.supervisor/**' was neutralised"
hasE '^[[:space:]]*\*\*/\.claude/[[:space:]]*$'    "$gi_bx" && no "(b2) a live '**/.claude/' survived apply"    || ok "(b2) '**/.claude/' was neutralised"
hasE '^\*\.swp$' "$gi_bx" && ok "(b2) unrelated user rule '*.swp' preserved verbatim" || no "(b2) apply dropped an unrelated user rule"
hasF 'apply: WARNING' "$out_bx" && no "(b2) apply warned even though the negation DID take effect" || ok "(b2) no spurious warning when readiness is 'configured'"
# remove must still round-trip the newly-recognised forms
orig_bx="$(mkfix)/orig.gitignore"; printf '# editor\n*.swp\n.claude/**\n.supervisor/**\n**/.claude/\n' > "$orig_bx"
mem "$Bx" remove >/dev/null 2>&1
if cmp -s "$orig_bx" "$Bx/.gitignore"; then ok "(b2) apply → remove restores the '**'-family .gitignore BYTE-EXACTLY"; else no "(b2) the '**' family did not round-trip through remove"; fi

# A survivor this rewriter does NOT recognise (a deeper `.claude/agent-memory/**`) must be
# reported, not papered over: the headline is qualified and the WINNING pattern is named from a
# real `git check-ignore -v` probe, never guessed.
By="$(newgit https://github.com/acme/widget.git)"
seed_stores "$By"
printf '.claude/\n.claude/agent-memory/**\n' > "$By/.gitignore"
out_by="$(mem "$By" apply 2>&1)"; rc_by=$?
[ "$rc_by" -eq 0 ] && ok "(b2) apply still exits 0 with an unrecognised surviving exclude" || no "(b2) non-zero ($rc_by)"
hasF 'apply: WARNING' "$out_by" && ok "(b2) apply WARNS when the post-write verdict is not 'configured' (no unqualified success)" || no "(b2) apply reported plain success while an intended path stayed ignored"
hasF 'STILL IGNORED' "$out_by" && ok "(b2) the warning says which intended paths are still ignored" || no "(b2) the warning does not flag the still-ignored intended paths"
hasF '.claude/agent-memory/**' "$out_by" && ok "(b2) the warning NAMES the surviving pattern (from git check-ignore -v, not a guess)" || no "(b2) the warning does not name the surviving pattern"

# ============================================================================
echo "== (b3) a user's PRE-EXISTING working '.claude/*' form SURVIVES apply UNCOMMENTED =="
# `X/*` is the one directory-shaped form deliberately absent from comment_bare_excludes' list. Not
# because commenting it could neutralise the module's own fix — it cannot, since
# proposed_applied_content pipes only the STRIPPED pre-existing file through the neutraliser and
# appends the managed block AFTERWARDS — but because `X/*` is not an obstacle at all: it excludes
# the CONTENTS and leaves the directory traversable, which is exactly what the `!` lines need. A
# user who already wrote it is already correct, so neutralising it would be pointless churn (and
# `remove` would then have to restore it). A comment is not a test; this fixture is the pin.
Bz="$(newgit https://github.com/acme/widget.git)"
seed_stores "$Bz"
printf '# editor\n*.swp\n.claude/*\n!.claude/agent-memory/\n.supervisor/\n' > "$Bz/.gitignore"
orig_bz="$(mkfix)/orig.gitignore"; cp "$Bz/.gitignore" "$orig_bz"
out_bz="$(mem "$Bz" apply 2>&1)"; rc_bz=$?
[ "$rc_bz" -eq 0 ] && ok "(b3) apply exits 0 on a .gitignore that already carries the working '.claude/*' form" || no "(b3) apply non-zero ($rc_bz)"
gi_bz="$(cat "$Bz/.gitignore")"
hasE '^# \.claude/\*[[:space:]]' "$gi_bz" && no "(b3) apply COMMENTED OUT the user's pre-existing '.claude/*' — the WORKING form must never be neutralised" || ok "(b3) the user's pre-existing '.claude/*' survives apply UNCOMMENTED"
n_live_bz="$(grep -cE '^\.claude/\*$' <<< "$gi_bz" | tr -d ' ')"
[ "${n_live_bz:-0}" -eq 2 ] && ok "(b3) BOTH live '.claude/*' lines remain (the user's own + the managed block's)" || no "(b3) expected 2 live '.claude/*' lines, found ${n_live_bz:-0} — the user's copy was neutralised"
hasE '^# \.supervisor/[[:space:]]' "$gi_bz" && ok "(b3) the BARE '.supervisor/' in the same file is still neutralised (only the working form is exempt)" || no "(b3) the bare '.supervisor/' was not neutralised"
assert_committable "$Bz" "$P_MEM" "(b3) $P_MEM is committable with a pre-existing working form in place"
assert_ignored "$Bz" "$P_LOGS" "(b3) $P_LOGS still ignored"
mem "$Bz" remove >/dev/null 2>&1
if cmp -s "$orig_bz" "$Bz/.gitignore"; then ok "(b3) apply → remove round-trips a .gitignore carrying the working form BYTE-EXACTLY"; else no "(b3) the pre-existing working form did not round-trip through remove"; fi

# ============================================================================
echo "== (b4) the 'partial' verdict (OVER-inclusion) gets its OWN remediation copy =="
# `partial` fires when an UNINTENDED path becomes COMMITTABLE — the OPPOSITE of (b2)'s surviving
# exclude. Until this fixture existed the branch was entirely undriven, and warn_if_not_configured()
# fell through to the UNDER-inclusion copy: with REPORT_BLOCKED_INTENDED empty it named NOTHING and
# then told the user to "comment out the rule named above" — backwards advice whose remedy (deleting
# an exclude) would leak MORE.
#
# The driver is a NESTED .gitignore, which is the realistic shape: patterns in `.claude/.gitignore`
# take PRECEDENCE over the root file, so an over-broad `!` there survives the appended managed block
# (whose own `.claude/*` would otherwise re-ignore anything a root-level `!` re-included).
B4="$(newgit https://github.com/acme/widget.git)"
seed_stores "$B4"
printf '.claude/\n.supervisor/\n' > "$B4/.gitignore"
printf '!settings.local.json\n!worktrees/\n' > "$B4/.claude/.gitignore"
out_b4="$(mem "$B4" apply 2>&1)"; rc_b4=$?
[ "$rc_b4" -eq 0 ] && ok "(b4) apply exits 0 on an over-including .gitignore (fail-safe)" || no "(b4) apply non-zero ($rc_b4)"
# The verdict really is `partial` — the branch is genuinely driven, not assumed.
has '^Memory readiness: partial' "$out_b4" && ok "(b4) the verdict really IS 'partial' (the branch is driven by a real fixture)" || no "(b4) fixture did not produce a 'partial' verdict (got: $(grep '^Memory readiness:' <<< "$out_b4" | head -n1))"
# ...for the right reason: intended paths fine, unintended leaking.
assert_committable "$B4" "$P_MEM"   "(b4) precondition: the intended $P_MEM is committable (so this is NOT under-inclusion)"
assert_committable "$B4" "$P_LOCAL" "(b4) precondition: the unintended $P_LOCAL LEAKED (committable) — the over-inclusion this branch is about"
hasF 'apply: WARNING' "$out_b4" && ok "(b4) apply WARNS on a 'partial' verdict (no unqualified success headline)" || no "(b4) apply reported plain success while an unintended path was committable"
hasF 'OVER-inclusion' "$out_b4" && ok "(b4) the warning names the failure mode as OVER-inclusion" || no "(b4) the warning does not name over-inclusion"
hasF "$P_LOCAL" "$out_b4" && ok "(b4) the warning NAMES the specific unintended path that became committable" || no "(b4) the warning names no leaked path"
hasF "$P_WT" "$out_b4" && ok "(b4) the warning names the second leaked unintended path too (per path, never a bulk claim)" || no "(b4) the warning omitted a leaked path"
hasF '!settings.local.json' "$out_b4" && ok "(b4) the warning names the winning '!' rule from a real check-ignore -v probe, not a guess" || no "(b4) the warning does not name the winning re-include"
hasi 're-include' "$out_b4" && ok "(b4) the remediation points at the over-broad '!' re-include as the cause" || no "(b4) the remediation does not point at the re-include"
# THE BACKWARDS COPY MUST BE ABSENT. This is the actual regression the branch exists to prevent.
hasi 'comment out the rule named above' "$out_b4" && no "(b4) the MISLEADING under-inclusion copy ('comment out the rule named above') was printed for an over-inclusion failure" || ok "(b4) the misleading under-inclusion copy is NOT printed"
hasF 'STILL IGNORED' "$out_b4" && no "(b4) the warning claimed intended paths are STILL IGNORED when none are" || ok "(b4) the warning does not claim a non-existent under-inclusion"
# and the UNDER-inclusion branch must keep its own copy (no cross-contamination from the new branch)
hasi 'comment out the rule named above' "$out_by" && ok "(b4) the under-inclusion branch (b2) still carries its own 'comment out the rule' remedy" || no "(b4) the under-inclusion remedy was lost from the (b2) path"
hasF 'OVER-inclusion' "$out_by" && no "(b4) the under-inclusion branch wrongly printed the over-inclusion copy" || ok "(b4) the under-inclusion branch does not print over-inclusion copy"

# ============================================================================
echo "== (b5) git's own lexer decides what is an obstacle — leading-space / inline-# forms ignore NOTHING =="
# A reviewer flagged `.claude/   # my note` as escaping comment_bare_excludes' trimmed match. It
# does escape it — and that is CORRECT, because git has NO inline-comment syntax and does not strip
# LEADING whitespace: neither form excludes anything under `.claude/`, so neither is an obstacle to
# the negation and neutralising it would rewrite a user's file for no benefit. Asserted against real
# `git check-ignore`, because "git treats it as X" is exactly the kind of claim that must be probed.
B5="$(newgit https://github.com/acme/widget.git)"
seed_stores "$B5"
printf '.claude/   # my note\n   .supervisor/\n' > "$B5/.gitignore"
assert_committable "$B5" "$P_MEM" "(b5) an INLINE-# '.claude/   # my note' line does not ignore $P_MEM (git has no inline comments)"
assert_committable "$B5" "$P_LOCAL" "(b5) it does not ignore $P_LOCAL either — it is not a directory exclude at all"
assert_committable "$B5" "$P_LES" "(b5) a LEADING-whitespace '   .supervisor/' line does not ignore $P_LES (git keeps leading whitespace)"
# TRAILING whitespace IS stripped by git, so that form IS a real obstacle — and IS neutralised.
B5b="$(newgit https://github.com/acme/widget.git)"
seed_stores "$B5b"
printf '.claude/   \n' > "$B5b/.gitignore"
assert_ignored "$B5b" "$P_MEM" "(b5) by contrast a TRAILING-whitespace '.claude/   ' IS a real exclude in git (trailing space is stripped)"
out_b5b="$(mem "$B5b" apply 2>&1)"
has '^Memory readiness: configured' "$out_b5b" && ok "(b5) apply neutralises the trailing-whitespace form (verdict configured)" || no "(b5) the trailing-whitespace exclude was not neutralised"
assert_committable "$B5b" "$P_MEM" "(b5) $P_MEM is committable after neutralising the trailing-whitespace exclude"
# The non-obstacle forms survive apply UNTOUCHED and still round-trip byte-exactly through remove.
orig_b5="$(mkfix)/orig.gitignore"; cp "$B5/.gitignore" "$orig_b5"
out_b5="$(mem "$B5" apply 2>&1)"
gi_b5="$(cat "$B5/.gitignore")"
hasF '.claude/   # my note' "$gi_b5" && ok "(b5) the inline-# line survives apply verbatim (not commented, not dropped)" || no "(b5) apply mangled the inline-# line"
hasF '   .supervisor/' "$gi_b5" && ok "(b5) the leading-whitespace line survives apply verbatim" || no "(b5) apply mangled the leading-whitespace line"
has '^Memory readiness: configured' "$out_b5" && ok "(b5) the verdict is 'configured' — leaving the non-obstacles live costs nothing" || no "(b5) leaving the non-obstacle forms live broke the negation"
mem "$B5" remove >/dev/null 2>&1
if cmp -s "$orig_b5" "$B5/.gitignore"; then ok "(b5) apply → remove round-trips the non-obstacle forms BYTE-EXACTLY"; else no "(b5) the non-obstacle forms did not round-trip through remove"; fi

# ============================================================================
echo "== (c) dotfile sidecars commit — asserted explicitly, separately from the ** globs =="
# Their absence would silently strip provenance from a fresh clone (read-lessons.sh's read-side
# provenance gate depends on them), and a dotfile inside a re-included directory is its own
# silent-failure class — so these get their own assertions, not a '** covers it' claim.
assert_committable "$Ab" "$P_MEM_DOT" "(c) dotfile sidecar $P_MEM_DOT is committable"
assert_committable "$Ab" "$P_LES_DOT" "(c) dotfile sidecar $P_LES_DOT is committable"

# ============================================================================
echo "== (d) allowlist — a LIST, rename-tolerant, foreign records excluded, remote-defaulted =="
if [ -z "$JQ" ]; then
  ok "(d) jq unavailable — allowlist/ledger group skipped (pass)"
else
  # (d1) fresh install with NO config → defaults to the CURRENT remote's owner/repo.
  D1="$(newgit https://github.com/acme/widget.git)"
  al_d1="$(mem "$D1" allowlist 2>/dev/null)"
  [ "$al_d1" = "acme/widget" ] && ok "(d1) fresh install defaults the allowlist to the current remote (acme/widget)" || no "(d1) fresh-install default wrong (got: $al_d1)"
  src_d1="$(mem "$D1" allowlist 2>&1 >/dev/null)"
  hasF 'default (current git remote)' "$src_d1" && ok "(d1) source reported as 'default (current git remote)'" || no "(d1) allowlist source not reported as the remote default (got: $src_d1)"
  # ssh scp-style remotes resolve identically (no owner is ever hardcoded).
  D1b="$(newgit git@github.com:someone-else/other-repo.git)"
  al_d1b="$(mem "$D1b" allowlist 2>/dev/null)"
  [ "$al_d1b" = "someone-else/other-repo" ] && ok "(d1) ssh scp-style remote resolves to owner/repo (no hardcoded owner)" || no "(d1) ssh remote did not resolve (got: $al_d1b)"

  # (d2) apply STORES the allowlist as a JSON ARRAY — never a string.
  D2="$(newgit https://github.com/acme/widget.git)"
  printf '.claude/\n.supervisor/\n' > "$D2/.gitignore"
  mem "$D2" apply >/dev/null 2>&1
  cfg_type="$(jq -r '.setup_memory.repo_allowlist | type' "$D2/.supervisor/config.json" 2>/dev/null)"
  [ "$cfg_type" = "array" ] && ok "(d2) seeded .setup_memory.repo_allowlist is a JSON array (never a string)" || no "(d2) seeded allowlist type is '$cfg_type', expected array"
  [ "$(jq -r '.setup_memory.repo_allowlist[0]' "$D2/.supervisor/config.json" 2>/dev/null)" = "acme/widget" ] && ok "(d2) seeded entry is the current remote" || no "(d2) seeded entry wrong"
  # unrelated config keys survive the merge
  D2b="$(newgit https://github.com/acme/widget.git)"
  printf '.claude/\n' > "$D2b/.gitignore"
  mkdir -p "$D2b/.supervisor"; printf '{"auto_review": false, "other": {"k": 1}}\n' > "$D2b/.supervisor/config.json"
  mem "$D2b" apply >/dev/null 2>&1
  [ "$(jq -r '.auto_review' "$D2b/.supervisor/config.json" 2>/dev/null)" = "false" ] && ok "(d2) unrelated config key .auto_review survived the allowlist merge" || no "(d2) allowlist merge clobbered an unrelated config key"
  [ "$(jq -r '.other.k' "$D2b/.supervisor/config.json" 2>/dev/null)" = "1" ] && ok "(d2) nested unrelated config key survived" || no "(d2) nested unrelated config key lost"

  # (d3) THE RENAME CASE — the reason the field is a list at all. A ledger holding records under a
  # PRE-RENAME slug and the CURRENT slug must retain BOTH when both are listed.
  D3="$(newgit https://github.com/acme/widget.git)"
  cat > "$D3/ledger.jsonl" <<'LEDGER'
{"repo":"acme/old-name","number":1,"review_rounds":3}
{"repo":"acme/widget","number":2,"review_rounds":1}
{"repo":"stranger/elsewhere","number":3,"review_rounds":9}
{"number":4,"review_rounds":0}
LEDGER
  both="$(mem "$D3" filter-ledger --ledger "$D3/ledger.jsonl" --allow acme/widget --allow acme/old-name 2>/dev/null)"
  # jq, never grep — `grep -c '"repo"'` cannot see a SPACED-form record and would under-count here
  # exactly as it does against this plugin's own ledger. See the header note and group (l2).
  n_both="$(ledger_count "$both")"
  [ "$n_both" = "2" ] && ok "(d3) rename case: records under BOTH slugs retained (2 of 4, counted with jq)" || no "(d3) rename case retained $n_both records, expected 2"
  ledger_has_repo "$both" "acme/old-name" && ok "(d3) the PRE-RENAME slug's record is retained (a live-remote filter would have dropped it)" || no "(d3) pre-rename record dropped"
  ledger_has_repo "$both" "acme/widget"   && ok "(d3) the current slug's record is retained" || no "(d3) current-slug record dropped"
  # (d4) a record OUTSIDE the allowlist is excluded.
  ledger_has_repo "$both" "stranger/elsewhere" && no "(d4) a foreign-repo record leaked through the filter" || ok "(d4) foreign-repo record 'stranger/elsewhere' excluded"
  ledger_has_field "$both" number 4 && no "(d4) a record with NO .repo leaked through (unattributable must be excluded)" || ok "(d4) record with no .repo excluded (unattributable → not retained)"
  # (d5) the live-remote default alone drops the pre-rename half — the documented hazard, asserted.
  only_remote="$(mem "$D3" filter-ledger --ledger "$D3/ledger.jsonl" 2>/dev/null)"
  ledger_has_repo "$only_remote" "acme/old-name" && no "(d5) remote-only allowlist unexpectedly retained the pre-rename record" || ok "(d5) remote-only allowlist DROPS the pre-rename record — this is exactly why the allowlist is a list"
  ledger_has_repo "$only_remote" "acme/widget" && ok "(d5) remote-only allowlist still retains the current slug" || no "(d5) remote-only allowlist retained nothing at all"
  # (d6) an empty allowlist retains NOTHING (fail-closed), never everything.
  D6="$(newgit)"   # no remote at all
  cp "$D3/ledger.jsonl" "$D6/ledger.jsonl"
  empty_out="$(mem "$D6" filter-ledger --ledger "$D6/ledger.jsonl" 2>/dev/null)"
  [ -z "$empty_out" ] && ok "(d6) empty allowlist retains NOTHING (fail-closed, never 'everything')" || no "(d6) empty allowlist leaked records"
  src_d6="$(mem "$D6" allowlist 2>&1 >/dev/null)"
  hasF 'unset (no git remote' "$src_d6" && ok "(d6) no-remote fixture reports the allowlist source as unset" || no "(d6) no-remote source label wrong (got: $src_d6)"
  # (d7) a STRING-shaped allowlist is warned about (the stored shape must be a list).
  D7="$(newgit)"
  mkdir -p "$D7/.supervisor"; printf '{"setup_memory":{"repo_allowlist":"acme/widget"}}\n' > "$D7/.supervisor/config.json"
  warn_d7="$(mem "$D7" allowlist 2>&1 >/dev/null)"
  hasi 'MUST be a JSON array' "$warn_d7" && ok "(d7) a STRING allowlist is loudly flagged as a misconfiguration" || no "(d7) string-shaped allowlist accepted silently (got: $warn_d7)"
  # (d8) a malformed ledger line is skipped, not fatal.
  printf 'NOT JSON AT ALL\n{"repo":"acme/widget","number":99}\n' >> "$D3/ledger.jsonl"
  robust="$(mem "$D3" filter-ledger --ledger "$D3/ledger.jsonl" --allow acme/widget 2>/dev/null)"; rc_r=$?
  [ "$rc_r" -eq 0 ] && ok "(d8) filter-ledger exits 0 on a ledger containing a malformed line" || no "(d8) filter-ledger non-zero on malformed line ($rc_r)"
  ledger_has_field "$robust" number 99 && ok "(d8) records AFTER the malformed line are still retained (per-line fallback works)" || no "(d8) the malformed line swallowed the rest of the ledger"

  # (d10) AN UNTERMINATED FINAL LINE IS STILL FILTERED — the `|| [ -n "$line" ]` guard on
  # filter_ledger_by_allowlist's per-line fallback, pinned.
  #
  # THE FIXTURE DELIBERATELY OMITS THE TRAILING NEWLINE — same reason as group (l8), and it must not
  # be "tidied" into one. A bare `while IFS= read -r line; do … done < "$ledger"` NEVER RUNS ITS BODY
  # for an unterminated final line (`read` returns non-zero at EOF even though it filled $line), and
  # every OTHER filter-ledger fixture above ends with a newline, so nothing else here can catch it.
  # Here the loss is in the OPPOSITE direction from (l8): the dropped final line is a VALID,
  # ALLOWLISTED record, so it is silently absent from `filter-ledger > tmp && mv tmp ledger` — the
  # documented remedy — i.e. real data loss in the exact path users are told to run.
  D10="$(newgit https://github.com/acme/widget.git)"
  # The malformed middle line is what forces the per-line FALLBACK (the whole-file jq pass aborts);
  # without it the guard is never reached and this case would assert nothing.
  printf '%s\n%s\n%s' \
    '{"repo":"acme/widget","number":1}' \
    'NOT JSON AT ALL' \
    '{"repo":"acme/widget","number":3}' > "$D10/ledger.jsonl"
  tail_out="$(mem "$D10" filter-ledger --ledger "$D10/ledger.jsonl" --allow acme/widget 2>/dev/null)"
  ledger_has_field "$tail_out" number 1 && ok "(d10) the record BEFORE the malformed line is retained" || no "(d10) the leading record was dropped"
  # THE assertion — this is the one that goes red when `|| [ -n "$line" ]` is reverted.
  ledger_has_field "$tail_out" number 3 && ok "(d10) a VALID allowlisted FINAL record with NO trailing newline is RETAINED (unterminated-line guard)" || no "(d10) the unterminated final record was SILENTLY DROPPED — data loss in the filter-ledger remedy path"
  # NEGATIVE CONTROL — the guard recovers the line, it does not defeat jq's `select`. Same shape,
  # same missing trailing newline, but the final record is FOREIGN and must still be excluded.
  D10b="$(newgit https://github.com/acme/widget.git)"
  printf '%s\n%s\n%s' \
    '{"repo":"acme/widget","number":1}' \
    'NOT JSON AT ALL' \
    '{"repo":"stranger/elsewhere","number":3}' > "$D10b/ledger.jsonl"
  tail_foreign="$(mem "$D10b" filter-ledger --ledger "$D10b/ledger.jsonl" --allow acme/widget 2>/dev/null)"
  ledger_has_repo "$tail_foreign" "stranger/elsewhere" && no "(d10) a FOREIGN unterminated final record leaked through — the guard defeated the allowlist filter" || ok "(d10) a FOREIGN final record with NO trailing newline is still EXCLUDED (guard recovers the line, jq still filters it)"
fi

# (d9) A FILESYSTEM-PATH REMOTE CARRIES NO OWNER. `origin = /Users/x/myrepo` has the same shape as
# `host/owner/repo` once you only look at the last two segments, so a naive tail split returns
# `x/myrepo` — an owner invented from a parent DIRECTORY name, which contradicts remote_slug's own
# "NEVER guesses an owner" contract and would silently mis-scope the ledger filter.
# (Outside the jq guard on purpose: `allowlist` resolution needs no jq.)
D9="$(newgit /Users/someone/parent-dir/myrepo)"
al_d9="$(mem "$D9" allowlist 2>/dev/null)"
[ -z "$al_d9" ] && ok "(d9) a filesystem-path remote yields NO allowlist default (no owner fabricated from a parent dir)" || no "(d9) a filesystem-path remote fabricated the owner '$al_d9'"
src_d9="$(mem "$D9" allowlist 2>&1 >/dev/null)"
hasF 'unset (no git remote' "$src_d9" && ok "(d9) the path remote is reported as 'unset', not as a resolved default" || no "(d9) wrong source label for a path remote (got: $src_d9)"
D9b="$(newgit ../sibling-repo)"
[ -z "$(mem "$D9b" allowlist 2>/dev/null)" ] && ok "(d9) a RELATIVE path remote also yields no default" || no "(d9) a relative path remote fabricated an owner"
D9c="$(newgit ssh://git@github.com/acme/widget.git)"
[ "$(mem "$D9c" allowlist 2>/dev/null)" = "acme/widget" ] && ok "(d9) a real ssh:// URL still resolves (the path guard did not over-reject)" || no "(d9) the path guard broke ssh:// URL resolution"

