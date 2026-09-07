import Foundation
@testable import RocketLaunch

private final class FixtureBundle {}

enum LaunchFixtures {
    static func data() throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: FixtureBundle.self)
        #endif
        guard let url = bundle.url(forResource: "launch-response", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func data(estimatedDate: [String: Any]) throws -> Data {
        var page = try JSONSerialization.jsonObject(with: data()) as! [String: Any]
        var launches = page["result"] as! [[String: Any]]
        launches[0]["est_date"] = estimatedDate
        page["result"] = launches
        return try JSONSerialization.data(withJSONObject: page)
    }

    static func launches() throws -> [RocketLaunch] {
        try JSONDecoder().decode(SearchResultsPage.self, from: data()).result
    }
}

final class ControlledLaunchRepository: LaunchRepository {
    private(set) var completions: [(Result<[RocketLaunch], RocketLaunchAPIError>) -> Void] = []
    func fetchUpcomingLaunches(completion: @escaping (Result<[RocketLaunch], RocketLaunchAPIError>) -> Void) {
        completions.append(completion)
    }
}

final class ControlledLaunchFeature: LaunchScheduleFeature {
    private(set) var completions: [(Result<RocketLaunch?, RocketLaunchAPIError>) -> Void] = []
    func refresh(completion: @escaping (Result<RocketLaunch?, RocketLaunchAPIError>) -> Void) {
        completions.append(completion)
    }
}
