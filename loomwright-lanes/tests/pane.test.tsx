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
  // A real mobile mount, not a stub: resolve() still hands back an Input there (it returns every element on every
  // surface), so only the module's surface guard keeps the note out; the kit drops an Input it cannot draw, hence the label check too.
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

// A question whose options could not be read: a pre-`items` core leaves the key out, the jq-failure fallback sends `items: []`.
test('a question with no readable options shows the main-session fallback, no buttons, and still counts', async ($, on) => {
  const calls: Call[] = []
  const bare = { id: 'toolu_q', asked_at: '2026-10-11T09:18:00Z', waiting_s: 720, question: 'Which path?' }
  const shapes = [bare, { ...bare, question: 'Still which path?', items: [] }]
  let doc: unknown = null
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(doc) }))
  on('ui.toast', async () => ({ value: undefined }))
  for (const [n, q] of shapes.entries()) {
    doc = { ...DOC, lanes: [DOC.lanes[0], { ...DOC.lanes[1], questions: [q] }] }
    if (n === 0) await $.command.run(RUN)
    for (const surface of ['terminal', 'desktop'] as const) {
      const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface, ...PANE })
      if (n === 1 && surface === 'terminal') await ui.press({ key: 'refresh' })
      const fallback = new RegExp(`^${q.question.replace(/[?.]/g, '\\$&')} Answer it from the main session with lane-answer\\.$`)
      expect(await ui.find({ type: 'Text', text: fallback })).toBeDefined()
      expect(await ui.find({ type: 'Text', text: /^1 question waiting$/ })).toBeDefined()
      for (const k of ['toolu_q:send', 'toolu_q:note', 'toolu_q:0:A', 'toolu_q:0:B', 'toolu_q:1:z']) expect(await ui.find({ key: k })).toBeUndefined()
      await ui.unmount()
    }
  }
  // Two lane-status reads, one plugin lookup: the located script is reused for the same (empty) loomwrightRoot.
  expect(calls.filter(c => c.argv.includes('lane-status')).length).toBeGreaterThanOrEqual(2)
  expect(calls.filter(c => c.argv[0] === 'claude').length).toBe(1)
  expect(calls.some(c => c.argv.includes('lane-answer'))).toBe(false)
})

// The step rail, the wave's start and keep-awake. The mocked clock is 2025-10-09T08:53:20Z (1_760_000_000 s);
// utc_offset_s 19800 (+05:30) makes it 14:23 local. Times below are relative to it.
const T0 = 1_760_000_000
const iso = (agoS: number) => new Date((T0 - agoS) * 1000).toISOString().replace(/\.000Z$/, 'Z')
const step = (id: string, name: string, state: string, startedAgo: number | null, endedAgo: number | null, lines: string[] = []) => ({
  id, name, state, started_at: startedAgo === null ? null : iso(startedAgo), ended_at: endedAgo === null ? null : iso(endedAgo),
  duration_s: startedAgo === null ? null : (endedAgo === null ? startedAgo : startedAgo - endedAgo), lines,
})
const APP_HOLD = [{ pid: 39844, process: 'Claude', assertion: 'NoIdleSleepAssertion', name: 'Electron', kind: 'claude-app' }]
const RAIL_DOC = {
  ...DOC,
  run_started_at: iso(5640),
  utc_offset_s: 19800,
  machine: { ...DOC.machine, state: 'ok', load1: 4.1, keep_awake: 'held', keep_awake_lasting: false, keep_awake_holders: APP_HOLD },
  lanes: [
    {
      ...DOC.lanes[0], started_at: iso(3640),
      timeline: {
        started_at: iso(3640), current: 'build', label: 'Build · EXECUTE', phase: 'EXECUTE', phase_status: 'running',
        phases: [{ phase: 'INIT', at: iso(3540) }, { phase: 'PRE_FLIGHT_SYNC', at: iso(3480) }],
        steps: [
          step('pick', 'Pick', 'done', 3640, 3600, ['picked reqs/a.md']),
          step('plan', 'Plan', 'done', null, null),
          step('build', 'Build', 'active', 3540, null, ['Supervisor started', 'Supervisor PRE_FLIGHT_SYNC: preflight_clear']),
          step('heal', 'Heal', 'pending', null, null), step('drain', 'Drain', 'pending', null, null),
          step('decide', 'Decide', 'pending', null, null), step('merge', 'Merge', 'pending', null, null),
        ],
      },
    },
  ],
}

