import SwiftUI

struct LaunchScheduleView: View {
    @State private var viewModel = LaunchScheduleViewModel()
    @State private var showsAbout = false
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if viewModel.hasLaunch {
                    timing
                    AppCard {
                        VStack(alignment: .leading, spacing: 18) {
                            fact("Who", viewModel.provider, "building.2")
                            Divider()
                            fact("Rocket", viewModel.vehicle, "arrow.up.right")
                            Divider()
                            fact("Launch country", viewModel.country, "globe")
                            Text(viewModel.site).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What for?").font(.headline)
                            Text(viewModel.launchTitle).font(.title3.bold())
                            Text(viewModel.missionSummary).foregroundStyle(.secondary)
                        }
                    }
                } else if viewModel.isLoading {
                    ProgressView("Finding the next launch…")
                        .frame(maxWidth: .infinity).padding(.vertical, 80)
                } else if viewModel.isEmpty {
                    ContentUnavailableView("No launches listed", systemImage: "moon.stars",
                        description: Text("Check again soon for an updated schedule."))
                }
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(themeManager.selected.error)
                        .accessibilityIdentifier("launchError")
                }
                if !viewModel.isLoading {
                    Button { viewModel.requestRefresh() } label: {
                        Label(viewModel.errorMessage == nil ? "Refresh schedule" : "Try again", systemImage: "arrow.clockwise")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("refreshLaunches")
                } else if viewModel.hasLaunch {
                    ProgressView("Updating schedule…").frame(maxWidth: .infinity)
                }
                Link("Data by RocketLaunch.Live", destination: URL(string: "https://www.rocketlaunch.live")!)
                    .font(.footnote).frame(maxWidth: .infinity)
            }.padding(20)
        }
        .background(themeManager.selected.background)
        .foregroundStyle(themeManager.selected.foreground)
        .navigationTitle("Next launch")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsAbout = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About RocketLaunch")
            }
        }
        .sheet(isPresented: $showsAbout) { NavigationStack { AboutView() } }
        .onAppear { viewModel.loadIfNeeded() }
        .onDisappear { viewModel.cancelRefresh() }
    }

    private var timing: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("NEXT SCHEDULED LAUNCH", systemImage: "clock")
                .font(.caption.weight(.semibold)).tracking(1)
            Text(viewModel.launchTime).font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
            Text(viewModel.timingNote).font(.subheadline).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(24)
        .foregroundStyle(.white)
        .background(themeManager.selected.heroGradient, in: RoundedRectangle(cornerRadius: 24))
    }

    private func fact(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
    }
}

#Preview { NavigationStack { LaunchScheduleView() }.environment(ThemeManager()) }
