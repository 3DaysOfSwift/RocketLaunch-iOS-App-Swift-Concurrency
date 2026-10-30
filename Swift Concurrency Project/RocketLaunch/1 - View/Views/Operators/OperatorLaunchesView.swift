import SwiftUI

struct OperatorLaunchesView: View {
    @State private var viewModel = OperatorLaunchesViewModel()

    var body: some View {
        ThemedList {
            Section {
                SourceStatusView(sources: viewModel.sources, refresh: { viewModel.requestRefresh(source: $0) })
            }
            Section("Launches") {
                if viewModel.launches.isEmpty {
                    Text("No launches currently listed for this operator.")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.launches) { launch in
                    Button { viewModel.showLaunch(launch) } label: {
                        LaunchListRow(presentation: LaunchPresentation(launch: launch), source: launch.source.name)
                    }.buttonStyle(.plain)
                }
            }
        }
        .modifier(ThemedListBackground())
        .onDisappear { viewModel.cancelRefresh() }
        .navigationTitle(viewModel.title)
        .navigationDestination(isPresented: $viewModel.showingLaunch) { OperatorLaunchDetailView() }
    }
}

struct LaunchListRow: View {
    let presentation: LaunchPresentation
    let source: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(presentation.launchTitle).font(.headline)
            Text(presentation.launchTime).font(.subheadline)
            Text(presentation.vehicle).font(.subheadline).foregroundStyle(.secondary)
            Text(source).font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
}

struct SourceStatusView: View {
    @Environment(ThemeManager.self) private var themeManager
    let sources: [LaunchSourceSnapshot]
    let refresh: (LaunchSourceID) -> Void
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            statusContent(at: context.date)
        }
    }
    private func statusContent(at date: Date) -> some View {
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
                                .disabled(!SourceStatusPresentation.canRetry(source, at: date))
                                .accessibilityLabel("Refresh \(source.id.name)")
                        }
                    }
                    if case .failed = source.phase {
                        Label(SourceStatusPresentation.message(source, at: date), systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(themeManager.selected.error)
                    } else {
                        Text(SourceStatusPresentation.message(source, at: date)).font(.caption).foregroundStyle(.secondary)
                    }
                    if let retryDate = source.nextRefreshAt, retryDate > date, source.phase != .loading {
                        Text("Refresh available after \(retryDate.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
