<!-- bump: minor -->
/lanes shows every lane's step, a seven-step rail and when the wave started; keep-awake reads the desktop app's hold
`lane-status --json` gives each lane a `timeline` (pick · plan · build · heal · drain · decide · merge, each with its
state, start, end, time spent and last lines, plus a current-step label such as `Build · EXECUTE`) read from the lane
run file's `## Progress` and its Supervisor state, a lane `started_at`, and the wave's `run_started_at` and
`utc_offset_s`; the plain view prints a `steps:` line. Keep-awake now reads macOS power assertions, so the Claude
desktop app's "keep computer awake while Claude works" hold shows as held instead of "not held" — but only a
`caffeinate` counts as lasting (the app's hold follows Code-session work and lanes are not Code sessions), so the
suggestion stays and `--keep-awake` still starts one. The loomwright-lanes pane draws it all: four header tiles
(wave start, lanes, a load sparkline, keep-awake with a Keep awake for this wave button), and per lane its current
step, its start time and a hoverable seven-step rail.
