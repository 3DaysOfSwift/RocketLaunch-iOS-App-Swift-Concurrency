# Current migration status — 2026-09-07

Swift Concurrency/Observation implementation is ready for final review. Original archive and callback checkpoints remain preserved. App and tests now target iOS 17 and Swift 6 with complete concurrency checks. The user has not yet signed off the completed migration.

Current account-wide usage: 71% used / 29% remaining. Compared with the initial 66% used baseline, the rounded change is 5 percentage points across all account activity, not an exact per-migration credit charge.

## Completed implementation

- AppModel remains the composition root; one MainActor observable LaunchScheduleManager owns feature state.
- Domain values are immutable/Sendable; transport payloads are private to the feature's repository.
- Native async URLSession replaces NetworkManager and callbacks. The repository actor owns decoding and maps transport data to domain values.
- MainActor replaces manual queue hops; Observation replaces Combine. The screen owns its ViewModel with State.
- Request identity prevents stale publication. The ViewModel owns/cancels replaceable Tasks and does not retain itself through the pending operation.
- Empty/error/retry states and refresh-after-success are implemented as approved. Successful content remains available during refresh/failure. Cancellation restores settled state.
- UI palette is explicitly owned by AppColourTheme/ThemeManager, with a development-only alternate palette.

## Phase audit

| Pass | Status and evidence |
| --- | --- |
| 1–4: ownership and architecture | Implemented; callback baseline/characterisation checkpoint preserved. User ran callback app and reported decoding defect, then authorized continuation after repair. |
| 5–6: Model/UI concurrency | Implemented and tested; native async API, explicit actors, real cancellation and stale-response tests. |
| 7–8: feature/test folders | Implemented; feature owns networking/domain files; six focused XCTest suites plus shared fixtures. |
| 9–10: cooperative execution | Source/isolation audit and runtime tests passed. No audio/ticker/caching work applies. Physical-device profiling is pending; no measured performance improvement claimed. |
| 12: Observation | Approved and implemented; iOS 17 minimum, observable feature/ViewModel/theme, State-owned ViewModel, protocol observation and lifetime tests pass. |
| 13–15: execution/concurrency review | Repository actor owns decode; MainActor performs short state/presentation work. Reviewed overlap, failure, cancellation, owner destruction and preserved content. Tests pass. Additional manual recovery/profiling remains pending. |
| 16: final iterative review | OPEN for developer acceptance and remaining manual checks. No new concrete implementation defect identified in the current audit. |

## Verification

- All 35 XCTest cases passed on macOS with Swift 6.
- All 35 passed in Xcode on iPhone Air, iOS 26.2 (12:29 Bangkok, 2026-09-07).
- Generic iOS device test build and Release app build passed.
- The shell initially blocked nested Apple macro sandbox execution. A temporary compiler invocation flag enabled device/Release verification inside the existing execution environment. No sandbox or checking override was written to project settings. Normal Xcode simulator builds/tests passed.
- Manual live API smoke: idle → Refresh → displayed next launch; Refresh remained available and subsequent requests completed. Screen screenshot reviewed.
- Pending: manual offline/recovery and empty screens; accessibility/device profiling; developer final review. See MIGRATION_REVIEW.md.

No Git commit, push or official final feature report has been created in this phase. The feature report remains the post-acceptance handover required by the skill.

---

# Earlier checkpoint history

# Migration ledger

## Status

Historical callback checkpoint (superseded by the current status below). Original archive retained with SHA-256. No Git commit created.

## Verification

- Original: generic iOS device Debug build passed, signing disabled.
- Original: eight deterministic characterisation checks passed.
- Pass 1: generic iOS device build and all eight checks passed.
- Callback architecture checkpoint: generic iOS device build and all eight checks passed.
- Manual iOS regression: pending; simulator service unavailable.
- Original contains no XCTest target. A reproducible external characterisation runner establishes baseline evidence without changing original sources.

## Ownership ledger

