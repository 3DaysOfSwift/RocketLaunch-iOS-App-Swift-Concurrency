import Foundation
import Observation

@MainActor @Observable
final class AboutViewModel {
    @ObservationIgnored private let settingsFeature: SettingsFeature

    init(settingsFeature: SettingsFeature = AppModel.shared.settingsFeature) {
        self.settingsFeature = settingsFeature
    }

    var spaceXURL: URL { settingsFeature.spaceXURL }
    var launchLibraryURL: URL { settingsFeature.launchLibraryURL }
    var rocketLaunchURL: URL { settingsFeature.rocketLaunchURL }
}
