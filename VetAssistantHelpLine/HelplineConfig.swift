import Foundation

enum HelplineConfig {
    // ⚙️ SETUP: replace with the dedicated help-line email address before shipping.
    static let email = "REPLACE_WITH_YOUR_HELPLINE_EMAIL@example.com"

    static let poisonControlNumber = "8884264435"
    static let poisonControlDisplay = "(888) 426-4435"
    static let emergencyVetLocatorURL = URL(string: "https://vetlocator.com/")!

    static let responseWindow = "24–48 hours"

    struct ServiceTier {
        let name: String
        let price: String
        let details: String
    }

    static let serviceTiers: [ServiceTier] = [
        ServiceTier(
            name: "Quick question",
            price: "Free",
            details: "One email reply within 24–48 hours: a clear, plain-English answer to one general pet-care question, with links to trusted resources when helpful."
        ),
        ServiceTier(
            name: "Detailed question",
            price: "$10",
            details: "An in-depth written reply with step-by-step suggestions and curated resources for your situation, plus one follow-up email within a week."
        ),
        ServiceTier(
            name: "30-minute consult",
            price: "$25",
            details: "A scheduled phone or video call for general care guidance — routines, new-pet setup, vet-visit prep — with a short email recap afterward."
        )
    ]

    static let tierFormOptions = [
        "Quick question — Free (one email reply)",
        "Detailed question — $10 (in-depth reply + one follow-up)",
        "30-minute consult — $25 (scheduled call)",
        "Not sure — recommend one for me"
    ]

    static let disclaimer = """
    This app is run by a veterinary assistant and provides general pet-care \
    education only. It does not offer veterinary medical advice, diagnosis, \
    treatment, or prescriptions, and does not create a veterinarian–client–patient \
    relationship. Always consult a licensed veterinarian for medical concerns \
    about your pet. If your pet is in distress, contact an emergency veterinary \
    clinic immediately.
    """
}
