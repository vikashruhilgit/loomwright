#!/usr/bin/env python3
"""result_block_parser.py — shared substrate for the deterministic result-block validators.

Written for Fix 4 / 4e: five mechanical `type: prompt` SubagentStop hooks are
replaced by zero-token `type: command` scripts. This module holds everything
those five validators share, so the nested-YAML-subset parser is written,
hardened and self-tested ONCE.

Behaviour-compatible with, and lifted from, `validate-launch-pad-result.py`:

  1. PAYLOAD EXTRACTION LADDER (`extract_payload` / `extract_payload_text`)
     last_assistant_message -> result_block -> output -> agent_output ->
     agent_transcript_path -> transcript_path (the subagent-scoped path is
     preferred over the shared session one). Plus `--raw` mode, where stdin IS
     the agent output text with no JSON envelope.

  2. BLOCK LOCATION (`find_last_block` / `find_last_named_block`)
     The LAST block wins — "the most recent emission wins" contract. Two
     emission shapes are supported, because the agents genuinely use both:
       (a) YAML form   `WORKER_RESULT:` + indented body
                       (docs/RESULT_SCHEMAS.md, execute-manager, supervisor,
                       plan-reviewer, qa-executor)
       (b) Markdown    `## WORKER_RESULT` + `- key: value` bullets
           bullet form (agents/worker.md's Output Format)

  3. NESTED-YAML-SUBSET PARSE (`parse_block`)
     Returns (fields, errors). Supported subset:
       - scalars, incl. all five YAML null spellings:
         empty-after-colon, `~`, `null`, `Null`, `NULL`
       - quoted literals — a quoted "null" is the STRING "null", not null
       - inline flow sequences        `[a, b]`
       - inline flow mappings         `{k: v}`
       - flow sequences OF mappings   `[{kind: file, path: x, status: present}]`
       - block sequences              `- item`
       - block sequences OF mappings  `- kind: file` / `  path: x`
       - nested block mappings
     ANY construct outside that subset (block scalars `|`/`>`, anchors/aliases,
     merge keys, tab indentation, unterminated quotes or brackets, trailing
     junk after a flow collection, duplicate keys, `key:value` with no space)
     is reported in `errors` as an EXPLICIT parse failure. Nothing is ever
     silently coerced.

  4. `emit(ok, reason)` — the single exit point. ALWAYS `sys.exit(0)`.

INVARIANT (a violation here is a security regression, not a bug):
    Every consumer of this module ALWAYS exits 0. These become `type: command`
    hooks carrying `|| true`, so a non-zero exit would be masked and the
    validator would be silently dead (CLAUDE.md §Failure-Mode Invariants, R3).
    `run_validator()` exists to guarantee that: ANY uncaught exception still
    routes through `emit()`.

    Unparseable stdin  => emit(True).  If the hook plumbing is malformed we
                          cannot validate, and we must not break the agent loop.
    Missing result block => emit(False, reason). That is a real finding.

No third-party dependency. Standard library only — PyYAML is NOT available on
the target macOS system Python (3.9.6), verified with `python3 -c "import yaml"`.
Target syntax level: Python 3.9.
"""

import glob
import json
import os
import re
import sys


# ── exit point ───────────────────────────────────────────────────────────────

def emit(ok, reason=""):
    """Print the decision JSON and exit 0. SINGLE EXIT POINT for every validator.

    {"ok": true}                   — passes
    {"ok": false, "reason": "..."} — fails

    The exit code is ALWAYS 0: these run as `type: command` hooks under
    `|| true`, and the decision is communicated on stdout, never via status.
    """
    out = {"ok": bool(ok)}
    if not ok:
        out["reason"] = reason
    try:
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()
    except (OSError, ValueError):
        # A closed/broken stdout must not turn into a non-zero exit.
        pass
    sys.exit(0)


