import SwiftUI

extension View {
    /// A "Done" button above the keyboard that closes it, whichever text field
    /// on this page is focused. Without it, a page with only a short text
    /// field and no room to scroll gives no way to put the keyboard away.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }

    /// Lifts a floating control above the "Done" bar while the keyboard is open.
    /// Since iOS 26 that bar floats over the keyboard's top edge, and the safe
    /// area ends at that edge, so anything pinned to the bottom of the page would
    /// sit half behind it.
    func aboveKeyboardDoneBar(_ keyboardShown: Bool) -> some View {
        modifier(AboveKeyboardDoneBar(keyboardShown: keyboardShown))
    }
}

private struct AboveKeyboardDoneBar: ViewModifier {
    let keyboardShown: Bool
    /// How far the bar reaches above the top edge of the keyboard.
    @ScaledMetric private var clearance: CGFloat = 34

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardShown ? clearance : 0)
            .animation(.default, value: keyboardShown)
    }
}
