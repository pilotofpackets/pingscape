import SwiftUI

extension ShapeStyle where Self == Color {
    /// Text and symbols on an accent-filled surface (prominent buttons, the
    /// selected chip). White in light mode. In dark mode the accent turns
    /// light, and white on it falls to about 2:1, so this turns dark there.
    ///
    /// Set it on the label itself: `.borderedProminent` paints its label white
    /// and wins over a style set outside the button.
    static var onAccent: Color { Color("AccentForeground") }
}