def run_validator(fn):
    """Run a validator's main(), guaranteeing exit 0 through emit() on ANY path.

    R3 in the brief: "A validator exits non-zero on an edge (uncaught exception
    before emit), and `|| true` masks it — the hook silently validates nothing."
    A crash inside the validator is indistinguishable, from the agent loop's
    point of view, from malformed hook plumbing: we cannot validate, so we
    fail SAFE with ok:true and leave a diagnostic on stderr (visible in hook
    logs) rather than inventing a verdict.
    """
    try:
        fn()
    except SystemExit:
        raise
    except BaseException as exc:  # deliberate: nothing may escape this frame
        try:
            sys.stderr.write(
                "result_block_parser: validator crashed, failing safe (ok:true): "
                "%s: %s\n" % (type(exc).__name__, exc)
            )
        except BaseException:
            pass
        try:
            emit(True)
        except SystemExit:
            raise
        except BaseException:
            os._exit(0)
    # A validator that returned without emitting still must not hang the loop.
    emit(True)


# ── payload extraction ───────────────────────────────────────────────────────

class _Sentinel(object):
    def __init__(self, name):
        self._name = name

    def __repr__(self):
        return self._name

    def __bool__(self):
        return False


#: Returned by extract_payload() when stdin was not a JSON object at all.
PAYLOAD_UNPARSEABLE = _Sentinel("PAYLOAD_UNPARSEABLE")

NO_OUTPUT_REASON = (
    "could not locate agent output in the SubagentStop payload "
    "(checked last_assistant_message / result_block / output / agent_output / "
    "agent_transcript_path / transcript_path)"
)

#: The extraction ladder, in priority order. Kept as data so the self-test can
#: assert the order rather than re-encode it.
PAYLOAD_TEXT_KEYS = ("last_assistant_message", "result_block", "output", "agent_output")
PAYLOAD_TRANSCRIPT_KEYS = ("agent_transcript_path", "transcript_path")


def _last_assistant_text_from_transcript(path):
    """Best-effort extraction of the LAST assistant message's text from a Claude
    Code transcript JSONL. The transcript schema is not formally documented, so
    we defensively pull `text` parts from the last assistant-role entry.
    Returns "" on any read/parse failure."""
    last_text = ""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except (json.JSONDecodeError, ValueError):
                    continue
                msg = obj.get("message") if isinstance(obj, dict) else None
                if not isinstance(msg, dict):
                    msg = obj if isinstance(obj, dict) else {}
                role = msg.get("role") or obj.get("role") or obj.get("type")
                if role != "assistant":
                    continue
                content = msg.get("content")
                texts = []
                if isinstance(content, str):
                    texts.append(content)
                elif isinstance(content, list):
                    for part in content:
                        if isinstance(part, dict) and isinstance(part.get("text"), str):
                            texts.append(part["text"])
                if texts:
                    last_text = "\n".join(texts)
    except OSError:
        return ""
    return last_text


def extract_payload(argv=None, stream=None):
    """Read stdin once and resolve the agent's output text.

    Returns (text, payload) where:
      text == PAYLOAD_UNPARSEABLE — stdin was not a JSON object (or was
                                    unreadable). Caller MUST emit(True).
      text == ""                  — payload parsed but no agent output found.
                                    Caller emits ok:false with NO_OUTPUT_REASON.
      text is a str               — the agent output text.
    `payload` is the decoded hook payload dict, or None in --raw mode / on
    failure. Validators use it for the `cwd` field.
    """
    argv = sys.argv[1:] if argv is None else list(argv)
    stream = sys.stdin if stream is None else stream
    raw_mode = "--raw" in argv

    try:
        text = stream.read()
    except (OSError, UnicodeDecodeError, ValueError):
        return PAYLOAD_UNPARSEABLE, None

    if raw_mode:
        return text, None

    try:
        payload = json.loads(text)
    except (json.JSONDecodeError, ValueError):
        # Malformed hook plumbing — we cannot validate. Never break the loop.
        return PAYLOAD_UNPARSEABLE, None
    if not isinstance(payload, dict):
        return PAYLOAD_UNPARSEABLE, None

    for key in PAYLOAD_TEXT_KEYS:
        val = payload.get(key)
        if isinstance(val, str) and val:
            return val, payload

    # Prefer the subagent-scoped `agent_transcript_path` (the finishing
    # subagent's own messages) over the shared session `transcript_path`.
    for tp_key in PAYLOAD_TRANSCRIPT_KEYS:
        tp = payload.get(tp_key)
        if isinstance(tp, str) and tp and os.path.exists(tp):
            txt = _last_assistant_text_from_transcript(tp)
            if txt:
                return txt, payload

    return "", payload


