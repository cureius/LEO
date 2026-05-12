import SwiftUI

/// Reusable row for any Item — used on Today, Inbox, and Habits.
/// Long-press reveals context menu for Complete / Edit / Delete.
struct ItemRow: View {
    let item: any Item
    let onComplete: (any Item) -> Void
    let onTap: (any Item) -> Void
    var onDelete: ((any Item) -> Void)? = nil

    var body: some View {
        Button { onTap(item) } label: {
            HStack(spacing: Theme.Spacing.md) {
                completionButton
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(Theme.Typography.body)
                        .foregroundStyle(item.isCompleted ? Theme.Color.textSecondary : Theme.Color.textPrimary)
                        .strikethrough(item.isCompleted)
                        .lineLimit(2)
                    secondaryLine
                }
                Spacer(minLength: 0)
                trailingAccessories
            }
            .padding(.vertical, Theme.Spacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.isCompleted {
                Button("Mark incomplete", systemImage: "arrow.uturn.backward.circle") { onComplete(item) }
            } else {
                Button("Complete", systemImage: "checkmark.circle") { onComplete(item) }
            }
            Button("Edit", systemImage: "pencil") { onTap(item) }
            if let onDelete {
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) { onDelete(item) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Double tap to open. Long press for actions.")
    }

    // MARK: - Sub-views

    private var completionButton: some View {
        Button {
            onComplete(item)
        } label: {
            Image(systemName: completionIcon)
                .font(.system(size: 22))
                .foregroundStyle(completionColor)
                .contentShape(Circle().scale(1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.isCompleted ? "Mark incomplete" : "Mark complete")
    }

    private var completionIcon: String {
        switch item {
        case is AlarmItem:         return item.isCompleted ? "bell.slash.fill" : "bell.fill"
        case is HabitInstanceItem: return item.isCompleted ? "circle.fill" : "circle"
        case is EventItem:         return item.isCompleted ? "calendar.badge.checkmark" : "calendar"
        case is WorkoutItem:       return item.isCompleted ? "figure.strengthtraining.traditional" : "circle"
        case is MealItem:          return item.isCompleted ? "fork.knife.circle.fill" : "circle"
        default:                   return item.isCompleted ? "checkmark.circle.fill" : "circle"
        }
    }

    private var completionColor: Color {
        item.isCompleted ? Theme.Color.success : Theme.Color.textSecondary
    }

    @ViewBuilder
    private var secondaryLine: some View {
        let parts = secondaryParts
        if !parts.isEmpty {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Text(part)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
        }
    }

    private var secondaryParts: [String] {
        var parts: [String] = []
        switch item.anchor {
        case .dueAt(let d):
            parts.append("Due \(d.formatted(.relative(presentation: .named)))")
        case .timeBlock(let s, let e):
            if item.anchor.isAllDayBlock {
                parts.append("All day")
            } else {
                parts.append("\(s.formatted(.dateTime.hour().minute())) – \(e.formatted(.dateTime.hour().minute()))")
            }
        case .point(let d):
            parts.append(d.formatted(.dateTime.hour().minute()))
        default: break
        }
        if let event = item as? EventItem, let loc = event.location {
            parts.append("· \(loc)")
        }
        if item is HabitInstanceItem {
            parts.append("· Habit")
        }
        if let workout = item as? WorkoutItem {
            parts.append("· ~\(workout.estimatedKcal) kcal")
        }
        if let meal = item as? MealItem {
            parts.append("· \(meal.displayKcal) kcal")
        }
        return parts
    }

    @ViewBuilder
    private var trailingAccessories: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if item.importance == .urgent {
                LEOChip(label: "Urgent", color: Theme.Color.danger)
            } else if item.importance == .high {
                LEOChip(label: "High", color: Theme.Color.warning)
            }
            let visibleTags = Array(item.tags.prefix(2))
            ForEach(visibleTags, id: \.id) { tag in
                LEOChip(label: tag.name)
            }
            if item.tags.count > 2 {
                Text("+\(item.tags.count - 2)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
        }
    }

    private var accessibilityLabel: String {
        var parts = [itemTypeLabel, item.title]
        switch item.anchor {
        case .dueAt(let d): parts.append("due \(d.formatted(.relative(presentation: .named)))")
        case .timeBlock(let s, _): parts.append("at \(s.formatted(.dateTime.hour().minute()))")
        case .point(let d): parts.append("at \(d.formatted(.dateTime.hour().minute()))")
        default: break
        }
        if item.importance != .normal { parts.append(item.importance.displayName) }
        if item.isCompleted { parts.append("completed") }
        return parts.joined(separator: ", ")
    }

    private var itemTypeLabel: String {
        switch item {
        case is TaskItem:          return "Task"
        case is EventItem:         return "Event"
        case is ReminderItem:      return "Reminder"
        case is AlarmItem:         return "Alarm"
        case is HabitInstanceItem: return "Habit"
        case is WorkoutItem:       return "Workout"
        case is MealItem:          return "Meal"
        default:                   return "Item"
        }
    }
}

#Preview {
    List {
        ItemRow(item: TaskItem(title: "Draft Q3 report", importance: .high, anchor: .dueAt(.now.addingTimeInterval(86400))), onComplete: { _ in }, onTap: { _ in })
        ItemRow(item: ReminderItem(title: "Call mom", anchor: .point(.now.addingTimeInterval(3600))), onComplete: { _ in }, onTap: { _ in })
        ItemRow(item: HabitInstanceItem(title: "Gym", anchor: .timeBlock(start: .now, end: .now.addingTimeInterval(3600)), habitID: UUID()), onComplete: { _ in }, onTap: { _ in })
    }
    .scrollContentBackground(.hidden)
    .background(Theme.Color.background)
}
