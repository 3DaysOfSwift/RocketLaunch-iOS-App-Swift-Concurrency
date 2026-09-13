![3 Days of Swift Concurrency](readme-images/3DaysOfSwift-Concurrency-Header.png)

# RocketLaunch

A free SwiftUI launch-schedule app and teaching resource for [3 Days of Swift Concurrency](https://www.3daysofswiftconcurrency.com). It targets iOS 17+, uses Observation and Swift 6 complete concurrency checking, and separates presentation from actor-owned business state.

## Run and test

1. Open `Swift Concurrency Project/RocketLaunch.xcodeproj` in Xcode 26.2 or later.
2. Select the **RocketLaunch** scheme and an iPhone simulator.
3. Press **⌘R** to run or **⌘U** to run the unit tests. For a physical device, configure your development team and bundle identifier.

From the repository root, you can also run:

```sh
xcodebuild -project "Swift Concurrency Project/RocketLaunch.xcodeproj" -scheme RocketLaunch -destination 'platform=iOS Simulator,name=iPhone Air' test
```

Choose an installed simulator name if iPhone Air is unavailable. The supported test entry point is the Xcode test target; there is no separate host-test runner in this repository. Tests use controlled repositories, sessions and clocks rather than live API responses.

## Architecture

`View → MainActor ViewModel → async Feature API → Feature actor → API actor`

- **1 - View:** SwiftUI, themed presentation and observable main-actor view models.
- **2 - AppModel:** dependency construction, authoritative launch/reminder state, source caches and APIs.
- **3 - App Resources:** icon assets, sample JSON, privacy manifest and offline privacy policy.

AppModel constructs dependencies without downloading data. The feature owns mutable business state and sends complete immutable Sendable snapshots to its view models. Provider refreshes overlap and publish independently. Shared requests have explicit owners, cancellation-aware waiters and identities that reject obsolete results. Task groups are structured concurrency; shared request and effect tasks have explicitly managed lifetimes.

Read [Architecture](Swift%20Concurrency%20Project/ARCHITECTURE.md) and [Swift Concurrency with Feature Actors](Swift%20Concurrency%20Project/SWIFT_CONCURRENCY_WITH_FEATURE_ACTORS.md). This follows the model/view separation used in [Trend](https://github.com/3DaysOfSwift/Trend-iOS-App-Swift-Concurrency).

## App experience

Five tabs provide **Next**, **Upcoming**, **Operators**, **Changes** and **Reminders**. Next shows the earliest precise future launch, or an eligible record with uncertain timing when no precise future launch is available. Elapsed precise launches cannot become Next, even when the final cached launch expires. Upcoming supports filters and search. Records retain source attribution; duplicate launches from different sources are not silently reconciled.

Changes records up to 100 schedule/mission changes detected between downloads during the session. It is not a news feed. Reminders are requested by source-qualified launch ID, use the current model record, and expose pending, scheduled and failed delivery. They are reconciled when the app refreshes; there is no background polling or push server. Notification delivery depends on iOS settings.

Settings offers eight colour themes. Double-tap Next to cycle through them. The selected theme and reminder records persist locally; launch caches are in memory. The bundled sample JSON is not an automatic offline fallback.

## Three providers, including an intentional failure example

RocketLaunch.Live supplies its next five launches, Launch Library requests fifty, and the community SpaceX API requests up to fifty. Each provider has independent cache, loading, cooldown and failure state. Launch Library has a five-minute refresh cooldown; SpaceX has a sixty-second cooldown and twenty-second timeout.

**SpaceX stays enabled deliberately as a real-world failure-handling example.** It failed during the 13 September 2026 review while the other two providers succeeded. A failed source must not prevent usable results from appearing. The community service is not official SpaceX, and its availability or data freshness is not guaranteed. SpaceX also appears as an operator in data supplied by other providers. Fixture tests do not establish live-service health.

## Teaching and validation

Start with the [Day 1 guide](TEACHING_GUIDE.md). See the [dated validation record](TEACHING_VALIDATION.md) for completed checks and remaining release work. The full reference implementation includes advanced request-sharing and reminder policies; students do not need to learn all of these before tracing one complete feature.

## Privacy and release status

An offline privacy policy is available from About and Settings; its repository copy is [PRIVACY.md](PRIVACY.md). The app bundles a required-reason manifest for its app-owned UserDefaults access.

This is a teaching build, **not a declaration of App Store readiness**. Before submission, publish the policy at a stable public URL, configure App Store Connect privacy/support metadata, verify provider practices and terms, and complete physical-device, accessibility and distribution validation. SpaceX remains intentionally enabled for the lesson.
