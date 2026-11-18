// comment.mjs — `selvedge comment <run-dir> --pr <n>`, run by selvedge/bin/selvedge.
//
//   selvedge comment <run-dir> --pr <n> [--yes] [--base <ref>] [--allow-public-values]
//
// Posts a run folder's verdicts to a PR as ONE comment, created once and updated in place: the
// comment is the first on the PR whose body holds COMMENT_MARKER (comment-render.mjs). The body is
// built by renderComment from the run folder's verdict.json, plan.json and criteria.json, plus each
// earlier plan revision's own verdict per criterion (read here: runs.jsonl and the earlier run folders).
//
// In order: parse the flags; refuse without --yes when stdin is not a terminal (comment_requires_yes);
// read the run folder (no verdict.json → verdict_missing; a plan.json whose sha256 is not verdict.json's
// plan_sha256 → plan_modified); resolve the base ref (--base, else `origin/<baseRefName>` from
// `gh pr view <n> --json baseRefName`); read `comment` from `<base>:selvedge.json` (loadConfig with
// base: the working tree's selvedge.json is never read, so a PR branch cannot opt itself in to
// publishing values; an unreadable base config leaves the defaults, values unpublished); when
// `comment.read_values` is true, `gh repo view --json visibility` must say PRIVATE, else
// read_values_public_repo unless --allow-public-values (an unreadable answer is not PRIVATE: fail
// closed); render; confirm (--yes, else one y/N line on the terminal); then find / update / create
// through `gh`. The body always travels to `gh` as a file (`-F body=@<file>`, `--body-file <file>`)
// in an argument array, never in argv text or a shell string.
//
// stdout: the comment URL `gh` returns, never the body. Exit codes: 0 posted (or declined at the
// prompt), 1 `gh` failed, 2 a usage error or a refusal (the reason on stderr). Every reason comes
// from REASONS in env-config.mjs.
//
// Node >= 18, standard library only.
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { EnvError, REASONS, UsageError, isMain, loadConfig, parseCliArgs, readOneLine, repoRoot } from './env-config.mjs';
import { RUN_FILES, RUN_ID_PATTERN, readRunsLog, runsRoot } from './plan-runs.mjs';
import { RUN_EVENT, VERDICTS, VERDICT_FILE } from './verdict.mjs';
import { COMMENT_MARKER, renderComment } from './comment-render.mjs';

// The one repo visibility that lets read values be published without --allow-public-values.
export const VISIBILITY_PRIVATE = 'PRIVATE';

const USAGE = `Usage: selvedge comment <run-dir> --pr <n> [--yes] [--base <ref>] [--allow-public-values]

Post the run folder's verdicts to PR <n> as ONE comment (found again by the hidden marker
${COMMENT_MARKER}, updated in place). Text only: criterion, interpretation, assumptions, steps
(type + locator; a goto shows its path), expected value, matched, verdict and its revisions, evidence
class, reason and hint. No URL origin or query string, no fill value, no screenshot or trace, and no
value the run read unless the base branch's selvedge.json sets "comment": {"read_values": true}.

  --yes                    post without asking (required when stdin is not a terminal)
  --base <ref>             read "comment" from <ref>:selvedge.json (default origin/<the PR's base>)
  --allow-public-values    with read_values on, post them on a repo that is not private

stdout: the comment URL. Exit codes: 0 posted (or declined), 1 gh failed, 2 usage error or refusal
(comment_requires_yes, verdict_missing, plan_modified, read_values_public_repo, …).`;

// A failed `gh` call (exit 1).
export class GhError extends Error {}

const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

function err(line) {
  process.stderr.write(`selvedge comment: ${line}\n`);
}

function gh(args, what) {
  try {
    return execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: 64 * 1024 * 1024 });
  } catch (e) {
    const why = e && e.code === 'ENOENT' ? 'gh is not on PATH' : (e && e.stderr ? String(e.stderr).trim().split('\n')[0] : e && e.message);
    throw new GhError(`gh ${what} failed: ${why}`);
  }
}

