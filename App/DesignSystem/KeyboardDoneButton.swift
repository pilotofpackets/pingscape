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
}
