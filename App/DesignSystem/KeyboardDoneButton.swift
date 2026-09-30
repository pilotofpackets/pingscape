import SwiftUI

extension View {
    /// A "Done" button above the keyboard that closes it, whichever text field
    /// on this page is focused. Without it, a page with only a short text
    /// field and no room to scroll gives no way to put the keyboard away.
    func keyboardDoneButton() -> some View {
        keyboardDoneButton { EmptyView() }
    }

    /// The same, with more buttons in front of "Done". They sit in the bar the
    /// system puts on the keyboard, so they are in reach on every device, however
    /// tall the keyboard is.
    func keyboardDoneButton<Leading: View>(@ViewBuilder leading: () -> Leading) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                leading()
                Spacer()
                Button("Done") { Keyboard.dismiss() }
            }
        }
    }
}

enum Keyboard {
    /// Closes the keyboard, whichever field has it.
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
