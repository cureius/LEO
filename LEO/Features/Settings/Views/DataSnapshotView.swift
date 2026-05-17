import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct DataSnapshotView: View {
    @Environment(AppEnvironment.self) private var appEnv

    // Export state
    @State private var isExporting = false
    @State private var exportedFileURL: URL? = nil
    @State private var showShareSheet = false
    @State private var exportError: String? = nil

    // Import state
    @State private var showFilePicker = false
    @State private var pendingData: Data? = nil
    @State private var showModeConfirm = false
    @State private var showReplaceConfirm = false
    @State private var isRestoring = false
    @State private var restoreResult: SnapshotRestoreResult? = nil
    @State private var restoreError: String? = nil

    var body: some View {
        List {
            exportSection
            importSection
        }
        .navigationTitle("Backup & Restore")
        // Share sheet
        .sheet(isPresented: $showShareSheet, onDismiss: { exportedFileURL = nil }) {
            if let url = exportedFileURL {
                ShareSheetView(url: url)
                    .ignoresSafeArea()
            }
        }
        // File picker for import
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.json, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                loadFile(url: url)
            case .failure(let err):
                restoreError = err.localizedDescription
            }
        }
        // Mode picker after file is loaded
        .confirmationDialog(
            "Choose restore mode",
            isPresented: $showModeConfirm,
            titleVisibility: .visible
        ) {
            Button("Merge — add missing items") {
                Task { await runRestore(mode: .merge) }
            }
            Button("Replace — wipe and restore all", role: .destructive) {
                showReplaceConfirm = true
            }
            Button("Cancel", role: .cancel) { pendingData = nil }
        } message: {
            Text("Merge keeps your existing data and adds records from the backup that aren't already present. Replace deletes everything first, then restores the backup completely.")
        }
        // Extra confirmation for destructive replace
        .confirmationDialog(
            "Replace all LEO data?",
            isPresented: $showReplaceConfirm,
            titleVisibility: .visible
        ) {
            Button("Replace everything", role: .destructive) {
                Task { await runRestore(mode: .replace) }
            }
            Button("Cancel", role: .cancel) { pendingData = nil }
        } message: {
            Text("This permanently deletes all your current tasks, events, habits, and history, then replaces them with the backup. This cannot be undone.")
        }
    }

    // MARK: - Export section

    @ViewBuilder
    private var exportSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Creates a single file containing all your tasks, events, reminders, alarms, habits, workouts, meals, and body data. Use it to transfer your data or keep a personal backup.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Button {
                Task { await runExport() }
            } label: {
                HStack {
                    Label("Create Backup", systemImage: "arrow.up.doc")
                    Spacer()
                    if isExporting { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(isExporting || isRestoring)

            if let err = exportError {
                Label(err, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.danger)
            }
        } header: {
            Text("Export Snapshot")
        }
    }

    // MARK: - Import section

    @ViewBuilder
    private var importSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Restore from a previously exported .leobackup file. Choose Merge to add missing items, or Replace to fully reset to the backup state.")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.textSecondary)
            }

            Button {
                restoreResult = nil
                restoreError = nil
                showFilePicker = true
            } label: {
                HStack {
                    Label("Restore from Backup", systemImage: "arrow.down.doc")
                    Spacer()
                    if isRestoring { ProgressView().scaleEffect(0.8) }
                }
            }
            .disabled(isExporting || isRestoring)

            if let result = restoreResult {
                restoreResultView(result)
            }
            if let err = restoreError {
                Label(err, systemImage: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.Color.danger)
            }
        } header: {
            Text("Import Snapshot")
        } footer: {
            Text("Supported file: .leobackup (JSON)")
        }
    }

    @ViewBuilder
    private func restoreResultView(_ r: SnapshotRestoreResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Restore complete", systemImage: "checkmark.circle")
                .font(.caption.bold())
                .foregroundStyle(Theme.Color.success)
            Group {
                if r.itemsRestored > 0 {
                    Text("• \(r.itemsRestored) items restored")
                }
                if r.habitsRestored > 0 {
                    Text("• \(r.habitsRestored) habits + \(r.instancesRestored) instances restored")
                }
                if r.measurementsRestored > 0 {
                    Text("• \(r.measurementsRestored) body measurements restored")
                }
                if r.profileRestored {
                    Text("• Body profile restored")
                }
                if r.skipped > 0 {
                    Text("• \(r.skipped) records skipped (already exist)")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.Color.textSecondary)
        }
    }

    // MARK: - Actions

    private func runExport() async {
        isExporting = true
        exportError = nil
        defer { isExporting = false }
        do {
            let data = try await appEnv.snapshotService.exportData()
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("LEO-Backup-\(formattedDate()).leobackup")
            try data.write(to: url, options: .atomic)
            exportedFileURL = url
            showShareSheet = true
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func loadFile(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            pendingData = try Data(contentsOf: url)
            showModeConfirm = true
        } catch {
            restoreError = error.localizedDescription
        }
    }

    private func runRestore(mode: SnapshotRestoreMode) async {
        guard let data = pendingData else { return }
        pendingData = nil
        isRestoring = true
        restoreError = nil
        restoreResult = nil
        defer { isRestoring = false }
        do {
            restoreResult = try await appEnv.snapshotService.restoreData(from: data, mode: mode)
        } catch {
            restoreError = error.localizedDescription
        }
    }

    private func formattedDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}

// MARK: - Platform share sheet

#if os(iOS)
private struct ShareSheetView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
#else
private struct ShareSheetView: View {
    let url: URL
    var body: some View {
        Text("File saved to: \(url.path)")
            .padding()
            .onAppear { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}
#endif

#Preview {
    NavigationStack {
        DataSnapshotView()
            .environment(AppEnvironment(useInMemory: true))
    }
}
