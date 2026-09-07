import SwiftUI

struct ContentView: View {
    @State private var viewModel = LaunchScheduleViewModel()
    @State private var selection = "next"
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { LaunchScheduleView(viewModel: viewModel) }
                .tabItem { Label("Next", systemImage: "clock") }.tag("next")
            ForEach(viewModel.operators) { launchOperator in
                NavigationStack {
                    OperatorLaunchesView(operatorID: launchOperator.id, name: launchOperator.name, viewModel: viewModel)
                }
                .tabItem { Label(viewModel.tabTitle(for: launchOperator), systemImage: "sparkles") }
                .tag(launchOperator.id)
            }
        }
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
