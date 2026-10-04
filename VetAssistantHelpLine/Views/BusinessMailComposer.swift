import MessageUI
import SwiftUI

struct BusinessEmailDraft: Identifiable {
    let id = UUID()
    let recipient: String
    let subject: String
    let body: String

    init?(mailto: URL) {
        guard mailto.scheme == "mailto", !mailto.path.isEmpty,
              let components = URLComponents(url: mailto, resolvingAgainstBaseURL: false) else { return nil }
        recipient = mailto.path
        subject = components.queryItems?.first(where: { $0.name == "subject" })?.value ?? ""
        body = components.queryItems?.first(where: { $0.name == "body" })?.value ?? ""
    }
}

struct BusinessMailComposer: UIViewControllerRepresentable {
    let draft: BusinessEmailDraft
    let onFinish: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients([draft.recipient])
        composer.setSubject(draft.subject)
        composer.setMessageBody(draft.body, isHTML: false)
        // iOS may use its default account if this mailbox is missing. The detail
        // screen explicitly tells the operator to check From before sending.
        composer.setPreferredSendingEmailAddress(HelplineConfig.replyEmail)
        return composer
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let onFinish: (Bool) -> Void
        init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

        func mailComposeController(_ controller: MFMailComposeViewController,
                                   didFinishWith result: MFMailComposeResult, error: Error?) {
            onFinish(result == .failed || error != nil)
        }
    }
}
