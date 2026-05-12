import SwiftUI

/// Presents the AI-proposed Diff for user review.
/// Each change can be individually accepted or rejected before applying.
@MainActor
struct DiffReviewSheet: View {
    let diff: DiffPayload
    let onApply: ([DiffChange]) -> Void  // accepted changes (full objects)
    @Environment(\.dismiss) private var dismiss

    @State private var accepted: Set<String>

    init(diff: DiffPayload, onApply: @escaping ([DiffChange]) -> Void) {
        self.diff = diff
        self.onApply = onApply
        _accepted = State(initialValue: Set(diff.changes.map(\.itemID)))
    }

    // MARK: - Apply button label and tint

    private var acceptedChanges: [DiffChange] {
        diff.changes.filter { accepted.contains($0.itemID) }
    }

    private var applyLabel: String {
        let n = accepted.count
        let adds    = acceptedChanges.filter { $0.kind == "add"    }.count
        let deletes = acceptedChanges.filter { $0.kind == "delete" }.count
        let updates = acceptedChanges.filter { $0.kind == "update" }.count
        if deletes > 0 && adds == 0 && updates == 0 {
            return "Remove \(deletes) item\(deletes == 1 ? "" : "s")"
        }
        if adds > 0 && deletes == 0 && updates == 0 {
            return "Add \(adds) item\(adds == 1 ? "" : "s")"
        }
        if updates > 0 && adds == 0 && deletes == 0 {
            return "Reschedule \(updates) item\(updates == 1 ? "" : "s")"
        }
        return "Apply \(n) change\(n == 1 ? "" : "s")"
    }

    private var applyTint: Color {
        let deletes = acceptedChanges.filter { $0.kind == "delete" }.count
        let adds    = acceptedChanges.filter { $0.kind == "add"    }.count
        if deletes > 0 && adds == 0 { return Theme.Color.danger }
        return Theme.Color.accent
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Rationale header
                VStack(alignment: .leading, spacing: 6) {
                    Label("LEO suggests", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.accent)
                    Text(diff.rationale)
                        .font(Theme.Typography.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Theme.Color.surface)

                Divider()

                // Changes list
                List {
                    ForEach(diff.changes, id: \.itemID) { change in
                        DiffChangeRow(change: change, isAccepted: accepted.contains(change.itemID)) {
                            if accepted.contains(change.itemID) {
                                accepted.remove(change.itemID)
                            } else {
                                accepted.insert(change.itemID)
                            }
                        }
                    }
                }
                .listStyle(.plain)

                Divider()

                // Apply button
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .buttonStyle(.bordered)
                    Button(applyLabel) {
                        let acceptedChanges = diff.changes.filter { accepted.contains($0.itemID) }
                        onApply(acceptedChanges)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(applyTint)
                    .disabled(accepted.isEmpty)
                }
                .padding()
            }
            .navigationTitle("Review changes")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Change row

private struct DiffChangeRow: View {
    let change: DiffChange
    let isAccepted: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(changeColor.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: changeIcon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(changeColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.Color.textPrimary)
                    .lineLimit(1)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(get: { isAccepted }, set: { _ in onToggle() }))
                .labelsHidden()
        }
        .padding(.vertical, 6)
        .opacity(isAccepted ? 1 : 0.45)
    }

    // MARK: - Computed display properties

    private var title: String {
        switch change.kind {
        case "add":    return change.pendingItem?.title ?? change.newValue
        case "delete": return change.newValue.isEmpty ? "Unknown item" : change.newValue
        default:       return change.newValue.isEmpty ? "Update \(change.field)" : change.newValue
        }
    }

    private var subtitle: String? {
        switch change.kind {
        case "add":
            guard let p = change.pendingItem else { return nil }
            var parts: [String] = [p.type.capitalized]
            if let start = p.start {
                let formatOptions: [ISO8601DateFormatter.Options] = [
                    [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime],
                    [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
                ]
                for opts in formatOptions {
                    let iso = ISO8601DateFormatter(); iso.formatOptions = opts
                    if let date = iso.date(from: start) {
                        parts.append(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        break
                    }
                }
            }
            return parts.joined(separator: " · ")
        case "delete":
            return "Will be permanently deleted"
        case "update":
            return change.newValue.isEmpty ? nil : "New time: \(change.newValue)"
        default:
            return nil
        }
    }

    private var changeIcon: String {
        if change.kind == "add", let p = change.pendingItem {
            switch p.type {
            case "event":    return "calendar.badge.plus"
            case "reminder": return "bell.badge.plus"
            default:         return "checklist"
            }
        }
        switch change.kind {
        case "add":    return "plus.circle.fill"
        case "delete": return "trash.circle.fill"
        default:       return "pencil.circle.fill"
        }
    }

    private var changeColor: Color {
        switch change.kind {
        case "add":    return Theme.Color.success
        case "delete": return Theme.Color.danger
        default:       return Theme.Color.accent
        }
    }
}
