# =============================================================================
echo "== W. plan-waves (parallel-automate/04: read-only wave planner; fixtures under mktemp -d, --root = fixture root) =="
W_T="$(mktemp -d)"
W_REPO="$(cd "$HERE/../.." && pwd)"
# w_item <path under W_T> <Depends body|-> <Touches body|-> [status line]  ('-' omits the section; bodies use printf %b)
w_item() {
  mkdir -p "$(dirname "$W_T/$1")"
  {
    echo "# Item $1"
    if [ -n "${4:-}" ]; then echo; echo "## Status: $4"; fi
    if [ "$2" != - ]; then echo; echo "## Depends on"; printf '%b\n' "$2"; fi
    if [ "$3" != - ]; then echo; echo "## Touches"; printf '%b\n' "$3"; fi
    echo; echo "## Notes"; echo "prose"
  } > "$W_T/$1"
}
# w_run <root> <helper> <input> <args...> — stdout in W_OUT, stderr in W_ERR, exit code in W_RC
w_run() {
  local root="$1" helper="$2" input="$3"; shift 3
  W_RC=0
  W_OUT="$(bash "$helper" plan-waves "$input" --root "$root" "$@" 2>"$W_T/err")" || W_RC=$?
  W_ERR="$(cat "$W_T/err")"
}
w_list() { printf '%s\n' "$@" > "$W_T/list"; }
w_expect() {  # <label> <expected stdout (printf %b)>
  local want; want="$(printf '%b' "$2")"
  if [ "$W_RC" -eq 0 ] && [ "$W_OUT" = "$want" ]; then ok "$1"; else no "$1 (rc=$W_RC) got: $(printf '%s' "$W_OUT" | tr '\n' '|') err: $W_ERR"; fi
}
w_fails() {  # <label> <stderr substring>
  if [ "$W_RC" -eq 1 ] && [ -z "$W_OUT" ] && grep -qF -- "$2" <<<"$W_ERR"; then ok "$1"; else no "$1 (rc=$W_RC out='$W_OUT' err='$W_ERR')"; fi
}

# W1 disjoint items share a wave; the absent companion table is announced on stderr and the plan proceeds.
rm -rf "$W_T/q"
w_item q/01-a.md none 'a/x.sh'
w_item q/02-b.md none 'b/y.sh'
w_list q/01-a.md q/02-b.md
w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W1 disjoint items share a wave" 'wave 1: q/01-a.md q/02-b.md'
case "$W_ERR" in *"plan-waves: no $W_T/.agent/companions.json — no companion expansion"*|*"/.agent/companions.json — no companion expansion"*) ok "W1 absent companions.json ⇒ one stderr note" ;; *) no "W1 absent companions note missing: $W_ERR" ;; esac

# W2 prefix-intersecting items never share a wave (a/ vs a/b.sh; a/b vs a/b).
rm -rf "$W_T/q"
w_item q/01-a.md none 'a/'
w_item q/02-b.md none 'a/b.sh'
w_item q/03-c.md none 'z/b'
w_item q/04-d.md none 'z/b'
w_list q/01-a.md q/02-b.md q/03-c.md q/04-d.md
w_run "$W_T" "$H" "$W_T/list" --max 4
w_expect "W2 prefix/equal entries intersect (a/ vs a/b.sh; z/b vs z/b)" 'wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md q/04-d.md'

# W3 companion expansion separates two items editing DIFFERENT x/skills/<s>/SKILL.md (fixture table);
#    mutation control (ii): the same items under a root with NO companions.json share a wave.
W_C="$W_T/croot"; W_NC="$W_T/nocroot"
mkdir -p "$W_C/.agent" "$W_NC"
cat > "$W_C/.agent/companions.json" <<'JSON'
{"schema_version": 1, "companions": [
  {"when": "x/skills/*/SKILL.md", "add": ["x/skills/SKILLS_INDEX.md"]},
  {"when": "x/agents/*", "new": true, "add": ["x/INDEX.md"]}
]}
JSON
for r in "$W_C" "$W_NC"; do
  mkdir -p "$r/q" "$r/x/agents"; : > "$r/x/agents/old.md"
  printf '# s1\n## Depends on\nnone\n## Touches\nx/skills/s1/SKILL.md\n' > "$r/q/01-s1.md"
  printf '# s2\n## Depends on\nnone\n## Touches\nx/skills/s2/SKILL.md\n' > "$r/q/02-s2.md"
done
printf 'q/01-s1.md\nq/02-s2.md\n' > "$W_T/list"
W_SEP_WANT='wave 1: q/01-s1.md\nwave 2: q/02-s2.md'
w_run "$W_C" "$H" "$W_T/list" --max 3
w_expect "W3 companion expansion separates two different x/skills/<s>/SKILL.md items" "$W_SEP_WANT"
w_run "$W_NC" "$H" "$W_T/list" --max 3
if [ "$W_OUT" != "$(printf '%b' "$W_SEP_WANT")" ] && [ "$W_OUT" = "wave 1: q/01-s1.md q/02-s2.md" ]; then
  ok "W3 MUTATION CONTROL (ii): companion table removed ⇒ the separation assertion turns red (they share wave 1) — the table is load-bearing"
else no "W3 mutation control (ii) did not turn red: $W_OUT"; fi

# W4 a "new": true rule fires for a missing path and not for an existing one.
printf '# n\n## Depends on\nnone\n## Touches\nx/agents/new.md\n' > "$W_C/q/03-new.md"
printf '# o\n## Depends on\nnone\n## Touches\nx/agents/old.md\n' > "$W_C/q/04-old.md"
printf '# i\n## Depends on\nnone\n## Touches\nx/INDEX.md\n' > "$W_C/q/05-idx.md"
printf 'q/05-idx.md\nq/03-new.md\n' > "$W_T/list"
w_run "$W_C" "$H" "$W_T/list" --max 3
w_expect "W4 \"new\" rule fires for a missing file (x/agents/new.md drags x/INDEX.md)" 'wave 1: q/05-idx.md\nwave 2: q/03-new.md'
printf 'q/05-idx.md\nq/04-old.md\n' > "$W_T/list"
w_run "$W_C" "$H" "$W_T/list" --max 3
w_expect "W4 \"new\" rule does NOT fire for an existing file (x/agents/old.md)" 'wave 1: q/05-idx.md q/04-old.md'
# A directory entry D/ fires a rule whose literal prefix D/ covers (x/agents/ vs "x/agents/*"), new rules included.
printf '# d\n## Depends on\nnone\n## Touches\nx/agents/\n' > "$W_C/q/06-dir.md"
printf 'q/06-dir.md\nq/05-idx.md\n' > "$W_T/list"
w_run "$W_C" "$H" "$W_T/list" --max 3
w_expect "W4 directory entry x/agents/ fires the new rule ⇒ drags x/INDEX.md" 'wave 1: q/06-dir.md\nwave 2: q/05-idx.md'

# W5 dependency ordering across waves, incl. an in-set ../other/NN-x.md dependency (physical-path key).
rm -rf "$W_T/q" "$W_T/other"
w_item q/01-a.md '../other/05-y.md' 'a'
w_item q/02-b.md '1' 'b'
w_item other/05-y.md none 'y'
w_list q/01-a.md q/02-b.md other/05-y.md
w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W5 deps order the waves (../other dep in the plan set; numeric id 1 ⇒ 01-a.md)" 'wave 1: other/05-y.md\nwave 2: q/01-a.md\nwave 3: q/02-b.md'

