import SwiftUI
import MessageUI

@MainActor
struct FeedbackView: View {
    enum FeedbackType: String, CaseIterable { case bug = "Bug", idea = "Feature idea", praise = "Praise" }

    @State private var type: FeedbackType = .bug
    @State private var description = ""
    @State private var email = ""
    @State private var showMailComposer = false
    @State private var showMailFallback = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Type", selection: $type) {
                        ForEach(FeedbackType.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Description") {
                    TextEditor(text: $description)
                        .frame(minHeight: 100)
                }

                Section("Your email (optional)") {
                    TextField("email@example.com", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                }

                Section("Diagnostics") {
                    Text("App version \(appVersion), iOS \(iosVersion), device \(deviceModel)")
                        .font(.caption)
                        .foregroundStyle(Theme.Color.textSecondary)
                    Text("Diagnostic info will be attached to your report.")
                        .font(.caption2)
                        .foregroundStyle(Theme.Color.textSecondary)
                }
            }
            .navigationTitle("Send feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { send() }
                        .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func send() {
        if MFMailComposeViewController.canSendMail() {
            showMailComposer = true
        } else {
            // Fallback to mailto: URL
            let subject = "[\(type.rawValue)] LEO Feedback"
            let body = buildBody()
            let urlString = "mailto:feedback@leo.app?subject=\(subject.urlEncoded)&body=\(body.urlEncoded)"
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
            dismiss()
        }
    }

    private func buildBody() -> String {
        """
        Type: \(type.rawValue)

        Description:
        \(description)

        ---
        App: \(appVersion)
        iOS: \(iosVersion)
        Device: \(deviceModel)
        Email: \(email.isEmpty ? "(not provided)" : email)
        """
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var iosVersion: String { UIDevice.current.systemVersion }
    private var deviceModel: String { UIDevice.current.model }
}

extension String {
    var urlEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self
    }
}
