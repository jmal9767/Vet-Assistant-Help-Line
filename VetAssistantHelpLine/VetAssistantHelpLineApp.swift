import SwiftUI

@main
struct VetAssistantHelpLineApp: App {
    @StateObject private var purchaseStore = PurchaseStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(purchaseStore)
        }
    }
}
