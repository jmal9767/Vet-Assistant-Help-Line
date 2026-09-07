import Foundation

enum HelplineConfig {
    /// The client page the QR code points to — the same URL as the printed
    /// poster (docs/share-qr.png), so every QR code lands in the same place.
    static let siteURL = URL(string: "https://jmal9767.github.io/Vet-Assistant-Help-Line/")!

    static let purpose = """
    Not sure whether your pet needs a vet — or the emergency room? Get a \
    thorough, honest answer from a veterinary assistant with hands-on \
    experience in both emergency and general practice — so you can make \
    the right call for your pet.
    """

    // The three steps shown on the shareable card and welcome page.
    static let howItWorks = [
        "Scan the code & send your question",
        "I confirm the price and you pay by secure link — protected by a full satisfaction guarantee",
        "Your answer arrives in your chosen time frame — not helped? Full refund"
    ]

    // Shown on the shareable card; keep in sync with the website pages.
    static let canHelpWith = [
        "\"Is this an emergency — or can it wait?\"",
        "General care, feeding & husbandry",
        "Grooming, enrichment & behavior basics",
        "Home care & recovery questions after a vet visit",
        "Preparing for vet or ER visits & what to ask",
        "New-pet, senior-pet & routine-care basics"
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
        PriceSection(title: "Email answers — standard reply within 24–48 hours", items: [
            ServicePrice(service: "Quick question",
                         price: "$10",
                         detail: "One straightforward question — one email reply"),
            ServicePrice(service: "Detailed question",
                         price: "$20",
                         detail: "Multi-part, behavior, or \"should I see a vet?\" questions — in-depth reply plus one follow-up")
        ]),
        PriceSection(title: "Need it faster? Add to any email answer", items: [
            ServicePrice(service: "Same-day reply",
                         price: "+$10",
                         detail: "Your answer within 12 hours"),
            ServicePrice(service: "Express reply",
                         price: "+$20",
                         detail: "Your answer within 2–4 hours — not for emergencies")
        ]),
        PriceSection(title: "Talk it through — scheduled with you", items: [
            ServicePrice(service: "Text chat · 15 min",
                         price: "$20",
                         detail: "Back-and-forth by text message"),
            ServicePrice(service: "Phone call · 15 min",
                         price: "$25",
                         detail: "Quick guidance call"),
            ServicePrice(service: "Phone call · 30 min",
                         price: "$40",
                         detail: "General care guidance on any topic")
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
    general pet-care education only. It does not replace or supersede the \
    advice, diagnosis, or treatment of a licensed veterinarian. Responses \
    are not immediate — if you believe your pet may be experiencing a \
    life-threatening emergency, do not wait for a reply. Contact an \
    emergency veterinary hospital right away.
    """

    // Appended to the bottom of every reply template.
    static let disclaimerFooter = """
    —
    A reminder: I'm a veterinary assistant, and this help line provides general \
    pet-care education only. Nothing here replaces or supersedes the advice, \
    diagnosis, or treatment of a licensed veterinarian. For any medical concern, \
    please see a licensed veterinarian — and if your pet may be experiencing a \
    life-threatening emergency, don't wait for my reply: contact an emergency \
    veterinary hospital immediately.
    """
}
