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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let label: LocalizedStringResource
    let value: String
    var monospaced = false
    /// Addresses and network names. Hidden while the mask is on.
    var sensitive = false
    /// Always stack label and value (for long values).
    var stacked = false
    /// A short explanation shown under the value, in the stacked layout only.
    var note: LocalizedStringResource?
    /// A few words added in brackets to the value in a shared report, where
    /// `note` does not go: without it the report read as if the cellular
    /// IPv6 address belonged to the Wi-Fi connection.
    var reportNote: LocalizedStringResource?

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

    /// Each line of `string` broken into two at a ".", ":" or "_" (never through
    /// the middle of an octet or group), for a value that has to wrap.
    /// SwiftUI's own wrapping has no such string to break at and cuts
    /// wherever the width runs out, so this is done by hand instead. Line by
    /// line, because a list of addresses (DNS servers) split once as a whole
    /// broke one address in the middle and left a lone digit on a line. A
    /// line no wider than the halves of the others stays whole: the column
    /// is that wide anyway (an IPv4 server next to IPv6 ones).
    nonisolated static func wrapped(_ string: String) -> String {
        let lines = string.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let split = lines.map(wrappedLine)
        let column = split.flatMap { $0.split(separator: "\n") }.map(\.count).max() ?? 0
        return zip(lines, split).map { line, halves in line.count <= column ? line : halves }
            .joined(separator: "\n")
    }

    /// `string` with an invisible break opportunity after every ".", ":" and
    /// "_", for a value too long even for two lines (the accessibility text
    /// sizes): it then wraps between groups, never inside one ("3C:A6:2F:" /
    /// "1B:D3:22", not "3C:A" / "6:2F"). Only for display; copies, reports
    /// and VoiceOver get the value as it is.
    nonisolated static func breakable(_ string: String) -> String {
        var result = ""
        for character in string {
            result.append(character)
            if character == "." || character == ":" || character == "_" { result.append("\u{200B}") }
        }
        return result
    }

    nonisolated static func wrappedLine(_ string: String) -> String {
        // "_" too: a cipher suite (TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256)
        // otherwise got a hyphen from the system that is not in the name.
        let separators: Set<Character> = [".", ":", "_"]
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
            // At the accessibility sizes label and value do not fit side by
            // side: the label was cut to "Name…" and an address broke after
            // every few characters. Stacked, each gets the full width.
            if stacked || dynamicTypeSize.isAccessibilitySize {
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
        .recordRow(
            label: label, value: reportNote.map { "\(value) (\(String(localized: $0)))" } ?? value,
            sensitive: effectiveSensitive)
    }

    private func valueText(_ string: String) -> some View {
        Text(string)
            // The placeholder in the regular font everywhere: in the monospaced
            // one its dots came out larger, so hidden addresses looked unlike
            // a hidden network name next to them.
            .font(monospaced && string != PrivacyMask.placeholder ? .system(.body, design: .monospaced) : .body)
    }

    /// The value at its normal size on one line if that fits, or — the
    /// value never moves under the label — broken at a "." or ":" and
    /// shrunk a little rather than either overflowing or getting cut with
    /// "…".
    private var adaptiveValue: some View {
        ViewThatFits(in: .horizontal) {
            valueText(shown)
            valueText(Self.wrapped(shown))
                .multilineTextAlignment(.trailing)
                .minimumScaleFactor(0.85)
            // The last resort, used when nothing fits: as many lines as it
            // takes, broken only between groups.
            valueText(Self.breakable(shown))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.subdued)
        // VoiceOver and the UI tests get the value without the line breaks
        // and invisible break points added for display.
        .accessibilityLabel(Text(verbatim: shown))
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
                    .foregroundStyle(.subdued)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row whose value is a status: a dot and a short text. Like `DataRow`, the
/// label shrinks rather than moving the status under it.
struct StatusRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let label: LocalizedStringResource
    let text: String
    var tone: StatusDot.Tone = .good
    /// A refresh button at the end of the row, for a status that can be checked
    /// again. Keeps it in this row instead of a second row with the same label.
    /// Only a symbol, so it fits next to the status in every language; the
    /// title is what VoiceOver reads.
    var action: (title: LocalizedStringResource, perform: () -> Void)?

    private var status: some View {
        HStack(spacing: 8) {
            StatusDot(tone: tone)
            Text(text)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if let action {
            Button(action: action.perform) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel(Text(action.title))
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Side by side the label was cut off at the largest sizes.
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        status
                        Spacer(minLength: 0)
                        actionButton
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(label)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    status
                    actionButton
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .contextMenu { RowCopyMenu(value: text) }
        // With a button, VoiceOver must still reach it on its own.
        .accessibilityElement(children: action == nil ? .combine : .contain)
        .recordRow(label: label, value: text)
    }
}

/// A row that asks for a permission.
struct PermissionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let label: LocalizedStringResource
    let buttonTitle: LocalizedStringResource
    /// Why a previous attempt failed, shown under the label so a retry that
    /// fails again reads differently from a tap that did nothing.
    var detail: String?
    let action: () -> Void

    private var button: some View {
        Button(action: action) {
            Text(buttonTitle).multilineTextAlignment(.leading)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(dynamicTypeSize.isAccessibilitySize ? .roundedRectangle : .capsule)
        // Next to a long detail it was squeezed into a tall empty capsule, so
        // it keeps its width. Not at the accessibility sizes: there "Measure
        // response time" grew wider than the screen and pushed the whole page
        // off its left edge; under the label it may wrap instead.
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
    }

    private var labelStack: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
            if let detail {
                Text(detail).font(.footnote).foregroundStyle(.subdued)
            }
        }
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    labelStack
                    button
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 16) {
                    labelStack
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    button
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
    }
}
