import SwiftUI

struct MacContentPane: View {
    @Environment(MacNavigationModel.self) private var nav

    var body: some View {
        // No NavigationStack here — each feature view owns its own navigation if needed.
        // .id(nav.selection) tears down and recreates the view when section changes,
        // clearing any transient state (scroll position, loading, etc.).
        Group {
            switch nav.selection {
            case .today:   MacTodayView()
            case .inbox:   MacInboxView()
            case .habits:  MacHabitsView()
            case .ask:     MacAssistantChatView()
            case .fitness: MacFitnessHomeView()
            case .settings: EmptyView()
            }
        }
        .id(nav.selection)  // reset the view tree when section changes
    }
}
