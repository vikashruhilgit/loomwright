# wsplit.sed — the ONE mutation control for wait-for-checks-line.sh, shared by every suite that
# tests the reader or a consumer of it (test-wait-for-checks.sh, test-drain-subfloor-decision.sh,
# test-automate-helpers.sh ESC). Applied with `sed -f` to a COPY of the reader, it reverts
# wfc_line_parse to the pre-fix shell word-splitting of the line (default IFS, one token per
# field): a spaced check name keeps only its first word. Each suite's spaced-name legs must turn
# red against it; a suite whose legs stay green under it no longer tests the class of bug.
/^  WFC_HAVE_PENDING_NAMES=0; WFC_HAVE_RED_NAMES=0$/a\
  set -f; for _t in $l; do case "$_t" in sha=*) WFC_SHA="${_t#sha=}" ;; required=*) WFC_REQUIRED="${_t#required=}" ;; pending=*) WFC_PENDING="${_t#pending=}" ;; pending_names=*) WFC_PENDING_NAMES="${_t#pending_names=}"; WFC_HAVE_PENDING_NAMES=1 ;; red_names=*) WFC_RED_NAMES="${_t#red_names=}"; WFC_HAVE_RED_NAMES=1 ;; esac; done; set +f; return 0
