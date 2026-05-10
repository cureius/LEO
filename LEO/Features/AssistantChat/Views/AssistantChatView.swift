import SwiftUI

// MARK: - Entry point for the Ask LEO tab
// Checks for API key synchronously at init so no NavigationStack swapping occurs.

@MainActor
struct AssistantChatView: View {
    @Environment(AppEnvironment.self) private var appEnv
    // Read from Keychain synchronously — avoids false→true flip that breaks tab navigation
    @State private var hasAPIKey = KeychainHelper.load(key: "claude_api_key") != nil
        || ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] != nil
    @State private var showAPIKeySetup = false

    var body: some View {
        // Single NavigationStack for the whole tab — never swapped, so tab bar stays stable
        NavigationStack {
            if hasAPIKey {
                ChatHomeBody()
            } else {
                noAPIKeyContent
            }
        }
        .sheet(isPresented: $showAPIKeySetup) {
            APIKeySetupSheet { hasAPIKey = true }
                .environment(appEnv)
        }
    }

    // MARK: - No API key content (no NavigationStack — lives inside the one above)

    private var noAPIKeyContent: some View {
        VStack(spacing: 28) {
            Spacer()

            LEOAvatar(size: 64)

            VStack(spacing: 10) {
                Text("API Key Required")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.Color.textPrimary)
                Text("Ask LEO uses the Claude API.\nAdd your Anthropic API key to get started.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button { showAPIKeySetup = true } label: {
                Label("Add API Key", systemImage: "key.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 28)
                    .padding(.vertical, 13)
                    .background(Theme.Color.accent)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            Link("Get a key at console.anthropic.com",
                 destination: URL(string: "https://console.anthropic.com/")!)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Color.accent)

            Spacer()
        }
        .navigationTitle("Ask LEO")
    }
}

// MARK: - API Key setup sheet

struct APIKeySetupSheet: View {
    @Environment(AppEnvironment.self) private var appEnv
    @State private var key = ""
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("sk-ant-api03-…", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("Stored securely in the device Keychain. Only sent to Anthropic's servers.")
                }
                Section {
                    Link("Get a key at console.anthropic.com",
                         destination: URL(string: "https://console.anthropic.com/")!)
                }
            }
            .navigationTitle("Add API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await appEnv.claudeClient.setAPIKey(key.trimmingCharacters(in: .whitespaces))
                            onSaved()
                            dismiss()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
