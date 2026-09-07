import Foundation

protocol LaunchScheduleFeatureAPI: AnyObject, Sendable {
    var snapshot: LaunchScheduleSnapshot { get async }
    func snapshots() async -> AsyncStream<LaunchScheduleSnapshot>
    func loadIfNeeded() async
    func refresh() async
    func refresh(source: LaunchSourceID) async
    func updateNextLaunch() async
}

/// Owns business state and processing independently of the UI's main actor.
actor LaunchScheduleFeature: LaunchScheduleFeatureAPI {
    private(set) var state: LaunchScheduleState = .idle
    private(set) var sources: [LaunchSourceSnapshot]
    private(set) var operators: [LaunchOperator] = []
    private(set) var nextLaunch: RocketLaunch?
    private(set) var updates: [LaunchUpdate] = []
    private let onRefresh: @Sendable (LaunchSourceUpdate) async -> Void
    private let configurations: [LaunchSourceConfiguration]
    private let now: @Sendable () -> Date
    private var requests: [LaunchSourceID: UUID] = [:]
    private var rollback: [LaunchSourceID: LaunchSourceSnapshot] = [:]

    init(repository: any LaunchRepository) {
        self.init(sources: [.init(id: .rocketLaunchLive, repository: repository)])
    }

    init(sources: [LaunchSourceConfiguration], now: @escaping @Sendable () -> Date = { Date() }, onRefresh: @escaping @Sendable (LaunchSourceUpdate) async -> Void = { _ in }) {
        precondition(Set(sources.map(\.id)).count == sources.count)
        self.configurations = sources; self.now = now; self.onRefresh = onRefresh
        self.sources = sources.map { LaunchSourceSnapshot(id: $0.id) }
        self.lastPublished = .init(revision: 0, state: .idle, nextLaunch: nil, sources: self.sources, operators: [], upcomingLaunches: [], updates: [])
    }

    private var initialLoadInProgress = false
    private var lastPublished: LaunchScheduleSnapshot?
    private var revision: UInt64 = 0
    private var upcomingLaunches: [RocketLaunch] = []
    private var observers: [UUID: AsyncStream<LaunchScheduleSnapshot>.Continuation] = [:]
    var snapshot: LaunchScheduleSnapshot {
        .init(revision: revision, state: state, nextLaunch: nextLaunch, sources: sources, operators: operators,
              upcomingLaunches: upcomingLaunches, updates: updates)
    }
    func snapshots() -> AsyncStream<LaunchScheduleSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<LaunchScheduleSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        // Registration and initial delivery are one actor-isolated operation.
        continuation.yield(snapshot)
        return stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    private func publish() {
        guard snapshot != lastPublished else { return }
        revision += 1
        let value = snapshot
        lastPublished = value
        for observer in observers.values { observer.yield(value) }
    }
    deinit { for observer in observers.values { observer.finish() } }

    /// The feature makes the initial-load decision before its first suspension.
    func loadIfNeeded() async {
        guard !Task.isCancelled, !initialLoadInProgress else { return }
        let unfinished = sources.filter { $0.phase == .idle }.map(\.id)
        guard !unfinished.isEmpty else { return }
        initialLoadInProgress = true
        defer { initialLoadInProgress = false }
        await withTaskGroup(of: Void.self) { group in
            for source in unfinished {
                group.addTask { await self.refresh(source: source) }
            }
        }
    }

    /// Each child commits independently; the first response can populate the UI.
    func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            for configuration in configurations {
                group.addTask { await self.refresh(source: configuration.id) }
            }
        }
    }

    func refresh(source: LaunchSourceID) async {
        guard !Task.isCancelled,
              let index = sources.firstIndex(where: { $0.id == source }),
              let config = configurations.first(where: { $0.id == source }) else { return }
        if let retryAt = sources[index].nextRefreshAt, now() < retryAt { return }
        let id = UUID()
        let previous = rollback[source] ?? sources[index]
        requests[source] = id; rollback[source] = previous
        sources[index].phase = .loading
        sources[index].nextRefreshAt = now().addingTimeInterval(config.minimumRefreshInterval)
        updateNextLaunch()
        defer { if requests[source] == id { requests[source] = nil; rollback[source] = nil } }
        do {
            let launches = try await config.repository.fetchUpcomingLaunches()
            try Task.checkCancellation()
            guard requests[source] == id else { return }
            recordChanges(from: sources[index].launches, to: launches)
            sources[index].launches = launches
            sources[index].fetchedAt = now()
            sources[index].phase = .loaded
            rebuildOperators()
            updateNextLaunch()
            // A later request must roll back to this committed result while reminders update.
            rollback[source] = sources[index]
            await onRefresh(.init(source: source, revision: revision, launches: launches))
        } catch {
            guard requests[source] == id else { return }
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                sources[index] = previous
            } else {
                sources[index].phase = .failed(Self.failure(for: error))
            }
            updateNextLaunch()
        }
    }

    /// Stored output is recalculated only on model events, never in a View getter.
    func updateNextLaunch() {
        let currentTime = now()
        // Expiring a cooldown is a meaningful UI change, even when launches did not change.
        for index in sources.indices {
            if let deadline = sources[index].nextRefreshAt, deadline <= currentTime {
                sources[index].nextRefreshAt = nil
            }
        }
        upcomingLaunches = LaunchScheduleSnapshot.upcoming(from: sources.flatMap(\.launches), now: currentTime)
        let eligible = sources.filter { if case .failed = $0.phase { return false }; return true }.flatMap(\.launches)
            .filter { $0.source != .spaceX || ($0.details.sortTime ?? .distantPast) >= currentTime }
        let future = eligible.filter { ($0.details.plannedTime ?? .distantPast) >= currentTime }
        nextLaunch = future.min { $0.details.plannedTime! < $1.details.plannedTime! }
            ?? eligible.first(where: { $0.details.plannedTime == nil }) ?? eligible.first
        if let nextLaunch { state = sources.contains(where: { $0.phase == .loading }) ? .loading(previous: nextLaunch) : .loaded(nextLaunch) }
        else if sources.contains(where: { $0.phase == .loading }) { state = .loading(previous: state.launch) }
        else if let failure = sources.compactMap({ snapshot -> LaunchLoadFailure? in
            if case .failed(let failure) = snapshot.phase { return failure }; return nil
        }).first { state = .failed(failure, previous: state.launch) }
        else if sources.allSatisfy({ $0.phase == .idle }) { state = .idle }
        else { state = .empty }
        publish()
    }

    private func rebuildOperators() {
        let all = sources.flatMap(\.launches)
        let grouped = Dictionary(grouping: all) { LaunchOperator.key(for: $0.details.provider) }
        // Retain discovered operators for this session, even after an empty response.
        let existingIDs = Set(operators.map(\.id))
        for key in grouped.keys.sorted() where !existingIDs.contains(key) {
            let name = LaunchOperator.canonicalName(grouped[key]?.first?.details.provider)
            operators.append(LaunchOperator(id: key, name: name, launches: []))
        }
        for index in operators.indices {
            operators[index].sourceIDs.formUnion((grouped[operators[index].id] ?? []).map(\.source))
            operators[index].launches = (grouped[operators[index].id] ?? []).sorted {
                let lhs = $0.details.sortTime ?? $0.details.plannedTime ?? .distantFuture
                let rhs = $1.details.sortTime ?? $1.details.plannedTime ?? .distantFuture
                return lhs == rhs ? $0.id < $1.id : lhs < rhs
            }
        }
    }

    private func recordChanges(from old: [RocketLaunch], to new: [RocketLaunch]) {
        let oldByID = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for launch in new {
            guard let previous = oldByID[launch.id] else { continue }
            let timeChanged = previous.details.plannedTime != launch.details.plannedTime
                || previous.details.estimatedDateLabel != launch.details.estimatedDateLabel
            let missionChanged = previous.name != launch.name || previous.details.missionDescription != launch.details.missionDescription
                || previous.missions != launch.missions
            guard timeChanged || missionChanged else { continue }
            updates.insert(LaunchUpdate(id: UUID(), detectedAt: now(), previous: previous, launch: launch, timeChanged: timeChanged), at: 0)
        }
        updates = Array(updates.prefix(100))
    }

    private static func failure(for error: any Error) -> LaunchLoadFailure {
        if let error = error as? LaunchRepositoryError {
            switch error {
            case .invalidResponse: return .invalidResponse
            case .httpStatus(let status): return .server(statusCode: status)
            case .invalidData: return .invalidData
            }
        }
        switch (error as? URLError)?.code {
        case .notConnectedToInternet: return .offline
        case .timedOut: return .timedOut
        default: return .network
        }
    }
}

