#!/usr/bin/env bash
# wait-lib.sh — bounded CONDITION waits for the self-tests (iq02 T07). Sourced, never run: it is
# deliberately not named test-*.sh (the run-self-tests.sh glob would run it as a test, and
# check-test-hermetic.sh covers only test-*.sh). Self-test: loomwright/scripts/test-wait-lib.sh.
#
# Why: a test that sleeps a fixed time and then asserts on async output (S6's `sleep 0.3` before
# reading the caffeinate stub's log) races the write it reads; under a loaded pool it fails, and the
# fix-round costs a whole suite run. Wait on the condition the assertion reads instead.
#
#   wait_for_cmd <timeout_s> <cmd…>                     0 once <cmd…> succeeds (its output discarded)
#   wait_for_file_content <file> <fixed-string> <timeout_s>   0 once <file> contains the string
#   wait_for_pid_gone <pid> <timeout_s>                 0 once `kill -0 <pid>` fails
#
# Each polls every 0.1 s and is bounded by the CLOCK (date +%s), never by an iteration count: a slow
# `sleep` stretched a count-bounded wait to ~15 s once (test-ci-slot.sh G13). A deadline miss returns
# 1 and prints `wait-lib: timed out after <n>s waiting for: <condition>` on stderr — the caller's
# assertion message still names what it needed. Never exits the caller; bash 3.2 / BSD safe.
# Honest limit: the clock has whole-second resolution, so a wait may run up to ~1 s past <timeout_s>.
# wait_for_pid_gone on an unreaped child of the CALLER's own shell sees it as alive until bash reaps
# it (bash reaps background jobs on SIGCHLD, so this is normally immediate).

wait_for_cmd() {
  local t="$1" end; shift
  case "$t" in ''|*[!0-9]*) echo "wait-lib: timeout must be whole seconds, got '$t'" >&2; return 1 ;; esac
  end=$(( $(date +%s) + t ))
  while :; do
    if "$@" >/dev/null 2>&1; then return 0; fi
    if [ "$(date +%s)" -ge "$end" ]; then
      echo "wait-lib: timed out after ${t}s waiting for: ${WAIT_LIB_WHAT:-$*}" >&2
      return 1
    fi
    sleep 0.1   # fixed-sleep-ok: the poll interval of a clock-bounded wait
  done
}

wait_for_file_content() {
  WAIT_LIB_WHAT="'$2' in $1" wait_for_cmd "$3" grep -qF -- "$2" "$1"
}

_wait_lib_pid_gone() { ! kill -0 "$1" 2>/dev/null; }
wait_for_pid_gone() {
  WAIT_LIB_WHAT="pid $1 to exit" wait_for_cmd "$2" _wait_lib_pid_gone "$1"
}
