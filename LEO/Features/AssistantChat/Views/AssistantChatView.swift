import SwiftUI

@MainActor
struct AssistantChatView: View {
    @State private var vm: AssistantChatViewModel
    @State private var showDiffReview = false
    @State private var selectedDiff: DiffPayload? = nil

    init(vm: AssistantChatViewModel) {
        _vm = State(wrappedValue: vm)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if vm.messages.isEmpty {
                            suggestionsView
                        } else {
                            ForEach(vm.messages) { msg in
                                MessageBubble(message: msg) { diff in
                                    selectedDiff = diff
                                    showDiffReview = true
                                }
                                .id(msg.id)
                            }
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Color.danger)
                    .padding(.horizontal)
            }

            Divider()

            // Input bar
            HStack(spacing: 12) {
                TextField("Ask LEO…", text: $vm.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(10)
                    .background(Theme.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .onSubmit { Task { await vm.send() } }

                Button {
                    Task { await vm.send() }
                } label: {
                    Image(systemName: vm.isSending ? "ellipsis.circle" : "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(vm.isSending ? Theme.Color.textSecondary : Theme.Color.accent)
                }
                .disabled(vm.isSending || vm.inputText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .navigationTitle("Ask LEO")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Clear") { vm.clearHistory() }
                    .disabled(vm.messages.isEmpty)
            }
        }
        .sheet(isPresented: $showDiffReview) {
            if let diff = selectedDiff {
                DiffReviewSheet(diff: diff) { accepted in
                    // TODO (M4-T03): apply accepted changes via repository
                    _ = accepted
                }
            }
        }
    }

    // MARK: - Suggestions

    private var suggestionsView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(Theme.Color.accent)
            Text("What would you like to plan?")
                .font(Theme.Typography.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(vm.suggestions, id: \.self) { s in
                    Button(s) {
                        Task { await vm.send(s) }
                    }
                    .font(.caption)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(Theme.Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
            }
        }
        .padding(.top, 40)
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let onDiffTap: (DiffPayload) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant || message.role == .toolCall || message.role == .toolResult {
                Image(systemName: "sparkles.square.filled.on.square")
                    .foregroundStyle(Theme.Color.accent)
                    .frame(width: 28)
            } else {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Group {
                    switch message.role {
                    case .diffProposal:
                        diffProposalBubble
                    default:
                        Text(message.text.isEmpty ? "…" : message.text)
                            .padding(10)
                            .background(bubbleColor)
                            .foregroundStyle(message.role == .user ? .white : Theme.Color.textPrimary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                }
            }

            if message.role == .user { Spacer() }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var diffProposalBubble: some View {
        Button {
            if let diff = message.diff { onDiffTap(diff) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundStyle(Theme.Color.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Proposed changes")
                        .font(.caption.bold())
                    Text(message.text)
                        .font(.caption)
                        .lineLimit(2)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }
            .padding(10)
            .background(Theme.Color.accentMuted)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .buttonStyle(.plain)
    }

    private var bubbleColor: Color {
        switch message.role {
        case .user:        return Theme.Color.accent
        case .toolCall, .toolResult: return Theme.Color.surface
        default:           return Theme.Color.surfaceElevated
        }
    }
}
