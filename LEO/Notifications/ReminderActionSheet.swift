import SwiftUI

// MARK: - In-app alarm sheet shown when user taps a reminder notification

struct ReminderActionSheet: View {
    let alert: PendingReminderAlert
    let onDone: @MainActor () async -> Void
    let onSnooze: @MainActor (TimeInterval) async -> Void
    let onDismiss: @MainActor () -> Void

    @State private var isActing = false

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(.tertiaryLabel))
                .frame(width: 40, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 6)

            // Icon + title
            VStack(spacing: 18) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Theme.Color.accent, Theme.Color.accent.opacity(0.7)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text(alert.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .multilineTextAlignment(.center)

                    if let date = alert.dueDate {
                        Label(
                            date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()),
                            systemImage: "clock"
                        )
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Color.textSecondary)
                    }
                }
            }
            .padding(.top, 20)
            .padding(.bottom, 32)
            .padding(.horizontal, 24)

            Divider()

            // Action buttons
            VStack(spacing: 0) {
                // Done
                actionButton(
                    title: "Done",
                    subtitle: "Mark as completed",
                    icon: "checkmark.circle.fill",
                    color: Theme.Color.success
                ) {
                    isActing = true
                    await onDone()
                }

                Divider().padding(.leading, 60)

                // Snooze 10 min
                actionButton(
                    title: "Snooze 10 minutes",
                    subtitle: "Remind me again at \(snoozeTime(60 * 10))",
                    icon: "clock.arrow.circlepath",
                    color: Theme.Color.accent
                ) {
                    isActing = true
                    await onSnooze(60 * 10)
                }

                Divider().padding(.leading, 60)

                // Snooze 1 hour
                actionButton(
                    title: "Snooze 1 hour",
                    subtitle: "Remind me again at \(snoozeTime(3600))",
                    icon: "clock.arrow.circlepath",
                    color: Theme.Color.textSecondary
                ) {
                    isActing = true
                    await onSnooze(3600)
                }

                Divider()

                // Dismiss (no action)
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 17))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .disabled(isActing)

            Spacer(minLength: 0)
        }
        .background(Color(.systemBackground))
        .presentationDetents([.medium])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder
    private func actionButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(color)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.Color.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.Color.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func snoozeTime(_ seconds: TimeInterval) -> String {
        Date.now.addingTimeInterval(seconds).formatted(.dateTime.hour().minute())
    }
}
