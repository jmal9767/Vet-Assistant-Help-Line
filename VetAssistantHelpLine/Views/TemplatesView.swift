import SwiftUI

struct TemplatesView: View {
    fileprivate struct Template: Identifiable {
        let id = UUID()
        let title: String
        let intent: String
        let icon: String
        let tint: Color
        let text: String
    }

    private let templates: [Template] = [
        Template(
            title: "Greeting",
            intent: "Start an educational answer after the service decision is clear.",
            icon: "hand.wave.fill",
            tint: AppPalette.brand,
            text: """
            Hi [name], thanks for reaching out to the Vet Assistant Help Line. \
            I reviewed your question about [pet name / your pet], and here's \
            the general pet-care guidance I can offer:
            """
        ),
        Template(
            title: "Complimentary Service",
            intent: "Tell the client you are waiving the charge.",
            icon: "gift.fill",
            tint: AppPalette.clinicGreen,
            text: """
            Hi [name], I reviewed your question about [pet name]. I'm happy to \
            provide this [email / text / phone] response at no charge. There is \
            no payment required.
            """
        ),
        Template(
            title: "Confirm Price",
            intent: "Use before taking payment or starting a paid answer.",
            icon: "creditcard.fill",
            tint: AppPalette.clinicGreen,
            text: """
            Hi [name], thanks for sending this in. Based on what you described, \
            I can provide this by [email / text / phone]. Based on the question and \
            estimated time, the price is [amount from $5 to $40]. If that works \
            for you, I'll send the payment link before I begin.
            """
        ),
        Template(
            title: "Send PayPal Link",
            intent: "Use when the client prefers PayPal.",
            icon: "link.circle.fill",
            tint: AppPalette.brand,
            text: """
            Hi [name], the total for [service] is [price]. Here is the PayPal \
            payment link: [PayPal link]\n\nOnce payment is complete, I'll send \
            the answer by [email / text / phone] in the selected time frame.
            """
        ),
        Template(
            title: "Send Cash App Link",
            intent: "Use when the client prefers Cash App.",
            icon: "dollarsign.circle.fill",
            tint: AppPalette.clinicGreen,
            text: """
            Hi [name], the total for [service] is [price]. Here is the Cash App \
            payment link: [Cash App link]\n\nOnce payment is complete, I'll send \
            the answer by [email / text / phone] in the selected time frame.
            """
        ),
        Template(
            title: "Received + Next Step",
            intent: "Reassure a client after intake and explain what happens next.",
            icon: "checkmark.message.fill",
            tint: AppPalette.clinicGreen,
            text: """
            Hi [name], I received your question about [pet name]. I'll review \
            the details and any files you sent, then let you know whether I can \
            provide a complimentary response or offer a price from $5 to $40. \
            Nothing is charged automatically.
            """
        ),
        Template(
            title: "Request Files",
            intent: "Ask for photos, videos, records, or labels when context is missing.",
            icon: "paperclip",
            tint: AppPalette.brand,
            text: """
            If you have them, please send any helpful files before I answer: \
            photos, videos, discharge notes, lab work, medication labels, food \
            labels, screenshots, or other documents. Files help with context, \
            but they still don't replace an exam by a licensed veterinarian.
            """
        ),
        Template(
            title: "Recommend Seeing a Vet",
            intent: "Use when the pet should be examined soon.",
            icon: "stethoscope",
            tint: AppPalette.clinicGreen,
            text: """
            Based on what you've described, this is something a licensed \
            veterinarian should take a look at. I'd recommend scheduling an \
            appointment soon - and if things get worse before then, don't wait: \
            contact an emergency clinic.
            """
        ),
        Template(
            title: "Emergency Redirect",
            intent: "Send immediately when red flags are present.",
            icon: "exclamationmark.triangle.fill",
            tint: AppPalette.danger,
            text: """
            What you're describing could be an emergency. Please contact an \
            emergency veterinary clinic right away rather than waiting for a \
            reply here. You can find one near you at https://vetlocator.com, and \
            ASPCA Poison Control is available 24/7 at (888) 426-4435.
            """
        ),
        Template(
            title: "Out of Scope",
            intent: "For diagnosis, medication, and dosage questions.",
            icon: "lock.shield.fill",
            tint: AppPalette.warmGold,
            text: """
            I'm sorry, but as a veterinary assistant I can't diagnose conditions \
            or recommend medications or doses - that has to come from a licensed \
            veterinarian who can examine your pet. What I can do is help you \
            prepare questions for that visit.
            """
        ),
        Template(
            title: "Disclaimer Footer",
            intent: "Add this to the bottom of client replies.",
            icon: "doc.text.fill",
            tint: AppPalette.brand,
            text: HelplineConfig.disclaimerFooter
        )
    ]

    @State private var copiedTemplateID: UUID?
    @State private var searchText = ""

    private var filteredTemplates: [Template] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return templates
        }
        return templates.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
            || $0.intent.localizedCaseInsensitiveContains(searchText)
            || $0.text.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HeroPanel(
                            icon: "text.badge.checkmark",
                            title: "Reply templates",
                            subtitle: "Copy consistent language for routine replies, emergency redirects, and scope boundaries."
                        )

                        if filteredTemplates.isEmpty {
                            ContentUnavailableView(
                                "No matching templates",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different search term.")
                            )
                            .padding(.top, 24)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredTemplates) { template in
                                    TemplateCard(
                                        template: template,
                                        isCopied: copiedTemplateID == template.id
                                    ) {
                                        UIPasteboard.general.string = template.text
                                        copiedTemplateID = template.id
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Templates")
            .searchable(text: $searchText, prompt: "Search replies")
        }
    }
}

private struct TemplateCard: View {
    let template: TemplatesView.Template
    let isCopied: Bool
    let copy: () -> Void

    var body: some View {
        InfoTile {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: template.icon)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(template.tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.headline)
                    Text(template.intent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button(action: copy) {
                    Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
            }

            Text(template.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineSpacing(2)
                .textSelection(.enabled)
        }
    }
}

#Preview {
    TemplatesView()
}
