meta-sync — test the push-retry exhaustion and missing-meta-base-object fallback
`test-meta-sync.sh` gains two legs that pin two fail-closed branches of `meta-sync.sh` no test reached before. Leg 34
drives an origin whose `pre-receive` hook rejects every push: the push exits 1 with `push_failed`, the hook ran exactly
the script's own `MAX_ATTEMPTS` times (read from the script, never hard-coded), the branch tip and meta-base are
unchanged, and a PATH git shim proves every one of those pushes was unforced. Leg 35 records a nonexistent tree sha
in `<gitdir>/meta-base`: push, pull and a `--paths-from` push all warn `missing from the object store` and fall back
to the history-aware no-base derivation, so a branch-deleted file is never re-added and an unlisted conflict still
aborts. Two new sed-built mutation controls (36, 37) turn each leg red: exhausted retries exiting 0, and a missing
base read as the empty tree. `meta-sync.sh` itself is unchanged.
