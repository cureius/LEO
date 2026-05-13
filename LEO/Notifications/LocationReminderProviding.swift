import Foundation

@MainActor
public protocol LocationReminderProviding: AnyObject, Sendable {
    func requestWhenInUsePermission()
    func requestAlwaysPermission()
    func sync(items: [any Item])
    func stopAll()
}
