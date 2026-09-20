import SwiftUI

struct ReferenceView: View {
    private let redFlags = [
        "Difficulty breathing",
        "Seizures or collapse",
        "Suspected poisoning",
        "Hit by a car or major trauma",
        "Bloated belly or unproductive retching",
        "Unable to urinate, especially male cats",
        "Pale or blue gums",
        "Uncontrolled bleeding",
        "Heatstroke symptoms",
        "Eye injury",
        "Prolonged labor or birthing trouble",
        "Snake or spider bite"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                AppPalette.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        HeroPanel(
                            icon: "cross.case.fill",
                            title: "Emergency reference",
                            subtitle: "When a red flag appears, send the client to emergency care before answering by email.",
                            tint: AppPalette.danger
                        ) {
                            Link(destination: HelplineConfig.emergencyVetLocatorURL) {
                                Label("Open Emergency Vet Locator", systemImage: "location.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(AppPalette.danger)
                        }

                        InfoTile {
                            SectionHeader("Red-Flag Signs", subtitle: "Do not wait on asynchronous care-line replies for these.")

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                                ForEach(redFlags, id: \.self) { flag in
                                    HStack(alignment: .top, spacing: 8) {
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundStyle(AppPalette.danger)
                                        Text(flag)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(AppPalette.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }

                        InfoTile {
                            SectionHeader("Client Resources", subtitle: "Fast links for messages and phone calls.")

                            Link(destination: URL(string: "tel:\(HelplineConfig.poisonControlNumber)")!) {
                                Label("Poison Control \(HelplineConfig.poisonControlDisplay)", systemImage: "phone.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)

                            Link(destination: HelplineConfig.emergencyVetLocatorURL) {
                                Label("Emergency Vet Locator", systemImage: "map.fill")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)

                            Text("ASPCA Animal Poison Control is available 24/7. A consultation fee may apply.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Reference")
        }
    }
}

#Preview {
    ReferenceView()
}
