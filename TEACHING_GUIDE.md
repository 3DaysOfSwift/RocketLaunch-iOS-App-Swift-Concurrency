# Day 1: Swift Concurrency with Feature Actors

## Learning outcome

Trace one user action from SwiftUI through a main-actor view model to an actor-owned model and back as an immutable snapshot. Explain why network waiting does not need a blocked thread, why actor isolation protects state, and why an await can allow other work to interleave.

## Preparation

Open `Swift Concurrency Project/RocketLaunch.xcodeproj`, select RocketLaunch and an installed iPhone simulator, and run the tests with ⌘U. Run the app before class and check the provider status sheet. Internet availability and launch times will vary. SpaceX is intentionally retained as a live failure example; do not promise it always fails in a particular way or at a particular time.

For deterministic demonstrations use the existing test target: `ControlledLaunchRepository`, `TestClock` and isolated URLSession fixtures let you control completion order without waiting for an actual launch. There is currently no switch that runs the whole UI against a scripted offline provider.

## Walkthrough

1. **Begin with the app.** Show Next, Upcoming and the source status sheet. Ask what should happen when one source fails while another succeeds.
2. **Find ownership.** Open `AppModel.swift`, then `LaunchScheduleFeature.swift`. AppModel constructs the graph; the feature actor owns business state. Construction does not start a request.
3. **Trace the boundary.** Open `LaunchScheduleViewModel.swift` and its refresh action. The view model owns observable presentation state on MainActor. It awaits the feature API and consumes complete snapshots.
4. **Follow the request.** Open `RocketLaunchAPI.swift`. URLSession suspends during the request; decoding occurs in the API actor. Returning a result does not authorize stale work to replace newer state.
5. **Observe independent completion.** Inspect `refresh()` and the shared request path. A task group starts provider callers; each source can settle and publish before the others. A long-lived shared request is explicitly owned rather than an ordinary child of one screen action.
6. **Explain state publication.** Follow `publish()` and `snapshots()`. Each observer receives current state and subsequent immutable snapshots. BufferingNewest(1) is appropriate for replaceable state, not a general-purpose event log.
7. **Test time as input.** Run `testElapsedLaunchCannotBecomeNext` and `testNextExpiresWhenClockPassesFinalCachedLaunch`. Advance TestClock and inspect the stored Next value. Time can change business validity even without a new network response.

## Exercises

- In a controlled repository test, complete the second provider before the first. Assert that its results are visible immediately.
- Make one source fail and another succeed. Assert both the usable result and the failed source status.
- Cancel one of two callers sharing a request. Explain why the other caller must keep its result.
- Advance the clock past the final launch. Verify Next becomes empty while the provider cache remains intact.

Keep each exercise focused on an observable contract. The test support supplies controlled completion and a synchronized clock; do not use arbitrary sleep delays to guess execution order.

## Language to use accurately

Actors provide isolation, not dedicated threads or CPU cores. An actor serializes its isolated work and may admit another operation when execution suspends. Async does not mean parallel, and Task does not automatically mean background execution. The UI boundary is MainActor; ordinary feature/API actors execute independently of it. Small presentation filtering still runs in view models.

Task groups provide structured child lifetimes. This app also owns unstructured tasks for shared requests, observation, notification permission and committed reminder effects. Explain the owner and cancellation policy rather than claiming every task is structured.

## Material for later lessons

Request identity checks, continuation-based waiters, last-caller cancellation, observer teardown and reminder reconciliation are advanced examples. For reminders, begin with the policy: look up the current launch by ID and commit desired state before suspension, then revalidate operation identity after external notification work. Actor safety does not make a sequence spanning await automatically atomic.

## End-of-lesson check

Students should be able to point to the owner of each mutable value, identify every suspension in one flow, describe what cancellation means for that flow, and demonstrate a failure with a deterministic test. They should not need to count threads to explain why the UI can stay responsive.
