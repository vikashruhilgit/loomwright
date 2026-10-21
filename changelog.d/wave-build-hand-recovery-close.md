A hand-recovered wave-build reports its completion; the ma10 allowlist leg no longer flakes under load
When `wave-build` stops on a conflict or red CI and the owner integrates by hand, the wave PR used to be
opened by hand, so `wave-build` never ran again and never sent the `pass ok` that closes the step's
telemetry threads. The `wave-build` failure threads stayed open after their waves merged. The lanes
skill's step 9 now ends that recovery by re-running `wave-build`. The re-run reads the open PR, prints
`done` and sends `pass ok`, and test-wave-build W2x pins that event. The test-setup-memory ma10
hung-entry leg bounded every gh call at 1s, so on a loaded host the bound killed the answering ORIGIN
lookup first and the leg read red with no plugin fault. It now uses a 3s bound, which still sits far
below the 7s hang.
