# Concurrency inventory

| Legacy mechanism | Existing guarantee/problem | Planned replacement | Required verification |
| --- | --- | --- | --- |
| URLSession.dataTask completion | One request; task handle discarded; errors/status lost | Native async URLSession data API | Real request cancellation, HTTP errors, decoding and failure |
| DispatchQueue.main.async | Publish UI-facing result on main queue | MainActor state and directly awaitable feature command | Strict compiler checks and ViewModel result tests |
| isRefreshing plus defer | Flag cleared on synchronous return; no actual deduplication | Explicit refresh lifetime and request identity | Overlap, cancellation and stale-response tests |
| Unmanaged overlapping refresh | Completion order decides final displayed launch | Newest accepted refresh wins | Controlled reversed completions |
| ObservableObject/Published | Combine UI observation, no actor isolation | Observable feature and ViewModel on MainActor | Observation tests and iOS manual regression |

No DispatchGroup, semaphore, barrier or multi-provider parallelism exists in this starter. No task group or actor-per-provider will be invented solely to match course prose. Networking/decode execution ownership will be established from the actual compiler settings during migration.