| Original owner | Responsibility | Current owner | Intended owner | Remaining work |
| --- | --- | --- | --- | --- |
| ContentView | Construct screen ViewModel | LaunchScheduleView StateObject | Same screen using State/Observation | Approved iOS 17 change later |
| System | Assemble live dependencies | AppModel.live | AppModel.live | None for construction |
| RocketLaunchCalender | Coordinate schedule refresh | LaunchScheduleManager | LaunchScheduleManager | Replace callback lifetime; fix guard |
| LaunchScheduleViewModel | Select first returned launch | LaunchScheduleManager | LaunchScheduleManager | Preserve selection in async tests |
| LaunchScheduleViewModel | UI values and publishing | LaunchScheduleViewModel | MainActor observable ViewModel | Async intent and managed task lifetime |
| RocketLaunchAPI | Fetch/decode transport page | RocketLaunchAPI via LaunchRepository | Feature-owned network repository | Async URLSession, status/errors, cancellation |
| NetworkManager | URLSession callback | NetworkManager | Network repository | Remove unnecessary wrapper during async conversion |
| RocketLaunchDataTypes | API payload structures | Feature folder, temporary transport/domain overlap | Private DTOs under networking; small domain Launch | Split without changing visible content |

## Pass status

1. Screen lifetime and adjacency: implementation/build checks passed. Root ContentView is stateless composition and needs no artificial ViewModel.
2. Composition root: AppModel created with explicit dependency and live factory.
3. Feature extraction: narrow LaunchScheduleFeature and LaunchRepository added; first-result selection belongs to the feature.
4. Architecture milestone: IN PROGRESS, manual comparison and final boundary audit pending. Callback-era transport/domain types and screen-owned result are explicitly temporary. Do not label these the final template.
5–6. Swift Concurrency/SwiftUI integration: NOT STARTED.
7–10. Ownership, tests and execution audit: NOT COMPLETE; only relevant work will be applied. Audio/ticker requirements from Metro-specific examples are not applicable to this app.
12. Observation: approved with iOS 17; NOT STARTED.
13–16. Execution/refinement/final review: NOT STARTED. Completion requires real evidence and developer review.

## Approved scope changes

- User: Use iOS 17 and Observation.
- User: Fix identified refresh, stale-response, empty-result and error/retry defects during migration, preserving single-API scope.

## Usage baseline

2026-09-07 before migration implementation: 66% weekly allowance used / 34% remaining. Percentages are account-wide, rounded reports, not per-project credits. Concurrent work prevents exact attribution.

Checkpoint usage report: 67% used / 33% remaining. Reported account-wide change since the start is 1 percentage point; this is rounded and not an exact migration credit cost.

## Live baseline defect correction — 2026-09-07

User confirmed the app launches in the simulator, but the downloaded response failed decoding a null estimated day. Corrected optionality of LaunchDate month/day/year under explicit user authorization. Preserved original archive and Original project. Five decoding regression checks added inside this Git repository; complete legacy behaviour checks remain available outside it. This is an existing defect exposed by manual validation, not a key-name mismatch. Git initialization was performed by the user; no remote created or commit made by the assistant.

## Xcode test-target checkpoint — 2026-09-07

- Added the hosted `RocketLaunchTests` iOS target, target dependency, generated test Info.plist, test resource membership and shared RocketLaunch scheme. Cmd-U now includes the test target.
- Migrated the five standalone JSON checks into XCTest. Added 17 cases for feature, ViewModel, composition and real networking boundaries, for 22 total.
- Added explicit URLSession injection in NetworkManager; AppModel.live continues using URLSession.shared. This changes testability, not live request behaviour.
- Defect characterisation cases are labelled as transitional evidence, not acceptance of broken behaviour. Replace these assertions when the approved concurrency/error-state fixes land.
- Generic iOS device `build-for-testing` passed with signing disabled. This verifies both app and test compilation/linking.
- Same 22 XCTest cases passed on macOS through Tests/run-host-tests.py, with no live network and zero failures. The runner copies current production Model/ViewModel sources into an ephemeral package; it does not create a competing implementation.
- iOS simulator execution remains unavailable to this process. The user can run the shared scheme with Cmd-U. No iOS runtime result is claimed.
- Concurrency migration remains pending; this checkpoint supplies its regression protection. No deployment target or product behaviour change was introduced here.
