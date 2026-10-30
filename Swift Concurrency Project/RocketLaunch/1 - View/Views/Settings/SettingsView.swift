import SwiftUI

struct SettingsView: View {
    @State private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Colour theme", selection: $viewModel.selectedTheme) {
                    ForEach(AppColourTheme.allCases) { theme in
                        Text(theme.name).tag(theme)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Double-tap the Next screen to cycle through the themes. Your choice is saved automatically. System follows your device’s appearance.")
            }
            .listRowBackground(viewModel.selectedTheme.surface)
            Section("Privacy") {
                NavigationLink("Privacy policy") { PrivacyPolicyView() }
            }
            .listRowBackground(viewModel.selectedTheme.surface)
            Section("Preview") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(viewModel.selectedTheme.name, systemImage: "sparkles").font(.headline)
                    Text("Ready for the next launch.").font(.title2.bold())
                }
                .foregroundStyle(.white)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowBackground(viewModel.selectedTheme.heroGradient)
        }
        .scrollContentBackground(.hidden)
        .background(viewModel.selectedTheme.background)
        .tint(viewModel.selectedTheme.accent)
        .preferredColorScheme(viewModel.selectedTheme.colourScheme)
        .navigationTitle("Settings")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
