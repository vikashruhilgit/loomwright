// The `$.state` contract of loomwright-lanes, and the shape of `lane-status --json` it reads
// (Loomwright's automate-lanes.sh `_lanes_status_doc`, schema_version 1). Nothing here is truth:
// every value is a copy of the last lane-status read, or the person's own unsent picks.

export type LaneOption = { label: string; description: string | null }

export type LaneQuestionItem = {
  question: string | null
  header: string | null
  multiSelect: boolean
  options: LaneOption[]
}

export type LaneQuestion = {
  id: string
  asked_at: string | null
  waiting_s: number | null
  question: string | null
  /** Every question of the call, in order; its index is lane-answer's answer key. */
  items?: LaneQuestionItem[]
}

export type LaneRow = {
  lane: string
  path: string
  item: string | null
  run_id: string
  state: string
  reason: string
  pr: string | null
  pr_state: string | null
  branch?: string | null
  last_progress: string
  last_actions: string[]
  last_message: string
  questions: LaneQuestion[]
  ci_slot: { state: string; position: number | null; held: string | null }
  held_for_load: string | null
  readiness: { score: string; summary: string; file: string } | null
  /** Questions this lane's stamped policy answered on its own, or null. */
  policy?: { answered: number; first_at: string | null; last_at: string | null; last_gate: string | null; last_label: string } | null
  /** When the lane started: its run file's first dated line, else its last launch. */
  started_at?: string | null
  /** The seven-step rail (pick · plan · build · heal · drain · decide · merge), or null. */
  timeline?: LaneTimeline | null
}

/** done · pending, and the current step's state: active, waiting (on the owner), held, trouble. */
export type LaneStepState = 'done' | 'pending' | 'active' | 'waiting' | 'held' | 'trouble'

export type LaneStep = {
  id: string
  name: string
  state: LaneStepState
  started_at: string | null
  ended_at: string | null
  /** Ended − started; for the current step, now − started. */
  duration_s: number | null
  /** The step's last few `## Progress` lines (and Supervisor decisions), oldest first. */
  lines: string[]
}

export type LaneTimeline = {
  started_at: string | null
  current: string | null
  /** The current step's words: "Build · EXECUTE", "Drain · round 2", or "Done". */
  label: string | null
  steps: LaneStep[]
  /** The lane's Supervisor phase now (EXECUTE, SELF_HEAL…) and status, when its state is this item's. */
  phase: string | null
  phase_status: string | null
  /** When each Supervisor phase first logged a decision, oldest first. */
  phases: Array<{ phase: string; at: string }>
}

export type LaneAwakeHolder = { pid: number | null; process: string; assertion: string; name: string; kind: 'caffeinate' | 'claude-app' | 'other' }

export type LaneMachine = {
  state: string
  load1: number | string
  cpus: number | string
  mem_pressure: string
  /** `held` when a caffeinate or the Claude app holds the machine awake now. */
  keep_awake: string
  /** A caffeinate holds it: the one hold that lasts the wave (the app's follows Code-session work). */
  keep_awake_lasting?: boolean
  keep_awake_holders?: LaneAwakeHolder[]
}

export type LaneWave = { wave: number | null; branch: string; pr: string; built_at: string | null }

export type LaneStatusDoc = {
  schema_version: number
  parent_run_id: string | null
  generated_at?: string
  /** The wave's start: the parent run file's first dated line. */
  run_started_at?: string | null
  /** The machine's UTC offset, so local clock times can be shown without a time zone database. */
  utc_offset_s?: number | null
  /** Every wave PR the run opened (wave-build's `## Progress` record), oldest first; absent before 0.3.0's Loomwright. */
  waves?: LaneWave[]
  machine: LaneMachine
  memory_pressure?: boolean
  keep_awake_suggestion?: string | null
  lanes: LaneRow[]
}

/** Unsent picks: question id → answer key → chosen labels. */
export type LanePicks = Record<string, Record<string, string[]>>

/** lane-answer's own words from the last send (its refusal included), and whether it took. */
export type LaneNote = { text: string; ok: boolean }

/** What the pane last read: the document, or why there is none. */
export type LaneSnapshot = { doc: LaneStatusDoc | null; error: string | null; at: number }

declare module 'claude-code' {
  interface PluginState {
    'loomwright-lanes': {
      snapshot: LaneSnapshot
      /** Question ids already announced by a toast. */
      seen: Record<string, boolean>
      picks: LanePicks
      message: LaneNote
      /** Unsent notes: question id → the owner's draft note. */
      notes: Record<string, string>
      /** Lanes whose Details view is open. */
      open: Record<string, boolean>
      /** The last lines of lane-feed per open lane. */
      details: Record<string, string[]>
      /** Whether the last read was overloaded (so the alert toasts once per episode). */
      overloaded: boolean
      /** load1 of the recent reads, oldest first (the header's sparkline). */
      loads: number[]
      /** What `lane-status --keep-awake` said the last time the button was pressed. */
      awake: LaneNote
      /** Presses whose work is in flight (`send:<question id>`, `awake`, `refresh`): their buttons say so. */
      working: Record<string, boolean>
    }
  }
}
