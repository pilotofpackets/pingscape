import SwiftUI

extension ShapeStyle where Self == Color {
    /// Text and symbols on an accent-filled surface (prominent buttons, the
    /// selected chip). White in light mode. In dark mode the accent turns
    /// light, and white on it falls to about 2:1, so this turns dark there.
    ///
    /// Set it on the label itself: `.borderedProminent` paints its label white
    /// and wins over a style set outside the button.
    static var onAccent: Color { Color("AccentForeground", bundle: .pingscapeResources) }
}

extension ShapeStyle where Self == Color {
    /// Secondary text that still reads well. The system's secondary label
    /// color reaches only about 3.4:1 on white, under the 4.5:1 that body and
    /// footnote text need (WCAG AA), and Apple's accessibility audit flags it
    /// on every value. This keeps the quieter look at about 7:1 in light mode
    /// and 9:1 in dark mode, enough for thin footnote text too. For symbols,
    /// `.secondary` is enough.
    static var subdued: Color { Color.primary.opacity(0.7) }
}
