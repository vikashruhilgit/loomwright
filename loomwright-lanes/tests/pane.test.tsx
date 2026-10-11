import type { On } from 'claude-code'
import { expect, mock, test } from 'claude-code/testing'

// A fixture `lane-status --json` (automate-lanes.sh schema_version 1): one running lane, one lane waiting
// on a two-question call (single + multiSelect, a label containing a comma), an overloaded machine.
const DOC = {
  schema_version: 1,
  parent_run_id: 'automate-2026-10-11-090000',
  generated_at: '2026-10-11T09:30:00Z',
  machine: { state: 'overloaded', load1: 72.5, cpus: 12, mem_pressure: 'warn', keep_awake: 'not held' },
  memory_pressure: false,
  keep_awake_suggestion: 'caffeinate -i -w 4242',
  lanes: [
    {
      lane: 'L1', path: '/w/lanes/L1', item: 'reqs/a.md', run_id: 'r-L1', state: 'running', reason: '',
      pr: 'https://github.com/o/r/pull/5', pr_state: null, branch: 'feature/a', last_progress: '- picked reqs/a.md',
      last_actions: ['Bash git status', 'Edit x.ts', 'Bash ci-local'], last_message: 'Running the suite now.',
      questions: [], ci_slot: { state: 'waiting', position: 2, held: null }, held_for_load: null,
      readiness: { score: '5/5', summary: 'ready (5/5)', file: '/w/lanes/L1/r.md' },
    },
    {
      lane: 'L2', path: '/w/lanes/L2', item: 'reqs/b.md', run_id: 'r-L2', state: 'awaiting_input', reason: 'question toolu_q',
      pr: null, pr_state: null, branch: 'feature/b', last_progress: '', last_actions: ['AskUserQuestion'],
      last_message: 'Two ways to do this.', ci_slot: { state: 'none', position: null, held: null }, held_for_load: null,
      readiness: null,
      questions: [
        {
          id: 'toolu_q', asked_at: '2026-10-11T09:18:00Z', waiting_s: 720, question: 'Which path?',
          items: [
            { question: 'Which path?', header: 'Path', multiSelect: false, options: [{ label: 'A', description: 'the first' }, { label: 'B', description: null }] },
            { question: 'Which checks?', header: null, multiSelect: true, options: [{ label: 'x, y', description: null }, { label: 'z', description: null }] },
          ],
        },
      ],
    },
  ],
}

type Call = { argv: readonly string[]; stdin?: string }

function stub(on: On, calls: Call[], status: () => { exitCode: number; stdout: string }) {
  on('process.run', async (_$, e) => {
    calls.push({ argv: e.argv, stdin: e.init?.stdin })
    const a = e.argv.join(' ')
    const r = a.startsWith('claude plugin list')
      ? { exitCode: 0, stdout: JSON.stringify([{ id: 'loomwright@atelier', enabled: true, installPath: '/plugins/loomwright/9.9.9' }]) }
      : a.includes(' lane-status ')
        ? status()
        : a.includes(' lane-answer ')
          ? { exitCode: 0, stdout: 'lane-answer: L2 answered (toolu_q) — resumed' }
          : { exitCode: 0, stdout: '[say] one\n[tool] Bash two' }
    return { value: { ...r, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.status', async () => ({ value: undefined }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  mock.clock(on, { now: 1_760_000_000_000 })
}

const PANE = {
  component: 'Pane',
  requestId: 'loomwright-lanes',
  props: { title: 'Lanes', isFocused: true, bodyColumns: 120, placement: 'dock', scroll: { offset: 0, bodyRows: 60 }, view: {} },
} as const
const RUN = { command: 'lanes', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } } as const

test('the pane shows machine health, wait time, latest message, branch, readiness and option buttons', async ($, on) => {
  const calls: Call[] = []
  const toasts: string[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(DOC) }))
  on('ui.toast', async (_$, e) => {
    toasts.push(JSON.stringify(e))
    return { value: undefined }
  })
  await $.command.run(RUN)
  expect(toasts.some(t => t.includes('HIGH-LOAD'))).toBe(true)
  expect(toasts.some(t => t.includes('L2 is waiting for your answer'))).toBe(true)
  // Located through `claude plugin list`, then only the three lane commands.
  expect(calls.some(c => c.argv.join(' ') === 'bash /plugins/loomwright/9.9.9/scripts/automate-lanes.sh lane-status --json')).toBe(true)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface, ...PANE })
    expect(await ui.find({ type: 'Text', text: /HIGH-LOAD — machine overloaded/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /load1 72\.5 on 12 CPUs/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Inbox$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^1 question waiting$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /answer it in the Inbox/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^12 min$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Two ways to do this\.$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^feature\/a$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^5\/5 ✓$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /waiting · position 2/ })).toBeDefined()
    // The exact option labels lane-answer accepts, one button each.
    for (const k of ['toolu_q:0:A', 'toolu_q:0:B', 'toolu_q:1:x, y', 'toolu_q:1:z']) expect(await ui.find({ key: k })).toBeDefined()
    await ui.unmount()
  }
})

