import SwiftUI

struct UpcomingView: View {
    let viewModel: LaunchScheduleViewModel
    @State private var filters = BrowseViewModel()
    var body: some View {
        List {
            Section {
                Picker("Operator", selection: $filters.operatorID) {
                    Text("All operators").tag("")
                    ForEach(viewModel.operators) { Text($0.name).tag($0.id) }
                }
                countryFilter
            }
            Section {
                ForEach(filters.launches(in: viewModel.operators)) { launch in
                    NavigationLink { LaunchDetailView(launch: launch) } label: {
                        LaunchListRow(viewModel: .init(launch: launch), source: launch.source.name)
                    }
                }
                if filters.launches(in: viewModel.operators).isEmpty {
                    Text(viewModel.isLoading ? "Loading launches…" : "No launches match these filters.")
                        .foregroundStyle(.secondary)
                }
            } footer: { Text("Launches are attributed to each source. The same launch may appear more than once.") }
            Section("Data sources") { SourceStatusView(viewModel: viewModel) }
        }
        .navigationTitle("Upcoming")
        .searchable(text: $filters.search, prompt: "Mission, rocket or operator")
        .toolbar { Button { viewModel.requestRefresh() } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh launches") }
    }
    private var countryFilter: some View {
        Picker("Launch country", selection: $filters.country) {
            Text("All countries").tag("")
            ForEach(filters.countries(in: viewModel.operators), id: \.self) { Text($0).tag($0) }
        }
    }
}

struct OperatorsView: View {
    let viewModel: LaunchScheduleViewModel
    @State private var filters = BrowseViewModel()
    var body: some View {
        List {
            Picker("Launch country", selection: $filters.country) {
                Text("All countries").tag("")
                ForEach(filters.countries(in: viewModel.operators), id: \.self) { Text($0).tag($0) }
            }
            ForEach(filters.operators(in: viewModel.operators)) { item in
                NavigationLink {
                    OperatorLaunchesView(operatorID: item.id, name: item.name, viewModel: viewModel)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.name).font(.headline)
                        Text("\(item.launches.count) launch records").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            if filters.operators(in: viewModel.operators).isEmpty {
                Text(viewModel.isLoading ? "Finding operators…" : "No operators match these filters.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Operators")
        .searchable(text: $filters.search, prompt: "Find an operator")
    }
}

struct UpdatesView: View {
    let viewModel: LaunchScheduleViewModel
    var body: some View {
        List {
            if viewModel.updates.isEmpty {
                ContentUnavailableView("No changes detected yet", systemImage: "arrow.triangle.2.circlepath",
                    description: Text("When a refresh reveals a changed launch time or mission, it will appear here."))
            }
            ForEach(viewModel.updates) { update in
                NavigationLink { LaunchDetailView(launch: update.launch) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(update.launch.name).font(.headline)
                        if update.timeChanged {
                            Text("Previously: \(LaunchDetailViewModel(launch: update.previous).launchTime)")
                                .foregroundStyle(.secondary)
                            Text("Now: \(LaunchDetailViewModel(launch: update.launch).launchTime)")
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
        .navigationTitle("Updates")
        .toolbar { Button("Refresh") { viewModel.requestRefresh() } }
    }
}