def extract_payload_text(argv=None, stream=None):
    """Thin wrapper over extract_payload() returning only the text component."""
    return extract_payload(argv, stream)[0]


# ── block location ───────────────────────────────────────────────────────────

def _yaml_header_re(name):
    # `NAME:` alone on a line, optionally indented, optionally trailing comment.
    return re.compile(r"^([ \t]*)" + re.escape(name) + r"[ \t]*:[ \t]*(?:#.*)?$")


def _md_header_re(name):
    # `## NAME`, 1-6 hashes, optional bold/backtick decoration, optional colon.
    return re.compile(
        r"^[ \t]*#{1,6}[ \t]+`?\*{0,2}" + re.escape(name) + r"\*{0,2}`?[ \t]*:?[ \t]*$"
    )


def _indent_of(line):
    """Leading-whitespace width, counting tabs as one column (block framing only)."""
    return len(line) - len(line.lstrip(" \t"))


def _space_indent(line):
    """Leading SPACE width. Used wherever a dedent could otherwise swallow a tab."""
    return len(line) - len(line.lstrip(" "))


def find_last_block(text, name):
    """Return the LAST `name` block in `text` (header line + body), or None.

    Two shapes are recognised; whichever occurs LAST in the text wins:

      YAML form                  Markdown bullet form
      -----------------------    ---------------------------
      WORKER_RESULT:             ## WORKER_RESULT
        schema_version: 2        - schema_version: 2
        status: completed        - status: completed

    Returning the LAST block matches the plugin-wide contract ("the most recent
    emission wins"): agents legitimately restate example blocks while
    summarising what they emitted.

    Termination is deliberately STRICT (same posture as
    validate-launch-pad-result.py): a blank line, a dedent to the header's own
    level, or any line that does not belong to the body ends the block.
    """
    if not isinstance(text, str) or not text:
        return None

    yaml_hdr = _yaml_header_re(name)
    md_hdr = _md_header_re(name)
    lines = text.split("\n")
    best = None
    i = 0
    while i < len(lines):
        line = lines[i]

        m = yaml_hdr.match(line)
        if m:
            base = len(m.group(1))
            block = [line]
            j = i + 1
            while j < len(lines):
                nxt = lines[j]
                if nxt.strip() == "":
                    break
                if _indent_of(nxt) > base:
                    block.append(nxt)
                    j += 1
                else:
                    break
            best = "\n".join(block)
            i = max(j, i + 1)
            continue

        if md_hdr.match(line):
            block = [line]
            j = i + 1
            first_bullet_indent = None
            while j < len(lines):
                nxt = lines[j]
                if nxt.strip() == "":
                    break
                ind = _indent_of(nxt)
                stripped = nxt.lstrip(" \t")
                if stripped.startswith("- ") or stripped == "-":
                    if first_bullet_indent is None:
                        first_bullet_indent = ind
                    if ind < first_bullet_indent:
                        break
                    block.append(nxt)
                    j += 1
                    continue
                if first_bullet_indent is not None and ind > first_bullet_indent:
                    # Continuation line of a bullet (nested block sequence etc).
                    block.append(nxt)
                    j += 1
                    continue
                break
            if first_bullet_indent is not None:
                best = "\n".join(block)
            i = max(j, i + 1)
            continue

        i += 1

    return best


def find_last_named_block(text, names):
    """Like find_last_block, for a set of alternative block names.

    Returns (name, block) for whichever named block occurs LAST in `text`, or
    (None, None). Used by the Execute Manager validator, whose agent emits
    EITHER an EXECUTE_RESULT or an EXECUTE_CHECKPOINT.
    """
    found = None
    for name in names:
        block = find_last_block(text, name)
        if block is None:
            continue
        pos = text.rfind(block)
        if found is None or pos > found[0]:
            found = (pos, name, block)
    if found is None:
        return None, None
    return found[1], found[2]


# ── scalar / flow parsing ────────────────────────────────────────────────────

NULL_SPELLINGS = ("~", "null", "Null", "NULL")
TRUE_SPELLINGS = ("true", "True", "TRUE")
FALSE_SPELLINGS = ("false", "False", "FALSE")

_UNSUPPORTED_LEADERS = {
    "|": "block scalar (|)",
    ">": "block scalar (>)",
    "&": "anchor (&)",
    "*": "alias (*)",
    "!": "explicit tag (!)",
}


