import SwiftUI

/// Presents the AI-proposed Diff for user review.
/// Each change can be individually accepted or rejected before applying.
@MainActor
struct DiffReviewSheet: View {
    let diff: DiffPayload
    let onApply: (Set<String>) -> Void  // accepted change itemIDs
    @Environment(\.dismiss) private var dismiss

    @State private var accepted: Set<String>

    init(diff: DiffPayload, onApply: @escaping (Set<String>) -> Void) {
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
                    Button("Apply \(accepted.count) change\(accepted.count == 1 ? "" : "s")") {
                        onApply(accepted)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
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
            Image(systemName: changeIcon)
                .foregroundStyle(changeColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(changeDescription)
                    .font(Theme.Typography.body)
                if !change.newValue.isEmpty && change.kind != "delete" {
                    Text(change.newValue)
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Toggle("", isOn: Binding(get: { isAccepted }, set: { _ in onToggle() }))
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }

    private var changeIcon: String {
        switch change.kind {
        case "add":    return "plus.circle"
        case "delete": return "trash.circle"
        default:       return "pencil.circle"
        }
    }

    private var changeColor: Color {
        switch change.kind {
        case "add":    return Theme.Color.success
        case "delete": return Theme.Color.danger
        default:       return Theme.Color.accent
        }
    }

    private var changeDescription: String {
        switch change.kind {
        case "add":    return "Add item"
        case "delete": return "Remove item"
        default:       return "Update \(change.field)"
        }
    }
}
