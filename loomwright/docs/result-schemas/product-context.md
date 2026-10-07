## PRODUCT_CONTEXT

The on-disk shape of `.agent/product.json`, the committed per-project **product-context store**: what
this project is, who it serves, and who it competes with. Like `FLOOR_PROJECTION` and `SYSTEM_CONTRACT`
this is **not an agent-emitted result block** — it is a state file, documented here because two
independent surfaces have to agree on it: the propose-only bootstrap that writes it
(`scripts/propose-product.sh`) and the fail-safe advisory reader that emits it
(`scripts/read-product.sh`). The store is a sibling of `.agent/rules/` and `.agent/orientation/`, is
**committed** (no `.gitignore` entry covers `.agent/`), and travels with the repo, so a project states
its identity once instead of re-typing it into every prompt.

**Created per project, never by this repo.** Nothing in the plugin ships a `.agent/product.json`; the
bootstrap creates one in the *user's* project on explicit confirmation. A project with no store is the
ordinary case, and the reader treats it as such.

```yaml
PRODUCT_CONTEXT:                 # the JSON root MUST be a single OBJECT (an array/scalar root is malformed)
  domain: string                 # required — what this project is, in the terms its own market uses
  stance: enum [product, tool]   # required — EXACTLY "product" or "tool". Load-bearing; see the mapping below
  audience: string               # required — who it serves, AND honestly whether that is evidence-backed or assumed
  competitors: array             # required — may be empty. Each entry is an object:
    - name: string               #   required — the competitor's name
      url: string                #   required — where it was (or would be) read from
      last_fetched: string|null  #   REQUIRED KEY, NULLABLE VALUE — ISO-8601 UTC, or null meaning NEVER FETCHED
  written_at: string             # required — ISO-8601 UTC, when the store was written
  head_sha: string               # required — the commit the store was written against
```

**`stance_default_action` is EMITTED-BUT-NOT-STORED.** It is a reader **output** only: it must never be
a key in `.agent/product.json`, and the bootstrap must never write it. It is derived by a **two-entry
lookup keyed on the stored `stance`**:

| stored `stance` | emitted `stance_default_action` |
|---|---|
| `product` | `build-highest-priority` |
| `tool` | `do-not-build-by-default` |
| absent / null / not a string / any other value | `unset` |

**Read this mapping; do not re-derive it.** A consuming lane takes `stance_default_action` from the
reader's output (or this table) and must not re-implement the lookup — that is the point of the field.
Hard-coding either action in a lane would make the lane carry ONE fixed policy regardless of the
project (telling a payments app to skip its missing fraud checks because parity is a NO for a tool);
deriving it from stored project data is the opposite of that. When `stance` does not resolve, the
reader emits `unset` and substitutes **neither** value — it never guesses a default. The mapping lives
in exactly one place in code: the `STANCE_ACTIONS` jq object in `scripts/read-product.sh`.

**`last_fetched` is NULLABLE-REQUIRED, and the two shapes are different facts.** The key is required;
its value may legitimately be `null`, meaning *never fetched*. Consumers MUST assert **key presence**
with jq `has("last_fetched")` and MUST NOT use `.last_fetched // <default>` — a `//` default silently
collapses a legitimate `null` into the missing-key case, after which the two are indistinguishable.
The reader renders them apart, and neither is ever rendered as a date or as "stale" (unknown is not old):

| shape | rendered as |
|---|---|
| key present, value `null` | `never fetched` (a complete record) |
| key present, non-empty string | the stored timestamp |
| key **absent** | `unset (key missing)` + a stderr warning (an incomplete record) |
| key present, any other type | `unset (malformed)` + a stderr warning |

**Provenance (`written_at` + `head_sha`) mirrors the orientation-memo header contract** (see
`.agent/orientation/README.md`), deliberately: recording the commit the store was written against makes
staleness measurable **against churn** rather than guessed from elapsed time — a store written against a
long-superseded HEAD is suspect however recent its timestamp.

**Reader contract (`scripts/read-product.sh`) — advisory and fail-SAFE, per the repo's bimodal failure
philosophy.** It ALWAYS exits 0; it never writes the store, never fetches anything, and never executes
any value it reads. In **every** degraded case it emits **nothing on stdout**, names the reason
**on stderr**, and exits 0 — the rule the reader enforces is that no path may reach `exit 0` with empty
stdout without having called `diag` first, so the guarantee holds for cases added later. The cases today
include: store absent, store malformed (unparseable JSON, or a root that is not an object), and `jq`
unavailable. (Deliberately stated as a rule rather than a count: an earlier version of this paragraph
pinned "three", which the reader had already outgrown twice — the exact class of unbacked claim the
`## PRODUCT_CONTEXT` store exists to reduce. `scripts/read-product.sh`'s own FAIL-SAFE header states the
same rule and names `grep -n 'diag "read-product:' $0` as the way to enumerate the live set.) A partially-odd store is demote-never-crash: the unusable field degrades
to `unset` with a stderr warning and every other field is still emitted, so a missing scalar can never
suppress the whole block. Output is a markdown block whose first line is the subordination banner
(`## Product context — advisory, subordinate to CLAUDE.md (on conflict, CLAUDE.md wins)`), one
`- <field>: <value>` line per field, and one indented row per competitor. Machine consumers gate on
**non-empty stdout**.

**Absence is the CONSUMER's to announce, not the reader's.** The reader stays quiet on stdout when the
store is missing precisely because it must not break or spam its callers. The seam that *needs* product
context is what must say, by name, that `.agent/product.json` is absent and offer the bootstrap — a
read-path-only store with no one announcing its absence is how a previous store in this repo ended up
orphaned and unused.

---

