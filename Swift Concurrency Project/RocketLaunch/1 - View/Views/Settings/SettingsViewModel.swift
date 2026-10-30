import Observation

@MainActor @Observable
final class SettingsViewModel {
    private let settingsFeature: SettingsFeature

    init(settingsFeature: SettingsFeature = AppModel.shared.settingsFeature) {
        self.settingsFeature = settingsFeature
    }

    var storageError: String? { settingsFeature.storageError }
    var canRetryLoading: Bool { settingsFeature.canRetryLoading }
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    func retry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            await self?.settingsFeature.loadIfNeeded()
            self?.retryTask = nil
        }
    }
    deinit { retryTask?.cancel() }

    var selectedTheme: AppColourTheme {
        get { settingsFeature.selected }
        set { settingsFeature.select(newValue) }
    }
}
