import SwiftUI

struct AboutView: View {
    @State private var viewModel = AboutViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColourTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                AppCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "sparkles").font(.largeTitle)
                            .foregroundStyle(theme.accent)
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
                        Link(destination: viewModel.spaceXURL) {
                            Label("Community SpaceX API", systemImage: "arrow.up.right.square")
                        }
                        Link(destination: viewModel.launchLibraryURL) {
                            Label("Visit The Space Devs", systemImage: "arrow.up.right.square")
                        }
                        Link(destination: viewModel.rocketLaunchURL) {
                            Label("Visit RocketLaunch.Live", systemImage: "arrow.up.right.square")
                        }
                    }
                }
                NavigationLink("Privacy policy") { PrivacyPolicyView() }
                Text("Made for the curious.").font(.footnote).foregroundStyle(.secondary)
            }.padding(20)
        }
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .navigationTitle("About")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// Bundled policy remains accessible without a network connection.
struct PrivacyPolicyView: View {
    @Environment(\.appColourTheme) private var theme
    @State private var viewModel = PrivacyPolicyViewModel()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let error = viewModel.loadError {
                    Text(error)
                    Button("Retry") { viewModel.retry() }
                } else {
                    Text(viewModel.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .padding(20)
        }
        .background(theme.background)
        .foregroundStyle(theme.foreground)
        .task { await viewModel.load() }
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