# W6 run-file input: plain [x] ⇒ merged-done; `# skipped:` row and an ABANDONED stamp ⇒ never landed;
#    a closed-out file (pending heading then done heading) ⇒ merged-done.
rm -rf "$W_T/q"
w_item q/01-a.md none 'a'
w_item q/02-b.md none 'b'
w_item q/03-c.md '01' 'c'
w_item q/04-d.md '02' 'd'
w_item q/05-e.md '06' 'e'
w_item q/06-f.md none 'f' 'done_with_escalation — ABANDONED (- [x] q/06-f.md  # abandoned: x)'
w_item q/07-g.md none 'g' 'pending'
printf '\n## Status: done\n' >> "$W_T/q/07-g.md"
w_item q/08-h.md '07' 'h'
cat > "$W_T/run.md" <<'RUN'
# Automate Run: automate-test
## Status: running
## Queue
- [x] q/01-a.md  # skipped: owner said so
- [x] q/02-b.md
- [ ] q/03-c.md
- [ ] q/04-d.md
- [ ] q/05-e.md
- [ ] q/08-h.md
## Current
RUN
w_run "$W_T" "$H" "$W_T/run.md" --max 3
w_expect "W6 run file: merged-done / skipped / ABANDONED / two-heading done" 'wave 1: q/04-d.md q/08-h.md\nblocked q/03-c.md: waits on 01 (skipped — never landed)\nblocked q/05-e.md: waits on 06 (abandoned — never landed)'

# W6b the owner's Queue row mark outranks the file stamp: a `# skipped:` / `# abandoned:` row over a
#     plain done / done_with_escalation stamp (Phase 4.5 writes those BEFORE any merge) never landed.
rm -rf "$W_T/q"
w_item q/01-a.md none 'a' 'done_with_escalation'
w_item q/02-b.md '01' 'b'
w_item q/03-c.md none 'c' 'done_with_escalation'
w_item q/04-d.md '03' 'd'
w_item q/05-e.md none 'e' 'done'
w_item q/06-f.md '05' 'f'
cat > "$W_T/run.md" <<'RUN'
# Automate Run: automate-test
## Status: running
## Queue
- [x] q/01-a.md  # skipped: owner said so
- [x] q/03-c.md  # abandoned: superseded
- [x] q/05-e.md  # skipped: dropped
- [ ] q/02-b.md
- [ ] q/04-d.md
- [ ] q/06-f.md
## Current
RUN
w_run "$W_T" "$H" "$W_T/run.md" --max 3
w_expect "W6b skipped/abandoned row over a done(_with_escalation) stamp ⇒ never landed (row wins)" 'blocked q/02-b.md: waits on 01 (skipped — never landed)\nblocked q/04-d.md: waits on 03 (abandoned — never landed)\nblocked q/06-f.md: waits on 05 (skipped — never landed)'

# W6c a run file whose title is a TOLERATED non-exact form (BOM + lower-case, automate-followups/19)
#     is still classified as a run file (is_run_file is plan_waves' input classifier): the plan set
#     is its unchecked Queue rows only. Read as an item list instead, the BOM line and the `- [ ]`
#     rows would be taken as item paths and the run would exit 1 ("item not found").
rm -rf "$W_T/q"
w_item q/01-a.md none 'a'
w_item q/02-b.md none 'b'
w_item q/03-c.md none 'c' 'done'
{ printf '\357\273\277# automate run: automate-test\n'
  printf '## Status: running\n## Queue\n- [x] q/03-c.md\n- [ ] q/01-a.md\n- [ ] q/02-b.md\n## Current\n'; } > "$W_T/run-tolerant.md"
w_run "$W_T" "$H" "$W_T/run-tolerant.md" --max 3
w_expect "W6c BOM + lower-case titled run file is parsed as a run file (plan set = its unchecked Queue rows)" 'wave 1: q/01-a.md q/02-b.md'

# W7 parked dependency; out-of-set pending dependency; transitive block.
rm -rf "$W_T/q"
w_item q/01-a.md '02' 'a'
w_item q/02-b.md none 'b' 'parked (waits on S1)'
w_item q/03-c.md '04' 'c'
w_item q/04-d.md none 'd' 'pending'
w_item q/05-e.md '01' 'e'
w_list q/01-a.md q/03-c.md q/05-e.md
w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W7 parked ⇒ depends on parked; pending out-of-set ⇒ waits on; transitive ⇒ waits on its id" 'blocked q/01-a.md: depends on parked 02\nblocked q/03-c.md: waits on 04\nblocked q/05-e.md: waits on 01'

# W8 missing / unknown / malformed Touches runs ALONE (the item in the middle of three disjoint ones).
w_alone() {  # <label> <Touches body|-> [helper]
  rm -rf "$W_T/q"
  w_item q/01-a.md none 'a'
  w_item q/02-b.md none "$2"
  w_item q/03-c.md none 'c'
  w_list q/01-a.md q/02-b.md q/03-c.md
  w_run "$W_T" "${3:-$H}" "$W_T/list" --max 3
}
W_ALONE_WANT='wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md'
w_alone missing -; w_expect "W8 missing Touches runs alone" "$W_ALONE_WANT"
w_alone unknown 'unknown'; w_expect "W8 'unknown' Touches runs alone" "$W_ALONE_WANT"
w_alone backtick '`b/x.sh`'; w_expect "W8 backtick Touches line ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone glob 'b/*.sh'; w_expect "W8 glob Touches line ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone pipe 'a|b'; w_expect "W8 'a|b' Touches line ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone prose 'b/x.sh and friends'; w_expect "W8 trailing prose ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone bullet '- b/x.sh'; w_expect "W8 bullet ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone mixed 'b/x.sh\nunknown'; w_expect "W8 unknown mixed with a path ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone empty ''; w_expect "W8 empty section ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dotdot 'b/../x'; w_expect "W8 '..' segment ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot '.'; w_expect "W8 bare '.' (whole repo) ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot-dir './'; w_expect "W8 './' ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot-lead './b/x.sh'; w_expect "W8 leading './' segment ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot-mid 'b/./x.sh'; w_expect "W8 inner '.' segment ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone dot-name 'b/.x.sh'; w_expect "W8 a dot-file name is NOT a '.' segment (still known)" 'wave 1: q/01-a.md q/02-b.md q/03-c.md'
w_alone duplicate 'b/x.sh\n\n## Touches\nb/y.sh'; w_expect "W8 heading twice ⇒ unknown, runs alone" "$W_ALONE_WANT"
w_alone blank-lines 'b/x.sh\n\nb/y.sh'; w_expect "W8 blank lines inside a section are ignored (still known)" 'wave 1: q/01-a.md q/02-b.md q/03-c.md'
# An unknown item first takes wave 1 alone.
rm -rf "$W_T/q"; w_item q/01-a.md none -; w_item q/02-b.md none 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md
w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W8 a missing-Touches FIRST item takes its wave alone" 'wave 1: q/01-a.md\nwave 2: q/02-b.md q/03-c.md'
# MUTATION CONTROL (i): a helper copy where a MISSING Touches is an EMPTY set must turn "missing runs alone" red.
sed 's/print "unknown"; exit }   # PW_MISSING_TOUCHES/print "known"; exit }   # PW_MISSING_TOUCHES/' "$H" > "$W_T/mut-empty.sh"
if [ -s "$W_T/mut-empty.sh" ] && ! cmp -s "$H" "$W_T/mut-empty.sh" && bash -n "$W_T/mut-empty.sh"; then
  w_alone missing - "$W_T/mut-empty.sh"
  if [ "$W_OUT" != "$(printf '%b' "$W_ALONE_WANT")" ]; then
    ok "W8 MUTATION CONTROL (i): missing-Touches-as-empty-set mutant turns 'missing runs alone' red ($(printf '%s' "$W_OUT" | tr '\n' '|'))"
  else no "W8 mutation control (i) stayed green — the assertion is vacuous"; fi
  w_alone missing -; w_expect "W8 mutation control (i): the REAL helper stays green" "$W_ALONE_WANT"
else no "W8 mutation control (i) inconclusive: mutant empty, identical or not valid bash"; fi

# W9 undeclared queue ⇒ one item per wave in queue order.
rm -rf "$W_T/q"; w_item q/01-a.md - 'a'; w_item q/02-b.md - 'b'; w_item q/03-c.md - 'c'
w_run "$W_T" "$H" "$W_T/q" --max 3
w_expect "W9 undeclared queue (dir input) ⇒ one item per wave in order" "wave 1: $W_T/q/01-a.md\nwave 2: $W_T/q/02-b.md\nwave 3: $W_T/q/03-c.md"

