import SwiftUI

struct RemindersView: View {
    @Environment(\.appColourTheme) private var theme
    @State private var viewModel = ReminderViewModel()
    var body: some View {
        ThemedList {
            if let error = viewModel.storageError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.error)
                    Button("Retry loading reminders") { viewModel.loadIfNeeded() }
                }
            } else if viewModel.reminders.isEmpty {
                ContentUnavailableView("Your launch reminders", systemImage: "bell",
                    description: Text("Open a launch’s details to set an alert before liftoff."))
            }
            if let error = viewModel.writeError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(theme.error)
                    Button("Retry saving reminders") { viewModel.retryWrite() }.disabled(viewModel.isBusy)
                }
            }
            ForEach(viewModel.reminders) { reminder in
                Button { viewModel.showLaunch(reminder.launch) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reminder.launch.name).font(.headline)
                        if reminder.status == .pending {
                            Label("Scheduling…", systemImage: "clock").font(.caption)
                        } else if let issue = reminder.issue {
                            Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(theme.error)
                        } else {
                            Text(reminder.fireDate, format: .dateTime.month().day().hour().minute())
                            Text(reminder.fireDate > Date() ? "\(reminder.minutesBefore) minutes before launch" : "Reminder time passed")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(reminder.launch.source.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .swipeActions { Button("Remove", role: .destructive) { viewModel.remove(reminder.id) }.disabled(viewModel.isBusy) }
            }
            Section {
                Text("Reminders use the last downloaded schedule. Launch time changes update reminders when the app refreshes; the app does not monitor changes in the background.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .modifier(ThemedListBackground())
        .navigationTitle("Reminders")
        .navigationDestination(isPresented: $viewModel.showingLaunch) { ReminderLaunchDetailView() }
    }
}
