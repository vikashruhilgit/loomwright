<!-- bump: patch -->
The tracked allowlist request file no longer requests the pre-rename slug
`.agent/meta-allowlist.txt` drops `vikashruhilgit/ai-agent-manager`. That slug is a separate repository on GitHub now,
not a redirect, so `setup-memory.sh allowlist` already refused it (`not this repository`). The run history on the
metadata branch was rewritten to `vikashruhilgit/loomwright` (42 ledger records plus forge URLs), so nothing still
needs it. The file's note now records why the entry is gone. Data only: no script or behavior change.
