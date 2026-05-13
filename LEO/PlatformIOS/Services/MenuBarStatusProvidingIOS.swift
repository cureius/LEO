import Foundation

final class MenuBarStatusProvidingIOS: MenuBarStatusProviding {
    func updateNextItem(_ item: (any Item)?) async {}
    func showActiveAlarm(_ alarm: AlarmItem?) async {}
}
