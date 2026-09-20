import SwiftUI

private enum ServiceOffer: String, CaseIterable, Identifiable {
    case quickEmail = "Quick email response · $10"
    case quickText = "Quick text response · $10"
    case writtenEmail = "Written email support · $20"
    case writtenText = "Written text support · $20"
    case phoneConversation = "Phone conversation · $35"
    case textConversation = "Live-text conversation · $35"
    case complimentaryEmail = "Complimentary email · $0"
    case complimentaryText = "Complimentary text · $0"
    case complimentaryPhone = "Complimentary phone call · $0"
    case referral = "Refer to veterinarian · $0"

    var id: String { rawValue }
    var amount: String {
        switch self {
        case .quickEmail, .quickText: "$10"
        case .writtenEmail, .writtenText: "$20"
        case .phoneConversation, .textConversation: "$35"
        default: "$0"
        }
    }
    var replyMethod: String {
        switch self {
        case .quickEmail, .writtenEmail, .complimentaryEmail, .referral: "Email"
        case .quickText, .writtenText, .textConversation, .complimentaryText: "Text message"
        case .phoneConversation, .complimentaryPhone: "Phone call"
        }
    }
    var requiresPayment: Bool { amount != "$0" }
    var needsPhone: Bool { replyMethod != "Email" }
    var paymentStatus: String {
        switch self {
        case .referral: "Referred — no charge"
        case .complimentaryEmail, .complimentaryText, .complimentaryPhone: "Complimentary"
        default: "Payment requested"
        }
    }
}

private enum PaymentChoice: String, CaseIterable, Identifiable {
    case paypal = "PayPal or Apple Pay"
    case cashApp = "Cash App"

    var id: String { rawValue }
}

struct QuestionDetailView: View {
    @Environment(QuestionStore.self) private var store
    @Environment(\.openURL) private var openURL
    @AppStorage("setup.helplineEmail") private var helplineEmail = ""
    @AppStorage("setup.cashAppLink") private var cashAppLink = ""

