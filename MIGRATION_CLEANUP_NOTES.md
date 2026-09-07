# Migration cleanup notes

Track developer corrections here so they can inform an additional cleanup pass in the migration instructions. These notes do not yet modify the migration skill.

## 1. Feature naming and declaration placement

- **Mistake:** Named the concrete feature `LaunchScheduleManager` and put its API protocol in a separate `LaunchScheduleFeature.swift` file.
- **Required convention:** Name the concrete feature `LaunchScheduleFeature`. Name its API protocol `LaunchScheduleFeatureAPI` and declare it above the implementation in the same `LaunchScheduleFeature.swift` file. Do not create a separate file for every declaration by default.
- **Correction:** Combined the protocol, implementation and associated state/error declarations into `LaunchScheduleFeature.swift`; updated composition, tests, Xcode references and documentation.
- **Proposed cleanup check:** Review each migrated feature for a concrete class named `<DomainName>Feature`, an API protocol named `<DomainName>FeatureAPI`, and colocated protocol/implementation. Split declarations only when there is a concrete reason.

- **Naming refinement:** The developer subsequently chose `LaunchScheduleFeature` / `LaunchScheduleFeatureAPI` in place of the initial `LaunchSchedule` / `LaunchScheduleFeature` pairing. Stored properties can use the concise domain name `launchSchedule`. Use this latest convention in the cleanup pass.

## Feature additions during UI work

- Register new feature and ViewModel files in the Xcode target; the host test runner discovers files independently and alone cannot establish Xcode membership.
- Keep source cache commits settled before awaiting downstream reminder updates so replacement requests roll back to the latest accepted data.
- Notification replacement needs unique request IDs and stale-completion rejection, including removal while scheduling is suspended.
- Keep country filter aliases consistent across data sources.

## Actor feature migration pass

- An async Feature API marked MainActor does not offload business computation. Use separate concrete feature actors when the intended contract is off-main business ownership.
- Replace direct observable feature reads with immutable Sendable snapshots held by MainActor ViewModels. Register streams and initial replay atomically; use independent subscribers, bounded buffering, revisions and explicit consumer task ownership.
- Do not perform persistence in a main-actor composition initializer. Load lazily inside the owning feature actor.
- Revisit every await boundary for reentrancy, including feature-to-feature notifications. Source revisions and operation IDs serve different ordering purposes.
- Update tests to await snapshots and verify progressive UI publication, subscriber cancellation, off-main business work and main-actor observation.
