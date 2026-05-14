import SwiftUI

/// Compact quick-add field used in the Mac toolbar and the floating capture window.
@MainActor
struct MacQuickAddView: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var vm: QuickAddViewModel? = nil
    @FocusState private var focused: Bool
    var onCommit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Theme.Color.accent)
                .font(.system(size: 16))

            if let vm {
                TextField("Capture a task, event, reminder…", text: Binding(get: { vm.text }, set: { vm.text = $0 }))
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        Task { _ = await vm.submit(); onCommit?() }
                    }

                if let summary = vm.parsedSummary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }

                if !vm.text.isEmpty {
                    Button {
                        Task { _ = await vm.submit(); onCommit?() }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundStyle(Theme.Color.accent)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Capture a task, event, reminder…")
                    .foregroundStyle(.secondary)
                    .font(.body)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.Color.surface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? Theme.Color.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .task {
            if vm == nil {
                vm = QuickAddViewModel(repository: appEnv.itemRepository)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .leoOpenQuickAdd)) { _ in
            focused = true
        }
    }
}
