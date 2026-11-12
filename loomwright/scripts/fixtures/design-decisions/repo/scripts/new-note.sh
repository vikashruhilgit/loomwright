#!/usr/bin/env bash
# new-note.sh <title> — create notes/<title>.md. Fixture for brief-c (the file it modifies).
set -euo pipefail
title="${1:?usage: new-note.sh <title>}"
mkdir -p notes
printf '# %s\n' "$title" > "notes/$title.md"
echo "notes/$title.md"