    let question: ClientQuestion
    @State private var showMailError = false
    @State private var selectedOffer: ServiceOffer = .writtenEmail
    @State private var selectedPayment: PaymentChoice = .paypal
    @State private var showArchiveConfirmation = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                questionCard
                attachmentsCard
                petCard
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
            Text("No email app is set up on this device.")
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
            Text("This removes the CloudKit record and cannot be undone. Uploaded files expire separately after 30 days.")
        }
        .onAppear {
            selectedOffer = defaultOffer
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
            SectionHeader("Reply", subtitle: question.email.isEmpty ? "No email address was included with this submission." : "Confirm payment, reply from your public care-line account, then mark the case answered.")

            CompactLabel(
                title: "Client-facing sender",
                value: publicReplyAddressText,
                icon: "eye.slash.fill"
            )

            VStack(spacing: 10) {
                if let url = phoneCallURL, question.preferredReply == "Phone call" {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Call Client", systemImage: "phone.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.clinicGreen)
                }

                if let url = textReplyURL {
                    Button {
                        openURL(url)
                    } label: {
                        Label("Reply by Text", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppPalette.clinicGreen)
                }

                Button {
                    if let url = replyURL {
                        openURL(url) { accepted in
                            if !accepted { showMailError = true }
                        }
                    } else {
                        showMailError = true
                    }
                } label: {
                    Label("Reply by Email From Public Mailbox", systemImage: "envelope.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(question.email.isEmpty || publicHelpLineEmail.isEmpty)

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
            SectionHeader("Service and payment", subtitle: "Choose the service after reviewing the question. PayPal and Apple Pay confirm automatically; verify Cash App before marking it paid.")

            HStack(spacing: 10) {
                MetricPill(title: "Payment", value: question.paymentStatus, icon: "creditcard.fill", tint: paymentTint)
                MetricPill(title: "Amount", value: question.paymentAmount, icon: "dollarsign.circle.fill", tint: AppPalette.clinicGreen)
            }
            CompactLabel(title: "Signed consent", value: signedConsentText, icon: "signature")

            Picker("Service offer", selection: $selectedOffer) {
                ForEach(ServiceOffer.allCases) { offer in
                    Text(offer.rawValue).tag(offer)
                }
            }
            .pickerStyle(.menu)

            if selectedOffer.requiresPayment {
                Picker("Payment option", selection: $selectedPayment) {
                    ForEach(PaymentChoice.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)
            }

            if selectedOffer.requiresPayment {
                CompactLabel(
                    title: selectedPayment.rawValue,
                    value: selectedPaymentLink.isEmpty ? "Add your Cash App for Business link in Settings before sending the offer." : selectedPaymentLink,
                    icon: "link.circle.fill"
                )
            } else {
                CompactLabel(title: "Charge", value: "No payment required", icon: "gift.fill")
            }

            Button {
                Task {
                    await store.applyServiceOffer(
                        name: selectedOffer.rawValue,
                        replyMethod: selectedOffer.replyMethod,
                        amount: selectedOffer.amount,
                        paymentMethod: selectedPayment.rawValue,
                        paymentLink: selectedOffer.requiresPayment ? selectedPaymentLink : "",
                        paymentStatus: selectedOffer.paymentStatus,
                        for: question
                    )
                    if let offerMessageURL { openURL(offerMessageURL) }
                }
            } label: {
                Label("Save Decision + Prepare Client Message", systemImage: "paperplane.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(selectedOffer.requiresPayment ? AppPalette.brand : AppPalette.clinicGreen)
            .disabled((selectedOffer.requiresPayment && selectedPaymentLink.isEmpty) || (selectedOffer.needsPhone && question.phone == nil))

            if let link = question.paymentLink, !link.isEmpty, let paymentURL = URL(string: link) {
                Link(destination: paymentURL) {
                    Label("Open Saved Payment Link", systemImage: "safari.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if (question.paymentStatus == "Payment requested" && question.paymentMethod == PaymentChoice.cashApp.rawValue) || question.paymentStatus == "Paid" {
                HStack(spacing: 10) {
                    Button {
                        Task { await store.updatePayment(status: "Paid", amount: question.paymentAmount, link: question.paymentLink, for: question) }
                    } label: {
                        Label("Mark Paid", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(AppPalette.clinicGreen)

                    Button {
                        Task { await store.updatePayment(status: "Refunded", amount: question.paymentAmount, link: question.paymentLink, for: question) }
                    } label: {
                        Label("Refunded", systemImage: "arrow.uturn.backward.circle.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var questionCard: some View {
        InfoTile {
            SectionHeader("Client Concern", subtitle: "Review this before choosing the service and price.")
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
            SectionHeader("Pet")
            CompactLabel(title: "Name", value: question.petName, icon: "heart.fill")
            CompactLabel(title: "Species", value: question.species, icon: "pawprint.fill")
            CompactLabel(title: "Age", value: question.age, icon: "birthday.cake.fill")
            CompactLabel(title: "Category", value: question.category, icon: "tag.fill")
            CompactLabel(title: "Client urgency", value: question.urgency, icon: "exclamationmark.triangle.fill")
        }
    }

    private var petDisplayName: String {
        question.petName == "Pet" ? "a \(question.species.lowercased())" : "\(question.petName), a \(question.species.lowercased())"
    }

    private var paymentTint: Color {
        switch question.paymentStatus {
        case "Paid": AppPalette.clinicGreen
        case "Complimentary": AppPalette.clinicGreen
        case "Refunded": AppPalette.brand
        case "Payment requested": AppPalette.warmGold
        case "Referred — no charge": AppPalette.brand
        case "Reviewing": AppPalette.warmGold
        default: AppPalette.danger
        }
    }

    private var defaultOffer: ServiceOffer {
        switch question.preferredReply {
        case "Text message": .quickText
        case "Phone call": .phoneConversation
        default: .quickEmail
        }
    }

    private var selectedPaymentLink: String {
        switch selectedPayment {
        case .paypal:
            var components = URLComponents(url: HelplineConfig.checkoutBaseURL.appending(path: "pay"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "question", value: question.id.recordName)]
            return components?.url?.absoluteString ?? ""
        case .cashApp:
            return cashAppLink.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var offerMessageURL: URL? {
        let paymentSentence = selectedOffer.requiresPayment
            ? "The price is \(selectedOffer.amount). If you would like to continue, pay with \(selectedPayment.rawValue) here: \(selectedPaymentLink). " + (selectedPayment == .cashApp ? "Please tell me after you send it so I can confirm it." : "My app will confirm the payment automatically.")
            : selectedOffer == .referral
                ? "There is no charge. This request needs a licensed veterinarian, so please contact your veterinarian or an emergency hospital if the concern may be urgent."
                : "I can provide this service at no charge. No payment is required."
        let message = "Hi \(question.name), I reviewed your request about \(petDisplayName). I can offer: \(selectedOffer.rawValue). \(paymentSentence)"

        if selectedOffer.replyMethod != "Email", let phone = question.phone {
            var components = URLComponents()
            components.scheme = "sms"
            components.path = phone.filter { $0.isNumber || $0 == "+" }
            components.queryItems = [URLQueryItem(name: "body", value: message)]
            return components.url
        }
        guard !question.email.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = question.email
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Your Paws & Whiskers Care Line request"),
            URLQueryItem(name: "body", value: message)
        ]
        return components.url
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
        guard !publicHelpLineEmail.isEmpty else {
            return "Set a public care-line email in Settings before replying. Mail cannot hide a personal sender by itself."
        }
        return "\(publicHelpLineEmail) should be the only email address clients see."
    }

    private var publicHelpLineEmail: String {
        helplineEmail.trimmingCharacters(in: .whitespacesAndNewlines)
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
