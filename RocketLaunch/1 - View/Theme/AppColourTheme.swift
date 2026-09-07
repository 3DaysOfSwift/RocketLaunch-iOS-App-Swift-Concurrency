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
    var foreground: Color { self == .midnight ? .white : .primary }
    var buttonForeground: Color { .white }
    var error: Color { self == .midnight ? .orange : .red }
}
