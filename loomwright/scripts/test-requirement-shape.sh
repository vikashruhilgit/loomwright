#!/usr/bin/env bash
# test-requirement-shape.sh — self-test for the requirement-shape standard (parallel-automate/18
# Part C): the plan-doc template in skills/user-story-writing/SKILL.md §"Requirement Shape" and
# the Product Owner plan-doc naming. The template is EXTRACTED from the skill (between the
# `plan-doc-template:begin/end` markers), never copied, so a template edit is what gets tested.
#   (S1) the template carries the eight sections in order, the checklist last, and no `- [ ]`
#        line before `## Checklist` (resolve-backlog reads every `- [ ]` line in the doc)
#   (S2) a plan doc built from the template is NOT enqueued by `resolve-folder` (its done stamp),
#        while the folder's items are
#   (S3) `resolve-backlog` on that plan doc reads its checklist in checklist order, not
#        directory order
#   (S4) Product Owner: the agent and its command mirror name the same plan-doc file pattern;
#        PO's own prior-stories glob matches a story and NOT a `_BACKLOG-*.md` plan doc; a PO
#        plan doc beside the stories is skipped by `resolve-folder`
#   (S5) size check (parallel-automate/18b): the skill's §"Shape decision" no longer says "count by
#        hand" and names `automate-helpers.sh right-size <item>`; the PO agent and its command
#        mirror both run `right-size` on each persisted file AFTER the `plan-waves --lint` call,
#        with identical Persist-step text; all three carry the same "small enough to review in one
#        PR, large enough to pay the run's fixed cost" sentence
#   MUTATION CONTROLS (each must turn its check red): (M1) the template's status stamp deleted
#   ⇒ S2 fails (the plan doc is enqueued); (M2) one required section deleted ⇒ S1 fails;
#   (M3) the "count by hand" sentence restored in the skill ⇒ S5 fails.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/hermetic-test-env.sh"
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
SKILL="$ROOT/skills/user-story-writing/SKILL.md"
PO_AGENT="$ROOT/agents/product-owner.md"
PO_CMD="$ROOT/commands/product-owner.md"
H="$HERE/automate-helpers.sh"
pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
no() { fail=$((fail + 1)); echo "FAIL $1"; }
T="$(mktemp -d "${TMPDIR:-/tmp}/test-requirement-shape.XXXXXX")"
trap 'rm -rf "$T"' EXIT

# The required sections, in order. The first is matched as a prefix (the stamp carries a reason).
SECTIONS='## Status: done
## Why now
## Owner decisions
## Order
## Run
## Considered and not queued
## Revisit when
## Checklist'

# extract_template <skill.md> — the fenced template body between the markers, fences dropped.
extract_template() {
  awk '/<!-- plan-doc-template:begin -->/{on=1; next} /<!-- plan-doc-template:end -->/{on=0} on && !/^```/' "$1"
}

# sections_ok <template> — 0 when the H2 headings are exactly SECTIONS in order, the checklist is
# last, and no `- [ ]` line sits before `## Checklist`; prints the reason otherwise.
sections_ok() {
  local got want
  got="$(grep '^## ' "$1" | sed 's/^\(## Status: done\).*/\1/')"
  if [ "$got" != "$SECTIONS" ]; then printf 'headings were:\n%s\n' "$got"; return 1; fi
  if awk '/^## Checklist/{c=1} /^- \[ \] /&&!c{bad=1} END{exit !bad}' "$1"; then
    echo "a '- [ ]' line sits before ## Checklist"; return 1
  fi
  grep -q '^- \[ \] ' "$1" || { echo "no checklist line"; return 1; }
  return 0
}

# build_set <template> <repo> — a requirement set `theme/` under <repo>/.supervisor/requirements,
# its plan doc instantiated from <template>. The checklist order (03 then 01) is the REVERSE of
# directory order, so S3 can tell the two apart.
build_set() {
  local d="$2/.supervisor/requirements/theme"
  mkdir -p "$d"
  sed -e 's#<folder>#theme#g' -e 's#01-<slug>#03-third#' -e 's#02-<slug>#01-first#' "$1" > "$d/_BACKLOG.md"
  printf '# 01 — first\n\n## Status: pending\n' > "$d/01-first.md"
  printf '# 03 — third\n\n## Status: pending\n' > "$d/03-third.md"
}

