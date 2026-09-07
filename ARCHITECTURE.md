# RocketLaunch architecture

AppModel constructs and owns the runnable application model. Business features are actors; SwiftUI observes main-actor ViewModels containing immutable feature snapshots. The app has five fixed tabs: Next, Upcoming, Operators, Changes and Reminders.

```text
Main actor                         Feature actors                 Service actors
SwiftUI → observable ViewModel ───→ LaunchScheduleFeature ────────→ RocketLaunchAPI
                              │                           ├─────→ LaunchLibraryAPI
                              │                           └─────→ SpaceXAPI
                              └──→ RemindersFeature ────────────→ LocalLaunchNotifications
          ← Sendable snapshots ←      actor-owned state
```

## The feature boundary

LaunchScheduleFeatureAPI and RemindersFeatureAPI are Sendable asynchronous contracts declared directly above their concrete actors in the same files. They expose commands, a current immutable snapshot and an asynchronous snapshot stream. AppModel remains MainActor-isolated for composition; constructing a separate actor does not give that actor MainActor isolation. Construction starts no requests and does not load reminder storage.

LaunchScheduleFeature owns source caches, request identities, cooldowns, operator grouping, schedule-change detection, upcoming eligibility and ordering, and stored nextLaunch. These operations execute on its actor. RemindersFeature owns reminder validation, replacement identities, reconciliation, JSON encoding/decoding and UserDefaults access on its actor. Reminder storage loads lazily on the first command or subscription, not during main-actor construction.

API actors await native URLSession operations and decode their responses on their own actor execution paths. Immutable Sendable domain values cross the boundaries. No detached tasks or unsafe production Sendable declarations are needed.

An actor is a serial isolation domain, not a dedicated thread or CPU core. Separate actors can make concurrent progress, and network waits suspend tasks. An await permits reentrancy; request identities and revision checks still matter.

## Snapshot delivery and lifetime

Each snapshots() call registers an independent AsyncStream subscriber and immediately yields the current complete snapshot in the same actor-isolated operation. There is no gap between registration and the initial read. Streams buffer only the newest complete snapshot, preventing an inactive UI from accumulating an unbounded queue. Intermediate presentation states can be coalesced; source caches and the bounded change journal remain in the latest snapshot.

Every publication has a monotonically increasing revision. ViewModels reject older snapshots, including a delayed stream value arriving after a direct command-completion read. Subscription generation IDs prevent canceled subscriptions from publishing after observation restarts.

The root owns the two observable ViewModels. They own their stream-consumer tasks, capture themselves weakly inside long-lived loops, stop observing on root disappearance and cancel on deinitialization. Each stream termination schedules a short actor cleanup task to remove its continuation; this is not an independently running business operation. Ending one subscriber does not end the others or cancel source work.

The ViewModel delegates loadIfNeeded to the feature, which checks its authoritative source state and marks an initial load in progress before awaiting provider work. A fresh ViewModel cannot trigger another initial download merely because its first snapshot has not arrived. An entirely canceled initial load can be retried. Refresh tasks remain ViewModel-owned and replaceable. The root lifecycle owns the awaitable clock-monitor task. Tab switches do not dispose of these shared owners. A bounded foreground clock-update task is also retained and canceled by the schedule ViewModel.

## Refresh and ordering

A structured task group starts the configured sources concurrently. Each source commits and publishes as it completes; the UI does not await the slowest source before displaying available results. Ordinary errors are isolated per provider. Stale request IDs cannot overwrite newer data, and canceled requests restore their last settled source snapshot.

Operator groups rebuild only on accepted data changes. Clock events recompute time-sensitive upcoming/Next results without rebuilding operator groups. An unchanged complete snapshot is not republished. Expired cooldowns are cleared as meaningful state changes so refresh controls update even when launch data is unchanged. Next prefers precise future launches from non-failed sources and retains explicitly labelled undated/elapsed fallbacks. Failed source caches remain available with failure attribution in browse screens. Cross-source duplicates are not silently reconciled.

After a source commit, AppModel's Sendable callback passes one LaunchSourceUpdate containing the source, publication revision and launch values to the reminders actor. That actor rejects older source revisions, checks them between records, and checks freshness again after notification scheduling returns, before committing the replacement. A superseded request cancels only its newly scheduled notification. The error path also checks freshness before changing a reminder or canceling its old alert. Individual operation IDs independently protect user replacement/removal.

The reminder capacity rule counts saved launch IDs together with pending operation IDs. A pending addition reserves its slot before suspension; replacements reuse the same launch's slot. Completion, failure and removal release reservations without clearing a newer operation's token.

## Presentation

ViewModels hold read-only observable snapshots. They format text and apply user-selected search, operator and country filters. Upcoming eligibility and chronological ordering are already calculated by the feature. Small presentation operations and theme selection intentionally remain on the main actor.

The eight colour themes remain in the MainActor ThemeManager. Settings and Next's double-tap gesture share its persisted selection. Detail screens display the immutable launch record selected by the user.

## Sources and reminders

RocketLaunch.Live supplies five records; Launch Library supplies one page of up to 50; the archived community SpaceX API is a third integration with independent failure handling. These are bounded lists, not a complete worldwide schedule. SpaceX records with past or unknown dates cannot become Next or appear in Upcoming; other providers still supply SpaceX launches. The current unreliable source remains in the live graph for the planned failure/recovery teaching exercise.

Changes retains up to 100 time/mission changes detected between downloads during the current app session. The first download establishes a baseline. Reminders persist between app launches and use system local notifications. Schedule refreshes update their times; no background polling or server push is implemented. Notification delivery depends on system settings. Watch links are shown only when supplied; ordinary launch-page links are labelled as information.

## Verification

88 XCTest cases pass on macOS and iPhone Air Simulator (iOS 26.2), covering decoding, cancellation, stale results, independent providers, reminder persistence and ordering, stream replay/coalescing, independent subscribers, ViewModel observation and incremental delivery. Runtime checks exercise feature calculations away from the main thread and observable publication on MainActor. The iOS simulator application builds successfully; live data loaded from RocketLaunch.Live and Launch Library while SpaceX failed independently.

These checks establish behavior and execution boundaries, not a measured frame-rate improvement or guaranteed parallel utilization of CPU cores. Device performance profiling and notification delivery remain separate validation work.
