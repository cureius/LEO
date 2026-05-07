import SwiftUI

struct LEOTextField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        TextField(placeholder, text: $text)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.Color.textPrimary)
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .onSubmit { onSubmit?() }
            .accessibilityLabel(placeholder)
    }
}

#Preview {
    struct Wrapper: View {
        @State private var text = ""
        var body: some View {
            LEOTextField(placeholder: "Add anything...", text: $text)
                .padding()
                .background(Theme.Color.background)
        }
    }
    return Wrapper()
}
