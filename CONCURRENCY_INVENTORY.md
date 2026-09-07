# Concurrency inventory — migrated implementation

| Legacy mechanism | Replacement and owner | Evidence |
| --- | --- | --- |
| URLSession.dataTask callback, discarded handle | Native async URLSession.data(from:) in RocketLaunchAPI actor | API success/error tests; testTaskCancellationStopsRealURLSessionRequest |
| DispatchQueue.main.async | MainActor isolation for observable feature and ViewModel | Swift 6 / complete checking; iOS tests |
| Ineffective isRefreshing/defer guard | ViewModel-owned replaceable Task plus feature request identity | testNewScreenRefreshCancelsPreviousTask; testOlderSuccessCannotOverwriteNewerSuccess |
| Completion-order publication | Latest accepted request owns state; cancellation checked before publication | Older-success/older-failure and cancelled-success tests |
| ObservableObject/Published | Observable feature, ViewModel and theme; State-owned screen model | Observation tests and live simulator refresh |
| Discarded transport errors/status | Throw native transport error; explicit HTTP and decoding failures | API tests; feature failure-classification test |

JSON decoding and domain mapping run synchronously on the repository actor after native asynchronous I/O. They do not run on the MainActor. An actor is not a dedicated thread. There is no app-level local cache, live observer, audio timer, persistence transaction or independent provider fan-out to migrate.

The only production Task handle belongs to LaunchScheduleViewModel. It is replaced on refresh and cancelled on disappearance/deinit. Directly awaited feature commands inherit their caller's cancellation. The feature also rejects obsolete responses across different callers without claiming to cancel every other caller's network Task.

The remaining checked continuations and locks are test fixtures, deliberately controlling operation order. No production @unchecked Sendable, callback continuation, GCD scheduling, blocking wait or detached Task remains.

Build settings: iOS 17.0, SWIFT_VERSION=6.0, SWIFT_STRICT_CONCURRENCY=complete for both configurations and targets. Xcode simulator execution passed all 35 tests. The restricted shell's nested macro sandbox required a one-command compiler option for device/Release verification; this option was not saved in project settings. Normal Xcode builds/tests passed without it.
