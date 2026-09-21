import SwiftUI

extension View {
    /// Keeps content at a comfortable width on wide screens (iPad, iPhone in
    /// landscape) and centers it. On a phone in portrait it changes nothing.
    func readableContentWidth(_ maximum: CGFloat = 720) -> some View {
        frame(maxWidth: maximum)
            .frame(maxWidth: .infinity)
    }
}
