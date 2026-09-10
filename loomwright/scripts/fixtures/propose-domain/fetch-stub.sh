#!/usr/bin/env bash
# fetch-stub.sh - the committed stand-in for PROPOSE_DOMAIN_FETCH_CMD.
#
# propose-domain.sh performs EVERY external call through one seam: it invokes
# `$PROPOSE_DOMAIN_FETCH_CMD <url>` and reads the source text from stdout. This stub is that
# command for tests: it never opens a socket, it maps a fixture url to a committed source file,
# and it optionally RECORDS every call so a test can assert on the number of external calls made
# rather than on what the script's code appears to do.
#
#   PROPOSE_DOMAIN_FETCH_CALLS=<file>   append one line per invocation (the url). This is the
#                                       stub's own knob, not one of propose-domain.sh's. Give it
#                                       a `.txt` path, never a `.log` one - see this directory's
#                                       README.md, "Why no fixture uses a .log extension".
#
# An unknown url exits 1 with no output, which is how a test exercises a FAILED fetch.
set -u

here="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
url="${1:-}"

if [ -n "${PROPOSE_DOMAIN_FETCH_CALLS:-}" ]; then
  printf '%s\n' "$url" >> "$PROPOSE_DOMAIN_FETCH_CALLS" 2>/dev/null || true
fi

case "$url" in
  *acme-docs*)      cat "$here/source-acme.txt" ;;
  *bolt-knowledge*) cat "$here/source-bolt.txt" ;;
  *cursive-wiki*)   cat "$here/source-cursive.txt" ;;
  *)                exit 1 ;;
esac
