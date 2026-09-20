import SwiftUI

struct InboxView: View {
    @Environment(QuestionStore.self) private var store
    @State private var selectedFilter: QuestionFilter = .new
    @State private var searchText = ""
    @State private var path: [String] = []

    private enum QuestionFilter: String, CaseIterable, Identifiable {
        case new = "New"
        case answered = "Answered"
        case archived = "Archived"
        case all = "All"
        var id: String { rawValue }
    }

    private var filteredQuestions: [ClientQuestion] {
        let source: [ClientQuestion]
        switch selectedFilter {
        case .new: source = store.newQuestions
        case .answered: source = store.answeredQuestions
        case .archived: source = store.archivedQuestions
        case .all: source = store.questions
        }
        guard !searchText.isEmpty else { return source }
        return source.filter {
            [$0.name, $0.petName, $0.species, $0.category, $0.question]
                .contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        @Bindable var store = store
        NavigationStack(path: $path) {
            ZStack {
                AppPalette.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        overview
                        Picker("Question status", selection: $selectedFilter) {
                            ForEach(QuestionFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        questionContent
                    }
                    .padding(16)
                }
                .refreshable { await store.refresh() }
            }
            .navigationTitle("Inbox")
            .searchable(text: $searchText, prompt: "Client, pet, or question")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refresh() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }
            }
            .navigationDestination(for: String.self) { recordName in
                if let question = store.question(recordName: recordName) {
                    QuestionDetailView(question: question)
                } else {
                    ContentUnavailableView("Question unavailable", systemImage: "questionmark.folder")
                }
            }
            .task {
                await store.refresh()
                await store.ensureSubscription()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openQuestionFromPush)) { notification in
                guard let recordName = notification.object as? String else { return }
                Task {
                    await store.refresh()
                    if store.question(recordName: recordName) != nil { path = [recordName] }
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: { Text(store.errorMessage ?? "") }
        }
    }

    private var overview: some View {
        HeroPanel(icon: "stethoscope", title: "Client queue", subtitle: "Review questions, choose free or paid service, reply, and archive completed cases.") {
            HStack(spacing: 10) {
                MetricPill(title: "New", value: "\(store.newQuestions.count)", icon: "bell.fill", tint: AppPalette.warmGold)
                MetricPill(title: "Answered", value: "\(store.answeredQuestions.count)", icon: "checkmark.circle.fill", tint: AppPalette.clinicGreen)
                MetricPill(title: "Archived", value: "\(store.archivedQuestions.count)", icon: "archivebox.fill", tint: AppPalette.brand)
            }
        }
    }

    @ViewBuilder
    private var questionContent: some View {
        if store.isLoading && store.questions.isEmpty && store.archivedQuestions.isEmpty {
            ProgressView("Loading questions…").padding(.top, 36)
        } else if filteredQuestions.isEmpty {
            ContentUnavailableView(
                searchText.isEmpty ? "No \(selectedFilter.rawValue.lowercased()) questions" : "No matches",
                systemImage: selectedFilter == .archived ? "archivebox" : "tray",
                description: Text(searchText.isEmpty ? "Pull down to check again." : "Try a different search.")
            ).padding(.top, 28)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredQuestions) { question in
                    NavigationLink(value: question.id.recordName) { QuestionRow(question: question) }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            if question.status == .archived {
                                Button("Restore") { Task { await store.setStatus(.new, for: question) } }
                                    .tint(AppPalette.clinicGreen)
                            } else {
                                Button("Archive") { Task { await store.setStatus(.archived, for: question) } }
                                    .tint(AppPalette.brand)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if question.status != .archived {
                                Button(question.status == .new ? "Answered" : "Reopen") {
                                    Task { await store.setStatus(question.status == .new ? .answered : .new, for: question) }
                                }
                                .tint(question.status == .new ? AppPalette.clinicGreen : AppPalette.warmGold)
                            }
                        }
                }
            }
        }
    }
}

private struct QuestionRow: View {
    let question: ClientQuestion
    var body: some View {
        InfoTile {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.headline.weight(.semibold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(question.name).font(.headline).lineLimit(1)
                        Spacer()
                        Text(question.submittedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(question.petName) · \(question.species) · \(question.preferredReply)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(question.question).font(.subheadline).lineLimit(2)
                    HStack {
                        Label(question.paymentStatus, systemImage: question.isComplimentary ? "gift.fill" : "creditcard")
                        if !question.attachments.isEmpty { Label("\(question.attachments.count)", systemImage: "paperclip") }
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(tint)
                }
            }
        }
    }
    private var tint: Color {
        switch question.status { case .new: AppPalette.warmGold; case .answered: AppPalette.clinicGreen; case .archived: AppPalette.brand }
    }
    private var icon: String {
        switch question.status { case .new: "bell.fill"; case .answered: "checkmark.circle.fill"; case .archived: "archivebox.fill" }
    }
}

#Preview { InboxView().environment(QuestionStore()) }
