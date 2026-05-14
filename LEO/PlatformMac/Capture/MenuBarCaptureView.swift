import SwiftUI

/// Contents of the MenuBarExtra popover — next event + quick-capture.
@MainActor
struct MenuBarCaptureView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var nextItem: (any Item)? = nil
    @State private var refreshToken = UUID()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Next event header
            nextEventRow
            Divider()

            // Quick capture
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Capture")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                MacQuickAddView(onCommit: { refreshToken = UUID() })
            }
            .padding(12)

            Divider()

            // Open button
            Button("Open LEO") {
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.title == "LEO" {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320)
        .task { await refreshNext() }
        .onChange(of: refreshToken) { _, _ in Task { await refreshNext() } }
        .onReceive(NotificationCenter.default.publisher(for: .leoDataDidChange)) { _ in
            Task { await refreshNext() }
        }
    }

    private var nextEventRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Next")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let item = nextItem {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.headline)
                            .lineLimit(1)
                        if let d = item.anchor.sortDate {
                            Text(d, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundStyle(Theme.Color.accent)
                }
            } else {
                Text("Nothing scheduled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
    }

    private func refreshNext() async {
        let all = (try? await appEnv.itemRepository.fetch()) ?? []
        let now = Date.now
        nextItem = all
            .compactMap { item -> (any Item, Date)? in
                guard let d = item.anchor.sortDate, d > now, !item.isCompleted else { return nil }
                return (item, d)
            }
            .sorted { $0.1 < $1.1 }
            .first?.0
    }
}