# W10 cycles: explicit and via the implicit rule ⇒ exit 1, stdout empty, items named.
rm -rf "$W_T/q"; w_item q/01-a.md '02' 'a'; w_item q/02-b.md '01' 'b'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W10 explicit cycle ⇒ exit 1, empty stdout" 'plan-waves: dependency cycle: q/01-a.md q/02-b.md'
rm -rf "$W_T/q"; w_item q/01-a.md '02' 'a'; w_item q/02-b.md - 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W10 implicit-rule cycle (01 ⇒ 02, undeclared 02 ⇒ every earlier) ⇒ exit 1, both named, 03 not" 'plan-waves: dependency cycle: q/01-a.md q/02-b.md'
case "$W_ERR" in *03-c.md*) no "W10 implicit cycle named a non-cycle item: $W_ERR" ;; *) ok "W10 the cycle message names only the cycle's items" ;; esac

# W11 unknown dependency id: zero matches and two matches ⇒ exit 1, stdout empty.
rm -rf "$W_T/q"; w_item q/01-a.md '09' 'a'
w_list q/01-a.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W11 zero-match id ⇒ unknown dependency" 'plan-waves: unknown dependency 09 in q/01-a.md'
w_item q/01-a.md '5' 'a'; w_item q/05-x.md none 'x'; w_item q/05-y.md none 'y'
w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W11 two-match id ⇒ unknown dependency" 'plan-waves: unknown dependency 5 in q/01-a.md'
w_item q/01-a.md '../nowhere/01-z.md' 'a'; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W11 a dependency path that is not an existing file ⇒ unknown dependency" 'plan-waves: unknown dependency ../nowhere/01-z.md in q/01-a.md'

# W11b a plan-set item that names no file on disk ⇒ exit 1 `item not found: <item>`, stdout empty
#      (an item-list line, and an unchecked run-file Queue row).
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'
w_list q/01-a.md q/02-gone.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_fails "W11b item-list line naming a missing file ⇒ exit 1, item not found" 'plan-waves: item not found: q/02-gone.md'
printf '# Automate Run: automate-test\n## Status: running\n## Queue\n- [ ] q/01-a.md\n- [ ] q/03-gone.md\n## Current\n' > "$W_T/run-missing.md"
w_run "$W_T" "$H" "$W_T/run-missing.md" --max 3
w_fails "W11b run-file Queue row naming a missing file ⇒ exit 1, item not found" 'plan-waves: item not found: q/03-gone.md'

# W12 --max respected: three disjoint items, --max 2 ⇒ 2 + 1.
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md none 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 2
w_expect "W12 --max 2 over three disjoint items ⇒ waves of 2 + 1" 'wave 1: q/01-a.md q/02-b.md\nwave 2: q/03-c.md'

# W13 companions.json malformed ⇒ exit 1 companions_malformed, stdout empty (every bad shape).
W_M="$W_T/mroot"; mkdir -p "$W_M/.agent"; cp -R "$W_T/q" "$W_M/q"
for bad in 'not json' '[]' '{"schema_version":2,"companions":[]}' '{"schema_version":1}' \
  '{"schema_version":1,"companions":[{"when":"a/*"}]}' '{"schema_version":1,"companions":[{"when":"a/*","add":["b"],"new":false}]}' \
  '{"schema_version":1,"companions":[{"when":"a/*","add":["b c"]}]}' '{"schema_version":1,"companions":[{"when":"a","add":["b"],"x":1}]}' \
  '{"schema_version":1,"companions":[{"when":"./a/*","add":["b"]}]}' '{"schema_version":1,"companions":[{"when":"a/./*","add":["b"]}]}' \
  '{"schema_version":1,"companions":[{"when":"a/*","add":["./b"]}]}' '{"schema_version":1,"companions":[{"when":"a/*","add":["b/../c"]}]}' \
  '{"schema_version":1,"companions":[{"when":"a/*","add":["."]}]}' '{"schema_version":1,"companions":[{"when":"a/*","add":["/b"]}]}' \
  '{"schema_version":1,"companions":[{"when":"a//*","add":["b"]}]}' \
  '{"schema_version":1,"companions":[{"when":"/a/*","add":["b"]}]}' '{"schema_version":1,"companions":[{"when":"a/../*","add":["b"]}]}'; do
  printf '%s\n' "$bad" > "$W_M/.agent/companions.json"
  w_run "$W_M" "$H" "$W_T/list" --max 2
  w_fails "W13 malformed companions.json '$bad' ⇒ exit 1" 'plan-waves: companions_malformed'
done
# Exactly ONE JSON document: a malformed first document followed by a valid one must not pass on
# the strength of the last document alone (and two valid documents are not that shape either).
printf '%s\n%s\n' '{"schema_version":2,"companions":[{"when":"a/*","add":["b"]}]}' '{"schema_version":1,"companions":[]}' > "$W_M/.agent/companions.json"
w_run "$W_M" "$H" "$W_T/list" --max 2
w_fails "W13 two documents, malformed first + valid second ⇒ exit 1" 'plan-waves: companions_malformed'
printf '%s\n%s\n' '{"schema_version":1,"companions":[]}' '{"schema_version":1,"companions":[]}' > "$W_M/.agent/companions.json"
w_run "$W_M" "$H" "$W_T/list" --max 2
w_fails "W13 two valid documents ⇒ exit 1 (exactly one document)" 'plan-waves: companions_malformed'
printf '{"schema_version":1,"companions":[]}\n' > "$W_M/.agent/companions.json"
W_RC=0; W_OUT="$(LOOMWRIGHT_JQ_BIN=/nonexistent/jq bash "$H" plan-waves "$W_T/list" --root "$W_M" --max 2 2>"$W_T/err")" || W_RC=$?; W_ERR="$(cat "$W_T/err")"
w_fails "W13 jq absent while companions.json exists ⇒ exit 1 companions_malformed" 'plan-waves: companions_malformed jq not found'

# W14 a fenced `## Touches` is ignored; a real one beside a fenced one still parses.
rm -rf "$W_T/q"
mkdir -p "$W_T/q"; printf '# a\n## Depends on\nnone\n\n## Example\n```markdown\n## Touches\na/x\n```\n' > "$W_T/q/01-a.md"
w_item q/02-b.md none 'b'
printf '# c\n## Depends on\nnone\n## Example\n```\n## Touches\nb\n```\n## Touches\nc\n' > "$W_T/q/03-c.md"
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W14 fenced ## Touches ignored (01 unknown ⇒ alone); a real section after a fenced one parses (03 known)" 'wave 1: q/01-a.md\nwave 2: q/02-b.md q/03-c.md'

# W15 harness-port shape (fixture copy): 01→04→06, 02, 03 independent, 05→07 sharing skills/review-heal/SKILL.md.
rm -rf "$W_T/hp"
w_item hp/01-worker-rules.md none 'agents/worker.md\ndocs/prompt-token-budgets.json'
w_item hp/02-not-ready-stamp.md none 'scripts/automate-helpers.sh'
w_item hp/03-cited-line-premise.md none 'agents/worker.md'
w_item hp/04-not-verified-transport.md '01' 'agents/worker.md\ndocs/RESULT_SCHEMAS.md'
w_item hp/05-dismissed-findings.md none 'skills/review-heal/SKILL.md\ndocs/RESULT_SCHEMAS.md'
w_item hp/06-shared-local-services.md '04' 'agents/worker.md'
w_item hp/07-ci-trust-probe.md '05' 'skills/review-heal/SKILL.md'
w_run "$W_T" "$H" "$W_T/hp" --max 3
w_wave() { printf '%s\n' "$W_OUT" | awk -v it="$1" '/^wave / { for (i = 3; i <= NF; i++) if ($i ~ ("/" it "$")) { sub(":", "", $2); print $2 } }'; }
w5="$(w_wave 05-dismissed-findings.md)"; w7="$(w_wave 07-ci-trust-probe.md)"; w1="$(w_wave 01-worker-rules.md)"; w3="$(w_wave 03-cited-line-premise.md)"
if [ "$W_RC" -eq 0 ] && [ -n "$w5" ] && [ -n "$w7" ] && [ "$w7" -gt "$w5" ]; then ok "W15 harness-port: 07 lands strictly after 05 (waves $w5 < $w7)"; else no "W15 07 not after 05: $W_OUT"; fi
if [ -n "$w1" ] && [ -n "$w3" ] && [ "$w1" != "$w3" ]; then ok "W15 harness-port: 03 never shares a wave with 01 (both touch agents/worker.md)"; else no "W15 03 shares a wave with 01: $W_OUT"; fi
[ "$(printf '%s\n' "$W_OUT" | grep -c '^blocked')" -eq 0 ] && ok "W15 harness-port: nothing blocked" || no "W15 harness-port blocked lines: $W_OUT"

