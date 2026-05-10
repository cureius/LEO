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
                    Button("Add \(accepted.count) item\(accepted.count == 1 ? "" : "s")") {
                        let acceptedChanges = diff.changes.filter { accepted.contains($0.itemID) }
                        onApply(acceptedChanges)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Color.accent)
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
        if change.kind == "add", let p = change.pendingItem { return p.title }
        if change.kind == "delete" { return "Remove item" }
        return change.newValue.isEmpty ? "Update \(change.field)" : change.newValue
    }

    private var subtitle: String? {
        if change.kind == "add", let p = change.pendingItem {
            var parts: [String] = [p.type.capitalized]
            if let start = p.start {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
                if let date = iso.date(from: start) ?? ISO8601DateFormatter().date(from: start) {
                    parts.append(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                }
            }
            return parts.joined(separator: " · ")
        }
        return change.newValue.isEmpty ? nil : change.newValue
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
