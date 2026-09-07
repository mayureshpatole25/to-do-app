# Completion celebrations

The installed app and development builds use the login user's
`Library/Application Support/com.empy.EmpyTood` directory. The app is distributed
outside the App Store and runs without App Sandbox, matching the installed app.
Persistence services resolve this location through `AppIdentity.dataDirectory`.
Debug builds can select an isolated directory with `EMPY_TOOD_STORAGE_DIRECTORY`
(a single directory name, never an absolute path).

`scripts/consolidate-stores.py` is a one-time local migration. Quit Tood before
running it. It backs up both stores, leaves the direct store's live task state
unchanged, recovers unique legacy items into archives, and imports unique retired
completions. Current task versions take precedence. The legacy directory becomes
a symlink to the canonical directory, so older non-sandboxed builds cannot fork
the data again. Journal entries from the same day use the authoritative version;
all original content remains in the backup. Never run a sandboxed older build
against this consolidated setup.

`completion_history.json` retains completion records after a task or sticky is
deleted. Ordinary task identities count once; recurring tasks use their scheduled
occurrence as part of their identity. Reopening a task removes its current
completion record. Milestone and day claims survive undo, so rechecking cannot
replay a celebration. Importing existing history silently establishes the
milestone baseline. A corrupt existing history is preserved and logged rather
than overwritten.

Every 50 completions shows a milestone. The first newly completed task of a day
shows a weekday streak: Saturdays and Sundays pause the counter. A missed weekday
breaks it, and today's unfinished day has until midnight. Weekend work counts
toward lifetime totals and can show the existing weekday streak. When both
messages trigger, only the milestone notice is shown.

The milestone takes priority when both messages trigger; there is one notice per
completion. A tinted inline banner temporarily replaces the date row above the
sticky title, with an Achievements ↗ link and a close control. It dismisses after
five seconds, restoring the date row. Narrow stickies wrap the banner content.
The banner belongs to the sticky's transient observable state; it never creates
another window or takes keyboard focus. Opening Achievements cancels the notice.

Home displays a horizontally scrolling calendar heatmap beneath the greeting.
Weekday labels stay fixed to the greeting’s left edge; wider windows reveal more
weeks. Month labels include the year. The calendar opens at the current month and
includes five years or all recorded history, whichever is longer. Orange intensity
reflects daily completions; custom hover labels show the date and count immediately. A compact column beside the heatmap shows lifetime
completions, done rate, longest weekday streak and current weekday streak, separated
by quiet rules. Streak values have at least two digits. View → Achievements opens a
reusable window with the same display, stacked vertically at narrow widths. Counts are
live and streaks refresh across date changes. `createdTaskKeys` records nonempty
tasks and recurring occurrences as they are created, retaining the denominator
after deletion. Earlier deleted unfinished tasks cannot be reconstructed.

Verification helpers:

- `AchievementHeatmapRegression.swift`: calendar alignment, local dates, month
  labels, future cells, leap days and intensity boundaries.
- `CompletionHistoryRegression.swift`: milestone boundaries, deduplication,
  undo/recheck, persisted claims, weekday streaks and occurrence identities.
- `AchievementNoticeRegression.swift`: milestone priority, sticky ownership,
  explicit close, replacement cancellation and five-second dismissal.
- `CelebrationPreview.swift`: persistent native visual preview; accepts
  `--streak` and `--reduced-motion`.
- `create-celebration-fixture.py`: isolated 49-completion integration fixture.

Compile the history regression with `AppIdentity.swift` and
`CompletionHistory.swift`. Native preview/notice helpers additionally require
`CelebrationPresenter.swift`. These helpers run independently of personal tasks.

The Overview section includes a searchable multi-select sticky popover. Clicking
a row toggles it without dismissing the popover; outside clicks dismiss it. Clear
resets to All stickies. The same filtered history drives the heatmap and all four
metrics. Task-to-sticky ownership is backfilled from live and archived snapshots
and retained for later task deletions. Older deleted tasks without recoverable
ownership remain in unfiltered totals.
