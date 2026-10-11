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
}

export type LaneMachine = {
  state: string
  load1: number | string
  cpus: number | string
  mem_pressure: string
  keep_awake: string
}

export type LaneStatusDoc = {
  schema_version: number
  parent_run_id: string | null
  generated_at?: string
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
      /** Lanes whose Details view is open. */
      open: Record<string, boolean>
      /** The last lines of lane-feed per open lane. */
      details: Record<string, string[]>
      /** Whether the last read was overloaded (so the alert toasts once per episode). */
      overloaded: boolean
    }
  }
}
