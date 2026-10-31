# Provider Routing for Read-Only Seats

> One resolver, one consent rule, one procedure. A "seat" is a read-only pipeline step (a reviewer, a grader, an analysis pass) that can run on a chosen AI CLI instead of Claude. Every seat paragraph in an agent, skill or command points here and restates none of it.

- **Seat list:** `scripts/resolve-routing.sh seats` is the only home of the seat ids. Each line is `<id> <home-file> <role-marker> <validator|->`. This file never restates that list or a count of it; read the script.
- **Provider list:** the `provider-*.sh` files in `scripts/adapters/providers/` are the provider table. Nothing here names the providers.
- **Default:** every seat runs on Claude, exactly as before, unless a `routing` entry, a per-run flag or the `voter_provider` alias names another provider **and** the user has granted that provider for this repo.

## What routes, and what never does

Only the seats `resolve-routing.sh seats` prints are routable, and a routed seat produces **analysis text only**. It never gains a write, a merge or an ask path: every file write, every question to the user and every sole-writer call stays on the Claude main thread exactly as today.

The conductor is not routable and is not a seat: the main session, the supervisor runner, execute-manager, context-keeper, worker, the `/autonomous` and `/automate` loops, the detached drain runner and the `TaskCompleted` prompt hook. `resolve-routing.sh seat worker` prints `REASON=unknown_seat` with `PROVIDER=claude`. Write seats are a separate, later decision.

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
- **Every other seat:** `--route <seat>=<p>` > `routing.seats.<seat>` > default. `--voter-provider` and `.voter_provider` do not apply to them.
- A repeated `--route` for the same seat: the last one wins. A `--route` for a different seat is ignored by this call but still checked against the seat list.
- `/supervisor --route <seat>=<provider>[:<model>]` (repeatable) is forwarded to every `resolve-routing.sh seat` call of that run; every other command reads config only.

## Consent rule (user scope only)

A non-Claude provider runs **only** when the user has granted it for this repo, in user scope. The grant is `repos.<slug>.providers` (an array of provider names) in the user-scope egress file that `scripts/resolve-egress-config.sh` reads, surfaced as its `PROVIDER_GRANTS` line (comma-joined, each name filtered to `[A-Za-z0-9_-]+`).

- The repo's own config can only **request** a provider. The resolver reports what a repo asks for under `REPO_REQUESTED_PROVIDERS`, an informational line nothing grants from.
- A missing grant is `PROVIDER=claude`, `REASON=provider_not_granted`, **regardless of `on_unavailable`**: a missing grant never sends. A missing, unreadable or malformed user-scope file means no grants.
- `claude` never needs a grant.
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
| `unknown_seat` | the `seat <id>` argument, a `routing.seats` key or a `--route` seat is not in `seats` |
| `invalid_provider` | bad provider name or model, no `provider-<name>.sh` file, or a seat value of the wrong type |
| `routing_default_not_claude` | `routing.default` is present and not `claude` |
| `provider_not_granted` | no user-scope grant for this repo |
| `provider_unavailable` | granted, CLI not on `PATH`, `fallback_to_default` |
| `provider_unavailable_strict` | the same with `strict`; `PROVIDER` is empty |

## Routed seat protocol

Every seat's home file carries one **Seat routing** paragraph that points here. The steps, in order:

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

A routed seat is advisory-equivalent to its Claude seat. It never decides a gate the Claude seat did not decide, and its output is validated, not trusted.

## Cost and honesty

- `lens-run.sh` reports `cost: "unknown"`, never `0`: a routed seat's spend is not measured by this plugin and must not be reported as free.
- The lens runner is not a sandbox. It scrubs the child environment, runs in a throwaway clone, and detects tree mutation (`lens_mutated_tree`); the provider CLI's own tool permissions are not pinned by this plugin. `setup-providers.sh check` grades `permissions pinnable` (and so `usable for write seats`) only from its permission probe: one isolated model call, from an empty throwaway directory, with a fixed prompt asking the CLI to create `probe.txt` under the provider's pin flags and no allow rule; the grade needs the CLI to answer and nothing to appear in that directory. Pin flags present in `--help` with no observed denial read `pin flags advertised (unverified)`, and a CLI that wrote the file, or left that directory removed, replaced or unlistable, reads `unpinnable (pin flags not enforced)`. The probe shows one denial on one fixed prompt; it does not show that every tool, path or prompt is denied. The diff and prompt are sent to the vendor, the CLI can read every tracked file at the reviewed commit in the throwaway clone, and network egress is not blocked, which is why consent is per repo, per provider, in user scope.
- A routed answer can carry text shaped by the reviewed diff (prompt injection). That is why it goes through the Claude path's validator and why a routed seat has no write, merge or ask path.
- `/setup providers status` shows the probe's verdict per provider and the resolved routing per seat; it writes nothing.
