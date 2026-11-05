# Evidence — touches-name-shared-files-at-intake, Validation 2 (live Product Owner run)

A live headless `/loomwright:product-owner --non-interactive` run on a scratch fixture whose feature must register
in an existing command index. The persisted story's `## Touches` lists that existing index file and the test that
pins the registered list, and the contract change the sweep found (the pinned list) landed as an Acceptance
Criterion rather than a contract-change flag. Run 2026-11-05 on this branch's checkout with the sweep edits on disk
(content of commit `01050da`).

## Fixture

A scratch git repo under the session scratchpad (`po-fixture/`, never this repo), one commit:

```
.
├── CLAUDE.md
├── package.json
├── src
│   ├── cli.ts
│   └── commands
│       ├── hello.ts
│       ├── index.ts
│       └── types.ts
└── tests
    └── commands.test.ts
```

- `src/commands/index.ts` — the registry: `import { hello } from "./hello"; export const commands: Command[] = [hello];` plus `dispatch(name, args)`.
- `src/commands/hello.ts` — the one existing command (`Hello, ${args[0] ?? "world"}!`).
- `tests/commands.test.ts` — asserts `commands.map((c) => c.name)` equals `["hello"]`, and dispatches `hello`.
- `CLAUDE.md` — an `## Architecture` section (every command is registered in `src/commands/index.ts`; the test pins the list; test command `npm test`) and a `## Domain Knowledge` section, so no domain flag opens.
- No `.beads/`, no `.agent/` (so file-fallback persistence, no house rules, no companions rules).

## Command

Run from the fixture root, Claude Code 2.1.318:

```
claude -p "/loomwright:product-owner --non-interactive feature: \"add a goodbye command that prints 'Goodbye, <name>!' (default name: world). After the change the registered command list is exactly [\\\"hello\\\", \\\"goodbye\\\"], in that order.\"" \
  --plugin-dir <checkout>/loomwright --allowedTools "Read,Write,Edit,Glob,Grep,Bash" < /dev/null
```

Exit 0. The prompt sits before `--allowedTools` on purpose: a first attempt put it after, the variadic flag
swallowed it, and the CLI exited 1 with `Input must be provided either through stdin or as a prompt argument`
before any session started.

The run used the checkout, not an installed copy: every plugin path in the session transcript is under
`<checkout>/loomwright/scripts/` (`read-product.sh`, `read-rules.sh`, `propose-product.sh`, `automate-helpers.sh`),
none under `~/.claude/plugins/cache/`; the expanded command carries the new `**Shared-file sweep:**` bullet and the
`contract-change flags` `<n>` term (each found in the transcript), and the run's report prints the new
`Contract changes:` Assumption Check line, which no released prompt has.

## Run output (Assumption Check, as reported)

```
- [!] **Contract changes:** None that need an owner decision. The test at `tests/commands.test.ts:6` currently
  requires the command list to be exactly `["hello"]`. The request names the new list (`["hello", "goodbye"]`, in
  that order), so I wrote it into the acceptance criteria instead of raising it as an open question.
```

No `po_gate` line (no flag open), one story persisted as
`.supervisor/requirements/2026-11-05-200638-goodbye-command.md`; `plan-waves --lint` passed and `right-size` said
`small` with no batch candidate to fold into.

## Persisted story (excerpt)

The contract-change AC:

```
- [ ] Given the command registry, when the registered command names are listed, then they are exactly `["hello", "goodbye"]`, in that order (contract change: the registry test currently pins `["hello"]` and must be updated to this exact list)
```

The persisted `## Touches`, verbatim:

```
## Touches
src/commands/goodbye.ts
src/commands/index.ts
tests/commands.test.ts
```

`src/commands/index.ts` is the existing index the feature must register in, and `tests/commands.test.ts` is the
existing test that pins the registered list: both are existing files the story plugs into, beside the one new file
it creates.

## Limits

- One run of a model, so it shows the instruction is followed, not that it always is.
- No control run on the base prompt. The fixture's CLAUDE.md names the registry and its test, so the base prompt
  might also have listed them here; this run proves the new behaviour is present, not the size of the improvement.
  The post-merge measure of that is the owner's loomwright-studio item 06 re-run.

Verdict: PASS for Validation 2
