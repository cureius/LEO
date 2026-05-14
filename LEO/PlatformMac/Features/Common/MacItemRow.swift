import SwiftUI

/// Mac-native item row for list views (Today, Inbox, Habits).
/// Shows completion icon, title, time/date, and importance.
struct MacItemRow: View {
    let item: any Item
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            completionIcon
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    .strikethrough(item.isCompleted)
                    .lineLimit(1)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            importanceDot
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Theme.Color.accent.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
    }

    private var completionIcon: some View {
        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : typeIcon)
            .font(.system(size: 14))
            .foregroundStyle(item.isCompleted ? Theme.Color.success : typeColor)
            .frame(width: 18)
    }

    @ViewBuilder
    private var importanceDot: some View {
        if !item.isCompleted && item.importance != .normal {
            Circle()
                .fill(importanceColor)
                .frame(width: 6, height: 6)
        }
    }

    private var subtitle: String? {
        switch item.anchor {
        case .point(let d), .dueAt(let d):
            return d.formatted(.dateTime.hour().minute())
        case .timeBlock(let s, let e):
            return "\(s.formatted(.dateTime.hour().minute())) – \(e.formatted(.dateTime.hour().minute()))"
        case .location(let t):
            return "📍 \(t.coordinate.latitude.formatted(.number.precision(.fractionLength(2))))°"
        case .untimed:
            if let raw = item.rruleRaw, let rule = try? RRule.parse(raw) {
                return "↩ \(RecurrenceFormatter.summary(for: rule))"
            }
            return nil
        }
    }

    private var typeIcon: String {
        switch item {
        case is EventItem:         return "calendar"
        case is ReminderItem:      return "bell"
        case is AlarmItem:         return "alarm"
        case is HabitInstanceItem: return "repeat.circle"
        case is WorkoutItem:       return "figure.strengthtraining.traditional"
        case is MealItem:          return "fork.knife"
        default:                   return "circle"
        }
    }

    private var typeColor: Color {
        switch item {
        case is EventItem:    return Theme.Color.accent
        case is AlarmItem:    return Theme.Color.danger
        case is ReminderItem: return Theme.Color.warning
        default:              return Theme.Color.textSecondary
        }
    }

    private var importanceColor: Color {
        switch item.importance {
        case .urgent: return Theme.Color.danger
        case .high:   return Theme.Color.warning
        case .low:    return .secondary
        case .normal: return .clear
        }
    }
}
