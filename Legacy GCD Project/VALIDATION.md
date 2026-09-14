# GCD validation — 13 September 2026

## Completed

- Separate Xcode project and app/test targets created in Legacy GCD Project.
- Swift 5 language mode, iOS 17 deployment target, separate GCD bundle identifier and app display name.
- **All 40 tests passed on iPhone Air / iOS 26.2 in Xcode 26.2**, zero failures, at 23:25 local time on 13 September 2026.
- Expanded suite: 40 callback-based tests passed in a temporary host package using the actual model/API/view-model sources.
- Live GCD app ran in the simulator. RocketLaunch.Live returned five records, Launch Library returned fifty, and the community SpaceX API displayed an independent failed state.
- Next, Upcoming, launch details, Operators, Changes and Reminders were opened successfully. UI uses the copied theme and component system.
- Source scan found no feature actors, async/await methods, Task-based work or AsyncStream in the GCD app and tests.

## Covered contracts

The suite includes three provider decoders, malformed and uncertain dates, an isolated HTTP error response, independent provider publication/failure, main-queue snapshots, off-main feature calculation, observer cancellation, shared-request cancellation, last-caller detachment, late-result rejection, cooldowns, launch expiry, change detection, view-model delivery, invalid reminders, save-by-current-ID, schedule failure, stale scheduling completion, removal during scheduling, refresh replacement and time passing during notification scheduling.

The suite has 40 tests, not a one-for-one translation of the sibling project's larger suite. The production screens, decoding models and synchronous business rules were reused; callback ownership and lifecycle paths were rewritten.

## Remaining limits

Physical-device notification delivery, system permission/relaunch testing, exhaustive accessibility/theme checks and Instruments profiling remain manual acceptance work. Unit tests use an injected notification client and do not prove system alert delivery. Live provider health is separate from fixture correctness.

This is the GCD migration starting point, not an App Store submission. No commit, push or submission was performed.
