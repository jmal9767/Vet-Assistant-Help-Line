import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            EmergencyView()
                .tabItem {
                    Label("Emergency", systemImage: "exclamationmark.triangle.fill")
                }

            AskQuestionView()
                .tabItem {
                    Label("Ask", systemImage: "envelope.fill")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "pawprint.fill")
                }
        }
        .tint(Color("AccentColor"))
    }
}

#Preview {
    ContentView()
}
