# Concurrency inventory

## Execution ownership

| Owner | Execution and responsibility |
| --- | --- |
| AppModel | MainActor composition only; owns feature references |
| LaunchScheduleFeature actor | Source cache commits, grouping, sorting, change detection, upcoming eligibility, Next selection |
| RemindersFeature actor | Reminder validation, reconciliation, JSON persistence and authoritative reminder state |
| API actors | Native asynchronous URLSession calls, response validation, decoding and domain mapping |
| LocalLaunchNotifications actor | Notification request preparation and asynchronous system calls |
| Observable ViewModels | MainActor snapshot publication, presentation formatting and user filters |
| ThemeManager | MainActor UI preference state |

## Tasks and cancellation

- LaunchScheduleViewModel owns replaceable refresh-all and per-source Task handles. Request generation checks prevent old task completion from clearing newer handles.
- LaunchScheduleFeature creates structured child tasks for provider fan-out. Source failures remain independent; each successful source publishes before the group completes. Cancellation is checked around transport/decoding and before cache publication. Decoding itself is synchronous and not preemptively interrupted.
- Both ViewModels own cancelable snapshot-consumer tasks. They capture their owners weakly between stream values and reject old subscription generations. Root disappearance cancels observation; deinit cancels retained tasks.
- SwiftUI owns the root's awaitable clock loop. Task.sleep suspends without blocking a thread. The schedule ViewModel retains a short foreground clock-update task.
- ReminderViewModel owns its user-command task. Notification operations use unique IDs so removing/replacing a reminder cannot let an older scheduled alert restore stale state. These system side effects are protected by operation identity; cancellation alone is not treated as a rollback guarantee.
- AsyncStream termination uses a short Task to remove the continuation on its feature actor. There are no detached tasks, blocking waits or GCD scheduling in production.

## Data delivery and ordering

Each feature offers independent AsyncStream subscriptions with initial-state replay and bufferingNewest(1). Snapshots are complete immutable Sendable values. Monotonic revisions guard ViewModel publication against delayed older snapshots. LaunchSourceUpdate carries mandatory source/revision metadata into reminder reconciliation. Freshness is checked before committing a scheduled notification and before recording scheduling failure, as well as between records. Pending additions reserve reminder capacity across suspension. Unchanged schedule snapshots are suppressed, while cooldown expiry remains an observable state change. The feature owns the initial-load decision.

Actors serialize synchronous state access but are reentrant at await. They do not own dedicated threads, and one feature's calculation does not automatically spread across CPU cores. In particular, marking a method async alone is not the execution boundary: entering a separate feature actor is.

## Evidence

88 tests pass on macOS and iPhone Air Simulator (iOS 26.2). Added coverage verifies two subscribers, slow-consumer coalescing, independent subscriber cancellation, initial reminder replay, stale reminder source revisions, actual off-main feature processing and main-actor observable publication before another provider finishes. Existing network cancellation, replacement request, failure isolation and owner-release tests remain in place.

The application builds with Swift 6 and complete concurrency checking. The live Simulator check loaded five RocketLaunch.Live and 50 Launch Library records with independent SpaceX failure. This is execution/correctness evidence, not an Instruments performance measurement. Test-only locks/checked continuations provide controlled clocks and completion ordering; production requires no unchecked Sendable escape hatches.