def _skip_ws(s, i):
    while i < len(s) and s[i] in " \t":
        i += 1
    return i


_DQ_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", '"': '"', "/": "/"}


def _read_quoted(s, i):
    """s[i] must be a quote character. Returns (value, next_index, err)."""
    q = s[i]
    i += 1
    buf = []
    while i < len(s):
        c = s[i]
        if q == '"' and c == "\\" and i + 1 < len(s):
            buf.append(_DQ_ESCAPES.get(s[i + 1], s[i + 1]))
            i += 2
            continue
        if q == "'" and c == "'" and i + 1 < len(s) and s[i + 1] == "'":
            buf.append("'")
            i += 2
            continue
        if c == q:
            return "".join(buf), i + 1, None
        buf.append(c)
        i += 1
    return None, i, "unterminated quoted scalar"


def parse_scalar(raw):
    """Parse a single YAML scalar. Returns (value, err).

    value is None for the five YAML null spellings (empty-after-colon, `~`,
    `null`, `Null`, `NULL`). A QUOTED "null"/'null' is the STRING "null" —
    never the null value. Everything else is returned as a str (numbers and
    booleans are NOT coerced here; validators do their own typed reads so the
    reason strings can name the offending literal verbatim).
    """
    s = raw.strip()
    if s == "" or s in NULL_SPELLINGS:
        return None, None
    if s[0] in "\"'":
        val, idx, err = _read_quoted(s, 0)
        if err:
            return None, err
        tail = s[idx:].strip()
        if tail and not tail.startswith("#"):
            return None, "trailing content after quoted scalar: %r" % tail
        return val, None
    if s[0] in _UNSUPPORTED_LEADERS:
        return None, "unsupported YAML construct: %s" % _UNSUPPORTED_LEADERS[s[0]]
    return s, None


def _flow_value(s, i):
    """Parse one flow-context value starting at s[i]. Returns (value, i, err)."""
    i = _skip_ws(s, i)
    if i >= len(s):
        return None, i, "unexpected end of flow collection"

    c = s[i]

    if c == "[":
        items = []
        i = _skip_ws(s, i + 1)
        if i < len(s) and s[i] == "]":
            return items, i + 1, None
        while True:
            val, i, err = _flow_value(s, i)
            if err:
                return None, i, err
            items.append(val)
            i = _skip_ws(s, i)
            if i >= len(s):
                return None, i, "unterminated flow sequence (missing ']')"
            if s[i] == ",":
                i = _skip_ws(s, i + 1)
                if i < len(s) and s[i] == "]":  # trailing comma
                    return items, i + 1, None
                continue
            if s[i] == "]":
                return items, i + 1, None
            return None, i, "unexpected character %r in flow sequence" % s[i]

    if c == "{":
        mapping = {}
        i = _skip_ws(s, i + 1)
        if i < len(s) and s[i] == "}":
            return mapping, i + 1, None
        while True:
            i = _skip_ws(s, i)
            if i >= len(s):
                return None, i, "unterminated flow mapping (missing '}')"
            if s[i] in "\"'":
                key, i, err = _read_quoted(s, i)
                if err:
                    return None, i, err
            else:
                j = i
                while j < len(s) and s[j] not in ":,}":
                    j += 1
                key = s[i:j].strip()
                i = j
            if not key:
                return None, i, "empty key in flow mapping"
            i = _skip_ws(s, i)
            if i >= len(s) or s[i] != ":":
                return None, i, "flow mapping key %r is not followed by ':'" % key
            i = _skip_ws(s, i + 1)
            if i < len(s) and s[i] in ",}":
                val = None  # `{k: }` — empty-after-colon is YAML null
            else:
                val, i, err = _flow_value(s, i)
                if err:
                    return None, i, err
            if key in mapping:
                return None, i, "duplicate key %r in flow mapping" % key
            mapping[key] = val
            i = _skip_ws(s, i)
            if i >= len(s):
                return None, i, "unterminated flow mapping (missing '}')"
            if s[i] == ",":
                i = _skip_ws(s, i + 1)
                if i < len(s) and s[i] == "}":  # trailing comma
                    return mapping, i + 1, None
                continue
            if s[i] == "}":
                return mapping, i + 1, None
            return None, i, "unexpected character %r in flow mapping" % s[i]

    if c in "\"'":
        val, i, err = _read_quoted(s, i)
        return val, i, err

    if c in _UNSUPPORTED_LEADERS:
        return None, i, "unsupported YAML construct: %s" % _UNSUPPORTED_LEADERS[c]

    j = i
    while j < len(s) and s[j] not in ",]}":
        j += 1
    tok = s[i:j].strip()
    val, err = parse_scalar(tok)
    return val, j, err


