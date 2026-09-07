import SwiftUI

struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Picker("Colour theme", selection: Binding(get: { themeManager.selected }, set: { themeManager.select($0) })) {
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
            .listRowBackground(themeManager.selected.surface)
            Section("Preview") {
                VStack(alignment: .leading, spacing: 12) {
                    Label(themeManager.selected.name, systemImage: "sparkles").font(.headline)
                    Text("Ready for the next launch.").font(.title2.bold())
                }
                .foregroundStyle(.white)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowBackground(themeManager.selected.heroGradient)
        }
        .scrollContentBackground(.hidden)
        .background(themeManager.selected.background)
        .tint(themeManager.selected.accent)
        .preferredColorScheme(themeManager.selected.colourScheme)
        .navigationTitle("Settings")
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