enum LaunchLoadFailure: Equatable, Sendable {
    case offline, timedOut, invalidResponse, invalidData, network
    case server(statusCode: Int)
}

enum LaunchScheduleState: Equatable, Sendable {
    case idle
    case loading(previous: RocketLaunch?)
    case loaded(RocketLaunch)
    case empty
    case failed(LaunchLoadFailure, previous: RocketLaunch?)

    var launch: RocketLaunch? {
        switch self {
        case .loaded(let launch): launch
        case .loading(let previous), .failed(_, let previous): previous
        case .idle, .empty: nil
        }
    }
}

enum LaunchSourceID: String, Sendable, Codable, CaseIterable, Identifiable {
    case rocketLaunchLive, launchLibrary, spaceX
    var id: String { rawValue }
    var name: String {
        switch self {
        case .rocketLaunchLive: "RocketLaunch.Live"
        case .launchLibrary: "Launch Library"
        case .spaceX: "SpaceX API"
        }
    }
}

/// One accepted provider response, with the revision that orders its reconciliation.
struct LaunchSourceUpdate: Sendable {
    let source: LaunchSourceID
    let revision: UInt64
    let launches: [RocketLaunch]
}

struct LaunchSourceConfiguration: Sendable {
    let id: LaunchSourceID
    let repository: any LaunchRepository
    var minimumRefreshInterval: TimeInterval = 0
}

