#!/usr/bin/env bash
# required-checks-named.sh — sourced library. The ONE reading of a named required-checks set, for every
# script that decides on one: review-heal-next-step.sh (the drain's `named` mode — the `--required-checks
# name:` flag and the config's `required_checks` key), wait-for-checks.sh (`--named-required`) and
# setup-base-branch.sh (the `status` advisory). Restating either rule in a caller lets it drift from the
# drain, so a caller sources this file instead.
#
# named_required_valid <jq_bin> — stdin: a JSON value. Prints it de-duplicated (first occurrence kept, compact)
#   and returns 0 when it is a non-empty array of check names — strings with a non-space character and no
#   control character; prints nothing and returns 1 otherwise.
#
# required_read_no_list <captured output> — the stdout and stderr of a FAILED `drain-gh-read.sh
#   required-checks` read, concatenated. 0 when that read left no list, so a named set may stand in:
#   GitHub's paid-plan refusal, a 404 saying the base is not protected ("Branch not protected") or cannot be
#   seen ("Not Found" — a token without admin read), and every other unreadable read (a token-scope 403, a 5xx,
#   a body that is not JSON, an unreadable ruleset read behind an unprotected classic base). 1 when a
#   protection exists: classic protection was READABLE and only the ruleset read failed (drain-gh-read.sh's
#   `(classic protection readable)` marker — the readable classic list must never be replaced), or a 404 with
#   any other body ("Required status checks not enabled", a reworded 404 — the safe direction). A failed
#   ruleset read behind a classic 404 is judged by that 404's body, which drain-gh-read.sh carries in its
#   `(classic: <err>)` part — so a reviews-only base (classic 404 "Required status checks not enabled",
#   the wait's /protection read 200) never takes a named set, matching wait-for-checks.sh --named-required.

named_required_valid() {
  "$1" -ce 'if type == "array" and length > 0
      and all(.[]; type == "string" and test("\\S") and (explode | any(.[]; . < 32 or . == 127) | not))
    then reduce .[] as $n ([]; if index($n) then . else . + [$n] end) else empty end' 2>/dev/null
}

required_read_no_list() {
  case "$1" in *"(classic protection readable): "*) return 1 ;; esac
  case "$1" in *"(HTTP 404)"*|*'"status":"404"'*) ;; *) return 0 ;; esac
  case "$1" in *"Branch not protected"*|*'"message":"Not Found"'*|*"gh: Not Found (HTTP 404)"*) return 0 ;; esac
  return 1
}