def parse_value(raw):
    """Parse the right-hand side of a `key:` line. Returns (value, err).

    Dispatches to the flow parser for `[`/`{` leaders, otherwise to
    parse_scalar. Junk trailing a closed flow collection is an EXPLICIT
    failure — never a silent coercion to a string.
    """
    s = raw.strip()
    if not s:
        return None, None
    if s[0] in "[{":
        val, idx, err = _flow_value(s, 0)
        if err:
            return None, err
        tail = s[idx:].strip()
        if tail and not tail.startswith("#"):
            return None, "trailing content after flow collection: %r" % tail
        return val, None
    return parse_scalar(s)


# ── block-body parsing ───────────────────────────────────────────────────────

_KEY_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_.+\-]*)[ \t]*:(?:[ \t](.*)|[ \t]*)$")
_SEQ_MARKER = "\x00SEQ"


class _Tok(object):
    __slots__ = ("indent", "content", "no")

    def __init__(self, indent, content, no):
        self.indent = indent
        self.content = content
        self.no = no

    def __repr__(self):  # pragma: no cover - debugging aid
        return "_Tok(%d, %r, %d)" % (self.indent, self.content, self.no)


def _tokenize(lines, errors):
    toks = []
    for offset, raw in enumerate(lines):
        no = offset + 1
        if raw.strip() == "":
            continue
        lead = raw[: len(raw) - len(raw.lstrip(" \t"))]
        if "\t" in lead:
            errors.append("line %d uses a TAB for indentation (unsupported)" % no)
            continue
        body = raw.strip()
        if body.startswith("#"):
            continue
        if body in ("---", "..."):
            errors.append("line %d: multi-document YAML markers are unsupported" % no)
            continue
        if body.startswith("<<"):
            errors.append("line %d: YAML merge keys (<<) are unsupported" % no)
            continue
        toks.append(_Tok(len(lead), body, no))
    return toks


def _expand_sequence_markers(toks, errors):
    """Rewrite `- content` into a marker token plus an indented content token.

    This turns block-sequence handling into the same shape as mapping handling
    and, crucially, makes `- kind: file` / `  path: x` (a sequence OF mappings)
    fall out of the ordinary recursive descent instead of needing a special case.
    """
    out = []
    for tok in toks:
        indent, content, no = tok.indent, tok.content, tok.no
        while True:
            if content == "-":
                out.append(_Tok(indent, _SEQ_MARKER, no))
                content = None
                break
            if content.startswith("- "):
                out.append(_Tok(indent, _SEQ_MARKER, no))
                rest = content[2:]
                extra = len(rest) - len(rest.lstrip(" "))
                indent = indent + 2 + extra
                content = rest.lstrip(" ")
                if content == "":
                    content = None
                    break
                continue
            break
        if content is not None:
            if content.startswith("-") and not _KEY_RE.match(content):
                # e.g. `-item` (no space) — not a valid sequence entry.
                errors.append(
                    "line %d: %r is not a valid mapping entry or sequence item "
                    "(a sequence item needs '- ' with a space)" % (no, content)
                )
                continue
            out.append(_Tok(indent, content, no))
    return out


def _collect_body(toks, i, indent):
    """Return (body_tokens, next_index) for tokens indented deeper than `indent`."""
    start = i
    while i < len(toks) and toks[i].indent > indent:
        i += 1
    return toks[start:i], i


def _parse_nested(body, errors):
    """Parse a collected body (mapping, sequence, or single scalar)."""
    if not body:
        return None
    if body[0].content == _SEQ_MARKER:
        return _parse_sequence(body, 0, body[0].indent, errors)[0]
    if _KEY_RE.match(body[0].content):
        return _parse_mapping(body, 0, body[0].indent, errors)[0]
    if len(body) > 1:
        errors.append(
            "line %d: multi-line plain scalars are unsupported "
            "(use a quoted or flow value)" % body[0].no
        )
        return None
    val, err = parse_value(body[0].content)
    if err:
        errors.append("line %d: %s" % (body[0].no, err))
    return val


