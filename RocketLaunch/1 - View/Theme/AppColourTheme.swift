import SwiftUI

/// A second development palette keeps the screen's colours explicitly owned.
enum AppColourTheme: Equatable {
    case system, midnight

    var background: Color {
        if self == .midnight { return Color(red: 0.05, green: 0.07, blue: 0.13) }
        #if os(iOS)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }
    var surface: Color {
        if self == .midnight { return Color(red: 0.09, green: 0.12, blue: 0.20) }
        #if os(iOS)
        return Color(uiColor: .secondarySystemBackground)
        #else
        return Color(nsColor: .controlBackgroundColor)
        #endif
    }
    var accent: Color { self == .midnight ? .cyan : Color(red: 0.16, green: 0.34, blue: 0.70) }
    var heroGradient: LinearGradient {
        LinearGradient(colors: [Color(red: 0.06, green: 0.12, blue: 0.24), Color(red: 0.12, green: 0.27, blue: 0.40)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var foreground: Color { self == .midnight ? .white : .primary }
    var buttonForeground: Color { self == .midnight ? .black : .white }
    var error: Color { self == .midnight ? .orange : .red }
}