// A file's JSON. Only a parse failure becomes onBad(<why>); a file that cannot be read throws as is
// (each caller checks presence first and names its own reason).
function readJson(file, onBad) {
  const text = readFileSync(file, 'utf8');
  try {
    return JSON.parse(text);
  } catch (e) {
    throw onBad(e && e.message);
  }
}

// readRunFolder(runDir) → { verdict, plan, criteria, planSha256 }. Throws EnvError verdict_missing
// (no usable verdict.json), not_frozen (no plan.json), plan_modified (plan.json's sha256 is not
// verdict.json's plan_sha256), plan_invalid, criteria_not_found / criteria_invalid.
export function readRunFolder(runDir) {
  const verdictFile = path.join(runDir, VERDICT_FILE);
  if (!existsSync(verdictFile)) throw new EnvError(REASONS.verdict_missing, `no ${VERDICT_FILE} in ${runDir}; run \`selvedge verdict ${runDir}\` first`);
  const verdict = readJson(verdictFile, (why) => new EnvError(REASONS.verdict_missing, `${verdictFile} is not valid JSON: ${why}`));
  if (!isPlainObject(verdict) || !isPlainObject(verdict.criteria)) {
    throw new EnvError(REASONS.verdict_missing, `${verdictFile} is not a verdict (no criteria object)`);
  }
  const planFile = path.join(runDir, RUN_FILES.plan);
  let planBytes;
  try {
    planBytes = readFileSync(planFile);
  } catch (e) {
    if (e && e.code === 'ENOENT') throw new EnvError(REASONS.not_frozen, `no ${RUN_FILES.plan} in ${runDir}`);
    throw e;
  }
  const planSha256 = createHash('sha256').update(planBytes).digest('hex');
  if (planSha256 !== verdict.plan_sha256) throw new EnvError(REASONS.plan_modified, `${planFile} has sha256 ${planSha256}, but ${VERDICT_FILE} was derived from ${verdict.plan_sha256}; nothing is posted for a plan that did not run`);
  let plan;
  try {
    plan = JSON.parse(planBytes.toString('utf8'));
  } catch (e) {
    throw new EnvError(REASONS.plan_invalid, `${planFile} is not valid JSON: ${e && e.message}`);
  }
  if (!isPlainObject(plan)) throw new EnvError(REASONS.plan_invalid, `${planFile} is not a plan object`);
  const criteriaFile = path.join(runDir, RUN_FILES.criteria);
  if (!existsSync(criteriaFile)) throw new EnvError(REASONS.criteria_not_found, `no ${RUN_FILES.criteria} in ${runDir}`);
  const doc = readJson(criteriaFile, (why) => new EnvError(REASONS.criteria_invalid, `${criteriaFile} is not valid JSON: ${why}`));
  if (!isPlainObject(doc) || !Array.isArray(doc.criteria)) throw new EnvError(REASONS.criteria_invalid, `${criteriaFile} has no criteria list`);
  return { verdict, plan, criteria: doc.criteria, planSha256 };
}

// An earlier run folder's verdict.json under <root>/.selvedge/runs/<run_id>/, or null when the id is
// not a run id or the file is absent / unreadable.
function readEarlierVerdict(root, runId) {
  if (typeof runId !== 'string' || !new RegExp(RUN_ID_PATTERN).test(runId)) return null;
  try {
    const v = JSON.parse(readFileSync(path.join(runsRoot(root), runId, VERDICT_FILE), 'utf8'));
    return isPlainObject(v) && isPlainObject(v.criteria) ? v : null;
  } catch {
    return null;
  }
}

