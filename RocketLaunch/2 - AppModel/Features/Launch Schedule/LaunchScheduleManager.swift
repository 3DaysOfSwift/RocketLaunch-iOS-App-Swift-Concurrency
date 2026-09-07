import Foundation

/// Owns the choice of the next launch. Callback lifetime defects are preserved
/// at this architecture checkpoint and corrected in the concurrency pass.
final class LaunchScheduleManager: LaunchScheduleFeature {
    private let repository: any LaunchRepository
    private(set) var isRefreshing = false

    init(repository: any LaunchRepository) {
        self.repository = repository
    }

    func refresh(completion: @escaping (Result<RocketLaunch?, RocketLaunchAPIError>) -> Void) {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        repository.fetchUpcomingLaunches { result in
            completion(result.map { $0.first })
        }
    }
}
