import SwiftUI

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.Color.danger)
            Text(message)
                .font(Theme.Typography.callout)
                .foregroundStyle(Theme.Color.textPrimary)
                .lineLimit(2)
            Spacer()
            if let retry {
                Button("Retry", action: retry)
                    .font(Theme.Typography.callout.bold())
                    .foregroundStyle(Theme.Color.accent)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .strokeBorder(Theme.Color.danger.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

#Preview {
    VStack {
        ErrorBanner(message: "Could not sync with iCloud.", retry: {})
        ErrorBanner(message: "Notification permission denied. Enable in Settings.")
    }
    .padding()
    .background(Theme.Color.background)
}