// criterionHistory(root, run) → { <criterion id>: [{ revision, verdict, scope }] } for every entry of
// verdict.json's prior_revisions that ran: the revision's own run line in <root>/.selvedge/runs.jsonl
// (event "run", the same criteria_sha256 and plan_revision, replay_of null — the match priorRevisions
// in verdict.mjs uses), then that run folder's verdict.json `criteria[<id>].verdict` (scope
// "criterion"); when the folder, its verdict.json or the criterion's entry is missing, the revision's
// run-level verdict (scope "run"). A revision that never ran (verdict null) has no entry.
export function criterionHistory(root, { verdict, plan }) {
  const history = {};
  const prior = Array.isArray(verdict.prior_revisions) ? verdict.prior_revisions.filter(isPlainObject) : [];
  if (!root || prior.length === 0) return history;
  const { entries } = readRunsLog(root);
  const criteriaSha256 = isPlainObject(plan) ? plan.criteria_sha256 : undefined;
  for (const pr of prior) {
    if (pr.verdict === null) continue;
    const line = entries.find((e) => e.event === RUN_EVENT && e.criteria_sha256 === criteriaSha256 && e.plan_revision === pr.revision && e.replay_of === null);
    const earlier = line ? readEarlierVerdict(root, line.run_id) : null;
    for (const id of Object.keys(verdict.criteria)) {
      const entry = earlier && isPlainObject(earlier.criteria[id]) ? earlier.criteria[id] : null;
      const own = entry && Object.values(VERDICTS).includes(entry.verdict) ? entry.verdict : null;
      if (!history[id]) history[id] = [];
      history[id].push(own ? { revision: pr.revision, verdict: own, scope: 'criterion' } : { revision: pr.revision, verdict: pr.verdict, scope: 'run' });
    }
  }
  return history;
}

// The base ref the opt-in is read from: `origin/<baseRefName>` of the PR.
function prBaseRef(pr) {
  const out = gh(['pr', 'view', pr, '--json', 'baseRefName'], `pr view ${pr} --json baseRefName`);
  let name;
  try {
    name = JSON.parse(out).baseRefName;
  } catch {
    name = null;
  }
  if (typeof name !== 'string' || name === '' || name.startsWith('-')) throw new GhError(`gh pr view ${pr} returned no usable baseRefName`);
  return `origin/${name}`;
}

// The `comment` block of <base>:selvedge.json. An unreadable base config (no file on that ref, an
// unknown ref) keeps the defaults: read values stay unpublished.
function commentConfig({ cwd, base }) {
  try {
    return loadConfig({ cwd, base }).config.comment;
  } catch (e) {
    if (e instanceof EnvError && e.reason === REASONS.base_config_unreadable) {
      err(`${e.message}; using the defaults (read values are not published)`);
      return { read_values: false, redact: [] };
    }
    throw e;
  }
}

// The repo's visibility (PUBLIC, PRIVATE, INTERNAL), or null when gh cannot say.
function repoVisibility() {
  try {
    const v = JSON.parse(gh(['repo', 'view', '--json', 'visibility'], 'repo view --json visibility')).visibility;
    return typeof v === 'string' ? v.toUpperCase() : null;
  } catch {
    return null;
  }
}

// The id of the first comment on the PR whose body holds the marker, or null.
function findCommentId(pr) {
  const out = gh(['api', '--paginate', '--slurp', `repos/{owner}/{repo}/issues/${pr}/comments`], `api issues/${pr}/comments`);
  let pages;
  try {
    pages = JSON.parse(out);
  } catch (e) {
    throw new GhError(`gh api issues/${pr}/comments returned no JSON: ${e && e.message}`);
  }
  const comments = Array.isArray(pages) ? pages.flat() : [];
  for (const c of comments) {
    if (isPlainObject(c) && typeof c.body === 'string' && c.body.includes(COMMENT_MARKER)) return String(c.id);
  }
  return null;
}

