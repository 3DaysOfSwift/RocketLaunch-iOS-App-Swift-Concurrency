import SwiftUI

struct AppCard<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(themeManager.selected.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct ThemedListBackground: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden).background(themeManager.selected.background)
    }
}
