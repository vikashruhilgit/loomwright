# =============================================================================
echo "== H. reconcile-status (queue-hygiene/01: dry-run-default requirement Status reconciler) =="

# rs_key <s> — the stub's filename-safe key (mirrors the stub script's own key()).
rs_key() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }
# rs_skey <rel> — the key of the term reconcile-status SEARCHES for <rel>: the
# short ref (no `.supervisor/requirements/` prefix, no `.md`), because GitHub
# search does not find a full requirement path (PR #484).
rs_skey() { local r="${1#.supervisor/requirements/}"; rs_key "${r%.md}"; }

# rs_stub_bin <dir> — a gh stub keyed on `pr list --search <term>` and
# `pr view <url>`, reading canned JSON from $GH_STUB_DIR/list-<key>.json /
# view-<key>.json (absent list ⇒ "[]", absent view ⇒ exit 1), plus `api …
# repos/<o>/<r>/pulls/<n>/files` (the >100-file diff fallback) from
# api-<key>.txt, one path per line (absent ⇒ exit 1). Dedicated to
# this section (not make_stub_bin) because reconcile-status's evidence-lookup
# needs TWO gh verbs discriminated by argument, not one fixed response file.
rs_stub_bin() {
  local bin="$1"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
set -u
key() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '_'; }
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "list" ]; then
  shift 2; term=""
  while [ "$#" -gt 0 ]; do case "$1" in --search) term="${2:-}"; shift 2 ;; *) shift ;; esac; done
  f="$GH_STUB_DIR/list-$(key "$term").json"
  [ -f "$f" ] && cat "$f" || printf '[]'
  exit 0
fi
if [ "${1:-}" = "pr" ] && [ "${2:-}" = "view" ]; then
  url="${3:-}"
  f="$GH_STUB_DIR/view-$(key "$url").json"
  [ -f "$f" ] && cat "$f" || exit 1
  exit 0
