# Evidence — provider probe (`setup-providers.sh check`)

Real output from this machine (the owner's macOS dev box), captured 2026-10-27 at 11:11 UTC on branch
`feature/providers-probe-setup-check`, base commit `84d9023b2d7561c3c34929df3e64696bad7b2339`. Source requirement:
`.supervisor/requirements/provider-routing/02-providers-probe.md`. This is the input item 03 rewrites its premises
from.

Nothing in the transcript is hand-written. The one edit is path redaction: the repo root reads `<repo>`.

## CLI versions on this machine

| CLI | On PATH | Version |
|-----|---------|---------|
| `claude` | yes | `2.1.309 (Claude Code)` |
| `cursor-agent` | yes | `2026.10.22-27dcf5f` (it was `2026.09.18-9a7762b` earlier the same day; it updated itself between two runs) |
| `codex` | no | — |
| `gemini` | no | — |
| `grok` | no | — |
| `copilot` | no | — |

## The report

```text
$ bash loomwright/scripts/setup-providers.sh check
setup-providers check — read-only probe of the provider table
  date: 2026-10-27T11:11:50Z · providers dir: <repo>/loomwright/scripts/adapters/providers
  smoke: fixed prompt (no repo content) · cwd: a throwaway mktemp -d dir, never the repo · HOME: the REAL HOME (login state lives there; never scrubbed) · timeout 120s (other calls 20s)
  writes: only its own mktemp -d scratch dir, removed on exit · never installs anything · never reads, prints or stores an API key or token
  limit: a provider CLI may write its own session/state files under the real HOME while the smoke runs
  legend: a ":" after a column name marks a column that did not pass

claude: installed 2.1.309 (Claude Code) · auth ok · headless pass · permissions pinnable · browser: unknown => usable for write seats
codex: installed: no => not usable: installed
    install: npm install -g @openai/codex
copilot: installed: no => not usable: installed
    install: npm install -g @github/copilot
cursor (cursor-agent): installed 2026.10.22-27dcf5f · auth ok · headless pass · permissions: unpinnable · browser: unknown => usable for read-only seats
gemini: installed: no => not usable: installed
    install: npm install -g @google/gemini-cli
grok: installed: no => not usable: installed
    install: curl -fsSL https://x.ai/cli/install.sh | bash
$ echo $?
0
```

The run took about 28 seconds; nearly all of it is the two real smokes.

## What the report establishes

- **`claude`: usable for write seats.** Auth came from its own auth-status command, the smoke returned the fixed
  reply inside the `.result` envelope the lens adapter unwraps, and `--help` advertises the same permission-pinning
  flags `dispatch-pr-review.sh` requires before it dispatches.
- **`cursor-agent`: usable for read-only seats, not write seats.** It was logged in on 2026-10-27, which corrects the
  source requirement's premise that it was not. The smoke passed, and the reply came back in a top-level `.result`
  string, so the lens adapter's envelope guess for this CLI held. Permissions are `unpinnable` by its table entry's
  declaration: print mode "Has access to all tools", there is no per-invocation allowlist flag, and the entry never
  adopts `-f`/`--force`. The smoke needs `--trust`. Without it, print mode exits 1 with "Workspace Trust Required"
  for any directory it has not seen, and the smoke's cwd is always new.
- **`grok`: OUTSTANDING.** `grok` was not installed when this item ran, so the row above is the real
  `installed: no` row. The real-binary report AC2 asks for (real values in the installed, auth and headless columns)
  **has not been produced**. It is still owed once the owner installs and logs in to `grok`: re-run the command
  above and append the output here. Until then every `grok` invocation field in `provider-grok.sh` is a DOCUMENTED
  ASSUMPTION taken from docs.x.ai (cited with dates in that file's header). The stub suite covers the code paths, but
  no real `grok` binary has exercised them.
- **`codex`, `gemini`, `copilot`:** not installed. Their rows show the install hint, nothing else ran, and their
  table fields stay DOCUMENTED ASSUMPTIONs.
- **`browser` is `unknown` for every provider.** No probe has shown any of them driving a browser.

## Honest limits

- **The script's own writes are contained. A vendor CLI's writes are not.** `test-setup-providers.sh` asserts, with
  stub CLIs and a temp HOME, that the script writes nothing outside its `mktemp -d` scratch dir and removes that on
  exit. A real smoke runs a real vendor CLI under the real HOME, and that CLI may write its own state. What was
  observed after this run:
  - `cursor-agent` created a per-directory entry under its own projects directory in the home tree, named after the
    smoke's throwaway cwd. Each run adds one. It also updated itself between two runs the same day.
  - `claude` left no project or session entry for the smoke's cwd under its own config tree. The smoke passes
    `--no-session-persistence` and `--safe-mode`, which skips user hooks, plugins and MCP servers.
- **The smoke spends real model calls.** Each installed, logged-in provider answers one short fixed prompt per
  `check` run.
- **`pinnable` means the pinning flags exist in `--help`.** For `claude` that is the same test the drain dispatcher
  already relies on. For `grok` and `copilot` it would mean only that their documented flags are present. No
  denial has been observed on a real binary.
- **Auth for `grok`, `copilot`, `codex` and `gemini` is decided by the smoke.** None of them documents a
  non-interactive auth-status command that this item could find. A passing smoke proves auth. A failing smoke is
  reported `not_logged_in` only when its output matches the table entry's not-logged-in pattern, and that pattern
  is a guess at the vendor's wording until a real logged-out run confirms it.
