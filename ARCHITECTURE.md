# RocketLaunch architecture

AppModel composes the shared runnable model. The free SwiftUI app displays Next followed by dynamically discovered launch-operator tabs.

```text
ContentView → root LaunchScheduleViewModel → LaunchScheduleFeatureAPI
                                            LaunchScheduleFeature
                                              ├─ RocketLaunchAPI actor
                                              └─ LaunchLibraryAPI actor
```

LaunchScheduleFeatureAPI is declared directly above the concrete MainActor Observable LaunchScheduleFeature in the same file. Each API implements the Sendable LaunchRepository contract. Private DTOs and decoding remain inside their respective API files. Immutable domain values carry source-qualified IDs and the launch information required by the screens.

## Ownership and state

LaunchScheduleFeature owns separate in-memory source snapshots: list, phase, successful download timestamp and next permitted refresh time. It also stores operator groups and nextLaunch. Every accepted refresh updates one source and recomputes the stored aggregate. It preserves discovered operator identity and source membership for the session, even after an empty response. Known operator aliases are normalized in the model.

Refresh-all uses structured child tasks. Ordinary API errors are isolated per source; they do not cancel successful siblings. Results publish incrementally, while the calling refresh method awaits group completion. Source-specific request IDs reject stale completions. Cancellation restores the previous settled source snapshot. Launch Library attempts are spaced at least five minutes apart within the running app.

Next chooses the earliest precise future time from non-failed sources, with explicitly labelled undated/elapsed fallbacks. The root’s lifecycle-bound clock monitor requests recomputation once per minute, and foreground activation does the same. It never runs selection logic in a View getter. Cross-source records stay attributed and are not silently reconciled or deduplicated.

## UI

The root owns one Observable LaunchScheduleViewModel and its refresh handles, so tab changes do not cancel shared work. Each operator tab has its own NavigationStack. LaunchDetailViewModel formats a selected immutable launch snapshot and is colocated with the schedule ViewModel. Sources show explicit loading, failure and previous-cache messages; failed downloads never become successful empty lists. About is a sheet with attribution to both sources. Native iPhone tab overflow uses More.

Presentation reads the model; network and selection logic do not live in Views. ThemeManager owns the system/midnight palettes. The hosted test app keeps the live screen dormant.

## Validation and limits

53 host tests cover the model, ViewModels, decoding and networking cancellation. Both live sources loaded in Simulator. The application currently has two API integrations; a third needs verification. Launch Library fetches one page of up to 50 upcoming records; RocketLaunch.Live’s free endpoint supplies five. These are bounded source lists, not a claim of complete global coverage. Cache storage is in memory only. The detailed current behavior is recorded in MULTI_PROVIDER_DESIGN.md.
