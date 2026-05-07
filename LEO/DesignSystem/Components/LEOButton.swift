import SwiftUI

struct LEOButton: View {
    enum Style { case primary, secondary, destructive }

    let label: String
    let style: Style
    let action: () -> Void

    init(_ label: String, style: Style = .primary, action: @escaping () -> Void) {
        self.label = label
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Typography.headline)
                .foregroundStyle(foregroundColor)
                .padding(.vertical, Theme.Spacing.md)
                .padding(.horizontal, Theme.Spacing.xl)
                .frame(maxWidth: style == .primary ? .infinity : nil)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .accessibilityLabel(label)
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:     return Theme.Color.accent
        case .secondary:   return Theme.Color.surface
        case .destructive: return Theme.Color.danger.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:     return .white
        case .secondary:   return Theme.Color.textPrimary
        case .destructive: return Theme.Color.danger
        }
    }
}

#Preview {
    VStack(spacing: Theme.Spacing.lg) {
        LEOButton("Primary Action") {}
        LEOButton("Secondary", style: .secondary) {}
        LEOButton("Delete", style: .destructive) {}
    }
    .padding(Theme.Spacing.xl)
    .background(Theme.Color.background)
}
