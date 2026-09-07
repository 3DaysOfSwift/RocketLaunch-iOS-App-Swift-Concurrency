# Migration review

Implementation checkpoint: 2026-09-07, uncommitted working tree. Overall acceptance remains pending.

## Architecture checklist

| Check | Assessment and evidence |
| --- | --- |
| Folder ownership | View, AppModel and resources separated; Launch Schedule owns all domain/network files. |
| Screen ViewModel ownership | One LaunchScheduleViewModel beside its screen, owned using State. ContentView is stateless composition. |
| Clean screen construction | No screen receives feature managers, ViewModels or service closures. Theme is UI environment state. |
| Business rules below UI | Feature selects the first launch; domain supplies primary mission semantics. ViewModel formats display values. |
| Narrow feature dependencies | ViewModel depends only on LaunchScheduleFeatureAPI; AppModel dependencies are explicit. |
| External-system boundary | Sendable LaunchRepository isolates native URLSession and private transport decoding. |
| Async commands/lifetimes | Feature and ViewModel refresh are directly awaitable; managed screen Task lives only in ViewModel. |
| Required ordering | Latest accepted request owns publication. Reversed successes/failures and cancellation are tested. |
| Deterministic inputs | Fixed response fixtures and controlled continuations. No clock-dependent rule exists. |
| Test ownership | Dedicated ViewModel/theme suites and separate construction/feature/API/decoding suites. |
| Minimal layers | Deleted NetworkManager wrapper; one repository actor, one feature manager; no task group without independent work. |
| Authoritative state | Feature state is read-only externally. ViewModels compute values instead of copying domain state. |
| MainActor availability | JSON mapping/decoding lives in repository actor. Only short state and presentation work stays on MainActor. |
| Failure honesty | Explicit empty, failed and loading states; retained content; native transport and HTTP failures mapped to recovery messages. |
| Domain ownership | Immutable feature-owned values; private DTOs/CodingKeys under networking. |
| Observation | Real screen updated after live async refresh; computed/protocol sharing and theme changes tested. |
| Thread-safety escape hatches | No production unchecked Sendable. Test URLProtocol store uses a documented lock invariant. |
| UI usability | Scrollable layout, semantic text sizes, accessible identifiers/headings. Live normal-size layout checked. Larger sizes/VoiceOver pending. |
| Profiling | No timing-sensitive workload or performance regression observed during basic smoke, but no device benchmark/profile collected. |
| Final acceptance | Pending developer review and manual offline/empty/retry checks. |

## Remaining manual checks

1. Confirm current screen and Refresh behaviour meet expectations.
2. With connectivity unavailable, request a refresh: error should be visible, previous launch retained if available, Try Again offered.
3. Restore connectivity and tap Try Again: successful content should return and the error disappear.
4. Review empty-state presentation with a controlled empty response if required; automated coverage already verifies it.
5. Check large Dynamic Type/VoiceOver and a physical device before treating this as a commercial reference.

The current audit found no further concrete architecture change worth adding. These outstanding validations must not be represented as completed, and the final feature report is intentionally deferred until acceptance.

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

## Follow-up fixes completed — 7 September 2026

Resolved both findings from the follow-up review. Pending reminder operations retain the launch being saved; accepted source updates invalidate changed pending times before any reconciliation suspension. This covers first saves without a persisted record. Obsolete successes cancel their own notification, obsolete failures return the same superseded outcome, and unchanged refreshes preserve pending saves. ReminderSaveOutcome distinguishes committed saves from superseded commands; the ViewModel shows an explanatory message. The redundant token cleanup in catch was removed; defer remains the owner of token cleanup.

loadIfNeeded now requests only idle providers after a partial initial load has settled, retaining completed provider caches and existing cooldown/in-progress guards. The review reproduction now uses explicit request expectations rather than a timed sleep.

Validation: all 94 XCTest cases passed on macOS and iPhone Air Simulator (iOS 26.2), including six new tests for pending first-save freshness, unknown times, unchanged updates, stale scheduling failures, double-tap/UI outcome handling, and partial-load recovery. Existing removal and concurrent-capacity tests also assert the new command outcomes. Xcode compiled the application and test bundle successfully.

Reevaluation: the two reproduced cases are resolved; existing actor-boundary, progressive-publication, cancellation and capacity tests still pass. AppModel composition and feature actors remain unchanged in their roles. Notification clients are test doubles; real device delivery and Instruments performance measurements remain separate validation work. No claim is made that these tests exhaust every possible interleaving.
