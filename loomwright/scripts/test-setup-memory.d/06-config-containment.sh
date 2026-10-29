# 06-config-containment.sh — test part for test-setup-memory.sh (sourced BY NAME at top level, so it
# shares that file's fixtures, helpers and counters; never run on its own).
#
# (cc) physical-path containment of the allowlist writer. `apply` seeds the repo allowlist into
# <repo>/.supervisor/config.json; a repo that commits a symlinked `.supervisor -> <elsewhere>`
# must not make that write — or its backup — land outside the repo. seed_allowlist therefore asks
# contained-path-lib.sh (cpl_check_write) before it touches anything, and SKIPS with the named
# reason instead. Cases:
#   (a) symlinked parent -> outside, with a pre-existing outside config: SKIPPED — path_outside_repo,
#       the outside folder byte-identical (listing + cksum), no backup, no temp; gated mutation
#       control: neutralising the cpl_check_write call lets the same fixture write outside
#   (b) `.supervisor -> ./real-supervisor` inside the repo, and `--root <relative>`: still seeded
#   (c) a repo reached through a symlinked ANCESTOR: still seeded
#   (d) a symlinked LEAF (config.json -> an inside file): SKIPPED — symlink, link and target
#       unchanged (a deliberate tightening: the write used to `mv` over the link)
# Fixtures are mktemp dirs under FIXTURE_ROOT (newgit / mkfix); the plugin repo is never touched.
echo "== (cc) physical-path containment of the allowlist writer =="

# cc_sig <dir> — a byte-level fingerprint of a directory: sorted listing + a cksum per file.
cc_sig() { { (cd "$1" && find . -print | LC_ALL=C sort && find . -type f -exec cksum {} + | LC_ALL=C sort); } 2>&1; }
# cc_repo — a fresh git fixture with an origin (so apply has a slug to seed) and a .gitignore.
cc_repo() {
  local d; d="$(newgit https://github.com/acme/widget.git)"
  printf 'node_modules/\n.supervisor/\n' > "$d/.gitignore"
  printf '%s' "$d"
}

# (a) symlinked parent -> outside
CC_OUT="$(mkfix)"; printf '{"keep":1}\n' > "$CC_OUT/config.json"
CC_A="$(cc_repo)"; ln -s "$CC_OUT" "$CC_A/.supervisor" || setup_fail "(cc-a) could not link .supervisor -> outside"
cc_a0="$(cc_sig "$CC_OUT")"
o="$(mem "$CC_A" apply 2>&1)"
if hasF "allowlist: SKIPPED — path_outside_repo:" "$o" && hasF "nothing was written (unchanged)" "$o"; then ok "(cc-a) .supervisor -> outside: allowlist SKIPPED — path_outside_repo"; else no "(cc-a) symlinked parent not refused with path_outside_repo: $(grep allowlist <<< "$o")"; fi
[ "$(cc_sig "$CC_OUT")" = "$cc_a0" ] && ok "(cc-a) the outside folder is byte-identical (listing + cksum)" || no "(cc-a) THE OUTSIDE FOLDER CHANGED"
[ -z "$(ls "$CC_OUT" | grep -v '^config\.json$')" ] && ok "(cc-a) no backup and no temp file was left beside the outside config" || no "(cc-a) stray file(s) in the outside folder: $(ls "$CC_OUT" | tr '\n' ' ')"
[ "$(cat "$CC_OUT/config.json")" = '{"keep":1}' ] && ok "(cc-a) the outside config content is unchanged" || no "(cc-a) outside config content changed"

# (a-mut) gated mutation control: neutralise the cpl_check_write call ⇒ the same fixture writes outside
CC_MUT="$(mkfix)"
sed 's/cpl_check_write allowlist/true allowlist/' "$MEMB" > "$CC_MUT/setup-memory.sh"
cp "$HERE/contained-path-lib.sh" "$CC_MUT/" || setup_fail "(cc-mut) could not place contained-path-lib.sh beside the mutant"
if [ ! -s "$CC_MUT/setup-memory.sh" ] || cmp -s "$MEMB" "$CC_MUT/setup-memory.sh" || ! bash -n "$CC_MUT/setup-memory.sh" 2>/dev/null; then
  no "(cc-mut) mutation control: the mutant did not build (empty, sed matched nothing, or bash -n failed) — inconclusive"
else
  CC_OUT2="$(mkfix)"; printf '{"keep":1}\n' > "$CC_OUT2/config.json"
  CC_M="$(cc_repo)"; ln -s "$CC_OUT2" "$CC_M/.supervisor" || setup_fail "(cc-mut) could not link .supervisor -> outside"
  cc_m0="$(cc_sig "$CC_OUT2")"
  bash "$CC_MUT/setup-memory.sh" --root "$CC_M" apply >/dev/null 2>&1
  if [ "$(cc_sig "$CC_OUT2")" != "$cc_m0" ]; then ok "(cc-mut) mutation control: without the cpl_check_write call the allowlist writes OUTSIDE the repo — case (a) bites"
  else no "(cc-mut) mutation control: the mutant did not write outside — case (a) is vacuous"; fi
