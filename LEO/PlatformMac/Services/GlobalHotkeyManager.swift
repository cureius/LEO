import AppKit
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo.mac", category: "hotkey")

/// Registers a global keyboard shortcut (default ⌃⌥Space) using NSEvent global monitors.
/// Requires Accessibility permission (System Settings → Privacy & Security → Accessibility).
@MainActor
final class GlobalHotkeyManager {
    private var monitor: Any?
    private var handler: (() -> Void)?

    func start(handler: @escaping () -> Void) {
        self.handler = handler
        // ⌃⌥Space: keyCode 49 (space), modifiers .control + .option
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 49,
                  event.modifierFlags.contains([.control, .option]),
                  !event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.shift) else { return }
            DispatchQueue.main.async { self?.handler?() }
        }
        if monitor != nil {
            logger.info("Global hotkey (⌃⌥Space) registered")
        } else {
            logger.warning("Global hotkey registration failed — Accessibility permission may be required")
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }

    /// Whether Accessibility permission is granted (required for global hotkey).
    static var accessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Open System Settings to the Accessibility privacy pane.
    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
