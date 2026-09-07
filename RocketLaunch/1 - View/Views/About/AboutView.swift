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
                        Text("Launch information comes from RocketLaunch.Live, The Space Devs’ Launch Library, and the community SpaceX API. The SpaceX API is not an official SpaceX service. Schedules are provisional and can change; some mission details may not yet be available.")
                            .foregroundStyle(.secondary)
                        Link(destination: URL(string: "https://github.com/r-spacex/SpaceX-API")!) {
                            Label("Community SpaceX API", systemImage: "arrow.up.right.square")
                        }
                        Link(destination: URL(string: "https://thespacedevs.com/llapi")!) {
                            Label("Visit The Space Devs", systemImage: "arrow.up.right.square")
                        }
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
