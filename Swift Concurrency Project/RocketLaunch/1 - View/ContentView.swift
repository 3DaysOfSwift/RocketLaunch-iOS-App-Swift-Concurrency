import SwiftUI

struct ContentView: View {
    @State private var selection = "next"
    @Environment(\.appColourTheme) private var theme

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { LaunchScheduleView() }
                .tabItem { Label("Next", systemImage: "clock") }.tag("next")
            NavigationStack { UpcomingView() }
                .tabItem { Label("Schedule", systemImage: "calendar") }.tag("upcoming")
            NavigationStack { OperatorsView() }
                .tabItem { Label("Operators", systemImage: "building.2") }.tag("operators")
            NavigationStack { UpdatesView() }
                .tabItem { Label("Changes", systemImage: "arrow.triangle.2.circlepath") }.tag("updates")
            NavigationStack { RemindersView() }
                .tabItem { Label("Reminders", systemImage: "bell") }.tag("reminders")
        }
        .tint(theme.accent)
        .preferredColorScheme(theme.colourScheme)
        .animation(.easeInOut(duration: 0.25), value: theme)
    }
}

#Preview { ContentView().environment(\.appColourTheme, .system) }
