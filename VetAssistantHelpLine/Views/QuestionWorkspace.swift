import SwiftUI
import MessageUI

struct QuestionWorkspace: View {
    @EnvironmentObject private var inbox: PrivateInbox
    let questionID: String
    @State private var summary = ""
    @State private var practical = ""
    @State private var boundary = ""
    @State private var sourceText = ""
    @State private var reviewed: Set<Int> = []
    @State private var working = false
    @State private var error: String?
    @State private var confirmation: String?
    @State private var mailMessage: QuestionEmail?
    @State private var showingMail = false
    @State private var handoffQuestion: OperatorQuestion?

    private var question: OperatorQuestion? { inbox.questions.first { $0.id == questionID } }
    private var sources: [String] {
        sourceText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    private var ready: Bool {
        guard let checklist = inbox.catalog?.answerChecklist, !checklist.isEmpty else { return false }
        return summary.trimmingCharacters(in: .whitespacesAndNewlines).count >= 30
            && practical.trimmingCharacters(in: .whitespacesAndNewlines).count >= 60
            && boundary.trimmingCharacters(in: .whitespacesAndNewlines).count >= 20
            && (1...3).contains(sources.count) && reviewed.count == checklist.count
    }

    var body: some View {
        Group {
            if let q = question {
                Form {
                    Section(q.statusTitle) {
                        Text(q.question).font(.headline)
                        if !q.context.isEmpty { Text(q.context) }
                        LabeledContent("Reply to", value: q.email)
                        LabeledContent("Requested format", value: q.format)
                        Text("Reference: \(q.id)").font(.caption).textSelection(.enabled)
                        if let due = q.clarificationDue ?? q.due { Text("Response target: \(OperatorQuestion.pacificDate(due))") }
                        if !q.note.isEmpty { Text(q.note) }
                    }
                    if let category = inbox.catalog?.categories.first(where: { $0.id == q.category }) {
                        Section("Response goal · " + category.title) {
                            Text(category.answerGoal)
                            Text(category.notIncluded).foregroundStyle(.secondary)
                            ForEach(category.sources, id: \.self) { source in
                                if let url = URL(string: source) { Link(source, destination: url) }
                            }
                        }
                    }
                    if let clarification = q.clarification { Section("Client’s included clarification") { Text(clarification) } }
                    if let answer = q.answer { answerSection("Published answer", answer: answer) }
                    if let answer = q.clarificationAnswer { answerSection("Published clarification", answer: answer) }

                    if q.canAnswer {
                        Section(q.clarification == nil ? "Write the answer" : "Explain the original answer") {
                            Text("Read the entire message first. If it needs medical judgment or you can only refer the client elsewhere, issue a full refund.").font(.footnote)
                            TextField("Direct answer to their actual question", text: $summary, axis: .vertical).lineLimit(3...10)
                            TextField("Useful explanation or practical checklist", text: $practical, axis: .vertical).lineLimit(5...18)
                            TextField("Relevant limits and when professional help is needed", text: $boundary, axis: .vertical).lineLimit(3...8)
                            TextField("1–3 checked HTTPS sources, one per line", text: $sourceText, axis: .vertical).textInputAutocapitalization(.never).autocorrectionDisabled().lineLimit(3...6)
                            Text("Drafts are not saved. Leaving this screen or backgrounding the app discards unfinished work.").font(.footnote).foregroundStyle(.secondary)
                        }
                        if let checklist = inbox.catalog?.answerChecklist {
                            Section("Human review required") {
                                ForEach(Array(checklist.enumerated()), id: \.offset) { index, item in
                                    Toggle(item, isOn: Binding(get: { reviewed.contains(index) }, set: { enabled in
                                        if enabled { reviewed.insert(index) } else { reviewed.remove(index) }
                                    }))
                                }
                            }
                        }
                        Section {
                            Button("Publish answer to client’s private page") { confirmation = "publish" }
                                .disabled(!ready || working || q.mailState == "unresolved")
                        } footer: { Text("Publishing is permanent. Email is prepared separately after the answer is saved.") }
                    }
                    if q.latestAnswer != nil {
                        Section("Email notification") {
                            if q.mailState == "pending" {
                                Button("Prepare email in Apple Mail") { beginMail(q) }.disabled(working || !MFMailComposeViewController.canSendMail())
                                if !MFMailComposeViewController.canSendMail() {
                                    Text("Set up your support mailbox in Apple Mail on this iPhone, then return. The answer is already available on the client’s private page.")
                                }
                            } else if q.mailState == "unresolved" {
                                Text("An email copy was prepared. Check Mail’s Drafts, Outbox and Sent folders before another copy is allowed.")
                                Button("I verified the email was sent or queued") { confirmation = "queued" }
                                Button("I deleted every unsent draft copy") { confirmation = "deleted" }
                            } else { Text("Email handed to Apple Mail. This confirms the handoff, not delivery. Check for a bounce in your support mailbox.") }
                            Text("Use info@bayareaapps.com as the From address in Mail. This app cannot select or verify the sending mailbox.").font(.footnote)
                        }
                    }
                    if q.state != "refunded" {
                        Section("Payment and scope") {
                            Button(q.state == "refund_requested" ? "Process or check full refund" : "Issue full refund", role: .destructive) { confirmation = "refund" }.disabled(working)
                            if q.state == "payment_hold" || q.state == "refund_requested" {
                                Button("Recheck Stripe payment status") { perform { _ = try await inbox.act(q, action: "reconcile") } }.disabled(working)
                            }
                            Text("If this question is outside your scope, do not sell a referral as an answer. Refund the full payment. Failed or disputed refunds require review in Stripe.").font(.footnote)
                        }
                    }
                    if let error { Section { Text(error).foregroundStyle(.red) } }
                    if working { ProgressView("Saving…") }
                }
                .disabled(working)
                .refreshable { await inbox.refresh() }
            } else { ContentUnavailableView("Inbox locked or question unavailable", systemImage: "lock", description: Text("Return to your inbox and refresh.")) }
        }
        .navigationTitle("Question workspace")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Confirm action", isPresented: Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } }), titleVisibility: .visible) {
            if let action = confirmation, let q = question {
                if action == "publish" {
                    Button("Publish reviewed answer") { publish(q) }
                } else if action == "refund" {
                    Button("Confirm full refund", role: .destructive) {
                        perform { _ = try await inbox.act(q, action: "refund", values: ["confirmed": true, "note": "A full refund has been requested for this question. No replacement purchase is required. Contact free support if you need help with the refund."]) }
                    }
                } else {
                    Button(action == "queued" ? "Confirm sent or queued" : "Confirm every unsent copy deleted") {
                        perform { _ = try await inbox.act(q, action: "mail", values: ["action": action, "confirmed": true]) }
                    }
                }
            }
        } message: {
            Text(confirmation == "publish" ? "The client can read this answer immediately. Verify the content, sources and scope before publishing." : confirmation == "refund" ? "This requests a full refund to the original payment method. Do not promise that a pending refund has reached the client’s bank." : "Only confirm what you have checked in Apple Mail. This prevents duplicate reply emails.")
        }
        .sheet(isPresented: $showingMail) {
            if let mailMessage {
                MailComposerView(isPresented: $showingMail, message: mailMessage) { result, mailError in
                    guard result == .sent, mailError == nil, let handoffQuestion else { return }
                    perform { _ = try await inbox.act(handoffQuestion, action: "mail", values: ["action": "queued", "confirmed": true]) }
                }.interactiveDismissDisabled()
            }
        }
    }

    private func answerSection(_ title: String, answer: EducationAnswer) -> some View {
        Section(title) {
            Text(answer.summary); Text(answer.practical); Text(answer.boundary)
            ForEach(answer.sources, id: \.self) { source in
                if let url = URL(string: source) { Link(source, destination: url) }
            }
        }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !working else { return }
        working = true; error = nil; confirmation = nil
        Task { @MainActor in
            defer { working = false }
            do { try await operation() }
            catch { self.error = error.localizedDescription; await inbox.refresh() }
        }
    }
    private func publish(_ q: OperatorQuestion) {
        perform {
            _ = try await inbox.act(q, action: "answer", values: ["summary": summary, "practical": practical, "boundary": boundary, "sources": sources, "reviewed": ready])
            summary = ""; practical = ""; boundary = ""; sourceText = ""; reviewed = []
        }
    }
    private func beginMail(_ q: OperatorQuestion) {
        guard MFMailComposeViewController.canSendMail() else { return }
        perform {
            let updated = try await inbox.act(q, action: "mail", values: ["action": "begin"])
            handoffQuestion = updated; mailMessage = updated.mail; showingMail = true
        }
    }
}
