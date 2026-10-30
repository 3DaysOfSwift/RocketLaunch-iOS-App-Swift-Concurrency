import Observation

@MainActor @Observable
final class SettingsViewModel {
    private let settingsFeature: SettingsFeature

    init(settingsFeature: SettingsFeature = AppModel.shared.settingsFeature) {
        self.settingsFeature = settingsFeature
    }

    var selectedTheme: AppColourTheme {
        get { settingsFeature.selected }
        set { settingsFeature.select(newValue) }
    }
}