test('each lane shows its current step, a seven-step rail with hover details, and when it started', async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(RAIL_DOC) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface, ...PANE })
    // The run, in the header: started 07:19:20Z = 12:49 local, running 1 h 34 min. No Started/Lanes tiles.
    expect(await ui.find({ type: 'Text', text: /^started 12:49 · running 1 h 34 min$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Lanes$/ })).toBeUndefined()
    // The lane: its step in the title, its own start, one hover scope per step.
    expect(await ui.find({ type: 'Text', text: /^● Build · EXECUTE$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /started 13:22 · 1 h 0 min$/ })).toBeDefined()
    for (const id of ['pick', 'plan', 'build', 'heal', 'drain', 'decide', 'merge']) expect(await ui.find({ key: `L1-step-${id}` })).toBeDefined()
    // One continuous bar, then ONE line: the current step, its place and time, and what comes next — no row of seven names.
    expect(await ui.find({ type: 'Text', text: /^step 3 of 7 · 59 min$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^next: Heal$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Heal$/ })).toBeUndefined()
    // The hover cards: the current step's time so far and Supervisor phases, a done step with no time, a pending one's purpose.
    expect(await ui.find({ type: 'Text', text: /^Build · now$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^since 13:24 · 59 min so far$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Supervisor: INIT 13:24 · PRE_FLIGHT_SYNC 13:25 · EXECUTE now$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^· Supervisor PRE_FLIGHT_SYNC: preflight_clear$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^no time recorded for this step$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Pick · done$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^13:22 → 13:23 · 40 s$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Phase 4\.5 integration review and fixes$/ })).toBeDefined()
    await ui.unmount()
  }
})

test('keep-awake names the Claude app hold, and the button starts caffeinate through lane-status --keep-awake', async ($, on) => {
  const calls: Call[] = []
  let doc: Record<string, unknown> = RAIL_DOC
  on('process.run', async (_$, e) => {
    calls.push({ argv: e.argv })
    const a = e.argv.join(' ')
    const stdout = a.startsWith('claude plugin list')
      ? JSON.stringify([{ id: 'loomwright@atelier', enabled: true, installPath: '/p' }])
      : a.endsWith('lane-status --keep-awake')
        ? 'keep-awake: started (opt-in --keep-awake) — caffeinate -i -w 4242 (pid 9); it ends with the coordinator\nlane-status: …'
        : JSON.stringify(doc)
    if (a.endsWith('lane-status --keep-awake')) {
      doc = { ...RAIL_DOC, machine: { ...RAIL_DOC.machine, keep_awake_lasting: true, keep_awake_holders: [...APP_HOLD, { pid: 9, process: 'caffeinate', assertion: 'PreventUserIdleSystemSleep', name: 'caffeinate', kind: 'caffeinate' }] } }
    }
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.status', async () => ({ value: undefined }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.toast', async () => ({ value: undefined }))
  mock.clock(on, { now: T0 * 1000 })
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'desktop', ...PANE })
  expect(await ui.find({ type: 'Text', text: /^Claude app only$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^drops when no Code session works$/ })).toBeDefined()
  await ui.press({ key: 'keep-awake' })
  expect(calls.some(c => c.argv.slice(2).join(' ') === 'lane-status --keep-awake')).toBe(true)
  expect(await ui.find({ type: 'Text', text: /^started \(opt-in --keep-awake\) — caffeinate -i -w 4242/ })).toBeDefined()
  // Re-read at once: a caffeinate now holds it, so the button is gone.
  expect(await ui.find({ type: 'Text', text: /^caffeinate holds it$/ })).toBeDefined()
  expect(await ui.find({ key: 'keep-awake' })).toBeUndefined()
  await ui.unmount()
})

