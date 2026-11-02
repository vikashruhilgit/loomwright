#!/usr/bin/env bash
# render-prompt.sh — render the Phase 4.5 round-1 code-reviewer spawn prompt from the plugin under test.
#
#   bash render-prompt.sh [<plugin root>]      the prompt on stdout (default plugin root: this checkout's)
#
# Source: <plugin>/skills/self-heal-advisory/SKILL.md, READ IN PLACE — the prompt is rendered at staging time
# and never copied into a case, so a replay always uses the protocol of the plugin being evaluated. It takes
# the `prompt: "…"` argument of the ONE `Task(` whose agent-type line is ANCHOR below (the code-reviewer
# spawn), from the `prompt: "` that follows it up to the closing `",` on the line before the Task's `model:`
# argument, then:
#   - drops every paragraph whose text says `include this line ONLY when` (all of their inputs are empty in a
#     round-1 replay: the prior-churn, house-rules, brief-conformance, deviations, pin-mutation and
#     module-shape blocks are omitted, as Phase 4.5 omits them when their input is empty)
#   - unescapes \" and removes the continuation-line indent
#   - substitutes {BASE_BRANCH} → main, {STACKED} → false, {feature_branch} → replay
# Fails closed (exit 1, the anchor named on stderr, nothing on stdout) when the anchor is missing or appears
# more than once, when the prompt's start / end cannot be found, or when any `{` remains after substitution —
# so an edit to that prompt that breaks the shape turns the selftest red instead of replaying a different
# prompt. bash 3.2 + BSD userland.
set -uo pipefail

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="${1:-$(cd "$LIB/../../.." && pwd)}"
SKILL="$PLUGIN/skills/self-heal-advisory/SKILL.md"
ANCHOR='subagent_type: "loomwright:code-reviewer",'
die() { echo "render-prompt: $1 (anchor: $ANCHOR in $SKILL)" >&2; exit 1; }
[ -f "$SKILL" ] || die "source file not found"

n="$(grep -cF "$ANCHOR" "$SKILL")"
[ "$n" = 1 ] || die "anchor found $n time(s), want exactly 1"

# The raw prompt: rc 3 = no `prompt: "` right after the anchor; rc 4 = no `model:` argument line after it, or
# the line before that does not end with `",`
raw="$(awk -v anchor="$ANCHOR" '
  st == 0 { if (index($0, anchor)) st = 1; next }
  st == 1 {
    if ($0 ~ /^[ \t]*$/) next
    if (match($0, /^[ \t]*prompt: "/)) { n = 1; buf[1] = substr($0, RSTART + RLENGTH); st = 2; next }
    exit 3
  }
  st == 2 {
    if ($0 ~ /^[ \t]*model:[ \t]/) { st = 3; exit }
    buf[++n] = $0
  }
  END {
    if (st == 1 || st == 0) exit 3
    if (st != 3) exit 4
    if (buf[n] !~ /",[ \t]*$/) exit 4
    sub(/",[ \t]*$/, "", buf[n])
    # the continuation lines share one indent: strip the smallest one
    min = -1
    for (i = 2; i <= n; i++) {
      if (buf[i] ~ /^[ \t]*$/) continue
      match(buf[i], /^ */); if (min < 0 || RLENGTH < min) min = RLENGTH
    }
    if (min < 0) min = 0
    print buf[1]
    for (i = 2; i <= n; i++) print (buf[i] ~ /^[ \t]*$/ ? "" : substr(buf[i], min + 1))
  }' "$SKILL")"
case $? in
  0) ;;
  3) die "no 'prompt: \"' line follows the anchor" ;;
  *) die "no closing '\",' on the line before the Task's 'model:' argument" ;;
esac
[ -n "$raw" ] || die "the prompt is empty"

out="$(printf '%s\n' "$raw" \
  | awk 'BEGIN { RS = ""; ORS = "\n\n" } index($0, "include this line ONLY when") == 0' \
  | sed -e 's/\\"/"/g' -e 's/{BASE_BRANCH}/main/g' -e 's/{STACKED}/false/g' -e 's/{feature_branch}/replay/g')"
left="$(printf '%s\n' "$out" | grep -o '{[^}]*}\{0,1\}' | sort -u | tr '\n' ' ')"
case "$out" in *'{'*) die "unsubstituted placeholder(s) remain: ${left:-'{'}" ;; esac
printf '%s\n' "$out"
