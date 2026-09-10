# Notes service (fixture project)

A stand-in project tree for `propose-domain.sh`'s capability inventory. It is a *fixture*, not a
real service: the files exist so the inventory has something real to grep, and so each of the
three inventory outcomes is reachable and controllable.

| Outcome | Reached through |
|---|---|
| `present` (not a gap at all) | `src/search_service.py` names usage analytics in CODE |
| `unverified` (documented, unconfirmed in code) | `docs/architecture.md` names webhooks, and `.agent/orientation/2026-09-01-search-area.md` names SAML, with no code file confirming either |
| `missing` (searched, both surfaces non-empty, no match) | everything else in the catalogue |

Do not "helpfully" add the missing capabilities to this tree: the point of each absence is that
it is absent.