# W16 the five-item acceptance fixture (two disjoint pairs + one dependent, --max 3), byte-for-byte.
rm -rf "$W_T/q"
w_item q/01-a.md none 'p/'
w_item q/02-b.md none 'r/'
w_item q/03-c.md none 'p/x.sh'
w_item q/04-d.md none 'r/y.sh'
w_item q/05-e.md '01' 's/'
w_list q/01-a.md q/02-b.md q/03-c.md q/04-d.md q/05-e.md; w_run "$W_T" "$H" "$W_T/list" --max 3
w_expect "W16 five-item acceptance fixture, byte-for-byte" 'wave 1: q/01-a.md q/02-b.md\nwave 2: q/03-c.md q/04-d.md q/05-e.md'

# W17 usage errors ⇒ exit 1, stdout empty.
w_run "$W_T" "$H" "$W_T/list"; w_fails "W17 --max missing ⇒ usage" 'usage:'
for m in 0 x -1 ''; do w_run "$W_T" "$H" "$W_T/list" --max "$m"; w_fails "W17 --max '$m' ⇒ usage" 'usage:'; done
w_run "$W_T" "$H" "$W_T/nope" --max 2; w_fails "W17 missing input ⇒ usage" 'usage:'
w_run "$W_T" "$H" "$W_T/list" --max 2 --bogus; w_fails "W17 unknown option ⇒ usage" 'usage:'
W_RC=0; W_OUT="$(bash "$H" plan-waves "$W_T/list" --max 2 --root --x 2>"$W_T/err")" || W_RC=$?; W_ERR="$(cat "$W_T/err")"
w_fails "W17 option-shaped --root ⇒ refused" '--root requires a checkout path'

# W18 read-only: no file written in the fixture root, the only git call is rev-parse --show-toplevel, never gh.
mkdir -p "$W_T/spy"
printf '#!/bin/sh\necho "git $*" >> "%s/spy/calls"\nexit 1\n' "$W_T" > "$W_T/spy/git"
printf '#!/bin/sh\necho "gh $*" >> "%s/spy/calls"\nexit 1\n' "$W_T" > "$W_T/spy/gh"
chmod +x "$W_T/spy/git" "$W_T/spy/gh"; : > "$W_T/spy/calls"
w_before="$(cd "$W_T" && find q list -print | env LC_ALL=C sort | xargs ls -ld 2>/dev/null | awk '{ print $5, $NF }')"
W_RC=0; W_OUT="$(cd "$W_T" && PATH="$W_T/spy:$PATH" bash "$H" plan-waves list --max 3 2>/dev/null)" || W_RC=$?
w_after="$(cd "$W_T" && find q list -print | env LC_ALL=C sort | xargs ls -ld 2>/dev/null | awk '{ print $5, $NF }')"
[ "$W_RC" -eq 0 ] && [ "$(cat "$W_T/spy/calls")" = "git rev-parse --show-toplevel" ] && ok "W18 only git call is rev-parse --show-toplevel; no gh; --root fell back to \$PWD" || no "W18 calls: $(tr '\n' '|' < "$W_T/spy/calls") rc=$W_RC"
[ "$w_before" = "$w_after" ] && [ ! -e "$W_T/.agent" ] && ok "W18 fixture tree unchanged after plan-waves (writes only its mktemp -d)" || no "W18 fixture tree changed"

