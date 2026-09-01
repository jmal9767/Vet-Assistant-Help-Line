import SwiftUI

struct AskQuestionView: View {
    @Environment(\.openURL) private var openURL

    private let speciesOptions = [
        "Dog", "Cat", "Bird", "Rabbit", "Reptile",
        "Small mammal (hamster, guinea pig, etc.)", "Other"
    ]
    private let categoryOptions = [
        "Feeding & nutrition (general)",
        "Grooming & general care",
        "Behavior & training basics",
        "Should I see a vet about this?",
        "Preparing for a vet visit",
        "New pet questions",
        "Other"
    ]

    @State private var name = ""
    @State private var species = "Dog"
    @State private var age = ""
    @State private var category = "Feeding & nutrition (general)"
    @State private var question = ""
    @State private var acknowledged = false
    @State private var showMailError = false

    private var canSend: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && acknowledged
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Questions are answered by email within \(HelplineConfig.responseWindow). For emergencies, use the Emergency tab instead.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About you and your pet") {
                    TextField("Your name", text: $name)
                    Picker("Pet species", selection: $species) {
                        ForEach(speciesOptions, id: \.self) { Text($0) }
                    }
                    TextField("Pet's age (e.g., 3 years)", text: $age)
                }

                Section("Your question") {
                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.self) { Text($0) }
                    }
                    TextEditor(text: $question)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if question.isEmpty {
                                Text("Describe what's going on, how long it's been happening, and anything you've already tried.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                Section {
                    Toggle(isOn: $acknowledged) {
                        Text("I understand this help line provides general educational information only — not veterinary medical advice, diagnosis, or treatment — and is not a substitute for care from a licensed veterinarian.")
                            .font(.footnote)
                    }
                }

                Section {
                    Button("Send my question") {
                        if let url = mailtoURL {
                            openURL(url) { accepted in
                                if !accepted { showMailError = true }
                            }
                        } else {
                            showMailError = true
                        }
                    }
                    .disabled(!canSend)
                }
            }
            .navigationTitle("Ask a Question")
            .alert("Couldn't open Mail", isPresented: $showMailError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No email app is set up on this device. You can email your question directly to \(HelplineConfig.email).")
            }
        }
    }

    private var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = HelplineConfig.email
        let body = """
        Name: \(name)
        Species: \(species)
        Age: \(age.isEmpty ? "Not given" : age)
        Category: \(category)
        Acknowledged educational-only disclaimer: Yes

        Question:
        \(question)
        """
        components.queryItems = [
            URLQueryItem(name: "subject", value: "[Help Line] \(category) — \(species)"),
            URLQueryItem(name: "body", value: body)
        ]
        return components.url
    }
}

#Preview {
    AskQuestionView()
}
