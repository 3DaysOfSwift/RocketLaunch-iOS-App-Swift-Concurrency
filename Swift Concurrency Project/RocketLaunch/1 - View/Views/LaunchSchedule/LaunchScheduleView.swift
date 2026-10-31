import SwiftUI

struct LaunchScheduleView: View {
    @State private var viewModel = LaunchScheduleViewModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize = 44
    @State private var showsSettings = false
    @State private var showsAbout = false
    @State private var showsSources = false
    @Environment(\.appColourTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if viewModel.hasLaunch {
                    timing
                    if let savedScheduleMessage = viewModel.savedScheduleMessage {
                        Label(savedScheduleMessage, systemImage: "clock.arrow.circlepath")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    missionCard
                    if let launch = viewModel.currentLaunch {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 20) { launchActions(launch) }
                            VStack(alignment: .leading, spacing: 16) { launchActions(launch) }
                        }
                    }
                } else if viewModel.isLoading {
                    ProgressView("Finding the next launch…")
                        .frame(maxWidth: .infinity).padding(.vertical, 80)
                } else if viewModel.isEmpty {
                    ContentUnavailableView("No launches listed", systemImage: "moon.stars",
                        description: Text("Check again soon for an updated schedule."))
                }
                if let error = viewModel.savedScheduleError {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(theme.error)
                }
                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .foregroundStyle(theme.error)
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
        .simultaneousGesture(TapGesture(count: 2).onEnded { viewModel.selectNextTheme() })
        .safeAreaInset(edge: .bottom) {
            if let error = viewModel.themeError {
                Text(error).font(.caption).padding(8).background(.regularMaterial)
            }
        }
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .onDisappear { viewModel.cancelRefresh() }
        .navigationTitle("Next launch")
        .navigationDestination(isPresented: $viewModel.showingLaunch) {
            if let launch = viewModel.selectedLaunch { LaunchDetailView(launch: launch) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showsSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsAbout = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About RocketLaunch")
            }
        }
        .sheet(isPresented: $showsSources) { NavigationStack { ThemedList { SourceStatusView(sources: viewModel.sources, refresh: { viewModel.requestRefresh(source: $0) }) }.navigationTitle("Data sources").toolbar { Button("Done") { showsSources = false } } } }
        .sheet(isPresented: $showsSettings) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showsAbout) { NavigationStack { AboutView() } }

    }

    private var timing: some View {
        VStack(spacing: 18) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 20) {
                        visorArtwork.frame(height: 140)
                        countdown(viewModel.countdown(at: context.date))
                            .padding(.horizontal, 20).padding(.bottom, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .background(theme.visorBackground, in: RoundedRectangle(cornerRadius: 28))
                } else {
                    visorArtwork
                        .overlay { countdown(viewModel.countdown(at: context.date)).padding(.horizontal, 42) }
                }
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 320)
            VStack(spacing: 6) {
                Text(viewModel.launchTime)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(viewModel.timingNote)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
        }
    }

    private var visorArtwork: some View {
        Image("LaunchVisor")
            .resizable().scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .accessibilityHidden(true)
    }

    private func countdown(_ presentation: CountdownPresentation) -> some View {
        VStack(spacing: 10) {
            Text("NEXT SCHEDULED LAUNCH")
                .font(.caption2.weight(.semibold)).tracking(1.5)
            if let days = presentation.days {
                Text(days).font(.subheadline.weight(.medium)).monospacedDigit()
            }
            if let clock = presentation.clock {
                Text(clock)
                    .font(.system(size: countdownSize, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .shadow(color: theme.visorGlow, radius: 12)
            }
            Text(presentation.status)
                .font(presentation.clock == nil ? .title3.weight(.medium) : .caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme.visorForeground)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityText)
        .accessibilityIdentifier("launchCountdown")
    }

    private var missionCard: some View {
        AppCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.launchTitle).font(.title2.weight(.semibold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        Label(viewModel.provider, systemImage: "building.2")
                        Label(viewModel.country, systemImage: "globe")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(viewModel.provider, systemImage: "building.2")
                        Label(viewModel.country, systemImage: "globe")
                    }
                }
                .font(.subheadline)
                Label(viewModel.vehicle, systemImage: "arrow.up.right")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let summary = viewModel.missionPreview {
                    Text(summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }

    @ViewBuilder private func launchActions(_ launch: RocketLaunch) -> some View {
        Button { viewModel.showLaunch(launch) } label: {
            Label("Launch details", systemImage: "arrow.right")
        }
        .buttonStyle(.borderedProminent)
        .foregroundStyle(theme.buttonForeground)
        if let url = launch.details.watchURL {
            Link(destination: url) { Label("Watch launch", systemImage: "play.circle.fill") }
        }
    }
}

#Preview { NavigationStack { LaunchScheduleView() }.environment(\.appColourTheme, .system) }
