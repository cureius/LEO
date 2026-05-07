import SwiftUI

struct LEOCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(Theme.Spacing.lg)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
    }
}

#Preview {
    LEOCard {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Card Title").font(Theme.Typography.headline)
            Text("Card body content goes here.").font(Theme.Typography.body)
        }
    }
    .padding()
    .background(Theme.Color.background)
}
