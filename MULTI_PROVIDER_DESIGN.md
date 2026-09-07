# Progressive launch data and fixed navigation

Updated 2026-09-07: five fixed tabs replace the earlier operator-per-tab design. Data providers supply records; operators are grouped within the Operators screen. The app remains fully free.

## Screens

Next, Upcoming, Operators, Changes and Reminders are always present. Operator groups populate after each accepted source response without waiting for the others. Known aliases such as CASC’s full name share an identity. Discovered operators remain for the session even if their current list becomes empty. Launch lists open source-labelled detail snapshots. Upcoming and Operators have independent presentation filters.

Each operator screen shows status and refresh controls for its known contributing sources, plus sources that have not yet returned data. Failure is explicit, with previous rows retained and labelled as previous data. An empty success clears that source’s rows. Source membership is remembered so an empty operator screen retains its refresh controls. Tab switches do not refetch or cancel the shared refresh.

## Data and concurrency

RocketLaunch.Live supplies its free next-five response. Launch Library 2 supplies up to 50 upcoming records from its production 2.3.0 endpoint. Its refresh attempts have a five-minute in-memory cooldown. The third source is the community r-spacex SpaceX API, queried for up to 50 upcoming records with populated rocket and launchpad details.

LaunchScheduleFeature owns one snapshot/cache per source, containing the entire decoded list, phase, fetched timestamp and next refresh time. All commits are isolated to LaunchScheduleFeature; network waiting and decoding happen through the API actors. Refresh-all uses a task group. Each child handles its own error and commits when ready. The caller awaits completion of the group, while the UI sees intermediate commits immediately. An individual source refresh uses the same commit path and cannot cancel another source’s work. Request IDs reject superseded responses. Cancellation restores that source’s settled state.

The root ViewModel owns refresh task handles across tab changes. SwiftUI owns the root’s awaitable clock-monitor task, which asks the feature to re-evaluate once a minute. Foreground activation also re-evaluates. There is no per-tab polling or network request.

## Stored Next and merging

The feature explicitly stores nextLaunch, recalculating after commits and clock events. It selects the earliest precise future time among eligible sources. If none exists, it falls back to an undated record, then a remaining scheduled record. Estimated dates remain estimates, and a passed scheduled time is labelled as awaiting an update; it does not prove liftoff. Failed sources are excluded from a newly selected candidate; the screen may retain the previous result alongside the failure message.

Operator lists combine source records using source-qualified identities. Records for the same real launch from different APIs remain source-labelled entries. This version does not claim cross-source deduplication, reconcile conflicting schedules or provide independently corroborated launch times. Those selection policies remain a future discussion. Source coverage and failures are visible.

## Verification

97 host XCTest cases pass, including incremental publication before the second source completes, failure isolation, cache separation, alias identity, empty-cache replacement, remembered operators, individual-refresh updates, stale-response rejection, cancellation, time-driven Next updates, cooldown and Launch Library date precision. Simulator live smoke confirmed both source responses (5 + 50 records). Navigation is also checked manually.

## Community SpaceX source

SpaceXAPI implements the documented v5 POST /launches/query endpoint and requests populated rocket/launchpad names. It is the community r-spacex project, not an official SpaceX service. It has its own memory cache, a 20-second request timeout, a 60-second refresh cooldown and independent failure state. Its status is available from Next’s data-source sheet, Upcoming and the SpaceX operator screen. A failed SpaceX request does not prevent other sources publishing.

Past or undated SpaceX schedule records may be browsed in its source-labelled cache but cannot become Next. A response containing only outdated records is labelled accordingly. Country is left unknown when absent from the launchpad schema; rocket-manufacturer country is not substituted. Decoding respects date precision. The archived service’s current availability and data freshness must not be inferred from successful fixture tests.

## Schedule updates and reminders

Updates keeps the latest 100 time or mission changes detected between successive downloads from the same source during this session. The initial download establishes the baseline; it does not create artificial updates. Updates is not a news feed or a background monitor.

LaunchScheduleFeature owns both launch data and persisted desired reminders, with an injected local-notification client. Screens request reminders by launch ID and lead time. Pending, scheduled and failed delivery are explicit. Users choose 5, 15 or 60 minutes before an exact future launch time. Permission is requested only after Set reminder. Successful source refreshes reconcile changed times, replace the associated notification, or cancel it and flag the record when timing becomes uncertain. Reminders use source-qualified launch IDs; selecting duplicate records from different providers can create separate reminders. There is no background polling or server push. Delivery remains subject to system notification settings.

Launch details expose HTTP(S) watch links only when supplied by a provider. RocketLaunch.Live launch-page links are labelled as information, not watch links.

## Actor feature boundary

LaunchScheduleFeature is now an actor. Its caches, grouping, chronological ordering, eligibility, change journal and stored Next value are computed on that actor. MainActor ViewModels receive complete versioned Sendable snapshots through independent AsyncStreams with newest-value buffering. Initial replay and per-source publication preserve progressive loading; cancellation and request identities preserve ordering. The same actor owns desired reminders and lazy persistence; no cross-feature source-revision callback remains. ID-based commands and notification identities protect freshness. See ARCHITECTURE.md for the current execution and ownership contract.
