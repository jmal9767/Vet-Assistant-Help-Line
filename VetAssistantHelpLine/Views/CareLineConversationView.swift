import SwiftUI

struct CareLineConversationView: View {
    @Environment(QuestionStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    let question: ClientQuestion
    @State private var thread: CareLineThread?
    @State private var openedToken: String?
    @State private var text = ""
    @State private var error: String?
    @State private var busy = false
    @State private var pendingID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    @State private var pendingText = ""
    private let service = CareLineConversationService()
    var body: some View {
        List {
            Section("Reply from your app") {
                Text("Clients read and reply on their private conversation page. Your sender is Paws & Whiskers Care Line; your personal email and phone number are not shown.")
                if let error { Text(error).foregroundStyle(.red) }
                if let thread {
                    LabeledContent("Payment", value: thread.paymentStatus)
                    if let url = thread.privateURL { ShareLink("Share This Client’s Private Conversation", item: url) }
                    Text("Share only with this client. Clients must return to this page to check replies; no SMS or email alerts are sent.").font(.footnote)
                } else if question.conversationToken == nil {
                    Button("Create Private Conversation") { Task { await create() } }.disabled(busy)
                    Text("For an older question, create a conversation and share its link with the client before switching from their original reply method.").font(.footnote)
                }
            }
            if let thread {
                Section("Client’s question") { Text(thread.question).textSelection(.enabled) }
                Section("Conversation") {
                    if thread.messages.isEmpty { Text("No replies yet.").foregroundStyle(.secondary) }
                    ForEach(thread.messages) { message in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(message.sender == "business" ? "Paws & Whiskers Care Line" : question.name).font(.caption.bold())
                            Text(message.text).textSelection(.enabled)
                            if let date = ISO8601DateFormatter.fractional.date(from: message.createdAt) { Text(date, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                Section("Your reply") {
                    TextField("Write your response", text: $text, axis: .vertical).lineLimit(4...12)
                    NavigationLink("Reply Templates") { TemplatesView() }
                    Button(busy ? "Please wait…" : "Send Care Line Reply") { Task { await send() } }
                        .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 4000)
                    Text("Sending posts to the client’s private page. Check payment status before providing a paid response. Phone calls take place separately.").font(.footnote)
                }
            }
        }.navigationTitle("Private Conversation")
        .refreshable { await refresh() }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await refresh()
                do { try await Task.sleep(for: .seconds(15)) } catch { break }
            }
        }
        .overlay { if scenePhase != .active { Color(.systemBackground).ignoresSafeArea().overlay { Label("Private Conversation", systemImage: "lock.fill") } } }
    }
    private func refresh() async {
        guard !busy, scenePhase == .active, let token = openedToken ?? question.conversationToken else { return }
        busy = true; defer { busy = false }
        do { thread = try await service.thread(token); error = nil }
        catch { self.error = error.localizedDescription; thread = nil }
    }
    private func create() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { let created = try await service.create(recordName: question.id.recordName); thread = created; openedToken = created.token; error = nil; await store.refresh() }
        catch { self.error = error.localizedDescription }
    }
    private func send() async {
        guard !busy, let token = thread?.token else { return }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if pendingText != value { pendingText = value; pendingID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
        busy = true; defer { busy = false }
        do { thread = try await service.send(value, id: pendingID, token: token); text = ""; pendingText = ""; error = nil; await store.refresh() }
        catch { self.error = error.localizedDescription }
    }
}
private extension ISO8601DateFormatter {
    static var fractional: ISO8601DateFormatter { let value = ISO8601DateFormatter(); value.formatOptions = [.withInternetDateTime,.withFractionalSeconds]; return value }
}
