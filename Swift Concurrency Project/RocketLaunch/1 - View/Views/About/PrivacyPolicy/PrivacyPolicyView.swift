import SwiftUI

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
