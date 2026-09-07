import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "sparkles").font(.largeTitle)
                            .foregroundStyle(themeManager.selected.accent)
                        Text("Space is for everyone.").font(.title.bold())
                        Text("When is the next rocket launch? Who’s launching it, from where, and what is the mission for? RocketLaunch gives you the essentials, completely free. No in-app purchases.")
                            .foregroundStyle(.secondary)
                    }
                }
                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Behind the schedule").font(.headline)
                        Text("Launch information comes from RocketLaunch.Live and The Space Devs’ Launch Library. Schedules are provisional and can change; some mission details may not yet be available.")
                            .foregroundStyle(.secondary)
                        Link("Visit The Space Devs", destination: URL(string: "https://thespacedevs.com/llapi")!)
                        Link(destination: URL(string: "https://www.rocketlaunch.live")!) {
                            Label("Visit RocketLaunch.Live", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                Text("Made for the curious.").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(themeManager.selected.background)
        .foregroundStyle(themeManager.selected.foreground)
        .navigationTitle("About")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
