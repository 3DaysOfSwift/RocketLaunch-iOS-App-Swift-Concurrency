import SwiftUI

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
        .navigationDestination(isPresented: $viewModel.showingOperator) {
            if let selected = viewModel.selectedOperator { OperatorLaunchesView(operator: selected) }
        }
        .searchable(text: $viewModel.filters.search, prompt: "Search companies and agencies")
    }
}
