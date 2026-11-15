// criteria.mjs — acceptance criteria in, criteria.json out, plus the testability pre-check.
//
//   selvedge criteria from-pr <n> [--source <label>]     the PR body's "Acceptance criteria" list (gh)
//   selvedge criteria from-md <file> [--source <label>]  a markdown `- ` list
//   selvedge criteria from-text [--source <label>]       stdin (a list, or one criterion per line)
//   selvedge criteria check <criteria.json>              testable / vague, with a rewrite for vague
//
// Same criteria text → the same criteria.json bytes, whatever the input: ids are `c-` + the first 12
// hex of sha256(normalized text), `source` is null unless --source is passed (provenance goes to
// stderr), and the file is pretty-printed with 2 spaces and a trailing newline.
//
// Also a library: classifyTestability, criteriaSha256, readCriteriaFile, validateCriteriaDoc are
// imported by the plan modules. The CLI runs only when this file is the main module.
//
// Exit codes: 0 ok, 1 an operation failed (gh), 2 usage error or a named reason on stderr. Every
// reason comes from REASONS in env-config.mjs.
//
// Node >= 18, standard library only.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { EnvError, REASONS, UsageError, isMain, parseCliArgs } from './env-config.mjs';
import { canonicalJson } from './env-approvals.mjs';

export const CRITERIA_SCHEMA_VERSION = 1;
// The validator's accepted key sets; selvedge/schemas/criteria.schema.json declares the same names
// (selvedge/tests/test-criteria.sh asserts they are equal).
export const CRITERIA_KEYS = Object.freeze(['schema_version', 'source', 'criteria']);
export const CRITERION_KEYS = Object.freeze(['id', 'text']);
export const CRITERION_ID_PATTERN = '^c-[0-9a-f]{12}$';

// The testability pre-check is deterministic: a criterion is vague when it uses one of these phrases
// and carries no quoted literal and no digit (a value a check could read).
export const VAGUE_PHRASES = Object.freeze([
  'works well',
  'looks good',
  'looks right',
  'looks nice',
  'user-friendly',
  'intuitive',
  'as expected',
  'properly',
  'correctly',
  'seamless',
]);

const USAGE = `Usage: selvedge criteria <command>

Commands:
  from-pr <n> [--source <label>]      the list under the PR body's "Acceptance criteria" heading
                                      (gh pr view <n> --json body)
  from-md <file> [--source <label>]   a markdown list (the "Acceptance criteria" section when there is one)
  from-text [--source <label>]        stdin: a list, or one criterion per line
  check <criteria.json>               classify each criterion testable or vague (with a rewrite)

from-* print criteria.json on stdout. Exit codes: 0 ok, 1 an operation failed, 2 usage error or a
named reason on stderr.`;

function sha256Hex(s) {
  return createHash('sha256').update(s, 'utf8').digest('hex');
}

// Strip a list marker, a checkbox marker and surrounding whitespace; collapse inner whitespace.
export function normalizeCriterionText(raw) {
  let s = String(raw).replace(/\s+/g, ' ').trim();
  s = s.replace(/^(?:[-*+]|\d{1,9}[.)])\s+/, '');
  s = s.replace(/^\[[ xX]\](?:\s+|$)/, '');
  return s.trim();
}

export function criterionId(text) {
  return `c-${sha256Hex(text).slice(0, 12)}`;
}

// sha256 hex of canonicalJson(criteria) — the criteria ARRAY only; `source` is excluded, so the
// same criteria from any input hash alike.
export function criteriaSha256(criteria) {
  if (!Array.isArray(criteria)) throw new TypeError('criteriaSha256 takes the criteria array');
  return sha256Hex(canonicalJson(criteria));
}

function escapeRe(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function hasQuotedLiteral(text) {
  return /"[^"]+"|“[^”]+”|`[^`]+`|(?:^|[^\w])'[^']+'(?!\w)/.test(text);
}

