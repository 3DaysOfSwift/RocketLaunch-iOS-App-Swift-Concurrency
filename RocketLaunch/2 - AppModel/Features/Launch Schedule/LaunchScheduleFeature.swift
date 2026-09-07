import Foundation
import Observation

@MainActor
protocol LaunchScheduleFeatureAPI: AnyObject {
    var state: LaunchScheduleState { get }
    var sources: [LaunchSourceSnapshot] { get }
    var operators: [LaunchOperator] { get }
    func refresh() async
    func refresh(source: LaunchSourceID) async
    func updateNextLaunch()
}

@MainActor
@Observable
final class LaunchScheduleFeature: LaunchScheduleFeatureAPI {
    private(set) var state: LaunchScheduleState = .idle
    private(set) var sources: [LaunchSourceSnapshot]
    private(set) var operators: [LaunchOperator] = []
    private(set) var nextLaunch: RocketLaunch?
    @ObservationIgnored private let configurations: [LaunchSourceConfiguration]
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var requests: [LaunchSourceID: UUID] = [:]
    @ObservationIgnored private var rollback: [LaunchSourceID: LaunchSourceSnapshot] = [:]

    convenience init(repository: any LaunchRepository) {
        self.init(sources: [.init(id: .rocketLaunchLive, repository: repository)])
    }

    init(sources: [LaunchSourceConfiguration], now: @escaping () -> Date = Date.init) {
        precondition(Set(sources.map(\.id)).count == sources.count)
        self.configurations = sources; self.now = now
        self.sources = sources.map { LaunchSourceSnapshot(id: $0.id) }
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
            sources[index].launches = launches
            sources[index].fetchedAt = now()
            sources[index].phase = .loaded
        } catch {
            guard requests[source] == id else { return }
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                sources[index] = previous
            } else {
                sources[index].phase = .failed(Self.failure(for: error))
            }
        }
        updateNextLaunch()
    }

    /// Stored output is recalculated only on model events, never in a View getter.
    func updateNextLaunch() {
        let all = sources.flatMap(\.launches)
        let grouped = Dictionary(grouping: all) { LaunchOperator.key(for: $0.details.provider) }
        // Retain discovered tabs for this session, even after an empty response.
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
        let eligible = sources.filter { if case .failed = $0.phase { return false }; return true }.flatMap(\.launches)
            .filter { $0.source != .spaceX || ($0.details.sortTime ?? .distantPast) >= now() }
        let future = eligible.filter { ($0.details.plannedTime ?? .distantPast) >= now() }
        nextLaunch = future.min { $0.details.plannedTime! < $1.details.plannedTime! }
            ?? eligible.first(where: { $0.details.plannedTime == nil }) ?? eligible.first
        if let nextLaunch { state = sources.contains(where: { $0.phase == .loading }) ? .loading(previous: nextLaunch) : .loaded(nextLaunch) }
        else if sources.contains(where: { $0.phase == .loading }) { state = .loading(previous: state.launch) }
        else if let failure = sources.compactMap({ snapshot -> LaunchLoadFailure? in
            if case .failed(let failure) = snapshot.phase { return failure }; return nil
        }).first { state = .failed(failure, previous: state.launch) }
        else if sources.allSatisfy({ $0.phase == .idle }) { state = .idle }
        else { state = .empty }
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

enum LaunchSourceID: String, Sendable, CaseIterable, Identifiable {
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
