import Foundation
import Observation

@MainActor @Observable
final class AboutViewModel {
    @ObservationIgnored private let feature: SettingsFeature

    init(feature: SettingsFeature = AppModel.shared.settingsFeature) {
        self.feature = feature
    }

    var spaceXURL: URL { feature.spaceXURL }
    var launchLibraryURL: URL { feature.launchLibraryURL }
    var rocketLaunchURL: URL { feature.rocketLaunchURL }
}
