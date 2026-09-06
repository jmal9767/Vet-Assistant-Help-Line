import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var inbox: PrivateInbox
    @State private var serviceURL = ""
    @State private var deviceKey = ""
    @State private var showAll = false
    @State private var showGuide = false
    @State private var confirmOpen = false

    var body: some View {
        NavigationStack {
            Group {
                if inbox.unlocked {
                    List {
                        Section {
                            LabeledContent("New questions", value: inbox.accepting ? "Open" : "Paused")
                            LabeledContent("Payments", value: inbox.live ? "Live" : "Test only")
                            Button(inbox.accepting ? "Pause new questions" : "Open for new questions") {
                                if inbox.accepting { Task { await inbox.setAvailability(false) } }
                                else { confirmOpen = true }
                            }
                            Toggle("Include completed questions", isOn: $showAll)
                        } footer: {
                            Text("Only paid submissions enter this inbox. Refresh to receive new questions; this is not a live emergency service.")
                        }
                        if let error = inbox.error { Section { Text(error).foregroundStyle(.red) } }
                        let visible = inbox.questions.filter { showAll || $0.needsAttention }
                        if visible.isEmpty {
                            ContentUnavailableView("No questions to review", systemImage: "tray", description: Text("New paid questions will appear here after you refresh."))
                        }
                        ForEach(visible) { question in
                            NavigationLink {
                                QuestionWorkspace(questionID: question.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(question.statusTitle).font(.caption.weight(.semibold)).foregroundStyle(question.overdue ? Color.red : Color.secondary)
                                    Text(question.question).lineLimit(3)
                                    if let due = question.clarificationDue ?? question.due {
                                        Text("Target: \(OperatorQuestion.pacificDate(due))").font(.footnote)
                                    }
                                    if question.mailState == "unresolved" { Label("Resolve email handoff", systemImage: "exclamationmark.envelope").font(.footnote) }
                                    else if question.mailState == "pending" { Text("Answer published · email pending").font(.footnote) }
                                }
                            }
                        }
                    }
                    .refreshable { await inbox.refresh() }
                } else {
                    Form {
                        Section {
                            Label("Your private work inbox", systemImage: "lock.shield").font(.title2)
                            Text("For Jahmal only. Clients use the website and pay through Stripe; they do not install this app.")
                        }
                        Section("First connection or changed settings") {
                            TextField("HTTPS service URL", text: $serviceURL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            SecureField("Private device key—not a Stripe key", text: $deviceKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                            Text("Leave these fields empty to unlock your saved connection. The key stays in this iPhone’s Keychain.").font(.footnote)
                        }
                        if let error = inbox.error { Text(error).foregroundStyle(.red) }
                        Button(inbox.busy ? "Connecting…" : "Unlock and connect") {
                            Task {
                                await inbox.unlock(url: serviceURL, token: deviceKey)
                                deviceKey = ""
                            }
                        }.disabled(inbox.busy)
                    }
                }
            }
            .navigationTitle("Help Line Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Service guide") { showGuide = true } }
                if inbox.unlocked {
                    ToolbarItem(placement: .topBarTrailing) { Button("Lock", systemImage: "lock") { inbox.lock() } }
                    ToolbarItem(placement: .bottomBar) { Button("Refresh", systemImage: "arrow.clockwise") { Task { await inbox.refresh() } }.disabled(inbox.busy) }
                }
            }
            .sheet(isPresented: $showGuide) { ServiceGuideView() }
            .confirmationDialog("Open the paid question queue?", isPresented: $confirmOpen, titleVisibility: .visible) {
                Button("Open queue") { Task { await inbox.setAvailability(true) } }
            } message: { Text("Confirm the website, Stripe webhooks, email, privacy controls, and your availability are ready. The server caps outstanding work at ten questions and checkout reservations.") }
        }
    }
}

struct ServiceGuideView: View {
    @EnvironmentObject private var inbox: PrivateInbox
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if let catalog = inbox.catalog {
                    Section(catalog.price + " · one question") {
                        Text(catalog.coverage); Text(catalog.responsePromise); Text(catalog.refundPolicy)
                    }
                    Section("Your scope") { Text(catalog.scope); Text(catalog.emergency) }
                    ForEach(catalog.categories) { category in
                        Section(category.title) {
                            Text(category.summary)
                            ForEach(category.examples, id: \.self) { Text($0) }
                            Text("Answer goal: " + category.answerGoal).fontWeight(.medium)
                            Text(category.notIncluded).foregroundStyle(.secondary)
                        }
                    }
                    Section("Before publishing every answer") {
                        ForEach(catalog.answerChecklist, id: \.self) { Text($0) }
                    }
                    Section("Free routes") {
                        ForEach(catalog.freeHelp, id: \.title) { item in VStack(alignment: .leading) { Text(item.title).font(.headline); Text(item.answer) } }
                    }
                } else { Text("Catalog unavailable. Do not accept questions until it is restored.") }
                Section("Device privacy") {
                    Text("Questions stay in memory while this app is unlocked. Backgrounding locks the inbox. Your device key is stored only in this iPhone’s Keychain; it is not a Stripe secret.")
                    Button("Remove saved connection", role: .destructive) { inbox.disconnect(); dismiss() }
                }
            }.navigationTitle("Service guide").toolbar { Button("Done") { dismiss() } }
        }
    }
}
