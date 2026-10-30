import SwiftUI

struct AppCard<Content: View>: View {
    @Environment(\.appColourTheme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ThemedListBackground: ViewModifier {
    @Environment(\.appColourTheme) private var theme
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background(theme.background)
    }
}

/// Apply row styling to the list content, not the surrounding List background.
struct ThemedList<Content: View>: View {
    @Environment(\.appColourTheme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Group { content }
                .listRowBackground(theme.surface)
                .listRowSeparatorTint(theme.separator)
        }
        .foregroundStyle(theme.foreground)
        .tint(theme.accent)
        .modifier(ThemedListBackground())
    }
}
