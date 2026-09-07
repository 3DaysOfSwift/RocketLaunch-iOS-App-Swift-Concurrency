import Foundation

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

@MainActor
protocol LaunchScheduleFeature: AnyObject {
    var state: LaunchScheduleState { get }
    func refresh() async
}
