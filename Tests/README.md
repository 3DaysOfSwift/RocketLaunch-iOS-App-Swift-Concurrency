# Running the regression suite

Use the shared RocketLaunch scheme in Xcode, select an iPhone simulator running iOS 17 or later, then Product → Test (Cmd-U). Tests live in RocketLaunchTests and are members of its iOS unit-test target. All 35 cases passed on iPhone Air/iOS 26.2.

`python3 Tests/run-host-tests.py` runs those same XCTest files on macOS 14+ with Swift 6 against the actual Model/ViewModel/theme sources. It generates a temporary package and cleans it after execution. This supplements the iOS tests and does not execute SwiftUI screens.

The response fixture is fixed. Network tests own ephemeral sessions and URLProtocol responses; none contacts the live endpoint. Controlled repository continuations deliberately delay completion so tests prove order and cancellation without timing sleeps. Test-only unchecked Sendable is restricted to a documented lock-protected URLProtocol fixture store.

The earlier defect-characterisation expectations have been replaced by assertions for approved corrected behaviour. Callback checkpoints remain in the local migration pack.

The five-tab revision has 68 passing host tests. Added coverage includes reminder persistence, permission denial, invalid/past times, automatic rescheduling, cancellation after removing an in-flight reminder, source identity, browsing filters and session change detection. Local notification delivery itself still needs device validation; unit tests inject a notification client.

The actor-feature revision has 77 passing host tests. Feature assertions await immutable snapshots. Additional tests cover independent stream subscribers, newest-snapshot buffering, subscriber cancellation, reminder replay, source revision ordering, off-main feature execution and MainActor ViewModel publication before the second provider completes.

Actor-feature validation, 2026-09-07: all 77 XCTest cases passed in Xcode on iPhone Air Simulator (iOS 26.2), as well as in the macOS host runner. This supersedes earlier MainActor-feature descriptions; ARCHITECTURE.md and CONCURRENCY_INVENTORY.md describe the current actor/snapshot implementation. Performance profiling and physical-device notification delivery are not claimed by these checks.
