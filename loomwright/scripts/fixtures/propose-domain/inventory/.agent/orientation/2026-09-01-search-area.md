---
areas: auth, search
head_sha: 0000000000000000000000000000000000000000
written_at: 2026-09-01T00:00:00Z
---

# Orientation: auth and search

Search is a single SQLite FTS table; the indexer is synchronous.

On authentication: the login path is username and password only. A previous evaluation looked at
putting SAML in front of it for larger teams, and the note was left here rather than in a ticket.
Whether any of that shipped is not recorded, and no code in this tree confirms it - which is the
whole point of this memo as a fixture: an orientation memo can make a capability *documented* and
still leave it *unconfirmed*.
