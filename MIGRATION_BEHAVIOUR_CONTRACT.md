# Rocket Launch — behaviour contract

Status: callback architecture checkpoint; concurrency migration not started.
Date: 2026-09-07, Asia/Bangkok.

Scope: one existing RocketLaunch.live endpoint, next-launch display. No multi-provider aggregation, persistence, new screens or App Store submission work.

## Approved decisions

The user approved iOS 17 and Observation, and fixes to refresh, stale-response, empty-result and error/retry defects on 2026-09-07. These are intentional changes for the next phase, not claims about legacy behaviour. The current callback checkpoint still supports iOS 15.2.

## Preserved behaviour

| ID | Plain-English requirement | Legacy evidence | Evidence status | Baseline | Replacement protection | Post-migration result | Manual regression | Difference and approval |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| BEH-001 | A newly created screen has not received a launch and uses None placeholders. | LaunchScheduleViewModel initial state | Inferred | Pass | Characterisation/main.swift | Callback checkpoint pass | Pending | None |
| BEH-002 | Constructing the application objects does not initiate networking. | System and ViewModel initializers | Inferred | Pass | Characterisation/main.swift | Callback checkpoint pass | Pending | None |
| BEH-003 | Refresh requests the existing launch endpoint. | NetworkManager and RocketLaunchAPI | Inferred | Pass, intercepted URLSession | Characterisation/main.swift | Callback checkpoint pass | Live API pending | None |
| BEH-004 | A nonempty success displays the first returned launch and its first mission description. | ViewModel result.first and missions.first | Inferred | Pass | Characterisation/main.swift | Callback checkpoint pass | Pending | Selection moved into feature |
| BEH-005 | A network failure does not publish a successful result. | ViewModel failure branch | Inferred | Pass | Characterisation/main.swift | Callback checkpoint pass | Pending | Visible error/retry improvement approved for next phase |
| BEH-006 | The initial screen offers Get Next Rocket Launch and a Refresh button. | LaunchScheduleView | Unprotected | Source inspected | Manual checklist | Same view conditional retained | Pending | None |
| BEH-007 | A loaded screen shows Next Launch, Name and Mission. | LaunchScheduleView | Unprotected | Source inspected | Manual checklist | Same view text retained | Pending | None |

## Existing defects exposed

| ID | Observed legacy behaviour | Evidence | Current checkpoint | Approved next behaviour |
| --- | --- | --- | --- | --- |
| DEF-001 | Refresh guard resets before callback completion; requests overlap. | Deterministic characterisation test | Reproduced | Define a managed refresh lifetime |
| DEF-002 | An older response can overwrite a newer response. | Controlled reverse completion test | Reproduced | Obsolete results must not publish |
| DEF-003 | Empty response enters success state with None placeholders. | Empty JSON response test | Reproduced | Honest empty state with retry |
| DEF-004 | Errors print only; HTTP status and transport errors are discarded. | NetworkManager and ViewModel source | Preserved | Meaningful errors and visible recovery |
| DEF-005 | Refresh is absent after success. | View conditional source | Preserved | Refresh available after success |
| DEF-006 | Parent constructs the ViewModel inside body. | ContentView source | Fixed at ownership checkpoint | Screen owns stable StateObject; later State with Observation |

No current legacy defect is promoted into a permanent product requirement. All automated results here are macOS executions of the real Foundation/SwiftUI ViewModel sources with URLProtocol fixtures; they are not iOS UI tests or proof the live API works.

## Manual comparison required

Open Original/RocketLaunch.xcodeproj and Migrated/RocketLaunch.xcodeproj in turn on the same simulator/device. Do not run both concurrently against the same app installation.

1. Fresh launch: check initial text and Refresh button; no automatic request.
2. Tap Refresh on a working network: compare Next Launch, Name and Mission.
3. Relaunch without connectivity: confirm the app stays on its initial state after failure.
4. Return online and retry: confirm a successful result can appear.
5. Record tester, date, device/OS, project version and results below. Live failures may indicate an API/schema problem and must be investigated, not treated as migration regressions automatically.

Manual result: PENDING. Simulator services are inaccessible from the current execution environment. Device builds are successful with signing disabled; no device execution is claimed.

## DEF-007 — nullable estimated launch dates (2026-09-07)

The user ran the callback checkpoint on iPhone Air Simulator and reported a decoding failure at result[0].est_date.day. The retrieved RocketLaunch.live response contains null day values and, for some launches, null month/day/year. The user explicitly requested correction. LaunchDate now accepts nullable/omitted date components while retaining type errors for malformed values. No dates are invented.

Regression: `python3 Tests/LaunchDecoding/run.py` checks complete dates, null day, all-null components, omitted components and invalid types. Three cases reproduced the failure before the fix; all five pass afterwards. Live screen verification after this fix remains pending.

## XCTest protection — 2026-09-07

The earlier standalone decoding runner has been replaced by `RocketLaunchTests/AppModel tests/Launch Schedule/LaunchDecodingTests.swift`. Run all tests in Xcode with Cmd-U or on macOS with `python3 Tests/run-host-tests.py`.

| Requirement/defect | In-repository protection |
| --- | --- |
| BEH-001/002 | LaunchScheduleViewModelTests.testInitialStateDoesNotStartNetworking; LaunchScheduleManagerTests.testConstructionDoesNotFetch |
| BEH-003 | LaunchScheduleManagerTests.testFirstReturnedLaunchIsSelected; RocketLaunchAPITests.testDecodesResponseThroughRealNetworkingBoundary |
| BEH-004 | LaunchScheduleManagerTests.testFirstReturnedLaunchIsSelected; LaunchScheduleViewModelTests.testRefreshPublishesLaunchNameAndMission |
| BEH-005 | LaunchScheduleViewModelTests.testFailureLeavesInitialStateAvailableForRetry; testFailureAfterSuccessRetainsDisplayedLaunch |
| DEF-001 | LaunchScheduleManagerTests.testLegacyRefreshGuardAllowsOverlappingRequests |
| DEF-002 | LaunchScheduleViewModelTests.testLegacyOlderResponseCanOverwriteNewerResponse |
| DEF-003 | LaunchScheduleViewModelTests.testLegacyEmptyResponseEntersReceivedStateWithPlaceholders |
| DEF-007 | LaunchDecodingTests (five cases); RocketLaunchAPITests.testNullDatesDecodeThroughTheRepository |

All 22 XCTest cases passed on macOS. The iOS test bundle builds successfully. BEH-006/007 remain manual screen checks, and iOS simulator execution is not yet recorded.
