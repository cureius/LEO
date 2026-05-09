import SwiftUI

// MARK: - Pro features

public enum ProFeature: String, CaseIterable {
    case realAlarms         = "real_alarms"
    case habits             = "habits"
    case weeklyReview       = "weekly_review"
    case advancedRecurrence = "advanced_recurrence"
    case habitRingWidget    = "habit_ring_widget"
    case liveActivities     = "live_activities"
    case unlimitedAI        = "unlimited_ai"
    case watchApp           = "watch_app"

    public var displayName: String {
        switch self {
        case .realAlarms:         return "Real Alarms"
        case .habits:             return "Habits & Streaks"
        case .weeklyReview:       return "Weekly AI Review"
        case .advancedRecurrence: return "Smart Scheduling"
        case .habitRingWidget:    return "Habit Ring Widget"
        case .liveActivities:     return "Live Activities"
        case .unlimitedAI:        return "Unlimited AI"
        case .watchApp:           return "Apple Watch App"
        }
    }
}

// MARK: - Gate logic

public enum ProGate {
    public static func requires(_ feature: ProFeature, entitlement: Entitlement) -> Bool {
        switch entitlement {
        case .pro: return false
        case .free, .unknown: return true
        }
    }
}

// MARK: - Gate modifier

struct ProGateModifier: ViewModifier {
    let feature: ProFeature
    @State private var showPaywall = false
    @State private var entitlement: Entitlement = .unknown

    func body(content: Content) -> some View {
        content
            .overlay {
                if ProGate.requires(feature, entitlement: entitlement) {
                    ProGateOverlay(feature: feature) { showPaywall = true }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView() }
            .task {
                entitlement = await StoreClient.shared.currentEntitlement
            }
    }
}

extension View {
    func proGated(_ feature: ProFeature) -> some View {
        modifier(ProGateModifier(feature: feature))
    }
}

// MARK: - Gate overlay

private struct ProGateOverlay: View {
    let feature: ProFeature
    let onUpgrade: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.Color.accent)
            Text("This requires LEO Pro")
                .font(Theme.Typography.headline)
            Text("\(feature.displayName) is a Pro feature.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("Try free for 7 days") { onUpgrade() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
