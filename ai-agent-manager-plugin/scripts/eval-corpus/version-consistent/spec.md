# Task: version-consistent

## What this task asks

The plugin.json version must be valid semver and consistent across
manifests; `validate-version.sh` must pass.

Specifically, the marketplace manifest (`.claude-plugin/marketplace.json`)
must point at an existing plugin source directory containing a plugin
manifest, and the version in `marketplace.json` must match the version in
the plugin's `plugin.json`. A version skew between the two manifests
breaks `/plugin install` and must be caught.

## How it's checked

`check.sh` resolves the repo root (via `git rev-parse --show-toplevel`)
and runs the repo-root version-validation gate:

```
bash scripts/validate-version.sh
```

It exits with that gate's status — exit 0 (consistent) = pass, non-zero
(skew or missing manifest) = fail. The check is deterministic and
read-only.
