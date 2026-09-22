import NetKit
import SwiftUI

/// The frame of a detail page: sections on the grouped background.
///
/// A page whose subject disappears while it is open (Wi-Fi drops, the VPN
/// stops) closes itself instead of showing an empty page.
struct DetailPage<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PrivacyMask.self) private var mask
    @State private var sections: [SectionRecord] = []

    let title: LocalizedStringResource
    var isAvailable = true
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                content
            }
            .readableContentWidth()
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(title))
        .navigationBarTitleDisplayMode(.inline)
        .onPreferenceChange(SectionRecordsKey.self) { sections = $0 }
        .toolbar {
            if !sections.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            Pasteboard.copy(
                                ReportFormatter.text(header: [], sections: sections.reportSections, masked: mask.isMasked))
                        } label: {
                            Label("Copy page", systemImage: "doc.on.doc")
                        }
                        ShareButtons(fileBaseName: pageFileName, header: [], sections: sections)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .onChange(of: isAvailable) { _, available in
            if !available { dismiss() }
        }
    }

    /// A file-name-safe version of the page title, for the exported file.
    private var pageFileName: String {
        String(localized: title).lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, char in
                if char != "-" || result.last != "-" { result.append(char) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
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
