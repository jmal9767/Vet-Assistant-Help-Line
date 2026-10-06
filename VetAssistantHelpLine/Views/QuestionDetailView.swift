import SwiftUI
import MessageUI

struct QuestionDetailView: View {
    @Environment(QuestionStore.self) private var store
    @Environment(\.openURL) private var openURL

    let question: ClientQuestion
    @State private var showMailError = false
    @State private var emailDraft: BusinessEmailDraft?
    @State private var showArchiveConfirmation = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                questionCard
                currentConditionCard
                petCard
                attachmentsCard
                clientCard
                paymentCard
                replyActions
            }
            .padding(16)
        }
        .background(AppPalette.appBackground.ignoresSafeArea())
        .navigationTitle(question.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if question.status == .archived {
                        showDeleteConfirmation = true
                    } else {
                        showArchiveConfirmation = true
                    }
                } label: {
                    Label(question.status == .archived ? "Delete Permanently" : "Archive", systemImage: question.status == .archived ? "trash" : "archivebox")
                }
            }
        }
        .alert("Couldn't open Mail", isPresented: $showMailError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Set up info@bayareaapps.com in iPhone Mail before replying. No message has been sent.")
        }
        .sheet(item: $emailDraft) { draft in
            BusinessMailComposer(draft: draft) { failed in
                emailDraft = nil
                showMailError = failed
            }
        }
        .confirmationDialog("Archive this question?", isPresented: $showArchiveConfirmation) {
            Button("Archive", role: .destructive) {
                Task { await store.setStatus(.archived, for: question) }
            }
            Button("Cancel", role: .cancel) { }
        }
        .confirmationDialog("Permanently delete this question?", isPresented: $showDeleteConfirmation) {
            Button("Delete Permanently", role: .destructive) {
                Task { await store.deletePermanently(question) }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes the CloudKit record and cannot be undone. Uploaded files remain separate and follow the file retention schedule.")
        }
    }

    private var header: some View {
        HeroPanel(
            icon: question.status == .new ? "exclamationmark.bubble.fill" : "checkmark.message.fill",
            title: question.category,
            subtitle: "Submitted by \(question.name) about \(petDisplayName).",
            tint: question.status == .new ? AppPalette.warmGold : AppPalette.clinicGreen
        ) {
            HStack(spacing: 10) {
                MetricPill(title: "Status", value: question.status == .new ? "New" : "Answered", icon: "circle.fill", tint: question.status == .new ? AppPalette.warmGold : AppPalette.clinicGreen)
                MetricPill(title: "Reply", value: question.preferredReply, icon: "bubble.left.and.text.bubble.right.fill", tint: AppPalette.brand)
            }
            HStack(spacing: 10) {
                MetricPill(title: "Channel", value: question.sourceChannel, icon: "phone.connection.fill", tint: AppPalette.brand)
                MetricPill(title: "Thread", value: question.conversationStatus, icon: "bubble.left.fill", tint: AppPalette.warmGold)
            }
            MetricPill(title: "Service", value: question.requestedService, icon: "creditcard.fill", tint: AppPalette.clinicGreen)
            MetricPill(title: "Client urgency", value: question.urgency, icon: "exclamationmark.triangle.fill", tint: question.urgency.contains("emergency") ? AppPalette.danger : AppPalette.warmGold)
        }
    }

    private var replyActions: some View {
        InfoTile {
            SectionHeader("Reply", subtitle: question.email.isEmpty ? "No email address was included with this submission." : "Answer directly in your private conversation. Phone-call requests keep a separate call option.")

            CompactLabel(
                title: "Client-facing sender",
                value: question.conversationToken == nil ? publicReplyAddressText : "Paws & Whiskers Care Line",
                icon: "eye.slash.fill"
            )

            VStack(spacing: 10) {
                NavigationLink { CareLineConversationView(question: question) } label: { Label("Reply in Care Line", systemImage: "bubble.left.and.bubble.right.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)

                if let url = phoneCallURL, question.preferredReply == "Phone call" {
                    Text("Calls use your phone carrier. Confirm your caller-ID privacy before calling; this app does not mask your number.").font(.footnote)
                    Button {
                        openURL(url)
                    } label: {
                        Label("Call Client", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.clinicGreen)
                }

                if question.conversationToken == nil {
                    Button { prepareEmail(replyURL) } label: { Label("Email an Older Request", systemImage: "envelope.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered).disabled(question.email.isEmpty)
                }
                Button {
                    Task { await store.setStatus(question.status == .new ? .answered : .new, for: question) }
                } label: {
                    Label(question.status == .new ? "Mark as Answered" : "Move Back to New", systemImage: question.status == .new ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var paymentCard: some View {
        InfoTile {
            SectionHeader("Service and payment", subtitle: question.paymentAmount == "$0" ? "Free Community Support — no payment required." : "Payment and refund status update automatically through PayPal or Apple Pay.")

            HStack(spacing: 10) {
                MetricPill(title: "Payment", value: question.paymentStatus, icon: "creditcard.fill", tint: paymentTint)
                MetricPill(title: "Amount", value: question.paymentAmount == "$0" ? "Free" : question.paymentAmount, icon: "dollarsign.circle.fill", tint: AppPalette.clinicGreen)
            }
            CompactLabel(title: "Signed consent", value: signedConsentText, icon: "signature")

            CompactLabel(title: "Selected service", value: question.requestedService, icon: "checkmark.circle.fill")

        }
    }

    private var questionCard: some View {
        InfoTile {
            SectionHeader("Client Concern", subtitle: "Review the client’s question and selected service.")
            Text(question.question.isEmpty ? "No concern was included." : question.question)
                .font(.body)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private var attachmentsCard: some View {
        if let attachmentSummary = question.attachmentSummary {
            InfoTile {
                SectionHeader("Private Files", subtitle: "Download links expire after 30 days.")
                ForEach(question.attachments) { attachment in
                    if let url = attachment.url {
                        Link(destination: url) {
                            Label(attachment.name, systemImage: "paperclip.circle.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text(attachment.detail).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(attachment.detail).font(.subheadline).textSelection(.enabled)
                    }
                }
                if question.attachments.isEmpty {
                    Text(attachmentSummary).font(.subheadline).textSelection(.enabled)
                }
            }
        }
    }

    private var clientCard: some View {
        InfoTile {
            SectionHeader("Client")
            CompactLabel(title: "Name", value: question.name, icon: "person.fill")
            CompactLabel(title: "Email", value: question.email.isEmpty ? "Not given" : question.email, icon: "envelope.fill")
            CompactLabel(title: "Preferred reply", value: question.preferredReply, icon: "bubble.left.and.text.bubble.right.fill")
            CompactLabel(title: "Requested service", value: question.requestedService, icon: "creditcard.fill")
            CompactLabel(title: "Preferred payment", value: question.paymentMethod, icon: "wallet.pass.fill")
            if let phone = question.phone {
                CompactLabel(title: "Phone", value: phone, icon: "phone.fill")
            }
            CompactLabel(title: "Received", value: fullDate, icon: "calendar")
        }
    }

    private var petCard: some View {
        InfoTile {
            SectionHeader("Dog or cat profile")
            CompactLabel(title: "Name", value: question.petName, icon: "heart.fill")
            CompactLabel(title: "Species", value: question.species, icon: "pawprint.fill")
            CompactLabel(title: "Breed or mix", value: question.breed, icon: "pawprint.circle.fill")
            CompactLabel(title: "Age", value: question.age, icon: "birthday.cake.fill")
            CompactLabel(title: "Sex", value: question.sex, icon: "person.crop.circle")
            CompactLabel(title: "Spayed / neutered", value: question.reproductiveStatus, icon: "checkmark.seal.fill")
            CompactLabel(title: "Weight", value: question.weight, icon: "scalemass.fill")
            CompactLabel(title: "Category", value: question.category, icon: "tag.fill")
            CompactLabel(title: "Client urgency", value: question.urgency, icon: "exclamationmark.triangle.fill")
        }
    }

    private var currentConditionCard: some View {
        InfoTile {
            SectionHeader("Current condition", subtitle: "Review these details before replying.")
            CompactLabel(title: "Started", value: question.symptomOnset, icon: "clock.fill")
            CompactLabel(title: "Trend", value: question.symptomTrend, icon: "chart.line.uptrend.xyaxis")
            CompactLabel(title: "Eating", value: question.appetite, icon: "fork.knife")
            CompactLabel(title: "Drinking", value: question.drinking, icon: "drop.fill")
            CompactLabel(title: "Urination", value: question.urination, icon: "toilet.fill")
            CompactLabel(title: "Stool", value: question.stool, icon: "list.bullet.clipboard.fill")
            CompactLabel(title: "Energy / behavior", value: question.energy, icon: "bolt.heart.fill")
            CompactLabel(title: "Vomiting", value: question.vomiting, icon: "waveform.path.ecg")
            Divider()
            CompactLabel(title: "Medical history", value: question.medicalHistory, icon: "cross.case.fill")
            CompactLabel(title: "Medications / supplements", value: question.currentMedications, icon: "pills.fill")
            CompactLabel(title: "Already tried / vet contacted", value: question.actionsTaken, icon: "checklist")
        }
    }

    private var petDisplayName: String {
        question.petName == "Pet" ? "a \(question.species.lowercased())" : "\(question.petName), a \(question.species.lowercased())"
    }

    private var paymentTint: Color {
        switch question.paymentStatus {
        case "Paid": AppPalette.clinicGreen
        case "Refunded", "Partially refunded": AppPalette.brand
        case "Payment requested": AppPalette.warmGold
        case "Referred — no charge": AppPalette.brand
        case "Reviewing": AppPalette.warmGold
        default: AppPalette.danger
        }
    }

    private var signedConsentText: String {
        guard let name = question.signedConsentName else {
            return "Not signed"
        }
        if let signedAt = question.signedConsentAt {
            return "Signed by \(name) on \(signedAt)"
        }
        return "Signed by \(name)"
    }

    private var publicReplyAddressText: String {
        return "Before sending, check From is \(publicHelpLineEmail). If it shows a personal address, cancel and set up the business mailbox in iPhone Mail."
    }

    private var publicHelpLineEmail: String {
        HelplineConfig.replyEmail
    }

    private func prepareEmail(_ url: URL?) {
        guard MFMailComposeViewController.canSendMail(), let url,
              let draft = BusinessEmailDraft(mailto: url) else {
            showMailError = true
            return
        }
        emailDraft = draft
    }

    private var fullDate: String {
        question.submittedAt.formatted(.dateTime.month().day().year().hour().minute())
    }

    private var textReplyURL: URL? {
        guard let phone = question.phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        let greeting = "Hi \(question.name), this is the Paws & Whiskers Care Line replying about \(petDisplayName). "
        var components = URLComponents()
        components.scheme = "sms"
        components.path = digits
        components.queryItems = [URLQueryItem(name: "body", value: greeting)]
        return components.url
    }

    private var phoneCallURL: URL? {
        guard let phone = question.phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    private var replyURL: URL? {
        guard !question.email.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = question.email
        let body = """
        Hi \(question.name),

        Thanks for reaching out to the Paws & Whiskers Care Line about \(petDisplayName).


        \(HelplineConfig.disclaimerFooter)
        """
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Re: Your dog-or-cat care question - \(question.category)"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}
