import SwiftUI

// MARK: - Chat home body (no NavigationStack — hosted inside AssistantChatView's stack)

struct ChatHomeBody: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var sessions: [ChatSession] = []
    @State private var isLoading = true
    @State private var activeSession: ChatSession? = nil
    @State private var renameSession: ChatSession? = nil
    @State private var renameText = ""

    private let store = ConversationStore.shared

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
        .navigationTitle("Ask LEO")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { createNewSession() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17, weight: .medium))
                }
            }
        }
        .navigationDestination(item: $activeSession) { session in
            ChatSessionView(session: session, appEnv: appEnv)
                .onDisappear { Task { await reload() } }
        }
        .alert("Rename chat", isPresented: Binding(
            get: { renameSession != nil },
            set: { if !$0 { renameSession = nil } }
        )) {
            TextField("Chat name", text: $renameText)
            Button("Save") {
                if var s = renameSession {
                    s.title = renameText.trimmingCharacters(in: .whitespaces)
                    Task { await store.save(s); await reload() }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { await reload() }
    }

    // MARK: - Session list

    private var sessionList: some View {
        List {
            ForEach(sessions) { session in
                Button { activeSession = session } label: {
                    SessionRow(session: session)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task { await store.delete(id: session.id); await reload() }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        renameText = session.title
                        renameSession = session
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(Theme.Color.accent)
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") {
                        renameText = session.title
                        renameSession = session
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        Task { await store.delete(id: session.id); await reload() }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await reload() }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Theme.Color.accent.opacity(0.2), Theme.Color.accent.opacity(0.05)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 80, height: 80)
                Image(systemName: "sparkles")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.Color.accent)
            }

            VStack(spacing: 8) {
                Text("No conversations yet")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Start a conversation with LEO to plan your day, reschedule tasks, or get smart suggestions.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button { createNewSession() } label: {
                Label("New conversation", systemImage: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(Theme.Color.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            Spacer()
        }
    }

    // MARK: - Helpers

    private func createNewSession() {
        let session = ChatSession.create()
        activeSession = session
        Task { await store.save(session) }
    }

    private func reload() async {
        sessions = await store.allSessions()
        isLoading = false
    }
}

// MARK: - Session row

private struct SessionRow: View {
    let session: ChatSession

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Theme.Color.accent, Theme.Color.accent.opacity(0.7)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                Image(systemName: session.isEmpty ? "bubble.left" : "sparkles")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            // Text
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(session.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Color.textPrimary)
                        .lineLimit(1)
                    Spacer()
                    Text(session.updatedAt.chatTimestamp)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Color.textSecondary)
                }
                Text(session.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .background(Theme.Color.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Date formatting helper

private extension Date {
    var chatTimestamp: String {
        let cal = Calendar.current
        if cal.isDateInToday(self)     { return formatted(.dateTime.hour().minute()) }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        if cal.isDate(self, equalTo: .now, toGranularity: .weekOfYear) {
            return formatted(.dateTime.weekday(.abbreviated))
        }
        return formatted(.dateTime.month(.abbreviated).day())
    }
}