# W19 every `## Touches` section under the REAL .supervisor/requirements/parallel-automate/ parses (not unknown).
#     Read through a plan-waves ITEM-LIST run on a copy of each file with its `## Depends on` section dropped
#     (so the copy is first and dependency-free) paired with a disjoint probe: known ⇒ copy + probe share wave 1,
#     unknown ⇒ the copy runs alone. Gitignored, so absent in CI / fresh worktrees ⇒ SKIP.
W_PA="$W_REPO/.supervisor/requirements/parallel-automate"
if [ -d "$W_PA" ]; then
  w_n=0; mkdir -p "$W_T/pa"
  for f in "$W_PA"/*.md; do
    [ -f "$f" ] && grep -q '^## Touches$' "$f" || continue
    w_n=$((w_n+1))
    awk '/^## Depends on$/ { skip = 1; next } skip && (/^# / || /^## /) { skip = 0 } !skip' "$f" > "$W_T/pa/01-copy.md"
    printf '# probe\n## Depends on\nnone\n## Touches\nzz-plan-waves-probe-only/\n' > "$W_T/pa/02-probe.md"
    printf 'pa/01-copy.md\npa/02-probe.md\n' > "$W_T/list"
    w_run "$W_T" "$H" "$W_T/list" --max 2
    w_expect "W19 real $(basename "$f") ## Touches parses (known)" 'wave 1: pa/01-copy.md pa/02-probe.md'
  done
  [ "$w_n" -gt 0 ] && ok "W19 checked $w_n real parallel-automate Touches sections" || no "W19 no Touches section found under $W_PA"
else
  echo "  SKIP: W19 $W_PA absent (gitignored) — real-queue Touches parse not checked here"
fi

# W20 the shipped .agent/companions.json "new" rules cover EVERY surface in scripts/check-doc-currency.sh's
#     FILES array (the authority). Parse drops comments, strips quotes, resolves $PLUGIN_JSON from its own
#     assignment line, FAILS on any other unresolved $ token, and must be non-empty and contain plugin.json.
#     A glob entry (the agent-help parts, `.../agent-help/*.md`) is covered by an add[] entry equal to, or an
#     ancestor of, its literal directory: companions add[] admits no glob characters, and a directory entry
#     reserves everything under it. The FILES=( ) block must be the ONLY assignment to FILES: a `FILES+=`
#     append (or a second `FILES=`) is a surface this parser cannot see, so it FAILS here.
W_DC="$W_REPO/scripts/check-doc-currency.sh"; W_CJ="$W_REPO/.agent/companions.json"
w_dc_entry() {  # <pj> <one FILES entry> ⇒ its path; $PLUGIN_JSON resolved; a glob ⇒ GLOB:<dir>; other $ / top-level glob ⇒ UNRESOLVED
  local pfx
  case "$2" in
    '$PLUGIN_JSON') printf '%s\n' "$1" ;;
    *'$'*) printf 'UNRESOLVED:%s\n' "$2" ;;
    *[*?[]*)
      pfx="${2%%[*?[]*}"
      case "$pfx" in */*) printf 'GLOB:%s\n' "${pfx%/*}" ;; *) printf 'UNRESOLVED:%s\n' "$2" ;; esac ;;
    *) printf '%s\n' "$2" ;;
  esac
}
# w20_check <check-doc-currency.sh> <companions.json> — sets W20_FILES (the parsed entries) and W20_MSG
# (empty when every entry is covered by every `new` rule, else the one-line reason).
w20_check() {
  local dc="$1" cj="$2" pj e a pfx w_add w_miss="" cov
  W20_MSG=""
  pj="$(sed -n 's/^PLUGIN_JSON="\([^"]*\)"$/\1/p' "$dc" | head -n1)"
  W20_FILES="$(awk '/^FILES=\(/ { p = 1; next } p && /^\)/ { exit } p' "$dc" \
    | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^#' | grep -v '^$' | tr -d '"' \
    | while IFS= read -r e; do w_dc_entry "$pj" "$e"; done)"
  if [ -z "$W20_FILES" ] || [ -z "$pj" ]; then W20_MSG="parsed FILES set (or PLUGIN_JSON) is empty"; return 0; fi
  if [ "$(grep -cE '^[[:space:]]*FILES\+?=' "$dc")" != 1 ]; then
    W20_MSG="FILES is assigned outside its one FILES=( ) block: $(grep -nE '^[[:space:]]*FILES\+?=' "$dc" | tr '\n' ' ')"; return 0
  fi
  if grep -q '^UNRESOLVED:' <<<"$W20_FILES"; then
    W20_MSG="unresolved \$ token or top-level glob in FILES: $(printf '%s' "$W20_FILES" | grep '^UNRESOLVED:' | tr '\n' ' ')"; return 0
  fi
  if ! grep -qxF 'loomwright/.claude-plugin/plugin.json' <<<"$W20_FILES"; then W20_MSG="parsed FILES lacks loomwright/.claude-plugin/plugin.json"; return 0; fi
  for pfx in 'loomwright/agents/*' 'loomwright/commands/*' 'loomwright/skills/*'; do
    w_add="$(jq -r --arg w "$pfx" '.companions[] | select(.when == $w and .new == true) | .add[]' "$cj" 2>/dev/null)"
    [ -n "$w_add" ] || w_miss="$w_miss [no new rule for $pfx]"
    while IFS= read -r e; do
      case "$e" in
        GLOB:*)
          cov=0
          while IFS= read -r a; do
            a="${a%/}"; [ -n "$a" ] || continue
            case "${e#GLOB:}" in "$a"|"$a"/*) cov=1; break ;; esac
          done <<<"$w_add"
          [ "$cov" = 1 ] || w_miss="$w_miss [$pfx lacks ${e#GLOB:}/ (glob entry)]" ;;
        *) grep -qxF -- "$e" <<<"$w_add" || w_miss="$w_miss [$pfx lacks $e]" ;;
      esac
    done <<<"$W20_FILES"
  done
  [ -z "$w_miss" ] || W20_MSG="companions.json drifted from check-doc-currency.sh FILES:$w_miss"
  return 0
}
w20_check "$W_DC" "$W_CJ"
[ -z "$W20_MSG" ] && ok "W20 shipped companions.json new rules cover all $(printf '%s\n' "$W20_FILES" | wc -l | tr -d ' ') check-doc-currency.sh FILES entries" || no "W20 $W20_MSG"
grep -qxF 'GLOB:loomwright/docs/command-parts/agent-help' <<<"$W20_FILES" \
  && ok "W20 the block parser sees the agent-help parts glob" \
  || no "W20 the parsed FILES set lacks the agent-help parts glob (got: $(printf '%s' "$W20_FILES" | tr '\n' ' '))"
# W20b the guard demonstrably sees the parts: drop the parts entry from every rule ⇒ W20 FAILS naming it.
jq '.companions |= map(.add |= map(select(startswith("loomwright/docs/command-parts/") | not)))' "$W_CJ" > "$W_T/w20-cj.json"
w20_check "$W_DC" "$W_T/w20-cj.json"
case "$W20_MSG" in
  *"lacks loomwright/docs/command-parts/agent-help/ (glob entry)"*) ok "W20b companions.json without the parts entry FAILS W20, naming the parts dir" ;;
  *) no "W20b companions.json without the parts entry should fail W20 naming the parts dir (got: '$W20_MSG')" ;;
esac
# W20c a surface appended with `FILES+=` (invisible to the block parser) FAILS W20.
{ cat "$W_DC"; printf 'FILES+=(loomwright/docs/extra.md)\n'; } > "$W_T/w20-dc.sh"
w20_check "$W_T/w20-dc.sh" "$W_CJ"
case "$W20_MSG" in
  *"assigned outside its one FILES=( ) block"*) ok "W20c a FILES+= append outside the block FAILS W20" ;;
  *) no "W20c a FILES+= append should fail W20 (got: '$W20_MSG')" ;;
esac

# =============================================================================
echo "== X. plan-waves --explain / --lint (parallel-automate/10: read-only; one grammar with the planner) =="
# x_rc <label> <expected rc> <expected stdout (printf %b)> — exact stdout AND exit code.
x_rc() {
  local want; want="$(printf '%b' "$3")"
  if [ "$W_RC" -eq "$2" ] && [ "$W_OUT" = "$want" ]; then ok "$1"; else no "$1 (rc=$W_RC, want $2) got: $(printf '%s' "$W_OUT" | tr '\n' '|') err: $W_ERR"; fi
}
# x_has <label> <line> — W_OUT contains <line> as a whole line.
x_has() { if grep -qxF -- "$2" <<<"$W_OUT"; then ok "$1"; else no "$1 — missing line '$2' in: $(printf '%s' "$W_OUT" | tr '\n' '|')"; fi; }

# X1 every --explain reason shape, each on a fixture that produces it (AC-2), stdout byte-for-byte.
rm -rf "$W_T/q"
w_item q/01-a.md none 'a/'; w_item q/02-b.md none 'a/b.sh'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: declared conflict names the item and the contained path" 0 'wave 1: q/01-a.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  conflicts with q/01-a.md on a/b.sh (declared)'
printf 'q/01-s1.md\nq/02-s2.md\n' > "$W_T/list"
w_run "$W_C" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: companion conflict names the rule's when" 0 'wave 1: q/01-s1.md\nwave 2: q/02-s2.md\nexplain q/02-s2.md (wave 2):\n  conflicts with q/01-s1.md on x/skills/SKILLS_INDEX.md (companion: x/skills/*/SKILL.md)'
rm -rf "$W_T/q" "$W_T/other"
w_item q/01-a.md '../other/05-y.md' 'a'; w_item q/02-b.md '1' 'b'; w_item other/05-y.md none 'y'
w_list q/01-a.md q/02-b.md other/05-y.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: depends on <item> (display path of the in-set dependency)" 0 'wave 1: other/05-y.md\nwave 2: q/01-a.md\nwave 3: q/02-b.md\nexplain q/01-a.md (wave 2):\n  depends on other/05-y.md\nexplain q/02-b.md (wave 3):\n  depends on q/01-a.md'
w_alone missing -; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: runs alone: Touches unknown (missing)" 0 'wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  runs alone: Touches unknown (missing)'
w_alone bullet '- b/x.sh'; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: runs alone: Touches unknown (unparsable line <N>: \"<text>\"), N 1-based in the item file" 0 'wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  runs alone: Touches unknown (unparsable line 7: "- b/x.sh")'
w_alone unknown 'unknown'; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: runs alone: Touches unknown (declared unknown)" 0 'wave 1: q/01-a.md q/03-c.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  runs alone: Touches unknown (declared unknown)'
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md - 'b'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: runs alone: Depends on missing ⇒ depends on every earlier item" 0 'wave 1: q/01-a.md\nwave 2: q/02-b.md\nexplain q/02-b.md (wave 2):\n  runs alone: Depends on missing ⇒ depends on every earlier item'
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md none 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 2 --explain
x_rc "X1 explain: wave <w> full (--max <N>)" 0 'wave 1: q/01-a.md q/02-b.md\nwave 2: q/03-c.md\nexplain q/03-c.md (wave 2):\n  wave 1 full (--max 2)'
rm -rf "$W_T/q"; w_item q/01-a.md none -; w_item q/02-b.md none 'b'; w_item q/03-c.md none 'c'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
x_rc "X1 explain: wave <w> runs <item> alone (Touches unknown)" 0 'wave 1: q/01-a.md\nwave 2: q/02-b.md q/03-c.md\nexplain q/02-b.md (wave 2):\n  wave 1 runs q/01-a.md alone (Touches unknown)\nexplain q/03-c.md (wave 2):\n  wave 1 runs q/01-a.md alone (Touches unknown)'
# Every reason of a multi-wave item, each distinct reason once (a conflict in wave 1, a dependency in wave 2).
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md none 'b'; w_item q/03-c.md '02' 'a/x'
w_list q/01-a.md q/02-b.md q/03-c.md; w_run "$W_T" "$H" "$W_T/list" --max 1 --explain
x_rc "X1 explain: every reason across earlier waves, each once" 0 'wave 1: q/01-a.md\nwave 2: q/02-b.md\nwave 3: q/03-c.md\nexplain q/02-b.md (wave 2):\n  wave 1 full (--max 1)\nexplain q/03-c.md (wave 3):\n  depends on q/02-b.md'

# X2 --explain leaves the wave/blocked lines and the exit codes alone (AC-1/AC-2): its stdout up to
#    the first `explain ` line equals the default run on the same input; errors stay exit 1 + empty stdout.
x_same() {  # <label> <root> <input> <max>
  local base
  w_run "$2" "$H" "$3" --max "$4"; base="$W_OUT"
  w_run "$2" "$H" "$3" --max "$4" --explain
  if [ "$W_RC" -eq 0 ] && [ "$(printf '%s\n' "$W_OUT" | awk '/^explain /{exit} {print}')" = "$base" ]; then ok "$1"; else no "$1 (rc=$W_RC) base: $(printf '%s' "$base" | tr '\n' '|') explain: $(printf '%s' "$W_OUT" | tr '\n' '|')"; fi
}
rm -rf "$W_T/q"
w_item q/01-a.md none 'p/'; w_item q/02-b.md none 'r/'; w_item q/03-c.md none 'p/x.sh'; w_item q/04-d.md none 'r/y.sh'; w_item q/05-e.md '01' 's/'
w_list q/01-a.md q/02-b.md q/03-c.md q/04-d.md q/05-e.md
x_same "X2 five-item fixture: --explain prefix == default output" "$W_T" "$W_T/list" 3
w_item q/06-f.md '07' 'f'; w_item q/07-g.md none 'g' 'parked (waits)'
w_list q/01-a.md q/02-b.md q/06-f.md q/03-c.md
x_same "X2 a blocked line is unchanged under --explain" "$W_T" "$W_T/list" 2
x_has "X2 blocked item keeps its blocked line under --explain" 'blocked q/06-f.md: depends on parked 07'
case "$W_OUT" in *"explain q/06-f.md"*) no "X2 a blocked item got an explain block" ;; *) ok "X2 a blocked item gets no explain block (its blocked line is its reason)" ;; esac
rm -rf "$W_T/q"; w_item q/01-a.md '02' 'a'; w_item q/02-b.md '01' 'b'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3 --explain
w_fails "X2 --explain on a cycle ⇒ exit 1, empty stdout" 'plan-waves: dependency cycle: q/01-a.md q/02-b.md'
w_run "$W_T" "$H" "$W_T/list" --explain; w_fails "X2 --explain still needs --max" 'usage:'
w_run "$W_T" "$H" "$W_T/list" --max 2 --explain --lint; w_fails "X2 --explain with --lint ⇒ usage" '--explain and --lint are separate modes'