test('a lane card links its PR and folds repeated actions', async ($, on) => {
  const calls: Call[] = []
  const doc = { ...DOC, lanes: [{ ...DOC.lanes[0], last_actions: ['Bash cd /Users/me/w/lanes/L1', 'Bash cd /Users/me/w/lanes/L1', 'Edit x.ts'] }] }
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(doc) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface, ...PANE })
    const link = await ui.find({ type: 'Link' })
    expect(link?.props).toEqual({ href: 'https://github.com/o/r/pull/5' })
    expect(link?.children).toEqual(['PR #5'])
    expect(await ui.find({ type: 'Text', text: /^· Bash cd ~\/w\/lanes\/L1 {2}\(×2\)$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^· Edit x\.ts$/ })).toBeDefined()
    await ui.unmount()
  }
})

test('in a narrow pane the rail still names the current step once, and keeps every hover card', async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(RAIL_DOC) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface, ...PANE, props: { ...PANE.props, bodyColumns: 40 } })
    expect(await ui.find({ type: 'Text', text: /^step 3 of 7 · 59 min$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^Heal$/ })).toBeUndefined()
    // The hover cards stay, one per step.
    expect(await ui.find({ key: 'L1-step-heal' })).toBeDefined()
    await ui.unmount()
  }
})

// A process.run stub whose lane-answer and lane-status calls can each be held open by a test.
function gated(on: On, calls: Call[]) {
  const held: { answer: Promise<void> | null; status: Promise<void> | null } = { answer: null, status: null }
  on('process.run', async (_$, e) => {
    calls.push({ argv: e.argv, stdin: e.init?.stdin })
    const a = e.argv.join(' ')
    if (a.includes(' lane-answer ') && held.answer) await held.answer
    if (a.includes(' lane-status ') && held.status) await held.status
    const r = a.startsWith('claude plugin list')
      ? { exitCode: 0, stdout: JSON.stringify([{ id: 'loomwright@atelier', enabled: true, installPath: '/p' }]) }
      : a.includes(' lane-answer ')
        ? { exitCode: 0, stdout: 'lane-answer: L2 answered (toolu_q) — resumed' }
        : { exitCode: 0, stdout: JSON.stringify(DOC) }
    return { value: { ...r, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.status', async () => ({ value: undefined }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.toast', async () => ({ value: undefined }))
  mock.clock(on, { now: 1_760_000_000_000 })
  const hold = (k: 'answer' | 'status') => {
    let release: () => void = () => {}
    held[k] = new Promise(r => { release = r })
    return () => { held[k] = null; release() }
  }
  return hold
}
const tick = () => new Promise(r => setTimeout(r, 20))

test('Send reads "Sending" while lane-answer runs and ignores a second press', async ($, on) => {
  const calls: Call[] = []
  const hold = gated(on, calls)
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'desktop', ...PANE })
  await ui.press({ key: 'toolu_q:0:A' })
  await ui.press({ key: 'toolu_q:1:z' })
  const release = hold('answer')
  const first = ui.press({ key: 'toolu_q:send' })
  await tick()
  expect((await ui.find({ key: 'toolu_q:send' }))?.text).toMatch(/Sending — resuming L2/)
  await ui.press({ key: 'toolu_q:send' })
  release()
  await first
  expect(calls.filter(c => c.argv.includes('lane-answer')).length).toBe(1)
  expect((await ui.find({ key: 'toolu_q:send' }))?.text).toMatch(/^Send answer and resume L2$/)
  await ui.unmount()
})

test('two Send presses in the same instant send one answer', async ($, on) => {
  const calls: Call[] = []
  const hold = gated(on, calls)
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'terminal', ...PANE })
  await ui.press({ key: 'toolu_q:0:A' })
  await ui.press({ key: 'toolu_q:1:z' })
  const release = hold('answer')
  // No tick between them: the second press arrives before the first one's state write lands.
  const both = Promise.all([ui.press({ key: 'toolu_q:send' }), ui.press({ key: 'toolu_q:send' })])
  await tick()
  release()
  await both
  expect(calls.filter(c => c.argv.includes('lane-answer')).length).toBe(1)
  await ui.unmount()
})

