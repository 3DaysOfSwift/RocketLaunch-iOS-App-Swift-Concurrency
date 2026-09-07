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
