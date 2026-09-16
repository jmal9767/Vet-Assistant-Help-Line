import SwiftUI
import UIKit

struct CompCodeView: View {
    private enum Service: String, CaseIterable, Identifiable {
        case quickEmail = "quick-email"
        case detailedEmail = "detailed-email"
        case quickText = "quick-text"
        case liveText = "live-text"
        case quickCall = "quick-call"
        case fullConsult = "full-consult"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quickEmail: "Quick question — email"
            case .detailedEmail: "Detailed question — email"
            case .quickText: "Quick question — text"
            case .liveText: "Live text chat — 15 minutes"
            case .quickCall: "Quick call — 15 minutes"
            case .fullConsult: "Full consult — 30 minutes"
            }
        }

        var allowsSpeed: Bool {
            switch self {
            case .quickEmail, .detailedEmail, .quickText:
                true
            case .liveText, .quickCall, .fullConsult:
                false
            }
        }
    }

    private enum ReplySpeed: String, CaseIterable, Identifiable {
        case standard
        case sameDay = "same-day"
        case express

        var id: String { rawValue }

        var title: String {
            switch self {
            case .standard: "Standard"
            case .sameDay: "Same-day reply"
            case .express: "Express reply (2–4 hours)"
            }
        }
    }

    private struct CreateResponse: Decodable {
        let ok: Bool
        let code: String
        let serviceLabel: String
        let speedLabel: String
        let expiresAt: Double
        let oneTimeUse: Bool
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    @State private var service: Service = .quickEmail
    @State private var speed: ReplySpeed = .standard
    @State private var expiryDays = 30
    @State private var operatorKey = ""
    @State private var generatedCode: String?
    @State private var generatedDetails: String?
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var isGenerating = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Complimentary access") {
                    Picker("Service", selection: $service) {
                        ForEach(Service.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }

                    if service.allowsSpeed {
                        Picker("Reply speed", selection: $speed) {
                            ForEach(ReplySpeed.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                    }

                    Picker("Expires after", selection: $expiryDays) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("60 days").tag(60)
                        Text("90 days").tag(90)
                    }
                }

                Section("Authorization") {
                    SecureField("Operator key", text: $operatorKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Text("The operator key is used only to authorize creation of a one-time neutral code.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task { await createCode() }
                    } label: {
                        HStack {
                            if isGenerating {
                                ProgressView()
                            }
                            Text(isGenerating ? "Generating…" : "Generate one-time code")
                        }
                    }
                    .disabled(isGenerating || operatorKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let generatedCode {
                    Section("Generated code") {
                        Text(generatedCode)
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .textSelection(.enabled)

                        if let generatedDetails {
                            Text(generatedDetails)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Button("Copy code") {
                            UIPasteboard.general.string = generatedCode
                            statusMessage = "Code copied."
                            isError = false
                        }

                        ShareLink(item: generatedCode) {
                            Label("Share code", systemImage: "square.and.arrow.up")
                        }
                    }
                }

                if let statusMessage {
                    Section {
                        Text(statusMessage)
                            .foregroundStyle(isError ? Color.red : Color.secondary)
                    }
                }
            }
            .navigationTitle("Free Codes")
            .onChange(of: service) { _, newValue in
                if !newValue.allowsSpeed {
                    speed = .standard
                }
            }
        }
    }

    @MainActor
    private func createCode() async {
        guard let baseURL = HelplineConfig.paymentWorkerURL else {
            isError = true
            statusMessage = "The payment worker URL has not been configured."
            return
        }

        isGenerating = true
        generatedCode = nil
        generatedDetails = nil
        statusMessage = nil
        defer { isGenerating = false }

        do {
            let url = baseURL.appending(path: "comp/new")
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(
                "Bearer " + operatorKey.trimmingCharacters(in: .whitespacesAndNewlines),
                forHTTPHeaderField: "Authorization"
            )

            let body: [String: Any] = [
                "service": service.rawValue,
                "speed": service.allowsSpeed ? speed.rawValue : ReplySpeed.standard.rawValue,
                "expiresDays": expiryDays
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            guard (200..<300).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error)
                    ?? "The code could not be created."
                isError = true
                statusMessage = message
                return
            }

            let result = try JSONDecoder().decode(CreateResponse.self, from: data)
            let expiration = Date(timeIntervalSince1970: result.expiresAt / 1000)
            generatedCode = result.code
            generatedDetails = "\(result.serviceLabel) · \(result.speedLabel) · one use · expires \(expiration.formatted(date: .abbreviated, time: .omitted))"
            isError = false
            statusMessage = "Code created."
        } catch {
            isError = true
            statusMessage = "The code could not be created: \(error.localizedDescription)"
        }
    }
}
