import Foundation

enum HelplineConfig {
    static let replyEmail = "info@bayareaapps.com"
    /// The client page the QR code points to — the same URL as the printed
    /// poster (docs/share-qr.png), so every QR code lands in the same place.
    static let siteURL = URL(string: "https://paws-whiskers-care-line.dkjmmz6whh.workers.dev/")!
    static let siteDisplayName = "Paws & Whiskers Care Line intake page"
    static let checkoutBaseURL = URL(string: "https://vet-helpline-development.dkjmmz6whh.workers.dev")!

    static let purpose = """
    Have questions about your dog or cat? Just ask. Send the details and get \
    clear, practical, general educational guidance from an experienced veterinary \
    assistant on your private conversation page or by phone.
    """

    static let costExplanation = """
    Clients choose Quick Question for $10, Detailed Guidance for $15, Phone Support \
    for $25, or Free Community Support and see the price before submitting. \
    Paid requests continue to PayPal or Apple Pay checkout automatically. \
    Free Community Support requires no payment.
    """

    // The three steps shown on the shareable card and welcome page.
    static let howItWorks = [
        "Scan the code and choose the option that works for you",
        "Tell me what is happening with your dog or cat; paid options continue to checkout",
        "I review the details and files, then answer on your private conversation page or by phone"
    ]

    // Shown on the shareable card; keep in sync with the website pages.
    static let canHelpWith = [
        "\"Is this an emergency — or can it wait?\"",
        "General care, feeding, husbandry & grooming",
        "Behavior basics and enrichment ideas",
        "Home care and recovery questions after a vet visit",
        "Photo, video, PDF and document review for context",
        "Vet or ER visit prep and questions to ask",
        "New and senior dog or cat routine-care basics"
    ]

    struct ServicePrice: Identifiable {
        let id = UUID()
        let service: String
        let price: String
        let detail: String
    }

    struct PriceSection: Identifiable {
        let id = UUID()
        let title: String
        let items: [ServicePrice]
    }

    // ⚙️ SETUP: adjust these to your real prices before sharing the QR card
    // (keep them in sync with index.html, welcome.html, and poster.html).
    static let priceMenu: [PriceSection] = [
        PriceSection(title: "Access options", items: [
            ServicePrice(service: "Quick Question",
                         price: "$10",
                         detail: "A reply on your private conversation page"),
            ServicePrice(service: "Detailed Guidance",
                         price: "$15",
                         detail: "More detailed guidance in your private conversation"),
            ServicePrice(service: "Phone Support",
                         price: "$25",
                         detail: "Talk through your question by phone"),
            ServicePrice(service: "Free Community Support",
                         price: "Free",
                         detail: "No-cost access when needed; no explanation required")
        ]),
        PriceSection(title: "Private file uploads", items: [
            ServicePrice(service: "Any file type",
                         price: "Included",
                         detail: "Up to 4 files, 10 MB each; links expire after 30 days")
        ])
    ]

    static let poisonControlNumber = "8884264435"
    static let poisonControlDisplay = "(888) 426-4435"
    static let emergencyVetLocatorURL = URL(string: "https://vetlocator.com/")!

    static let responseWindow = "24–48 hours"

    // Shown at the bottom of the shareable card; the web pages carry the
    // same wording in their footers.
    static let clientDisclaimer = """
    Disclaimer: This service is run by a veterinary assistant and provides \
    general dog-and-cat care education only. It is not veterinary medical advice and \
    does not diagnose, prescribe, recommend medication or doses, provide \
    treatment, or create a veterinarian-client-patient relationship. Contact \
    a licensed veterinarian for medical concerns. For a possible emergency, \
    contact an emergency veterinary hospital immediately.
    """

    // Appended to the bottom of every reply template.
    static let disclaimerFooter = """
    —
    A reminder: I'm a veterinary assistant, not a veterinarian. This is general \
    dog-and-cat care education only, not veterinary medical advice. I cannot diagnose, \
    prescribe, recommend medication or doses, provide a treatment plan, interpret \
    diagnostic results, or establish a veterinarian-client-patient relationship. \
    Contact a licensed veterinarian for medical concerns. For a possible emergency, \
    contact an emergency veterinary hospital immediately.
    """
}