// Updates the marker comment, or creates it. → { action, url }.
function postComment(pr, body) {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'selvedge-comment-'));
  const file = path.join(dir, 'body.md');
  try {
    writeFileSync(file, body, { mode: 0o600 });
    const id = findCommentId(pr);
    if (id !== null) {
      if (!/^[0-9]+$/.test(id)) throw new GhError(`the marker comment has no usable id (${JSON.stringify(id)})`);
      const out = gh(['api', '-X', 'PATCH', `repos/{owner}/{repo}/issues/comments/${id}`, '-F', `body=@${file}`], `api -X PATCH issues/comments/${id}`);
      let url = null;
      try {
        url = JSON.parse(out).html_url;
      } catch {
        url = null;
      }
      return { action: 'updated', url: typeof url === 'string' ? url : `comment ${id}` };
    }
    const out = gh(['pr', 'comment', pr, '--body-file', file], `pr comment ${pr}`);
    return { action: 'created', url: out.trim() };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

// runComment(argv, { interactive, readLine }) → exit code. `interactive` (stdin is a terminal by
// default) and `readLine` (one line from stdin, readOneLine) are injectable for the confirmation.
export async function runComment(argv, { interactive = Boolean(process.stdin.isTTY), readLine = readOneLine, cwd = process.cwd() } = {}) {
  const { flags, positional } = parseCliArgs(argv, { values: ['pr', 'base'], booleans: ['yes', 'allow-public-values'] });
  if (positional.length !== 1) throw new UsageError(positional.length === 0 ? 'a <run-dir> is required' : `one <run-dir> only (got ${positional.length})`);
  if (typeof flags.pr !== 'string' || !/^[0-9]+$/.test(flags.pr)) throw new UsageError('--pr <number> is required');
  const runDir = positional[0];
  let isDir = false;
  try {
    isDir = statSync(runDir).isDirectory();
  } catch {
    isDir = false;
  }
  if (!isDir) throw new UsageError(`${runDir} is not a directory`);
  if (!flags.yes && !interactive) throw new EnvError(REASONS.comment_requires_yes, 'posting a PR comment needs --yes when stdin is not a terminal; nothing was posted');

  const run = readRunFolder(runDir);
  const base = flags.base !== undefined ? flags.base : prBaseRef(flags.pr);
  const config = commentConfig({ cwd, base });
  let readValues = false;
  if (config.read_values) {
    const visibility = repoVisibility();
    if (visibility !== VISIBILITY_PRIVATE && !flags['allow-public-values']) throw new EnvError(REASONS.read_values_public_repo, `"comment.read_values" is on in ${base}:selvedge.json, but the repo is ${visibility || 'of unknown visibility'}, not ${VISIBILITY_PRIVATE}; pass --allow-public-values to publish redacted values anyway. Nothing was posted`);
    readValues = true;
  }
  const body = renderComment({ ...run, history: criterionHistory(repoRoot(runDir), run), readValues, redact: config.redact });

  if (!flags.yes) {
    process.stderr.write(`selvedge comment: post the selvedge verdict for ${Object.keys(run.verdict.criteria).length} criteria to PR #${flags.pr}${readValues ? ' (with redacted read values)' : ''}? [y/N] `);
    const answer = await readLine();
    if (typeof answer !== 'string' || answer.trim() !== 'y') return (err('not posted'), 0);
  }
  const { action, url } = postComment(flags.pr, body);
  err(`${action} the selvedge comment on PR #${flags.pr}`);
  process.stdout.write(`${url}\n`);
  return 0;
}

async function main(argv) {
  const major = Number(String(process.versions.node).split('.')[0]);
  if (!(major >= 18)) {
    err(`needs Node.js >= 18 (this is ${process.versions.node})`);
    return 1;
  }
  try {
    if (argv.length === 0) {
      process.stderr.write(`${USAGE}\n`);
      return 2;
    }
    if (['help', '-h', '--help'].includes(argv[0])) {
      process.stdout.write(`${USAGE}\n`);
      return 0;
    }
    return await runComment(argv);
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
    if (e instanceof GhError) {
      err(e.message);
      return 1;
    }
    err(e && e.message ? e.message : String(e));
    return 1;
  }
}

// exitCode, not process.exit(): exiting at once can drop stdout still queued for a pipe.
if (isMain(import.meta.url)) process.exitCode = await main(process.argv.slice(2));