test('send refuses until every question is picked, then answers through lane-answer only', async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(DOC) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'terminal', ...PANE })
  // Pick one is a radio (○ ●), pick any a checkbox (☐ ☑).
  expect((await ui.find({ key: 'toolu_q:0:A' }))?.text).toContain('○')
  expect((await ui.find({ key: 'toolu_q:1:z' }))?.text).toContain('☐')
  await ui.press({ key: 'toolu_q:0:A' })
  expect((await ui.find({ key: 'toolu_q:0:A' }))?.text).toContain('●')
  await ui.press({ key: 'toolu_q:send' })
  expect(await ui.find({ type: 'Text', text: /^Not sent$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /L2: pick an option for every question first/ })).toBeDefined()
  expect(calls.some(c => c.argv.includes('lane-answer'))).toBe(false)

  await ui.press({ key: 'toolu_q:1:x, y' })
  await ui.press({ key: 'toolu_q:1:z' })
  expect((await ui.find({ key: 'toolu_q:1:z' }))?.text).toContain('☑')
  await ui.press({ key: 'toolu_q:send' })
  const sent = calls.find(c => c.argv.includes('lane-answer'))
  expect(sent?.argv.slice(2)).toEqual(['lane-answer', '/w/lanes/L2', 'toolu_q', '--owner-command', '/lanes answer L2 toolu_q', '--via', 'lanes-addon'])
  expect(JSON.parse(sent?.stdin ?? '{}')).toEqual({ answers: { '0': 'A', '1': 'x, y,z' } })
  expect(await ui.find({ type: 'Text', text: /^Sent$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /L2: lane-answer: L2 answered/ })).toBeDefined()
  await ui.unmount()
})

test('a failing lane-status shows "status unavailable" and nothing else', async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 2, stdout: 'lane-status: boom' }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'terminal', ...PANE })
  expect(await ui.find({ type: 'Text', text: /Lane status unavailable/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /lane-status: boom/ })).toBeDefined()
  expect(calls.every(c => !c.argv.includes('lane-answer'))).toBe(true)
  await ui.unmount()
})

test('loomwrightRoot is used as given, with no plugin-list lookup', { options: { loomwrightRoot: '/dev/checkout/loomwright/' } }, async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(DOC) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  expect(calls.some(c => c.argv[0] === 'claude')).toBe(false)
  expect(calls.some(c => c.argv[1] === '/dev/checkout/loomwright/scripts/automate-lanes.sh')).toBe(true)
})

