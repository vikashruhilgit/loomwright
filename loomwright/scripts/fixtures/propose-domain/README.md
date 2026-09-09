# `propose-domain` fixtures — why these files are committed

These are the committed inputs for `loomwright/scripts/propose-domain.sh` (the `--domain` basis of
`/propose`) and for its self-test.

## Why they are committed rather than read from the real tree

`propose-domain.sh`'s real inputs are a product store at `.agent/product.json` and an output
directory under `.supervisor/requirements/proposed/`. **Root `.gitignore` excludes `.supervisor/*`,
and this plugin repo deliberately ships no product store of its own** — the store is created
per-project at runtime by `propose-product.sh`, never by the plugin.

So a test driven off the real tree would find no store, take the fail-safe "no product context"
path, write nothing, and **exit 0**. It would pass. It would pass with the producer deleted. A
green CI run would mean nothing at all, which is the single most-recorded defect class in this
repo: a check that cannot fail.

Committing the fixtures is what makes the assertions able to fail. The self-test copies this tree
into a `mktemp -d` **outside the repo root**, points `PROPOSE_DOMAIN_STORE` and
`PROPOSE_DOMAIN_OUT_DIR` at it, and asserts by **parsing the emitted files** — never by reading
the script.

## Why no fixture uses a `.log` extension

Root `.gitignore` carries a bare `*.log` under its `# Logs` section. It matches at every depth, so
`git add` **silently skips** any `.log` file added here: it would be present on the author's disk,
absent from a fresh clone, and CI would exercise a path with the fixture missing. The failure is
invisible on the machine that wrote it.

Nothing in this directory uses that extension, and the fetch stub's optional call recorder
(`PROPOSE_DOMAIN_FETCH_CALLS`) is documented to take a `.txt` path for the same reason. Verify with
`git check-ignore -v <path>` (expect no match) and `git ls-files` — never with `git add -f`, which
hides the problem instead of fixing it.

## The files

| File | What it is for |
|---|---|
| `product.json` | A valid store, `stance: "product"`. Three competitors, so the `PROPOSE_DOMAIN_MAX_FETCHES=1` partial-coverage case is exercisable. |
| `product-tool.json` | **Byte-identical to `product.json` except `stance: "tool"`.** The pair is the whole point: the same fixture under the two stances must yield the *same* classifications and *different* default actions, because stance decides only the default action and never the classification. |
| `source-acme.txt` `source-bolt.txt` `source-cursive.txt` | Stand-in fetched source text, one per competitor. Between them they name a mostly disjoint set of domain expectations, so which gaps appear is a function of which sources were reached. The one deliberate overlap is single sign-on, named by **both** `source-acme.txt` and `source-cursive.txt` — see "Why Cursive must corroborate something this project lacks" below. |
| `fetch-stub.sh` | The stand-in `PROPOSE_DOMAIN_FETCH_CMD`. Opens no socket; maps a fixture url to one of the source files; optionally appends each call to `$PROPOSE_DOMAIN_FETCH_CALLS` so a test can count external calls instead of reading the code. An unknown url exits 1 with no output — that is the failed-fetch case. |
| `inventory/` | A small project tree for the capability inventory, built so all three inventory outcomes are reachable: `present` (usage analytics, in code), `unverified` (webhooks in a doc, SAML in an `.agent/orientation/` memo, neither confirmed in code), and `missing` (everything else). |

### What the store fixture is built to produce

`product.json`'s `domain` is a knowledge-base/search service — deliberately **not** a payments
domain. That is load-bearing: it makes the catalogue's payments-scoped expectation classify as
`NOT-FOR-US`, which is the case the suppression criterion needs (a recorded `NOT-FOR-US` gap must
not be re-raised on a second run).

The competitors' `last_fetched` values are also deliberate:

- `Acme Docs` — a recent date (fresh under the default threshold).
- `Bolt Knowledge` — `2019-01-01T00:00:00Z`, old enough to be named **stale** in the output.
- `Cursive Wiki` — `null`, meaning **never fetched**. That is a complete record, not a missing
  one, and it must be rendered as "never fetched" — never as a date and never as "stale". Unknown
  is not old.

Sorted by name, the fetch order is Acme → Bolt → Cursive, so `PROPOSE_DOMAIN_MAX_FETCHES=1`
reaches exactly Acme and must report the other two by name as not reached.

### Why Cursive must corroborate something this project lacks

A source is only *cited* in an emitted gap file, and so its fetch date is only *rendered*, when it
corroborates a capability that turns out to be a gap. Cursive Wiki is the only competitor with
`last_fetched: null`, so **Cursive is the only path to the "never fetched" rendering** — if nothing
Cursive names is ever emitted as a gap, that branch of the output is never produced and a test for
it would pass vacuously against an empty set.

Cursive's original two capabilities are both fragile in that role: `usage-analytics` is confirmed
`present` in `inventory/` by design, and `audit-log`, while a gap in `inventory/`, matches in code
in the plugin repo itself — so a real-tree run cites Cursive for neither. `single-sign-on` is
therefore named here as well: it is `unverified` in `inventory/` (a `.agent/orientation/` memo
mentions SAML, no code confirms it) and has no code match in the plugin repo either, which keeps
the never-fetched arm exercised on both trees rather than by luck.

The consequence to keep in mind when reading the emitted files: `domain--single-sign-on.md` cites
**two** sources — Acme with a real date, Cursive as "never fetched" — and that pairing is the point.
"Never fetched" is a complete record rendered as its own thing; it is never a date and never stale.

## One honest caveat

The `inventory/` tree and the `source-*.txt` files live inside this plugin repo, so a run of
`propose-domain.sh` against **this** repo's own tree would see them in its doc surface. That is
visible rather than hidden — every emitted gap names the files it matched — but it is a reason the
real-tree run is a local corroboration only, and never the thing CI asserts on.
