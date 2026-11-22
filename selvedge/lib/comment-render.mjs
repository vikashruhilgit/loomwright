// comment-render.mjs — the body of the ONE selvedge PR comment, and the read-value redaction.
//
// Pure: no file, network or environment access, no `gh`. selvedge/lib/comment.mjs reads the run folder
// and hands renderComment plain values; renderComment returns the body string.
//
// The body starts with COMMENT_MARKER (how `selvedge comment` finds its own comment again), then one
// summary line (`<n> PASS · <n> PASS after revision · <n> FAIL · …`, zero counts omitted), then one
// <details> block per criterion: the criterion text, the verdict cell (with the per-criterion revision
// history), interpretation, unverified assumptions (material ones marked), the plan's steps as type +
// locator only, the expected value (op + value from the plan), matched yes/no, evidence class, the
// reason and its unblock hint (BLOCKED / NOT_VERIFIABLE) with, for a criterion the plan lists under
// not_planned, the planner's detail and rewrite (redacted), the read value only when the caller says it
// may be shown (always after redaction), and the short plan sha256 + revision.
//
// What the body never carries: an http:// or https:// URL (a goto shows its URL's path only, and every
// free-text field has each URL rewritten to its path, so no origin and no query string), the header
// names Cookie / Set-Cookie / Authorization, a fill or select value, a resolved {{NAME}} value (the
// renderer never reads the environment), and anything from evidence.jsonl, screenshots or traces (it
// is never given them).
//
// Node >= 18, standard library only.
import { REASONS } from './env-config.mjs';
import { VERDICTS, countVerdicts } from './verdict.mjs';

export const COMMENT_MARKER = '<!-- selvedge:verdict -->';
export const REDACTED = '[redacted]';
export const PASS_AFTER_REVISION = 'PASS after revision';
export const SHORT_SHA_LENGTH = 12;

// The default redaction patterns (JavaScript regular-expression sources), applied to every read value
// before the configured `comment.redact` patterns. Each match becomes REDACTED.
export const DEFAULT_REDACT_PATTERNS = Object.freeze([
  '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}', // an email address
  '\\?[^\\s#]*=[^\\s#]*', // a URL query string (from `?`, holding at least one `=`)
  '[A-Za-z0-9+/_-]{32,}={0,2}', // a base64 / hex token of 32+ characters
  '\\d{6,}', // a run of 6+ digits
]);

// One unblock hint per BLOCKED / NOT_VERIFIABLE reason, keyed by REASONS values.
export const UNBLOCK_HINTS = Object.freeze({
  [REASONS.host_not_allowed]: 'list the origin in selvedge.json `origins`, or fix the plan step that left it',
  [REASONS.remote_resolves_private]: 'test that app on a local origin instead',
  [REASONS.remote_mutation_refused]: 'test on a local origin, or set `allow_remote_mutation` on purpose',
  [REASONS.proxy_loopback_disabled]: 'unset PLAYWRIGHT_DISABLE_FORCED_CHROMIUM_PROXIED_LOOPBACK and run again',
  [REASONS.proxy_unavailable]: 'run again (`selvedge run --replay <run-dir>`)',
  [REASONS.env_hooks_unapproved]: 'run `selvedge env approve`',
  [REASONS.env_hooks_remote_origin]: 'run the hooks only while every origin is local',
  [REASONS.playwright_unavailable]: 'install playwright in the repo, or set SELVEDGE_PLAYWRIGHT_MODULE',
  [REASONS.placeholder_unset]: 'set the named variable in the environment and run again',
  [REASONS.step_failed]: 'check the locator of the failed step, then plan again',
  [REASONS.stuck_screen]: 'plan again with steps that change the page',
  [REASONS.budget_exceeded]: 'raise SELVEDGE_RUN_BUDGET_MS (or the planner token budget) and run again',
  [REASONS.run_interrupted]: 'run again (`selvedge run --replay <run-dir>`)',
  [REASONS.needs_auth]: 'run `selvedge auth setup`',
  [REASONS.criterion_not_testable]: 'rewrite the criterion with a value a check can read',
  [REASONS.side_effect_not_observable]: 'name a side effect a check can read before and after the action',
  [REASONS.exploration_budget]: 'raise SELVEDGE_SNAPSHOT_BUDGET and plan again',
  [REASONS.no_value_read]: 'check what the read step targets, then plan again',
  [REASONS.material_assumption]: 'confirm the assumption, then plan again without it',
});

