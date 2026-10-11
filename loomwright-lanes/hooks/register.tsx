// loomwright-lanes — the OPTIONAL in-session pane over Loomwright's `/automate --parallel` lanes
// (parallel-automate/14, decision P9). It holds no truth of its own: it READS `lane-status --json`
// (state) and `lane-feed` (Details), and WRITES only through `lane-answer` (which validates the labels
// and resumes the lane). It never reads a lane's files, never launches or resumes a lane itself, and
// never merges. Uninstalled, the lanes behave identically: `lane-status --watch` plus answering in
// the main session is the plain view.
//
// Every Loomwright call goes through `lane()` below, and `locate()` is the one other process call
// (`claude plugin list --json`, to find the installed Loomwright). scripts/test-lanes-addon.sh holds
// the module to exactly that.
import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { LaneNote, LaneOption, LanePicks, LaneQuestion, LaneRow, LaneSnapshot, LaneStatusDoc } from '../types'

const PANE = 'loomwright-lanes'
const TITLE = 'Lanes'
const POLL_MS = 15_000
const IDLE_EVERY = 4
const DETAIL_STEPS = 20
const VIA = 'lanes-addon'

const snapshot = atom({ plugin: 'loomwright-lanes', key: 'snapshot' } as const, { doc: null, error: null, at: 0 } as LaneSnapshot)
const seen = atom({ plugin: 'loomwright-lanes', key: 'seen' } as const, {} as Record<string, boolean>)
const picks = atom({ plugin: 'loomwright-lanes', key: 'picks' } as const, {} as LanePicks)
const message = atom({ plugin: 'loomwright-lanes', key: 'message' } as const, { text: '', ok: true } as LaneNote)
const open = atom({ plugin: 'loomwright-lanes', key: 'open' } as const, {} as Record<string, boolean>)
const details = atom({ plugin: 'loomwright-lanes', key: 'details' } as const, {} as Record<string, string[]>)
const noteDrafts = atom({ plugin: 'loomwright-lanes', key: 'notes' } as const, {} as Record<string, string>)
const overloaded = atom({ plugin: 'loomwright-lanes', key: 'overloaded' } as const, false)

type LaneCommand = 'lane-status' | 'lane-feed' | 'lane-answer'
type Ran = { ok: boolean; out: string }

// ---- reaching Loomwright ---------------------------------------------------------------------------

let script: string | null = null

/** automate-lanes.sh of the configured folder, else of the installed loomwright plugin; null when neither. */
async function locate($: EngineInterface, configured: string): Promise<string | null> {
  if (script) return script
  if (configured.trim() !== '') {
    script = `${configured.trim().replace(/\/+$/, '')}/scripts/automate-lanes.sh`
    return script
  }
  try {
    const r = await $.process.run(['claude', 'plugin', 'list', '--json'], { timeoutMs: 30_000 })
    if (r.exitCode !== 0) return null
    const list = JSON.parse(r.stdout) as Array<{ id?: string; enabled?: boolean; installPath?: string }>
    const lw = list.find(p => (p.id ?? '').startsWith('loomwright@') && p.enabled !== false && p.installPath)
    script = lw?.installPath ? `${lw.installPath}/scripts/automate-lanes.sh` : null
  } catch {
    script = null
  }
  return script
}

/** The one door to Loomwright: `bash automate-lanes.sh <lane-status|lane-feed|lane-answer> …`. */
async function lane($: EngineInterface, configured: string, sub: LaneCommand, args: string[], stdin?: string): Promise<Ran> {
  const s = await locate($, configured)
  if (!s) return { ok: false, out: 'loomwright not found (install loomwright, or set loomwrightRoot in /config)' }
  try {
    const r = await $.process.run(['bash', s, sub, ...args], { timeoutMs: 60_000, ...(stdin === undefined ? {} : { stdin }) })
    return { ok: r.exitCode === 0, out: (r.exitCode === 0 ? r.stdout : r.stdout + r.stderr).trim() }
  } catch (err) {
    return { ok: false, out: String(err) }
  }
}

// ---- reading -----------------------------------------------------------------------------------------

const WAITING = new Set(['awaiting_input', 'answer_pending'])
const TROUBLE = new Set(['stalled', 'died', 'lost_to_reset', 'missing', 'blocked_launch', 'gone', 'escalated', 'failed', 'rate_limit', 'drain_died'])

function glyph(l: LaneRow): string {
  if (l.state === 'running') return '▶'
  if (WAITING.has(l.state)) return '❓'
  if (TROUBLE.has(l.state)) return '⚠'
  if (l.state === 'held_for_load') return '⏸'
  return '■'
}