fi
if [ "${1:-}" = "api" ]; then
  ep=""
  for a in "$@"; do case "$a" in repos/*) ep="$a" ;; esac; done
  f="$GH_STUB_DIR/api-$(key "$ep").txt"
  [ -f "$f" ] && cat "$f" || exit 1
  exit 0
fi
exit 0
STUB
  chmod +x "$bin/gh"
}

# rs_repo — fixture root per AC-1/2/3/5/9: (a) done, (b) pending+merged+cited,
# (c) pending+open, (d) operator-run/, (e) 00-index. Returns "<repo>\t<rel_b>".
RS_URL="https://github.com/acme/widgets/pull/42"
rs_repo() {
  local r rq relb
  r="$(mktemp -d)"
  mkdir -p "$r/.supervisor/requirements/qh/operator-run" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/bin" "$r/ghstub"
  rq="$r/.supervisor/requirements/qh"
  printf '# a\n\n## Status: done (PR #1, merge abcdef1)\n' > "$rq/01-a-done.md"
  relb=".supervisor/requirements/qh/02-b-merged.md"
  printf '# b\n\nSome prose.\n\n## Status: pending\n' > "$r/$relb"
  printf '# c\n\n## Status: pending\n' > "$rq/03-c-open.md"
  printf '# d\n\n## Status: pending\n' > "$rq/operator-run/04-d.md"
  printf '# index\n' > "$rq/00-index.md"
  rs_stub_bin "$r/bin"
  jq -n --arg url "$RS_URL" '[{url:$url}]' > "$r/ghstub/list-$(rs_skey "$relb").json"
  jq -n --arg rel "$relb" --arg url "$RS_URL" \
    '{state:"MERGED",mergedAt:"2026-09-01T00:00:00Z",number:42,body:("Ships "+$rel),mergeCommit:{oid:"abcdef1234567890"},headRefName:"feature/b",changedFiles:1,files:[{path:"src/b.sh"}]}' \
    > "$r/ghstub/view-$(rs_key "$RS_URL").json"
  printf '[]' > "$r/ghstub/list-$(rs_skey ".supervisor/requirements/qh/03-c-open.md").json"
  printf '%s\t%s' "$r" "$relb"
}
rs_run() {
  # rs_run <repo> <args...> — RUN_OUT / RUN_RC set. RS_H overrides the helper (mutation controls).
  local r="$1"; shift
  RUN_OUT="$(GH_STUB_DIR="$r/ghstub" PATH="$r/bin:$PATH" LOOMWRIGHT_GH_BIN=gh bash "${RS_H:-$H}" reconcile-status "$@" 2>/dev/null)"; RUN_RC=$?
}
# rs_mutant <exact helper line> <replacement> — a copy of the helper with that ONE
# line replaced; RSM names the copy's dir. Returns 1 when the line is not found.
rs_mutant() {
  RSM="$(mktemp -d)"; cp "$HERE"/*.sh "$HERE"/*.py "$RSM/" 2>/dev/null; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$RSM/"
  OLD="$1" NEW="$2" awk '$0 == ENVIRON["OLD"] { print ENVIRON["NEW"]; next } { print }' "$H" > "$RSM/automate-helpers.sh"
  ! cmp -s "$H" "$RSM/automate-helpers.sh"
}

# H1. AC-1: dry run over the 5-file fixture prints exactly ONE plan line (b), writes nothing.
IFS=$'\t' read -r R RELB <<<"$(rs_repo)"
BEFORE="$(cd "$R" && find .supervisor/requirements -type f -exec sh -c 'echo "$1" $(cksum < "$1")' _ {} \; | sort)"
rs_run "$R" "$R/.supervisor/requirements/qh"
nplan="$(printf '%s\n' "$RUN_OUT" | grep -c '^plan	')"
AFTER="$(cd "$R" && find .supervisor/requirements -type f -exec sh -c 'echo "$1" $(cksum < "$1")' _ {} \; | sort)"
if [ "$nplan" = "1" ] && grep -qF "plan	$RELB	done (PR #42, merge abcdef1)" < <(printf '%s\n' "$RUN_OUT") && [ "$BEFORE" = "$AFTER" ]; then
  ok "H1 AC-1: dry run prints exactly one plan line for (b), root untouched (diff -r equivalent)"
else
  no "H1 AC-1 wrong (nplan=$nplan out='$RUN_OUT' unchanged=$([ "$BEFORE" = "$AFTER" ] && echo y || echo n))"
fi
rm -rf "$R"

# H2. AC-2: --apply stamps (b) ONLY — §6 shape byte-for-byte, stale trailing
#     '## Status: pending' removed, is_done() true for (b) only.
IFS=$'\t' read -r R RELB <<<"$(rs_repo)"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
B="$R/$RELB"
if grep -qF '## Status: done (PR #42, merge abcdef1)' "$B" \
   && grep -qE '^- \*\*Completed:\*\* [0-9]{4}-' "$B" \
   && grep -qF -- '- **PR:** '"$RS_URL" "$B" \
   && ! grep -qE '^## Status:[[:space:]]*pending[[:space:]]*$' "$B"; then
  ok "H2 AC-2: (b) stamped byte-shape 'done (PR #n, merge sha7)' + Completed/Brief/PR, stale pending line removed"
else
  no "H2 AC-2 stamp shape wrong: $(cat "$B")"
fi
if grep -qE '^## Status:[[:space:]]*done\b' "$B" && ! grep -qE '^## Status:[[:space:]]*done\b' "$R/.supervisor/requirements/qh/03-c-open.md"; then
  ok "H2 is_done()-shape true for (b) only (c stays pending)"
else
  no "H2 (c) unexpectedly stamped"
fi
rm -rf "$R"

# H3. AC-3 mutation control: delete the path citation from (b)'s PR-body fixture ⇒ no plan line, no stamp.
IFS=$'\t' read -r R RELB <<<"$(rs_repo)"
jq -n --arg url "$RS_URL" '{state:"MERGED",mergedAt:"2026-09-01T00:00:00Z",number:42,body:"unrelated prose, no path here",mergeCommit:{oid:"abcdef1234567890"},headRefName:"feature/b",changedFiles:1,files:[{path:"src/b.sh"}]}' \
  > "$R/ghstub/view-$(rs_key "$RS_URL").json"
rs_run "$R" "$R/.supervisor/requirements/qh"
DRY_OUT="$RUN_OUT"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if [ -z "$DRY_OUT" ] && ! grep -qE '^## Status:[[:space:]]*done\b' "$R/$RELB"; then
  ok "H3 AC-3 mutation control: citation deleted ⇒ no plan line, no stamp"
else
  no "H3 mutation control failed (dry='$DRY_OUT' apply_status=$(grep '^## Status' "$R/$RELB"))"
fi
rm -rf "$R"

# H4. AC-4: a run-file `# abandoned:` Queue row stamps done_with_escalation;
#     a row without the marker stamps nothing. The abandoned item is STATUS-LESS: a first-line
#     `pending`/`ready` item is never stamped from a Queue row (owner decision D-conflict-1, H10).
R="$(mktemp -d)"
mkdir -p "$R/.supervisor/requirements/qh" "$R/.supervisor/automate" "$R/.supervisor/jobs/done" "$R/bin" "$R/ghstub"
rs_stub_bin "$R/bin"
printf '# ab\n' > "$R/.supervisor/requirements/qh/05-abandoned.md"
printf '# nope\n\n## Status: pending\n' > "$R/.supervisor/requirements/qh/06-not-abandoned.md"
ABROW='- [x] .supervisor/requirements/qh/05-abandoned.md  # abandoned: owner dropped track 2026-09-01'
{
  printf '# run\n## Status: running\n## Queue\n'
  printf '%s\n' "$ABROW"
  printf -- '- [x] .supervisor/requirements/qh/06-not-abandoned.md  # skipped: unrelated\n'
  printf '## Progress\n'
} > "$R/.supervisor/automate/run1.md"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if grep -qF -- "## Status: done_with_escalation — ABANDONED ($ABROW)" "$R/.supervisor/requirements/qh/05-abandoned.md" \
   && ! grep -qE '^## Status:[[:space:]]*done' "$R/.supervisor/requirements/qh/06-not-abandoned.md"; then
  ok "H4 AC-4: abandoned row stamps done_with_escalation verbatim; unmark row stamps nothing"
else
  no "H4 AC-4 wrong (ab=$(grep '^## Status' "$R/.supervisor/requirements/qh/05-abandoned.md") not=$(grep '^## Status' "$R/.supervisor/requirements/qh/06-not-abandoned.md" 2>/dev/null || echo none))"
fi
rm -rf "$R"

# H5. AC-5: never downgrades an existing done file — re-run leaves (a) byte-unchanged.
IFS=$'\t' read -r R RELB <<<"$(rs_repo)"
A="$R/.supervisor/requirements/qh/01-a-done.md"
BEFORE_A="$(cksum < "$A")"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
AFTER_A="$(cksum < "$A")"
if [ "$BEFORE_A" = "$AFTER_A" ]; then
  ok "H5 AC-5: an already-done file is byte-unchanged after a --apply pass"
else
  no "H5 AC-5: done file (a) was modified"
fi
rm -rf "$R"

# H5b. automate-followups/36 B-B: under a HOME-LIKE root (`…/home/alice/proj`) no printed row and no
#      written line carries an absolute path — the `- **Brief:**` line --apply stamps is the
#      repo-relative done/ brief, and an abandoned row's run-file field is repo-relative. (The
#      meta-sync home_path scrub refused the old absolute forms on lane metadata pushes.)
rs_home_repo() { # prints the repo root: (b) merged+cited WITH a done/ brief, plus an abandoned Queue row
  local base r relb
  base="$(mktemp -d)"; r="$base/home/alice/proj"
  mkdir -p "$r/.supervisor/requirements/qh" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/bin" "$r/ghstub"
  r="$(cd "$r" && pwd -P)"
  relb=".supervisor/requirements/qh/02-b-merged.md"
  printf '# b\n\n## Status: pending\n' > "$r/$relb"
  printf '# Brief\n## Environment\n- **Source requirement:** %s\n' "$relb" > "$r/.supervisor/jobs/done/2026-10-01-b-merged.md"
  printf '# ab\n' > "$r/.supervisor/requirements/qh/05-abandoned.md"   # status-less: D-conflict-1 (H10) never abandons a pending item
  printf '# run\n## Status: running\n## Queue\n- [x] .supervisor/requirements/qh/05-abandoned.md  # abandoned: owner dropped it\n## Progress\n' > "$r/.supervisor/automate/run1.md"
  rs_stub_bin "$r/bin"
  jq -n --arg url "$RS_URL" '[{url:$url}]' > "$r/ghstub/list-$(rs_skey "$relb").json"
  jq -n --arg rel "$relb" --arg url "$RS_URL" \
    '{state:"MERGED",mergedAt:"2026-09-01T00:00:00Z",number:42,body:("Ships "+$rel),mergeCommit:{oid:"abcdef1234567890"},headRefName:"feature/b",changedFiles:1,files:[{path:"src/b.sh"}]}' \
    > "$r/ghstub/view-$(rs_key "$RS_URL").json"
  printf '%s' "$r"
}
rs_home_check() { # <repo> — 0 iff dry run + --apply print and write no absolute path, with the relative forms present
  local r="$1" dry
  rs_run "$r" "$r/.supervisor/requirements"; dry="$RUN_OUT"
  rs_run "$r" "$r/.supervisor/requirements" --apply
  RSH_OUT="$dry"$'\n'"$RUN_OUT"
  ! grep -qE '/(Users|home)/' <<<"$RSH_OUT" \
    && ! grep -rqE '/(Users|home)/' "$r/.supervisor/requirements" \
    && grep -qxF -- '- **Brief:** .supervisor/jobs/done/2026-10-01-b-merged.md' "$r/.supervisor/requirements/qh/02-b-merged.md" \
    && grep -qF "plan	.supervisor/requirements/qh/05-abandoned.md	done_with_escalation — ABANDONED	.supervisor/automate/run1.md" <<<"$dry" \
    && grep -qF "stamped	.supervisor/requirements/qh/05-abandoned.md	done_with_escalation — ABANDONED	.supervisor/automate/run1.md" <<<"$RUN_OUT"
}
R="$(rs_home_repo)"
if rs_home_check "$R"; then
  ok "H5b B-B: home-like root ⇒ no /Users/ or /home/ path in any printed row or written line; Brief + abandoned run file repo-relative"
else
  no "H5b B-B: out=$(printf '%s' "$RSH_OUT" | tr '\n' '|') brief=$(grep 'Brief:' "$R/.supervisor/requirements/qh/02-b-merged.md")"
fi
rm -rf "${R%/home/alice/proj}"
# Mutation control: the pre-fix writer (absolute done_brief / abandoned run file) turns H5b red.
RSHM="$(mktemp -d)"
sed -e 's/^      printf -- '"'"'- \*\*Brief:\*\* %s\\n'"'"' "\${brief_rel:-unknown}"$/      printf -- '"'"'- **Brief:** %s\\n'"'"' "${done_brief:-unknown}"  # mutant B-B/' \
    -e 's/^    af_rel="\${af#"\$proj_root"\/}" .*$/    af_rel="$af"  # mutant B-B/' "$H" > "$RSHM/automate-helpers.sh"
for e in "$(dirname "$H")"/*; do [ "$(basename "$e")" = automate-helpers.sh ] || ln -s "$e" "$RSHM/$(basename "$e")"; done
if [ "$(grep -c '# mutant B-B' "$RSHM/automate-helpers.sh")" = 2 ] && bash -n "$RSHM/automate-helpers.sh"; then
  R="$(rs_home_repo)"
  if RS_H="$RSHM/automate-helpers.sh" rs_home_check "$R"; then
    no "H5b mutation control REFUTED: the absolute-path writer still passed"
  elif grep -qE '/home/alice/proj/' <<<"$RSH_OUT$(cat "$R/.supervisor/requirements/qh/02-b-merged.md")"; then
    ok "H5b mutation control: the absolute-path writer leaks /home/alice/proj/ — the leg is load-bearing"
  else
    no "H5b mutation control failed for another reason: $(printf '%s' "$RSH_OUT" | tr '\n' '|')"
  fi
  rm -rf "${R%/home/alice/proj}"
else
  no "H5b mutant B-B not built ($(grep -c '# mutant B-B' "$RSHM/automate-helpers.sh") of 2 edits applied)"
fi
rm -rf "$RSHM"

# H6. brief-shipped (stamp-requirement-status.sh's "job landed, ACs unverified" heading) is
#     PROMOTED on the same merged-PR evidence as any other not-done file, and only LISTED (an
#     `info` row, file byte-unchanged) without it (owner decision 2026-10-13, reversing the
#     queue-hygiene/01 "listed, never promoted" non-goal: that early return hid every plain-run
#     requirement from the one recovery path its honest limit names — 27 such files in the
#     owner's checkout). The stamp is APPENDED, the brief-shipped heading never rewritten.
RS_SREL=".supervisor/requirements/qh/07-shipped.md"
RS_SBRIEF=".supervisor/jobs/done/2026-10-01-qh-07-shipped.md"
RS_SURL="https://github.com/acme/widgets/pull/88"
# rs_shipped_repo <state> <headRefName> <body> <files-json> [<extra status line>] — a brief-shipped
# requirement in the byte shape stamp-requirement-status.sh writes, its done/ brief (Source
# requirement pointer + `- **PR:**` Outcome line), and one candidate PR in the given state.
rs_shipped_repo() {
  local r; r="$(mktemp -d)"
  mkdir -p "$r/.supervisor/requirements/qh" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/bin" "$r/ghstub"
  rs_stub_bin "$r/bin"
  {
    printf '# shipped\n\nProse.\n\n## Status: brief-shipped\n'
    printf '\nJob `.supervisor/jobs/done/%s` completed (reconciled from the job lifecycle, not self-reported).\n' "$(basename "$RS_SBRIEF")"
    printf 'Acceptance criteria are NOT machine-verified here — review them before promoting this to `## Status: done`.\n'
    [ -n "${5:-}" ] && printf '\n%s\n' "$5"
  } > "$r/$RS_SREL"
  printf '# Brief\n## Environment\n- **Source requirement:** %s\n\n## Outcome\n- **Status:** completed\n- **PR:** %s\n' \
    "$RS_SREL" "$RS_SURL" > "$r/$RS_SBRIEF"
  jq -n --arg url "$RS_SURL" '[{url:$url}]' > "$r/ghstub/list-$(rs_skey "$RS_SREL").json"
  jq -n --arg st "$1" --arg head "$2" --arg body "$3" --argjson files "$4" \
    '{state:$st,mergedAt:(if $st=="MERGED" then "2026-10-02T00:00:00Z" else null end),number:88,body:$body,mergeCommit:{oid:"0a1b2c3d4e5f6789"},headRefName:$head,changedFiles:($files|length),files:($files|map({path:.}))}' \
    > "$r/ghstub/view-$(rs_key "$RS_SURL").json"
  printf '%s' "$r"
}
RSS_DRY=""; RSS_APPLY=""
RS_SROW_SLUG="$RS_SREL	done (PR #88, merge 0a1b2c3)	head branch 'feature/qh-07-shipped' matches brief slug 'qh-07-shipped'"
RS_SROW_CITE="$RS_SREL	done (PR #88, merge 0a1b2c3)	PR body cites $RS_SREL"
# rs_shipped_promotes <repo> <row-suffix> — 0 iff the dry run prints `plan\t<row>` and writes
# nothing, then --apply prints `stamped\t<row>`, keeps the original bytes as a prefix (heading
# never rewritten), appends the §6 shape so is_done matches, and a re-run is a byte-identical no-op.
rs_shipped_promotes() {
  local r="$1" row="$2" f="$1/$RS_SREL" orig n
  orig="$(cksum < "$f")"; n="$(wc -c < "$f" | tr -d ' ')"
  rs_run "$r" "$r/.supervisor/requirements/qh"; RSS_DRY="$RUN_OUT"
  [ "$RSS_DRY" = "plan	$row" ] && [ "$(cksum < "$f")" = "$orig" ] || return 1
  cp "$f" "$f.orig"
  rs_run "$r" "$r/.supervisor/requirements/qh" --apply; RSS_APPLY="$RUN_OUT"
  [ "$RSS_APPLY" = "stamped	$row" ] || return 1
  [ "$(head -c "$n" "$f" | cksum)" = "$(cksum < "$f.orig")" ] || return 1
  grep -qxF '## Status: brief-shipped' "$f" \
    && grep -qxF '## Status: done (PR #88, merge 0a1b2c3)' "$f" \
    && grep -qE '^- \*\*Completed:\*\* [0-9]{4}-' "$f" \
    && grep -qxF -- "- **Brief:** $RS_SBRIEF" "$f" \
    && grep -qxF -- "- **PR:** $RS_SURL" "$f" \
    && grep -qE '^## Status:[[:space:]]*done(_with_escalation)?\b' "$f" || return 1
  local stamped; stamped="$(cksum < "$f")"
  rs_run "$r" "$r/.supervisor/requirements/qh" --apply
  [ -z "$RUN_OUT" ] && [ "$(cksum < "$f")" = "$stamped" ]
}
# rs_shipped_listed <repo> <pr field> — 0 iff dry run AND --apply each print exactly the one info
# row and the file is byte-unchanged.
rs_shipped_listed() {
  local r="$1" f="$1/$RS_SREL" orig; orig="$(cksum < "$f")"
  rs_run "$r" "$r/.supervisor/requirements/qh"; RSS_DRY="$RUN_OUT"
  rs_run "$r" "$r/.supervisor/requirements/qh" --apply; RSS_APPLY="$RUN_OUT"
  [ "$RSS_DRY" = "info	$RS_SREL	brief-shipped	$2" ] && [ "$RSS_APPLY" = "$RSS_DRY" ] && [ "$(cksum < "$f")" = "$orig" ]
}

# H6a. brief-shipped + its done/ brief's PR MERGED on a branch matching the brief slug ⇒ plan row
#      (dry run), stamped under --apply, append-only, idempotent.
R="$(rs_shipped_repo MERGED feature/qh-07-shipped "Ships the thing." '["src/x.sh"]')"
if rs_shipped_promotes "$R" "$RS_SROW_SLUG"; then
  ok "H6a brief-shipped + merged branch-slug PR: plan row (dry run, file untouched), stamped under --apply (append-only, is_done true, brief-shipped heading kept), re-run a no-op"
else
  no "H6a brief-shipped not promoted (dry='$RSS_DRY' apply='$RSS_APPLY' file=$(tr '\n' '|' < "$R/$RS_SREL"))"
fi
# Mutation control: the pre-fix early return restored (brief-shipped ⇒ info row, return) ⇒ H6a red.
RS_SHIP_LINE='  case "$status_hdr" in *brief-shipped*) shipped=1 ;; esac'
RS_SHIP_MUT='  case "$status_hdr" in *brief-shipped*) printf '"'"'info\t%s\tbrief-shipped\t%s\n'"'"' "$rel" "no PR recorded"; return 0 ;; esac'
rm -rf "$R"; R="$(rs_shipped_repo MERGED feature/qh-07-shipped "Ships the thing." '["src/x.sh"]')"
if rs_mutant "$RS_SHIP_LINE" "$RS_SHIP_MUT"; then
  if RS_H="$RSM/automate-helpers.sh" rs_shipped_promotes "$R" "$RS_SROW_SLUG"; then
    no "H6a mutation control REFUTED: the early-return helper still promoted brief-shipped"
  elif grep -qxF '## Status: brief-shipped' "$R/$RS_SREL" && ! grep -qE '^## Status:[[:space:]]*done' "$R/$RS_SREL"; then
    ok "H6a mutation control: with the early return restored the merged brief-shipped file is never promoted — the fall-through is load-bearing"
  else
    no "H6a mutation control failed for another reason (dry='$RSS_DRY' apply='$RSS_APPLY')"
  fi
else
  no "H6a mutation control: the brief-shipped case line was not found in the helper"
fi
rm -rf "$R" "$RSM"

# H6b. The body-citation path promotes a brief-shipped file too (branch does not match the slug).
R="$(rs_shipped_repo MERGED feature/unrelated "Implements \`qh/07-shipped\`." '["src/x.sh"]')"
rs_shipped_promotes "$R" "$RS_SROW_CITE" \
  && ok "H6b brief-shipped + merged PR whose Implements line cites it ⇒ plan, then stamped" \
  || no "H6b body-citation promotion wrong (dry='$RSS_DRY' apply='$RSS_APPLY')"
rm -rf "$R"

# H6c. No merged evidence ⇒ the info row exactly as before, file byte-unchanged under --apply:
#      the done/ brief's PR still OPEN; a self-citing PR (its diff modifies the requirement);
#      an all-.supervisor/ diff on a slug-matching branch; the engine's own trail PR.
R="$(rs_shipped_repo OPEN feature/qh-07-shipped "Ships the thing." '["src/x.sh"]')"
rs_shipped_listed "$R" "$RS_SURL" && ok "H6c brief-shipped + OPEN PR ⇒ info row only (dry run and --apply), file byte-unchanged" \
  || no "H6c OPEN PR leg wrong (dry='$RSS_DRY' apply='$RSS_APPLY')"
rm -rf "$R"
R="$(rs_shipped_repo MERGED feature/unrelated "Implements \`qh/07-shipped\`." "[\"src/x.sh\",\"$RS_SREL\"]")"
rs_shipped_listed "$R" "$RS_SURL" && ok "H6c brief-shipped + self-citing PR (diff modifies the requirement) ⇒ info row only" \
  || no "H6c self-citing leg wrong (dry='$RSS_DRY' apply='$RSS_APPLY')"
rm -rf "$R"
R="$(rs_shipped_repo MERGED feature/qh-07-shipped "Ships the thing." '[".supervisor/automate/run.md"]')"
rs_shipped_listed "$R" "$RS_SURL" && ok "H6c brief-shipped + all-.supervisor/ diff on a slug-matching branch ⇒ info row only" \
  || no "H6c all-.supervisor leg wrong (dry='$RSS_DRY' apply='$RSS_APPLY')"
rm -rf "$R"
R="$(rs_shipped_repo MERGED chore/automate-2026-10-01-000000-trail-1 "Implements \`qh/07-shipped\`." '["src/x.sh"]')"
rs_shipped_listed "$R" "$RS_SURL" && ok "H6c brief-shipped cited only by a trail PR ⇒ info row only" \
  || no "H6c trail leg wrong (dry='$RSS_DRY' apply='$RSS_APPLY')"
rm -rf "$R"
# No done/ brief and no candidate at all ⇒ 'no PR recorded', as before.
R="$(rs_shipped_repo MERGED feature/qh-07-shipped "Ships the thing." '["src/x.sh"]')"
rm -f "$R/$RS_SBRIEF" "$R/ghstub/list-$(rs_skey "$RS_SREL").json"
rs_shipped_listed "$R" "no PR recorded" && ok "H6c brief-shipped with no done/ brief and no candidate ⇒ info row 'no PR recorded'" \
  || no "H6c no-candidate leg wrong (dry='$RSS_DRY' apply='$RSS_APPLY')"
rm -rf "$R"
# H6d. A brief-shipped file that ALSO carries a not-ready heading (an owner `parked` decision) is
#      never promoted, even with merged evidence — still listed.
R="$(rs_shipped_repo MERGED feature/qh-07-shipped "Ships the thing." '["src/x.sh"]' '## Status: parked')"
rs_shipped_listed "$R" "$RS_SURL" && ok "H6d brief-shipped + a parked heading ⇒ info row only, never promoted despite merged evidence" \
  || no "H6d parked leg wrong (dry='$RSS_DRY' apply='$RSS_APPLY')"
rm -rf "$R"

# H7. The engine's own trail PR is never evidence (sibling defect of the
#     trail-PR-moves-main fix, run automate-2026-10-01-142337). A trail PR's
#     body lists every path it commits, so a body citation there is "committed",
#     never "shipped".
RS_TRAIL="https://github.com/acme/widgets/pull/321"
rs_trail_repo() {  # <trail headRefName> → "<repo>\t<draft rel>\t<req rel>"
  local r reld relq
  r="$(mktemp -d)"
  mkdir -p "$r/.supervisor/requirements/qh/proposed" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/bin" "$r/ghstub"
  reld=".supervisor/requirements/qh/proposed/automate-2026-01-01-000000--01-a-abc123--dismissed-1b4e0236.md"
  relq=".supervisor/requirements/qh/01-a.md"
  printf '# Dismissed finding\n\n- **Decision:** follow-up\n> some finding\n' > "$r/$reld"
  printf '# a\n\n## Status: pending\n' > "$r/$relq"
  rs_stub_bin "$r/bin"
  jq -n --arg url "$RS_TRAIL" '[{url:$url}]' > "$r/ghstub/list-$(rs_skey "$reld").json"
  jq -n --arg url "$RS_TRAIL" '[{url:$url}]' > "$r/ghstub/list-$(rs_skey "$relq").json"
  # The diff is deliberately NOT the trail's real one (which commits the cited
  # files, all under .supervisor/): H8's diff rules would then exclude it too,
  # and the mutation control below could not isolate the branch-name rule.
  # The body cites both on IMPLEMENTS lines for the same reason: H9's
  # passing-mention rule would otherwise exclude a bare path list too.
  jq -n --arg d "$reld" --arg q "$relq" --arg h "$1" \
    '{state:"MERGED",mergedAt:"2026-09-30T00:00:00Z",number:321,body:("Trail paths:\nImplements "+$q+"\nImplements "+$d),mergeCommit:{oid:"6b388ae000000000"},headRefName:$h,changedFiles:1,files:[{path:"src/trail-fixture.sh"}]}' \
    > "$r/ghstub/view-$(rs_key "$RS_TRAIL").json"
  printf '%s\t%s\t%s' "$r" "$reld" "$relq"
}
IFS=$'\t' read -r R RELD RELQ <<<"$(rs_trail_repo chore/automate-2026-09-30-054439-trail-2)"
rs_run "$R" "$R/.supervisor/requirements/qh"
DRY_OUT="$RUN_OUT"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if [ -z "$DRY_OUT" ] && [ -z "$RUN_OUT" ] && ! grep -q '^## Status' "$R/$RELD" && grep -qE '^## Status: pending$' "$R/$RELQ"; then
  ok "H7 a merged trail PR whose body cites a proposed/ draft and a Queue requirement is not evidence (no plan, no stamp)"
else
  no "H7 trail PR read as evidence (dry='$DRY_OUT' apply='$RUN_OUT')"
fi
# Mutation control: the exclusion neutered in a copy of the helper ⇒ the same fixture plans both files again.
RSM="$(mktemp -d)"; cp "$HERE"/*.sh "$HERE"/*.py "$RSM/" 2>/dev/null; cp -R "$HERE/setup-memory.d" "$HERE/meta-sync.d" "$RSM/"
sed 's/^    _rs_is_trail_branch "\$headref" && continue$/    :/' "$H" > "$RSM/automate-helpers.sh"
if cmp -s "$H" "$RSM/automate-helpers.sh"; then
  no "H7 mutation control: the exclusion line was not found (the sed no longer matches)"
else
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  if grep -qF "plan	$RELD	done (PR #321, merge 6b388ae)" <<<"$RUN_OUT" && grep -qF "plan	$RELQ	done (PR #321" <<<"$RUN_OUT"; then
    ok "H7 mutation control: without the trail-branch exclusion the draft and the requirement plan 'done (PR #321)' — the exclusion is load-bearing"
  else
    no "H7 mutation control: mutant did not reproduce the defect (out='$RUN_OUT') — H7 would be vacuous"
  fi
fi
rm -rf "$R" "$RSM"
# A trail candidate listed ahead of the real implementation PR is skipped, not fatal.
IFS=$'\t' read -r R RELD RELQ <<<"$(rs_trail_repo chore/automate-2026-09-30-054439-trail-2)"
jq -n --arg t "$RS_TRAIL" --arg u "$RS_URL" '[{url:$t},{url:$u}]' > "$R/ghstub/list-$(rs_skey "$RELQ").json"
jq -n --arg q "$RELQ" '{state:"MERGED",mergedAt:"2026-09-01T00:00:00Z",number:42,body:("Ships "+$q),mergeCommit:{oid:"abcdef1234567890"},headRefName:"feature/a",changedFiles:1,files:[{path:"src/a.sh"}]}' \
  > "$R/ghstub/view-$(rs_key "$RS_URL").json"
rs_run "$R" "$R/.supervisor/requirements/qh"
if [ "$(printf '%s\n' "$RUN_OUT" | grep -c '^plan	')" = "1" ] && grep -qF "plan	$RELQ	done (PR #42, merge abcdef1)	PR body cites $RELQ" <<<"$RUN_OUT"; then
  ok "H7 a trail candidate ahead of the real PR is skipped; the plan names the implementation PR #42"
else
  no "H7 trail-then-real candidate order wrong (out='$RUN_OUT')"
fi
rm -rf "$R"
# The exclusion is the trail shape only: a near-miss branch name stays evidence.
IFS=$'\t' read -r R RELD RELQ <<<"$(rs_trail_repo chore/x-trail-final)"
rs_run "$R" "$R/.supervisor/requirements/qh"
grep -qF "plan	$RELQ	done (PR #321" <<<"$RUN_OUT" && ok "H7 near-miss branch chore/x-trail-final (no numeric suffix) is still evidence" || no "H7 near-miss excluded (out='$RUN_OUT')"
rm -rf "$R"

# H8. A body citation is evidence only when the PR's diff did not itself add or
#     modify the cited requirement; an all-.supervisor/ diff is never evidence;
#     an unreadable or incomplete diff is no evidence. (2026-10-03: PR #359,
#     chore/meta-scrub-cleanup, ADDED meta-sync-followups/04 as `## Status:
#     pending`, listed it in its body, and the dry run read "would stamp done
#     (PR #359)".)
RS_D="https://github.com/acme/widgets/pull/359"
RS_DREL=".supervisor/requirements/qh/04-scrub-safe-briefs.md"
rs_diff_repo() {  # <files_json_array> [changedFiles] → "<repo>"; PR #359 cites RS_DREL in its body
  local r
  r="$(mktemp -d)"
  mkdir -p "$r/.supervisor/requirements/qh" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/bin" "$r/ghstub"
  printf '# scrub\n\n## Status: pending\n' > "$r/$RS_DREL"
  rs_stub_bin "$r/bin"
  jq -n --arg url "$RS_D" '[{url:$url}]' > "$r/ghstub/list-$(rs_skey "$RS_DREL").json"
  # An IMPLEMENTS-line citation (not #359's real bare list), so the diff rules
  # are what each H8 leg isolates — H9's passing-mention rule would end it first.
  jq -n --arg q "$RS_DREL" --argjson f "$1" --arg c "${2:-}" \
    '{state:"MERGED",mergedAt:"2026-10-02T00:00:00Z",number:359,body:("Queues:\nImplements "+$q),mergeCommit:{oid:"9a78b9c000000000"},headRefName:"chore/meta-scrub-cleanup",
      files:[$f[]|{path:.}],changedFiles:(if $c=="" then ($f|length) else ($c|tonumber) end)}' \
    > "$r/ghstub/view-$(rs_key "$RS_D").json"
  printf '%s' "$r"
}
rs_plans_359() { grep -qF "plan	$RS_DREL	done (PR #359, merge 9a78b9c)	PR body cites $RS_DREL" <<<"$RUN_OUT"; }
RS_TOUCH_LINE='      grep -qxF -- "$rel" <<<"$paths" || justification="PR body cites $rel"'
RS_TOUCH_MUT='      justification="PR body cites $rel"'
RS_SUP_LINE="    grep -qv '^\\.supervisor/' <<<\"\$paths\" || continue"

# H8a. The PR adds the requirement (plus a non-.supervisor file) and cites it ⇒ no plan, no stamp.
R="$(rs_diff_repo "[\"$RS_DREL\",\"docs/scrub.md\"]")"
rs_run "$R" "$R/.supervisor/requirements/qh"
DRY_OUT="$RUN_OUT"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if [ -z "$DRY_OUT" ] && [ -z "$RUN_OUT" ] && grep -qE '^## Status: pending$' "$R/$RS_DREL"; then
  ok "H8a a PR whose diff adds the cited requirement is not evidence (no plan, no stamp under --apply)"
else
  no "H8a requirement-adding PR read as evidence (dry='$DRY_OUT' apply='$RUN_OUT')"
fi
# Mutation control: the diff-membership check removed ⇒ the same fixture plans 'done (PR #359)' again.
if rs_mutant "$RS_TOUCH_LINE" "$RS_TOUCH_MUT"; then
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  rs_plans_359 && ok "H8a mutation control: without the diff-membership check the requirement plans 'done (PR #359)' — the check is load-bearing" \
    || no "H8a mutation control: mutant did not reproduce the defect (out='$RUN_OUT') — H8a would be vacuous"
else
  no "H8a mutation control: the membership line was not found in the helper"
fi
rm -rf "$R" "$RSM"
# Control: the same PR without the requirement in its diff ⇒ the plan row.
R="$(rs_diff_repo '["docs/scrub.md"]')"
rs_run "$R" "$R/.supervisor/requirements/qh"
rs_plans_359 && ok "H8a control: the same citing PR without the requirement in its diff plans 'done (PR #359)'" || no "H8a control: no plan row (out='$RUN_OUT')"
rm -rf "$R"

# H8b. The real PR #359 shape (every changed file under .supervisor/, the requirement among them) ⇒ no plan.
R="$(rs_diff_repo "[\".supervisor/automate/automate-2026-09-01-232353.md\",\".supervisor/jobs/done/2026-10-02-x.md\",\"$RS_DREL\"]")"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8b the PR #359 shape (all-.supervisor diff that adds the requirement) plans nothing" || no "H8b PR #359 shape planned (out='$RUN_OUT')"
rm -rf "$R"

# H8c. An all-.supervisor/ diff that does NOT touch the requirement is still not evidence.
R="$(rs_diff_repo '[".supervisor/jobs/done/2026-10-02-x.md",".supervisor/automate/run.md"]')"
rs_run "$R" "$R/.supervisor/requirements/qh"
if [ -z "$RUN_OUT" ]; then
  ok "H8c a citing PR whose changed files are all under .supervisor/ is not evidence"
else
  no "H8c all-.supervisor diff read as evidence (out='$RUN_OUT')"
fi
if rs_mutant "$RS_SUP_LINE" '    :'; then
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  rs_plans_359 && ok "H8c mutation control: without the all-.supervisor check the same fixture plans — the check is load-bearing" \
    || no "H8c mutation control: mutant did not reproduce (out='$RUN_OUT') — H8c would be vacuous"
else
  no "H8c mutation control: the all-.supervisor line was not found in the helper"
fi
rm -rf "$R" "$RSM"

# H8e. The all-.supervisor/ exclusion also holds on the BRANCH-SLUG path: a done/
#      brief points at the requirement and names PR #359, whose head branch ends in
#      the brief's slug and whose body does NOT cite the requirement.
rs_slug_repo() {  # <files_json_array> → "<repo>"
  local r v
  r="$(rs_diff_repo "$1")"
  v="$r/ghstub/view-$(rs_key "$RS_D").json"
  jq '.body = "no path cited here" | .headRefName = "feature/scrub-safe-briefs"' "$v" > "$r/v.json" && mv "$r/v.json" "$v"
  printf '# brief\n\n## Environment\n- **Source requirement:** %s\n\n## Outcome\n- **PR:** %s\n' "$RS_DREL" "$RS_D" \
    > "$r/.supervisor/jobs/done/2026-10-02-scrub-safe-briefs.md"
  printf '%s' "$r"
}
rs_slug_plans() { grep -qF "plan	$RS_DREL	done (PR #359, merge 9a78b9c)	head branch 'feature/scrub-safe-briefs' matches brief slug 'scrub-safe-briefs'" <<<"$RUN_OUT"; }
# Control: the same slug-matched PR with an implementation file in its diff ⇒ the plan row.
R="$(rs_slug_repo '["src/scrub.sh",".supervisor/jobs/done/2026-10-02-scrub-safe-briefs.md"]')"
rs_run "$R" "$R/.supervisor/requirements/qh"
rs_slug_plans && ok "H8e control: a slug-matched PR with an implementation file plans 'done (PR #359)' via the branch slug" || no "H8e control: no slug plan row (out='$RUN_OUT')"
rm -rf "$R"
R="$(rs_slug_repo '[".supervisor/jobs/done/2026-10-02-scrub-safe-briefs.md",".supervisor/automate/run.md"]')"
rs_run "$R" "$R/.supervisor/requirements/qh"
DRY_OUT="$RUN_OUT"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if [ -z "$DRY_OUT" ] && [ -z "$RUN_OUT" ] && grep -qE '^## Status: pending$' "$R/$RS_DREL"; then
  ok "H8e a slug-matched PR whose changed files are all under .supervisor/ is not evidence (no plan, no stamp)"
else
  no "H8e all-.supervisor slug match read as evidence (dry='$DRY_OUT' apply='$RUN_OUT')"
fi
if rs_mutant "$RS_SUP_LINE" '    :'; then
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  rs_slug_plans && ok "H8e mutation control: without the all-.supervisor check the slug path plans — the check covers both paths" \
    || no "H8e mutation control: mutant did not reproduce (out='$RUN_OUT') — H8e would be vacuous"
else
  no "H8e mutation control: the all-.supervisor line was not found in the helper"
fi
rm -rf "$R" "$RSM"

# H8d. Fail closed on an unreadable or incomplete diff; a >100-file diff is re-read in full.
R="$(rs_diff_repo '["docs/scrub.md"]')"
jq 'del(.files, .changedFiles)' "$R/ghstub/view-$(rs_key "$RS_D").json" > "$R/v.json" && mv "$R/v.json" "$R/ghstub/view-$(rs_key "$RS_D").json"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8d a view with no files/changedFiles is no evidence (fail closed)" || no "H8d unreadable diff read as evidence (out='$RUN_OUT')"
rm -rf "$R"
# pr view returned a 1-entry page of a 150-file diff; no REST answer ⇒ no evidence.
R="$(rs_diff_repo '["docs/scrub.md"]' 150)"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8d a truncated diff whose REST re-read fails is no evidence" || no "H8d truncated diff read as evidence (out='$RUN_OUT')"
RS_API="$R/ghstub/api-$(rs_key "repos/acme/widgets/pulls/359/files").txt"
{ for i in $(seq 1 149); do printf 'src/f%s.sh\n' "$i"; done; printf '%s\n' "$RS_DREL"; } > "$RS_API"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8d the requirement found on a later REST page of a 150-file diff ⇒ no evidence" || no "H8d requirement past pr view's first page missed (out='$RUN_OUT')"
{ for i in $(seq 1 150); do printf 'src/f%s.sh\n' "$i"; done; } > "$RS_API"
rs_run "$R" "$R/.supervisor/requirements/qh"
rs_plans_359 && ok "H8d a complete 150-file REST re-read without the requirement keeps the citation as evidence" || no "H8d complete REST re-read lost the evidence (out='$RUN_OUT')"
sed '$d' "$RS_API" > "$R/a.txt" && mv "$R/a.txt" "$RS_API"
rs_run "$R" "$R/.supervisor/requirements/qh"
[ -z "$RUN_OUT" ] && ok "H8d a REST re-read still short of changedFiles is no evidence" || no "H8d short REST re-read read as evidence (out='$RUN_OUT')"
rm -rf "$R"

# H9. A body citation is evidence only on an IMPLEMENTS-shaped line. On
#     2026-10-11 the any-mention rule planned five false stamps: PR #470's
#     `plan-waves` example listed af/36, af/39 and pa/18; PR #482 named the
#     `proposed/` follow-up draft it filed; PR #457 named a task plan. And it
#     MISSED af/27, because PR #484 cited the short form and GitHub search does
#     not find the full path at all.
RS_C="https://github.com/acme/widgets/pull/77"
RS_CREL=".supervisor/requirements/qh/09-board-and-right-size.md"
# rs_cite_repo <rel> <status heading or ""> <body> → "<repo>"; PR #77 (merged,
# diff src/x.sh) is the ONLY search hit for <rel>'s short ref.
rs_cite_repo() {
  local r
  r="$(mktemp -d)"
  mkdir -p "$r/$(dirname "$1")" "$r/.supervisor/jobs/done" "$r/.supervisor/automate" "$r/bin" "$r/ghstub"
  { printf '# req\n\n'; [ -n "$2" ] && printf '%s\n' "$2"; } > "$r/$1"
  rs_stub_bin "$r/bin"
  jq -n --arg url "$RS_C" '[{url:$url}]' > "$r/ghstub/list-$(rs_skey "$1").json"
  jq -n --arg b "$3" \
    '{state:"MERGED",mergedAt:"2026-10-11T00:00:00Z",number:77,body:$b,mergeCommit:{oid:"61048c0000000000"},headRefName:"feature/pa22-split",changedFiles:1,files:[{path:"src/x.sh"}]}' \
    > "$r/ghstub/view-$(rs_key "$RS_C").json"
  printf '%s' "$r"
}
rs_plans_77() { grep -qF "plan	$1	done (PR #77, merge 61048c0)	PR body cites $1" <<<"$RUN_OUT"; }
RS_CITE_LINE='    if _rs_implements_cites "$body" "$short"; then'
RS_CITE_MUT='    if case "$body" in *"$rel"*) true ;; *) false ;; esac; then'
# The PR #470 shape: implements ANOTHER requirement, lists this one in an example.
RS_PASSING="Requirement: \`.supervisor/requirements/qh/22-split-surfaces.md\` (lane L1).

printf '%s\\n' $RS_CREL \\
  .supervisor/requirements/qh/36-engine-fixes.md > open.txt
wave 1: $RS_CREL"

# H9a. A passing mention ⇒ no plan, no stamp; the old any-mention rule restored ⇒ red.
R="$(rs_cite_repo "$RS_CREL" '## Status: pending' "$RS_PASSING")"
rs_run "$R" "$R/.supervisor/requirements/qh"
DRY_OUT="$RUN_OUT"
rs_run "$R" "$R/.supervisor/requirements/qh" --apply
if [ -z "$DRY_OUT" ] && [ -z "$RUN_OUT" ] && grep -qE '^## Status: pending$' "$R/$RS_CREL"; then
  ok "H9a a requirement only mentioned in passing (the PR #470 shape) gets no plan and no stamp"
else
  no "H9a passing mention read as evidence (dry='$DRY_OUT' apply='$RUN_OUT')"
fi
if rs_mutant "$RS_CITE_LINE" "$RS_CITE_MUT"; then
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  rs_plans_77 "$RS_CREL" && ok "H9a mutation control: the any-mention rule restored plans 'done (PR #77)' for the passing mention — the implements-line check is load-bearing" \
    || no "H9a mutation control: mutant did not reproduce the defect (out='$RUN_OUT') — H9a would be vacuous"
else
  no "H9a mutation control: the citation line was not found in the helper"
fi
rm -rf "$R" "$RSM"

# H9b. `Implements <full path>` (the PR #483 shape) ⇒ plan row.
R="$(rs_cite_repo "$RS_CREL" '## Status: pending' "Implements \`$RS_CREL\`, re-scoped to its two live problems.")"
rs_run "$R" "$R/.supervisor/requirements/qh"
rs_plans_77 "$RS_CREL" && ok "H9b 'Implements <full path>' plans 'done (PR #77)'" || no "H9b full-path Implements line not evidence (out='$RUN_OUT')"
rm -rf "$R"

# H9c. `Implements <short slug>` (the PR #484 shape: no prefix, no .md) ⇒ plan row —
#      and only because the search uses the short form (stub answers that term alone).
R="$(rs_cite_repo "$RS_CREL" '## Status: pending' 'Implements `qh/09-board-and-right-size`.')"
rs_run "$R" "$R/.supervisor/requirements/qh"
rs_plans_77 "$RS_CREL" && ok "H9c 'Implements <short slug>' plans 'done (PR #77)'" || no "H9c short-slug Implements line not evidence (out='$RUN_OUT')"
if rs_mutant '  search_json="$("$GH" pr list --state merged --search "$short" --json url --limit 5 2>/dev/null)"' \
             '  search_json="$("$GH" pr list --state merged --search "$rel" --json url --limit 5 2>/dev/null)"'; then
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
  [ -z "$RUN_OUT" ] && ok "H9c mutation control: searching the full path finds no candidate (the PR #484 miss) — the short-form search is load-bearing" \
    || no "H9c mutation control: full-path search still planned (out='$RUN_OUT') — H9c would be vacuous"
else
  no "H9c mutation control: the search line was not found in the helper"
fi
rm -rf "$R" "$RSM"

# H9d. Other implements shapes seen on main: `Closes <id> (`<path>`)`, a bold
#      list-item `Requirement:`, lower-case verbs ⇒ plan row each.
for body in "Closes qh-09 (\`$RS_CREL\`). Follow-up to #426." \
            "- **Requirement:** \`qh/09-board-and-right-size.md\`" \
            "ships \`qh/09-board-and-right-size\`"; do
  R="$(rs_cite_repo "$RS_CREL" '' "$body")"
  rs_run "$R" "$R/.supervisor/requirements/qh"
  rs_plans_77 "$RS_CREL" && ok "H9d implements shape plans: $body" || no "H9d implements shape not evidence: '$body' (out='$RUN_OUT')"
  rm -rf "$R"
done

# H9e. Near misses on a verb line ⇒ no plan: the path after the first clause,
#      a longer slug that starts with this one, a path nested under another dir,
#      and a verb that is only a prefix of a word.
for body in 'Implements `qh/22-split-surfaces`; unblocks `qh/09-board-and-right-size`.' \
            'Implements `qh/22-split-surfaces`. Next: `qh/09-board-and-right-size`.' \
            'Implements `qh/09-board-and-right-size-v2`.' \
            'Implements `other/qh/09-board-and-right-size`.' \
            'Shipshape notes on `qh/09-board-and-right-size`.'; do
  R="$(rs_cite_repo "$RS_CREL" '## Status: pending' "$body")"
  rs_run "$R" "$R/.supervisor/requirements/qh"
  [ -z "$RUN_OUT" ] && ok "H9e near miss is no evidence: $body" || no "H9e near miss read as evidence: '$body' (out='$RUN_OUT')"
  rm -rf "$R"
done

# H9f. A not-ready heading (is_not_ready) is never reconciled: a `## Status: proposed`
#      draft (the PR #482 shape) or a `parked` item with a real Implements line ⇒ no plan.
RS_GATE_LINE='  is_not_ready "$f" || evidence="$(_rs_evidence_for "$rel" "$done_brief" "$seed")"'
RS_GATE_MUT='  evidence="$(_rs_evidence_for "$rel" "$done_brief" "$seed")"'
# Every other not-done heading stays promotable (ground-truth-json.md's contract).
for st in '## Status: in-progress' '## Status: in review — PR #77, awaiting merge'; do
  R="$(rs_cite_repo "$RS_CREL" "$st" "Implements \`$RS_CREL\`.")"
  rs_run "$R" "$R/.supervisor/requirements/qh"
  rs_plans_77 "$RS_CREL" && ok "H9f '$st' with an Implements line still plans 'done (PR #77)'" || no "H9f '$st' not reconciled (out='$RUN_OUT')"
  rm -rf "$R"
done
for st in '## Status: proposed' '## Status: parked'; do
  R="$(rs_cite_repo "$RS_CREL" "$st" "Implements \`$RS_CREL\`.")"
  rs_run "$R" "$R/.supervisor/requirements/qh"
  [ -z "$RUN_OUT" ] && ok "H9f '$st' is never stamped, even with an Implements line" || no "H9f '$st' planned (out='$RUN_OUT')"
  if [ "$st" = '## Status: proposed' ]; then
    if rs_mutant "$RS_GATE_LINE" "$RS_GATE_MUT"; then
      RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements/qh"
      rs_plans_77 "$RS_CREL" && ok "H9f mutation control: without the status gate the proposed draft plans — the gate is load-bearing" \
        || no "H9f mutation control: mutant did not reproduce (out='$RUN_OUT') — H9f would be vacuous"
    else
      no "H9f mutation control: the status-gate line was not found in the helper"
    fi
    rm -rf "$RSM"
  fi
  rm -rf "$R"
done

# H9g. A top-level `<slug>-plan.md` task plan (the PR #457 shape) is never a
#      candidate; a nested `*-plan.md` requirement still is.
RS_TP=".supervisor/requirements/done-stamp-before-merge-plan.md"
R="$(rs_cite_repo "$RS_TP" '' "Implements \`$RS_TP\`.")"
rs_run "$R" "$R/.supervisor/requirements"
[ -z "$RUN_OUT" ] && ok "H9g a top-level task plan is never a candidate" || no "H9g task plan planned (out='$RUN_OUT')"
if rs_mutant '    case "$base" in *-plan.md) return 0 ;; esac' '    :'; then
  RS_H="$RSM/automate-helpers.sh" rs_run "$R" "$R/.supervisor/requirements"
  rs_plans_77 "$RS_TP" && ok "H9g mutation control: without the task-plan skip it plans — the skip is load-bearing" \
    || no "H9g mutation control: mutant did not reproduce (out='$RUN_OUT') — H9g would be vacuous"
else
  no "H9g mutation control: the task-plan skip line was not found in the helper"
fi
rm -rf "$R" "$RSM"
RS_NP=".supervisor/requirements/qh/10-lane-plan.md"
R="$(rs_cite_repo "$RS_NP" '## Status: pending' "Implements \`$RS_NP\`.")"
rs_run "$R" "$R/.supervisor/requirements"
rs_plans_77 "$RS_NP" && ok "H9g a nested *-plan.md requirement is still reconciled" || no "H9g nested *-plan.md skipped (out='$RUN_OUT')"
rm -rf "$R"

# H10. Owner decision D-conflict-1 (parallel-automate/18a AC7): `--apply` never stamps ABANDONED from a
#      Queue row on an item whose FIRST `## Status:` line is explicit pending/ready. A `conflict` one
#      (no Kept-open marker settling the row) is byte-unchanged with ONE `info\t<rel>\tconflict\t<run
#      file>` row; a kept-open one (marker dated on the row's run date) is byte-unchanged with no row
#      at all; a `brief-shipped` and a status-less item named by such a row are still stamped.
RS_ABRUN=".supervisor/automate/automate-2026-09-01-100000.md"
rs_conflict_repo() {
  local r; r="$(mktemp -d)"
  mkdir -p "$r/.supervisor/requirements/qh" "$r/.supervisor/automate" "$r/.supervisor/jobs/done" "$r/bin" "$r/ghstub"
  rs_stub_bin "$r/bin"
  printf '# c\n\n## Status: pending\n' > "$r/.supervisor/requirements/qh/11-conflict.md"
  printf '# k\n\n## Status: ready\n\n- **Kept open:** 2026-09-01 — supersedes automate-2026-09-01-100000\n' > "$r/.supervisor/requirements/qh/12-kept.md"
  printf '# s\n\n## Status: brief-shipped\n' > "$r/.supervisor/requirements/qh/13-shipped.md"
  printf '# n\n' > "$r/.supervisor/requirements/qh/14-none.md"
  {
    printf '# Automate Run: conflict fixture\n## Status: done\n## Queue\n'
    for i in 11-conflict 12-kept 13-shipped 14-none; do printf -- '- [x] .supervisor/requirements/qh/%s.md  # abandoned: owner dropped it\n' "$i"; done
    printf '## Progress\n'
  } > "$r/$RS_ABRUN"
  printf '%s' "$r"
}
# rs_conflict_check <repo> — dry run + --apply; prints one verdict word per expectation
rs_conflict_check() {
  local r="$1" q=".supervisor/requirements/qh" b11 b12 dry
  b11="$(cksum < "$r/$q/11-conflict.md")"; b12="$(cksum < "$r/$q/12-kept.md")"
  rs_run "$r" "$r/$q"; dry="$RUN_OUT"
  rs_run "$r" "$r/$q" --apply
  [ "$(cksum < "$r/$q/11-conflict.md")" = "$b11" ] && printf 'c-unchanged ' || printf 'c-WRITTEN '
  [ "$(grep -cxF "info	$q/11-conflict.md	conflict	$RS_ABRUN" <<<"$dry"$'\n'"$RUN_OUT")" = 2 ] && printf 'c-info ' || printf 'c-NOINFO '
  grep -qE "^(plan|stamped)	$q/11-conflict.md	" <<<"$dry"$'\n'"$RUN_OUT" && printf 'c-PLANNED ' || printf 'c-noplan '
  [ "$(cksum < "$r/$q/12-kept.md")" = "$b12" ] && printf 'k-unchanged ' || printf 'k-WRITTEN '
  grep -qF "$q/12-kept.md" <<<"$dry"$'\n'"$RUN_OUT" && printf 'k-NAMED ' || printf 'k-silent '
  grep -qxF -- "## Status: done_with_escalation — ABANDONED (- [x] $q/13-shipped.md  # abandoned: owner dropped it)" "$r/$q/13-shipped.md" \
    && grep -qxF '## Status: brief-shipped' "$r/$q/13-shipped.md" && printf 's-stamped ' || printf 's-UNSTAMPED '
  grep -qxF -- "## Status: done_with_escalation — ABANDONED (- [x] $q/14-none.md  # abandoned: owner dropped it)" "$r/$q/14-none.md" \
    && printf 'n-stamped' || printf 'n-UNSTAMPED'
}
RS_CWANT="c-unchanged c-info c-noplan k-unchanged k-silent s-stamped n-stamped"
R="$(rs_conflict_repo)"
RS_CGOT="$(rs_conflict_check "$R")"
if [ "$RS_CGOT" = "$RS_CWANT" ]; then
  ok "H10 D-conflict-1: conflict item byte-unchanged + one info conflict row (dry run and --apply); kept-open item byte-unchanged and unnamed; brief-shipped and status-less items still stamped ABANDONED"
else
  no "H10 D-conflict-1 wrong: got '$RS_CGOT', want '$RS_CWANT'"
fi
rm -rf "$R"
# Mutation controls — each pin of the guard line, on a copy of the helper: (a) the guard line deleted
# ⇒ the conflict item is stamped; (b) the explicit pending/ready skip dropped, keeping only the
# _bl_is_conflict check ⇒ the kept-open item is stamped; (c) the skip widened to any `## Status:`
# line ⇒ the brief-shipped item is left unstamped.
RS_GUARD="$(grep -F 'if _rs_first_status_open "$fabs"; then _bl_is_conflict' "$H")"
RS_GUARD_N="$(grep -cF 'if _rs_first_status_open "$fabs"; then _bl_is_conflict' "$H")"
rs_conflict_mutant() { # <label> <replacement line> <a word the mutant must lose from RS_CWANT>
  local got
  if [ "$RS_GUARD_N" = 1 ] && rs_mutant "$RS_GUARD" "$2" && bash -n "$RSM/automate-helpers.sh"; then
    R="$(rs_conflict_repo)"
    got="$(RS_H="$RSM/automate-helpers.sh" rs_conflict_check "$R")"
    case " $got " in
      *" $3 "*) no "H10 mutation control ($1) REFUTED: '$3' still holds ($got)" ;;
      *) ok "H10 mutation control ($1): '$3' no longer holds — the pin is load-bearing" ;;
    esac
    rm -rf "$R"
  else
    no "H10 mutation control ($1) not built (guard line found $RS_GUARD_N times, or the mutant is unchanged / does not parse)"
  fi
  rm -rf "$RSM"
}
rs_conflict_mutant "guard line deleted" "" c-unchanged
rs_conflict_mutant "pending/ready skip dropped, conflict check kept" \
  '          _bl_is_conflict "$fabs" "$reqpath" "$automate_dir" "$af" >/dev/null 2>&1 && { printf '"'"'info\t%s\tconflict\t%s\n'"'"' "$reqpath" "$af_rel"; continue; }' k-unchanged
rs_conflict_mutant "skip widened to any ## Status: line" "${RS_GUARD/_rs_first_status_open \"\$fabs\"/grep -q '^## Status:' \"\$fabs\"}" s-stamped