def _parse_sequence(toks, i, indent, errors):
    items = []
    while i < len(toks) and toks[i].indent == indent and toks[i].content == _SEQ_MARKER:
        i += 1
        body, i = _collect_body(toks, i, indent)
        items.append(_parse_nested(body, errors))
    return items, i


def _parse_mapping(toks, i, indent, errors):
    result = {}
    while i < len(toks):
        tok = toks[i]
        if tok.indent < indent:
            break
        if tok.content == _SEQ_MARKER:
            errors.append(
                "line %d: sequence item found where a mapping key was expected" % tok.no
            )
            break
        if tok.indent > indent:
            errors.append(
                "line %d: unexpected indentation for %r" % (tok.no, tok.content)
            )
            i += 1
            continue
        match = _KEY_RE.match(tok.content)
        if not match:
            errors.append(
                "line %d: %r is not a 'key: value' entry "
                "(a mapping needs a space after the colon)" % (tok.no, tok.content)
            )
            i += 1
            continue
        key = match.group(1)
        rest = match.group(2)
        if key in result:
            errors.append("line %d: duplicate key %r" % (tok.no, key))
        if rest is None or rest.strip() == "":
            body, i = _collect_body(toks, i + 1, indent)
            if body:
                result[key] = _parse_nested(body, errors)
            else:
                # empty-after-colon — one of the five YAML null spellings
                result[key] = None
            continue
        val, err = parse_value(rest)
        if err:
            errors.append("line %d: %s" % (tok.no, err))
        result[key] = val
        i += 1
    return result, i


def _normalize_body(block, errors):
    """Strip the header and de-indent the body into plain YAML lines.

    Handles both emission shapes; the markdown bullet form's `- ` markers are
    dropped so the two collapse onto one representation before parsing.
    """
    lines = block.split("\n")
    if not lines:
        return []
    header = lines[0]
    body = lines[1:]

    if re.match(r"^[ \t]*#{1,6}[ \t]", header):
        # Markdown bullet form: `- key: value` at a fixed base indent.
        base = None
        for line in body:
            if line.strip() == "":
                continue
            stripped = line.lstrip(" ")
            if stripped.startswith("- ") or stripped == "-":
                base = _indent_of(line)
                break
        if base is None:
            return []
        out = []
        for offset, line in enumerate(body):
            if line.strip() == "":
                out.append("")
                continue
            ind = _indent_of(line)
            if ind == base:
                if not (line[base:].startswith("- ") or line[base:].rstrip() == "-"):
                    errors.append(
                        "line %d: %r is not a '- key: value' bullet in a "
                        "markdown-style result block" % (offset + 2, line.strip())
                    )
                    continue
                out.append(line[base + 2:] if line[base:].startswith("- ") else "")
            elif ind > base:
                # Continuation / nested content: shift left by the bullet width.
                out.append(line[min(base + 2, ind):])
            else:
                errors.append(
                    "line %d: %r is dedented out of the result block"
                    % (offset + 2, line.strip())
                )
        return out

    # YAML form: de-indent by the minimum indent of the body.
    #
    # The shift is computed over SPACES ONLY, deliberately. Counting a leading
    # tab as indentation would let the dedent CONSUME it, and _tokenize's
    # tab-indentation rejection would then never see it — a construct outside
    # the supported subset would be silently normalised into a valid one, which
    # is exactly the silent coercion this parser must never do.
    indents = [_space_indent(l) for l in body if l.strip() != ""]
    if not indents:
        return []
    shift = min(indents)
    return [l[shift:] if l.strip() != "" else "" for l in body]


