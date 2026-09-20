import SwiftUI

extension View {
    /// Liquid Glass for the control layer: the hero card and floating buttons.
    /// Data rows stay on plain surfaces so they remain easy to read.
    ///
    /// This is the only place that checks the OS version for glass.
    func glassSurface(cornerRadius: CGFloat = 28) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
    }
}

private struct GlassSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background(Color(.secondarySystemGroupedBackground), in: shape)
                .overlay(shape.strokeBorder(.separator))
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        }
    }
}
