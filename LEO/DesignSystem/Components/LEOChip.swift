import SwiftUI

struct LEOChip: View {
    let label: String
    var icon: String? = nil
    var color: Color = Theme.Color.accentMuted

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(label)
                .font(Theme.Typography.caption)
        }
        .foregroundStyle(Theme.Color.textPrimary)
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(color.opacity(0.18))
        .clipShape(Capsule())
        .accessibilityLabel(label)
    }
}

#Preview {
    HStack {
        LEOChip(label: "Work", icon: "briefcase.fill")
        LEOChip(label: "Health", icon: "heart.fill", color: Theme.Color.success)
        LEOChip(label: "Urgent", color: Theme.Color.danger)
    }
    .padding()
    .background(Theme.Color.background)
}