def parse_block(block):
    """Parse a located result block into (fields, errors).

    `fields` maps top-level key -> parsed value:
        str          scalar (quotes stripped; numbers/booleans left as text)
        None         one of the five YAML null spellings
        list         flow or block sequence (possibly of dicts)
        dict         flow or block mapping

    KEY PRESENCE vs NULL: `key in fields` is the presence test; `fields[key] is
    None` is the null test. They are DIFFERENT outcomes and every validator
    that has a nullable-but-required field must check presence explicitly
    (the nullable-required-field lesson — a truthiness check silently accepts
    a missing key when null is also legal).

    `errors` is a list of explicit parse-failure strings. A non-empty list
    means the block used a construct outside the supported subset; callers
    MUST surface it rather than proceeding on partial data.
    """
    errors = []
    if not block:
        return {}, ["empty result block"]
    lines = _normalize_body(block, errors)
    toks = _tokenize(lines, errors)
    toks = _expand_sequence_markers(toks, errors)
    if not toks:
        errors.append("result block has no parseable body lines")
        return {}, errors
    base = toks[0].indent
    fields, consumed = _parse_mapping(toks, 0, base, errors)
    if consumed < len(toks):
        errors.append(
            "line %d: trailing content could not be parsed (%r)"
            % (toks[consumed].no, toks[consumed].content)
        )
    return fields, errors


# ── typed reads / small helpers used by every validator ──────────────────────

def present(fields, key):
    """Key-PRESENCE test. Distinct from truthiness and from null-ness."""
    return key in fields


def is_null(fields, key):
    """True iff the key is present AND parsed as a YAML null."""
    return key in fields and fields[key] is None


def as_int(value):
    """Return (int, None) for an integer literal, else (None, describe)."""
    if isinstance(value, bool):
        return None, repr(value)
    if isinstance(value, int):
        return value, None
    if isinstance(value, str):
        token = value.strip()
        if re.match(r"^[+-]?\d+$", token):
            return int(token), None
    return None, repr(value)


def as_bool(value):
    """Return (bool, None) for a YAML boolean literal, else (None, describe)."""
    if isinstance(value, bool):
        return value, None
    if isinstance(value, str):
        token = value.strip()
        if token in TRUE_SPELLINGS:
            return True, None
        if token in FALSE_SPELLINGS:
            return False, None
    return None, repr(value)


def as_text(value):
    """Render a parsed value back to a comparable string ("" for null)."""
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    return str(value)


def is_empty_scalar(value):
    """True for null, empty string, or the conventional 'none'/'n/a' placeholders."""
    if value is None:
        return True
    if isinstance(value, str):
        return value.strip().lower() in ("", "none", "null", "n/a", "na", "-")
    if isinstance(value, (list, dict)):
        return len(value) == 0
    return False


def load_block(names, missing_reason, argv=None, stream=None):
    """Common prologue shared by all five validators.

    Resolves stdin -> agent text -> the LAST result block -> parsed fields,
    emitting (and exiting 0) on every failure path:

      unparseable stdin       -> emit(True)                 (plumbing malformed)
      no agent output located -> emit(False, NO_OUTPUT_REASON)
      no result block found   -> emit(False, missing_reason)
      block parse failure     -> emit(False, "<block> could not be parsed: ...")

    Returns (block_name, fields, text, payload) on success.
    """
    if isinstance(names, str):
        names = (names,)
    text, payload = extract_payload(argv, stream)
    if text is PAYLOAD_UNPARSEABLE:
        emit(True)
    if not text:
        emit(False, NO_OUTPUT_REASON)

    name, block = find_last_named_block(text, names)
    if block is None:
        emit(False, missing_reason)

    fields, errors = parse_block(block)
    if errors:
        emit(
            False,
            "%s block could not be parsed (unsupported or malformed YAML): %s"
            % (name, "; ".join(errors[:3])),
        )
    return name, fields, text, payload


# ── shared worker-side helpers (kept here so they are self-tested once) ──────

#: The destructive commands the worker SubagentStop prompt scans for.
DESTRUCTIVE_COMMANDS = ("rm -rf", "git push", "git reset --hard", "DROP", "TRUNCATE")

# Command position: start of line, or after a shell separator. Matching bare
# substrings would fire on the many prose mentions ("no git push", "never
# rm -rf"), so the patterns are anchored to command position and lines
# carrying a negation cue are skipped — the same negation-filter convention
# CLAUDE.md already uses for the `gh pr merge --squash` invariant check
# (`grep -viE "no |never |not "`).
_CMD_START = r"(?:^|(?<=&&)|(?<=\|\|)|(?<=;)|(?<=`)|(?<=\$\())[ \t]*(?:[$>][ \t]+)?"

