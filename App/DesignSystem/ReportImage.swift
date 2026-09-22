import NetKit
import SwiftUI
import UIKit

/// Draws a report (already masked and filtered, see `ReportFormatter.masked`)
/// as a PNG, in the app's own card style. Self-contained on purpose: it takes
/// plain data, not a live view or the environment, so it can be built off
/// screen for `ImageRenderer`.
@MainActor
enum ReportImage {
    /// A fixed width, portable regardless of the device this runs on (an
    /// iPhone content column, readable when opened on any screen).
    private static let width: CGFloat = 402

    static func pngData(title: String, header: [String], sections: [ReportSection]) -> Data? {
        guard !sections.isEmpty else { return nil }
        let view = ReportImageView(title: title, header: header, sections: sections)
            .frame(width: width)
        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return nil }
        return image.pngData()
    }
}

private struct ReportImageView: View {
    let title: String
    let header: [String]
    let sections: [ReportSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2.bold())
                ForEach(header, id: \.self) { line in
                    Text(line).font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title.uppercased())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(section.rows.enumerated()), id: \.offset) { index, row in
                            rowView(row)
                            if index != section.rows.count - 1 {
                                Divider().padding(.leading, 16)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            }
        }
        .padding(20)
        .background(Color(.systemGroupedBackground))
    }

    private func rowView(_ row: ReportRow) -> some View {
        Group {
            if row.isPreformatted {
                VStack(alignment: .leading, spacing: 4) {
                    if !row.label.isEmpty {
                        Text(row.label).foregroundStyle(.secondary)
                    }
                    Text(row.value).font(.system(.footnote, design: .monospaced))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(row.label)
                    Spacer(minLength: 8)
                    Text(row.value)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }
}
