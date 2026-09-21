import NetKit
import SwiftUI
import UIKit

/// What a row shows, as text. Rows report themselves upward, so a section or a
/// page can be copied and the overview can be shared as a report that holds
/// exactly the rows on screen and nothing else.
struct RowRecord: Equatable {
    let label: String
    let value: String
    let sensitive: Bool
    var preformatted = false
}

struct SectionRecord: Equatable {
    let title: String
    let rows: [RowRecord]
}

struct RowRecordsKey: PreferenceKey {
    static let defaultValue: [RowRecord] = []

    static func reduce(value: inout [RowRecord], nextValue: () -> [RowRecord]) {
        value += nextValue()
    }
}

struct SectionRecordsKey: PreferenceKey {
    static let defaultValue: [SectionRecord] = []

    static func reduce(value: inout [SectionRecord], nextValue: () -> [SectionRecord]) {
        value += nextValue()
    }
}

/// Copies the section a row is in. Two actions of the same section are equal,
/// so a new closure on every update does not redraw all the rows.
struct CopySectionAction: Equatable {
    let id: UUID
    let perform: () -> Void

    static func == (lhs: CopySectionAction, rhs: CopySectionAction) -> Bool { lhs.id == rhs.id }
}

extension EnvironmentValues {
    /// Set by `InfoSection`.
    @Entry var copySection: CopySectionAction?
}

extension View {
    /// Reports the row as text. A row without a value reports nothing.
    func recordRow(label: LocalizedStringResource, value: String, sensitive: Bool = false) -> some View {
        preference(
            key: RowRecordsKey.self,
            value: value.isEmpty ? [] : [RowRecord(label: String(localized: label), value: value, sensitive: sensitive)])
    }
}

extension [SectionRecord] {
    var reportSections: [ReportSection] {
        map { section in
            ReportSection(
                title: section.title,
                rows: section.rows.map {
                    ReportRow(label: $0.label, value: $0.value, isSensitive: $0.sensitive, isPreformatted: $0.preformatted)
                })
        }
    }
}

@MainActor
enum Pasteboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

/// The menu of a long press on a row: the value as it is (also while values
/// are hidden, because whoever copies one value means it) and the section.
struct RowCopyMenu: View {
    @Environment(\.copySection) private var copySection
    let value: String

    var body: some View {
        Button {
            Pasteboard.copy(value)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        if let copySection {
            Button {
                copySection.perform()
            } label: {
                Label("Copy section", systemImage: "list.bullet.rectangle")
            }
        }
    }
}