test('two Keep awake presses and two Refresh now presses in the same instant run once each', async ($, on) => {
  const calls: Call[] = []
  const hold = gated(on, calls)
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'terminal', ...PANE })
  const reads = () => calls.filter(c => c.argv.includes('lane-status') && !c.argv.includes('--keep-awake')).length
  const before = reads()
  let release = hold('status')
  let both = Promise.all([ui.press({ key: 'refresh' }), ui.press({ key: 'refresh' })])
  await tick()
  release()
  await both
  expect(reads()).toBe(before + 1)
  release = hold('status')
  both = Promise.all([ui.press({ key: 'keep-awake' }), ui.press({ key: 'keep-awake' })])
  await tick()
  release()
  await both
  expect(calls.filter(c => c.argv.includes('--keep-awake')).length).toBe(1)
  await ui.unmount()
})

test('the re-read after an answer is not lost when a poll is already reading', async ($, on) => {
  const calls: Call[] = []
  const hold = gated(on, calls)
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'terminal', ...PANE })
  await ui.press({ key: 'toolu_q:0:A' })
  await ui.press({ key: 'toolu_q:1:z' })
  const release = hold('status')
  const poll = ui.press({ key: 'refresh' }) // a read in flight, as a 15 s poll would be
  await tick()
  const sent = ui.press({ key: 'toolu_q:send' })
  await tick()
  release()
  await Promise.all([poll, sent])
  const at = calls.findIndex(c => c.argv.includes('lane-answer'))
  expect(at).toBeGreaterThan(-1)
  expect(calls.slice(at + 1).some(c => c.argv.includes('lane-status'))).toBe(true)
  await ui.unmount()
})

test('a question already answered elsewhere says so and clears the picks', async ($, on) => {
  const calls: Call[] = []
  on('process.run', async (_$, e) => {
    calls.push({ argv: e.argv })
    const a = e.argv.join(' ')
    const r = a.startsWith('claude plugin list')
      ? { exitCode: 0, stdout: JSON.stringify([{ id: 'loomwright@atelier', enabled: true, installPath: '/p' }]), stderr: '' }
      : a.includes(' lane-answer ')
        ? { exitCode: 1, stdout: '', stderr: 'lane-answer: refused — toolu_q already answered' }
        : { exitCode: 0, stdout: JSON.stringify(DOC), stderr: '' }
    return { value: { ...r, isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('ui.status', async () => ({ value: undefined }))
  on('ui.open', async () => ({ value: { isPlaced: true } }))
  on('ui.toast', async () => ({ value: undefined }))
  mock.clock(on, { now: 1_760_000_000_000 })
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'terminal', ...PANE })
  await ui.press({ key: 'toolu_q:0:A' })
  await ui.press({ key: 'toolu_q:1:z' })
  await ui.press({ key: 'toolu_q:send' })
  expect(await ui.find({ type: 'Text', text: /L2: this question was already answered \(from the main session, most likely\)/ })).toBeDefined()
  expect((await ui.find({ key: 'toolu_q:0:A' }))?.text).toContain('○')
  await ui.unmount()
})

test('the wave card lists every wave oldest first: built waves with their PR and state, then the wave being worked', async ($, on) => {
  const calls: Call[] = []
  const doc = { ...RAIL_DOC, waves: [
    { wave: 1, branch: 'wave/r-w1', pr: 'https://github.com/o/r/pull/9', built_at: iso(600), lanes: ['L7', 'L8'], state: 'merged' },
    { wave: 2, branch: 'wave/r-w2', pr: 'https://github.com/o/r/pull/12', built_at: null, lanes: ['L9'], state: 'open' },
  ], next_wave: { wave: 3, lanes: ['L1'] } }
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(doc) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface, ...PANE })
    const links = await ui.findAll({ type: 'Link' })
    const hrefs = links.map(l => (l.props as { href: string }).href)
    expect(hrefs.indexOf('https://github.com/o/r/pull/9')).toBeLessThan(hrefs.indexOf('https://github.com/o/r/pull/12'))
    expect(await ui.find({ type: 'Text', text: /^Wave 1$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^merged ✓$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^L7 L8 · built 14:13$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^ready to merge$/ })).toBeDefined()
    // The wave being worked: its number, its lanes and what they are doing.
    expect(await ui.find({ type: 'Text', text: /^Wave 3$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^in progress$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^L1 · 1 running$/ })).toBeDefined()
    await ui.unmount()
  }
})