type Tone = 'success' | 'error' | 'warning' | 'suggestion' | 'subtle' | undefined

function tone(l: LaneRow): Tone {
  if (l.state === 'running') return 'suggestion'
  if (WAITING.has(l.state) || l.state === 'held_for_load') return 'warning'
  if (TROUBLE.has(l.state)) return 'error'
  if (['ready_for_release', 'awaiting_merge', 'merged', 'done'].includes(l.state)) return 'success'
  return undefined
}

/** A see-through wash of a tone (desktop backgrounds): reads on a light and a dark pane alike. */
const RGB: Record<string, string> = {
  success: '22, 163, 74',
  error: '220, 38, 38',
  warning: '217, 119, 6',
  suggestion: '37, 99, 235',
  subtle: '120, 120, 120',
}
function tint(t: Tone, alpha: number): string {
  return `rgba(${RGB[t ?? 'subtle']}, ${alpha})`
}

/** The state in words: `awaiting_input` reads "waiting for you". */
function label(l: LaneRow): string {
  if (l.state === 'awaiting_input') return 'waiting for you'
  if (l.state === 'answer_pending') return 'answer held'
  return l.state.replace(/_/g, ' ')
}

function prRef(pr: string): string {
  const n = /\/pull\/(\d+)/.exec(pr)
  return n ? `PR #${n[1]}` : pr
}

function isReady(l: LaneRow): boolean {
  return !!l.readiness && /^(\d+)\/\1$/.test(l.readiness.score)
}

