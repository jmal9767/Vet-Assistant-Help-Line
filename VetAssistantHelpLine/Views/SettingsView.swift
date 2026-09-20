import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("setup.helplineEmail") private var helplineEmail = ""
    @AppStorage("setup.cashAppLink") private var cashAppLink = ""
    @State private var notificationStatus = "Checking…"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    InfoTile {
                        SectionHeader("Contact", subtitle: "These are the only details you may need to change.")
                        TextField("Public care-line email", text: $helplineEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        settingsField("Cash App for Business link", text: $cashAppLink)
                    }

                    InfoTile {
                        SectionHeader("Notifications", subtitle: "Receive an alert when a client submits a question.")
                        CompactLabel(title: "Permission", value: notificationStatus, icon: "bell.fill")
                        Button {
                            requestNotifications()
                        } label: {
                            Label("Enable Notifications", systemImage: "bell.badge.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    InfoTile {
                        SectionHeader("Care-line tools")
                        NavigationLink { TemplatesView() } label: {
                            settingsRow("Reply Templates", icon: "text.badge.checkmark")
                        }
                        NavigationLink { ReferenceView() } label: {
                            settingsRow("Emergency Reference", icon: "cross.case.fill")
                        }
                        Button { openURL(HelplineConfig.siteURL) } label: {
                            settingsRow("Open Client Website", icon: "safari.fill")
                        }
                    }
                }
                .padding(16)
            }
            .background(AppPalette.appBackground.ignoresSafeArea())
            .navigationTitle("Settings")
            .task { await updateNotificationStatus() }
        }
    }

    private func settingsField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .textFieldStyle(.roundedBorder)
    }

    private func settingsRow(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            Task { @MainActor in
                notificationStatus = granted ? "Enabled" : "Disabled in iPhone Settings"
                if granted { UIApplication.shared.registerForRemoteNotifications() }
            }
        }
    }

    private func updateNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationStatus = "Enabled"
        case .denied: notificationStatus = "Disabled in iPhone Settings"
        case .notDetermined: notificationStatus = "Not enabled yet"
        @unknown default: notificationStatus = "Unknown"
        }
    }
}

#Preview { SettingsView() }
