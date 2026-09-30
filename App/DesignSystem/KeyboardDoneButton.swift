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

/// A floating "Done" button that closes the keyboard, for a page that draws its
/// own bar above the keyboard. The system's Done bar (`keyboardDoneButton`)
/// did not always show on a real phone, so a page that must not lose a button
/// next to the keyboard cannot rely on it.
struct KeyboardDoneBarButton: View {
    var body: some View {
        Button {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        } label: {
            Text("Done")
                .font(.headline)
                .padding(.horizontal, 20)
                .frame(minHeight: 50)
                .glassSurface(cornerRadius: 25)
        }
        .buttonStyle(.plain)
    }
}
