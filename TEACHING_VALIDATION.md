# Teaching validation — 7 September 2026

## Result

The source and teaching pass is complete. RocketLaunch is suitable for teaching actor ownership, progressive async work, cancellation and reentrancy through a worked example. This is not a certification of fault-free software or a measured physical-device performance claim.

## Evidence from this pass

| Check | Result | Scope |
| --- | --- | --- |
| macOS host XCTest run | 98 passed, 0 failures, 18:20:16 local time | Real model, view model and theme sources; controlled dependencies |
| Xcode simulator XCTest run | 98 passed, 0 failures, 18:20:42 local time | Xcode 26.2, iPhone Air simulator, iOS 26.2; includes app/test compilation |
| Reminder refresh regression | Passed in both runs | A new download completes while an old notification operation is suspended; obsolete alert identity is cleaned up |
| Actor and task ownership review | No additional confirmed correctness defect found in reviewed paths | Does not exhaust every possible interleaving |
| Instruments | Captured a 20-second simulator launch using Time Profiler through Xcode | Trace remains open in Instruments, not exported. No interaction workload, main-thread call-tree analysis or device benchmark was completed |
| Documentation review | Updated | Three-day progression, scoped claims, task ownership and scheduling-versus-delivery distinction |

Command-line Instruments failed to initialize its cache directory due to filesystem permissions. Xcode's GUI profiling route successfully recorded the simulator process. Capturing a trace is not the same as analyzing responsiveness: no numerical performance conclusion is claimed from this recording.

Implementation cleanup made completeRefresh synchronous and Request.previous immutable. This makes the no-suspension commit boundary explicit without changing its behaviour. No new architecture layer was introduced.

## Remaining device validation

These are unexecuted checks, not passed tests. Use a development device and a controlled launch fixture with a near-future time so the exercise does not depend on a live provider changing its schedule. Keep fixture timing changes in a test configuration, not the production API mapping.

| Scenario | Procedure and expected observation |
| --- | --- |
| First permission prompt | Save, allow, inspect scheduled state and then background the app. Confirm the alert appears once at the intended time. Record device OS and notification settings. |
| Denied permission | Save and deny. Confirm failed intent remains visible; enable permission in Settings and retry. Confirm only the current request is pending. |
| Replace/remove while scheduling | Hold a test notification client before completion, change time or remove, then release. The automated tests cover the model ordering; repeat with actual iOS request inspection to validate integration. |
| Background and return | Start refresh, background, return and verify useful cached data and recoverable source states. Do not assume the process keeps running indefinitely in the background. |
| Terminate/relaunch | Terminate around notification acceptance. On relaunch inspect both stored reminder state and iOS pending requests. Current recovery flags stored pending records as interrupted; it does not reconcile the system's pending requests. Record this limitation explicitly. |
| Revoked notification authorization | Disable notifications outside the app after scheduling. Observe the difference between previously accepted scheduling and current permission; do not describe scheduled status as guaranteed alert delivery. |

A restart can occur after iOS accepted a notification but before the model persisted scheduled status. This architecture does not make those two systems transactional. If automatic recovery is a product requirement, implement and test reconciliation against pending system requests before claiming it is supported.

## Performance exercise to finish

On a physical device, record launch, refresh, rapid tab changes, list scrolling and detail navigation using Time Profiler and an interaction/hitch instrument. Include representative cached data and a slow provider. Inspect the main-thread call tree for decoding, model sorting and persistence, and inspect any visible stalls. Save the trace with device, OS, build configuration, workload and observations. A simulator launch recording alone does not demonstrate sustained interactive performance.

## Publication wording

Supported: “An actor-based application model with main-actor presentation state, explicit task ownership and regression-tested ordering.”

Unsupported: “All work runs off the main thread”, “five extra CPUs are guaranteed”, “fully structured concurrency”, “notifications are transactionally saved”, or “proven free of UI stalls”.

Use TEACHING_GUIDE.md for the lesson sequence. Historical migration records retain earlier validation checkpoints; this document describes this pass.
