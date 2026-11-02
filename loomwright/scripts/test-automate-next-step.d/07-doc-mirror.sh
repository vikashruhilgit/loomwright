echo "-- D. the schema doc mirrors the driver (closed lists)"
DOC="$HERE/../docs/result-schemas/automate-run.md"
arms="$(awk '/^ns_dispatch\(\) \{/,/^}/' "$DRIVER" | sed -n 's/^    \([a-z][a-z-]*\)) .*/\1/p' | env LC_ALL=C sort | tr '\n' ' ')"
docarms="$(grep -F "one of the driver's \`case\` arms:" "$DOC" | sed 's/.*arms: //; s/).*//' | grep -oE '`[a-z-]+`' | tr -d '`' | env LC_ALL=C sort | tr '\n' ' ')"
[ -n "$arms" ] && [ "$arms" = "$docarms" ] && ok "D: the doc's step list equals the driver's case arms ($arms)" || no "D: steps: driver '$arms' vs doc '$docarms'"
dos="$(grep -oE 'ns_emit (spawn|ask|park|done|[a-z]+) ' "$DRIVER" | awk '{print $2}' | env LC_ALL=C sort -u | tr '\n' ' ')"
docdos="$(grep -E '^\| `[a-z]+` \| ' "$DOC" | sed -n 's/^| `\([a-z]*\)` | .*/\1/p' | env LC_ALL=C sort -u | tr '\n' ' ')"
[ "$dos" = "ask done park spawn " ] && [ "$docdos" = "$dos" ] && ok "D: the closed do enum (spawn | ask | park | done) — emitter and doc agree" \
  || no "D: do enum: driver '$dos' vs doc '$docdos'"
# the spawn's `what` values (automate-speed/09 added "launch pad phase"): the driver's emitters vs the doc's spawn row
whats="$(grep -oE 'what: "[^"]+"' "$DRIVER" | sed 's/^what: //' | tr -d '"' | env LC_ALL=C sort -u | tr '\n' '|')"
docwhats="$(grep -E '^\| `spawn` \| ' "$DOC" | grep -oE '`"[^"`]+"`' | tr -d '`"' | env LC_ALL=C sort -u | tr '\n' '|')"
[ "$whats" = "/autonomous run|fix-now re-drain|launch pad phase|owned drain|" ] && [ "$docwhats" = "$whats" ] \
  && ok "D: the spawn's what values (/autonomous run | fix-now re-drain | launch pad phase | owned drain) — emitter and doc agree" \
  || no "D: what values: driver '$whats' vs doc '$docwhats'"
# the coordinator_model closed list: the driver's NS_CM_VALUES vs the schema doc's restatement beside the key
cmv="$(awk "/^NS_CM_VALUES='/{f=1; sub(/^NS_CM_VALUES='/, \"\")} f{ l = \$0; e = sub(/'\$/, \"\", l); print l; if (e) exit }" "$DRIVER" | env LC_ALL=C sort | tr '\n' ' ')"
doccmv="$(grep -F 'coordinator_model values (closed):' "$DOC" | grep -oE '`(session|claude-[a-z0-9-]+)`' | tr -d '`' | env LC_ALL=C sort -u | tr '\n' ' ')"
[ "$cmv" = "claude-haiku-5-5 claude-sonnet-5-5 session " ] && [ "$doccmv" = "$cmv" ] \
  && ok "D: the coordinator_model closed list (session | claude-haiku-5-5 | claude-sonnet-5-5) — driver and doc agree" \
  || no "D: coordinator_model values: driver '$cmv' vs doc '$doccmv'"
grep -qF 'coordinator_model' <<<"$(grep -F '**Common fields:**' "$DOC")" && ok "D: the doc's Common fields name coordinator_model" \
  || no "D: the doc's Common fields do not name coordinator_model"
