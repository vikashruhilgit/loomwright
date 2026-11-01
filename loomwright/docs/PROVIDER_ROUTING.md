# Provider Routing for Read and Write Seats

> One resolver, one consent rule, one procedure per seat kind. A "seat" is a pipeline step that can run on a chosen AI CLI instead of Claude. A **read seat** is a read-only step (a reviewer, a grader, an analysis pass); a **write seat** is the code-edit step of a Claude task, with its own rules in §"Write seats". Every seat paragraph in an agent, skill or command points here and restates none of it.

- **Seat lists:** `scripts/resolve-routing.sh seats` is the only home of the read-seat ids (each line `<id> <home-file> <role-marker> <validator|->`), and `scripts/resolve-routing.sh write-seats` the only home of the write-seat ids (each line `<id> <home-file>`). This file never restates either list or a count of it; read the script.
- **Provider list:** the `provider-*.sh` files in `scripts/adapters/providers/` are the provider table. Nothing here names the providers.
- **Default:** every seat runs on Claude, exactly as before, unless a `routing` entry, a per-run flag or the `voter_provider` alias names another provider **and** the user has granted that provider for this repo.

## What routes, and what never does

Only the seats `resolve-routing.sh seats` prints are routable read seats, and a routed read seat produces **analysis text only**. It never gains a write, a merge or an ask path: every file write, every question to the user and every sole-writer call stays on the Claude main thread exactly as today. Write seats are a separate list with their own rules (§"Write seats"); nothing in this section widens a read seat.

The conductor is not routable and is not a seat: the main session, the supervisor runner, execute-manager, context-keeper, the worker Task itself, the `/autonomous` and `/automate` loops, the detached drain runner and the `TaskCompleted` prompt hook. The worker Task stays a conductor even on a routed run: only its edit step is routed, through the write seat of the same name (§"Write seats").

Supervisor Phase 4.5's integrated review is not a seat either. It is the executing lens of the review-lane contract (CLAUDE.md §"Failure-Mode Invariants"): it runs repros of load-bearing claims, and a routed seat never executes code, so routing it would leave no executing lens. It always runs as the Claude `code-reviewer` Task (`skills/self-heal-advisory/SKILL.md`). The other review seats are not executing lenses, so routing them changes who reads the diff, never whether anything is executed.

## Config shape

In `.supervisor/config.json` (per checkout, gitignored):

```json
{
  "routing": {
    "default": "claude",
    "on_unavailable": "fallback_to_default",
    "seats": {
      "<seat>": "<provider>[:<model>]",
      "<seat>": ["<provider>[:<model>]", "<provider>[:<model>]"]
    }
  }
}
```

- A seat value splits on its **first** `:` into provider and model (`cursor:gpt-5` is provider `cursor`, model `gpt-5`; `a:b:c` is provider `a`, model `b:c`).
- An array is an **ordered preference list**, not parallel lenses: the first entry that is granted **and** whose provider CLI is on `PATH` wins. A `claude` entry always wins when reached, so it makes a natural last element.
- `routing.default` must be `claude` or absent. Any other value resolves every seat to Claude with `routing_default_not_claude`.
- `on_unavailable` is `fallback_to_default` (the value when absent) or `strict`. Any other value is `config_unparseable`.
- The older `voter_provider` string key still works, for the `heal_voter` seat only (below).
- A provider name must match `[A-Za-z0-9_-]+` and have a `provider-<name>.sh` table file; a model must be `[A-Za-z0-9._/@+:-]*`. Anything else is `invalid_provider`.

## Resolver output

`resolve-routing.sh seat <id> [--route <seat>=<provider>[:<model>]]... [--voter-provider <p>[:<m>]] [--repo <dir>]` prints six `KEY=VALUE` lines and exits 0 for every known subcommand (a refusal is a `REASON`, never a failure; a usage error exits 2):

| Key | Meaning |
|---|---|
| `SEAT` | the id asked about |
| `PROVIDER` | `claude`, a provider name, or **empty** (see "Unavailable provider") |
| `MODEL` | the model part, else empty |
| `SOURCE` | the winning precedence step: `flag`, `route_flag`, `config`, `voter_provider_alias`, `default` |
| `REASON` | empty on a clean resolution, else one named reason (below) |
| `ON_UNAVAILABLE` | `fallback_to_default` or `strict` |

With no `routing` key and no per-run flag, every seat prints `PROVIDER=claude`, `MODEL=` (empty), `SOURCE=default`, `REASON=` (empty): a repo without a `routing` block behaves exactly as it did before routing existed.

