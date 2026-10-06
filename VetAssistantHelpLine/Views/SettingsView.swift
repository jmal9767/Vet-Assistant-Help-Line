import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(QuestionStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var notificationStatus = "Checking…"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    InfoTile {
                        SectionHeader("Contact", subtitle: "These are the only details you may need to change.")
                        CompactLabel(title: "Business support email", value: HelplineConfig.replyEmail, icon: "envelope.fill")
                        Text("New questions use private conversations: answer with Reply in Care Line. This business mailbox remains available for support and older email requests. Before sending email, check the From address and signature.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    InfoTile {
                        SectionHeader("Notifications", subtitle: "Receive an alert when a client submits a question.")
                        CompactLabel(title: "Permission", value: notificationStatus, icon: "bell.fill")
                        CompactLabel(title: "Inbox alerts", value: store.notificationSetupComplete ? "Connected" : "Not connected yet", icon: "tray.fill")
                        if let message = store.notificationSetupError {
                            Text(message).font(.footnote).foregroundStyle(AppPalette.danger)
                            Button("Retry Inbox Alerts") { Task { await store.ensureSubscription() } }
                        }
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
            .task {
                await updateNotificationStatus()
                await store.ensureSubscription()
            }
        }
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

#Preview { SettingsView().environment(QuestionStore()) }
