## Module: providers

Routes read-only pipeline **seats** (reviewers, graders, analysis passes) to another AI CLI. Claude stays the default everywhere: a repo with no `routing` block behaves exactly as before, and a seat leaves Claude only when BOTH the repo's config asks for it AND you have granted that provider for this repo. The seat list is `bash "${CLAUDE_PLUGIN_ROOT}/scripts/resolve-routing.sh" seats` (never restated here); the routed-seat procedure and the consent rule are `docs/PROVIDER_ROUTING.md`.

Two scripts, split on purpose. `${CLAUDE_PLUGIN_ROOT}/scripts/setup-providers.sh check` is the READ-ONLY probe of the provider table (it writes nothing). `${CLAUDE_PLUGIN_ROOT}/scripts/setup-routing.sh` (`status` / `apply` / `remove`) is the one writer. It writes `<project>/.supervisor/config.json` key `.routing` ONLY and the user-scope `~/.claude/loomwright/egress.json` key `repos.<slug>.providers` ONLY (this repo's slug) — a jq merge / `del`, backup-first, parse-gated, atomic, byte-compare idempotent, every other key preserved. Every refusal or abort writes nothing and exits 0 with a named headline.

**Check.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-providers.sh" check` and keep its output (it starts each installed provider CLI with a fixed prompt and no repo content, so it can take a while — say so first). Then run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-routing.sh" status` for the config's raw `.routing`, this repo's slug, its user-scope grants, the providers the repo merely requests, and one resolved line per seat.

**Report.** Print `check`'s table and verdicts VERBATIM — never a hard-coded provider list — then `status`'s output. A repo-requested provider with no grant resolves to Claude with `reason=provider_not_granted`; say so rather than implying it routes. For `status`, STOP after the report — no offer, no writes.

**Offer — CONSENT-BEARING.** `remove` names its action and runs directly. For `apply` (explicit, or chosen from bare `/setup providers`), offer ONLY providers whose verdict reads `usable for read-only seats` or `usable for write seats`; if there are none, report that and stop. Anything else (`not usable: …`) is never offered, and `setup-routing.sh` refuses it anyway. Use `AskUserQuestion` (cap 4 options):
1. **Which provider?** — one option per usable provider (up to the cap, plus `Cancel`).
2. **Which seats?** — print the `resolve-routing.sh seats` ids, then ask for the ids to route (free text, comma-separated) with `Cancel` as the other option. `/setup providers apply --seat <id>=<provider>[:<model>] …` supplies them and skips this question; it never skips question 3.
3. **Grant?** — asked unless the `status` grants cell already lists the provider. The question NAMES the provider and states what is sent to it: "Allow `<provider>` to receive, for `<slug>`, the diff under review and each routed seat's prompt? The provider CLI also gets read access to every tracked file at the reviewed commit (even for seats with no diff), and the runner does not block its network egress." Options: `Grant <provider>` / `Route only — no grant (seats stay on Claude until you grant)` / `Cancel`. Only the first writes a grant; a declined ask writes none.

Can't ask (non-interactive, or inside a subagent): report and stop with `Setup: providers — not changed (cannot ask)`; nothing is written.

**Apply.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-routing.sh" apply --seat <id>=<provider>[:<model>] …` and add `--grant <provider>` ONLY after the Grant answer above was yes; `--on-unavailable strict` only if the user asked for it (the default is `fallback_to_default`). Repeating `--seat` for one id makes an ordered preference list. It re-probes the provider before writing. Relay each headline verbatim — one per target, `apply routing:` and `apply grant:`:
- `applied` (+ `backup: <path>`) / `applied (created <file>)` — written; a `verify:` status follows.
- `no-op — …` — nothing written, no backup.
- `REFUSED (unknown_seat | invalid_provider_name | invalid_model | provider_not_probed | provider_not_usable | claude_needs_no_grant | no_repo_slug)` — nothing written, even for the other target of the same call.
- `ABORTED (<reason>)` — `config_unparseable`, `routing_unexpected_shape`, `egress_unparseable`, `egress_unexpected_shape`, `symlink`, `no_home`, `jq_unavailable`, `no_backup_name`, `backup_failed`, `write_failed`. Nothing written; **never repair a file to get past it**.

**Verify.** Success is claimed ONLY from the `verify:` block: each seat just routed must show `provider=<provider>` with an empty `reason=`. A seat that still shows `reason=provider_not_granted` (no grant yet) or `provider_unavailable` (the CLI is not on PATH) is reported as such, never as routed.

**Subflow: `/setup providers remove`.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-routing.sh" remove` and relay `remove routing:` and `remove grant:`. It deletes the `routing` key and THIS repo's `providers` grant only; a second run reports `no-op`. Removing narrows what is sent, so it asks nothing.

**Idempotency note.** A second identical `apply` reports `no-op`, leaves each file byte-identical and makes no backup. The grant is additive (a new provider is appended, existing entries keep their order) and is never written by a seat write.

---

