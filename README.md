![3 Days of Swift Concurrency — learn async/await, tasks and actors in Swift](readme-images/3DaysOfSwift-Concurrency-Header.png)

# Rocket Launch

Rocket Launch is a small SwiftUI app that retrieves upcoming launches and displays the next launch’s name and mission. It is a working migration example for [3 Days of Swift Concurrency](https://www.3daysofswiftconcurrency.com): taking an existing callback-based iOS application towards explicit feature ownership and cooperative Swift Concurrency.

The project began as a starter pack. Its unfinished behaviour and real defects give us concrete problems to investigate, protect with tests and improve through a documented migration.

## Migration status

**The migration is in progress.** The current checkpoint establishes the AppModel architecture while retaining completion handlers, `DispatchQueue.main.async`, `ObservableObject` and `@Published`. It currently supports iOS 15.2 and later.

The next stage targets iOS 17, Swift Concurrency and Apple’s Observation framework. Managed refresh lifetimes, stale-response protection, and clear empty/error/retry states are approved improvements that have not yet been implemented. Nullable estimated launch dates have already been corrected and covered by regression checks.

This repository is a teaching application under development, not a completed App Store release.

## The architectural sentence

`View → ViewModel → Feature API → Feature Manager → Repository`

That sentence is also the folder structure. Open `RocketLaunch.xcodeproj` in Xcode and the first distinction is between `1 - View` and `2 - AppModel`:

- **1 - View** contains SwiftUI and presentation state. `LaunchScheduleView` owns its tightly coupled `LaunchScheduleViewModel` using `@StateObject` at this callback checkpoint.
- **2 - AppModel** contains the composition root and the launch feature: its API, manager, data types, repository contract and networking implementation.
- **3 - App Resources** contains the app’s assets and sample JSON.

`AppModel.live()` assembles the dependencies without starting a request. The ViewModel asks the narrow `LaunchScheduleFeature` to refresh. `LaunchScheduleManager` selects the first returned launch, while `RocketLaunchAPI` retrieves and decodes the response through `NetworkManager`. The ViewModel prepares values for the screen.

The architecture follows the principles used by [Trend](https://github.com/3DaysOfSwift/Trend-iOS-App-Swift-Concurrency). Read the [AppModel iOS Application Template](https://github.com/3DaysOfSwift/Trend-iOS-App-Swift-Concurrency/blob/main/APPMODEL_IOS_APPLICATION_TEMPLATE.md) for the target architecture and [ARCHITECTURE.md](ARCHITECTURE.md) for this project’s current implementation and transitional boundaries.

## Launch data

The app makes one request to the [RocketLaunch.live upcoming-launch endpoint](https://fdo.rocketlaunch.live/json/launches/next/5). It displays the first launch returned by that API and the description of its first mission, falling back to “None” when that description is unavailable.

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
4. Build and run, then tap **Refresh**.

The current screen shows the launch details after a successful request. Visible error handling and refreshing after success are still part of the migration work described above.

## Verification

The callback architecture checkpoint builds for a generic iOS device. Eight external characterisation checks were run against both the original starter and this checkpoint, including controlled responses that reproduce the legacy refresh and stale-response defects. The migration ledger records that evidence; the external runner is not included in this repository.

This repository includes five decoding regression checks covering complete dates, a null day, entirely unknown dates, omitted date components and malformed component types. Run them on a Mac with Xcode and Python 3 installed:

```bash
python3 Tests/LaunchDecoding/run.py
```

The checks compile the application’s real decoding types and use the bundled JSON fixture. They require no live API connection. They are standalone checks, not an Xcode test target or a replacement for manual iOS testing.

## Following the migration

The migration separates architecture changes, concurrency conversion and intentional product improvements. Existing defects are recorded explicitly rather than silently becoming requirements for the new implementation.

- [Behaviour contract](MIGRATION_BEHAVIOUR_CONTRACT.md) — preserved behaviour, approved changes and the manual regression checklist.
- [Migration ledger](MIGRATION_LEDGER.md) — completed checkpoints, temporary responsibilities and remaining verification.
- [Concurrency inventory](CONCURRENCY_INVENTORY.md) — callback lifetimes, ordering problems and planned replacements.

The original starter uses one launch API. Task groups or additional actors will only be introduced when the application has a concrete need for them.

## 3 Days of Swift Concurrency

Explore the training program at [3DaysOfSwiftConcurrency.com](https://www.3daysofswiftconcurrency.com) and the related projects on [3DaysOfSwift](https://github.com/3DaysOfSwift).
