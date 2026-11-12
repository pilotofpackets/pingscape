import UIKit
import XCTest

/// Measures contrast in a screenshot, as a second opinion on the audit's
/// contrast findings: the audit flagged text that measured 6:1 in its own
/// pixels, and once measured next to the text (its frame lay partly off
/// the screen). A finding counts only when both agree.
struct PixelContrast {
    private let pixels: [UInt8]
    private let width: Int
    private let height: Int
    private let scale: CGFloat

    init?(_ screenshot: XCUIScreenshot) {
        let image = screenshot.image
        guard let cgImage = image.cgImage else { return nil }
        let w = cgImage.width, h = cgImage.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        width = w
        height = h
        scale = image.size.width > 0 ? CGFloat(w) / image.size.width : image.scale
        pixels = buffer
    }

    /// The contrast between the text and the background inside `frame`
    /// (points): the background is the most common brightness, the text the
    /// one farthest from it. `nil` when the frame is not on the screenshot.
    func ratio(in frame: CGRect) -> Double? {
        let pixelFrame = CGRect(
            x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !pixelFrame.isNull, pixelFrame.width >= 2, pixelFrame.height >= 2,
            pixelFrame.width * pixelFrame.height >= frame.width * frame.height * scale * scale * 0.9
        else { return nil }
        var values: [Double] = []
        values.reserveCapacity(Int(pixelFrame.width * pixelFrame.height))
        for y in Int(pixelFrame.minY)..<Int(pixelFrame.maxY) {
            for x in Int(pixelFrame.minX)..<Int(pixelFrame.maxX) {
                let i = (y * width + x) * 4
                values.append(
                    Self.luminance(Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255))
            }
        }
        values.sort()
        let background = values[values.count / 2]
        let text = abs(values.first! - background) > abs(values.last! - background) ? values.first! : values.last!
        return (max(text, background) + 0.05) / (min(text, background) + 0.05)
    }

    static func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func linear(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
