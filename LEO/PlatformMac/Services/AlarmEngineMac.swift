import Foundation
import AVFoundation
import AppKit
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo.mac", category: "alarm")

/// macOS alarm engine. Uses UNNotificationRequest for scheduling and
/// AVAudioPlayer for in-app audio escalation. Brings the app window forward on fire.
actor AlarmEngineMac: AlarmEngineProtocol {
    private let notificationManager: NotificationManager
    private var audioPlayer: AVAudioPlayer?
    private var escalationTask: Task<Void, Never>? = nil
    private var armed: Set<UUID> = []

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    func arm(_ alarm: AlarmItem) async {
        guard case .point(let fireDate) = alarm.anchor, fireDate > .now else {
            logger.warning("Cannot arm alarm \(alarm.id): no future fire date")
            return
        }
        armed.insert(alarm.id)
        try? await notificationManager.schedule(
            identifier: "alarm.\(alarm.id).fire",
            title: "⏰ \(alarm.title)",
            body: alarm.notes ?? "Alarm",
            date: fireDate,
            categoryIdentifier: NotificationCategory.alarm,
            userInfo: ["itemID": alarm.id.uuidString, "isAlarm": true]
        )
        logger.info("Armed alarm '\(alarm.title)' for \(fireDate)")
    }

    func disarm(id: UUID) async {
        armed.remove(id)
        await notificationManager.cancel(identifiers: ["alarm.\(id).fire"])
        await stopAudio()
        logger.info("Disarmed alarm \(id)")
    }

    func snooze(alarm: AlarmItem, minutes: Int) async {
        await disarm(id: alarm.id)
        var snoozed = alarm
        snoozed.anchor = .point(.now.addingTimeInterval(TimeInterval(minutes * 60)))
        await arm(snoozed)
    }

    func startAudioPlayback(sound: AlarmSound, escalates: Bool) async {
        guard sound != .hapticOnly else { return }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3")
                   ?? Bundle.main.url(forResource: "alarm_default", withExtension: "mp3") else {
            logger.warning("Alarm sound file not found for: \(sound.rawValue)")
            return
        }
        audioPlayer = try? AVAudioPlayer(contentsOf: url)
        audioPlayer?.numberOfLoops = -1
        audioPlayer?.volume = escalates ? 0.1 : 1.0
        audioPlayer?.play()

        // Bring LEO window to front
        await MainActor.run { NSApp.activate(ignoringOtherApps: true) }

        if escalates {
            escalationTask = Task { [weak self] in
                for step in 1...30 {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    await self?.setVolume(Float(step) / 30.0)
                }
            }
        }
        logger.info("Alarm audio started: \(sound.rawValue), escalates=\(escalates)")
    }

    func stopAudio() async {
        escalationTask?.cancel()
        escalationTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    private func setVolume(_ v: Float) {
        audioPlayer?.volume = min(1.0, v)
    }
}
