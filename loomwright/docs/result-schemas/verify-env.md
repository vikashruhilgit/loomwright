## VERIFY_ENV

The on-disk shape of `.agent/verify.json`, the committed per-project **verification-environment
contract**: how the app under test is started, health-checked, authenticated, seeded and reset, and how
the plugin can prove the target is **not production**. Like `PRODUCT_CONTEXT` this is **not an
agent-emitted result block** — it is a state file, documented here because three independent surfaces
have to agree on it: the propose-only bootstrap that writes it (`scripts/propose-verify.sh`), the
fail-safe advisory reader that validates and emits it (`scripts/read-verify.sh`), and the executor that
runs it (`scripts/verify-env.sh`). The store is a sibling of `.agent/product.json`, is **committed**
(no `.gitignore` entry covers `.agent/`), and travels with the repo, so a project declares its
verification environment once instead of every `/verify` run re-guessing it.

**Created per project, never by this repo.** Nothing in the plugin ships a `.agent/verify.json`; the
bootstrap creates one in the *user's* project on explicit confirmation. A project with no store is the
ordinary case, and the reader treats it as such.

```yaml
VERIFY_ENV:                        # the JSON root MUST be a single OBJECT (an array/scalar root is malformed)
  start: string|null               # REQUIRED KEY, NULLABLE VALUE — shell string that starts the app; null = already running
  base_url: string                 # required — where the app under test is reached; non_prod_assert.base_url_matches is evaluated AGAINST it
  health: string                   # required — a path (relative to base_url) or a full URL that must answer 2xx (STATUS READ, not `curl -f`: a 3xx is NOT healthy)
  auth: object                     # required
    method: enum [none, storage_state]   # required
    storage_state_path: string|null      # REQUIRED non-empty when method is storage_state; null/absent otherwise
    probe_path: string|null              # optional — a route that answers 401/403/302 when logged out (the auth-probe target)
  non_prod_assert: object          # required — AT LEAST ONE usable member; every present member must be well-typed:
    base_url_matches: string       #   an ERE tested against base_url (non-empty)
    env_var_equals: {name, value}  #   name a POSIX identifier `[A-Za-z_][A-Za-z0-9_]*`, value string — the executor compares $name to value;
                                   #   a well-typed member whose name is NOT an identifier is UNUSABLE, not mistyped (see below)
    cmd: string                    #   a shell string; exit 0 = pass
  seed: string|null                # REQUIRED KEY, NULLABLE VALUE — shell string that seeds the app; null = nothing to seed
  reset: string|null               # REQUIRED KEY, NULLABLE VALUE — shell string that resets state; null = nothing to reset
  stop: string|null                # REQUIRED KEY, NULLABLE VALUE — shell string that stops the app; null = kill the pid recorded at start
  ready_timeout_s: number          # optional — seconds the executor polls health after start; DEFAULT 60, applied by the EXECUTOR, never the reader
  notes: any                       # optional — free-form, passed through untouched
```

**TRUST SURFACE — the shell-string members are executed, not inert data.** `start`, `stop`, `seed`,
`reset` and `non_prod_assert.cmd` are arbitrary shell, committed by the project, and `verify-env.sh`
runs them via `bash -c` with the caller's **full shell privileges** — they are trusted exactly like
`package.json` scripts, no more and no less. Consequences that follow from that and are stated here so
the schema cannot imply otherwise: the **executor is the only surface that runs them** (the reader and
the bootstrap never do — the seam test plants `touch <marker>` in every shell-string member and asserts
no marker appears after a read); never run `verify-env.sh` against a store you have not read; and
whether an *unattended* lane may invoke the executor at all is a decision for that lane (`/verify`),
not something this schema grants.

**Nullable-required keys, and the two shapes are different facts.** `start`, `seed`, `reset` and `stop`
are required keys whose value may legitimately be `null`, meaning *nothing to run here*. A key that is
**absent** is a different fact — the author never decided — and the store is **malformed**. Consumers
MUST assert **key presence** with jq `has("<key>")` and MUST NOT use `.<key> // <default>` — a `//`
default silently collapses a legitimate `null` into the missing-key case, after which the two are
indistinguishable (the defect that shipped once in `read-rules.sh`). `test-verify-seam.sh`'s mutation
control deletes the `seed` presence check from a *copy* of the reader and asserts the missing-`seed`
fixture is then accepted, so the check is proven load-bearing rather than assumed.

| shape | reader verdict |
|---|---|
| key present, value `null` | valid — the executor skips that step |
| key present, non-empty string | valid — the executor runs it (after the non-prod gate) |
| key **absent** | **malformed** — `[required_key_missing:<key>]` on stderr, nothing on stdout |
| key present, any other type | **malformed** — `[type_invalid:<key>]` |

