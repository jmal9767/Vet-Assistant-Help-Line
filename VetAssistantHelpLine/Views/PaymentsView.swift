import SwiftUI

struct PaymentsView: View {
    @Environment(QuestionStore.self) private var store

    private var paymentQuestions: [ClientQuestion] {
        store.questions
            .filter { $0.paymentStatus != "Reviewing" && !$0.paymentStatus.isEmpty }
            .sorted { $0.submittedAt > $1.submittedAt }
    }

    private var pendingQuestions: [ClientQuestion] {
        paymentQuestions.filter { $0.paymentStatus == "Payment requested" }
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
                            subtitle: "Track the service and payment choice each client made before submitting."
                        ) {
                            HStack(spacing: 10) {
                                MetricPill(title: "Pending", value: "\(pendingQuestions.count)", icon: "clock.fill", tint: AppPalette.warmGold)
                                MetricPill(title: "Paid", value: "\(paidQuestions.count)", icon: "checkmark.circle.fill", tint: AppPalette.clinicGreen)
                                MetricPill(title: "Refunded", value: "\(refundedCount)", icon: "arrow.uturn.backward.circle.fill", tint: AppPalette.brand)
                            }
                        }

                        if paymentQuestions.isEmpty {
                            ContentUnavailableView(
                                "No payment records",
                                systemImage: "creditcard",
                                description: Text("New client-selected services will appear here after submission.")
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

    private var refundedCount: Int {
        paymentQuestions.filter { $0.paymentStatus == "Refunded" }.count
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

                    Text("Client concern")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                    Text(question.question.isEmpty ? "No concern was included." : question.question)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

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
        case "Refunded": "arrow.uturn.backward.circle.fill"
        case "Referred — no charge": "cross.case.fill"
        case "Payment requested": "paperplane.fill"
        default: "clock.fill"
        }
    }

    private var tint: Color {
        switch question.paymentStatus {
        case "Paid": AppPalette.clinicGreen
        case "Refunded": AppPalette.brand
        case "Referred — no charge": AppPalette.brand
        case "Payment requested": AppPalette.warmGold
        default: AppPalette.danger
        }
    }
}

#Preview {
    PaymentsView()
        .environment(QuestionStore())
}
