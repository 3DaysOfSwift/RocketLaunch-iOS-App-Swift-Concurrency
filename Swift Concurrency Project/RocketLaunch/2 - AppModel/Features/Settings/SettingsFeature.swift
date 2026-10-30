import Foundation
import Observation

enum AppColourTheme: String, CaseIterable, Identifiable {
    case system, midnight, ocean, forest, sunset, nebula, lunar, crimson
    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: "System"
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .sunset: "Sunset"
        case .nebula: "Nebula"
        case .lunar: "Lunar"
        case .crimson: "Crimson"
        }
    }
}

@MainActor
@Observable
final class SettingsFeature {
    private(set) var selected: AppColourTheme
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private let privacyPolicyLoader: any PrivacyPolicyLoading
    private static let storageKey = "rocketlaunch.colourTheme"

    init(defaults: UserDefaults? = nil, privacyPolicyLoader: any PrivacyPolicyLoading = BundledPrivacyPolicyLoader()) {
        self.defaults = defaults
        self.privacyPolicyLoader = privacyPolicyLoader
        selected = defaults?.string(forKey: Self.storageKey).flatMap(AppColourTheme.init(rawValue:)) ?? .system
    }
    let spaceXURL = URL(string: "https://github.com/r-spacex/SpaceX-API")!
    let launchLibraryURL = URL(string: "https://thespacedevs.com/llapi")!
    let rocketLaunchURL = URL(string: "https://www.rocketlaunch.live")!

    func loadPrivacyPolicy() async throws -> String {
        try await privacyPolicyLoader.load()
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
