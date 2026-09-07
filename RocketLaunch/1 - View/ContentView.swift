import SwiftUI

struct ContentView: View {
    @Environment(ThemeManager.self) private var themeManager
    var body: some View {
        NavigationStack { LaunchScheduleView() }
            .tint(themeManager.selected.accent)
    }
}

#Preview { ContentView().environment(ThemeManager()) }
