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
lazily, so no file (or an own-slug-only file) makes zero calls. Only a github.com origin is checked: `gh api`
asks github.com, so a GitLab, Bitbucket or GitHub Enterprise origin would be compared with a github.com namesake;
such an origin grants nothing and makes no `gh` call. Every `gh` call is bounded by
`LOOMWRIGHT_ALLOWLIST_GH_TIMEOUT` seconds (default 10; portable, no `timeout` binary). On overrun `gh` is killed with
its whole process group, so a child it left holding the output pipe (one that ignores TERM, or one an exit-0 `gh`
never waited for) cannot outlast the bound, and the call counts as failing. One overrun stops further calls, so a
hung `gh` costs `validate-entry.sh` or `meta-sync.sh` at most two bounds plus a 1s kill grace each; a descendant
that deliberately leaves the process group is not covered. The runner writes no temp file (it reads `gh` through a pipe), so `allowlist` still writes nothing. The request file is untrusted input, so the work it drives is capped too: at most 20 non-own entries are compared per resolution (`LOOMWRIGHT_ALLOWLIST_MAX_ENTRIES`, clamped to 100), each later entry is named (`over the 20-entry cap`) and never passed to `gh`, and reading stops after 200 lines. A request file that exists but cannot be read (mode 000, a directory) is named on stderr (`allowlist: ignored .agent/meta-allowlist.txt — not readable`) and grants nothing; an absent one stays silent. Origin's slug and host come from one `git remote get-url origin` per resolution through one URL parser, so the github.com gate can never disagree with the slug it gates. Results are not cached across invocations, by design: a cache would be a file and `allowlist` writes none; the lazy lookup, the bound and the cap limit the cost, and `.supervisor/config.json`'s array skips the request file (and `gh`) entirely. Status lines go to stderr, so stdout stays the
list that `meta-sync.sh`'s push scrub and `validate-entry.sh` read. New legs in `test-setup-memory.sh` (thirteen
mutants, including the host check, the single origin read, the unreadable-file line, the overrun check, the process-group signal and poll, and the entry cap) and `test-meta-sync.sh` (a fresh clone with no config pushes old-slug history; a mutant without the
layer is refused) use stubbed `gh`, and the legs of `test-validate-entry.sh` and `test-committed-twin-scrub.sh` that
resolve the allowlist against the real checkout run behind a failing `gh` stub, so a fresh clone makes no network call. `/setup memory` docs, the consent disclosure, the setup skill's
"does not travel" lesson and `validate-entry.sh`'s restated precedence now describe the request/grant split.
Honest limit, verified live on 2026-10-12: `vikashruhilgit/ai-agent-manager` is now a separate repository on GitHub (created 2026-07-02), not a redirect, so the seeded old slug is correctly refused here and this repo's old-slug ledger records still need `.supervisor/config.json` on a fresh clone; resolving that is an owner follow-up.
