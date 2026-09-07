![3 Days of Swift Concurrency — learn async/await, tasks and actors in Swift](readme-images/3DaysOfSwift-Concurrency-Header.png)

# Rocket Launch

Rocket Launch is a small SwiftUI app that retrieves upcoming launches and displays the next launch’s name and mission. It is a working migration example for [3 Days of Swift Concurrency](https://www.3daysofswiftconcurrency.com): taking an existing callback-based iOS application towards explicit feature ownership and cooperative Swift Concurrency.

The project began as a starter pack. Its unfinished behaviour and real defects give us concrete problems to investigate, protect with tests and improve through a documented migration.

## Migration status

**The Swift Concurrency implementation is ready for final review.** The app now targets **iOS 17 and later**, uses **Swift 6 with complete concurrency checking**, and uses Apple’s Observation framework.

Refresh uses native asynchronous URLSession networking, actor-owned decoding and business state, delivered as immutable snapshots to MainActor ViewModels. A new screen refresh cancels its previous Task, and the feature rejects obsolete results before publication. Loading, empty and error states are explicit; refresh/retry remains available after success or failure.

All 77 XCTest cases pass on macOS and iPhone Air Simulator (iOS 26.2). The live launch flow has been checked in the simulator. Final manual recovery/accessibility checks and developer acceptance remain open; this is not an App Store release.

## The architectural sentence

Read [Swift Concurrency with Feature Actors — Modern iOS Architecture 26](SWIFT_CONCURRENCY_WITH_FEATURE_ACTORS.md) for the full design rationale, team rules, runtime model and implementation guidance.

`View → MainActor ViewModel → async Feature API → Feature actor → API actor`

That sentence is also the folder structure. Open `RocketLaunch.xcodeproj` in Xcode and the first distinction is between `1 - View` and `2 - AppModel`:

- **1 - View** contains SwiftUI and presentation state. The root `ContentView` owns its shared `@Observable` `LaunchScheduleViewModel` using `@State`.
- **2 - AppModel** contains the composition root and the launch feature: its asynchronous API, actor, data types, repository contract and networking implementation.
- **3 - App Resources** contains the app’s assets and sample JSON.

`AppModel.live()` assembles the dependencies without starting a request. The ViewModel asks the narrow `LaunchScheduleFeatureAPI` to refresh. `LaunchScheduleFeature` stores each source’s list, groups launches by operator and selects the next candidate, while the `RocketLaunchAPI` actor retrieves and decodes the response using `URLSession.data(from:)`. The feature publishes complete Sendable snapshots through independent AsyncStreams. The ViewModel observes those snapshots and prepares values for the screen. Reminders use the same actor/snapshot boundary, including off-main persistence.

The architecture follows the principles used by [Trend](https://github.com/3DaysOfSwift/Trend-iOS-App-Swift-Concurrency). Read the [AppModel iOS Application Template](https://github.com/3DaysOfSwift/Trend-iOS-App-Swift-Concurrency/blob/main/APPMODEL_IOS_APPLICATION_TEMPLATE.md) for the target architecture and [ARCHITECTURE.md](ARCHITECTURE.md) for this project’s current implementation and transitional boundaries.

## Launch data

The app fetches RocketLaunch.Live’s next five launches, Launch Library 2’s next 50, and up to 50 from the community SpaceX API. The sources start concurrently and publish independently. Each source has its own in-memory cache and explicit failure state. Operator lists retain source attribution; cross-source duplicates and conflicting schedules are not silently reconciled.

Estimated dates may be incomplete. The decoding model accepts unknown month, day and year values without inventing dates or rejecting an otherwise valid launch.

The current app merges three sources into operator lists and a stored Next result. Its caches are in memory only; fresh results require the external APIs and a working network connection. The bundled `TestData.json` is a test fixture, not an automatic offline fallback.

## Running

1. Clone this repository:

   ```bash
   git clone https://github.com/3DaysOfSwift/RocketLaunch-iOS-App-Swift-Concurrency.git
   cd RocketLaunch-iOS-App-Swift-Concurrency
   ```

2. Open `RocketLaunch.xcodeproj` in Xcode.
3. Select an iPhone simulator or configure your development team and bundle identifier to run on a device.
4. Build and run; the screen loads automatically. Use **Refresh schedule** to update it.

The screen retains the last launch during refresh or failure, displays a recoverable error when needed, and offers Refresh or Try Again. An empty response has its own message.

## Tests

`RocketLaunchTests` is an iOS unit-test target included in the shared **RocketLaunch** scheme. Select an iPhone simulator and press **⌘U** (Product → Test).

The 77 XCTest cases cover:

- AppModel construction and independent application graphs.
- Launch selection, empty responses and repository failures.
- ViewModel initial state, displayed values, failure recovery and retained results.
- JSON decoding with complete, null, omitted and malformed date components.
- The real networking/decoding boundary using an isolated URLSession and controlled responses.
- Cancellation of real URLSession requests, stale-response rejection, Task replacement and cancellation when the screen owner disappears or is released.
- Shared Observation updates and theme selection.

Tests are grouped into `View model tests`, `AppModel tests`, shared `Test Support` and `Fixtures`. They do not contact the live API or mutate `AppModel.shared`.

The iOS app and test bundle build successfully. All 77 tests passed in Xcode on iPhone Air (iOS 26.2) and on macOS using the same test files and actual Model/ViewModel sources.

When a simulator is unavailable, run the host checks on a Mac with Xcode and Python 3:

```bash
python3 Tests/run-host-tests.py
```

This creates a temporary Swift package from the current sources and executes the same XCTest suite. It does not run SwiftUI screens or replace manual iOS regression testing.

## Following the migration

The migration separates architecture changes, concurrency conversion and intentional product improvements. Existing defects are recorded explicitly rather than silently becoming requirements for the new implementation.

- [Behaviour contract](MIGRATION_BEHAVIOUR_CONTRACT.md) — preserved behaviour, approved changes and the manual regression checklist.
- [Migration ledger](MIGRATION_LEDGER.md) — completed checkpoints, temporary responsibilities and remaining verification.
- [Concurrency inventory](CONCURRENCY_INVENTORY.md) — implemented execution, cancellation and ordering guarantees.
- [Migration review](MIGRATION_REVIEW.md) — architecture audit and remaining acceptance checks.

The original starter used one launch API. The current app uses a task group for independent providers and feature actors for business processing; the migration ledger records that progression.

## 3 Days of Swift Concurrency

Explore the training program at [3DaysOfSwiftConcurrency.com](https://www.3daysofswiftconcurrency.com) and the related projects on [3DaysOfSwift](https://github.com/3DaysOfSwift).

## App experience

RocketLaunch is completely free, with no in-app purchases. Five fixed tabs provide Next, Upcoming, Operators, Changes and Reminders. Next gives a short overview with detail and watch links when supplied. Upcoming filters by operator, launch country and search; Operators filters by name and launch country. Source failures and previous cached data remain visible with independent refresh controls. Operator lists populate as each source returns. Planned times appear in local time; estimates remain explicit.

Launch Library refresh attempts have a five-minute cooldown within the running app. The community SpaceX API is also enabled as a third source. See [MULTI_PROVIDER_DESIGN.md](MULTI_PROVIDER_DESIGN.md) for the progressive refresh behavior and current limits.

## Community SpaceX source

SpaceXAPI implements the documented v5 POST /launches/query endpoint and requests populated rocket/launchpad names. It is the community r-spacex project, not an official SpaceX service. It has its own memory cache, a 20-second request timeout, a 60-second refresh cooldown and independent failure state. Its status is available from Next’s data-source sheet, Upcoming and the SpaceX operator screen. A failed SpaceX request does not prevent other sources publishing.

Past or undated SpaceX schedule records may be browsed in its source-labelled cache but cannot become Next. A response containing only outdated records is labelled accordingly. Country is left unknown when absent from the launchpad schema; rocket-manufacturer country is not substituted. Decoding respects date precision. The archived service’s current availability and data freshness must not be inferred from successful fixture tests.

## Schedule updates and reminders

Changes keeps the latest 100 time or mission changes detected between successive downloads from the same source during this session. The initial download establishes the baseline; it does not create artificial updates. Changes is not a news feed or a background monitor.

RemindersFeature owns persisted reminder records and injected local-notification scheduling. Users choose 5, 15 or 60 minutes before an exact future launch time. Permission is requested only after Set reminder. Successful source refreshes reconcile changed times, replace the associated notification, or cancel it and flag the record when timing becomes uncertain. Reminders use source-qualified launch IDs; selecting duplicate records from different providers can create separate reminders. There is no background polling or server push. Delivery remains subject to system notification settings.

Launch details expose HTTP(S) watch links only when supplied by a provider. RocketLaunch.Live launch-page links are labelled as information, not watch links.

## Colour themes

Choose from System, Midnight, Ocean, Forest, Sunset, Nebula, Lunar and Crimson. Open Settings using the gear on Next and choose a theme from the dropdown, or double-tap Next to cycle through all eight. The selected theme is saved between launches. System follows the device appearance; Midnight, Nebula and Crimson use dark appearance and the other named palettes use light appearance.