# X2b --explain state does not leak across calls in ONE shell process: the helper's functions are
#     sourced (its trailing `main "$@"` dispatch line dropped, `main` itself untouched), plan_waves
#     runs --explain and then a default call, and the second call must equal a fresh default run
#     byte-for-byte with no `explain ` line (a global _PW_EXPLAIN set by call 1 and never reset fails it).
rm -rf "$W_T/q"; w_item q/01-a.md none 'a/'; w_item q/02-b.md none 'a/b.sh'
w_list q/01-a.md q/02-b.md
w_run "$W_T" "$H" "$W_T/list" --max 3; X2B_FRESH="$W_OUT"
mkdir -p "$W_T/x2b-tmp"
X2B_RC=0
X2B_OUT="$(TMPDIR="$W_T/x2b-tmp" bash -c '
  grep -qx "main \"\$@\"" "$1" || { echo "no trailing main dispatch line" >&2; exit 3; }
  source <(sed "/^main \"\\\$@\"\$/d" "$1")
  plan_waves "$2" --root "$3" --max 3 --explain > /dev/null
  plan_waves "$2" --root "$3" --max 3
' _ "$H" "$W_T/list" "$W_T" 2>"$W_T/err")" || X2B_RC=$?
if [ "$X2B_RC" -eq 0 ] && [ -n "$X2B_FRESH" ] && [ "$X2B_OUT" = "$X2B_FRESH" ] && ! grep -q '^explain ' <<<"$X2B_OUT"; then
  ok "X2b a default plan_waves call after an --explain call in the same shell is byte-identical to a fresh default run"
else
  no "X2b --explain leaked into a later default call (rc=$X2B_RC) got: $(printf '%s' "$X2B_OUT" | tr '\n' '|') fresh: $(printf '%s' "$X2B_FRESH" | tr '\n' '|') err: $(cat "$W_T/err")"
fi
rm -rf "$W_T/x2b-tmp"