_DESTRUCTIVE_PATTERNS = (
    ("rm -rf", re.compile(_CMD_START + r"(?:sudo[ \t]+)?rm[ \t]+-[a-zA-Z]*[rR][a-zA-Z]*[fF]\b", re.M)),
    ("rm -rf", re.compile(_CMD_START + r"(?:sudo[ \t]+)?rm[ \t]+-[a-zA-Z]*[fF][a-zA-Z]*[rR]\b", re.M)),
    ("git push", re.compile(_CMD_START + r"git[ \t]+(?:-[^ \t]+[ \t]+)*push\b", re.M)),
    ("git reset --hard", re.compile(_CMD_START + r"git[ \t]+(?:-[^ \t]+[ \t]+)*reset[ \t]+--hard\b", re.M)),
    ("DROP", re.compile(r"\bDROP[ \t]+(?:TABLE|DATABASE|SCHEMA|VIEW|INDEX|COLUMN|CONSTRAINT|TYPE)\b")),
    ("TRUNCATE", re.compile(r"\bTRUNCATE[ \t]+(?:TABLE[ \t]|[A-Za-z_])")),
)

_NEGATION_RE = re.compile(
    r"(?i)\b(?:no|not|non|never|without|avoid|avoided|avoids|forbid\w*|prohibit\w*|"
    r"disallow\w*|refus\w*|skip|skipped|blocked|must[ \t]not|cannot|can't|don't|"
    r"do[ \t]not|did[ \t]not|didn't|check|scan|scanned|scanning)\b"
)


def find_destructive_command(text):
    """Return the destructive command found in `text` as an executed command, else None.

    HONEST LIMITS: this is a heuristic, exactly as the haiku prompt it replaces
    was a judgement call. It anchors to command position and skips lines
    carrying a negation cue, so the plugin's own prose ("no destructive
    commands (rm -rf, git push, ...)") does not false-positive. It can still be
    evaded by an unusual invocation form; it is a tripwire, not a sandbox.
    """
    if not text:
        return None
    for label, pattern in _DESTRUCTIVE_PATTERNS:
        for match in pattern.finditer(text):
            line_start = text.rfind("\n", 0, match.start()) + 1
            line_end = text.find("\n", match.end())
            line = text[line_start:line_end if line_end != -1 else len(text)]
            if _NEGATION_RE.search(line):
                continue
            return label
    return None


def worker_summary_file_evidence(task_id, text, payload):
    """True when there is evidence a worker summary file was written.

    Checked in order (strongest first):
      1. `{cwd}/.worker-summary.md`                       (inline / worktree cwd)
      2. `{cwd}/.supervisor/worker-summaries/{task_id}.md` (inline mode)
      3. `../*{task_id}/.worker-summary.md`                (sibling worktree, per
         the ARCHITECTURE_CONTRACTS worktree naming convention)
      4. the literal marker `summary_file_write_failed` in the output (the
         documented best-effort degradation)
      5. the output naming the summary file it wrote

    Tier 5 exists for PARITY, not laxity: the prompt hook this replaces was a
    model call with only the transcript — it had NO filesystem access at all,
    so text evidence was its ONLY evidence. Tiers 1-3 are a strict improvement
    over that; dropping tier 5 would make the check stricter than the thing it
    replaces and would false-fail every worktree whose directory name does not
    embed the task_id.
    """
    roots = [os.getcwd()]
    if isinstance(payload, dict):
        cwd = payload.get("cwd")
        if isinstance(cwd, str) and cwd and cwd not in roots:
            roots.append(cwd)

    for root in roots:
        try:
            if os.path.exists(os.path.join(root, ".worker-summary.md")):
                return True
            if task_id and os.path.exists(
                os.path.join(root, ".supervisor", "worker-summaries", task_id + ".md")
            ):
                return True
            if task_id:
                parent = os.path.dirname(os.path.abspath(root))
                if glob.glob(os.path.join(parent, "*" + task_id, ".worker-summary.md")):
                    return True
        except OSError:
            continue

    if "summary_file_write_failed" in text:
        return True
    if ".worker-summary.md" in text or "worker-summaries/" in text:
        return True
    return False


if __name__ == "__main__":  # pragma: no cover - module is a library
    sys.stderr.write(
        "result_block_parser.py is a library module for the validate-*-result.py "
        "hooks; it is not meant to be executed directly.\n"
    )
    sys.exit(0)
