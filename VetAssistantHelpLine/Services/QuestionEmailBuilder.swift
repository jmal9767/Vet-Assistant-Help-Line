import Foundation

enum QuestionEmailBuilder {
    static func build(
        draft: QuestionDraft,
        credit: PaidQuestionCredit
    ) -> QuestionEmail? {
        guard draft.isReadyForReview,
              let category = draft.category,
              credit.productID == HelplineConfig.educationQuestionProductID,
              !credit.signedTransactionJWS.isEmpty,
              let appAccountToken = credit.appAccountToken else {
            return nil
        }

        let submissionReference = appAccountToken.uuidString
        let shortSubmissionReference = submissionReference.prefix(8)
        let subject = "\(HelplineConfig.emailSubjectPrefix) \(category.title) [\(shortSubmissionReference)]"

        let body = """
        PAID QUESTION FOR SCOPE REVIEW

        Submission reference / Apple app-account token: \(submissionReference)
        Apple transaction reference: \(credit.id)
        Apple environment: \(credit.environment)

        APPLE-SIGNED TRANSACTION PROOF (JWS)
        Verify this Apple signature and confirm the bundle, product, transaction reference, \
        app-account token, and Production environment. Then confirm in the operator ledger \
        that this transaction was not previously redeemed before accepting the paid question.
        \(credit.signedTransactionJWS)

        TOPIC
        \(category.title)

        QUESTION
        \(category.guidedQuestion.prompt)
        \(draft.answer(for: category.guidedQuestion))

        CLIENT ATTESTATION
        \(HelplineConfig.emailAttestationSummary)
        """

        return QuestionEmail(
            recipient: HelplineConfig.recipientEmail,
            subject: subject,
            body: body
        )
    }
}
