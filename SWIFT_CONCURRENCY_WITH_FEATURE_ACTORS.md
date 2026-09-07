# Swift Concurrency with Feature Actors

**Modern iOS Architecture 26**  
A practical architecture for AppModel, feature actors and observable ViewModels.  
2026 edition · Developed through the RocketLaunch teaching application · 7 September 2026

> Keep the main actor focused on presentation. Give business features ownership of their state and processing. Connect them through asynchronous commands and immutable snapshots.

“Modern iOS Architecture 26” is the name of this reference edition. It describes our current architectural choices, not an Apple standard or a requirement to replace working architecture every year. The principles should remain useful as Swift and its frameworks evolve.

## 1. Three ideas that fit together

AppModel, KISS and feature actors answer different questions.

| Idea | Question it answers | Practical result |
| --- | --- | --- |
| **AppModel** | What constitutes the runnable application model, and who owns it? | An explicit composition root constructs features and connects their dependencies. |
| **Feature actors** | Where does business state live, and where does its processing execute? | Each substantial stateful feature has an isolated owner outside the main actor. |
| **KISS** | How much structure does this application actually need? | Clear responsibilities with a small number of useful types and boundaries. |
| **Observable ViewModels** | What state does this interface need to present? | Main-actor presentation state that the UI can read synchronously. |

Together, these ideas make the architectural separation between the interface and the model an execution boundary as well as an organizational boundary.

We do not need to invent a framework to express this. Swift already supplies actors, Sendable values, asynchronous functions, task groups, asynchronous sequences and Observation.

## 2. The model is the runnable application

In this architecture, “model” means more than the structs decoded from JSON. It includes the application's rules, feature state, calculations, coordination and storage behavior. Those data structs are values used by the model.

RocketLaunch's model can retrieve launch data, maintain provider caches, group operators, choose the next launch, detect schedule changes and manage reminders without a SwiftUI screen telling it how to perform those operations. Tests invoke those capabilities directly through injected dependencies.

The interface expresses user intent and presents results. It does not decide which provider response is authoritative or whether an outdated launch qualifies as Next.

This is a deliberate interpretation of model separation. It is compatible with familiar separation-of-concerns principles, without claiming that every MVVM implementation or every piece of architecture literature prescribes this exact design.

## 3. The architecture at a glance

**AppModel constructs and owns two business features: launch scheduling and reminders. Each feature is an actor. Each has a main-actor ViewModel that presents its state to SwiftUI.**

The diagram below shows the actual RocketLaunch components and how they communicate after AppModel has connected them.

```mermaid
flowchart TB
    subgraph UI["Main actor · presentation"]
        Views["SwiftUI screens"]
        LaunchVM["LaunchScheduleViewModel<br/>Observable launch snapshot"]
        ReminderVM["ReminderViewModel<br/>Observable reminder snapshot"]
        Views -->|Launch intents| LaunchVM
        Views -->|Reminder intents| ReminderVM
    end

    subgraph Model["Application model · each actor has its own isolation"]
        LaunchFeature["LaunchScheduleFeature actor<br/>Caches · grouping · Changes · Next"]
        ReminderFeature["RemindersFeature actor<br/>Reminder rules · saved reminders"]
        RocketAPI["RocketLaunchAPI actor"]
        LibraryAPI["LaunchLibraryAPI actor"]
        SpaceXAPI["SpaceXAPI actor"]
        Notifications["LocalLaunchNotifications actor"]

        LaunchFeature -->|Fetch launches| RocketAPI
        LaunchFeature -->|Fetch launches| LibraryAPI
        LaunchFeature -->|Fetch launches| SpaceXAPI
        ReminderFeature -->|Schedule or cancel alerts| Notifications
        LaunchFeature -->|Accepted schedule changes| ReminderFeature
    end

    LaunchVM -->|Async feature commands| LaunchFeature
    LaunchFeature -->|Launch snapshots| LaunchVM
    ReminderVM -->|Async feature commands| ReminderFeature
    ReminderFeature -->|Reminder snapshots| ReminderVM
```

**There are two parallel feature paths:**

| Feature | Main-actor presentation | Actor-owned business work | Dependencies |
| --- | --- | --- | --- |
| Launch scheduling | LaunchScheduleViewModel | LaunchScheduleFeature | Three launch API actors |
| Reminders | ReminderViewModel | RemindersFeature | LocalLaunchNotifications actor; persistence inside the feature |

The ViewModels call their features through `LaunchScheduleFeatureAPI` and `RemindersFeatureAPI`. Those protocols describe the boundary; they are not additional runtime components. SwiftUI reads the observable snapshots held by the ViewModels to present the results.

