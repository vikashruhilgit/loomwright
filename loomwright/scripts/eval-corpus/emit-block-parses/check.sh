#!/usr/bin/env bash
# check.sh — emit-block-parses eval task.
# Sibling oracle to `parity-emit-block`, one layer deeper: that task asks whether
# every hook-required FIELD NAME is present in the emit template; this one asks
# whether the template, copied verbatim, would actually PARSE.
#
# The gap is real and was live in the tree: the adjudication EXECUTE_CHECKPOINT
# templates carried all five required fields (parity-emit-block green) but wrapped
# `adjudication_options: [...]` and a quoted `reason` across lines for readability.
# `result_block_parser.py` supports a strict YAML subset that rejects a continued
# flow collection and rejects block scalars (> / |) outright, so both templates
# were rejected at the PARSE step — before rule 6 was ever consulted.
#
# Oracle: PARSE-level only. Semantic rules (worktree paths must be siblings, an
# adjudication needs non-empty evidence, ...) are deliberately NOT asserted — a
# template's `{placeholder}` values cannot satisfy them, and doing so would make
# the check untestable rather than stronger. Rule conformance is the hook's job
# and `test-result-validators.sh`'s; line-structure conformance is this task's.
#
# Deterministic and read-only.
#
# Usage: bash check.sh [--root <dir>]
#   --root defaults to the enclosing git repo root (the runner cd's into this
#   task dir, which lives inside the repo). The mutation self-test points it at
#   a fixture tree carrying scripts/check-contract-parity.sh + loomwright/agents/
#   + loomwright/scripts/result_block_parser.py.
set -uo pipefail

if [ "${1:-}" = "--root" ]; then
  repo_root="${2:?--root requires a directory}"
else
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "emit-block-parses: not inside a git repo (and no --root given)" >&2
    exit 1
  }
fi

parity="$repo_root/scripts/check-contract-parity.sh"
[ -f "$parity" ] || { echo "emit-block-parses: $parity missing" >&2; exit 1; }
[ -f "$repo_root/loomwright/scripts/result_block_parser.py" ] || {
  echo "emit-block-parses: result_block_parser.py missing under $repo_root" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || {
  echo "emit-block-parses: python3 not available" >&2; exit 1; }

# Same MANIFEST, same parse convention as parity-emit-block — deliberately reusing
# check-contract-parity.sh's single source of field truth rather than adding another
# parallel table. (Re-verified: the assignment still opens with a bare `MANIFEST="`
# line and closes with a bare `"`.)
manifest="$(awk '/^MANIFEST="$/{f=1;next} f&&/^"$/{exit} f' "$parity")"
[ -n "$manifest" ] || { echo "emit-block-parses: could not parse MANIFEST from $parity" >&2; exit 1; }

MANIFEST="$manifest" REPO_ROOT="$repo_root" python3 - <<'PY'
import os, re, sys

repo_root = os.environ["REPO_ROOT"]
sys.path.insert(0, os.path.join(repo_root, "loomwright", "scripts"))
try:
    from result_block_parser import parse_block
except Exception as exc:                                   # pragma: no cover
    sys.stderr.write("emit-block-parses: cannot import result_block_parser: %s\n" % exc)
    sys.exit(1)


def regions(text, block):
    """Every emit-template occurrence for `block`, each captured SEPARATELY.

    Same two authoring styles parity-emit-block recognises, with one deliberate
    difference: that task unions the occurrences (it only needs the set of field
    names); parseability is a per-template property, so each is kept apart and
    parsed on its own. Fence toggling is avoided here too — agent files contain
    unbalanced fences — so a YAML region ends at a dedent to the anchor's indent
    or at the next fence line, whichever comes first.
    """
    lines = text.split("\n")
    yaml_anchor = re.compile(r"^(\s*)" + re.escape(block) + r":\s*(#.*)?$")
    md_anchor = re.compile(r"^#+\s+" + re.escape(block) + r"\s*$")
    out, i = [], 0
    while i < len(lines):
        m = yaml_anchor.match(lines[i])
        if m:
            base = len(m.group(1))
            buf, j = [lines[i]], i + 1
            while j < len(lines):
                line = lines[j]
                if line.strip().startswith("```"):
                    break
                if line.strip() == "":
                    buf.append(line); j += 1; continue
                if len(line) - len(line.lstrip(" ")) <= base:
                    break
                buf.append(line); j += 1
            out.append(("yaml", i + 1, "\n".join(buf)))
            i = j
            continue
        if md_anchor.match(lines[i]):
            buf, j = [lines[i]], i + 1
            while j < len(lines) and (
                lines[j].strip() == ""
                or lines[j].lstrip().startswith("- ")
                or lines[j].startswith("    ")
            ):
                if lines[j].strip() == "" and buf and buf[-1].strip() == "":
                    break
                buf.append(lines[j]); j += 1
            out.append(("md", i + 1, "\n".join(buf)))
            i = j
            continue
        i += 1
    return out


def normalize(text):
    """Substitute authoring placeholders with an inert scalar.

    `{subtask_id}` and `[...]` are template notation, not emitted bytes; left
    alone they parse as a flow mapping / flow sequence and every template would
    fail for a reason that has nothing to do with the defect class this task
    exists to catch.

    LOAD-BEARING: both substitutions are WITHIN A SINGLE LINE and never add or
    remove a line break. Line structure — which is exactly what a wrapped flow
    collection or a block scalar gets wrong — passes through untouched, so the
    check cannot normalize away the thing it is checking. The mutation control
    in spec.md pins this.
    """
    text = re.sub(r"\{[^{}\n]*\}", "x", text)
    text = re.sub(r"\[\.\.\.\]", "[x]", text)
    return text


fail = 0
checked = 0
for row in os.environ["MANIFEST"].strip().split("\n"):
    if not row.strip():
        continue
    _matcher, agent, block, _fields = row.split("|", 3)
    agent_path = os.path.join(repo_root, "loomwright", "agents", agent)
    if not os.path.isfile(agent_path):
        sys.stderr.write("FAIL: %s missing at %s\n" % (agent, agent_path))
        fail = 1
        continue
    with open(agent_path) as fh:
        text = fh.read()

    found = regions(text, block)
    if not found:
        # parity-emit-block already reports a missing template with its own
        # wording; not duplicating that failure keeps the two oracles distinct.
        continue

    for style, lineno, region in found:
        checked += 1
        _fields_parsed, errors = parse_block(normalize(region))
        if errors:
            sys.stderr.write(
                "FAIL: %s: %s emit template at line %d (%s style) does not parse — "
                "copied verbatim it is rejected before any rule is checked:\n"
                % (agent, block, lineno, style)
            )
            for err in errors[:4]:
                sys.stderr.write("         %s\n" % err)
            if len(errors) > 4:
                sys.stderr.write("         ... and %d more\n" % (len(errors) - 4))
            fail = 1

if checked == 0:
    sys.stderr.write(
        "FAIL: emit-block-parses: no emit template was located for any MANIFEST row "
        "— the extraction found nothing to assert on, which is a vacuous pass\n"
    )
    fail = 1

if fail:
    sys.stderr.write("✗ emit-block-parses: an emit template is not parseable.\n")
    sys.exit(1)
print(
    "✓ emit-block-parses: all %d emit templates parse under "
    "result_block_parser." % checked
)
PY
