import SwiftUI

/// One label and one value.
///
/// The label sits left and the value right. If they do not fit on one line
/// (large text, a long IPv6 address) the label moves above the value, which
/// then wraps. Values are never truncated. Long press copies a value.
struct DataRow: View {
    @Environment(PrivacyMask.self) private var mask

    let label: LocalizedStringResource
    let value: String
    var monospaced = false
    /// Addresses and network names. Hidden while the mask is on.
    var sensitive = false
    /// Always stack label and value (for long values).
    var stacked = false

    private var shown: String {
        sensitive ? mask.shown(value) : value
    }

    var body: some View {
        Group {
            if stacked {
                stackedLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    inlineLayout
                    stackedLayout
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu { RowCopyMenu(value: value) }
        .accessibilityElement(children: .combine)
        .recordRow(label: label, value: value, sensitive: sensitive)
    }

    private var valueText: some View {
        Text(shown)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
    }

    private var inlineLayout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
            Spacer(minLength: 8)
            valueText
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        // Wrap to a second line rather than cut a value with "…".
        .fixedSize(horizontal: false, vertical: true)
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            valueText
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row whose value is a status: a dot and a short text. Like `DataRow`, it
/// stacks label above status when they do not fit on one line.
struct StatusRow: View {
    let label: LocalizedStringResource
    let text: String
    var tone: StatusDot.Tone = .good

    private var status: some View {
        HStack(spacing: 8) {
            StatusDot(tone: tone)
            Text(text)
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label)
                Spacer(minLength: 8)
                status
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu { RowCopyMenu(value: text) }
        .accessibilityElement(children: .combine)
        .recordRow(label: label, value: text)
    }
}

/// A row that asks for a permission.
struct PermissionRow: View {
    let label: LocalizedStringResource
    let buttonTitle: LocalizedStringResource
    let action: () -> Void

    private var button: some View {
        Button(buttonTitle, action: action)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text(label)
                Spacer(minLength: 8)
                button
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(label)
                button
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
    }
}
