// runner/steps.mjs — the ONE plan-step executor: how a typed plan step drives a Playwright page.
//
// `selvedge snapshot` (lib/snapshot.mjs) runs a prefix through runStep, and `selvedge run`
// (runner/execute.mjs) runs a criterion's steps through runStep, readValue and expectMatches. There
// is no second executor: a step means the same thing in a snapshot prefix and in a run.
//
//   locate(page, locator)      the Playwright locator for a plan locator (role / label / text /
//                              testid; never CSS or XPath)
//   navigate(page, url)        goto, failing on an HTTP status >= 400 (naming the guard's reason
//                              when the guard refused the request)
//   runStep(page, step)        one resolved goto / click / fill / select / check / press / wait_for
//                              step; any other type throws (read and expect are not actions)
//   readValue(page, step)      one `read` step's value: text (innerText, trimmed), value
//                              (inputValue), checked (boolean), count (number), url, or
//                              attribute:<name> (string, or null when the attribute is absent)
//   expectMatches(step, reads) whether an `expect` step holds over the criterion's reads so far
//                              (the last read is the value checked; changed_from compares it with
//                              the read before it)
//
// Playwright's own actionability checks stay on (no `force`): a click on a hidden or covered
// element, or a locator that matches nothing or more than one element (strict mode), fails the step
// after the page's default timeout.
//
// Node >= 18, standard library only (Playwright is the caller's; never imported here).
import { reasonOfResponse } from './route-guard.mjs';

const ATTRIBUTE_PREFIX = 'attribute:';

// The Playwright locator for a plan-step locator (role / label / text / testid; never CSS).
export function locate(page, loc) {
  if ('role' in loc) {
    const opts = {};
    if ('name' in loc) opts.name = loc.name;
    if ('exact' in loc) opts.exact = loc.exact;
    return page.getByRole(loc.role, opts);
  }
  if ('label' in loc) return page.getByLabel(loc.label);
  if ('text' in loc) return page.getByText(loc.text);
  return page.getByTestId(loc.testid);
}

// Navigate, and fail on an HTTP error status (naming the guard's reason when the guard refused it).
export async function navigate(page, url) {
  const response = await page.goto(url);
  if (response && response.status() >= 400) {
    const reason = reasonOfResponse(response);
    throw new Error(`${url} answered HTTP ${response.status()}${reason ? ` (the guard refused it: ${reason})` : ''}`);
  }
}

// Run one validated, resolved step. Playwright's strict mode makes a locator that matches more than
// one element fail the step, as a locator matching nothing does (after the timeout).
export async function runStep(page, step) {
  switch (step.type) {
    case 'goto':
      await navigate(page, step.url);
      return;
    case 'click':
      await locate(page, step.locator).click();
      return;
    case 'fill':
      await locate(page, step.locator).fill(step.value);
      return;
    case 'select':
      await locate(page, step.locator).selectOption(step.value);
      return;
    case 'check':
      await locate(page, step.locator).setChecked(step.checked !== false);
      return;
    case 'press':
      if (step.locator) await locate(page, step.locator).press(step.key);
      else await page.keyboard.press(step.key);
      return;
    case 'wait_for':
      await locate(page, step.locator).waitFor({ state: step.state });
      return;
    default:
      // read / expect go through readValue / expectMatches; nothing else is a step.
      throw new Error(`step type ${JSON.stringify(step.type)} is not an action runStep runs`);
  }
}

// readValue(page, step) → the value one `read` step reads (see the header).
export async function readValue(page, step) {
  const p = step.property;
  if (p === 'url') return page.url();
  const loc = locate(page, step.locator);
  if (p === 'text') return String(await loc.innerText()).trim();
  if (p === 'value') return await loc.inputValue();
  if (p === 'checked') return await loc.isChecked();
  if (p === 'count') return await loc.count();
  if (typeof p === 'string' && p.startsWith(ATTRIBUTE_PREFIX)) {
    // getAttribute does not wait; waitFor makes an absent element fail the step, as the others do
    await loc.waitFor({ state: 'attached' });
    return await loc.getAttribute(p.slice(ATTRIBUTE_PREFIX.length));
  }
  throw new Error(`read property ${JSON.stringify(p)} is not one readValue reads`);
}

const isNumberLike = (v) => (typeof v === 'number' && Number.isFinite(v)) || (typeof v === 'string' && v.trim() !== '' && Number.isFinite(Number(v)));
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// expectMatches(step, reads) → true when the expect holds. `reads` is every value the criterion's
// read steps returned so far, in order; the last one is checked. No read, or a null last read,
// never matches (except changed_from, which compares two reads).
export function expectMatches(step, reads) {
  const list = Array.isArray(reads) ? reads : [];
  if (list.length === 0) return false;
  const last = list[list.length - 1];
  const { op, value } = step;
  switch (op) {
    case 'equals':
      return last !== null && last !== undefined && String(last) === String(value);
    case 'contains':
      return typeof last === 'string' && last.includes(value);
    case 'matches':
      return last !== null && last !== undefined && new RegExp(value).test(String(last));
    case 'gt':
      return isNumberLike(last) && Number(last) > value;
    case 'lt':
      return isNumberLike(last) && Number(last) < value;
    case 'changed_from': {
      if (list.length < 2) return false;
      const changed = !same(last, list[list.length - 2]);
      return changed === value;
    }
    default:
      throw new Error(`expect op ${JSON.stringify(op)} is not one expectMatches knows`);
  }
}
