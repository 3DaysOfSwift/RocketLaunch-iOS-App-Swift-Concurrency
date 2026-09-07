import Observation

@MainActor
@Observable
final class ThemeManager {
    private(set) var selected: AppColourTheme = .system
    func select(_ theme: AppColourTheme) { selected = theme }
}
