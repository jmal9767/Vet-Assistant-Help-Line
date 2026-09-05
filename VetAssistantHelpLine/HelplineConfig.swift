import Foundation

enum HelplineConfig {
    static let serviceName = "Veterinary Assistant Help Line"
    static let recipientEmail = "info@bayareaapps.com"
    static let educationQuestionProductID =
        "com.bayareaapps.vetassistanthelpline.education_question"

    static let poisonControlNumber = "8884264435"
    static let poisonControlDisplay = "(888) 426-4435"

    static let responsePromise =
        "A paid initial email with valid Apple proof, or an authorized replacement, normally receives one human review result—an eligible answer or a scope/referral notice—by 5:00 p.m. Pacific Time on the second business day after it reaches the service inbox. The first business day after actual receipt is day one. Business days are Monday through Friday, excluding U.S. federal holidays; there is no 5:00 p.m. receipt cutoff or rollover. This is a target, not a guaranteed deadline."

    static let responseTimeAcknowledgement =
        "I understand a valid paid email or authorized replacement normally receives a human answer or scope/referral notice by 5:00 p.m. Pacific Time on the second business day after actual inbox receipt. The first business day after receipt is day one; weekends and U.S. federal holidays do not count, and there is no 5:00 p.m. receipt cutoff or rollover. This is not an emergency service or guaranteed deadline."

    static let purchaseCoverageStatement =
        "One verified Apple in-app purchase unlocks preparation of one general-education question email for human scope review. If eligible, it receives one human-written educational answer; otherwise, the replacement policy applies."

    static let paidSubmissionVerificationStatement =
        "Apple's signed transaction authenticates purchase fields, not the editable email body. Keep that proof private: Bay Area Apps treats the first message for which it verifies and atomically redeems the signed Production transaction as the paid initial submission. A direct new-thread question without verified proof and a transaction available for first redemption is free administrative support only. An authorized same-thread replacement or exact technical resend is reconciled to the canonical paid thread and does not redeem the transaction again."

    static let scopeStatement = """
    This service is independently operated by a California veterinary assistant, \
    which is an unlicensed support role. The operator is not a veterinarian, and no \
    veterinarian supervises, reviews, or participates in this service. It is not a \
    veterinary clinic and provides only narrow, general education. It does not \
    evaluate symptoms, safety, behavior, or urgency; diagnose; predict an outcome; \
    provide first aid or treatment; recommend products, foods, diets, supplements, \
    medications, or doses; interpret records, tests, or images; or create a \
    veterinarian–client–patient relationship.
    """

    static let noEmergencyAcknowledgement =
        "I am not using this service about a pet who may be sick, injured, pregnant, post-operative, in distress, exposed to something harmful, or changing rapidly. If I am unsure or worried, I will contact a licensed veterinarian now instead of waiting for this service."

    static let educationOnlyAcknowledgement =
        "My question is one general education question only—not symptoms, exposure, urgency, diagnosis, prognosis, first aid, treatment, products, foods, diets, supplements, medication or dosage, behavior or safety concerns, records, tests, images, illness, or injury."

    static let veterinaryCareAcknowledgement =
        "I understand that medical or safety concerns require a licensed veterinarian and should not wait for this service; possible poisoning in the United States can also be directed to ASPCA Animal Poison Control."

    static let purchaseAcknowledgement =
        "I understand Apple processes payment when I approve the purchase. The question credit is marked used when Apple Mail reports the email queued, or when I explicitly confirm I sent it with another email app. After the complete email is displayed in Apple Mail, a saved, cancelled, failed, or unknown result must be resolved as sent or deleted before the credit can be used again; the same applies after a fallback email is copied. Queued does not guarantee delivery, and the app cannot restore a used credit. If my initial question is ineligible, exactly one eligible replacement must reach the service inbox from the same sender address and in the same thread by 11:59 p.m. Pacific Time on the 90th calendar day after the replacement-offer email is sent; an ineligible replacement does not create another replacement."

    static let adultPurchaseAcknowledgement =
        "I confirm I am at least 18 and authorized to make this purchase."

    static let unusedPurchasePolicy =
        "A verified question credit that the app has not marked used does not expire. If Bay Area Apps discontinues the paid service before you can use it, contact purchase support so the credit can be honored or an Apple refund request can be supported."

    static let missingEmailSupportStatement =
        "If the app marks a credit used but the prepared message is missing from your mail account or no service response arrives, contact free purchase support with the Apple transaction reference. Do not purchase again."

    static let replacementQuestionPolicy =
        "If a valid paid initial question is outside this educational scope, the human reply will explain the boundary and will offer exactly one replacement. That eligible replacement question must reach the service inbox from the same sender address and in the same email thread by 11:59 p.m. Pacific Time on the 90th calendar day after the replacement-offer email is sent. No other purchase is required. This does not create or restore an in-app credit, and an ineligible replacement does not create another replacement. Invalid proof, fraud, abuse, or misuse does not create a replacement right."

    static let questionDataWarning =
        "Do not enter names, contact details, pet demographics or history, symptoms, injury, exposure, urgency, behavior or safety concerns, products, foods, diets, supplements, doses, treatments, medications, records, test results, or image information."

    static let emailAttestationSummary =
        "The client completed all required in-app safety, educational-scope, response-time, purchase and email-handoff, and adult-purchase confirmations immediately before using this verified credit. The operator must still independently review the question and Apple proof."

    static let freeProviderAndCostGuidance =
        "Provider-finding and cost questions do not require a paid submission. Contact clinics directly to ask about availability, exam fees, written estimates, payment options, and local nonprofit or veterinary-school resources. This service does not endorse a provider or financial product."

    static let emailSubjectPrefix = "[Veterinary Assistant Help Line]"

    static var emergencyVetLocatorURL: URL? {
        URL(string: "https://maps.apple.com/?q=emergency%20veterinarian")
    }

    static var californiaVeterinaryLicenseLookupURL: URL? {
        URL(string: "https://search.dca.ca.gov/")
    }

    static var poisonControlPhoneURL: URL? {
        URL(string: "tel:\(poisonControlNumber)")
    }

    static var contactEmailURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipientEmail
        return components.url
    }

    static var applePurchaseSupportURL: URL? {
        URL(string: "https://reportaproblem.apple.com/")
    }

    static var privacyPolicyURL: URL? {
        URL(string: "https://bayareaapps.com/veterinary-assistant-help-line/privacy.html")
    }

    static var termsPolicyURL: URL? {
        URL(string: "https://bayareaapps.com/veterinary-assistant-help-line/terms.html")
    }
}
