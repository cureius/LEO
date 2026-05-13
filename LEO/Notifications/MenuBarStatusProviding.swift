import Foundation

public protocol MenuBarStatusProviding: AnyObject, Sendable {
    func updateNextItem(_ item: (any Item)?) async
    func showActiveAlarm(_ alarm: AlarmItem?) async
}
