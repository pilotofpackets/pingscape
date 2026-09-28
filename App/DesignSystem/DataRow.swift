import SwiftUI

/// One label and one value.
///
/// The label sits left and the value right. If they do not fit on one line
/// (large text, a long IPv6 address) the label moves above the value, which
/// then wraps. Values are never truncated. Long press copies a value, or
/// hides just that one (independent of the "Hide values" toggle).
struct DataRow: View {
    @Environment(PrivacyMask.self) private var mask

    let label: LocalizedStringResource
    let value: String
    var monospaced = false
    /// Addresses and network names. Hidden while the mask is on.
    var sensitive = false
    /// Always stack label and value (for long values).
    var stacked = false
    /// A short explanation shown under the value, in the stacked layout only.
    var note: LocalizedStringResource?

    /// "Not available", "Off", "On": the state of a field that would be
    /// sensitive if it had a value (External IPv6, Proxy, …). Masked along
    /// with the sensitive rows even where the row itself is not marked
    /// `sensitive`, so a masked screenshot does not single out which optional
    /// values are absent or which switches are on.
    private static let maskedStates: Set<String> = [
        String(localized: "Not available"),
        String(localized: "Off"),
        String(localized: "On"),
    ]

    private var labelKey: String { String(localized: label) }

    private var isIndividuallyHidden: Bool {
        mask.isIndividuallyHidden(label: labelKey, value: value)
    }

    private var effectiveSensitive: Bool {
        sensitive || Self.maskedStates.contains(value)
    }

    private var shown: String {
        isIndividuallyHidden ? PrivacyMask.placeholder : (effectiveSensitive ? mask.shown(value) : value)
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
        .contextMenu {
            RowCopyMenu(value: value)
            Button {
                mask.toggleIndividuallyHidden(label: labelKey, value: value)
            } label: {
                if isIndividuallyHidden {
                    Label("Show value", systemImage: "eye")
                } else {
                    Label("Hide value", systemImage: "eye.slash")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .recordRow(label: label, value: value, sensitive: effectiveSensitive)
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
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let note {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
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
    /// Why a previous attempt failed, shown under the label so a retry that
    /// fails again reads differently from a tap that did nothing.
    var detail: String?
    let action: () -> Void

    private var button: some View {
        Button(buttonTitle, action: action)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
    }

    private var labelStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                labelStack
                Spacer(minLength: 8)
                button
            }
            VStack(alignment: .leading, spacing: 8) {
                labelStack
                button
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
    }
}
