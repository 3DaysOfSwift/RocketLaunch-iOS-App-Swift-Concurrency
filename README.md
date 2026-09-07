![3 Days of Swift Concurrency — learn async/await, tasks and actors in Swift](readme-images/3DaysOfSwift-Concurrency-Header.png)

# Rocket Launch

Rocket Launch is a small SwiftUI app that retrieves upcoming launches and displays the next launch’s name and mission. It is a working migration example for [3 Days of Swift Concurrency](https://www.3daysofswiftconcurrency.com): taking an existing callback-based iOS application towards explicit feature ownership and cooperative Swift Concurrency.

The project began as a starter pack. Its unfinished behaviour and real defects give us concrete problems to investigate, protect with tests and improve through a documented migration.

## Migration status

**The Swift Concurrency implementation is ready for final review.** The app now targets **iOS 17 and later**, uses **Swift 6 with complete concurrency checking**, and uses Apple’s Observation framework.

Refresh uses native asynchronous URLSession networking, actor-owned decoding and MainActor-owned feature state. A new screen refresh cancels its previous Task, and the feature rejects obsolete results before publication. Loading, empty and error states are explicit; refresh/retry remains available after success or failure.

All 40 XCTest cases pass on macOS; the previous 35-test suite also passed on iPhone Air Simulator (iOS 26.2). The live launch flow has been checked in the simulator. Final manual recovery/accessibility checks and developer acceptance remain open; this is not an App Store release.

## The architectural sentence

`View → ViewModel → Feature API → Feature Manager → Repository`

That sentence is also the folder structure. Open `RocketLaunch.xcodeproj` in Xcode and the first distinction is between `1 - View` and `2 - AppModel`:

- **1 - View** contains SwiftUI and presentation state. `LaunchScheduleView` owns its tightly coupled `@Observable` `LaunchScheduleViewModel` using `@State`.
- **2 - AppModel** contains the composition root and the launch feature: its API, manager, data types, repository contract and networking implementation.
- **3 - App Resources** contains the app’s assets and sample JSON.

`AppModel.live()` assembles the dependencies without starting a request. The ViewModel asks the narrow `LaunchScheduleFeatureAPI` to refresh. `LaunchScheduleFeature` selects the first returned launch, while the `RocketLaunchAPI` actor retrieves and decodes the response using `URLSession.data(from:)`. The ViewModel prepares values for the screen.

The architecture follows the principles used by [Trend](https://github.com/3DaysOfSwift/Trend-iOS-App-Swift-Concurrency). Read the [AppModel iOS Application Template](https://github.com/3DaysOfSwift/Trend-iOS-App-Swift-Concurrency/blob/main/APPMODEL_IOS_APPLICATION_TEMPLATE.md) for the target architecture and [ARCHITECTURE.md](ARCHITECTURE.md) for this project’s current implementation and transitional boundaries.

## Launch data

The app makes one request to the [RocketLaunch.live upcoming-launch endpoint](https://fdo.rocketlaunch.live/json/launches/next/5). It displays the first launch returned by that API, including planned time, provider, vehicle, launch-site country and mission purpose. Unpublished details are labelled explicitly.

Estimated dates may be incomplete. The decoding model accepts unknown month, day and year values without inventing dates or rejecting an otherwise valid launch.

The current app has no local launch cache or multi-provider aggregation. Its live results depend on the external API and a working network connection. The bundled `TestData.json` is a test fixture, not an automatic offline fallback.

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

The 40 XCTest cases cover:

- AppModel construction and independent application graphs.
- Launch selection, empty responses and repository failures.
- ViewModel initial state, displayed values, failure recovery and retained results.
- JSON decoding with complete, null, omitted and malformed date components.
- The real networking/decoding boundary using an isolated URLSession and controlled responses.
- Cancellation of real URLSession requests, stale-response rejection, Task replacement and cancellation when the screen owner disappears or is released.
- Shared Observation updates and theme selection.

Tests are grouped into `View model tests`, `AppModel tests`, shared `Test Support` and `Fixtures`. They do not contact the live API or mutate `AppModel.shared`.

The iOS app and test bundle build successfully. All 35 tests passed in Xcode on iPhone Air (iOS 26.2) and on macOS using the same test files and actual Model/ViewModel sources.

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

The original starter uses one launch API. Task groups or additional actors will only be introduced when the application has a concrete need for them.

## 3 Days of Swift Concurrency

Explore the training program at [3DaysOfSwiftConcurrency.com](https://www.3daysofswiftconcurrency.com) and the related projects on [3DaysOfSwift](https://github.com/3DaysOfSwift).

## App experience

RocketLaunch is completely free, with no in-app purchases. One screen automatically loads the next launch and answers when, who, launch country and mission purpose. Planned times appear in the device’s local time; estimated dates and unpublished details stay explicit. Manual refresh and retry are available, and About opens as a sheet. Data by RocketLaunch.Live.
