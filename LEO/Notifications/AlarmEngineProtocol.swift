import Foundation

public protocol AlarmEngineProtocol: Actor {
    func arm(_ alarm: AlarmItem) async
    func disarm(id: UUID) async
    func snooze(alarm: AlarmItem, minutes: Int) async
    func startAudioPlayback(sound: AlarmSound, escalates: Bool) async
    func stopAudio() async
}
