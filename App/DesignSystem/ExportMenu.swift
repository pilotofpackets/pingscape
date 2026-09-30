import CoreTransferable
import NetKit
import SwiftUI
import UniformTypeIdentifiers

/// A standalone "Share" toolbar button with the three formats as a submenu.
/// For a menu that already exists on the page (the detail pages' "More" menu
/// next to "Copy page"), use `ShareButtons` directly instead, flat in that menu.
struct ExportMenu: View {
    let fileBaseName: String
    let header: [String]
    let sections: [SectionRecord]

    var body: some View {
        Menu {
            ShareButtons(fileBaseName: fileBaseName, header: header, sections: sections)
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share")
    }
}

/// Share as text, image or JSON. All three are a `ShareLink`, which presents the
/// share sheet itself. The buttons sit inside a `Menu`, and a `.sheet` on a view
/// in a menu never shows, because that view is gone once the menu closes. Image
/// and JSON hold real work (rendering, writing a file), which a `Transferable`
/// does only when the share sheet asks for the file, not on every redraw of a
/// page that keeps changing, such as a running tool.
struct ShareButtons: View {
    @Environment(PrivacyMask.self) private var mask
    let fileBaseName: String
    let header: [String]
    let sections: [SectionRecord]

    private var reportSections: [ReportSection] { sections.reportSections }

    var body: some View {
        let title = "Pingscape \(fileBaseName)"
        ShareLink(item: ReportFormatter.text(header: header, sections: reportSections, masked: mask.isMasked)) {
            Label("Share as text", systemImage: "doc.plaintext")
        }
        ShareLink(item: report(as: ReportImageFile.self), preview: SharePreview(title)) {
            Label("Share as image", systemImage: "photo")
        }
        ShareLink(item: report(as: ReportJSONFile.self), preview: SharePreview(title)) {
            Label("Share as JSON", systemImage: "curlybraces")
        }
    }

    private func report<File: ReportFile>(as _: File.Type) -> File {
        File(fileBaseName: fileBaseName, header: header, sections: reportSections, masked: mask.isMasked)
    }
}

/// A report that becomes a file when it is shared. Holds the plain data only
/// (the same masking and filtering as the text) and does nothing until asked.
private protocol ReportFile: Transferable, Sendable {
    var fileBaseName: String { get }
    var header: [String] { get }
    var sections: [ReportSection] { get }
    var masked: Bool { get }
    static var fileExtension: String { get }

    init(fileBaseName: String, header: [String], sections: [ReportSection], masked: Bool)
    @MainActor func data() throws -> Data
}

private extension ReportFile {
    /// Writes the file under a name that says what it is and when it was made.
    @MainActor func sentFile() throws -> SentTransferredFile {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "pingscape-\(fileBaseName)-\(formatter.string(from: Date())).\(Self.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try data().write(to: url, options: .atomic)
        return SentTransferredFile(url)
    }
}

private struct ReportImageFile: ReportFile {
    static let fileExtension = "png"
    let fileBaseName: String
    let header: [String]
    let sections: [ReportSection]
    let masked: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { report in
            try await report.sentFile()
        }
    }

    @MainActor func data() throws -> Data {
        let visible = ReportFormatter.masked(sections, masked: masked)
        guard let data = ReportImage.pngData(title: fileBaseName, header: header, sections: visible) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return data
    }
}

private struct ReportJSONFile: ReportFile {
    static let fileExtension = "json"
    let fileBaseName: String
    let header: [String]
    let sections: [ReportSection]
    let masked: Bool

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { report in
            try await report.sentFile()
        }
    }

    @MainActor func data() throws -> Data {
        try ReportFormatter.json(header: header, sections: sections, masked: masked)
    }
}