test('with no lanes and no pane opened it polls once a minute, not every 15 s', async ($, on) => {
  const calls: Call[] = []
  on('process.run', async (_$, e) => {
    calls.push({ argv: e.argv })
    const stdout = e.argv[0] === 'claude'
      ? JSON.stringify([{ id: 'loomwright@atelier', enabled: true, installPath: '/p' }])
      : JSON.stringify({ schema_version: 1, parent_run_id: null, machine: { state: 'ok', load1: 1, cpus: 8, mem_pressure: 'ok', keep_awake: 'not held' }, lanes: [] })
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.status', async () => ({ value: undefined }))
  on('command.register', async () => ({ value: { command: 'lanes' } }))
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  const clock = mock.clock(on, { now: 0 })
  await $.session.start({ cwd: '/w', surface: 'terminal', isInteractive: true })
  const reads = () => calls.filter(c => c.argv.includes('lane-status')).length
  await clock.advance(1)
  const first = reads()
  await clock.advance(15_000 * 3)
  expect(reads()).toBe(first)
  await clock.advance(15_000)
  expect(reads()).toBe(first + 1)
})

test('Refresh now re-reads lane-status at once', async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(DOC) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  const reads = () => calls.filter(c => c.argv.includes('lane-status')).length
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'terminal', ...PANE })
  const before = reads()
  await ui.press({ key: 'refresh' })
  expect(reads()).toBe(before + 1)
  await ui.unmount()
})

// Two lanes waiting: L3's question is older than L2's, and L3 already has a held answer; L2 also has policy answers.
const INBOX_DOC = {
  ...DOC,
  machine: { ...DOC.machine, state: 'ok' },
  lanes: [
    { ...DOC.lanes[1], policy: { answered: 2, first_at: '2026-10-11T08:00:00Z', last_at: '2026-10-11T09:00:00Z', last_gate: 'plan-review', last_label: 'Proceed' } },
    {
      ...DOC.lanes[1], lane: 'L3', path: '/w/lanes/L3', item: 'reqs/c.md', state: 'answer_pending', reason: 'answer held',
      questions: [{ id: 'toolu_old', asked_at: '2026-10-11T07:00:00Z', waiting_s: 9000, question: 'Go ahead?',
        items: [{ question: 'Go ahead?', header: null, multiSelect: false, options: [{ label: 'Yes', description: null }, { label: 'No', description: null }] }] }],
    },
  ],
}

test('the inbox lists every waiting question oldest first, carries a note, and offers to replace a held answer', async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(INBOX_DOC) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface, ...PANE })
    expect(await ui.find({ type: 'Text', text: /^2 questions waiting$/ })).toBeDefined()
    // Oldest first: L3's send button comes before L2's in document order.
    const sends = (await ui.findAll({ type: 'Button' })).map(b => b.key).filter(k => k?.endsWith(':send'))
    expect(sends).toEqual(['toolu_old:send', 'toolu_q:send'])
    expect(await ui.find({ type: 'Text', text: /An answer is held/ })).toBeDefined()
    expect(await ui.find({ type: 'Button', text: /Replace held answer for L3/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /2 answered automatically · last plan-review → Proceed/ })).toBeDefined()
    expect(await ui.find({ key: 'toolu_q:note' })).toBeDefined()
    await ui.unmount()
  }
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'terminal', ...PANE })
  await ui.press({ key: 'toolu_old:0:Yes' })
  await ui.input({ key: 'toolu_old:note', text: 'ship it after the suite' })
  await ui.press({ key: 'toolu_old:send' })
  const sent = calls.find(c => c.argv.includes('lane-answer'))
  expect(sent?.argv.slice(3, 5)).toEqual(['/w/lanes/L3', 'toolu_old'])
  expect(JSON.parse(sent?.stdin ?? '{}')).toEqual({ answers: { '0': 'Yes' }, note: 'ship it after the suite' })
  await ui.unmount()
})

test('on a surface with no text input the note field is left out and an answer still sends', async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(DOC) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  // The mobile element table has no Input, so this is the real `Input === null` branch, not a stub.
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'mobile', ...PANE })
  expect(await ui.find({ key: 'toolu_q:note' })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /Note to the lane/ })).toBeUndefined()
  for (const k of ['toolu_q:0:A', 'toolu_q:send']) expect(await ui.find({ key: k })).toBeDefined()
  await ui.press({ key: 'toolu_q:0:A' })
  await ui.press({ key: 'toolu_q:1:z' })
  await ui.press({ key: 'toolu_q:send' })
  const sent = calls.find(c => c.argv.includes('lane-answer'))
  expect(JSON.parse(sent?.stdin ?? '{}')).toEqual({ answers: { '0': 'A', '1': 'z' } })
  await ui.unmount()
})
