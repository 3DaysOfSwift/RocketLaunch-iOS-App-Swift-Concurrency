import SwiftUI

struct ContentView: View {
    @State private var reminders = ReminderViewModel()
    @State private var selection = "next"
    @Environment(ThemeManager.self) private var themeManager

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
        .environment(reminders)
        .alert("Reminder", isPresented: Binding(get: { reminders.errorMessage != nil }, set: { if !$0 { reminders.errorMessage = nil } })) {
            Button("OK") { reminders.errorMessage = nil }
        } message: { Text(reminders.errorMessage ?? "") }
        .tint(themeManager.selected.accent)
        .preferredColorScheme(themeManager.selected.colourScheme)
        .animation(.easeInOut(duration: 0.25), value: themeManager.selected)
    }
}

#Preview { ContentView().environment(ThemeManager()) }
