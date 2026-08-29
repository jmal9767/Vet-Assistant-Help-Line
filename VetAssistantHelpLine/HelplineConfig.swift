import Foundation

enum HelplineConfig {
    // ⚙️ SETUP: replace with the dedicated help-line email address before shipping.
    static let email = "REPLACE_WITH_YOUR_HELPLINE_EMAIL@example.com"

    static let poisonControlNumber = "8884264435"
    static let poisonControlDisplay = "(888) 426-4435"
    static let emergencyVetLocatorURL = URL(string: "https://vetlocator.com/")!

    static let responseWindow = "24–48 hours"

    static let disclaimer = """
    This app is run by a veterinary assistant and provides general pet-care \
    education only. It does not offer veterinary medical advice, diagnosis, \
    treatment, or prescriptions, and does not create a veterinarian–client–patient \
    relationship. Always consult a licensed veterinarian for medical concerns \
    about your pet. If your pet is in distress, contact an emergency veterinary \
    clinic immediately.
    """
}
