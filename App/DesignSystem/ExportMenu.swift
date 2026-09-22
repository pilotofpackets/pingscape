import NetKit
import SwiftUI
import UIKit

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

/// Share as text, image or JSON. Text is cheap and reuses the app's own
/// `ShareLink(item:)`. Image and JSON hold real work (rendering, writing a
/// file), so they run only on a tap, not on every redraw of a page that keeps
/// changing, such as a running tool.
struct ShareButtons: View {
    @Environment(PrivacyMask.self) private var mask
    let fileBaseName: String
    let header: [String]
    let sections: [SectionRecord]
    @State private var sharedFile: SharedFile?

    private var reportSections: [ReportSection] { sections.reportSections }

    var body: some View {
        Group {
            ShareLink(item: ReportFormatter.text(header: header, sections: reportSections, masked: mask.isMasked)) {
                Label("Share as text", systemImage: "doc.plaintext")
            }
            Button {
                shareImage()
            } label: {
                Label("Share as image", systemImage: "photo")
            }
            Button {
                shareJSON()
            } label: {
                Label("Share as JSON", systemImage: "curlybraces")
            }
        }
        .sheet(item: $sharedFile) { file in
            ActivityView(items: [file.url])
        }
    }

    private func shareImage() {
        let masked = ReportFormatter.masked(reportSections, masked: mask.isMasked)
        guard let data = ReportImage.pngData(title: fileBaseName, header: header, sections: masked) else { return }
        sharedFile = write(data, extension: "png")
    }

    private func shareJSON() {
        guard let data = try? ReportFormatter.json(header: header, sections: reportSections, masked: mask.isMasked) else {
            return
        }
        sharedFile = write(data, extension: "json")
    }

    private func write(_ data: Data, extension fileExtension: String) -> SharedFile? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "pingscape-\(fileBaseName)-\(formatter.string(from: Date())).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return SharedFile(url: url)
        } catch {
            return nil
        }
    }
}

private struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet, for a file that was just built (`ShareLink` cannot
/// be triggered from code, only tapped, so image and JSON go through this).
private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
