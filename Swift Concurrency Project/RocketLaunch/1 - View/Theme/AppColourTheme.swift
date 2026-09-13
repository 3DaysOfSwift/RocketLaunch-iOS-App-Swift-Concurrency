import SwiftUI

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
    var colourScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .midnight, .nebula, .crimson: .dark
        default: .light
        }
    }
    private var palette: (background: UInt32, surface: UInt32, accent: UInt32, heroStart: UInt32, heroEnd: UInt32) {
        switch self {
        case .system: (0xFFFFFF, 0xF2F2F7, 0x2957B3, 0x0F1F3D, 0x1F4566)
        case .midnight: (0x0D1221, 0x172133, 0x67DCFA, 0x15294D, 0x21546B)
        case .ocean: (0xEDF7FA, 0xDAEEF3, 0x006982, 0x064257, 0x087D91)
        case .forest: (0xF0F5ED, 0xE0EBDA, 0x32633B, 0x183C2C, 0x3A6B44)
        case .sunset: (0xFFF4ED, 0xFBE4D5, 0xA13D25, 0x762C35, 0xB6502B)
        case .nebula: (0x191329, 0x2A2040, 0xD6B1FF, 0x36205B, 0x69417D)
        case .lunar: (0xF5F3EE, 0xE8E5DD, 0x55534D, 0x333B43, 0x62635D)
        case .crimson: (0x300D16, 0x481824, 0xFFB3A7, 0x591425, 0x8B2939)
        }
    }
    var background: Color {
        if self == .system {
            #if os(iOS)
            return Color(uiColor: .systemBackground)
            #else
            return Color(nsColor: .windowBackgroundColor)
            #endif
        }
        return colour(palette.background)
    }
    var surface: Color {
        if self == .system {
            #if os(iOS)
            return Color(uiColor: .secondarySystemBackground)
            #else
            return Color(nsColor: .controlBackgroundColor)
            #endif
        }
        return colour(palette.surface)
    }
    var accent: Color { colour(palette.accent) }
    var heroGradient: LinearGradient {
        LinearGradient(colors: [colour(palette.heroStart), colour(palette.heroEnd)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    var foreground: Color { .primary }
    var separator: Color { foreground.opacity(0.15) }
    var buttonForeground: Color { colourScheme == .dark ? .black : .white }
    var error: Color { colourScheme == .dark ? .orange : .red }
    private func colour(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
}
