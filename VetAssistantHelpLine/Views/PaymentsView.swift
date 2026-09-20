import SwiftUI

struct PaymentsView: View {
    @Environment(QuestionStore.self) private var store

    private var paymentQuestions: [ClientQuestion] {
        store.questions.sorted { $0.submittedAt > $1.submittedAt }
    }

    private var pendingQuestions: [ClientQuestion] {
        paymentQuestions.filter { !["Paid", "Refunded", "Complimentary"].contains($0.paymentStatus) }
    }

    private var paidQuestions: [ClientQuestion] {
        paymentQuestions.filter { $0.paymentStatus == "Paid" }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HeroPanel(
                            icon: "creditcard.fill",
                            title: "Payments",
                            subtitle: "Track service price, payment links, signatures, and paid cases from inside the app."
                        ) {
                            HStack(spacing: 10) {
                                MetricPill(title: "Pending", value: "\(pendingQuestions.count)", icon: "clock.fill", tint: AppPalette.warmGold)
                                MetricPill(title: "Paid", value: "\(paidQuestions.count)", icon: "checkmark.circle.fill", tint: AppPalette.clinicGreen)
                                MetricPill(title: "Free", value: "\(complimentaryCount)", icon: "gift.fill", tint: AppPalette.brand)
                            }
                        }

                        if paymentQuestions.isEmpty {
                            ContentUnavailableView(
                                "No payment records",
                                systemImage: "creditcard",
                                description: Text("Client submissions will appear here after they arrive.")
                            )
                            .padding(.top, 24)
                        } else {
                            LazyVStack(spacing: 12) {
                                ForEach(paymentQuestions) { question in
                                    NavigationLink {
                                        QuestionDetailView(question: question)
                                    } label: {
                                        PaymentRow(question: question)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await store.refresh() }
            }
            .navigationTitle("Payments")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(store.isLoading)
                }
            }
            .task { await store.refresh() }
        }
    }

    private var complimentaryCount: Int {
        paymentQuestions.filter { $0.paymentStatus == "Complimentary" }.count
    }
}

private struct PaymentRow: View {
    let question: ClientQuestion

    var body: some View {
        InfoTile {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(question.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 10)
                        Text(question.paymentAmount)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(tint)
                    }

                    Text(question.requestedService)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(question.paymentMethod)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Label(question.paymentStatus, systemImage: iconName)
                        if question.signedConsentName != nil {
                            Label("Signed", systemImage: "signature")
                        } else {
                            Label("Unsigned", systemImage: "signature")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                }
            }
        }
    }

    private var iconName: String {
        switch question.paymentStatus {
        case "Paid": "checkmark.circle.fill"
        case "Complimentary": "gift.fill"
        case "Refunded": "arrow.uturn.backward.circle.fill"
        case "Payment requested": "paperplane.fill"
        default: "clock.fill"
        }
    }

    private var tint: Color {
        switch question.paymentStatus {
        case "Paid": AppPalette.clinicGreen
        case "Complimentary": AppPalette.clinicGreen
        case "Refunded": AppPalette.brand
        case "Payment requested": AppPalette.warmGold
        default: AppPalette.danger
        }
    }
}

#Preview {
    PaymentsView()
        .environment(QuestionStore())
}