The one connection between features has a specific purpose: an accepted launch refresh can change the time of an existing reminder. AppModel wires a callback that sends those launch records and their revision to RemindersFeature for reconciliation. The launch feature does not manage notification requests itself.

AppModel supplies ownership and wiring. The arrows show runtime communication. The application-model box groups related responsibilities; it does **not** represent one shared actor or one background thread.

## 4. Making effective use of Swift Concurrency

The goal is to leave execution resources available for useful work and keep expensive business processing away from UI execution. It is not to maximize the number of threads or force every CPU core to remain busy.

An asynchronous network operation can suspend while it waits for a response. A suspended task does not require a thread to sit waiting. Structured child tasks let independent operations overlap, while their parent retains responsibility for completion and cancellation. These are central parts of Swift's concurrency model. [Structured concurrency: SE-0304](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)

An ordinary feature actor provides a separate isolation domain. Its actor-isolated synchronous work runs through its executor, rather than being placed on the main actor. An actor serializes access to its state; it does not reserve a thread or a CPU core. Separate actors can make concurrent progress, and their work may execute in parallel when scheduling and hardware permit. [Actors: SE-0306](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md)

For RocketLaunch, this means launch calculations can proceed independently of rendering and interaction. It does **not** mean that one sorting operation automatically occupies five other CPU cores. If a future feature contains a large, divisible calculation, parallelizing that calculation is a separate, measured design decision.

### The boundary is actor isolation, not the word `async`

A main-actor ViewModel can call:

```swift
await feature.refresh()
```

When `feature` is our concrete feature actor, its actor-isolated method executes under that feature's isolation. The calling task can suspend and the main actor can process other work. When the ViewModel resumes its own isolated code, it resumes on the main actor.

Writing `async` on a MainActor method does not relocate its synchronous calculations. Likewise, `Task {}` created in a main-actor context generally inherits that actor context. Our separate concrete actors establish the intended execution boundary.

Swift 6.2 also introduced `@concurrent` for explicitly running a nonisolated asynchronous function away from the caller's actor. It can be useful for independent computations. This architecture does not depend on that annotation: its stateful business boundary is expressed with actors. Compiler settings affect the defaults for nonisolated async functions, so a team should document those settings rather than infer execution from `async` alone. [Async function isolation: SE-0461](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0461-async-function-isolation.md)

## 5. The team rule for the main actor

**The main actor owns presentation and UI interaction. Substantial business processing belongs to feature actors or appropriate services.**

| Main-actor responsibilities | Feature/service responsibilities |
| --- | --- |
| Observable presentation state | Authoritative business state |
| Navigation and transient interaction state | Eligibility and selection rules |
| Display formatting and small user filters | Grouping, substantial sorting and transformations |
| Theme selection | Data retrieval, decoding and persistence |
| Starting and managing UI-owned tasks | Coordinating business operations and publishing outcomes |

This is a responsibility rule, not a ban on every calculation on the main actor. Formatting a short label or applying a small screen filter may be entirely appropriate. If presentation work becomes expensive, measure it and move the expensive portion behind a suitable asynchronous boundary.

Likewise, placing blocking file or legacy API calls in an actor does not make those calls cooperative. They still occupy their executor's worker while running. Large synchronous I/O needs an appropriate implementation; simply wrapping it in an actor is not a universal solution.

## 6. AppModel constructs the graph

AppModel provides a recognizable entry point to the runnable model. In RocketLaunch it constructs the launch feature, reminder feature and API dependencies, then connects accepted launch updates to reminder reconciliation.

Its composition method is main-actor isolated because that is convenient for the app entry point. This does not transfer main-actor isolation to separately constructed feature actors.

Construction should remain lightweight. It should not quietly start network requests or perform substantial storage work. RocketLaunch loads saved reminders lazily within the reminders actor when a command or subscription first needs them.

The shared live graph is a production convenience. Tests can construct independent graphs with controlled repositories, notification clients and isolated storage. Feature implementations should receive dependencies rather than reach back into `AppModel.shared` for collaborators.

## 7. A feature owns its state and its API

Our naming convention is explicit:

```swift
protocol LaunchScheduleFeatureAPI: AnyObject, Sendable {
    var snapshot: LaunchScheduleSnapshot { get async }
    func snapshots() async -> AsyncStream<LaunchScheduleSnapshot>
    func refresh() async
    func refresh(source: LaunchSourceID) async
    func updateNextLaunch() async
}

actor LaunchScheduleFeature: LaunchScheduleFeatureAPI {
    // Authoritative state, commands and snapshot publication.
}
```

This is an abbreviated declaration from the application. The protocol sits immediately above its concrete implementation in the same file. The stored dependency can simply be named `launchSchedule`.

The protocol describes the asynchronous contract and requires a Sendable implementation. The concrete `actor` declaration establishes this implementation's isolation. A protocol alone does not guarantee that every possible conformer uses a non-main executor.