# X3 --lint: every malformed shape flagged with its 1-based line, the exact text and the reason (AC-3/AC-4).
#    Single-item input; the w_item layout puts the Depends on body on line 4, the Touches body on line 7.
x_lint_t() {  # <label> <Touches body> <expected Touches verdict> <expected rc>
  rm -rf "$W_T/q"; w_item q/02-b.md none "$2"
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  local runs="0 of 1 items will run alone: none"
  case "$3" in ok) ;; *) runs="1 of 1 items will run alone: $W_T/q/02-b.md" ;; esac
  x_rc "$1" "$4" "$W_T/q/02-b.md: Touches $3; Depends on ok\n$runs\n0 of 1 items depend on every earlier item: none"
}
x_lint_t "X3 lint: a path list is ok (exit 0)" 'b/x.sh\nb/dir/' ok 0
x_lint_t "X3 lint: a sole unknown is ok (declared unknown) and does NOT set exit 1" 'unknown' 'ok (declared unknown)' 0
x_lint_t "X3 lint: parenthetical '(only if a test exposes a defect)' flagged" '(only if a test exposes a defect)' 'line 7: "(only if a test exposes a defect)" — parenthetical/prose' 1
x_lint_t "X3 lint: '(part B)' flagged" 'b/x.sh (part B)' 'line 7: "b/x.sh (part B)" — parenthetical/prose' 1
x_lint_t "X3 lint: comma list 'a, b' flagged" 'a, b' 'line 7: "a, b" — comma list' 1
x_lint_t "X3 lint: '- ' bullet flagged" '- b/x.sh' 'line 7: "- b/x.sh" — "- " bullet' 1
x_lint_t "X3 lint: backticks flagged" '`b/x.sh`' 'line 7: "`b/x.sh`" — backticks' 1
x_lint_t "X3 lint: prose flagged" 'b/x.sh and friends' 'line 7: "b/x.sh and friends" — parenthetical/prose' 1
x_lint_t "X3 lint: leading / flagged" '/b/x.sh' 'line 7: "/b/x.sh" — leading /' 1
x_lint_t "X3 lint: '..' segment flagged" 'b/../x' 'line 7: "b/../x" — . or .. segment' 1
x_lint_t "X3 lint: './' segment flagged" './b/x.sh' 'line 7: "./b/x.sh" — . or .. segment' 1
x_lint_t "X3 lint: '//' flagged" 'b//x.sh' 'line 7: "b//x.sh" — //' 1
x_lint_t "X3 lint: a glob character flagged" 'b/*.sh' 'line 7: "b/*.sh" — character outside [A-Za-z0-9._/@+-]' 1
x_lint_t "X3 lint: trailing whitespace flagged" 'b/x.sh ' 'line 7: "b/x.sh " — leading/trailing whitespace' 1
x_lint_t "X3 lint: unknown mixed with paths flagged on the unknown line" 'b/x.sh\nunknown' 'line 8: "unknown" — unknown mixed with paths' 1
x_lint_t "X3 lint: empty section flagged on its heading" '' 'line 6: "## Touches" — empty section' 1
x_lint_t "X3 lint: duplicated section flagged on the second heading" 'b/x.sh\n\n## Touches\nb/y.sh' 'line 9: "## Touches" — duplicated section' 1
x_lint_t "X3 lint: several bad lines ⇒ the first, plus a count" '- a\n- b' 'line 7: "- a" — "- " bullet (+1 more)' 1
rm -rf "$W_T/q"; w_item q/02-b.md none -
w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
x_rc "X3 lint: missing Touches ⇒ missing section, exit 1" 1 "$W_T/q/02-b.md: Touches missing section; Depends on ok\n1 of 1 items will run alone: $W_T/q/02-b.md\n0 of 1 items depend on every earlier item: none"
x_lint_d() {  # <label> <Depends body|-> <expected Depends verdict> <expected rc>
  rm -rf "$W_T/q"; w_item q/02-b.md "$2" 'b/x.sh'
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  local dep="0 of 1 items depend on every earlier item: none"
  case "$3" in ok) ;; *) dep="1 of 1 items depend on every earlier item: $W_T/q/02-b.md" ;; esac
  x_rc "$1" "$4" "$W_T/q/02-b.md: Touches ok; Depends on $3\n0 of 1 items will run alone: none\n$dep"
}
x_lint_d "X3 lint: valid Touches and NO Depends on ⇒ exit 1" - 'missing section' 1
x_lint_d "X3 lint: Depends on ids and paths are ok" '03\n../other/01-x.md' ok 0
x_lint_d "X3 lint: Depends on none mixed with ids" 'none\n03' 'line 4: "none" — none mixed with ids' 1
x_lint_d "X3 lint: Depends on none repeated" 'none\nnone' 'line 5: "none" — none repeated' 1
x_lint_d "X3 lint: Depends on prose ⇒ not an id or *.md path" 'item 03 (part B)' 'line 4: "item 03 (part B)" — not an id or *.md path' 1
x_lint_d "X3 lint: Depends on 4-digit id ⇒ not an id or *.md path" '0003' 'line 4: "0003" — not an id or *.md path' 1
x_lint_d "X3 lint: Depends on empty section" '' 'line 3: "## Depends on" — empty section' 1
x_lint_d "X3 lint: Depends on duplicated" 'none\n\n## Depends on\nnone' 'line 6: "## Depends on" — duplicated section (+1 more)' 1
# Directory input = what the folder intake would enqueue (resolve_folder: done / proposed / parked skipped).
rm -rf "$W_T/q"
w_item q/01-a.md none 'a'; w_item q/02-b.md - 'b'; w_item q/03-c.md none 'c' 'done'; w_item q/04-d.md none 'd' 'proposed'
w_run "$W_T" "$H" "$W_T/q" --lint
x_rc "X3 lint: directory input lints exactly the resolve_folder set; one line per item + two count lines; exit 1" 1 "$W_T/q/01-a.md: Touches ok; Depends on ok\n$W_T/q/02-b.md: Touches ok; Depends on missing section\n0 of 2 items will run alone: none\n1 of 2 items depend on every earlier item: $W_T/q/02-b.md"
w_run "$W_T" "$H" "$W_T/q/" --lint --max 0
[ "$W_RC" -eq 1 ] && [ -n "$W_OUT" ] && ok "X3 lint: --max is ignored (even an invalid one) — lint never needs it" || no "X3 lint with --max 0: rc=$W_RC out='$W_OUT' err=$W_ERR"
# Item-list and run-file inputs resolve the plan set exactly as the planner does.
w_list q/01-a.md
w_run "$W_T" "$H" "$W_T/list" --lint
x_rc "X3 lint: item-list input (display = the list line)" 0 'q/01-a.md: Touches ok; Depends on ok\n0 of 1 items will run alone: none\n0 of 1 items depend on every earlier item: none'
printf '# Automate Run: automate-test\n## Status: running\n## Queue\n- [x] q/03-c.md\n- [ ] q/02-b.md\n## Current\n' > "$W_T/run-lint.md"
w_run "$W_T" "$H" "$W_T/run-lint.md" --lint
x_rc "X3 lint: run-file input = its unchecked Queue rows" 1 'q/02-b.md: Touches ok; Depends on missing section\n0 of 1 items will run alone: none\n1 of 1 items depend on every earlier item: q/02-b.md'
w_list q/01-a.md q/09-gone.md; w_run "$W_T" "$H" "$W_T/list" --lint
w_fails "X3 lint: an item that names no file ⇒ exit 1, empty stdout" 'plan-waves: item not found: q/09-gone.md'
w_run "$W_T" "$H" "$W_T/nope.md" --lint; w_fails "X3 lint: missing input ⇒ usage" 'usage:'

# X4 one grammar (AC-5): on every shape, lint `ok`/`ok (declared unknown)` vs failure agrees with
#    what the planner reads — Touches known ⇔ the middle item shares wave 1 with two disjoint items;
#    Depends on parsed ⇔ the second item shares wave 1 (its dependency 03 is out of the plan set and done).
x_agree_n=0
while IFS='|' read -r x_lbl x_body; do
  [ -n "$x_lbl" ] || continue
  w_alone "$x_lbl" "$x_body"; x_plan="$W_OUT"
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  x_v="$(printf '%s\n' "$W_OUT" | sed -n '1s/^.*: Touches \(.*\); Depends on .*$/\1/p')"
  if [ "$x_plan" = "wave 1: q/01-a.md q/02-b.md q/03-c.md" ]; then x_known=1; else x_known=0; fi
  if [ "$x_v" = ok ]; then x_lok=1; else x_lok=0; fi
  if [ "$x_known" -eq "$x_lok" ] && [ -n "$x_v" ]; then x_agree_n=$((x_agree_n+1)); else no "X4 Touches '$x_lbl': planner known=$x_known but lint says '$x_v'"; fi
