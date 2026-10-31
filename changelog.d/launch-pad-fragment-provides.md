<!-- bump: patch -->
Briefs no longer promise a changelog fragment their own version bump deletes
Launch Pad's provides authoring rules, the supervisor-readiness contract schema and Plan Reviewer Criterion 12 now say a provides entry must still exist when its subtask completes. A subtask that writes a `changelog.d/` fragment and then runs the version bump names the folded `CHANGELOG.md` entry instead of the fragment, which the bump deletes; the disk gate otherwise reports it missing and stops the run at an adjudication checkpoint. A lane that never bumps still lists the fragment.
