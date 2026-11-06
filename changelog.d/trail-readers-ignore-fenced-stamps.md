<!-- bump: patch -->
Closeout and the trail's evidence gate ignore a closeout block quoted in a code fence
`_co_stamped` read a quoted block as already stamped, so closeout could skip a real stamp, and `_done_prs` read a quoted `## Status: done` and its PR as a real done claim, so the trail could exclude a file that was never done. Both now read through `status_unfenced`, which also treats `~~~` as a fence. Without the library they read the whole file, so a real stamp is never hidden.
