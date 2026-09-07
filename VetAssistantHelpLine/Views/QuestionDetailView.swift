import SwiftUI

struct QuestionDetailView: View {
    @Environment(QuestionStore.self) private var store
    @Environment(\.openURL) private var openURL

    let question: ClientQuestion
    @State private var showMailError = false

    var body: some View {
        List {
            Section("From") {
                LabeledContent("Name", value: question.name)
                LabeledContent("Email", value: question.email.isEmpty ? "Not given" : question.email)
                LabeledContent("Received") {
                    Text(question.submittedAt, format: .dateTime.month().day().hour().minute())
                }
            }

            Section("Pet") {
                LabeledContent("Species", value: question.species)
                LabeledContent("Age", value: question.age)
                LabeledContent("Category", value: question.category)
            }

            Section("Question") {
                Text(question.question)
                    .textSelection(.enabled)
            }

            Section {
                Button {
                    if let url = replyURL {
                        openURL(url) { accepted in
                            if !accepted { showMailError = true }
                        }
                    } else {
                        showMailError = true
                    }
                } label: {
                    Label("Reply by email", systemImage: "arrowshape.turn.up.left.fill")
                }
                .disabled(question.email.isEmpty)

                if question.status == .new {
                    Button {
                        Task { await store.setStatus(.answered, for: question) }
                    } label: {
                        Label("Mark as answered", systemImage: "checkmark.circle.fill")
                    }
                } else {
                    Button {
                        Task { await store.setStatus(.new, for: question) }
                    } label: {
                        Label("Mark as new", systemImage: "arrow.uturn.backward.circle")
                    }
                }
            } footer: {
                if question.email.isEmpty {
                    Text("This submission didn't include an email address, so there's no way to reply.")
                }
            }
        }
        .navigationTitle(question.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Couldn't open Mail", isPresented: $showMailError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No email app is set up on this device.")
        }
    }

    private var replyURL: URL? {
        guard !question.email.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = question.email
        let body = """
        Hi \(question.name),

        Thanks for reaching out to the help line about your \(question.species.lowercased()).



        \(HelplineConfig.disclaimerFooter)
        """
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Re: Your pet-care question — \(question.category)"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}
