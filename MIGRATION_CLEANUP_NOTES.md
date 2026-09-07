# Migration cleanup notes

Track developer corrections here so they can inform an additional cleanup pass in the migration instructions. These notes do not yet modify the migration skill.

## 1. Feature naming and declaration placement

- **Mistake:** Named the concrete feature `LaunchScheduleManager` and put its API protocol in a separate `LaunchScheduleFeature.swift` file.
- **Required convention:** Name the concrete feature `LaunchScheduleFeature`. Name its API protocol `LaunchScheduleFeatureAPI` and declare it above the implementation in the same `LaunchScheduleFeature.swift` file. Do not create a separate file for every declaration by default.
- **Correction:** Combined the protocol, implementation and associated state/error declarations into `LaunchScheduleFeature.swift`; updated composition, tests, Xcode references and documentation.
- **Proposed cleanup check:** Review each migrated feature for a concrete class named `<DomainName>Feature`, an API protocol named `<DomainName>FeatureAPI`, and colocated protocol/implementation. Split declarations only when there is a concrete reason.

- **Naming refinement:** The developer subsequently chose `LaunchScheduleFeature` / `LaunchScheduleFeatureAPI` in place of the initial `LaunchSchedule` / `LaunchScheduleFeature` pairing. Stored properties can use the concise domain name `launchSchedule`. Use this latest convention in the cleanup pass.

## Feature additions during UI work

- Register new feature and ViewModel files in the Xcode target; the host test runner discovers files independently and alone cannot establish Xcode membership.
- Keep source cache commits settled before awaiting downstream reminder updates so replacement requests roll back to the latest accepted data.
- Notification replacement needs unique request IDs and stale-completion rejection, including removal while scheduling is suspended.
- Keep country filter aliases consistent across data sources.

## Actor feature migration pass

- An async Feature API marked MainActor does not offload business computation. Use separate concrete feature actors when the intended contract is off-main business ownership.
- Replace direct observable feature reads with immutable Sendable snapshots held by MainActor ViewModels. Register streams and initial replay atomically; use independent subscribers, bounded buffering, revisions and explicit consumer task ownership.
- Do not perform persistence in a main-actor composition initializer. Load lazily inside the owning feature actor.
- Revisit every await boundary for reentrancy, including feature-to-feature notifications. Source revisions and operation IDs serve different ordering purposes.
- Update tests to await snapshots and verify progressive UI publication, subscriber cancellation, off-main business work and main-actor observation.

## Concurrency review — 7 September 2026

Review used an isolated temporary copy; production code was not changed. The existing 77 tests passed, but two additional deterministic tests failed. These cases must be added as regressions when fixing the implementation:

1. **A suspended reminder reschedule can outlive a newer source revision.** Save time T1, suspend revision 2 while scheduling T2, then reconcile revision 3 containing T1. Revision 3 skips the record because the stored reminder still says T1, leaving revision 2's operation token valid. Resuming revision 2 incorrectly commits T2. Check freshness at the side-effect commit boundary and invalidate superseded pending work even when the latest record matches currently stored state. Cancel any obsolete newly scheduled notification while preserving the latest valid reminder.
2. **The reminder capacity check does not include pending additions.** With 49 saved reminders, suspend the 50th addition, then save a different launch. Both calls pass the pre-await capacity guard and 51 records can commit. Reserve capacity across suspension or revalidate before commit and cancel a rejected notification. The ViewModel's busy flag is not the feature's concurrency invariant.

Smaller cleanup candidates: put authoritative load-if-needed decisions inside the feature (a new ViewModel initially has an idle projection even when the shared feature is loaded); avoid publishing unchanged clock snapshots; remove the obsolete operator tab-title helper; replace independently optional reconciliation source/revision parameters with a coherent typed update if that API is retained.

The actor/snapshot structure remains appropriate. These findings refine reentrancy protection; they do not require replacing the architecture. Prior statements that source revisions fully prevent stale reminder reconciliation were too broad: the existing sequential ordering test did not cover an already suspended scheduling operation.

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

## Follow-up concurrency review — 7 September 2026

The previous six fixes remain in place. A fresh review ran the 88 existing tests plus two additional reproductions in an isolated copy: 90 tests, two failures, both new cases. Production code was not changed during this review.

1. **P2 — First reminder save can miss a source update while suspended.** `save` calls `schedule` without source metadata; `isCurrent(nil)` always returns true. If notification scheduling (including permission handling) suspends before the first record is committed, `reconcile` sees no saved record and skips it. A changed source time is therefore accepted by the launch feature while the first save subsequently commits its old time and notification. Reproduced by suspending the first save for T1, reconciling a source update for T2, then completing the save: T1 is still committed. Extend reconciliation/freshness handling to pending first saves, with an explicit result for superseded user commands. The earlier fix covered rescheduling existing records, not this case.
2. **P2 — Partial initial-load cancellation leaves an idle provider unrequested on reappearance.** When provider A commits and provider B is canceled, B rolls back to idle. `loadIfNeeded` requires every source to be idle, so A's loaded state prevents retrying B. Reproduced with controlled repositories: after reappearance B still has only its original request. Load only sources still needing their initial result, preserving completed caches and the existing in-progress/cooldown protections. Full explicit refresh remains a workaround.

Smaller cleanup: make superseded reminder command outcomes explicit instead of returning ordinary Void success after canceling an obsolete notification; document command policies (ignore overlapping button taps, replace same-launch pending work, reconcile accepted source versions). The redundant schedule catch that clears the same token as defer can also be simplified. These do not justify a generic concurrency framework.