test('a wave record from an older Loomwright (no lanes, no state) still links its PR and names its branch', async ($, on) => {
  const calls: Call[] = []
  const doc = { ...RAIL_DOC, waves: [{ wave: 1, branch: 'wave/r-w1', pr: 'https://github.com/o/r/pull/9', built_at: iso(600) }] }
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(doc) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'desktop', ...PANE })
  expect((await ui.findAll({ type: 'Link' })).some(l => (l.props as { href: string }).href === 'https://github.com/o/r/pull/9')).toBe(true)
  expect(await ui.find({ type: 'Text', text: /^wave\/r-w1 · built 14:13$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^merged ✓$/ })).toBeUndefined()
  await ui.unmount()
})

// A lane closed out and removed: its clone is gone, lane-status reads it from the salvage copy.
const CLOSED = {
  ...DOC.lanes[0], lane: 'L3', path: '/w/lanes/L3', item: 'reqs/phase-2/2026-10-14-094204-triggers.md', run_id: 'r-L3', state: 'removed', outcome: 'done',
  pr: 'https://github.com/o/r/pull/49', branch: 'feature/c', last_message: "Don't merge it yet: the wave is still open.",
  last_actions: ['Bash gh pr view 49'], ci_slot: { state: 'none', position: null, held: null }, readiness: null,
  started_at: iso(9000), ended_at: iso(1800),
  timeline: { started_at: iso(9000), current: null, label: 'Done', phase: null, phase_status: null, phases: [],
    steps: ['pick', 'plan', 'build', 'heal', 'drain', 'decide', 'merge'].map(id => step(id, id, 'done', null, null)) },
}

test('a finished lane collapses to one row — how it ended, its PR, its wave, when it finished and how long it ran', async ($, on) => {
  const calls: Call[] = []
  const doc = { ...RAIL_DOC, waves: [{ wave: 1, branch: 'wave/r-w1', pr: 'https://github.com/o/r/pull/51', built_at: iso(2400), lanes: ['L3'], state: 'merged' }],
    next_wave: { wave: 2, lanes: ['L1'] }, lanes: [...RAIL_DOC.lanes, CLOSED] }
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(doc) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface, ...PANE })
    // No full card: no rail, no stale latest message, no step buttons for L3.
    expect(await ui.find({ key: 'L3-step-pick' })).toBeUndefined()
    expect(await ui.find({ key: 'L3:details' })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /Don't merge it yet/ })).toBeUndefined()
    // The compact row.
    expect(await ui.find({ type: 'Text', text: /^Finished · 1$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^ · 1 merged$/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /^✓ done$/ })).toBeDefined()
    const prLink = (await ui.findAll({ type: 'Link' })).find(l => (l.props as { href: string }).href === 'https://github.com/o/r/pull/49')
    expect(prLink?.children).toEqual(['#49'])
    // One line: wave, end time (08:23:20Z = 13:53 local), how long it ran (9000 − 1800 s, frozen), the short item name.
    expect(await ui.find({ type: 'Text', text: /^wave 1 · 13:53 · ran 2 h 0 min · triggers$/ })).toBeDefined()
    // The live lane keeps its full card.
    expect(await ui.find({ key: 'L1-step-pick' })).toBeDefined()
    await ui.unmount()
  }
})

