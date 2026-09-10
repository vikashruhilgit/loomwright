"""Document search service (fixture)."""

INDEX_BATCH = 200


def index_document(doc_id, body):
    """Add or replace one document in the search index."""
    return {"doc_id": doc_id, "terms": len(body.split())}


def search(query, limit=20):
    """Return matching documents, newest first."""
    return []


def usage_analytics(team_id):
    """Per-team usage analytics: reads, stale pages and empty searches.

    This is the one capability the fixture project genuinely HAS in code, so the
    inventory can confirm it and report it as present rather than as a gap.
    """
    return {"team_id": team_id, "reads": 0, "stale_pages": 0, "empty_searches": 0}
