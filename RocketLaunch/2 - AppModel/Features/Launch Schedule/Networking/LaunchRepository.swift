import Foundation

protocol LaunchRepository {
    func fetchUpcomingLaunches(completion: @escaping (Result<[RocketLaunch], RocketLaunchAPIError>) -> Void)
}