/** How long a question has waited: "just now", "12 min", "2 h 5 min". */
function waited(s: number | null): string {
  if (s === null || !Number.isFinite(s)) return ''
  const m = Math.max(0, Math.floor(s / 60))
  if (m < 1) return 'just now'
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60} min`
}

function clip(s: string, n: number): string {
  return s.length <= n ? s : s.slice(0, Math.max(0, n - 1)) + '…'
}

function waitingCount(doc: LaneStatusDoc): number {
  return doc.lanes.filter(l => l.questions.length > 0).length
}

async function loadDetails($: EngineInterface, configured: string, l: LaneRow): Promise<void> {
  const r = await lane($, configured, 'lane-feed', [l.path])
  const lines = r.out.split('\n').filter(x => x.trim() !== '')
  await update($, details, all => ({ ...all, [l.lane]: r.ok ? lines.slice(-DETAIL_STEPS) : [`(details unavailable: ${clip(r.out, 200)})`] }))
}

let busy = false

async function refresh($: EngineInterface, configured: string): Promise<void> {
  if (busy) return
  busy = true
  try {
    const r = await lane($, configured, 'lane-status', ['--json'])
    const at = await $.clock.now()
    let doc: LaneStatusDoc | null = null
    try {
      doc = r.ok ? (JSON.parse(r.out) as LaneStatusDoc) : null
    } catch {
      doc = null
    }
    if (!doc || !Array.isArray(doc.lanes)) {
      // Fail-safe: say so, keep the last good document on screen, change nothing.
      await update($, snapshot, s => ({ ...s, at, error: clip(r.out || 'status unreadable', 300) }))
      $.ui.status('lanes: status unavailable')
      return
    }
    await update($, snapshot, () => ({ doc, error: null, at }))

    const running = doc.lanes.filter(l => l.state === 'running').length
    const asking = waitingCount(doc)
    const hot = doc.machine?.state === 'overloaded'
    $.ui.status(
      doc.lanes.length === 0
        ? undefined
        : `lanes: ${running} running${asking ? ` · ${asking} waiting for you` : ''}${hot ? ' · HIGH-LOAD' : ''}`,
    )

    if (hot && !(await read($, overloaded))) $.ui.toast(`HIGH-LOAD: machine overloaded (load1 ${doc.machine.load1} on ${doc.machine.cpus} CPUs) — /lanes`)
    if (hot !== (await read($, overloaded))) await update($, overloaded, () => hot)

    const known = await read($, seen)
    for (const l of doc.lanes) {
      for (const q of l.questions) {
        if (known[q.id]) continue
        $.ui.toast(`${l.lane} is waiting for your answer — /lanes`)
        await update($, seen, s => ({ ...s, [q.id]: true }))
      }
    }

    const opened = await read($, open)
    for (const l of doc.lanes) if (opened[l.lane]) await loadDetails($, configured, l)
  } finally {
    busy = false
  }
}

// ---- answering -----------------------------------------------------------------------------------------

/** Ready to send: every question has one pick (or, multiSelect, at least one). */
function complete(q: LaneQuestion, mine: Record<string, string[]>): boolean {
  const items = q.items ?? []
  return items.length > 0 && items.every((it, i) => {
    const n = (mine[String(i)] ?? []).length
    return it.multiSelect ? n >= 1 : n === 1
  })
}

async function send($: EngineInterface, configured: string, l: LaneRow, q: LaneQuestion): Promise<void> {
  const mine = (await read($, picks))[q.id] ?? {}
  if (!complete(q, mine)) {
    await update($, message, () => ({ text: `${l.lane}: pick an option for every question first.`, ok: false }))
    return
  }
  // lane-answer's own format: one entry per question index; multiSelect labels comma-joined.
  const answers: Record<string, string> = {}
  for (const [k, v] of Object.entries(mine)) answers[k] = v.join(',')
  // The optional note rides with the answer; lane-answer delivers it as an annotation, never the decision.
  const text = ((await read($, noteDrafts))[q.id] ?? '').trim()
  const r = await lane(
    $,
    configured,
    'lane-answer',
    [l.path, q.id, '--owner-command', `/lanes answer ${l.lane} ${q.id}`, '--via', VIA],
    JSON.stringify(text ? { answers, note: text } : { answers }),
  )
  // lane-answer's words, verbatim — its refusal text included.
  await update($, message, () => ({ text: `${l.lane}: ${r.out || (r.ok ? 'answered' : 'lane-answer failed')}`, ok: r.ok }))
  if (r.ok) {
    await update($, picks, all => Object.fromEntries(Object.entries(all).filter(([id]) => id !== q.id)))
    await update($, noteDrafts, all => Object.fromEntries(Object.entries(all).filter(([id]) => id !== q.id)))
  }
  await refresh($, configured)
}

// ---- the module ------------------------------------------------------------------------------------------

export const register: Register = (on, options) => {
  const configured = typeof options.loomwrightRoot === 'string' ? options.loomwrightRoot : ''

  // Installed, the module runs in every session; one with no lanes and no pane opened polls once a
  // minute instead of every 15 s (a wave started later is still noticed, and toasts, within a minute).
  let ticks = 0
  let opened = false

  on('session.start', async ($, e, next) => {
    await $.command.register({ name: 'lanes', description: 'Open the live pane of the --parallel lanes (Loomwright lane-status)' })
    void refresh($, configured)
    $.clock.every(POLL_MS, () => {
      ticks += 1
      void (async () => {
        const idle = !opened && ((await read($, snapshot)).doc?.lanes.length ?? 0) === 0
        if (!idle || ticks % IDLE_EVERY === 0) await refresh($, configured)
      })()
    })
    return next(e)
  })

  on('command.run', { command: 'lanes' }, async $ => {
    opened = true
    await refresh($, configured)
    const placed = await $.ui.open({ id: PANE, title: TITLE })
    return { text: placed.isPlaced ? 'Lanes pane opened (refreshes every 15 s).' : 'Lanes refreshed (no surface placed the pane).' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const ui = $.ui.resolve(e)
    const { Box, Text, Button } = ui
    const Input = e.surface !== 'mobile' && 'Input' in ui ? ui.Input : null // the mobile surface has no text field; resolve() returns every element on every surface, so decide by surface, not by the table
    const cols = Math.max(32, e.props.bodyColumns ?? 80)
    const inner = cols - 4 // a lane card's border and padding
    const snap = await read($, snapshot)
    const chosen = await read($, picks)
    const note = await read($, message)
    const notes = await read($, noteDrafts)
    const opened = await read($, open)
    const det = await read($, details)
    const doc = snap.doc

    // Sections. On the desktop a section is a soft tint of its tone and has no border, so the
    // surface's own buttons stand out against it; the terminal, where a background fills whole cells,
    // draws one rounded border in the tone instead. Only the tone carries meaning, never the shape.
    const desk = e.surface === 'desktop'
    const card = (t: Tone, strength: 'soft' | 'strong' = 'soft') =>
      desk
        ? { backgroundColor: tint(t, strength === 'strong' ? 0.16 : 0.08), paddingX: 2, paddingY: 1 }
        : { borderStyle: 'round', borderColor: t ?? 'subtle', paddingX: 1 }
    // A question's options sit on one tray of the page's own color (`inverseText`: white on a light
    // pane, black on a dark one), so the surface's light buttons read as white on the tinted card. A
    // desktop rounds a Box's corners only through its border, so the border is drawn in the same color.
    const tray = desk
      ? ({ borderStyle: 'round', borderColor: 'inverseText', backgroundColor: 'inverseText', paddingX: 1, paddingY: 1 } as const)
      : {}

    // One label column, so every lane's facts line up: "Item    reqs/a.md".
    const LABEL = 9
    const row = (key: string, label: string, value: string, tone?: Tone, wrap = false) => (
      <Box flexDirection="row" key={key}>
        <Box width={LABEL} flexShrink={0}>
          <Text dimColor>{label}</Text>
        </Box>
        <Text color={tone} wrap={wrap ? 'wrap' : 'truncate-end'}>{wrap ? value : clip(value, inner - LABEL)}</Text>
      </Box>
    )

    // The inbox: every lane's pending question in one list, oldest first (what `lane-status --inbox`
    // lists), each answered right here through lane-answer.
    const inboxEntry = (l: LaneRow, q: LaneQuestion) => {
      const mine = chosen[q.id] ?? {}
      const items = q.items ?? []
      const ready = complete(q, mine)
      return (
        <Box key={`${q.id}`} flexDirection="column" marginTop={1} {...card('warning', 'strong')}>
          <Box flexDirection="row" justifyContent="space-between">
            <Text>
              <Text bold>{l.lane}</Text>
              <Text dimColor>{`  ${l.item ? l.item.split('/').slice(-1)[0] : ''}`}</Text>
            </Text>
            <Text color="warning">{waited(q.waiting_s)}</Text>
          </Box>
          {l.state === 'answer_pending' ? (
            <Text color="warning" wrap="wrap">
              An answer is held (the machine was busy); the next /automate --resume delivers it. Sending again replaces it.
            </Text>
          ) : null}
          {items.length === 0 ? (
            <Text wrap="wrap">{`${q.question ?? 'The question could not be read.'} Answer it from the main session with lane-answer.`}</Text>
          ) : null}
          {items.map((it, i) => (
            <Box flexDirection="column" marginTop={1} key={`${q.id}-q${i}`}>
              {it.header ? <Text dimColor>{it.header.toUpperCase()}</Text> : null}
              <Text bold wrap="wrap">{it.question ?? ''}</Text>
              <Text dimColor>{it.multiSelect ? 'Pick one or more' : 'Pick one'}</Text>
              {(() => {
                // A picked option is filled and carries its mark (● ○ pick one, ☑ ☐ pick any);
                // Send stays light until every question is answered. Options without a
                // description sit side by side as chips; described ones stack, text beneath.
                const described = it.options.some(o => !!o.description)
                const button = (o: LaneOption) => {
                  const picked = (mine[String(i)] ?? []).includes(o.label)
                  const mark = it.multiSelect ? (picked ? '☑' : '☐') : picked ? '●' : '○'
                  return (
                    <Button
                      key={`${q.id}:${i}:${o.label}`}
                      variant={picked ? 'primary' : 'secondary'}
                      onPress={() =>
                        update($, picks, all => {
                          const cur = all[q.id]?.[String(i)] ?? []
                          const labels = it.multiSelect
                            ? cur.includes(o.label) ? cur.filter(x => x !== o.label) : [...cur, o.label]
                            : [o.label]
                          return { ...all, [q.id]: { ...(all[q.id] ?? {}), [String(i)]: labels } }
                        })
                      }
                    >
                      {`${mark}  ${o.label}`}
                    </Button>
                  )
                }
                return described ? (
                  <Box flexDirection="column" marginTop={1} rowGap={1} {...tray}>
                    {it.options.map(o => (
                      <Box flexDirection="column" key={`${q.id}-q${i}-${o.label}`}>
                        {button(o)}
                        {o.description ? (
                          <Box paddingLeft={3}>
                            <Text dimColor wrap="wrap">{o.description}</Text>
                          </Box>
                        ) : null}
                      </Box>
                    ))}
                  </Box>
                ) : (
                  <Box flexDirection="row" flexWrap="wrap" marginTop={1} columnGap={1} rowGap={1} {...tray}>
                    {it.options.map(o => button(o))}
                  </Box>
                )
              })()}
            </Box>
          ))}
          {items.length > 0 && Input ? (
            <Box flexDirection="column" marginTop={1}>
              <Text dimColor>Note to the lane (optional; it reads it, it never decides)</Text>
              <Input
                key={`${q.id}:note`}
                placeholder="e.g. prefer the smaller diff"
                value={notes[q.id] ?? ''}
                submitLabel="Keep"
                onInput={(v: string) => update($, noteDrafts, all => ({ ...all, [q.id]: v }))}
                onSubmit={(v: string) => update($, noteDrafts, all => ({ ...all, [q.id]: v }))}
              />
            </Box>
          ) : null}
          {items.length > 0 ? (
            <Box flexDirection="column" marginTop={2}>
              <Box alignSelf="flex-start">
                <Button key={`${q.id}:send`} variant={ready ? 'primary' : 'secondary'} onPress={() => send($, configured, l, q)}>
                  {l.state === 'answer_pending' ? `Replace held answer for ${l.lane}` : `Send answer and resume ${l.lane}`}
                </Button>
              </Box>
              {!ready ? <Text dimColor>Answer every question to send.</Text> : null}
            </Box>
          ) : null}
        </Box>
      )
    }

    if (!snap.at) return <Text dimColor>Reading lane-status…</Text>
    if (!doc) {
      return (
        <Box flexDirection="column" {...card('warning')}>
          <Text bold color="warning">Lane status unavailable</Text>
          <Text wrap="wrap">{snap.error ?? 'No reading yet.'}</Text>
          <Box marginTop={1}>
            <Text dimColor wrap="wrap">The lanes are unaffected. Plain view: lane-status --watch</Text>
          </Box>
        </Box>
      )
    }

    const m = doc.machine
    const hot = m?.state === 'overloaded'
    const asking = waitingCount(doc)
    const age = Math.max(0, Math.round(((await $.clock.now()) - snap.at) / 1000))
    const pending = doc.lanes
      .flatMap(l => l.questions.map(q => ({ l, q })))
      .sort((a, b) => (b.q.waiting_s ?? 0) - (a.q.waiting_s ?? 0))

    return (
      <Box flexDirection="column" gap={1}>
        {/* Header: the run, the counts, the freshness. */}
        <Box flexDirection="column">
          <Box flexDirection="row" justifyContent="space-between">
            <Text bold>{`${doc.lanes.length} lane${doc.lanes.length === 1 ? '' : 's'}`}</Text>
            <Text dimColor>{`updated ${age}s ago`}</Text>
          </Box>
          <Text dimColor wrap="truncate-end">{clip(doc.parent_run_id ?? 'no run', cols)}</Text>
          {asking > 0 ? <Text bold color="warning">{`${asking} waiting for you`}</Text> : null}
        </Box>

        {/* Machine health. */}
        {hot ? (
          <Box flexDirection="column" {...card('error', 'strong')}>
            <Text bold color="error">HIGH-LOAD — machine overloaded</Text>
            <Text wrap="wrap">{`load1 ${m.load1} on ${m.cpus} CPUs · memory ${m.mem_pressure}. New lane launches are held until it eases.`}</Text>
          </Box>
        ) : null}
        <Box flexDirection="column">
          {row('m-load', 'Machine', `${m?.state ?? 'unknown'} · load ${m?.load1 ?? '?'} on ${m?.cpus ?? '?'} CPUs · memory ${m?.mem_pressure ?? '?'}`, hot ? 'error' : m?.state === 'busy' ? 'warning' : undefined)}
          {row('m-awake', 'Awake', m?.keep_awake === 'held' ? 'keep-awake held' : 'keep-awake not held', m?.keep_awake === 'held' ? undefined : 'warning')}
          {doc.keep_awake_suggestion && m?.keep_awake !== 'held' ? row('m-hint', '', `run it yourself: ${doc.keep_awake_suggestion}`, 'subtle') : null}
          {doc.memory_pressure ? row('m-mem', 'Memory', 'pressure — new lane launches are held', 'warning') : null}
        </Box>

        {snap.error ? (
          <Text color="warning" wrap="wrap">{`The last read failed, showing the one before: ${snap.error}`}</Text>
        ) : null}
        {doc.lanes.length === 0 ? <Text dimColor wrap="wrap">No lanes yet. A wave started with /automate --parallel shows up here.</Text> : null}

        {/* Inbox: everything waiting for you, oldest first. */}
        {doc.lanes.length > 0 ? (
          <Box flexDirection="column">
            <Box flexDirection="row" justifyContent="space-between">
              <Text bold>Inbox</Text>
              <Text color={asking > 0 ? 'warning' : 'success'} bold={asking > 0}>
                {asking > 0 ? `${pending.length} question${pending.length === 1 ? '' : 's'} waiting` : 'nothing waiting'}
              </Text>
            </Box>
            {pending.length === 0 ? <Text dimColor>No lane is waiting for you.</Text> : null}
            {pending.map(({ l, q }) => inboxEntry(l, q))}
            {note.text ? (
              <Box flexDirection="column" marginTop={1} {...card(note.ok ? 'success' : 'warning')}>
                <Text bold color={note.ok ? 'success' : 'warning'}>{note.ok ? 'Sent' : 'Not sent'}</Text>
                <Text wrap="wrap">{note.text}</Text>
              </Box>
            ) : null}
          </Box>
        ) : null}

        {/* One card per lane. */}
        {doc.lanes.map(l => (
          <Box key={`lane-${l.lane}`} flexDirection="column" {...card(tone(l))}>
            <Box flexDirection="row" justifyContent="space-between">
              <Text>
                <Text bold>{l.lane}</Text>
                <Text>{'  '}</Text>
                <Text bold color={tone(l)}>{`${glyph(l)} ${label(l)}`}</Text>
              </Text>
              {l.pr ? <Text dimColor>{prRef(l.pr)}</Text> : null}
            </Box>
            {l.reason && !WAITING.has(l.state) ? <Text dimColor wrap="wrap">{l.reason}</Text> : null}

            <Box flexDirection="column" marginTop={1}>
              {row(`${l.lane}-item`, 'Item', l.item ? l.item.split('/').slice(-2).join('/') : '—')}
              {row(`${l.lane}-branch`, 'Branch', l.branch ?? '—')}
              {l.readiness ? row(`${l.lane}-ready`, 'Ready', isReady(l) ? `${l.readiness.score} ✓` : l.readiness.summary, isReady(l) ? 'success' : 'warning') : null}
              {l.ci_slot?.state === 'waiting' ? row(`${l.lane}-ci`, 'CI slot', `waiting · position ${l.ci_slot.position}`) : null}
              {l.ci_slot?.state === 'holding' ? row(`${l.lane}-ci`, 'CI slot', 'running its checks') : null}
              {l.held_for_load ? row(`${l.lane}-held`, 'Held', l.held_for_load, 'warning') : null}
              {l.questions.length > 0
                ? row(`${l.lane}-q`, 'Question', `waiting ${waited(Math.max(...l.questions.map(q => q.waiting_s ?? 0)))} · answer it in the Inbox`, 'warning')
                : null}
              {l.policy ? row(`${l.lane}-policy`, 'Policy', `${l.policy.answered} answered automatically · last ${l.policy.last_gate ?? '?'} → ${l.policy.last_label}`) : null}
              {l.last_progress ? row(`${l.lane}-prog`, 'Progress', l.last_progress.replace(/^- /, '').replace(/^\d{4}-\d{2}-\d{2}T[\d:]+Z\s+/, ''), undefined, true) : null}
            </Box>

            {l.last_message ? (
              <Box flexDirection="column" marginTop={1}>
                <Text dimColor>Latest message</Text>
                <Text italic wrap="wrap">{clip(l.last_message, inner * 3)}</Text>
              </Box>
            ) : null}

            {(opened[l.lane] ? det[l.lane] ?? ['loading…'] : l.last_actions).length > 0 ? (
              <Box flexDirection="column" marginTop={1}>
                <Text dimColor>{opened[l.lane] ? `Last ${DETAIL_STEPS} steps` : 'Last actions'}</Text>
                {(opened[l.lane] ? det[l.lane] ?? ['loading…'] : l.last_actions).map((a, i) => (
                  <Text dimColor wrap="truncate-end" key={`${l.lane}-a${i}`}>{clip(`· ${a}`, inner)}</Text>
                ))}
              </Box>
            ) : null}
            <Box marginTop={1}>
              <Button
                key={`${l.lane}:details`}
                variant="secondary"
                onPress={async () => {
                  const now = !(await read($, open))[l.lane]
                  await update($, open, all => ({ ...all, [l.lane]: now }))
                  if (now) await loadDetails($, configured, l)
                }}
              >
                {opened[l.lane] ? 'Hide steps' : `Show last ${DETAIL_STEPS} steps`}
              </Button>
            </Box>

          </Box>
        ))}

        <Box flexDirection="row" alignItems="center" columnGap={2}>
          <Text dimColor>{`Refreshes every ${POLL_MS / 1000} s`}</Text>
          <Button key="refresh" variant="secondary" onPress={() => refresh($, configured)}>
            ↻ Refresh now
          </Button>
        </Box>
      </Box>
    )
  })
}
