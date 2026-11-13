#!/usr/bin/env bash
# test-cli.sh — pins selvedge/bin/selvedge: --version is the manifest's version read at run time
# (directly, from a fixture copy with a different version, and through the install-cli symlink),
# the no-argument help lists install-cli, and install-cli links, re-runs cleanly, and refuses to
# replace a regular file.
#
# Hermetic: every install-cli run gets a fresh temp HOME; the user's ~/.local/bin is never touched.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$TESTS_DIR/.." && pwd)"
CLI="$PLUGIN_DIR/bin/selvedge"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/selvedge-cli.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home-default"
mkdir -p "$HOME"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "  ok   $1"; }
ko() { fail=$((fail + 1)); echo "  FAIL $1"; }

# The expected version comes from the manifest via jq — an independent reader from the CLI's own.
want="selvedge $(jq -r '.version' "$PLUGIN_DIR/.claude-plugin/plugin.json")"

out="$(bash "$CLI" --version 2>&1)"; rc=$?
[ "$rc" -eq 0 ] && [ "$out" = "$want" ] && ok "--version prints the manifest version ($want)" || ko "--version: rc=$rc out='$out' want='$want'"

out="$(bash "$CLI" 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && grep -qxF "$want" <<<"$out" && grep -qE '^ +install-cli ' <<<"$out"; } \
  && ok "no arguments prints the version and a subcommand list with install-cli" || ko "no-arg help: rc=$rc out='$out'"

out="$(bash "$CLI" no-such-command 2>&1)"; rc=$?
[ "$rc" -eq 2 ] && ok "unknown command exits 2" || ko "unknown command: rc=$rc"

# Not a literal: a fixture copy with another version reports that version.
fx="$TMP/fixture-plugin"
mkdir -p "$fx/bin" "$fx/.claude-plugin"
cp "$CLI" "$fx/bin/selvedge"
jq '.version = "9.8.7"' "$PLUGIN_DIR/.claude-plugin/plugin.json" > "$fx/.claude-plugin/plugin.json"
out="$(bash "$fx/bin/selvedge" --version 2>&1)"
[ "$out" = "selvedge 9.8.7" ] && ok "--version is read from the manifest at run time (fixture 9.8.7)" || ko "fixture --version: '$out'"
jq -c '.version = "9.8.6"' "$PLUGIN_DIR/.claude-plugin/plugin.json" > "$fx/.claude-plugin/plugin.json"
out="$(bash "$fx/bin/selvedge" --version 2>&1)"
[ "$out" = "selvedge 9.8.6" ] && ok "--version reads a minified (one-line) manifest" || ko "minified manifest --version: '$out'"
rm "$fx/.claude-plugin/plugin.json"
out="$(bash "$fx/bin/selvedge" --version 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && grep -qF "manifest not found" <<<"$out"; } && ok "a missing manifest fails, naming it" || ko "missing manifest: rc=$rc out='$out'"

# install-cli: link, print, re-run.
export HOME="$TMP/home-install"
mkdir -p "$HOME"
dest="$HOME/.local/bin/selvedge"
out="$(bash "$CLI" install-cli 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && [ -L "$dest" ] && [ "$(readlink "$dest")" = "$CLI" ]; } \
  && ok "install-cli creates $HOME/.local/bin/selvedge -> bin/selvedge" || ko "install-cli: rc=$rc link='$(readlink "$dest" 2>/dev/null)' out='$out'"
grep -qF "$dest" <<<"$out" && ok "install-cli prints what it did" || ko "install-cli output does not name $dest: '$out'"
grep -qF "is not on your PATH" <<<"$out" && ok "install-cli says when \$HOME/.local/bin is not on PATH" || ko "no PATH note: '$out'"
out="$(PATH="$HOME/.local/bin:$PATH" bash "$CLI" install-cli 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && [ -L "$dest" ] && grep -qF "already links" <<<"$out"; } \
  && ok "a second install-cli run succeeds and says it had nothing to do" || ko "second install-cli: rc=$rc out='$out'"
grep -qF "is not on your PATH" <<<"$out" && ko "PATH note printed although \$HOME/.local/bin is on PATH: '$out'" || ok "no PATH note when \$HOME/.local/bin is on PATH"

# Through the symlink: the CLI resolves its real path, so the manifest is still found.
out="$("$dest" --version 2>&1)"
[ "$out" = "$want" ] && ok "--version through the install-cli symlink prints the manifest version" || ko "via symlink: '$out'"
# Through a relative link to that link (a two-hop chain).
ln -s "selvedge" "$HOME/.local/bin/sv-alias"
out="$("$HOME/.local/bin/sv-alias" --version 2>&1)"
[ "$out" = "$want" ] && ok "--version through a relative two-hop symlink chain" || ko "via two-hop chain: '$out'"

# A regular file at the destination is never overwritten.
export HOME="$TMP/home-regular"
mkdir -p "$HOME/.local/bin"
dest="$HOME/.local/bin/selvedge"
printf '#!/bin/sh\necho mine\n' > "$dest"
cp "$dest" "$TMP/regular.orig"
out="$(bash "$CLI" install-cli 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "install-cli over a regular file exits non-zero" || ko "install-cli over a regular file exited 0: '$out'"
grep -qF "refusing to overwrite" <<<"$out" && ok "it prints the refusal" || ko "no refusal message: '$out'"
{ [ ! -L "$dest" ] && cmp -s "$dest" "$TMP/regular.orig"; } && ok "the regular file is left byte-identical" || ko "the regular file was changed"

# A directory at the destination is refused too.
export HOME="$TMP/home-dir"
mkdir -p "$HOME/.local/bin/selvedge"
out="$(bash "$CLI" install-cli 2>&1)"; rc=$?
{ [ "$rc" -ne 0 ] && [ -d "$HOME/.local/bin/selvedge" ] && [ ! -L "$HOME/.local/bin/selvedge" ]; } \
  && ok "install-cli over a directory exits non-zero and leaves it" || ko "install-cli over a directory: rc=$rc out='$out'"

# A symlink pointing elsewhere is replaced, and the output says what it pointed to.
export HOME="$TMP/home-other-link"
mkdir -p "$HOME/.local/bin"
ln -s "$TMP/elsewhere" "$HOME/.local/bin/selvedge"
out="$(bash "$CLI" install-cli 2>&1)"; rc=$?
{ [ "$rc" -eq 0 ] && [ "$(readlink "$HOME/.local/bin/selvedge")" = "$CLI" ] && grep -qF "it pointed to $TMP/elsewhere" <<<"$out"; } \
  && ok "install-cli replaces a link pointing elsewhere and reports the old target" || ko "other-link replace: rc=$rc out='$out'"

out="$(HOME="" bash "$CLI" install-cli 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "install-cli with an empty HOME exits non-zero" || ko "empty HOME: rc=$rc out='$out'"

echo "test-cli: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
