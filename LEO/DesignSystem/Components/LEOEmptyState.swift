import SwiftUI

struct LEOEmptyState: View {
    let title: String
    let message: String
    let icon: String
    var action: (label: String, handler: () -> Void)? = nil

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(Theme.Color.textSecondary)
            VStack(spacing: Theme.Spacing.sm) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Color.textPrimary)
                Text(message)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let action {
                LEOButton(action.label, action: action.handler)
                    .frame(maxWidth: 240)
            }
        }
        .padding(Theme.Spacing.xxl)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LEOEmptyState(
        title: "Nothing today",
        message: "Capture anything you owe your future self.",
        icon: "calendar.badge.plus",
        action: ("Add something", {})
    )
    .background(Theme.Color.background)
}
