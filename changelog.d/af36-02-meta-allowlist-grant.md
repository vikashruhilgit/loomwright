<!-- bump: minor -->
The repo allowlist travels as a tracked request file; only same-repo entries are granted
`setup-memory.sh allowlist` reads a new tracked request file, `.agent/meta-allowlist.txt` (seeded with this repo's
current and pre-rename slugs), as part of precedence layer 4 beside the current-remote default: `--allow` →
`$LOOMWRIGHT_MEMORY_REPO_ALLOWLIST` → the `.supervisor/config.json` array → the remote plus the request file's
GRANTED entries. A listed slug is only a request. It is granted only when `gh api repos/<slug> --jq .id` equals
origin's id, so a renamed repo's redirecting old slug is granted, and a slug naming another repository is ignored
and named on stderr (`allowlist: ignored <slug> — not this repository`). `gh` is a new optional dependency that
fails closed: when it is missing or failing, no request entry is granted and the layer yields the remote alone,
as before. Layers 1–3 still win with the file unread and no `gh` call. Origin's own slug never needs `gh`, a
malformed entry is never passed to it, a filesystem-path origin grants nothing, and origin's id is looked up
lazily, so no file (or an own-slug-only file) makes zero calls. Status lines go to stderr, so stdout stays the
list that `meta-sync.sh`'s push scrub and `validate-entry.sh` read. New legs in `test-setup-memory.sh` (six
mutants) and `test-meta-sync.sh` (a fresh clone with no config pushes old-slug history; a mutant without the
layer is refused) use stubbed `gh`. `/setup memory` docs, the consent disclosure, the setup skill's
"does not travel" lesson and `validate-entry.sh`'s restated precedence now describe the request/grant split.
Honest limit, verified live on 2026-10-12: `vikashruhilgit/ai-agent-manager` is now a separate repository on GitHub (created 2026-07-02), not a redirect, so the seeded old slug is correctly refused here and this repo's old-slug ledger records still need `.supervisor/config.json` on a fresh clone; resolving that is an owner follow-up.
