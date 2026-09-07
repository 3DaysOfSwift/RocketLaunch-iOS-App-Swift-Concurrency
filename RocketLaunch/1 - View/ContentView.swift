import SwiftUI

struct ContentView: View {
    @State private var viewModel = LaunchScheduleViewModel()
    @State private var reminders = ReminderViewModel()
    @State private var selection = "next"
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { LaunchScheduleView(viewModel: viewModel) }
                .tabItem { Label("Next", systemImage: "clock") }.tag("next")
            NavigationStack { UpcomingView(viewModel: viewModel) }
                .tabItem { Label("Upcoming", systemImage: "calendar") }.tag("upcoming")
            NavigationStack { OperatorsView(viewModel: viewModel) }
                .tabItem { Label("Operators", systemImage: "building.2") }.tag("operators")
            NavigationStack { UpdatesView(viewModel: viewModel) }
                .tabItem { Label("Changes", systemImage: "arrow.triangle.2.circlepath") }.tag("updates")
            NavigationStack { RemindersView() }
                .tabItem { Label("Reminders", systemImage: "bell") }.tag("reminders")
        }
        .environment(reminders)
        .alert("Reminder", isPresented: Binding(get: { reminders.errorMessage != nil }, set: { if !$0 { reminders.errorMessage = nil } })) {
            Button("OK") { reminders.errorMessage = nil }
        } message: { Text(reminders.errorMessage ?? "") }
        .tint(themeManager.selected.accent)
        .onAppear { viewModel.loadIfNeeded() }
        .task { await viewModel.monitorTime() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { viewModel.updateNextLaunch() }
        }
        .onDisappear { viewModel.cancelRefresh() }
    }
}

#Preview { ContentView().environment(ThemeManager()) }
