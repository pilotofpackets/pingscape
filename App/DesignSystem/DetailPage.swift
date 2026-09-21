import SwiftUI

/// The frame of a detail page: sections on the grouped background.
///
/// A page whose subject disappears while it is open (Wi-Fi drops, the VPN
/// stops) closes itself instead of showing an empty page.
struct DetailPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: LocalizedStringKey
    var isAvailable = true
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: isAvailable) { _, available in
            if !available { dismiss() }
        }
    }
}

/// A row that leads to another page.
struct LinkRow<Value: Hashable>: View {
    let label: LocalizedStringKey
    var detail: String?
    let value: Value

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 16) {
                Text(label).foregroundStyle(.primary)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
