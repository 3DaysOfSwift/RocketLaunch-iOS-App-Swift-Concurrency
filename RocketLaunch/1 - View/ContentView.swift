import SwiftUI

struct ContentView: View {
    var body: some View { LaunchScheduleView() }
}

#Preview {
    ContentView().environment(ThemeManager())
}
