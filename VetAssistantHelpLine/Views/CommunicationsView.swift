import SwiftUI

struct CommunicationsView: View {
    @Environment(QuestionStore.self) private var store
    @State private var selectedChannel: ChannelFilter = .all

    private enum ChannelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case website = "Website"
        case sms = "SMS"
        case email = "Email"
        case phone = "Phone"

        var id: String { rawValue }
    }

    private var filteredQuestions: [ClientQuestion] {
        let sorted = store.questions.sorted { $0.submittedAt > $1.submittedAt }
        guard selectedChannel != .all else { return sorted }
        return sorted.filter { $0.sourceChannel.localizedCaseInsensitiveContains(selectedChannel.rawValue) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HeroPanel(
                            icon: "bubble.left.and.bubble.right.fill",
                            title: "Communications",
                            subtitle: "Client texts, emails, and masked call requests belong here once your relay provider is connected."
                        ) {
                            HStack(spacing: 10) {
                                MetricPill(title: "Open", value: "\(openCount)", icon: "bubble.left.fill", tint: AppPalette.warmGold)
                                MetricPill(title: "Channels", value: "SMS / Email / Phone", icon: "phone.connection.fill", tint: AppPalette.brand)
                            }
                        }

                        Picker("Channel", selection: $selectedChannel) {
                            ForEach(ChannelFilter.allCases) { channel in
                                Text(channel.rawValue).tag(channel)
                            }
                        }
                        .pickerStyle(.segmented)

                        if filteredQuestions.isEmpty {
                            ContentUnavailableView(
                                "No conversations yet",
                                systemImage: "bubble.left.and.bubble.right",
                                description: Text("Messages from the masked text/email/call relay will appear here.")
                            )
                            .padding(.top, 24)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredQuestions) { question in
                                    NavigationLink {
                                        QuestionDetailView(question: question)
                                    } label: {
                                        CommunicationRow(question: question)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await store.refresh() }
            }
            .navigationTitle("Communications")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }
            }
            .task { await store.refresh() }
        }
    }

    private var openCount: Int {
        store.questions.filter { $0.conversationStatus != "Closed" }.count
    }
}

private struct CommunicationRow: View {
    let question: ClientQuestion

    var body: some View {
        InfoTile {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(question.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 10)
                        Text(question.sourceChannel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(tint)
                    }

                    Text(question.conversationStatus)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(question.question)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var iconName: String {
        switch question.sourceChannel.lowercased() {
        case let value where value.contains("sms"):
            "message.fill"
        case let value where value.contains("email"):
            "envelope.fill"
        case let value where value.contains("phone"):
            "phone.fill"
        default:
            "globe"
        }
    }

    private var tint: Color {
        switch question.sourceChannel.lowercased() {
        case let value where value.contains("sms"):
            AppPalette.clinicGreen
        case let value where value.contains("email"):
            AppPalette.brand
        case let value where value.contains("phone"):
            AppPalette.warmGold
        default:
            AppPalette.brand
        }
    }
}

#Preview {
    CommunicationsView()
        .environment(QuestionStore())
}
