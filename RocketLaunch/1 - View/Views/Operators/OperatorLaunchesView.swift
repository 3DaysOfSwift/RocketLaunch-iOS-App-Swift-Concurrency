import SwiftUI

struct OperatorLaunchesView: View {
    let operatorID: String
    let name: String
    let viewModel: LaunchScheduleViewModel

    var body: some View {
        List {
            Section {
                SourceStatusView(viewModel: viewModel, operatorID: operatorID)
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
        .navigationTitle(name)
    }
}

private struct LaunchListRow: View {
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
                Text("What for?").font(.headline)
                Text(viewModel.missionSummary)
                Text("Data by \(launch.source.name). Details reflect the downloaded record you selected.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(themeManager.selected.background)
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
    let viewModel: LaunchScheduleViewModel
    var operatorID: String? = nil
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            statusContent
        }
    }
    private var statusContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(viewModel.relevantSources(for: operatorID)) { source in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(source.id.name).font(.subheadline.bold())
                        Spacer()
                        if source.phase == .loading { ProgressView() }
                        else {
                            Button("Refresh") { viewModel.requestRefresh(source: source.id) }
                                .font(.caption).buttonStyle(.borderless)
                                .disabled(!viewModel.canRetry(source))
                                .accessibilityLabel("Refresh \(source.id.name)")
                        }
                    }
                    if case .failed = source.phase {
                        Label(viewModel.sourceMessage(source), systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.red)
                    } else {
                        Text(viewModel.sourceMessage(source)).font(.caption).foregroundStyle(.secondary)
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
