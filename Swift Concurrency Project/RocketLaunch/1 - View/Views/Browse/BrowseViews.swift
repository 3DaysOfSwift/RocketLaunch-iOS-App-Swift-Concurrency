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
                        LaunchListRow(presentation: .init(launch: launch), source: launch.source.name)
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

struct OperatorsView: View {
    @State private var viewModel = OperatorsViewModel()
    var body: some View {
        return ThemedList {
            Picker("Launch country", selection: $viewModel.filters.country) {
                Text("All countries").tag("")
                ForEach(viewModel.countries, id: \.self) { Text($0).tag($0) }
            }
            ForEach(viewModel.operators) { item in
                Button { viewModel.showOperator(item) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).font(.headline)
                        Text(viewModel.filters.launchCountLabel(for: item)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            if viewModel.operators.isEmpty {
                Text(viewModel.isLoading ? "Finding operators…" : "No operators match these filters.")
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .modifier(ThemedListBackground())
        .navigationTitle("Who’s launching?")
        .navigationDestination(isPresented: $viewModel.showingOperator) { OperatorLaunchesView() }
        .searchable(text: $viewModel.filters.search, prompt: "Search companies and agencies")
    }
}

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
                            Text("Previously: \(LaunchPresentation(launch: update.previous).launchTime)")
                                .foregroundStyle(.secondary)
                            Text("Now: \(LaunchPresentation(launch: update.launch).launchTime)")
                        } else { Text("Mission information updated") }
                        Text("\(update.launch.source.name) · \(update.detectedAt.formatted(date: .abbreviated, time: .shortened))")
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
