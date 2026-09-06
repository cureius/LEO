import EventKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "calendar-sync")

/// Drives `EventKitBridge.sync()` from three signals:
/// 1. `EKEventStoreChanged` — fires when iOS pulls new data from CalDAV/Exchange (Google, iCloud, Exchange).
/// 2. Foreground activations — called by the app on scene activation.
/// 3. Background app refresh — called from the `BGAppRefreshTask` handler.
///
/// All entry points coalesce into a single debounced sync to avoid hammering EKEventStore.
actor CalendarSyncCoordinator {
    private let bridge: EventKitBridge
    private var observerTask: Task<Void, Never>?
    private var pendingSync: Task<Void, Never>?
    private let debounce: Duration = .seconds(2)

    init(bridge: EventKitBridge) {
        self.bridge = bridge
    }

    /// Begin observing `EKEventStoreChanged`. Idempotent.
    func start() {
        guard observerTask == nil else { return }
        observerTask = Task { [weak self] in
            let stream = NotificationCenter.default.notifications(named: .EKEventStoreChanged)
            for await _ in stream {
                await self?.scheduleSync(reason: "EKEventStoreChanged")
            }
        }
        logger.info("CalendarSyncCoordinator observing EKEventStoreChanged")
    }

    func stop() {
        observerTask?.cancel()
        observerTask = nil
        pendingSync?.cancel()
        pendingSync = nil
    }

    /// Foreground activation hook — runs `refreshSourcesIfNecessary` (pulls remote) then a debounced sync.
    func syncOnForeground() async {
        await bridge.refreshSources()
        await scheduleSync(reason: "foreground")
    }

    /// Background-task hook — runs immediately (no debounce). Returns when done.
    func syncForBackgroundTask() async {
        await syncImmediately(reason: "background")
    }

    /// Explicit user-initiated refresh (⌘R). Skips the debounce: a command the user
    /// invoked should act now, not two seconds later, and must not be cancellable by
    /// an unrelated store notification arriving in the meantime.
    func syncNow() async {
        await syncImmediately(reason: "manual refresh")
    }

    private func syncImmediately(reason: String) async {
        pendingSync?.cancel()
        pendingSync = nil
        await bridge.refreshSources()
        await runSync(reason: reason)
    }

    /// Debounced sync — coalesces bursts of EKEventStoreChanged into one run.
    private func scheduleSync(reason: String) async {
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.runSync(reason: reason)
        }
    }

    private func runSync(reason: String) async {
        logger.info("Calendar sync starting — reason: \(reason)")
        do {
            let report = try await bridge.sync()
            logger.info("Calendar sync done (\(reason)): +\(report.imported) ~\(report.updated) -\(report.removed)")
        } catch {
            logger.error("Calendar sync failed (\(reason)): \(error.localizedDescription)")
        }
    }
}
