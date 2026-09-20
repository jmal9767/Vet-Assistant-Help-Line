import SwiftUI
import CoreImage.CIFilterBuiltins

/// A shareable card that explains the service, lists prices, and shows a
/// QR code that opens the client page.
struct ShareView: View {
    @AppStorage("setup.clientSiteURL") private var clientSiteURL = HelplineConfig.siteURL.absoluteString
    @AppStorage("setup.siteDisplayName") private var siteDisplayName = HelplineConfig.siteDisplayName
    @State private var cardImage: Image?

    private var shareURL: URL {
        URL(string: clientSiteURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? HelplineConfig.siteURL
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HeroPanel(
                            icon: "qrcode.viewfinder",
                            title: "Share the care line",
                            subtitle: "Use this client-facing card for posters, messages, and quick handouts."
                        ) {
                            if let cardImage {
                                ShareLink(
                                    item: cardImage,
                                    preview: SharePreview("Paws & Whiskers Care Line", image: cardImage)
                                ) {
                                    Label("Share Card", systemImage: "square.and.arrow.up")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }

                        ShareCard(siteURL: shareURL, siteDisplayName: siteDisplayName)
                            .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 8)

                        Text("Scanning the QR code opens the public page where clients submit questions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Share")
            .onAppear { migrateLegacyBrandSettings() }
            .task(id: clientSiteURL) { renderCard() }
            .task(id: siteDisplayName) { renderCard() }
        }
    }

    @MainActor
    private func renderCard() {
        let renderer = ImageRenderer(content: ShareCard(siteURL: shareURL, siteDisplayName: siteDisplayName).frame(width: 460))
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            cardImage = Image(uiImage: uiImage)
        }
    }

    private func migrateLegacyBrandSettings() {
        if clientSiteURL.contains("jmal9767.github.io") {
            clientSiteURL = HelplineConfig.siteURL.absoluteString
        }
        if siteDisplayName.contains("Vet Assistant Help Line") {
            siteDisplayName = HelplineConfig.siteDisplayName
        }
    }
}

private struct ShareCard: View {
    let siteURL: URL
    let siteDisplayName: String

    // The card is always white for printing and sharing, so it uses fixed ink colors.
    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let mutedInk = Color(red: 0.30, green: 0.33, blue: 0.38)
    private let line = Color(red: 0.88, green: 0.90, blue: 0.92)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "pawprint.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(AppPalette.brand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Paws & Whiskers Care Line")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(ink)
                    Text("Practical dog-and-cat care guidance")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppPalette.brand)
                }
            }

            Text(HelplineConfig.purpose)
                .font(.footnote)
                .foregroundStyle(ink)
                .lineSpacing(2)

            Divider().overlay(line)

            QRBlock(siteURL: siteURL, siteDisplayName: siteDisplayName)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                CardSectionTitle("How it Works")
                ForEach(Array(HelplineConfig.howItWorks.enumerated()), id: \.offset) { index, step in
                    NumberedLine(number: index + 1, text: step)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                CardSectionTitle("What it Costs")
                Text(HelplineConfig.costExplanation)
                    .font(.caption)
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .background(AppPalette.clinicGreen.opacity(0.09), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            CardSectionTitle("Services")

            VStack(alignment: .leading, spacing: 10) {
                ForEach(HelplineConfig.priceMenu) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppPalette.brand)

                        ForEach(section.items) { item in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(item.service)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ink)
                                    Spacer(minLength: 8)
                                    Text(item.price)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(AppPalette.clinicGreen)
                                }
                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(mutedInk)
                            }
                        }
                    }
                    .padding(10)
                    .background(AppPalette.brand.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                CardSectionTitle("Ask About")
                ForEach(HelplineConfig.canHelpWith, id: \.self) { item in
                    Label(item, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(ink)
                }
            }

            EmergencyNote()

            Text(HelplineConfig.clientDisclaimer)
                .font(.caption2)
                .foregroundStyle(mutedInk)
                .lineSpacing(1)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(line)
        }
        .environment(\.colorScheme, .light)
    }
}

private struct QRBlock: View {
    let siteURL: URL
    let siteDisplayName: String

    var body: some View {
        VStack(spacing: 10) {
            if let qr = ShareCard.qrImage(for: siteURL) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 260, height: 260)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.black.opacity(0.35), lineWidth: 2)
                    }
            }

            Text("Scan to ask a question")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color(red: 0.08, green: 0.09, blue: 0.11))
                .multilineTextAlignment(.center)

            Text(siteDisplayName.isEmpty ? siteURL.absoluteString : siteDisplayName)
                .font(.caption2)
                .foregroundStyle(Color(red: 0.30, green: 0.33, blue: 0.38))
                .multilineTextAlignment(.center)
        }
    }
}

private struct NumberedLine: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(AppPalette.brand, in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(Color(red: 0.08, green: 0.09, blue: 0.11))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CardSectionTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(AppPalette.brand)
    }
}

private struct EmergencyNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Emergencies cannot wait for email")
                .font(.caption.weight(.bold))
                .foregroundStyle(AppPalette.danger)
            Text("Trouble breathing, seizures, bleeding, or possible poisoning: contact an emergency vet immediately. Poison Control: \(HelplineConfig.poisonControlDisplay) (24/7, fee may apply).")
                .font(.caption2)
                .foregroundStyle(Color(red: 0.08, green: 0.09, blue: 0.11))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppPalette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension ShareCard {
    static func qrImage(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    ShareView()
}
