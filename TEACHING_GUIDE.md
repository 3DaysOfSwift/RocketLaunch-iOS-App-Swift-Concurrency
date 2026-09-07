# Teaching Swift Concurrency with Feature Actors

This is a guided route through the current RocketLaunch implementation, not a claim that every app needs this amount of coordination. The repository contains the completed implementation; the stages below are lesson and exercise plans, not separate implemented branches.

## Prerequisites and outcome

Students should know Swift value/reference types, protocols, SwiftUI state and basic async/await. By the end, they should be able to identify the owner of mutable state, explain what may change across an await, and choose a task lifetime deliberately.

Read ARCHITECTURE.md first. Use SWIFT_CONCURRENCY_WITH_FEATURE_ACTORS.md for the architectural explanation and CONCURRENCY_INVENTORY.md to trace ownership. The names AppModel and Feature are conventions for this project, not Swift language requirements.

## Day 1 — One request and a clear boundary

Begin with RocketLaunchAPI, LaunchRepository, AppModel and LaunchScheduleViewModel. Follow one command from the main-actor view model into the feature, through the API and back as a value. Initially explain only one provider; leave sharing, reminders and streams for later lessons.

Explain that URLSession suspends while waiting for I/O. Decoding is synchronous work performed from the API actor. Merely adding async to a function does not choose a background executor. An actor is an isolation boundary, not a dedicated thread.

Exercise: inject a fixture repository and show loaded, empty and failed results without a network connection. Ask students to locate where the business decision ends and presentation formatting begins. Use the repository decoding tests and LaunchScheduleFeatureTests to check their answers.

Checkpoint: students can explain why AppModel can be MainActor while the business actor is not, and why a synchronous helper called inside the actor need not create another Task.

## Day 2 — Independent providers and task ownership

Trace refresh(), refresh(source:), registerRefresh and cancelRefresh. The task group owns child callers; the feature separately owns shared downloads. This implementation combines structured concurrency with explicitly owned unstructured tasks. It is not wholly structured simply because refresh-all uses a task group.

Introduce independent source snapshots and progressive publication. One provider can finish or fail while another is suspended. bufferingNewest(1) is suitable here because each element is complete current state; it would be wrong for an event log whose every event must be processed.

Exercise: suspend two fixture providers and release them in reverse order. Then cancel one caller sharing a request; the other caller must still receive its result. Cancel the last caller and release its old transport afterward; the obsolete result must not commit. Use SharedRefreshTests and the progressive-loading tests as concrete examples.

Checkpoint: students can name the owner and end condition of each Task. They can explain why cancellation is cooperative, why a request ID is still needed and why a canceled download can temporarily coexist with its replacement.

## Day 3 — Business consistency across suspension

Start with the older-screen problem: a detail screen holds an immutable launch whose time is now outdated. Have the screen submit the source-qualified ID and lead time. The actor looks up the current launch and validates and stores desired reminder state without await.

Trace setReminder, prepareReminder, reconcileReminders and deliverReminder. State that must change consistently shares one actor. This is why launches and reminder decisions share an owner even though they have separate screens and snapshots.

Exercise: hold notification scheduling, change the launch time, refresh again and finally release the older scheduling operation. Predict which record survives and which notification ID must be canceled. Run testNewRefreshDownloadsWhilePreviousNotificationIsSuspended and testSaveByIDUsesCurrentCacheDespiteOldScreenValue in UnifiedReminderTests.

Then remove the reminder while scheduling is suspended. Explain why canceling a task is not a rollback of an external system operation. Notification effects have their own lifetime so a slow effect cannot keep a completed download in flight.

Checkpoint: students can distinguish stored intent, accepted notification scheduling and actual alert delivery. They can explain pending, scheduled, failed and superseded without claiming an atomic transaction across UserDefaults and iOS notifications.

## A compact demonstration of the design change

| Scenario | Tempting implementation | Required behaviour in this app |
| --- | --- | --- |
| Old screen saves a reminder | Send its entire launch value back | Resolve ID using the current actor cache |
| Two refresh callers overlap | Cancel the first or start duplicate downloads | Share the active request and track callers independently |
| Old notification finishes late | Mark the current reminder successful | Check its unique notification identity and clean up obsolete work |
| Notification scheduling stalls | Keep refresh registered until it finishes | Complete the model commit and own effects separately |

For a live demonstration, make a temporary teaching copy and deliberately remove one guard. Run the relevant regression before restoring it. Do not present intentionally broken code as a production alternative.

## Language to use accurately

- Actors prevent unsynchronized access to their isolated state. They do not make a whole async method indivisible across awaits.
- Actor execution is not a FIFO guarantee for concurrently submitted commands. This app's current desired identity decides which external completion is still relevant.
- Task groups provide structured child lifetimes. Task {} creates unstructured work whose ownership must be explained separately.
- Async network waiting frees execution resources. It does not mean that all CPU cores are processing the request.
- MainActor owns presentation here. Small formatting and presentation filters remain there; measure their cost before claiming the interface cannot stall.
- Persistence here uses UserDefaults. It is not a transactional or crash-durable outbox. On restart, interrupted pending state is flagged; system notification reconciliation is not implemented.

These language rules follow Swift's [actor proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md) and [structured concurrency proposal](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md). The task ownership and reminder policies are project-specific decisions.

## Scope and release evidence

Teach the model boundary as reusable. Introduce shared downloads, streams and notification effects only when the app's requirements justify them. A small feature with a single caller may need only an actor method returning a value.

Use TEACHING_VALIDATION.md for dated evidence and remaining device checks. Automated model tests do not prove physical alert delivery or establish a responsiveness benchmark. The source-qualified ID identifies a provider record; matching the same real launch across providers is a different problem.