// classifyTestability(text) → { testability: 'testable' } | { testability: 'vague', phrase, rewrite }.
export function classifyTestability(text) {
  const t = typeof text === 'string' ? text : '';
  const lower = t.toLowerCase();
  const phrase = VAGUE_PHRASES.find((p) => new RegExp(`(?:^|[^a-z0-9])${escapeRe(p)}(?:$|[^a-z0-9])`).test(lower));
  if (!phrase || /\d/.test(t) || hasQuotedLiteral(t)) return { testability: 'testable' };
  return {
    testability: 'vague',
    phrase,
    rewrite: `After <the action>, <the element> shows "<the exact text or number>" (replace "${phrase}" in "${t}" with a value a check can read)`,
  };
}

const ATX_HEADING = /^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$/;
const BOLD_HEADING = /^\s{0,3}(\*\*|__)(.+?)\1:?\s*$/;
const THEMATIC_BREAK = /^\s{0,3}([-*_])(?:\s*\1){2,}\s*$/;
const LIST_ITEM = /^(\s*)(?:[-*+]|\d{1,9}[.)])\s+(.*)$/;
const FENCE = /^\s*(?:```|~~~)/;
const AC_TITLE = /acceptance criteria/i;

// The lines of the section under the first heading (ATX `#…` or a bold-only line) whose title
// contains "Acceptance criteria", up to the next heading of the same or a higher level; null when
// there is no such heading.
function acceptanceSection(lines) {
  for (let i = 0; i < lines.length; i += 1) {
    const atx = ATX_HEADING.exec(lines[i]);
    const bold = atx ? null : BOLD_HEADING.exec(lines[i]);
    const title = atx ? atx[2] : bold ? bold[2] : null;
    if (title === null || !AC_TITLE.test(title)) continue;
    const level = atx ? atx[1].length : 7; // a bold line ends at any heading
    let end = lines.length;
    for (let j = i + 1; j < lines.length; j += 1) {
      const h = ATX_HEADING.exec(lines[j]);
      if ((h && h[1].length <= level) || (!atx && BOLD_HEADING.test(lines[j]))) {
        end = j;
        break;
      }
    }
    return lines.slice(i + 1, end);
  }
  return null;
}

// Top-level list items (indent 0-3). An indented continuation line or a nested item is folded into
// its parent item; a blank line or a paragraph ends it. Fenced code is skipped.
function listItems(lines) {
  const items = [];
  let cur = null;
  let inFence = false;
  for (const line of lines) {
    if (FENCE.test(line)) {
      inFence = !inFence;
      cur = null;
      continue;
    }
    if (inFence) continue;
    if (line.trim() === '' || THEMATIC_BREAK.test(line) || ATX_HEADING.test(line)) {
      cur = null;
      continue;
    }
    const m = LIST_ITEM.exec(line);
    if (m) {
      const indent = m[1].replace(/\t/g, '    ').length;
      if (indent <= 3) {
        cur = { raw: m[2] };
        items.push(cur);
      } else if (cur) {
        cur.raw += ` ${m[2]}`;
      }
      continue;
    }
    if (cur && /^\s/.test(line)) cur.raw += ` ${line.trim()}`;
    else cur = null;
  }
  return items.map((it) => it.raw);
}

function toCriteria(raws) {
  const seen = new Set();
  const out = [];
  for (const raw of raws) {
    const text = normalizeCriterionText(raw);
    if (text === '') continue;
    const id = criterionId(text);
    if (seen.has(id)) continue;
    seen.add(id);
    out.push({ id, text });
  }
  return out;
}

// extractCriteria(text, { mode }) → [{ id, text }].
//  - 'pr':   the list under an "Acceptance criteria" heading; no heading → [].
//  - 'md':   that section's list when the heading exists, else every top-level list item.
//  - 'text': like 'md'; with no list item at all, each non-blank, non-heading line is a criterion.
export function extractCriteria(text, { mode }) {
  const lines = String(text).replace(/\r\n?/g, '\n').split('\n');
  const section = acceptanceSection(lines);
  if (mode === 'pr' && section === null) return [];
  const scope = section === null ? lines : section;
  let raws = listItems(scope);
  if (raws.length === 0 && mode === 'text') {
    raws = scope.filter((l) => l.trim() !== '' && !ATX_HEADING.test(l) && !FENCE.test(l));
  }
  return toCriteria(raws);
}

export function criteriaDoc(criteria, source = null) {
  return { schema_version: CRITERIA_SCHEMA_VERSION, source, criteria };
}

export function serializeCriteria(doc) {
  return `${JSON.stringify(doc, null, 2)}\n`;
}

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

// Throws EnvError criteria_invalid (or criteria_not_found for an empty list) naming the first problem.
export function validateCriteriaDoc(doc) {
  const bad = (msg) => {
    throw new EnvError(REASONS.criteria_invalid, msg);
  };
  if (!isPlainObject(doc)) bad('criteria.json must be a JSON object');
  for (const k of Object.keys(doc)) if (!CRITERIA_KEYS.includes(k)) bad(`unknown key "${k}" (allowed: ${CRITERIA_KEYS.join(', ')})`);
  for (const k of CRITERIA_KEYS) if (!(k in doc)) bad(`missing "${k}"`);
  if (doc.schema_version !== CRITERIA_SCHEMA_VERSION) bad(`"schema_version" must be ${CRITERIA_SCHEMA_VERSION}`);
  if (doc.source !== null && typeof doc.source !== 'string') bad('"source" must be a string or null');
  if (!Array.isArray(doc.criteria)) bad('"criteria" must be an array');
  if (doc.criteria.length === 0) throw new EnvError(REASONS.criteria_not_found, 'criteria.json lists no criteria');
  const ids = new Set();
  doc.criteria.forEach((c, i) => {
    if (!isPlainObject(c)) bad(`criteria[${i}] must be an object`);
    for (const k of Object.keys(c)) if (!CRITERION_KEYS.includes(k)) bad(`criteria[${i}]: unknown key "${k}"`);
    if (typeof c.text !== 'string' || c.text === '' || normalizeCriterionText(c.text) !== c.text) {
      bad(`criteria[${i}].text must be a non-empty normalized string`);
    }
    if (c.id !== criterionId(c.text)) bad(`criteria[${i}].id must be ${criterionId(c.text)} (c- + 12 hex of sha256(text))`);
    if (ids.has(c.id)) bad(`criteria[${i}]: duplicate id ${c.id}`);
    ids.add(c.id);
  });
  return doc;
}

// readCriteriaFile(file) → a validated criteria.json document.
export function readCriteriaFile(file) {
  let raw;
  try {
    raw = readFileSync(file, 'utf8');
  } catch (e) {
    throw new EnvError(REASONS.criteria_not_found, `cannot read ${file}: ${e && e.code ? e.code : e && e.message}`);
  }
  let doc;
  try {
    doc = JSON.parse(raw);
  } catch (e) {
    throw new EnvError(REASONS.criteria_invalid, `${file} is not valid JSON: ${e && e.message}`);
  }
  return validateCriteriaDoc(doc);
}

// ---- CLI ---------------------------------------------------------------------------------------
function err(line) {
  process.stderr.write(`selvedge criteria: ${line}\n`);
}

function emit(criteria, source, provenance) {
  if (criteria.length === 0) throw new EnvError(REASONS.criteria_not_found, `no criteria found in ${provenance}`);
  process.stdout.write(serializeCriteria(criteriaDoc(criteria, source === undefined ? null : source)));
  err(`${criteria.length} criteria from ${provenance}`);
  return 0;
}

function cmdFromPr(args) {
  const { flags, positional } = parseCliArgs(args, { values: ['source'] });
  if (positional.length !== 1 || !/^[0-9]+$/.test(positional[0])) throw new UsageError('from-pr takes one PR number');
  const n = positional[0];
  let body;
  try {
    const out = execFileSync('gh', ['pr', 'view', n, '--json', 'body'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 16 * 1024 * 1024,
    });
    body = JSON.parse(out).body;
  } catch (e) {
    const why = e && e.code === 'ENOENT' ? 'gh is not on PATH' : (e && e.stderr ? String(e.stderr).trim().split('\n')[0] : e && e.message);
    err(`gh pr view ${n} --json body failed: ${why}`);
    return 1;
  }
  if (typeof body !== 'string') {
    err(`gh pr view ${n} returned no body`);
    return 1;
  }
  const criteria = extractCriteria(body, { mode: 'pr' });
  return emit(criteria, flags.source, `PR #${n} (the list under its "Acceptance criteria" heading, via gh pr view)`);
}

function cmdFromMd(args) {
  const { flags, positional } = parseCliArgs(args, { values: ['source'] });
  if (positional.length !== 1) throw new UsageError('from-md takes one markdown file');
  let text;
  try {
    text = readFileSync(positional[0], 'utf8');
  } catch (e) {
    throw new EnvError(REASONS.criteria_not_found, `cannot read ${positional[0]}: ${e && e.code ? e.code : e && e.message}`);
  }
  return emit(extractCriteria(text, { mode: 'md' }), flags.source, positional[0]);
}

function cmdFromText(args) {
  const { flags, positional } = parseCliArgs(args, { values: ['source'] });
  if (positional.length) throw new UsageError(`from-text reads stdin; unexpected argument: ${positional[0]}`);
  let text = '';
  try {
    text = readFileSync(0, 'utf8');
  } catch (e) {
    if (!e || e.code !== 'EAGAIN') throw e;
  }
  return emit(extractCriteria(text, { mode: 'text' }), flags.source, 'stdin');
}

function cmdCheck(args) {
  const { positional } = parseCliArgs(args);
  if (positional.length !== 1) throw new UsageError('check takes one criteria.json');
  const doc = readCriteriaFile(positional[0]);
  let vague = 0;
  for (const c of doc.criteria) {
    const r = classifyTestability(c.text);
    if (r.testability === 'vague') {
      vague += 1;
      process.stdout.write(`vague ${c.id} (${JSON.stringify(r.phrase)}): rewrite: ${r.rewrite}\n`);
    } else {
      process.stdout.write(`testable ${c.id}\n`);
    }
  }
  err(`${doc.criteria.length} criteria: ${doc.criteria.length - vague} testable, ${vague} vague (vague ones are never planned)`);
  return 0;
}

async function main(argv) {
  const major = Number(String(process.versions.node).split('.')[0]);
  if (!(major >= 18)) {
    err(`needs Node.js >= 18 (this is ${process.versions.node})`);
    return 1;
  }
  const [cmd, ...rest] = argv;
  try {
    switch (cmd) {
      case 'from-pr': return cmdFromPr(rest);
      case 'from-md': return cmdFromMd(rest);
      case 'from-text': return cmdFromText(rest);
      case 'check': return cmdCheck(rest);
      case 'help': case '-h': case '--help':
        process.stdout.write(`${USAGE}\n`);
        return 0;
      case undefined:
        process.stderr.write(`${USAGE}\n`);
        return 2;
      default:
        throw new UsageError(`unknown criteria command: ${cmd}`);
    }
  } catch (e) {
    if (e instanceof UsageError) {
      err(e.message);
      process.stderr.write(`\n${USAGE}\n`);
      return 2;
    }
    if (e instanceof EnvError) {
      err(`${e.reason}: ${e.message}`);
      return 2;
    }
    err(e && e.message ? e.message : String(e));
    return 1;
  }
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
if (isMain(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
