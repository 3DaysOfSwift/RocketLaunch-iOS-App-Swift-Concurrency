import SwiftUI

struct LaunchScheduleView: View {
    let viewModel: LaunchScheduleViewModel
    @State private var showsAbout = false
    @State private var showsSources = false
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if viewModel.hasLaunch {
                    timing
                    AppCard {
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(alignment: .top, spacing: 24) {
                                fact("Who", viewModel.provider, "building.2")
                                Spacer(minLength: 0)
                                fact("Country", viewModel.country, "globe")
                            }
                            fact("Rocket", viewModel.vehicle, "arrow.up.right")
                        }
                    }
                    AppCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("What for?").font(.headline)
                            Text(viewModel.launchTitle).font(.title3.bold())
                            Text(viewModel.missionSummary).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    if let launch = viewModel.currentLaunch {
                        NavigationLink("Launch details") { LaunchDetailView(launch: launch) }
                            .buttonStyle(.borderedProminent)
                            .foregroundStyle(themeManager.selected.buttonForeground)
                        if let url = launch.details.watchURL {
                            Link(destination: url) { Label("Watch launch", systemImage: "play.circle.fill") }
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
                    .padding(.top, 12)
                } else if viewModel.hasLaunch {
                    ProgressView("Updating schedule…").frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 16) {
                    Button("Data sources and refresh status") { showsSources = true }
                    Text("Next is based on the available sources. Schedules may disagree or change.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .padding(.bottom, 24)
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
        .sheet(isPresented: $showsSources) { NavigationStack { List { SourceStatusView(viewModel: viewModel) }.navigationTitle("Data sources").toolbar { Button("Done") { showsSources = false } } } }
        .sheet(isPresented: $showsAbout) { NavigationStack { AboutView() } }

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

#Preview { NavigationStack { LaunchScheduleView(viewModel: LaunchScheduleViewModel()) }.environment(ThemeManager()) }
