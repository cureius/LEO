import SwiftUI

struct MacInspector: View {
    @Environment(MacNavigationModel.self) private var nav

    var body: some View {
        Group {
            if nav.selectedItemID != nil {
                // Full item-detail inspector implemented in MM3-T04
                VStack(alignment: .leading, spacing: 12) {
                    Text("Item Details")
                        .font(.headline)
                        .padding(.top)
                    Text("Detail editor — MM3-T04")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
            } else {
                emptyState
            }
        }
        .frame(minWidth: 280, idealWidth: 320)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No item selected")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Select an item to view its details")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
