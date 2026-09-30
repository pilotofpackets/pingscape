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

    /// Moves a floating control at the bottom of the page level with the "Done"
    /// bar while the keyboard is open. Since iOS 26 that bar floats over the
    /// keyboard's top edge, and the safe area ends at that edge, so the control
    /// would sit half behind it. Beside it, in the free space, it stays in view.
    func levelWithKeyboardDoneBar(_ keyboardShown: Bool) -> some View {
        modifier(LevelWithKeyboardDoneBar(keyboardShown: keyboardShown))
    }
}

private struct LevelWithKeyboardDoneBar: ViewModifier {
    let keyboardShown: Bool
    /// From the resting place of a 50 pt button, 8 pt above the safe area, down to
    /// the middle of the Done bar.
    @ScaledMetric private var drop: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .offset(y: keyboardShown ? drop : 0)
            .animation(.default, value: keyboardShown)
    }
}
