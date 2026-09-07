# Concurrency inventory

| Owner | Responsibility |
| --- | --- |
| AppModel, MainActor | Construct and retain the application graph |
| LaunchScheduleFeature actor | Authoritative launch caches, Next, Changes, desired reminders, persistence and notification revision checks |
| API actors | Native async transport, decoding and mapping |
| LocalLaunchNotifications actor | Shared permission request and iOS notification effects |
| Observable ViewModels, MainActor | Snapshot publication, presentation and owned UI tasks |

Refresh-all has structured child callers. The feature owns one shared request Task per source and tracks cancellation-aware waiters. Multiple callers join useful work; cooldown applies only to new requests. Last-waiter cancellation detaches ownership and rejects late results. Initial loading requests idle sources and joins loading sources. UI refresh taps do not cancel an active UI command.

Reminder lookup by ID, validation and desired-state storage are synchronous on the same actor as launch data. Refresh updates both sets of state before suspension. External effects carry unique notification IDs and check current desired state after await. Pending and failed delivery remain explicit. Removal and replacement cannot be undone by an obsolete effect. An ongoing user save can authorize its replacement's permission request; ordinary refreshes cannot initiate permission prompts.

Snapshot streams replay complete state with newest-value buffering and independent subscriptions. MainActor ViewModels reject stale revisions/subscriptions. Root clock monitoring suspends with Task.sleep; actors do not reserve threads or automatically parallelize a calculation across cores. Shared request tasks and the permission task are explicitly owned unstructured work; there are no detached tasks, GCD scheduling or blocking waits in production.

97 host tests pass. The iOS app/test bundle build with Swift 6 complete concurrency checking. Current simulator execution remains pending while the Mac is locked. Device notifications and Instruments performance are not claimed as verified.
