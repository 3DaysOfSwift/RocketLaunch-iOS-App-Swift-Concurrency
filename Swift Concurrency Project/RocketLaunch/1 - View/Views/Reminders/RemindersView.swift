import SwiftUI

struct RemindersView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(ReminderViewModel.self) private var viewModel
    var body: some View {
        ThemedList {
            if viewModel.reminders.isEmpty {
                ContentUnavailableView("Your launch reminders", systemImage: "bell",
                    description: Text("Open a launch’s details to set an alert before liftoff."))
            }
            ForEach(viewModel.reminders) { reminder in
                NavigationLink { LaunchDetailView(launch: reminder.launch) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(reminder.launch.name).font(.headline)
                        if reminder.status == .pending {
                            Label("Scheduling…", systemImage: "clock").font(.caption)
                        } else if let issue = reminder.issue {
                            Label(issue, systemImage: "exclamationmark.triangle").foregroundStyle(themeManager.selected.error)
                        } else {
                            Text(reminder.fireDate, format: .dateTime.month().day().hour().minute())
                            Text(reminder.fireDate > Date() ? "\(reminder.minutesBefore) minutes before launch" : "Reminder time passed")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(reminder.launch.source.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions { Button("Remove", role: .destructive) { viewModel.remove(reminder.id) }.disabled(viewModel.isBusy) }
            }
            Section {
                Text("Reminders use the last downloaded schedule. Launch time changes update reminders when the app refreshes; the app does not monitor changes in the background.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .modifier(ThemedListBackground())
        .navigationTitle("Reminders")
    }
}