struct LaunchSourceSnapshot: Equatable, Sendable, Identifiable {
    let id: LaunchSourceID
    var launches: [RocketLaunch] = []
    var fetchedAt: Date?
    var nextRefreshAt: Date?
    var phase: Phase = .idle
    enum Phase: Equatable, Sendable { case idle, loading, loaded, failed(LaunchLoadFailure) }
}

struct LaunchOperator: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    var launches: [RocketLaunch]
    var sourceIDs: Set<LaunchSourceID> = []
    static func canonicalName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed.lowercased() {
        case "", "tbd", "unknown operator": return "Unknown operator"
        case "china aerospace science and technology corporation", "casc": return "CASC"
        case "china aerospace science and industry corporation", "casic": return "CASIC"
        case "space exploration technologies", "spacex": return "SpaceX"
        case "united launch alliance", "ula": return "ULA"
        case "indian space research organization", "isro": return "ISRO"
        case "japan aerospace exploration agency", "jaxa": return "JAXA"
        default: return trimmed
        }
    }
    static func key(for name: String?) -> String {
        canonicalName(name).lowercased()
    }
}

struct LaunchUpdate: Identifiable, Equatable, Sendable {
    let id: UUID
    let detectedAt: Date
    let previous: RocketLaunch
    let launch: RocketLaunch
    let timeChanged: Bool
}

/// Immutable UI projection. The actor retains authoritative mutable state.
struct LaunchScheduleSnapshot: Equatable, Sendable {
    let revision: UInt64
    let state: LaunchScheduleState
    let nextLaunch: RocketLaunch?
    let sources: [LaunchSourceSnapshot]
    let operators: [LaunchOperator]
    let upcomingLaunches: [RocketLaunch]
    let updates: [LaunchUpdate]
    static let initial = Self(revision: 0, state: .idle, nextLaunch: nil, sources: [], operators: [], upcomingLaunches: [], updates: [])

    // Shared policy, executed by the feature when its data or clock changes.
    static func upcoming(from launches: [RocketLaunch], now: Date) -> [RocketLaunch] {
        launches.filter { launch in
            launch.source == .spaceX ? (launch.details.sortTime ?? .distantPast) >= now
                : (launch.details.plannedTime ?? .distantFuture) >= now
        }.sorted {
            let lhs = $0.details.sortTime ?? $0.details.plannedTime ?? .distantFuture
            let rhs = $1.details.sortTime ?? $1.details.plannedTime ?? .distantFuture
            return lhs == rhs ? $0.id < $1.id : lhs < rhs
        }
    }
}
