import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            InboxView()
                .tabItem { Label("Inbox", systemImage: "tray.fill") }
                .tag(0)

            CommunicationsView()
                .tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right.fill") }
                .tag(1)

            PaymentsView()
                .tabItem { Label("Payments", systemImage: "creditcard.fill") }
                .tag(2)

            ShareView()
                .tabItem { Label("Share", systemImage: "qrcode.viewfinder") }
                .tag(3)

            SettingsView()
                .tabItem { Label("More", systemImage: "ellipsis.circle.fill") }
                .tag(4)
        }
        .tint(AppPalette.brand)
        .onReceive(NotificationCenter.default.publisher(for: .openQuestionFromPush)) { _ in
            selectedTab = 0
        }
    }
}

#Preview { ContentView().environment(QuestionStore()) }
