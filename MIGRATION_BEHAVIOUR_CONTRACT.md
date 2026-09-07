# Rocket Launch — behaviour contract

Date: 2026-09-07, Asia/Bangkok. Status: implementation and automated checks passed; remaining manual recovery checks and developer acceptance pending.

## Scope and approved changes

One existing RocketLaunch.live endpoint and its next-launch display are retained. The user approved iOS 17/Observation and corrections to refresh, stale responses, empty results and error/retry handling. The later nullable-date decoding fix was explicitly requested after running the callback app. No multi-provider aggregation, automatic launch loading, persistence or App Store submission work is included.

The supplied archive and original sources are preserved outside this Git repository in the local migration pack. Callback checkpoints are retained there, including Pass-04-Callback-With-Tests.zip. The original built and its baseline checks passed, including tests exposing defects; these did not declare the defects desirable.

## Preserved requirements

| ID | Requirement | Legacy evidence/status | Baseline | Replacement protection | Current result | Manual evidence |
| --- | --- | --- | --- | --- | --- | --- |
| BEH-001 | Initial state has no launch and uses None for missing display values. | ViewModel; inferred | Pass | testInitialStateDoesNotStartNetworking | Pass | Initial heading/button observed in Simulator |
| BEH-002 | Construction performs no network request. | System/ViewModel initializers; inferred | Pass | testConstructionDoesNotFetch; AppModelTests | Pass | Screen remained idle before Refresh |
| BEH-003 | Refresh requests the existing launch endpoint. | API source; inferred | Pass with fixture | testDecodesResponseThroughRealAsyncNetworkingBoundary | Pass | Live API result loaded on iPhone Air |
| BEH-004 | Display the first returned launch and first mission description. | Legacy result.first/missions.first; inferred | Pass | testRefreshLoadsFirstReturnedLaunch; ViewModel loaded/fallback tests | Pass | Name: TBD / Mission: None displayed from live response |
| BEH-005 | Failed refresh must not replace a good result with false success. | Legacy failure branch; inferred | Pass | testFailureRetainsLastLaunchAndRetryCanReplaceIt | Pass, now with visible recovery | Offline/retry screen check pending |
| BEH-006 | Initial screen offers a Refresh action. | Legacy View; inferred | Source inspected | SwiftUI source plus manual smoke | Pass | Codex, 2026-09-07, iPhone Air/iOS 26.2 |
| BEH-007 | Loaded screen shows Next Launch, Name and Mission. | Legacy View; inferred | Source inspected | ViewModel tests plus manual smoke | Pass | Codex, 2026-09-07, iPhone Air/iOS 26.2 |

## Existing defects exposed and approved corrections

| ID | Original defect | Approved correction | Evidence/result |
| --- | --- | --- | --- |
| DEF-001 | Refresh guard reset before request finished. | Screen replaces its previous Task; newest feature request owns publication. | Managed-task replacement test passes |
| DEF-002 | Older response could overwrite newer data. | Check operation identity and cancellation before publication. | Reversed-success, reversed-failure and cancelled-success tests pass |
| DEF-003 | Empty response entered success with placeholder content. | Explicit empty state, no invented launch, Refresh remains available. | Feature/API/ViewModel empty tests pass; manual empty screen pending |
| DEF-004 | Errors/status discarded or printed only. | Preserve transport errors; reject failed HTTP status; publish classified recoverable failure. | API HTTP/transport/invalid-data tests and feature classification pass; manual error/retry pending |
| DEF-005 | Refresh disappeared after success. | Keep Refresh button after load; show Try Again on failure. | Repeated live simulator refresh passed; manual offline recovery pending |
| DEF-006 | Parent constructed ViewModel inside body. | Screen owns State model; initializers remain cheap; deinit cancels work. | Owner-release/lifecycle tests pass; live screen works |
| DEF-007 | Null estimated date components failed decoding. | Preserve unknown components as nil; reject malformed types. | Five decoding regressions and repository null-date test pass |

Cancellation restores the last settled state without displaying a cancellation error. A replacement cancelled before completion does not allow an older superseded result to publish. App-store readiness, global multi-window deduplication and real-device performance guarantees are not asserted.

## Test and manual record

- macOS: 35 identical XCTest cases passed under Swift 6.
- iPhone Air Simulator, iOS 26.2: 35 XCTest cases passed in Xcode at 12:29 Bangkok time on 2026-09-07; zero failures.
- Manual simulator: Codex observed idle screen, clicked Refresh, observed live result and clicked Refresh again after success. Screenshot reviewed for the screen layout. Date: 2026-09-07.
- Earlier user check: callback app launched, but null-date decoding failed; defect was fixed and regression-tested before this concurrency phase.
- Pending: manual offline → visible error → reconnect → retry; manual empty response; large Dynamic Type/VoiceOver and physical-device responsiveness review.

The test suite deterministically exercises failures/empty states without depending on the public service. Those tests do not replace the pending manual checks. Overall migration acceptance remains open until the developer reviews the result and the required manual checks are recorded.

## Product revision: fully free launch utility (2026-09-07)

The developer superseded the tabbed/IAP direction: no paid offering. The UI now starts loading when shown, rather than requiring an initial button tap (supersedes BEH-006). ViewModel construction itself still starts no networking. Missing UI values use explicit unpublished/unknown text rather than “None” (updates BEH-001 presentation). The first returned launch remains authoritative; provider, vehicle, launch-site country, mission purpose and planned/estimated time are now displayed. Source timestamps with minute, second or fractional-second precision are supported. About is an information sheet.

## Progressive operator tabs — 2026-09-07

The latest product instruction supersedes the single-screen design. Next remains fixed; operator tabs appear as API results arrive. Two live APIs now have independent in-memory caches, source failure states and cooldown-aware refresh. A task group publishes each source independently; shared root task ownership survives tab changes. Source-qualified rows open detail snapshots. LaunchScheduleFeature stores the next candidate and updates it on source commits and clock events. See MULTI_PROVIDER_DESIGN.md for current selection policy, source limits and verification. Third source and cross-source conflict reconciliation remain unresolved; no fake integration was added.
