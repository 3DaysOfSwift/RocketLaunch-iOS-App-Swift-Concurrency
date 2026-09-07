# Migration cleanup notes

Track developer corrections here so they can inform an additional cleanup pass in the migration instructions. These notes do not yet modify the migration skill.

## 1. Feature naming and declaration placement

- **Mistake:** Named the concrete feature `LaunchScheduleManager` and put its API protocol in a separate `LaunchScheduleFeature.swift` file.
- **Required convention:** Name the concrete feature `LaunchScheduleFeature`. Name its API protocol `LaunchScheduleFeatureAPI` and declare it above the implementation in the same `LaunchScheduleFeature.swift` file. Do not create a separate file for every declaration by default.
- **Correction:** Combined the protocol, implementation and associated state/error declarations into `LaunchScheduleFeature.swift`; updated composition, tests, Xcode references and documentation.
- **Proposed cleanup check:** Review each migrated feature for a concrete class named `<DomainName>Feature`, an API protocol named `<DomainName>FeatureAPI`, and colocated protocol/implementation. Split declarations only when there is a concrete reason.

- **Naming refinement:** The developer subsequently chose `LaunchScheduleFeature` / `LaunchScheduleFeatureAPI` in place of the initial `LaunchSchedule` / `LaunchScheduleFeature` pairing. Stored properties can use the concise domain name `launchSchedule`. Use this latest convention in the cleanup pass.