Choose feature boundaries around meaningful business ownership. Launch scheduling and reminders have separate state and responsibilities, so separate actors are useful. A trivial display preference does not need an actor, snapshot stream and service abstraction just to satisfy a diagram.

## 8. Snapshots connect isolated state to observable state

SwiftUI needs values it can read synchronously while evaluating a View. It should not await actor properties from `body` or reconstruct business decisions during rendering.

Each feature therefore publishes a complete immutable Sendable snapshot. The feature remains authoritative; the ViewModel holds a local representation for presentation. The UI sends commands to change the model, rather than mutating that representation and treating it as business truth.

Our main-actor ViewModels use `@Observable`. When a View reads observable properties, Observation can track those dependencies and SwiftUI can update the relevant presentation when they change. This gives the interface a coherent local state to read; it does not promise that SwiftUI performs a cheap equality comparison of the whole model or skips all rendering work. [Observation: SE-0395](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0395-observability.md)

The same separation can support UIKit. A main-actor controller can observe or consume presentation updates and apply them to its views. UIKit does not gain SwiftUI's rendering behavior merely because the ViewModel is observable.

There is a granularity tradeoff: storing one aggregate snapshot makes coherent publication simple, but changing that property may invalidate multiple consumers. Split presentation state further only when measurements or screen requirements justify it.

## 9. Why the state travels through a stream

A single return value is sufficient for a single result. RocketLaunch needs progressive results: one provider may finish while another is still loading or failing.

Its feature API exposes both a current snapshot and a stream of snapshots. The production stream contract is:

- Each subscriber receives its own stream and continuation.
- Registration and initial-state replay happen in one actor-isolated operation.
- Publications contain complete state, not partial mutations that consumers must reconstruct.
- `bufferingNewest(1)` keeps the latest complete snapshot for a slow consumer.
- Each publication carries a monotonically increasing revision.
- Ending one subscription does not terminate the other subscribers.

Newest-value buffering is suitable for current screen state. It would be inappropriate for a stream of payments, analytics events or commands where every item must be processed. RocketLaunch's change journal is part of authoritative feature state, so a later snapshot still contains retained changes even if an intermediate snapshot was skipped.

LaunchScheduleFeature suppresses publications when the complete snapshot is unchanged. Clock processing still publishes meaningful changes, including cooldown expiry and changed upcoming eligibility. The actor also owns loadIfNeeded, avoiding a duplicate initial fetch when a newly created ViewModel has not received its first snapshot.

ViewModels reject older revisions. This protects against a delayed stream value arriving after a newer direct snapshot read. Subscription generation IDs also prevent a canceled consumer from publishing into a restarted observation session.

## 10. Structured work and owned long-lived tasks

RocketLaunch starts its provider work using a task group:

```swift
func refresh() async {
    await withTaskGroup(of: Void.self) { group in
        for configuration in configurations {
            group.addTask {
                await self.refresh(source: configuration.id)
            }
        }
    }
}
```

Each source method catches and classifies its ordinary errors independently, commits accepted data and publishes a snapshot. The group still waits for all its children, but the screen can display available results before the group's overall operation completes. A failed SpaceX request therefore does not discard working Launch Library results.

Not every task in the application is structurally nested. UI-triggered refresh handles and long-lived observation consumers use explicitly owned `Task` instances. Their ViewModels retain and cancel them. The root lifecycle owns the awaitable clock monitor. A short task in stream termination removes the continuation on the feature actor.

These lifetimes must be visible in the design. Root disappearance stops subscriptions and refresh work; deinitialization cancels retained handles. Tab changes preserve the shared root owners. Stream loops capture their ViewModels weakly between values so observation does not keep an abandoned screen owner alive indefinitely.

## 11. Actors do not remove ordering problems

