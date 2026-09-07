# Callback architecture checkpoint

```text
1 - View
  LaunchScheduleView owns LaunchScheduleViewModel
                      ↓ LaunchScheduleFeature
2 - AppModel
  AppModel.live assembles LaunchScheduleManager
                      ↓ LaunchRepository
  RocketLaunchAPI → NetworkManager → URLSession
3 - App Resources
```

This is a migration checkpoint, not the completed AppModel template. Callbacks, Combine and iOS 15.2 remain for behavioural comparison. LaunchScheduleManager chooses the first API result; the ViewModel formats its name and mission for display. AppModel construction does not trigger requests. All Model files belong to Launch Schedule except application assembly.

The temporary source types still mirror the transport schema. Shared observable feature state, explicit MainActor isolation, a small domain value and async request lifetimes follow after the architecture comparison. See the ledger for these accepted staging items.

## Test architecture

`RocketLaunchTests` is a hosted iOS XCTest target, enabled in the shared RocketLaunch scheme. `View model tests` verifies presentation behaviour; `AppModel tests` verifies construction, feature commands, API decoding and networking. Shared fixtures and controlled callback implementations make outcomes deterministic. Each network test owns an ephemeral URLSession, leaving the production shared session untouched.

`NetworkManager` now requires an explicit URLSession. AppModel.live supplies `.shared`, preserving live behaviour. The dependency exists so repository tests can exercise real URL loading and decoding without external requests.

All 22 XCTest cases pass through the macOS host runner. The iOS test bundle compiles and links; simulator execution and manual SwiftUI checks remain separate verification requirements.