const URL_RE = /\bhttps?:\/\/[^\s<>"'`)\]]+/gi;
const SCHEME_RE = /https?:\/\//gi;
const HEADER_NAME_RE = /set-cookie|cookie|authorization/gi;

const isPlainObject = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

// Every http(s) URL in `text` replaced by its path (no origin, no query string, no fragment). A bare
// scheme the URL pattern cannot take (`http://` at the end, or before a quote) is dropped.
export function urlsToPaths(text) {
  return String(text)
    .replace(URL_RE, (m) => {
      try {
        return new URL(m).pathname;
      } catch {
        return '/';
      }
    })
    .replace(SCHEME_RE, '');
}

function escapeHtml(text) {
  return String(text).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// The header names Cookie / Set-Cookie / Authorization, in any case, become REDACTED.
function scrubHeaderNames(text) {
  return String(text).replace(HEADER_NAME_RE, REDACTED);
}

// Free text from the criteria or the plan, made safe for the body: one line, each URL as its path,
// no header name, HTML-escaped.
function freeText(value) {
  let t = String(value).replace(/\s*[\r\n]+\s*/g, ' ');
  t = urlsToPaths(t);
  return escapeHtml(scrubHeaderNames(t));
}

// redactValue(value, patterns) → the value as a string with every match of every pattern (the
// defaults first, then `patterns`) replaced by REDACTED. `patterns` are RegExp sources or RegExps;
// null / undefined is returned unchanged.
export function redactValue(value, patterns = []) {
  if (value === null || value === undefined) return value;
  let out = String(value);
  for (const p of [...DEFAULT_REDACT_PATTERNS, ...patterns]) {
    const source = p instanceof RegExp ? p.source : String(p);
    out = out.replace(new RegExp(source, 'g'), REDACTED);
  }
  return out;
}

// A plan-step locator as `role "button" name "Save"` / `label "Email"` / `text "…"` / `testid "…"`.
function locatorText(loc) {
  if (!isPlainObject(loc)) return '';
  const parts = [];
  for (const key of ['role', 'name', 'label', 'text', 'testid']) {
    if (typeof loc[key] === 'string') parts.push(`${key} "${freeText(loc[key])}"`);
  }
  if (loc.exact === true) parts.push('exact');
  return parts.join(' ');
}

// One plan step as type + locator only: a goto shows its URL's path, a read its property, an expect
// its op. A fill / select value and a press key are never shown.
function stepText(step) {
  if (!isPlainObject(step)) return '`?`';
  const type = typeof step.type === 'string' ? step.type.replace(/[^a-z_]/g, '') : '?';
  const parts = [`\`${type}\``];
  if (type === 'goto') {
    let p = '/';
    try {
      p = new URL(String(step.url)).pathname;
    } catch {
      p = '/';
    }
    parts.push(escapeHtml(scrubHeaderNames(p.replace(SCHEME_RE, ''))));
  }
  if (type === 'read' && typeof step.property === 'string') parts.push(escapeHtml(scrubHeaderNames(step.property)));
  if (type === 'expect' && typeof step.op === 'string') parts.push(escapeHtml(step.op));
  const loc = locatorText(step.locator);
  if (loc) parts.push(loc);
  return parts.join(' ');
}

function expectedText(expected) {
  if (!isPlainObject(expected)) return 'none';
  const value = typeof expected.value === 'string' ? `"${freeText(expected.value)}"` : freeText(JSON.stringify(expected.value));
  return `${freeText(expected.op)} ${value}`;
}

function shortSha(sha) {
  return typeof sha === 'string' ? sha.slice(0, SHORT_SHA_LENGTH) : 'unknown';
}

// The verdict cell. Without earlier revisions: the bare verdict. With them, one part per earlier
// revision, then the current one: `FAIL on plan 1 → PASS on plan 2`. A revision that never ran is
// `not run on plan <r>`; one whose run folder (or the criterion's entry in it) is gone shows the
// run-level verdict labelled `(whole run)`.
function verdictCell(current, revision, priorRevisions, own) {
  if (priorRevisions.length === 0) return current;
  const parts = [];
  for (const pr of priorRevisions) {
    const found = own.find((h) => h.revision === pr.revision && h.scope === 'criterion');
    if (pr.verdict === null) parts.push(`not run on plan ${pr.revision}`);
    else if (found) parts.push(`${found.verdict} on plan ${pr.revision}`);
    else parts.push(`${pr.verdict} on plan ${pr.revision} (whole run)`);
  }
  parts.push(`${current} on plan ${revision === null ? '?' : revision}`);
  return parts.join(' → ');
}

// True when the criterion is PASS now and its OWN verdict on some earlier plan was not PASS (a
// run-level fallback never counts).
function passAfterRevision(current, priorRevisions, own) {
  if (current !== VERDICTS.PASS) return false;
  return priorRevisions.some((pr) => {
    const found = own.find((h) => h.revision === pr.revision && h.scope === 'criterion');
    return Boolean(found) && found.verdict !== VERDICTS.PASS;
  });
}

// renderComment({ verdict, plan, criteria, history, readValues, redact }) → the comment body.
//  verdict     verdict.json (parsed)
//  plan        plan.json (parsed): the steps per criterion
//  criteria    criteria.json's `criteria` list [{ id, text }] (the order of the blocks)
//  history     { <criterion id>: [{ revision, verdict, scope: 'criterion' | 'run' }] } — each earlier
//              revision's own verdict for that criterion (comment.mjs reads it from the runs log)
//  readValues  show each criterion's read value (redacted); false by default
//  redact      extra redaction patterns applied after DEFAULT_REDACT_PATTERNS
export function renderComment({ verdict, plan = {}, criteria = [], history = {}, readValues = false, redact = [] }) {
  const patterns = [];
  patterns.push(...redact);
  const byId = isPlainObject(verdict.criteria) ? verdict.criteria : {};
  const textOf = new Map(criteria.filter((c) => isPlainObject(c) && typeof c.id === 'string').map((c) => [c.id, c.text]));
  const ids = [...[...textOf.keys()].filter((id) => id in byId), ...Object.keys(byId).filter((id) => !textOf.has(id))];
  const priorRevisions = Array.isArray(verdict.prior_revisions) ? verdict.prior_revisions.filter(isPlainObject) : [];
  const revision = Number.isInteger(verdict.plan_revision) ? verdict.plan_revision : null;
  const sha = shortSha(verdict.plan_sha256);
  const stepsBy = isPlainObject(plan.steps_by_criterion) ? plan.steps_by_criterion : {};
  const notPlannedBy = new Map((Array.isArray(plan.not_planned) ? plan.not_planned : [])
    .filter((np) => isPlainObject(np) && typeof np.id === 'string').map((np) => [np.id, np]));
  const ownOf = (id) => (Array.isArray(history[id]) ? history[id] : []);

  const revised = new Set();
  for (const id of ids) {
    if (passAfterRevision(byId[id].verdict, priorRevisions, ownOf(id))) revised.add(id);
  }
  const counts = countVerdicts(ids.filter((id) => !revised.has(id)).map((id) => byId[id].verdict));
  const summary = [
    [VERDICTS.PASS, counts[VERDICTS.PASS]],
    [PASS_AFTER_REVISION, revised.size],
    [VERDICTS.FAIL, counts[VERDICTS.FAIL]],
    [VERDICTS.BLOCKED, counts[VERDICTS.BLOCKED]],
    [VERDICTS.NOT_VERIFIABLE, counts[VERDICTS.NOT_VERIFIABLE]],
  ].filter(([, n]) => n > 0).map(([label, n]) => `${n} ${label}`).join(' · ');

  const lines = [
    COMMENT_MARKER,
    '### Selvedge verdict',
    '',
    `**${summary || 'no criteria'}**`,
    '',
    `Plan \`${sha}\` · revision ${revision === null ? 'unknown' : revision}`,
    '',
  ];
  for (const id of ids) {
    const c = byId[id];
    const cell = verdictCell(c.verdict, revision, priorRevisions, ownOf(id));
    const text = textOf.has(id) ? textOf.get(id) : id;
    lines.push('<details>', `<summary>${freeText(cell)} — ${freeText(text)}</summary>`, '');
    lines.push(`- **Criterion:** ${freeText(text)} (\`${freeText(id)}\`)`);
    lines.push(`- **Verdict:** ${freeText(cell)}`);
    lines.push(`- **Interpretation:** ${typeof c.interpretation === 'string' ? freeText(c.interpretation) : 'none'}`);
    const assumptions = Array.isArray(c.unverified_assumptions) ? c.unverified_assumptions.filter(isPlainObject) : [];
    if (assumptions.length === 0) lines.push('- **Unverified assumptions:** none');
    else {
      lines.push('- **Unverified assumptions:**');
      for (const a of assumptions) lines.push(`  - ${a.material === true ? '**(material)** ' : ''}${freeText(a.text)}`);
    }
    const steps = isPlainObject(stepsBy[id]) && Array.isArray(stepsBy[id].steps) ? stepsBy[id].steps : [];
    if (steps.length === 0) lines.push('- **Steps:** none planned');
    else {
      lines.push('- **Steps:**');
      steps.forEach((s, i) => lines.push(`  ${i + 1}. ${stepText(s)}`));
    }
    lines.push(`- **Expected:** ${expectedText(c.expected)}`);
    lines.push(`- **Matched:** ${c.matched === true ? 'yes' : c.matched === false ? 'no' : 'no check ran'}`);
    lines.push(`- **Evidence class:** ${freeText(c.evidence_class)}`);
    if (c.verdict === VERDICTS.BLOCKED || c.verdict === VERDICTS.NOT_VERIFIABLE) {
      const hint = UNBLOCK_HINTS[c.reason];
      lines.push(`- **Reason:** \`${freeText(c.reason)}\`${hint ? ` — ${hint}` : ''}`);
      // The planner's own words for a criterion it did not plan (the pages it looked at, or the
      // rewrite it suggests), redacted like a read value: they can quote what a snapshot showed. URLs
      // become paths before redaction, as for the read value, so a redaction never splits a URL.
      const np = notPlannedBy.get(id);
      const note = (label, v) => {
        if (typeof v === 'string' && v.trim() !== '') lines.push(`- **${label}:** ${freeText(redactValue(urlsToPaths(v), patterns))}`);
      };
      if (np && np.reason === c.reason) {
        note('Planner note', np.detail);
        note('Suggested rewrite', np.rewrite);
      }
    }
    let shown = c.read_value === null || c.read_value === undefined ? null : redactValue(urlsToPaths(c.read_value), patterns);
    if (!readValues) shown = null;
    if (shown !== null) lines.push(`- **Read value:** "${freeText(shown)}"`);
    else lines.push(`- **Read value:** not published${readValues ? ' (nothing was read)' : ' (`comment.read_values` is off)'}`);
    lines.push(`- **Plan:** \`${sha}\` · revision ${revision === null ? 'unknown' : revision}`);
    lines.push('', '</details>', '');
  }
  return `${lines.join('\n').replace(/\n+$/, '')}\n`;
}
