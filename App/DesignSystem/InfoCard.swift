import NetKit
import SwiftUI

/// A titled group of rows on a plain, opaque surface.
///
/// With `details:` the header gets a "Details ›" link that pushes the value
/// onto the enclosing `NavigationStack`.
struct InfoSection<Trailing: View, Content: View>: View {
    @Environment(PrivacyMask.self) private var mask
    @State private var rows: [RowRecord] = []
    @State private var sectionID = UUID()

    let title: LocalizedStringResource
    /// Marks the card as the one that actually governs the connection right
    /// now (a VPN with a full tunnel): a colored border, nothing else changes.
    var prominent = false
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 16)
            InfoCard(prominent: prominent) { content }
                .environment(\.copySection, CopySectionAction(id: sectionID, perform: copy))
                .onPreferenceChange(RowRecordsKey.self) { rows = $0 }
                // The rows belong to this section and go no further up.
                .transformPreference(RowRecordsKey.self) { $0 = [] }
                .preference(key: SectionRecordsKey.self, value: rows.isEmpty ? [] : [record])
        }
    }

    private var record: SectionRecord {
        SectionRecord(title: String(localized: title), rows: rows)
    }

    private func copy() {
        Pasteboard.copy(ReportFormatter.text(of: record.reportSection, masked: mask.isMasked))
    }
}

extension SectionRecord {
    var reportSection: ReportSection {
        ReportSection(
            title: title,
            rows: rows.map {
                ReportRow(label: $0.label, value: $0.value, isSensitive: $0.sensitive, isPreformatted: $0.preformatted)
            })
    }
}

extension InfoSection where Trailing == EmptyView {
    init(title: LocalizedStringResource, prominent: Bool = false, @ViewBuilder content: () -> Content) {
        self.init(title: title, prominent: prominent, trailing: { EmptyView() }, content: content)
    }
}

extension InfoSection {
    init<Value: Hashable>(
        title: LocalizedStringResource, details value: Value, prominent: Bool = false,
        @ViewBuilder content: () -> Content
    ) where Trailing == DetailsLink<Value> {
        self.init(title: title, prominent: prominent, trailing: { DetailsLink(value: value) }, content: content)
    }
}

/// "Details ›", the link in a section header.
struct DetailsLink<Value: Hashable>: View {
    let value: Value

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 3) {
                Text("Details")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            // A comfortable tap target without making the header taller.
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .padding(.vertical, -10)
    }
}

/// Rows with separators between them, on a rounded surface.
struct InfoCard<Content: View>: View {
    var prominent = false
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    subview
                    if subview.id != subviews.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            if prominent {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.tint, lineWidth: 2)
            }
        }
    }
}
