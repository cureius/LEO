import SwiftUI

/// Settings → Cloud Sync. Sign in, see status, back up / restore, sign out.
struct CloudSyncView: View {
    @Environment(AppEnvironment.self) private var appEnv

    var body: some View {
        #if canImport(Supabase)
        CloudSyncContent(itemRepository: appEnv.itemRepository,
                         habitRepository: appEnv.habitRepository,
                         bodyProfileRepository: appEnv.bodyProfileRepository)
        #else
        List {
            Section { Text("Cloud sync isn't available in this build.") }
        }
        .navigationTitle("Cloud Sync")
        #endif
    }
}

#if canImport(Supabase)
import Supabase

private struct CloudSyncContent: View {
    let itemRepository: ItemRepository
    let habitRepository: HabitRepository
    let bodyProfileRepository: BodyProfileRepository

    @Environment(\.dismiss) private var dismiss
    @State private var manager = SupabaseManager.shared

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var status: String?
    @State private var error: String?
    @State private var lastSynced: Date?
    @State private var pendingConfirmation = false

    var body: some View {
        List {
            #if os(macOS)
            // Always-visible dismiss — toolbar buttons can be unreliable in
            // sheets presented over the macOS Settings window.
            Section {
                Button("Done") { dismiss() }
            }
            #endif
            if !manager.isConfigured {
                Section {
                    Label("Supabase isn't configured.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.Color.warning)
                    Text("Add SUPABASE_URL and SUPABASE_ANON_KEY, then rebuild.")
                        .font(.caption).foregroundStyle(Theme.Color.textSecondary)
                }
            } else if manager.isSignedIn {
                signedInSection
            } else if pendingConfirmation {
                confirmationSection
            } else {
                signInSection
            }

            if let status {
                Section { Label(status, systemImage: "checkmark.circle").foregroundStyle(Theme.Color.success) }
            }
            if let error {
                Section { Label(error, systemImage: "xmark.circle").foregroundStyle(Theme.Color.danger) }
            }
        }
        .navigationTitle("Cloud Sync")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            LiveSyncController.shared.configure(itemRepository: itemRepository,
                                                habitRepository: habitRepository,
                                                bodyProfileRepository: bodyProfileRepository)
            await manager.restoreSession()
            if manager.isSignedIn { await runInitialSync() }
        }
    }

    // MARK: Auth

    private var signInSection: some View {
        Section {
            TextField("Email", text: $email)
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                #endif
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .autocorrectionDisabled()

            Button { Task { await authenticate(signUp: false) } } label: {
                HStack { Text("Sign In"); Spacer(); if busy { ProgressView().scaleEffect(0.8) } }
            }
            .disabled(busy || email.isEmpty || password.isEmpty)

            Button("Create Account") { Task { await authenticate(signUp: true) } }
                .disabled(busy || email.isEmpty || password.isEmpty)
        } header: {
            Text("Account")
        } footer: {
            Text("Sign in on each device with the same account to sync. Your data is protected by row-level security — no one else can read it.")
        }
    }

    // MARK: Awaiting email confirmation

    private var confirmationSection: some View {
        Section {
            Label("Check your email", systemImage: "envelope.badge")
                .foregroundStyle(Theme.Color.accent)
            Text("We sent a confirmation link to \(email). Tap it, then come back and sign in.")
                .font(.caption).foregroundStyle(Theme.Color.textSecondary)

            Button { Task { await authenticate(signUp: false) } } label: {
                HStack { Text("I've confirmed — Sign In"); Spacer(); if busy { ProgressView().scaleEffect(0.8) } }
            }
            .disabled(busy || password.isEmpty)

            Button("Resend confirmation email") { Task { await resend() } }
                .disabled(busy)
            Button("Use a different email", role: .cancel) { pendingConfirmation = false }
                .disabled(busy)
        } header: {
            Text("Confirm your account")
        }
    }

    // MARK: Signed in

    private var signedInSection: some View {
        Group {
            Section {
                Label("Live sync is on", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(Theme.Color.success)
                if let lastSynced {
                    LabeledContent("Last synced", value: lastSynced.formatted(.relative(presentation: .named)))
                }
            } header: { Text("Status") }

            Section {
                Button { Task { await action("Synced") { try await LiveSyncController.shared.syncNow() } } } label: {
                    rowLabel("Sync now", "arrow.triangle.2.circlepath", busy: busy)
                }
                Button { Task { await action("Backed up to cloud") { try await LiveSyncController.shared.backupNow() } } } label: {
                    rowLabel("Back up to cloud now", "icloud.and.arrow.up", busy: busy)
                }
                Button { Task { await action("Restored from cloud") { try await LiveSyncController.shared.restoreFromCloud() } } } label: {
                    rowLabel("Restore from cloud", "icloud.and.arrow.down", busy: busy)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { LiveSyncController.shared.deactivate(); await manager.signOut(); status = nil }
                } label: { Text("Sign Out") }
            }
        }
    }

    private func rowLabel(_ title: String, _ icon: String, busy: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if busy { ProgressView().scaleEffect(0.8) }
        }
    }

    // MARK: Actions

    private func authenticate(signUp: Bool) async {
        busy = true; error = nil; status = nil
        defer { busy = false }
        do {
            if signUp {
                let confirmed = try await manager.signUp(email: email, password: password)
                if confirmed {
                    password = ""; pendingConfirmation = false
                    await runInitialSync()
                } else {
                    pendingConfirmation = true   // wait for the email link
                }
            } else {
                try await manager.signIn(email: email, password: password)
                password = ""; pendingConfirmation = false
                await runInitialSync()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func resend() async {
        busy = true; error = nil; status = nil
        defer { busy = false }
        do {
            try await manager.resendConfirmation(email: email)
            status = "Confirmation email re-sent to \(email)"
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func runInitialSync() async {
        await action("Synced") { try await LiveSyncController.shared.syncNow() }
        LiveSyncController.shared.goLive()
    }

    private func action(_ successText: String, _ work: () async throws -> Void) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            try await work()
            status = successText
            lastSynced = .now
        } catch {
            self.error = error.localizedDescription
        }
    }
}
#endif
