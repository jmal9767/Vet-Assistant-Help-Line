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
        "Parasite prevention basics (fleas, ticks, worms)",
        "Dental & oral care basics",
        "Senior pet care",
        "New pet questions",
        "Should I see a vet about this?",
        "Preparing for a vet visit",
        "Vet costs & payment help",
        "Other"
    ]
    private let sexOptions = [
        "Not specified",
        "Female, spayed",
        "Female, not spayed",
        "Male, neutered",
        "Male, not neutered",
        "Not sure"
    ]
    private let durationOptions = [
        "Just noticed today",
        "1–3 days",
        "About a week",
        "More than a week",
        "Ongoing / comes and goes",
        "Not applicable — general question"
    ]
    private let categoryHints: [String: String] = [
        "Feeding & nutrition (general)":
            "Helpful details: current food and daily amount, treats or supplements, and how their appetite has been lately.",
        "Grooming & general care":
            "Helpful details: coat type, how often you groom now, any mats, flaking, or odor, and the tools or products you use.",
        "Behavior & training basics":
            "Helpful details: when and where the behavior happens, what happens right before it, what you've tried, and any recent changes at home.",
        "Parasite prevention basics (fleas, ticks, worms)":
            "Helpful details: whether your pet goes outdoors, your general region, current prevention (no doses needed), and other pets in the home.",
        "Dental & oral care basics":
            "Helpful details: what their teeth and breath are like, whether they tolerate mouth handling, and when a vet last checked their teeth.",
        "Senior pet care":
            "Helpful details: age, any vet-diagnosed conditions, changes in mobility, eating, sleeping, or bathroom habits, and their last checkup.",
        "New pet questions":
            "Helpful details: where the pet came from, how long you've had them, other pets or kids at home, and whether they've seen a vet yet.",
        "Should I see a vet about this?":
            "Helpful details: exactly what you're seeing (photos help — attach them in Mail), when it started, whether it's improving or worsening, and eating/drinking/energy/bathroom changes.",
        "Preparing for a vet visit":
            "Helpful details: what the visit is for and what you most want to get out of the appointment.",
        "Vet costs & payment help":
            "Helpful details: your general area so I can find local options, and what kind of care you're trying to afford. If your pet is unwell now, please don't wait on me.",
        "Other":
            "Helpful details: anything about your pet's history that seems relevant, and what outcome you're hoping for."
    ]

    @State private var name = ""
    @State private var location = ""
    @State private var petName = ""
    @State private var species = "Dog"
    @State private var breed = ""
    @State private var age = ""
    @State private var sex = "Not specified"
    @State private var weight = ""
    @State private var category = "Feeding & nutrition (general)"
    @State private var duration = "Not applicable — general question"
    @State private var question = ""
    @State private var tried = ""
    @State private var changes = ""
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
                    Text("Questions are answered by email within \(HelplineConfig.responseWindow), always free of charge. For emergencies, use the Emergency tab instead. The more detail you give, the more useful my answer can be — optional fields can be skipped.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About you") {
                    TextField("Your name", text: $name)
                    TextField("City & state (optional)", text: $location)
                } footer: {
                    Text("Your general area helps me point you to local clinics and low-cost resources.")
                }

                Section("About your pet") {
                    TextField("Pet's name (optional)", text: $petName)
                    Picker("Pet species", selection: $species) {
                        ForEach(speciesOptions, id: \.self) { Text($0) }
                    }
                    TextField("Breed or type (optional)", text: $breed)
                    TextField("Pet's age (e.g., 3 years)", text: $age)
                    Picker("Sex & spay/neuter", selection: $sex) {
                        ForEach(sexOptions, id: \.self) { Text($0) }
                    }
                    TextField("Approx. weight (optional, e.g., 45 lb)", text: $weight)
                }

                Section("Your question") {
                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.self) { Text($0) }
                    }
                    Picker("How long has this been going on?", selection: $duration) {
                        ForEach(durationOptions, id: \.self) { Text($0) }
                    }
                    TextEditor(text: $question)
                        .frame(minHeight: 120)
                        .overlay(alignment: .topLeading) {
                            if question.isEmpty {
                                Text("Describe what's going on in as much detail as you can — what you're seeing, when it happens, and anything that makes it better or worse.")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                } footer: {
                    if let hint = categoryHints[category] {
                        Text(hint)
                    }
                }

                Section("Extra detail (optional)") {
                    TextField("What have you already tried?", text: $tried, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Changes in eating, drinking, energy, or bathroom habits?", text: $changes, axis: .vertical)
                        .lineLimit(2...4)
                } footer: {
                    Text("Photos help! After the email opens you can attach photos or a short video before sending.")
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

    private func orNotGiven(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Not given" : trimmed
    }

    private var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = HelplineConfig.email
        let body = """
        Name: \(orNotGiven(name))
        Location: \(orNotGiven(location))

        Pet name: \(orNotGiven(petName))
        Species: \(species)
        Breed/type: \(orNotGiven(breed))
        Age: \(orNotGiven(age))
        Sex & spay/neuter: \(sex == "Not specified" ? "Not given" : sex)
        Approx. weight: \(orNotGiven(weight))

        Category: \(category)
        How long: \(duration)
        Acknowledged educational-only disclaimer: Yes

        Question:
        \(orNotGiven(question))

        Already tried:
        \(orNotGiven(tried))

        Changes in eating/drinking/energy/bathroom habits:
        \(orNotGiven(changes))
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
