import Foundation
import Observation

@MainActor
@Observable
final class SettingsFeature {
    private(set) var selected: AppColourTheme
    @ObservationIgnored private let defaults: UserDefaults?
    private static let storageKey = "rocketlaunch.colourTheme"

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        selected = defaults?.string(forKey: Self.storageKey).flatMap(AppColourTheme.init(rawValue:)) ?? .system
    }
    func select(_ theme: AppColourTheme) {
        defaults?.set(theme.rawValue, forKey: Self.storageKey)
        selected = theme
    }
    func selectNextTheme() {
        let themes = AppColourTheme.allCases
        let index = themes.firstIndex(of: selected) ?? 0
        select(themes[(index + 1) % themes.count])
    }
}
