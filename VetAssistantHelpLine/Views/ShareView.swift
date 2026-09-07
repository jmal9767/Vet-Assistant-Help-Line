import SwiftUI
import CoreImage.CIFilterBuiltins

/// A shareable card that explains the service, lists prices, and shows a
/// QR code that opens the client page.
struct ShareView: View {
    @State private var cardImage: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ShareCard()
                        .padding(.horizontal)

                    if let cardImage {
                        ShareLink(
                            item: cardImage,
                            preview: SharePreview("Vet Assistant Help Line", image: cardImage)
                        ) {
                            Label("Share this card", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                    }

                    Text("Print it, post it, or send it — scanning the QR code opens the help-line page where clients submit questions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Share")
            .task { renderCard() }
        }
    }

    @MainActor
    private func renderCard() {
        let renderer = ImageRenderer(content: ShareCard().frame(width: 400))
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            cardImage = Image(uiImage: uiImage)
        }
    }
}

private struct ShareCard: View {
    // The card is always white (it's meant to be printed and shared), so use
    // fixed ink colors rather than system colors that invert in dark mode.
    private let ink = Color(red: 0.08, green: 0.09, blue: 0.11)
    private let mutedInk = Color(red: 0.24, green: 0.27, blue: 0.32)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "pawprint.fill")
                Text("Vet Assistant Help Line")
                    .font(.title3.bold())
            }
            .foregroundStyle(Color("AccentColor"))

            Text(HelplineConfig.purpose)
                .font(.footnote)
                .foregroundStyle(ink)

            VStack(alignment: .leading, spacing: 3) {
                Text("How it works")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("AccentColor"))
                ForEach(Array(HelplineConfig.howItWorks.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .fontWeight(.semibold)
                        Text(step)
                    }
                    .font(.caption)
                    .foregroundStyle(ink)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("What you can ask")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("AccentColor"))
                ForEach(HelplineConfig.canHelpWith, id: \.self) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•")
                        Text(item)
                    }
                    .font(.caption)
                    .foregroundStyle(ink)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(HelplineConfig.priceMenu) { section in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(section.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color("AccentColor"))
                        ForEach(section.items) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(item.service)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(ink)
                                    Spacer()
                                    Text(item.price)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color("AccentColor"))
                                }
                                Text(item.detail)
                                    .font(.caption2)
                                    .foregroundStyle(mutedInk)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(12)
            .background(Color("AccentColor").opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            HStack(spacing: 14) {
                if let qr = Self.qrImage(for: HelplineConfig.siteURL) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 110, height: 110)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan to see how it works & ask a question")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ink)
                    Text(HelplineConfig.siteURL.absoluteString)
                        .font(.caption2)
                        .foregroundStyle(mutedInk)
                    Text("Standard replies within \(HelplineConfig.responseWindow) — faster options above. No app download needed.")
                        .font(.caption2)
                        .foregroundStyle(mutedInk)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("⚠️ Emergencies can't wait for email")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                Text("Trouble breathing, seizures, bleeding, or possible poisoning — contact an emergency vet immediately. Poison Control: \(HelplineConfig.poisonControlDisplay) (24/7, fee may apply).")
                    .font(.caption2)
                    .foregroundStyle(ink)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

            Text(HelplineConfig.clientDisclaimer)
                .font(.caption2)
                .foregroundStyle(mutedInk)
        }
        .padding(20)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.quaternary)
        )
        .environment(\.colorScheme, .light)
    }

    private static func qrImage(for url: URL) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        // Tint the QR modules with the app accent color so the card matches
        // the printed poster (docs/share-qr.png).
        let colored = CIFilter.falseColor()
        colored.inputImage = output
        colored.color0 = CIColor(color: UIColor(named: "AccentColor") ?? .black)
        colored.color1 = CIColor(red: 1, green: 1, blue: 1)
        guard let tinted = colored.outputImage else { return nil }

        let scaled = tinted.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    ShareView()
}