Reevaluation: AppModel composition, ordinary feature actors, MainActor snapshots and structured provider fan-out remain appropriate. The outstanding work is cross-operation business ordering and partial lifecycle recovery. Passing tests establish the scenarios covered; the previous reevaluation did not cover these two combinations. Device performance profiling and real notification delivery remain unmeasured.

## Follow-up fixes completed — 7 September 2026

Resolved both findings from the follow-up review. Pending reminder operations retain the launch being saved; accepted source updates invalidate changed pending times before any reconciliation suspension. This covers first saves without a persisted record. Obsolete successes cancel their own notification, obsolete failures return the same superseded outcome, and unchanged refreshes preserve pending saves. ReminderSaveOutcome distinguishes committed saves from superseded commands; the ViewModel shows an explanatory message. The redundant token cleanup in catch was removed; defer remains the owner of token cleanup.

loadIfNeeded now requests only idle providers after a partial initial load has settled, retaining completed provider caches and existing cooldown/in-progress guards. The review reproduction now uses explicit request expectations rather than a timed sleep.

Validation: all 94 XCTest cases passed on macOS and iPhone Air Simulator (iOS 26.2), including six new tests for pending first-save freshness, unknown times, unchanged updates, stale scheduling failures, double-tap/UI outcome handling, and partial-load recovery. Existing removal and concurrent-capacity tests also assert the new command outcomes. Xcode compiled the application and test bundle successfully.

Reevaluation: the two reproduced cases are resolved; existing actor-boundary, progressive-publication, cancellation and capacity tests still pass. AppModel composition and feature actors remain unchanged in their roles. Notification clients are test doubles; real device delivery and Instruments performance measurements remain separate validation work. No claim is made that these tests exhaust every possible interleaving.

## Boundary review — 7 September 2026

Reviewed the working tree including the previous fixes. An isolated host-test copy ran the 94 existing cases plus three new checks: 97 tests, three failures, all in the new checks. Application and test sources in this repository were not changed by this review.

1. **P2 — A save from a stale detail value can undo a completed reconciliation.** LaunchDetailView holds a selected RocketLaunch value and sends it back on Update reminder. After reconciliation accepts T2, saving the older detail value T1 overwrites the reminder with T1. The pending-save check cannot catch an update that already completed before save began. Reproduced by saving T1, reconciling T2, then saving T1 with a new lead time. Define a freshness contract for incoming save commands: resolve current launch data by identity or reject a stale version. UI intent should supply reminder preferences without becoming authoritative for launch time.
2. **P2 — Reappearance while cancellation is still settling drops the new load intent.** loadIfNeeded returns while initialLoadInProgress is true, even if that work has been canceled. After the old request unwinds and rolls back to idle there is no retained retry intent. The previous partial-load fix covers reentry after cancellation completes, not reentry during it. Reproduced with a repository held suspended until after the new load call. Preserve or await the new intent through cancellation completion, respecting the new caller's lifetime.
3. **P2 — Cancel-and-replace refresh conflicts with cooldown.** The ViewModel cancels an active refresh before starting its replacement. A cooldown-bearing provider rejects the replacement while the original attempt's cooldown remains set. The original then exits due to cancellation, leaving no completed request. Upcoming/Operators refresh actions can trigger this sequence. Reproduced with a five-minute provider cooldown and delayed cancellation completion. Coordinate active-request ownership with cooldown: join/retain useful work or arrange an accepted replacement before discarding it, without bypassing rate-limit policy.

Recommended next pass: specify source freshness and active-request lifecycle together, and test both orderings around each relevant suspension. Preserve the existing actor/snapshot architecture. Additional abstraction or more actors would not resolve these business policies. Optional readability cleanup is lower priority than these three behaviors.

## Shared launch and reminder actor — 7 September 2026

Developer approved grouping launch data and reminder decisions under the same actor. LaunchScheduleFeature now owns both sets of authoritative state. AppModel owns one business actor; the separate RemindersFeature/RemindersFeatureAPI and LaunchSourceUpdate callback/revision protocol have been removed. LaunchReminders.swift contains reminder values and the notification client; the actor API and implementation stay together.

The UI sends launch ID and lead time. Lookup, validation, capacity and desired-state persistence happen without suspension. Source commits synchronously update pending and saved desired reminders before external scheduling. Notification identities serve as effect revisions: stale success is canceled, stale failure cannot damage a newer record, and removal cannot be undone by late delivery. Delivery status is pending/scheduled/failed. Failed records remain available for retry/removal and count toward capacity. Older persisted records decode without the new field; interrupted pending records are flagged on reload.

Refresh policy now joins active provider requests. ViewModels ignore repeated active refresh taps. The actor owns one request Task per provider with cancellation-aware waiters. Last-waiter cancellation detaches ownership immediately and rejects old results; a new screen can resume loading before old transport has finished. Joining active work does not create a new HTTP request or bypass cooldown. Initial loading joins loading sources and fetches idle sources while retaining settled caches.

The notification client coalesces permission requests. Refresh effects may continue an active user save's permission intent; an ordinary refresh does not independently prompt. A second date check rejects notification scheduling that returned after its fire time passed.

Validation: 97 host XCTest cases pass. The iOS app and test bundle build successfully with Swift 6 complete concurrency checking. The preceding two-actor suite's obsolete API tests were replaced with 19 unified reminder tests and four shared-request tests, while existing relevant tests remain/adapt to the new policies. Current simulator execution was blocked by the locked Mac. No physical-device delivery or performance benchmark is claimed.

Reevaluation: the three recorded boundary defects are addressed by current-data lookup and shared request ownership, rather than more cross-actor revision patches. The core business decision is now one actor transaction; external side effects remain explicitly versioned. Architecture and concurrency guides have been updated, including the diagram. Simulator regression and real notification verification remain open.
