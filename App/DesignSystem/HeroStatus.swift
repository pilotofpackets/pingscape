import SwiftUI

/// The status card at the top of the overview: the one place with glass
/// inside the content.
struct HeroStatus: View {
    let title: LocalizedStringKey
    let subtitle: String?
    let tone: StatusDot.Tone
    let systemImage: String
    let chips: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StatusDot(tone: tone).scaleEffect(1.3)
                Text(title).font(.title2.bold())
                Spacer(minLength: 8)
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let subtitle {
                Text(subtitle).foregroundStyle(.secondary)
            }
            if !chips.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        Label(chip, systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(cornerRadius: 30)
        .accessibilityElement(children: .combine)
    }
}
