import Foundation

protocol LaunchScheduleFeature {
    func refresh(completion: @escaping (Result<RocketLaunch?, RocketLaunchAPIError>) -> Void)
}
