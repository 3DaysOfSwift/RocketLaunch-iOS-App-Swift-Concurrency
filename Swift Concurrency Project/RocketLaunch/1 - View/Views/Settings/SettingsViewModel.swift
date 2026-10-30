import Observation

@MainActor @Observable
final class SettingsViewModel {
    private let feature: SettingsFeature

    init(feature: SettingsFeature = AppModel.shared.settingsFeature) {
        self.feature = feature
    }

    var selectedTheme: AppColourTheme {
        get { feature.selected }
        set { feature.select(newValue) }
    }
}
