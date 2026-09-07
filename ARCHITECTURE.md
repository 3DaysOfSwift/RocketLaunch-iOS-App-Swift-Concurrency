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
