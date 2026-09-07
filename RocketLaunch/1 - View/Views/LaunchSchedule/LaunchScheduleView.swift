import SwiftUI

struct LaunchScheduleView: View {
    @State private var viewModel = LaunchScheduleViewModel()
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(viewModel.hasLaunch ? "Next Launch" : "Get Next Rocket Launch")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                if viewModel.hasLaunch {
                    Text("Name: \(viewModel.launchName)")
                    Text("Mission: \(viewModel.mission)")
                }
                if viewModel.isLoading {
                    ProgressView("Loading launches…")
                }
                if viewModel.isEmpty {
                    Text("No upcoming launches were returned. Try refreshing again later.")
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(themeManager.selected.error)
                        .accessibilityIdentifier("launchError")
                }
                Button(viewModel.errorMessage == nil ? "Refresh" : "Try Again") {
                    viewModel.requestRefresh()
                }
                .buttonStyle(.borderedProminent)
                .foregroundStyle(themeManager.selected.buttonForeground)
                .accessibilityIdentifier("refreshLaunches")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .foregroundStyle(themeManager.selected.foreground)
        .background(themeManager.selected.background)
        .onDisappear { viewModel.cancelRefresh() }
    }
}

#Preview {
    LaunchScheduleView().environment(ThemeManager())
}
