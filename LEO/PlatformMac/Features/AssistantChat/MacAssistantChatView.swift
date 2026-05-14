import SwiftUI

/// Mac-native AI assistant hub. Reuses iOS ChatHomeView and ChatSessionView
/// via NavigationStack; adapts sizing for big screens.
@MainActor
struct MacAssistantChatView: View {
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        AssistantChatView()
    }
}
