#!/usr/bin/env python3
"""materialize.py — build a runnable SubagentStop payload from the committed
real-shape fixture in this directory (see README.md for provenance).

Usage:
  materialize.py <out_dir> <agent_type> <handback_message_file|-> <recap_text>
                 [--cwd <abs>] [--no-agent-transcript] [--parent-handback]
                 [--extra-handback <message_file>]

Writes <out_dir>/agent-transcript.jsonl (the committed transcript with its
`__HANDBACK_MESSAGE__` / `__RECAP__` placeholders filled) and prints the
payload JSON on stdout, with `agent_transcript_path` rewritten to the
materialised transcript's ABSOLUTE path (every real payload carries absolute
paths) and `last_assistant_message` set to <recap_text>.

  -                     handback message is empty (the transcript's
                        SubagentHandback call is dropped entirely)
  --no-agent-transcript omit `agent_transcript_path` from the payload
  --parent-handback     write the transcript at `transcript_path` (the PARENT
                        session) instead, and omit `agent_transcript_path`
  --extra-handback F    insert an EARLIER SubagentHandback carrying F's text,
                        so "the LAST handback wins" can be asserted
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def main(argv):
    out_dir, agent_type, hb_file, recap = argv[:4]
    rest = argv[4:]
    cwd = None
    no_atp = "--no-agent-transcript" in rest
    parent = "--parent-handback" in rest
    extra = None
    if "--cwd" in rest:
        cwd = rest[rest.index("--cwd") + 1]
    if "--extra-handback" in rest:
        with open(rest[rest.index("--extra-handback") + 1], encoding="utf-8") as fh:
            extra = fh.read()
    hb = ""
    if hb_file != "-":
        with open(hb_file, encoding="utf-8") as fh:
            hb = fh.read()

    with open(os.path.join(HERE, "payload.json"), encoding="utf-8") as fh:
        payload = json.load(fh)
    entries = []
    with open(os.path.join(HERE, "agent-transcript.jsonl"), encoding="utf-8") as fh:
        for line in fh:
            if line.strip():
                entries.append(json.loads(line))

    out = []
    for e in entries:
        content = e["message"]["content"]
        if isinstance(content, list):
            parts = []
            for part in content:
                if part.get("name") == "SubagentHandback":
                    if extra is not None:
                        parts.append(dict(part, id="toolu_hb_early",
                                          input={"message": extra}))
                    if not hb:
                        continue
                    part = dict(part, input={"message": hb})
                elif part.get("type") == "text" and part.get("text") == "__RECAP__":
                    part = dict(part, text=recap)
                parts.append(part)
            if not parts:
                continue
            e = dict(e, message=dict(e["message"], content=parts))
        out.append(e)

    os.makedirs(out_dir, exist_ok=True)
    tpath = os.path.abspath(os.path.join(out_dir, "agent-transcript.jsonl"))
    with open(tpath, "w", encoding="utf-8") as fh:
        for e in out:
            fh.write(json.dumps(e) + "\n")

    payload["agent_type"] = agent_type
    payload["last_assistant_message"] = recap
    payload["agent_transcript_path"] = tpath
    if cwd is not None:
        payload["cwd"] = cwd
    if parent:
        payload["transcript_path"] = tpath
        del payload["agent_transcript_path"]
    elif no_atp:
        del payload["agent_transcript_path"]
    sys.stdout.write(json.dumps(payload))


if __name__ == "__main__":
    main(sys.argv[1:])