Actor isolation prevents simultaneous unsynchronized access to actor-owned mutable state. It does not make a whole async operation indivisible. Other operations may enter while it is suspended, and actor scheduling should not be treated as FIFO business ordering. [Actor reentrancy: SE-0306](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0306-actors.md#actor-reentrancy)

Consider two refreshes. A starts first, B starts later, B finishes first, and A returns last. Both responses can be perfectly valid JSON. The feature must still prevent A from overwriting the newer accepted result.

RocketLaunch uses several identities for different purposes:

| Identity | What it protects |
| --- | --- |
| Per-source request ID | Acceptance of the latest request and cancellation rollback |
| ViewModel task ID | Old completion clearing a newer task handle |
| Snapshot revision | Older state overwriting newer presentation |
| Subscription generation | A canceled consumer publishing after restart |
| Source revision sent to reminders | An older launch update undoing newer reconciliation |
| Notification operation ID | A suspended schedule operation restoring a removed or replaced reminder |

A reminder reschedule illustrates why these checks belong after suspension as well as before it. Suppose the saved time is T1, an update starts scheduling T2, and a newer update restores T1 before scheduling finishes. Comparing the latest update with saved state is insufficient: both say T1, but the old T2 operation is still in flight. RocketLaunch rechecks the source revision immediately before committing the scheduled replacement. An obsolete success cancels its own new notification; an obsolete failure cannot mark the current reminder as failed.

Capacity is another actor invariant that must survive suspension. With 49 saved reminders, two concurrent additions must not both claim the final slot. RemindersFeature counts saved IDs together with pending operation IDs, reserving capacity before awaiting the notification client. A replacement uses its existing launch's slot, and failure releases the reservation.

The public reconciliation API accepts one Sendable LaunchSourceUpdate, containing a required source, revision and launch values. This keeps ordering metadata attached to the data it describes.

Cancellation is cooperative. Code checks it at appropriate boundaries; it is not proof that a remote operation or system side effect has been undone. State acceptance and side-effect reconciliation remain explicit responsibilities.

## 12. KISS keeps the architecture teachable

The purpose of these boundaries is to make ownership and execution easier to understand. Keep that benefit visible in the code:

1. Keep a feature's protocol and implementation together.
2. Give an actor one meaningful business responsibility.
3. Use ordinary Sendable values for results and dependencies.
4. Keep decoding details private to the API adapter where practical.
5. Add streams when progressive or ongoing state warrants them.
6. Keep substantial business rules out of presentation getters.
7. Avoid universal managers, generic event buses and detached tasks introduced merely to “make it concurrent.”

A model can remain feature-isolated without every helper becoming another actor. Synchronous helpers called from the owning actor can execute within that actor's current execution context. Expensive independent work can be separated when there is a concrete reason.

## 13. Applying this to an existing app

Start by identifying the authoritative state and its owner. Then classify work by responsibility and execution requirements.

For a feature that should become an actor, replace synchronous UI reads of mutable feature state with a Sendable snapshot contract. Move UI observability to the main-actor ViewModel. Add asynchronous commands and, where needed, a stream with initial replay and a defined buffering policy.

Audit every new suspension point for stale data, cancellation and reentrancy. Move substantial persistence out of composition initializers. Preserve behavior such as progressive loading and independent failures rather than returning one final result just because it simplifies a function signature.

Finally, test the boundary itself as well as the feature's answers. The compiler checks isolation and Sendable requirements; tests check behavior, ownership and ordering. Profiling checks the performance outcome.

## 14. What RocketLaunch demonstrates today

The implemented application has:

- A LaunchScheduleFeature actor for caches, grouping, chronological ordering, eligibility, change detection and Next selection.
- A RemindersFeature actor for reminder processing and persistence.
- API actors for asynchronous retrieval, decoding and domain mapping.
- Main-actor observable ViewModels with versioned snapshot delivery.
- Concurrent provider retrieval with independent publication and failure handling.
- Main-actor UI preferences, formatting and small presentation filters.

As verified on 7 September 2026, all **88 tests passed on macOS and iPhone Air Simulator running iOS 26.2**. Coverage includes off-main feature processing, main-actor observable publication, progressive results, independent subscriptions, latest-snapshot buffering, stale requests, cancellation and reminder ordering. Eleven regression tests added in the cleanup pass cover suspended rescheduling, stale failures, unknown times, pending capacity and failure release, initial-load ownership/retry, and clock/cooldown publication. Earlier live verification loaded five RocketLaunch.Live records and 50 Launch Library records while the SpaceX integration failed independently.

This establishes that the intended boundaries work in the tested implementation. It is not an Instruments benchmark, a guarantee of zero UI stalls, or evidence that every hardware core is being used. Device responsiveness, large datasets, expensive formatting and notification delivery remain matters for targeted validation.

## 15. The architectural conclusion

We are making proper use of Swift's runtime by giving it explicit isolation, suspendable work and meaningful opportunities for concurrency. The runtime manages threads; the architecture determines what work competes with the UI and how results become safe to present.

**AppModel gives the application an identifiable model. Feature actors give that model execution boundaries. Observable ViewModels give the interface local presentation state. KISS keeps those choices understandable.**

That is the intent of **Modern iOS Architecture 26: Swift Concurrency with Feature Actors**.

## Further reading in this repository

- [Current RocketLaunch architecture](ARCHITECTURE.md)
- [Concurrency ownership and guarantees](CONCURRENCY_INVENTORY.md)
- [Provider behavior and limitations](MULTI_PROVIDER_DESIGN.md)
- [Migration decisions and verification](MIGRATION_LEDGER.md)
- [Migration cleanup lessons](MIGRATION_CLEANUP_NOTES.md)
