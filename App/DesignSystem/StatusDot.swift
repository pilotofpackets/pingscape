import SwiftUI

/// A small colored dot. Always sits next to text: color is never the only signal.
struct StatusDot: View {
    enum Tone {
        case good, warning, critical, neutral

        var color: Color {
            switch self {
            case .good: .green
            case .warning: .orange
            case .critical: .red
            case .neutral: .secondary
            }
        }
    }

    let tone: Tone

    var body: some View {
        Circle()
            .fill(tone.color)
            .frame(width: 9, height: 9)
            .accessibilityHidden(true)
    }
}
