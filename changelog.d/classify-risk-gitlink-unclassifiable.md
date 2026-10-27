<!-- bump: minor -->
classify-risk.sh names a symlinked or submodule base .agent unclassifiable and ignores unrelated .agent symlinks
A base `.agent` or `.agent/risk.json` that is a symlink now gives `unclassifiable: risk_json_symlink`, and a base `.agent` that is a submodule gives `unclassifiable: risk_json_gitlink` (both `high_risk: null`), so a project that commits either shape parks the `/automate --auto-merge` gate on every diff until `.agent` is a regular directory; any other symlink under `.agent/` is no longer judged.
