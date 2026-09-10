# Architecture

The service is one process: an HTTP handler, an indexer and a SQLite store.

## Eventing (design note, not implemented)

We have discussed emitting outbound webhooks on publish and archive so downstream tools can
react without polling. Nothing in `src/` implements it yet, and no decision has been recorded.

This file is exactly the ambiguous case the inventory must NOT resolve into "missing": the
capability is named in the docs and unconfirmed in the code, which is `unverified`.
