import Foundation
import SwiftUI

final class LaunchScheduleViewModel: ObservableObject {
    private let feature: any LaunchScheduleFeature
    private var nextRocketLaunch: RocketLaunch?
    @Published private(set) var receivedNextRocketLaunch = false

    var mission: String { nextRocketLaunch?.missions.first?.description ?? "None" }
    var launchName: String { nextRocketLaunch?.name ?? "None" }

    init(feature: any LaunchScheduleFeature = AppModel.shared.launchSchedule) {
        self.feature = feature
    }

    func refresh() {
        feature.refresh { [self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let launch):
                    self.nextRocketLaunch = launch
                    self.receivedNextRocketLaunch = true
                case .failure(let error):
                    print(error)
                }
            }
        }
    }
}