fi

# (b) .supervisor -> ./real-supervisor inside the repo
CC_B="$(cc_repo)"; mkdir -p "$CC_B/real-supervisor"; ln -s ./real-supervisor "$CC_B/.supervisor" || setup_fail "(cc-b) could not link .supervisor -> ./real-supervisor"
o="$(mem "$CC_B" apply 2>&1)"
if hasF "allowlist: seeded as a JSON array" "$o" && [ "$(jq -r '.setup_memory.repo_allowlist | type' "$CC_B/real-supervisor/config.json" 2>/dev/null)" = "array" ]; then ok "(cc-b) .supervisor -> ./real-supervisor (inside the repo): still seeded"; else no "(cc-b) inside-pointing symlink falsely refused: $(grep allowlist <<< "$o")"; fi
# (b) --root <relative>: a repo named relatively, from its parent and from within
CC_B2="$(cc_repo)"
o="$(cd "$(dirname "$CC_B2")" && bash "$MEM" --root "$(basename "$CC_B2")" apply 2>&1)"
if hasF "allowlist: seeded as a JSON array" "$o" && [ -s "$CC_B2/.supervisor/config.json" ]; then ok "(cc-b) --root <relative-name> run from the repo's parent: seeded"; else no "(cc-b) --root <relative-name> falsely refused: $(grep allowlist <<< "$o")"; fi
CC_B3="$(cc_repo)"
o="$(cd "$CC_B3" && bash "$MEM" --root . apply 2>&1)"
if hasF "allowlist: seeded as a JSON array" "$o" && [ -s "$CC_B3/.supervisor/config.json" ]; then ok "(cc-b) --root . run from inside the repo: seeded"; else no "(cc-b) --root . falsely refused: $(grep allowlist <<< "$o")"; fi
# (b) --root <relative> with the symlinked-parent fixture is still refused (relative does not bypass)
CC_OUT3="$(mkfix)"; printf '{"keep":1}\n' > "$CC_OUT3/config.json"
CC_B4="$(cc_repo)"; ln -s "$CC_OUT3" "$CC_B4/.supervisor" || setup_fail "(cc-b) could not link .supervisor -> outside"
cc_b40="$(cc_sig "$CC_OUT3")"
o="$(cd "$CC_B4" && bash "$MEM" --root . apply 2>&1)"
{ hasF "allowlist: SKIPPED — path_outside_repo:" "$o" && [ "$(cc_sig "$CC_OUT3")" = "$cc_b40" ]; } && ok "(cc-b) --root . with .supervisor -> outside is still refused, outside untouched" || no "(cc-b) --root . bypassed the containment check: $(grep allowlist <<< "$o")"

# (c) the repo is reached through a symlink ABOVE its root
CC_C="$(cc_repo)"; CC_CL="$(mkfix)"
ln -s "$(dirname "$CC_C")" "$CC_CL/link" || setup_fail "(cc-c) could not link the repo's parent"
o="$(mem "$CC_CL/link/$(basename "$CC_C")" apply 2>&1)"
if hasF "allowlist: seeded as a JSON array" "$o" && [ -s "$CC_C/.supervisor/config.json" ]; then ok "(cc-c) repo reached through a symlinked ancestor: seeded"; else no "(cc-c) symlinked ancestor falsely refused: $(grep allowlist <<< "$o")"; fi

# (d) leaf symlink: config.json -> an inside file
CC_D="$(cc_repo)"; mkdir -p "$CC_D/.supervisor"; printf '{"keep":1}\n' > "$CC_D/.supervisor/target.json"
ln -s target.json "$CC_D/.supervisor/config.json" || setup_fail "(cc-d) could not link config.json -> target.json"
cc_d0="$(cc_sig "$CC_D/.supervisor")"
o="$(mem "$CC_D" apply 2>&1)"
{ hasF "allowlist: SKIPPED — symlink:" "$o" && [ "$(cc_sig "$CC_D/.supervisor")" = "$cc_d0" ] && [ "$(readlink "$CC_D/.supervisor/config.json")" = "target.json" ] && [ "$(cat "$CC_D/.supervisor/target.json")" = '{"keep":1}' ]; } \
  && ok "(cc-d) config.json symlinked (even to an inside file): SKIPPED — symlink, link and target unchanged, no backup" || no "(cc-d) leaf symlink not refused cleanly: $(grep allowlist <<< "$o")"
