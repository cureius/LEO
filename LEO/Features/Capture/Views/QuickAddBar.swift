import SwiftUI

struct QuickAddBar: View {
    @State private var vm: QuickAddViewModel
    var onItemAdded: (() -> Void)? = nil

    init(repository: ItemRepository, onItemAdded: (() -> Void)? = nil) {
        _vm = State(wrappedValue: QuickAddViewModel(repository: repository))
        self.onItemAdded = onItemAdded
    }

    var body: some View {
        QuickAddBarContent(vm: vm, onItemAdded: onItemAdded)
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
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { isFocused = false }
                                .fontWeight(.semibold)
                        }
                    }

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
            isFocused = false
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
    let env = AppEnvironment(useInMemory: true)
    VStack {
        Spacer()
        QuickAddBar(repository: env.itemRepository, onItemAdded: {})
    }
    .background(Theme.Color.background)
}
