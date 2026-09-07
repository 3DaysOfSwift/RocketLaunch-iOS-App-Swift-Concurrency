## Notification-effect lifetime validation

98 macOS host tests pass. The iOS app and test bundle build successfully. The regression verifies that a new refresh fetches and commits newer data while an older notification effect is suspended, then checks obsolete-alert cleanup. Delivery-dependent assertions observe reminder status separately from download completion. The teaching pass subsequently ran all 98 tests on the iPhone Air simulator (iOS 26.2). Physical-device checks remain open; see ../TEACHING_VALIDATION.md.

# Current validation: shared launch and reminder actor

97 host XCTest cases pass against the real Model/ViewModel sources. The iOS application and test target build successfully. The current simulator run is pending because the Mac was locked; earlier simulator counts below describe earlier revisions.

The separate reminder actor and its cross-feature reconciliation API have been removed. Their tests were replaced with 19 tests through the unified ID-based command/cache boundary and four shared-request lifecycle tests. Other decoding, progressive-source, snapshot, theme, ViewModel and cancellation coverage remains. Existing stale-response tests now explicitly cancel the old caller before starting new work; overlapping live callers share requests instead of superseding each other.

Coverage includes stale detail IDs resolving current data, desired state before suspension, pending first saves participating in refresh, unchanged/unknown times, late success/failure cleanup, removal/replacement, capacity, explicit delivery failure/retry, expired scheduling, legacy persistence, interrupted persistence, double taps, partial startup recovery and joining requests during cooldown.

Permission flags and notification identities are checked with injected clients. Actual permission dialogs, physical-device notification delivery and Instruments profiling remain separate checks.

## Previous validation history

# Running the regression suite

Use the shared RocketLaunch scheme in Xcode, select an iPhone simulator running iOS 17 or later, then Product → Test (Cmd-U). Tests live in RocketLaunchTests and are members of its iOS unit-test target. All 35 cases passed on iPhone Air/iOS 26.2.

`python3 Tests/run-host-tests.py` runs those same XCTest files on macOS 14+ with Swift 6 against the actual Model/ViewModel/theme sources. It generates a temporary package and cleans it after execution. This supplements the iOS tests and does not execute SwiftUI screens.

The response fixture is fixed. Network tests own ephemeral sessions and URLProtocol responses; none contacts the live endpoint. Controlled repository continuations deliberately delay completion so tests prove order and cancellation without timing sleeps. Test-only unchecked Sendable is restricted to a documented lock-protected URLProtocol fixture store.

The earlier defect-characterisation expectations have been replaced by assertions for approved corrected behaviour. Callback checkpoints remain in the local migration pack.

The five-tab revision has 68 passing host tests. Added coverage includes reminder persistence, permission denial, invalid/past times, automatic rescheduling, cancellation after removing an in-flight reminder, source identity, browsing filters and session change detection. Local notification delivery itself still needs device validation; unit tests inject a notification client.

The actor-feature revision has 77 passing host tests. Feature assertions await immutable snapshots. Additional tests cover independent stream subscribers, newest-snapshot buffering, subscriber cancellation, reminder replay, source revision ordering, off-main feature execution and MainActor ViewModel publication before the second provider completes.

Actor-feature validation, 2026-09-07: all 77 XCTest cases passed in Xcode on iPhone Air Simulator (iOS 26.2), as well as in the macOS host runner. This supersedes earlier MainActor-feature descriptions; ARCHITECTURE.md and CONCURRENCY_INVENTORY.md describe the current actor/snapshot implementation. Performance profiling and physical-device notification delivery are not claimed by these checks.

Concurrency cleanup, 2026-09-07: all **88 tests** passed on macOS and iPhone Air Simulator (iOS 26.2). Eleven new regressions cover suspended rescheduling with newer unchanged/changed/unknown times, stale scheduling failure, pending capacity and failure release, initial-load ownership and cancellation retry, fresh ViewModel loading, unchanged clock ticks and cooldown expiry. The original two failing race reproductions are now part of the permanent Xcode test target.

Follow-up cleanup, 2026-09-07: all **94 tests** pass on macOS and iPhone Air Simulator. Six further tests cover first-save freshness and its explicit outcome, unchanged and unknown launch times, stale failure, double-tap handling, and partial initial-load recovery.
