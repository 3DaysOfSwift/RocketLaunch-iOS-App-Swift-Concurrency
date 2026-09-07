import Foundation
import Observation

@MainActor
protocol LaunchScheduleFeatureAPI: AnyObject {
    var state: LaunchScheduleState { get }
    func refresh() async
}

@MainActor
@Observable
final class LaunchScheduleFeature: LaunchScheduleFeatureAPI {
    private(set) var state: LaunchScheduleState = .idle
    @ObservationIgnored private let repository: any LaunchRepository
    @ObservationIgnored private var latestRequest: UUID?
    @ObservationIgnored private var rollbackState: LaunchScheduleState?

    init(repository: any LaunchRepository) { self.repository = repository }

    /// The newest request owns publication, even if older I/O ignores cancellation.
    func refresh() async {
        guard !Task.isCancelled else { return }
        let request = UUID()
        let previous = rollbackState ?? state
        latestRequest = request
        rollbackState = previous
        state = .loading(previous: previous.launch)
        defer {
            if latestRequest == request {
                latestRequest = nil
                rollbackState = nil
            }
        }

        do {
            let launches = try await repository.fetchUpcomingLaunches()
            try Task.checkCancellation()
            guard latestRequest == request else { return }
            state = launches.first.map(LaunchScheduleState.loaded) ?? .empty
        } catch {
            guard latestRequest == request else { return }
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                state = previous
            } else {
                state = .failed(Self.failure(for: error), previous: previous.launch)
            }
        }
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
