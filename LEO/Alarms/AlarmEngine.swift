import Foundation
import AVFoundation
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.theblueman.leo", category: "alarm")

/// Two-layer alarm system:
/// 1. UNNotificationRequest (critical sound when permitted, standard otherwise)
/// 2. AVAudioSession playback layer (only when app is foregrounded or via Live Activity)
///
/// iOS limitation: true alarm-override-silent requires critical alert entitlement from Apple.
/// Without it, this falls back to the loudest available standard notification.
actor AlarmEngine {

    private var audioPlayer: AVAudioPlayer?
    private var escalationTimer: Timer?
    private var armedAlarms: Set<UUID> = []
    private let notificationManager: NotificationManager

    init(notificationManager: NotificationManager) {
        self.notificationManager = notificationManager
    }

    // MARK: - Arm

    func arm(_ alarm: AlarmItem) async {
        guard case .point(let fireDate) = alarm.anchor, fireDate > .now else {
            logger.warning("Cannot arm alarm \(alarm.id): no future fire date")
            return
        }
        armedAlarms.insert(alarm.id)

        // Layer 1: Schedule UNNotificationRequest
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

    // MARK: - Disarm

    func disarm(id: UUID) async {
        armedAlarms.remove(id)
        await notificationManager.cancel(identifiers: ["alarm.\(id).fire"])
        stopAudio()
        logger.info("Disarmed alarm \(id)")
    }

    // MARK: - Audio layer (foreground)

    /// Call when the alarm fires and the app is foregrounded (or via Live Activity interaction).
    func startAudioPlayback(sound: AlarmSound, escalates: Bool) {
        guard sound != .hapticOnly else { return }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("AVAudioSession activation failed: \(error)")
            return
        }

        if let url = soundURL(for: sound) {
            audioPlayer = try? AVAudioPlayer(contentsOf: url)
            audioPlayer?.numberOfLoops = -1  // Loop indefinitely
            audioPlayer?.volume = escalates ? 0.1 : 1.0
            audioPlayer?.play()
        }

        if escalates {
            startEscalation()
        }
        logger.info("Alarm audio started: \(sound.rawValue) escalates=\(escalates)")
    }

    func stopAudio() {
        escalationTimer?.invalidate()
        escalationTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Snooze

    func snooze(alarm: AlarmItem, minutes: Int = 9) async {
        await disarm(id: alarm.id)
        var snoozed = alarm
        snoozed.anchor = .point(Date.now.addingTimeInterval(TimeInterval(minutes * 60)))
        await arm(snoozed)
    }

    // MARK: - Private

    private func soundURL(for sound: AlarmSound) -> URL? {
        Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3")
        ?? Bundle.main.url(forResource: "alarm_default", withExtension: "mp3")
    }

    private func startEscalation() {
        // Ramp volume from 0.1 to 1.0 over 30 seconds in 1-second steps
        var step = 0
        escalationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            step += 1
            Task { await self.setVolume(Float(step) / 30.0) }
            if step >= 30 { timer.invalidate() }
        }
    }

    private func setVolume(_ volume: Float) {
        audioPlayer?.volume = min(1.0, volume)
    }
}
