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

Snapshot streams replay complete state with newest-value buffering and independent subscriptions. MainActor ViewModels reject stale revisions/subscriptions. Root clock monitoring suspends with Task.sleep; actors do not reserve threads or automatically parallelize a calculation across cores. Shared request tasks, reminder effect batches and the permission task are explicitly owned unstructured work; there are no detached tasks, GCD scheduling or blocking waits in production.

98 host tests pass. The iOS app/test bundle build with Swift 6 complete concurrency checking. All 98 tests also passed on the iPhone Air simulator (iOS 26.2), 7 September 2026. Device notifications and Instruments performance are not claimed as verified.

### Refresh completion and notification delivery

A provider refresh completes after committing launch data and desired reminder state. It removes its active request and resumes callers without awaiting notification delivery. The feature owns separate task batches for those effects; each batch uses a task group and removes its handle when finished. These tasks retain the model until delivery and obsolete-notification cleanup settle. Screen cancellation does not cancel committed reminder intent. New downloads still respect provider cooldowns and share genuinely active downloads.

Reminder snapshots report pending, scheduled or failed delivery independently of refresh completion. Direct user saves still await their own delivery result.

Teaching sequence: [Three-day teaching guide](TEACHING_GUIDE.md). Validation evidence and device exercises: [Teaching validation](TEACHING_VALIDATION.md).