# folder_skips_plan_doc <template> <repo> — 0 when resolve-folder lists exactly the two items.
folder_skips_plan_doc() {
  local out d="$2/.supervisor/requirements/theme"
  build_set "$1" "$2"
  out="$(bash "$H" resolve-folder "$d" 2>&1)"
  [ "$out" = "$d/01-first.md
$d/03-third.md" ] || { printf '%s\n' "$out"; return 1; }
}

TPL="$T/template.md"
extract_template "$SKILL" > "$TPL"
if [ -s "$TPL" ]; then ok "template extracted from SKILL.md between the plan-doc-template markers"
else no "no template between the plan-doc-template markers in $SKILL"; fi

# (S1)
if r="$(sections_ok "$TPL")"; then ok "(S1) template: eight sections in order, checklist last, no '- [ ]' before it"
else no "(S1) template sections wrong: $r"; fi

# (S2)
if r="$(folder_skips_plan_doc "$TPL" "$T/s2")"; then ok "(S2) resolve-folder skips the template-built plan doc (done stamp) and lists its items"
else no "(S2) resolve-folder enqueued the plan doc or lost an item:
$r"; fi

# (S3) — run from the repo root, as the loop does (checklist paths are repo-root-relative).
out="$(cd "$T/s2" && bash "$H" resolve-backlog .supervisor/requirements/theme/_BACKLOG.md 2>&1)"
if [ "$out" = ".supervisor/requirements/theme/03-third.md
.supervisor/requirements/theme/01-first.md" ]; then
  ok "(S3) resolve-backlog reads the plan doc's checklist in checklist order (03, 01), not directory order"
else no "(S3) resolve-backlog wrong:
$out"; fi

# (S4) Product Owner naming.
PLAN_PAT='.supervisor/requirements/_BACKLOG-{YYYY-MM-DD-HHMMSS}-{slug}.md'
STORY_PAT='.supervisor/requirements/{YYYY-MM-DD-HHMMSS}-{slug}.md'
if grep -qF "$PLAN_PAT" "$PO_AGENT" && grep -qF "$PLAN_PAT" "$PO_CMD"; then
  ok "(S4) agent and command mirror both name the plan doc $PLAN_PAT"
else no "(S4) plan-doc pattern missing from the PO agent or its command mirror"; fi
GLOB="$(grep -oE 'Read prior stories\*\* by globbing `[^`]+`' "$PO_AGENT" | sed 's/.*`\(.*\)`/\1/')"
if [ -z "$GLOB" ]; then
  no "(S4) could not read PO's prior-stories glob from $PO_AGENT"
else
  R="$T/s4"; mkdir -p "$R/.supervisor/requirements"
  ts='2026-10-12-101500'
  story="$(printf '%s' "$STORY_PAT" | sed -e "s/{YYYY-MM-DD-HHMMSS}/$ts/" -e 's/{slug}/checkout-flow/')"
  plan="$(printf '%s' "$PLAN_PAT" | sed -e "s/{YYYY-MM-DD-HHMMSS}/$ts/" -e 's/{slug}/checkout-flow/')"
  printf '# story\n\n## Status: pending\n' > "$R/$story"
  sed -e "s#- \[ \] .*01-<slug>.md#- [ ] $story#" -e '/02-<slug>/d' "$TPL" > "$R/$plan"
  matched="$(cd "$R" && bash -c 'shopt -s nullglob; for f in $1; do echo "$f"; done' _ "$GLOB")"
  if [ "$matched" = "$story" ]; then ok "(S4) PO's prior-stories glob $GLOB matches the story and not the _BACKLOG- plan doc"
  else no "(S4) glob $GLOB matched:
$matched"; fi
  out="$(bash "$H" resolve-folder "$R/.supervisor/requirements" 2>&1)"
  if [ "$out" = "$R/$story" ]; then ok "(S4) a PO plan doc beside its stories is skipped by resolve-folder"
  else no "(S4) resolve-folder on PO's directory:
$out"; fi
fi

# (S5) size check. skill_size_ok <skill.md> — 0 when "count by hand" is absent and the skill names
# the right-size call and the aim sentence; prints the reason otherwise.
RS_SKILL='`automate-helpers.sh right-size <item>`'
RS_PO="the same script's \`right-size <each persisted file>\`"
RS_AIM="small enough to review in one PR, large enough to pay the run's fixed cost; when two stories touch the same files, prefer one story with parts"
LINT_PO='plan-waves <each persisted file> --lint`'
skill_size_ok() {
  if grep -qi 'count by hand' "$1"; then echo "the skill still says 'count by hand'"; return 1; fi
  grep -qF "$RS_SKILL" "$1" || { echo "the skill does not name $RS_SKILL"; return 1; }
  grep -qF "$RS_AIM" "$1" || { echo "the skill lacks the aim sentence"; return 1; }
  return 0
}
if r="$(skill_size_ok "$SKILL")"; then ok "(S5) skill: no 'count by hand'; names $RS_SKILL and the aim sentence"
else no "(S5) skill size check: $r"; fi
pa="$(grep -F '**Persist**' "$PO_AGENT")"; pc="$(grep -F '**Persist**' "$PO_CMD")"
if [ -n "$pa" ] && [ "$pa" = "$pc" ]; then ok "(S5) PO agent and command mirror: identical Persist-step text"
else no "(S5) PO agent and command mirror Persist steps differ (or are missing)"; fi
# right-size must come after the --lint call on the same Persist line, with the aim sentence.
if printf '%s\n' "$pa" | awk -v l="$LINT_PO" -v r="$RS_PO" -v a="$RS_AIM" '
     { i = index($0, l); j = index($0, r); k = index($0, a) } END { exit !(i > 0 && j > i && k > j) }'; then
  ok "(S5) PO Persist step runs right-size on each persisted file after plan-waves --lint, then the aim sentence"
else no "(S5) PO Persist step: right-size missing, before the --lint call, or without the aim sentence"; fi

# (M1) status stamp deleted ⇒ S2 must fail.
sed '/^## Status: done (index document/d' "$SKILL" > "$T/m1-skill.md"
if cmp -s "$SKILL" "$T/m1-skill.md"; then no "(M1) mutant not built (no status stamp line in the template)"
else
  extract_template "$T/m1-skill.md" > "$T/m1.md"
  if folder_skips_plan_doc "$T/m1.md" "$T/m1" >/dev/null; then no "(M1) control did not discriminate: a stampless plan doc was still skipped"
  else ok "(M1) control: without the status stamp resolve-folder enqueues the plan doc — the stamp is load-bearing"; fi
fi

# (M2) one required section deleted ⇒ S1 must fail.
sed '/^## Revisit when$/d' "$SKILL" > "$T/m2-skill.md"
if cmp -s "$SKILL" "$T/m2-skill.md"; then no "(M2) mutant not built (no '## Revisit when' line in the template)"
else
  extract_template "$T/m2-skill.md" > "$T/m2.md"
  if sections_ok "$T/m2.md" >/dev/null; then no "(M2) control did not discriminate: a template missing a section passed"
  else ok "(M2) control: a template missing '## Revisit when' fails the section check — the list is load-bearing"; fi
fi

# (M3) "count by hand" restored ⇒ S5 must fail.
sed 's/^Check it with `automate-helpers.sh right-size <item>`/No mechanical size check ships yet: count by hand. &/' "$SKILL" > "$T/m3-skill.md"
if cmp -s "$SKILL" "$T/m3-skill.md"; then no "(M3) mutant not built (no 'Check it with' right-size line in the skill)"
elif skill_size_ok "$T/m3-skill.md" >/dev/null; then no "(M3) control did not discriminate: a skill saying 'count by hand' passed"
else ok "(M3) control: restoring 'count by hand' fails the size check — the check is load-bearing"; fi

echo "test-requirement-shape: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
