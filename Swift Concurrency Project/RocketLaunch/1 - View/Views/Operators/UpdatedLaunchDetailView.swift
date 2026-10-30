import SwiftUI

struct UpdatedLaunchDetailView: View {
    @State private var viewModel: UpdatedLaunchDetailViewModel

    init(launch: RocketLaunch) {
        _viewModel = State(initialValue: UpdatedLaunchDetailViewModel(launch: launch))
    }

    var body: some View {
        Group {
            if let launch = viewModel.launch {
                LaunchDetailContent(launch: launch, presentation: viewModel.presentation, reminderSaved: viewModel.reminderSaved,
                    isBusy: viewModel.isBusy, minutesBefore: $viewModel.minutesBefore,
                    save: { viewModel.save() })
            } else {
                ContentUnavailableView("Choose a launch", systemImage: "calendar")
            }
        }
        .alert("Reminder", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } })) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: { Text(viewModel.errorMessage ?? "") }
        .navigationTitle("Launch details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