**`non_prod_assert` fails CLOSED, and is never inferred.** The executor's `assert-non-prod` evaluates
every usable member and passes only if **at least one** passes; a store whose `non_prod_assert` has no
usable member is refused with `non_prod_assert_empty`, and one whose members all fail is refused with
`non_prod_assert_failed`. **`env_var_equals.name` must be a POSIX identifier —
`[A-Za-z_][A-Za-z0-9_]*` — and all three surfaces enforce the SAME rule** (the executor looks the
variable up with `${!name}`, which can only ever fail for anything else): `propose-verify.sh` refuses
`--non-prod env=NAME=VAL` with a non-identifier `NAME` at parse time (exit 1, nothing written, the
message names the rule); the reader treats a well-typed member with a non-identifier `name` as an
**unusable** member — named on stderr as `[env_var_name_invalid:<name>]` — that does not count toward
"at least one usable", so the store is malformed (`non_prod_assert_empty`) only when **no usable member
remains** and is still emitted when another member is usable; and the executor's own check fails the
member closed if one ever reaches it. Without the parity, `env=NODE-ENV=development` passed proposal,
`--confirm` and the reader, and failed closed only at the first run. Every other executor subcommand (`start`, `stop`, `seed`, `reset`,
`auth-probe`) runs `assert-non-prod` first, **in the same invocation**, and refuses with the gate's own
token (`non_prod_assert_failed` / `non_prod_assert_empty`) before touching anything; independently, the
two `bash -c` sites refuse with `non_prod_not_asserted` if the gate did not pass in-process (the inner
belt the seam test's mutation control exercises by deleting the dispatch-level gate call from a copy).
The bootstrap never guesses this member: no signal in
a repo says what production looks like for a given project (a `.env` with `NODE_ENV=development` says
nothing about where `base_url` points), so `propose-verify.sh` refuses to write without an explicit
`--non-prod <regex|env=NAME=VAL|cmd=…>` — exit 1, on every path, `--confirm` or not. For the same
reason it never defaults `base_url` (a guessed localhost placeholder would let `base_url_matches` pass
against a URL the app is not at): with nothing scannable and no `--base-url` the dry run prints
`BLOCKED` and the write refuses (exit 2).

**Reader contract (`scripts/read-verify.sh`) — advisory and fail-SAFE, STRICT on shape.** It ALWAYS
exits 0; it never writes the store, never fetches anything, and **never executes any value it reads**.
On success it prints the validated contract as **one compact JSON object line** on stdout (machine
consumers gate on non-empty stdout, then `jq` it). In **every** degraded case — store absent (stderr
names the path), unparseable JSON, non-object root, any required key missing, any mistyped member,
`non_prod_assert` with no usable member, `jq` unavailable — it emits **nothing on stdout**, names the
reason **on stderr**, and exits 0. Unlike `read-product.sh` it does **not** demote-and-continue: this
contract is input to an executor that will start, seed and reset a live app, so a partially-valid store
is exactly what the non-prod gate exists to refuse — the reader fails SAFE on the read so the executor
fails CLOSED on the run. Every malformed diagnostic ends with a stable, grep-able **reason token** in
brackets (`[store_absent]`, `[required_key_missing:seed]`, `[type_invalid:auth.method]`,
`[non_prod_assert_empty]`, …) so the executor forwards the reader's reason verbatim instead of inventing
its own — in particular, `assert-non-prod` against `{"non_prod_assert": {}}` reports the reader's
`non_prod_assert_empty`, not a generic *store unreadable*. The rule the reader enforces is that no path
may reach `exit 0` with empty stdout without naming its reason; the live set is enumerated by
`grep -n 'diag "read-verify:' scripts/read-verify.sh` plus the `MALFORMED` lines of its jq program —
read it from the code, never from a count kept here.

**Executor contract (`scripts/verify-env.sh`).** It **loads the contract through the reader and never
re-parses the file** — empty reader stdout ⇒ `verify_store_unreadable` (non-zero), with the reader's
stderr forwarded. It locates the reader as a **sibling script** — `read-verify.sh` resolved relative
to its own `dirname "${BASH_SOURCE[0]}"` — never through a harness-specific install path, so it stays a
vendor-neutral core script. It applies `ready_timeout_s` (default 60, **wall-clock seconds** against a
`date +%s` deadline — not a poll count, so a hanging health endpoint cannot stretch the wait) when polling
`health` after `start`; on timeout it runs `stop` and exits non-zero with `health_timeout`. **Healthy
means an HTTP 2xx and nothing else:** the poll reads the status code (`curl -w '%{http_code}'`, no `-f`,
no `-L`) and accepts only `2xx` — `curl -f` fails only on 4xx/5xx, so under it a health route that
302s to a login page would have reported `ready`; a redirect is observed, never followed. **Lifecycle
verdicts are never vacuous:** a subcommand exits 0 only when the guarantee its name promises actually held
in that invocation. `start` refuses with `already_started` while the pid recorded by a previous `start`
is still alive (a stale record whose process is gone is cleared, never refused, so a re-start after a
crash works); a start string that exits non-zero before health answers is `start_exited:<rc>` (record
dropped, `stop` run), while one that exits 0 is a detached starter (`docker compose up -d`) whose record
is dropped and whose health is still polled. `stop` with `stop: null` kills the recorded pid and **waits
for it to be gone** (SIGTERM, then SIGKILL); a recorded pid that was not running is `not_running`
(non-zero — nothing was stopped; the dead record is cleared), one that survives both signals is
`stop_failed`, and no record at all is the contract's no-op (exit 0). It **never writes
`.agent/verify.json`**.

**Sole writer (`scripts/propose-verify.sh`) — propose-only, `--confirm`-gated.** It scans the project
(`package.json` scripts, `playwright.config.*`, `.env*`, `docker-compose*`, `prisma/seed*`, `Makefile`)
for candidates, prints the proposal with each candidate's source, validates the proposal's shape
**through the reader** before the confirm gate (it can never write a file the reader would refuse), and
writes only on `--confirm` (or an interactive TTY "y"): `mkdir -p .agent`, a same-directory temp file,
one atomic move. The seam test greps `loomwright/scripts/*.sh` (excluding `test-*.sh`) for a move onto
the literal store name and requires exactly one hit. It refuses from a non-primary checkout (top-level
`.git` is a **file** ⇒ exit 3), never clobbers an existing store, and honours `--repo <dir>` so its tests
write under a `mktemp -d` project and never under this repo's `.agent/`.

**Absence is the CONSUMER's to announce, not the reader's.** The reader names the missing path on stderr
and stays quiet on stdout. The seam that *needs* the contract — `/verify`, the executor — must say, by
name, that `.agent/verify.json` is absent, name the bootstrap, and **stop before the app is touched**.

---

