import Foundation

enum HelplineConfig {
    /// The client page the QR code points to — the same URL as the printed
    /// poster (docs/share-qr.png), so every QR code lands in the same place.
    static let siteURL = URL(string: "https://jmal9767.github.io/Vet-Assistant-Help-Line/")!

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

    // BEGIN SERVICE MENU
    static let headline = "Feel more confident caring for your pet."
    static let purpose = "Personal help from Jahmal, a veterinary assistant with emergency and general-practice experience. Turn an everyday pet-care question into clear, practical steps you can use at home."
    static let scope = "General pet-care education for one pet and one nonmedical topic per purchase. Symptoms, medication questions and decisions about whether care can wait belong with a licensed veterinarian."
    static let included = "Every option includes practical next steps, a written answer or recap to keep, and one written clarification on the same topic requested within 7 calendar days of your answer or session."
    static let timing = "Written-answer deadlines start after your request is accepted and payment is completed. Any needed details are collected first. Your confirmation gives the exact due date and time before you pay. Business days are Monday–Friday, excluding U.S. federal holidays, in Pacific Time."
    static let booking = "Text and phone sessions start at the appointment time agreed before payment. The minutes shown are conversation time, not a wait for a reply. Your recap arrives within 1 business day after the session. Sessions depend on availability; this is not an on-demand line."
    static let followUp = "Send your included clarification by replying to your answer or recap within 7 calendar days. It receives one written reply within 2 business days. A new topic or another pet needs a separate quote; there are no automatic extra charges."
    static let guarantee = "No charge to submit a request. The service, full price and deadline are confirmed before payment. If your question cannot be answered within this service, you will not be charged; if already paid, you receive a full refund. If you do not feel your question was answered, reply to request a full refund. You may also request a full refund if the agreed deadline is missed or you cancel before the answer is sent or the session begins."
    static let requestTiming = "Allow up to 2 business days for a request review and quote. Submitting the form does not start a paid service or reserve an appointment."
    static let howItWorks = [
        "Send your everyday care question and choose an option — no payment to submit.",
        "Receive confirmation of what is included, the full price and an exact deadline or appointment before you pay.",
        "Get practical steps, a written answer or recap, and one included clarification within 7 days."
    ]
    static let canHelpWith = [
        "Set up a practical new-pet routine",
        "Choose enrichment and everyday grooming supplies",
        "Organize feeding and household care routines",
        "Prepare a checklist and questions for a vet visit"
    ]
    static let priceMenu: [PriceSection] = [
        PriceSection(title: "Written help", items: [
            ServicePrice(service: "Focused written answer", price: "$10", detail: "Email or text — same price. One straightforward care question, with a personal explanation and practical next steps. Within 1 business day after confirmation and payment."),
            ServicePrice(service: "Detailed written guide", price: "$20", detail: "Email. Related questions on one care topic, organized into a step-by-step guide, checklist and useful resources. Within 2 business days after confirmation and payment."),
        ]),
        PriceSection(title: "Scheduled conversations", items: [
            ServicePrice(service: "Live text session", price: "$25", detail: "20 minutes of scheduled text conversation. Work through one care topic together, ask questions as you go, and receive an emailed recap. At your confirmed appointment time."),
            ServicePrice(service: "Phone support session", price: "$35", detail: "30 minutes of scheduled phone conversation. Talk through one care topic at a comfortable pace, with time for questions and an emailed recap. At your confirmed appointment time."),
        ]),
    ]
// END SERVICE MENU

    static let poisonControlNumber = "8884264435"
    static let poisonControlDisplay = "(888) 426-4435"
    static let emergencyVetLocatorURL = URL(string: "https://vetlocator.com/")!


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
