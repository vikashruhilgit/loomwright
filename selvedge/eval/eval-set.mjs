// eval-set.mjs — the known-answer set's tooling: split, validate, no-leak check, the held-out
// manifest, counts, and the planted-defect start-folder check. An owner-only measurement tool, not a
// selvedge CLI command; the set's layout and data model are in selvedge/eval/README.md.
//
//   node selvedge/eval/eval-set.mjs count                     validate + manifest check + answers check,
//                                                            then each count beside its floor (met | open)
//   node selvedge/eval/eval-set.mjs validate                  split.json, both cases.json, real-bugs.json
//   node selvedge/eval/eval-set.mjs check-leak                tracked files under selvedge/eval/ hold no
//                                                            held-out answer or variant (+ validate)
//   node selvedge/eval/eval-set.mjs split <cases.json>        add cases (each with its answer): sides by the
//                                                            rule, held-out answers to the outside folder
//   node selvedge/eval/eval-set.mjs side <group_id>…          the side the recorded rule gives each group
//   node selvedge/eval/eval-set.mjs manifest write|check      the outside folder vs held-out/manifest.sha256
//   node selvedge/eval/eval-set.mjs check-start-folder <dir>  the planted-defect author's start folder
//   node selvedge/eval/eval-set.mjs import-planted <out-dir>  the planted-defect session's out/ folder:
//                                                            opaque group ids, variants filed by side,
//                                                            cases added as split does
//
// Every command takes --repo <dir> (the repository top level; default: the checkout this file is in).
// The outside folder is $SELVEDGE_EVAL_HELD_OUT, default ~/.claude/selvedge-eval/held-out/.
//
// Split rule (SPLIT_RULE): a group goes to tuning when the first 8 hex of sha256(seed + ":" +
// group_id), read as an integer, mod 100 is below 40; else held-out. Per group, so adding a group
// never moves an existing one.
//
// Reason tokens, printed `eval-set: FAIL <token>: <detail>` on stderr. Each token sits on exactly
// one code line, the line that records that failure, so a test can pin it:
//   split_unreadable, defect_on_both_sides, case_on_wrong_side, case_invalid,
//   held_out_answer_committed, real_bug_entry_incomplete, no_tracked_files, manifest_empty,
//   manifest_invalid, manifest_mismatch, manifest_missing_file, manifest_extra_file,
//   held_out_answers_incomplete, start_folder_not_clean, planted_import_invalid
//
// Exit codes: 0 ok, 1 a named failure, 2 usage error or cannot run. Node >= 18, standard library
// only; criterion ids come from selvedge/lib/criteria.mjs, never a second copy.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { homedir, tmpdir } from 'node:os';
import { basename, dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { criterionId, normalizeCriterionText } from '../lib/criteria.mjs';
import { isMain } from '../lib/env-config.mjs';

export const EVAL_REL = 'selvedge/eval';
export const SPLIT_RULE = 'sha256(seed:group_id)[0:8] mod 100, below 40 -> tuning';
export const FLOORS = Object.freeze({ known_fail: 100, known_pass: 100, real_bug_fail: 30, held_out_fail: 60 });
export const SOURCES = Object.freeze(['real-bug', 'non-defect', 'planted']);
export const ANSWERS = Object.freeze(['PASS', 'FAIL']);
const MANIFEST_REL = `${EVAL_REL}/held-out/manifest.sha256`;
const START_FOLDER_FILES = Object.freeze(['app-server.mjs', 'servers.mjs']);
const SHA1_RE = /^[0-9a-f]{40}$/;
const REPO_RE = /^[\w.-]+\/[\w.-]+$/;
// A case_id is a plain token: it becomes a key of answers.json, so `__proto__`-style names are out.
const CASE_ID_RE = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
// The planted-defect session's slugs and cases.jsonl lines (selvedge/eval/planted-session-brief.md).
const PLANTED_SLUG_RE = /^pd-[a-z0-9][a-z0-9-]*$/;
const PLANTED_FIELDS = Object.freeze(['answer', 'criterion', 'group_id', 'variant']);
const DEFAULT_REPO = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..');

const USAGE = `Usage: node selvedge/eval/eval-set.mjs <command> [--repo <dir>]

Commands:
  count                     validate, manifest check, answers check, then each count beside its floor
  validate                  split.json, tuning/ and held-out/cases.json, real-bugs.json
  check-leak                no held-out answer or variant in the tracked files under ${EVAL_REL}/
  split <cases.json>        add cases (each with an answer); held-out answers go to the outside folder
  side <group_id>...        the side the recorded rule gives each group
  manifest write|check      the outside folder against ${MANIFEST_REL}
  check-start-folder <dir>  <dir> holds only copies of tests/fixtures/app-server.mjs and servers.mjs
  import-planted <out-dir>  add the planted-defect session's variants and cases (opaque group ids)

The outside folder is $SELVEDGE_EVAL_HELD_OUT (default ~/.claude/selvedge-eval/held-out/).
Exit codes: 0 ok, 1 a named failure on stderr, 2 usage error or cannot run.`;

class UsageError extends Error {}

function sha256Hex(buf) {
  return createHash('sha256').update(buf).digest('hex');
}

function isObj(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function nonEmpty(v) {
  return typeof v === 'string' && v.trim().length > 0;
}

function readJson(file) {
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch (e) {
    return { ok: false, missing: e.code === 'ENOENT', error: `${file}: ${e.code || e.message}` };
  }
  try {
    return { ok: true, value: JSON.parse(text) };
  } catch (e) {
    return { ok: false, missing: false, error: `${file}: not valid JSON (${e.message})` };
  }
}

// Write via a temp file + rename, so a crash never leaves a half-written file.
function writeAtomic(file, text) {
  mkdirSync(dirname(file), { recursive: true });
  const tmp = `${file}.tmp-${process.pid}`;
  writeFileSync(tmp, text);
  renameSync(tmp, file);
}

function jsonText(value) {
  return `${JSON.stringify(value, null, 2)}\n`;
}

export function heldOutDir(env = process.env) {
  return env.SELVEDGE_EVAL_HELD_OUT ? resolve(env.SELVEDGE_EVAL_HELD_OUT) : join(homedir(), '.claude', 'selvedge-eval', 'held-out');
}

// sideOf(seed, groupId) → 'tuning' | 'held-out' — the split rule (SPLIT_RULE).
export function sideOf(seed, groupId) {
  const v = parseInt(sha256Hex(`${seed}:${groupId}`).slice(0, 8), 16) % 100;
  return v < 40 ? 'tuning' : 'held-out';
}

// Every non-directory entry below dir, as sorted posix-relative paths ([] when dir is absent).
// Symlinks and other special entries are listed too, never skipped silently.
export function listFiles(dir) {
  const out = [];
  const walk = (abs) => {
    for (const d of readdirSync(abs, { withFileTypes: true })) {
      const p = join(abs, d.name);
      if (d.isDirectory()) walk(p);
      else out.push(relative(dir, p).split(sep).join('/'));
    }
  };
  if (existsSync(dir) && statSync(dir).isDirectory()) walk(dir);
  return out.sort();
}

function fileSha(file) {
  try {
    return sha256Hex(readFileSync(file));
  } catch {
    return null;
  }
}

function newCtx() {
  return { problems: [], leaks: new Set(), invalid: [], answerGaps: [] };
}

// The failures that several checks can find, each recorded on its one line.
function flush(ctx) {
  for (const l of ctx.leaks) ctx.problems.push(`held_out_answer_committed: ${l}`);
  for (const m of ctx.invalid) ctx.problems.push(`case_invalid: ${m}`);
  for (const g of ctx.answerGaps) ctx.problems.push(`held_out_answers_incomplete: ${g}`);
  ctx.leaks.clear();
  ctx.invalid.length = 0;
  ctx.answerGaps.length = 0;
  return ctx.problems;
}

// git ls-files under prefix; an empty list (or a git failure) fails closed.
export function trackedFiles(repo, prefix, ctx) {
  let out = '';
  try {
    out = execFileSync('git', ['-C', repo, 'ls-files', '-z', '--full-name', '--', prefix], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      maxBuffer: 64 * 1024 * 1024,
    });
  } catch {
    out = '';
  }
  const files = out.split('\0').filter(Boolean);
  if (files.length === 0) ctx.problems.push(`no_tracked_files: git ls-files -- ${prefix} returned nothing in ${repo}`);
  return files;
}

export function readSplit(repo, ctx) {
  const r = readJson(join(repo, EVAL_REL, 'split.json'));
  const ok = r.ok && isObj(r.value) && r.value.rule === SPLIT_RULE && nonEmpty(r.value.seed);
  if (!ok) ctx.problems.push(`split_unreadable: ${r.ok ? `${EVAL_REL}/split.json names no rule "${SPLIT_RULE}" and non-empty seed` : r.error}`);
  return ok ? r.value : null;
}

// A cases file is {schema_version: 1, cases: [...]}; absent reads as no cases.
function readCasesFile(file, label, ctx) {
  const r = readJson(file);
  if (!r.ok && r.missing) return [];
  if (!r.ok) {
    ctx.invalid.push(r.error);
    return [];
  }
  const cases = Array.isArray(r.value) ? r.value : isObj(r.value) ? r.value.cases : undefined;
  if (!Array.isArray(cases)) {
    ctx.invalid.push(`${label} holds no "cases" array`);
    return [];
  }
  return cases;
}

// The shape problems of one case (no side or answer-direction checks here).
export function caseShapeProblems(c) {
  if (!isObj(c)) return ['is not an object'];
  const p = [];
  if (!(typeof c.case_id === 'string' && CASE_ID_RE.test(c.case_id))) p.push('case_id ([A-Za-z0-9][A-Za-z0-9._-]*)');
  if (!nonEmpty(c.group_id)) p.push('group_id');
  if (!SOURCES.includes(c.source)) p.push(`source (one of ${SOURCES.join(', ')})`);
  const cr = c.criterion;
  if (!isObj(cr) || !nonEmpty(cr.text) || cr.text !== normalizeCriterionText(cr.text)) p.push('criterion.text (normalized, non-empty)');
  else if (cr.id !== criterionId(cr.text)) p.push('criterion.id (criterionId(criterion.text))');
  const t = c.target;
  if (!isObj(t)) p.push('target');
  else if (t.kind === 'commit') {
    if (!(typeof t.repo === 'string' && REPO_RE.test(t.repo))) p.push('target.repo (owner/name)');
    if (!(typeof t.sha === 'string' && SHA1_RE.test(t.sha))) p.push('target.sha (40 hex)');
  } else if (t.kind === 'variant') {
    if (!nonEmpty(t.path) || t.path.startsWith('/') || t.path.split('/').includes('..')) p.push('target.path (relative, no ..)');
  } else p.push('target.kind (commit | variant)');
  if ('answer' in c && !ANSWERS.includes(c.answer)) p.push('answer (PASS | FAIL)');
  return p;
}

function setupOk(s) {
  const steps = (a) => Array.isArray(a) && a.length > 0 && a.every(nonEmpty);
  return steps(s) || (isObj(s) && steps(s.parent) && steps(s.fix));
}

// The missing or malformed fields of one real-bugs.json entry.
export function realBugGaps(e) {
  if (!isObj(e)) return ['is not an object'];
  const gaps = [];
  if (!(typeof e.repo === 'string' && REPO_RE.test(e.repo))) gaps.push('repo');
  if (!(Number.isInteger(e.pr) && e.pr > 0)) gaps.push('pr');
  if (!(typeof e.parent_sha === 'string' && SHA1_RE.test(e.parent_sha))) gaps.push('parent_sha');
  if (!(typeof e.fix_sha === 'string' && SHA1_RE.test(e.fix_sha))) gaps.push('fix_sha');
  if (!setupOk(e.setup)) gaps.push('setup');
  if (e.status !== 'used' && e.status !== 'skipped') gaps.push('status (used | skipped)');
  if (e.status === 'skipped' && !nonEmpty(e.skip_reason)) gaps.push('skip_reason');
  return gaps;
}

function readRealBugs(repo) {
  const r = readJson(join(repo, EVAL_REL, 'real-bugs.json'));
  if (!r.ok && r.missing) return { entries: [], incomplete: [] };
  if (!r.ok) return { entries: [], incomplete: [r.error] };
  const entries = Array.isArray(r.value) ? r.value : isObj(r.value) ? r.value.entries : undefined;
  if (!Array.isArray(entries)) return { entries: [], incomplete: [`${EVAL_REL}/real-bugs.json holds no "entries" array`] };
  const incomplete = [];
  entries.forEach((e, i) => {
    const gaps = realBugGaps(e);
    if (gaps.length) incomplete.push(`${EVAL_REL}/real-bugs.json entry ${i}${isObj(e) && e.pr ? ` (pr ${e.pr})` : ''} lacks ${gaps.join(', ')}`);
  });
  return { entries, incomplete };
}

export function loadSet(repo, ctx) {
  const split = readSplit(repo, ctx);
  const tuning = readCasesFile(join(repo, EVAL_REL, 'tuning', 'cases.json'), `${EVAL_REL}/tuning/cases.json`, ctx);
  const heldOut = readCasesFile(join(repo, EVAL_REL, 'held-out', 'cases.json'), `${EVAL_REL}/held-out/cases.json`, ctx);
  const realBugs = readRealBugs(repo);
  return { split, tuning, heldOut, realBugs };
}

function leakMessage(file, c, group) {
  return `${file} case ${c.case_id} (held-out group ${group}) carries an answer`;
}

// The set's own rules: shapes, unique ids, one side per group, the side the rule gives, real-bug
// links and answer directions, complete real-bug entries, no answer in held-out/cases.json.
export function checkSet(set, ctx) {
  const { split, tuning, heldOut, realBugs } = set;
  const seen = new Set();
  const sides = [
    ['tuning', `${EVAL_REL}/tuning/cases.json`, tuning],
    ['held-out', `${EVAL_REL}/held-out/cases.json`, heldOut],
  ];
  // `${repo}@${sha}` → [{role: 'parent' | 'fix', group}], complete "used" entries only. One commit can
  // be one bug's fix_sha and the next bug's parent_sha (back-to-back merges), so a commit keeps every
  // link, and a case on a shared commit takes its role from its own entry (group_id, default sm-pr-<pr>).
  const used = new Map();
  const link = (key, role, group) => {
    if (!used.has(key)) used.set(key, []);
    used.get(key).push({ role, group });
  };
  for (const e of realBugs.entries) {
    if (isObj(e) && e.status === 'used' && realBugGaps(e).length === 0) {
      const group = nonEmpty(e.group_id) ? e.group_id : `sm-pr-${e.pr}`;
      link(`${e.repo}@${e.parent_sha}`, 'parent', group);
      link(`${e.repo}@${e.fix_sha}`, 'fix', group);
    }
  }
  const groupsBySide = { tuning: new Set(), 'held-out': new Set() };
  const wrong = [];
  for (const [side, label, cases] of sides) {
    cases.forEach((c, i) => {
      const shape = caseShapeProblems(c);
      if (shape.length) {
        ctx.invalid.push(`${label} case ${isObj(c) && nonEmpty(c.case_id) ? c.case_id : `#${i}`}: bad ${shape.join(', ')}`);
        return;
      }
      if (seen.has(c.case_id)) ctx.invalid.push(`${label} case ${c.case_id}: case_id appears twice in the set`);
      seen.add(c.case_id);
      groupsBySide[side].add(c.group_id);
      if (split && sideOf(split.seed, c.group_id) !== side) wrong.push(`${label} case ${c.case_id} (group ${c.group_id}) belongs on ${sideOf(split.seed, c.group_id)}`);
      if (side === 'held-out' && 'answer' in c) ctx.leaks.add(leakMessage(label, c, c.group_id));
      if (side === 'tuning' && !('answer' in c)) ctx.invalid.push(`${label} case ${c.case_id}: a tuning case needs an answer`);
      if (c.source === 'non-defect' && 'answer' in c && c.answer !== 'PASS') ctx.invalid.push(`${label} case ${c.case_id}: a non-defect case's answer is PASS`);
      if (c.source === 'real-bug') {
        const links = (c.target.kind === 'commit' && used.get(`${c.target.repo}@${c.target.sha}`)) || [];
        const own = links.find((l) => l.group === c.group_id);
        const role = own ? own.role : new Set(links.map((l) => l.role)).size === 1 ? links[0].role : undefined;
        if (links.length === 0) ctx.invalid.push(`${label} case ${c.case_id}: a real-bug case targets the parent_sha or fix_sha of a complete "used" real-bugs.json entry`);
        else if (!role) ctx.invalid.push(`${label} case ${c.case_id}: its commit is the parent_sha of one "used" real-bugs.json entry and the fix_sha of another, and neither entry's group_id (default sm-pr-<pr>) is ${c.group_id}`);
        else if ('answer' in c && c.answer !== (role === 'parent' ? 'FAIL' : 'PASS')) ctx.invalid.push(`${label} case ${c.case_id}: a real-bug case is FAIL on parent_sha, PASS on fix_sha`);
      }
    });
  }
  const both = [...groupsBySide.tuning].filter((g) => groupsBySide['held-out'].has(g)).sort();
  for (const g of both) ctx.problems.push(`defect_on_both_sides: group ${g} has cases in both tuning/cases.json and held-out/cases.json`);
  for (const w of wrong) ctx.problems.push(`case_on_wrong_side: ${w}`);
  for (const m of realBugs.incomplete) ctx.problems.push(`real_bug_entry_incomplete: ${m}`);
}

export function readManifest(repo) {
  const file = join(repo, MANIFEST_REL);
  let text = '';
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    return { entries: [], bad: [] };
  }
  const entries = [];
  const bad = [];
  const seen = new Set();
  text.split('\n').forEach((line, i) => {
    if (line === '') return;
    const m = /^([0-9a-f]{64}) {2}(.+)$/.exec(line);
    const rel = m ? m[2] : '';
    if (!m || rel.startsWith('/') || rel.split('/').includes('..') || seen.has(rel)) bad.push(`line ${i + 1}`);
    else {
      seen.add(rel);
      entries.push({ sha: m[1], rel });
    }
  });
  return { entries, bad };
}

export function manifestCheck(repo, ctx, outside = heldOutDir()) {
  const { entries, bad } = readManifest(repo);
  for (const b of bad) ctx.problems.push(`manifest_invalid: ${MANIFEST_REL} ${b} is not "<sha256>  <relative path>" (unique, relative, no ..)`);
  if (entries.length === 0) ctx.problems.push(`manifest_empty: ${MANIFEST_REL} is missing or lists no file`);
  const present = new Set(listFiles(outside));
  const listed = new Set(entries.map((e) => e.rel));
  const missing = [];
  const mismatched = [];
  for (const e of entries) {
    if (!present.has(e.rel)) missing.push(e.rel);
    else if (fileSha(join(outside, e.rel)) !== e.sha) mismatched.push(e.rel);
  }
  const extra = [...present].filter((r) => !listed.has(r));
  for (const r of mismatched) ctx.problems.push(`manifest_mismatch: ${r}`);
  for (const r of missing) ctx.problems.push(`manifest_missing_file: ${r}`);
  for (const r of extra) ctx.problems.push(`manifest_extra_file: ${r}`);
}

export function manifestWrite(repo, outside = heldOutDir()) {
  const files = listFiles(outside);
  if (files.length === 0) throw new Error(`manifest write: nothing to list under ${outside} (the outside folder is missing or empty)`);
  const lines = files.map((rel) => {
    const sha = fileSha(join(outside, rel));
    if (!sha) throw new Error(`manifest write: cannot read ${join(outside, rel)}`);
    return `${sha}  ${rel}\n`;
  });
  writeAtomic(join(repo, MANIFEST_REL), lines.join(''));
  return files.length;
}

// The held-out answers in the outside folder; gaps go to ctx.answerGaps.
export function readAnswers(heldOut, ctx, outside = heldOutDir()) {
  const r = readJson(join(outside, 'answers.json'));
  if (!r.ok) {
    ctx.answerGaps.push(r.missing ? `${join(outside, 'answers.json')} is missing` : r.error);
    return null;
  }
  if (!isObj(r.value)) {
    ctx.answerGaps.push(`${join(outside, 'answers.json')} is not a JSON object`);
    return null;
  }
  const want = new Set(heldOut.filter(isObj).map((c) => c.case_id));
  const keys = Object.keys(r.value);
  const missing = [...want].filter((k) => !Object.prototype.hasOwnProperty.call(r.value, k)).sort();
  const extra = keys.filter((k) => !want.has(k)).sort();
  const badValue = keys.filter((k) => want.has(k) && !ANSWERS.includes(r.value[k])).sort();
  if (missing.length) ctx.answerGaps.push(`answers.json lacks held-out case ids: ${missing.join(', ')}`);
  if (extra.length) ctx.answerGaps.push(`answers.json has ids that are not held-out cases: ${extra.join(', ')}`);
  if (badValue.length) ctx.answerGaps.push(`answers.json answers are not PASS | FAIL for: ${badValue.join(', ')}`);
  return r.value;
}

// The JSON values a tracked file holds, read by content, never by name: the whole file when it
// parses as JSON, else each line that parses (JSON Lines). [] when nothing parses.
function jsonValues(file) {
  let text;
  try {
    text = readFileSync(file, 'utf8');
  } catch {
    return [];
  }
  try {
    return [JSON.parse(text)];
  } catch {
    const out = [];
    for (const line of text.split('\n')) {
      const s = line.trim();
      if (!(s.startsWith('{') || s.startsWith('['))) continue;
      try {
        out.push(JSON.parse(s));
      } catch {
        // not a JSON line
      }
    }
    return out;
  }
}

// Every held-out answer inside one JSON value, at any depth: an object that carries `answer` and
// belongs to a held-out group (its group_id's side) or to a held-out case (its case_id), and an
// object whose keys are held-out case ids mapped to PASS | FAIL.
function answerLeaks(value, rel, seed, heldOutGroup, add) {
  const seen = new Set();
  const walk = (v) => {
    if (v === null || typeof v !== 'object' || seen.has(v)) return;
    seen.add(v);
    if (Array.isArray(v)) {
      for (const x of v) walk(x);
      return;
    }
    if ('answer' in v) {
      const group = nonEmpty(v.group_id) && sideOf(seed, v.group_id) === 'held-out' ? v.group_id : heldOutGroup.get(v.case_id);
      if (group !== undefined) add(leakMessage(rel, v, group));
    }
    const hit = Object.keys(v).filter((k) => heldOutGroup.has(k) && ANSWERS.includes(v[k]));
    if (hit.length) add(`${rel} maps held-out case ids to answers (${hit.sort().join(', ')})`);
    for (const k of Object.keys(v)) walk(v[k]);
  };
  walk(value);
}

// Leak checks over the tracked files under selvedge/eval/.
export function leakCheck(repo, split, heldOut, ctx, outside = heldOutDir()) {
  const tracked = trackedFiles(repo, EVAL_REL, ctx);
  if (!split) return;
  const heldOutGroup = new Map(heldOut.filter((c) => isObj(c) && typeof c.case_id === 'string').map((c) => [c.case_id, c.group_id]));
  // An outside variant file left unchanged from a start-folder base (tests/fixtures/app-server.mjs or
  // servers.mjs) is public already, and a committed tuning variant may hold the same bytes; only
  // files under variants/ get this exemption, so a copy of answers.json is always a leak.
  const baseShas = new Set(START_FOLDER_FILES.map((n) => fileSha(join(repo, 'selvedge', 'tests', 'fixtures', n))).filter(Boolean));
  const outsideHashes = new Map();
  const addOutside = (sha, rel) => {
    if (!(rel.startsWith('variants/') && baseShas.has(sha))) outsideHashes.set(sha, rel);
  };
  for (const e of readManifest(repo).entries) addOutside(e.sha, e.rel);
  for (const rel of listFiles(outside)) {
    const sha = fileSha(join(outside, rel));
    if (sha) addOutside(sha, rel);
  }
  outsideHashes.delete(sha256Hex('')); // an empty file carries no answer
  for (const rel of tracked) {
    const name = basename(rel);
    if (name === 'answers.json') ctx.leaks.add(`${rel} is named answers.json (held-out answers live only in the outside folder)`);
    const vm = /(?:^|\/)variants\/([^/]+)\//.exec(rel);
    if (vm && sideOf(split.seed, vm[1]) === 'held-out') ctx.leaks.add(`${rel} is under held-out group ${vm[1]}'s variants path`);
    if (rel === MANIFEST_REL) continue;
    const abs = join(repo, rel);
    const sha = fileSha(abs);
    if (sha && outsideHashes.has(sha)) ctx.leaks.add(`${rel} has the bytes of outside file ${outsideHashes.get(sha)}`);
    for (const v of jsonValues(abs)) answerLeaks(v, rel, split.seed, heldOutGroup, (m) => ctx.leaks.add(m));
  }
}

// split: add input cases (each with an answer) to the set, by the rule; held-out answers go to the
// outside folder. Writes nothing when any check fails.
export function splitCases(repo, inputFile, ctx, outside = heldOutDir()) {
  const set = loadSet(repo, ctx);
  if (!set.split) return null;
  const input = existsSync(resolve(inputFile)) ? readCasesFile(resolve(inputFile), inputFile, ctx) : [];
  if (!existsSync(resolve(inputFile))) ctx.invalid.push(`${inputFile} does not exist`);
  const r = readJson(join(outside, 'answers.json'));
  if (!r.ok && !r.missing) ctx.answerGaps.push(r.error);
  if (r.ok && !isObj(r.value)) ctx.answerGaps.push(`${join(outside, 'answers.json')} is not a JSON object`);
  const answers = r.ok && isObj(r.value) ? { ...r.value } : {};
  const bySide = { tuning: new Map(set.tuning.map((c) => [c.case_id, c])), 'held-out': new Map(set.heldOut.map((c) => [c.case_id, c])) };
  input.forEach((c, i) => {
    const shape = caseShapeProblems(c);
    if (!shape.length && !ANSWERS.includes(c.answer)) shape.push('answer (PASS | FAIL)');
    if (shape.length) {
      ctx.invalid.push(`${inputFile} case ${isObj(c) && nonEmpty(c.case_id) ? c.case_id : `#${i}`}: bad ${shape.join(', ')}`);
      return;
    }
    const side = sideOf(set.split.seed, c.group_id);
    bySide.tuning.delete(c.case_id);
    bySide['held-out'].delete(c.case_id);
    if (side === 'tuning') {
      bySide.tuning.set(c.case_id, c);
    } else {
      const { answer, ...rest } = c;
      bySide['held-out'].set(c.case_id, rest);
      answers[c.case_id] = answer;
    }
  });
  const byId = (a, b) => (a.case_id < b.case_id ? -1 : a.case_id > b.case_id ? 1 : 0);
  const next = { ...set, tuning: [...bySide.tuning.values()].sort(byId), heldOut: [...bySide['held-out'].values()].sort(byId) };
  checkSet(next, ctx);
  const ids = new Set(next.heldOut.map((c) => c.case_id));
  for (const k of Object.keys(answers)) if (!ids.has(k)) delete answers[k];
  if (flush(ctx).length) return null;
  writeAtomic(join(repo, EVAL_REL, 'tuning', 'cases.json'), jsonText({ schema_version: 1, cases: next.tuning }));
  writeAtomic(join(repo, EVAL_REL, 'held-out', 'cases.json'), jsonText({ schema_version: 1, cases: next.heldOut }));
  const sorted = Object.fromEntries(Object.keys(answers).sort().map((k) => [k, answers[k]]));
  writeAtomic(join(outside, 'answers.json'), jsonText(sorted));
  return { tuning: next.tuning.length, heldOut: next.heldOut.length };
}

// plantedGroupId(slug) — the group id a planted slug gets in the set. The slug describes the bug,
// so in held-out/cases.json beside the criteria it would give the answers away; only this hash goes
// in, and the slug-to-id list stays in the session's own folder (imported-ids.tsv).
export function plantedGroupId(slug) {
  return `pd-${sha256Hex(`planted:${slug}`).slice(0, 10)}`;
}

// importPlanted: read <out>/cases.jsonl and <out>/pd-<slug>/ (the planted-defect session's output),
// give each slug its opaque group id, add the cases through splitCases (so every split rule applies
// and a refusal writes nothing), then copy each variant to its side: committed under
// tuning/variants/<id>/, or to the outside folder's variants/<id>/. Prints counts only.
export function importPlanted(repo, outDir, ctx, outside = heldOutDir()) {
  const bad = (m) => ctx.problems.push(`planted_import_invalid: ${m}`);
  const split = readSplit(repo, ctx);
  if (!split) return null;
  const out = resolve(outDir);
  const jsonl = join(out, 'cases.jsonl');
  if (!existsSync(jsonl)) {
    bad(`${jsonl} does not exist`);
    return null;
  }
  const bySlug = new Map();
  readFileSync(jsonl, 'utf8').split('\n').forEach((line, i) => {
    if (!line.trim()) return;
    const at = `cases.jsonl line ${i + 1}`;
    let c;
    try {
      c = JSON.parse(line);
    } catch {
      return bad(`${at} is not JSON`);
    }
    if (!isObj(c) || Object.keys(c).sort().join(',') !== PLANTED_FIELDS.join(',')) return bad(`${at} needs exactly the fields ${PLANTED_FIELDS.join(', ')}`);
    if (!(typeof c.group_id === 'string' && PLANTED_SLUG_RE.test(c.group_id))) return bad(`${at}: group_id is not pd-<slug> (lowercase letters, digits, -)`);
    if (c.variant !== c.group_id) return bad(`${at}: variant is not its group_id`);
    if (!ANSWERS.includes(c.answer)) return bad(`${at}: answer is not PASS or FAIL`);
    const text = nonEmpty(c.criterion) ? normalizeCriterionText(c.criterion) : '';
    if (!text) return bad(`${at}: criterion is empty`);
    if (!bySlug.has(c.group_id)) bySlug.set(c.group_id, []);
    const list = bySlug.get(c.group_id);
    if (list.some((x) => x.text === text)) return bad(`${at}: ${c.group_id} already has this criterion`);
    list.push({ text, answer: c.answer });
  });
  const folders = readdirSync(out, { withFileTypes: true }).filter((d) => d.name.startsWith('pd-')).map((d) => d.name).sort();
  for (const f of folders) if (!bySlug.has(f)) bad(`variant folder ${f} has no case in cases.jsonl`);
  const ids = new Map();
  const plans = [];
  for (const [slug, list] of [...bySlug].sort((a, b) => (a[0] < b[0] ? -1 : 1))) {
    if (!list.some((x) => x.answer === 'FAIL')) bad(`${slug} has no FAIL criterion, so it plants nothing`);
    const src = join(out, slug);
    if (!(existsSync(src) && lstatSync(src).isDirectory())) {
      bad(`${slug} has cases but no variant folder ${slug}/`);
      continue;
    }
    const files = listFiles(src);
    if (!files.includes('app-server.mjs')) bad(`${slug}/ has no app-server.mjs`);
    for (const f of files) if (!lstatSync(join(src, f)).isFile()) bad(`${slug}/${f} is not a regular file`);
    const id = plantedGroupId(slug);
    if (ids.has(id)) bad(`${slug} and ${ids.get(id)} hash to the same group id ${id}`);
    ids.set(id, slug);
    const side = sideOf(split.seed, id);
    const dest = side === 'tuning' ? join(repo, EVAL_REL, 'tuning', 'variants', id) : join(outside, 'variants', id);
    const there = listFiles(dest);
    if (there.length && (there.join('\n') !== files.join('\n') || files.some((f) => fileSha(join(src, f)) !== fileSha(join(dest, f))))) {
      bad(`${slug}: ${dest} already holds a different variant`);
    }
    plans.push({ slug, id, side, src, dest, files, list });
  }
  if (flush(ctx).length) return null;
  const cases = plans.flatMap((p) =>
    p.list.map((x) => {
      const cid = criterionId(x.text);
      return { case_id: `${p.id}.${cid.slice(2)}`, group_id: p.id, source: 'planted', criterion: { id: cid, text: x.text }, target: { kind: 'variant', path: `variants/${p.id}` }, answer: x.answer };
    }),
  );
  const tmp = mkdtempSync(join(tmpdir(), 'selvedge-import-planted-'));
  let r;
  try {
    writeFileSync(join(tmp, 'cases.json'), jsonText({ schema_version: 1, cases }));
    r = splitCases(repo, join(tmp, 'cases.json'), ctx, outside);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
  if (!r) return null;
  for (const p of plans) {
    for (const f of p.files) {
      mkdirSync(dirname(join(p.dest, f)), { recursive: true });
      copyFileSync(join(p.src, f), join(p.dest, f));
    }
  }
  writeAtomic(join(out, 'imported-ids.tsv'), plans.map((p) => `${p.slug}\t${p.id}\t${p.side}\n`).join(''));
  const n = (side, what) => plans.filter((p) => p.side === side).reduce((a, p) => a + (what === 'groups' ? 1 : p.list.length), 0);
  return { groups: { tuning: n('tuning', 'groups'), heldOut: n('held-out', 'groups') }, cases: { tuning: n('tuning', 'cases'), heldOut: n('held-out', 'cases') }, ids: join(out, 'imported-ids.tsv') };
}

export function checkStartFolder(repo, dir, ctx) {
  const tracked = trackedFiles(repo, 'selvedge', ctx);
  const fixtures = new Map(START_FOLDER_FILES.map((n) => [n, `selvedge/tests/fixtures/${n}`]));
  const allowed = new Map();
  for (const [n, rel] of fixtures) {
    const sha = fileSha(join(repo, rel));
    if (!sha) throw new Error(`cannot read ${join(repo, rel)}`);
    allowed.set(n, sha);
  }
  const fixtureRels = new Set(fixtures.values());
  const twins = new Map();
  for (const rel of tracked) {
    if (fixtureRels.has(rel)) continue;
    const sha = fileSha(join(repo, rel));
    if (sha && !twins.has(sha)) twins.set(sha, rel);
  }
  const unclean = [];
  const target = resolve(dir);
  if (!(existsSync(target) && statSync(target).isDirectory())) unclean.push(`${dir} is not a directory`);
  else {
    const files = listFiles(target);
    for (const rel of files) {
      const sha = fileSha(join(target, rel));
      if (allowed.has(rel) && allowed.get(rel) === sha) continue;
      const twin = sha ? twins.get(sha) : undefined;
      unclean.push(twin ? `${rel} (a copy of ${twin})` : `${rel} (not a copy of ${[...fixtureRels].join(' or ')})`);
    }
    for (const n of START_FOLDER_FILES) if (!files.includes(n)) unclean.push(`${n} is missing (copy ${fixtures.get(n)})`);
  }
  for (const u of unclean) ctx.problems.push(`start_folder_not_clean: ${u}`);
}

function countLines(set, answers) {
  const all = [
    ...set.tuning.map((c) => ({ c, side: 'tuning', answer: c.answer })),
    ...set.heldOut.map((c) => ({ c, side: 'held-out', answer: answers[c.case_id] })),
  ];
  const n = (pred) => all.filter(pred).length;
  const groups = new Set(all.map((x) => x.c.group_id)).size;
  const rows = [
    ['known-FAIL', n((x) => x.answer === 'FAIL'), FLOORS.known_fail],
    ['known-PASS', n((x) => x.answer === 'PASS'), FLOORS.known_pass],
    ['real-bug known-FAIL', n((x) => x.answer === 'FAIL' && x.c.source === 'real-bug'), FLOORS.real_bug_fail],
    ['held-out known-FAIL', n((x) => x.answer === 'FAIL' && x.side === 'held-out'), FLOORS.held_out_fail],
  ];
  const out = [`cases: ${all.length} (tuning ${set.tuning.length}, held-out ${set.heldOut.length}) in ${groups} group(s)`];
  for (const [label, count, floor] of rows) out.push(`${label.padEnd(20)} ${String(count).padStart(5)}   floor ${String(floor).padStart(3)}   ${count >= floor ? 'met' : 'open'}`);
  return out;
}

function parseArgs(argv) {
  const positional = [];
  let repo = DEFAULT_REPO;
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--repo') {
      if (i + 1 >= argv.length) throw new UsageError('--repo needs a directory');
      repo = resolve(argv[++i]);
    } else if (a.startsWith('--repo=')) repo = resolve(a.slice('--repo='.length));
    else if (a === '-h' || a === '--help') positional.unshift('help');
    else if (a.startsWith('-')) throw new UsageError(`unknown flag ${a}`);
    else positional.push(a);
  }
  return { repo, positional };
}

function finish(ctx, okLine) {
  const problems = flush(ctx);
  if (problems.length) {
    for (const p of problems) process.stderr.write(`eval-set: FAIL ${p}\n`);
    return 1;
  }
  if (okLine) process.stdout.write(`${okLine}\n`);
  return 0;
}

export function main(argv) {
  const { repo, positional } = parseArgs(argv);
  const [cmd, ...rest] = positional;
  const ctx = newCtx();
  const need = (n, what) => {
    if (rest.length !== n) throw new UsageError(`${cmd} takes ${what}`);
  };
  switch (cmd) {
    case undefined:
    case 'help':
      process.stdout.write(`${USAGE}\n`);
      return cmd ? 0 : 2;
    case 'validate': {
      need(0, 'no arguments');
      const set = loadSet(repo, ctx);
      checkSet(set, ctx);
      return finish(ctx, `eval-set: OK — set valid (tuning ${set.tuning.length}, held-out ${set.heldOut.length} case(s))`);
    }
    case 'check-leak': {
      need(0, 'no arguments');
      const set = loadSet(repo, ctx);
      leakCheck(repo, set.split, set.heldOut, ctx);
      checkSet(set, ctx);
      return finish(ctx, `eval-set: OK — no held-out answer or variant in the tracked files under ${EVAL_REL}/`);
    }
    case 'split': {
      need(1, 'one <cases.json>');
      const r = splitCases(repo, rest[0], ctx);
      if (!r) return finish(ctx);
      process.stdout.write(`eval-set: OK — tuning ${r.tuning}, held-out ${r.heldOut} case(s); held-out answers in ${join(heldOutDir(), 'answers.json')}\n`);
      process.stdout.write('next: node selvedge/eval/eval-set.mjs manifest write, then check-leak and count\n');
      return 0;
    }
    case 'side': {
      if (rest.length === 0) throw new UsageError('side takes one or more <group_id>');
      const split = readSplit(repo, ctx);
      if (!split) return finish(ctx);
      for (const g of rest) process.stdout.write(`${g}\t${sideOf(split.seed, g)}\n`);
      return 0;
    }
    case 'manifest': {
      if (rest.length !== 1 || !['write', 'check'].includes(rest[0])) throw new UsageError('manifest takes write | check');
      if (rest[0] === 'write') {
        const n = manifestWrite(repo);
        process.stdout.write(`eval-set: OK — wrote ${MANIFEST_REL} (${n} file(s) under ${heldOutDir()})\n`);
        return 0;
      }
      manifestCheck(repo, ctx);
      return finish(ctx, `eval-set: OK — ${heldOutDir()} matches ${MANIFEST_REL}`);
    }
    case 'check-start-folder': {
      need(1, 'one <dir>');
      checkStartFolder(repo, rest[0], ctx);
      return finish(ctx, `eval-set: OK — ${rest[0]} holds only copies of tests/fixtures/${START_FOLDER_FILES.join(' and ')}`);
    }
    case 'import-planted': {
      need(1, 'one <out-dir>');
      const r = importPlanted(repo, rest[0], ctx);
      if (!r) return finish(ctx);
      process.stdout.write(`eval-set: OK — planted groups: tuning ${r.groups.tuning} (${r.cases.tuning} case(s)), held-out ${r.groups.heldOut} (${r.cases.heldOut} case(s)); slug-to-id list in ${r.ids}\n`);
      process.stdout.write(`next: node selvedge/eval/eval-set.mjs manifest write, then check-leak and count; commit ${EVAL_REL}/tuning/, ${EVAL_REL}/held-out/cases.json and the manifest\n`);
      return 0;
    }
    case 'count': {
      need(0, 'no arguments');
      const set = loadSet(repo, ctx);
      checkSet(set, ctx);
      manifestCheck(repo, ctx);
      const answers = set.split ? readAnswers(set.heldOut, ctx) : null;
      if (flush(ctx).length || !answers) return finish(ctx);
      process.stdout.write(`${countLines(set, answers).join('\n')}\n`);
      return 0;
    }
    default:
      throw new UsageError(`unknown command ${cmd}`);
  }
}

if (isMain(import.meta.url)) {
  let code;
  try {
    code = main(process.argv.slice(2));
  } catch (e) {
    if (e instanceof UsageError) {
      process.stderr.write(`eval-set: ${e.message}\n\n${USAGE}\n`);
    } else {
      process.stderr.write(`eval-set: CANNOT RUN — ${e.message}\n`);
    }
    code = 2;
  }
  process.exitCode = code;
}
