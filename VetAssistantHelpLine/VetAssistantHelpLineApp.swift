import SwiftUI

@main
struct VetAssistantHelpLineApp: App {
    @StateObject private var inbox = PrivateInbox()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(inbox)
                .overlay {
                    if scenePhase != .active {
                        Color(.systemBackground).ignoresSafeArea().overlay {
                            Label("Private inbox", systemImage: "lock.fill").font(.title2)
                        }
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { inbox.lock() }
                }
        }
    }
}
