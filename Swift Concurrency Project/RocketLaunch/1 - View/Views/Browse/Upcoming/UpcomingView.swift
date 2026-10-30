import SwiftUI

struct UpcomingView: View {
    @State private var viewModel = UpcomingViewModel()
    var body: some View {
        return ThemedList {
            Section {
                Picker("Operator", selection: $viewModel.filters.operatorID) {
                    Text("All operators").tag("")
                    ForEach(viewModel.operators) { Text($0.name).tag($0.id) }
                }
                countryFilter
            }
            Section {
                ForEach(viewModel.launches) { launch in
                    Button { viewModel.showLaunch(launch) } label: {
                        LaunchListRow(presentation: viewModel.presentation(for: launch), source: launch.source.name)
                    }
                }
                if viewModel.launches.isEmpty {
                    Text(viewModel.isLoading ? "Loading launches…" : "No launches match these filters.")
                        .foregroundStyle(.secondary)
                }
            } footer: { Text("Launches are attributed to each source. The same launch may appear more than once.") }
            Section("Data sources") { SourceStatusView(sources: viewModel.sources, refresh: { viewModel.requestRefresh(source: $0) }) }
        }
        .buttonStyle(.plain)
        .modifier(ThemedListBackground())
        .onDisappear { viewModel.cancelRefresh() }
        .navigationTitle("Upcoming")
        .navigationDestination(isPresented: $viewModel.showingLaunch) {
            if let launch = viewModel.selectedLaunch { UpcomingLaunchDetailView(launch: launch) }
        }
        .searchable(text: $viewModel.filters.search, prompt: "Mission, rocket or operator")
        .toolbar { Button { viewModel.requestRefresh() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh launches") }
    }
    private var countryFilter: some View {
        return Picker("Filter", selection: $viewModel.filters.country) {
            Text("All countries").tag("")
            ForEach(viewModel.countries, id: \.self) { Text($0).tag($0) }
        }
    }
}
