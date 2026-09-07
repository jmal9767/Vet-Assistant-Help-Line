import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }

            TemplatesView()
                .tabItem {
                    Label("Templates", systemImage: "doc.on.doc.fill")
                }

            ShareView()
                .tabItem {
                    Label("Share", systemImage: "qrcode")
                }

            ReferenceView()
                .tabItem {
                    Label("Reference", systemImage: "cross.case.fill")
                }
        }
        .tint(Color("AccentColor"))
    }
}

#Preview {
    ContentView()
        .environment(QuestionStore())
}
