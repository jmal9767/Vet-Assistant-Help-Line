import SwiftUI

struct InboxView: View {
    @Environment(QuestionStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                if store.questions.isEmpty {
                    if store.isLoading {
                        ProgressView("Checking for questions…")
                    } else {
                        ContentUnavailableView(
                            "No questions yet",
                            systemImage: "tray",
                            description: Text("Client questions from the website will show up here. Pull down to check again.")
                        )
                    }
                } else {
                    questionList
                }
            }
            .navigationTitle("Inbox")
            .refreshable { await store.refresh() }
            .task {
                await store.refresh()
                await store.ensureSubscription()
            }
            .alert("Something went wrong",
                   isPresented: Binding(
                       get: { store.errorMessage != nil },
                       set: { if !$0 { store.errorMessage = nil } }
                   )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }

    private var questionList: some View {
        List {
            if !store.newQuestions.isEmpty {
                Section("New") {
                    ForEach(store.newQuestions) { question in
                        row(for: question)
                    }
                }
            }
            if !store.answeredQuestions.isEmpty {
                Section("Answered") {
                    ForEach(store.answeredQuestions) { question in
                        row(for: question)
                    }
                }
            }
        }
    }

    private func row(for question: ClientQuestion) -> some View {
        NavigationLink {
            QuestionDetailView(question: question)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(question.name)
                        .font(.headline)
                    Spacer()
                    Text(question.submittedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("\(question.species) · \(question.category)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(question.question)
                    .font(.subheadline)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .leading) {
            if question.status == .new {
                Button {
                    Task { await store.setStatus(.answered, for: question) }
                } label: {
                    Label("Answered", systemImage: "checkmark.circle.fill")
                }
                .tint(.green)
            } else {
                Button {
                    Task { await store.setStatus(.new, for: question) }
                } label: {
                    Label("Mark New", systemImage: "arrow.uturn.backward.circle.fill")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                Task { await store.setStatus(.archived, for: question) }
            } label: {
                Label("Archive", systemImage: "archivebox.fill")
            }
        }
    }
}

#Preview {
    InboxView()
        .environment(QuestionStore())
}
