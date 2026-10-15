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

import type { LaneNote, LaneOption, LanePicks, LaneQuestion, LaneRow, LaneSnapshot, LaneStatusDoc, LaneStep, LaneStepState } from '../types'

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
const loads = atom({ plugin: 'loomwright-lanes', key: 'loads' } as const, [] as number[])
const awake = atom({ plugin: 'loomwright-lanes', key: 'awake' } as const, { text: '', ok: true } as LaneNote)
const working = atom({ plugin: 'loomwright-lanes', key: 'working' } as const, {} as Record<string, boolean>)
const LOAD_SAMPLES = 40 // 10 minutes of 15 s reads

type LaneCommand = 'lane-status' | 'lane-feed' | 'lane-answer'
type Ran = { ok: boolean; out: string }

// ---- reaching Loomwright ---------------------------------------------------------------------------

// The located script, remembered with the loomwrightRoot it was located for: a lookup made for one
// configured value is never reused for another (a found path only; "not found" is asked again).
let located: { for: string; path: string } | null = null

/** automate-lanes.sh of the configured folder, else of the installed loomwright plugin; null when neither. */
async function locate($: EngineInterface, configured: string): Promise<string | null> {
  if (located && located.for === configured) return located.path
  located = null
  if (configured.trim() !== '') {
    located = { for: configured, path: `${configured.trim().replace(/\/+$/, '')}/scripts/automate-lanes.sh` }
    return located.path
  }
  try {
    const r = await $.process.run(['claude', 'plugin', 'list', '--json'], { timeoutMs: 30_000 })
    if (r.exitCode !== 0) return null
    const list = JSON.parse(r.stdout) as Array<{ id?: string; enabled?: boolean; installPath?: string }>
    const lw = list.find(p => (p.id ?? '').startsWith('loomwright@') && p.enabled !== false && p.installPath)
    if (lw?.installPath) located = { for: configured, path: `${lw.installPath}/scripts/automate-lanes.sh` }
  } catch {
    // an unreadable plugin list: not found, asked again on the next call
  }
  return located ? located.path : null
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
/** Parked for the owner's merge: one name everywhere, "ready to merge", in the ready (success) tone — ◆ is kept for a question. */
const PARKED = new Set(['ready_for_release', 'awaiting_merge'])
const TROUBLE = new Set(['stalled', 'died', 'lost_to_reset', 'missing', 'blocked_launch', 'gone', 'escalated', 'failed', 'rate_limit', 'drain_died', 'abandoned'])

/** Its item landed: merged, or closed out (and removed) as done. */
function landed(l: LaneRow): boolean {
  return l.state === 'merged' || l.state === 'done' || l.outcome === 'done'
}

/** No longer part of the work: landed, or taken out of the wave (removed, abandoned). Drawn as one compact row. */
function finished(l: LaneRow): boolean {
  return landed(l) || l.state === 'removed' || l.state === 'abandoned'
}

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
/** The tones as RGB, so tints and the load chart draw from ONE table (the host's tones, by eye). */
const RGB: Record<string, string> = {
  success: '22, 163, 74',
  error: '220, 38, 38',
  warning: '217, 119, 6',
  suggestion: '37, 99, 235',
  subtle: '120, 120, 120',
}
/** Wash strengths, named once: a card's soft and strong tint, a tile, and the step bar's track, done and current fills. */
const WASH = { soft: 0.08, strong: 0.16, tile: 0.07, track: 0.22, done: 0.8, lit: 0.95 } as const
function tint(t: Tone, alpha: number): string {
  return `rgba(${RGB[t ?? 'subtle']}, ${alpha})`
}

/** The state in words: `awaiting_input` reads "waiting for you". */
function label(l: LaneRow): string {
  if (l.state === 'awaiting_input') return 'waiting for you'
  if (l.state === 'answer_pending') return 'answer held'
  if (PARKED.has(l.state)) return 'ready to merge'
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

/** Action lines as read: a home folder as `~`, and a line repeated in a row folded into one `(×3)`. */
function tidy(lines: string[]): string[] {
  const out: Array<{ text: string; n: number }> = []
  for (const raw of lines) {
    const text = raw.replace(/\/(?:Users|home)\/[^/\s]+/g, '~')
    const last = out[out.length - 1]
    if (last && last.text === text) last.n += 1
    else out.push({ text, n: 1 })
  }
  return out.map(x => (x.n > 1 ? `${x.text}  (×${x.n})` : x.text))
}

function waitingCount(doc: LaneStatusDoc): number {
  return doc.lanes.filter(l => l.questions.length > 0).length
}

async function feed($: EngineInterface, configured: string, l: LaneRow): Promise<string[]> {
  const r = await lane($, configured, 'lane-feed', [l.path])
  const lines = r.out.split('\n').filter(x => x.trim() !== '')
  return r.ok ? lines.slice(-DETAIL_STEPS) : [`(details unavailable: ${clip(r.out, 200)})`]
}

async function loadDetails($: EngineInterface, configured: string, l: LaneRow): Promise<void> {
  const lines = await feed($, configured, l)
  await update($, details, all => ({ ...all, [l.lane]: lines }))
}

// A press's work in flight. The claim is a module Set, taken and checked in one synchronous step: a
// guard that first awaited a state read let two presses in the same instant both pass it (two
// lane-answer calls). The `working` state only mirrors it, so the button can read "…ing".
const claimed = new Set<string>()

/** Runs `work` unless the same key's work is already running; the button says so meanwhile. */
async function exclusive($: EngineInterface, key: string, work: () => Promise<void>): Promise<void> {
  if (claimed.has(key)) return
  claimed.add(key)
  try {
    await update($, working, all => ({ ...all, [key]: true }))
    await work()
  } finally {
    claimed.delete(key)
    await update($, working, all => Object.fromEntries(Object.entries(all).filter(([k]) => k !== key)))
  }
}

// One read at a time, and none lost: a refresh asked for while one runs (a press's re-read landing on a
// 15 s poll) runs once more after it, and its caller waits for that — dropping it left an answered
// question on screen until the next poll, inviting a second Send that lane-answer then refuses.
let reading: Promise<void> | null = null
let again = false

function refresh($: EngineInterface, configured: string): Promise<void> {
  if (reading) {
    again = true
    return reading
  }
  reading = (async () => {
    try {
      do {
        again = false
        await readOnce($, configured)
      } while (again)
    } finally {
      reading = null
    }
  })()
  return reading
}

async function readOnce($: EngineInterface, configured: string): Promise<void> {
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
  const l1 = Number(doc.machine?.load1)
  if (Number.isFinite(l1)) await update($, loads, all => [...all, l1].slice(-LOAD_SAMPLES))

  const running = doc.lanes.filter(l => l.state === 'running').length
  const asking = waitingCount(doc)
  const hot = doc.machine?.state === 'overloaded'
  const done = doc.lanes.filter(landed).length
  $.ui.status(
    doc.lanes.length === 0
      ? undefined
      : `lanes: ${running} running${asking ? ` · ${asking} waiting for you` : ''}${done ? ` · ${done} done` : ''}${hot ? ' · HIGH-LOAD' : ''}`,
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

  // Every open lane's feed in one write: each state write redraws the pane, so a poll writes as
  // few times as it can.
  const opened = await read($, open)
  const fresh: Record<string, string[]> = {}
  for (const l of doc.lanes) if (opened[l.lane]) fresh[l.lane] = await feed($, configured, l)
  if (Object.keys(fresh).length > 0) await update($, details, all => ({ ...all, ...fresh }))
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
  const key = `send:${q.id}`
  if (claimed.has(key)) return // already sending: a second press would only be refused
  const mine = (await read($, picks))[q.id] ?? {}
  if (!complete(q, mine)) {
    await update($, message, () => ({ text: `${l.lane}: pick an option for every question first.`, ok: false }))
    return
  }
  await exclusive($, key, () => deliver($, configured, l, q, mine))
}

async function deliver($: EngineInterface, configured: string, l: LaneRow, q: LaneQuestion, mine: Record<string, string[]>): Promise<void> {
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
  // lane-answer's words, verbatim — its refusal text included. "Already answered" is the race with the
  // main session (lane-wait relays the same question there): the lane has its answer, so say that.
  const taken = !r.ok && /already answered/.test(r.out)
  await update($, message, () => ({
    text: taken
      ? `${l.lane}: this question was already answered (from the main session, most likely) — nothing was sent twice. (${clip(r.out, 200)})`
      : `${l.lane}: ${r.out || (r.ok ? 'answered' : 'lane-answer failed')}`,
    ok: r.ok,
  }))
  if (r.ok || taken) {
    await update($, picks, all => Object.fromEntries(Object.entries(all).filter(([id]) => id !== q.id)))
    await update($, noteDrafts, all => Object.fromEntries(Object.entries(all).filter(([id]) => id !== q.id)))
  }
  await refresh($, configured)
}

// ---- keeping the machine awake -----------------------------------------------------------------------------

/** The owner's press: `lane-status --keep-awake` starts `caffeinate -i -w <this session>` (macOS only, and
 *  only when no caffeinate holds already); it ends with the session. The desktop app's own keep-awake
 *  holds only while a Code session works, and lanes are not Code sessions, so it can drop mid-wave. */
async function keepAwake($: EngineInterface, configured: string): Promise<void> {
  await exclusive($, 'awake', async () => {
    const r = await lane($, configured, 'lane-status', ['--keep-awake'])
    const said = r.out.split('\n').find(x => x.startsWith('keep-awake:')) ?? clip(r.out || 'lane-status --keep-awake said nothing', 300)
    await update($, awake, () => ({ text: said, ok: r.ok && !/not started/.test(said) }))
    await refresh($, configured)
  })
}

/** The owner's Refresh now: the same read, with its button saying so while it runs. */
async function refreshNow($: EngineInterface, configured: string): Promise<void> {
  await exclusive($, 'refresh', () => refresh($, configured))
}

// ---- time and the step rail ---------------------------------------------------------------------------------

/** "25 s", "4 min", "1 h 34 min". */
function span(s: number | null | undefined): string {
  if (s === null || s === undefined || !Number.isFinite(s)) return ''
  const t = Math.max(0, Math.round(s))
  if (t < 60) return `${t} s`
  const m = Math.floor(t / 60)
  return m < 60 ? `${m} min` : `${Math.floor(m / 60)} h ${m % 60} min`
}

/** An ISO UTC time as the machine's local "18:22" (lane-status gives the offset; the sandbox has no zone). */
function clock(iso: string | null | undefined, offset: number | null | undefined): string {
  const ms = iso ? Date.parse(iso) : NaN
  if (!Number.isFinite(ms)) return ''
  const t = (((Math.floor(ms / 1000) + (offset ?? 0)) % 86400) + 86400) % 86400
  const hh = String(Math.floor(t / 3600)).padStart(2, '0')
  const mm = String(Math.floor((t % 3600) / 60)).padStart(2, '0')
  return `${hh}:${mm}${offset === null || offset === undefined ? ' UTC' : ''}`
}

/** Seconds since an ISO time, at `now` (ms). */
function since(iso: string | null | undefined, now: number): number | null {
  const ms = iso ? Date.parse(iso) : NaN
  return Number.isFinite(ms) ? Math.max(0, (now - ms) / 1000) : null
}

/** An item path as a short name: `reqs/2026-10-14-094202-adapter.md` reads `adapter`. */
function itemName(item: string): string {
  return (item.split('/').pop() ?? item).replace(/\.md$/, '').replace(/^\d{4}-\d{2}-\d{2}-\d{6}-/, '')
}

/** The lane header's clock: "2 h 5 min" running, or "ran 53 min" frozen at `ended_at` once it stopped working. */
function ranFor(l: LaneRow, started: string, now: number): string {
  const end = l.ended_at ? Date.parse(l.ended_at) : NaN
  return Number.isFinite(end) ? `ran ${span(since(started, end))}` : span(since(started, now))
}

const STEP_TONE: Record<LaneStepState, Tone> = {
  done: 'success', active: 'suggestion', waiting: 'warning', held: 'subtle', trouble: 'error', pending: 'subtle',
}
const STEP_MARK: Record<LaneStepState, string> = { done: '✓', active: '●', waiting: '◆', held: '⏸', trouble: '✕', pending: '' }
const STEP_WORD: Record<LaneStepState, string> = {
  done: 'done', active: 'now', waiting: 'waiting for you', held: 'held', trouble: 'stopped', pending: 'pending',
}
/** What each step is, for a step that has no line of its own yet. */
const STEP_ABOUT: Record<string, string> = {
  pick: 'take the item from the lane backlog',
  plan: 'Launch Pad: brief + Plan Review',
  build: 'Supervisor: preflight, execute, open the PR',
  heal: 'Phase 4.5 integration review and fixes',
  drain: 'review → fix → re-review until mergeable',
  decide: 'your call on dismissed findings',
  merge: 'park, merge, close out',
}

/** A load sparkline in block characters (the terminal's; remote surfaces draw an Svg). */
function blocks(xs: number[], top: number): string {
  const bars = '▁▂▃▄▅▆▇█'
  return xs.map(x => bars[Math.min(7, Math.max(0, Math.round((x / Math.max(top, 0.01)) * 7)))]).join('')
}

/** One rail segment on a remote surface. The seven sit flush, so they read as ONE bar: only the first and
 *  last round their outer ends, a 2-unit notch parts neighbours, and the current step is drawn taller so
 *  it is found without color. Stretched to its slot (about as wide as the viewBox, so the ends stay round). */
const BAR_PX = 10
function segSvg(fill: string, first: boolean, last: boolean, tall: boolean): string {
  const w = 100, y = tall ? 0 : 2, h = tall ? BAR_PX : BAR_PX - 4, r = h / 2, x1 = last ? w : w - 2
  const d = [
    `M${first ? r : 0},${y}`, `H${last ? x1 - r : x1}`,
    last ? `A${r},${r} 0 0 1 ${x1 - r},${y + h}` : `V${y + h}`,
    `H${first ? r : 0}`,
    first ? `A${r},${r} 0 0 1 ${r},${y}` : `V${y}`, 'Z',
  ].join(' ')
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${BAR_PX}" width="${w}" height="${BAR_PX}" preserveAspectRatio="none">`
    + `<path d="${d}" fill="${fill}"/></svg>`
}

/** The same trend as an SVG: the load line, and the CPU count as a dashed ceiling. */
function sparkSvg(xs: number[], cpus: number): string {
  const w = 160, h = 34, top = Math.max(cpus, ...xs, 1) * 1.1
  const pts = xs.map((x, i) => `${xs.length < 2 ? w : ((i / (xs.length - 1)) * w).toFixed(1)},${(h - 2 - (x / top) * (h - 4)).toFixed(1)}`).join(' ')
  const cy = (h - 2 - (cpus / top) * (h - 4)).toFixed(1)
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" width="${w}" height="${h}">`
    + (cpus > 0 ? `<line x1="0" x2="${w}" y1="${cy}" y2="${cy}" stroke="rgb(${RGB.error})" stroke-width="1" stroke-dasharray="3 3" opacity="0.7"/>` : '')
    + `<polyline fill="none" stroke="rgb(${RGB.suggestion})" stroke-width="2" stroke-linejoin="round" points="${pts}"/>`
    + `</svg>`
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
    const { Box, Text, Button, Link } = ui
    const Input = e.surface !== 'mobile' && 'Input' in ui ? ui.Input : null // the mobile surface has no text field; resolve() returns every element on every surface, so decide by surface, not by the table
    const cols = Math.max(32, e.props.bodyColumns ?? 80)
    const inner = cols - 4 // a lane card's border and padding
    const snap = await read($, snapshot)
    const chosen = await read($, picks)
    const note = await read($, message)
    const notes = await read($, noteDrafts)
    const opened = await read($, open)
    const det = await read($, details)
    const busyNow = await read($, working)
    const doc = snap.doc

    // Sections. On the desktop a section is a soft tint of its tone and has no border, so the
    // surface's own buttons stand out against it; the terminal, where a background fills whole cells,
    // draws one rounded border in the tone instead. Only the tone carries meaning, never the shape.
    const desk = e.surface === 'desktop'
    const card = (t: Tone, strength: 'soft' | 'strong' = 'soft') =>
      desk
        ? { backgroundColor: tint(t, strength === 'strong' ? WASH.strong : WASH.soft), paddingX: 2, paddingY: 1 }
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
      const sending = !!busyNow[`send:${q.id}`]
      return (
        <Box key={`${q.id}`} flexDirection="column" marginTop={1} {...card('warning', 'strong')}>
          <Box flexDirection="row" justifyContent="space-between">
            <Text>
              <Text bold>{l.lane}</Text>
              <Text dimColor>{`  ${l.item ? itemName(l.item) : ''}`}</Text>
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
              <Text wrap="wrap">
                {it.header ? <Text dimColor>{`${it.header} · `}</Text> : null}
                <Text bold>{it.question ?? ''}</Text>
              </Text>
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
                      dimColor={sending && !picked}
                      onPress={() =>
                        sending ? undefined : update($, picks, all => {
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
              <Input
                key={`${q.id}:note`}
                label="Note"
                placeholder="optional; guidance, not an answer"
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
                <Button key={`${q.id}:send`} variant={ready && !sending ? 'primary' : 'secondary'} dimColor={!ready && !sending} onPress={() => send($, configured, l, q)}>
                  {sending
                    ? `⏳ Sending — resuming ${l.lane}…`
                    : l.state === 'answer_pending' ? `Replace held answer for ${l.lane}` : `Send answer and resume ${l.lane}`}
                </Button>
              </Box>
              {sending ? (
                <Text dimColor wrap="wrap">lane-answer is checking the answer and resuming the lane; this takes a few seconds.</Text>
              ) : !ready ? (
                <Text dimColor>Answer every question to send.</Text>
              ) : null}
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
    const now = await $.clock.now()
    const age = Math.max(0, Math.round((now - snap.at) / 1000))
    const off = doc.utc_offset_s ?? null
    const hist = await read($, loads)
    const awakeNote = await read($, awake)
    const Svg = e.surface !== 'terminal' && 'Svg' in ui ? ui.Svg : null
    const waves = (doc.waves ?? []).filter(w => /^https:\/\//.test(w.pr))
    const next = doc.next_wave && doc.next_wave.lanes.length > 0 ? doc.next_wave : null
    const nextLanes = next ? doc.lanes.filter(l => next.lanes.includes(l.lane)) : []
    const nextOf = (pred: (l: LaneRow) => boolean) => nextLanes.filter(pred).length
    const nextAsk = nextOf(l => WAITING.has(l.state))
    const nextBad = nextOf(l => TROUBLE.has(l.state))
    const nextPark = nextOf(l => ['ready_for_release', 'awaiting_merge'].includes(l.state))
    const nextWord = nextLanes.length > 0 && nextPark + nextOf(landed) === nextLanes.length ? 'ready to build' : 'in progress'
    const nextSplit = [
      nextOf(l => l.state === 'running') ? `${nextOf(l => l.state === 'running')} running` : '',
      nextAsk ? `${nextAsk} waiting for you` : '',
      nextPark ? `${nextPark} parked` : '',
      nextBad ? `${nextBad} stopped` : '',
    ].filter(Boolean).join(' · ')
    const waveOf = (l: LaneRow) => waves.find(w => (w.lanes ?? []).includes(l.lane))?.wave ?? null
    const live = doc.lanes.filter(l => !finished(l))
    const closed = doc.lanes.filter(finished)
    const pending = doc.lanes
      .flatMap(l => l.questions.map(q => ({ l, q })))
      .sort((a, b) => (b.q.waiting_s ?? 0) - (a.q.waiting_s ?? 0))

    // Header tiles: when the wave started, its lanes, the machine's load, and keep-awake.
    const tileStyle = desk
      ? { backgroundColor: tint('subtle', WASH.tile), paddingX: 2, paddingY: 1 }
      : { borderStyle: 'round', borderColor: 'subtle', paddingX: 1 }
    const tile = (key: string, title: string, body: JSX.Element[]) => (
      <Box key={key} flexDirection="column" flexGrow={1} minWidth={24} {...tileStyle}>
        <Text dimColor>{title}</Text>
        {body}
      </Box>
    )
    const cpus = Number(m?.cpus)
    const holders = m?.keep_awake_holders ?? []
    // An older Loomwright reports no `keep_awake_lasting`; its `held` meant a caffeinate.
    const lasting = m?.keep_awake_lasting ?? m?.keep_awake === 'held'
    const caff = holders.find(h => h.kind === 'caffeinate')
    const [awakeWord, awakeTone, awakeSub]: [string, Tone, string] = lasting
      ? ['caffeinate holds it', 'success', caff?.pid ? `pid ${caff.pid} · ends with its session` : 'lasts the wave']
      : holders.some(h => h.kind === 'claude-app')
        ? ['Claude app only', 'warning', 'drops when no Code session works']
        : ['not held', 'warning', 'the machine may idle-sleep']

    // A parked lane is ready, not asking (success, ●, never the ◆ a question uses). In a wave the owner merges
    // the WAVE PR, never the lane's, so there it reads "parked for wave N"; outside a wave, "ready to merge".
    const waveNo = (l: LaneRow) => waveOf(l) ?? (next && next.lanes.includes(l.lane) ? next.wave : null)
    const parkedWord = (l: LaneRow) => (waveNo(l) !== null ? `parked for wave ${waveNo(l)}` : 'ready to merge')
    const stepTone = (l: LaneRow, st: LaneStep): Tone => (st.state === 'waiting' && PARKED.has(l.state) ? 'success' : STEP_TONE[st.state])
    const stepMark = (l: LaneRow, st: LaneStep) => (st.state === 'waiting' && PARKED.has(l.state) ? '●' : STEP_MARK[st.state])
    const stepWord = (l: LaneRow, st: LaneStep) => (st.state === 'waiting' && PARKED.has(l.state) ? parkedWord(l) : STEP_WORD[st.state])

    /** A step's times in words: "since 13:24 · 59 min so far", "13:22 → 13:23 · 40 s", or what a pending step does. */
    const stepWhen = (st: LaneStep): string => {
      const lit = st.state !== 'done' && st.state !== 'pending'
      const went = lit ? since(st.started_at, now) : st.duration_s
      return st.state === 'pending'
        ? STEP_ABOUT[st.id] ?? ''
        : !st.started_at
          ? 'no time recorded for this step'
          : lit
            ? `since ${clock(st.started_at, off)} · ${span(went)} so far`
            : `${clock(st.started_at, off)} → ${clock(st.ended_at, off) || '…'}${went !== null ? ` · ${span(went)}` : ''}`
    }

    // The step rail: ONE continuous bar in seven flush segments, colored by state — done green, the current
    // step its state's color and drawn taller, the rest a faint track — then one line naming the current
    // step, its place and time, and what comes next. Each segment is a hover scope whose card (times, its
    // last lines, Supervisor phases for Build) shows under the pointer.
    const rail = (l: LaneRow) => {
      const steps = l.timeline?.steps ?? []
      if (steps.length === 0) return null
      const segW = Math.max(2, Math.floor(inner / steps.length))
      const cardW = Math.min(44, inner)
      const curIx = steps.findIndex(st => st.state !== 'done' && st.state !== 'pending')
      const cur = curIx >= 0 ? steps[curIx] : null
      const after = curIx >= 0 ? steps[curIx + 1] ?? null : null
      const curFor = cur?.started_at ? span(since(cur.started_at, now)) : ''
      const summary = cur
        ? `step ${curIx + 1} of ${steps.length}${curFor ? ` · ${curFor}` : ''}`
        : `all ${steps.length} steps done`
      const alt = cur
        ? `Step ${curIx + 1} of ${steps.length}, ${cur.name}, ${stepWord(l, cur)}`
        : `All ${steps.length} steps done`
      return (
        <Box flexDirection="column" marginTop={1}>
          <Box flexDirection="row" columnGap={0}>
            {steps.map((st: LaneStep, i: number) => {
              const t = stepTone(l, st)
              const lit = st.state !== 'done' && st.state !== 'pending'
              const fill = st.state === 'pending' ? tint('subtle', WASH.track) : st.state === 'done' ? tint('success', WASH.done) : tint(t, WASH.lit)
              const when = stepWhen(st)
              const tl = l.timeline
              const sup = st.id === 'build' && tl && (tl.phase || tl.phases.length > 0)
                ? [...tl.phases.map(p => `${p.phase} ${clock(p.at, off)}`), ...(lit && tl.phase ? [`${tl.phase} now`] : [])].join(' · ')
                : ''
              return (
                <Box key={`${l.lane}-step-${st.id}`} flexDirection="column" width={segW} flexGrow={1}>
                  {Svg ? (
                    <Svg
                      source={segSvg(fill, i === 0, i === steps.length - 1, lit)}
                      alt={i === 0 ? alt : `${st.name}: ${stepWord(l, st)}`}
                      height={BAR_PX}
                    />
                  ) : (
                    <Text color={st.state === 'pending' ? undefined : t} dimColor={st.state === 'pending'} bold={lit} wrap="truncate-end">
                      {(st.state === 'pending' ? '─' : '━').repeat(segW)}
                    </Text>
                  )}
                  <Box
                    position="absolute"
                    top={1}
                    {...(i >= Math.ceil(steps.length / 2) ? { right: 0 } : { left: 0 })}
                    width={cardW}
                    display="none"
                    hover={{ display: 'flex' }}
                    flexDirection="column"
                    backgroundColor="inverseText"
                    borderStyle="round"
                    borderColor={lit ? t ?? 'subtle' : 'subtle'}
                    paddingX={desk ? 2 : 1}
                    paddingY={desk ? 1 : 0}
                  >
                    <Text bold color={lit ? t : undefined}>{`${st.name} · ${stepWord(l, st)}`}</Text>
                    <Text dimColor wrap="wrap">{when}</Text>
                    {sup ? <Text dimColor wrap="wrap">{`Supervisor: ${sup}`}</Text> : null}
                    {st.lines.slice(-3).map((x, k) => (
                      <Text key={`${l.lane}-${st.id}-l${k}`} wrap="wrap">{`· ${clip(x, 160)}`}</Text>
                    ))}
                  </Box>
                </Box>
              )
            })}
          </Box>
          <Box flexDirection="row" justifyContent="space-between" marginTop={desk ? 1 : 0}>
            <Text color={cur ? stepTone(l, cur) : 'success'} bold wrap="truncate-end">{summary}</Text>
            {after ? <Text dimColor wrap="truncate-end">{`next: ${after.name}`}</Text> : null}
          </Box>
        </Box>
      )
    }

    return (
      <Box flexDirection="column" gap={1}>
        {/* Header: the run, how long it has run, and the freshness. */}
        <Box flexDirection="column">
          <Box flexDirection="row" justifyContent="space-between">
            <Text>
              <Text bold>Run</Text>
              <Text dimColor>{`  ${clip(doc.parent_run_id ?? 'no run', Math.max(8, cols - 24))}`}</Text>
            </Text>
            <Text dimColor>{`updated ${age} s ago`}</Text>
          </Box>
          <Text dimColor>
            {doc.run_started_at ? `started ${clock(doc.run_started_at, off)} · running ${span(since(doc.run_started_at, now))}` : 'start not recorded'}
          </Text>
        </Box>

        {hot ? (
          <Box flexDirection="column" {...card('error', 'strong')}>
            <Text bold color="error">HIGH-LOAD — machine overloaded</Text>
            <Text wrap="wrap">{`load1 ${m.load1} on ${m.cpus} CPUs · memory ${m.mem_pressure}. New lane launches are held until it eases.`}</Text>
          </Box>
        ) : null}
        {doc.memory_pressure ? <Text color="warning" wrap="wrap">Memory pressure — new lane launches are held.</Text> : null}

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
            {pending.map(({ l, q }) => inboxEntry(l, q))}
            {note.text ? (
              <Box flexDirection="column" marginTop={1} {...card(note.ok ? 'success' : 'warning')}>
                <Text bold color={note.ok ? 'success' : 'warning'}>{note.ok ? 'Sent' : 'Not sent'}</Text>
                <Text wrap="wrap">{note.text}</Text>
              </Box>
            ) : null}
          </Box>
        ) : null}

        {/* Waves, oldest first: each built wave's PR and whether it landed, then the wave being worked now. */}
        {waves.length > 0 || next ? (
          <Box flexDirection="column" {...card(next ? 'suggestion' : waves.some(w => w.state === 'open') ? 'warning' : 'success')}>
            {waves.map(w => (
              <Box key={`wave-${w.pr}`} flexDirection="column">
                <Box flexDirection="row" columnGap={1} flexWrap="wrap">
                  <Text bold>{w.wave !== null ? `Wave ${w.wave}` : 'Wave'}</Text>
                  {w.state === 'merged' ? <Text color="success" bold>merged ✓</Text> : null}
                  {w.state === 'open' ? <Text color="warning" bold>ready to merge</Text> : null}
                  <Link key={`wave-pr-${w.pr}`} href={w.pr}>{prRef(w.pr)}</Link>
                </Box>
                <Text dimColor wrap="truncate-end">
                  {[w.lanes?.length ? w.lanes.join(' ') : w.branch, w.built_at ? `built ${clock(w.built_at, off)}` : ''].filter(Boolean).join(' · ')}
                </Text>
              </Box>
            ))}
            {next ? (
              <Box key="wave-next" flexDirection="column">
                <Box flexDirection="row" columnGap={1} flexWrap="wrap">
                  <Text bold>{`Wave ${next.wave}`}</Text>
                  <Text color={nextAsk ? 'warning' : nextBad ? 'error' : 'suggestion'} bold>{nextWord}</Text>
                </Box>
                <Text dimColor wrap="truncate-end">{[next.lanes.join(' '), nextSplit].filter(Boolean).join(' · ')}</Text>
              </Box>
            ) : null}
          </Box>
        ) : null}

        {/* The machine: load and keep-awake. */}
        <Box flexDirection="row" flexWrap="wrap" columnGap={1} rowGap={1}>
          {tile('t-load', `Load · ${m?.state ?? 'unknown'}`, [
            hist.length > 1
              ? Svg
                ? <Svg key="t-load-svg" source={sparkSvg(hist, Number.isFinite(cpus) ? cpus : 0)} alt={`Load ${m?.load1 ?? 'unknown'} of ${m?.cpus ?? '?'} CPUs over the last ${hist.length} reads; the dashed line marks the CPU count`} width={160} height={34} />
                : <Text key="t-load-bars" color="suggestion">{blocks(hist, Math.max(Number.isFinite(cpus) ? cpus : 1, ...hist))}</Text>
              : <Text key="t-load-wait" dimColor>trend after the next read</Text>,
            <Text key="t-load-now" wrap="wrap">
              <Text bold color={hot ? 'error' : m?.state === 'busy' ? 'warning' : undefined}>{`${m?.load1 ?? '?'}`}</Text>
              <Text dimColor>{` on ${m?.cpus ?? '?'} CPUs${Svg && hist.length > 1 ? ' (dashed)' : ''} · memory ${m?.mem_pressure ?? '?'}`}</Text>
            </Text>,
          ])}
          {tile('t-awake', 'Keep awake', [
            <Text key="t-awake-word" bold color={awakeTone}>{awakeWord}</Text>,
            <Text key="t-awake-sub" dimColor wrap="wrap">{awakeSub}</Text>,
            ...(!lasting && doc.keep_awake_suggestion
              ? [
                  <Box key="t-awake-btn" marginTop={1} alignSelf="flex-start">
                    <Button key="keep-awake" variant="secondary" onPress={() => keepAwake($, configured)}>
                      {busyNow.awake ? '⏳ Starting caffeinate…' : 'Keep awake for this wave'}
                    </Button>
                  </Box>,
                ]
              : []),
            ...(awakeNote.text
              ? [<Text key="t-awake-said" color={awakeNote.ok ? 'success' : 'warning'} wrap="wrap">{awakeNote.text.replace(/^keep-awake: /, '')}</Text>]
              : []),
          ])}
        </Box>

        {/* One card per lane still in the work: its step and when it started, the rail, then the facts. */}
        {live.map(l => {
          const tl = l.timeline
          const cur = tl?.steps.find(st => st.state !== 'done' && st.state !== 'pending')
          const headTone = cur ? stepTone(l, cur) : tone(l)
          const head = PARKED.has(l.state)
            ? `● ${parkedWord(l).replace(/^./, c => c.toUpperCase())}`
            : tl?.label
              ? `${cur ? stepMark(l, cur) : '✓'} ${tl.label}${l.state !== 'running' ? ` · ${label(l)}` : ''}`
              : `${glyph(l)} ${label(l)}`
          const started = l.started_at ?? tl?.started_at ?? null
          return (
          <Box key={`lane-${l.lane}`} flexDirection="column" {...card(headTone ?? tone(l))}>
            <Box key={`${l.lane}-head`} flexDirection={inner < 56 ? 'column' : 'row'} justifyContent="space-between">
              <Text>
                <Text bold>{l.lane}</Text>
                <Text>{'  '}</Text>
                <Text bold color={headTone}>{head}</Text>
              </Text>
              <Box flexDirection="row" flexShrink={0}>
                {l.pr && /^https:\/\//.test(l.pr) ? <Link key={`${l.lane}-pr`} href={l.pr}>{prRef(l.pr)}</Link> : null}
                {l.pr && !/^https:\/\//.test(l.pr) ? <Text dimColor>{prRef(l.pr)}</Text> : null}
                {started ? <Text dimColor>{`${l.pr ? ' · ' : ''}started ${clock(started, off)} · ${ranFor(l, started, now)}`}</Text> : null}
              </Box>
            </Box>
            {l.reason && !WAITING.has(l.state) ? <Text dimColor wrap="wrap">{l.reason}</Text> : null}
            {rail(l)}

            <Box flexDirection="column" marginTop={1}>
              {row(`${l.lane}-item`, 'Item', l.item ? itemName(l.item) : '—')}
              {row(`${l.lane}-branch`, 'Branch', l.branch ?? '—')}
              {l.readiness ? row(`${l.lane}-ready`, 'Ready', isReady(l) ? `${l.readiness.score} ✓` : l.readiness.summary, isReady(l) ? 'success' : 'warning') : null}
              {l.ci_slot?.state === 'waiting' ? row(`${l.lane}-ci`, 'CI slot', `waiting · position ${l.ci_slot.position}`) : null}
              {l.ci_slot?.state === 'holding' ? row(`${l.lane}-ci`, 'CI slot', 'running its checks') : null}
              {l.held_for_load ? row(`${l.lane}-held`, 'Held', l.held_for_load, 'warning') : null}
              {l.questions.length > 0
                ? row(`${l.lane}-q`, 'Question', `waiting ${waited(Math.max(...l.questions.map(q => q.waiting_s ?? 0)))} · answer it in the Inbox`, 'warning')
                : null}
              {l.policy ? row(`${l.lane}-policy`, 'Policy', `${l.policy.answered} answered automatically · last ${l.policy.last_gate ?? '?'} → ${l.policy.last_label}`) : null}
              {l.last_progress ? row(`${l.lane}-prog`, 'Last step', l.last_progress.replace(/^- /, '').replace(/^\d{4}-\d{2}-\d{2}T[\d:]+Z\s+/, ''), undefined, true) : null}
            </Box>

            {l.last_message ? (
              <Box flexDirection="column" marginTop={1}>
                <Text dimColor>Latest message</Text>
                <Text wrap="wrap">{clip(l.last_message, inner * 3)}</Text>
              </Box>
            ) : null}

            {opened[l.lane] && tl && tl.steps.length > 0 ? (
              <Box key={`${l.lane}-steps`} flexDirection="column" marginTop={1}>
                <Text dimColor>Steps</Text>
                {tl.steps.map(st => (
                  <Box key={`${l.lane}-steprow-${st.id}`} flexDirection="column">
                    <Text color={st.state === 'pending' ? undefined : stepTone(l, st)} dimColor={st.state === 'pending'} wrap="truncate-end">
                      {clip(`${st.name} · ${stepWord(l, st)} · ${stepWhen(st)}`, inner)}
                    </Text>
                    {st.lines.length > 0 ? <Text dimColor wrap="truncate-end">{clip(`   ${st.lines[st.lines.length - 1]}`, inner)}</Text> : null}
                  </Box>
                ))}
              </Box>
            ) : null}
            {(opened[l.lane] ? det[l.lane] ?? ['loading…'] : l.last_actions).length > 0 ? (
              <Box flexDirection="column" marginTop={1}>
                <Text dimColor>{opened[l.lane] ? `Last ${DETAIL_STEPS} steps` : 'Last actions'}</Text>
                {tidy(opened[l.lane] ? det[l.lane] ?? ['loading…'] : l.last_actions).map((a, i) => (
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
                {opened[l.lane] ? (det[l.lane] ? 'Hide steps' : '⏳ Loading steps…') : `Show last ${DETAIL_STEPS} steps`}
              </Button>
            </Box>
          </Box>
          )
        })}

        {/* Finished lanes, one line each: how it ended, its PR, its wave, when, how long, what. */}
        {closed.length > 0 ? (
          <Box flexDirection="column" {...card('subtle')}>
            <Text>
              <Text bold>{`Finished · ${closed.length}`}</Text>
              <Text dimColor>
                {[
                  closed.filter(landed).length ? `${closed.filter(landed).length} merged` : '',
                  closed.filter(l => l.state === 'abandoned').length ? `${closed.filter(l => l.state === 'abandoned').length} abandoned` : '',
                  closed.filter(l => !landed(l) && l.state === 'removed').length ? `${closed.filter(l => !landed(l) && l.state === 'removed').length} removed` : '',
                ].filter(Boolean).map(x => ` · ${x}`).join('')}
              </Text>
            </Text>
            {closed.map(l => {
              const ok = landed(l)
              const w = waveOf(l)
              const word = ok ? 'done' : l.state === 'abandoned' ? 'abandoned' : 'removed'
              const started = l.started_at ?? l.timeline?.started_at ?? null
              const pr = l.pr ? /\/pull\/(\d+)/.exec(l.pr)?.[1] : undefined
              return (
                <Box key={`done-${l.lane}`} flexDirection="row" columnGap={1} marginTop={1}>
                  <Box key={`done-${l.lane}-head`} flexShrink={0} flexDirection="row" columnGap={1}>
                    <Text bold>{l.lane}</Text>
                    <Text bold color={ok ? 'success' : l.state === 'abandoned' ? 'error' : undefined}>{`${ok ? '✓' : l.state === 'abandoned' ? '✕' : '■'} ${word}`}</Text>
                    {pr && /^https:\/\//.test(l.pr ?? '') ? <Link key={`done-${l.lane}-pr`} href={l.pr ?? ''}>{`#${pr}`}</Link> : null}
                  </Box>
                  <Box flexShrink={1} flexGrow={1} minWidth={0}>
                  <Text dimColor wrap="truncate-end">
                    {[
                      w !== null ? `wave ${w}` : '',
                      l.ended_at ? clock(l.ended_at, off) : '',
                      started && l.ended_at ? `ran ${span(since(started, Date.parse(l.ended_at)))}` : '',
                      l.item ? itemName(l.item) : '',
                    ].filter(Boolean).join(' · ')}
                  </Text>
                  </Box>
                </Box>
              )
            })}
          </Box>
        ) : null}

        <Box flexDirection="row" alignItems="center" columnGap={2}>
          <Text dimColor>{`Refreshes every ${POLL_MS / 1000} s`}</Text>
          <Button key="refresh" variant="secondary" onPress={() => refreshNow($, configured)}>
            {busyNow.refresh ? '⏳ Refreshing…' : '↻ Refresh now'}
          </Button>
        </Box>
      </Box>
    )
  })
}
