import SwiftUI

struct LaunchDetailContent: View {
    let launch: RocketLaunch
    let presentation: LaunchPresentation
    @Environment(\.appColourTheme) private var theme
    let reminderSaved: Bool
    let isBusy: Bool
    @Binding var minutesBefore: Int
    let save: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(presentation.launchTitle).font(.largeTitle.bold())
                AppCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(presentation.launchTime, systemImage: "clock").font(.title3.bold())
                        Text(presentation.timingNote).foregroundStyle(.secondary)
                    }
                }
                AppCard {
                    VStack(alignment: .leading, spacing: 16) {
                        detail("Operator", presentation.provider)
                        detail("Rocket", presentation.vehicle)
                        detail("Launch country", presentation.country)
                        detail("Launch site", presentation.site)
                    }
                }
                if let url = launch.details.watchURL {
                    Link(destination: url) { Label("Watch launch", systemImage: "play.circle.fill") }
                        .buttonStyle(.borderedProminent)
                }
                if let url = launch.details.detailsURL {
                    Link("More launch information", destination: url)
                }
                AppCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Reminder", systemImage: "bell").font(.headline)
                        if launch.details.plannedTime != nil {
                            Picker("Alert before launch", selection: $minutesBefore) {
                                Text("5 minutes").tag(5)
                                Text("15 minutes").tag(15)
                                Text("1 hour").tag(60)
                            }
                            Button(reminderSaved ? "Update reminder" : "Set reminder") {
                                save()
                            }.buttonStyle(.bordered).disabled(isBusy)
                            if reminderSaved { Text("Saved in Reminders").font(.caption).foregroundStyle(.secondary) }
                        } else {
                            Text("Reminders become available when an exact launch time is announced.")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Text("What for?").font(.headline)
                Text(presentation.missionSummary)
                Text("Data by \(launch.source.name). Details reflect the downloaded record you selected.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(theme.background)
        .modifier(ThemedListBackground())
    }
    private func detail(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
    }
}

