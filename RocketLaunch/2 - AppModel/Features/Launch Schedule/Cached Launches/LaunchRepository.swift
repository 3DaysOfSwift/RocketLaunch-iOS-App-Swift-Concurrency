import Foundation

protocol LaunchRepository: Sendable {
    func fetchUpcomingLaunches() async throws -> [RocketLaunch]
}

enum LaunchRepositoryError: Error, Equatable, Sendable {
    case invalidResponse
    case httpStatus(Int)
    case invalidData
}
