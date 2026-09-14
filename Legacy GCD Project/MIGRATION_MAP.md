# GCD → Swift Concurrency migration map

The destination reference is `../Swift Concurrency Project/RocketLaunch.xcodeproj`. Keep both projects runnable throughout the lesson. They use different bundle identifiers and share no app-data container.

## Begin with unchanged behaviour

Show Next and source status. A provider may fail while other providers produce usable results. Show an uncertain date and a launch detail screen. Explain that the migration preserves these contracts; it changes how execution and ownership are expressed.

Both projects retain the same feature names and data models. The differences below are implementation choices rather than reasons to redesign the screens.

| GCD baseline | Swift Concurrency destination | Teaching point |
| --- | --- | --- |
| LaunchRepository callback plus cancellation token | async throwing repository method | The result/error and cancellation become part of a task flow |
| URLSession completion handler plus decoding queue | URLSession async method inside API actor | Suspension and explicit isolation replace callback routing |
| LaunchScheduleFeature class and private serial queue | LaunchScheduleFeature actor | Compiler-enforced isolation replaces manual queue discipline |
| observe callback and token | snapshots AsyncStream | Subscription lifetime and latest-state delivery |
| DispatchGroup with notify | task group | Completion/cancellation follow structured child lifetimes where applicable |
| Request token, ID and completion waiters | owned Task, ID and continuation waiters | Shared work still needs an explicit owner and stale-result policy |
| main-queue callback delivery | MainActor observable view model | UI state has an explicit actor boundary |
| DispatchSourceTimer | cancellable Task.sleep loop | Clock monitoring follows an owned asynchronous lifetime |
| reminder callback chains and ID checks | asynchronous reminder effects and ID checks | Actor isolation does not make operations spanning suspension atomic |

## Suggested checkpoints

1. Run GCD tests and trace one successful provider download. Keep the screen and decoded types unchanged.
2. Convert one repository boundary to async/await, including cancellation and malformed-response tests. During an incremental migration, label temporary adapters and remove them once their callers migrate.
3. Convert feature state ownership to an actor. Replace direct queue access with the feature API. Identify every new suspension and the state that must be rechecked afterward.
4. Move snapshot delivery and UI state to AsyncStream and MainActor. Preserve initial replay and observer cancellation. The GCD callback implementation queues each snapshot; the destination's bufferingNewest(1) intentionally coalesces replaceable state for slow consumers.
5. Convert refresh coordination. Independent results must still appear before the final provider finishes. Shared requests do not become ordinary children of one arbitrary screen; retain their explicit ownership policy.
6. Convert reminders last. Compare save-by-ID, synchronous desired-state commit, external scheduling, and post-callback/post-await identity checks. Test replacement and removal while scheduling is pending.
7. Remove obsolete queues and callback adapters. Turn on Swift 6 complete concurrency checking and rerun behaviour tests.

## Deterministic exercises

Use ControlledRepository and ControlledNotifications in the GCD test target. They deliberately allow late callbacks after cancellation and let the test release completions in a chosen order. Use TestClock instead of sleeping. XCTest waits pump test delivery; production code never blocks waiting on a DispatchGroup or semaphore.

Useful starting tests:

- testEarliestLaunchAndIndependentFailure
- testTwoCallersShareRequestAndOneCancellationPreservesOther
- testLastCancellationDetachesLateResponseFromNewRequest
- testClockExpiryClearsStoredNext
- testRefreshReplacesPendingReminderWithoutRestoringOldID
- testNewReminderWinsWhenOldSchedulingFinishesLast

## Explain the benefit accurately

The GCD app is intended to be well-behaved code, not manufactured callback spaghetti. Its queue discipline is documented and asserted at important boundaries, but the compiler does not prove it. The migration adds actor isolation and task-lifetime tools while preserving explicit product policies.

Neither approach assigns a permanent thread or CPU core to each feature. Both allow independent network operations to overlap. Swift Concurrency reduces manual coordination; it does not eliminate the need to define cancellation, obsolete-result handling, or reminder ordering.
