import SwiftUI

struct QuickAddBar: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var viewModel: QuickAddViewModel? = nil
    var onItemAdded: (() -> Void)? = nil

    var body: some View {
        Group {
            if let vm = viewModel {
                QuickAddBarContent(vm: vm, onItemAdded: onItemAdded)
            }
        }
        .onAppear {
            guard viewModel == nil else { return }
            viewModel = QuickAddViewModel(repository: appEnv.itemRepository)
        }
    }
}

// Separate view so @Bindable works on the unwrapped vm
private struct QuickAddBarContent: View {
    @Bindable var vm: QuickAddViewModel
    var onItemAdded: (() -> Void)?

    @State private var showUndoToast = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Interpretation chip — shown while focused and we have a parse
            if let summary = vm.parsedSummary, isFocused {
                HStack {
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.accent)
                    Text(summary)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
                .accessibilityLabel("Interpreted as: \(summary)")
            }

            HStack(spacing: Theme.Spacing.sm) {
                TextField("Capture anything…", text: $vm.text, axis: .vertical)
                    .font(Theme.Typography.body)
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .onSubmit { Task { await submitAndNotify() } }
                    .accessibilityLabel("Quick add")
                    .accessibilityHint("Type anything to capture it. Press Return to save.")

                Button { Task { await submitAndNotify() } } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(vm.text.isEmpty ? Theme.Color.textSecondary : Theme.Color.accent)
                }
                .disabled(vm.text.isEmpty)
                .accessibilityLabel("Submit")
            }
            .padding(Theme.Spacing.md)
            .background(Theme.Color.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: -2)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)

            // Undo toast
            if showUndoToast {
                HStack {
                    Text("Captured")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Color.textPrimary)
                    Spacer()
                    Button("Undo") {
                        Task {
                            await vm.undo()
                            withAnimation { showUndoToast = false }
                            onItemAdded?()
                        }
                    }
                    .font(Theme.Typography.callout.bold())
                    .foregroundStyle(Theme.Color.accent)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.sm)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(Theme.Color.background)
    }

    private func submitAndNotify() async {
        let submitted = await vm.submit()
        if submitted {
            withAnimation(.spring(duration: 0.25)) { showUndoToast = true }
            onItemAdded?()
            Task {
                try? await Task.sleep(for: .seconds(10))
                withAnimation { showUndoToast = false }
            }
        }
    }
}

#Preview {
    VStack {
        Spacer()
        QuickAddBar(onItemAdded: {})
    }
    .environment(AppEnvironment(useInMemory: true))
    .background(Theme.Color.background)
}
