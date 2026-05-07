import Foundation

/// Priority level for any Item. Int raw value allows ordering (low < normal < high < urgent).
public enum Importance: Int, Hashable, Sendable, Codable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case urgent = 3

    var displayName: String {
        switch self {
        case .low:    return "Low"
        case .normal: return "Normal"
        case .high:   return "High"
        case .urgent: return "Urgent"
        }
    }

    var systemImage: String {
        switch self {
        case .low:    return "arrow.down.circle"
        case .normal: return "minus.circle"
        case .high:   return "exclamationmark.circle"
        case .urgent: return "exclamationmark.2.circle.fill"
        }
    }
}
