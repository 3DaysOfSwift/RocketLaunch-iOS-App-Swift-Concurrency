import SwiftUI

struct OperatorLaunchesView: View {
    let operatorID: String
    let name: String
    @State private var viewModel = OperatorLaunchesViewModel()

    var body: some View {
        ThemedList {
            Section {
                SourceStatusView(sources: viewModel.relevantSources(for: operatorID), refresh: { viewModel.requestRefresh(source: $0) })
            }
            Section("Launches") {
                if viewModel.launches(for: operatorID).isEmpty {
                    Text("No launches currently listed for this operator.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.launches(for: operatorID)) { launch in
                    NavigationLink { LaunchDetailView(launch: launch) } label: {
                        LaunchListRow(viewModel: LaunchDetailViewModel(launch: launch), source: launch.source.name)
                    }
                }
            }
        }
        .modifier(ThemedListBackground())
        .onDisappear { viewModel.cancelRefresh() }
        .navigationTitle(name)
    }
}

struct LaunchListRow: View {
    let viewModel: LaunchDetailViewModel
    let source: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(viewModel.launchTitle).font(.headline)
            Text(viewModel.launchTime).font(.subheadline)
            Text(viewModel.vehicle).font(.subheadline).foregroundStyle(.secondary)
            Text(source).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
}

struct LaunchDetailView: View {
    let launch: RocketLaunch
    @Environment(ThemeManager.self) private var themeManager
    @State private var reminders = LaunchDetailScreenViewModel()
    @State private var minutesBefore = 15
    private var viewModel: LaunchDetailViewModel { .init(launch: launch) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(viewModel.launchTitle).font(.largeTitle.bold())
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(viewModel.launchTime, systemImage: "clock").font(.title3.bold())
                        Text(viewModel.timingNote).foregroundStyle(.secondary)
                    }
                }
                AppCard {
                    VStack(alignment: .leading, spacing: 16) {
                        detail("Operator", viewModel.provider)
                        detail("Rocket", viewModel.vehicle)
                        detail("Launch country", viewModel.country)
                        detail("Launch site", viewModel.site)
                    }
                }
                if let url = launch.details.watchURL {
                    Link(destination: url) { Label("Watch launch", systemImage: "play.circle.fill") }
                        .buttonStyle(.borderedProminent)
                }
                if let url = launch.details.detailsURL {
                    Link("More launch information", destination: url)
                }
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Reminder", systemImage: "bell").font(.headline)
                        if launch.details.plannedTime != nil {
                            Picker("Alert before launch", selection: $minutesBefore) {
                                Text("5 minutes").tag(5)
                                Text("15 minutes").tag(15)
                                Text("1 hour").tag(60)
                            }
                            Button(reminders.contains(launch.id) ? "Update reminder" : "Set reminder") {
                                reminders.save(launch.id, minutesBefore: minutesBefore)
                            }.buttonStyle(.bordered).disabled(reminders.isBusy)
                            if reminders.contains(launch.id) { Text("Saved in Reminders").font(.caption).foregroundStyle(.secondary) }
                        } else {
                            Text("Reminders become available when an exact launch time is announced.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("What for?").font(.headline)
                Text(viewModel.missionSummary)
                Text("Data by \(launch.source.name). Details reflect the downloaded record you selected.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(themeManager.selected.background)
        .modifier(ThemedListBackground())
        .alert("Reminder", isPresented: Binding(get: { reminders.errorMessage != nil }, set: { if !$0 { reminders.errorMessage = nil } })) {
            Button("OK") { reminders.errorMessage = nil }
        } message: { Text(reminders.errorMessage ?? "") }
        .navigationTitle("Launch details")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
    }
}

struct SourceStatusView: View {
    @Environment(ThemeManager.self) private var themeManager
    let sources: [LaunchSourceSnapshot]
    let refresh: (LaunchSourceID) -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            statusContent
        }
    }
    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(source.id.name).font(.subheadline.bold())
                        Spacer()
                        if source.phase == .loading { ProgressView() }
                        else {
                            Button("Refresh") { refresh(source.id) }
                                .font(.caption).buttonStyle(.borderless)
                                .disabled(!SourceStatusPresentation.canRetry(source))
                                .accessibilityLabel("Refresh \(source.id.name)")
                        }
                    }
                    if case .failed = source.phase {
                        Label(SourceStatusPresentation.message(source), systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(themeManager.selected.error)
                    } else {
                        Text(SourceStatusPresentation.message(source)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let date = source.nextRefreshAt, date > Date(), source.phase != .loading {
                        Text("Refresh available after \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