done <<'SHAPES'
path|b/x.sh
dir|b/
two|b/x.sh\nb/y.sh
blank-lines|b/x.sh\n\nb/y.sh
dot-name|b/.x.sh
unknown|unknown
unknown-twice|unknown\nunknown
backtick|`b/x.sh`
glob|b/*.sh
pipe|a|b
prose|b/x.sh and friends
bullet|- b/x.sh
paren|(only if a test exposes a defect)
comma|a, b
mixed|b/x.sh\nunknown
empty|
dotdot|b/../x
dot|.
dot-lead|./b/x.sh
lead-slash|/b/x.sh
double-slash|b//x.sh
trailing-space|b/x.sh\0040
duplicate|b/x.sh\n\n## Touches\nb/y.sh
fence|b/x.sh\n```\nb/y.sh\n```
SHAPES
[ "$x_agree_n" -eq 24 ] && ok "X4 lint ok ⇔ planner known on all 24 Touches shapes" || no "X4 Touches agreement on $x_agree_n of 24 shapes"
x_agree_n=0
while IFS='|' read -r x_lbl x_body; do
  [ -n "$x_lbl" ] || continue
  rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md "$x_body" 'b'; w_item q/03-c.md none 'c' 'done'
  w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3; x_plan="$W_OUT"
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  x_v="$(printf '%s\n' "$W_OUT" | sed -n '1s/^.*; Depends on \(.*\)$/\1/p')"
  if [ "$x_plan" = "wave 1: q/01-a.md q/02-b.md" ]; then x_known=1; else x_known=0; fi
  if [ "$x_v" = ok ]; then x_lok=1; else x_lok=0; fi
  if [ "$x_known" -eq "$x_lok" ] && [ -n "$x_v" ]; then x_agree_n=$((x_agree_n+1)); else no "X4 Depends '$x_lbl': planner parsed=$x_known ($x_plan) but lint says '$x_v'"; fi
done <<'SHAPES'
none|none
id|03
id-1|3
path|03-c.md
rel-path|../q/03-c.md
none-mixed|none\n03
none-twice|none\nnone
prose|item 03 (part B)
four-digit|0003
bullet|- 03
empty|
fence|03\n```\n03\n```
SHAPES
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md - 'b'
w_list q/01-a.md q/02-b.md; w_run "$W_T" "$H" "$W_T/list" --max 3; x_plan="$W_OUT"
w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
case "$x_plan|$W_OUT" in "wave 1: q/01-a.md"*"Depends on missing section"*) x_agree_n=$((x_agree_n+1)) ;; *) no "X4 Depends 'missing': $x_plan / $W_OUT" ;; esac
[ "$x_agree_n" -eq 13 ] && ok "X4 lint ok ⇔ planner parsed on all 13 Depends on shapes" || no "X4 Depends agreement on $x_agree_n of 13 shapes"

# X5 read-only: --lint and --explain write nothing in the fixture tree; the only git call is rev-parse.
rm -rf "$W_T/q"; w_item q/01-a.md none 'a'; w_item q/02-b.md - 'b'; w_list q/01-a.md q/02-b.md
for x_mode in "--lint" "--max 3 --explain"; do
  : > "$W_T/spy/calls"
  w_before="$(cd "$W_T" && find q list -print | env LC_ALL=C sort | xargs ls -ld 2>/dev/null | awk '{ print $5, $NF }')"
  # shellcheck disable=SC2086 # word-split on purpose: the mode's flags
  W_RC=0; W_OUT="$(cd "$W_T" && PATH="$W_T/spy:$PATH" bash "$H" plan-waves list $x_mode 2>/dev/null)" || W_RC=$?
  w_after="$(cd "$W_T" && find q list -print | env LC_ALL=C sort | xargs ls -ld 2>/dev/null | awk '{ print $5, $NF }')"
  [ -n "$W_OUT" ] && [ "$(cat "$W_T/spy/calls")" = "git rev-parse --show-toplevel" ] && [ "$w_before" = "$w_after" ] \
    && ok "X5 plan-waves list $x_mode: read-only (tree unchanged, only git rev-parse, no gh)" \
    || no "X5 $x_mode: rc=$W_RC calls=$(tr '\n' '|' < "$W_T/spy/calls") out='$W_OUT'"
done

# X6 MUTATION CONTROL (AC-4): a helper copy whose ONE grammar line also accepts `(`, `)` and spaces
#    must turn X3's parenthetical assertion red — the lint verdict comes from that line, not a copy.
sed '/# PW_TOUCHES_GRAMMAR/s|!/^\[A-Za-z0-9._\\/@+-\]+\$/|!/^[A-Za-z0-9._\\/@+() -]+$/|' "$H" > "$W_T/mut-paren.sh"
if [ -s "$W_T/mut-paren.sh" ] && ! cmp -s "$H" "$W_T/mut-paren.sh" && bash -n "$W_T/mut-paren.sh"; then
  rm -rf "$W_T/q"; w_item q/02-b.md none '(only if a test exposes a defect)'
  w_run "$W_T" "$W_T/mut-paren.sh" "$W_T/q/02-b.md" --lint
  case "$W_OUT" in
    *"Touches ok; "*) ok "X6 MUTATION CONTROL: grammar-accepts-parenthetical mutant turns X3's parenthetical assertion red (lint now says ok, rc=$W_RC)" ;;
    *) no "X6 mutation control stayed green — the X3 parenthetical assertion is vacuous: $W_OUT" ;;
  esac
  w_run "$W_T" "$H" "$W_T/q/02-b.md" --lint
  x_has "X6 mutation control: the REAL helper still flags it" "$W_T/q/02-b.md: Touches line 7: \"(only if a test exposes a defect)\" — parenthetical/prose; Depends on ok"
else no "X6 mutation control inconclusive: mutant empty, identical or not valid bash"; fi

# X7 GRAMMAR DRIFT: the Touches path grammar is hand-copied in three places that share no code —
#    the PW_TOUCHES_GRAMMAR line (this helper's --lint), PATH_TOK / BAD_SEG beside touches_of in
#    automate-dismissed.sh, and vt_touches in propose-from-verify.sh. One token set, every token's file
#    created under a fixture root (so only the grammar can reject it), runs through all three; each must
#    accept/reject exactly as the expected column. Tokens stay inside the SHARED grammar: the two
#    extractors' own extra rules (needs `/` or `.`, no trailing `/`, trailing `.` stripped) are not
#    exercised. The extractor copies are run straight out of their scripts (sed-extracted), never re-typed.
X7_R="$W_T/x7"; rm -rf "$X7_R"
x7_tokens='src/a.ts|1 @scope/x.ts|1 -dash/x.ts|1 a+b/c_d.v1.md|1 /abs/x.ts|0 a//b.ts|0 ./c.ts|0 d/../c.ts|0 d/./c.ts|0 e/f~g.ts|0 e/f$g.ts|0'
for x7_p in src/a.ts @scope/x.ts -dash/x.ts a+b/c_d.v1.md abs/x.ts a/b.ts c.ts d/c.ts 'e/f~g.ts' 'e/f$g.ts'; do
  mkdir -p "$X7_R/$(dirname -- "$x7_p")"; : > "$X7_R/$x7_p"
done
X7_PY="$(sed -n '/^PATH_TOK = re.compile/,/^    return found$/p' "$HERE/automate-dismissed.sh")"
X7_SH="$(sed -n '/^vt_touches() {$/,/^}$/p' "$HERE/propose-from-verify.sh")"
if [ -z "$X7_PY" ] || ! grep -q '^def touches_of' <<<"$X7_PY" || [ -z "$X7_SH" ]; then
  no "X7 drift test could not extract the grammar copies (PATH_TOK..touches_of / vt_touches moved?)"
else
  for x7_e in $x7_tokens; do
    x7_t="${x7_e%|*}"; x7_want="${x7_e#*|}"
    rm -rf "$W_T/q"; w_item q/02-b.md none "$x7_t"
    w_run "$X7_R" "$H" "$W_T/q/02-b.md" --lint
    case "$W_OUT" in *": Touches ok; "*) x7_awk=1 ;; *) x7_awk=0 ;; esac
    x7_py="$(X7_CODE="$X7_PY" python3 -c '
import os, re, sys
repo_root = sys.argv[1]
exec(os.environ["X7_CODE"])
print(1 if sys.argv[2] in touches_of({"source": sys.argv[2], "finding": ""}) else 0)' "$X7_R" "$x7_t" 2>&1)"
    x7_sh="$(VT_ROOT="$X7_R" bash -c 'eval "$1"; grep -qxF -- "$2" < <(vt_touches "$2") && echo 1 || echo 0' _ "$X7_SH" "$x7_t" 2>&1)"
    if [ "$x7_awk$x7_py$x7_sh" = "$x7_want$x7_want$x7_want" ]; then
      ok "X7 grammar drift: '$x7_t' accepted=$x7_want by all three copies"
    else
      no "X7 grammar drift on '$x7_t' (want $x7_want): PW_TOUCHES_GRAMMAR=$x7_awk touches_of=$x7_py vt_touches=$x7_sh"
    fi
  done
fi

# W-AS24 (automate-speed/24): `--verbose` is a no-op in every mode — the default and `--verbose` stdout
# both equal the exact-bytes goldens captured by running the PRE-change plan-waves on the committed
# fixture (fixtures/terse-output/plan-waves/: root/ = the items + list, <mode>.golden = stdout); the
# `--touches` bytes lane-readiness reads stay unchanged.
W_G="$HERE/fixtures/terse-output/plan-waves"
for w_v in "" --verbose; do
  for w_m in "max|$W_G/root/list|--max 2" "lint|$W_G/root/list|--lint" "touches|$W_G/root/q/04-d.md|--touches" "explain|$W_G/root/list|--max 2 --explain"; do
    w_mn="${w_m%%|*}"; w_in="${w_m#*|}"; w_args="${w_in#*|}"; w_in="${w_in%%|*}"
    # shellcheck disable=SC2086  # w_args / w_v are word lists on purpose
    w_run "$W_G/root" "$H" "$w_in" $w_args $w_v
    if [ "$W_RC" -eq 0 ] && [ -s "$W_G/$w_mn.golden" ] && [ "$W_OUT" = "$(cat "$W_G/$w_mn.golden")" ]; then
      ok "W-AS24 plan-waves --$w_mn ${w_v:-(default)} equals the pre-change golden"
    else
      no "W-AS24 plan-waves --$w_mn ${w_v:-(default)} differs from $w_mn.golden (rc=$W_RC): $(printf '%s' "$W_OUT" | tr '\n' '|') err: $W_ERR"
    fi
  done
done
rm -rf "$W_T"

