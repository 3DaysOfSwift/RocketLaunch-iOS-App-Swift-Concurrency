# Current migration status — 2026-09-07

Swift Concurrency/Observation implementation is ready for final review. Original archive and callback checkpoints remain preserved. App and tests now target iOS 17 and Swift 6 with complete concurrency checks. The user has not yet signed off the completed migration.

Current account-wide usage: 71% used / 29% remaining. Compared with the initial 66% used baseline, the rounded change is 5 percentage points across all account activity, not an exact per-migration credit charge.

## Completed implementation

- AppModel remains the composition root; one MainActor observable LaunchScheduleFeature owns feature state.
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
| RocketLaunchCalender | Coordinate schedule refresh | LaunchScheduleFeature | LaunchScheduleFeature | Replace callback lifetime; fix guard |
| LaunchScheduleViewModel | Select first returned launch | LaunchScheduleFeature | LaunchScheduleFeature | Preserve selection in async tests |
| LaunchScheduleViewModel | UI values and publishing | LaunchScheduleViewModel | MainActor observable ViewModel | Async intent and managed task lifetime |
| RocketLaunchAPI | Fetch/decode transport page | RocketLaunchAPI via LaunchRepository | Feature-owned network repository | Async URLSession, status/errors, cancellation |
| NetworkManager | URLSession callback | NetworkManager | Network repository | Remove unnecessary wrapper during async conversion |
| RocketLaunchDataTypes | API payload structures | Feature folder, temporary transport/domain overlap | Private DTOs under networking; small domain Launch | Split without changing visible content |

## Pass status

1. Screen lifetime and adjacency: implementation/build checks passed. Root ContentView is stateless composition and needs no artificial ViewModel.
2. Composition root: AppModel created with explicit dependency and live factory.
3. Feature extraction: narrow LaunchScheduleFeatureAPI and LaunchRepository added; first-result selection belongs to the feature.
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

Checkpoint usage report: 68% used / 33% remaining. Reported account-wide change since the start is 1 percentage point; this is rounded and not an exact migration credit cost.

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

## Progressive operator tabs — 2026-09-07

The latest product instruction supersedes the single-screen design. Next remains fixed; operator tabs appear as API results arrive. Two live APIs now have independent in-memory caches, source failure states and cooldown-aware refresh. A task group publishes each source independently; shared root task ownership survives tab changes. Source-qualified rows open detail snapshots. LaunchScheduleFeature stores the next candidate and updates it on source commits and clock events. See MULTI_PROVIDER_DESIGN.md for current selection policy, source limits and verification. Third source and cross-source conflict reconciliation remain unresolved; no fake integration was added.

## Third source: SpaceX API — 2026-09-07

Developer explicitly requested the community SpaceX API after reviewing its archived status. Added the documented query adapter, independent cache/status, source identity and attribution. Past/undated records are excluded from Next. Six additional fixture/behavior checks pass (59 host tests total), including HTTP failure and outdated schedule exclusion. No third-party endpoint reliability is claimed from those tests.

Live Simulator check: RocketLaunch.Live returned 5 records and Launch Library returned 50. The SpaceX request failed and displayed “Refresh failed · No data available” with its own refresh cooldown. Next and the other sources remained usable. The iOS Simulator build succeeded.

## Five fixed tabs — 2026-09-07

Supersedes the operator-per-tab layout with Next, Upcoming, Operators, Updates and Reminders. Added search and country/operator filters, conditional watch/information links, a session-scoped schedule-change log and persistent local reminders. AppModel composes both features; accepted refreshes reconcile changed notification times. Reminder permission, invalid dates, rescheduling, persistence, source identity, filters and change detection are covered by automated checks. 68 host tests pass; Simulator app build and live operator filtering were checked. Notification delivery has not been claimed as tested on a physical device.

## Feature actors and observable snapshots — 2026-09-07

Developer approved moving business features off MainActor. Converted LaunchScheduleFeature and RemindersFeature into actors with Sendable async protocols, immutable versioned snapshots and independent bounded AsyncStream subscriptions. Observable ViewModels now hold presentation snapshots and own subscription tasks. Moved reminder loading/encoding/UserDefaults work into its actor, moved upcoming eligibility/ordering out of BrowseViewModel, and separated operator rebuilding from clock events. Source revision checks protect cross-actor reminder reconciliation. Existing tests were adapted to async snapshots without removing their behavior assertions; seven new tests cover stream and actor boundaries (77 host tests passing). Live Simulator loaded both working providers and preserved independent SpaceX failure.

Actor-feature validation, 2026-09-07: all 77 XCTest cases passed in Xcode on iPhone Air Simulator (iOS 26.2), as well as in the macOS host runner. This supersedes earlier MainActor-feature descriptions; ARCHITECTURE.md and CONCURRENCY_INVENTORY.md describe the current actor/snapshot implementation. Performance profiling and physical-device notification delivery are not claimed by these checks.

## Concurrency cleanup completed — 7 September 2026

All six recorded items are resolved:

- Reminder reconciliation checks source freshness at the post-suspension commit and failure boundaries. Superseded successful scheduling cancels its own notification; a newer unchanged time preserves the existing valid alert. New unknown times invalidate pending replacements and cancel outdated alerts.
- Reminder capacity includes pending additions, with reservations released on completion, failure or removal. Replacement and removal tokens remain independent of source revisions.
- LaunchScheduleFeature owns loadIfNeeded and guards the initial operation before suspension. A fresh ViewModel delegates this decision instead of relying on its initial empty projection.
- Unchanged schedule snapshots are not published. Clock handling explicitly publishes cooldown expiry so retry controls do not become stuck.
- The unused operator tabTitle helper was removed.
- LaunchSourceUpdate keeps required source, revision and launch values together in the reconciliation API.

Validation: 88 XCTest cases passed on macOS and in Xcode on iPhone Air Simulator (iOS 26.2). This includes the two previously failing races and nine further regression cases. The iOS application builds successfully with Swift 6 and complete concurrency checking. Test notification clients verify final active notification IDs and obsolete-request cleanup; no physical-device notification delivery is claimed.

Reevaluation: these fixes preserve the existing AppModel composition, ordinary feature actors, structured provider fan-out and MainActor presentation snapshots. The recorded defects are resolved without adding detached tasks or a generic messaging framework. Runtime boundary and progressive-publication tests still pass. This review establishes the tested ordering and ownership guarantees, not universal freedom from races or measured UI performance. Instruments profiling and physical-device notification delivery remain separate validation work.
