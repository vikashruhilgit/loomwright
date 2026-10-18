<!-- bump: patch -->
setup-memory.sh and meta-sync.sh are split into sourced modules (move-only)
`loomwright/scripts/setup-memory.sh` and `loomwright/scripts/meta-sync.sh` are now thin entry points. Each sources
one module per concern, by name, from `setup-memory.d/` or `meta-sync.d/` (automate-speed/20, owner decision D6). A
change to the memory gate or the metadata-branch sync now edits a small file, so two lanes of one wave stop colliding
on two very large scripts. The code moved verbatim: each entry point's `_sm_bundle` / `_ms_bundle` output, with the
loader and the source-marker lines removed, equals the base blob byte for byte. Every subcommand, flag, `--help`
text, output byte and exit code is unchanged, and so are the scrub rules and the managed set. A missing module
refuses with `missing module file: <script>.d/<name>.sh` before any lock, fetch or write. Each entry's header
gains a `# Modules` map that names the module holding each function. `test-setup-memory.sh` and
`test-meta-sync.sh` are thin runners over named parts in `test-setup-memory.d/` and `test-meta-sync.d/`. Both
report the same totals as base. Their text reads (the `sed` mutant sources, the `cmp` gates and the static greps)
go through the bundle, and every run still uses the real entry point. Two new tests,
`test-setup-memory-modules.sh` and `test-meta-sync-modules.sh`, check the dispatch, the loader refusal, the
by-name sourcing and the verbatim move. Tests that copy one of the two scripts into a staging dir now copy its
`.d` folder too. Their mutants read the bundle (setup-only edits, no expected value changed). The vendor-coupling
allowances moved with their references, and the flat total is unchanged. Two line-pinned citations were
re-pointed. Measurements are in `docs/evidence/as20-split-memory-and-meta-scripts.md`.
