import SwiftUI

/// One label and one value.
///
/// The label sits left and the value right, and stays there: if they do not
/// fit on one line, the label shrinks and the value wraps onto more lines,
/// but the value never moves under the label. `stacked` opts a row with a
/// long value (a full IPv6 address) into a layout with the label on its own
/// line above, for a value that needs the full row width to read
/// comfortably — but the value still hugs the right edge, wrapping onto more
/// lines as needed. Values are never truncated. Long press copies a value,
/// or hides just that one (independent of the "Hide values" toggle).
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

    /// `string` broken into two lines at a "." or ":" (never through the
    /// middle of an octet or group), for a value that has to wrap. SwiftUI's
    /// own wrapping has no such string to break at and cuts wherever the
    /// width runs out, so this is done by hand instead.
    private func wrapped(_ string: String) -> String {
        let separators: Set<Character> = [".", ":"]
        var segments: [String] = []
        var current = ""
        for character in string {
            current.append(character)
            if separators.contains(character) {
                segments.append(current)
                current = ""
            }
        }
        if !current.isEmpty { segments.append(current) }
        guard segments.count > 1 else { return string }
        let firstLineCount = Int((Double(segments.count) / 2).rounded(.up))
        return segments[..<firstLineCount].joined() + "\n" + segments[firstLineCount...].joined()
    }

    var body: some View {
        Group {
            if stacked {
                stackedLayout
            } else {
                inlineLayout
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

    private func valueText(_ string: String) -> some View {
        Text(string)
            .font(monospaced ? .system(.body, design: .monospaced) : .body)
    }

    /// The value at its normal size on one line if that fits, or — the
    /// value never moves under the label — broken at a "." or ":" and
    /// shrunk a little rather than either overflowing or getting cut with
    /// "…".
    private var adaptiveValue: some View {
        ViewThatFits(in: .horizontal) {
            valueText(shown)
            valueText(wrapped(shown))
                .multilineTextAlignment(.trailing)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(.secondary)
    }

    private var inlineLayout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            adaptiveValue
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                adaptiveValue
                    .fixedSize(horizontal: false, vertical: true)
            }
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

/// A row whose value is a status: a dot and a short text. Like `DataRow`, the
/// label shrinks rather than moving the status under it.
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
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .layoutPriority(1)
            Spacer(minLength: 8)
            status
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
        HStack(spacing: 16) {
            labelStack
                .layoutPriority(1)
            Spacer(minLength: 8)
            button
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
    }
}
