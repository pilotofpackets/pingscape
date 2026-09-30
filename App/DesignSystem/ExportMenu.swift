import NetKit
import Photos
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
///
/// They cannot be a `ShareLink` with a `Transferable` (the system asks for the
/// file on the main thread and waits, which hangs the app while the export
/// waits for the main actor, and Photos does not take the file as an image),
/// nor a `.sheet` on a view in this menu (that view is gone once the menu
/// closes). So the share sheet is presented from UIKit, on the top controller.
struct ShareButtons: View {
    @Environment(PrivacyMask.self) private var mask
    let fileBaseName: String
    let header: [String]
    let sections: [SectionRecord]

    private var reportSections: [ReportSection] { sections.reportSections }

    var body: some View {
        ShareLink(item: ReportFormatter.text(header: header, sections: reportSections, masked: mask.isMasked)) {
            Label("Share as text", systemImage: "doc.plaintext")
        }
        Button {
            shareImage()
        } label: {
            Label("Share as image", systemImage: "photo")
        }
        Button {
            saveImage()
        } label: {
            Label("Save image to Photos", systemImage: "square.and.arrow.down")
        }
        Button {
            shareJSON()
        } label: {
            Label("Share as JSON", systemImage: "curlybraces")
        }
    }

    private func renderImage() -> Data? {
        let masked = ReportFormatter.masked(reportSections, masked: mask.isMasked)
        return ReportImage.pngData(title: fileBaseName, header: header, sections: masked)
    }

    private func shareImage() {
        guard let data = renderImage(), let image = UIImage(data: data), let url = write(data, extension: "png") else {
            return
        }
        ActivitySheet.present(ImageItem(image: image, url: url))
    }

    /// Its own item, not only the share sheet's "Save Image": iOS drops that one
    /// from the sheet once Photos access is refused, and then nothing would say why.
    private func saveImage() {
        guard let data = renderImage(), let url = write(data, extension: "png") else { return }
        Task { await PhotoSaver.save(url) }
    }

    private func shareJSON() {
        guard let data = try? ReportFormatter.json(header: header, sections: reportSections, masked: mask.isMasked) else {
            return
        }
        guard let url = write(data, extension: "json") else { return }
        ActivitySheet.present(url)
    }

    private func write(_ data: Data, extension fileExtension: String) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let name = "pingscape-\(fileBaseName)-\(formatter.string(from: Date())).\(fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// An image for the share sheet: the image for "Save Image", copy, print and
/// the like, and the file (with its name) for everything else, such as AirDrop
/// and Messages. The sheet offers "Save Image" only for an image, not a file.
private final class ImageItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let url: URL

    init(image: UIImage, url: URL) {
        self.image = image
        self.url = url
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { image }

    func activityViewController(_ controller: UIActivityViewController, itemForActivityType type: UIActivity.ActivityType?) -> Any? {
        switch type {
        case .saveToCameraRoll, .copyToPasteboard, .assignToContact, .print: image
        default: url
        }
    }
}

/// Saves a file to Photos, asking for the add-only permission first. After a
/// refusal iOS asks no more, so it says why and leads to Settings. Opens Photos
/// once the image is saved; iOS has no call to open one photo without read
/// access to the library.
@MainActor
private enum PhotoSaver {
    static func save(_ url: URL) async {
        switch await PHPhotoLibrary.requestAuthorization(for: .addOnly) {
        case .authorized, .limited:
            if await add(url) { openPhotos() }
        case .denied:
            ActivitySheet.offerSettings()
        default:
            break
        }
    }

    /// Not on the main actor: Photos runs the change block on its own queue, and
    /// a block made on the main actor would trap there.
    private nonisolated static func add(_ url: URL) async -> Bool {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
            }
            return true
        } catch {
            return false
        }
    }

    static func openPhotos() {
        if let photos = URL(string: "photos-redirect://") { UIApplication.shared.open(photos) }
    }
}

/// The system share sheet for a file or image that was just built, presented
/// from the top view controller of the active window.
@MainActor
private enum ActivitySheet {
    static func present(_ item: Any) {
        guard let top = topController() else { return }
        let controller = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        // On an iPad the share sheet is a popover and needs an anchor: the
        // top right, where the toolbar button is.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.maxX - 44, y: top.view.safeAreaInsets.top, width: 1, height: 1)
            popover.permittedArrowDirections = .up
        }
        controller.completionWithItemsHandler = { type, completed, _, _ in
            if type == .saveToCameraRoll, completed { PhotoSaver.openPhotos() }
        }
        top.present(controller, animated: true)
    }

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = scene.keyWindow ?? scene.windows.first,
              var top = window.rootViewController
        else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// Says why the image was not saved and leads to Settings.
    static func offerSettings() {
        guard let top = topController() else { return }
        let alert = UIAlertController(
            title: String(localized: "Photos access is off"),
            message: String(localized: "To save the image, Pingscape needs to be allowed to add to your photos. Allow it in Settings."),
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Open Settings"), style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        })
        top.present(alert, animated: true)
    }
}
