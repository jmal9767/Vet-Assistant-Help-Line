import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @Environment(\.openURL) private var openURL
    @AppStorage("setup.helplineEmail") private var helplineEmail = ""
    @AppStorage("setup.checkoutBaseURL") private var checkoutBaseURL = "https://vet-helpline-development.dkjmmz6whh.workers.dev"
    @AppStorage("setup.cashAppLink") private var cashAppLink = ""
    @State private var notificationStatus = "Checking…"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HeroPanel(icon: "ellipsis.circle.fill", title: "More", subtitle: "Your reply settings, payment links, templates, references, and policies.") {
                        HStack(spacing: 10) {
                            MetricPill(title: "Questions", value: "CloudKit", icon: "icloud.fill", tint: AppPalette.clinicGreen)
                            MetricPill(title: "Files", value: "Private", icon: "lock.fill", tint: AppPalette.brand)
                        }
                    }

                    InfoTile {
                        SectionHeader("Reply email", subtitle: "Use a help-line address that clients are allowed to see.")
                        TextField("Public help-line email", text: $helplineEmail)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
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
                        SectionHeader("Payments", subtitle: "PayPal and Apple Pay confirm automatically. Confirm Cash App payments yourself after they arrive.")
                        settingsField("Secure checkout address", text: $checkoutBaseURL)
                        settingsField("Cash App for Business link", text: $cashAppLink)
                        Button { openURL(URL(string: "https://developer.paypal.com/dashboard/applications/live")!) } label: {
                            settingsRow("Open PayPal Business Setup", icon: "safari.fill")
                        }
                        Button { openURL(URL(string: "https://cash.app/account/settings")!) } label: {
                            settingsRow("Open Cash App Settings", icon: "dollarsign.circle.fill")
                        }
                    }

                    InfoTile {
                        SectionHeader("Tools")
                        NavigationLink { TemplatesView() } label: {
                            settingsRow("Reply Templates", icon: "text.badge.checkmark")
                        }
                        NavigationLink { ReferenceView() } label: {
                            settingsRow("Emergency Reference", icon: "cross.case.fill")
                        }
                    }

                    InfoTile {
                        SectionHeader("Client pages")
                        Button { openURL(HelplineConfig.siteURL) } label: {
                            settingsRow("Open Client Website", icon: "safari.fill")
                        }
                        Button { openURL(URL(string: "https://jmal9767.github.io/Vet-Assistant-Help-Line/privacy.html")!) } label: {
                            settingsRow("Privacy Notice", icon: "hand.raised.fill")
                        }
                        Button { openURL(URL(string: "https://jmal9767.github.io/Vet-Assistant-Help-Line/terms.html")!) } label: {
                            settingsRow("Service and Refund Terms", icon: "doc.text.fill")
                        }
                    }
                }
                .padding(16)
            }
            .background(AppPalette.appBackground.ignoresSafeArea())
            .navigationTitle("More")
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