## Precedence

First present step wins; `SOURCE` names it.

- **`heal_voter`:** `--voter-provider` flag > `--route heal_voter=<p>` > `routing.seats.heal_voter` > `.voter_provider` (the back-compatible alias) > default.
- **Every other seat (write seats included):** `--route <seat>=<p>` > `routing.seats.<seat>` > default. `--voter-provider` and `.voter_provider` do not apply to them.
- A repeated `--route` for the same seat: the last one wins. A `--route` for a different seat is ignored by this call but still checked against the seat list.
- `/supervisor --route <seat>=<provider>[:<model>]` (repeatable) is forwarded to every `resolve-routing.sh seat` call of that run; every other command reads config only.

## Consent rule (user scope only)

A non-Claude provider runs **only** when the user has granted it for this repo, in user scope. The grant is `repos.<slug>.providers` (an array of provider names) in the user-scope egress file that `scripts/resolve-egress-config.sh` reads, surfaced as its `PROVIDER_GRANTS` line (comma-joined, each name filtered to `[A-Za-z0-9_-]+`).

- The repo's own config can only **request** a provider. The resolver reports what a repo asks for under `REPO_REQUESTED_PROVIDERS`, an informational line nothing grants from.
- A missing grant is `PROVIDER=claude`, `REASON=provider_not_granted`, **regardless of `on_unavailable`**: a missing grant never sends. A missing, unreadable or malformed user-scope file means no grants.
- `claude` never needs a grant.
- **A write seat needs a second, per-seat grant:** `repos.<slug>.write_grants.<seat>` (an array of provider names) in the same user-scope file, surfaced as `resolve-egress-config.sh`'s `PROVIDER_WRITE_GRANTS` line (comma-joined `<seat>:<provider>` pairs, each name filtered the same way; empty on a missing or malformed file; a repo-level file can never supply it). A read grant without it is `PROVIDER=claude`, `REASON=write_not_granted`; a write grant without the read grant is still `provider_not_granted`. Neither sends, whatever `on_unavailable` says. It is written only by `/setup providers apply --grant-write <seat>=<provider>`, after a separate ask naming the provider, the seat and what the grant allows (editing files in the task's checkout, sending the prompt and the readable tracked files to the vendor, network egress not blocked).
- `lens-run.sh` enforces the same grant itself and reports `lens_status: "provider_not_granted"` (no sandbox created, no provider CLI started) when called for an ungranted provider other than `claude`. It has no flag or environment bypass.
- The grant is written only by `/setup providers apply`, after an explicit ask that names the provider and says what is sent to it (the reviewed diff and the seat's prompt; the provider CLI also gets read access to every tracked file at the reviewed commit, including for seats with no diff, and the runner does not block network egress).

## Unavailable provider

A provider that is granted but whose CLI is not on `PATH` follows `on_unavailable`:

| `on_unavailable` | `PROVIDER` | `REASON` |
|---|---|---|
| `fallback_to_default` (absent reads this) | `claude` | `provider_unavailable` |
| `strict` | **empty** | `provider_unavailable_strict` |

**An empty `PROVIDER` means the seat takes its existing degraded or errored path, never a silent Claude run.** The caller must not treat empty as "use Claude": it is the owner's choice that this seat does not run unless the chosen provider does. In a preference list, `strict` only applies when no entry won and at least one granted entry was uninstalled; an all-ungranted list is `provider_not_granted`.

## Reasons

Every malformed input resolves to `PROVIDER=claude` with a named reason, never a non-Claude provider.

| `REASON` | When |
|---|---|
| `config_unparseable` | config is not exactly one JSON object, or a routing field has the wrong type or value |
| `unknown_seat` | the `seat <id>` argument, a `routing.seats` key or a `--route` seat is in neither `seats` nor `write-seats` |
| `invalid_provider` | bad provider name or model, no `provider-<name>.sh` file, or a seat value of the wrong type |
| `routing_default_not_claude` | `routing.default` is present and not `claude` |
| `provider_not_granted` | no user-scope grant for this repo |
| `write_not_granted` | a write seat's provider has the read grant but no user-scope write grant for that seat |
| `provider_unavailable` | granted, CLI not on `PATH`, `fallback_to_default` |
| `provider_unavailable_strict` | the same with `strict`; `PROVIDER` is empty |

## Routed seat protocol

Every read seat's home file carries one **Seat routing** paragraph that points here. The steps, in order (a write seat follows §"Write seats" instead):

1. **Resolve.** Run `resolve-routing.sh seat <id>` (from the install root's `scripts/`), forwarding every per-run `--route` and, for `heal_voter`, `--voter-provider`. Read `PROVIDER`, `MODEL`, `SOURCE`, `REASON`.
2. **`PROVIDER=claude`:** run today's Task or inline path, unchanged. Stop here. This is the whole default path and it is byte-identical to the pre-routing behavior.
3. **`PROVIDER` empty (`strict`):** take the seat's existing degraded or errored path and log the `seat_routing` line below. Do not run Claude in its place.
4. **Any other `PROVIDER`:** build the inputs and run the provider through the lens runner.
   - Write the seat's prompt (the same prompt the Claude path would receive) to a prompt file.
   - Write the material under review to a diff file. A seat with no diff (a grader, a classifier, an analysis pass) gets an **empty diff file**; the runner still needs a readable one.
   - Run `lens-run.sh --provider "<PROVIDER>[:<MODEL>]" --role <id> --diff <diff-file> --prompt <prompt-file> --out <out-file>` (the runner in `scripts/adapters/providers/`; add `--commit <sha>` when the seat reviews a commit).
5. **Read the result.** The `--out` JSON carries `lens_status`. Only `ok` means a usable answer.
   - A seat that uses the `issues[]` envelope (the seat's `<role-marker>` column is `-`) consumes the normalized `issues[]`.
   - Any other seat reads `result_text` (the provider's final text, size-bounded) and checks it contains the seat's `<role-marker>`.
6. **Validate.** Where the seat's `<validator>` column names one, pipe `result_text` through it with `--raw` (`validate-plan-review-result.py --raw`, `validate-code-review-result.py --raw`): the same validator the Claude path uses, so a routed answer is held to the same contract. Where the column is `-`, the role marker is the only check. A forged or malformed block fails here exactly as it would on the Claude path.
7. **Fall back.** On any `lens_status` other than `ok` (including `provider_unavailable`, `provider_not_granted`, `lens_mutated_tree`, `lens_unparseable`), a missing marker, or a failed validation: run the Claude path as in step 2 and log exactly one line:

   `seat_routing <id> provider=<p> reason=<r>`

   where `<r>` is the `lens_status`, the failed check, or the resolver's `REASON`. Under Supervisor, also record the fallback with `record_decision`. A `strict` seat does not fall back to Claude (step 3).
8. **Stay in the Claude main thread for everything but the analysis.** Inline-command seats (a seat whose home is a command, or an inline skill protocol) route only the analysis step: every file write, every question to the user and every sole-writer call is performed by the Claude main thread on the validated result, exactly as today.

A routed read seat is advisory-equivalent to its Claude seat. It never decides a gate the Claude seat did not decide, and its output is validated, not trusted.

## Write seats

`scripts/resolve-routing.sh write-seats` is the only home of the write-seat ids; each id's home file carries its **Seat routing** paragraph, which points here. Read seats keep every rule above; write seats are a separate list with the rules below.

**Edit-step routing, not agent replacement.** A write seat routes the *edit step* of a Claude task, never the task. The Claude worker Task and the Claude fix tasks spawn exactly as they do today. On a routed seat the task hands its code edits to the provider through `scripts/adapters/providers/write-run.sh` and never edits files itself on that path. After the provider returns, the task runs the same post-edit steps as today: tests/lint, `outputs_verified`, its commit flow and its result block (`WORKER_RESULT` or the fix report). So the `WORKER_RESULT` contract, `out_of_lane`, the SubagentStop validators and the commit flow are unchanged.

### Eligibility and consent

- **Config time:** `setup-routing.sh apply` refuses a write seat (`--seat`) or a write grant (`--grant-write`) for any non-Claude provider whose `setup-providers.sh check` verdict is not exactly `usable for write seats`. It prints `REFUSED (provider_not_write_usable)` and writes nothing. A read seat still accepts `usable for read-only seats`.
- **Two grants:** a write seat runs only with the read grant **and** its own per-seat write grant (§"Consent rule"). A missing write grant prints `write_not_granted` and never sends. `write-run.sh` checks both grants again against the checkout's own repo, with no flag or environment bypass.
- **Pinnable only:** a provider whose table file defines no `provider_write_argv` cannot run a write seat (`write_unpinnable`).

### The isolated launch

- **Isolated HOME only.** `write-run.sh` starts the CLI only through `launch_provider_cli isolated` and takes no home-mode argument. Why: Grok reads `~/.claude/settings.json`, and a `permissions.defaultMode: "auto"` there overrides `--permission-mode dontAsk`, so a write launch under the real HOME is fail-OPEN. The launcher also never copies a login file whose first path segment is `.claude` into the isolated HOME.
- **Allow-list pin.** The argv is the provider's pin mode plus explicit allow rules for file read/edit tools only. There is no shell tool, so the provider cannot run tests; the Claude task runs them.
- **Pre-launch refusals** start no CLI and leave the tree untouched (the closed `write_status` list, with each refusal's condition, is `write-run.sh`'s header; it is not restated here). Two matter for the operator:
  - `write_tree_dirty`: the checkout had uncommitted or untracked non-ignored changes, so a restore could not tell the provider's files from the caller's.
  - `write_repo_settings_present`: the checkout root holds a `.claude/settings.local.json` (existence is the test, even gitignored), or a `.claude/settings.json` with a `permissions` key. Such a repo-side file could widen the pin, and the eligibility probe never tested it. A checkout whose root holds a local settings file refuses routed edits until the owner moves the file. A fresh linked worktree has none.
- **The provider never commits or pushes, and its done claim is ignored.** `write_status` comes from the exit, the time bound and the git fingerprint, never from the reply text. Whether the work counts is decided by the Claude-side gates: the disk gate, tests/lint, `out_of_lane`, Phase 4.5 and the drain's checks.
- **No merge or ask path.** A routed write seat edits files in its checkout and nothing else. Every question to the user, every commit, push and merge, and every sole-writer call stays with Claude, exactly as today.
- **Hook contract.** The provider is not a Claude Code session. Under the isolated launch, no Loomwright plugin hook, hook-written state, telemetry or guard runs inside it. The Claude task's own hooks (its SubagentStop validator, the test-integrity and finalize-publish guards) and the Supervisor-side gates carry the checks.

### Edit-step procedure (the routed task's side)

1. **Provider.** Use the provider the caller resolved (D1 below); never resolve again. `PROVIDER=claude` means today's path, unchanged: stop here.
2. **Prepare.** Record the pre-launch commit (`git rev-parse HEAD` in the checkout). Write the edit instructions to a prompt file **outside** the checkout (a file inside it makes the tree dirty). The instructions are the ones the task would act on itself (criteria or findings, lanes, files), without the test and commit steps, plus on a retry the previous gate output. Remove a leftover `.worker-summary.md` from an earlier attempt when it is not gitignored.
3. **Launch.** `write-run.sh --provider "<PROVIDER>[:<MODEL>]" --seat <id> --worktree <checkout top level> --prompt <file> --out <file outside the checkout>`, as ONE Bash call with `timeout: 600000`. The CLI bound (`LOOMWRIGHT_WRITE_CLI_TIMEOUT`, default and clamp in the script's header) leaves the restore room inside that cap.
4. **Read** `write_status` from `--out`. Only `ok` continues; `changed_files` lists what the provider touched.
5. **Post-edit steps as today.** If one fails after an `ok` launch (tests/lint, `outputs_verified`, or a self-review that would need an edit), first run `write-run.sh --restore <pre-launch sha> --worktree <checkout>` (it starts no CLI and refuses, changing nothing, when HEAD moved), then apply the failure rules with reason `post_edit_gate`.

### D1, D2 and the failure rules

- **D1 holds at resolve time.** `on_unavailable: fallback_to_default` applies only when a write seat is resolved: the worker seat once per run at Supervisor Phase 3 entry, the Phase 4.5 fix seat once per Phase 4.5 entry, the drain fix seat once per drain. Every worker spawn of a run carries that one provider. A later per-subtask failure goes through `docs/FAILURE_ESCALATION.md` §"Worker Failure", never a Claude edit mid-run, so a branch never mixes authors. An empty `PROVIDER` (`strict`) for the worker seat fails the run at Phase 3 entry, before any spawn.
- **D2.** Each write seat reads only its own `routing.seats.<seat>` and `--route <seat>=…`. A fix seat never inherits the worker seat's provider.
- **Restore.** `write-run.sh` restores the tree itself on every non-`ok` post-launch status: tracked files back to the pre-launch commit, untracked non-ignored files removed. On `write_git_tampered` it first puts back the byte snapshot of the git config and hooks, so a planted hook or `core.hooksPath` never runs later under the real HOME. A restore that cannot be completed reads `write_git_tampered` with `tree_restored: false`, never a softer status. After an `ok` launch whose post-edit step fails, the task runs `--restore` (step 5).

| Outcome | Worker seat | Phase 4.5 fix seat | Drain fix seat |
|---|---|---|---|
| a pre-launch refusal, `write_timeout`, `write_failed`, or `ok` then a failed post-edit step (after `--restore`) | the worker reports `WORKER_RESULT` `status: failed`, `error: "write_seat_failed:<write_status \| post_edit_gate>"`; one same-worktree retry in the restored tree, same provider, previous output in the retry prompt | `fallback_to_default`: the fix task makes the fix itself on the clean tree and logs one `seat_routing` line. `strict`: the fix-task crash path (`status: checkpoint`) | `fallback_to_default`: as the Phase 4.5 fix seat. `strict`: the drain answers `{"pushed": false, "push_failed": "write_seat_failed:<status> — <notes>"}` and ends ESCALATED |
| `write_git_tampered` (HEAD, the branch ref, remotes, config or hooks changed) | the worker reports `status: failed`, `error: "write_seat_tampered: <notes>"`, and that **stops the whole run**: no retry, no further spawn, no Claude fallback, no merge; brief → `failed/` | **exit the heal loop at once** (`write_seat_tampered`, `heal_decision: ESCALATED`); brief → `failed/` | the drain ends ESCALATED through the same `push_failed` answer, carrying `write_seat_tampered` |

The `seat_routing <seat> provider=<p> reason=<write_status|post_edit_gate>` line is logged once per fallback. In every escalation, `write-run.sh`'s `notes` (the changed fingerprint sections and paths, and whether they were restored) go to the owner. The stop's exact shape lives with each seat's home paragraph and `agents/supervisor.md`.

### Honest limits (write seats)

- The launcher is blast-radius reduction, not a sandbox. The provider can still write outside the checkout and reach the network, and the prompt plus every tracked file it can read are sent to the vendor. That is why consent is per seat, per provider, in user scope.
- Gitignored paths inside the checkout (for example `.supervisor/`, or an ignored `.claude/settings.local.json` the provider writes during the launch) are neither checked by the `write_tree_dirty` refusal nor removed by the restore.
- The fingerprint's `own` refs scope does not see a new branch or tag. On the Parallel Path, sibling workers that are already running may run git with a planted hook until the tampered run's restore returns.
- A SIGKILL of `write-run.sh` skips the restore; the clamp keeps the launch inside the caller's 600-second cap so that a Bash-level kill does not happen first.
- Grok's allow-rule names: `Edit` and `Write` were probed as enforced rule names; `Read`, `Grep` and `Glob` come from the vendor's permissions guide and were not probed. A wrong name makes the provider edit nothing, so `outputs_verified` fails closed; it cannot widen access.
- A repo-level `.grok/config.toml` in the checkout is **not** refused by `write-run.sh`. The vendor guide says project allow rules merge with the launch's own, so such a file could widen the pin. This is unrefused and unprobed.
- A drain stopped by a drain fix-seat failure reports `termination_reason: push_failed`, a misnomer; the reason text carries `write_seat_failed:<write_status>` or `write_seat_tampered`.

## Cost and honesty

- `lens-run.sh` and `write-run.sh` report `cost: "unknown"`, never `0`: a routed seat's spend is not measured by this plugin and must not be reported as free.
- The lens runner is not a sandbox. It scrubs the child environment, runs in a throwaway clone, and detects tree mutation (`lens_mutated_tree`); the provider CLI's own tool permissions are not pinned by this plugin. `setup-providers.sh check` grades `permissions pinnable` (and so `usable for write seats`) only from its permission probe: one isolated model call, from an empty throwaway directory, with a fixed prompt asking the CLI to create `probe.txt` under the provider's pin flags and no allow rule; the grade needs the CLI to answer and nothing to appear in that directory. Pin flags present in `--help` with no observed denial read `pin flags advertised (unverified)`, and a CLI that wrote the file, or left that directory removed, replaced or unlistable, reads `unpinnable (pin flags not enforced)`. The probe shows one denial on one fixed prompt; it does not show that every tool, path or prompt is denied. The diff and prompt are sent to the vendor, the CLI can read every tracked file at the reviewed commit in the throwaway clone, and network egress is not blocked, which is why consent is per repo, per provider, in user scope.
- A routed answer can carry text shaped by the reviewed diff (prompt injection). That is why it goes through the Claude path's validator and why a routed read seat has no write, merge or ask path (a write seat's counterpart is in §"Write seats").
- `/setup providers status` shows the probe's verdict per provider and the resolved routing per seat; it writes nothing.
