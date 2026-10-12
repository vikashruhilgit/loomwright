Runtime scripts find the plugin root through the vendor-neutral LOOMWRIGHT_ROOT
The scripts that read the plugin's install root at runtime now get it from `resolve-loomwright-root.sh` instead of
reading the Claude Code variable themselves: the validate-entry lookup in `add-orientation.sh`, `add-rule.sh`,
`audit-rules.sh`, `write-agent-memory.sh`, `write-lessons.sh`, `write-project-memory.sh` and
`write-system-contract.sh`, plus `validate-entry.sh` (its setup-memory lookup), `build-handoff.sh` (its reader
lookup) and `automate-lanes.sh` (the lane's `--plugin-dir`). A non-Claude adapter can now set `LOOMWRIGHT_ROOT` and
these scripts honour it. Each sources the resolver in a subshell, so nothing new is exported, and falls back to its
old location-derived path when the resolver beside it is missing. Behaviour change: when the Claude variable is unset,
a pre-set `LOOMWRIGHT_ROOT` now wins over the location-derived fallback, so the suites that unset the Claude variable to
exercise that fallback now unset `LOOMWRIGHT_ROOT` too. Each of those suites gains a case proving a pre-set
`LOOMWRIGHT_ROOT` is used, and each case was shown to fail against the old harness-only lookup.
`set-otel-resource-attrs.sh` stays on the Claude variable and is labelled Claude-only adapter code. Printed
instructions, the two `hooks.json` parsers and prose-asserting tests are unchanged. The vendor-coupling allowances
for the migrated scripts are lowered (six reach zero and are removed). Nine test allowances rise by one each, for the
single unset that keeps the new case hermetic. `docs/CORE_CONTRACT.md` §"Root resolution" records the new state.
