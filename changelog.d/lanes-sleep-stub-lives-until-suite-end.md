<!-- bump: patch -->
test-automate-lanes.sh's sleep stub stays live until the suite ends
The `STUB_MODE=sleep` stand-in for a headless lane session ran `sleep 60`, so under heavy parallel load the AH lane-wait legs (reached more than 60 s after lane L2's launch) read L2 as `died` and five checks failed. The stub now holds while a marker file under the suite's temp dir exists; cleanup removes the marker first, so every held session exits on its own within a second, with a 30-minute backstop for a suite killed before its cleanup.
