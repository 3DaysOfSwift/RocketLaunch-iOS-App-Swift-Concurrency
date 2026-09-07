# Progressive operator tabs

Implemented 2026-09-07 following the developer’s final clarification: data providers supply records; tabs represent the launch operators discovered in those records. The app remains fully free.

## Screens

Next is always present. Operator tabs appear after each accepted response, without waiting for the other source. Within each batch new names are sorted, then appended; established tabs keep their order. Known aliases such as CASC’s full name share an identity. Discovered tabs remain for the session even if their current list becomes empty. Each tab has independent navigation to a source-labelled launch detail snapshot. iPhone uses its native More menu when there are too many tabs for the bar.

Each operator screen shows status and refresh controls for its known contributing sources, plus sources that have not yet returned data. Failure is explicit, with previous rows retained and labelled as previous data. An empty success clears that source’s rows. Source membership is remembered so an empty tab retains its refresh controls. Tab switches do not refetch or cancel the shared refresh.

## Data and concurrency

RocketLaunch.Live supplies its free next-five response. Launch Library 2 supplies up to 50 upcoming records from its production 2.3.0 endpoint. Its refresh attempts have a five-minute in-memory cooldown. The third source is the community r-spacex SpaceX API, queried for up to 50 upcoming records with populated rocket and launchpad details.

LaunchScheduleFeature owns one snapshot/cache per source, containing the entire decoded list, phase, fetched timestamp and next refresh time. All commits are Main Actor isolated; network waiting and decoding happen through the API actors. Refresh-all uses a task group. Each child handles its own error and commits when ready. The caller awaits completion of the group, while the UI sees intermediate commits immediately. An individual source refresh uses the same commit path and cannot cancel another source’s work. Request IDs reject superseded responses. Cancellation restores that source’s settled state.

The root ViewModel owns refresh task handles across tab changes. SwiftUI owns the root’s awaitable clock-monitor task, which asks the feature to re-evaluate once a minute. Foreground activation also re-evaluates. There is no per-tab polling or network request.

## Stored Next and merging

The feature explicitly stores nextLaunch, recalculating after commits and clock events. It selects the earliest precise future time among eligible sources. If none exists, it falls back to an undated record, then a remaining scheduled record. Estimated dates remain estimates, and a passed scheduled time is labelled as awaiting an update; it does not prove liftoff. Failed sources are excluded from a newly selected candidate; the screen may retain the previous result alongside the failure message.

Operator lists combine source records using source-qualified identities. Records for the same real launch from different APIs remain source-labelled entries. This version does not claim cross-source deduplication, reconcile conflicting schedules or provide independently corroborated launch times. Those selection policies remain a future discussion. Source coverage and failures are visible.

## Verification

59 host XCTest cases pass, including incremental publication before the second source completes, failure isolation, cache separation, alias identity, empty-cache replacement, remembered tabs, individual-refresh updates, stale-response rejection, cancellation, time-driven Next updates, cooldown and Launch Library date precision. Simulator live smoke confirmed both source responses (5 + 50 records). Navigation is also checked manually.

## Community SpaceX source

SpaceXAPI implements the documented v5 POST /launches/query endpoint and requests populated rocket/launchpad names. It is the community r-spacex project, not an official SpaceX service. It has its own memory cache, a 20-second request timeout, a 60-second refresh cooldown and independent failure state. Its status is shown on Next and the SpaceX operator screen. A failed SpaceX request does not prevent other sources publishing.

Past or undated SpaceX schedule records may be browsed in its source-labelled cache but cannot become Next. A response containing only outdated records is labelled accordingly. Country is left unknown when absent from the launchpad schema; rocket-manufacturer country is not substituted. Decoding respects date precision. The archived service’s current availability and data freshness must not be inferred from successful fixture tests.
