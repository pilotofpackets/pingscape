import SwiftUI

/// A titled group of rows on a plain, opaque surface.
///
/// With `details:` the header gets a "Details ›" link that pushes the value
/// onto the enclosing `NavigationStack`.
struct InfoSection<Trailing: View, Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 16)
            InfoCard { content }
        }
    }
}

extension InfoSection where Trailing == EmptyView {
    init(title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.init(title: title, trailing: { EmptyView() }, content: content)
    }
}

extension InfoSection {
    init<Value: Hashable>(
        title: LocalizedStringKey, details value: Value, @ViewBuilder content: () -> Content
    ) where Trailing == DetailsLink<Value> {
        self.init(title: title, trailing: { DetailsLink(value: value) }, content: content)
    }
}

/// "Details ›", the link in a section header.
struct DetailsLink<Value: Hashable>: View {
    let value: Value

    var body: some View {
        NavigationLink(value: value) {
            HStack(spacing: 3) {
                Text("Details")
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            // A comfortable tap target without making the header taller.
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .padding(.vertical, -10)
    }
}

/// Rows with separators between them, on a rounded surface.
struct InfoCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    subview
                    if subview.id != subviews.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