test("a parked lane's clock stops at ended_at instead of counting to now", async ($, on) => {
  const calls: Call[] = []
  const parked = { ...RAIL_DOC.lanes[0], state: 'ready_for_release', ended_at: iso(640) }
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify({ ...RAIL_DOC, lanes: [parked] }) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'desktop', ...PANE })
  // started 3640 s ago, stopped 640 s ago: ran 50 min (not 1 h 0 min).
  expect(await ui.find({ type: 'Text', text: /started 13:22 · ran 50 min$/ })).toBeDefined()
  // Parked reads as ready (●), never the ◆ a question uses; outside a wave it is the lane's own PR to merge.
  expect(await ui.find({ type: 'Text', text: /^● Ready to merge$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /◆/ })).toBeUndefined()
  await ui.unmount()
})

test('in a wave a parked lane reads "parked for wave N" — the owner merges the wave PR, not the lane PR', async ($, on) => {
  const calls: Call[] = []
  const parked = { ...RAIL_DOC.lanes[0], state: 'ready_for_release', ended_at: iso(640) }
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify({ ...RAIL_DOC, lanes: [parked], next_wave: { wave: 2, lanes: ['L1'] } }) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'desktop', ...PANE })
  expect(await ui.find({ type: 'Text', text: /^● Parked for wave 2$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^● Ready to merge$/ })).toBeUndefined()
  expect(await ui.find({ type: 'Text', text: /^L1 · 1 parked$/ })).toBeDefined()
  await ui.unmount()
})

test('a question header sits inline before the question, not as an all-caps label above it', async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(DOC) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'desktop', ...PANE })
  expect(await ui.find({ type: 'Text', text: /^Path · $/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^PATH$/ })).toBeUndefined()
  // The note field carries its own label (a screen reader names the field), not a caption above it.
  expect((await ui.find({ key: 'toolu_q:note' }))?.props).toMatchObject({ label: 'Note', placeholder: 'optional; guidance, not an answer' })
  // Send reads dim until every question is answered (buttons have no disabled state; the helper line says why).
  expect((await ui.find({ key: 'toolu_q:send' }))?.props).toMatchObject({ dimColor: true })
  expect(await ui.find({ type: 'Text', text: /^Answer every question to send\.$/ })).toBeDefined()
  await ui.unmount()
})

test('Show last 20 steps also lists every step with its state, times and last line — no pointer needed', async ($, on) => {
  const calls: Call[] = []
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify(RAIL_DOC) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'desktop', ...PANE })
  expect(await ui.find({ key: 'L1-steps' })).toBeUndefined()
  await ui.press({ key: 'L1:details' })
  expect(await ui.find({ key: 'L1-steps' })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^Build · now · since 13:24 · 59 min so far$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^Pick · done · 13:22 → 13:23 · 40 s$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^Heal · pending · Phase 4\.5 integration review and fixes$/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /^ {3}Supervisor PRE_FLIGHT_SYNC: preflight_clear$/ })).toBeDefined()
  await ui.unmount()
})

test('layout holds: a narrow pane stacks the lane title over its PR and times; a Finished row never squeezes its status', async ($, on) => {
  const calls: Call[] = []
  const closed = { ...RAIL_DOC.lanes[0], lane: 'L3', state: 'removed', outcome: 'done', pr: 'https://github.com/o/r/pull/49', ended_at: iso(1800), timeline: null }
  stub(on, calls, () => ({ exitCode: 0, stdout: JSON.stringify({ ...RAIL_DOC, lanes: [...RAIL_DOC.lanes, closed] }) }))
  on('ui.toast', async () => ({ value: undefined }))
  await $.command.run(RUN)
  for (const [cols, dir] of [[40, 'column'], [120, 'row']] as const) {
    const ui = await $.ui.mount({ plugin: 'loomwright-lanes', surface: 'desktop', ...PANE, props: { ...PANE.props, bodyColumns: cols } })
    expect((await ui.find({ key: 'L1-head' }))?.props).toMatchObject({ flexDirection: dir })
    expect((await ui.find({ key: 'done-L3-head' }))?.props).toMatchObject({ flexShrink: 0 })
    await ui.unmount()
  }
})
