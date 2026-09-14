# RocketLaunch — GCD teaching baseline

This is a separately runnable counterpart to the sibling Swift Concurrency app. It preserves the SwiftUI screens, Observation view models, themes, app icon, AppModel dependency graph, three providers, filters, change history and local reminders. Its asynchronous implementation uses **Grand Central Dispatch and completion handlers**.

## Open, run and test

Open **RocketLaunch.xcodeproj**, select the **RocketLaunch** scheme and an installed iPhone simulator, then press **⌘R**. Press **⌘U** for the callback-based unit tests. Xcode 26.2 was used for validation; the app targets iOS 17 and later.

The installed app is named **RocketLaunch GCD**, with bundle identifier `com.swiftsimplified.rocketlaunch.gcd.RocketLaunch`. It can coexist with the Swift Concurrency app and has separate preferences and reminders. Select your development team when running on a physical device.

From this folder:

```sh
xcodebuild -project RocketLaunch.xcodeproj -scheme RocketLaunch -destination 'platform=iOS Simulator,name=iPhone Air' test
```

The project uses Swift 5 language mode to represent an explicit queue-discipline baseline. This is a concurrency comparison, not a recreation of an old iOS SDK. SwiftUI and Observation remain modern in both apps.

## Queue ownership

`View → UI ViewModel → callback Feature API → serial feature queue → callback API / decoding queue`

- The feature's private serial queue owns launch caches, Next, operators, change history and desired reminders. Public calls enqueue work; mutable state is never exposed directly.
- URLSession data tasks use completion handlers. Each API has a serial decoding queue. The network waits without a blocked application worker.
- DispatchGroup coordinates refresh completion without waiting synchronously. Results publish independently as each provider completes.
- CancellationToken uses a small lock solely for cancellation registration; handlers execute after releasing the lock. One cancelled caller does not cancel another caller's shared request. The last caller detaches ownership immediately; request IDs reject late responses.
- Snapshot subscriptions return cancellation tokens. Deliveries use DispatchQueue.main and check cancellation again before invoking the observer. View models cancel subscriptions and replaceable refresh work when their owner disappears.
- DispatchSourceTimer requests clock-driven Next updates. It is resumed once and cancelled with the view-model observation lifetime.
- Committed reminder effects outlive a screen. System callbacks re-enter the feature queue and validate notification IDs before accepting their results.

There are no feature actors, async/await functions, Swift Tasks or AsyncStreams in this baseline. The names `URLSessionDataTask` and `DispatchQueue.async` refer to callback/GCD APIs.

## Behaviour retained

Next selects an eligible future launch or an uncertain-time candidate; a precisely dated elapsed launch cannot become Next. Source caches remain available after expiry. Three providers retain separate status and caches. **The community SpaceX API remains enabled intentionally as a live failure-handling example**, while SpaceX also appears as an operator from other sources.

Upcoming and Operators retain filters, detail navigation and source attribution. Cross-provider duplicates remain visible. Changes is a session-local comparison log, not a news feed. Reminders use source-qualified launch IDs, persist desired state locally and reconcile on refresh; no background polling or push server is introduced.

The privacy manifest and offline policy are copied into the target's resources. About and Settings expose the policy. This teaching build does not constitute App Store release validation.

## Teach the migration

Use [MIGRATION_MAP.md](MIGRATION_MAP.md) to compare files and plan the conversion into the sibling Swift Concurrency project. Start with one provider, one feature and one screen; introduce shared cancellation and reminder effects after students understand the basic boundary.

See [VALIDATION.md](VALIDATION.md) for the tested contracts and limits. The GCD suite is purpose-built for callbacks; it is not a claim that every one of the sibling app's tests has been translated one-for-one.
