import MessageUI
import SwiftUI

struct MailComposerView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let message: QuestionEmail
    let onFinish: (MFMailComposeResult, Error?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented, onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        controller.mailComposeDelegate = context.coordinator
        controller.setToRecipients([message.recipient])
        controller.setSubject(message.subject)
        controller.setMessageBody(message.body, isHTML: false)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: MFMailComposeViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        private let isPresented: Binding<Bool>
        private let onFinish: (MFMailComposeResult, Error?) -> Void
        private var hasFinished = false

        init(
            isPresented: Binding<Bool>,
            onFinish: @escaping (MFMailComposeResult, Error?) -> Void
        ) {
            self.isPresented = isPresented
            self.onFinish = onFinish
        }

        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult,
            error: Error?
        ) {
            guard !hasFinished else { return }
            hasFinished = true
            isPresented.wrappedValue = false
            onFinish(result, error)
        }
    }
}
