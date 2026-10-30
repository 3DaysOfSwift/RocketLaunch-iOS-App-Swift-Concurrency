import SwiftUI

struct UpdatesView: View {
    @State private var viewModel = UpdatesViewModel()
    var body: some View {
        ThemedList {
            Section {
                SourceStatusView(sources: viewModel.sources, refresh: { viewModel.requestRefresh(source: $0) })
            }
            if viewModel.updates.isEmpty {
                ContentUnavailableView("No changes detected yet", systemImage: "arrow.triangle.2.circlepath",
                    description: Text("When a refresh reveals a changed launch time or mission, it will appear here."))
            }
            ForEach(viewModel.updates) { update in
                Button { viewModel.showLaunch(update.launch) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(update.launch.name).font(.headline)
                        if update.timeChanged {
                            Text("Previously: \(viewModel.previousLaunchTime(for: update))")
                                .foregroundStyle(.secondary)
                            Text("Now: \(viewModel.currentLaunchTime(for: update))")
                        } else { Text("Mission information updated") }
                        Text(viewModel.sourceAndDetectionTime(for: update))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Text("Changes are compared with each source’s previous download during this app session. This is a schedule log, not a news feed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .modifier(ThemedListBackground())
        .onDisappear { viewModel.cancelRefresh() }
        .navigationTitle("Changes")
        .navigationDestination(isPresented: $viewModel.showingLaunch) {
            if let launch = viewModel.selectedLaunch { UpdatedLaunchDetailView(launch: launch) }
        }
        .toolbar { Button("Refresh") { viewModel.requestRefresh() } }
    }
}

