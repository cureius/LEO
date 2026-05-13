import Foundation

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case today
    case inbox
    case habits
    case ask
    case fitness
    case settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today:    return "Today"
        case .inbox:    return "Inbox"
        case .habits:   return "Habits"
        case .ask:      return "Ask LEO"
        case .fitness:  return "Fitness"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .today:    return "sun.max.fill"
        case .inbox:    return "tray.fill"
        case .habits:   return "repeat.circle.fill"
        case .ask:      return "sparkles"
        case .fitness:  return "figure.run"
        case .settings: return "gearshape"
        }
    }
}

@Observable
final class MacNavigationModel {
    var selection: SidebarSection = .today
    var selectedItemID: UUID? = nil
    var inspectorVisible: Bool = true
}
