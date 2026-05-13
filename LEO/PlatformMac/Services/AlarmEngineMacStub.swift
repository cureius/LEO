import Foundation

// Full implementation in MM6-T02. Stub satisfies AlarmEngineProtocol at compile time.
actor AlarmEngineMacStub: AlarmEngineProtocol {
    func arm(_ alarm: AlarmItem) async {}
    func disarm(id: UUID) async {}
    func snooze(alarm: AlarmItem, minutes: Int) async {}
    func startAudioPlayback(sound: AlarmSound, escalates: Bool) async {}
    func stopAudio() async {}
}
