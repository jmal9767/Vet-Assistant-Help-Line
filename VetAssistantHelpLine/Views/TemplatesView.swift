import SwiftUI

struct TemplatesView: View {
    private struct Template: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    private let templates: [Template] = [
        Template(
            title: "Greeting",
            text: """
            Hi! Thanks for reaching out to the help line. Here's some general \
            information that may help:
            """
        ),
        Template(
            title: "Recommend seeing a vet",
            text: """
            Based on what you've described, this is something a licensed \
            veterinarian should take a look at. I'd recommend scheduling an \
            appointment soon — and if things get worse before then, don't wait: \
            contact an emergency clinic.
            """
        ),
        Template(
            title: "Emergency redirect",
            text: """
            What you're describing could be an emergency. Please contact an \
            emergency veterinary clinic right away rather than waiting for a \
            reply here. You can find one near you at https://vetlocator.com, and \
            ASPCA Poison Control is available 24/7 at (888) 426-4435.
            """
        ),
        Template(
            title: "Out of scope (diagnosis / medication)",
            text: """
            I'm sorry, but as a veterinary assistant I can't diagnose conditions \
            or recommend medications or doses — that has to come from a licensed \
            veterinarian who can examine your pet. What I can do is help you \
            prepare questions for that visit.
            """
        ),
        Template(
            title: "Disclaimer footer",
            text: HelplineConfig.disclaimerFooter
        )
    ]

    @State private var copiedTemplateID: UUID?

    var body: some View {
        NavigationStack {
            List(templates) { template in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(template.title)
                            .font(.headline)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = template.text
                            copiedTemplateID = template.id
                        } label: {
                            if copiedTemplateID == template.id {
                                Label("Copied", systemImage: "checkmark")
                            } else {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                    Text(template.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            .navigationTitle("Reply Templates")
        }
    }
}

#Preview {
    TemplatesView()
}
