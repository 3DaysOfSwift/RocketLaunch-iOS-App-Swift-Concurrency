# Rocket Launch architecture

Status: Swift Concurrency implementation ready for final manual review. iOS 17+, Swift 6, complete concurrency checking in Debug and Release.

## Dependency and ownership map

```text
1 - View
  RocketLaunchApp → ThemeManager
  ContentView → LaunchScheduleView (@State ViewModel)
                        ↓ LaunchScheduleFeature
2 - AppModel
  AppModel.live → LaunchScheduleManager (@MainActor, @Observable)
                        ↓ LaunchRepository (Sendable)
                 RocketLaunchAPI (actor)
                        ↓ URLSession.data(from:)
3 - App Resources
  Asset catalog and legacy JSON fixture
```

AppModel assembles the one launch feature with explicit dependencies. Construction performs no I/O. Refresh remains a user action; automatic launch loading would change the starter's behaviour and is not introduced. ContentView is a stateless root and does not need a second ViewModel.

## Feature state and domain decisions

LaunchScheduleManager owns one read-only observable state: idle, loading with an optional previous launch, loaded, empty, or failed with an optional previous launch. It chooses the first launch returned by the API. RocketLaunch.primaryMissionDescription represents the original first-mission rule. Missing mission descriptions are displayed as “None” by the ViewModel.

The ViewModel reads the feature's authoritative state through LaunchScheduleFeature, formats presentation values and error messages, and owns the screen's replaceable Task. It does not retain a second launch collection. Swift Observation tracks computed properties through the feature protocol.

Domain values are immutable and Sendable. API payloads and CodingKeys remain private to RocketLaunchAPI.swift; only the required payload fields are decoded. Unknown estimated month/day/year values remain nil. Invalid values for required fields still fail decoding.

## Refresh ordering and cancellation

1. The screen reports Refresh to its ViewModel.
2. requestRefresh cancels the screen's previous Task and stores its replacement.
3. The feature sets a new request identity and publishes loading while retaining any previous launch.
4. The repository awaits native URLSession I/O, validates HTTP status and decodes on its actor.
5. The feature checks cancellation and request identity before publishing.
6. Success publishes the first launch or an honest empty state. Failure preserves previous content and exposes a recoverable error. Cancellation restores the last settled state and is not displayed as a failure.

An older response cannot replace a newer result even if its I/O ignores cancellation. Independent callers share the feature's publication identity; cancelling a Task stops only work owned by that Task. Across different screens, stale publication is rejected even if older I/O continues until it finishes. No global deduplication or cross-screen task cancellation is claimed.

The ViewModel cancels work on disappearance and destruction. Its Task captures the feature but only weakly captures the ViewModel, allowing the screen owner to be released during a pending request. Direct refresh() is also awaitable when another caller already owns the Task lifetime.

## Execution ownership

- MainActor: feature state transitions, request identity, ViewModel presentation, SwiftUI and theme selection.
- RocketLaunchAPI actor: request coordination, response validation, JSON decoding and domain mapping.
- URLSession: asynchronous network transport; cancellation propagates to the underlying request.

There are no callback adapters, DispatchQueue hops, detached Tasks or invented task groups in production. One endpoint does not require multi-provider parallelism. No storage, audio, ticker, CPU-worker pool or optimistic persistence has been added. Off-main ownership is verified from actor isolation and Swift 6 builds; it is not a measured performance claim.

## Presentation

The screen has loading, empty and error states and always offers refresh/retry. Loaded content stays visible while refreshing or after a failed update. A ScrollView and semantic text styles accommodate longer missions and Dynamic Type. AppColourTheme centralises system/midnight palettes; ThemeManager is observable and UI-only. The alternative palette is a development option, not a new user settings feature.

## Tests and validation

RocketLaunchTests contains 35 XCTest cases grouped by ViewModel, feature, repository/decoding, AppModel and theme responsibilities. Fixtures and isolated URLSession instances avoid the real API during tests. Test-only unchecked Sendable declarations are limited to URLProtocol and a lock-protected response store; production uses actor isolation and immutable Sendable values.

All 35 cases passed on macOS and in Xcode on iPhone Air, iOS 26.2. The device test bundle and Release app build passed. Live simulator smoke testing confirmed initial state, successful fetch, displayed launch/mission and refresh after success. Empty/error/retry/cancellation logic has deterministic test coverage; manual offline/recovery, large Dynamic Type, VoiceOver and physical-device profiling are not claimed complete. See MIGRATION_REVIEW.md.

### API placement

`2 - AppModel/Features/Launch Schedule/RocketLaunchAPI` contains the concrete RocketLaunchAPI actor and its private transport payloads. This API belongs to the Launch Schedule feature. The LaunchRepository contract sits directly in `Features/Launch Schedule`. AppModel composes the two; the feature manager depends on the contract rather than the concrete API.
